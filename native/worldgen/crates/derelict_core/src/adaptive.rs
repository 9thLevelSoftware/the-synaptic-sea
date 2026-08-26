//! Deterministic, bounded classical adaptive decisions.
use crate::player_model::PlayerModelV2;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

pub const ADAPTIVE_PROPOSAL_SCHEMA_V2: &str = "adaptive-proposal-2";
pub const ADAPTIVE_DECISION_TRACE_SCHEMA: &str = "adaptive-decision-trace-1";
pub const CLASSICAL_RULE_VERSION: &str = "adaptive-classical-1";
pub const ENCOUNTER_PACING_DELTAS_BP: [i32; 5] = [-2500, -1250, 0, 1250, 2500];
const MAX_ITEMS: usize = 64;
const MAX_ID: usize = 96;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AdaptiveDecisionKind {
    WorldRanker,
    SiteRanker,
    EncounterDirector,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AdaptiveRationaleCode {
    ValidatedCandidate,
    ChallengeFit,
    PaceFit,
    ResourcePressureFit,
    StableTieBreak,
    AuthoredEnvelope,
    CombatMastery,
    DamagePressure,
    ResourcePressure,
    ObjectivePace,
    NoValidatedCandidate,
    ClassicalFallback,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AdaptiveFallbackReason {
    NoValidatedCandidate,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields, rename_all = "snake_case")]
pub enum AdaptiveActionV2 {
    NoOp,
    SelectCandidate {
        candidate_id: String,
    },
    AdjustEncounter {
        encounter_id: String,
        pacing_delta_bp: i32,
    },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AdaptiveProposalV2 {
    pub schema_version: String,
    pub score: i32,
    pub rationale_codes: Vec<AdaptiveRationaleCode>,
    pub confidence_bp: u16,
    pub rule_model_version: String,
    pub action: AdaptiveActionV2,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CandidateFeatures {
    pub challenge_bp: u16,
    pub pace_bp: u16,
    pub resource_cost_bp: u16,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ValidatedCandidateInput {
    candidate_id: String,
    features: CandidateFeatures,
}
impl ValidatedCandidateInput {
    pub fn new(
        candidate_id: impl Into<String>,
        features: CandidateFeatures,
    ) -> Result<Self, AdaptiveError> {
        let candidate_id = candidate_id.into();
        valid_id(&candidate_id)?;
        validate_features(features)?;
        Ok(Self {
            candidate_id,
            features,
        })
    }
    pub fn candidate_id(&self) -> &str {
        &self.candidate_id
    }
    pub fn features(&self) -> CandidateFeatures {
        self.features
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AdaptiveCandidateRecord {
    pub candidate_id: String,
    pub features: CandidateFeatures,
    pub score: i32,
    pub action: AdaptiveActionV2,
    pub rationale_codes: Vec<AdaptiveRationaleCode>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AdaptiveDecisionTrace {
    pub schema_version: String,
    pub decision_id: String,
    pub kind: AdaptiveDecisionKind,
    pub rule_version: String,
    pub player_values_bp: [u16; 4],
    pub candidates: Vec<AdaptiveCandidateRecord>,
    pub proposal: AdaptiveProposalV2,
    pub selected_candidate_id: Option<String>,
    pub applied: bool,
    pub fallback: Option<AdaptiveFallbackReason>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ClassicalSiteProfile {
    pub id: String,
    pub challenge_bp: u16,
    pub pace_bp: u16,
    pub resource_cost_bp: u16,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ClassicalRules {
    pub schema_version: String,
    pub rule_version: String,
    pub site_profiles: Vec<ClassicalSiteProfile>,
    pub encounter_pacing_deltas_bp: Vec<i32>,
    pub max_pacing_delta_bp: i32,
}
impl ClassicalRules {
    pub fn bundled() -> Result<Self, AdaptiveError> {
        let r: Self = serde_json::from_str(include_str!("../assets/adaptive/classical_v1.json"))
            .map_err(|e| AdaptiveError::Json(e.to_string()))?;
        r.validate()?;
        Ok(r)
    }
    pub fn validate(&self) -> Result<(), AdaptiveError> {
        if self.schema_version != ADAPTIVE_PROPOSAL_SCHEMA_V2
            || self.rule_version != CLASSICAL_RULE_VERSION
            || self.max_pacing_delta_bp != 2500
            || self.encounter_pacing_deltas_bp != ENCOUNTER_PACING_DELTAS_BP
        {
            return Err(AdaptiveError::Invalid("classical_rules"));
        }
        if self.site_profiles.len() != 3
            || self.site_profiles.iter().any(|p| {
                p.id.is_empty()
                    || p.challenge_bp > 10000
                    || p.pace_bp > 10000
                    || p.resource_cost_bp > 10000
            })
        {
            return Err(AdaptiveError::Invalid("site_profiles"));
        }
        let ids: BTreeSet<_> = self.site_profiles.iter().map(|p| p.id.as_str()).collect();
        if ids != BTreeSet::from(["key_lock_salvage", "repair_recovery", "survey"]) {
            return Err(AdaptiveError::Invalid("site_profile_ids"));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum AdaptiveError {
    #[error("invalid adaptive field: {0}")]
    Invalid(&'static str),
    #[error("adaptive JSON parse failed: {0}")]
    Json(String),
}
fn valid_id(value: &str) -> Result<(), AdaptiveError> {
    if value.is_empty()
        || value.len() > MAX_ID
        || !value.bytes().all(|b| {
            b.is_ascii_lowercase() || b.is_ascii_digit() || matches!(b, b':' | b'_' | b'-')
        })
    {
        Err(AdaptiveError::Invalid("identifier"))
    } else {
        Ok(())
    }
}
fn validate_features(f: CandidateFeatures) -> Result<(), AdaptiveError> {
    if f.challenge_bp > 10000 || f.pace_bp > 10000 || f.resource_cost_bp > 10000 {
        Err(AdaptiveError::Invalid("features"))
    } else {
        Ok(())
    }
}
fn fit(actual: u16, target: u16) -> i32 {
    10000 - (i32::from(actual).abs_diff(i32::from(target)) as i32)
}
fn score(features: CandidateFeatures, p: [u16; 4]) -> i32 {
    (fit(features.challenge_bp, p[0])
        + fit(features.pace_bp, p[3])
        + fit(features.resource_cost_bp, p[2]))
        / 3
}
fn confidence(score: i32) -> u16 {
    u16::try_from((5000 + score / 2).clamp(0, 10000)).unwrap_or(0)
}
fn encounter_delta(values: [u16; 4]) -> i32 {
    let utility = i32::from(values[0])
        - 5000
        - (i32::from(values[1]) - 5000) / 2
        - (i32::from(values[2]) - 5000) / 2
        + (i32::from(values[3]) - 5000) / 4;
    let utility = utility.clamp(-2500, 2500);
    ENCOUNTER_PACING_DELTAS_BP
        .into_iter()
        .min_by_key(|delta| ((utility - delta).abs(), *delta))
        .unwrap()
}
fn candidate_rationales(
    f: CandidateFeatures,
    p: [u16; 4],
    tie: bool,
) -> Vec<AdaptiveRationaleCode> {
    let mut r = vec![AdaptiveRationaleCode::ValidatedCandidate];
    if fit(f.challenge_bp, p[0]) >= 9000 {
        r.push(AdaptiveRationaleCode::ChallengeFit)
    }
    if fit(f.pace_bp, p[3]) >= 9000 {
        r.push(AdaptiveRationaleCode::PaceFit)
    }
    if fit(f.resource_cost_bp, p[2]) >= 9000 {
        r.push(AdaptiveRationaleCode::ResourcePressureFit)
    }
    if tie {
        r.push(AdaptiveRationaleCode::StableTieBreak)
    }
    r
}
fn base_trace(
    decision_id: &str,
    kind: AdaptiveDecisionKind,
    player: &PlayerModelV2,
) -> Result<([u16; 4], String), AdaptiveError> {
    valid_id(decision_id)?;
    player
        .validate()
        .map_err(|_| AdaptiveError::Invalid("player"))?;
    if kind == AdaptiveDecisionKind::EncounterDirector {
        return Ok((player.normalized_values(), decision_id.into()));
    }
    Ok((player.normalized_values(), decision_id.into()))
}

pub fn rank_validated_candidates(
    decision_id: impl Into<String>,
    kind: AdaptiveDecisionKind,
    player: &PlayerModelV2,
    inputs: &[ValidatedCandidateInput],
) -> Result<AdaptiveDecisionTrace, AdaptiveError> {
    if kind == AdaptiveDecisionKind::EncounterDirector {
        return Err(AdaptiveError::Invalid("decision_kind"));
    }
    let decision_id = decision_id.into();
    let (values, _) = base_trace(&decision_id, kind, player)?;
    let mut sorted = inputs.iter().collect::<Vec<_>>();
    sorted.sort_by_key(|c| c.candidate_id.as_str());
    if sorted.len() > MAX_ITEMS
        || sorted
            .windows(2)
            .any(|w| w[0].candidate_id == w[1].candidate_id)
    {
        return Err(AdaptiveError::Invalid("candidate_ids"));
    }
    if sorted.is_empty() {
        let proposal = AdaptiveProposalV2 {
            schema_version: ADAPTIVE_PROPOSAL_SCHEMA_V2.into(),
            score: 0,
            rationale_codes: vec![
                AdaptiveRationaleCode::NoValidatedCandidate,
                AdaptiveRationaleCode::ClassicalFallback,
            ],
            confidence_bp: 0,
            rule_model_version: CLASSICAL_RULE_VERSION.into(),
            action: AdaptiveActionV2::NoOp,
        };
        return Ok(AdaptiveDecisionTrace {
            schema_version: ADAPTIVE_DECISION_TRACE_SCHEMA.into(),
            decision_id,
            kind,
            rule_version: CLASSICAL_RULE_VERSION.into(),
            player_values_bp: values,
            candidates: vec![],
            proposal,
            selected_candidate_id: None,
            applied: false,
            fallback: Some(AdaptiveFallbackReason::NoValidatedCandidate),
        });
    }
    let scored: Vec<_> = sorted
        .iter()
        .map(|c| (score(c.features, values), *c))
        .collect();
    let best = scored.iter().map(|x| x.0).max().unwrap();
    let winner = scored
        .iter()
        .filter(|x| x.0 == best)
        .min_by_key(|x| x.1.candidate_id.as_str())
        .unwrap();
    let tie = scored.iter().filter(|x| x.0 == best).count() > 1;
    let candidates = scored
        .iter()
        .map(|(s, c)| AdaptiveCandidateRecord {
            candidate_id: c.candidate_id.clone(),
            features: c.features,
            score: *s,
            action: AdaptiveActionV2::SelectCandidate {
                candidate_id: c.candidate_id.clone(),
            },
            rationale_codes: candidate_rationales(c.features, values, tie && *s == best),
        })
        .collect::<Vec<_>>();
    let proposal = AdaptiveProposalV2 {
        schema_version: ADAPTIVE_PROPOSAL_SCHEMA_V2.into(),
        score: best,
        rationale_codes: candidate_rationales(winner.1.features, values, tie),
        confidence_bp: confidence(best),
        rule_model_version: CLASSICAL_RULE_VERSION.into(),
        action: AdaptiveActionV2::SelectCandidate {
            candidate_id: winner.1.candidate_id.clone(),
        },
    };
    Ok(AdaptiveDecisionTrace {
        schema_version: ADAPTIVE_DECISION_TRACE_SCHEMA.into(),
        decision_id,
        kind,
        rule_version: CLASSICAL_RULE_VERSION.into(),
        player_values_bp: values,
        candidates,
        selected_candidate_id: Some(winner.1.candidate_id.clone()),
        proposal,
        applied: true,
        fallback: None,
    })
}

pub fn direct_encounter(
    decision_id: impl Into<String>,
    encounter_id: impl Into<String>,
    player: &PlayerModelV2,
) -> Result<AdaptiveDecisionTrace, AdaptiveError> {
    let decision_id = decision_id.into();
    let encounter_id = encounter_id.into();
    valid_id(&decision_id)?;
    valid_id(&encounter_id)?;
    let rules = ClassicalRules::bundled()?;
    let values = player.normalized_values();
    player
        .validate()
        .map_err(|_| AdaptiveError::Invalid("player"))?;
    let delta = encounter_delta(values);
    let mut rationale = vec![
        AdaptiveRationaleCode::AuthoredEnvelope,
        AdaptiveRationaleCode::CombatMastery,
        AdaptiveRationaleCode::DamagePressure,
        AdaptiveRationaleCode::ResourcePressure,
        AdaptiveRationaleCode::ObjectivePace,
    ];
    rationale.dedup();
    let proposal = AdaptiveProposalV2 {
        schema_version: ADAPTIVE_PROPOSAL_SCHEMA_V2.into(),
        score: delta,
        rationale_codes: rationale,
        confidence_bp: confidence(delta),
        rule_model_version: rules.rule_version.clone(),
        action: AdaptiveActionV2::AdjustEncounter {
            encounter_id: encounter_id.clone(),
            pacing_delta_bp: delta,
        },
    };
    Ok(AdaptiveDecisionTrace {
        schema_version: ADAPTIVE_DECISION_TRACE_SCHEMA.into(),
        decision_id,
        kind: AdaptiveDecisionKind::EncounterDirector,
        rule_version: rules.rule_version,
        player_values_bp: values,
        candidates: vec![],
        proposal,
        selected_candidate_id: None,
        applied: true,
        fallback: None,
    })
}

impl AdaptiveProposalV2 {
    pub fn from_json(json: &str) -> Result<Self, AdaptiveError> {
        let proposal: Self =
            serde_json::from_str(json).map_err(|e| AdaptiveError::Json(e.to_string()))?;
        proposal.validate()?;
        Ok(proposal)
    }
    pub fn validate(&self) -> Result<(), AdaptiveError> {
        if self.schema_version != ADAPTIVE_PROPOSAL_SCHEMA_V2
            || self.rule_model_version != CLASSICAL_RULE_VERSION
            || self.rationale_codes.is_empty()
            || self.rationale_codes.len() > MAX_ITEMS
            || self.confidence_bp > 10000
            || self.score < -10000
            || self.score > 10000
        {
            return Err(AdaptiveError::Invalid("proposal"));
        }
        match &self.action {
            AdaptiveActionV2::NoOp => {}
            AdaptiveActionV2::SelectCandidate { candidate_id } => valid_id(candidate_id)?,
            AdaptiveActionV2::AdjustEncounter {
                encounter_id,
                pacing_delta_bp,
            } => {
                valid_id(encounter_id)?;
                if self.score != *pacing_delta_bp
                    || !ENCOUNTER_PACING_DELTAS_BP.contains(pacing_delta_bp)
                {
                    return Err(AdaptiveError::Invalid("encounter_pacing_delta"));
                }
            }
        }
        Ok(())
    }
}
impl AdaptiveDecisionTrace {
    pub fn validate(&self) -> Result<(), AdaptiveError> {
        valid_id(&self.decision_id)?;
        if self.schema_version != ADAPTIVE_DECISION_TRACE_SCHEMA
            || self.rule_version != CLASSICAL_RULE_VERSION
            || self.candidates.len() > MAX_ITEMS
            || self.player_values_bp.iter().any(|v| *v > 10000)
        {
            return Err(AdaptiveError::Invalid("trace"));
        }
        self.proposal.validate()?;
        if (self.kind == AdaptiveDecisionKind::EncounterDirector)
            != matches!(
                self.proposal.action,
                AdaptiveActionV2::AdjustEncounter { .. }
            )
        {
            return Err(AdaptiveError::Invalid("kind_action"));
        }
        let mut ids = BTreeSet::new();
        if self.kind == AdaptiveDecisionKind::EncounterDirector && !self.candidates.is_empty() {
            return Err(AdaptiveError::Invalid("encounter_candidates"));
        }
        for c in &self.candidates {
            valid_id(&c.candidate_id)?;
            validate_features(c.features)?;
            if !ids.insert(c.candidate_id.as_str()) {
                return Err(AdaptiveError::Invalid("candidate_ids"));
            }
            if c.score < -10000 || c.score > 10000 {
                return Err(AdaptiveError::Invalid("candidate_score"));
            }
            if c.action
                != (AdaptiveActionV2::SelectCandidate {
                    candidate_id: c.candidate_id.clone(),
                })
            {
                return Err(AdaptiveError::Invalid("candidate_action"));
            }
            if c.rationale_codes.is_empty()
                || c.rationale_codes.len() > MAX_ITEMS
                || c.rationale_codes.windows(2).any(|w| w[0] == w[1])
            {
                return Err(AdaptiveError::Invalid("candidate_rationales"));
            }
            if c.score != score(c.features, self.player_values_bp) {
                return Err(AdaptiveError::Invalid("candidate_score"));
            }
        }
        if self
            .candidates
            .windows(2)
            .any(|w| w[0].candidate_id >= w[1].candidate_id)
        {
            return Err(AdaptiveError::Invalid("candidate_order"));
        }
        if !self.candidates.is_empty() {
            let best = self.candidates.iter().map(|c| c.score).max().unwrap();
            let tie = self.candidates.iter().filter(|c| c.score == best).count() > 1;
            for c in &self.candidates {
                if c.rationale_codes
                    != candidate_rationales(
                        c.features,
                        self.player_values_bp,
                        tie && c.score == best,
                    )
                {
                    return Err(AdaptiveError::Invalid("candidate_rationales"));
                }
            }
            let winner = self
                .candidates
                .iter()
                .filter(|c| c.score == best)
                .min_by_key(|c| c.candidate_id.as_str())
                .unwrap();
            if self.proposal.score != best
                || self.proposal.confidence_bp != confidence(best)
                || self.proposal.rationale_codes
                    != candidate_rationales(winner.features, self.player_values_bp, tie)
            {
                return Err(AdaptiveError::Invalid("proposal_consistency"));
            }
        } else if self.kind != AdaptiveDecisionKind::EncounterDirector
            && (!matches!(self.proposal.action, AdaptiveActionV2::NoOp)
                || self.proposal.score != 0
                || self.proposal.rationale_codes
                    != [
                        AdaptiveRationaleCode::NoValidatedCandidate,
                        AdaptiveRationaleCode::ClassicalFallback,
                    ])
        {
            return Err(AdaptiveError::Invalid("empty_candidate_consistency"));
        }
        if self.kind == AdaptiveDecisionKind::EncounterDirector {
            let expected = encounter_delta(self.player_values_bp);
            if self.proposal.score != expected
                || self.proposal.confidence_bp != confidence(expected)
                || self.proposal.rationale_codes
                    != [
                        AdaptiveRationaleCode::AuthoredEnvelope,
                        AdaptiveRationaleCode::CombatMastery,
                        AdaptiveRationaleCode::DamagePressure,
                        AdaptiveRationaleCode::ResourcePressure,
                        AdaptiveRationaleCode::ObjectivePace,
                    ]
            {
                return Err(AdaptiveError::Invalid("encounter_consistency"));
            }
        }
        match (
            &self.proposal.action,
            &self.selected_candidate_id,
            self.fallback,
            self.applied,
        ) {
            (
                AdaptiveActionV2::NoOp,
                None,
                Some(AdaptiveFallbackReason::NoValidatedCandidate),
                false,
            ) => {}
            (AdaptiveActionV2::SelectCandidate { candidate_id }, Some(selected), None, true)
                if candidate_id == selected
                    && self.candidates.iter().any(|c| c.candidate_id == *selected) => {}
            (
                AdaptiveActionV2::AdjustEncounter {
                    pacing_delta_bp, ..
                },
                None,
                None,
                true,
            ) if *pacing_delta_bp == encounter_delta(self.player_values_bp) => {}
            _ => return Err(AdaptiveError::Invalid("trace_consistency")),
        }
        Ok(())
    }
    pub fn replay(&self, player: &PlayerModelV2) -> Result<(), AdaptiveError> {
        self.validate()?;
        let fresh = match self.kind {
            AdaptiveDecisionKind::EncounterDirector => direct_encounter(
                self.decision_id.clone(),
                match &self.proposal.action {
                    AdaptiveActionV2::AdjustEncounter { encounter_id, .. } => encounter_id.clone(),
                    _ => return Err(AdaptiveError::Invalid("action")),
                },
                player,
            )?,
            k => {
                let inputs = self
                    .candidates
                    .iter()
                    .map(|c| ValidatedCandidateInput::new(c.candidate_id.clone(), c.features))
                    .collect::<Result<Vec<_>, _>>()?;
                rank_validated_candidates(self.decision_id.clone(), k, player, &inputs)?
            }
        };
        if fresh != *self {
            return Err(AdaptiveError::Invalid("replay"));
        }
        Ok(())
    }
}
