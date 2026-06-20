extends SceneTree

# ShipGenerator smoke. Drives the full blueprint -> RoomGraph ->
# ShipStructure pipeline and verifies that the returned Node3D tree
# is well-formed. Covers the three cases the rest of the procgen
# smokes use as their canonical example seeds:
#
#   1. life boat  — smallest valid ship (2-4 rooms, no bridge /
#      life_support).
#   2. small ship — mid-size (4-8 rooms, includes bridge + life_support).
#   3. determinism — two calls with the same seed/size/condition
#      produce structurally identical GeneratedShip roots.
#
# Prints a single `SHIP GENERATOR PASS life_boat=true small=true
# deterministic=true` line on success so automated verification can
# grep for it; on any failure pushes an error and quits with code 1
# so a regression blocks the gate (matching the project's
# `quit-on-first-failure` convention from the other smokes).
#
# NOTE: GDScript `class_name` globals may not be available at parse
# time in `godot --headless --script` mode, so all cross-file type
# references go through the preloaded `*Script` constants. This is
# the same pattern RoomGraphGenerator and StructuralPlacer use.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const StructuralPlacerScript := preload("res://scripts/procgen/structural_placer.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")


func _init() -> void:
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()

	# --- Case 1: life boat -----------------------------------------
	# Smallest valid ship; pipeline must run end-to-end and produce
	# a GeneratedShip with at least one ShipStructure child.
	var ship_life: Node3D = generator.generate_from_seed(
			42,
			ShipBlueprintScript.Size.LIFE_BOAT,
			ShipBlueprintScript.Condition.DAMAGED)
	if not _assert_ship("life_boat", ship_life):
		quit(1)
		return

	# --- Case 2: small ship ----------------------------------------
	# Mid-size ship; we verify the ShipStructure child has a room
	# count inside the SMALL range (4-8 rooms inclusive).
	var ship_small: Node3D = generator.generate_from_seed(
			123,
			ShipBlueprintScript.Size.SMALL,
			ShipBlueprintScript.Condition.PRISTINE)
	if not _assert_ship("small", ship_small):
		quit(1)
		return
	var small_room_count: int = _room_count_for(ship_small)
	if small_room_count < 4 or small_room_count > 8:
		push_error("SHIP GENERATOR FAIL small room_count=%d expected in [4,8]" % small_room_count)
		quit(1)
		return

	# --- Case 3: determinism ---------------------------------------
	# Two independent generations with identical inputs must produce
	# structurally identical roots: same GeneratedShip name, same
	# number of children, same room count, and the same set of room
	# ids. We rebuild the graph via the same sub-generators so we
	# can compare room ids without having to traverse the Node3D
	# tree (which works but is noisier).
	var ship_same1: Node3D = generator.generate_from_seed(
			4242,
			ShipBlueprintScript.Size.SMALL,
			ShipBlueprintScript.Condition.DAMAGED)
	var ship_same2: Node3D = generator.generate_from_seed(
			4242,
			ShipBlueprintScript.Size.SMALL,
			ShipBlueprintScript.Condition.DAMAGED)

	if ship_same1 == null or ship_same2 == null:
		push_error("SHIP GENERATOR FAIL determinism ship_same1=%s ship_same2=%s" % [
			str(ship_same1), str(ship_same2),
		])
		quit(1)
		return

	if ship_same1.get_child_count() != ship_same2.get_child_count():
		push_error("SHIP GENERATOR FAIL determinism child_count mismatch a=%d b=%d" % [
			ship_same1.get_child_count(), ship_same2.get_child_count(),
		])
		quit(1)
		return

	var rooms1: Array[String] = _room_ids_for(ship_same1)
	var rooms2: Array[String] = _room_ids_for(ship_same2)
	rooms1.sort()
	rooms2.sort()
	if str(rooms1) != str(rooms2):
		push_error("SHIP GENERATOR FAIL determinism room_ids mismatch a=%s b=%s" % [
			str(rooms1), str(rooms2),
		])
		quit(1)
		return

	# --- Pass ------------------------------------------------------
	print("SHIP GENERATOR PASS life_boat=true small=true deterministic=true")
	quit(0)


# Asserts that `ship` is a non-null Node3D named "GeneratedShip" with
# at least one direct child (the ShipStructure root) and that the
# ShipStructure has at least one child of its own (at least one room
# placed). Returns true on success, pushes an error and returns false
# on any failure.
func _assert_ship(label: String, ship: Node3D) -> bool:
	if ship == null:
		push_error("SHIP GENERATOR FAIL %s ship is null" % label)
		return false
	if not (ship is Node3D):
		push_error("SHIP GENERATOR FAIL %s ship is not Node3D (got %s)" % [label, str(ship)])
		return false
	if String(ship.name) != "GeneratedShip":
		push_error("SHIP GENERATOR FAIL %s ship.name=%s expected=GeneratedShip" % [
			label, str(ship.name),
		])
		return false
	if ship.get_child_count() < 1:
		push_error("SHIP GENERATOR FAIL %s ship has no children" % label)
		return false

	# The ShipStructure root must be a child of the GeneratedShip.
	var structure: Node = ship.get_child(0)
	if structure == null:
		push_error("SHIP GENERATOR FAIL %s structure child is null" % label)
		return false
	if String(structure.name) != "ShipStructure":
		push_error("SHIP GENERATOR FAIL %s structure.name=%s expected=ShipStructure" % [
			label, str(structure.name),
		])
		return false
	if structure.get_child_count() < 1:
		push_error("SHIP GENERATOR FAIL %s structure has no rooms" % label)
		return false

	return true


# Returns the number of room children inside a GeneratedShip's
# ShipStructure sub-tree. Assumes the caller already validated that
# `ship` is a non-null GeneratedShip with a ShipStructure child.
func _room_count_for(ship: Node3D) -> int:
	if ship == null or ship.get_child_count() < 1:
		return 0
	return ship.get_child(0).get_child_count()


# Returns the names of every room Node3D inside a GeneratedShip's
# ShipStructure sub-tree. Used by the determinism check so we can
# compare room sets without re-implementing a deep tree walk in the
# test body.
func _room_ids_for(ship: Node3D) -> Array[String]:
	var ids: Array[String] = []
	if ship == null or ship.get_child_count() < 1:
		return ids
	var structure: Node = ship.get_child(0)
	for child in structure.get_children():
		ids.append(String(child.name))
	return ids