use derelict_core::manifest::{BuildManifest, ManifestError};

const VALID: &str = r#"{
  "manifest_schema":"procgen-build-manifest-2",
  "rust_source_commit":"b78fedf2624c2d54f0f42b6c0ad3c488fbd9e6a9",
  "generator_version":3,
  "content_manifest_path":"data/procgen/manifests/content_manifest.json",
  "content_manifest_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "target":"x86_64-pc-windows-msvc",
  "artifact":{"kind":"gdextension","path":"addons/derelict/bin/win64/derelict_godot.dll","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
  "export_schemas":{"procgen_request":"procgen-request-1","procgen_bundle":"procgen-bundle-3","world_ir":"world-ir-2","site_ir":"site-ir-2","gameplay_ir":"gameplay-ir-1","presentation_ir":"presentation-ir-1","generation_trace":"generation-trace-2","adaptive_proposal":"adaptive-proposal-1"}
}"#;

#[test]
fn valid_manifest_parses_and_validates() {
    let manifest = BuildManifest::from_json_platform_v3(VALID).unwrap();
    manifest.validate_platform_v3().unwrap();
}

#[test]
fn unknown_major_is_rejected() {
    let json = VALID.replace("procgen-build-manifest-2", "procgen-build-manifest-3");
    assert!(matches!(
        BuildManifest::from_json_platform_v3(&json),
        Err(ManifestError::UnknownSchemaMajor(_))
    ));
}

#[test]
fn malformed_hash_is_rejected() {
    let json = VALID.replace(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "bad",
    );
    assert!(BuildManifest::from_json_platform_v3(&json).is_err());
}

#[test]
fn unknown_structural_field_is_rejected() {
    let json = VALID.replace("\n}", ",\n  \"unexpected\": true\n}");
    assert!(BuildManifest::from_json_platform_v3(&json).is_err());
}

#[test]
fn content_manifest_requires_sorted_entries_and_no_unknown_fields() {
    let valid = r#"{"manifest_schema":"procgen-content-manifest-1","files":[{"path":"a","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],"content_manifest_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#;
    assert!(BuildManifest::content_from_json(valid).is_ok());
    let extra = valid.replace("}", ",\"extra\":1}");
    assert!(BuildManifest::content_from_json(&extra).is_err());
}

#[test]
fn every_required_build_field_is_enforced() {
    let cases = [
        (
            "b78fedf2624c2d54f0f42b6c0ad3c488fbd9e6a9",
            "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
        ),
        ("data/procgen/manifests/content_manifest.json", "wrong.json"),
        ("x86_64-pc-windows-msvc", "linux"),
        ("procgen-request-1", "wrong-schema"),
    ];
    for (needle, replacement) in cases {
        let json = VALID.replace(needle, replacement);
        assert!(
            BuildManifest::from_json_platform_v3(&json).is_err(),
            "tampered field {needle}"
        );
    }
    for schema in [
        "procgen_request",
        "procgen_bundle",
        "world_ir",
        "site_ir",
        "gameplay_ir",
        "presentation_ir",
        "generation_trace",
        "adaptive_proposal",
    ] {
        let marker = match schema {
            "procgen_request" => "procgen-request-1",
            "procgen_bundle" => "procgen-bundle-3",
            "world_ir" => "world-ir-2",
            "site_ir" => "site-ir-2",
            "gameplay_ir" => "gameplay-ir-1",
            "presentation_ir" => "presentation-ir-1",
            "generation_trace" => "generation-trace-2",
            _ => "adaptive-proposal-1",
        };
        assert!(
            BuildManifest::from_json_platform_v3(&VALID.replace(marker, "wrong-schema")).is_err(),
            "tampered schema {schema}"
        );
    }
}

#[test]
fn draft_2020_schema_enforces_both_exact_target_artifact_pairs() {
    let legacy_schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../schemas/procgen-build-manifest-1.schema.json"
    ))
    .unwrap();
    let legacy_validator = jsonschema::validator_for(&legacy_schema).unwrap();
    // The published build-manifest-1 schema is an immutable structural
    // contract; validate its historical export map separately from the
    // current platform-v3 map exercised above.
    let legacy = VALID
        .replace("procgen-build-manifest-2", "procgen-build-manifest-1")
        .replace("procgen-bundle-3", "procgen-bundle-2")
        .replace("site-ir-2", "site-ir-1")
        .replace("generation-trace-2", "generation-trace-1");
    let windows: serde_json::Value = serde_json::from_str(&legacy).unwrap();
    assert!(legacy_validator.is_valid(&windows));
    let web = legacy
        .to_string()
        .replace("x86_64-pc-windows-msvc", "wasm32-unknown-unknown")
        .replace("gdextension", "wasm")
        .replace(
            "addons/derelict/bin/win64/derelict_godot.dll",
            "addons/derelict/bin/web/derelict_wasm_bg.wasm",
        );
    assert!(legacy_validator.is_valid(&serde_json::from_str::<serde_json::Value>(&web).unwrap()));
    let mismatch = legacy.replace("gdextension", "wasm");
    assert!(
        !legacy_validator.is_valid(&serde_json::from_str::<serde_json::Value>(&mismatch).unwrap())
    );
    let unknown = legacy.replace("\n}", ",\n  \"unexpected\": true\n}");
    assert!(
        !legacy_validator.is_valid(&serde_json::from_str::<serde_json::Value>(&unknown).unwrap())
    );

    let current_schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../schemas/procgen-build-manifest-2.schema.json"
    ))
    .unwrap();
    let current_validator = jsonschema::validator_for(&current_schema).unwrap();
    let current: serde_json::Value = serde_json::from_str(VALID).unwrap();
    assert!(current_validator.is_valid(&current));
    let substituted = VALID.replace("site-ir-2", "site-ir-1");
    assert!(!current_validator
        .is_valid(&serde_json::from_str::<serde_json::Value>(&substituted).unwrap()));
}
