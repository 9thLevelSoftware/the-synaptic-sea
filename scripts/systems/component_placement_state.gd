extends RefCounted
class_name ComponentPlacementState

## PKG-B2.3a pure placement of components into wall/center slots.
## Deterministic under (layout, seed). Never touches scene tree.

const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

const MAX_WALL_FILLS: int = 3
const MAX_CENTER_FILLS: int = 1

## placed: Array of {component_instance_id, component_id, room_id, slot_kind, slot_index, cell, condition, linked_system, linked_subcomponent, item_form, mass}
var placed: Array = []
## Authored/generated physical mount descriptors. Empty descriptors stay here so
## player installation addresses real slots rather than synthetic placeholders.
var physical_slots: Array = []
## Saved mounted records rejected by the current layout/catalog contract. They
## remain serialized for later recovery work, but never occupy or authorize a slot.
var rejected_saved_components: Array = []
var seed_value: int = 0


func clear() -> void:
	placed.clear()
	physical_slots.clear()
	rejected_saved_components.clear()


func populate(layout: Dictionary, catalog: RefCounted, p_seed: int, occupied_cells: Dictionary = {}) -> int:
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
	var used_cells: Dictionary = occupied_cells.duplicate()
	var instance_n: int = 0
	for room_v in (rooms_v as Array):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var room_id: String = str(room.get("id", ""))
		if room_id.is_empty():
			continue
		var role: String = str(room.get("room_role", room.get("role", "default")))
		_register_authored_physical_slots(room, room_id, "wall", "wall_slots", catalog)
		_register_authored_physical_slots(room, room_id, "center", "center_slots", catalog)
		instance_n += _fill_slots(room, room_id, role, "wall", "wall_slots", catalog, rng, used_keys, used_cells)
		instance_n += _fill_slots(room, room_id, role, "center", "center_slots", catalog, rng, used_keys, used_cells)
	return placed.size()


## Population retains its legacy structural synthesis for world dressing, but P11
## exposes only explicit descriptors as player-installable physical slots.
func _register_authored_physical_slots(room: Dictionary, room_id: String, slot_kind: String, slot_key: String, catalog: RefCounted) -> void:
	var slots: Array = _extract_authored_slots(room, slot_key)
	for index in range(slots.size()):
		if typeof(slots[index]) != TYPE_DICTIONARY:
			continue
		var info: Dictionary = slots[index] as Dictionary
		var profile_id: String = str(info.get("component_slot_profile_id", ""))
		if profile_id.is_empty() or catalog == null or not catalog.has_method("get_slot_profile"):
			continue
		var profile: Dictionary = catalog.call("get_slot_profile", profile_id)
		if profile.is_empty():
			continue
		var descriptor: Dictionary = info.duplicate(true)
		# Current catalog policy always overwrites any copied fit fields.
		for key in ["footprint_cells", "socket_type", "allowed_component_types"]:
			descriptor[key] = profile.get(key, [] if key != "socket_type" else "")
		descriptor["slot_id"] = "%s_%s_%d" % [room_id, slot_kind, index]
		descriptor["room_id"] = room_id
		descriptor["slot_kind"] = slot_kind
		descriptor["slot_index"] = index
		descriptor["occupied"] = false
		physical_slots.append(descriptor)


func _extract_authored_slots(room: Dictionary, slot_key: String) -> Array:
	var interior: Variant = room.get("interior_zones", null)
	if interior is Dictionary and _interior_zones_have_slots(interior as Dictionary):
		var interior_slots: Variant = (interior as Dictionary).get(slot_key, [])
		if interior_slots is Array:
			return _normalize_slots(interior_slots as Array, slot_key == "wall_slots")
		return []
	var direct: Variant = room.get(slot_key, null)
	if direct is Array and not (direct as Array).is_empty():
		return _normalize_slots(direct as Array, slot_key == "wall_slots")
	var zones: Variant = room.get("zones", {})
	if zones is Dictionary:
		var zone_slots: Variant = (zones as Dictionary).get(slot_key, [])
		if zone_slots is Array and not (zone_slots as Array).is_empty():
			return _normalize_slots(zone_slots as Array, slot_key == "wall_slots")
	return []


func _fill_slots(
		room: Dictionary,
		room_id: String,
		role: String,
		slot_kind: String,
		slot_key: String,
		catalog: RefCounted,
		rng: RandomNumberGenerator,
		used_keys: Dictionary,
		used_cells: Dictionary) -> int:
	var slots: Array = _extract_slots(room, slot_key)
	if slots.is_empty():
		return 0
	var choices: Array = catalog.call("role_set", role, slot_kind)
	if choices.is_empty():
		return 0
	var reserved: Dictionary = _reserved_cell_keys(room, room_id)
	var filled: int = 0
	var max_fill: int = MAX_WALL_FILLS if slot_kind == "wall" else MAX_CENTER_FILLS
	for i in range(slots.size()):
		if filled >= max_fill:
			break
		var key: String = "%s|%s|%d" % [room_id, slot_kind, i]
		if used_keys.has(key):
			continue
		var slot_info: Dictionary = slots[i] if typeof(slots[i]) == TYPE_DICTIONARY else {}
		var profile_id: String = str(slot_info.get("component_slot_profile_id", ""))
		var profile: Dictionary = catalog.call("get_slot_profile", profile_id) if catalog.has_method("get_slot_profile") else {}
		if profile_id.is_empty() or profile.is_empty():
			continue
		for profile_key in ["footprint_cells", "socket_type", "allowed_component_types"]:
			slot_info[profile_key] = profile.get(profile_key, [] if profile_key != "socket_type" else "")
		var cell_value: Variant = slot_info.get("cell", "")
		var parsed_cell: Array = LayoutSerializerScript.parse_slot_cell(cell_value)
		var cell_key: String = _cell_occupancy_key(room_id, parsed_cell)
		if not cell_key.is_empty() and (used_cells.has(cell_key) or reserved.has(cell_key)):
			continue
		var fitting_choices: Array = []
		for choice_v in choices:
			if not (choice_v is Dictionary):
				continue
			var choice_id: String = str((choice_v as Dictionary).get("component_id", ""))
			if catalog.has_method("validate_component_fit") and bool(catalog.call("validate_component_fit", choice_id, {
				"slot_kind": slot_kind,
				"component_slot_profile_id": profile_id,
			}).get("ok", false)):
				fitting_choices.append((choice_v as Dictionary).duplicate(true))
		var component_id: String = _weighted_pick(fitting_choices, rng)
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
		var stored_cell: Variant = parsed_cell if parsed_cell.size() >= 2 else cell_value
		var entry: Dictionary = {
			"component_instance_id": "%s_%s_%d" % [room_id, slot_kind, i],
			"component_id": component_id,
			"room_id": room_id,
			"slot_kind": slot_kind,
			"slot_index": i,
			"cell": stored_cell,
			"against_wall": bool(slot_info.get("against_wall", slot_kind == "wall")),
			"component_slot_profile_id": profile_id,
			"footprint_cells": slot_info.get("footprint_cells", []),
			"socket_type": str(slot_info.get("socket_type", "")),
			"allowed_component_types": slot_info.get("allowed_component_types", []),
			"condition": float(def.get("condition_default", 1.0)),
			"item_form": str(def.get("item_form", component_id)),
			"mass": float(def.get("mass", 10.0)),
			"linked_system": str(def.get("linked_system", "")),
			"linked_subcomponent": str(def.get("linked_subcomponent", "")),
			"mounted": true,
			"ship_mod_managed": false,
		}
		placed.append(entry)
		used_keys[key] = true
		if not cell_key.is_empty():
			used_cells[cell_key] = true
		filled += 1
	return filled


func _extract_slots(room: Dictionary, slot_key: String) -> Array:
	# REQ-FILL-001: interior_zones from WallDoorResolver / serializer first.
	# Serializer always emits the three keys, even as empty arrays — treat an
	# all-empty zone object as absent so floor-only rooms still synthesize.
	var interior: Variant = room.get("interior_zones", null)
	if interior is Dictionary and _interior_zones_have_slots(interior as Dictionary):
		var interior_slots: Variant = (interior as Dictionary).get(slot_key, [])
		if interior_slots is Array:
			return _normalize_slots(interior_slots as Array, slot_key == "wall_slots")
		return []
	# Legacy: slots may live on room root or under zones.
	var direct: Variant = room.get(slot_key, null)
	if direct is Array and not (direct as Array).is_empty():
		return _normalize_slots(direct as Array, slot_key == "wall_slots")
	var zones: Variant = room.get("zones", {})
	if zones is Dictionary:
		var z: Variant = (zones as Dictionary).get(slot_key, [])
		if z is Array and not (z as Array).is_empty():
			return _normalize_slots(z as Array, slot_key == "wall_slots")
	# Golden/hub layouts often only stamp floor structural_placements — synthesize
	# wall/center slots from floor cells so component population still runs.
	return _synthesize_slots_from_structure(room, slot_key)


func _interior_zones_have_slots(interior: Dictionary) -> bool:
	for key in ["wall_slots", "center_slots", "reserved_cells"]:
		var values: Variant = interior.get(key, [])
		if values is Array and not (values as Array).is_empty():
			return true
	return false


func _normalize_slots(raw: Array, against_wall: bool) -> Array:
	var out: Array = []
	for item in raw:
		var cell_value: Variant = item
		var wall_flag: bool = against_wall
		var extra: Dictionary = {}
		if typeof(item) == TYPE_DICTIONARY:
			var row: Dictionary = item
			cell_value = row.get("cell", "")
			wall_flag = bool(row.get("against_wall", against_wall))
			extra = row.duplicate(true)
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(cell_value)
		var entry: Dictionary = extra if not extra.is_empty() else {}
		entry["against_wall"] = wall_flag
		if parsed.size() >= 2:
			entry["cell"] = parsed
		else:
			entry["cell"] = cell_value
		out.append(entry)
	return out


func _reserved_cell_keys(room: Dictionary, room_id: String) -> Dictionary:
	var keys: Dictionary = {}
	var interior: Variant = room.get("interior_zones", {})
	if not (interior is Dictionary):
		return keys
	var reserved_v: Variant = (interior as Dictionary).get("reserved_cells", [])
	if not (reserved_v is Array):
		return keys
	for cell_v in (reserved_v as Array):
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(cell_v)
		var key: String = _cell_occupancy_key(room_id, parsed)
		if not key.is_empty():
			keys[key] = true
	return keys


func _cell_occupancy_key(room_id: String, cell: Array) -> String:
	if cell.size() < 2:
		return ""
	return "%s|%d|%d" % [room_id, int(cell[0]), int(cell[1])]


## Derive wall_slots / center_slots from floor structural placements (max 3 wall, 1 center).
func _synthesize_slots_from_structure(room: Dictionary, slot_key: String) -> Array:
	var floors: Array = []
	var placements_v: Variant = room.get("structural_placements", [])
	if typeof(placements_v) != TYPE_ARRAY:
		return []
	for p_v in (placements_v as Array):
		if typeof(p_v) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_v
		var kind: String = str(p.get("module_id", p.get("module", ""))).to_lower()
		if not (kind.begins_with("floor") or kind.find("floor") >= 0):
			continue
		var cell: String = str(p.get("name", p.get("cell", "")))
		var pos_v: Variant = p.get("world_position", null)
		floors.append({"cell": cell, "world_position": pos_v, "against_wall": slot_key == "wall_slots"})
	if floors.is_empty():
		return []
	if slot_key == "center_slots":
		return [floors[0]]
	if slot_key == "wall_slots":
		var out: Array = []
		var n: int = mini(3, floors.size())
		for i in range(n):
			var row: Dictionary = (floors[i] as Dictionary).duplicate(true)
			row["against_wall"] = true
			out.append(row)
		return out
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
	var dynamic_placed: Array = []
	for entry_v in placed:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = (entry_v as Dictionary).duplicate(true)
		# Fit authority belongs to the current generated slot + current catalog.
		for fit_key in ["footprint_cells", "socket_type", "allowed_component_types"]:
			entry.erase(fit_key)
		dynamic_placed.append(entry)
	return {
		"schema": "component_placement_v2",
		"seed": seed_value,
		"count": dynamic_placed.size(),
		"placed": dynamic_placed,
		"rejected_saved_components": rejected_saved_components.duplicate(true),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	seed_value = int(summary.get("seed", 0))
	var p: Variant = summary.get("placed", [])
	if typeof(p) != TYPE_ARRAY:
		return false
	placed = (p as Array).duplicate(true)
	# Legacy summaries may contain fit fields/physical_slots. Preserve dynamic
	# records for migration, but never restore those fields as fit authority.
	for index in range(placed.size()):
		if not (placed[index] is Dictionary):
			continue
		var entry: Dictionary = (placed[index] as Dictionary).duplicate(true)
		for fit_key in ["footprint_cells", "socket_type", "allowed_component_types"]:
			entry.erase(fit_key)
		placed[index] = entry
	physical_slots.clear()
	var rejected_v: Variant = summary.get("rejected_saved_components", [])
	rejected_saved_components = (rejected_v as Array).duplicate(true) if rejected_v is Array else []
	return true


## Rebuild current physical policy from the active layout, then overlay only
## saved component/mounted dynamics whose stable slot IDs still exist and fit.
func restore_from_layout(
		layout: Dictionary,
		catalog: RefCounted,
		p_seed: int,
		summary: Dictionary,
		occupied_cells: Dictionary = {}) -> bool:
	var saved_v: Variant = summary.get("placed", [])
	if not (saved_v is Array):
		return false
	var prior_rejected_v: Variant = summary.get("rejected_saved_components", [])
	var prior_rejected: Array = (prior_rejected_v as Array).duplicate(true) if prior_rejected_v is Array else []
	var saved_by_slot: Dictionary = {}
	for saved_entry_v in saved_v as Array:
		if not (saved_entry_v is Dictionary):
			continue
		var saved_entry: Dictionary = (saved_entry_v as Dictionary).duplicate(true)
		var saved_id: String = str(saved_entry.get("component_instance_id", ""))
		if not saved_id.is_empty():
			saved_by_slot[saved_id] = saved_entry
	populate(layout, catalog, p_seed, occupied_cells)
	rejected_saved_components = prior_rejected
	var generated_by_slot: Dictionary = {}
	for generated_v in placed:
		if generated_v is Dictionary:
			generated_by_slot[str((generated_v as Dictionary).get("component_instance_id", ""))] = generated_v
	var restored: Array = []
	var restored_slot_ids: Dictionary = {}
	for slot_v in physical_slots:
		if not (slot_v is Dictionary):
			continue
		var slot: Dictionary = slot_v as Dictionary
		var slot_id: String = str(slot.get("slot_id", ""))
		var saved: Dictionary = saved_by_slot.get(slot_id, {}) as Dictionary
		if saved.is_empty():
			if generated_by_slot.has(slot_id):
				restored.append((generated_by_slot[slot_id] as Dictionary).duplicate(true))
			continue
		restored_slot_ids[slot_id] = true
		var component_id: String = str(saved.get("component_id", ""))
		var fit: Dictionary = catalog.call("validate_component_fit", component_id, slot) if catalog != null and catalog.has_method("validate_component_fit") else {"ok": false, "reason": "missing_fit_contract"}
		if not bool(fit.get("ok", false)):
			_quarantine_saved(slot_id, str(fit.get("reason", "incompatible_fit")), saved)
			continue
		if not bool(saved.get("mounted", true)):
			var dismounted: Dictionary = _entry_from_saved(slot, saved, catalog)
			if not dismounted.is_empty():
				dismounted["mounted"] = false
				restored.append(dismounted)
			continue
		var mounted: Dictionary = _entry_from_saved(slot, saved, catalog)
		if not mounted.is_empty():
			mounted["mounted"] = true
			restored.append(mounted)
	for saved_slot_v in saved_by_slot.keys():
		var saved_slot_id: String = str(saved_slot_v)
		if not restored_slot_ids.has(saved_slot_id):
			_quarantine_saved(saved_slot_id, "slot_removed", saved_by_slot[saved_slot_v] as Dictionary)
	placed = restored
	return not physical_slots.is_empty()


func _quarantine_saved(slot_id: String, reason: String, saved: Dictionary) -> void:
	rejected_saved_components.append({
		"slot_id": slot_id,
		"reason": reason,
		"saved_entry": saved.duplicate(true),
	})


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


func get_physical_slot(slot_id: String) -> Dictionary:
	for slot_v in physical_slots:
		if slot_v is Dictionary and str((slot_v as Dictionary).get("slot_id", "")) == slot_id:
			return (slot_v as Dictionary).duplicate(true)
	return {}


func _entry_from_saved(slot: Dictionary, saved: Dictionary, catalog: RefCounted) -> Dictionary:
	var component_id: String = str(saved.get("component_id", ""))
	if catalog == null or not catalog.has_method("has_component") or not bool(catalog.call("has_component", component_id)):
		return {}
	var definition: Dictionary = catalog.call("get_component", component_id)
	var entry: Dictionary = {
		"component_instance_id": str(slot.get("slot_id", "")),
		"component_id": component_id,
		"room_id": str(slot.get("room_id", "")),
		"slot_kind": str(slot.get("slot_kind", "")),
		"slot_index": int(slot.get("slot_index", -1)),
		"cell": slot.get("cell", ""),
		"against_wall": bool(slot.get("against_wall", false)),
		"component_slot_profile_id": str(slot.get("component_slot_profile_id", "")),
		"footprint_cells": slot.get("footprint_cells", []),
		"socket_type": str(slot.get("socket_type", "")),
		"allowed_component_types": slot.get("allowed_component_types", []),
		"condition": clampf(float(saved.get("condition", definition.get("condition_default", 1.0))), 0.0, 1.0),
		"item_form": str(definition.get("item_form", component_id)),
		"mass": maxf(0.0, float(definition.get("mass", 0.0))),
		"linked_system": str(definition.get("linked_system", "")),
		"linked_subcomponent": str(definition.get("linked_subcomponent", "")),
		"mounted": bool(saved.get("mounted", true)),
		"ship_mod_managed": bool(saved.get("ship_mod_managed", false)),
	}
	var source_lot_v: Variant = saved.get("source_lot", null)
	if source_lot_v is Dictionary and _valid_source_lot(source_lot_v as Dictionary, str(entry.get("item_form", ""))):
		entry["source_lot"] = (source_lot_v as Dictionary).duplicate(true)
		entry["source_lot_id"] = str((source_lot_v as Dictionary).get("lot_id", ""))
		entry["condition"] = float((source_lot_v as Dictionary).get("condition", entry.get("condition", 1.0)))
	return entry


## Converts generated/authored placement records into stable physical-slot
## descriptors for a specific ship.  These are the only mount targets P11 accepts.
func get_physical_slot_descriptors(ship_id: String) -> Array:
	var descriptors: Array = []
	if ship_id.is_empty():
		return descriptors
	var mounted_by_slot: Dictionary = {}
	for entry_v in placed:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v as Dictionary
		var slot_id: String = str(entry.get("component_instance_id", ""))
		var kind: String = str(entry.get("slot_kind", ""))
		if slot_id.is_empty() or kind.is_empty():
			continue
		mounted_by_slot[slot_id] = bool(entry.get("mounted", true))
	if not physical_slots.is_empty():
		for descriptor_v in physical_slots:
			if typeof(descriptor_v) != TYPE_DICTIONARY:
				continue
			var descriptor: Dictionary = (descriptor_v as Dictionary).duplicate(true)
			var descriptor_id: String = str(descriptor.get("slot_id", ""))
			if descriptor_id.is_empty():
				continue
			descriptor["ship_id"] = ship_id
			descriptor["occupied"] = bool(mounted_by_slot.get(descriptor_id, false))
			if descriptor["occupied"]:
				var mounted_entry: Dictionary = get_entry(descriptor_id)
				for dynamic_key in ["component_id", "item_form", "condition", "mass", "linked_system", "linked_subcomponent"]:
					descriptor[dynamic_key] = mounted_entry.get(dynamic_key, "")
			descriptors.append(descriptor)
		return descriptors
	return descriptors


## Refresh exact current profile data for already-authored descriptors. Missing
## profile IDs remain unusable; slot_kind is deliberately never consulted.
func ensure_physical_slot_profiles(catalog: RefCounted) -> void:
	if catalog == null or not catalog.has_method("get_slot_profile"):
		return
	for index in range(physical_slots.size()):
		if not (physical_slots[index] is Dictionary):
			continue
		var existing: Dictionary = (physical_slots[index] as Dictionary).duplicate(true)
		var profile: Dictionary = catalog.call("get_slot_profile", str(existing.get("component_slot_profile_id", "")))
		if profile.is_empty():
			continue
		for key in ["footprint_cells", "socket_type", "allowed_component_types"]:
			existing[key] = profile.get(key, [] if key != "socket_type" else "")
		physical_slots[index] = existing


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
	var source_lot_v: Variant = e.get("source_lot", null)
	if source_lot_v is Dictionary and _valid_source_lot(source_lot_v as Dictionary, item_form):
		out["item_lot"] = (source_lot_v as Dictionary).duplicate(true)
	return out


## Roll back a coordinator-side destination failure without reconstructing or
## replacing the authoritative mounted record.
func restore_dismounted(instance_id: String) -> bool:
	var idx: int = find_index(instance_id)
	if idx < 0:
		return false
	var entry: Dictionary = placed[idx]
	if bool(entry.get("mounted", true)):
		return false
	entry["mounted"] = true
	placed[idx] = entry
	return true


## Remount into a free or previously emptied slot. Consumes one item_form from inventory dict.
## inventory is item_id -> qty. Mutates inventory on success.
func mount(
		item_form: String,
		room_id: String,
		slot_kind: String,
		slot_index: int,
		inventory: Dictionary,
		catalog: RefCounted = null,
		source_lot: Dictionary = {}) -> Dictionary:
	return mount_by_slot_id(
		"%s_%s_%d" % [room_id, slot_kind, slot_index], item_form, inventory, catalog, source_lot)


func mount_by_slot_id(
		slot_id: String,
		item_form: String,
		inventory: Dictionary,
		catalog: RefCounted,
		source_lot: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"instance_id": "",
		"item_form": item_form,
	}
	if item_form.is_empty():
		out["reason"] = "no_item"
		return out
	if catalog == null or not catalog.has_method("component_id_for_item_form") or not catalog.has_method("get_component"):
		out["reason"] = "physical_slot_required"
		return out
	var slot: Dictionary = get_physical_slot(slot_id)
	if slot.is_empty():
		out["reason"] = "unknown_slot"
		return out
	var component_id: String = str(catalog.call("component_id_for_item_form", item_form))
	if component_id.is_empty():
		out["reason"] = "unknown_component"
		return out
	var definition: Dictionary = catalog.call("get_component", component_id)
	if definition.is_empty() or str(definition.get("item_form", component_id)) != item_form:
		out["reason"] = "unknown_component"
		return out
	var fit: Dictionary = catalog.call("validate_component_fit", component_id, slot) if catalog.has_method("validate_component_fit") else {"ok": false, "reason": "missing_fit_contract"}
	if not bool(fit.get("ok", false)):
		out["reason"] = str(fit.get("reason", "incompatible_fit"))
		return out
	if int(inventory.get(item_form, 0)) < 1:
		out["reason"] = "missing_item"
		return out
	if not source_lot.is_empty() and not _valid_source_lot(source_lot, item_form):
		out["reason"] = "invalid_source_lot"
		return out
	# Prefer remounting an existing dismounted entry in this slot.
	var target_idx: int = -1
	for i in range(placed.size()):
		if typeof(placed[i]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = placed[i]
		if str(e.get("component_instance_id", "")) != slot_id:
			continue
		target_idx = i
		break
	if target_idx >= 0:
		var existing: Dictionary = placed[target_idx]
		if bool(existing.get("mounted", true)):
			out["reason"] = "slot_occupied"
			return out
	var mounted: Dictionary = _entry_from_saved(slot, {
		"component_id": component_id,
		"condition": definition.get("condition_default", 1.0),
		"mounted": true,
		"ship_mod_managed": true,
	}, catalog)
	if mounted.is_empty():
		out["reason"] = "unknown_component"
		return out
	if not source_lot.is_empty():
		mounted["source_lot"] = source_lot.duplicate(true)
		mounted["source_lot_id"] = str(source_lot.get("lot_id", ""))
		mounted["condition"] = float(source_lot.get("condition", mounted.get("condition", 1.0)))
	if target_idx >= 0:
		placed[target_idx] = mounted
	else:
		placed.append(mounted)
	inventory[item_form] = int(inventory.get(item_form, 0)) - 1
	if int(inventory[item_form]) <= 0:
		inventory.erase(item_form)
	out["ok"] = true
	out["instance_id"] = slot_id
	out["component_id"] = component_id
	return out


static func _valid_source_lot(lot: Dictionary, expected_item_form: String) -> bool:
	if str(lot.get("lot_id", "")).is_empty() or str(lot.get("item_id", "")) != expected_item_form \
			or int(lot.get("quantity", 0)) != 1 or str(lot.get("quality_tier", "")).is_empty():
		return false
	if not (lot.get("origin", null) is Dictionary):
		return false
	var score_v: Variant = lot.get("quality_score", null)
	var condition_v: Variant = lot.get("condition", null)
	if (typeof(score_v) not in [TYPE_INT, TYPE_FLOAT]) or (typeof(condition_v) not in [TYPE_INT, TYPE_FLOAT]):
		return false
	var score: float = float(score_v)
	var condition: float = float(condition_v)
	if not is_finite(score) or score < 0.0 or score > 1.0 \
			or not is_finite(condition) or condition < 0.0 or condition > 1.0:
		return false
	return str(lot.get("quality_tier")) == QualityTierResolverScript.tier_for_score(score)


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
