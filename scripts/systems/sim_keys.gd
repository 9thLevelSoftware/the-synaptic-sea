extends RefCounted
class_name SimKeys

## Canonical string keys for tick / pipeline context dictionaries.
##
## Pre-polish architecture prerequisite (PKG-A2): replace stringly-typed
## context.get("…") call sites so typos fail at compile-time / review time.
## Values are the historical wire strings — producers may still emit literals
## during the migration window; consumers should import SimKeys.
##
## Scope: pure systems first. Coordinator renames are owned by ShipRuntime /
## Integrator packages so parallel agents do not fight over playable_generated_ship.gd.

# --- Vitals hot path (VitalsState.tick) ---
const MOVING: String = "moving"
const RADIATION_HEALTH_DRAIN: String = "radiation_health_drain"
const ATMOSPHERE_HEALTH_DRAIN: String = "atmosphere_health_drain"
const FIRE_HEALTH_DRAIN: String = "fire_health_drain"
const SANITY_HEALTH_DRAIN: String = "sanity_health_drain"
const ENCUMBRANCE_HEALTH_DRAIN: String = "encumbrance_health_drain"
const TEMPERATURE_THIRST_MULT: String = "temperature_thirst_mult"
const TEMPERATURE_HUNGER_MULT: String = "temperature_hunger_mult"  # PKG-C3.1b cold→hunger
const WOUND_THIRST_MULT: String = "wound_thirst_mult"              # PKG-C3.1b wounds→thirst
const WOUND_HEALTH_DRAIN: String = "wound_health_drain"            # PKG-C3.1b bleed→health
const STATUS_STAMINA_RECOVERY_MULT: String = "status_stamina_recovery_mult"
const SANITY_STAMINA_RECOVERY_MULT: String = "sanity_stamina_recovery_mult"

# --- Threat perception / AI ---
const NOISE_LEVEL: String = "noise_level"
const LIGHT_LEVEL: String = "light_level"
const SIGHT_LEVEL: String = "sight_level"
const CROUCHING: String = "crouching"
const SAME_ROOM: String = "same_room"
const DETECT_THRESHOLD: String = "detect_threshold"
const ROOM_ID: String = "room_id"
const PLAYER_POSITION: String = "player_position"

# --- Ship systems tick contexts ---
const POWERED_RATIO: String = "powered_ratio"
const BREACH_COUNT: String = "breach_count"
const RECYCLED_WATER: String = "recycled_water"
const MANAGER_OPERATIONAL: String = "manager_operational"
const HULL_PENALTY: String = "hull_penalty"
const BREACHED_COMPARTMENTS: String = "breached_compartments"
const DAMAGED_COMPARTMENTS: String = "damaged_compartments"
const SHIP_OXYGEN_PRESENT: String = "ship_oxygen_present"
const ARC_ARCING: String = "arc_arcing"
const CLOSED_LINKS: String = "closed_links"

# --- Sustenance rollup ---
const HYDROPONICS_SUMMARY: String = "hydroponics_summary"
const WATER_RECYCLER_SUMMARY: String = "water_recycler_summary"
const MEALS_ACTIVE: String = "meals_active"

# --- Hallucination director ---
const SANITY: String = "sanity"
const IN_SAFE_ZONE: String = "in_safe_zone"
const ANCHOR_POSITIONS: String = "anchor_positions"

# --- Effect / consumable pipeline object handles ---
const VITALS_STATE: String = "vitals_state"
const SANITY_STATE: String = "sanity_state"
const RADIATION_STATE: String = "radiation_state"
const BODY_TEMPERATURE_STATE: String = "body_temperature_state"
const STATUS_EFFECTS_STATE: String = "status_effects_state"
const EFFECT_DISPATCHER: String = "effect_dispatcher"
const MEDICINE_STATE: String = "medicine_state"
const STIMULANT_STATE: String = "stimulant_state"
const ADDICTION_STATE: String = "addiction_state"
const UTILITY_STATE: String = "utility_state"
const SPOILAGE_STATE: String = "spoilage_state"

# --- Oxygen / field atmosphere ---
const PLAYER_IN_BREACH_ZONE: String = "player_in_breach_zone"

# --- Loot distribution ---
const BIOME_ID: String = "biome_id"
const DEPTH: String = "depth"
const CONTAINER_KIND: String = "container_kind"
const ITEM_DEFINITIONS: String = "item_definitions"
const UNIQUE_STATE: String = "unique_state"
const CONDITION: String = "condition"
const LOOT_QUALITY_MODIFIER: String = "loot_quality_modifier"


## Stable set of vitals hot-path keys (for smokes / contract checks).
static func vitals_hot_path_keys() -> PackedStringArray:
	return PackedStringArray([
		MOVING,
		RADIATION_HEALTH_DRAIN,
		ATMOSPHERE_HEALTH_DRAIN,
		FIRE_HEALTH_DRAIN,
		SANITY_HEALTH_DRAIN,
		ENCUMBRANCE_HEALTH_DRAIN,
		TEMPERATURE_THIRST_MULT,
		TEMPERATURE_HUNGER_MULT,
		WOUND_THIRST_MULT,
		WOUND_HEALTH_DRAIN,
		STATUS_STAMINA_RECOVERY_MULT,
		SANITY_STAMINA_RECOVERY_MULT,
	])


## All documented keys in this catalog (alphabetical-ish by group order above).
static func all_keys() -> PackedStringArray:
	return PackedStringArray([
		MOVING, RADIATION_HEALTH_DRAIN, ATMOSPHERE_HEALTH_DRAIN, FIRE_HEALTH_DRAIN,
		SANITY_HEALTH_DRAIN, ENCUMBRANCE_HEALTH_DRAIN, TEMPERATURE_THIRST_MULT,
		TEMPERATURE_HUNGER_MULT, WOUND_THIRST_MULT, WOUND_HEALTH_DRAIN,
		STATUS_STAMINA_RECOVERY_MULT, SANITY_STAMINA_RECOVERY_MULT,
		NOISE_LEVEL, LIGHT_LEVEL, SIGHT_LEVEL, CROUCHING, SAME_ROOM, DETECT_THRESHOLD,
		ROOM_ID, PLAYER_POSITION,
		POWERED_RATIO, BREACH_COUNT, RECYCLED_WATER, MANAGER_OPERATIONAL, HULL_PENALTY,
		BREACHED_COMPARTMENTS, DAMAGED_COMPARTMENTS, SHIP_OXYGEN_PRESENT, ARC_ARCING, CLOSED_LINKS,
		HYDROPONICS_SUMMARY, WATER_RECYCLER_SUMMARY, MEALS_ACTIVE,
		SANITY, IN_SAFE_ZONE, ANCHOR_POSITIONS,
		VITALS_STATE, SANITY_STATE, RADIATION_STATE, BODY_TEMPERATURE_STATE,
		STATUS_EFFECTS_STATE, EFFECT_DISPATCHER, MEDICINE_STATE, STIMULANT_STATE,
		ADDICTION_STATE, UTILITY_STATE, SPOILAGE_STATE,
		PLAYER_IN_BREACH_ZONE,
		BIOME_ID, DEPTH, CONTAINER_KIND, ITEM_DEFINITIONS, UNIQUE_STATE, CONDITION,
		LOOT_QUALITY_MODIFIER,
	])
