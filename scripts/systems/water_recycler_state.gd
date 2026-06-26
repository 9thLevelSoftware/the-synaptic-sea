extends RefCounted
class_name WaterRecyclerState

## Pure model for the water recycler / purifier.
## Converts contaminated water into purified water over time.
## Never touches the scene tree.

enum State { IDLE, RECYCLING }

var input_item_id: String = ""
var output_item_id: String = "purified_water"
var conversion_ratio: float = 1.0    # 1 input -> 1 output
var recycle_time_seconds: float = 30.0
var power_cost: float = 5.0

var state: int = State.IDLE
var progress_seconds: float = 0.0
var input_quantity: int = 0
var output_ready: int = 0

func configure(config: Dictionary) -> void:
	input_item_id = str(config.get("input_item_id", ""))
	output_item_id = str(config.get("output_item_id", "purified_water"))
	conversion_ratio = float(config.get("conversion_ratio", 1.0))
	recycle_time_seconds = maxf(0.1, float(config.get("recycle_time_seconds", 30.0)))
	power_cost = float(config.get("power_cost", 5.0))
	state = State.IDLE
	progress_seconds = 0.0
	input_quantity = 0
	output_ready = 0

func load_input(item_id: String, qty: int, available_power: float) -> Dictionary:
	if state != State.IDLE:
		return {"ok": false, "reason": "not_idle"}
	if available_power < power_cost:
		return {"ok": false, "reason": "insufficient_power"}
	if qty <= 0:
		return {"ok": false, "reason": "no_input"}
	input_item_id = item_id
	input_quantity = qty
	state = State.RECYCLING
	progress_seconds = 0.0
	return {"ok": true, "reason": ""}

func tick(delta_seconds: float) -> bool:
	if state != State.RECYCLING:
		return false
	if delta_seconds <= 0.0:
		return false
	progress_seconds += delta_seconds
	if progress_seconds >= recycle_time_seconds:
		state = State.IDLE
		output_ready = int(float(input_quantity) * conversion_ratio)
		input_quantity = 0
		return true
	return false

func get_progress_ratio() -> float:
	if recycle_time_seconds <= 0.0:
		return 0.0
	return clampf(progress_seconds / recycle_time_seconds, 0.0, 1.0)

func collect_output() -> Dictionary:
	if output_ready <= 0:
		return {"ok": false, "item_id": "", "quantity": 0}
	var out: Dictionary = {
		"ok": true,
		"item_id": output_item_id,
		"quantity": output_ready,
	}
	output_ready = 0
	return out

func get_summary() -> Dictionary:
	return {
		"input_item_id": input_item_id,
		"output_item_id": output_item_id,
		"conversion_ratio": conversion_ratio,
		"recycle_time_seconds": recycle_time_seconds,
		"power_cost": power_cost,
		"state": state,
		"progress_seconds": progress_seconds,
		"input_quantity": input_quantity,
		"output_ready": output_ready,
		"progress_ratio": get_progress_ratio(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	for key in ["input_item_id", "output_item_id"]:
		var new_val: String = str(summary.get(key, get(key)))
		if new_val != get(key):
			set(key, new_val)
			changed = true
	for key in ["conversion_ratio", "recycle_time_seconds", "power_cost", "progress_seconds"]:
		var new_val: float = float(summary.get(key, get(key)))
		if absf(new_val - get(key)) > 0.001:
			set(key, new_val)
			changed = true
	for key in ["state", "input_quantity", "output_ready"]:
		var new_val: int = int(summary.get(key, get(key)))
		if new_val != get(key):
			set(key, new_val)
			changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var state_name: String = "IDLE"
	if state == State.RECYCLING:
		state_name = "RECYCLING"
	lines.append("Water Recycler: %s [%s]" % [output_item_id, state_name])
	if state == State.RECYCLING:
		lines.append("  progress=%d%% input=%d" % [int(round(get_progress_ratio() * 100.0)), input_quantity])
	if output_ready > 0:
		lines.append("  ready: %s x%d" % [output_item_id, output_ready])
	return lines
