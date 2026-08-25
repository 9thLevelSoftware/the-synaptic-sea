extends RefCounted
class_name LifeBoatBuilder

# Builds the fixed life boat layout. The life boat is always the same
# — 3 rooms in a linear arrangement:
#
#   [engine_bay] — [airlock] — [cockpit]
#
# The airlock is the connection point to the derelict's dock.
# The cockpit has flight controls and scanner.
# The engine bay has engineering, maintenance, and life support.
#
# This is NOT procgen — the occupancy is hand-authored and deterministic.
# Geometry comes from StructuralEdgeCompiler, same contract as derelicts.

const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")

const SCHEMA_VERSION: String = "1.2.0"
const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0
const DEFAULT_KIT_ID: String = "ship_structural_v0"
const DEFAULT_KIT_PATH: String = "res://data/kits/ship_structural_v0.json"

# Life boat room definitions. Order matters — index 0 is the airlock
# (dock connection point).
# Layout: linear chain along X axis (bow = +X, stern = -X)
#   cockpit_01 at x=1 (bow), airlock_01 at x=0 (mid), engine_bay_01 at x=-1 (stern)
const ROOMS: Array[Dictionary] = [
	{"id": "airlock_01", "role": "airlock", "deck": 0},
	{"id": "cockpit_01", "role": "bridge", "deck": 0},
	{"id": "engine_bay_01", "role": "engineering", "deck": 0},
]

# Fixed grid positions (cell x, cell z) for each room. Single-cell rooms.
const ROOM_CELL_X: Dictionary = {
	"airlock_01": 0,
	"cockpit_01": 1,
	"engine_bay_01": -1,
}
const ROOM_CELL_Z: Dictionary = {
	"airlock_01": 0,
	"cockpit_01": 0,
	"engine_bay_01": 0,
}


# Builds the life boat as a Node3D tree. Returns a Node3D named
# "LifeBoat" with a ShipStructure child and one room node per id.
# Wrappers are instanced from the compiled structural_plan.
static func build(biome: String = "") -> Node3D:
	var layout: Dictionary = build_layout(biome)
	var plan_variant: Variant = layout.get("structural_plan", null)
	if typeof(plan_variant) != TYPE_DICTIONARY or (plan_variant as Dictionary).is_empty():
		push_error("LifeBoatBuilder: missing validated structural_plan")
		return null
	var module_to_scene: Dictionary = _module_scene_map(str(layout.get("kit_id", DEFAULT_KIT_ID)))
	if module_to_scene.is_empty():
		push_error("LifeBoatBuilder: kit has no wrapper scenes")
		return null

	var structure: Node3D = Node3D.new()
	structure.name = "ShipStructure"
	var room_nodes: Dictionary = {}
	for room_def in ROOMS:
		var rid: String = str(room_def["id"])
		var room_node: Node3D = Node3D.new()
		room_node.name = rid
		var cx: int = int(ROOM_CELL_X[rid])
		var cz: int = int(ROOM_CELL_Z[rid])
		room_node.position = Vector3(float(cx) * CELL_SIZE, float(int(room_def["deck"])) * DECK_HEIGHT, float(cz) * CELL_SIZE)
		structure.add_child(room_node)
		room_nodes[rid] = room_node

	var plan: Dictionary = plan_variant
	if not _instance_plan_records(plan.get("floor_placements", []), module_to_scene, room_nodes, structure):
		structure.free()
		return null
	if not _instance_plan_records(plan.get("placements", []), module_to_scene, room_nodes, structure):
		structure.free()
		return null
	if not _instance_plan_records(plan.get("ceiling_placements", []), module_to_scene, room_nodes, structure):
		structure.free()
		return null

	var root: Node3D = Node3D.new()
	root.name = "LifeBoat"
	root.add_child(structure)
	return root


# Returns a layout Dictionary in LayoutSerializer schema v1.2.0 format.
# Occupancy is three shared-edge cells; portals sit on the two real seams.
static func build_layout(biome: String = "") -> Dictionary:
	var kit_id: String = _kit_id_for_biome(biome)
	var rooms_array: Array = []
	for room_def in ROOMS:
		var rid: String = room_def["id"]
		var role: String = room_def["role"]
		var deck: int = room_def["deck"]
		var cx: int = ROOM_CELL_X[rid]
		var cz: int = ROOM_CELL_Z[rid]
		var world_x: float = float(cx) * CELL_SIZE
		var world_y: float = float(deck) * DECK_HEIGHT
		var world_z: float = float(cz) * CELL_SIZE
		rooms_array.append({
			"id": rid,
			"room_role": role,
			"role": role,
			"deck": deck,
			"cells": [[cx, cz]],
			"footprint": [1, 1],
			"structural_placements": [],
			"portals": [],
			"interior_zones": {},
			"motif_requests": [],
			"world_origin": [world_x, world_y, world_z],
		})

	var portals: Array = [
		{
			"id": "airlock_01_to_cockpit_01",
			"from_room": "airlock_01",
			"to_room": "cockpit_01",
			"from_cell": [ROOM_CELL_X["airlock_01"], ROOM_CELL_Z["airlock_01"], 0],
			"to_cell": [ROOM_CELL_X["cockpit_01"], ROOM_CELL_Z["cockpit_01"], 0],
			"module_id": "doorway_frame_open_1x1",
			"state": "DOOR",
		},
		{
			"id": "airlock_01_to_engine_bay_01",
			"from_room": "airlock_01",
			"to_room": "engine_bay_01",
			"from_cell": [ROOM_CELL_X["airlock_01"], ROOM_CELL_Z["airlock_01"], 0],
			"to_cell": [ROOM_CELL_X["engine_bay_01"], ROOM_CELL_Z["engine_bay_01"], 0],
			"module_id": "doorway_frame_open_1x1",
			"state": "DOOR",
		},
	]
	var room_links: Array = []
	for portal_variant in portals:
		var portal: Dictionary = portal_variant
		room_links.append({
			"id": str(portal["id"]),
			"from_room": str(portal["from_room"]),
			"to_room": str(portal["to_room"]),
			"from_cell": portal["from_cell"],
			"to_cell": portal["to_cell"],
			"module_id": str(portal["module_id"]),
			"link_type": "door",
		})

	var layout: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"document_kind": "ship_layout",
		"program_id": "life_boat_fixed",
		"kit_id": kit_id,
		"design_intent": "fixed hand-authored life boat layout",
		"cell_size": CELL_SIZE,
		"rooms": rooms_array,
		"room_links": room_links,
		"portals": portals,
		"blocked_links": [],
		"vertical_connections": [],
		"landmarks": [],
		"critical_path": ["airlock_01", "cockpit_01"],
		"fire_zones": [],
		"arc_zones": [],
		"breach_zones": [],
		"prototype": {
			"start_room": "airlock_01",
			"goal_room": "cockpit_01",
		},
	}

	var compiler: RefCounted = StructuralEdgeCompilerScript.new()
	var structural_plan: Dictionary = compiler.compile(layout)
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
	if not bool(verdict.get("ok", false)):
		push_error("LifeBoatBuilder: structural plan validation failed: %s" % str(verdict.get("errors", [])))
	layout["structural_plan"] = structural_plan
	_apply_plan_to_rooms(layout, structural_plan, portals)
	return layout


# Returns the RoomGraph for the life boat. Useful for tests and for
# the start scene combiner to inspect room roles without building
# the full Node3D tree.
static func build_graph() -> RoomGraphScript:
	var graph: RoomGraphScript = RoomGraphScript.new()
	for room_def in ROOMS:
		graph.add_room(room_def["id"], room_def["role"], room_def["deck"])
	graph.add_link("airlock_01", "cockpit_01", "door")
	graph.add_link("airlock_01", "engine_bay_01", "door")
	return graph


# Returns the Node3D for the airlock room inside a built life boat.
# The start scene combiner uses this to position the life boat
# adjacent to the derelict dock.
static func get_airlock_node(life_boast_root: Node3D) -> Node3D:
	if life_boast_root == null or life_boast_root.get_child_count() < 1:
		return null
	var structure: Node = life_boast_root.get_child(0)
	if structure == null:
		return null
	return structure.get_node_or_null("airlock_01")


static func _kit_id_for_biome(biome: String) -> String:
	match biome:
		"breach_field":
			return "ship_structural_hazard"
		"dead_fleet":
			return "ship_structural_industrial"
		_:
			return DEFAULT_KIT_ID


static func _apply_plan_to_rooms(layout: Dictionary, plan: Dictionary, portals: Array) -> void:
	var rooms: Array = layout.get("rooms", [])
	var by_room: Dictionary = {}
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var rid: String = str(room.get("id", ""))
		room["structural_placements"] = []
		room["portals"] = []
		by_room[rid] = room
	for record_variant in (plan.get("floor_placements", []) as Array) + (plan.get("placements", []) as Array) + (plan.get("ceiling_placements", []) as Array):
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		var room_id: String = str(record.get("room_id", record.get("owner_room", "")))
		if room_id.is_empty():
			var room_ids: Variant = record.get("room_ids", [])
			if typeof(room_ids) == TYPE_ARRAY and not (room_ids as Array).is_empty():
				room_id = str((room_ids as Array)[0])
		if not by_room.has(room_id):
			continue
		var pos: Array = _vec3_to_array(record.get("position", []))
		var cell_variant: Variant = record.get("cell", [0, 0, 0])
		var cell_arr: Array = cell_variant if typeof(cell_variant) == TYPE_ARRAY else _cell_to_array(cell_variant, int(record.get("deck", 0)))
		(by_room[room_id]["structural_placements"] as Array).append({
			"name": str(record.get("placement_id", record.get("id", ""))),
			"module": str(record.get("module_id", "")),
			"module_id": str(record.get("module_id", "")),
			"position": pos if pos.size() >= 3 else cell_arr,
			"world_position": pos,
			"yaw_degrees": float(record.get("yaw_degrees", 0.0)),
		})
	for portal_variant in portals:
		if typeof(portal_variant) != TYPE_DICTIONARY:
			continue
		var portal: Dictionary = portal_variant
		var from_room: String = str(portal.get("from_room", ""))
		if by_room.has(from_room):
			(by_room[from_room]["portals"] as Array).append(portal.duplicate(true))


static func _instance_plan_records(records_variant: Variant, module_to_scene: Dictionary, room_nodes: Dictionary, structure: Node3D) -> bool:
	if typeof(records_variant) != TYPE_ARRAY:
		return true
	for record_variant in (records_variant as Array):
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		var module_id: String = str(record.get("module_id", ""))
		if module_id.is_empty():
			continue
		var scene_path: String = str(module_to_scene.get(module_id, ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			push_error("LifeBoatBuilder: missing wrapper for module %s" % module_id)
			return false
		var packed: Resource = ResourceLoader.load(scene_path)
		if packed == null or not (packed is PackedScene):
			push_error("LifeBoatBuilder: wrapper is not PackedScene: %s" % scene_path)
			return false
		var instance: Node = (packed as PackedScene).instantiate()
		if instance == null or not (instance is Node3D):
			if instance != null:
				instance.free()
			push_error("LifeBoatBuilder: failed to instance %s" % module_id)
			return false
		var wrapper: Node3D = instance as Node3D
		var world_pos: Vector3 = _as_vector3(record.get("position", Vector3.ZERO))
		wrapper.rotation_degrees.y = float(record.get("yaw_degrees", 0.0))
		wrapper.name = str(record.get("placement_id", record.get("id", module_id))).replace(":", "_").replace("|", "_")
		var room_id: String = str(record.get("room_id", record.get("owner_room", "")))
		if room_id.is_empty():
			var room_ids: Variant = record.get("room_ids", [])
			if typeof(room_ids) == TYPE_ARRAY and not (room_ids as Array).is_empty():
				room_id = str((room_ids as Array)[0])
		var parent: Node3D = room_nodes.get(room_id, structure) as Node3D
		if parent == null:
			parent = structure
		wrapper.position = world_pos - parent.position
		parent.add_child(wrapper)
	return true


static func _module_scene_map(kit_id: String) -> Dictionary:
	var kit_path: String = "res://data/kits/%s.json" % kit_id
	if not FileAccess.file_exists(kit_path):
		kit_path = DEFAULT_KIT_PATH
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(kit_path))
	var module_to_scene: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		var modules_variant: Variant = (parsed as Dictionary).get("modules", [])
		if typeof(modules_variant) == TYPE_ARRAY:
			for module_variant in (modules_variant as Array):
				if typeof(module_variant) != TYPE_DICTIONARY:
					continue
				var module: Dictionary = module_variant
				var module_id: String = str(module.get("module_id", ""))
				var scene_path: String = str(module.get("godot_wrapper_scene", ""))
				if not module_id.is_empty() and not scene_path.is_empty():
					module_to_scene[module_id] = scene_path
	if module_to_scene.is_empty() and kit_path != DEFAULT_KIT_PATH:
		return _module_scene_map(DEFAULT_KIT_ID)
	return module_to_scene


static func _vec3_to_array(value: Variant) -> Array:
	if typeof(value) == TYPE_VECTOR3:
		var vector: Vector3 = value
		return [vector.x, vector.y, vector.z]
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 3:
			return [float(arr[0]), float(arr[1]), float(arr[2])]
	return []


static func _cell_to_array(value: Variant, deck: int) -> Array:
	if typeof(value) == TYPE_VECTOR2I:
		var cell: Vector2i = value
		return [cell.x, deck, cell.y]
	if typeof(value) == TYPE_ARRAY:
		return value
	return [0, deck, 0]


static func _as_vector3(value: Variant) -> Vector3:
	if typeof(value) == TYPE_VECTOR3:
		return value
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO
