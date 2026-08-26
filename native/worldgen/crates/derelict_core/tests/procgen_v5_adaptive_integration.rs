use derelict_core::adaptive::{AdaptiveActionV2, AdaptiveDecisionKind};
use derelict_core::manifest::ExportSchemas;
use derelict_core::model::CauseOfLoss;
use derelict_core::player_model::{PlayerSignal, PlayerSignalKind, PLAYER_MODEL_SCHEMA_V2};
use derelict_core::procgen::{
    generate_bundle, Domain, PlayerModel, PresentationRequest, ProcgenBundle, ProcgenFailureCode,
    ProcgenRequest, SiteRequest, PROCGEN_BUNDLE_SCHEMA,
};
use derelict_core::{GenData, PROCGEN_GENERATOR_VERSION};

const CONTENT_HASH: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

fn request(seed: u64) -> ProcgenRequest {
    ProcgenRequest {
        schema_version: "procgen-request-2".into(),
        world_seed: seed,
        site: SiteRequest {
            site_id: format!("site:gate4:{seed}"),
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
            schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
            signals: PlayerSignalKind::ALL
                .into_iter()
                .map(|kind| PlayerSignal {
                    kind,
                    value_bp: 5_000,
                })
                .collect(),
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

#[test]
fn extraction_failures_are_typed_replayable_and_preserve_structural_v2() {
    // Gate 6 found these exact requests while scaling the composite campaign.
    // Repairing either would alter the structural-v2 byte contract. Until an
    // explicit structural-v3 migration, the safe result is a stable typed
    // failure and no partially valid SiteIR.
    let cases = [
        (194, 3_311, -4_806, None, None),
        (
            230,
            3_923,
            -4_770,
            Some(9_500),
            Some(CauseOfLoss::ReactorBreach),
        ),
    ];
    let data = GenData::default_bundle().unwrap();
    for (case, seed, x, intactness, cause) in cases {
        let mut regression = request(seed);
        regression.site = SiteRequest {
            site_id: format!("campaign-site-{case}"),
            x,
            y: -5_000,
            archetype_id: "freighter".into(),
            kit_id: "default".into(),
            intactness_override_bp: intactness,
            cause_of_loss: cause,
            loot_richness_bp: 10_000,
        };
        regression.player_model.signals.clear();
        regression.presentation.seed = case ^ 0x55aa;

        let first = generate_bundle(regression.clone(), &data).unwrap_err();
        let replay = generate_bundle(regression, &data).unwrap_err();
        first.validate().unwrap();
        assert_eq!(first, replay, "case={case}");
        assert_eq!(first.code, ProcgenFailureCode::FallbackFailure);
        assert_eq!(first.stage, "site");
        assert!(!first.retryable);
        assert_eq!(first.fallback_id.as_deref(), Some("authored-safe-return"));
    }
}

#[test]
fn exhausted_structural_retries_return_a_replayable_fail_closed_result() {
    // Gate 6's composite campaign found this exact request. The structural
    // compiler exhausts its bounded placement retries, so the public contract
    // must expose a deterministic typed failure instead of partial content.
    let mut regression = request(6_269);
    regression.site = SiteRequest {
        site_id: "campaign-site-368".into(),
        x: -4_632,
        y: -5_000,
        archetype_id: "shuttle".into(),
        kit_id: "default".into(),
        intactness_override_bp: None,
        cause_of_loss: None,
        loot_richness_bp: 10_000,
    };
    regression.player_model.signals.clear();
    regression.presentation.seed = 368 ^ 0x55aa;

    let data = GenData::default_bundle().unwrap();
    let first = generate_bundle(regression.clone(), &data).unwrap_err();
    let replay = generate_bundle(regression, &data).unwrap_err();

    first.validate().unwrap();
    assert_eq!(first, replay);
    assert_eq!(first.code, ProcgenFailureCode::GenerationFailure);
    assert_eq!(first.stage, "generation");
    assert!(first.retryable);
    assert_eq!(first.fallback_id, None);
}

#[test]
fn v5_bundle_contains_three_ordered_replayable_adaptive_decisions() {
    let bundle = bundle(request(42));
    bundle.validate().unwrap();
    assert_eq!(bundle.schema_version, "procgen-bundle-5");
    assert_eq!(bundle.gameplay_ir.schema_version, "gameplay-ir-3");
    assert_eq!(bundle.trace.schema_version, "generation-trace-4");
    assert_eq!(bundle.version.export_schemas, ExportSchemas::platform_v5());
    assert_eq!(PROCGEN_BUNDLE_SCHEMA, "procgen-bundle-5");
    assert_eq!(bundle.trace.adaptive_decisions.len(), 3);
    assert_eq!(
        bundle
            .trace
            .adaptive_decisions
            .iter()
            .map(|d| d.kind)
            .collect::<Vec<_>>(),
        vec![
            AdaptiveDecisionKind::WorldRanker,
            AdaptiveDecisionKind::SiteRanker,
            AdaptiveDecisionKind::EncounterDirector
        ]
    );
    for decision in &bundle.trace.adaptive_decisions {
        decision.replay(&bundle.request.player_model).unwrap();
    }
    assert_eq!(
        bundle.trace.adaptive_decisions[0]
            .selected_candidate_id
            .as_deref(),
        Some(bundle.world_ir.archetype_id.as_str())
    );
    assert_eq!(
        bundle.trace.adaptive_decisions[1]
            .selected_candidate_id
            .as_deref(),
        Some(bundle.site_ir.mission_graph.mission_id.as_str())
    );
    assert!(matches!(
        bundle.trace.adaptive_decisions[2].proposal.action,
        AdaptiveActionV2::AdjustEncounter { .. }
    ));
}

#[test]
fn adaptive_bundle_is_semantically_deterministic_and_presentation_independent() {
    let first = bundle(request(7));
    let second = bundle(request(7));
    assert_eq!(first.semantic_hash, second.semantic_hash);
    assert_eq!(first.world_ir, second.world_ir);
    assert_eq!(first.site_ir, second.site_ir);
    assert_eq!(first.gameplay_ir, second.gameplay_ir);
    assert_eq!(
        first.trace.adaptive_decisions,
        second.trace.adaptive_decisions
    );
    let mut cosmetic = request(7);
    cosmetic.presentation = PresentationRequest {
        seed: 999,
        locale: "fr-FR".into(),
    };
    let changed = bundle(cosmetic);
    assert_eq!(first.world_ir, changed.world_ir);
    assert_eq!(first.site_ir, changed.site_ir);
    assert_eq!(first.gameplay_ir, changed.gameplay_ir);
    assert_eq!(
        first.trace.adaptive_decisions,
        changed.trace.adaptive_decisions
    );
}

#[test]
fn adaptive_bundle_tampering_fails_closed() {
    let bundle = bundle(request(19));
    for mutation in [
        "candidate_score",
        "proposal",
        "player_inputs",
        "selected_id",
        "decision_order",
        "encounter_pacing",
    ] {
        let mut value = serde_json::to_value(&bundle).unwrap();
        let decisions = value["trace"]["adaptive_decisions"].as_array_mut().unwrap();
        match mutation {
            "candidate_score" => decisions[0]["candidates"][0]["score"] = 1.into(),
            "proposal" => decisions[1]["proposal"]["score"] = 1.into(),
            "player_inputs" => decisions[0]["player_values_bp"][0] = 9999.into(),
            "selected_id" => decisions[1]["selected_candidate_id"] = "site:tampered".into(),
            "decision_order" => decisions.reverse(),
            "encounter_pacing" => {
                decisions[2]["proposal"]["action"]["adjust_encounter"]["pacing_delta_bp"] =
                    2500.into()
            }
            _ => unreachable!(),
        }
        assert!(
            ProcgenBundle::from_json(&serde_json::to_string(&value).unwrap()).is_err(),
            "tamper {mutation} accepted"
        );
    }
    let mut unknown = serde_json::to_value(&bundle).unwrap();
    unknown["trace"]["adaptive_decisions"][0]["unknown"] = true.into();
    assert!(ProcgenBundle::from_json(&serde_json::to_string(&unknown).unwrap()).is_err());
}

#[test]
fn difficulty_and_bounded_player_snapshot_preserve_valid_adaptive_outcomes() {
    let baseline = bundle(request(23));
    let mut pressured_request = request(23);
    pressured_request.difficulty_id = "hardened".into();
    for signal in &mut pressured_request.player_model.signals {
        signal.value_bp = match signal.kind {
            PlayerSignalKind::CombatMastery | PlayerSignalKind::ObjectivePace => 10_000,
            PlayerSignalKind::DamagePressure | PlayerSignalKind::ResourcePressure => 0,
        };
    }
    let pressured = bundle(pressured_request);
    baseline.validate().unwrap();
    pressured.validate().unwrap();
    let base_threat = baseline.gameplay_ir.encounter.total_threat;
    let pressured_threat = pressured.gameplay_ir.encounter.total_threat;
    assert!(pressured_threat >= base_threat);
}
