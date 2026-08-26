use derelict_core::manifest::{BuildManifest, ManifestError};

const VALID: &str = r#"{
  "manifest_schema":"procgen-build-manifest-1",
  "rust_source_commit":"b78fedf2624c2d54f0f42b6c0ad3c488fbd9e6a9",
  "generator_version":2,
  "content_manifest_path":"data/procgen/manifests/content_manifest.json",
  "content_manifest_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "target":"x86_64-pc-windows-msvc",
  "artifact":{"kind":"gdextension","path":"addons/derelict/bin/win64/derelict_godot.dll","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
  "export_schemas":{"procgen_request":"procgen-request-1","procgen_bundle":"procgen-bundle-1","world_ir":"world-ir-1","site_ir":"site-ir-1","gameplay_ir":"gameplay-ir-1","presentation_ir":"presentation-ir-1","generation_trace":"generation-trace-1","adaptive_proposal":"adaptive-proposal-1"}
}"#;

#[test]
fn valid_manifest_parses_and_validates() {
    let manifest = BuildManifest::from_json(VALID).unwrap();
    manifest.validate().unwrap();
}

#[test]
fn unknown_major_is_rejected() {
    let json = VALID.replace("procgen-build-manifest-1", "procgen-build-manifest-2");
    assert!(matches!(BuildManifest::from_json(&json), Err(ManifestError::UnknownSchemaMajor(_))));
}

#[test]
fn malformed_hash_is_rejected() {
    let json = VALID.replace("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bad");
    assert!(BuildManifest::from_json(&json).is_err());
}

#[test]
fn unknown_structural_field_is_rejected() {
    let json = VALID.replace("\n}", ",\n  \"unexpected\": true\n}");
    assert!(BuildManifest::from_json(&json).is_err());
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
        ("b78fedf2624c2d54f0f42b6c0ad3c488fbd9e6a9", "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"),
        ("data/procgen/manifests/content_manifest.json", "wrong.json"),
        ("x86_64-pc-windows-msvc", "linux"),
        ("procgen-request-1", "wrong-schema"),
    ];
    for (needle, replacement) in cases {
        let json = VALID.replace(needle, replacement);
        assert!(BuildManifest::from_json(&json).is_err(), "tampered field {needle}");
    }
}
