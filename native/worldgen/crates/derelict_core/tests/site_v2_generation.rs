use derelict_core::site::{
    fallback_return_path, generate_site, validate_site_for_request, PropKind, SITE_RNG_CHANNELS,
};
use derelict_core::world::{WorldGenerationRequest, WorldKey, PROCGEN_GENERATOR_VERSION};
use derelict_core::{generate_ship, GenData, GenParams};
use std::collections::BTreeSet;

fn request(seed: u64, archetype: &str) -> WorldGenerationRequest {
    WorldGenerationRequest {
        world_seed: seed,
        platform_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: "a".repeat(64),
        site_id: "site:test".into(),
        x: 4,
        y: -3,
        archetype_id: archetype.into(),
    }
}

fn ship_for(seed: u64, archetype: &str) -> (WorldGenerationRequest, derelict_core::Ship) {
    let request = request(seed, archetype);
    let key = WorldKey {
        world_seed: request.world_seed,
        platform_version: request.platform_version,
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
        &GenParams::new(archetype),
        &GenData::default_bundle().unwrap(),
    )
    .unwrap();
    (request, ship)
}

fn generate(
    seed: u64,
    archetype: &str,
) -> (
    WorldGenerationRequest,
    derelict_core::site::SiteGenerationOutcome,
) {
    let (request, ship) = ship_for(seed, archetype);
    let outcome = generate_site(ship, &request)
        .unwrap_or_else(|error| panic!("site seed {seed} archetype {archetype}: {error}"));
    (request, outcome)
}

#[test]
fn generated_site_is_complete_deterministic_and_request_bound() {
    let (request, first) = generate(17, "shuttle");
    let (_, second) = generate(17, "shuttle");
    assert_eq!(first, second);
    validate_site_for_request(&first.site, &request).unwrap();
    assert_eq!(
        first.site.ship.seed,
        WorldKey {
            world_seed: request.world_seed,
            platform_version: request.platform_version,
            content_manifest_hash: request.content_manifest_hash.clone(),
            site_id: request.site_id.clone(),
            x: request.x,
            y: request.y,
            domain: "site".into(),
            channel: "site.structural".into(),
            sub_index: 0,
        }
        .seed()
        .unwrap()
    );
    assert_eq!(
        first
            .site
            .functional_props
            .iter()
            .filter(|prop| prop.kind == PropKind::ExtractionConsole)
            .count(),
        1
    );
    assert_eq!(
        fallback_return_path(&first.site),
        first
            .site
            .ship
            .critical_path
            .iter()
            .rev()
            .copied()
            .collect::<Vec<_>>()
    );
    for channel in SITE_RNG_CHANNELS {
        assert!(first
            .trace
            .candidate_decisions
            .iter()
            .any(|decision| decision.starts_with(&format!("channel:{channel}:"))));
    }
}

#[test]
fn deterministic_corpus_exercises_all_authored_templates() {
    let mut missions = BTreeSet::new();
    let mut accepted = 0;
    let mut rejected = 0;
    for seed in 0..192 {
        let (request, ship) = ship_for(seed, "shuttle");
        match generate_site(ship, &request) {
            Ok(outcome) => {
                validate_site_for_request(&outcome.site, &request).unwrap();
                missions.insert(outcome.site.mission_graph.mission_id.clone());
                accepted += 1;
            }
            Err(_) => rejected += 1,
        }
    }
    assert!(accepted >= 100, "accepted={accepted} rejected={rejected}");
    assert!(missions.contains("survey"), "missions={missions:?}");
    assert!(
        missions.contains("key_lock_salvage"),
        "missions={missions:?}"
    );
    assert!(
        missions.contains("repair_recovery"),
        "missions={missions:?}"
    );
}
