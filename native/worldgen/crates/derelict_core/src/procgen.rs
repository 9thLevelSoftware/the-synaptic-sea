//! Versioned contracts and the single-pass generation bundle.
use crate::adaptive::{
    rank_validated_candidates, AdaptiveDecisionKind, AdaptiveDecisionTrace, CandidateFeatures,
    ValidatedCandidateInput,
};
pub use crate::adaptive::{
    AdaptiveActionV2 as AdaptiveAction, AdaptiveProposalV2 as AdaptiveProposal,
};
use crate::creature::{
    CreatureBlueprint, CreatureBlueprintSetOutcome, CreatureCatalogue, CreatureGenerationContext,
};
use crate::encounter::{
    DifficultyBand, EncounterCatalogue, EncounterGenerationContext, EncounterGenerationOutcome,
    EncounterRationale,
};
use crate::item_generation::{
    DropBinding, ItemBlueprint, ItemCatalogue, ItemGenerationContext, ItemGenerationOutcome,
    SourceBinding, SourceKind, MAX_ITEMS,
};
use crate::manifest::ExportSchemas;
use crate::model::{CauseOfLoss, Ship, GENERATOR_VERSION};
pub use crate::player_model::PlayerModelV2 as PlayerModel;
use crate::presentation::{
    PresentationCatalogue, PresentationContext, PresentationOutput, PresentationSubject,
    SubjectKind,
};
pub use crate::site::SiteIR;
pub use crate::world::WorldIR;
use crate::world::{WorldGenerationRequest, WorldRules};
use crate::{generate_ship_timed, GenData, GenParams};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::collections::BTreeSet;
use web_time::Instant;

pub const PROCGEN_REQUEST_SCHEMA: &str = crate::manifest::PROCGEN_REQUEST_SCHEMA_V2;
pub const PROCGEN_BUNDLE_SCHEMA: &str = crate::manifest::PROCGEN_BUNDLE_SCHEMA_V5;
pub const WORLD_IR_SCHEMA: &str = crate::manifest::WORLD_IR_SCHEMA_V2;
pub const SITE_IR_SCHEMA: &str = crate::manifest::SITE_IR_SCHEMA;
pub const GAMEPLAY_IR_SCHEMA: &str = crate::manifest::GAMEPLAY_IR_SCHEMA_V3;
pub const PRESENTATION_IR_SCHEMA: &str = crate::manifest::PRESENTATION_IR_SCHEMA_V2;
pub const GENERATION_TRACE_SCHEMA: &str = crate::manifest::GENERATION_TRACE_SCHEMA;
pub const ADAPTIVE_PROPOSAL_SCHEMA: &str = crate::manifest::ADAPTIVE_PROPOSAL_SCHEMA;
pub const PLAYER_MODEL_SCHEMA: &str = crate::player_model::PLAYER_MODEL_SCHEMA_V2;
pub const FAILURE_SCHEMA: &str = "procgen-failure-1";
pub const GENERATION_METRICS_SCHEMA: &str = "generation-metrics-1";
pub const RNG_CHANNELS: [&str; 37] = [
    "world.archetype",
    "world.biome",
    "world.hazard",
    "world.resource",
    "world.landmark",
    "world.route_cost",
    "site.structural",
    "site.mission_template",
    "site.gate_order",
    "site.functional_props",
    "site.spatial_annotations",
    "meta",
    "hull",
    "template",
    "topology",
    "residual_fill",
    "door",
    "furnish",
    "story",
    "intact",
    "breach",
    "scorch",
    "seal",
    "bodies",
    "fracture",
    "debris",
    "loot",
    "gameplay.creature_blueprint",
    "gameplay.creature_ability",
    "gameplay.creature_material",
    "gameplay.encounter_candidate",
    "gameplay.encounter_faction",
    "gameplay.encounter_reward",
    "gameplay.encounter_selection",
    "gameplay.item_family",
    "gameplay.item_affix",
    "presentation.asset_assembly",
];

#[derive(
    Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(rename_all = "lowercase")]
pub enum Domain {
    World,
    Site,
    Gameplay,
    Presentation,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SiteRequest {
    pub site_id: String,
    pub x: i32,
    pub y: i32,
    pub archetype_id: String,
    pub kit_id: String,
    pub intactness_override_bp: Option<u16>,
    pub cause_of_loss: Option<CauseOfLoss>,
    pub loot_richness_bp: u16,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PresentationRequest {
    pub seed: u64,
    pub locale: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ProcgenRequest {
    pub schema_version: String,
    pub world_seed: u64,
    pub site: SiteRequest,
    pub difficulty_id: String,
    pub player_model: PlayerModel,
    pub requested_domains: Vec<Domain>,
    pub generator_version: u32,
    pub content_manifest_hash: String,
    pub presentation: PresentationRequest,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct VersionEnvelope {
    pub generator_version: u32,
    pub content_manifest_hash: String,
    pub export_schemas: ExportSchemas,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GameplayIR {
    pub schema_version: String,
    pub legacy_slice: GameplaySlice,
    pub creature_blueprints: Vec<CreatureBlueprint>,
    pub encounter: EncounterGenerationOutcome,
    pub items: Vec<ItemBlueprint>,
    pub drops: Vec<DropBinding>,
    pub decisions: Vec<GameplayDecisionRecord>,
}

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema,
)]
#[serde(rename_all = "snake_case")]
pub enum GameplayDecisionDomain {
    Creature,
    Encounter,
    Item,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(
    tag = "code",
    content = "detail",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum GameplayRationaleCode {
    CreatureValidated,
    CreatureIncompatible,
    CreatureSelected,
    ItemAuthoredCompatible,
    ItemNoCompatibleAffix,
    ItemArithmeticOverflow,
    ItemIncompatible,
    ItemEconomyCap,
    ItemAuthoredBaseline,
    ItemSafeEmpty,
    Encounter(EncounterRationale),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GameplayDecisionRecord {
    pub decision_id: String,
    pub channel_id: String,
    pub domain: GameplayDecisionDomain,
    pub candidate_id: String,
    pub score_bp: u16,
    pub accepted: bool,
    pub rationale_codes: Vec<GameplayRationaleCode>,
    pub selected_id: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GameplaySlice {
    pub schema_version: String,
    pub document_kind: String,
    pub program_id: String,
    pub start_room: String,
    pub goal_room: String,
    pub critical_path: Vec<String>,
    pub fire_zones: Vec<FireZone>,
    pub objectives: Vec<Objective>,
    pub loot_containers: Vec<LootContainer>,
    pub summary: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct FireZone {}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Objective {
    pub id: String,
    pub sequence: u32,
    #[serde(rename = "type")]
    pub objective_type: String,
    pub kind: String,
    pub room_id: String,
    pub room_role: String,
    pub semantic: String,
    pub cell: [i32; 3],
    pub approach_cell: [i32; 3],
    pub approach_distance_cells: u32,
    pub interactable: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LootContainer {
    pub id: String,
    pub kind: String,
    pub room_id: String,
    pub approach_cell: [i32; 3],
    pub loot_table: String,
}
pub type PresentationIR = PresentationOutput;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema, Default)]
#[serde(deny_unknown_fields)]
pub struct GenerationTrace {
    pub schema_version: String,
    pub rng_channels: Vec<String>,
    pub candidate_decisions: Vec<String>,
    pub failed_constraints: Vec<String>,
    pub repairs: Vec<String>,
    pub retries: Vec<String>,
    pub fallback: Option<String>,
    pub adaptive_decisions: Vec<AdaptiveDecisionTrace>,
    pub stage_timings_micros: BTreeMap<String, u128>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema, Default)]
#[serde(deny_unknown_fields)]
pub struct GenerationMetrics {
    pub schema_version: String,
    pub pipeline_executions: u32,
    pub room_count: u32,
    pub entity_count: u32,
    pub structural_placement_count: u32,
    pub stage_timings_micros: BTreeMap<String, u128>,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ProcgenBundle {
    pub schema_version: String,
    pub version: VersionEnvelope,
    pub request: ProcgenRequest,
    pub world_ir: WorldIR,
    pub site_ir: SiteIR,
    pub gameplay_ir: GameplayIR,
    pub presentation_ir: PresentationIR,
    pub semantic_hash: String,
    pub metrics: GenerationMetrics,
    pub trace: GenerationTrace,
}

fn parse_stage_fallbacks(
    fallback: Option<&str>,
) -> Result<(Option<&str>, Option<&str>), ProcgenError> {
    let Some(fallback) = fallback else {
        return Ok((None, None));
    };
    let mut world = None;
    let mut site = None;
    for part in fallback.split('|') {
        if let Some(id) = part.strip_prefix("world:") {
            if id.is_empty() || world.replace(id).is_some() || site.is_some() {
                return Err(ProcgenError::InvalidRequest("fallback"));
            }
        } else if let Some(id) = part.strip_prefix("site:") {
            if id.is_empty() || site.replace(id).is_some() {
                return Err(ProcgenError::InvalidRequest("fallback"));
            }
        } else {
            return Err(ProcgenError::InvalidRequest("fallback"));
        }
    }
    Ok((world, site))
}

fn compose_stage_fallbacks(world: Option<String>, site: Option<String>) -> Option<String> {
    match (world, site) {
        (None, None) => None,
        (Some(world), None) => Some(format!("world:{world}")),
        (None, Some(site)) => Some(format!("site:{site}")),
        (Some(world), Some(site)) => Some(format!("world:{world}|site:{site}")),
    }
}

fn adaptive_contract_error(_: crate::adaptive::AdaptiveError) -> ProcgenError {
    ProcgenError::InvalidRequest("adaptive_trace")
}

fn world_candidate_features(world: &WorldIR) -> Result<CandidateFeatures, ProcgenError> {
    let marker_id = &world.extraction.selected_marker_id;
    let challenge_bp = world
        .hazard_fields
        .iter()
        .find(|field| &field.marker_id == marker_id)
        .and_then(|field| u16::try_from(field.severity_bp).ok())
        .ok_or(ProcgenError::InvalidRequest("world_adaptive_features"))?;
    let resource_cost_bp = world
        .resource_pressures
        .iter()
        .find(|field| &field.marker_id == marker_id)
        .and_then(|field| u16::try_from(field.pressure_bp).ok())
        .ok_or(ProcgenError::InvalidRequest("world_adaptive_features"))?;
    let pace_bp = world
        .routes
        .iter()
        .find(|route| {
            (&route.from == marker_id && route.to == world.extraction.hub_anchor_id)
                || (route.from == world.extraction.hub_anchor_id && &route.to == marker_id)
        })
        .and_then(|route| u16::try_from(route.cost_bp).ok())
        .ok_or(ProcgenError::InvalidRequest("world_adaptive_features"))?;
    Ok(CandidateFeatures {
        challenge_bp,
        pace_bp,
        resource_cost_bp,
    })
}

fn world_adaptive_trace(
    world: &WorldIR,
    used_fallback: bool,
    player: &PlayerModel,
) -> Result<AdaptiveDecisionTrace, ProcgenError> {
    let inputs = if used_fallback {
        Vec::new()
    } else {
        vec![ValidatedCandidateInput::new(
            world.archetype_id.clone(),
            world_candidate_features(world)?,
        )
        .map_err(adaptive_contract_error)?]
    };
    rank_validated_candidates(
        "decision:world-ranker",
        AdaptiveDecisionKind::WorldRanker,
        player,
        &inputs,
    )
    .map_err(adaptive_contract_error)
}

fn empty_site_adaptive_trace(player: &PlayerModel) -> Result<AdaptiveDecisionTrace, ProcgenError> {
    rank_validated_candidates(
        "decision:site-ranker",
        AdaptiveDecisionKind::SiteRanker,
        player,
        &[],
    )
    .map_err(adaptive_contract_error)
}

impl ProcgenBundle {
    pub fn from_json(json: &str) -> Result<Self, ProcgenError> {
        let value: Value = serde_json::from_str(json)?;
        let Some(schema) = value.get("schema_version").and_then(Value::as_str) else {
            return Err(ProcgenError::InvalidRequest("schema_version"));
        };
        check_schema(schema, PROCGEN_BUNDLE_SCHEMA)?;
        let bundle: Self = serde_json::from_value(value)?;
        bundle.validate()?;
        Ok(bundle)
    }
    pub fn validate(&self) -> Result<(), ProcgenError> {
        check_schema(&self.schema_version, PROCGEN_BUNDLE_SCHEMA)?;
        self.request.validate()?;
        check_schema(&self.world_ir.schema_version, WORLD_IR_SCHEMA)?;
        check_schema(&self.site_ir.schema_version, SITE_IR_SCHEMA)?;
        check_schema(&self.gameplay_ir.schema_version, GAMEPLAY_IR_SCHEMA)?;
        check_schema(&self.presentation_ir.schema_version, PRESENTATION_IR_SCHEMA)?;
        check_schema(&self.trace.schema_version, GENERATION_TRACE_SCHEMA)?;
        check_schema(&self.metrics.schema_version, GENERATION_METRICS_SCHEMA)?;
        if self.metrics.pipeline_executions != 1
            || self.trace.rng_channels.as_slice() != RNG_CHANNELS
        {
            return Err(ProcgenError::InvalidRequest("metrics_trace"));
        }
        if self.version.generator_version != self.request.generator_version
            || self.version.content_manifest_hash != self.request.content_manifest_hash
        {
            return Err(ProcgenError::InvalidRequest("version"));
        }
        if self.version.export_schemas != ExportSchemas::platform_v5() {
            return Err(ProcgenError::InvalidRequest("export_schemas"));
        }
        let [world_adaptive, site_adaptive, encounter_adaptive] =
            self.trace.adaptive_decisions.as_slice()
        else {
            return Err(ProcgenError::InvalidRequest("adaptive_trace_order"));
        };
        if world_adaptive.kind != AdaptiveDecisionKind::WorldRanker
            || world_adaptive.decision_id != "decision:world-ranker"
            || site_adaptive.kind != AdaptiveDecisionKind::SiteRanker
            || site_adaptive.decision_id != "decision:site-ranker"
            || encounter_adaptive.kind != AdaptiveDecisionKind::EncounterDirector
            || encounter_adaptive.decision_id != "decision:encounter-director"
        {
            return Err(ProcgenError::InvalidRequest("adaptive_trace_order"));
        }
        for decision in &self.trace.adaptive_decisions {
            decision
                .validate()
                .and_then(|_| decision.replay(&self.request.player_model))
                .map_err(adaptive_contract_error)?;
        }
        let world_request = WorldGenerationRequest {
            world_seed: self.request.world_seed,
            platform_version: self.request.generator_version,
            content_manifest_hash: self.request.content_manifest_hash.clone(),
            site_id: self.request.site.site_id.clone(),
            x: self.request.site.x,
            y: self.request.site.y,
            archetype_id: self.request.site.archetype_id.clone(),
        };
        let rules =
            WorldRules::bundled().map_err(|_| ProcgenError::InvalidRequest("world_rules"))?;
        let (world_fallback_id, site_fallback_id) =
            parse_stage_fallbacks(self.trace.fallback.as_deref())?;
        let valid_world = if let Some(world_fallback_id) = world_fallback_id {
            let fallback = crate::world::WorldFallback::bundled()
                .map_err(|_| ProcgenError::InvalidRequest("world_fallback"))?;
            if world_fallback_id != fallback.fallback_id
                || self.trace.repairs.iter().any(|repair| {
                    repair != "reconciled:fragment_metadata" && !repair.starts_with("site:")
                })
                || !self
                    .trace
                    .candidate_decisions
                    .iter()
                    .any(|d| d == "rejected_candidate")
                || !self
                    .trace
                    .candidate_decisions
                    .iter()
                    .any(|d| d == "selected_fallback")
            {
                return Err(ProcgenError::InvalidRequest("world_fallback_trace"));
            }
            self.world_ir
                .validate_for_fallback(&world_request, &rules, &fallback)
        } else {
            if self
                .trace
                .candidate_decisions
                .iter()
                .any(|d| d == "selected_fallback")
            {
                return Err(ProcgenError::InvalidRequest("world_fallback_trace"));
            }
            self.world_ir.validate_for_request(&world_request, &rules)
        };
        valid_world.map_err(|_| ProcgenError::InvalidRequest("world"))?;
        if self.world_ir.world_seed != self.request.world_seed
            || self.world_ir.site_id != self.request.site.site_id
            || self.world_ir.x != self.request.site.x
            || self.world_ir.y != self.request.site.y
            || self.world_ir.archetype_id != self.request.site.archetype_id
        {
            return Err(ProcgenError::InvalidRequest("world_identity"));
        }
        let expected_world_adaptive = world_adaptive_trace(
            &self.world_ir,
            world_fallback_id.is_some(),
            &self.request.player_model,
        )?;
        if *world_adaptive != expected_world_adaptive {
            return Err(ProcgenError::InvalidRequest("world_adaptive_trace"));
        }
        crate::site::validate_site_for_request(&self.site_ir, &world_request)
            .map_err(|_| ProcgenError::InvalidRequest("site"))?;
        let site_repairs = self
            .trace
            .repairs
            .iter()
            .filter_map(|repair| repair.strip_prefix("site:"))
            .collect::<Vec<_>>();
        if site_repairs.len() > 2
            || site_repairs
                .iter()
                .any(|repair| !matches!(*repair, "relocate_required_prop" | "replace_gate_binding"))
        {
            return Err(ProcgenError::InvalidRequest("site_repairs"));
        }
        let rejected_site_candidate = self
            .trace
            .candidate_decisions
            .iter()
            .any(|decision| decision == "site:rejected_candidate");
        let selected_site_fallback = self
            .trace
            .candidate_decisions
            .iter()
            .any(|decision| decision == "site:selected_fallback");
        match site_fallback_id {
            Some("authored-safe-return")
                if self.site_ir.mission_graph.mission_id == "authored-safe-return"
                    && rejected_site_candidate
                    && selected_site_fallback => {}
            None if self.site_ir.mission_graph.mission_id != "authored-safe-return"
                && !rejected_site_candidate
                && !selected_site_fallback => {}
            _ => return Err(ProcgenError::InvalidRequest("site_fallback_trace")),
        }
        if site_fallback_id.is_some() {
            if *site_adaptive != empty_site_adaptive_trace(&self.request.player_model)? {
                return Err(ProcgenError::InvalidRequest("site_adaptive_trace"));
            }
        } else {
            let (expected_site, expected_site_adaptive) = crate::site::generate_site_adaptive(
                self.site_ir.ship.clone(),
                &world_request,
                &self.request.player_model,
            )
            .map_err(|_| ProcgenError::InvalidRequest("site_adaptive_trace"))?;
            if expected_site.site != self.site_ir || expected_site_adaptive != *site_adaptive {
                return Err(ProcgenError::InvalidRequest("site_adaptive_trace"));
            }
            let actual_site_decisions = self
                .trace
                .candidate_decisions
                .iter()
                .filter_map(|decision| decision.strip_prefix("site:"))
                .collect::<Vec<_>>();
            if actual_site_decisions
                != expected_site
                    .trace
                    .candidate_decisions
                    .iter()
                    .map(String::as_str)
                    .collect::<Vec<_>>()
            {
                return Err(ProcgenError::InvalidRequest("site_adaptive_trace"));
            }
        }
        if self.site_ir.ship.seed != self.world_ir.site_seed
            || self.site_ir.ship.archetype_id != self.request.site.archetype_id
        {
            return Err(ProcgenError::InvalidRequest("ship_identity"));
        }
        let expected_placements = self
            .site_ir
            .ship
            .plan
            .placements
            .len()
            .checked_add(self.site_ir.ship.plan.floor_placements.len())
            .and_then(|n| n.checked_add(self.site_ir.ship.plan.ceiling_placements.len()))
            .and_then(|n| u32::try_from(n).ok())
            .ok_or(ProcgenError::InvalidRequest("metrics"))?;
        let expected_entities = self
            .site_ir
            .ship
            .entities
            .len()
            .checked_add(self.gameplay_ir.encounter.spawns.len())
            .and_then(|count| count.checked_add(self.gameplay_ir.items.len()))
            .and_then(|count| u32::try_from(count).ok())
            .ok_or(ProcgenError::InvalidRequest("metrics"))?;
        if self.metrics.room_count
            != u32::try_from(self.site_ir.ship.room_graph.nodes.len())
                .map_err(|_| ProcgenError::InvalidRequest("metrics"))?
            || self.metrics.entity_count != expected_entities
            || self.metrics.structural_placement_count != expected_placements
        {
            return Err(ProcgenError::InvalidRequest("metrics"));
        }
        if self
            .trace
            .rng_channels
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>()
            != RNG_CHANNELS
        {
            return Err(ProcgenError::InvalidRequest("rng_channels"));
        }
        if self.trace.candidate_decisions.len() > 4096
            || self.trace.failed_constraints.len() > 4096
            || self.trace.retries.len() > 4096
        {
            return Err(ProcgenError::InvalidRequest("trace_bounds"));
        }
        if self.trace.repairs.len() > 4096
            || self.trace.stage_timings_micros.len() > 4096
            || self.trace.stage_timings_micros.keys().any(|k| k.is_empty())
            || self
                .trace
                .stage_timings_micros
                .values()
                .any(|v| *v > 3_600_000_000)
            || self.trace.fallback.as_ref().is_some_and(String::is_empty)
            || self
                .trace
                .candidate_decisions
                .iter()
                .chain(self.trace.failed_constraints.iter())
                .chain(self.trace.repairs.iter())
                .chain(self.trace.retries.iter())
                .any(|s| s.is_empty())
        {
            return Err(ProcgenError::InvalidRequest("trace_bounds"));
        }
        if self.trace.stage_timings_micros != self.metrics.stage_timings_micros {
            return Err(ProcgenError::InvalidRequest("trace_metrics_timings"));
        }
        let expected_gameplay =
            crate::structural::export::to_gameplay_slice_json(&self.site_ir.ship);
        let actual_gameplay = serde_json::to_value(&self.gameplay_ir.legacy_slice)?;
        if self.gameplay_ir.legacy_slice.schema_version != "1.1.0"
            || self.gameplay_ir.legacy_slice.document_kind != "ship_gameplay_slice"
            || actual_gameplay != expected_gameplay
        {
            return Err(ProcgenError::InvalidRequest("gameplay_identity"));
        }
        let expected_gameplay_ir = build_gameplay_ir(
            &self.request,
            &self.site_ir,
            self.gameplay_ir.legacy_slice.clone(),
        )?;
        if self.gameplay_ir != expected_gameplay_ir {
            return Err(ProcgenError::InvalidRequest("gameplay_identity"));
        }
        if expected_gameplay_ir.encounter.trace.adaptive != *encounter_adaptive {
            return Err(ProcgenError::InvalidRequest("encounter_adaptive_trace"));
        }
        validate_gameplay_decisions(&self.gameplay_ir.decisions)?;
        let expected_presentation_ir =
            build_presentation_ir(&self.request, &self.site_ir, &expected_gameplay_ir)?;
        if self.presentation_ir != expected_presentation_ir {
            return Err(ProcgenError::InvalidRequest("presentation_identity"));
        }
        if self.semantic_hash != semantic_hash(self)? {
            return Err(ProcgenError::InvalidRequest("semantic_hash"));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ProcgenFailureCode {
    InvalidRequest,
    UnsupportedSchema,
    UnsupportedDomain,
    GeneratorContentMismatch,
    GenerationFailure,
    ValidationFailure,
    FallbackFailure,
    AdapterFailure,
    ManifestFailure,
    Capacity,
    Overload,
    Cancellation,
    Timeout,
    InternalFailure,
    UnknownRequest,
    ResultConsumed,
    ResultExpired,
    Shutdown,
    TooLateCancellation,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ProcgenFailure {
    pub schema_version: String,
    pub code: ProcgenFailureCode,
    pub stage: String,
    pub message: String,
    pub retryable: bool,
    pub fallback_id: Option<String>,
}

impl ProcgenFailure {
    pub fn from_json(json: &str) -> Result<Self, ProcgenError> {
        let value: Value = serde_json::from_str(json)?;
        if let Some(schema) = value.get("schema_version").and_then(Value::as_str) {
            check_schema(schema, FAILURE_SCHEMA)?;
        }
        let failure: Self = serde_json::from_value(value)?;
        failure.validate()?;
        Ok(failure)
    }
    pub fn validate(&self) -> Result<(), ProcgenError> {
        check_schema(&self.schema_version, FAILURE_SCHEMA)?;
        if self.stage.is_empty()
            || self.message.is_empty()
            || self.fallback_id.as_ref().is_some_and(String::is_empty)
        {
            return Err(ProcgenError::InvalidRequest("failure"));
        }
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ProcgenError {
    #[error("contract JSON parse failed: {0}")]
    Json(#[from] serde_json::Error),
    #[error("unknown schema major: {0}")]
    UnknownSchemaMajor(String),
    #[error("invalid request field: {0}")]
    InvalidRequest(&'static str),
    #[error("generation failed: {0}")]
    Generation(String),
}

impl ProcgenRequest {
    pub fn from_json(json: &str) -> Result<Self, ProcgenError> {
        let value: Value = serde_json::from_str(json)?;
        if let Some(schema) = value.get("schema_version").and_then(Value::as_str) {
            check_schema(schema, PROCGEN_REQUEST_SCHEMA)?;
        }
        let req: Self = serde_json::from_value(value)?;
        req.validate()?;
        Ok(req)
    }
    pub fn validate(&self) -> Result<(), ProcgenError> {
        check_schema(&self.schema_version, PROCGEN_REQUEST_SCHEMA)?;
        if self.world_seed > crate::world::MAX_PUBLIC_SEED {
            return Err(ProcgenError::InvalidRequest("world_seed"));
        }
        if self.generator_version != crate::world::PROCGEN_GENERATOR_VERSION {
            return Err(ProcgenError::InvalidRequest("generator_version"));
        }
        if self.site.site_id.is_empty()
            || self.site.archetype_id.is_empty()
            || self.site.kit_id.is_empty()
            || difficulty_band(&self.difficulty_id).is_err()
        {
            return Err(ProcgenError::InvalidRequest("identity"));
        }
        if self.site.intactness_override_bp.is_some_and(|v| v > 10_000)
            || self.site.loot_richness_bp > 30_000
        {
            return Err(ProcgenError::InvalidRequest("bounds"));
        }
        self.player_model
            .validate()
            .map_err(|_| ProcgenError::InvalidRequest("player_model"))?;
        if self.requested_domains.is_empty()
            || self.requested_domains.iter().any(|d| {
                !matches!(
                    d,
                    Domain::World | Domain::Site | Domain::Gameplay | Domain::Presentation
                )
            })
        {
            return Err(ProcgenError::InvalidRequest("requested_domains"));
        }
        let mut unique = std::collections::BTreeSet::new();
        if self.requested_domains.iter().any(|d| !unique.insert(d)) {
            return Err(ProcgenError::InvalidRequest("requested_domains"));
        }
        if !is_sha256(&self.content_manifest_hash) {
            return Err(ProcgenError::InvalidRequest("content_manifest_hash"));
        }
        if !is_locale(&self.presentation.locale) {
            return Err(ProcgenError::InvalidRequest("presentation.locale"));
        }
        if self.presentation.seed > crate::world::MAX_PUBLIC_SEED {
            return Err(ProcgenError::InvalidRequest("presentation.seed"));
        }
        Ok(())
    }
}

/// The established v2 ship pipeline records fracture membership before its
/// bounded connectivity repair may destroy isolated rooms. The layered bundle
/// contract removes only those stale references; it does not rerun or mutate
/// topology. This preserves the v2 structural generator while making the new
/// IR fail-closed and self-consistent.
fn reconcile_bundle_fragments(ship: &mut Ship) -> bool {
    if !ship.fractured {
        return false;
    }
    let original = ship.fragments.clone();
    let live_rooms: BTreeSet<_> = ship.topology.rooms.iter().map(|room| room.id).collect();
    for fragment in &mut ship.fragments {
        fragment.rooms.retain(|room| live_rooms.contains(room));
    }
    ship.fragments.retain(|fragment| !fragment.rooms.is_empty());

    let covered_rooms: BTreeSet<_> = ship
        .fragments
        .iter()
        .flat_map(|fragment| fragment.rooms.iter().copied())
        .collect();
    if ship.fragments.len() == 1 && covered_rooms == live_rooms {
        ship.fractured = false;
        ship.fragments.clear();
    }
    ship.fragments != original
}

fn world_request_for(request: &ProcgenRequest) -> WorldGenerationRequest {
    WorldGenerationRequest {
        world_seed: request.world_seed,
        platform_version: request.generator_version,
        content_manifest_hash: request.content_manifest_hash.clone(),
        site_id: request.site.site_id.clone(),
        x: request.site.x,
        y: request.site.y,
        archetype_id: request.site.archetype_id.clone(),
    }
}

fn difficulty_band(difficulty_id: &str) -> Result<DifficultyBand, ProcgenError> {
    match difficulty_id {
        "standard" => Ok(DifficultyBand::Standard),
        "hardened" => Ok(DifficultyBand::Hardened),
        "deep_dive" => Ok(DifficultyBand::DeepDive),
        _ => Err(ProcgenError::InvalidRequest("difficulty_id")),
    }
}

fn gameplay_identifier(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value.bytes().all(|byte| {
            byte.is_ascii_lowercase()
                || byte.is_ascii_digit()
                || matches!(byte, b':' | b'_' | b'-' | b'.')
        })
}

fn item_rationale(value: &str) -> Result<GameplayRationaleCode, ProcgenError> {
    match value {
        "authored_compatible" => Ok(GameplayRationaleCode::ItemAuthoredCompatible),
        "rejected_no_compatible_affix" => Ok(GameplayRationaleCode::ItemNoCompatibleAffix),
        "rejected_arithmetic_overflow" => Ok(GameplayRationaleCode::ItemArithmeticOverflow),
        "rejected_item_incompatible" => Ok(GameplayRationaleCode::ItemIncompatible),
        "rejected_economy_cap" => Ok(GameplayRationaleCode::ItemEconomyCap),
        _ => Err(ProcgenError::Generation(format!(
            "item decision uses unknown rationale: {value}"
        ))),
    }
}

fn gameplay_decisions(
    creature_set: &CreatureBlueprintSetOutcome,
    encounter: &EncounterGenerationOutcome,
    items: &ItemGenerationOutcome,
) -> Result<Vec<GameplayDecisionRecord>, ProcgenError> {
    let mut decisions = Vec::new();
    for (trace_index, trace) in creature_set.traces.iter().enumerate() {
        let channel_id = trace
            .channel_ids
            .first()
            .ok_or_else(|| ProcgenError::Generation("creature trace has no channel".into()))?;
        for (candidate_index, candidate) in trace.considered.iter().enumerate() {
            let selected = trace.selected.as_deref() == Some(candidate.candidate_id.as_str());
            let rationale = if selected {
                GameplayRationaleCode::CreatureSelected
            } else if candidate.accepted {
                GameplayRationaleCode::CreatureValidated
            } else {
                GameplayRationaleCode::CreatureIncompatible
            };
            decisions.push(GameplayDecisionRecord {
                decision_id: format!("creature:{trace_index:02}:{candidate_index:02}"),
                channel_id: channel_id.clone(),
                domain: GameplayDecisionDomain::Creature,
                candidate_id: candidate.candidate_id.clone(),
                score_bp: u16::try_from(candidate.score)
                    .map_err(|_| ProcgenError::Generation("creature score exceeds u16".into()))?,
                accepted: candidate.accepted,
                rationale_codes: vec![rationale],
                selected_id: selected.then(|| candidate.candidate_id.clone()),
            });
        }
    }
    for decision in &encounter.trace.decisions {
        decisions.push(GameplayDecisionRecord {
            decision_id: format!("encounter:{}", decision.decision_id),
            channel_id: decision.channel_id.clone(),
            domain: GameplayDecisionDomain::Encounter,
            candidate_id: decision.candidate_id.clone(),
            score_bp: decision.score_bp,
            accepted: decision.accepted,
            rationale_codes: decision
                .rationale_codes
                .iter()
                .copied()
                .map(GameplayRationaleCode::Encounter)
                .collect(),
            selected_id: decision.selected_spawn_id.clone(),
        });
    }
    for (index, candidate) in items.trace.considered.iter().enumerate() {
        let selected = candidate.accepted
            && items
                .trace
                .selected
                .iter()
                .any(|selected| selected == &candidate.candidate_id);
        decisions.push(GameplayDecisionRecord {
            decision_id: format!("item:{index:02}"),
            channel_id: "gameplay.item_affix".into(),
            domain: GameplayDecisionDomain::Item,
            candidate_id: candidate.candidate_id.clone(),
            score_bp: u16::try_from(candidate.score_bp)
                .map_err(|_| ProcgenError::Generation("item score exceeds u16".into()))?,
            accepted: candidate.accepted,
            rationale_codes: vec![item_rationale(&candidate.rationale)?],
            selected_id: selected.then(|| candidate.candidate_id.clone()),
        });
    }
    match items.trace.fallback.as_deref() {
        None => {}
        Some("authored_baseline") => {
            let selected =
                items.trace.selected.first().ok_or_else(|| {
                    ProcgenError::Generation("item fallback has no selection".into())
                })?;
            decisions.push(GameplayDecisionRecord {
                decision_id: "item:fallback".into(),
                channel_id: "gameplay.item_family".into(),
                domain: GameplayDecisionDomain::Item,
                candidate_id: selected.clone(),
                score_bp: 0,
                accepted: true,
                rationale_codes: vec![GameplayRationaleCode::ItemAuthoredBaseline],
                selected_id: Some(selected.clone()),
            });
        }
        Some("authored_safe_empty") => decisions.push(GameplayDecisionRecord {
            decision_id: "item:safe_empty".into(),
            channel_id: "gameplay.item_family".into(),
            domain: GameplayDecisionDomain::Item,
            candidate_id: "authored_safe_empty".into(),
            score_bp: 0,
            accepted: false,
            rationale_codes: vec![GameplayRationaleCode::ItemSafeEmpty],
            selected_id: None,
        }),
        Some(_) => {
            return Err(ProcgenError::Generation(
                "item trace uses unknown fallback".into(),
            ))
        }
    }
    validate_gameplay_decisions(&decisions)?;
    Ok(decisions)
}

fn validate_gameplay_decisions(decisions: &[GameplayDecisionRecord]) -> Result<(), ProcgenError> {
    if decisions.is_empty() || decisions.len() > 512 {
        return Err(ProcgenError::InvalidRequest("gameplay_decisions"));
    }
    let mut decision_ids = BTreeSet::new();
    for decision in decisions {
        if !gameplay_identifier(&decision.decision_id)
            || !gameplay_identifier(&decision.channel_id)
            || !gameplay_identifier(&decision.candidate_id)
            || decision.score_bp > 10_000
            || decision.rationale_codes.is_empty()
            || !decision_ids.insert(&decision.decision_id)
            || decision.accepted != decision.selected_id.is_some()
            || decision
                .selected_id
                .as_deref()
                .is_some_and(|selected| !gameplay_identifier(selected))
        {
            return Err(ProcgenError::InvalidRequest("gameplay_decisions"));
        }
    }
    Ok(())
}

fn build_gameplay_ir(
    request: &ProcgenRequest,
    site_ir: &SiteIR,
    legacy_slice: GameplaySlice,
) -> Result<GameplayIR, ProcgenError> {
    let world_request = world_request_for(request);
    let creature_catalogue = CreatureCatalogue::bundled()
        .map_err(|error| ProcgenError::Generation(error.to_string()))?;
    let min_clearance = site_ir
        .spatial_annotations
        .rooms
        .iter()
        .map(|room| room.minimum_clearance)
        .min()
        .ok_or(ProcgenError::InvalidRequest("spatial_annotations"))?;
    let creature_context = CreatureGenerationContext {
        request: world_request.clone(),
        min_clearance,
        max_footprint_cells: u16::try_from(crate::creature::MAX_CELLS)
            .map_err(|_| ProcgenError::Generation("creature footprint capacity".into()))?,
        threat_cap: creature_catalogue.rules.max_threat,
        performance_cap: creature_catalogue.rules.max_performance,
        instance_cap: creature_catalogue.rules.max_instances,
    };
    let creature_set =
        crate::creature::generate_creature_blueprint_set(&creature_context, &creature_catalogue)
            .map_err(|error| ProcgenError::Generation(error.to_string()))?;
    creature_set
        .validate(&creature_context, &creature_catalogue)
        .map_err(|error| ProcgenError::Generation(error.to_string()))?;

    let encounter_catalogue = EncounterCatalogue::bundled()
        .map_err(|error| ProcgenError::Generation(error.to_string()))?;
    let encounter_context = EncounterGenerationContext {
        request: world_request.clone(),
        difficulty_id: difficulty_band(&request.difficulty_id)?,
        player: request.player_model.clone(),
        loot_richness_bp: request.site.loot_richness_bp,
        threat_cap: 3_000,
        performance_cap: 3_000,
        economy_cap: 2_000,
    };
    let encounter = crate::encounter::generate_encounters(
        &encounter_context,
        &encounter_catalogue,
        site_ir,
        &creature_set.blueprints,
    )
    .map_err(|error| ProcgenError::Generation(error.to_string()))?;

    let mut sources: Vec<SourceBinding> = legacy_slice
        .loot_containers
        .iter()
        .map(|container| SourceBinding {
            source_id: container.id.clone(),
            source_kind: SourceKind::Container,
        })
        .chain(encounter.spawns.iter().map(|spawn| SourceBinding {
            source_id: spawn.reward_source_id.clone(),
            source_kind: SourceKind::EncounterReward,
        }))
        .collect();
    sources.sort_by(|left, right| left.source_id.cmp(&right.source_id));
    if sources
        .windows(2)
        .any(|pair| pair[0].source_id == pair[1].source_id)
    {
        return Err(ProcgenError::Generation(
            "duplicate gameplay reward source".into(),
        ));
    }
    let item_catalogue =
        ItemCatalogue::bundled().map_err(|error| ProcgenError::Generation(error.to_string()))?;
    let max_count = u16::try_from(sources.len().min(MAX_ITEMS))
        .map_err(|_| ProcgenError::Generation("item source capacity".into()))?;
    let item_context = ItemGenerationContext {
        request: world_request,
        difficulty_id: request.difficulty_id.clone(),
        loot_richness_bp: u32::from(request.site.loot_richness_bp),
        eligible_sources: sources,
        max_total_value: item_catalogue.caps.max_total_value,
        max_count,
    };
    let item_outcome = crate::item_generation::generate_items(&item_context, &item_catalogue)
        .map_err(|error| ProcgenError::Generation(error.to_string()))?;
    item_outcome
        .validate(&item_context, &item_catalogue)
        .map_err(|error| ProcgenError::Generation(error.to_string()))?;
    let decisions = gameplay_decisions(&creature_set, &encounter, &item_outcome)?;

    Ok(GameplayIR {
        schema_version: GAMEPLAY_IR_SCHEMA.into(),
        legacy_slice,
        creature_blueprints: creature_set.blueprints,
        encounter,
        items: item_outcome.items,
        drops: item_outcome.drops,
        decisions,
    })
}

fn build_presentation_ir(
    request: &ProcgenRequest,
    site_ir: &SiteIR,
    gameplay_ir: &GameplayIR,
) -> Result<PresentationIR, ProcgenError> {
    let mut subjects = vec![
        PresentationSubject {
            subject_id: "environment:ambient".into(),
            subject_kind: SubjectKind::Environment,
            binding_tags: vec!["ambient.default".into()],
        },
        PresentationSubject {
            subject_id: "ship:structural".into(),
            subject_kind: SubjectKind::Ship,
            binding_tags: vec!["structural.default".into()],
        },
    ];
    for blueprint in &gameplay_ir.creature_blueprints {
        let family = blueprint
            .id
            .strip_prefix("creature_")
            .ok_or_else(|| ProcgenError::Generation("unknown creature visual family".into()))?;
        subjects.push(PresentationSubject {
            subject_id: format!("creature:{}", blueprint.id),
            subject_kind: SubjectKind::Creature,
            binding_tags: vec![format!("creature.{family}")],
        });
    }
    for item in &gameplay_ir.items {
        let family = item
            .visual_tag
            .strip_prefix("item_")
            .ok_or_else(|| ProcgenError::Generation("unknown item visual family".into()))?;
        subjects.push(PresentationSubject {
            subject_id: format!("item:{}", item.id),
            subject_kind: SubjectKind::Item,
            binding_tags: vec![format!("item.{family}")],
        });
    }
    for (index, _) in site_ir.functional_props.iter().enumerate() {
        subjects.push(PresentationSubject {
            subject_id: format!("objective:{index:02}"),
            subject_kind: SubjectKind::Objective,
            binding_tags: vec!["objective.default".into()],
        });
    }
    subjects.sort_by(|left, right| left.subject_id.cmp(&right.subject_id));
    if subjects.len() > 128
        || subjects
            .windows(2)
            .any(|pair| pair[0].subject_id == pair[1].subject_id)
    {
        return Err(ProcgenError::Generation(
            "presentation subject capacity".into(),
        ));
    }
    let context = PresentationContext {
        request: world_request_for(request),
        presentation_seed: request.presentation.seed,
        locale: request.presentation.locale.clone(),
        subjects,
    };
    let catalogue = PresentationCatalogue::bundled()
        .map_err(|error| ProcgenError::Generation(error.to_string()))?;
    let output = crate::presentation::assemble(&context, &catalogue)
        .map_err(|error| ProcgenError::Generation(error.to_string()))?;
    output
        .validate(&context, &catalogue)
        .map_err(|error| ProcgenError::Generation(error.to_string()))?;
    Ok(output)
}

pub fn generate_bundle(
    request: ProcgenRequest,
    data: &GenData,
) -> Result<ProcgenBundle, ProcgenFailure> {
    generate_bundle_with_site_transform(request, data, |outcome, _| Ok(outcome))
}

/// Fault-injection seam for exercising the complete post-site pipeline.
/// Production adapters expose only [`generate_bundle`].
#[doc(hidden)]
pub fn generate_bundle_with_site_transform<S>(
    request: ProcgenRequest,
    data: &GenData,
    site_transform: S,
) -> Result<ProcgenBundle, ProcgenFailure>
where
    S: FnOnce(
        crate::site::SiteGenerationOutcome,
        &WorldGenerationRequest,
    ) -> Result<crate::site::SiteGenerationOutcome, crate::site::SiteError>,
{
    request.validate().map_err(|e| {
        failure(
            ProcgenFailureCode::InvalidRequest,
            "request",
            e.to_string(),
            false,
        )
    })?;
    let world_request = WorldGenerationRequest {
        world_seed: request.world_seed,
        platform_version: request.generator_version,
        content_manifest_hash: request.content_manifest_hash.clone(),
        site_id: request.site.site_id.clone(),
        x: request.site.x,
        y: request.site.y,
        archetype_id: request.site.archetype_id.clone(),
    };
    let world = crate::world::generate_world(&world_request).map_err(|e| {
        let code = if matches!(e, crate::world::WorldError::Invalid(_)) {
            ProcgenFailureCode::InvalidRequest
        } else {
            ProcgenFailureCode::GenerationFailure
        };
        let retryable = matches!(code, ProcgenFailureCode::GenerationFailure);
        failure(code, "world", e.to_string(), retryable)
    })?;
    let seed = world.world_ir.site_seed;
    let params = GenParams {
        archetype_id: request.site.archetype_id.clone(),
        intactness_override: request.site.intactness_override_bp,
        cause_override: request.site.cause_of_loss,
        loot_richness: request.site.loot_richness_bp,
    };
    generate_bundle_with_world_and_site_transform(
        request,
        data,
        world,
        || generate_ship_timed(seed, &params, data),
        site_transform,
    )
}

#[doc(hidden)]
pub fn generate_bundle_with_pipeline<F>(
    request: ProcgenRequest,
    data: &GenData,
    pipeline: F,
) -> Result<ProcgenBundle, ProcgenFailure>
where
    F: FnOnce() -> Result<crate::pipeline::GenReport, crate::pipeline::GenError>,
{
    let world_request = WorldGenerationRequest {
        world_seed: request.world_seed,
        platform_version: request.generator_version,
        content_manifest_hash: request.content_manifest_hash.clone(),
        site_id: request.site.site_id.clone(),
        x: request.site.x,
        y: request.site.y,
        archetype_id: request.site.archetype_id.clone(),
    };
    let world = crate::world::generate_world(&world_request).map_err(|e| {
        failure(
            ProcgenFailureCode::GenerationFailure,
            "world",
            e.to_string(),
            true,
        )
    })?;
    generate_bundle_with_world_pipeline(request, data, world, pipeline)
}

fn generate_bundle_with_world_pipeline<F>(
    request: ProcgenRequest,
    data: &GenData,
    world: crate::world::WorldGenerationOutcome,
    pipeline: F,
) -> Result<ProcgenBundle, ProcgenFailure>
where
    F: FnOnce() -> Result<crate::pipeline::GenReport, crate::pipeline::GenError>,
{
    generate_bundle_with_world_and_site_transform(request, data, world, pipeline, |outcome, _| {
        Ok(outcome)
    })
}

fn generate_bundle_with_world_and_site_transform<F, S>(
    request: ProcgenRequest,
    _data: &GenData,
    world: crate::world::WorldGenerationOutcome,
    pipeline: F,
    site_transform: S,
) -> Result<ProcgenBundle, ProcgenFailure>
where
    F: FnOnce() -> Result<crate::pipeline::GenReport, crate::pipeline::GenError>,
    S: FnOnce(
        crate::site::SiteGenerationOutcome,
        &WorldGenerationRequest,
    ) -> Result<crate::site::SiteGenerationOutcome, crate::site::SiteError>,
{
    request.validate().map_err(|e| {
        failure(
            ProcgenFailureCode::InvalidRequest,
            "request",
            e.to_string(),
            false,
        )
    })?;
    let report = pipeline().map_err(|e| {
        failure(
            ProcgenFailureCode::GenerationFailure,
            "generation",
            e.to_string(),
            true,
        )
    })?;
    let mut ship = report.ship;
    let repaired_fragments = reconcile_bundle_fragments(&mut ship);
    if ship.generator_version != GENERATOR_VERSION
        || ship.seed != world.world_ir.site_seed
        || ship.archetype_id != request.site.archetype_id
    {
        return Err(failure(
            ProcgenFailureCode::ValidationFailure,
            "generation",
            "pipeline ship does not match request identity".into(),
            false,
        ));
    }
    let crate::world::WorldGenerationOutcome {
        world_ir,
        candidate_decisions: world_decisions,
        repairs: world_repairs,
        fallback: world_fallback,
    } = world;
    let world_adaptive =
        world_adaptive_trace(&world_ir, world_fallback.is_some(), &request.player_model).map_err(
            |error| {
                failure(
                    ProcgenFailureCode::ValidationFailure,
                    "world_adaptive",
                    error.to_string(),
                    false,
                )
            },
        )?;
    let world_request = WorldGenerationRequest {
        world_seed: request.world_seed,
        platform_version: request.generator_version,
        content_manifest_hash: request.content_manifest_hash.clone(),
        site_id: request.site.site_id.clone(),
        x: request.site.x,
        y: request.site.y,
        archetype_id: request.site.archetype_id.clone(),
    };
    let site_started = Instant::now();
    let (generated_site, mut site_adaptive) =
        crate::site::generate_site_adaptive(ship, &world_request, &request.player_model).map_err(
            |error| {
                let mut failure = failure(
                    ProcgenFailureCode::FallbackFailure,
                    "site",
                    error.to_string(),
                    false,
                );
                failure.fallback_id = Some("authored-safe-return".into());
                failure
            },
        )?;
    let site_outcome = site_transform(generated_site, &world_request).map_err(|error| {
        let mut failure = failure(
            ProcgenFailureCode::FallbackFailure,
            "site",
            error.to_string(),
            false,
        );
        failure.fallback_id = Some("authored-safe-return".into());
        failure
    })?;
    if site_outcome.trace.fallback.is_some() {
        site_adaptive = empty_site_adaptive_trace(&request.player_model).map_err(|error| {
            failure(
                ProcgenFailureCode::ValidationFailure,
                "site_adaptive",
                error.to_string(),
                false,
            )
        })?;
    } else if site_adaptive.selected_candidate_id.as_deref()
        != Some(site_outcome.site.mission_graph.mission_id.as_str())
    {
        return Err(failure(
            ProcgenFailureCode::ValidationFailure,
            "site_adaptive",
            "site transform changed the ranked candidate identity".into(),
            false,
        ));
    }
    let site_micros = site_started.elapsed().as_micros();
    let crate::site::SiteGenerationOutcome {
        site: site_ir,
        trace: site_trace,
    } = site_outcome;
    let ship = &site_ir.ship;
    let legacy_slice = crate::structural::export::to_gameplay_slice_json(ship);
    let legacy_slice: GameplaySlice = serde_json::from_value(legacy_slice).map_err(|error| {
        failure(
            ProcgenFailureCode::InternalFailure,
            "gameplay",
            error.to_string(),
            false,
        )
    })?;
    let gameplay_started = Instant::now();
    let gameplay_ir = build_gameplay_ir(&request, &site_ir, legacy_slice).map_err(|error| {
        failure(
            ProcgenFailureCode::GenerationFailure,
            "gameplay",
            error.to_string(),
            false,
        )
    })?;
    let gameplay_micros = gameplay_started.elapsed().as_micros();
    let presentation_started = Instant::now();
    let presentation_ir =
        build_presentation_ir(&request, &site_ir, &gameplay_ir).map_err(|error| {
            failure(
                ProcgenFailureCode::GenerationFailure,
                "presentation",
                error.to_string(),
                false,
            )
        })?;
    let presentation_micros = presentation_started.elapsed().as_micros();
    let version = VersionEnvelope {
        generator_version: request.generator_version,
        content_manifest_hash: request.content_manifest_hash.clone(),
        export_schemas: ExportSchemas::platform_v5(),
    };
    let room_count = u32::try_from(ship.room_graph.nodes.len()).map_err(|_| {
        failure(
            ProcgenFailureCode::Capacity,
            "metrics",
            "room count exceeds u32".into(),
            false,
        )
    })?;
    let entity_count = ship
        .entities
        .len()
        .checked_add(gameplay_ir.encounter.spawns.len())
        .and_then(|count| count.checked_add(gameplay_ir.items.len()))
        .and_then(|count| u32::try_from(count).ok())
        .ok_or_else(|| {
            failure(
                ProcgenFailureCode::Capacity,
                "metrics",
                "entity count exceeds u32".into(),
                false,
            )
        })?;
    let structural_placement_count = ship
        .plan
        .placements
        .len()
        .checked_add(ship.plan.floor_placements.len())
        .and_then(|n| n.checked_add(ship.plan.ceiling_placements.len()))
        .and_then(|n| u32::try_from(n).ok())
        .ok_or_else(|| {
            failure(
                ProcgenFailureCode::Capacity,
                "metrics",
                "placement count exceeds u32".into(),
                false,
            )
        })?;
    let mut stage_timings_micros: BTreeMap<String, u128> = report
        .stage_micros
        .iter()
        .map(|(key, value)| ((*key).into(), *value))
        .collect();
    stage_timings_micros.insert("site_overlay".into(), site_micros);
    stage_timings_micros.insert("gameplay_compile".into(), gameplay_micros);
    stage_timings_micros.insert("presentation_assembly".into(), presentation_micros);
    let metrics = GenerationMetrics {
        schema_version: GENERATION_METRICS_SCHEMA.into(),
        pipeline_executions: 1,
        room_count,
        entity_count,
        structural_placement_count,
        stage_timings_micros,
    };
    let site_repairs = site_trace
        .repairs
        .into_iter()
        .map(|repair| format!("site:{repair}"));
    let repairs = world_repairs
        .into_iter()
        .chain(repaired_fragments.then_some("reconciled:fragment_metadata".into()))
        .chain(site_repairs)
        .collect();
    let trace = GenerationTrace {
        schema_version: GENERATION_TRACE_SCHEMA.into(),
        rng_channels: RNG_CHANNELS.iter().map(|s| (*s).into()).collect(),
        candidate_decisions: world_decisions
            .into_iter()
            .chain(report.candidate_decisions)
            .chain(
                site_trace
                    .candidate_decisions
                    .into_iter()
                    .map(|decision| format!("site:{decision}")),
            )
            .chain(
                gameplay_ir
                    .decisions
                    .iter()
                    .map(|decision| format!("gameplay:{}", decision.decision_id)),
            )
            .collect(),
        failed_constraints: report.failed_constraints,
        repairs,
        retries: report.retries,
        adaptive_decisions: vec![
            world_adaptive,
            site_adaptive,
            gameplay_ir.encounter.trace.adaptive.clone(),
        ],
        stage_timings_micros: metrics.stage_timings_micros.clone(),
        fallback: compose_stage_fallbacks(world_fallback, site_trace.fallback),
    };
    let mut bundle = ProcgenBundle {
        schema_version: PROCGEN_BUNDLE_SCHEMA.into(),
        version,
        request,
        world_ir,
        site_ir,
        gameplay_ir,
        presentation_ir,
        semantic_hash: String::new(),
        metrics,
        trace,
    };
    bundle.semantic_hash = semantic_hash(&bundle).map_err(|e| {
        failure(
            ProcgenFailureCode::InternalFailure,
            "hash",
            e.to_string(),
            false,
        )
    })?;
    bundle.validate().map_err(|e| {
        failure(
            ProcgenFailureCode::ValidationFailure,
            "bundle",
            e.to_string(),
            false,
        )
    })?;
    Ok(bundle)
}

pub fn migration_layout(bundle: &ProcgenBundle) -> Result<Value, ProcgenError> {
    bundle.validate()?;
    Ok(crate::structural::export::to_layout_json(
        &bundle.site_ir.ship,
        &crate::structural::export::ExportOptions {
            kit_id: bundle.request.site.kit_id.clone(),
            difficulty_id: bundle.request.difficulty_id.clone(),
            ..Default::default()
        },
    ))
}
pub fn migration_gameplay(bundle: &ProcgenBundle) -> Result<Value, ProcgenError> {
    bundle.validate()?;
    Ok(serde_json::to_value(&bundle.gameplay_ir.legacy_slice)?)
}
pub fn canonical_json_hash(value: &Value) -> Result<String, ProcgenError> {
    let bytes = serde_json::to_vec(&canonical(value.clone()))?;
    let digest = Sha256::digest(bytes);
    Ok(digest.iter().map(|b| format!("{b:02x}")).collect())
}

pub fn semantic_hash(bundle: &ProcgenBundle) -> Result<String, ProcgenError> {
    let mut projection = Map::new();
    projection.insert("version".into(), serde_json::to_value(&bundle.version)?);
    projection.insert("request".into(), mechanical_request(&bundle.request));
    projection.insert("world_ir".into(), serde_json::to_value(&bundle.world_ir)?);
    projection.insert("site_ir".into(), serde_json::to_value(&bundle.site_ir)?);
    projection.insert(
        "gameplay_ir".into(),
        serde_json::to_value(&bundle.gameplay_ir)?,
    );
    let bytes = serde_json::to_vec(&canonical(Value::Object(projection)))?;
    let digest = Sha256::digest(bytes);
    Ok(digest.iter().map(|b| format!("{b:02x}")).collect())
}
fn mechanical_request(req: &ProcgenRequest) -> Value {
    let mut v = serde_json::to_value(req).unwrap_or(Value::Null);
    if let Some(o) = v.as_object_mut() {
        o.remove("presentation");
        if let Some(domains) = o.get_mut("requested_domains").and_then(Value::as_array_mut) {
            domains.sort_by_key(|value| value.as_str().unwrap_or_default().to_owned());
        }
    }
    v
}
fn canonical(v: Value) -> Value {
    match v {
        Value::Object(o) => Value::Object(o.into_iter().map(|(k, v)| (k, canonical(v))).collect()),
        Value::Array(a) => Value::Array(a.into_iter().map(canonical).collect()),
        v => v,
    }
}
fn check_schema(actual: &str, expected: &str) -> Result<(), ProcgenError> {
    if actual == expected {
        Ok(())
    } else if actual.starts_with(&expected[..expected.rfind('-').unwrap() + 1]) {
        Err(ProcgenError::UnknownSchemaMajor(actual.into()))
    } else {
        Err(ProcgenError::InvalidRequest("schema_version"))
    }
}
fn is_sha256(s: &str) -> bool {
    s.len() == 64
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn is_locale(s: &str) -> bool {
    let mut parts = s.split('-');
    let Some(language) = parts.next() else {
        return false;
    };
    (2..=3).contains(&language.len())
        && language.bytes().all(|b| b.is_ascii_alphabetic())
        && parts.all(|part| {
            (2..=8).contains(&part.len()) && part.bytes().all(|b| b.is_ascii_alphanumeric())
        })
}
fn failure(
    code: ProcgenFailureCode,
    stage: &str,
    message: String,
    retryable: bool,
) -> ProcgenFailure {
    ProcgenFailure {
        schema_version: FAILURE_SCHEMA.into(),
        code,
        stage: stage.into(),
        message,
        retryable,
        fallback_id: None,
    }
}
