use derelict_core::adaptive::AdaptiveDecisionKind;
use derelict_core::manifest::ExportSchemas;
use derelict_core::player_model::{PlayerSignal, PlayerSignalKind, PLAYER_MODEL_SCHEMA_V2};
use derelict_core::procgen::{
    generate_bundle, semantic_hash, Domain, GameplayDecisionDomain, PlayerModel,
    PresentationRequest, ProcgenBundle, ProcgenRequest, SiteRequest, GAMEPLAY_IR_SCHEMA,
    PLAYER_MODEL_SCHEMA, PRESENTATION_IR_SCHEMA, PROCGEN_BUNDLE_SCHEMA, PROCGEN_REQUEST_SCHEMA,
};
use derelict_core::{GenData, PROCGEN_GENERATOR_VERSION};

const CONTENT_HASH: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

fn request(seed: u64) -> ProcgenRequest {
    ProcgenRequest {
        schema_version: PROCGEN_REQUEST_SCHEMA.into(),
        world_seed: seed,
        site: SiteRequest {
            site_id: format!("site:gate3:{seed}"),
            x: 3,
            y: -2,
            archetype_id: "shuttle".into(),
            kit_id: "ship_structural_v0".into(),
            intactness_override_bp: Some(6_000),
            cause_of_loss: None,
            loot_richness_bp: 10_000,
        },
        difficulty_id: "standard".into(),
        player_model: PlayerModel {
            schema_version: PLAYER_MODEL_SCHEMA.into(),
            signals: Vec::new(),
        },
        requested_domains: vec![
            Domain::World,
            Domain::Site,
            Domain::Gameplay,
            Domain::Presentation,
        ],
        generator_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: CONTENT_HASH.into(),
        presentation: PresentationRequest {
            seed: 9,
            locale: "en-US".into(),
        },
    }
}

fn bundle(request: ProcgenRequest) -> ProcgenBundle {
    generate_bundle(request, &GenData::default_bundle().unwrap()).unwrap()
}

fn item_value(bundle: &ProcgenBundle) -> u32 {
    bundle
        .gameplay_ir
        .items
        .iter()
        .map(|item| item.economy_value)
        .sum()
}

#[test]
fn bundle_v4_exports_complete_validated_gameplay_and_presentation_layers() {
    let bundle = bundle(request(42));
    bundle.validate().unwrap();
    assert_eq!(bundle.schema_version, "procgen-bundle-5");
    assert_eq!(bundle.request.schema_version, "procgen-request-2");
    assert_eq!(bundle.request.player_model.schema_version, "player-model-2");
    assert_eq!(bundle.gameplay_ir.schema_version, "gameplay-ir-3");
    assert_eq!(bundle.presentation_ir.schema_version, "presentation-ir-2");
    assert_eq!(bundle.version.export_schemas, ExportSchemas::platform_v5());
    assert_eq!(PROCGEN_BUNDLE_SCHEMA, "procgen-bundle-5");
    assert_eq!(PROCGEN_REQUEST_SCHEMA, "procgen-request-2");
    assert_eq!(PLAYER_MODEL_SCHEMA, PLAYER_MODEL_SCHEMA_V2);
    assert_eq!(GAMEPLAY_IR_SCHEMA, "gameplay-ir-3");
    assert_eq!(PRESENTATION_IR_SCHEMA, "presentation-ir-2");
    assert_eq!(bundle.trace.adaptive_decisions.len(), 3);
    assert_eq!(
        bundle
            .trace
            .adaptive_decisions
            .iter()
            .map(|decision| decision.kind)
            .collect::<Vec<_>>(),
        vec![
            AdaptiveDecisionKind::WorldRanker,
            AdaptiveDecisionKind::SiteRanker,
            AdaptiveDecisionKind::EncounterDirector,
        ]
    );
    for decision in &bundle.trace.adaptive_decisions {
        decision.replay(&bundle.request.player_model).unwrap();
    }

    assert_eq!(bundle.gameplay_ir.creature_blueprints.len(), 3);
    assert!(bundle
        .gameplay_ir
        .creature_blueprints
        .windows(2)
        .all(|pair| pair[0].id < pair[1].id));
    let blueprint_ids: std::collections::BTreeSet<_> = bundle
        .gameplay_ir
        .creature_blueprints
        .iter()
        .map(|blueprint| blueprint.id.as_str())
        .collect();
    assert!(bundle
        .gameplay_ir
        .encounter
        .spawns
        .iter()
        .all(|spawn| blueprint_ids.contains(spawn.blueprint_id.as_str())));
    assert_eq!(
        bundle.gameplay_ir.items.len(),
        bundle.gameplay_ir.drops.len()
    );
    let source_ids: std::collections::BTreeSet<_> = bundle
        .gameplay_ir
        .legacy_slice
        .loot_containers
        .iter()
        .map(|container| container.id.as_str())
        .chain(
            bundle
                .gameplay_ir
                .encounter
                .spawns
                .iter()
                .map(|spawn| spawn.reward_source_id.as_str()),
        )
        .collect();
    assert!(bundle
        .gameplay_ir
        .drops
        .iter()
        .all(|drop| source_ids.contains(drop.source_id.as_str())));
    assert!(!bundle.gameplay_ir.decisions.is_empty());
    assert!(bundle.gameplay_ir.decisions.iter().any(|decision| {
        decision.domain == GameplayDecisionDomain::Creature && decision.accepted
    }));
    assert!(bundle
        .gameplay_ir
        .decisions
        .iter()
        .any(|decision| { decision.domain == GameplayDecisionDomain::Item && decision.accepted }));
    assert!(bundle
        .gameplay_ir
        .decisions
        .iter()
        .all(|decision| decision.score_bp <= 10_000 && !decision.rationale_codes.is_empty()));
    assert!(!bundle.presentation_ir.instructions.is_empty());
    assert!(bundle
        .presentation_ir
        .instructions
        .iter()
        .all(|instruction| !instruction.asset_ids.is_empty()
            && !instruction.adapter_binding_ids.is_empty()));
    assert_eq!(bundle.semantic_hash, semantic_hash(&bundle).unwrap());
}

#[test]
fn identical_request_replays_and_presentation_inputs_cannot_change_mechanics() {
    let first = bundle(request(7));
    let second = bundle(request(7));
    let mut first_replay = first.clone();
    let mut second_replay = second.clone();
    first_replay.metrics.stage_timings_micros.clear();
    first_replay.trace.stage_timings_micros.clear();
    second_replay.metrics.stage_timings_micros.clear();
    second_replay.trace.stage_timings_micros.clear();
    assert_eq!(first_replay, second_replay);

    let mut cosmetic_request = request(7);
    cosmetic_request.presentation.seed = 1_234;
    cosmetic_request.presentation.locale = "fr-FR".into();
    let cosmetic = bundle(cosmetic_request);
    assert_eq!(first.gameplay_ir, cosmetic.gameplay_ir);
    assert_eq!(first.semantic_hash, cosmetic.semantic_hash);
}

#[test]
fn difficulty_is_monotonic_for_identical_world_and_player_snapshot() {
    let mut outputs = Vec::new();
    for difficulty in ["standard", "hardened", "deep_dive"] {
        let mut request = request(31);
        request.difficulty_id = difficulty.into();
        outputs.push(bundle(request));
    }
    assert!(outputs.windows(2).all(|pair| {
        pair[0].gameplay_ir.encounter.trace.budgets.threat_limit
            < pair[1].gameplay_ir.encounter.trace.budgets.threat_limit
    }));
    assert!(outputs.windows(2).all(|pair| {
        pair[0].gameplay_ir.encounter.total_threat <= pair[1].gameplay_ir.encounter.total_threat
    }));
}

#[test]
fn loot_richness_preserves_encounter_composition_and_never_reduces_item_value() {
    let mut poor = request(55);
    poor.site.loot_richness_bp = 0;
    let poor = bundle(poor);
    let mut rich = request(55);
    rich.site.loot_richness_bp = 30_000;
    let rich = bundle(rich);
    let encounter_projection = |bundle: &ProcgenBundle| {
        bundle
            .gameplay_ir
            .encounter
            .spawns
            .iter()
            .map(|spawn| {
                (
                    spawn.room,
                    spawn.cell,
                    spawn.blueprint_id.clone(),
                    spawn.faction_id.clone(),
                )
            })
            .collect::<Vec<_>>()
    };
    assert_eq!(encounter_projection(&poor), encounter_projection(&rich));
    assert!(poor.gameplay_ir.items.len() <= rich.gameplay_ir.items.len());
    assert!(item_value(&poor) <= item_value(&rich));
}

#[test]
fn bounded_player_snapshot_is_the_only_adaptive_mechanical_input() {
    let baseline = bundle(request(81));
    let mut capable_request = request(81);
    capable_request.player_model.signals = vec![
        PlayerSignal {
            kind: PlayerSignalKind::CombatMastery,
            value_bp: 10_000,
        },
        PlayerSignal {
            kind: PlayerSignalKind::DamagePressure,
            value_bp: 0,
        },
        PlayerSignal {
            kind: PlayerSignalKind::ResourcePressure,
            value_bp: 0,
        },
        PlayerSignal {
            kind: PlayerSignalKind::ObjectivePace,
            value_bp: 10_000,
        },
    ];
    let capable = bundle(capable_request);
    assert!(
        baseline.gameplay_ir.encounter.trace.budgets.threat_limit
            < capable.gameplay_ir.encounter.trace.budgets.threat_limit
    );
    assert_ne!(baseline.semantic_hash, capable.semantic_hash);
}

#[test]
fn mixed_contracts_and_nested_output_tampering_fail_closed() {
    let valid = request(101);
    let mut json = serde_json::to_value(&valid).unwrap();
    json["schema_version"] = "procgen-request-1".into();
    assert!(ProcgenRequest::from_json(&json.to_string()).is_err());
    let mut json = serde_json::to_value(&valid).unwrap();
    json["player_model"]["schema_version"] = "player-model-1".into();
    assert!(ProcgenRequest::from_json(&json.to_string()).is_err());
    let mut json = serde_json::to_value(&valid).unwrap();
    json["player_model"]["account_id"] = "forbidden".into();
    assert!(ProcgenRequest::from_json(&json.to_string()).is_err());

    let generated = bundle(valid);
    let mut invalid = generated.clone();
    invalid.gameplay_ir.creature_blueprints[0].ability_id = "missing".into();
    assert!(invalid.validate().is_err());
    let mut invalid = generated.clone();
    invalid.gameplay_ir.decisions[0].score_bp = 10_001;
    assert!(invalid.validate().is_err());
    let mut invalid = generated;
    invalid.presentation_ir.instructions[0].adapter_binding_ids[0] =
        "binding:execute:script".into();
    assert!(invalid.validate().is_err());
}

#[test]
fn deterministic_composite_corpus_validates_all_nested_layers() {
    for seed in 0..64 {
        let bundle = bundle(request(seed));
        bundle.validate().unwrap();
        assert_eq!(bundle.semantic_hash, semantic_hash(&bundle).unwrap());
    }
}
