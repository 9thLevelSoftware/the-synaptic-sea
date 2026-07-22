extends RefCounted
class_name WorkActionResolver

## PKG-B2.2b: resolve a completed WorkAction against world models.
## Pure — returns a result dictionary for the scene layer to apply
## (inventory, audio, threat noise, training bus).

const ModuleIntegrityConsequencesScript := preload("res://scripts/systems/module_integrity_consequences.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")


## Complete an active WorkActionState against optional ModuleIntegrityMap.
## Returns:
##   ok, verb, noise, xp_event, yields, consumed, module_id, module_state,
##   atmosphere_link, nav_gap, crawl_passable
static func resolve_completion(
		work: RefCounted,
		module_map: RefCounted = null,
		module_id: String = "") -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"verb": "",
		"noise": 0.0,
		"xp_event": "",
		"yields": {},
		"consumed": {},
		"module_id": module_id,
		"module_state": "",
		"atmosphere_link": false,
		"nav_gap": false,
		"crawl_passable": false,
		"reason": "",
	}
	if work == null:
		out["reason"] = "no_work"
		return out
	var status: String = str(work.get("status"))
	if status != WorkActionStateScript.STATUS_COMPLETED:
		out["reason"] = "not_completed"
		return out
	var def: Dictionary = {}
	if work.has_method("get_summary"):
		var sum: Dictionary = work.call("get_summary")
		def = sum.get("definition", {}) if typeof(sum.get("definition", {})) == TYPE_DICTIONARY else {}
	out["verb"] = str(def.get("verb", ""))
	out["noise"] = float(work.call("noise")) if work.has_method("noise") else float(def.get("noise", 0.0))
	out["xp_event"] = str(work.call("xp_event")) if work.has_method("xp_event") else str(def.get("xp_event", ""))
	if work.has_method("materials_yielded"):
		out["yields"] = work.call("materials_yielded")
	if work.has_method("materials_consumed"):
		out["consumed"] = work.call("materials_consumed")

	var verb: String = out["verb"]
	var target_kind: String = str(def.get("target_kind", "module"))
	if module_map != null and not module_id.is_empty() and target_kind in ["module", "breach"]:
		var kind: String = ""
		var m: RefCounted = module_map.call("get_module", module_id) if module_map.has_method("get_module") else null
		if m != null:
			kind = str(m.get("kind"))
		match verb:
			"cut", "pry":
				# Destroy / heavy damage the structural module.
				module_map.call("apply_damage", module_id, 1.0, kind)
			"weld", "patch":
				if m != null and m.has_method("repair"):
					m.call("repair", 0.35)
				else:
					# ensure then repair
					module_map.call("ensure_module", module_id, kind)
					m = module_map.call("get_module", module_id)
					if m != null and m.has_method("repair"):
						m.call("repair", 0.35)
			_:
				pass
		var st: String = str(module_map.call("get_state", module_id))
		out["module_state"] = st
		var cons: Dictionary = ModuleIntegrityConsequencesScript.consequence_for_state(st)
		out["atmosphere_link"] = bool(cons.get("atmosphere_link", false))
		out["nav_gap"] = bool(cons.get("nav_gap", false))
		out["crawl_passable"] = bool(cons.get("crawl_passable", false))

	out["ok"] = true
	return out


## Apply yields into a simple inventory Dictionary (item_id -> qty). Mutates inventory.
static func apply_yields_to_inventory(inventory: Dictionary, yields: Dictionary) -> Dictionary:
	for item_id in yields.keys():
		var add: int = int(yields[item_id])
		if add == 0:
			continue
		var key: String = str(item_id)
		inventory[key] = int(inventory.get(key, 0)) + add
	return inventory


## Consume materials from inventory Dictionary. Returns false if insufficient.
static func consume_from_inventory(inventory: Dictionary, consumed: Dictionary) -> bool:
	for item_id in consumed.keys():
		var need: int = int(consumed[item_id])
		var key: String = str(item_id)
		if int(inventory.get(key, 0)) < need:
			return false
	for item_id in consumed.keys():
		var need2: int = int(consumed[item_id])
		var key2: String = str(item_id)
		inventory[key2] = int(inventory.get(key2, 0)) - need2
		if int(inventory[key2]) <= 0:
			inventory.erase(key2)
	return true
