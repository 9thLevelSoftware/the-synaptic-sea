use derelict_core::procgen::{
    AdaptiveProposal, GameplayIR, GenerationMetrics, GenerationTrace, PlayerModel, PresentationIR,
    ProcgenBundle, ProcgenFailure, ProcgenRequest, SiteIR, WorldIR,
};
use schemars::{
    gen::{SchemaGenerator, SchemaSettings},
    JsonSchema,
};
use serde_json::Value;
use std::{env, fs, path::PathBuf, process};

fn schema<T: JsonSchema>() -> Value {
    // schemars 0.8 emits the Draft 2019-09 vocabulary; the structural
    // vocabulary used here is compatible, and the exported contract opts in
    // to the required Draft 2020-12 metaschema explicitly below.
    let settings = SchemaSettings::draft2019_09();
    let generator = SchemaGenerator::new(settings);
    let mut value =
        serde_json::to_value(generator.into_root_schema_for::<T>()).expect("schema serializes");
    upgrade_draft2020(&mut value);
    value["$schema"] = Value::String("https://json-schema.org/draft/2020-12/schema".into());
    value
}

fn def<'a>(root: &'a mut Value, name: &str) -> &'a mut Value {
    if root
        .get("definitions")
        .and_then(Value::as_object)
        .is_none_or(|defs| !defs.contains_key(name))
        && (root.get("title").and_then(Value::as_str) == Some(name)
            || root
                .get("properties")
                .and_then(Value::as_object)
                .is_some_and(|p| p.contains_key("schema_version")))
    {
        return root;
    }
    root.get_mut("definitions")
        .and_then(Value::as_object_mut)
        .and_then(|defs| defs.get_mut(name))
        .unwrap_or_else(|| panic!("missing schema definition {name}"))
}

fn const_field(root: &mut Value, definition: &str, field: &str, value: &str) {
    let property = def(root, definition)
        .get_mut("properties")
        .and_then(Value::as_object_mut)
        .and_then(|properties| properties.get_mut(field))
        .unwrap_or_else(|| panic!("missing {definition}.{field}"));
    *property = serde_json::json!({"const": value});
}

fn apply_request_constraints(root: &mut Value) {
    let request = def(root, "ProcgenRequest");
    let props = request["properties"].as_object_mut().unwrap();
    props["schema_version"] = serde_json::json!({"const":"procgen-request-1"});
    props["content_manifest_hash"] =
        serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
    props["generator_version"] = serde_json::json!({"const":2});
    props["difficulty_id"] = serde_json::json!({"type":"string","minLength":1});
    props["requested_domains"]["minItems"] = serde_json::json!(1);
    props["requested_domains"]["uniqueItems"] = serde_json::json!(true);
    let site = def(root, "SiteRequest");
    let site_props = site["properties"].as_object_mut().unwrap();
    site_props["intactness_override_bp"] = serde_json::json!({"anyOf":[{"type":"null"},{"type":"integer","minimum":0,"maximum":10000}]});
    site_props["loot_richness_bp"] =
        serde_json::json!({"type":"integer","minimum":0,"maximum":30000});
    for field in ["site_id", "archetype_id", "kit_id"] {
        site_props[field] = serde_json::json!({"type":"string","minLength":1});
    }
    def(root, "PlayerModel")["properties"]["schema_version"] =
        serde_json::json!({"const":"player-model-1"});
    def(root, "PresentationRequest")["properties"]["locale"] =
        serde_json::json!({"type":"string","pattern":"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"});
}

fn apply_gameplay_constraints(root: &mut Value) {
    let slice = def(root, "GameplaySlice");
    slice["properties"]["schema_version"] = serde_json::json!({"const":"1.1.0"});
    slice["properties"]["document_kind"] = serde_json::json!({"const":"ship_gameplay_slice"});
    for field in ["program_id", "start_room", "goal_room", "summary"] {
        slice["properties"][field] = serde_json::json!({"type":"string","minLength":1});
    }
    slice["properties"]["fire_zones"] = serde_json::json!({"type":"array","maxItems":0});
}

fn apply_adaptive_constraints(root: &mut Value) {
    let proposal = def(root, "AdaptiveProposal");
    proposal["properties"]["confidence_bp"] =
        serde_json::json!({"type":"integer","minimum":0,"maximum":10000});
    proposal["properties"]["rationale_codes"] =
        serde_json::json!({"type":"array","minItems":1,"items":{"type":"string","minLength":1}});
    proposal["properties"]["rule_model_version"] =
        serde_json::json!({"type":"string","minLength":1});
    require_nonempty_fields(
        def(root, "AdaptiveAction"),
        &["candidate_id", "encounter_id"],
    );
}

fn apply_trace_constraints(root: &mut Value) {
    let trace = def(root, "GenerationTrace");
    trace["properties"]["rng_channels"] = serde_json::json!({"const":["meta","hull","template","topology","residual_fill","door","furnish","story","intact","breach","scorch","seal","bodies","fracture","debris","loot"]});
    for field in [
        "candidate_decisions",
        "failed_constraints",
        "repairs",
        "retries",
    ] {
        trace["properties"][field] = serde_json::json!({"type":"array","maxItems":4096,"items":{"type":"string","minLength":1}});
    }
    trace["properties"]["fallback"] =
        serde_json::json!({"anyOf":[{"type":"null"},{"type":"string","minLength":1}]});
    trace["properties"]["stage_timings_micros"] = serde_json::json!({"type":"object","maxProperties":4096,"propertyNames":{"minLength":1},"additionalProperties":{"type":"integer","minimum":0,"maximum":3600000000u64}});
}

fn apply_metrics_constraints(root: &mut Value) {
    let metrics = def(root, "GenerationMetrics");
    metrics["properties"]["schema_version"] = serde_json::json!({"const":"generation-metrics-1"});
    metrics["properties"]["pipeline_executions"] = serde_json::json!({"const":1});
    metrics["properties"]["stage_timings_micros"] = serde_json::json!({"type":"object","maxProperties":4096,"propertyNames":{"minLength":1},"additionalProperties":{"type":"integer","minimum":0,"maximum":3600000000u64}});
}

fn upgrade_draft2020(value: &mut Value) {
    match value {
        Value::Object(map) => {
            if let Some(items) = map.remove("items") {
                if items.is_array() {
                    map.insert("prefixItems".into(), items);
                    map.insert("items".into(), Value::Bool(true));
                } else {
                    map.insert("items".into(), items);
                }
            }
            for child in map.values_mut() {
                upgrade_draft2020(child);
            }
        }
        Value::Array(values) => {
            for child in values {
                upgrade_draft2020(child);
            }
        }
        _ => {}
    }
}

fn require_nonempty_fields(value: &mut Value, fields: &[&str]) {
    match value {
        Value::Object(map) => {
            for field in fields {
                if map.contains_key(*field) {
                    map.insert(
                        (*field).into(),
                        serde_json::json!({"type":"string","minLength":1}),
                    );
                }
            }
            for child in map.values_mut() {
                require_nonempty_fields(child, fields);
            }
        }
        Value::Array(values) => {
            for child in values {
                require_nonempty_fields(child, fields);
            }
        }
        _ => {}
    }
}

fn enrich(name: &str, root: &mut Value) {
    let (definition, version) = match name {
        "procgen-request-1" => ("ProcgenRequest", "procgen-request-1"),
        "procgen-bundle-1" => ("ProcgenBundle", "procgen-bundle-1"),
        "world-ir-1" => ("WorldIR", "world-ir-1"),
        "site-ir-1" => ("SiteIR", "site-ir-1"),
        "gameplay-ir-1" => ("GameplayIR", "gameplay-ir-1"),
        "presentation-ir-1" => ("PresentationIR", "presentation-ir-1"),
        "generation-trace-1" => ("GenerationTrace", "generation-trace-1"),
        "adaptive-proposal-1" => ("AdaptiveProposal", "adaptive-proposal-1"),
        "player-model-1" => ("PlayerModel", "player-model-1"),
        "procgen-failure-1" => ("ProcgenFailure", "procgen-failure-1"),
        "generation-metrics-1" => ("GenerationMetrics", "generation-metrics-1"),
        _ => return,
    };
    const_field(root, definition, "schema_version", version);
    root["title"] = Value::String(name.into());
    if matches!(name, "procgen-request-1" | "procgen-bundle-1") {
        apply_request_constraints(root);
    }
    if matches!(name, "gameplay-ir-1" | "procgen-bundle-1") {
        apply_gameplay_constraints(root);
    }
    if name == "adaptive-proposal-1" {
        apply_adaptive_constraints(root);
    }
    if matches!(name, "generation-trace-1" | "procgen-bundle-1") {
        apply_trace_constraints(root);
    }
    if matches!(name, "generation-metrics-1" | "procgen-bundle-1") {
        apply_metrics_constraints(root);
    }
    if name == "procgen-bundle-1" {
        for (nested, nested_version) in [
            ("WorldIR", "world-ir-1"),
            ("SiteIR", "site-ir-1"),
            ("GameplayIR", "gameplay-ir-1"),
            ("PresentationIR", "presentation-ir-1"),
            ("GenerationTrace", "generation-trace-1"),
            ("GenerationMetrics", "generation-metrics-1"),
        ] {
            const_field(root, nested, "schema_version", nested_version);
        }
        def(root, "VersionEnvelope")["properties"]["content_manifest_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        def(root, "VersionEnvelope")["properties"]["generator_version"] =
            serde_json::json!({"const":2});
        def(root, "ProcgenBundle")["properties"]["semantic_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        let exports = def(root, "ExportSchemas")["properties"]
            .as_object_mut()
            .unwrap();
        for (field, value) in [
            ("procgen_request", "procgen-request-1"),
            ("procgen_bundle", "procgen-bundle-1"),
            ("world_ir", "world-ir-1"),
            ("site_ir", "site-ir-1"),
            ("gameplay_ir", "gameplay-ir-1"),
            ("presentation_ir", "presentation-ir-1"),
            ("generation_trace", "generation-trace-1"),
            ("adaptive_proposal", "adaptive-proposal-1"),
        ] {
            exports[field] = serde_json::json!({"const":value});
        }
    } else if name == "procgen-failure-1" {
        let failure = def(root, "ProcgenFailure");
        failure["properties"]["stage"] = serde_json::json!({"type":"string","minLength":1});
        failure["properties"]["message"] = serde_json::json!({"type":"string","minLength":1});
        failure["properties"]["fallback_id"] =
            serde_json::json!({"anyOf":[{"type":"null"},{"type":"string","minLength":1}]});
    }
}

fn main() {
    let out = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../schemas");
    let items: [(&str, Value); 11] = [
        ("procgen-request-1", schema::<ProcgenRequest>()),
        ("procgen-bundle-1", schema::<ProcgenBundle>()),
        ("world-ir-1", schema::<WorldIR>()),
        ("site-ir-1", schema::<SiteIR>()),
        ("gameplay-ir-1", schema::<GameplayIR>()),
        ("presentation-ir-1", schema::<PresentationIR>()),
        ("generation-trace-1", schema::<GenerationTrace>()),
        ("adaptive-proposal-1", schema::<AdaptiveProposal>()),
        ("player-model-1", schema::<PlayerModel>()),
        ("procgen-failure-1", schema::<ProcgenFailure>()),
        ("generation-metrics-1", schema::<GenerationMetrics>()),
    ];
    let write = env::args().any(|arg| arg == "--write");
    let check = env::args().any(|arg| arg == "--check");
    if !write && !check {
        eprintln!("usage: export_schemas --write|--check");
        process::exit(2);
    }
    for (name, value) in items {
        let mut value = value;
        enrich(name, &mut value);
        let path = out.join(format!("{name}.schema.json"));
        let bytes = serde_json::to_vec_pretty(&value).expect("schema JSON");
        let mut expected = bytes.clone();
        expected.push(b'\n');
        if write {
            fs::write(&path, expected).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
        } else if check {
            let actual = fs::read(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
            if actual != expected {
                eprintln!("schema drift: {}", path.display());
                process::exit(1);
            }
        }
    }
}
