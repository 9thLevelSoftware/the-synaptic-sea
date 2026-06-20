extends RefCounted
class_name StructuralPlacer

# Builds the physical "shell" of a procedurally generated ship from a
# RoomGraph. Consumes the same RoomGraph that RoomGraphGenerator emits
# (and that later tasks — gameplay/prop placement, lighting, encounters
# — will also read) and produces a Node3D tree of structural modules
# under a single "ShipStructure" root.
#
# The placer is the bridge between the abstract topology (rooms with
# roles, connected by doors) and the concrete scene-graph world
# (PackedScene wrappers placed at world coordinates). It is intentionally
# deterministic given the same RoomGraph: room order is the graph's room
# order, and modules within a room are placed in a fixed line along +Z
# scaled by CELL_SIZE. This determinism is what lets the same blueprint
# be reproduced as a usable scene file later.
#
# Why a RefCounted and not a Node3D? The placer itself is a pure
# builder. It does not need to be in the scene tree, has no per-frame
# state, and exposing `place_structure` as a method on a RefCounted
# makes it trivially unit-testable from a SceneTree smoke (no need to
# attach to a parent, no leaked nodes). The output (the ShipStructure
# root) is a Node3D that the caller is expected to add to the tree.

# Preload the peer data class so type annotations resolve cleanly under
# `godot --headless --script`. class_name globals (RoomGraph) may not
# be registered yet during the first parse pass in headless mode, so we
# reference the script via preload just like the smokes do.
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")

# World-space size of a single cell. All structural modules in
# ship_structural_v0 are authored on a 1x1 (or 2x1 / 1x2) grid where
# each cell is CELL_SIZE metres. Keeping it as a constant here means
# downstream placers (props, lighting) and tests can align to the same
# grid without re-deriving it from the module scenes.
const CELL_SIZE: float = 4.0

# Root directory of the structural module PackedScenes. Modules are
# referenced by their stem (e.g. "floor_1x1") and the placer resolves
# the full res:// path at load time. Keeping the directory in one place
# means the library can be swapped to ship_structural_v1, etc. by
# changing just this constant.
const MODULE_BASE_PATH: String = "res://scenes/wrappers/structural/ship_structural_v0/"

# Maps each room role produced by RoomGraphGenerator to the ordered
# list of structural module stems to place along that room's Z-axis
# run. The first module sits at the room's origin, each subsequent
# module is offset by CELL_SIZE further along +Z.
#
# Stems, not full paths: the placer resolves the path via
# MODULE_BASE_PATH so the same mapping can be used in tests without
# hard-coding res:// URLs.
#
# Roles not present in this map fall back to the default fallback list
# (just a single floor_1x1) so a future role added to the generator
# never crashes placement — it just gets the minimum structure.
const ROOM_MODULES: Dictionary = {
	"airlock": [
		"floor_1x1",
		"floor_1x1",
		"doorway_frame_open_1x1",
	],
	"corridor": [
		"corridor_floor_1x1",
		"corridor_floor_1x1",
	],
	"engineering": [
		"floor_1x1",
		"floor_2x1",
		"wall_straight_1x1",
	],
	"life_support": [
		"floor_1x1",
		"floor_1x1",
		"wall_straight_1x1",
	],
	"bridge": [
		"floor_2x1",
		"floor_2x1",
		"wall_straight_1x1",
	],
	"cargo": [
		"floor_2x1",
		"floor_2x1",
	],
	"crew_quarters": [
		"floor_1x1",
		"floor_1x1",
	],
	"medical": [
		"floor_1x1",
		"floor_1x1",
	],
	"maintenance": [
		"floor_1x1",
		"corridor_floor_1x1",
	],
}

# Fallback module list for any role that is not in ROOM_MODULES. A
# single floor_1x1 is the minimum structural footprint: a deck cell
# you can stand on. This is the safety net for forward-compatibility
# when a new role is added to the generator before the placer learns
# about it.
const FALLBACK_MODULES: Array[String] = ["floor_1x1"]


# Builds the ShipStructure Node3D for the given graph.
#
# Returns a Node3D named "ShipStructure" with one child Node3D per
# room; each child holds the placed module instances along its +Z
# axis. The returned root is NOT attached to the scene tree — the
# caller decides where to add it (root scene, a generator output
# node, a test scene, etc.).
#
# Rooms are iterated in the graph's order, which means the chain
# RoomGraphGenerator builds (airlock → engineering → …) ends up laid
# out along world +Z. Each room's origin is offset by the running
# position so rooms don't overlap.
#
# The return type is declared as Node3D (not the more specific
# Node3D subclass) so callers can chain further Node3D operations
# (e.g. transform) without upcasting.
func place_structure(graph: RoomGraphScript) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "ShipStructure"

	# Track the running Z offset across rooms. Each room advances
	# the cursor by the number of modules it placed times CELL_SIZE,
	# so a 2-module room is 2 cells long, a 3-module room is 3 cells
	# long, etc. Using a local float keeps the math obvious and
	# avoids depending on any per-room metadata we don't have yet.
	var z_cursor: float = 0.0
	for room in graph.rooms:
		var room_node: Node3D = _create_room_node(room, z_cursor)
		root.add_child(room_node)
		var module_count: int = _modules_for_role(String(room["role"])).size()
		z_cursor += float(module_count) * CELL_SIZE

	return root


# Builds a single room's Node3D and populates it with the role's
# module list. The room node is named after the room id (e.g.
# "airlock_01") and positioned at `(0, 0, x_offset)` so the room
# anchor sits on the world Z axis at `x_offset`.
#
# Each module is instantiated from its PackedScene, parented to the
# room node, and offset further along +Z by index * CELL_SIZE. If a
# module fails to load (missing .tscn, bad path), the placer pushes
# an error and continues with the next module rather than aborting:
# partial structure is better than no structure for downstream
# gameplay debugging.
func _create_room_node(room: Dictionary, x_offset: float) -> Node3D:
	var room_id: String = String(room.get("id", "room"))
	var role: String = String(room.get("role", ""))

	var room_node: Node3D = Node3D.new()
	room_node.name = room_id
	room_node.position = Vector3(0.0, 0.0, x_offset)

	var modules: Array[String] = _modules_for_role(role)
	for i in range(modules.size()):
		var stem: String = modules[i]
		var instance: Node3D = _instantiate_module(stem)
		if instance == null:
			# _instantiate_module already pushed the error; skip
			# the bad module so the room's remaining modules
			# still get placed. Also advance the world-space
			# cursor to keep rooms non-overlapping.
			continue
		# Naming includes the stem + index so a single room with
		# two "floor_1x1" modules (e.g. airlock) produces
		# distinguishable children: "floor_1x1_0", "floor_1x1_1".
		instance.name = "%s_%d" % [stem, i]
		instance.position = Vector3(0.0, 0.0, float(i) * CELL_SIZE)
		room_node.add_child(instance)

	return room_node


# Returns the ordered module stem list for a given role. Unknown
# roles fall back to FALLBACK_MODULES so the placer never crashes
# on a new role. The returned Array[String] is safe to index and
# iterate.
func _modules_for_role(role: String) -> Array[String]:
	if not ROOM_MODULES.has(role):
		return FALLBACK_MODULES.duplicate()
	var raw = ROOM_MODULES[role]
	if raw is Array:
		# Coerce each element to String in case the literal was
		# inferred as a Variant array; this also filters out any
		# accidental non-string entries without crashing.
		var out: Array[String] = []
		for entry in raw:
			out.append(String(entry))
		return out
	return FALLBACK_MODULES.duplicate()


# Loads and instantiates a single module by its stem (e.g. "floor_1x1")
# using MODULE_BASE_PATH. Returns the root Node3D of the instantiated
# scene, or null on load failure (after pushing an error so the
# regression shows up in the smoke output).
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
		# Defensive: every structural module in ship_structural_v0
		# is authored with a Node3D root. If this ever fires, the
		# scene file is mis-typed and should be fixed, not worked
		# around.
		push_error("STRUCTURAL PLACER FAIL module root is not Node3D: %s" % path)
		instance.queue_free()
		return null
	return instance
