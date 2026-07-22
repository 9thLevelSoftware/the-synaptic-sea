extends RefCounted
class_name ComponentMountResolver

## PKG-B2.3b: resolve completed mount/dismount WorkActions against ComponentPlacementState.
## Pure — mutates placement + inventory Dictionary; scene applies encumbrance/UI.

const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")


## Complete a dismount WorkAction. work.target_id must be component_instance_id.
static func resolve_dismount(
		work: RefCounted,
		placement: RefCounted,
		inventory: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"verb": "unbolt",
		"item_form": "",
		"mass": 0.0,
		"instance_id": "",
		"noise": 0.0,
		"xp_event": "",
	}
	if work == null or placement == null:
		out["reason"] = "no_work_or_placement"
		return out
	if str(work.get("status")) != WorkActionStateScript.STATUS_COMPLETED:
		out["reason"] = "not_completed"
		return out
	var instance_id: String = str(work.get("target_id"))
	if instance_id.is_empty():
		out["reason"] = "no_target"
		return out
	var result: Dictionary = placement.call("dismount", instance_id)
	if not bool(result.get("ok", false)):
		out["reason"] = str(result.get("reason", "dismount_failed"))
		return out
	var item_form: String = str(result.get("item_form", ""))
	var qty: int = maxi(1, int(result.get("qty", 1)))
	inventory[item_form] = int(inventory.get(item_form, 0)) + qty
	out["ok"] = true
	out["item_form"] = item_form
	out["mass"] = float(result.get("mass", 0.0))
	out["instance_id"] = instance_id
	out["noise"] = float(work.call("noise")) if work.has_method("noise") else 0.15
	out["xp_event"] = str(work.call("xp_event")) if work.has_method("xp_event") else "salvage"
	out["component_id"] = str(result.get("component_id", ""))
	out["linked_system"] = str(result.get("linked_system", ""))
	out["linked_subcomponent"] = str(result.get("linked_subcomponent", ""))
	return out


## Complete a mount WorkAction. work.target_id format: room|slot_kind|slot_index|item_form
## or pass explicit fields via mount_context.
static func resolve_mount(
		work: RefCounted,
		placement: RefCounted,
		inventory: Dictionary,
		catalog: RefCounted = null,
		mount_context: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"verb": "mount",
		"item_form": "",
		"instance_id": "",
		"noise": 0.0,
		"xp_event": "",
	}
	if work == null or placement == null:
		out["reason"] = "no_work_or_placement"
		return out
	if str(work.get("status")) != WorkActionStateScript.STATUS_COMPLETED:
		out["reason"] = "not_completed"
		return out
	var room_id: String = str(mount_context.get("room_id", ""))
	var slot_kind: String = str(mount_context.get("slot_kind", "wall"))
	var slot_index: int = int(mount_context.get("slot_index", 0))
	var item_form: String = str(mount_context.get("item_form", ""))
	if item_form.is_empty() or room_id.is_empty():
		# Parse target_id: room|slot_kind|slot_index|item_form
		var tid: String = str(work.get("target_id"))
		var parts: PackedStringArray = tid.split("|")
		if parts.size() >= 4:
			room_id = parts[0]
			slot_kind = parts[1]
			slot_index = int(parts[2])
			item_form = parts[3]
	if item_form.is_empty() or room_id.is_empty():
		out["reason"] = "bad_target"
		return out
	var result: Dictionary = placement.call(
		"mount", item_form, room_id, slot_kind, slot_index, inventory, catalog)
	if not bool(result.get("ok", false)):
		out["reason"] = str(result.get("reason", "mount_failed"))
		return out
	out["ok"] = true
	out["item_form"] = item_form
	out["instance_id"] = str(result.get("instance_id", ""))
	out["noise"] = float(work.call("noise")) if work.has_method("noise") else 0.20
	out["xp_event"] = str(work.call("xp_event")) if work.has_method("xp_event") else "repair"
	return out
