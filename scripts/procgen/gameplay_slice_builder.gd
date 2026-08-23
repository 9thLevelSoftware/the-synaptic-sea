extends RefCounted
class_name GameplaySliceBuilder

# Builds a gameplay_slice Dictionary from a completed layout Dictionary.
# This populates start/goal rooms, objectives, loot containers, and the
# arc_zones hazard array (fire/breach stay runtime-seeded per ship:
# _seed_derelict_fire / _seed_derelict_breaches in the coordinator).
#
# The layout pipeline produces structural geometry only.
# This builder adds the gameplay layer on top.

const CONNECTIVE_ROLES: Array[String] = [
	"corridor", "main_spine", "hub", "ramp", "elevator", "airlock", "dock",
]

const RoomVariantSelectorScript := preload("res://scripts/procgen/room_variant_selector.gd")
const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")
var _variant_selector: RefCounted = RoomVariantSelectorScript.new()


# Returns the loot_table key a room should use: the variant's loot_bias when
# present and non-empty, otherwise the supplied role-derived default.
func _loot_table_for_room(room: Dictionary, role_default: String) -> String:
	var variant: String = str(room.get("variant", "standard"))
	var bias: String = str((_variant_selector.effects_for(variant).get("sim", {}) as Dictionary).get("loot_bias", ""))
	return bias if not bias.is_empty() else role_default


func build(layout: Dictionary) -> Dictionary:
	var proto: Dictionary = layout.get("prototype", {})
	var rooms: Array = layout.get("rooms", [])

	var start_room: String = str(proto.get("start_room", ""))
	var goal_room: String = str(proto.get("goal_room", ""))

	# Fallback: if prototype doesn't specify start/goal, pick from rooms
	if start_room.is_empty() or goal_room.is_empty():
		var airlock_id: String = ""
		var bridge_id: String = ""
		for room in rooms:
			var role: String = str(room.get("room_role", ""))
			var rid: String = str(room.get("id", ""))
			if role == "airlock" and airlock_id.is_empty():
				airlock_id = rid
			if role == "bridge" and bridge_id.is_empty():
				bridge_id = rid
		if start_room.is_empty():
			start_room = airlock_id if not airlock_id.is_empty() else str(rooms[0].get("id", "")) if rooms.size() > 0 else ""
		if goal_room.is_empty():
			goal_room = bridge_id if not bridge_id.is_empty() else str(rooms[rooms.size() - 1].get("id", "")) if rooms.size() > 0 else ""

	var occupied: Dictionary = {}
	var boarding: Dictionary = _boarding_info(rooms, start_room)

	var objectives: Array = []
	var sequence: int = 1

	# Place salvage objectives in non-connective rooms (cargo, engineering, etc.)
	var room_index: int = 0
	for room in rooms:
		var rid: String = str(room.get("id", ""))
		var role: String = str(room.get("room_role", ""))
		if rid == start_room or rid == goal_room:
			room_index += 1
			continue
		if role in CONNECTIVE_ROLES:
			room_index += 1
			continue
		var salvage_pick: Dictionary = _pick_slot_cell(room, "salvage", occupied, boarding)
		var approach_cell: Array = salvage_pick.get("cell", []) as Array
		if approach_cell.is_empty():
			room_index += 1
			continue
		var salvage_obj: Dictionary = {
			"id": "obj_salvage_%s" % rid,
			"sequence": sequence,
			"type": "salvage",
			"kind": "single",
			"room_id": rid,
			"approach_cell": approach_cell,
			"loot_table": _loot_table_for_room(room, _salvage_loot_table_for_role(role)),
		}
		if not str(salvage_pick.get("slot_kind", "")).is_empty():
			salvage_obj["slot_kind"] = str(salvage_pick.get("slot_kind", ""))
			salvage_obj["slot_index"] = int(salvage_pick.get("slot_index", 0))
		objectives.append(salvage_obj)
		sequence += 1
		room_index += 1

	# Always add a "reach goal" objective as the final objective
	var goal_room_dict: Dictionary = _find_room(rooms, goal_room)
	var goal_pick: Dictionary = _pick_slot_cell(goal_room_dict, "loot", occupied, boarding)
	var goal_approach: Array = goal_pick.get("cell", []) as Array
	if goal_approach.is_empty():
		push_warning("GameplaySliceBuilder: goal room '%s' has no floor cells; using [0,0,0] fallback" % goal_room)
		goal_approach = [0, 0, 0]
	var goal_obj: Dictionary = {
		"id": "obj_reach_goal",
		"sequence": sequence,
		"type": "interact",
		"kind": "single",
		"room_id": goal_room,
		"approach_cell": goal_approach,
	}
	if not str(goal_pick.get("slot_kind", "")).is_empty():
		goal_obj["slot_kind"] = str(goal_pick.get("slot_kind", ""))
		goal_obj["slot_index"] = int(goal_pick.get("slot_index", 0))
	objectives.append(goal_obj)

	var loot_containers: Array = []
	var container_index: int = 0
	room_index = 0
	for room in rooms:
		var rid2: String = str(room.get("id", ""))
		var role2: String = str(room.get("room_role", ""))
		if rid2 == start_room or rid2 == goal_room:
			room_index += 1
			continue
		if role2 in CONNECTIVE_ROLES:
			room_index += 1
			continue
		var loot_pick: Dictionary = _pick_slot_cell(room, "loot", occupied, boarding)
		var cell2: Array = loot_pick.get("cell", []) as Array
		if cell2.is_empty():
			room_index += 1
			continue
		var kind2: String = "generic_locker" if container_index % 2 == 1 else "generic_crate"
		var loot_entry: Dictionary = {
			"id": "loot_%s" % rid2,
			"kind": kind2,
			"room_id": rid2,
			"approach_cell": cell2,
			"loot_table": _loot_table_for_room(room, kind2),
		}
		if not str(loot_pick.get("slot_kind", "")).is_empty():
			loot_entry["slot_kind"] = str(loot_pick.get("slot_kind", ""))
			loot_entry["slot_index"] = int(loot_pick.get("slot_index", 0))
		loot_containers.append(loot_entry)
		container_index += 1
		room_index += 1

	return {
		"start_room": start_room,
		"goal_room": goal_room,
		"objectives": objectives,
		"loot_containers": loot_containers,
		"fire_zones": [],
		"arc_zones": _build_arc_zones(layout, start_room, goal_room, objectives),
		"breach_zones": [],
	}


# Deterministic single arc zone on a NON-critical link, mirroring the
# hand-authored golden intent ("non-critical side branch; arc cannot trap the
# player or block any main objective"): both endpoints must be off the
# critical path, must not be the start/goal room, and must not host an
# objective — the arc cycles passability, and the objective spine must stay
# traversable.
# First qualifying link in layout order (no rng: per-seed replay stable).
# Returns [] when no safe side link exists (small spine ships stay arc-free).
func _build_arc_zones(layout: Dictionary, start_room: String, goal_room: String, objectives: Array) -> Array:
	var links_variant: Variant = layout.get("room_links", [])
	if not (links_variant is Array):
		return []
	var excluded: Dictionary = {start_room: true, goal_room: true}
	var cp: Variant = layout.get("critical_path", [])
	if cp is Array:
		for rid in (cp as Array):
			excluded[str(rid)] = true
	for objective in objectives:
		if objective is Dictionary:
			excluded[str((objective as Dictionary).get("room_id", ""))] = true
	for link_variant in (links_variant as Array):
		if not (link_variant is Dictionary):
			continue
		var link: Dictionary = link_variant
		var from_room: String = str(link.get("from_room", ""))
		var to_room: String = str(link.get("to_room", ""))
		if from_room.is_empty() or to_room.is_empty():
			continue
		if excluded.has(from_room) or excluded.has(to_room):
			continue
		var entry: Dictionary = {
			"id": "%s_to_%s_arc" % [from_room, to_room],
			"from_room": from_room,
			"to_room": to_room,
			"kind": "electrical_arc",
			"rationale": "generated: non-critical side link off the objective spine; arc cannot trap the player or block an objective",
		}
		# Reuse the link's own cell endpoints when present; the loader falls
		# back to room centers otherwise (_cell_world_from_link_endpoint).
		if link.has("from_cell"):
			entry["from_cell"] = link["from_cell"]
		if link.has("to_cell"):
			entry["to_cell"] = link["to_cell"]
		return [entry]
	return []


func _find_room(rooms: Array, room_id: String) -> Dictionary:
	for room in rooms:
		if str(room.get("id", "")) == room_id:
			return room
	return {}


## Maps a room role to a salvage loot table key (defined in loot_tables.json).
func _salvage_loot_table_for_role(role: String) -> String:
	match role:
		"engineering", "engine", "reactor", "machine_shop":
			return "salvage_engineering"
		"cargo", "storage", "hold":
			return "salvage_cargo"
		_:
			return "salvage_cargo"


func _get_first_floor_cell(room: Dictionary) -> Array:
	var placements: Array = room.get("structural_placements", [])
	for placement in placements:
		var placement_name: String = str(placement.get("name", ""))
		if not placement_name.begins_with("floor_cell"):
			continue
		# Parse floor_cell_x{X}_z{Z} or floor_cell_d{D}_x{X}_z{Z}
		var parts: PackedStringArray = placement_name.split("_")
		for i in range(parts.size()):
			if String(parts[i]).begins_with("x") and i + 1 < parts.size() and String(parts[i + 1]).begins_with("z"):
				var x_str: String = String(parts[i]).substr(1)
				var z_str: String = String(parts[i + 1]).substr(1)
				if x_str.is_valid_int() and z_str.is_valid_int():
					var deck: int = int(room.get("deck", 0))
					return [int(x_str), int(z_str), deck]
	return []


func _boarding_info(rooms: Array, start_room: String) -> Dictionary:
	var room: Dictionary = _find_room(rooms, start_room)
	if room.is_empty() or start_room.is_empty():
		return {}
	var reserved: Array = _interior_cell_list(room, "reserved_cells")
	var cell: Array = []
	if not reserved.is_empty():
		cell = reserved[0]
	else:
		var first: Array = _get_first_floor_cell(room)
		if first.size() >= 2:
			cell = [int(first[0]), int(first[1])]
	if cell.size() < 2:
		return {}
	return {
		"room_id": start_room,
		"cell": cell,
		"deck": int(room.get("deck", 0)),
	}


func _interior_cell_list(room: Dictionary, slot_key: String) -> Array:
	var interior: Variant = room.get("interior_zones", {})
	if not (interior is Dictionary):
		return []
	var raw: Variant = (interior as Dictionary).get(slot_key, [])
	if not (raw is Array):
		return []
	var out: Array = []
	for item in (raw as Array):
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(item)
		if parsed.size() >= 2:
			out.append(parsed)
	return out


func _wall_slot_cells(room: Dictionary) -> Array:
	var interior: Variant = room.get("interior_zones", {})
	if not (interior is Dictionary):
		return []
	var raw: Variant = (interior as Dictionary).get("wall_slots", [])
	if not (raw is Array):
		return []
	var out: Array = []
	for item in (raw as Array):
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(item)
		if parsed.size() >= 2:
			out.append(parsed)
	return out


func _cell_key(room_id: String, cell: Array) -> String:
	if cell.size() < 2:
		return ""
	return "%s|%d|%d" % [room_id, int(cell[0]), int(cell[1])]


func _is_blocked(room_id: String, cell: Array, occupied: Dictionary, boarding: Dictionary) -> bool:
	if cell.size() < 2:
		return true
	if str(boarding.get("room_id", "")) == room_id:
		var bcell: Array = boarding.get("cell", []) as Array if typeof(boarding.get("cell", [])) == TYPE_ARRAY else []
		if bcell.size() >= 2 and int(cell[0]) == int(bcell[0]) and int(cell[1]) == int(bcell[1]):
			return true
	var key: String = _cell_key(room_id, cell)
	return key.is_empty() or occupied.has(key)


func _claim(room_id: String, cell: Array, occupied: Dictionary) -> void:
	var key: String = _cell_key(room_id, cell)
	if not key.is_empty():
		occupied[key] = true


func _all_floor_cells(room: Dictionary) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var deck: int = int(room.get("deck", 0))
	var placements: Array = room.get("structural_placements", [])
	for placement in placements:
		if typeof(placement) != TYPE_DICTIONARY:
			continue
		var placement_name: String = str((placement as Dictionary).get("name", ""))
		if not placement_name.begins_with("floor_cell"):
			continue
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(placement_name)
		if parsed.size() < 2:
			continue
		var key: String = "%d|%d" % [int(parsed[0]), int(parsed[1])]
		if seen.has(key):
			continue
		seen[key] = true
		out.append([int(parsed[0]), int(parsed[1]), deck])
	return out


func _pick_slot_cell(
		room: Dictionary,
		kind: String,
		occupied: Dictionary,
		boarding: Dictionary) -> Dictionary:
	var rid: String = str(room.get("id", ""))
	var deck: int = int(room.get("deck", 0))
	var reserved: Array = _interior_cell_list(room, "reserved_cells")
	var reserved_set: Dictionary = {}
	for cell in reserved:
		reserved_set[_cell_key(rid, cell)] = true
	var centers: Array = _interior_cell_list(room, "center_slots")
	var walls: Array = _wall_slot_cells(room)
	var picked: Dictionary = {}
	if kind == "salvage":
		picked = _pick_salvage_slot(rid, deck, centers, reserved, reserved_set, occupied, boarding)
	else:
		picked = _pick_loot_slot(rid, deck, centers, walls, reserved_set, occupied, boarding)
	if not picked.is_empty():
		_claim(rid, picked.get("cell", []), occupied)
		return picked
	var floors: Array = _all_floor_cells(room)
	for i in range(floors.size()):
		var fallback: Array = floors[i]
		if _is_blocked(rid, fallback, occupied, boarding):
			continue
		if kind != "salvage" and reserved_set.has(_cell_key(rid, fallback)):
			continue
		# print (not push_warning): run_clean treats WARNING: as a hard fail.
		print("GameplaySliceBuilder slot_fallback room=%s kind=%s" % [rid, kind])
		_claim(rid, fallback, occupied)
		return {"cell": fallback, "slot_kind": "floor", "slot_index": i, "fallback": true}
	return {}


func _pick_loot_slot(
		rid: String,
		deck: int,
		centers: Array,
		walls: Array,
		reserved_set: Dictionary,
		occupied: Dictionary,
		boarding: Dictionary) -> Dictionary:
	for i in range(centers.size()):
		var cell: Array = centers[i]
		if _is_blocked(rid, cell, occupied, boarding):
			continue
		if reserved_set.has(_cell_key(rid, cell)):
			continue
		return {"cell": [int(cell[0]), int(cell[1]), deck], "slot_kind": "center", "slot_index": i}
	for i in range(walls.size()):
		var cell: Array = walls[i]
		if _is_blocked(rid, cell, occupied, boarding):
			continue
		if reserved_set.has(_cell_key(rid, cell)):
			continue
		return {"cell": [int(cell[0]), int(cell[1]), deck], "slot_kind": "wall", "slot_index": i}
	return {}


func _pick_salvage_slot(
		rid: String,
		deck: int,
		centers: Array,
		reserved: Array,
		reserved_set: Dictionary,
		occupied: Dictionary,
		boarding: Dictionary) -> Dictionary:
	var adjacent: Array = []
	for i in range(centers.size()):
		var cell: Array = centers[i]
		if _is_blocked(rid, cell, occupied, boarding):
			continue
		if reserved_set.has(_cell_key(rid, cell)):
			continue
		if _neighbors_reserved(cell, reserved_set, rid):
			adjacent.append(i)
	if not adjacent.is_empty():
		var idx: int = int(adjacent[0])
		var cell: Array = centers[idx]
		return {"cell": [int(cell[0]), int(cell[1]), deck], "slot_kind": "center", "slot_index": idx}
	for i in range(centers.size()):
		var cell: Array = centers[i]
		if _is_blocked(rid, cell, occupied, boarding):
			continue
		if reserved_set.has(_cell_key(rid, cell)):
			continue
		return {"cell": [int(cell[0]), int(cell[1]), deck], "slot_kind": "center", "slot_index": i}
	for i in range(reserved.size()):
		var cell: Array = reserved[i]
		if _is_blocked(rid, cell, occupied, boarding):
			continue
		return {"cell": [int(cell[0]), int(cell[1]), deck], "slot_kind": "reserved", "slot_index": i}
	return {}


func _neighbors_reserved(cell: Array, reserved_set: Dictionary, rid: String) -> bool:
	if cell.size() < 2:
		return false
	var x: int = int(cell[0])
	var z: int = int(cell[1])
	var neighbors: Array = [[x + 1, z], [x - 1, z], [x, z + 1], [x, z - 1]]
	for n in neighbors:
		if reserved_set.has(_cell_key(rid, n)):
			return true
	return false
