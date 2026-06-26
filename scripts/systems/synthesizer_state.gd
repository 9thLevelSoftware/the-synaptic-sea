extends RefCounted
class_name SynthesizerState

## Pure model for the nutrient synthesizer station.
## Thin wrapper around CookingState semantics with synthesizer-specific
## recipe filtering and power-consumption tracking. Never touches the scene tree.

var _cooking = load("res://scripts/systems/cooking_state.gd").new()
var total_power_consumed: float = 0.0

func configure(config: Dictionary) -> void:
	_cooking.configure(config)
	total_power_consumed = 0.0

## Start synthesis. Same contract as CookingState.start_cooking.
func start_synthesis(inventory_summary: Dictionary, skill_level: int, available_power: float) -> Dictionary:
	var result: Dictionary = _cooking.start_cooking(inventory_summary, skill_level, available_power)
	if result.get("ok", false):
		total_power_consumed += _cooking.power_cost
	return result

func tick(delta_seconds: float) -> bool:
	return _cooking.tick(delta_seconds)

func is_complete() -> bool:
	return _cooking.is_complete()

func collect_result() -> Dictionary:
	return _cooking.collect_result()

func cancel() -> void:
	_cooking.cancel()

func get_progress_ratio() -> float:
	return _cooking.get_progress_ratio()

func get_summary() -> Dictionary:
	var cooking_summary: Dictionary = _cooking.get_summary()
	cooking_summary["total_power_consumed"] = total_power_consumed
	cooking_summary["station_type"] = "synthesizer"
	return cooking_summary

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = _cooking.apply_summary(summary)
	var new_total: float = float(summary.get("total_power_consumed", total_power_consumed))
	if absf(new_total - total_power_consumed) > 0.001:
		total_power_consumed = new_total
		changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var cooking_script = load("res://scripts/systems/cooking_state.gd")
	var state_name: String = "IDLE"
	if _cooking.state == cooking_script.State.COOKING:
		state_name = "SYNTHESIZING"
	elif _cooking.state == cooking_script.State.COMPLETE:
		state_name = "COMPLETE"
	lines.append("Synthesizer: %s [%s]" % [_cooking.recipe_name, state_name])
	if _cooking.state == cooking_script.State.COOKING:
		lines.append("  progress=%d%%" % int(round(get_progress_ratio() * 100.0)))
	elif _cooking.state == cooking_script.State.COMPLETE:
		lines.append("  ready: %s x%d" % [_cooking.produces_item_id, _cooking.produces_quantity])
	lines.append("  total_power=%.1f" % total_power_consumed)
	return lines
