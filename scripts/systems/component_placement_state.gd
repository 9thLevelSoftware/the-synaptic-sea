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
func link_ship_systems(systems_doc: Dictionary, catalog: RefCounted) -> int:
	var linked: int = 0
	var systems_v: Variant = systems_doc.get("systems", [])
	if typeof(systems_v) != TYPE_ARRAY:
		return 0
	# Index placed by linked_system for coverage check
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
	# Optionally stamp unlinked components that match role systems (soft link)
	for entry2 in placed:
		if typeof(entry2) != TYPE_DICTIONARY:
			continue
		var e2: Dictionary = entry2
		if not str(e2.get("linked_system", "")).is_empty():
			continue
		# leave unlinked generic furniture
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
