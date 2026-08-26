//! Versioned contracts and the single-pass generation bundle.
use crate::manifest::ExportSchemas;
use crate::model::{CauseOfLoss, Ship, GENERATOR_VERSION};
use crate::{generate_ship_timed, GenData, GenParams};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

pub const PROCGEN_REQUEST_SCHEMA: &str = "procgen-request-1";
pub const PROCGEN_BUNDLE_SCHEMA: &str = "procgen-bundle-1";
pub const WORLD_IR_SCHEMA: &str = "world-ir-1";
pub const SITE_IR_SCHEMA: &str = "site-ir-1";
pub const GAMEPLAY_IR_SCHEMA: &str = "gameplay-ir-1";
pub const PRESENTATION_IR_SCHEMA: &str = "presentation-ir-1";
pub const GENERATION_TRACE_SCHEMA: &str = "generation-trace-1";
pub const ADAPTIVE_PROPOSAL_SCHEMA: &str = "adaptive-proposal-1";
pub const PLAYER_MODEL_SCHEMA: &str = "player-model-1";
pub const FAILURE_SCHEMA: &str = "procgen-failure-1";

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Domain { World, Site, Gameplay, Presentation }

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SiteRequest {
    pub site_id: String, pub x: i32, pub y: i32, pub archetype_id: String, pub kit_id: String,
    pub intactness_override_bp: Option<u16>, pub cause_of_loss: Option<CauseOfLoss>, pub loot_richness_bp: u16,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PlayerModel { pub schema_version: String, pub signals: Vec<i32> }
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PresentationRequest { pub seed: u64, pub locale: String }
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProcgenRequest {
    pub schema_version: String, pub world_seed: u64, pub site: SiteRequest, pub difficulty_id: String,
    pub player_model: PlayerModel, pub requested_domains: Vec<Domain>, pub generator_version: u32,
    pub content_manifest_hash: String, pub presentation: PresentationRequest,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VersionEnvelope { pub generator_version: u32, pub content_manifest_hash: String, pub export_schemas: ExportSchemas }

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorldIR { pub schema_version: String, pub world_seed: u64, pub site_id: String, pub x: i32, pub y: i32, pub archetype_id: String }
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SiteIR { pub schema_version: String, pub ship: Ship }
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GameplayIR { pub schema_version: String, pub legacy_slice: Value }
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PresentationIR { pub schema_version: String, pub kit_id: String, pub locale: String, pub seed: u64, pub approved_bindings: BTreeMap<String, String> }

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct GenerationTrace {
    pub schema_version: String, pub rng_channels: Vec<String>, pub candidate_decisions: Vec<String>,
    pub failed_constraints: Vec<String>, pub repairs: Vec<String>, pub retries: Vec<String>,
    pub fallback: Option<String>, pub stage_timings_micros: BTreeMap<String, u128>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct GenerationMetrics { pub pipeline_executions: u32, pub room_count: u32, pub entity_count: u32, pub structural_placement_count: u32, pub stage_timings_micros: BTreeMap<String, u128> }
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProcgenBundle {
    pub schema_version: String, pub version: VersionEnvelope, pub request: ProcgenRequest,
    pub world_ir: WorldIR, pub site_ir: SiteIR, pub gameplay_ir: GameplayIR, pub presentation_ir: PresentationIR,
    pub semantic_hash: String, pub metrics: GenerationMetrics, pub trace: GenerationTrace,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProcgenFailureCode { InvalidRequest, UnsupportedSchema, UnsupportedDomain, GeneratorContentMismatch, GenerationFailure, ValidationFailure, FallbackFailure, AdapterFailure, ManifestFailure, Capacity, Overload, Cancellation, Timeout, InternalFailure }
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProcgenFailure { pub schema_version: String, pub code: ProcgenFailureCode, pub stage: String, pub message: String, pub retryable: bool, pub fallback_id: Option<String> }

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AdaptiveAction { NoOp, SelectCandidate { candidate_id: String }, AdjustEncounter { encounter_id: String, pacing_delta: i32 } }
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdaptiveProposal { pub schema_version: String, pub score: i32, pub rationale_codes: Vec<String>, pub confidence_bp: u16, pub rule_model_version: String, pub action: AdaptiveAction }

#[derive(Debug, thiserror::Error)]
pub enum ProcgenError { #[error("contract JSON parse failed: {0}")] Json(#[from] serde_json::Error), #[error("unknown schema major: {0}")] UnknownSchemaMajor(String), #[error("invalid request field: {0}")] InvalidRequest(&'static str), #[error("generation failed: {0}")] Generation(String) }

impl ProcgenRequest {
    pub fn from_json(json: &str) -> Result<Self, ProcgenError> {
        let value: Value = serde_json::from_str(json)?;
        if let Some(schema) = value.get("schema_version").and_then(Value::as_str) { check_schema(schema, PROCGEN_REQUEST_SCHEMA)?; }
        let req: Self = serde_json::from_value(value)?; req.validate()?; Ok(req)
    }
    pub fn validate(&self) -> Result<(), ProcgenError> {
        check_schema(&self.schema_version, PROCGEN_REQUEST_SCHEMA)?;
        if self.generator_version != GENERATOR_VERSION { return Err(ProcgenError::InvalidRequest("generator_version")); }
        if self.site.site_id.is_empty() || self.site.archetype_id.is_empty() || self.site.kit_id.is_empty() || self.difficulty_id.is_empty() { return Err(ProcgenError::InvalidRequest("identity")); }
        if self.site.intactness_override_bp.map_or(false, |v| v > 10_000) || self.site.loot_richness_bp > 30_000 { return Err(ProcgenError::InvalidRequest("bounds")); }
        check_schema(&self.player_model.schema_version, PLAYER_MODEL_SCHEMA)?;
        if self.requested_domains.is_empty() || self.requested_domains.iter().any(|d| !matches!(d, Domain::World | Domain::Site | Domain::Gameplay | Domain::Presentation)) { return Err(ProcgenError::InvalidRequest("requested_domains")); }
        if !is_sha256(&self.content_manifest_hash) { return Err(ProcgenError::InvalidRequest("content_manifest_hash")); }
        Ok(())
    }
}

pub fn generate_bundle(request: ProcgenRequest, data: &GenData) -> Result<ProcgenBundle, ProcgenFailure> {
    request.validate().map_err(|e| failure(ProcgenFailureCode::InvalidRequest, "request", e.to_string(), false))?;
    let params = GenParams { archetype_id: request.site.archetype_id.clone(), intactness_override: request.site.intactness_override_bp, cause_override: request.site.cause_of_loss, loot_richness: request.site.loot_richness_bp };
    let report = generate_ship_timed(request.world_seed, &params, data).map_err(|e| failure(ProcgenFailureCode::GenerationFailure, "generation", e.to_string(), true))?;
    let ship = report.ship;
    let legacy_slice = crate::structural::export::to_gameplay_slice_json(&ship);
    let world_ir = WorldIR { schema_version: WORLD_IR_SCHEMA.into(), world_seed: request.world_seed, site_id: request.site.site_id.clone(), x: request.site.x, y: request.site.y, archetype_id: request.site.archetype_id.clone() };
    let site_ir = SiteIR { schema_version: SITE_IR_SCHEMA.into(), ship: ship.clone() };
    let gameplay_ir = GameplayIR { schema_version: GAMEPLAY_IR_SCHEMA.into(), legacy_slice };
    let presentation_ir = PresentationIR { schema_version: PRESENTATION_IR_SCHEMA.into(), kit_id: request.site.kit_id.clone(), locale: request.presentation.locale.clone(), seed: request.presentation.seed, approved_bindings: BTreeMap::new() };
    let version = VersionEnvelope { generator_version: request.generator_version, content_manifest_hash: request.content_manifest_hash.clone(), export_schemas: ExportSchemas::v1() };
    let metrics = GenerationMetrics { pipeline_executions: 1, room_count: ship.room_graph.nodes.len() as u32, entity_count: ship.entities.len() as u32, structural_placement_count: ship.plan.placements.len() as u32, stage_timings_micros: report.stage_micros.iter().map(|(k,v)| ((*k).into(), *v)).collect() };
    let trace = GenerationTrace { schema_version: GENERATION_TRACE_SCHEMA.into(), rng_channels: vec!["meta".into(), "hull".into(), "template".into(), "topology".into(), "residual_fill".into(), "story".into(), "intact".into(), "damage".into(), "loot".into()], candidate_decisions: report.candidate_decisions, failed_constraints: report.failed_constraints, retries: report.retries, stage_timings_micros: metrics.stage_timings_micros.clone(), ..Default::default() };
    let mut bundle = ProcgenBundle { schema_version: PROCGEN_BUNDLE_SCHEMA.into(), version, request, world_ir, site_ir, gameplay_ir, presentation_ir, semantic_hash: String::new(), metrics, trace };
    bundle.semantic_hash = semantic_hash(&bundle).map_err(|e| failure(ProcgenFailureCode::InternalFailure, "hash", e.to_string(), false))?; Ok(bundle)
}

pub fn semantic_hash(bundle: &ProcgenBundle) -> Result<String, ProcgenError> {
    let mut projection = Map::new(); projection.insert("version".into(), serde_json::to_value(&bundle.version)?); projection.insert("request".into(), mechanical_request(&bundle.request)); projection.insert("world_ir".into(), serde_json::to_value(&bundle.world_ir)?); projection.insert("site_ir".into(), serde_json::to_value(&bundle.site_ir)?); projection.insert("gameplay_ir".into(), serde_json::to_value(&bundle.gameplay_ir)?);
    let bytes = serde_json::to_vec(&canonical(Value::Object(projection)))?; let digest = Sha256::digest(bytes); Ok(digest.iter().map(|b| format!("{b:02x}")).collect())
}
fn mechanical_request(req: &ProcgenRequest) -> Value { let mut v = serde_json::to_value(req).unwrap_or(Value::Null); if let Some(o) = v.as_object_mut() { o.remove("presentation"); } v }
fn canonical(v: Value) -> Value { match v { Value::Object(o) => Value::Object(o.into_iter().map(|(k,v)|(k,canonical(v))).collect()), Value::Array(a) => Value::Array(a.into_iter().map(canonical).collect()), v => v } }
fn check_schema(actual: &str, expected: &str) -> Result<(), ProcgenError> { if actual == expected { Ok(()) } else if actual.starts_with(&expected[..expected.rfind('-').unwrap()+1]) { Err(ProcgenError::UnknownSchemaMajor(actual.into())) } else { Err(ProcgenError::InvalidRequest("schema_version")) } }
fn is_sha256(s: &str) -> bool { s.len() == 64 && s.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) }
fn failure(code: ProcgenFailureCode, stage: &str, message: String, retryable: bool) -> ProcgenFailure { ProcgenFailure { schema_version: FAILURE_SCHEMA.into(), code, stage: stage.into(), message, retryable, fallback_id: None } }
