use derelict_core::creature::CreatureCatalogue;
use derelict_core::encounter::*;
use derelict_core::player_model::{
    PlayerModelV2, PlayerSignal, PlayerSignalKind, PLAYER_MODEL_SCHEMA_V2,
};
use derelict_core::site::{generate_site, SiteIR};
use derelict_core::world::{WorldGenerationRequest, WorldKey, PROCGEN_GENERATOR_VERSION};
use derelict_core::{generate_ship, GenData, GenParams};

fn fixture(
    seed: u64,
) -> (
    EncounterGenerationContext,
    EncounterCatalogue,
    SiteIR,
    CreatureCatalogue,
) {
    for candidate_seed in seed..seed + 64 {
        let request = WorldGenerationRequest {
            world_seed: candidate_seed,
            platform_version: PROCGEN_GENERATOR_VERSION,
            content_manifest_hash: "a".repeat(64),
            site_id: "site:adaptive-test".into(),
            x: 2,
            y: -1,
            archetype_id: "shuttle".into(),
        };
        let key = WorldKey {
            world_seed: candidate_seed,
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
            &GenParams::new("shuttle"),
            &GenData::default_bundle().unwrap(),
        )
        .unwrap();
        if let Ok(outcome) = generate_site(ship, &request) {
            let context = EncounterGenerationContext {
                request,
                difficulty_id: DifficultyBand::DeepDive,
                player: PlayerModelV2 {
                    schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
                    signals: Vec::new(),
                },
                loot_richness_bp: 10_000,
                threat_cap: 3_000,
                performance_cap: 3_000,
                economy_cap: 2_000,
            };
            return (
                context,
                EncounterCatalogue::bundled().unwrap(),
                outcome.site,
                CreatureCatalogue::bundled().unwrap(),
            );
        }
    }
    panic!("no adaptive encounter fixture");
}

fn with_player(
    mut context: EncounterGenerationContext,
    values: [u16; 4],
) -> EncounterGenerationContext {
    context.player.signals = PlayerSignalKind::ALL
        .into_iter()
        .zip(values)
        .map(|(kind, value_bp)| PlayerSignal { kind, value_bp })
        .collect();
    context
}

#[test]
fn director_trace_is_bound_replayed_and_tamper_evident() {
    let (context, catalogue, site, creatures) = fixture(0);
    let outcome = generate_encounters(&context, &catalogue, &site, &creatures.fallbacks).unwrap();
    assert_eq!(outcome.schema_version, "encounter-output-3");
    assert_eq!(
        outcome.trace.adaptive.decision_id,
        "decision:encounter-director"
    );
    assert_eq!(
        outcome.trace.adaptive.player_values_bp,
        context.player.normalized_values()
    );
    outcome
        .validate(&context, &catalogue, &site, &creatures.fallbacks)
        .unwrap();
    let mut tampered = outcome.clone();
    tampered.trace.adaptive.proposal.score += 1;
    assert!(tampered
        .validate(&context, &catalogue, &site, &creatures.fallbacks)
        .is_err());
    let mut rebound = outcome;
    rebound.composition_id.push('x');
    assert!(rebound
        .validate(&context, &catalogue, &site, &creatures.fallbacks)
        .is_err());
}

#[test]
fn director_factor_is_bounded_monotonic_and_deterministic() {
    let (base, catalogue, site, creatures) = fixture(17);
    let low = generate_encounters(
        &with_player(base.clone(), [0, 10_000, 10_000, 0]),
        &catalogue,
        &site,
        &creatures.fallbacks,
    )
    .unwrap();
    let neutral = generate_encounters(&base, &catalogue, &site, &creatures.fallbacks).unwrap();
    let high = generate_encounters(
        &with_player(base.clone(), [10_000, 0, 0, 10_000]),
        &catalogue,
        &site,
        &creatures.fallbacks,
    )
    .unwrap();
    assert_eq!(low.trace.budgets.player_factor_bp, 7_500);
    assert_eq!(neutral.trace.budgets.player_factor_bp, 10_000);
    assert_eq!(high.trace.budgets.player_factor_bp, 12_500);
    assert!(low.trace.budgets.threat_limit <= neutral.trace.budgets.threat_limit);
    assert!(neutral.trace.budgets.threat_limit <= high.trace.budgets.threat_limit);
    assert_eq!(
        high.trace.budgets.performance_limit,
        neutral.trace.budgets.performance_limit
    );
    assert_eq!(
        high.trace.budgets.economy_limit,
        neutral.trace.budgets.economy_limit
    );
    let repeat = generate_encounters(
        &with_player(base, [10_000, 0, 0, 10_000]),
        &catalogue,
        &site,
        &creatures.fallbacks,
    )
    .unwrap();
    assert_eq!(high, repeat);
}
