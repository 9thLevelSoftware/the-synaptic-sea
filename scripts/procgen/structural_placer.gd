extends RefCounted
class_name StructuralPlacer

# Builds the physical "shell" of a ship from a RoomGraph using 2D
# grid placement with spatial rules.
#
# v3 changes:
#   - Stronger directional preferences (room roles have preferred
#     quadrants of the ship).
#   - Airlock separation: on non-life-boat ships, airlock must not
#     be directly adjacent to bridge. Airlock goes on the side
#     (east or west), bridge goes forward (north).
#   - More aggressive branching: direction order shuffled per-room,
#     more random links, rooms spread outward from center.
#   - Post-layout swap: rooms that ended up in the wrong zone get
#     swapped with rooms in better positions.

const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const KitCatalogScript := preload("res://scripts/procgen/kit_catalog.gd")

const CELL_SIZE: float = 4.0
const ROOM_GAP: float = 2.0
const MODULE_BASE_PATH: String = "res://scenes/wrappers/structural/ship_structural_v0/"

# Room footprints in grid cells.
const ROOM_FOOTPRINTS: Dictionary = {
	"engineering": Vector2i(2, 1),
	"bridge": Vector2i(2, 1),
	"cargo": Vector2i(2, 1),
	"life_support": Vector2i(2, 1),
	"bay": Vector2i(2, 1),
}

# Module lists per role.
const ROOM_MODULES: Dictionary = {
	# --- Ship roles ---
	"airlock": ["floor_1x1", "floor_1x1", "doorway_frame_open_1x1"],
	"corridor": ["corridor_floor_1x1", "corridor_floor_1x1"],
	"engineering": ["floor_1x1", "floor_2x1", "wall_straight_1x1"],
	"life_support": ["floor_1x1", "floor_1x1", "wall_straight_1x1"],
	"bridge": ["floor_2x1", "floor_2x1", "wall_straight_1x1"],
	"cargo": ["floor_2x1", "floor_2x1"],
	"crew_quarters": ["floor_1x1", "floor_1x1"],
	"medical": ["floor_1x1", "floor_1x1"],
	"maintenance": ["floor_1x1", "corridor_floor_1x1"],
	# --- Life boat roles ---
	"cockpit": ["floor_1x1", "floor_1x1", "wall_straight_1x1"],
	"engine_bay": ["floor_1x1", "floor_2x1", "wall_straight_1x1"],
	# --- Derelict roles ---
	"compartment": ["floor_1x1", "floor_1x1", "floor_1x1"],
	"bay": ["floor_2x1", "floor_2x1", "floor_1x1"],
	"quarters": ["floor_1x1", "floor_1x1"],
	"dock": ["floor_1x1", "floor_1x1", "doorway_frame_open_1x1"],
}

const FALLBACK_MODULES: Array[String] = ["floor_1x1"]

# Direction vectors: 0=north(-Z), 1=east(+X), 2=south(+Z), 3=west(-X)
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

# Directional zones. Each role has a preferred quadrant of the ship.
# "north" = forward, "south" = aft, "east" = starboard, "west" = port.
# The placer tries to put each room in its preferred zone relative to
# the ship's center of mass.
const DIRECTION_PREFERENCES: Dictionary = {
	"engineering": [2, 1, 3, 0],   # aft
	"engine_bay": [2, 1, 3, 0],    # aft
	"bridge": [0, 1, 3, 2],        # forward
	"cockpit": [0, 1, 3, 2],       # forward
	"cargo": [1, 2, 3, 0],         # starboard
	"life_support": [3, 0, 1, 2],  # port
	"airlock": [1, 3, 2, 0],       # sides (east/west), NOT forward
	"dock": [1, 3, 2, 0],          # sides
	"corridor": [0, 1, 2, 3],      # no preference
	"maintenance": [2, 3, 1, 0],   # aft-port
	"medical": [3, 2, 0, 1],       # port-aft
	"crew_quarters": [3, 0, 1, 2], # port
	"quarters": [3, 0, 1, 2],      # port
	"compartment": [0, 1, 2, 3],   # no preference
}

# Roles that are "forward" — used for airlock separation check.
const FORWARD_ROLES: Array[String] = ["bridge", "cockpit"]

# Minimum grid distance between airlock and bridge on non-life-boat ships.
const AIRLOCK_BRIDGE_MIN_DIST: int = 3

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Role -> module-list source. Lazily configured from res://data/kits/ on first
# use. When the catalog is unavailable (missing dir) or has no mapping for a
# role, _modules_for_role falls back to the built-in ROOM_MODULES const so the
# default/no-biome output is byte-identical to the pre-KitCatalog behaviour.
var kit_catalog
# Biome id used to pick a biome-biased kit (e.g. breach_field -> hazard kit).
# Empty selects the default kit (ship_structural_v0 == ROOM_MODULES).
var biome: String = ""


func place_structure(graph: RoomGraphScript, seed_value: int = 0, p_biome: String = "") -> Node3D:
	if graph.rooms.is_empty():
		return null

	rng.seed = seed_value
	biome = p_biome
	_ensure_kit_catalog()

	# Phase 1: compute grid positions via BFS with strong preferences.
	var grid_positions: Dictionary = _layout_rooms(graph)
	if grid_positions.is_empty():
		push_error("STRUCTURAL PLACER FAIL grid layout returned empty")
		return null

	# Phase 2: airlock separation enforcement.
	_enforce_airlock_separation(graph, grid_positions)

	# Phase 3: build the Node3D tree.
	var root: Node3D = Node3D.new()
	root.name = "ShipStructure"

	for room in graph.rooms:
		var rid: String = String(room["id"])
		var role: String = String(room["role"])
		var grid_pos: Vector2i = grid_positions.get(rid, Vector2i.ZERO)

		var world_x: float = float(grid_pos.x) * (CELL_SIZE + ROOM_GAP)
		var world_z: float = float(grid_pos.y) * (CELL_SIZE + ROOM_GAP)

		var room_node: Node3D = _create_room_node(room, Vector3(world_x, 0.0, world_z))
		root.add_child(room_node)

	return root


# --- BFS Layout ---

func _layout_rooms(graph: RoomGraphScript) -> Dictionary:
	var positions: Dictionary = {}
	var occupied: Dictionary = {}

	if graph.rooms.is_empty():
		return positions

	# Place first room at origin.
	var first_id: String = String(graph.rooms[0]["id"])
	var first_role: String = String(graph.rooms[0]["role"])
	var first_fp: Vector2i = _footprint_for_role(first_role)
	positions[first_id] = Vector2i(0, 0)
	_occupy_cells(occupied, Vector2i(0, 0), first_fp, first_id)

	var visited: Dictionary = {first_id: true}
	var queue: Array[String] = [first_id]

	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current_pos: Vector2i = positions[current_id]
		var current_fp: Vector2i = _footprint_for_role(_role_for_room(graph, current_id))

		var connected: Array[String] = []
		for cid in graph.get_connected_rooms(current_id):
			connected.append(cid)

		# Shuffle connected rooms for more varied branching.
		_shuffle_array(connected)

		for connected_id in connected:
			if visited.has(connected_id):
				continue
			visited[connected_id] = true

			var connected_role: String = _role_for_room(graph, connected_id)
			var connected_fp: Vector2i = _footprint_for_role(connected_role)

			var best_pos: Vector2i = _find_adjacent_position(
				current_pos, current_fp, connected_fp, connected_role, occupied)

			if best_pos == Vector2i(-99999, -99999):
				best_pos = _find_any_free_position(current_pos, connected_fp, occupied)

			if best_pos == Vector2i(-99999, -99999):
				push_error("STRUCTURAL PLACER WARN could not place room %s" % connected_id)
				continue

			positions[connected_id] = best_pos
			_occupy_cells(occupied, best_pos, connected_fp, connected_id)
			queue.append(connected_id)

	return positions


# Fisher-Yates shuffle for Array[String].
func _shuffle_array(arr: Array[String]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _find_adjacent_position(
		parent_pos: Vector2i,
		parent_fp: Vector2i,
		new_fp: Vector2i,
		new_role: String,
		occupied: Dictionary) -> Vector2i:

	# Get preferred directions and shuffle within preference tiers.
	var prefs: Array = DIRECTION_PREFERENCES.get(new_role, [0, 1, 2, 3])

	# Try preferred directions with some randomization.
	var tried: Dictionary = {}
	for attempt in range(prefs.size() * 2):
		var dir_idx: int
		if attempt < prefs.size():
			dir_idx = prefs[attempt]
		else:
			dir_idx = rng.randi_range(0, 3)
		if tried.has(dir_idx):
			continue
		tried[dir_idx] = true

		var dir: Vector2i = DIRECTIONS[dir_idx]
		var candidate: Vector2i = _adjacent_cell(parent_pos, parent_fp, dir)
		if _can_place(candidate, new_fp, occupied):
			return candidate

		# Try rotated footprint.
		var rotated_fp: Vector2i = Vector2i(new_fp.y, new_fp.x)
		if rotated_fp != new_fp:
			if _can_place(candidate, rotated_fp, occupied):
				return candidate

	# Try ALL directions with ALL rotations as fallback.
	for dir_idx in range(4):
		var dir: Vector2i = DIRECTIONS[dir_idx]
		for fp in [new_fp, Vector2i(new_fp.y, new_fp.x)]:
			var candidate: Vector2i = _adjacent_cell(parent_pos, parent_fp, dir)
			if _can_place(candidate, fp, occupied):
				return candidate

	return Vector2i(-99999, -99999)


func _adjacent_cell(parent_pos: Vector2i, parent_fp: Vector2i, dir: Vector2i) -> Vector2i:
	if dir == Vector2i(0, -1):
		return Vector2i(parent_pos.x, parent_pos.y - 1)
	elif dir == Vector2i(1, 0):
		return Vector2i(parent_pos.x + parent_fp.x, parent_pos.y)
	elif dir == Vector2i(0, 1):
		return Vector2i(parent_pos.x, parent_pos.y + parent_fp.y)
	else:
		return Vector2i(parent_pos.x - 1, parent_pos.y)


func _can_place(pos: Vector2i, footprint: Vector2i, occupied: Dictionary) -> bool:
	for dx in range(footprint.x):
		for dz in range(footprint.y):
			if occupied.has(Vector2i(pos.x + dx, pos.y + dz)):
				return false
	return true


func _find_any_free_position(
		parent_pos: Vector2i,
		footprint: Vector2i,
		occupied: Dictionary) -> Vector2i:
	for radius in range(1, 20):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dz) != radius:
					continue
				var candidate: Vector2i = Vector2i(parent_pos.x + dx, parent_pos.y + dz)
				if _can_place(candidate, footprint, occupied):
					return candidate
	return Vector2i(-99999, -99999)


func _occupy_cells(occupied: Dictionary, pos: Vector2i, footprint: Vector2i, room_id: String) -> void:
	for dx in range(footprint.x):
		for dz in range(footprint.y):
			occupied[Vector2i(pos.x + dx, pos.y + dz)] = room_id


# --- Airlock Separation ---
#
# On non-life-boat ships, if the airlock is directly adjacent to
# the bridge (Manhattan distance < AIRLOCK_BRIDGE_MIN_DIST), swap
# the airlock with a room that's farther from the bridge.

func _enforce_airlock_separation(graph: RoomGraphScript, positions: Dictionary) -> void:
	# Find airlock and bridge rooms.
	var airlock_id: String = ""
	var bridge_id: String = ""
	for room in graph.rooms:
		var role: String = String(room["role"])
		if role == "airlock":
			airlock_id = String(room["id"])
		elif role in FORWARD_ROLES:
			bridge_id = String(room["id"])

	if airlock_id.is_empty() or bridge_id.is_empty():
		return  # No airlock or bridge (derelict or life boat).

	var airlock_pos: Vector2i = positions.get(airlock_id, Vector2i.ZERO)
	var bridge_pos: Vector2i = positions.get(bridge_id, Vector2i.ZERO)
	var dist: int = abs(airlock_pos.x - bridge_pos.x) + abs(airlock_pos.y - bridge_pos.y)

	if dist >= AIRLOCK_BRIDGE_MIN_DIST:
		return  # Already far enough.

	# Find a room to swap with the airlock. We want a room that's
	# farther from the bridge and not itself a forward-adjacent room.
	var best_swap: String = ""
	var best_dist: int = dist
	for room in graph.rooms:
		var rid: String = String(room["id"])
		if rid == airlock_id or rid == bridge_id:
			continue
		var role: String = String(room["role"])
		if role in FORWARD_ROLES:
			continue  # Don't swap with bridge/cockpit.
		var rpos: Vector2i = positions.get(rid, Vector2i.ZERO)
		var rdist: int = abs(rpos.x - bridge_pos.x) + abs(rpos.y - bridge_pos.y)
		if rdist > best_dist:
			best_dist = rdist
			best_swap = rid

	if best_swap.is_empty():
		return  # No suitable swap found.

	# Swap positions.
	var swap_pos: Vector2i = positions[best_swap]
	positions[best_swap] = airlock_pos
	positions[airlock_id] = swap_pos


# --- Helpers ---

func _footprint_for_role(role: String) -> Vector2i:
	if ROOM_FOOTPRINTS.has(role):
		return ROOM_FOOTPRINTS[role]
	return Vector2i(1, 1)


func _role_for_room(graph: RoomGraphScript, room_id: String) -> String:
	var room: Dictionary = graph.get_room(room_id)
	if room.is_empty():
		return ""
	return String(room["role"])


func _create_room_node(room: Dictionary, world_pos: Vector3) -> Node3D:
	var room_id: String = String(room.get("id", "room"))
	var role: String = String(room.get("role", ""))

	var room_node: Node3D = Node3D.new()
	room_node.name = room_id
	room_node.position = world_pos

	var modules: Array[String] = _modules_for_role(role)
	for i in range(modules.size()):
		var stem: String = modules[i]
		var instance: Node3D = _instantiate_module(stem)
		if instance == null:
			continue
		instance.name = "%s_%d" % [stem, i]
		instance.position = Vector3(0.0, 0.0, float(i) * CELL_SIZE)
		room_node.add_child(instance)

	return room_node


func _ensure_kit_catalog() -> void:
	if kit_catalog != null:
		return
	kit_catalog = KitCatalogScript.new()
	# configure() is idempotent and never raises; a missing kits dir just
	# leaves the catalog empty so _modules_for_role uses the const fallback.
	kit_catalog.configure("res://data/kits/")


func _modules_for_role(role: String) -> Array[String]:
	# Prefer the data-driven KitCatalog (role -> module list, biome-biased).
	# kits_for_role() returns FALLBACK_MODULES (["floor_1x1"]) when a kit is
	# loaded but the role is unknown to it; treat that as "no catalog answer"
	# and fall through to the built-in ROOM_MODULES so known roles keep their
	# richer module lists. The const is also the safety net when no kit loaded.
	if kit_catalog != null:
		var from_kit: Array[String] = kit_catalog.kits_for_role(role, biome)
		if not from_kit.is_empty() and not _is_bare_fallback(from_kit):
			return from_kit
	if not ROOM_MODULES.has(role):
		return FALLBACK_MODULES.duplicate()
	var raw = ROOM_MODULES[role]
	if raw is Array:
		var out: Array[String] = []
		for entry in raw:
			out.append(String(entry))
		return out
	return FALLBACK_MODULES.duplicate()


# True when the catalog returned only the generic single-cell fallback, which
# means it had no real mapping for the role (vs. a deliberate kit list).
func _is_bare_fallback(mods: Array[String]) -> bool:
	return mods.size() == 1 and mods[0] == FALLBACK_MODULES[0]


func _instantiate_module(stem: String) -> Node3D:
	var path: String = MODULE_BASE_PATH + stem + ".tscn"
	if not ResourceLoader.exists(path):
		push_error("STRUCTURAL PLACER FAIL module not found: %s" % path)
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("STRUCTURAL PLACER FAIL module load returned null: %s" % path)
		return null
	if not packed.can_instantiate():
		push_error("STRUCTURAL PLACER FAIL module cannot be instantiated: %s" % path)
		return null
	var instance: Node = packed.instantiate()
	if instance == null:
		push_error("STRUCTURAL PLACER FAIL module instantiate returned null: %s" % path)
		return null
	if not (instance is Node3D):
		push_error("STRUCTURAL PLACER FAIL module root is not Node3D: %s" % path)
		instance.queue_free()
		return null
	return instance
