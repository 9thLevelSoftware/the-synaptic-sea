extends RefCounted
class_name ItemQualityEffects

## P05 declarative bridge from exact lot quality to a live consumer. Condition
## remains deliberately separate: only quality_score/tier selects this multiplier.

const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")
const PATH := "res://data/items/quality_effects.json"
const VALID_CONSUMERS: Array[String] = [
	"quantity_only", "tool_work_speed", "component_efficiency",
	"repair_integrity", "consumable_potency",
]

var _items: Dictionary = {}
var _tiers = QualityTierResolverScript.new()

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_items = ((parsed as Dictionary).get("items", {}) as Dictionary).duplicate(true)

func consumer_for(item_id: String) -> String:
	var entry: Variant = _items.get(item_id, {})
	return str((entry as Dictionary).get("consumer", "quantity_only")) if entry is Dictionary else "quantity_only"

func multiplier_for_lot(item_id: String, lot: Dictionary) -> float:
	if consumer_for(item_id) == "quantity_only":
		return 1.0
	var tier: String = str(lot.get("quality_tier", ""))
	if tier.is_empty():
		tier = QualityTierResolverScript.tier_for_score(float(lot.get("quality_score", 0.5)))
	return _tiers.multiplier_for_tier(tier)

func effect_for_lot(item_id: String, lot: Dictionary) -> Dictionary:
	var consumer: String = consumer_for(item_id)
	var multiplier: float = multiplier_for_lot(item_id, lot)
	return {
		"consumer": consumer,
		"multiplier": multiplier,
		"text": effect_text(consumer, multiplier),
	}


func effect_text_for_lot(item_id: String, lot: Dictionary) -> String:
	return effect_text(consumer_for(item_id), multiplier_for_lot(item_id, lot))


static func effect_text(consumer: String, multiplier: float) -> String:
	match consumer:
		"tool_work_speed":
			return "Work speed x%.2f" % multiplier
		"component_efficiency":
			return "Power draw /%.2f" % multiplier
		"repair_integrity":
			return "Repair integrity x%.2f" % multiplier
		"consumable_potency":
			return "Potency x%.2f" % multiplier
		_:
			return "Quantity only (no quality modifier)"
