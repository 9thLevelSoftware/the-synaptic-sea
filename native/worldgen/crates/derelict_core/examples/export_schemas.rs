use derelict_core::procgen::{
    AdaptiveProposal, GenerationMetrics, GenerationTrace, GameplayIR, PlayerModel, PresentationIR,
    ProcgenBundle, ProcgenFailure, ProcgenRequest, SiteIR, WorldIR,
};
use schemars::{gen::{SchemaGenerator, SchemaSettings}, JsonSchema};
use serde_json::Value;
use std::{env, fs, path::PathBuf, process};

fn schema<T: JsonSchema>() -> Value {
    // schemars 0.8 emits the Draft 2019-09 vocabulary; the structural
    // vocabulary used here is compatible, and the exported contract opts in
    // to the required Draft 2020-12 metaschema explicitly below.
    let settings = SchemaSettings::draft2019_09();
    let generator = SchemaGenerator::new(settings);
    let mut value = serde_json::to_value(generator.into_root_schema_for::<T>()).expect("schema serializes");
    upgrade_draft2020(&mut value);
    value["$schema"] = Value::String("https://json-schema.org/draft/2020-12/schema".into());
    value
}

fn def<'a>(root: &'a mut Value, name: &str) -> &'a mut Value {
    if root.get("definitions").and_then(Value::as_object).map_or(true, |defs| !defs.contains_key(name))
        && (root.get("title").and_then(Value::as_str) == Some(name)
            || root.get("properties").and_then(Value::as_object).map_or(false, |p| p.contains_key("schema_version"))) {
        return root;
    }
    root.get_mut("definitions").and_then(Value::as_object_mut)
        .and_then(|defs| defs.get_mut(name)).unwrap_or_else(|| panic!("missing schema definition {name}"))
}

fn const_field(root: &mut Value, definition: &str, field: &str, value: &str) {
    let property = def(root, definition).get_mut("properties").and_then(Value::as_object_mut)
        .and_then(|properties| properties.get_mut(field)).unwrap_or_else(|| panic!("missing {definition}.{field}"));
    *property = serde_json::json!({"const": value});
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
            for child in map.values_mut() { upgrade_draft2020(child); }
        }
        Value::Array(values) => for child in values { upgrade_draft2020(child); },
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
    if name == "procgen-request-1" {
        let request = def(root, definition);
        let props = request["properties"].as_object_mut().unwrap();
        props["content_manifest_hash"] = serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        props["generator_version"] = serde_json::json!({"const":2});
        let site = def(root, "SiteRequest");
        let site_props = site["properties"].as_object_mut().unwrap();
        site_props["intactness_override_bp"] = serde_json::json!({"anyOf":[{"type":"null"},{"type":"integer","minimum":0,"maximum":10000}]});
        site_props["loot_richness_bp"] = serde_json::json!({"type":"integer","minimum":0,"maximum":30000});
        site_props["site_id"] = serde_json::json!({"type":"string","minLength":1});
        site_props["archetype_id"] = serde_json::json!({"type":"string","minLength":1});
        site_props["kit_id"] = serde_json::json!({"type":"string","minLength":1});
        let pres = def(root, "PresentationRequest");
        pres["properties"]["locale"] = serde_json::json!({"type":"string","pattern":"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"});
    } else if name == "procgen-bundle-1" {
        for (nested, nested_version) in [("WorldIR", "world-ir-1"), ("SiteIR", "site-ir-1"), ("GameplayIR", "gameplay-ir-1"), ("PresentationIR", "presentation-ir-1"), ("GenerationTrace", "generation-trace-1"), ("GenerationMetrics", "generation-metrics-1")] {
            const_field(root, nested, "schema_version", nested_version);
        }
        def(root, "GenerationMetrics")["properties"]["pipeline_executions"] = serde_json::json!({"const":1});
        def(root, "GenerationTrace")["properties"]["rng_channels"] = serde_json::json!({"type":"array","minItems":16,"maxItems":16,"items":{"type":"string"}});
        def(root, "VersionEnvelope")["properties"]["content_manifest_hash"] = serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        let exports = def(root, "ExportSchemas")["properties"].as_object_mut().unwrap();
        for (field, value) in [("procgen_request", "procgen-request-1"), ("procgen_bundle", "procgen-bundle-1"), ("world_ir", "world-ir-1"), ("site_ir", "site-ir-1"), ("gameplay_ir", "gameplay-ir-1"), ("presentation_ir", "presentation-ir-1"), ("generation_trace", "generation-trace-1"), ("adaptive_proposal", "adaptive-proposal-1")] { exports[field] = serde_json::json!({"const":value}); }
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
