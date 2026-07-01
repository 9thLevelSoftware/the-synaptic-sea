extends RefCounted
class_name GameplaySliceBuilder

# Builds a gameplay_slice Dictionary from a completed layout Dictionary.
# This populates start/goal rooms, objectives, and empty hazard zone arrays.
#
# The layout pipeline produces structural geometry only.
# This builder adds the gameplay layer on top.

const CONNECTIVE_ROLES: Array[String] = [
	"corridor", "main_spine", "hub", "ramp", "elevator", "airlock", "dock",
]

const RoomVariantSelectorScript := preload("res://scripts/procgen/room_variant_selector.gd")
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

	var objectives: Array = []
	var sequence: int = 1

	# Place salvage objectives in non-connective rooms (cargo, engineering, etc.)
	for room in rooms:
		var rid: String = str(room.get("id", ""))
		var role: String = str(room.get("room_role", ""))
		if rid == start_room or rid == goal_room:
			continue
		if role in CONNECTIVE_ROLES:
			continue
		var approach_cell: Array = _get_first_floor_cell(room)
		if approach_cell.is_empty():
			continue
		objectives.append({
			"id": "obj_salvage_%s" % rid,
			"sequence": sequence,
			"type": "salvage",
			"kind": "single",
			"room_id": rid,
			"approach_cell": approach_cell,
			"loot_table": _loot_table_for_room(room, _salvage_loot_table_for_role(role)),
		})
		sequence += 1

	# Always add a "reach goal" objective as the final objective
	var goal_room_dict: Dictionary = _find_room(rooms, goal_room)
	var goal_approach: Array = _get_first_floor_cell(goal_room_dict)
	if goal_approach.is_empty():
		push_warning("GameplaySliceBuilder: goal room '%s' has no floor cells; using [0,0,0] fallback" % goal_room)
		goal_approach = [0, 0, 0]
	objectives.append({
		"id": "obj_reach_goal",
		"sequence": sequence,
		"type": "interact",
		"kind": "single",
		"room_id": goal_room,
		"approach_cell": goal_approach,
	})

	var loot_containers: Array = []
	var container_index: int = 0
	for room in rooms:
		var rid2: String = str(room.get("id", ""))
		var role2: String = str(room.get("room_role", ""))
		if rid2 == start_room or rid2 == goal_room:
			continue
		if role2 in CONNECTIVE_ROLES:
			continue
		var cell2: Array = _get_first_floor_cell(room)
		if cell2.is_empty():
			continue
		var kind2: String = "generic_locker" if container_index % 2 == 1 else "generic_crate"
		loot_containers.append({
			"id": "loot_%s" % rid2,
			"kind": kind2,
			"room_id": rid2,
			"approach_cell": cell2,
			"loot_table": _loot_table_for_room(room, kind2),
		})
		container_index += 1

	return {
		"start_room": start_room,
		"goal_room": goal_room,
		"objectives": objectives,
		"loot_containers": loot_containers,
		"fire_zones": [],
		"arc_zones": [],
		"breach_zones": [],
	}


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
