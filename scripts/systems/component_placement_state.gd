extends RefCounted
class_name ComponentPlacementState

## PKG-B2.3a pure placement of components into wall/center slots.
## Deterministic under (layout, seed). Never touches scene tree.

const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")

## placed: Array of {component_instance_id, component_id, room_id, slot_kind, slot_index, cell, condition, linked_system, linked_subcomponent, item_form, mass}
var placed: Array = []
var seed_value: int = 0


func clear() -> void:
	placed.clear()


func populate(layout: Dictionary, catalog: RefCounted, p_seed: int) -> int:
	clear()
	seed_value = p_seed
	if catalog == null or not catalog.has_method("role_set"):
		return 0
	var rooms_v: Variant = layout.get("rooms", [])
	if typeof(rooms_v) != TYPE_ARRAY:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(p_seed) ^ 0xC0A1E5C) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1
	var used_keys: Dictionary = {}  # room|slot_kind|index -> true
	var instance_n: int = 0
	for room_v in (rooms_v as Array):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var room_id: String = str(room.get("id", ""))
		if room_id.is_empty():
			continue
		var role: String = str(room.get("room_role", room.get("role", "default")))
		instance_n += _fill_slots(room, room_id, role, "wall", "wall_slots", catalog, rng, used_keys)
		instance_n += _fill_slots(room, room_id, role, "center", "center_slots", catalog, rng, used_keys)
	return placed.size()


func _fill_slots(
		room: Dictionary,
		room_id: String,
		role: String,
		slot_kind: String,
		slot_key: String,
		catalog: RefCounted,
		rng: RandomNumberGenerator,
		used_keys: Dictionary) -> int:
	var slots: Array = _extract_slots(room, slot_key)
	if slots.is_empty():
		return 0
	var choices: Array = catalog.call("role_set", role, slot_kind)
	if choices.is_empty():
		return 0
	var filled: int = 0
	for i in range(slots.size()):
		var key: String = "%s|%s|%d" % [room_id, slot_kind, i]
		if used_keys.has(key):
			continue
		var component_id: String = _weighted_pick(choices, rng)
		if component_id.is_empty() or not catalog.call("has_component", component_id):
			continue
		var def: Dictionary = catalog.call("get_component", component_id)
		# Prefer components whose slot matches
		var want_slot: String = str(def.get("slot", slot_kind))
		if want_slot != slot_kind and want_slot != "any":
			# try once more
			component_id = _weighted_pick(choices, rng)
			if component_id.is_empty():
				continue
			def = catalog.call("get_component", component_id)
			want_slot = str(def.get("slot", slot_kind))
			if want_slot != slot_kind and want_slot != "any":
				continue
		var slot_info: Dictionary = slots[i] if typeof(slots[i]) == TYPE_DICTIONARY else {}
		var entry: Dictionary = {
			"component_instance_id": "%s_%s_%d" % [room_id, slot_kind, i],
			"component_id": component_id,
			"room_id": room_id,
			"slot_kind": slot_kind,
			"slot_index": i,
			"cell": str(slot_info.get("cell", "")),
			"against_wall": bool(slot_info.get("against_wall", slot_kind == "wall")),
			"condition": float(def.get("condition_default", 1.0)),
			"item_form": str(def.get("item_form", component_id)),
			"mass": float(def.get("mass", 10.0)),
			"linked_system": str(def.get("linked_system", "")),
			"linked_subcomponent": str(def.get("linked_subcomponent", "")),
			"mounted": true,
		}
		placed.append(entry)
		used_keys[key] = true
		filled += 1
	return filled


func _extract_slots(room: Dictionary, slot_key: String) -> Array:
	# Slots may live on room root or under zones (serializer variants).
	var direct: Variant = room.get(slot_key, null)
	if direct is Array:
		return direct as Array
	var zones: Variant = room.get("zones", {})
	if zones is Dictionary:
		var z: Variant = (zones as Dictionary).get(slot_key, [])
		if z is Array:
			return z as Array
	return []


func _weighted_pick(choices: Array, rng: RandomNumberGenerator) -> String:
	var total: int = 0
	var weights: Array = []
	for c in choices:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var w: int = maxi(1, int((c as Dictionary).get("weight", 1)))
		weights.append({"id": str((c as Dictionary).get("component_id", "")), "w": w})
		total += w
	if total <= 0 or weights.is_empty():
		return ""
	var roll: int = rng.randi_range(1, total)
	var cum: int = 0
	for row in weights:
		cum += int(row["w"])
		if roll <= cum:
			return str(row["id"])
	return str(weights[weights.size() - 1]["id"])


## Attach linked_system/subcomponent for catalog-linked pieces; fill gaps from systems.json-shaped data.
## PKG-REQ-CMP-002: map unlinked physical placements onto uncovered subcomponents so
## each critical ship-system piece can exist as a strippable object when slots allow.
func link_ship_systems(systems_doc: Dictionary, catalog: RefCounted = null) -> int:
	var linked: int = 0
	var systems_v: Variant = systems_doc.get("systems", [])
	if typeof(systems_v) != TYPE_ARRAY:
		return 0
	# Re-stamp from catalog definitions when present (authoritative for named machines).
	if catalog != null and catalog.has_method("get_component"):
		for i in range(placed.size()):
			if typeof(placed[i]) != TYPE_DICTIONARY:
				continue
			var e: Dictionary = placed[i]
			var cid: String = str(e.get("component_id", ""))
			if cid.is_empty() or not catalog.call("has_component", cid):
				continue
			var def: Dictionary = catalog.call("get_component", cid)
			var ls: String = str(def.get("linked_system", ""))
			var lsub: String = str(def.get("linked_subcomponent", ""))
			if not ls.is_empty():
				e["linked_system"] = ls
				e["linked_subcomponent"] = lsub
				placed[i] = e
	# Index covered system.sub keys
	var covered: Dictionary = {}  # system.sub -> true
	for entry in placed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		var sys: String = str(e.get("linked_system", ""))
		var sub: String = str(e.get("linked_subcomponent", ""))
		if not sys.is_empty() and not sub.is_empty():
			covered["%s.%s" % [sys, sub]] = true
			linked += 1
	# Build uncovered subcomponent queue from systems_doc
	var uncovered: Array = []
	for sys_v in (systems_v as Array):
		if typeof(sys_v) != TYPE_DICTIONARY:
			continue
		var sys_row: Dictionary = sys_v
		var sid: String = str(sys_row.get("system_id", sys_row.get("id", "")))
		if sid.is_empty():
			continue
		var subs_v: Variant = sys_row.get("subcomponents", [])
		if typeof(subs_v) != TYPE_ARRAY:
			continue
		for sub_v in (subs_v as Array):
			if typeof(sub_v) != TYPE_DICTIONARY:
				continue
			var sub_id: String = str((sub_v as Dictionary).get("subcomponent_id", ""))
			if sub_id.is_empty():
				continue
			var key: String = "%s.%s" % [sid, sub_id]
			if not covered.has(key):
				uncovered.append({"system": sid, "sub": sub_id})
	# Soft-link unlinked furniture placements onto uncovered subs (deterministic order).
	var u: int = 0
	for i2 in range(placed.size()):
		if u >= uncovered.size():
			break
		if typeof(placed[i2]) != TYPE_DICTIONARY:
			continue
		var e2: Dictionary = placed[i2]
		if not str(e2.get("linked_system", "")).is_empty():
			continue
		var assign: Dictionary = uncovered[u]
		u += 1
		e2["linked_system"] = str(assign.get("system", ""))
		e2["linked_subcomponent"] = str(assign.get("sub", ""))
		e2["soft_linked"] = true
		placed[i2] = e2
		covered["%s.%s" % [e2["linked_system"], e2["linked_subcomponent"]]] = true
		linked += 1
	return linked


func occupancy_keys() -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for entry in placed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		var k: String = "%s|%s|%d" % [str(e.get("room_id", "")), str(e.get("slot_kind", "")), int(e.get("slot_index", 0))]
		if seen.has(k):
			continue
		seen[k] = true
		keys.append(k)
	keys.sort()
	return keys


func has_slot_collisions() -> bool:
	var seen: Dictionary = {}
	for entry in placed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		var k: String = "%s|%s|%d" % [str(e.get("room_id", "")), str(e.get("slot_kind", "")), int(e.get("slot_index", 0))]
		if seen.has(k):
			return true
		seen[k] = true
	return false


func get_summary() -> Dictionary:
	return {
		"schema": "component_placement_v1",
		"seed": seed_value,
		"count": placed.size(),
		"placed": placed.duplicate(true),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	seed_value = int(summary.get("seed", 0))
	var p: Variant = summary.get("placed", [])
	if typeof(p) != TYPE_ARRAY:
		return false
	placed = (p as Array).duplicate(true)
	return true


func fingerprint() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry in placed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		parts.append("%s:%s:%s:%d" % [
			str(e.get("room_id", "")),
			str(e.get("slot_kind", "")),
			str(e.get("component_id", "")),
			int(e.get("slot_index", 0)),
		])
	return "|".join(parts)


## --- PKG-B2.3b: mount / dismount pure ops (WorkAction resolve targets) ---

func find_index(instance_id: String) -> int:
	for i in range(placed.size()):
		if typeof(placed[i]) != TYPE_DICTIONARY:
			continue
		if str((placed[i] as Dictionary).get("component_instance_id", "")) == instance_id:
			return i
	return -1


func get_entry(instance_id: String) -> Dictionary:
	var idx: int = find_index(instance_id)
	if idx < 0:
		return {}
	return (placed[idx] as Dictionary).duplicate(true)


func is_mounted(instance_id: String) -> bool:
	var e: Dictionary = get_entry(instance_id)
	if e.is_empty():
		return false
	return bool(e.get("mounted", true))


## Dismount a placed component: marks mounted=false and returns yield payload.
## Does not mutate inventory (caller / resolver applies yields).
func dismount(instance_id: String) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"item_form": "",
		"mass": 0.0,
		"qty": 0,
		"component_id": "",
		"instance_id": instance_id,
	}
	var idx: int = find_index(instance_id)
	if idx < 0:
		out["reason"] = "not_found"
		return out
	var e: Dictionary = placed[idx]
	if not bool(e.get("mounted", true)):
		out["reason"] = "already_dismounted"
		return out
	var item_form: String = str(e.get("item_form", e.get("component_id", "")))
	if item_form.is_empty():
		out["reason"] = "no_item_form"
		return out
	e["mounted"] = false
	placed[idx] = e
	out["ok"] = true
	out["item_form"] = item_form
	out["mass"] = float(e.get("mass", 10.0))
	out["qty"] = 1
	out["component_id"] = str(e.get("component_id", ""))
	out["linked_system"] = str(e.get("linked_system", ""))
	out["linked_subcomponent"] = str(e.get("linked_subcomponent", ""))
	return out


## Remount into a free or previously emptied slot. Consumes one item_form from inventory dict.
## inventory is item_id -> qty. Mutates inventory on success.
func mount(
		item_form: String,
		room_id: String,
		slot_kind: String,
		slot_index: int,
		inventory: Dictionary,
		catalog: RefCounted = null) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"instance_id": "",
		"item_form": item_form,
	}
	if item_form.is_empty():
		out["reason"] = "no_item"
		return out
	if int(inventory.get(item_form, 0)) < 1:
		out["reason"] = "missing_item"
		return out
	# Prefer remounting an existing dismounted entry in this slot.
	var target_idx: int = -1
	for i in range(placed.size()):
		if typeof(placed[i]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = placed[i]
		if str(e.get("room_id", "")) != room_id:
			continue
		if str(e.get("slot_kind", "")) != slot_kind:
			continue
		if int(e.get("slot_index", -1)) != slot_index:
			continue
		target_idx = i
		break
	if target_idx >= 0:
		var existing: Dictionary = placed[target_idx]
		if bool(existing.get("mounted", true)):
			out["reason"] = "slot_occupied"
			return out
		# Must match the item form that was removed (or catalog-compatible).
		var want: String = str(existing.get("item_form", existing.get("component_id", "")))
		if want != item_form:
			out["reason"] = "wrong_item"
			return out
		existing["mounted"] = true
		placed[target_idx] = existing
		inventory[item_form] = int(inventory.get(item_form, 0)) - 1
		if int(inventory[item_form]) <= 0:
			inventory.erase(item_form)
		out["ok"] = true
		out["instance_id"] = str(existing.get("component_instance_id", ""))
		return out
	# Fresh mount into empty slot — require catalog to resolve component_id from item_form.
	if catalog == null or not catalog.has_method("component_id_for_item_form"):
		out["reason"] = "slot_empty_needs_catalog"
		return out
	var component_id: String = str(catalog.call("component_id_for_item_form", item_form))
	if component_id.is_empty():
		out["reason"] = "unknown_item_form"
		return out
	var def: Dictionary = catalog.call("get_component", component_id)
	var entry: Dictionary = {
		"component_instance_id": "%s_%s_%d" % [room_id, slot_kind, slot_index],
		"component_id": component_id,
		"room_id": room_id,
		"slot_kind": slot_kind,
		"slot_index": slot_index,
		"cell": "",
		"against_wall": slot_kind == "wall",
		"condition": float(def.get("condition_default", 1.0)),
		"item_form": item_form,
		"mass": float(def.get("mass", 10.0)),
		"linked_system": str(def.get("linked_system", "")),
		"linked_subcomponent": str(def.get("linked_subcomponent", "")),
		"mounted": true,
	}
	# Collision check
	if occupancy_keys().has("%s|%s|%d" % [room_id, slot_kind, slot_index]):
		out["reason"] = "slot_occupied"
		return out
	placed.append(entry)
	inventory[item_form] = int(inventory.get(item_form, 0)) - 1
	if int(inventory[item_form]) <= 0:
		inventory.erase(item_form)
	out["ok"] = true
	out["instance_id"] = str(entry["component_instance_id"])
	return out


func mounted_count() -> int:
	var n: int = 0
	for entry in placed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if bool((entry as Dictionary).get("mounted", true)):
			n += 1
	return n


func dismounted_count() -> int:
	return placed.size() - mounted_count()
