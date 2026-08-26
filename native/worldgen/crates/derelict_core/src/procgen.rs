//! Versioned contracts and the single-pass generation bundle.
use crate::manifest::ExportSchemas;
use crate::model::{CauseOfLoss, Ship, GENERATOR_VERSION};
pub use crate::world::WorldIR;
use crate::world::{WorldGenerationRequest, WorldRules};
use crate::{generate_ship_timed, GenData, GenParams};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::collections::BTreeSet;

pub const PROCGEN_REQUEST_SCHEMA: &str = crate::manifest::PROCGEN_REQUEST_SCHEMA;
pub const PROCGEN_BUNDLE_SCHEMA: &str = crate::manifest::PROCGEN_BUNDLE_SCHEMA_V2;
pub const WORLD_IR_SCHEMA: &str = crate::manifest::WORLD_IR_SCHEMA_V2;
pub const SITE_IR_SCHEMA: &str = crate::manifest::SITE_IR_SCHEMA;
pub const GAMEPLAY_IR_SCHEMA: &str = crate::manifest::GAMEPLAY_IR_SCHEMA;
pub const PRESENTATION_IR_SCHEMA: &str = crate::manifest::PRESENTATION_IR_SCHEMA;
pub const GENERATION_TRACE_SCHEMA: &str = crate::manifest::GENERATION_TRACE_SCHEMA;
pub const ADAPTIVE_PROPOSAL_SCHEMA: &str = crate::manifest::ADAPTIVE_PROPOSAL_SCHEMA;
pub const PLAYER_MODEL_SCHEMA: &str = "player-model-1";
pub const FAILURE_SCHEMA: &str = "procgen-failure-1";
pub const GENERATION_METRICS_SCHEMA: &str = "generation-metrics-1";
const RNG_CHANNELS: [&str; 23] = [
    "world.archetype",
    "world.biome",
    "world.hazard",
    "world.resource",
    "world.landmark",
    "world.route_cost",
    "site.structural",
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
pub struct PlayerModel {
    pub schema_version: String,
    pub signals: Vec<i32>,
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
pub struct SiteIR {
    pub schema_version: String,
    pub ship: Ship,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GameplayIR {
    pub schema_version: String,
    pub legacy_slice: GameplaySlice,
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
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PresentationIR {
    pub schema_version: String,
    pub kit_id: String,
    pub locale: String,
    pub seed: u64,
    pub approved_bindings: BTreeMap<String, String>,
}

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
        if self.version.export_schemas != ExportSchemas::platform_v3() {
            return Err(ProcgenError::InvalidRequest("export_schemas"));
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
        let valid_world = if self.trace.fallback.is_some() {
            let fallback = crate::world::WorldFallback::bundled()
                .map_err(|_| ProcgenError::InvalidRequest("world_fallback"))?;
            self.world_ir
                .validate_for_fallback(&world_request, &rules, &fallback)
        } else {
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
        if self.presentation_ir.kit_id != self.request.site.kit_id
            || self.presentation_ir.locale != self.request.presentation.locale
            || self.presentation_ir.seed != self.request.presentation.seed
        {
            return Err(ProcgenError::InvalidRequest("presentation_identity"));
        }
        if self.site_ir.ship.generator_version != GENERATOR_VERSION
            || self.site_ir.ship.seed != self.world_ir.site_seed
            || self.site_ir.ship.archetype_id != self.request.site.archetype_id
        {
            return Err(ProcgenError::InvalidRequest("ship_identity"));
        }
        self.site_ir
            .ship
            .topology
            .validate()
            .map_err(|_| ProcgenError::InvalidRequest("topology"))?;
        let profile = crate::stages::story::profile_for(self.site_ir.ship.cause_of_loss);
        let fragment_of = if self.site_ir.ship.fractured {
            if self.site_ir.ship.fragments.is_empty() {
                return Err(ProcgenError::InvalidRequest("fragments"));
            }
            let room_ids: BTreeSet<_> = self
                .site_ir
                .ship
                .topology
                .rooms
                .iter()
                .map(|room| room.id)
                .collect();
            let mut seen = BTreeSet::new();
            let mut mapping = BTreeMap::new();
            for fragment in &self.site_ir.ship.fragments {
                if fragment.rooms.is_empty() || !seen.insert(fragment.id) {
                    return Err(ProcgenError::InvalidRequest("fragments"));
                }
                for room in &fragment.rooms {
                    if !room_ids.contains(room) || mapping.insert(*room, fragment.id).is_some() {
                        return Err(ProcgenError::InvalidRequest("fragments"));
                    }
                }
            }
            if mapping.len() != room_ids.len() {
                return Err(ProcgenError::InvalidRequest("fragments"));
            }
            Some(mapping)
        } else {
            if !self.site_ir.ship.fragments.is_empty() {
                return Err(ProcgenError::InvalidRequest("fragments"));
            }
            None
        };
        let policy = crate::structural::validate::ValidationPolicy::post_damage(
            self.site_ir.ship.critical_path.clone(),
            fragment_of,
            profile.allows_fragment_split,
        );
        crate::structural::validate::validate(
            &self.site_ir.ship.plan,
            &self.site_ir.ship.topology,
            &policy,
        )
        .map_err(|_| ProcgenError::InvalidRequest("structural"))?;
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
        if self.metrics.room_count
            != u32::try_from(self.site_ir.ship.room_graph.nodes.len())
                .map_err(|_| ProcgenError::InvalidRequest("metrics"))?
            || self.metrics.entity_count
                != u32::try_from(self.site_ir.ship.entities.len())
                    .map_err(|_| ProcgenError::InvalidRequest("metrics"))?
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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
#[serde(rename_all = "snake_case")]
pub enum AdaptiveAction {
    NoOp,
    SelectCandidate {
        candidate_id: String,
    },
    AdjustEncounter {
        encounter_id: String,
        pacing_delta: i32,
    },
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AdaptiveProposal {
    pub schema_version: String,
    pub score: i32,
    pub rationale_codes: Vec<String>,
    pub confidence_bp: u16,
    pub rule_model_version: String,
    pub action: AdaptiveAction,
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
        if self.generator_version != crate::world::PROCGEN_GENERATOR_VERSION
            || self.world_seed > crate::world::MAX_PUBLIC_SEED
        {
            return Err(ProcgenError::InvalidRequest("generator_version"));
        }
        if self.site.site_id.is_empty()
            || self.site.archetype_id.is_empty()
            || self.site.kit_id.is_empty()
            || self.difficulty_id.is_empty()
        {
            return Err(ProcgenError::InvalidRequest("identity"));
        }
        if self.site.intactness_override_bp.is_some_and(|v| v > 10_000)
            || self.site.loot_richness_bp > 30_000
        {
            return Err(ProcgenError::InvalidRequest("bounds"));
        }
        check_schema(&self.player_model.schema_version, PLAYER_MODEL_SCHEMA)?;
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
        Ok(())
    }
}

impl AdaptiveProposal {
    pub fn from_json(json: &str) -> Result<Self, ProcgenError> {
        let value: Value = serde_json::from_str(json)?;
        let proposal: Self = serde_json::from_value(value)?;
        proposal.validate()?;
        Ok(proposal)
    }
    pub fn validate(&self) -> Result<(), ProcgenError> {
        check_schema(&self.schema_version, ADAPTIVE_PROPOSAL_SCHEMA)?;
        if self.rationale_codes.is_empty()
            || self.rationale_codes.iter().any(|s| s.is_empty())
            || self.rule_model_version.is_empty()
        {
            return Err(ProcgenError::InvalidRequest(
                "adaptive_proposal.identifiers",
            ));
        }
        if self.confidence_bp > 10_000 {
            return Err(ProcgenError::InvalidRequest(
                "adaptive_proposal.confidence_bp",
            ));
        }
        match &self.action {
            AdaptiveAction::NoOp => {}
            AdaptiveAction::SelectCandidate { candidate_id } if candidate_id.is_empty() => {
                return Err(ProcgenError::InvalidRequest("candidate_id"))
            }
            AdaptiveAction::AdjustEncounter { encounter_id, .. } if encounter_id.is_empty() => {
                return Err(ProcgenError::InvalidRequest("encounter_id"))
            }
            _ => {}
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

pub fn generate_bundle(
    request: ProcgenRequest,
    data: &GenData,
) -> Result<ProcgenBundle, ProcgenFailure> {
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
        failure(
            ProcgenFailureCode::GenerationFailure,
            "world",
            e.to_string(),
            true,
        )
    })?;
    let seed = world.world_ir.site_seed;
    let params = GenParams {
        archetype_id: request.site.archetype_id.clone(),
        intactness_override: request.site.intactness_override_bp,
        cause_override: request.site.cause_of_loss,
        loot_richness: request.site.loot_richness_bp,
    };
    generate_bundle_with_world_pipeline(request, data, world, || {
        generate_ship_timed(seed, &params, data)
    })
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
    _data: &GenData,
    world: crate::world::WorldGenerationOutcome,
    pipeline: F,
) -> Result<ProcgenBundle, ProcgenFailure>
where
    F: FnOnce() -> Result<crate::pipeline::GenReport, crate::pipeline::GenError>,
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
    let legacy_slice = crate::structural::export::to_gameplay_slice_json(&ship);
    let crate::world::WorldGenerationOutcome {
        world_ir,
        candidate_decisions: world_decisions,
        repairs: world_repairs,
        fallback: world_fallback,
    } = world;
    let site_ir = SiteIR {
        schema_version: SITE_IR_SCHEMA.into(),
        ship: ship.clone(),
    };
    let gameplay_ir = GameplayIR {
        schema_version: GAMEPLAY_IR_SCHEMA.into(),
        legacy_slice: serde_json::from_value(legacy_slice).map_err(|e| {
            failure(
                ProcgenFailureCode::InternalFailure,
                "gameplay",
                e.to_string(),
                false,
            )
        })?,
    };
    let presentation_ir = PresentationIR {
        schema_version: PRESENTATION_IR_SCHEMA.into(),
        kit_id: request.site.kit_id.clone(),
        locale: request.presentation.locale.clone(),
        seed: request.presentation.seed,
        approved_bindings: BTreeMap::new(),
    };
    let version = VersionEnvelope {
        generator_version: request.generator_version,
        content_manifest_hash: request.content_manifest_hash.clone(),
        export_schemas: ExportSchemas::platform_v3(),
    };
    let room_count = u32::try_from(ship.room_graph.nodes.len()).map_err(|_| {
        failure(
            ProcgenFailureCode::Capacity,
            "metrics",
            "room count exceeds u32".into(),
            false,
        )
    })?;
    let entity_count = u32::try_from(ship.entities.len()).map_err(|_| {
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
    let metrics = GenerationMetrics {
        schema_version: GENERATION_METRICS_SCHEMA.into(),
        pipeline_executions: 1,
        room_count,
        entity_count,
        structural_placement_count,
        stage_timings_micros: report
            .stage_micros
            .iter()
            .map(|(k, v)| ((*k).into(), *v))
            .collect(),
    };
    let trace = GenerationTrace {
        schema_version: GENERATION_TRACE_SCHEMA.into(),
        rng_channels: RNG_CHANNELS.iter().map(|s| (*s).into()).collect(),
        candidate_decisions: world_decisions
            .into_iter()
            .chain(report.candidate_decisions)
            .collect(),
        failed_constraints: report.failed_constraints,
        repairs: if repaired_fragments {
            world_repairs
                .into_iter()
                .chain(["reconciled:fragment_metadata".into()])
                .collect()
        } else {
            world_repairs
        },
        retries: report.retries,
        stage_timings_micros: metrics.stage_timings_micros.clone(),
        fallback: world_fallback,
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
            kit_id: bundle.presentation_ir.kit_id.clone(),
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
