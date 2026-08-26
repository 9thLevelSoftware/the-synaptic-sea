use derelict_core::creature::{CreatureCatalogue, ThreatRole};
use derelict_core::encounter::*;
use derelict_core::player_model::{
    PlayerModelV2, PlayerSignal, PlayerSignalKind, PLAYER_MODEL_SCHEMA_V2,
};
use derelict_core::site::{generate_site, SiteIR};
use derelict_core::world::{WorldGenerationRequest, WorldKey, PROCGEN_GENERATOR_VERSION};
use derelict_core::{generate_ship, GenData, GenParams};
use serde_json::Value;
use std::collections::BTreeSet;

fn request(seed: u64) -> WorldGenerationRequest {
    WorldGenerationRequest {
        world_seed: seed,
        platform_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: "a".repeat(64),
        site_id: "site:encounter-test".into(),
        x: 4,
        y: -3,
        archetype_id: "shuttle".into(),
    }
}

fn site(seed: u64) -> (WorldGenerationRequest, SiteIR) {
    for candidate_seed in seed..seed.saturating_add(64) {
        let request = request(candidate_seed);
        let structural_key = WorldKey {
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
            structural_key.seed().unwrap(),
            &GenParams::new("shuttle"),
            &GenData::default_bundle().unwrap(),
        )
        .unwrap();
        if let Ok(outcome) = generate_site(ship, &request) {
            return (request, outcome.site);
        }
    }
    panic!("no valid site fixture in seed window starting at {seed}");
}

fn baseline_player() -> PlayerModelV2 {
    PlayerModelV2 {
        schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
        signals: Vec::new(),
    }
}

fn extreme_player(value_bp: u16) -> PlayerModelV2 {
    PlayerModelV2 {
        schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
        signals: PlayerSignalKind::ALL
            .into_iter()
            .map(|kind| PlayerSignal { kind, value_bp })
            .collect(),
    }
}

fn context(
    request: WorldGenerationRequest,
    difficulty_id: DifficultyBand,
    loot_richness_bp: u16,
) -> EncounterGenerationContext {
    EncounterGenerationContext {
        request,
        difficulty_id,
        player: baseline_player(),
        loot_richness_bp,
        threat_cap: 3_000,
        performance_cap: 3_000,
        economy_cap: 2_000,
    }
}

fn content() -> (EncounterCatalogue, CreatureCatalogue) {
    let encounters = EncounterCatalogue::bundled().unwrap();
    let creatures = CreatureCatalogue::bundled().unwrap();
    encounters.validate().unwrap();
    creatures.validate().unwrap();
    (encounters, creatures)
}

fn generate(seed: u64, difficulty: DifficultyBand, loot: u16) -> EncounterGenerationOutcome {
    let (request, site) = site(seed);
    let (catalogue, creatures) = content();
    let context = context(request, difficulty, loot);
    let outcome = generate_encounters(&context, &catalogue, &site, &creatures.fallbacks).unwrap();
    outcome
        .validate(&context, &catalogue, &site, &creatures.fallbacks)
        .unwrap();
    outcome
}

fn mechanical_spawns(
    outcome: &EncounterGenerationOutcome,
) -> Vec<(
    u16,
    derelict_core::structural::plan::Cell,
    String,
    String,
    ThreatRole,
)> {
    outcome
        .spawns
        .iter()
        .map(|spawn| {
            (
                spawn.room,
                spawn.cell,
                spawn.blueprint_id.clone(),
                spawn.faction_id.clone(),
                spawn.threat_role,
            )
        })
        .collect()
}

fn first_nonempty() -> (
    EncounterGenerationContext,
    EncounterCatalogue,
    SiteIR,
    Vec<derelict_core::creature::CreatureBlueprint>,
    EncounterGenerationOutcome,
) {
    let (catalogue, creatures) = content();
    for seed in 0..128 {
        let (request, site) = site(seed);
        let context = context(request, DifficultyBand::DeepDive, 10_000);
        let outcome =
            generate_encounters(&context, &catalogue, &site, &creatures.fallbacks).unwrap();
        if !outcome.spawns.is_empty() {
            return (context, catalogue, site, creatures.fallbacks, outcome);
        }
    }
    panic!("encounter corpus produced no fair nonempty composition");
}

#[test]
fn catalogue_is_closed_canonical_and_fully_cross_referenced() {
    let (catalogue, _) = content();
    assert_eq!(catalogue.schema_version, ENCOUNTER_CATALOGUE_SCHEMA);
    assert!(catalogue.difficulty.windows(2).all(|pair| {
        pair[0].threat_budget < pair[1].threat_budget
            && pair[0].performance_budget < pair[1].performance_budget
            && pair[0].economy_budget < pair[1].economy_budget
            && pair[0].group_cap < pair[1].group_cap
    }));

    let mut value = serde_json::to_value(&catalogue).unwrap();
    value["factions"][0]["unknown_nested"] = Value::from(true);
    assert!(serde_json::from_value::<EncounterCatalogue>(value).is_err());

    let mut invalid = catalogue.clone();
    invalid.factions[1].id = invalid.factions[0].id.clone();
    assert!(invalid.validate().is_err());
    let mut invalid = catalogue.clone();
    invalid.difficulty.swap(0, 1);
    assert!(invalid.validate().is_err());
    let mut invalid = catalogue.clone();
    invalid.difficulty[0].economy_budget = 0;
    assert!(invalid.validate().is_err());
    let mut invalid = catalogue.clone();
    invalid.max_candidates = 129;
    assert!(invalid.validate().is_err());
    let mut invalid = catalogue.clone();
    invalid.reward_values.reverse();
    assert!(invalid.validate().is_err());
    let mut invalid = catalogue;
    invalid.factions[0].ability_ids[0] = "missing".into();
    assert!(invalid.validate().is_err());
}

#[test]
fn generation_is_deterministic_replayable_and_trace_bounded() {
    let first = generate(17, DifficultyBand::DeepDive, 10_000);
    let second = generate(17, DifficultyBand::DeepDive, 10_000);
    assert_eq!(first, second);
    assert_eq!(first.schema_version, ENCOUNTER_OUTPUT_SCHEMA);
    assert_eq!(first.trace.channel_ids, ENCOUNTER_RNG_CHANNELS);
    assert!(first.trace.candidates.len() <= 128);
    assert!(first.trace.decisions.len() <= 128);
    assert!(first
        .trace
        .candidates
        .iter()
        .all(|candidate| candidate.score_bp <= 10_000));
    assert_eq!(
        first.trace.selected_spawn_ids,
        first
            .spawns
            .iter()
            .map(|spawn| spawn.spawn_id.clone())
            .collect::<Vec<_>>()
    );
    assert!(first.trace.decisions.iter().all(|decision| {
        !decision.decision_id.is_empty()
            && !decision.candidate_id.is_empty()
            && decision.score_bp <= 10_000
    }));
}

#[test]
fn spawns_obey_site_occupancy_navigation_visibility_and_reference_constraints() {
    let (context, catalogue, site, blueprints, outcome) = first_nonempty();
    let protected_rooms: BTreeSet<_> = site
        .ship
        .critical_path
        .iter()
        .copied()
        .chain([site.ship.entry_room, site.ship.goal_room])
        .collect();
    let protected_cells: BTreeSet<_> = site
        .functional_props
        .iter()
        .flat_map(|prop| [prop.anchor, prop.approach])
        .collect();
    let navigation_rooms: BTreeSet<_> =
        site.navigation.nodes.iter().map(|node| node.room).collect();
    let creatures = CreatureCatalogue::bundled().unwrap();
    let mut occupied = BTreeSet::new();
    for spawn in &outcome.spawns {
        assert!(!protected_rooms.contains(&spawn.room));
        assert!(!protected_cells.contains(&spawn.cell));
        assert!(navigation_rooms.contains(&spawn.room));
        let blueprint = blueprints
            .iter()
            .find(|blueprint| blueprint.id == spawn.blueprint_id)
            .unwrap();
        assert_eq!(blueprint.ability_id, spawn.ability_id);
        assert_eq!(blueprint.threat_role, spawn.threat_role);
        let footprint = creatures
            .footprints
            .iter()
            .find(|footprint| footprint.id == blueprint.footprint_id)
            .unwrap();
        for offset in &footprint.cells {
            let cell = derelict_core::structural::plan::Cell::new(
                spawn.cell.deck,
                spawn.cell.x + i32::from(offset.x),
                spawn.cell.y + i32::from(offset.y),
            );
            assert!(occupied.insert(cell));
            assert!(!protected_cells.contains(&cell));
        }
    }
    outcome
        .validate(&context, &catalogue, &site, &blueprints)
        .unwrap();
}

#[test]
fn difficulty_and_player_adjustment_preserve_monotonic_threat_envelopes() {
    let (catalogue, creatures) = content();
    for player in [extreme_player(0), baseline_player(), extreme_player(10_000)] {
        for seed in 0..32 {
            let (request, site) = site(seed);
            let mut outputs = Vec::new();
            for difficulty in [
                DifficultyBand::Standard,
                DifficultyBand::Hardened,
                DifficultyBand::DeepDive,
            ] {
                let mut context = context(request.clone(), difficulty, 10_000);
                context.player = player.clone();
                outputs.push(
                    generate_encounters(&context, &catalogue, &site, &creatures.fallbacks).unwrap(),
                );
            }
            assert!(outputs.windows(2).all(|pair| {
                pair[0].trace.budgets.threat_limit < pair[1].trace.budgets.threat_limit
            }));
            assert!(outputs
                .windows(2)
                .all(|pair| pair[0].total_threat <= pair[1].total_threat));
        }
    }
}

#[test]
fn loot_richness_changes_rewards_only_and_never_reduces_value() {
    for seed in 0..48 {
        let poor = generate(seed, DifficultyBand::DeepDive, 0);
        let rich = generate(seed, DifficultyBand::DeepDive, 30_000);
        assert_eq!(mechanical_spawns(&poor), mechanical_spawns(&rich));
        assert!(poor.total_reward_value <= rich.total_reward_value);
        assert!(poor
            .spawns
            .iter()
            .zip(&rich.spawns)
            .all(|(left, right)| left.reward_value <= right.reward_value));
    }
}

#[test]
fn all_authored_and_caller_caps_are_enforced() {
    let (context, catalogue, site, blueprints, outcome) = first_nonempty();
    let budget = catalogue
        .difficulty
        .iter()
        .find(|budget| budget.id == context.difficulty_id)
        .unwrap();
    assert!(outcome.total_threat <= context.threat_cap);
    assert!(outcome.total_threat <= outcome.trace.budgets.threat_limit);
    assert!(outcome.total_performance <= context.performance_cap.min(budget.performance_budget));
    assert!(outcome.total_reward_value <= context.economy_cap);
    assert!(outcome.total_reward_value <= outcome.trace.budgets.economy_limit);
    assert!(outcome.spawns.len() <= usize::from(budget.group_cap));
    for blueprint in &blueprints {
        assert!(
            outcome
                .spawns
                .iter()
                .filter(|spawn| spawn.blueprint_id == blueprint.id)
                .count()
                <= usize::from(blueprint.instance_cap)
        );
    }
    outcome
        .validate(&context, &catalogue, &site, &blueprints)
        .unwrap();
}

#[test]
fn safe_empty_fallback_is_complete_and_validated() {
    let (request, site) = site(9);
    let (catalogue, creatures) = content();
    let mut context = context(request, DifficultyBand::DeepDive, 30_000);
    context.threat_cap = 1;
    let outcome = generate_encounters(&context, &catalogue, &site, &creatures.fallbacks).unwrap();
    assert!(outcome.spawns.is_empty());
    assert_eq!(outcome.total_threat, 0);
    assert_eq!(outcome.total_performance, 0);
    assert_eq!(outcome.total_reward_value, 0);
    assert_eq!(
        outcome.trace.fallback.as_deref(),
        Some(catalogue.safe_empty_fallback_id.as_str())
    );
    outcome
        .validate(&context, &catalogue, &site, &creatures.fallbacks)
        .unwrap();
}

#[test]
fn independent_validator_rejects_output_and_trace_tampering() {
    let (context, catalogue, site, blueprints, outcome) = first_nonempty();

    let mut invalid = outcome.clone();
    invalid.total_threat = invalid.total_threat.saturating_add(1);
    assert!(invalid
        .validate(&context, &catalogue, &site, &blueprints)
        .is_err());

    let mut invalid = outcome.clone();
    invalid.spawns[0].blueprint_id = "missing".into();
    assert!(invalid
        .validate(&context, &catalogue, &site, &blueprints)
        .is_err());

    let mut invalid = outcome.clone();
    invalid.trace.decisions[0].score_bp = 10_001;
    assert!(invalid
        .validate(&context, &catalogue, &site, &blueprints)
        .is_err());

    let mut invalid = outcome;
    invalid.trace.selected_spawn_ids.clear();
    assert!(invalid
        .validate(&context, &catalogue, &site, &blueprints)
        .is_err());
}

#[test]
fn invalid_context_and_navigation_fail_closed() {
    let (request, mut site) = site(5);
    let (catalogue, creatures) = content();
    let mut context = context(request, DifficultyBand::Standard, 0);
    context.request.content_manifest_hash = "A".repeat(64);
    assert!(generate_encounters(&context, &catalogue, &site, &creatures.fallbacks).is_err());

    context.request.content_manifest_hash = "a".repeat(64);
    site.navigation.edges.clear();
    assert!(generate_encounters(&context, &catalogue, &site, &creatures.fallbacks).is_err());
}

#[test]
fn fixed_point_combat_simulation_is_closed_bounded_and_deterministic() {
    let request = CombatSimulationRequest {
        schema_version: COMBAT_SIMULATION_REQUEST_SCHEMA.into(),
        encounter_threat: 2_400,
        player_power_bp: 7_500,
        player_guard: 2_000,
        max_rounds: 64,
    };
    let first = simulate_fixed_point(&request).unwrap();
    let second = simulate_fixed_point(&request).unwrap();
    assert_eq!(first, second);
    assert_eq!(first.schema_version, COMBAT_SIMULATION_RESULT_SCHEMA);
    assert!(first.rounds_simulated <= request.max_rounds);
    assert!(first.remaining_threat <= request.encounter_threat);
    assert!(first.remaining_player_guard <= request.player_guard);

    let mut invalid = request.clone();
    invalid.player_power_bp = 10_001;
    assert!(simulate_fixed_point(&invalid).is_err());
    let mut invalid = request;
    invalid.max_rounds = 129;
    assert!(simulate_fixed_point(&invalid).is_err());
}

#[test]
fn adversarial_seed_sweep_exports_only_valid_or_safe_empty_compositions() {
    let (catalogue, creatures) = content();
    let mut nonempty = 0usize;
    for seed in 0..192 {
        let (request, site) = site(seed);
        for difficulty in [
            DifficultyBand::Standard,
            DifficultyBand::Hardened,
            DifficultyBand::DeepDive,
        ] {
            let context = context(request.clone(), difficulty, 10_000);
            let outcome =
                generate_encounters(&context, &catalogue, &site, &creatures.fallbacks).unwrap();
            outcome
                .validate(&context, &catalogue, &site, &creatures.fallbacks)
                .unwrap();
            if outcome.spawns.is_empty() {
                assert_eq!(
                    outcome.trace.fallback.as_deref(),
                    Some(catalogue.safe_empty_fallback_id.as_str())
                );
            } else {
                nonempty += 1;
                assert!(outcome.trace.fallback.is_none());
            }
        }
    }
    assert!(nonempty > 0, "all adversarial cases fell back safe-empty");
}
