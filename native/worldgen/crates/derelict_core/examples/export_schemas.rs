use derelict_core::lifecycle::{GeneratorManifest, LifecycleResult, ProcgenCapabilities};
use derelict_core::manifest::BuildManifest;
use derelict_core::procgen::{
    AdaptiveProposal, GameplayIR, GenerationMetrics, GenerationTrace, PlayerModel, PresentationIR,
    ProcgenBundle, ProcgenFailure, ProcgenRequest, SiteIR, RNG_CHANNELS,
};
use schemars::{
    gen::{SchemaGenerator, SchemaSettings},
    JsonSchema,
};
use serde_json::Value;
use sha2::{Digest, Sha256};
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

fn root_is_definition(root_title: &str, name: &str) -> bool {
    root_title == name
        || matches!(
            (root_title, name),
            ("procgen-request-1", "ProcgenRequest")
                | ("procgen-request-2", "ProcgenRequest")
                | (
                    "procgen-bundle-1" | "procgen-bundle-2" | "procgen-bundle-3",
                    "ProcgenBundle"
                )
                | ("procgen-bundle-4", "ProcgenBundle")
                | ("world-ir-1", "WorldIR")
                | ("world-ir-2", "WorldIRv2")
                | ("site-ir-1" | "site-ir-2", "SiteIR")
                | ("gameplay-ir-1", "GameplayIR")
                | ("gameplay-ir-2", "GameplayIR")
                | ("presentation-ir-1", "PresentationIR")
                | ("presentation-ir-2", "PresentationIR")
                | (
                    "presentation-ir-1" | "presentation-ir-2",
                    "PresentationOutput"
                )
                | ("PresentationOutput", "PresentationIR")
                | (
                    "generation-trace-1" | "generation-trace-2" | "generation-trace-3",
                    "GenerationTrace"
                )
                | ("adaptive-proposal-1", "AdaptiveProposal")
                | ("player-model-1", "PlayerModel")
                | ("player-model-2", "PlayerModel")
                | ("PlayerModelV2", "PlayerModel")
                | ("procgen-failure-1", "ProcgenFailure")
                | ("generation-metrics-1", "GenerationMetrics")
                | (
                    "procgen-lifecycle-result-1"
                        | "procgen-lifecycle-result-2"
                        | "procgen-lifecycle-result-3",
                    "LifecycleResult"
                )
                | ("procgen-lifecycle-result-4", "LifecycleResult")
                | (
                    "procgen-capabilities-1" | "procgen-capabilities-2",
                    "ProcgenCapabilities"
                )
                | ("procgen-capabilities-3", "ProcgenCapabilities")
                | (
                    "procgen-generator-manifest-1" | "procgen-generator-manifest-2",
                    "GeneratorManifest"
                )
                | ("procgen-generator-manifest-3", "GeneratorManifest")
                | ("procgen-build-manifest-3", "BuildManifest")
        )
}

fn def<'a>(root: &'a mut Value, name: &str) -> &'a mut Value {
    let root_title = root
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    if root_is_definition(&root_title, name) {
        return root;
    }
    let lookup_name = match name {
        "PresentationIR" => "PresentationOutput",
        "PlayerModel" => "PlayerModelV2",
        _ => name,
    };
    root.get_mut("definitions")
        .and_then(Value::as_object_mut)
        .and_then(|defs| defs.get_mut(lookup_name))
        .unwrap_or_else(|| panic!("missing schema definition {name}, title={root_title}"))
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
    props["generator_version"] = serde_json::json!({"const":3});
    props["world_seed"] =
        serde_json::json!({"type":"integer","minimum":0,"maximum":9007199254740991u64});
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
    if has_def(root, "PlayerModel") {
        def(root, "PlayerModel")["properties"]["schema_version"] =
            serde_json::json!({"const":"player-model-1"});
    }
    if has_def(root, "PresentationRequest") {
        def(root, "PresentationRequest")["properties"]["locale"] =
            serde_json::json!({"type":"string","pattern":"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"});
    }
}

fn apply_platform_v3_constraints(root: &mut Value) {
    if root.get("title").and_then(Value::as_str) == Some("world-ir-2") {
        def(root, "WorldIRv2")["properties"]["schema_version"] =
            serde_json::json!({"const":"world-ir-2"});
    } else if root.get("title").and_then(Value::as_str) == Some("site-ir-2") {
        def(root, "SiteIR")["properties"]["schema_version"] =
            serde_json::json!({"const":"site-ir-2"});
    } else if root.get("title").and_then(Value::as_str) == Some("generation-trace-2") {
        def(root, "GenerationTrace")["properties"]["schema_version"] =
            serde_json::json!({"const":"generation-trace-2"});
    } else if root.get("title").and_then(Value::as_str) == Some("procgen-bundle-3") {
        def(root, "ProcgenBundle")["properties"]["schema_version"] =
            serde_json::json!({"const":"procgen-bundle-3"});
    } else if root.get("title").and_then(Value::as_str) == Some("procgen-lifecycle-result-3") {
        def(root, "LifecycleResult")["properties"]["schema_version"] =
            serde_json::json!({"const":"procgen-lifecycle-result-3"});
    }
    let standalone_world = root.get("title").and_then(Value::as_str) == Some("world-ir-2");
    if !standalone_world
        && root
            .get("definitions")
            .and_then(Value::as_object)
            .is_some_and(|d| d.contains_key("ProcgenRequest"))
    {
        let request = def(root, "ProcgenRequest");
        request["properties"]["generator_version"] = serde_json::json!({"const":3});
        request["properties"]["world_seed"] =
            serde_json::json!({"type":"integer","minimum":0,"maximum":9007199254740991u64});
        let envelope = def(root, "VersionEnvelope");
        envelope["properties"]["generator_version"] = serde_json::json!({"const":3});
        let exports = def(root, "ExportSchemas");
        exports["properties"]["procgen_bundle"] = serde_json::json!({"const":"procgen-bundle-3"});
        exports["properties"]["world_ir"] = serde_json::json!({"const":"world-ir-2"});
        exports["properties"]["site_ir"] = serde_json::json!({"const":"site-ir-2"});
        exports["properties"]["generation_trace"] =
            serde_json::json!({"const":"generation-trace-2"});
    }
    if root
        .get("definitions")
        .and_then(Value::as_object)
        .is_some_and(|d| d.contains_key("WorldIRv2"))
        || standalone_world
    {
        let world = def(root, "WorldIRv2");
        world["properties"]["world_seed"] =
            serde_json::json!({"type":"integer","minimum":0,"maximum":9007199254740991u64});
        world["properties"]["site_seed"] =
            serde_json::json!({"type":"integer","minimum":0,"maximum":9007199254740991u64});
    }
    if root
        .get("definitions")
        .and_then(Value::as_object)
        .is_some_and(|definitions| definitions.contains_key("Ship"))
    {
        def(root, "Ship")["properties"]["generator_version"] = serde_json::json!({"const":2});
    }
    if root.get("title").and_then(Value::as_str) == Some("procgen-bundle-3")
        || root
            .get("definitions")
            .and_then(Value::as_object)
            .is_some_and(|definitions| definitions.contains_key("ProcgenBundle"))
    {
        def(root, "ProcgenBundle")["properties"]["semantic_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
    }
    if root
        .get("definitions")
        .and_then(Value::as_object)
        .is_some_and(|d| d.contains_key("GenerationTrace"))
    {
        let trace = def(root, "GenerationTrace");
        trace["properties"]["rng_channels"] = serde_json::json!({"const":["world.archetype","world.biome","world.hazard","world.resource","world.landmark","world.route_cost","site.structural","site.mission_template","site.gate_order","site.functional_props","site.spatial_annotations","meta","hull","template","topology","residual_fill","door","furnish","story","intact","breach","scorch","seal","bodies","fracture","debris","loot"]});
    }
    if let Some(adapter) = root
        .get_mut("definitions")
        .and_then(Value::as_object_mut)
        .and_then(|d| d.get_mut("AdapterSchemas"))
    {
        adapter["properties"]["lifecycle_result"] =
            serde_json::json!({"const":"procgen-lifecycle-result-3"});
    }
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
    trace["properties"]["rng_channels"] = serde_json::json!({"const":["world.archetype","world.biome","world.hazard","world.resource","world.landmark","world.route_cost","site.structural","site.mission_template","site.gate_order","site.functional_props","site.spatial_annotations","meta","hull","template","topology","residual_fill","door","furnish","story","intact","breach","scorch","seal","bodies","fracture","debris","loot"]});
    for field in [
        "candidate_decisions",
        "failed_constraints",
        "repairs",
        "retries",
    ] {
        trace["properties"][field] = serde_json::json!({"type":"array","maxItems":4096,"items":{"type":"string","minLength":1}});
    }
    trace["properties"]["fallback"] = serde_json::json!({"anyOf":[{"type":"null"},{"type":"string","pattern":"^(?:world:[a-z0-9_.:-]+(?:\\|site:[a-z0-9_.:-]+)?|site:[a-z0-9_.:-]+)$"}]});
    trace["properties"]["stage_timings_micros"] = serde_json::json!({"type":"object","maxProperties":4096,"propertyNames":{"minLength":1},"additionalProperties":{"type":"integer","minimum":0,"maximum":3600000000u64}});
}

fn apply_gate3_trace_constraints(root: &mut Value) {
    let trace = def(root, "GenerationTrace");
    trace["properties"]["schema_version"] = serde_json::json!({"const":"generation-trace-3"});
    trace["properties"]["rng_channels"] = serde_json::json!({"const": RNG_CHANNELS.as_slice()});
    for field in [
        "candidate_decisions",
        "failed_constraints",
        "repairs",
        "retries",
    ] {
        trace["properties"][field] = serde_json::json!({"type":"array","maxItems":4096,"items":{"type":"string","minLength":1}});
    }
    trace["properties"]["fallback"] = serde_json::json!({"anyOf":[{"type":"null"},{"type":"string","pattern":"^(?:world:[a-z0-9_.:-]+(?:\\|site:[a-z0-9_.:-]+)?|site:[a-z0-9_.:-]+)$"}]});
    trace["properties"]["stage_timings_micros"] = serde_json::json!({"type":"object","maxProperties":4096,"propertyNames":{"minLength":1},"additionalProperties":{"type":"integer","minimum":0,"maximum":3600000000u64}});
}

fn apply_metrics_constraints(root: &mut Value) {
    let metrics = def(root, "GenerationMetrics");
    metrics["properties"]["schema_version"] = serde_json::json!({"const":"generation-metrics-1"});
    metrics["properties"]["pipeline_executions"] = serde_json::json!({"const":1});
    metrics["properties"]["stage_timings_micros"] = serde_json::json!({"type":"object","maxProperties":4096,"propertyNames":{"minLength":1},"additionalProperties":{"type":"integer","minimum":0,"maximum":3600000000u64}});
}

fn has_def(root: &Value, key: &str) -> bool {
    let root_title = root
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if root_is_definition(root_title, key) {
        return true;
    }
    let lookup_name = match key {
        "PresentationIR" => "PresentationOutput",
        "PlayerModel" => "PlayerModelV2",
        _ => key,
    };
    root.get("definitions")
        .and_then(Value::as_object)
        .is_some_and(|definitions| definitions.contains_key(lookup_name))
}

/// Gate 3 is a new public contract family. Keep its bounds explicit in the
/// exported JSON rather than relying on schemars' Rust integer representation.
fn apply_gate3_constraints(name: &str, root: &mut Value) {
    let definition = match name {
        "procgen-request-2" => "ProcgenRequest",
        "player-model-2" => "PlayerModel",
        "gameplay-ir-2" => "GameplayIR",
        "presentation-ir-2" => "PresentationIR",
        "generation-trace-3" => "GenerationTrace",
        "procgen-bundle-4" => "ProcgenBundle",
        "procgen-lifecycle-result-4" => "LifecycleResult",
        "procgen-capabilities-3" => "ProcgenCapabilities",
        "procgen-generator-manifest-3" => "GeneratorManifest",
        "procgen-build-manifest-3" => "BuildManifest",
        _ => return,
    };
    if name == "procgen-build-manifest-3" {
        def(root, definition)["properties"]["manifest_schema"] =
            serde_json::json!({"const":"procgen-build-manifest-3"});
    } else {
        const_field(root, definition, "schema_version", name);
    }

    if has_def(root, "ProcgenRequest") || name == "procgen-request-2" {
        apply_request_constraints(root);
        let request = def(root, "ProcgenRequest");
        request["properties"]["schema_version"] = serde_json::json!({"const":"procgen-request-2"});
        request["properties"]["generator_version"] = serde_json::json!({"const":3});
        request["properties"]["world_seed"] =
            serde_json::json!({"type":"integer","minimum":0,"maximum":9007199254740991u64});
        request["properties"]["content_manifest_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        request["properties"]["requested_domains"]["minItems"] = serde_json::json!(1);
        request["properties"]["requested_domains"]["uniqueItems"] = serde_json::json!(true);
        if has_def(root, "PlayerModel") {
            def(root, "PlayerModel")["properties"]["schema_version"] =
                serde_json::json!({"const":"player-model-2"});
        }
    }
    if has_def(root, "GameplayIR") {
        apply_gameplay_constraints(root);
        def(root, "GameplayIR")["properties"]["schema_version"] =
            serde_json::json!({"const":"gameplay-ir-2"});
    }
    if has_def(root, "PresentationIR") {
        def(root, "PresentationIR")["properties"]["schema_version"] =
            serde_json::json!({"const":"presentation-ir-2"});
    }
    if has_def(root, "GenerationTrace") {
        apply_gate3_trace_constraints(root);
    }
    if has_def(root, "GenerationMetrics") {
        apply_metrics_constraints(root);
    }
    if has_def(root, "Ship") {
        def(root, "Ship")["properties"]["generator_version"] = serde_json::json!({"const":2});
    }
    if has_def(root, "ProcgenBundle") {
        let bundle = def(root, "ProcgenBundle");
        bundle["properties"]["schema_version"] = serde_json::json!({"const":"procgen-bundle-4"});
        bundle["properties"]["semantic_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        for (field, version) in [
            ("request", "procgen-request-2"),
            ("gameplay_ir", "gameplay-ir-2"),
            ("presentation_ir", "presentation-ir-2"),
        ] {
            if bundle["properties"].get(field).is_some() { /* nested consts are applied below */ }
            let _ = version;
        }
        if has_def(root, "VersionEnvelope") {
            def(root, "VersionEnvelope")["properties"]["generator_version"] =
                serde_json::json!({"const":3});
        }
        for (definition, version) in [
            ("ProcgenRequest", "procgen-request-2"),
            ("PlayerModel", "player-model-2"),
            ("GameplayIR", "gameplay-ir-2"),
            ("PresentationIR", "presentation-ir-2"),
            ("WorldIRv2", "world-ir-2"),
            ("SiteIR", "site-ir-2"),
            ("GenerationTrace", "generation-trace-3"),
            ("GenerationMetrics", "generation-metrics-1"),
        ] {
            if has_def(root, definition) {
                def(root, definition)["properties"]["schema_version"] =
                    serde_json::json!({"const":version});
            }
        }
        if has_def(root, "ExportSchemas") {
            let e = def(root, "ExportSchemas");
            for (field, value) in [
                ("procgen_request", "procgen-request-2"),
                ("procgen_bundle", "procgen-bundle-4"),
                ("world_ir", "world-ir-2"),
                ("site_ir", "site-ir-2"),
                ("gameplay_ir", "gameplay-ir-2"),
                ("presentation_ir", "presentation-ir-2"),
                ("generation_trace", "generation-trace-3"),
                ("adaptive_proposal", "adaptive-proposal-1"),
            ] {
                e["properties"][field] = serde_json::json!({"const":value});
            }
        }
    }
    if has_def(root, "LifecycleResult") {
        let lifecycle = def(root, "LifecycleResult");
        lifecycle["properties"]["schema_version"] =
            serde_json::json!({"const":"procgen-lifecycle-result-4"});
        lifecycle["properties"]["events"] =
            serde_json::json!({"type":"array","minItems":1,"maxItems":32});
        lifecycle["properties"]["request_id"] = serde_json::json!({"anyOf":[{"type":"integer","minimum":1,"maximum":9223372036854775807i64},{"type":"null"}]});
        let mut rules = Vec::new();
        for status in ["accepted", "queued", "running", "cancel_requested"] {
            rules.push(serde_json::json!({"if":{"properties":{"status":{"const":status}}},"then":{"required":["request_id"],"properties":{"request_id":{"type":"integer","minimum":1,"maximum":9223372036854775807i64},"bundle":{"const":null},"failure":{"const":null}}}}));
        }
        rules.push(serde_json::json!({"if":{"properties":{"status":{"const":"completed"}}},"then":{"required":["bundle"],"properties":{"bundle":{"not":{"const":null}},"failure":{"const":null}}}}));
        rules.push(serde_json::json!({"if":{"properties":{"status":{"const":"failed"}}},"then":{"required":["failure"],"properties":{"bundle":{"const":null},"failure":{"not":{"const":null}}}}}));
        root["allOf"] = Value::Array(rules);
    }
    if has_def(root, "ProcgenCapabilities") {
        let caps = def(root, "ProcgenCapabilities");
        caps["properties"]["schema_version"] =
            serde_json::json!({"const":"procgen-capabilities-3"});
        caps["properties"]["target"] = serde_json::json!({"type":"string","minLength":1});
        for field in [
            "queue_capacity",
            "retained_results",
            "max_request_bytes",
            "max_entities",
            "max_trace_entries",
            "max_events",
            "deadline_ms",
        ] {
            caps["properties"][field]["minimum"] = serde_json::json!(1);
        }
        caps["properties"]["max_events"] =
            serde_json::json!({"type":"integer","minimum":1,"maximum":32});
        caps["properties"]["max_trace_entries"] =
            serde_json::json!({"type":"integer","minimum":1,"maximum":4096});
        caps["properties"]["supported_domains"] =
            serde_json::json!({"const":["world","site","gameplay","presentation"]});
        root["allOf"] = serde_json::json!([{"if":{"properties":{"worker_mode":{"const":"thread_pool"}}},"then":{"properties":{"worker_count":{"minimum":1}}}}]);
        if has_def(root, "AdapterSchemas") {
            let a = def(root, "AdapterSchemas");
            a["properties"]["lifecycle_result"] =
                serde_json::json!({"const":"procgen-lifecycle-result-4"});
            a["properties"]["capabilities"] = serde_json::json!({"const":"procgen-capabilities-3"});
            a["properties"]["generator_manifest"] =
                serde_json::json!({"const":"procgen-generator-manifest-3"});
        }
    }
    if has_def(root, "GeneratorManifest") {
        let m = def(root, "GeneratorManifest");
        m["properties"]["schema_version"] =
            serde_json::json!({"const":"procgen-generator-manifest-3"});
        m["properties"]["generator_version"] = serde_json::json!({"const":3});
        m["properties"]["rust_source_commit"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{40}$"});
        m["properties"]["content_manifest_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        m["properties"]["target"] = serde_json::json!({"type":"string","minLength":1});
        if has_def(root, "ExportSchemas") {
            let e = def(root, "ExportSchemas");
            for (field, value) in [
                ("procgen_request", "procgen-request-2"),
                ("procgen_bundle", "procgen-bundle-4"),
                ("world_ir", "world-ir-2"),
                ("site_ir", "site-ir-2"),
                ("gameplay_ir", "gameplay-ir-2"),
                ("presentation_ir", "presentation-ir-2"),
                ("generation_trace", "generation-trace-3"),
                ("adaptive_proposal", "adaptive-proposal-1"),
            ] {
                e["properties"][field] = serde_json::json!({"const":value});
            }
        }
        if has_def(root, "AdapterSchemas") {
            let a = def(root, "AdapterSchemas");
            a["properties"]["lifecycle_result"] =
                serde_json::json!({"const":"procgen-lifecycle-result-4"});
            a["properties"]["capabilities"] = serde_json::json!({"const":"procgen-capabilities-3"});
            a["properties"]["generator_manifest"] =
                serde_json::json!({"const":"procgen-generator-manifest-3"});
        }
    }
    if has_def(root, "BuildManifest") {
        let manifest = def(root, "BuildManifest");
        manifest["properties"]["manifest_schema"] =
            serde_json::json!({"const":"procgen-build-manifest-3"});
        manifest["properties"]["rust_source_commit"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{40}$"});
        manifest["properties"]["generator_version"] = serde_json::json!({"const":3});
        manifest["properties"]["content_manifest_path"] =
            serde_json::json!({"const":"data/procgen/manifests/content_manifest.json"});
        manifest["properties"]["content_manifest_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        manifest["properties"]["target"] =
            serde_json::json!({"enum":["x86_64-pc-windows-msvc","wasm32-unknown-unknown"]});
        if has_def(root, "Artifact") {
            let artifact = def(root, "Artifact");
            artifact["properties"]["sha256"] =
                serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        }
        root["oneOf"] = serde_json::json!([
            {"properties":{"target":{"const":"x86_64-pc-windows-msvc"},"artifact":{"properties":{"kind":{"const":"gdextension"},"path":{"const":"addons/derelict/bin/win64/derelict_godot.dll"}}}},"required":["target","artifact"]},
            {"properties":{"target":{"const":"wasm32-unknown-unknown"},"artifact":{"properties":{"kind":{"const":"wasm"},"path":{"const":"addons/derelict/bin/web/derelict_wasm_bg.wasm"}}}},"required":["target","artifact"]}
        ]);
    }
    if has_def(root, "ExportSchemas") {
        let exports = def(root, "ExportSchemas");
        for (field, value) in [
            ("procgen_request", "procgen-request-2"),
            ("procgen_bundle", "procgen-bundle-4"),
            ("world_ir", "world-ir-2"),
            ("site_ir", "site-ir-2"),
            ("gameplay_ir", "gameplay-ir-2"),
            ("presentation_ir", "presentation-ir-2"),
            ("generation_trace", "generation-trace-3"),
            ("adaptive_proposal", "adaptive-proposal-1"),
        ] {
            exports["properties"][field] = serde_json::json!({"const":value});
        }
    }
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
        "procgen-request-2" => ("ProcgenRequest", "procgen-request-2"),
        "procgen-bundle-1" | "procgen-bundle-2" | "procgen-bundle-3" => {
            ("ProcgenBundle", "procgen-bundle-1")
        }
        "procgen-bundle-4" => ("ProcgenBundle", "procgen-bundle-4"),
        "world-ir-1" => ("WorldIR", "world-ir-1"),
        "world-ir-2" => ("WorldIRv2", "world-ir-1"),
        "site-ir-1" | "site-ir-2" => ("SiteIR", "site-ir-1"),
        "gameplay-ir-1" => ("GameplayIR", "gameplay-ir-1"),
        "gameplay-ir-2" => ("GameplayIR", "gameplay-ir-2"),
        "presentation-ir-1" => ("PresentationIR", "presentation-ir-1"),
        "presentation-ir-2" => ("PresentationIR", "presentation-ir-2"),
        "generation-trace-1" | "generation-trace-2" => ("GenerationTrace", "generation-trace-1"),
        "generation-trace-3" => ("GenerationTrace", "generation-trace-3"),
        "adaptive-proposal-1" => ("AdaptiveProposal", "adaptive-proposal-1"),
        "player-model-1" => ("PlayerModel", "player-model-1"),
        "player-model-2" => ("PlayerModel", "player-model-2"),
        "procgen-failure-1" => ("ProcgenFailure", "procgen-failure-1"),
        "generation-metrics-1" => ("GenerationMetrics", "generation-metrics-1"),
        "procgen-lifecycle-result-1"
        | "procgen-lifecycle-result-2"
        | "procgen-lifecycle-result-3" => ("LifecycleResult", "procgen-lifecycle-result-1"),
        "procgen-lifecycle-result-4" => ("LifecycleResult", "procgen-lifecycle-result-4"),
        "procgen-capabilities-1" | "procgen-capabilities-2" => ("ProcgenCapabilities", name),
        "procgen-capabilities-3" => ("ProcgenCapabilities", name),
        "procgen-generator-manifest-1" | "procgen-generator-manifest-2" => {
            ("GeneratorManifest", name)
        }
        "procgen-generator-manifest-3" => ("GeneratorManifest", name),
        "procgen-build-manifest-3" => ("BuildManifest", name),
        _ => return,
    };
    if name != "procgen-build-manifest-3" {
        const_field(root, definition, "schema_version", version);
    } else {
        def(root, definition)["properties"]["manifest_schema"] =
            serde_json::json!({"const":"procgen-build-manifest-3"});
    }
    root["title"] = Value::String(name.into());
    root["$id"] = Value::String(name.into());
    if matches!(
        name,
        "procgen-lifecycle-result-1" | "procgen-lifecycle-result-2" | "procgen-lifecycle-result-3"
    ) && !root
        .get("definitions")
        .and_then(Value::as_object)
        .is_some_and(|d| d.contains_key("ProcgenBundle") && d.contains_key("ProcgenRequest"))
    {
        return;
    }
    if matches!(
        name,
        "procgen-request-1" | "procgen-bundle-1" | "procgen-bundle-2" | "procgen-bundle-3"
    ) {
        apply_request_constraints(root);
    }
    if matches!(
        name,
        "gameplay-ir-1" | "procgen-bundle-1" | "procgen-bundle-2" | "procgen-bundle-3"
    ) {
        apply_gameplay_constraints(root);
    }
    if name == "adaptive-proposal-1" {
        apply_adaptive_constraints(root);
    }
    if matches!(
        name,
        "generation-trace-1"
            | "generation-trace-2"
            | "procgen-bundle-1"
            | "procgen-bundle-2"
            | "procgen-bundle-3"
    ) {
        apply_trace_constraints(root);
    }
    if matches!(
        name,
        "generation-metrics-1" | "procgen-bundle-1" | "procgen-bundle-2" | "procgen-bundle-3"
    ) {
        apply_metrics_constraints(root);
    }
    if matches!(
        name,
        "procgen-bundle-1" | "procgen-bundle-2" | "procgen-bundle-3"
    ) {
        let world_definition = if matches!(name, "procgen-bundle-2" | "procgen-bundle-3") {
            "WorldIRv2"
        } else {
            "WorldIR"
        };
        for (nested, nested_version) in [
            ("WorldIR", "world-ir-1"),
            (
                "SiteIR",
                if name == "procgen-bundle-3" {
                    "site-ir-2"
                } else {
                    "site-ir-1"
                },
            ),
            ("GameplayIR", "gameplay-ir-1"),
            ("PresentationIR", "presentation-ir-1"),
            (
                "GenerationTrace",
                if name == "procgen-bundle-3" {
                    "generation-trace-2"
                } else {
                    "generation-trace-1"
                },
            ),
            ("GenerationMetrics", "generation-metrics-1"),
        ] {
            const_field(
                root,
                if nested == "WorldIR" {
                    world_definition
                } else {
                    nested
                },
                "schema_version",
                if nested == "WorldIR" && matches!(name, "procgen-bundle-2" | "procgen-bundle-3") {
                    "world-ir-2"
                } else {
                    nested_version
                },
            );
        }
    } else if matches!(
        name,
        "procgen-lifecycle-result-1" | "procgen-lifecycle-result-2" | "procgen-lifecycle-result-3"
    ) {
        // The embedded bundle must retain the same constraints as the standalone
        // bundle contract, including all nested trace/gameplay enrichment.
        apply_request_constraints(root);
        apply_gameplay_constraints(root);
        apply_trace_constraints(root);
        apply_metrics_constraints(root);
        let world_definition = if matches!(
            name,
            "procgen-lifecycle-result-2" | "procgen-lifecycle-result-3"
        ) {
            "WorldIRv2"
        } else {
            "WorldIR"
        };
        for (nested, nested_version) in [
            ("WorldIR", "world-ir-1"),
            (
                "SiteIR",
                if name == "procgen-lifecycle-result-3" {
                    "site-ir-2"
                } else {
                    "site-ir-1"
                },
            ),
            ("GameplayIR", "gameplay-ir-1"),
            ("PresentationIR", "presentation-ir-1"),
            (
                "GenerationTrace",
                if name == "procgen-lifecycle-result-3" {
                    "generation-trace-2"
                } else {
                    "generation-trace-1"
                },
            ),
            ("GenerationMetrics", "generation-metrics-1"),
        ] {
            const_field(
                root,
                if nested == "WorldIR" {
                    world_definition
                } else {
                    nested
                },
                "schema_version",
                if nested == "WorldIR"
                    && matches!(
                        name,
                        "procgen-lifecycle-result-2" | "procgen-lifecycle-result-3"
                    )
                {
                    "world-ir-2"
                } else {
                    nested_version
                },
            );
        }
        let current = name == "procgen-lifecycle-result-3";
        const_field(
            root,
            "ProcgenBundle",
            "schema_version",
            if current {
                "procgen-bundle-3"
            } else if name == "procgen-lifecycle-result-2" {
                "procgen-bundle-2"
            } else {
                "procgen-bundle-1"
            },
        );
        def(root, "VersionEnvelope")["properties"]["generator_version"] =
            serde_json::json!({"const": if name == "procgen-lifecycle-result-1" { 2 } else { 3 }});
        def(root, "VersionEnvelope")["properties"]["content_manifest_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        def(root, "ProcgenBundle")["properties"]["semantic_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        let exports = if current {
            [
                ("procgen_request", "procgen-request-1"),
                ("procgen_bundle", "procgen-bundle-3"),
                ("world_ir", "world-ir-2"),
                ("site_ir", "site-ir-2"),
                ("gameplay_ir", "gameplay-ir-1"),
                ("presentation_ir", "presentation-ir-1"),
                ("generation_trace", "generation-trace-2"),
                ("adaptive_proposal", "adaptive-proposal-1"),
            ]
        } else {
            [
                ("procgen_request", "procgen-request-1"),
                (
                    "procgen_bundle",
                    if name == "procgen-lifecycle-result-2" {
                        "procgen-bundle-2"
                    } else {
                        "procgen-bundle-1"
                    },
                ),
                (
                    "world_ir",
                    if name == "procgen-lifecycle-result-2" {
                        "world-ir-2"
                    } else {
                        "world-ir-1"
                    },
                ),
                ("site_ir", "site-ir-1"),
                ("gameplay_ir", "gameplay-ir-1"),
                ("presentation_ir", "presentation-ir-1"),
                ("generation_trace", "generation-trace-1"),
                ("adaptive_proposal", "adaptive-proposal-1"),
            ]
        };
        for (field, value) in exports {
            def(root, "ExportSchemas")["properties"][field] = serde_json::json!({"const":value});
        }
        root["properties"]["request_id"] = serde_json::json!({"anyOf":[{"type":"integer","minimum":1,"maximum":9223372036854775807i64},{"type":"null"}]});
        let mut rules = Vec::new();
        for status in ["accepted", "queued", "running", "cancel_requested"] {
            rules.push(serde_json::json!({"if":{"properties":{"status":{"const":status}}},"then":{"required":["request_id"],"properties":{"request_id":{"type":"integer","minimum":1,"maximum":9223372036854775807i64},"bundle":{"const":null},"failure":{"const":null}}}}));
        }
        rules.push(serde_json::json!({"if":{"properties":{"status":{"const":"completed"}}},"then":{"required":["bundle"],"properties":{"bundle":{"not":{"const":null}},"failure":{"const":null}}}}));
        rules.push(serde_json::json!({"if":{"properties":{"status":{"const":"failed"}}},"then":{"required":["failure"],"properties":{"bundle":{"const":null},"failure":{"not":{"const":null}}}}}));
        root["allOf"] = Value::Array(rules);
    } else if name == "procgen-capabilities-2" {
        def(root, "ProcgenCapabilities")["properties"]["schema_version"] =
            serde_json::json!({"const":"procgen-capabilities-2"});
        let capabilities = def(root, "ProcgenCapabilities");
        for field in [
            "queue_capacity",
            "retained_results",
            "max_request_bytes",
            "max_entities",
            "max_trace_entries",
            "max_events",
            "deadline_ms",
        ] {
            capabilities["properties"][field]["minimum"] = serde_json::json!(1);
        }
        capabilities["properties"]["target"] = serde_json::json!({"type":"string","minLength":1});
        capabilities["properties"]["supported_domains"] =
            serde_json::json!({"const":["world","site","gameplay","presentation"]});
        capabilities["properties"]["max_events"] =
            serde_json::json!({"type":"integer","minimum":1,"maximum":32});
        capabilities["properties"]["max_trace_entries"] =
            serde_json::json!({"type":"integer","minimum":1,"maximum":4096});
        root["allOf"] = serde_json::json!([{"if":{"properties":{"worker_mode":{"const":"thread_pool"}}},"then":{"properties":{"worker_count":{"minimum":1}}}}]);
        for (field, value) in [
            ("lifecycle_result", "procgen-lifecycle-result-3"),
            ("capabilities", "procgen-capabilities-2"),
            ("generator_manifest", "procgen-generator-manifest-2"),
        ] {
            def(root, "AdapterSchemas")["properties"][field] = serde_json::json!({"const":value});
        }
    } else if name == "procgen-generator-manifest-2" {
        def(root, "GeneratorManifest")["properties"]["schema_version"] =
            serde_json::json!({"const":"procgen-generator-manifest-2"});
        def(root, "GeneratorManifest")["properties"]["generator_version"] =
            serde_json::json!({"const":3});
        def(root, "GeneratorManifest")["properties"]["rust_source_commit"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{40}$"});
        def(root, "GeneratorManifest")["properties"]["content_manifest_hash"] =
            serde_json::json!({"type":"string","pattern":"^[a-f0-9]{64}$"});
        let manifest = def(root, "GeneratorManifest");
        manifest["properties"]["target"] = serde_json::json!({"type":"string","minLength":1});
        let exports = def(root, "ExportSchemas")["properties"]
            .as_object_mut()
            .unwrap();
        for (field, value) in [
            ("procgen_request", "procgen-request-1"),
            ("procgen_bundle", "procgen-bundle-3"),
            ("world_ir", "world-ir-2"),
            ("site_ir", "site-ir-2"),
            ("gameplay_ir", "gameplay-ir-1"),
            ("presentation_ir", "presentation-ir-1"),
            ("generation_trace", "generation-trace-2"),
            ("adaptive_proposal", "adaptive-proposal-1"),
        ] {
            exports[field] = serde_json::json!({"const":value});
        }
        for (field, value) in [
            ("lifecycle_result", "procgen-lifecycle-result-3"),
            ("capabilities", "procgen-capabilities-2"),
            ("generator_manifest", "procgen-generator-manifest-2"),
        ] {
            def(root, "AdapterSchemas")["properties"][field] = serde_json::json!({"const":value});
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
    verify_immutable_pre_gate3(&out);
    let mut items: Vec<(&str, Value)> = vec![
        ("procgen-request-1", schema::<ProcgenRequest>()),
        ("procgen-request-2", schema::<ProcgenRequest>()),
        // Prior bundle/world/site/trace/lifecycle schemas are immutable
        // migration evidence and are not regenerated from current contracts.
        ("site-ir-2", schema::<SiteIR>()),
        ("gameplay-ir-1", schema::<GameplayIR>()),
        ("gameplay-ir-2", schema::<GameplayIR>()),
        ("presentation-ir-1", schema::<PresentationIR>()),
        ("presentation-ir-2", schema::<PresentationIR>()),
        ("generation-trace-2", schema::<GenerationTrace>()),
        ("generation-trace-3", schema::<GenerationTrace>()),
        ("adaptive-proposal-1", schema::<AdaptiveProposal>()),
        ("player-model-1", schema::<PlayerModel>()),
        ("player-model-2", schema::<PlayerModel>()),
        ("procgen-failure-1", schema::<ProcgenFailure>()),
        ("generation-metrics-1", schema::<GenerationMetrics>()),
        // procgen-lifecycle-result-1 is immutable migration evidence.
        ("procgen-capabilities-2", schema::<ProcgenCapabilities>()),
        ("procgen-capabilities-3", schema::<ProcgenCapabilities>()),
        (
            "procgen-generator-manifest-2",
            schema::<GeneratorManifest>(),
        ),
        (
            "procgen-generator-manifest-3",
            schema::<GeneratorManifest>(),
        ),
        ("procgen-build-manifest-3", schema::<BuildManifest>()),
    ];
    // Platform-v3 schemas are additive immutable siblings. Generate them from
    // the Rust contracts rather than maintaining hand-written JSON stubs.
    let mut world_v2 = schema::<derelict_core::world::WorldIRv2>();
    world_v2["title"] = Value::String("world-ir-2".into());
    world_v2["$id"] = Value::String("world-ir-2".into());
    apply_platform_v3_constraints(&mut world_v2);
    items.push(("world-ir-2", world_v2));
    let mut bundle_v3 = schema::<ProcgenBundle>();
    bundle_v3["title"] = Value::String("procgen-bundle-3".into());
    bundle_v3["$id"] = Value::String("procgen-bundle-3".into());
    apply_platform_v3_constraints(&mut bundle_v3);
    items.push(("procgen-bundle-3", bundle_v3));
    let mut bundle_v4 = schema::<ProcgenBundle>();
    bundle_v4["title"] = Value::String("procgen-bundle-4".into());
    bundle_v4["$id"] = Value::String("procgen-bundle-4".into());
    items.push(("procgen-bundle-4", bundle_v4));
    let mut lifecycle_v3 = schema::<LifecycleResult>();
    lifecycle_v3["title"] = Value::String("procgen-lifecycle-result-3".into());
    lifecycle_v3["$id"] = Value::String("procgen-lifecycle-result-3".into());
    apply_platform_v3_constraints(&mut lifecycle_v3);
    items.push(("procgen-lifecycle-result-3", lifecycle_v3));
    let mut lifecycle_v4 = schema::<LifecycleResult>();
    lifecycle_v4["title"] = Value::String("procgen-lifecycle-result-4".into());
    lifecycle_v4["$id"] = Value::String("procgen-lifecycle-result-4".into());
    items.push(("procgen-lifecycle-result-4", lifecycle_v4));
    let write = env::args().any(|arg| arg == "--write");
    let check = env::args().any(|arg| arg == "--check");
    if !write && !check {
        eprintln!("usage: export_schemas --write|--check");
        process::exit(2);
    }
    for (name, value) in items {
        // Historical v1/v2/v3 documents are immutable migration evidence;
        // only Gate 3 siblings are writable/checkable from this exporter.
        if !matches!(
            name,
            "procgen-request-2"
                | "player-model-2"
                | "gameplay-ir-2"
                | "presentation-ir-2"
                | "generation-trace-3"
                | "procgen-bundle-4"
                | "procgen-lifecycle-result-4"
                | "procgen-capabilities-3"
                | "procgen-generator-manifest-3"
                | "procgen-build-manifest-3"
        ) {
            continue;
        }
        let mut value = value;
        enrich(name, &mut value);
        if matches!(
            name,
            "world-ir-2"
                | "site-ir-2"
                | "generation-trace-2"
                | "procgen-bundle-3"
                | "procgen-lifecycle-result-3"
        ) {
            apply_platform_v3_constraints(&mut value);
        }
        if matches!(
            name,
            "procgen-request-2"
                | "player-model-2"
                | "gameplay-ir-2"
                | "presentation-ir-2"
                | "generation-trace-3"
                | "procgen-bundle-4"
                | "procgen-lifecycle-result-4"
                | "procgen-capabilities-3"
                | "procgen-generator-manifest-3"
                | "procgen-build-manifest-3"
        ) {
            apply_gate3_constraints(name, &mut value);
        }
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

fn verify_immutable_pre_gate3(schema_dir: &std::path::Path) {
    for (name, expected) in [
        (
            "adaptive-proposal-1.schema.json",
            "9D92DF4F8479A963E078E357F7553BBE26EF48DEC862A3EE8C95FAF7DF6625E5",
        ),
        (
            "gameplay-ir-1.schema.json",
            "CF8DECF0E1684D83F11BE4385DC334898E9E6BDC983356833799C9EF0DC132EA",
        ),
        (
            "generation-metrics-1.schema.json",
            "FE8652BB89E885D7B7CA81595C15F8D784F9CD91CF5B773E0094D042EE23630F",
        ),
        (
            "generation-trace-1.schema.json",
            "D2695A69D7B0CBF03DB07E530FEB3C1CB5392B94DF37969E08277C5B25E02B2F",
        ),
        (
            "generation-trace-2.schema.json",
            "F5A1702B329F15E4DEEFC69ADAF29AFECE4D96E63A0010EFC67B838905499C18",
        ),
        (
            "player-model-1.schema.json",
            "5BC50428586F9D42A4407A921B4EE34C334BC028B6A700FED78FECEFBF730761",
        ),
        (
            "presentation-ir-1.schema.json",
            "DEC7EAB72963E43CE34F51F61A031883F7CA5F3F95F0D92357C7F3418CA23E0E",
        ),
        (
            "procgen-build-manifest-1.schema.json",
            "54DEB28202A87816F51AB4B1CFE36C5684F67DC167B1F1C96562E20C6D569EDB",
        ),
        (
            "procgen-build-manifest-2.schema.json",
            "9DD18BBB3D642CD72F8615A1857020AACC3214E51219F09862BAAD17B74441E0",
        ),
        (
            "procgen-bundle-1.schema.json",
            "B99DCF19B4F1D515CCE8A0602ACAE41325B5E35ACACEE226D0ABCAA1AE063FBC",
        ),
        (
            "procgen-bundle-2.schema.json",
            "88CAEBDE282FF786E8EE2F867E580E5D45516D5B4E8F98E95B9B6C0B09422CFA",
        ),
        (
            "procgen-bundle-3.schema.json",
            "4ACD9F41C6A8920F81FC353948FAA56D08C7EAAF0AD02EE1A635A6DCF72BB967",
        ),
        (
            "procgen-capabilities-1.schema.json",
            "F287CB6FC652050FE95FC6FBC1A4EBF206C3B651ED0DABD7B7FE90F6D465DB9B",
        ),
        (
            "procgen-capabilities-2.schema.json",
            "460660C13D260ECE00A816156F2C1AF4D204CF518DC3C8C42E55C96BAB58A727",
        ),
        (
            "procgen-failure-1.schema.json",
            "FB4D455CBABF3F0285BAC7AF1E8103C554D4BB6C0611F50C8909AD7B4176D6A1",
        ),
        (
            "procgen-generator-manifest-1.schema.json",
            "5AB3BE902860518471178E60D6F22A7F6FF3FF1C093524E6237F341BFAA0921D",
        ),
        (
            "procgen-generator-manifest-2.schema.json",
            "F90A9253752F057AE87297AF239409DA79E9F8696532649E92F935394E26D61F",
        ),
        (
            "procgen-lifecycle-result-1.schema.json",
            "C1B31FC1CB6F859D57250B4A9770E303D4DF21B7B4E23B1858DBA104B761109D",
        ),
        (
            "procgen-lifecycle-result-2.schema.json",
            "8555ABBFB99310EBFA593F65C51ADB6C64BBC78872C4D6A27CF90AD932FB0BFB",
        ),
        (
            "procgen-lifecycle-result-3.schema.json",
            "8BF453AD4318F77844826496C485DF106BC353CDAD24BAB61A86B5B8E6436962",
        ),
        (
            "procgen-request-1.schema.json",
            "2D0A976D74315B97F7A9C7C07329FAD10F248639BDD09ABEF1E885BD89E7E1E2",
        ),
        (
            "site-ir-1.schema.json",
            "472EE16BFE3FF2E1DCE0C718C685EACA613FFEF0072DE806752AB913A46461CE",
        ),
        (
            "site-ir-2.schema.json",
            "CD0D56D693BCF695B89BCFED3AC9DEB7CF1EB5AA073515FD5E65360A13D8FABB",
        ),
        (
            "world-ir-1.schema.json",
            "6B61E97D569744DBAA46541244D16233F7F0DBA619D2322A5BEC0ACA84780F96",
        ),
        (
            "world-ir-2.schema.json",
            "D091226A46031BAF75CAD3E834F8C2032F58CA37884F4FFBCEFD14F83DB1205E",
        ),
    ] {
        let path = schema_dir.join(name);
        let bytes =
            fs::read(&path).unwrap_or_else(|e| panic!("immutable schema {}: {e}", path.display()));
        let actual = Sha256::digest(bytes);
        let actual = actual
            .iter()
            .map(|b| format!("{b:02X}"))
            .collect::<String>();
        if actual != expected {
            panic!("immutable schema drift: {}", path.display());
        }
    }
}
