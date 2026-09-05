extends RefCounted
class_name ShipModificationState

## PKG-D2.6: pure hub/ship component install manifest + power budget gate.
## Installs consume inventory item_form and add to ship slots; power budget
## constraints bite when demand exceeds supply. Never touches scene tree.

const DEFAULT_BUDGET_PATH: String = "res://data/ship_systems/power_budget_tables.json"

## installed: Array of {slot_id, component_id, item_form, power_draw, mass, source_ship}
var installed: Array = []
## Real placement descriptors, supplied by the selected ship.  P11 deliberately
## does not manufacture hub slots when the runtime has not supplied these.
var _physical_slots: Array = []
var _ship_id: String = ""
var _catalog: RefCounted = null
var _placement_owner: RefCounted = null
var power_supply: float = 100.0
var power_demand_baseline: float = 0.0
var min_operational_ratio: float = 0.5
var hull_plating_bonus: float = 0.0  # integrity repair buffer from plating installs


func configure(config: Dictionary = {}) -> void:
	installed.clear()
	_physical_slots.clear()
	_ship_id = str(config.get("ship_id", ""))
	_catalog = config.get("component_catalog", null) as RefCounted
	_placement_owner = config.get("component_placement", null) as RefCounted
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
	var slots: Variant = config.get("physical_slots", [])
	if slots is Array:
		bind_physical_slots(_ship_id, slots as Array, _catalog, _placement_owner)


## Bind this model to concrete, authored/generated slots for one ship.  A slot ID
## is the placement descriptor identity, never a panel index or a synthetic hub ID.
func bind_physical_slots(
		ship_id: String,
		slots: Array,
		catalog: RefCounted = null,
		placement_owner: RefCounted = null) -> bool:
	if ship_id.is_empty() or catalog == null or placement_owner == null:
		return false
	var normalized: Array = []
	var seen: Dictionary = {}
	for entry_v in slots:
		if typeof(entry_v) != TYPE_DICTIONARY:
			return false
		var entry: Dictionary = (entry_v as Dictionary).duplicate(true)
		var slot_id: String = str(entry.get("slot_id", ""))
		var descriptor_ship: String = str(entry.get("ship_id", ship_id))
		var slot_kind: String = str(entry.get("slot_kind", ""))
		var profile_id: String = str(entry.get("component_slot_profile_id", ""))
		if slot_id.is_empty() or descriptor_ship != ship_id or slot_kind.is_empty() \
				or profile_id.is_empty() or seen.has(slot_id) \
				or not catalog.has_method("get_slot_profile") \
				or (catalog.call("get_slot_profile", profile_id) as Dictionary).is_empty():
			return false
		entry["ship_id"] = ship_id
		entry["slot_id"] = slot_id
		entry["slot_kind"] = slot_kind
		normalized.append(entry)
		seen[slot_id] = true
	_ship_id = ship_id
	_physical_slots = normalized
	_catalog = catalog
	_placement_owner = placement_owner
	sync_from_placement()
	return true


func get_physical_slots() -> Array:
	if _placement_owner != null and _placement_owner.has_method("get_physical_slot_descriptors"):
		_physical_slots = _placement_owner.call("get_physical_slot_descriptors", _ship_id)
	return _physical_slots.duplicate(true)


func sync_from_placement() -> void:
	installed.clear()
	if _placement_owner == null or _catalog == null:
		return
	var entries_v: Variant = _placement_owner.get("placed")
	if not (entries_v is Array):
		return
	for entry_v in entries_v as Array:
		if not (entry_v is Dictionary) or not bool((entry_v as Dictionary).get("mounted", true)) \
				or not bool((entry_v as Dictionary).get("ship_mod_managed", false)):
			continue
		var entry: Dictionary = entry_v as Dictionary
		var component_id: String = str(entry.get("component_id", ""))
		if not _catalog.has_method("get_component"):
			continue
		var definition: Dictionary = _catalog.call("get_component", component_id)
		if definition.is_empty():
			continue
		installed.append({
			"slot_id": str(entry.get("component_instance_id", "")),
			"component_id": component_id,
			"item_form": str(definition.get("item_form", component_id)),
			"power_draw": maxf(0.0, float(definition.get("power_draw", 0.0))),
			"mass": maxf(0.0, float(definition.get("mass", 0.0))),
			"source_ship": _ship_id,
			"plating": bool(definition.get("plating", false)),
		})
	hull_plating_bonus = 0.0
	for installed_v in installed:
		if bool((installed_v as Dictionary).get("plating", false)):
			hull_plating_bonus += 0.05


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


## Shared preflight for panel and direct mutation APIs.  It completes every
## identity/catalog/physical-fit check before inventory or power can change.
func preflight_install(
		slot_id: String,
		component_id: String,
		item_form: String,
		inventory: Dictionary,
		target_ship_id: String = "") -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "slot_id": slot_id}
	if target_ship_id != "" and target_ship_id != _ship_id:
		out["reason"] = "wrong_ship"
		return out
	if _catalog == null or _placement_owner == null or get_physical_slots().is_empty() or _ship_id.is_empty():
		out["reason"] = "physical_slot_required"
		return out
	if component_id.is_empty() or not _catalog.has_method("has_component") or not bool(_catalog.call("has_component", component_id)):
		out["reason"] = "unknown_component"
		return out
	var definition: Dictionary = _catalog.call("get_component", component_id)
	if definition.is_empty():
		out["reason"] = "unknown_component"
		return out
	if item_form != str(definition.get("item_form", component_id)):
		out["reason"] = "incompatible_item_form"
		return out
	var slot: Dictionary = _find_physical_slot(slot_id)
	if slot.is_empty():
		out["reason"] = "unknown_slot"
		return out
	if bool(slot.get("occupied", false)) or _is_installed_in_slot(slot_id):
		out["reason"] = "slot_occupied"
		return out
	var fit: Dictionary = _catalog.call("validate_component_fit", component_id, slot) if _catalog.has_method("validate_component_fit") else {"ok": false, "reason": "missing_fit_contract"}
	if not bool(fit.get("ok", false)):
		out["reason"] = str(fit.get("reason", "incompatible_fit"))
		return out
	out["physical_fit_ok"] = true
	if int(inventory.get(item_form, 0)) < 1:
		out["reason"] = "missing_item"
		return out
	var power_gate: Dictionary = can_install(component_id, float(definition.get("power_draw", 0.0)))
	if not bool(power_gate.get("ok", false)):
		out["reason"] = str(power_gate.get("reason", "blocked"))
		return out
	out["ok"] = true
	out["definition"] = definition
	return out


func _find_physical_slot(slot_id: String) -> Dictionary:
	for slot_v in get_physical_slots():
		if typeof(slot_v) == TYPE_DICTIONARY and str((slot_v as Dictionary).get("slot_id", "")) == slot_id:
			return (slot_v as Dictionary).duplicate(true)
	return {}


func _is_installed_in_slot(slot_id: String) -> bool:
	for entry_v in installed:
		if typeof(entry_v) == TYPE_DICTIONARY and str((entry_v as Dictionary).get("slot_id", "")) == slot_id:
			return true
	return false


## Install from inventory Dictionary item_form->qty. Mutates inventory on success.
func install(
		slot_id: String,
		component_id: String,
		item_form: String,
		inventory: Dictionary,
		power_draw: float = 5.0,
		mass: float = 10.0,
		source_ship: String = "",
		plating: bool = false,
		target_ship_id: String = "") -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "slot_id": slot_id}
	var preflight: Dictionary = preflight_install(slot_id, component_id, item_form, inventory, target_ship_id)
	if not bool(preflight.get("ok", false)):
		out["reason"] = str(preflight.get("reason", "blocked"))
		return out
	var definition: Dictionary = preflight.get("definition", {}) as Dictionary
	power_draw = maxf(0.0, float(definition.get("power_draw", 0.0)))
	mass = maxf(0.0, float(definition.get("mass", 0.0)))
	plating = bool(definition.get("plating", false))
	if not _placement_owner.has_method("mount_by_slot_id"):
		out["reason"] = "physical_owner_required"
		return out
	var mounted: Dictionary = _placement_owner.call("mount_by_slot_id", slot_id, item_form, inventory, _catalog)
	if not bool(mounted.get("ok", false)):
		out["reason"] = str(mounted.get("reason", "mount_failed"))
		return out
	sync_from_placement()
	out["ok"] = true
	out["component_id"] = component_id
	return out


## Uninstall slot back into inventory.
func uninstall(slot_id: String, inventory: Dictionary) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "item_form": ""}
	if _placement_owner == null or not _placement_owner.has_method("dismount"):
		out["reason"] = "physical_owner_required"
		return out
	var result: Dictionary = _placement_owner.call("dismount", slot_id)
	if not bool(result.get("ok", false)):
		out["reason"] = str(result.get("reason", "not_found"))
		return out
	var form: String = str(result.get("item_form", ""))
	if not form.is_empty():
		inventory[form] = int(inventory.get(form, 0)) + maxi(1, int(result.get("qty", 1)))
	sync_from_placement()
	out["ok"] = true
	out["item_form"] = form
	out["component_id"] = str(result.get("component_id", ""))
	return out


func is_power_budget_ok() -> bool:
	return total_power_draw() <= power_supply + 0.001


## REQ-SMOD-001: plating installs reduce hub structure damage (cap 50%).
func structure_damage_resist() -> float:
	return clampf(hull_plating_bonus * 2.0, 0.0, 0.5)


func get_summary() -> Dictionary:
	return {
		"schema": "ship_modification_v2",
		"installed": installed.duplicate(true),
		"ship_id": _ship_id,
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
	_ship_id = str(summary.get("ship_id", _ship_id))
	# Physical occupancy/effects are re-derived only after the coordinator binds
	# the current ComponentPlacementState. A saved manifest cannot create mounts.
	_physical_slots.clear()
	installed.clear()
	_placement_owner = null
	return true
