use derelict_core::lifecycle::*;
use derelict_core::manifest::ExportSchemas;
use derelict_core::procgen::{
    generate_bundle, Domain, PlayerModel, PresentationRequest, ProcgenFailure, ProcgenFailureCode,
    ProcgenRequest, SiteRequest, FAILURE_SCHEMA, PLAYER_MODEL_SCHEMA, PROCGEN_REQUEST_SCHEMA,
};

fn schema_valid(name: &str, value: &serde_json::Value) -> bool {
    let path = format!("../../schemas/{name}.schema.json");
    let schema: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    jsonschema::validator_for(&schema).unwrap().is_valid(value)
}

fn request() -> ProcgenRequest {
    ProcgenRequest {
        schema_version: PROCGEN_REQUEST_SCHEMA.into(),
        world_seed: 42,
        site: SiteRequest {
            site_id: "site-a".into(),
            x: 3,
            y: -2,
            archetype_id: "shuttle".into(),
            kit_id: "default".into(),
            intactness_override_bp: None,
            cause_of_loss: None,
            loot_richness_bp: 10_000,
        },
        difficulty_id: "standard".into(),
        player_model: PlayerModel {
            schema_version: PLAYER_MODEL_SCHEMA.into(),
            signals: vec![1, -2],
        },
        requested_domains: vec![
            Domain::World,
            Domain::Site,
            Domain::Gameplay,
            Domain::Presentation,
        ],
        generator_version: 2,
        content_manifest_hash: "a".repeat(64),
        presentation: PresentationRequest {
            seed: 9,
            locale: "en-US".into(),
        },
    }
}

#[test]
fn accepted_omits_optional_payloads_and_capabilities_round_trip() {
    let json = r#"{"schema_version":"procgen-lifecycle-result-1","status":"accepted","request_id":7,"events":["admitted"]}"#;
    let accepted = LifecycleResult::from_json(json).unwrap();
    assert_eq!(accepted.bundle, None);
    assert_eq!(accepted.failure, None);
    let caps = capabilities();
    assert_eq!(
        ProcgenCapabilities::from_json(&serde_json::to_string(&caps).unwrap()).unwrap(),
        caps
    );
}

#[test]
fn lifecycle_nonterminal_constructors_cover_all_states() {
    let events = vec![LifecycleEvent::Admitted];
    for result in [
        LifecycleResult::accepted(1, events.clone()),
        LifecycleResult::queued(1, events.clone()),
        LifecycleResult::running(1, events.clone()),
        LifecycleResult::cancel_requested(1, events.clone()),
    ] {
        result.validate().unwrap();
    }
}

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
    let manifest_value = serde_json::to_value(&manifest).unwrap();
    assert!(schema_valid(
        "procgen-generator-manifest-1",
        &manifest_value
    ));
    let mut bad_schema = manifest_value.clone();
    bad_schema["adapter_schemas"]["capabilities"] = "wrong".into();
    assert!(!schema_valid("procgen-generator-manifest-1", &bad_schema));
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

#[test]
fn lifecycle_schema_and_rust_matrix_match_for_states_ids_and_events() {
    let events = vec![LifecycleEvent::Admitted];
    for result in [
        LifecycleResult::accepted(1, events.clone()),
        LifecycleResult::queued(2, events.clone()),
        LifecycleResult::running(3, events.clone()),
        LifecycleResult::cancel_requested(4, events.clone()),
    ] {
        let value = serde_json::to_value(&result).unwrap();
        assert!(schema_valid("procgen-lifecycle-result-1", &value));
        assert!(LifecycleResult::from_json(&serde_json::to_string(&value).unwrap()).is_ok());
    }
    let bundle = generate_bundle(
        request(),
        &derelict_core::GenData::default_bundle().unwrap(),
    )
    .unwrap();
    let completed = LifecycleResult::completed(Some(5), bundle, events.clone());
    let value = serde_json::to_value(&completed).unwrap();
    assert!(schema_valid("procgen-lifecycle-result-1", &value));
    assert!(LifecycleResult::from_json(&serde_json::to_string(&value).unwrap()).is_ok());
    let mut unknown = value.clone();
    unknown["unexpected"] = true.into();
    assert!(!schema_valid("procgen-lifecycle-result-1", &unknown));
    assert!(LifecycleResult::from_json(&serde_json::to_string(&unknown).unwrap()).is_err());

    for (field, bad) in [
        ("request_id", serde_json::Value::Null),
        ("request_id", 0.into()),
        (
            "request_id",
            serde_json::from_str("9223372036854775808").unwrap(),
        ),
    ] {
        let mut invalid =
            serde_json::to_value(LifecycleResult::accepted(1, events.clone())).unwrap();
        invalid[field] = bad;
        assert!(!schema_valid("procgen-lifecycle-result-1", &invalid));
        assert!(LifecycleResult::from_json(&serde_json::to_string(&invalid).unwrap()).is_err());
    }
    for count in [0, 33] {
        let mut invalid =
            serde_json::to_value(LifecycleResult::accepted(1, events.clone())).unwrap();
        invalid["events"] = serde_json::json!(vec!["admitted"; count]);
        assert!(!schema_valid("procgen-lifecycle-result-1", &invalid));
        assert!(LifecycleResult::from_json(&serde_json::to_string(&invalid).unwrap()).is_err());
    }
}

#[test]
fn capability_limits_and_all_failure_codes_validate_at_both_boundaries() {
    let caps = serde_json::to_value(capabilities()).unwrap();
    assert!(schema_valid("procgen-capabilities-1", &caps));
    for (field, value) in [("max_events", 33), ("max_trace_entries", 4097)] {
        let mut invalid = caps.clone();
        invalid[field] = value.into();
        assert!(!schema_valid("procgen-capabilities-1", &invalid));
        assert!(ProcgenCapabilities::from_json(&serde_json::to_string(&invalid).unwrap()).is_err());
    }
    let mut zero_workers = caps.clone();
    zero_workers["worker_count"] = 0.into();
    assert!(!schema_valid("procgen-capabilities-1", &zero_workers));
    let mut cooperative = caps.clone();
    cooperative["worker_mode"] = "cooperative".into();
    cooperative["worker_count"] = 0.into();
    assert!(schema_valid("procgen-capabilities-1", &cooperative));
    for code in [
        ProcgenFailureCode::InvalidRequest,
        ProcgenFailureCode::UnsupportedSchema,
        ProcgenFailureCode::UnsupportedDomain,
        ProcgenFailureCode::GeneratorContentMismatch,
        ProcgenFailureCode::GenerationFailure,
        ProcgenFailureCode::ValidationFailure,
        ProcgenFailureCode::FallbackFailure,
        ProcgenFailureCode::AdapterFailure,
        ProcgenFailureCode::ManifestFailure,
        ProcgenFailureCode::Capacity,
        ProcgenFailureCode::Overload,
        ProcgenFailureCode::Cancellation,
        ProcgenFailureCode::Timeout,
        ProcgenFailureCode::InternalFailure,
        ProcgenFailureCode::UnknownRequest,
        ProcgenFailureCode::ResultConsumed,
        ProcgenFailureCode::ResultExpired,
        ProcgenFailureCode::Shutdown,
        ProcgenFailureCode::TooLateCancellation,
    ] {
        let failure = ProcgenFailure {
            schema_version: FAILURE_SCHEMA.into(),
            code,
            stage: "lifecycle".into(),
            message: "failure".into(),
            retryable: false,
            fallback_id: None,
        };
        let value = serde_json::to_value(&failure).unwrap();
        assert!(schema_valid("procgen-failure-1", &value));
        assert!(ProcgenFailure::from_json(&serde_json::to_string(&value).unwrap()).is_ok());
    }
}
