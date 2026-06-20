extends SceneTree

# StructuralPlacer smoke (v3 grid placement). Builds a ShipBlueprint,
# runs it through RoomGraphGenerator to get a connected RoomGraph, feeds
# the graph to StructuralPlacer.place_structure(), and verifies the
# returned ShipStructure root.
#
# The v3 StructuralPlacer lays rooms out on a 2D grid via BFS with
# directional preferences (not the v1 single-line +Z stack). Each room
# node's world position is therefore an integer multiple of the grid
# step (CELL_SIZE + ROOM_GAP) on both X and Z, with Y == 0. Modules
# within a room are still spaced CELL_SIZE apart along local +Z.
#
# Verifies:
#   1. place_structure() returns a non-null Node3D named "ShipStructure".
#   2. The root has exactly one child per room in the graph.
#   3. Every room child is a Node3D positioned on the grid
#      (x and z are integer multiples of grid step; y == 0).
#   4. No two rooms share the same origin cell (non-overlapping origins).
#   5. Each room has the expected module count for its role (matching
#      ROOM_MODULES; fallback 1 for unknown roles), with modules spaced
#      CELL_SIZE apart on local +Z.
#   6. A second, independently-seeded ship also places correctly
#      (placer is not stateful across calls).
#   7. Determinism: the same graph placed twice yields identical room
#      positions.
#   8. An unknown role falls back to the single-floor footprint rather
#      than crashing the placer.
#
# On success prints a single PASS line; on the FIRST failure pushes an
# error and quits with code 1. IMPORTANT: in a SceneTree, quit() only
# sets a flag — _initialize() keeps running — so each failing assertion
# is surfaced by returning false up to _initialize(), which then quits
# and returns immediately (the old version called quit() mid-helper and
# fell through to a spurious PASS print).

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const StructuralPlacerScript := preload("res://scripts/procgen/structural_placer.gd")

const GRID_STEP: float = StructuralPlacerScript.CELL_SIZE + StructuralPlacerScript.ROOM_GAP
const EPS: float = 0.001


func _initialize() -> void:
	# --- Case 1: medium ship, deterministic seed ---------------------
	var counts_a: Array = _run_ship_case(
		"medium", ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 314)
	if counts_a.is_empty():
		quit(1)
		return

	# --- Case 2: small damaged ship, different seed ------------------
	var counts_b: Array = _run_ship_case(
		"small", ShipBlueprintScript.Size.SMALL, ShipBlueprintScript.Condition.DAMAGED, 2718)
	if counts_b.is_empty():
		quit(1)
		return

	# --- Case 3: unknown role falls back to a single floor ----------
	if not _run_unknown_role_case():
		quit(1)
		return

	print("STRUCTURAL PLACER PASS rooms=%d modules=%d second_rooms=%d second_modules=%d unknown_role_fallback=ok" % [
		int(counts_a[0]), int(counts_a[1]), int(counts_b[0]), int(counts_b[1]),
	])
	quit(0)


# Runs one full ship case (blueprint -> graph -> structure) and asserts
# the v3 grid placement invariants plus determinism. Returns
# [room_count, module_count] on success, or [] on the first failure
# (after pushing an error). Frees the structures it builds.
func _run_ship_case(label: String, p_size: int, p_condition: int, p_seed: int) -> Array:
	var bp: ShipBlueprintScript = ShipBlueprintScript.new(p_size, p_condition, p_seed)
	var gen: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var graph: RoomGraphScript = gen.generate(bp)

	var placer: StructuralPlacerScript = StructuralPlacerScript.new()
	var root: Node3D = placer.place_structure(graph)

	if root == null or not (root is Node3D):
		push_error("STRUCTURAL PLACER FAIL %s place_structure returned null/non-Node3D" % label)
		return []
	if root.name != "ShipStructure":
		push_error("STRUCTURAL PLACER FAIL %s root.name=%s expected=ShipStructure" % [label, str(root.name)])
		root.free()
		return []
	if root.get_child_count() != graph.rooms.size():
		push_error("STRUCTURAL PLACER FAIL %s children=%d expected=%d (rooms)" % [
			label, root.get_child_count(), graph.rooms.size()])
		root.free()
		return []

	var total_modules: int = 0
	var seen_origins: Dictionary = {}
	for room in graph.rooms:
		var rid: String = String(room["id"])
		var rrole: String = String(room["role"])

		var room_node: Node = root.get_node_or_null(NodePath(rid))
		if room_node == null or not (room_node is Node3D):
			push_error("STRUCTURAL PLACER FAIL %s room %s missing or not Node3D" % [label, rid])
			root.free()
			return []
		var room_pos: Vector3 = (room_node as Node3D).position

		# Grid alignment: x and z are integer multiples of GRID_STEP, y == 0.
		if absf(room_pos.y) > EPS:
			push_error("STRUCTURAL PLACER FAIL %s room %s y=%f expected 0" % [label, rid, room_pos.y])
			root.free()
			return []
		if not _is_grid_aligned(room_pos.x) or not _is_grid_aligned(room_pos.z):
			push_error("STRUCTURAL PLACER FAIL %s room %s pos=%s not grid-aligned (step=%f)" % [
				label, rid, str(room_pos), GRID_STEP])
			root.free()
			return []

		# Non-overlapping origins.
		var origin_key: String = "%d,%d" % [int(round(room_pos.x / GRID_STEP)), int(round(room_pos.z / GRID_STEP))]
		if seen_origins.has(origin_key):
			push_error("STRUCTURAL PLACER FAIL %s room %s origin %s collides with %s" % [
				label, rid, origin_key, str(seen_origins[origin_key])])
			root.free()
			return []
		seen_origins[origin_key] = rid

		# Module count for this role.
		var expected_module_count: int = _expected_module_count(rrole)
		var actual_module_count: int = room_node.get_child_count()
		if actual_module_count != expected_module_count:
			push_error("STRUCTURAL PLACER FAIL %s room %s (role=%s) modules=%d expected=%d" % [
				label, rid, rrole, actual_module_count, expected_module_count])
			root.free()
			return []

		# Each module sits at local z = i * CELL_SIZE (x == 0, y == 0).
		for i in range(actual_module_count):
			var module_node: Node = room_node.get_child(i)
			if not (module_node is Node3D):
				push_error("STRUCTURAL PLACER FAIL %s room %s module[%d] not Node3D" % [label, rid, i])
				root.free()
				return []
			var module_pos: Vector3 = (module_node as Node3D).position
			var expected_module_z: float = float(i) * StructuralPlacerScript.CELL_SIZE
			if not _approx_equal(module_pos.z, expected_module_z):
				push_error("STRUCTURAL PLACER FAIL %s room %s module[%d] z=%f expected=%f" % [
					label, rid, i, module_pos.z, expected_module_z])
				root.free()
				return []

		total_modules += actual_module_count

	# Determinism: placing the same graph again yields identical positions.
	var placer2: StructuralPlacerScript = StructuralPlacerScript.new()
	var root2: Node3D = placer2.place_structure(graph)
	if root2 == null:
		push_error("STRUCTURAL PLACER FAIL %s determinism second placement null" % label)
		root.free()
		return []
	for room in graph.rooms:
		var rid: String = String(room["id"])
		var n1: Node = root.get_node_or_null(NodePath(rid))
		var n2: Node = root2.get_node_or_null(NodePath(rid))
		if n1 == null or n2 == null or (n1 as Node3D).position != (n2 as Node3D).position:
			push_error("STRUCTURAL PLACER FAIL %s determinism room %s position differs" % [label, rid])
			root.free()
			root2.free()
			return []
	root.free()
	root2.free()

	return [graph.rooms.size(), total_modules]


# Hand-built graph with a role the generator never produces: the placer
# must not crash and must drop a single floor for the unknown role.
func _run_unknown_role_case() -> bool:
	var graph_custom: RoomGraphScript = RoomGraphScript.new()
	graph_custom.add_room("secret_01", "unknown_role_xyz", 0)
	graph_custom.add_room("airlock_99", "airlock", 0)
	graph_custom.add_link("secret_01", "airlock_99")

	var placer: StructuralPlacerScript = StructuralPlacerScript.new()
	var custom_root: Node3D = placer.place_structure(graph_custom)
	if custom_root == null or custom_root.name != "ShipStructure":
		push_error("STRUCTURAL PLACER FAIL unknown-role root invalid")
		if custom_root != null:
			custom_root.free()
		return false
	if custom_root.get_child_count() != 2:
		push_error("STRUCTURAL PLACER FAIL unknown-role children=%d expected=2" % custom_root.get_child_count())
		custom_root.free()
		return false
	var unknown_room: Node = custom_root.get_node_or_null("secret_01")
	if unknown_room == null:
		push_error("STRUCTURAL PLACER FAIL unknown-role secret_01 missing")
		custom_root.free()
		return false
	if unknown_room.get_child_count() != 1:
		push_error("STRUCTURAL PLACER FAIL unknown-role module count=%d expected=1 (fallback)" % unknown_room.get_child_count())
		custom_root.free()
		return false
	custom_root.free()
	return true


# Mirrors ROOM_MODULES in StructuralPlacer (kept here so the test reads
# as a clear spec of the contract).
func _expected_module_count(role: String) -> int:
	match role:
		"airlock": return 3
		"corridor": return 2
		"engineering": return 3
		"life_support": return 3
		"bridge": return 3
		"cargo": return 2
		"crew_quarters": return 2
		"medical": return 2
		"maintenance": return 2
		_: return 1  # fallback


func _is_grid_aligned(value: float) -> bool:
	var ratio: float = value / GRID_STEP
	return absf(ratio - round(ratio)) < EPS


func _approx_equal(a: float, b: float) -> bool:
	return abs(a - b) < EPS
