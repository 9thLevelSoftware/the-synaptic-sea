use derelict_core::adaptive::*;
use derelict_core::player_model::{
    PlayerModelV2, PlayerSignal, PlayerSignalKind, PLAYER_MODEL_SCHEMA_V2,
};

fn player() -> PlayerModelV2 {
    PlayerModelV2 {
        schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
        signals: PlayerSignalKind::ALL
            .into_iter()
            .map(|kind| PlayerSignal {
                kind,
                value_bp: 5_000,
            })
            .collect(),
    }
}

#[test]
fn classical_ranker_selects_validated_candidate_deterministically() {
    let a = ValidatedCandidateInput::new(
        "site:a",
        CandidateFeatures {
            challenge_bp: 9_000,
            pace_bp: 9_000,
            resource_cost_bp: 9_000,
        },
    )
    .unwrap();
    let b = ValidatedCandidateInput::new(
        "site:b",
        CandidateFeatures {
            challenge_bp: 5_000,
            pace_bp: 5_000,
            resource_cost_bp: 5_000,
        },
    )
    .unwrap();
    let trace = rank_validated_candidates(
        "decision:1",
        AdaptiveDecisionKind::SiteRanker,
        &player(),
        &[b, a],
    )
    .unwrap();
    assert_eq!(
        trace.proposal.action,
        AdaptiveActionV2::SelectCandidate {
            candidate_id: "site:b".into()
        }
    );
    trace.validate().unwrap();
    trace.replay(&player()).unwrap();
}

#[test]
fn empty_ranker_uses_classical_fallback_and_encounter_is_bounded() {
    let trace = rank_validated_candidates(
        "decision:2",
        AdaptiveDecisionKind::WorldRanker,
        &player(),
        &[],
    )
    .unwrap();
    assert_eq!(trace.proposal.action, AdaptiveActionV2::NoOp);
    assert_eq!(
        trace.fallback,
        Some(AdaptiveFallbackReason::NoValidatedCandidate)
    );
    let encounter = direct_encounter("decision:3", "encounter:1", &player()).unwrap();
    assert!(matches!(
        encounter.proposal.action,
        AdaptiveActionV2::AdjustEncounter { .. }
    ));
    encounter.validate().unwrap();
}

#[test]
fn tie_break_and_input_order_are_stable() {
    let a = ValidatedCandidateInput::new(
        "site:a",
        CandidateFeatures {
            challenge_bp: 5_000,
            pace_bp: 5_000,
            resource_cost_bp: 5_000,
        },
    )
    .unwrap();
    let b = ValidatedCandidateInput::new(
        "site:b",
        CandidateFeatures {
            challenge_bp: 5_000,
            pace_bp: 5_000,
            resource_cost_bp: 5_000,
        },
    )
    .unwrap();
    let first = rank_validated_candidates(
        "decision:4",
        AdaptiveDecisionKind::SiteRanker,
        &player(),
        &[b.clone(), a.clone()],
    )
    .unwrap();
    let second = rank_validated_candidates(
        "decision:4",
        AdaptiveDecisionKind::SiteRanker,
        &player(),
        &[a, b],
    )
    .unwrap();
    assert_eq!(first, second);
    assert_eq!(first.selected_candidate_id.as_deref(), Some("site:a"));
    assert!(first
        .proposal
        .rationale_codes
        .contains(&AdaptiveRationaleCode::StableTieBreak));
}

#[test]
fn encounter_uses_all_signals_and_supports_neutral() {
    let neutral = direct_encounter("decision:5", "encounter:1", &player()).unwrap();
    assert!(matches!(
        neutral.proposal.action,
        AdaptiveActionV2::AdjustEncounter {
            pacing_delta_bp: 0,
            ..
        }
    ));
    for kind in PlayerSignalKind::ALL {
        let mut p = player();
        p.signals
            .iter_mut()
            .find(|s| s.kind == kind)
            .unwrap()
            .value_bp = 10_000;
        let trace = direct_encounter("decision:6", "encounter:1", &p).unwrap();
        let expected = match kind {
            PlayerSignalKind::CombatMastery => 2500,
            PlayerSignalKind::DamagePressure | PlayerSignalKind::ResourcePressure => -2500,
            PlayerSignalKind::ObjectivePace => 1250,
        };
        assert!(
            matches!(trace.proposal.action, AdaptiveActionV2::AdjustEncounter { pacing_delta_bp, .. } if pacing_delta_bp == expected)
        );
    }
}

#[test]
fn replay_rejects_every_trace_field_tamper() {
    let a = ValidatedCandidateInput::new(
        "site:a",
        CandidateFeatures {
            challenge_bp: 5_000,
            pace_bp: 5_000,
            resource_cost_bp: 5_000,
        },
    )
    .unwrap();
    let b = ValidatedCandidateInput::new(
        "site:b",
        CandidateFeatures {
            challenge_bp: 7_000,
            pace_bp: 5_000,
            resource_cost_bp: 5_000,
        },
    )
    .unwrap();
    let trace = rank_validated_candidates(
        "decision:7",
        AdaptiveDecisionKind::SiteRanker,
        &player(),
        &[a, b],
    )
    .unwrap();
    trace.replay(&player()).unwrap();
    let mut tampered = trace.clone();
    tampered.decision_id = "INVALID".into();
    assert!(tampered.replay(&player()).is_err());
    let mut tampered = trace.clone();
    tampered.candidates[0].score += 1;
    assert!(tampered.replay(&player()).is_err());
    let mut tampered = trace.clone();
    tampered.candidates[0].features.challenge_bp += 1;
    assert!(tampered.replay(&player()).is_err());
    let mut tampered = trace.clone();
    tampered.candidates.reverse();
    assert!(tampered.replay(&player()).is_err());
    let mut tampered = trace.clone();
    tampered.selected_candidate_id = Some("site:z".into());
    assert!(tampered.replay(&player()).is_err());
}

#[test]
fn standalone_proposal_rejects_non_authored_encounter_delta() {
    let mut proposal = direct_encounter("decision:8", "encounter:1", &player())
        .unwrap()
        .proposal;
    proposal.score = 1;
    proposal.action = AdaptiveActionV2::AdjustEncounter {
        encounter_id: "encounter:1".into(),
        pacing_delta_bp: 1,
    };
    assert!(proposal.validate().is_err());

    proposal.score = 1_250;
    proposal.action = AdaptiveActionV2::AdjustEncounter {
        encounter_id: "encounter:1".into(),
        pacing_delta_bp: 1_250,
    };
    assert!(proposal.validate().is_ok());
}
