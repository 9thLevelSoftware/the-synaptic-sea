extends RefCounted
class_name HydroponicsState

## Pure model for hydroponics tray growth cycle.
## Plants a crop, ticks growth, and produces harvestable food.
## Never touches the scene tree.

enum State { IDLE, PLANTED, HARVESTABLE }

var crop_id: String = ""
var crop_name: String = ""
var produce_item_id: String = ""
var produce_quantity: int = 0
var growth_seconds: float = 120.0
var water_cost: float = 2.0
var power_cost: float = 3.0
var required_skill_level: int = 0

var state: int = State.IDLE
var progress_seconds: float = 0.0

func configure(config: Dictionary) -> void:
	crop_id = str(config.get("crop_id", ""))
	crop_name = str(config.get("display_name", crop_id))
	produce_item_id = str(config.get("produce_item_id", ""))
	produce_quantity = int(config.get("produce_quantity", 0))
	growth_seconds = maxf(0.1, float(config.get("growth_seconds", 120.0)))
	water_cost = float(config.get("water_cost", 2.0))
	power_cost = float(config.get("power_cost", 3.0))
	required_skill_level = int(config.get("required_skill_level", 0))
	state = State.IDLE
	progress_seconds = 0.0

func plant(crop_config: Dictionary, skill_level: int, available_water: float, available_power: float) -> Dictionary:
	if state != State.IDLE:
		return {"ok": false, "reason": "not_idle"}
	if skill_level < required_skill_level:
		return {"ok": false, "reason": "insufficient_skill"}
	if available_water < water_cost:
		return {"ok": false, "reason": "insufficient_water"}
	if available_power < power_cost:
		return {"ok": false, "reason": "insufficient_power"}
	configure(crop_config)
	state = State.PLANTED
	progress_seconds = 0.0
	return {"ok": true, "reason": "", "water_consumed": water_cost, "power_consumed": power_cost}

func tick(delta_seconds: float) -> bool:
	if state != State.PLANTED:
		return false
	if delta_seconds <= 0.0:
		return false
	progress_seconds += delta_seconds
	if progress_seconds >= growth_seconds:
		state = State.HARVESTABLE
		return true
	return false

func get_progress_ratio() -> float:
	if growth_seconds <= 0.0:
		return 0.0
	return clampf(progress_seconds / growth_seconds, 0.0, 1.0)

func harvest() -> Dictionary:
	if state != State.HARVESTABLE:
		return {"ok": false, "item_id": "", "quantity": 0}
	var out: Dictionary = {
		"ok": true,
		"item_id": produce_item_id,
		"quantity": produce_quantity,
	}
	state = State.IDLE
	progress_seconds = 0.0
	crop_id = ""
	return out

func get_summary() -> Dictionary:
	return {
		"crop_id": crop_id,
		"crop_name": crop_name,
		"state": state,
		"progress_seconds": progress_seconds,
		"growth_seconds": growth_seconds,
		"progress_ratio": get_progress_ratio(),
		"produce_item_id": produce_item_id,
		"produce_quantity": produce_quantity,
		"water_cost": water_cost,
		"power_cost": power_cost,
		"required_skill_level": required_skill_level,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_crop: String = str(summary.get("crop_id", crop_id))
	if new_crop != crop_id:
		crop_id = new_crop
		changed = true
	var new_name: String = str(summary.get("crop_name", crop_name))
	if new_name != crop_name:
		crop_name = new_name
		changed = true
	var new_state: int = int(summary.get("state", state))
	if new_state != state:
		state = new_state
		changed = true
	var new_progress: float = float(summary.get("progress_seconds", progress_seconds))
	if absf(new_progress - progress_seconds) > 0.001:
		progress_seconds = new_progress
		changed = true
	var new_growth: float = float(summary.get("growth_seconds", growth_seconds))
	if absf(new_growth - growth_seconds) > 0.001:
		growth_seconds = maxf(0.1, new_growth)
		changed = true
	var new_prod: String = str(summary.get("produce_item_id", produce_item_id))
	if new_prod != produce_item_id:
		produce_item_id = new_prod
		changed = true
	var new_qty: int = int(summary.get("produce_quantity", produce_quantity))
	if new_qty != produce_quantity:
		produce_quantity = new_qty
		changed = true
	var new_water: float = float(summary.get("water_cost", water_cost))
	if absf(new_water - water_cost) > 0.001:
		water_cost = new_water
		changed = true
	var new_power: float = float(summary.get("power_cost", power_cost))
	if absf(new_power - power_cost) > 0.001:
		power_cost = new_power
		changed = true
	var new_skill: int = int(summary.get("required_skill_level", required_skill_level))
	if new_skill != required_skill_level:
		required_skill_level = new_skill
		changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var state_name: String = "IDLE"
	if state == State.PLANTED:
		state_name = "PLANTED"
	elif state == State.HARVESTABLE:
		state_name = "HARVESTABLE"
	lines.append("Hydroponics: %s [%s]" % [crop_name, state_name])
	if state == State.PLANTED:
		lines.append("  growth=%d%%" % int(round(get_progress_ratio() * 100.0)))
	elif state == State.HARVESTABLE:
		lines.append("  ready: %s x%d" % [produce_item_id, produce_quantity])
	return lines
