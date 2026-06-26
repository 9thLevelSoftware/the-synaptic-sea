extends RefCounted
class_name BiomeProfile

# BiomeProfile — pure data class describing a Synapse Sea biome and
# its multipliers on hazard density, loot quality, and encounter
# density. Loads from a JSON file or Dictionary and exposes
# modifier(dial) -> float plus a deterministic biome selector.
#
# JSON schema (any field may be omitted; defaults apply):
#   {
#     "id": "abyssal_synapse_sea",
#     "description": "Deep-sea baseline",
#     "hazard_modifier": 1.0,
#     "loot_quality_modifier": 1.0,
#     "encounter_density_modifier": 1.0,
#     "ambient_color": [r, g, b],          # 0..1 floats
#     "ambient_intensity": 1.0,
#     "hazard_overrides": { "fire": 0.8 },
#     "encounter_table_id": "biomatter_lurker",
#     "loot_table_overrides": { "cargo": "biomatter_cargo" }
#   }
#
# All modifiers are stored as floats; the composition with
# DifficultyProfile happens in DifficultyProfile.combined_modifier.

const DIAL_HAZARD: String = "hazard_modifier"
const DIAL_LOOT: String = "loot_quality_modifier"
const DIAL_ENCOUNTER: String = "encounter_density_modifier"
const DIAL_AMBIENT: String = "ambient_intensity"

const ALL_DIALS: Array[String] = [
	DIAL_HAZARD, DIAL_LOOT, DIAL_ENCOUNTER, DIAL_AMBIENT,
]

const FALLBACK_AMBIENT_COLOR: Array = [0.6, 0.65, 0.75]

var id: String = ""
var description: String = ""
var hazard_modifier: float = 1.0
var loot_quality_modifier: float = 1.0
var encounter_density_modifier: float = 1.0
var ambient_color: Array = FALLBACK_AMBIENT_COLOR.duplicate()
var ambient_intensity: float = 1.0
var hazard_overrides: Dictionary = {}
var encounter_table_id: String = ""
var loot_table_overrides: Dictionary = {}


# Builds a BiomeProfile from a Dictionary (the parsed JSON content).
# Falls back to defaults for every missing field so a partial
# biome JSON never crashes the loader. Returns a RefCounted.
static func from_dict(data: Dictionary) -> RefCounted:
	var script: GDScript = load("res://scripts/procgen/biome_profile.gd")
	var biome: RefCounted = script.new()
	if data == null:
		biome.id = "unknown"
		return biome
	biome.id = str(data.get("id", "unknown"))
	biome.description = str(data.get("description", ""))
	biome.hazard_modifier = _safe_float(data.get("hazard_modifier", 1.0), 1.0)
	biome.loot_quality_modifier = _safe_float(data.get("loot_quality_modifier", 1.0), 1.0)
	biome.encounter_density_modifier = _safe_float(data.get("encounter_density_modifier", 1.0), 1.0)
	biome.ambient_intensity = _safe_float(data.get("ambient_intensity", 1.0), 1.0)

	var ambient_raw: Variant = data.get("ambient_color", [])
	if ambient_raw is Array and (ambient_raw as Array).size() >= 3:
		biome.ambient_color = [
			_safe_float((ambient_raw as Array)[0], 0.6),
			_safe_float((ambient_raw as Array)[1], 0.65),
			_safe_float((ambient_raw as Array)[2], 0.75),
		]

	var overrides_raw: Variant = data.get("hazard_overrides", {})
	if overrides_raw is Dictionary:
		for k in (overrides_raw as Dictionary).keys():
			biome.hazard_overrides[str(k)] = _safe_float((overrides_raw as Dictionary)[k], 1.0)

	var loot_raw: Variant = data.get("loot_table_overrides", {})
	if loot_raw is Dictionary:
		for k in (loot_raw as Dictionary).keys():
			biome.loot_table_overrides[str(k)] = str((loot_raw as Dictionary)[k])

	biome.encounter_table_id = str(data.get("encounter_table_id", ""))
	return biome


# Loads a BiomeProfile from a JSON file at `abs_path`. Returns null
# on parse error or missing file (the loader logs a warning and
# the caller can fall back to the default biome).
static func from_file(abs_path: String) -> RefCounted:
	if not FileAccess.file_exists(abs_path):
		return null
	var text: String = FileAccess.get_file_as_string(abs_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return from_dict(parsed)


# Returns the modifier value for `dial`. Unknown dial returns 1.0.
func modifier(dial: String) -> float:
	match dial:
		DIAL_HAZARD: return hazard_modifier
		DIAL_LOOT: return loot_quality_modifier
		DIAL_ENCOUNTER: return encounter_density_modifier
		DIAL_AMBIENT: return ambient_intensity
		_: return 1.0


# Returns the per-hazard override multiplier for `hazard_id`. If no
# override is registered, returns 1.0. The override is applied AFTER
# the base hazard_modifier in DifficultyProfile.combined_modifier().
func hazard_override(hazard_id: String) -> float:
	if hazard_overrides.has(hazard_id):
		return float(hazard_overrides[hazard_id])
	return 1.0


# Returns the loot table override id for `role`. Empty string means
# the role uses the default loot table.
func loot_table_for_role(role: String) -> String:
	if loot_table_overrides.has(role):
		return str(loot_table_overrides[role])
	return ""


# Returns the serialized form for save/load.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"description": description,
		"hazard_modifier": hazard_modifier,
		"loot_quality_modifier": loot_quality_modifier,
		"encounter_density_modifier": encounter_density_modifier,
		"ambient_color": ambient_color.duplicate(),
		"ambient_intensity": ambient_intensity,
		"hazard_overrides": hazard_overrides.duplicate(),
		"encounter_table_id": encounter_table_id,
		"loot_table_overrides": loot_table_overrides.duplicate(),
	}


# Deterministic biome selection. Given `seed_value`, returns one of
# the supplied `biome_ids`. Same seed always returns the same id.
static func select_biome(seed_value: int, biome_ids: Array[String]) -> String:
	if biome_ids.is_empty():
		return ""
	if biome_ids.size() == 1:
		return biome_ids[0]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(seed_value) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1
	var idx: int = rng.randi_range(0, biome_ids.size() - 1)
	return biome_ids[idx]


# --- Internal ---

static func _safe_float(v: Variant, fallback: float) -> float:
	if v == null:
		return fallback
	if v is float or v is int:
		return float(v)
	if v is String:
		var parsed: float = float(v)
		if is_nan(parsed) or is_inf(parsed):
			return fallback
		return parsed
	return fallback
