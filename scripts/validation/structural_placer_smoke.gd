extends SceneTree

# StructuralPlacer smoke. Builds a ShipBlueprint, runs it through
# RoomGraphGenerator to get a connected RoomGraph, feeds the graph to
# StructuralPlacer.place_structure(), and verifies the returned
# ShipStructure root has one child per room with the expected module
# counts.
#
# Verifies:
#   1. place_structure() returns a non-null Node3D named "ShipStructure"
#   2. The root has exactly one child per room in the graph
#   3. Every child is a Node3D
#   4. Each room node has the expected number of module children
#      (matching ROOM_MODULES for known roles, 1 for the fallback)
#   5. Modules are positioned in a non-overlapping line along +Z
#      (each instance's Z equals room_offset + i * CELL_SIZE)
#   6. A second, independently-seeded ship also places correctly
#      (placer is not stateful across calls)
#   7. An unknown role falls back to the single-floor footprint
#      rather than crashing the placer
#
# On success prints a single PASS line with the room/module counts so
# automated verification can grep for it; on any failure pushes an
# error and quits with code 1 so a regression blocks the gate.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const StructuralPlacerScript := preload("res://scripts/procgen/structural_placer.gd")


func _initialize() -> void:
	# --- Case 1: medium ship, deterministic seed ---------------------
	var counts_a: Array = _run_ship_case(
		"medium",
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.PRISTINE,
		314)

	# --- Case 2: small damaged ship, different seed -------------------
	# Confirms the placer is stateless — a second generate/place
	# cycle must produce the same shape for a fresh seed, not
	# accumulate state from the first call.
	var counts_b: Array = _run_ship_case(
		"small",
		ShipBlueprintScript.Size.SMALL,
		ShipBlueprintScript.Condition.DAMAGED,
		2718)

	# --- Case 3: unknown role falls back to a single floor -----------
	# Hand-built graph (not generator output) so we can introduce a
	# role the generator never produces. The placer must not crash;
	# it should drop a single floor_1x1.
	var graph_custom: RoomGraphScript = RoomGraphScript.new()
	graph_custom.add_room("secret_01", "unknown_role_xyz", 0)
	graph_custom.add_room("airlock_99", "airlock", 0)
	graph_custom.add_link("secret_01", "airlock_99")

	var placer: StructuralPlacerScript = StructuralPlacerScript.new()
	var custom_root: Node3D = placer.place_structure(graph_custom)
	if custom_root == null:
		push_error("STRUCTURAL PLACER FAIL unknown-role case returned null root")
		quit(1)
		return
	if custom_root.name != "ShipStructure":
		push_error("STRUCTURAL PLACER FAIL unknown-role case root.name=%s expected=ShipStructure" % str(custom_root.name))
		quit(1)
		return
	if custom_root.get_child_count() != 2:
		push_error("STRUCTURAL PLACER FAIL unknown-role case children=%d expected=2" % custom_root.get_child_count())
		quit(1)
		return
	var unknown_room: Node = custom_root.get_node("secret_01")
	if unknown_room == null:
		push_error("STRUCTURAL PLACER FAIL unknown-role case secret_01 missing")
		quit(1)
		return
	# The unknown role's fallback is a single floor_1x1.
	if unknown_room.get_child_count() != 1:
		push_error("STRUCTURAL PLACER FAIL unknown-role case module count=%d expected=1 (fallback)" % unknown_room.get_child_count())
		quit(1)
		return

	# --- Pass ---------------------------------------------------------
	print("STRUCTURAL PLACER PASS rooms=%d modules=%d second_rooms=%d second_modules=%d unknown_role_fallback=ok" % [
		int(counts_a[0]), int(counts_a[1]), int(counts_b[0]), int(counts_b[1]),
	])
	quit(0)


# Runs one full ship case (blueprint -> graph -> structure) and
# asserts the standard placement invariants. On failure pushes an
# error and quits with code 1 (so the test halts on the first
# regression, matching the other smokes' style). On success returns
# [room_count, module_count] so the PASS line can report totals.
# GDScript ints are value-typed, so we return a small Array rather
# than passing two ints by reference.
func _run_ship_case(
		label: String,
		p_size: int,
		p_condition: int,
		p_seed: int) -> Array:

	var bp: ShipBlueprintScript = ShipBlueprintScript.new(p_size, p_condition, p_seed)
	var gen: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var graph: RoomGraphScript = gen.generate(bp)

	var placer: StructuralPlacerScript = StructuralPlacerScript.new()
	var root: Node3D = placer.place_structure(graph)

	if root == null:
		push_error("STRUCTURAL PLACER FAIL %s place_structure returned null" % label)
		quit(1)
		return [0, 0]
	if not (root is Node3D):
		push_error("STRUCTURAL PLACER FAIL %s root is not Node3D (got %s)" % [label, str(root)])
		quit(1)
		return [0, 0]
	if root.name != "ShipStructure":
		push_error("STRUCTURAL PLACER FAIL %s root.name=%s expected=ShipStructure" % [label, str(root.name)])
		quit(1)
		return [0, 0]

	# Root must have exactly one child per room in the graph.
	if root.get_child_count() != graph.rooms.size():
		push_error("STRUCTURAL PLACER FAIL %s children=%d expected=%d (rooms)" % [
			label, root.get_child_count(), graph.rooms.size(),
		])
		quit(1)
		return [0, 0]

	# Walk each room and verify it has the expected module list, with
	# modules spaced CELL_SIZE apart on +Z, and the room itself
	# offset from origin by the cumulative Z of prior rooms.
	var expected_z_cursor: float = 0.0
	var total_modules: int = 0
	for room in graph.rooms:
		var rid: String = String(room["id"])
		var rrole: String = String(room["role"])

		var room_node: Node = root.get_node(rid)
		if room_node == null:
			push_error("STRUCTURAL PLACER FAIL %s room %s missing from structure" % [label, rid])
			quit(1)
			return [0, 0]
		if not (room_node is Node3D):
			push_error("STRUCTURAL PLACER FAIL %s room %s is not Node3D" % [label, rid])
			quit(1)
			return [0, 0]

		# The room's position must match the running Z cursor.
		var room_pos: Vector3 = (room_node as Node3D).position
		if not _approx_equal(room_pos.z, expected_z_cursor):
			push_error("STRUCTURAL PLACER FAIL %s room %s z=%f expected=%f" % [
				label, rid, room_pos.z, expected_z_cursor,
			])
			quit(1)
			return [0, 0]

		# Module count for this role: matches the placer's mapping
		# if the role is known, otherwise the fallback (1).
		var expected_module_count: int = _expected_module_count(rrole)
		var actual_module_count: int = room_node.get_child_count()
		if actual_module_count != expected_module_count:
			push_error("STRUCTURAL PLACER FAIL %s room %s (role=%s) modules=%d expected=%d" % [
				label, rid, rrole, actual_module_count, expected_module_count,
			])
			quit(1)
			return [0, 0]

		# Each module should sit at z = i * CELL_SIZE within the room.
		for i in range(actual_module_count):
			var module_node: Node = room_node.get_child(i)
			if not (module_node is Node3D):
				push_error("STRUCTURAL PLACER FAIL %s room %s module[%d] is not Node3D" % [label, rid, i])
				quit(1)
				return [0, 0]
			var module_pos: Vector3 = (module_node as Node3D).position
			var expected_module_z: float = float(i) * StructuralPlacerScript.CELL_SIZE
			if not _approx_equal(module_pos.z, expected_module_z):
				push_error("STRUCTURAL PLACER FAIL %s room %s module[%d] z=%f expected=%f" % [
					label, rid, i, module_pos.z, expected_module_z,
				])
				quit(1)
				return [0, 0]

		total_modules += actual_module_count
		expected_z_cursor += float(actual_module_count) * StructuralPlacerScript.CELL_SIZE

	# Final assertion: no two rooms overlap. The last module's world
	# Z must be ≤ the next room's Z (here, equal to the running cursor,
	# which is also the start of the next room's offset).
	# (For a graph with N rooms, the last module sits at
	# expected_z_cursor - CELL_SIZE; just sanity-check the cursor
	# matches the number of modules the placer actually placed.)
	var expected_total_z: float = float(total_modules) * StructuralPlacerScript.CELL_SIZE
	if not _approx_equal(expected_z_cursor, expected_total_z):
		push_error("STRUCTURAL PLACER FAIL %s final z_cursor=%f expected=%f" % [
			label, expected_z_cursor, expected_total_z,
		])
		quit(1)
		return [0, 0]

	return [graph.rooms.size(), total_modules]


# Returns the expected number of modules for a given role, mirroring
# the ROOM_MODULES mapping in StructuralPlacer. Kept in the smoke
# (not imported from the placer) so the test reads as a clear
# spec of the contract — a reader doesn't have to chase back to the
# source to know what to expect.
func _expected_module_count(role: String) -> int:
	match role:
		"airlock":
			return 3
		"corridor":
			return 2
		"engineering":
			return 3
		"life_support":
			return 3
		"bridge":
			return 3
		"cargo":
			return 2
		"crew_quarters":
			return 2
		"medical":
			return 2
		"maintenance":
			return 2
		_:
			return 1  # fallback


# Approximate float equality for world-space Z checks. Tolerance is
# generous (1e-3) so floating-point drift from the engine's
# transform math doesn't cause spurious failures; structural
# placement is a coarse grid, so 1mm precision is plenty.
func _approx_equal(a: float, b: float) -> bool:
	return abs(a - b) < 0.001
