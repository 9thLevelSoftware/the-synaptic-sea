use derelict_core::lifecycle::{
    AdapterSchemas, PROCGEN_CAPABILITIES_SCHEMA_V3, PROCGEN_GENERATOR_MANIFEST_SCHEMA_V3,
    PROCGEN_LIFECYCLE_RESULT_SCHEMA_V4 as LIFECYCLE_RESULT_SCHEMA_V4,
};
use derelict_core::manifest::{
    BuildManifest, ExportSchemas, GAMEPLAY_IR_SCHEMA_V2, MANIFEST_SCHEMA_V3,
    PRESENTATION_IR_SCHEMA_V2, PROCGEN_BUNDLE_SCHEMA_V4,
    PROCGEN_LIFECYCLE_RESULT_SCHEMA_V4 as MANIFEST_LIFECYCLE_RESULT_SCHEMA_V4,
    PROCGEN_REQUEST_SCHEMA_V2,
};

const HASH: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const COMMIT: &str = "b78fedf2624c2d54f0f42b6c0ad3c488fbd9e6a9";

#[test]
fn platform_v4_maps_are_exact() {
    assert_eq!(
        ExportSchemas::platform_v4(),
        ExportSchemas {
            procgen_request: "procgen-request-2".into(),
            procgen_bundle: "procgen-bundle-4".into(),
            world_ir: "world-ir-2".into(),
            site_ir: "site-ir-2".into(),
            gameplay_ir: "gameplay-ir-2".into(),
            presentation_ir: "presentation-ir-2".into(),
            generation_trace: "generation-trace-2".into(),
            adaptive_proposal: "adaptive-proposal-1".into(),
        }
    );
    assert_eq!(
        AdapterSchemas::platform_v4(),
        AdapterSchemas {
            lifecycle_result: "procgen-lifecycle-result-4".into(),
            capabilities: "procgen-capabilities-3".into(),
            generator_manifest: "procgen-generator-manifest-3".into(),
        }
    );
    assert_eq!(MANIFEST_SCHEMA_V3, "procgen-build-manifest-3");
    assert_eq!(PROCGEN_REQUEST_SCHEMA_V2, "procgen-request-2");
    assert_eq!(PROCGEN_BUNDLE_SCHEMA_V4, "procgen-bundle-4");
    assert_eq!(GAMEPLAY_IR_SCHEMA_V2, "gameplay-ir-2");
    assert_eq!(PRESENTATION_IR_SCHEMA_V2, "presentation-ir-2");
    assert_eq!(
        MANIFEST_LIFECYCLE_RESULT_SCHEMA_V4,
        "procgen-lifecycle-result-4"
    );
    assert_eq!(
        LIFECYCLE_RESULT_SCHEMA_V4,
        MANIFEST_LIFECYCLE_RESULT_SCHEMA_V4
    );
    assert_eq!(PROCGEN_CAPABILITIES_SCHEMA_V3, "procgen-capabilities-3");
    assert_eq!(
        PROCGEN_GENERATOR_MANIFEST_SCHEMA_V3,
        "procgen-generator-manifest-3"
    );
}

#[test]
fn platform_v3_constructors_and_validation_remain_unchanged() {
    let schemas = ExportSchemas::platform_v3();
    assert_eq!(schemas.procgen_request, "procgen-request-1");
    assert_eq!(schemas.procgen_bundle, "procgen-bundle-3");
    assert_eq!(schemas.world_ir, "world-ir-2");
    assert_eq!(schemas.site_ir, "site-ir-2");
    assert_eq!(schemas.gameplay_ir, "gameplay-ir-1");
    assert_eq!(schemas.presentation_ir, "presentation-ir-1");
    assert_eq!(schemas.generation_trace, "generation-trace-2");
    assert_eq!(schemas.adaptive_proposal, "adaptive-proposal-1");
    assert_eq!(
        AdapterSchemas::platform_v3().lifecycle_result,
        "procgen-lifecycle-result-3"
    );
    assert_eq!(
        AdapterSchemas::platform_v3().capabilities,
        "procgen-capabilities-2"
    );
    assert_eq!(
        AdapterSchemas::platform_v3().generator_manifest,
        "procgen-generator-manifest-2"
    );

    let mut prior = manifest(
        "x86_64-pc-windows-msvc",
        "gdextension",
        "addons/derelict/bin/win64/derelict_godot.dll",
    );
    prior.manifest_schema = "procgen-build-manifest-2".into();
    prior.export_schemas = schemas;
    prior.validate_platform_v3().unwrap();
    let json = serde_json::to_string(&prior).unwrap();
    BuildManifest::from_json_platform_v3(&json).unwrap();
}

fn manifest(target: &str, kind: &str, path: &str) -> BuildManifest {
    BuildManifest {
        manifest_schema: MANIFEST_SCHEMA_V3.into(),
        rust_source_commit: COMMIT.into(),
        generator_version: 3,
        content_manifest_path: "data/procgen/manifests/content_manifest.json".into(),
        content_manifest_hash: HASH.into(),
        target: target.into(),
        artifact: derelict_core::manifest::Artifact {
            kind: kind.into(),
            path: path.into(),
            sha256: HASH.into(),
        },
        export_schemas: ExportSchemas::platform_v4(),
    }
}

#[test]
fn platform_v4_accepts_native_and_web_pairs() {
    manifest(
        "x86_64-pc-windows-msvc",
        "gdextension",
        "addons/derelict/bin/win64/derelict_godot.dll",
    )
    .validate_platform_v4()
    .unwrap();
    manifest(
        "wasm32-unknown-unknown",
        "wasm",
        "addons/derelict/bin/web/derelict_wasm_bg.wasm",
    )
    .validate_platform_v4()
    .unwrap();
}

#[test]
fn platform_v4_rejects_tampered_identity_and_map() {
    let valid = manifest(
        "x86_64-pc-windows-msvc",
        "gdextension",
        "addons/derelict/bin/win64/derelict_godot.dll",
    );
    for bad in [
        {
            let mut x = valid.clone();
            x.manifest_schema = "procgen-build-manifest-2".into();
            x
        },
        {
            let mut x = valid.clone();
            x.generator_version = 2;
            x
        },
        {
            let mut x = valid.clone();
            x.rust_source_commit = COMMIT.to_ascii_uppercase();
            x
        },
        {
            let mut x = valid.clone();
            x.content_manifest_hash = "bad".into();
            x
        },
        {
            let mut x = valid.clone();
            x.artifact.sha256 = "BAD".into();
            x
        },
        {
            let mut x = valid.clone();
            x.target = "wasm32-unknown-unknown".into();
            x
        },
        {
            let mut x = valid.clone();
            x.artifact.path = "wrong.dll".into();
            x
        },
        {
            let mut x = valid.clone();
            x.export_schemas.procgen_request = "procgen-request-1".into();
            x
        },
    ] {
        assert!(bad.validate_platform_v4().is_err());
    }
}

#[test]
fn platform_v4_json_and_dto_keys_are_closed() {
    let valid = manifest(
        "x86_64-pc-windows-msvc",
        "gdextension",
        "addons/derelict/bin/win64/derelict_godot.dll",
    );
    let json = serde_json::to_string(&valid).unwrap();
    BuildManifest::from_json_platform_v4(&json).unwrap();
    let extra = json.trim_end_matches('}').to_owned() + ",\"extra\":true}";
    assert!(BuildManifest::from_json_platform_v4(&extra).is_err());
    let schemas = serde_json::to_string(&ExportSchemas::platform_v4()).unwrap();
    assert!(serde_json::from_str::<ExportSchemas>(
        &(schemas.trim_end_matches('}').to_owned() + ",\"extra\":true}")
    )
    .is_err());
    let adapters = serde_json::to_string(&AdapterSchemas::platform_v4()).unwrap();
    assert!(serde_json::from_str::<AdapterSchemas>(
        &(adapters.trim_end_matches('}').to_owned() + ",\"extra\":true}")
    )
    .is_err());
}
