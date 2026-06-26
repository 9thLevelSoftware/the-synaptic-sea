extends RefCounted
class_name QualityTierResolver

## Pure utility: resolves a numeric quality score [0.0, 1.0] into a named tier
## with a multiplier. Station level, skill level, and material quality all feed
## into the final score. Never touches the scene tree.

const TIER_ORDER: Array[String] = ["poor", "standard", "good", "excellent", "masterwork"]
const TIER_THRESHOLDS: Dictionary = {
	"poor": 0.0,
	"standard": 0.35,
	"good": 0.55,
	"excellent": 0.75,
	"masterwork": 0.90,
}
const DEFAULT_MULTIPLIERS: Dictionary = {
	"poor": 0.7,
	"standard": 1.0,
	"good": 1.25,
	"excellent": 1.6,
	"masterwork": 2.0,
}

var _tiers: Dictionary = {}
var _loaded: bool = false

func _init() -> void:
	_load_tiers()

func _load_tiers() -> void:
	var path: String = "res://data/recipes/recipe_definitions.json"
	if not FileAccess.file_exists(path):
		_tiers = DEFAULT_MULTIPLIERS.duplicate()
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_tiers = DEFAULT_MULTIPLIERS.duplicate()
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var qt: Variant = (parsed as Dictionary).get("quality_tiers", {})
		if qt is Dictionary:
			for tier_name in (qt as Dictionary):
				var tier_def: Variant = (qt as Dictionary)[tier_name]
				if tier_def is Dictionary:
					_tiers[str(tier_name)] = float((tier_def as Dictionary).get("multiplier", DEFAULT_MULTIPLIERS.get(str(tier_name), 1.0)))
	if _tiers.is_empty():
		_tiers = DEFAULT_MULTIPLIERS.duplicate()
	_loaded = true

## Computes a final quality score from component inputs, then returns the tier.
## Inputs:
##   material_quality: float [0.0, 1.0] (average ingredient quality)
##   skill_level: int (player skill level for this recipe category)
##   station_level: int (station upgrade level, 0 = base)
##   powered: bool (station has power)
## The score is: material_quality * 0.4 + skill_bonus * 0.35 + station_bonus * 0.25
## Power adds a flat +0.05 when true. Result is clamped [0.0, 1.0].
static func compute_score(material_quality: float, skill_level: int, station_level: int, powered: bool) -> float:
	var mq: float = clampf(material_quality, 0.0, 1.0)
	var skill_bonus: float = clampf(float(skill_level) * 0.08, 0.0, 0.35)
	var station_bonus: float = clampf(float(station_level) * 0.06, 0.0, 0.25)
	var power_bonus: float = 0.05 if powered else 0.0
	return clampf(mq * 0.4 + skill_bonus * 0.35 + station_bonus * 0.25 + power_bonus, 0.0, 1.0)

## Returns the tier name for a given score.
static func tier_for_score(score: float) -> String:
	var s: float = clampf(score, 0.0, 1.0)
	var chosen: String = "poor"
	for tier in TIER_ORDER:
		if s >= TIER_THRESHOLDS.get(tier, 0.0):
			chosen = tier
	return chosen

## Returns the multiplier for a tier name.
func multiplier_for_tier(tier_name: String) -> float:
	return clampf(float(_tiers.get(tier_name, DEFAULT_MULTIPLIERS.get(tier_name, 1.0))), 0.1, 5.0)

## Full resolve: returns {tier, multiplier, score}.
func resolve(material_quality: float, skill_level: int, station_level: int, powered: bool) -> Dictionary:
	var score: float = compute_score(material_quality, skill_level, station_level, powered)
	var tier: String = tier_for_score(score)
	return {
		"tier": tier,
		"multiplier": multiplier_for_tier(tier),
		"score": score,
	}

func get_summary() -> Dictionary:
	return {
		"tiers": _tiers.duplicate(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var t: Variant = summary.get("tiers", {})
	if t is Dictionary:
		_tiers = (t as Dictionary).duplicate()
		return true
	return false
