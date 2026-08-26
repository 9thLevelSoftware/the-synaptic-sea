use derelict_core::adaptive::{AdaptiveDecisionKind, AdaptiveFallbackReason};
use derelict_core::player_model::{PlayerModelV2, PLAYER_MODEL_SCHEMA_V2};
use derelict_core::site::generate_site;
use derelict_core::site::generate_site_adaptive;
use derelict_core::world::{WorldGenerationRequest, WorldKey, PROCGEN_GENERATOR_VERSION};
use derelict_core::{generate_ship, GenData, GenParams};

fn fixture(seed: u64) -> (WorldGenerationRequest, derelict_core::Ship) {
    let request = WorldGenerationRequest {
        world_seed: seed,
        platform_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: "a".repeat(64),
        site_id: "site:adaptive-test".into(),
        x: 2,
        y: -1,
        archetype_id: "shuttle".into(),
    };
    let key = WorldKey {
        world_seed: seed,
        platform_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: request.content_manifest_hash.clone(),
        site_id: request.site_id.clone(),
        x: request.x,
        y: request.y,
        domain: "site".into(),
        channel: "site.structural".into(),
        sub_index: 0,
    };
    let ship = generate_ship(
        key.seed().unwrap(),
        &GenParams::new("shuttle"),
        &GenData::default_bundle().unwrap(),
    )
    .unwrap();
    (request, ship)
}

fn baseline() -> PlayerModelV2 {
    PlayerModelV2 {
        schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
        signals: Vec::new(),
    }
}

fn extreme() -> PlayerModelV2 {
    PlayerModelV2 {
        schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
        signals: derelict_core::player_model::PlayerSignalKind::ALL
            .into_iter()
            .map(|kind| derelict_core::player_model::PlayerSignal {
                kind,
                value_bp: 10_000,
            })
            .collect(),
    }
}

#[test]
fn adaptive_site_api_returns_ranked_validated_candidate() {
    let (outcome, trace) = (0..128)
        .find_map(|seed| {
            let (request, ship) = fixture(seed);
            generate_site_adaptive(ship, &request, &baseline()).ok()
        })
        .expect("adaptive fixture should produce a valid site");
    assert_eq!(trace.kind, AdaptiveDecisionKind::SiteRanker);
    assert!(trace.fallback.is_none());
    assert_eq!(
        trace.selected_candidate_id.as_deref(),
        Some(outcome.site.mission_graph.mission_id.as_str())
    );
    assert!(trace
        .candidates
        .iter()
        .all(|candidate| !candidate.candidate_id.is_empty()));
    assert_eq!(
        trace.proposal.action,
        derelict_core::adaptive::AdaptiveActionV2::SelectCandidate {
            candidate_id: outcome.site.mission_graph.mission_id.clone()
        }
    );
}

#[test]
fn adaptive_site_empty_trace_uses_explicit_fallback_reason() {
    let trace = derelict_core::adaptive::rank_validated_candidates(
        "site:test",
        AdaptiveDecisionKind::SiteRanker,
        &baseline(),
        &[],
    )
    .unwrap();
    assert_eq!(
        trace.fallback,
        Some(AdaptiveFallbackReason::NoValidatedCandidate)
    );
    assert!(!trace.applied);
}

#[test]
fn adaptive_site_replays_and_legacy_generation_remains_deterministic() {
    let (request, ship) = fixture(0);
    let first = generate_site_adaptive(ship.clone(), &request, &baseline()).unwrap();
    let second = generate_site_adaptive(ship.clone(), &request, &baseline()).unwrap();
    assert_eq!(first, second);
    assert_eq!(
        generate_site(ship.clone(), &request).unwrap(),
        generate_site(ship, &request).unwrap()
    );
}

#[test]
fn player_snapshot_can_select_different_authored_profiles() {
    let mut found = false;
    for seed in 0..128 {
        let (request, ship) = fixture(seed);
        let baseline_result = generate_site_adaptive(ship.clone(), &request, &baseline());
        let extreme_result = generate_site_adaptive(ship, &request, &extreme());
        if let (Ok((base, _)), Ok((hard, _))) = (baseline_result, extreme_result) {
            if base.site.mission_graph.mission_id != hard.site.mission_graph.mission_id {
                found = true;
                break;
            }
        }
    }
    assert!(
        found,
        "fixture corpus should expose player-dependent profile selection"
    );
}
