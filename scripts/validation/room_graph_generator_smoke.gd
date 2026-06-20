extends SceneTree

# RoomGraphGenerator smoke. Generates a life boat, a small ship, and a
# medium ship from fixed seeds; asserts each has the expected role
# contents, falls inside the blueprint's room-count range, and is
# fully connected. Also verifies that two generations with the same
# seed produce identical graphs (determinism) and that two
# generations with different seeds produce different graphs (the RNG
# is actually being exercised). Prints a single PASS line on success
# so automated verification can grep for it; push_error + quit(1) on
# any failure path so a regression blocks the gate rather than
# silently passing.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")


func _initialize() -> void:
	# --- Case 1: life boat ----------------------------------------
	# LIFE_BOATs are tiny (2-4 rooms), must contain airlock + engineering,
	# and must NOT contain life_support or bridge. Connectivity still
	# required.
	var lifeboat_bp: ShipBlueprintScript = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.LIFE_BOAT,
			ShipBlueprintScript.Condition.PRISTINE,
			101)
	var lifeboat_count: int = _check_basic_ship(
			"life_boat",
			lifeboat_bp,
			2, 4,
			{
				"airlock": 1,
				"engineering": 1,
			},
			{
				"life_support": 0,
				"bridge": 0,
			})
	# Airlock must be the first room so downstream placers can treat
	# it as the chain root.
	var lifeboat_gen: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var lifeboat_graph: RoomGraphScript = lifeboat_gen.generate(lifeboat_bp)
	if String(lifeboat_graph.rooms[0]["role"]) != "airlock":
		push_error("ROOM GRAPH GENERATOR FAIL life_boat first room role=%s expected=airlock" % str(lifeboat_graph.rooms[0]["role"]))
		quit(1)
		return

	# --- Case 2: small ship ---------------------------------------
	# SMALL ships (4-8 rooms) must contain airlock, engineering, and
	# bridge. life_support is also required (skip only LIFE_BOAT).
	var small_bp: ShipBlueprintScript = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.SMALL,
			ShipBlueprintScript.Condition.DAMAGED,
			202)
	var small_count: int = _check_basic_ship(
			"small",
			small_bp,
			4, 8,
			{
				"airlock": 1,
				"engineering": 1,
				"bridge": 1,
				"life_support": 1,
			},
			{})

	# --- Case 3: medium ship --------------------------------------
	# MEDIUM ships (8-12 rooms) include everything: airlock,
	# engineering, bridge, life_support, and several optional roles.
	var medium_bp: ShipBlueprintScript = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.MEDIUM,
			ShipBlueprintScript.Condition.PRISTINE,
			303)
	var medium_count: int = _check_basic_ship(
			"medium",
			medium_bp,
			8, 12,
			{
				"airlock": 1,
				"engineering": 1,
				"bridge": 1,
				"life_support": 1,
			},
			{})

	# --- Case 4: determinism --------------------------------------
	# Two generators with the same blueprint must produce identical
	# graphs (room ids, roles, and link endpoints). The shape of the
	# graph (to_dict) is the canonical fingerprint.
	var determinism_bp: ShipBlueprintScript = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.MEDIUM,
			ShipBlueprintScript.Condition.WRECKED,
			4242)
	var gen_a: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var gen_b: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var graph_a: RoomGraphScript = gen_a.generate(determinism_bp)
	var graph_b: RoomGraphScript = gen_b.generate(determinism_bp)
	var a_payload: Dictionary = graph_a.to_dict()
	var b_payload: Dictionary = graph_b.to_dict()
	if str(a_payload) != str(b_payload):
		push_error("ROOM GRAPH GENERATOR FAIL determinism mismatch a=%s b=%s" % [str(a_payload), str(b_payload)])
		quit(1)
		return

	# Also confirm that changing the seed changes the result — guards
	# against a "deterministic" generator that always returns the same
	# graph regardless of seed.
	var other_bp: ShipBlueprintScript = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.MEDIUM,
			ShipBlueprintScript.Condition.WRECKED,
			9999)
	var gen_c: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var graph_c: RoomGraphScript = gen_c.generate(other_bp)
	var c_payload: Dictionary = graph_c.to_dict()
	if str(a_payload) == str(c_payload):
		push_error("ROOM GRAPH GENERATOR FAIL different seed produced identical graph (rng not exercised)")
		quit(1)
		return

	# --- Pass -----------------------------------------------------
	print("ROOM GRAPH GENERATOR PASS life_boat=%d small=%d medium=%d deterministic=true" % [
		lifeboat_count, small_count, medium_count,
	])
	quit(0)


# Runs the common assertions (count in range, required/excluded role
# counts, full connectivity) for one blueprint and returns the
# resulting room count so the PASS line can report it.
#
# `required_roles` is a role→exact-count map; every entry must match
# the generator's output. `excluded_roles` is the inverse: every
# entry must be 0 in the output (used to assert LIFE_BOATs don't have
# bridge/life_support).
func _check_basic_ship(
		label: String,
		blueprint: ShipBlueprintScript,
		min_rooms: int,
		max_rooms: int,
		required_roles: Dictionary,
		excluded_roles: Dictionary) -> int:

	var gen: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var graph: RoomGraphScript = gen.generate(blueprint)

	if graph.rooms.size() < min_rooms or graph.rooms.size() > max_rooms:
		push_error("ROOM GRAPH GENERATOR FAIL %s rooms=%d expected=[%d,%d]" % [
			label, graph.rooms.size(), min_rooms, max_rooms,
		])
		quit(1)
		return graph.rooms.size()

	if not graph.is_fully_connected():
		push_error("ROOM GRAPH GENERATOR FAIL %s graph not fully connected" % label)
		quit(1)
		return graph.rooms.size()

	for role in required_roles.keys():
		var expected: int = int(required_roles[role])
		var actual: int = graph.get_rooms_by_role(String(role)).size()
		if actual != expected:
			push_error("ROOM GRAPH GENERATOR FAIL %s role=%s count=%d expected=%d" % [
				label, str(role), actual, expected,
			])
			quit(1)
			return graph.rooms.size()

	for role in excluded_roles.keys():
		var expected_zero: int = int(excluded_roles[role])
		var actual_n: int = graph.get_rooms_by_role(String(role)).size()
		if actual_n != expected_zero:
			push_error("ROOM GRAPH GENERATOR FAIL %s role=%s count=%d expected=%d (excluded)" % [
				label, str(role), actual_n, expected_zero,
			])
			quit(1)
			return graph.rooms.size()

	# Room ids must be unique. The generator's _add_unique_role and
	# _fill_optional_rooms paths both rely on this, but assert it
	# here as a guard against future refactors.
	var seen: Dictionary = {}
	for room in graph.rooms:
		var rid: String = String(room["id"])
		if seen.has(rid):
			push_error("ROOM GRAPH GENERATOR FAIL %s duplicate room id=%s" % [label, rid])
			quit(1)
			return graph.rooms.size()
		seen[rid] = true

	return graph.rooms.size()
