use derelict_core::lifecycle::{
    AdapterKind, AdapterSchemas, GeneratorManifest, ProcgenCapabilities, WorkerMode,
    PROCGEN_CAPABILITIES_SCHEMA, PROCGEN_GENERATOR_MANIFEST_SCHEMA,
    PROCGEN_LIFECYCLE_RESULT_SCHEMA,
};
use derelict_core::manifest::{
    Artifact, BuildManifest, ExportSchemas, ADAPTIVE_PROPOSAL_SCHEMA, GAMEPLAY_IR_SCHEMA,
    GENERATION_TRACE_SCHEMA, MANIFEST_SCHEMA, PROCGEN_BUNDLE_SCHEMA,
};

const HASH: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const COMMIT: &str = "b78fedf2624c2d54f0f42b6c0ad3c488fbd9e6a9";

#[test]
fn current_v5_maps_and_aliases_are_exact() {
    assert_eq!(MANIFEST_SCHEMA, "procgen-build-manifest-4");
    assert_eq!(PROCGEN_BUNDLE_SCHEMA, "procgen-bundle-5");
    assert_eq!(GAMEPLAY_IR_SCHEMA, "gameplay-ir-3");
    assert_eq!(GENERATION_TRACE_SCHEMA, "generation-trace-4");
    assert_eq!(ADAPTIVE_PROPOSAL_SCHEMA, "adaptive-proposal-2");
    assert_eq!(
        PROCGEN_LIFECYCLE_RESULT_SCHEMA,
        "procgen-lifecycle-result-5"
    );
    assert_eq!(PROCGEN_CAPABILITIES_SCHEMA, "procgen-capabilities-4");
    assert_eq!(
        PROCGEN_GENERATOR_MANIFEST_SCHEMA,
        "procgen-generator-manifest-4"
    );
    assert_eq!(
        ExportSchemas::platform_v5(),
        ExportSchemas {
            procgen_request: "procgen-request-2".into(),
            procgen_bundle: "procgen-bundle-5".into(),
            world_ir: "world-ir-2".into(),
            site_ir: "site-ir-2".into(),
            gameplay_ir: "gameplay-ir-3".into(),
            presentation_ir: "presentation-ir-2".into(),
            generation_trace: "generation-trace-4".into(),
            adaptive_proposal: "adaptive-proposal-2".into(),
        }
    );
    assert_eq!(
        AdapterSchemas::platform_v5(),
        AdapterSchemas {
            lifecycle_result: "procgen-lifecycle-result-5".into(),
            capabilities: "procgen-capabilities-4".into(),
            generator_manifest: "procgen-generator-manifest-4".into(),
        }
    );
}

#[test]
fn platform_v4_remains_unchanged() {
    assert_eq!(
        ExportSchemas::platform_v4().procgen_bundle,
        "procgen-bundle-4"
    );
    assert_eq!(ExportSchemas::platform_v4().gameplay_ir, "gameplay-ir-2");
    assert_eq!(
        ExportSchemas::platform_v4().generation_trace,
        "generation-trace-3"
    );
    assert_eq!(
        ExportSchemas::platform_v4().adaptive_proposal,
        "adaptive-proposal-1"
    );
    assert_eq!(
        AdapterSchemas::platform_v4().lifecycle_result,
        "procgen-lifecycle-result-4"
    );
    assert_eq!(
        AdapterSchemas::platform_v4().capabilities,
        "procgen-capabilities-3"
    );
    assert_eq!(
        AdapterSchemas::platform_v4().generator_manifest,
        "procgen-generator-manifest-3"
    );
}

fn manifest(target: &str, kind: &str, path: &str) -> BuildManifest {
    BuildManifest {
        manifest_schema: MANIFEST_SCHEMA.into(),
        rust_source_commit: COMMIT.into(),
        generator_version: 3,
        content_manifest_path: "data/procgen/manifests/content_manifest.json".into(),
        content_manifest_hash: HASH.into(),
        target: target.into(),
        artifact: Artifact {
            kind: kind.into(),
            path: path.into(),
            sha256: HASH.into(),
        },
        export_schemas: ExportSchemas::platform_v5(),
    }
}

#[test]
fn v5_manifest_accepts_native_and_web_and_rejects_mixed_maps() {
    let native = manifest(
        "x86_64-pc-windows-msvc",
        "gdextension",
        "addons/derelict/bin/win64/derelict_godot.dll",
    );
    let web = manifest(
        "wasm32-unknown-unknown",
        "wasm",
        "addons/derelict/bin/web/derelict_wasm_bg.wasm",
    );
    native.validate_platform_v5().unwrap();
    web.validate_platform_v5().unwrap();
    for field in [
        "procgen_bundle",
        "gameplay_ir",
        "generation_trace",
        "adaptive_proposal",
    ] {
        let mut mixed = native.clone();
        let mut map = mixed.export_schemas.clone();
        match field {
            "procgen_bundle" => map.procgen_bundle = "procgen-bundle-4".into(),
            "gameplay_ir" => map.gameplay_ir = "gameplay-ir-2".into(),
            "generation_trace" => map.generation_trace = "generation-trace-3".into(),
            "adaptive_proposal" => map.adaptive_proposal = "adaptive-proposal-1".into(),
            _ => unreachable!(),
        }
        mixed.export_schemas = map;
        assert!(
            mixed.validate_platform_v5().is_err(),
            "mixed {field} accepted"
        );
    }
}

#[test]
fn v5_manifest_json_is_closed_and_current_parse_uses_v5() {
    let json = serde_json::to_string(&manifest(
        "x86_64-pc-windows-msvc",
        "gdextension",
        "addons/derelict/bin/win64/derelict_godot.dll",
    ))
    .unwrap();
    BuildManifest::from_json_platform_v5(&json).unwrap();
    BuildManifest::from_json(&json).unwrap();
    let extra = json.trim_end_matches('}').to_owned() + ",\"extra\":true}";
    assert!(BuildManifest::from_json_platform_v5(&extra).is_err());
}

fn capabilities() -> ProcgenCapabilities {
    ProcgenCapabilities {
        schema_version: PROCGEN_CAPABILITIES_SCHEMA.into(),
        adapter_kind: AdapterKind::Native,
        target: "x86_64-pc-windows-msvc".into(),
        supports_sync: true,
        supports_async: true,
        supports_cancel: true,
        worker_mode: WorkerMode::ThreadPool,
        worker_count: 2,
        queue_capacity: 8,
        retained_results: 16,
        max_request_bytes: 65536,
        max_entities: 4096,
        max_trace_entries: 4096,
        max_events: 32,
        deadline_ms: 2000,
        supported_domains: vec![
            derelict_core::procgen::Domain::World,
            derelict_core::procgen::Domain::Site,
            derelict_core::procgen::Domain::Gameplay,
            derelict_core::procgen::Domain::Presentation,
        ],
        schemas: AdapterSchemas::platform_v5(),
    }
}

fn generator_manifest() -> GeneratorManifest {
    GeneratorManifest {
        schema_version: PROCGEN_GENERATOR_MANIFEST_SCHEMA.into(),
        rust_source_commit: COMMIT.into(),
        generator_version: 3,
        content_manifest_hash: HASH.into(),
        export_schemas: ExportSchemas::platform_v5(),
        adapter_schemas: AdapterSchemas::platform_v5(),
        target: "x86_64-pc-windows-msvc".into(),
        dirty_development: false,
    }
}

#[test]
fn v5_capabilities_and_generator_manifest_validate_and_are_closed() {
    let caps = capabilities();
    caps.validate().unwrap();
    let caps_json = serde_json::to_string(&caps).unwrap();
    ProcgenCapabilities::from_json(&caps_json).unwrap();
    let caps_extra = caps_json.trim_end_matches('}').to_owned() + ",\"extra\":true}";
    assert!(ProcgenCapabilities::from_json(&caps_extra).is_err());

    let manifest = generator_manifest();
    manifest.validate().unwrap();
    let json = serde_json::to_string(&manifest).unwrap();
    GeneratorManifest::from_json(&json).unwrap();
    let extra = json.trim_end_matches('}').to_owned() + ",\"extra\":true}";
    assert!(GeneratorManifest::from_json(&extra).is_err());
}

#[test]
fn v5_generator_manifest_rejects_every_v4_export_and_adapter_substitution() {
    for field in [
        "procgen_request",
        "procgen_bundle",
        "world_ir",
        "site_ir",
        "gameplay_ir",
        "presentation_ir",
        "generation_trace",
        "adaptive_proposal",
    ] {
        let mut invalid = generator_manifest();
        let mut map = invalid.export_schemas.clone();
        match field {
            "procgen_request" => map.procgen_request = "procgen-request-1".into(),
            "procgen_bundle" => map.procgen_bundle = "procgen-bundle-4".into(),
            "world_ir" => map.world_ir = "world-ir-1".into(),
            "site_ir" => map.site_ir = "site-ir-1".into(),
            "gameplay_ir" => map.gameplay_ir = "gameplay-ir-2".into(),
            "presentation_ir" => map.presentation_ir = "presentation-ir-1".into(),
            "generation_trace" => map.generation_trace = "generation-trace-3".into(),
            "adaptive_proposal" => map.adaptive_proposal = "adaptive-proposal-1".into(),
            _ => unreachable!(),
        }
        invalid.export_schemas = map;
        assert!(invalid.validate().is_err(), "v4 export {field} accepted");
    }
    for field in ["lifecycle_result", "capabilities", "generator_manifest"] {
        let mut invalid = generator_manifest();
        let mut map = invalid.adapter_schemas.clone();
        match field {
            "lifecycle_result" => map.lifecycle_result = "procgen-lifecycle-result-4".into(),
            "capabilities" => map.capabilities = "procgen-capabilities-3".into(),
            "generator_manifest" => map.generator_manifest = "procgen-generator-manifest-3".into(),
            _ => unreachable!(),
        }
        invalid.adapter_schemas = map;
        assert!(invalid.validate().is_err(), "v4 adapter {field} accepted");
    }
}

#[test]
fn explicit_v4_build_manifest_validation_remains_accepted() {
    let mut prior = manifest(
        "x86_64-pc-windows-msvc",
        "gdextension",
        "addons/derelict/bin/win64/derelict_godot.dll",
    );
    prior.manifest_schema = "procgen-build-manifest-3".into();
    prior.export_schemas = ExportSchemas {
        procgen_request: "procgen-request-2".into(),
        procgen_bundle: "procgen-bundle-4".into(),
        world_ir: "world-ir-2".into(),
        site_ir: "site-ir-2".into(),
        gameplay_ir: "gameplay-ir-2".into(),
        presentation_ir: "presentation-ir-2".into(),
        generation_trace: "generation-trace-3".into(),
        adaptive_proposal: "adaptive-proposal-1".into(),
    };
    prior.validate_platform_v4().unwrap();
}
