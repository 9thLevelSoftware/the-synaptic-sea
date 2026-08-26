use super::generator::{legacy_request, runtime_capabilities, runtime_manifest, serialize_json};
use derelict_core::lifecycle::AdapterKind;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};

#[test]
fn compiled_identity_constructs_valid_manifest_and_exact_capabilities() {
    let manifest = runtime_manifest().expect("compiled manifest");
    assert_eq!(manifest.generator_version, 3);
    assert_eq!(
        manifest.adapter_schemas,
        derelict_core::lifecycle::AdapterSchemas::platform_v5()
    );
    assert_eq!(
        manifest.export_schemas,
        derelict_core::manifest::ExportSchemas::platform_v5()
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
    assert_eq!(request.schema_version, "procgen-request-2");
    assert_eq!(request.generator_version, 3);
    assert_eq!(request.site.site_id, "legacy-site");
    assert_eq!(request.site.kit_id, "ship_structural_v0");
    assert_eq!(request.difficulty_id, "standard");
    assert_eq!(request.presentation.locale, "en-US");
    assert_eq!(request.player_model.schema_version, "player-model-2");
    assert!(!request.content_manifest_hash.is_empty());
    assert!(request.validate().is_ok());

    let bundle = derelict_core::procgen::generate_bundle(
        request,
        &derelict_core::GenData::default_bundle().unwrap(),
    )
    .unwrap();
    assert_eq!(bundle.version.generator_version, 3);
    assert_eq!(bundle.site_ir.ship.generator_version, 2);
    assert_eq!(bundle.site_ir.ship.seed, bundle.world_ir.site_seed);
    assert_eq!(bundle.trace.adaptive_decisions.len(), 3);
    assert_eq!(
        bundle
            .trace
            .adaptive_decisions
            .iter()
            .map(|decision| decision.kind)
            .collect::<Vec<_>>(),
        vec![
            derelict_core::adaptive::AdaptiveDecisionKind::WorldRanker,
            derelict_core::adaptive::AdaptiveDecisionKind::SiteRanker,
            derelict_core::adaptive::AdaptiveDecisionKind::EncounterDirector,
        ]
    );
}

#[test]
fn legacy_request_with_damage_sealed_portal_uses_complete_safe_fallback() {
    let request = legacy_request(12, &derelict_core::model::GenParams::new("frigate"), "");
    let bundle = derelict_core::procgen::generate_bundle(
        request,
        &derelict_core::GenData::default_bundle().unwrap(),
    )
    .expect("valid legacy request must not fail when authored fallback sees a structural lock");

    assert!(bundle.validate().is_ok());
    assert_eq!(
        bundle.trace.fallback.as_deref(),
        Some("site:authored-safe-return")
    );
    assert_eq!(
        bundle.site_ir.mission_graph.mission_id,
        "authored-safe-return"
    );
    assert!(bundle
        .site_ir
        .ship
        .topology
        .portals
        .iter()
        .all(|portal| portal.state != derelict_core::structural::plan::EdgeKind::Locked));
    assert!(bundle.site_ir.mission_graph.gates.iter().all(|gate| {
        bundle
            .site_ir
            .navigation
            .edges
            .iter()
            .filter(|edge| edge.gate_id.as_deref() == Some(gate.id.as_str()))
            .count()
            == 2
    }));
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
    let bundle = derelict_core::procgen::generate_bundle(
        legacy_request(42, &derelict_core::model::GenParams::new("shuttle"), ""),
        &derelict_core::GenData::default_bundle().unwrap(),
    )
    .unwrap();
    let completed = derelict_core::lifecycle::LifecycleResult::completed(
        None,
        bundle.clone(),
        vec![derelict_core::lifecycle::LifecycleEvent::Completed],
    );
    let conversion_failed = super::generator::export_result_json(
        completed,
        |_| Err(derelict_core::procgen::ProcgenError::InvalidRequest("test")),
        serde_json::to_string,
    );
    assert_eq!(
        derelict_core::lifecycle::LifecycleResult::from_json(&conversion_failed)
            .unwrap()
            .failure
            .unwrap()
            .code,
        derelict_core::procgen::ProcgenFailureCode::AdapterFailure
    );
    let completed = derelict_core::lifecycle::LifecycleResult::completed(
        None,
        bundle,
        vec![derelict_core::lifecycle::LifecycleEvent::Completed],
    );
    let serialization_failed = super::generator::export_result_json(
        completed,
        derelict_core::procgen::migration_layout,
        |_| Err(serde_json::Error::io(std::io::Error::other("test"))),
    );
    assert_eq!(
        derelict_core::lifecycle::LifecycleResult::from_json(&serialization_failed)
            .unwrap()
            .failure
            .unwrap()
            .code,
        derelict_core::procgen::ProcgenFailureCode::AdapterFailure
    );
    let success = super::generator::export_result_json(
        derelict_core::lifecycle::LifecycleResult::completed(
            None,
            derelict_core::procgen::generate_bundle(
                legacy_request(904, &derelict_core::model::GenParams::new("shuttle"), ""),
                &derelict_core::GenData::default_bundle().unwrap(),
            )
            .unwrap(),
            vec![derelict_core::lifecycle::LifecycleEvent::Completed],
        ),
        derelict_core::procgen::migration_gameplay,
        serde_json::to_string,
    );
    assert!(!success.is_empty());
}

#[test]
fn runtime_access_reuses_identical_service() {
    let first = super::generator::runtime().unwrap();
    let second = super::generator::runtime().unwrap();
    assert!(std::sync::Arc::ptr_eq(&first.service, &second.service));
}

#[test]
fn lifecycle_string_helpers_have_typed_shapes_and_shared_runtime() {
    // Seed 42 is a checked connected structural fixture. A structurally legal
    // fracture may intentionally fail the stricter SiteIR reachability gate.
    let request = legacy_request(42, &derelict_core::model::GenParams::new("shuttle"), "");
    let request_json = serde_json::to_string(&request).unwrap();
    let sync = derelict_core::lifecycle::LifecycleResult::from_json(&super::generator::sync_json(
        &request_json,
    ))
    .unwrap();
    assert_eq!(
        sync.status,
        derelict_core::lifecycle::LifecycleStatus::Completed,
        "sync failure: {:?}",
        sync.failure
    );
    assert!(sync.request_id.is_none() && sync.bundle.is_some() && sync.failure.is_none());
    let accepted = derelict_core::lifecycle::LifecycleResult::from_json(
        &super::generator::submit_json(&request_json),
    )
    .unwrap();
    assert_eq!(
        accepted.status,
        derelict_core::lifecycle::LifecycleStatus::Accepted
    );
    let id = accepted.request_id.unwrap();
    let runtime = super::generator::runtime().unwrap();
    assert!(runtime
        .service
        .wait_terminal_for_test(id, std::time::Duration::from_secs(2)));
    let completed =
        derelict_core::lifecycle::LifecycleResult::from_json(&super::generator::poll_json(id))
            .unwrap();
    assert_eq!(
        completed.status,
        derelict_core::lifecycle::LifecycleStatus::Completed
    );
    let consumed =
        derelict_core::lifecycle::LifecycleResult::from_json(&super::generator::poll_json(id))
            .unwrap();
    assert_eq!(
        consumed.failure.unwrap().code,
        derelict_core::procgen::ProcgenFailureCode::ResultConsumed
    );
    let unknown =
        derelict_core::lifecycle::LifecycleResult::from_json(&super::generator::cancel_json(0))
            .unwrap();
    assert_eq!(
        unknown.failure.unwrap().code,
        derelict_core::procgen::ProcgenFailureCode::UnknownRequest
    );
    assert!(derelict_core::lifecycle::ProcgenCapabilities::from_json(
        &super::generator::capabilities_json()
    )
    .is_ok());
    assert!(derelict_core::lifecycle::GeneratorManifest::from_json(
        &super::generator::manifest_json()
    )
    .is_ok());
    let second = super::generator::runtime().unwrap();
    assert!(Arc::ptr_eq(&runtime.service, &second.service));
}

#[test]
fn legacy_bundle_converts_both_documents_after_one_generation() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let content_manifest_hash = runtime_manifest()
        .expect("compiled manifest")
        .content_manifest_hash;
    let count = Arc::new(AtomicUsize::new(0));
    let calls = count.clone();
    let data_for_generator = data.clone();
    let service = super::service::Service::new(
        super::service::Limits::default(),
        Arc::new(super::service::SystemClock::default()),
        content_manifest_hash,
        Arc::new(move |request| {
            calls.fetch_add(1, Ordering::SeqCst);
            derelict_core::procgen::generate_bundle(request, &data_for_generator)
        }),
    );
    let request = legacy_request(902, &derelict_core::model::GenParams::new("shuttle"), "");
    let id = service.submit(request).request_id.unwrap();
    assert!(service.wait_terminal_for_test(id, std::time::Duration::from_secs(2)));
    let bundle = service.poll(id).bundle.unwrap();
    let layout = derelict_core::procgen::migration_layout(&bundle).unwrap();
    let gameplay = derelict_core::procgen::migration_gameplay(&bundle).unwrap();
    assert!(!layout.to_string().is_empty() && !gameplay.to_string().is_empty());
    assert_eq!(count.load(Ordering::SeqCst), 1);
    service.shutdown();
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
