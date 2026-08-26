//! Authored, deterministic encounter composition for GameplayIR-2.

use crate::creature::{CreatureBlueprint, CreatureCatalogue, ThreatRole, MAX_CELLS};
use crate::player_model::{PlayerModelV2, PLAYER_SIGNAL_BASELINE_BP};
use crate::rng::stable_index;
use crate::site::{validate_site_for_request, LosPair, SiteIR, SpatialAnnotation};
use crate::structural::plan::Cell;
use crate::world::{WorldGenerationRequest, WorldKey, PROCGEN_GENERATOR_VERSION};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

pub const ENCOUNTER_CATALOGUE_SCHEMA: &str = "encounter-catalogue-2";
pub const ENCOUNTER_OUTPUT_SCHEMA: &str = "encounter-output-2";
pub const ENCOUNTER_RULES_VERSION: &str = "encounter-rules-2";
pub const COMBAT_SIMULATION_REQUEST_SCHEMA: &str = "combat-simulation-request-1";
pub const COMBAT_SIMULATION_RESULT_SCHEMA: &str = "combat-simulation-result-1";
pub const ENCOUNTER_RNG_CHANNELS: [&str; 3] = [
    "gameplay.encounter_candidate",
    "gameplay.encounter_faction",
    "gameplay.encounter_reward",
];

const MAX_FACTIONS: usize = 16;
const MAX_DIFFICULTIES: usize = 3;
const MAX_REWARD_TIERS: usize = 16;
const MAX_TRACE_RECORDS: usize = 128;
const MAX_SCANNED_CANDIDATES: usize = 16_384;
const MAX_COMBAT_ROUNDS: u16 = 128;
const MAX_COMBAT_THREAT: u32 = 100_000;
const MAX_COMBAT_GUARD: u32 = 1_000_000;
const MAX_LOOT_RICHNESS_BP: u16 = 30_000;
const MAX_CONTEXT_BUDGET: u32 = 100_000;

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, Ord, PartialOrd, Serialize, Deserialize, JsonSchema,
)]
#[serde(rename_all = "snake_case")]
pub enum DifficultyBand {
    Standard,
    Hardened,
    DeepDive,
}

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, Ord, PartialOrd, Serialize, Deserialize, JsonSchema,
)]
#[serde(rename_all = "snake_case")]
pub enum EncounterRationale {
    Accepted,
    IncompatibleFaction,
    IncompatibleRole,
    ProtectedRoom,
    ProtectedCell,
    NoClearance,
    FootprintOutOfRoom,
    Occupied,
    NavigationUnreachable,
    ExposedLos,
    NoCover,
    ThreatBudgetExceeded,
    PerformanceBudgetExceeded,
    EconomyBudgetExceeded,
    GroupCapExceeded,
    InstanceCapExceeded,
    NoFairSpawn,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct FactionRule {
    pub id: String,
    pub roles: Vec<ThreatRole>,
    pub ability_ids: Vec<String>,
    pub blueprint_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct DifficultyBudget {
    pub id: DifficultyBand,
    pub threat_budget: u32,
    pub performance_budget: u32,
    pub economy_budget: u32,
    pub group_cap: u16,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EncounterCatalogue {
    pub schema_version: String,
    pub rules_version: String,
    pub factions: Vec<FactionRule>,
    pub difficulty: Vec<DifficultyBudget>,
    pub max_candidates: u16,
    pub max_decisions: u16,
    pub safe_empty_fallback_id: String,
    pub reward_values: Vec<u16>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EncounterGenerationContext {
    pub request: WorldGenerationRequest,
    pub difficulty_id: DifficultyBand,
    pub player: PlayerModelV2,
    pub loot_richness_bp: u16,
    pub threat_cap: u32,
    pub performance_cap: u32,
    pub economy_cap: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EncounterSpawn {
    pub spawn_id: String,
    pub decision_id: String,
    pub reward_source_id: String,
    pub room: u16,
    pub cell: Cell,
    pub blueprint_id: String,
    pub faction_id: String,
    pub threat_role: ThreatRole,
    pub ability_id: String,
    pub threat_cost: u16,
    pub performance_cost: u16,
    pub reward_value: u16,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EncounterCandidate {
    pub candidate_id: String,
    pub channel_id: String,
    pub room: u16,
    pub cell: Cell,
    pub blueprint_id: String,
    pub faction_id: String,
    pub score_bp: u16,
    pub navigation_distance: u16,
    pub has_cover: bool,
    pub accepted: bool,
    pub rationale_codes: Vec<EncounterRationale>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EncounterDecision {
    pub decision_id: String,
    pub channel_id: String,
    pub candidate_id: String,
    pub score_bp: u16,
    pub accepted: bool,
    pub rationale_codes: Vec<EncounterRationale>,
    pub selected_spawn_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EncounterBudgetTrace {
    pub difficulty_id: DifficultyBand,
    pub player_factor_bp: u16,
    pub threat_limit: u32,
    pub performance_limit: u32,
    pub economy_limit: u32,
    pub group_cap: u16,
    pub minimum_reward_value: u16,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EncounterTrace {
    pub rules_version: String,
    pub channel_ids: Vec<String>,
    pub player_values_bp: [u16; 4],
    pub budgets: EncounterBudgetTrace,
    pub candidates: Vec<EncounterCandidate>,
    pub decisions: Vec<EncounterDecision>,
    pub selected_spawn_ids: Vec<String>,
    pub fallback: Option<String>,
    pub fallback_rationale: Option<EncounterRationale>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EncounterGenerationOutcome {
    pub schema_version: String,
    pub composition_id: String,
    pub spawns: Vec<EncounterSpawn>,
    pub total_threat: u32,
    pub total_performance: u32,
    pub total_reward_value: u32,
    pub trace: EncounterTrace,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CombatSimulationRequest {
    pub schema_version: String,
    pub encounter_threat: u32,
    pub player_power_bp: u16,
    pub player_guard: u32,
    pub max_rounds: u16,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CombatSimulationResult {
    pub schema_version: String,
    pub rounds_simulated: u16,
    pub remaining_threat: u32,
    pub remaining_player_guard: u32,
    pub player_prevailed: bool,
}

#[derive(Debug, thiserror::Error, Clone, PartialEq, Eq)]
pub enum EncounterError {
    #[error("invalid encounter content: {0}")]
    Invalid(String),
    #[error("encounter key: {0}")]
    Key(&'static str),
    #[error("encounter validation: {0}")]
    Validation(String),
}

#[derive(Clone)]
struct EvaluatedCandidate {
    record: EncounterCandidate,
    blueprint: CreatureBlueprint,
    footprint: Vec<Cell>,
}

fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 96
        && value.bytes().all(|byte| {
            byte.is_ascii_lowercase()
                || byte.is_ascii_digit()
                || matches!(byte, b':' | b'_' | b'-' | b'.')
        })
}

fn is_lower_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn canonical_strings(values: &[String]) -> bool {
    values.iter().all(|value| valid_id(value)) && values.windows(2).all(|pair| pair[0] < pair[1])
}

fn canonical_roles(values: &[ThreatRole]) -> bool {
    !values.is_empty() && values.windows(2).all(|pair| pair[0] < pair[1])
}

impl EncounterCatalogue {
    pub fn bundled() -> Result<Self, EncounterError> {
        let catalogue: Self =
            serde_json::from_str(include_str!("../assets/gameplay/encounters_v2.json"))
                .map_err(|error| EncounterError::Invalid(error.to_string()))?;
        catalogue.validate()?;
        Ok(catalogue)
    }

    pub fn validate(&self) -> Result<(), EncounterError> {
        let creatures = CreatureCatalogue::bundled()
            .map_err(|error| EncounterError::Invalid(error.to_string()))?;
        creatures
            .validate()
            .map_err(|error| EncounterError::Invalid(error.to_string()))?;
        self.validate_with_creatures(&creatures)
    }

    fn validate_with_creatures(&self, creatures: &CreatureCatalogue) -> Result<(), EncounterError> {
        if self.schema_version != ENCOUNTER_CATALOGUE_SCHEMA
            || self.rules_version != ENCOUNTER_RULES_VERSION
            || self.factions.is_empty()
            || self.factions.len() > MAX_FACTIONS
            || self.difficulty.len() != MAX_DIFFICULTIES
            || self.max_candidates == 0
            || usize::from(self.max_candidates) > MAX_TRACE_RECORDS
            || self.max_decisions != self.max_candidates
            || !valid_id(&self.safe_empty_fallback_id)
            || self.reward_values.is_empty()
            || self.reward_values.len() > MAX_REWARD_TIERS
            || self.reward_values.contains(&0)
            || self.reward_values.windows(2).any(|pair| pair[0] >= pair[1])
        {
            return Err(EncounterError::Invalid("catalogue_bounds".into()));
        }

        if self
            .factions
            .windows(2)
            .any(|pair| pair[0].id >= pair[1].id)
        {
            return Err(EncounterError::Invalid("faction_order".into()));
        }

        let blueprint_by_id: BTreeMap<_, _> = creatures
            .fallbacks
            .iter()
            .map(|blueprint| (blueprint.id.as_str(), blueprint))
            .collect();
        let ability_ids: BTreeSet<_> = creatures
            .abilities
            .iter()
            .map(|ability| ability.id.as_str())
            .collect();
        let mut covered_blueprints = BTreeSet::new();
        for faction in &self.factions {
            if !valid_id(&faction.id)
                || !canonical_roles(&faction.roles)
                || faction.ability_ids.is_empty()
                || faction.blueprint_ids.is_empty()
                || !canonical_strings(&faction.ability_ids)
                || !canonical_strings(&faction.blueprint_ids)
                || faction
                    .ability_ids
                    .iter()
                    .any(|ability| !ability_ids.contains(ability.as_str()))
            {
                return Err(EncounterError::Invalid(format!("faction:{}", faction.id)));
            }
            for blueprint_id in &faction.blueprint_ids {
                let blueprint = blueprint_by_id.get(blueprint_id.as_str()).ok_or_else(|| {
                    EncounterError::Invalid(format!("faction_blueprint:{blueprint_id}"))
                })?;
                if !faction.roles.contains(&blueprint.threat_role)
                    || !faction.ability_ids.contains(&blueprint.ability_id)
                {
                    return Err(EncounterError::Invalid(format!(
                        "faction_compatibility:{}",
                        faction.id
                    )));
                }
                covered_blueprints.insert(blueprint.id.as_str());
            }
            if faction.ability_ids.iter().any(|ability_id| {
                !faction.blueprint_ids.iter().any(|blueprint_id| {
                    blueprint_by_id
                        .get(blueprint_id.as_str())
                        .is_some_and(|blueprint| blueprint.ability_id == *ability_id)
                })
            }) {
                return Err(EncounterError::Invalid(format!(
                    "unused_faction_ability:{}",
                    faction.id
                )));
            }
        }
        if covered_blueprints.len() != creatures.fallbacks.len() {
            return Err(EncounterError::Invalid("blueprint_coverage".into()));
        }

        let expected_difficulties = [
            DifficultyBand::Standard,
            DifficultyBand::Hardened,
            DifficultyBand::DeepDive,
        ];
        for (budget, expected) in self.difficulty.iter().zip(expected_difficulties) {
            if budget.id != expected
                || budget.threat_budget == 0
                || budget.performance_budget == 0
                || budget.economy_budget == 0
                || budget.group_cap == 0
                || budget.threat_budget > MAX_CONTEXT_BUDGET
                || budget.performance_budget > MAX_CONTEXT_BUDGET
                || budget.economy_budget > MAX_CONTEXT_BUDGET
                || budget.group_cap > creatures.rules.max_instances
            {
                return Err(EncounterError::Invalid("difficulty_budget".into()));
            }
        }
        if self.difficulty.windows(2).any(|pair| {
            pair[0].threat_budget >= pair[1].threat_budget
                || pair[0].performance_budget >= pair[1].performance_budget
                || pair[0].economy_budget >= pair[1].economy_budget
                || pair[0].group_cap >= pair[1].group_cap
        }) {
            return Err(EncounterError::Invalid("difficulty_order".into()));
        }
        Ok(())
    }
}

fn validate_context(context: &EncounterGenerationContext) -> Result<(), EncounterError> {
    context
        .player
        .validate()
        .map_err(|error| EncounterError::Invalid(error.to_string()))?;
    if context.request.platform_version != PROCGEN_GENERATOR_VERSION
        || !valid_id(&context.request.site_id)
        || !valid_id(&context.request.archetype_id)
        || !is_lower_sha256(&context.request.content_manifest_hash)
        || context.loot_richness_bp > MAX_LOOT_RICHNESS_BP
        || context.threat_cap == 0
        || context.performance_cap == 0
        || context.economy_cap == 0
        || context.threat_cap > MAX_CONTEXT_BUDGET
        || context.performance_cap > MAX_CONTEXT_BUDGET
        || context.economy_cap > MAX_CONTEXT_BUDGET
    {
        return Err(EncounterError::Invalid("context".into()));
    }
    encounter_key(context, ENCOUNTER_RNG_CHANNELS[0], 0)?;
    Ok(())
}

fn validate_inputs(
    context: &EncounterGenerationContext,
    catalogue: &EncounterCatalogue,
    site: &SiteIR,
    blueprints: &[CreatureBlueprint],
) -> Result<CreatureCatalogue, EncounterError> {
    validate_context(context)?;
    validate_site_for_request(site, &context.request)
        .map_err(|error| EncounterError::Validation(error.to_string()))?;
    let creatures =
        CreatureCatalogue::bundled().map_err(|error| EncounterError::Invalid(error.to_string()))?;
    creatures
        .validate()
        .map_err(|error| EncounterError::Invalid(error.to_string()))?;
    catalogue.validate_with_creatures(&creatures)?;
    if blueprints.is_empty()
        || blueprints.len() > crate::creature::MAX_CANDIDATES
        || blueprints.windows(2).any(|pair| pair[0].id >= pair[1].id)
    {
        return Err(EncounterError::Invalid("blueprint_set".into()));
    }
    let validation_context = crate::creature::CreatureGenerationContext {
        request: context.request.clone(),
        min_clearance: 0,
        max_footprint_cells: u16::try_from(MAX_CELLS)
            .map_err(|_| EncounterError::Invalid("footprint_capacity".into()))?,
        threat_cap: creatures.rules.max_threat,
        performance_cap: creatures.rules.max_performance,
        instance_cap: creatures.rules.max_instances,
    };
    for blueprint in blueprints {
        creatures
            .validate_blueprint(blueprint, &validation_context)
            .map_err(|error| EncounterError::Invalid(error.to_string()))?;
        if !catalogue.factions.iter().any(|faction| {
            faction.blueprint_ids.contains(&blueprint.id)
                && faction.roles.contains(&blueprint.threat_role)
                && faction.ability_ids.contains(&blueprint.ability_id)
        }) {
            return Err(EncounterError::Invalid(format!(
                "blueprint_faction:{}",
                blueprint.id
            )));
        }
    }
    Ok(creatures)
}

fn encounter_key(
    context: &EncounterGenerationContext,
    channel: &str,
    sub_index: u32,
) -> Result<u64, EncounterError> {
    WorldKey {
        world_seed: context.request.world_seed,
        platform_version: context.request.platform_version,
        content_manifest_hash: context.request.content_manifest_hash.clone(),
        site_id: context.request.site_id.clone(),
        x: context.request.x,
        y: context.request.y,
        domain: "gameplay".into(),
        channel: channel.into(),
        sub_index,
    }
    .seed()
    .map_err(EncounterError::Key)
}

fn player_factor_bp(values: [u16; 4]) -> u16 {
    let baseline = i64::from(PLAYER_SIGNAL_BASELINE_BP);
    let mastery = i64::from(values[0]) - baseline;
    let damage_pressure = i64::from(values[1]) - baseline;
    let resource_pressure = i64::from(values[2]) - baseline;
    let objective_pace = i64::from(values[3]) - baseline;
    let adjustment = mastery - damage_pressure / 2 - resource_pressure / 2 + objective_pace / 4;
    u16::try_from((10_000i64 + adjustment).clamp(7_500, 12_500)).unwrap_or(10_000)
}

fn budget_trace(
    context: &EncounterGenerationContext,
    budget: &DifficultyBudget,
    minimum_reward_value: u16,
) -> Result<EncounterBudgetTrace, EncounterError> {
    let factor = player_factor_bp(context.player.normalized_values());
    let adjusted_threat = u64::from(budget.threat_budget)
        .checked_mul(u64::from(factor))
        .and_then(|value| value.checked_div(10_000))
        .and_then(|value| u32::try_from(value).ok())
        .ok_or_else(|| EncounterError::Invalid("threat_budget_overflow".into()))?;
    let economy_factor = 30_000u64 + u64::from(context.loot_richness_bp);
    let adjusted_economy = u64::from(budget.economy_budget)
        .checked_mul(economy_factor)
        .and_then(|value| value.checked_div(30_000))
        .and_then(|value| u32::try_from(value).ok())
        .ok_or_else(|| EncounterError::Invalid("economy_budget_overflow".into()))?;
    Ok(EncounterBudgetTrace {
        difficulty_id: context.difficulty_id,
        player_factor_bp: factor,
        threat_limit: adjusted_threat.min(context.threat_cap),
        performance_limit: budget.performance_budget.min(context.performance_cap),
        economy_limit: adjusted_economy.min(context.economy_cap),
        group_cap: budget.group_cap,
        minimum_reward_value,
    })
}

fn navigation_distances(site: &SiteIR) -> BTreeMap<u16, u16> {
    let mut distances = BTreeMap::from([(site.ship.entry_room, 0u16)]);
    let mut queue = VecDeque::from([site.ship.entry_room]);
    while let Some(room) = queue.pop_front() {
        let next_distance = distances.get(&room).copied().unwrap_or(0).saturating_add(1);
        for edge in &site.navigation.edges {
            let next = if edge.from_room == room {
                Some(edge.to_room)
            } else if edge.to_room == room {
                Some(edge.from_room)
            } else {
                None
            };
            if let Some(next) = next {
                if let std::collections::btree_map::Entry::Vacant(entry) = distances.entry(next) {
                    entry.insert(next_distance);
                    queue.push_back(next);
                }
            }
        }
    }
    distances
}

fn checked_footprint(
    origin: Cell,
    blueprint: &CreatureBlueprint,
    creatures: &CreatureCatalogue,
) -> Option<Vec<Cell>> {
    let footprint = creatures
        .footprints
        .iter()
        .find(|footprint| footprint.id == blueprint.footprint_id)?;
    footprint
        .cells
        .iter()
        .map(|offset| {
            Some(Cell::new(
                origin.deck,
                origin.x.checked_add(i32::from(offset.x))?,
                origin.y.checked_add(i32::from(offset.y))?,
            ))
        })
        .collect()
}

fn pair_connects(pair: &LosPair, left: Cell, right: Cell) -> bool {
    (pair.a == left && pair.b == right) || (pair.a == right && pair.b == left)
}

fn exposed_to_protected(
    annotation: &SpatialAnnotation,
    footprint: &[Cell],
    protected_cells: &BTreeSet<Cell>,
) -> bool {
    footprint.iter().any(|cell| {
        protected_cells.iter().any(|protected| {
            cell.deck == protected.deck
                && annotation
                    .los_pairs
                    .iter()
                    .any(|pair| pair_connects(pair, *cell, *protected))
        })
    })
}

fn compatible_factions<'a>(
    catalogue: &'a EncounterCatalogue,
    blueprint: &CreatureBlueprint,
) -> Vec<&'a FactionRule> {
    catalogue
        .factions
        .iter()
        .filter(|faction| {
            faction.blueprint_ids.contains(&blueprint.id)
                && faction.roles.contains(&blueprint.threat_role)
                && faction.ability_ids.contains(&blueprint.ability_id)
        })
        .collect()
}

fn build_candidates(
    context: &EncounterGenerationContext,
    catalogue: &EncounterCatalogue,
    site: &SiteIR,
    blueprints: &[CreatureBlueprint],
    creatures: &CreatureCatalogue,
) -> Result<Vec<EvaluatedCandidate>, EncounterError> {
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
    let distances = navigation_distances(site);
    let annotations: BTreeMap<_, _> = site
        .spatial_annotations
        .rooms
        .iter()
        .map(|annotation| (annotation.room, annotation))
        .collect();
    let mut rooms: Vec<_> = site.ship.topology.rooms.iter().collect();
    rooms.sort_by_key(|room| room.id);
    let mut ordered_blueprints: Vec<_> = blueprints.iter().collect();
    ordered_blueprints.sort_by(|left, right| left.id.cmp(&right.id));
    let mut candidates = Vec::new();
    let mut raw_index = 0usize;

    for room in rooms {
        let mut cells = room.cells.clone();
        cells.sort();
        let room_cells: BTreeSet<_> = cells.iter().copied().collect();
        let annotation = annotations
            .get(&room.id)
            .copied()
            .ok_or_else(|| EncounterError::Validation("missing spatial annotation".into()))?;
        for cell in cells {
            for blueprint in &ordered_blueprints {
                if raw_index >= MAX_SCANNED_CANDIDATES {
                    return Err(EncounterError::Invalid("candidate_scan_cap".into()));
                }
                let sub_index = u32::try_from(raw_index)
                    .map_err(|_| EncounterError::Invalid("candidate_index".into()))?;
                let factions = compatible_factions(catalogue, blueprint);
                if factions.is_empty() {
                    return Err(EncounterError::Invalid(format!(
                        "candidate_faction:{}",
                        blueprint.id
                    )));
                }
                let faction_seed = encounter_key(context, ENCOUNTER_RNG_CHANNELS[1], sub_index)?;
                let faction_index = stable_index(faction_seed, factions.len())
                    .ok_or_else(|| EncounterError::Invalid("faction_index".into()))?;
                let faction = factions[faction_index];
                let footprint = checked_footprint(cell, blueprint, creatures).unwrap_or_default();
                let footprint_definition = creatures
                    .footprints
                    .iter()
                    .find(|definition| definition.id == blueprint.footprint_id)
                    .ok_or_else(|| EncounterError::Invalid("footprint_ref".into()))?;
                let navigation_distance = distances.get(&room.id).copied().unwrap_or(u16::MAX);
                let has_cover = footprint
                    .iter()
                    .any(|footprint_cell| annotation.cover_cells.contains(footprint_cell));
                let mut rationale_codes = Vec::new();
                if protected_rooms.contains(&room.id) {
                    rationale_codes.push(EncounterRationale::ProtectedRoom);
                }
                if footprint.is_empty()
                    || !footprint
                        .iter()
                        .all(|footprint_cell| room_cells.contains(footprint_cell))
                {
                    rationale_codes.push(EncounterRationale::FootprintOutOfRoom);
                }
                if footprint
                    .iter()
                    .any(|footprint_cell| protected_cells.contains(footprint_cell))
                {
                    rationale_codes.push(EncounterRationale::ProtectedCell);
                }
                if footprint_definition.clearance < annotation.minimum_clearance {
                    rationale_codes.push(EncounterRationale::NoClearance);
                }
                if navigation_distance == u16::MAX {
                    rationale_codes.push(EncounterRationale::NavigationUnreachable);
                }
                if exposed_to_protected(annotation, &footprint, &protected_cells) {
                    rationale_codes.push(EncounterRationale::ExposedLos);
                }
                if !has_cover && navigation_distance <= 1 {
                    rationale_codes.push(EncounterRationale::NoCover);
                }

                let base_score =
                    encounter_key(context, ENCOUNTER_RNG_CHANNELS[0], sub_index)? % 8_001;
                let cover_bonus = if has_cover { 1_000u64 } else { 0 };
                let distance_bonus = u64::from(navigation_distance.min(5)) * 200;
                let score_bp = u16::try_from(
                    base_score
                        .saturating_add(cover_bonus)
                        .saturating_add(distance_bonus)
                        .min(10_000),
                )
                .map_err(|_| EncounterError::Invalid("candidate_score".into()))?;
                candidates.push(EvaluatedCandidate {
                    record: EncounterCandidate {
                        candidate_id: format!("candidate:{raw_index:05}"),
                        channel_id: ENCOUNTER_RNG_CHANNELS[0].into(),
                        room: room.id,
                        cell,
                        blueprint_id: blueprint.id.clone(),
                        faction_id: faction.id.clone(),
                        score_bp,
                        navigation_distance,
                        has_cover,
                        accepted: false,
                        rationale_codes,
                    },
                    blueprint: (*blueprint).clone(),
                    footprint,
                });
                raw_index = raw_index
                    .checked_add(1)
                    .ok_or_else(|| EncounterError::Invalid("candidate_count".into()))?;
            }
        }
    }
    Ok(candidates)
}

fn desired_reward_index(
    context: &EncounterGenerationContext,
    catalogue: &EncounterCatalogue,
) -> usize {
    let richness_band = usize::from(context.loot_richness_bp / 10_000);
    richness_band.min(catalogue.reward_values.len().saturating_sub(1))
}

fn reward_value(
    context: &EncounterGenerationContext,
    catalogue: &EncounterCatalogue,
    spawn_count: usize,
    economy_limit: u32,
) -> Result<u16, EncounterError> {
    if spawn_count == 0 {
        return Ok(0);
    }
    let count =
        u32::try_from(spawn_count).map_err(|_| EncounterError::Invalid("reward_count".into()))?;
    let desired = desired_reward_index(context, catalogue);
    catalogue.reward_values[..=desired]
        .iter()
        .rev()
        .copied()
        .find(|value| u32::from(*value).saturating_mul(count) <= economy_limit)
        .ok_or_else(|| EncounterError::Invalid("reward_economy".into()))
}

fn generate_unvalidated(
    context: &EncounterGenerationContext,
    catalogue: &EncounterCatalogue,
    site: &SiteIR,
    blueprints: &[CreatureBlueprint],
    creatures: &CreatureCatalogue,
) -> Result<EncounterGenerationOutcome, EncounterError> {
    let difficulty = catalogue
        .difficulty
        .iter()
        .find(|budget| budget.id == context.difficulty_id)
        .ok_or_else(|| EncounterError::Invalid("difficulty_id".into()))?;
    let minimum_reward = *catalogue
        .reward_values
        .first()
        .ok_or_else(|| EncounterError::Invalid("reward_values".into()))?;
    let budgets = budget_trace(context, difficulty, minimum_reward)?;
    let composition_economy_limit = difficulty.economy_budget.min(context.economy_cap);
    let mut raw_candidates = build_candidates(context, catalogue, site, blueprints, creatures)?;
    let mut eligible = Vec::new();
    let mut rejected = Vec::new();
    for candidate in raw_candidates.drain(..) {
        if candidate.record.rationale_codes.is_empty() {
            eligible.push(candidate);
        } else {
            rejected.push(candidate);
        }
    }
    eligible.sort_by(|left, right| {
        right
            .record
            .score_bp
            .cmp(&left.record.score_bp)
            .then(left.record.candidate_id.cmp(&right.record.candidate_id))
    });
    rejected.sort_by(|left, right| left.record.candidate_id.cmp(&right.record.candidate_id));

    let trace_cap = usize::from(catalogue.max_candidates);
    let mut considered: Vec<_> = eligible.into_iter().take(trace_cap).collect();
    let remaining = trace_cap.saturating_sub(considered.len());
    considered.extend(rejected.into_iter().take(remaining));

    let mut occupied = BTreeSet::new();
    let mut blueprint_counts: BTreeMap<String, u16> = BTreeMap::new();
    let mut total_threat = 0u32;
    let mut total_performance = 0u32;
    let mut spawns = Vec::new();
    let mut candidates = Vec::new();
    let mut decisions = Vec::new();

    for mut candidate in considered {
        let decision_index = decisions.len();
        let decision_id = format!("decision:{decision_index:03}");
        let mut rationale_codes = candidate.record.rationale_codes.clone();
        if rationale_codes.is_empty() {
            let blueprint_count = blueprint_counts
                .get(&candidate.blueprint.id)
                .copied()
                .unwrap_or(0);
            let next_threat = total_threat.checked_add(u32::from(candidate.blueprint.threat_cost));
            let next_performance =
                total_performance.checked_add(u32::from(candidate.blueprint.performance_cost));
            let next_count = spawns.len().checked_add(1);
            let next_minimum_reward = next_count
                .and_then(|count| u32::try_from(count).ok())
                .and_then(|count| count.checked_mul(u32::from(minimum_reward)));
            if candidate
                .footprint
                .iter()
                .any(|cell| occupied.contains(cell))
            {
                rationale_codes.push(EncounterRationale::Occupied);
            } else if spawns.len() >= usize::from(budgets.group_cap) {
                rationale_codes.push(EncounterRationale::GroupCapExceeded);
            } else if blueprint_count >= candidate.blueprint.instance_cap {
                rationale_codes.push(EncounterRationale::InstanceCapExceeded);
            } else if next_threat.is_none_or(|value| value > budgets.threat_limit) {
                rationale_codes.push(EncounterRationale::ThreatBudgetExceeded);
            } else if next_performance.is_none_or(|value| value > budgets.performance_limit) {
                rationale_codes.push(EncounterRationale::PerformanceBudgetExceeded);
            } else if next_minimum_reward.is_none_or(|value| value > composition_economy_limit) {
                rationale_codes.push(EncounterRationale::EconomyBudgetExceeded);
            } else {
                rationale_codes.push(EncounterRationale::Accepted);
            }
        }
        let accepted = rationale_codes == [EncounterRationale::Accepted];
        let selected_spawn_id = accepted.then(|| format!("spawn:{:03}", spawns.len()));
        candidate.record.accepted = accepted;
        candidate.record.rationale_codes = rationale_codes.clone();
        if accepted {
            occupied.extend(candidate.footprint.iter().copied());
            total_threat = total_threat
                .checked_add(u32::from(candidate.blueprint.threat_cost))
                .ok_or_else(|| EncounterError::Invalid("threat_total".into()))?;
            total_performance = total_performance
                .checked_add(u32::from(candidate.blueprint.performance_cost))
                .ok_or_else(|| EncounterError::Invalid("performance_total".into()))?;
            let count = blueprint_counts
                .entry(candidate.blueprint.id.clone())
                .or_insert(0);
            *count = count
                .checked_add(1)
                .ok_or_else(|| EncounterError::Invalid("instance_total".into()))?;
            let spawn_id = selected_spawn_id.clone().unwrap_or_default();
            let reward_sub_index = u32::try_from(spawns.len())
                .map_err(|_| EncounterError::Invalid("reward_index".into()))?;
            let reward_seed = encounter_key(context, ENCOUNTER_RNG_CHANNELS[2], reward_sub_index)?;
            spawns.push(EncounterSpawn {
                spawn_id,
                decision_id: decision_id.clone(),
                reward_source_id: format!("reward:{reward_seed:016x}"),
                room: candidate.record.room,
                cell: candidate.record.cell,
                blueprint_id: candidate.blueprint.id.clone(),
                faction_id: candidate.record.faction_id.clone(),
                threat_role: candidate.blueprint.threat_role,
                ability_id: candidate.blueprint.ability_id.clone(),
                threat_cost: candidate.blueprint.threat_cost,
                performance_cost: candidate.blueprint.performance_cost,
                reward_value: minimum_reward,
            });
        }
        decisions.push(EncounterDecision {
            decision_id,
            channel_id: "gameplay.encounter_selection".into(),
            candidate_id: candidate.record.candidate_id.clone(),
            score_bp: candidate.record.score_bp,
            accepted,
            rationale_codes,
            selected_spawn_id,
        });
        candidates.push(candidate.record);
    }

    let selected_reward = reward_value(context, catalogue, spawns.len(), budgets.economy_limit)?;
    for spawn in &mut spawns {
        spawn.reward_value = selected_reward;
    }
    let total_reward_value = u32::from(selected_reward)
        .checked_mul(
            u32::try_from(spawns.len())
                .map_err(|_| EncounterError::Invalid("reward_total".into()))?,
        )
        .ok_or_else(|| EncounterError::Invalid("reward_total".into()))?;
    let fallback = spawns
        .is_empty()
        .then(|| catalogue.safe_empty_fallback_id.clone());
    let fallback_rationale = spawns.is_empty().then_some(EncounterRationale::NoFairSpawn);
    let composition_seed = encounter_key(context, "gameplay.encounter_selection", 0)?;
    let selected_spawn_ids = spawns.iter().map(|spawn| spawn.spawn_id.clone()).collect();
    Ok(EncounterGenerationOutcome {
        schema_version: ENCOUNTER_OUTPUT_SCHEMA.into(),
        composition_id: format!("composition:{composition_seed:016x}"),
        spawns,
        total_threat,
        total_performance,
        total_reward_value,
        trace: EncounterTrace {
            rules_version: catalogue.rules_version.clone(),
            channel_ids: ENCOUNTER_RNG_CHANNELS
                .iter()
                .map(|channel| (*channel).into())
                .collect(),
            player_values_bp: context.player.normalized_values(),
            budgets,
            candidates,
            decisions,
            selected_spawn_ids,
            fallback,
            fallback_rationale,
        },
    })
}

pub fn generate_encounters(
    context: &EncounterGenerationContext,
    catalogue: &EncounterCatalogue,
    site: &SiteIR,
    blueprints: &[CreatureBlueprint],
) -> Result<EncounterGenerationOutcome, EncounterError> {
    let creatures = validate_inputs(context, catalogue, site, blueprints)?;
    let outcome = generate_unvalidated(context, catalogue, site, blueprints, &creatures)?;
    outcome.validate_static(context, catalogue, site, blueprints, &creatures)?;
    Ok(outcome)
}

impl EncounterGenerationOutcome {
    fn validate_static(
        &self,
        context: &EncounterGenerationContext,
        catalogue: &EncounterCatalogue,
        site: &SiteIR,
        blueprints: &[CreatureBlueprint],
        creatures: &CreatureCatalogue,
    ) -> Result<(), EncounterError> {
        if self.schema_version != ENCOUNTER_OUTPUT_SCHEMA
            || !valid_id(&self.composition_id)
            || self.spawns.len() > MAX_TRACE_RECORDS
            || self.trace.rules_version != catalogue.rules_version
            || self.trace.channel_ids
                != ENCOUNTER_RNG_CHANNELS
                    .iter()
                    .map(|channel| (*channel).to_owned())
                    .collect::<Vec<_>>()
            || self.trace.player_values_bp != context.player.normalized_values()
            || self.trace.candidates.len() != self.trace.decisions.len()
            || self.trace.candidates.len() > usize::from(catalogue.max_candidates)
            || self.trace.decisions.len() > usize::from(catalogue.max_decisions)
        {
            return Err(EncounterError::Validation("output_bounds".into()));
        }
        let difficulty = catalogue
            .difficulty
            .iter()
            .find(|budget| budget.id == context.difficulty_id)
            .ok_or_else(|| EncounterError::Validation("difficulty".into()))?;
        let minimum_reward = *catalogue
            .reward_values
            .first()
            .ok_or_else(|| EncounterError::Validation("reward_values".into()))?;
        if self.trace.budgets != budget_trace(context, difficulty, minimum_reward)? {
            return Err(EncounterError::Validation("budget_trace".into()));
        }

        let blueprint_by_id: BTreeMap<_, _> = blueprints
            .iter()
            .map(|blueprint| (blueprint.id.as_str(), blueprint))
            .collect();
        let mut candidate_ids = BTreeSet::new();
        let mut decision_ids = BTreeSet::new();
        for (candidate, decision) in self.trace.candidates.iter().zip(&self.trace.decisions) {
            if !valid_id(&candidate.candidate_id)
                || candidate.channel_id != ENCOUNTER_RNG_CHANNELS[0]
                || !valid_id(&candidate.blueprint_id)
                || !valid_id(&candidate.faction_id)
                || candidate.score_bp > 10_000
                || candidate.rationale_codes.is_empty()
                || !candidate_ids.insert(&candidate.candidate_id)
                || !valid_id(&decision.decision_id)
                || decision.channel_id != "gameplay.encounter_selection"
                || decision.candidate_id != candidate.candidate_id
                || decision.score_bp != candidate.score_bp
                || decision.accepted != candidate.accepted
                || decision.rationale_codes != candidate.rationale_codes
                || !decision_ids.insert(&decision.decision_id)
                || !blueprint_by_id.contains_key(candidate.blueprint_id.as_str())
                || !catalogue
                    .factions
                    .iter()
                    .any(|faction| faction.id == candidate.faction_id)
            {
                return Err(EncounterError::Validation("decision_trace".into()));
            }
            if candidate.accepted {
                if candidate.rationale_codes != [EncounterRationale::Accepted]
                    || decision.selected_spawn_id.is_none()
                {
                    return Err(EncounterError::Validation("accepted_decision".into()));
                }
            } else if decision.selected_spawn_id.is_some()
                || candidate.rationale_codes == [EncounterRationale::Accepted]
            {
                return Err(EncounterError::Validation("rejected_decision".into()));
            }
        }

        let selected_ids: Vec<_> = self
            .spawns
            .iter()
            .map(|spawn| spawn.spawn_id.clone())
            .collect();
        if self.trace.selected_spawn_ids != selected_ids {
            return Err(EncounterError::Validation("selected_spawn_ids".into()));
        }
        let safe_empty = self.spawns.is_empty();
        if safe_empty {
            if self.total_threat != 0
                || self.total_performance != 0
                || self.total_reward_value != 0
                || self.trace.fallback.as_deref() != Some(catalogue.safe_empty_fallback_id.as_str())
                || self.trace.fallback_rationale != Some(EncounterRationale::NoFairSpawn)
            {
                return Err(EncounterError::Validation("safe_empty".into()));
            }
        } else if self.trace.fallback.is_some() || self.trace.fallback_rationale.is_some() {
            return Err(EncounterError::Validation("unexpected_fallback".into()));
        }

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
        let annotations: BTreeMap<_, _> = site
            .spatial_annotations
            .rooms
            .iter()
            .map(|annotation| (annotation.room, annotation))
            .collect();
        let distances = navigation_distances(site);
        let mut occupied = BTreeSet::new();
        let mut spawn_ids = BTreeSet::new();
        let mut reward_source_ids = BTreeSet::new();
        let mut instance_counts: BTreeMap<&str, u16> = BTreeMap::new();
        let mut threat_total = 0u32;
        let mut performance_total = 0u32;
        let mut reward_total = 0u32;
        for spawn in &self.spawns {
            if !valid_id(&spawn.spawn_id)
                || !valid_id(&spawn.decision_id)
                || !valid_id(&spawn.reward_source_id)
                || !spawn_ids.insert(&spawn.spawn_id)
                || !reward_source_ids.insert(&spawn.reward_source_id)
            {
                return Err(EncounterError::Validation("spawn_ids".into()));
            }
            let decision = self
                .trace
                .decisions
                .iter()
                .find(|decision| decision.decision_id == spawn.decision_id)
                .ok_or_else(|| EncounterError::Validation("spawn_decision".into()))?;
            if !decision.accepted
                || decision.selected_spawn_id.as_deref() != Some(spawn.spawn_id.as_str())
            {
                return Err(EncounterError::Validation("spawn_selection".into()));
            }
            let blueprint = blueprint_by_id
                .get(spawn.blueprint_id.as_str())
                .copied()
                .ok_or_else(|| EncounterError::Validation("spawn_blueprint".into()))?;
            let faction = catalogue
                .factions
                .iter()
                .find(|faction| faction.id == spawn.faction_id)
                .ok_or_else(|| EncounterError::Validation("spawn_faction".into()))?;
            if blueprint.threat_role != spawn.threat_role
                || blueprint.ability_id != spawn.ability_id
                || blueprint.threat_cost != spawn.threat_cost
                || blueprint.performance_cost != spawn.performance_cost
                || !faction.blueprint_ids.contains(&blueprint.id)
                || !faction.roles.contains(&blueprint.threat_role)
                || !faction.ability_ids.contains(&blueprint.ability_id)
                || protected_rooms.contains(&spawn.room)
            {
                return Err(EncounterError::Validation("spawn_compatibility".into()));
            }
            let room = site
                .ship
                .topology
                .rooms
                .iter()
                .find(|room| room.id == spawn.room)
                .ok_or_else(|| EncounterError::Validation("spawn_room".into()))?;
            let room_cells: BTreeSet<_> = room.cells.iter().copied().collect();
            let annotation = annotations
                .get(&spawn.room)
                .copied()
                .ok_or_else(|| EncounterError::Validation("spawn_annotation".into()))?;
            let footprint = checked_footprint(spawn.cell, blueprint, creatures)
                .ok_or_else(|| EncounterError::Validation("spawn_footprint".into()))?;
            let footprint_definition = creatures
                .footprints
                .iter()
                .find(|definition| definition.id == blueprint.footprint_id)
                .ok_or_else(|| EncounterError::Validation("spawn_footprint_ref".into()))?;
            let navigation_distance = distances
                .get(&spawn.room)
                .copied()
                .ok_or_else(|| EncounterError::Validation("spawn_navigation".into()))?;
            let has_cover = footprint
                .iter()
                .any(|cell| annotation.cover_cells.contains(cell));
            if footprint_definition.clearance < annotation.minimum_clearance
                || footprint.iter().any(|cell| {
                    !room_cells.contains(cell)
                        || protected_cells.contains(cell)
                        || occupied.contains(cell)
                })
                || exposed_to_protected(annotation, &footprint, &protected_cells)
                || (!has_cover && navigation_distance <= 1)
            {
                return Err(EncounterError::Validation("spawn_fairness".into()));
            }
            occupied.extend(footprint);
            let instance_count = instance_counts.entry(&blueprint.id).or_insert(0);
            *instance_count = instance_count
                .checked_add(1)
                .ok_or_else(|| EncounterError::Validation("instance_total".into()))?;
            if *instance_count > blueprint.instance_cap {
                return Err(EncounterError::Validation("instance_cap".into()));
            }
            if !catalogue.reward_values.contains(&spawn.reward_value) {
                return Err(EncounterError::Validation("reward_value".into()));
            }
            threat_total = threat_total
                .checked_add(u32::from(spawn.threat_cost))
                .ok_or_else(|| EncounterError::Validation("threat_total".into()))?;
            performance_total = performance_total
                .checked_add(u32::from(spawn.performance_cost))
                .ok_or_else(|| EncounterError::Validation("performance_total".into()))?;
            reward_total = reward_total
                .checked_add(u32::from(spawn.reward_value))
                .ok_or_else(|| EncounterError::Validation("reward_total".into()))?;
        }
        let expected_reward = reward_value(
            context,
            catalogue,
            self.spawns.len(),
            self.trace.budgets.economy_limit,
        )?;
        if self
            .spawns
            .iter()
            .any(|spawn| spawn.reward_value != expected_reward)
            || threat_total != self.total_threat
            || performance_total != self.total_performance
            || reward_total != self.total_reward_value
            || self.total_threat > self.trace.budgets.threat_limit
            || self.total_performance > self.trace.budgets.performance_limit
            || self.total_reward_value > self.trace.budgets.economy_limit
            || self.spawns.len() > usize::from(self.trace.budgets.group_cap)
        {
            return Err(EncounterError::Validation("totals_or_caps".into()));
        }
        Ok(())
    }

    pub fn validate(
        &self,
        context: &EncounterGenerationContext,
        catalogue: &EncounterCatalogue,
        site: &SiteIR,
        blueprints: &[CreatureBlueprint],
    ) -> Result<(), EncounterError> {
        let creatures = validate_inputs(context, catalogue, site, blueprints)?;
        self.validate_static(context, catalogue, site, blueprints, &creatures)?;
        let replay = generate_unvalidated(context, catalogue, site, blueprints, &creatures)?;
        if replay != *self {
            return Err(EncounterError::Validation("deterministic_replay".into()));
        }
        Ok(())
    }
}

pub fn simulate_fixed_point(
    request: &CombatSimulationRequest,
) -> Result<CombatSimulationResult, EncounterError> {
    if request.schema_version != COMBAT_SIMULATION_REQUEST_SCHEMA
        || request.encounter_threat == 0
        || request.encounter_threat > MAX_COMBAT_THREAT
        || request.player_power_bp > 10_000
        || request.player_guard == 0
        || request.player_guard > MAX_COMBAT_GUARD
        || request.max_rounds == 0
        || request.max_rounds > MAX_COMBAT_ROUNDS
    {
        return Err(EncounterError::Invalid("combat_simulation_request".into()));
    }
    let mut remaining_threat = request.encounter_threat;
    let mut remaining_guard = request.player_guard;
    let mut rounds_simulated = 0u16;
    let player_damage = u32::from(request.player_power_bp) / 50;
    while rounds_simulated < request.max_rounds && remaining_threat > 0 && remaining_guard > 0 {
        rounds_simulated = rounds_simulated.saturating_add(1);
        remaining_threat = remaining_threat.saturating_sub(player_damage);
        if remaining_threat > 0 {
            let incoming = (remaining_threat / 100).max(1);
            remaining_guard = remaining_guard.saturating_sub(incoming);
        }
    }
    Ok(CombatSimulationResult {
        schema_version: COMBAT_SIMULATION_RESULT_SCHEMA.into(),
        rounds_simulated,
        remaining_threat,
        remaining_player_guard: remaining_guard,
        player_prevailed: remaining_threat == 0 && remaining_guard > 0,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn los_helper_is_symmetric_and_cover_independent() {
        let exposed = Cell::new(0, 0, 0);
        let protected = Cell::new(0, 0, 2);
        let annotation = SpatialAnnotation {
            room: 1,
            minimum_clearance: 1,
            cover_cells: vec![exposed],
            los_pairs: vec![LosPair {
                a: protected,
                b: exposed,
            }],
        };
        assert!(exposed_to_protected(
            &annotation,
            &[exposed],
            &BTreeSet::from([protected])
        ));
    }
}
