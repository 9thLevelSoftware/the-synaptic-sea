extends RefCounted
class_name DifficultyProfile

# DifficultyProfile — pure data class describing a difficulty preset.
# Loads from a JSON file or Dictionary and exposes
# modifier(dial) -> float plus composition with BiomeProfile.
#
# JSON schema (any field may be omitted; defaults apply):
#   {
#     "id": "standard",
#     "description": "Baseline difficulty",
#     "hazard_modifier": 1.0,
#     "loot_quality_modifier": 1.0,
#     "encounter_density_modifier": 1.0,
#     "ambient_intensity": 1.0
#   }
#
# combined_modifier() multiplies a biome and difficulty modifier and
# clamps the result to [0.0, 3.0] so the composition never produces
# an impossible seed (see RISK-012).

const DIAL_HAZARD: String = "hazard_modifier"
const DIAL_LOOT: String = "loot_quality_modifier"
const DIAL_ENCOUNTER: String = "encounter_density_modifier"
const DIAL_AMBIENT: String = "ambient_intensity"

const ALL_DIALS: Array[String] = [
	DIAL_HAZARD, DIAL_LOOT, DIAL_ENCOUNTER, DIAL_AMBIENT,
]

const COMBINED_MODIFIER_MIN: float = 0.0
const COMBINED_MODIFIER_MAX: float = 3.0

const STANDARD_ID: String = "standard"
const HARDENED_ID: String = "hardened"
const DEEP_DIVE_ID: String = "deep_dive"

var id: String = STANDARD_ID
var description: String = ""
var hazard_modifier: float = 1.0
var loot_quality_modifier: float = 1.0
var encounter_density_modifier: float = 1.0
var ambient_intensity: float = 1.0


static func from_dict(data: Dictionary) -> RefCounted:
	var script: GDScript = load("res://scripts/procgen/difficulty_profile.gd")
	var diff: RefCounted = script.new()
	if data == null:
		return diff
	diff.id = str(data.get("id", STANDARD_ID))
	diff.description = str(data.get("description", ""))
	diff.hazard_modifier = _safe_float(data.get("hazard_modifier", 1.0), 1.0)
	diff.loot_quality_modifier = _safe_float(data.get("loot_quality_modifier", 1.0), 1.0)
	diff.encounter_density_modifier = _safe_float(data.get("encounter_density_modifier", 1.0), 1.0)
	diff.ambient_intensity = _safe_float(data.get("ambient_intensity", 1.0), 1.0)
	return diff


static func from_file(abs_path: String) -> RefCounted:
	if not FileAccess.file_exists(abs_path):
		return null
	var text: String = FileAccess.get_file_as_string(abs_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return from_dict(parsed)


# Canonical difficulty_id -> profile-dict resolution (single source of
# truth; Tranche 4, 2026-07-06 audit). Order: authored JSON override at
# res://data/procgen/difficulty/<id>.json -> built-in presets -> standard.
# ship_layout_generator._resolve_difficulty delegates here and the settings
# menu renders for_id(id).hazard_modifier — keep both consumers in mind
# before changing any value.
static func resolve_dict(difficulty_id: String) -> Dictionary:
	if difficulty_id.is_empty():
		return {"id": STANDARD_ID}
	var rel_path: String = "res://data/procgen/difficulty/" + difficulty_id + ".json"
	if FileAccess.file_exists(rel_path):
		var text: String = FileAccess.get_file_as_string(rel_path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			return parsed
	match difficulty_id:
		HARDENED_ID:
			return {
				"id": HARDENED_ID,
				"hazard_modifier": 1.4,
				"loot_quality_modifier": 0.85,
				"encounter_density_modifier": 1.3,
				"ambient_intensity": 1.0,
			}
		DEEP_DIVE_ID:
			return {
				"id": DEEP_DIVE_ID,
				"hazard_modifier": 1.7,
				"loot_quality_modifier": 1.1,
				"encounter_density_modifier": 1.6,
				"ambient_intensity": 1.0,
			}
		_:
			return {
				"id": STANDARD_ID,
				"hazard_modifier": 1.0,
				"loot_quality_modifier": 1.0,
				"encounter_density_modifier": 1.0,
				"ambient_intensity": 1.0,
			}


# Convenience object form of resolve_dict() for consumers that want the
# dials directly (e.g. the settings menu's difficulty line).
static func for_id(difficulty_id: String) -> RefCounted:
	return from_dict(resolve_dict(difficulty_id))


# Returns the modifier value for `dial`. Unknown dial returns 1.0.
func modifier(dial: String) -> float:
	match dial:
		DIAL_HAZARD: return hazard_modifier
		DIAL_LOOT: return loot_quality_modifier
		DIAL_ENCOUNTER: return encounter_density_modifier
		DIAL_AMBIENT: return ambient_intensity
		_: return 1.0


# Returns `biome.modifier(dial) * self.modifier(dial)`, clamped to
# `[COMBINED_MODIFIER_MIN, COMBINED_MODIFIER_MAX]`. Accepts either a
# BiomeProfile instance or any RefCounted with a `modifier(dial)`
# method; null biome is treated as identity (1.0).
static func combined_modifier(biome, difficulty, dial: String) -> float:
	var b: float = 1.0
	if biome != null and biome.has_method("modifier"):
		b = float(biome.modifier(dial))
	var d: float = 1.0
	if difficulty != null and difficulty.has_method("modifier"):
		d = float(difficulty.modifier(dial))
	var combined: float = b * d
	if combined < COMBINED_MODIFIER_MIN:
		combined = COMBINED_MODIFIER_MIN
	if combined > COMBINED_MODIFIER_MAX:
		combined = COMBINED_MODIFIER_MAX
	return combined


# Deterministic difficulty selection. Given `seed_value`, returns
# one of the supplied `difficulty_ids`. Same seed always returns
# the same id. The default difficulty id list is the built-in
# `STANDARD / HARDENED / DEEP_DIVE` triple.
static func select_difficulty(seed_value: int, difficulty_ids: Array[String]) -> String:
	if difficulty_ids.is_empty():
		return STANDARD_ID
	if difficulty_ids.size() == 1:
		return difficulty_ids[0]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = (int(seed_value) ^ 0x5A5A5A5A) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1
	var idx: int = rng.randi_range(0, difficulty_ids.size() - 1)
	return difficulty_ids[idx]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"description": description,
		"hazard_modifier": hazard_modifier,
		"loot_quality_modifier": loot_quality_modifier,
		"encounter_density_modifier": encounter_density_modifier,
		"ambient_intensity": ambient_intensity,
	}


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
