use derelict_core::lifecycle::*;
use derelict_core::manifest::ExportSchemas;
use derelict_core::procgen::{Domain, ProcgenFailure, ProcgenFailureCode, FAILURE_SCHEMA};

fn failure() -> ProcgenFailure {
    ProcgenFailure {
        schema_version: FAILURE_SCHEMA.into(),
        code: ProcgenFailureCode::UnknownRequest,
        stage: "lifecycle".into(),
        message: "unknown request".into(),
        retryable: false,
        fallback_id: None,
    }
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
        max_request_bytes: 64 * 1024,
        max_entities: 4096,
        max_trace_entries: 4096,
        max_events: 32,
        deadline_ms: 2000,
        supported_domains: vec![
            Domain::World,
            Domain::Site,
            Domain::Gameplay,
            Domain::Presentation,
        ],
        schemas: AdapterSchemas::v1(),
    }
}

#[test]
fn lifecycle_failure_round_trip_and_state_validation() {
    let result = LifecycleResult::failed(
        Some(7),
        failure(),
        vec![LifecycleEvent::Admitted, LifecycleEvent::Failed],
    );
    result.validate().unwrap();
    let json = serde_json::to_string(&result).unwrap();
    assert_eq!(LifecycleResult::from_json(&json).unwrap(), result);

    let mut invalid = serde_json::to_value(&result).unwrap();
    invalid["bundle"] = serde_json::json!({});
    assert!(LifecycleResult::from_json(&serde_json::to_string(&invalid).unwrap()).is_err());
}

#[test]
fn capabilities_and_manifest_reject_bad_identity_and_limits() {
    let mut value = capabilities();
    value.validate().unwrap();
    value.supported_domains.swap(0, 1);
    assert!(value.validate().is_err());
    value = capabilities();
    value.max_events = 0;
    assert!(value.validate().is_err());

    let manifest = GeneratorManifest {
        schema_version: PROCGEN_GENERATOR_MANIFEST_SCHEMA.into(),
        rust_source_commit: "a".repeat(40),
        generator_version: 2,
        content_manifest_hash: "b".repeat(64),
        export_schemas: ExportSchemas::v1(),
        adapter_schemas: AdapterSchemas::v1(),
        target: "wasm32-unknown-unknown".into(),
        dirty_development: false,
    };
    manifest.validate().unwrap();
    let bad = serde_json::to_string(&manifest)
        .unwrap()
        .replace("dirty_development", "unknown");
    assert!(GeneratorManifest::from_json(&bad).is_err());
}

#[test]
fn event_bounds_and_failure_codes_are_stable() {
    let mut result = LifecycleResult::failed(Some(1), failure(), vec![LifecycleEvent::Failed]);
    result.events = vec![LifecycleEvent::Failed; 33];
    assert!(result.validate().is_err());
    for code in [
        ProcgenFailureCode::UnknownRequest,
        ProcgenFailureCode::ResultConsumed,
        ProcgenFailureCode::ResultExpired,
        ProcgenFailureCode::Shutdown,
        ProcgenFailureCode::TooLateCancellation,
    ] {
        let encoded = serde_json::to_string(&code).unwrap();
        assert_eq!(
            serde_json::from_str::<ProcgenFailureCode>(&encoded).unwrap(),
            code
        );
    }
}
