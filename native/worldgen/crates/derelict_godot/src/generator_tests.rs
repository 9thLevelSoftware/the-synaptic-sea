use super::generator::{legacy_request, runtime_capabilities, runtime_manifest, serialize_json};
use derelict_core::lifecycle::AdapterKind;

#[test]
fn compiled_identity_constructs_valid_manifest_and_exact_capabilities() {
    let manifest = runtime_manifest().expect("compiled manifest");
    assert_eq!(manifest.generator_version, 2);
    assert_eq!(
        manifest.adapter_schemas,
        derelict_core::lifecycle::AdapterSchemas::v1()
    );
    assert_eq!(
        manifest.export_schemas,
        derelict_core::manifest::ExportSchemas::v1()
    );
    assert!(manifest.validate().is_ok());

    let capabilities = runtime_capabilities().expect("compiled capabilities");
    assert_eq!(capabilities.adapter_kind, AdapterKind::Native);
    assert_eq!(capabilities.worker_count, 2);
    assert_eq!(capabilities.queue_capacity, 8);
    assert_eq!(capabilities.retained_results, 16);
    assert_eq!(capabilities.max_request_bytes, 64 * 1024);
    assert_eq!(capabilities.max_entities, 4096);
    assert_eq!(capabilities.max_trace_entries, 4096);
    assert_eq!(capabilities.max_events, 32);
    assert_eq!(capabilities.deadline_ms, 2000);
    assert!(capabilities.validate().is_ok());
}

#[test]
fn legacy_request_is_explicitly_normalized() {
    let request = legacy_request(42, &derelict_core::model::GenParams::new("shuttle"), "");
    assert_eq!(request.schema_version, "procgen-request-1");
    assert_eq!(request.generator_version, 2);
    assert_eq!(request.site.site_id, "legacy-site");
    assert_eq!(request.site.kit_id, "ship_structural_v0");
    assert_eq!(request.difficulty_id, "standard");
    assert_eq!(request.presentation.locale, "en-US");
    assert_eq!(request.player_model.schema_version, "player-model-1");
    assert!(!request.content_manifest_hash.is_empty());
    assert!(request.validate().is_ok());
}

#[test]
fn blank_legacy_identity_uses_authored_defaults() {
    let mut params = derelict_core::model::GenParams::new("   ");
    let request = super::generator::legacy_request(42, &params, "  ");
    assert_eq!(request.site.archetype_id, "corvette");
    assert_eq!(request.site.kit_id, "ship_structural_v0");
    params.archetype_id = " shuttle ".into();
    let explicit = super::generator::legacy_request(42, &params, " custom-kit ");
    assert_eq!(explicit.site.archetype_id, "shuttle");
    assert_eq!(explicit.site.kit_id, "custom-kit");
}

#[test]
fn legacy_export_failures_are_valid_lifecycle_documents() {
    let failure = derelict_core::procgen::ProcgenFailure {
        schema_version: "procgen-failure-1".into(),
        code: derelict_core::procgen::ProcgenFailureCode::GenerationFailure,
        stage: "generation".into(),
        message: "failed".into(),
        retryable: false,
        fallback_id: None,
    };
    let result = derelict_core::lifecycle::LifecycleResult::failed(
        None,
        failure,
        vec![derelict_core::lifecycle::LifecycleEvent::Failed],
    );
    let json = super::generator::export_result_json(
        result,
        |_| Err(derelict_core::procgen::ProcgenError::InvalidRequest("test")),
        serde_json::to_string,
    );
    assert!(derelict_core::lifecycle::LifecycleResult::from_json(&json).is_ok());
    assert_eq!(
        derelict_core::lifecycle::LifecycleResult::from_json(&json)
            .unwrap()
            .failure
            .unwrap()
            .code,
        derelict_core::procgen::ProcgenFailureCode::GenerationFailure
    );
}

#[test]
fn runtime_access_reuses_identical_service() {
    let first = super::generator::runtime().unwrap();
    let second = super::generator::runtime().unwrap();
    assert!(std::sync::Arc::ptr_eq(&first.service, &second.service));
}

#[test]
fn serialization_failure_is_a_stable_adapter_failure() {
    let result = serialize_json::<derelict_core::lifecycle::GeneratorManifest, _>(
        &runtime_manifest().expect("compiled manifest"),
        |_| Err(serde_json::Error::io(std::io::Error::other("injected"))),
    );
    let parsed = derelict_core::lifecycle::LifecycleResult::from_json(&result).unwrap();
    assert_eq!(
        parsed.failure.unwrap().code,
        derelict_core::procgen::ProcgenFailureCode::AdapterFailure
    );
}
