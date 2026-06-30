extends RefCounted
class_name SustenanceState

var facilities: Dictionary = {}
var total_power_consumed: float = 0.0
var total_materials_consumed: float = 0.0
var purified_water_ready: int = 0
var harvest_ready: int = 0
var meals_ready: int = 0

func configure(config: Dictionary) -> void:
	facilities = (config.get("facilities", {}) as Dictionary).duplicate(true)
	total_power_consumed = 0.0
	total_materials_consumed = 0.0
	purified_water_ready = 0
	harvest_ready = 0
	meals_ready = 0

func tick(_delta: float, context: Dictionary) -> void:
	var powered_ratio: float = clampf(float(context.get("powered_ratio", 0.0)), 0.0, 1.0)
	var hydro: Dictionary = (context.get("hydroponics_summary", {}) as Dictionary).duplicate(true)
	var water: Dictionary = (context.get("water_recycler_summary", {}) as Dictionary).duplicate(true)
	total_power_consumed = float(hydro.get("power_cost", 0.0)) + float(water.get("power_cost", 0.0))
	if powered_ratio < 0.5:
		total_power_consumed = 0.0
	total_materials_consumed = float(hydro.get("water_cost", 0.0)) + float(water.get("input_quantity", 0))
	harvest_ready = 1 if int(hydro.get("state", 0)) == 2 else 0  # 2 == HydroponicsState.State.HARVESTABLE
	meals_ready = 1 if bool(context.get("meals_active", false)) else 0
	purified_water_ready = int(water.get("output_ready", 0))

func get_summary() -> Dictionary:
	return {
		"facilities": facilities.duplicate(true),
		"total_power_consumed": total_power_consumed,
		"total_materials_consumed": total_materials_consumed,
		"purified_water_ready": purified_water_ready,
		"harvest_ready": harvest_ready,
		"meals_ready": meals_ready,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_facilities: Variant = summary.get("facilities", null)
	if typeof(new_facilities) == TYPE_DICTIONARY and JSON.stringify(new_facilities) != JSON.stringify(facilities):
		facilities = (new_facilities as Dictionary).duplicate(true)
		changed = true
	for key in ["total_power_consumed", "total_materials_consumed"]:
		var new_value: float = float(summary.get(key, get(key)))
		if absf(new_value - float(get(key))) > 0.001:
			set(key, new_value)
			changed = true
	for key in ["purified_water_ready", "harvest_ready", "meals_ready"]:
		var new_value: int = int(summary.get(key, get(key)))
		if new_value != int(get(key)):
			set(key, new_value)
			changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Sustenance power=%.1f materials=%.1f" % [total_power_consumed, total_materials_consumed])
	lines.append("Sustenance harvest=%d meals=%d water=%d" % [harvest_ready, meals_ready, purified_water_ready])
	return lines
