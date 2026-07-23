extends RefCounted
class_name ShipModificationState

## PKG-D2.6: pure hub/ship component install manifest + power budget gate.
## Installs consume inventory item_form and add to ship slots; power budget
## constraints bite when demand exceeds supply. Never touches scene tree.

const DEFAULT_BUDGET_PATH: String = "res://data/ship_systems/power_budget_tables.json"

## installed: Array of {slot_id, component_id, item_form, power_draw, mass, source_ship}
var installed: Array = []
var power_supply: float = 100.0
var power_demand_baseline: float = 0.0
var min_operational_ratio: float = 0.5
var hull_plating_bonus: float = 0.0  # integrity repair buffer from plating installs


func configure(config: Dictionary = {}) -> void:
	installed.clear()
	power_supply = maxf(0.0, float(config.get("power_supply", 100.0)))
	power_demand_baseline = maxf(0.0, float(config.get("power_demand_baseline", 0.0)))
	min_operational_ratio = clampf(float(config.get("min_operational_ratio", 0.5)), 0.0, 1.0)
	hull_plating_bonus = maxf(0.0, float(config.get("hull_plating_bonus", 0.0)))
	var raw: Variant = config.get("installed", [])
	if raw is Array:
		for e in raw:
			if typeof(e) == TYPE_DICTIONARY:
				installed.append((e as Dictionary).duplicate(true))
	if config.has("budget_path") or FileAccess.file_exists(DEFAULT_BUDGET_PATH):
		_load_budget(str(config.get("budget_path", DEFAULT_BUDGET_PATH)))


func _load_budget(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	power_supply = maxf(0.0, float(root.get("total_supply_units", power_supply)))
	min_operational_ratio = clampf(float(root.get("min_operational_ratio", min_operational_ratio)), 0.0, 1.0)
	var demand: Variant = root.get("baseline_demand_units", {})
	if demand is Dictionary:
		var total: float = 0.0
		for k in (demand as Dictionary).keys():
			total += float((demand as Dictionary)[k])
		power_demand_baseline = total


func installed_count() -> int:
	return installed.size()


func total_power_draw() -> float:
	var draw: float = power_demand_baseline
	for e in installed:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		draw += float((e as Dictionary).get("power_draw", 0.0))
	return draw


func power_ratio() -> float:
	if power_supply <= 0.0:
		return 0.0
	return clampf(1.0 - (total_power_draw() / power_supply), 0.0, 1.0)


func is_power_ok() -> bool:
	return is_power_budget_ok()


func can_install(component_id: String, power_draw: float) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": ""}
	if component_id.is_empty():
		out["reason"] = "no_component"
		return out
	if total_power_draw() + maxf(0.0, power_draw) > power_supply:
		out["reason"] = "power_budget"
		return out
	out["ok"] = true
	return out


## Install from inventory Dictionary item_form->qty. Mutates inventory on success.
func install(
		slot_id: String,
		component_id: String,
		item_form: String,
		inventory: Dictionary,
		power_draw: float = 5.0,
		mass: float = 10.0,
		source_ship: String = "",
		plating: bool = false) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "slot_id": slot_id}
	if slot_id.is_empty() or component_id.is_empty() or item_form.is_empty():
		out["reason"] = "bad_args"
		return out
	for e in installed:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("slot_id", "")) == slot_id:
			out["reason"] = "slot_occupied"
			return out
	if int(inventory.get(item_form, 0)) < 1:
		out["reason"] = "missing_item"
		return out
	var gate: Dictionary = can_install(component_id, power_draw)
	if not bool(gate.get("ok", false)):
		out["reason"] = str(gate.get("reason", "blocked"))
		return out
	inventory[item_form] = int(inventory.get(item_form, 0)) - 1
	if int(inventory[item_form]) <= 0:
		inventory.erase(item_form)
	installed.append({
		"slot_id": slot_id,
		"component_id": component_id,
		"item_form": item_form,
		"power_draw": maxf(0.0, power_draw),
		"mass": maxf(0.0, mass),
		"source_ship": source_ship,
		"plating": plating,
	})
	if plating:
		hull_plating_bonus += 0.05
	out["ok"] = true
	return out


## Uninstall slot back into inventory.
func uninstall(slot_id: String, inventory: Dictionary) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "item_form": ""}
	for i in range(installed.size()):
		if typeof(installed[i]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = installed[i]
		if str(e.get("slot_id", "")) != slot_id:
			continue
		var form: String = str(e.get("item_form", ""))
		if not form.is_empty():
			inventory[form] = int(inventory.get(form, 0)) + 1
		if bool(e.get("plating", false)):
			hull_plating_bonus = maxf(0.0, hull_plating_bonus - 0.05)
		installed.remove_at(i)
		out["ok"] = true
		out["item_form"] = form
		return out
	out["reason"] = "not_found"
	return out


func is_power_budget_ok() -> bool:
	return total_power_draw() <= power_supply + 0.001


## REQ-SMOD-001: plating installs reduce hub structure damage (cap 50%).
func structure_damage_resist() -> float:
	return clampf(hull_plating_bonus * 2.0, 0.0, 0.5)


func get_summary() -> Dictionary:
	return {
		"schema": "ship_modification_v1",
		"installed": installed.duplicate(true),
		"power_supply": power_supply,
		"power_demand_baseline": power_demand_baseline,
		"power_draw": total_power_draw(),
		"power_ok": is_power_budget_ok(),
		"min_operational_ratio": min_operational_ratio,
		"hull_plating_bonus": hull_plating_bonus,
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	power_supply = maxf(0.0, float(summary.get("power_supply", power_supply)))
	power_demand_baseline = maxf(0.0, float(summary.get("power_demand_baseline", power_demand_baseline)))
	min_operational_ratio = clampf(float(summary.get("min_operational_ratio", min_operational_ratio)), 0.0, 1.0)
	hull_plating_bonus = maxf(0.0, float(summary.get("hull_plating_bonus", hull_plating_bonus)))
	var raw: Variant = summary.get("installed", [])
	installed.clear()
	if raw is Array:
		for e in raw:
			if typeof(e) == TYPE_DICTIONARY:
				installed.append((e as Dictionary).duplicate(true))
	return true
