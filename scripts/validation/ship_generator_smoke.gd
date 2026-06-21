extends SceneTree

# ShipGenerator smoke (v4 pipeline). Drives the blueprint ->
# ShipLayoutGenerator -> GeneratedShipLoader path and verifies the
# returned Node3D tree is a fully-loaded ship.
#
# The v4 ShipGenerator no longer returns a hand-placed "ShipStructure"
# tree (the legacy RoomGraphGenerator/StructuralPlacer path). It returns
# the GeneratedShipLoader root named "GeneratedShip" with two children:
#   - "StructuralRoot": instantiated structural wrapper geometry + the
#     baked NavigationRegion3D.
#   - "ObjectiveRoot": gameplay objective volumes.
# The loader also exposes accessors (has_loaded_ship, get_start_transform,
# get_goal_position, get_objective_specs_copy, layout_doc) which are the
# real contract this smoke asserts against.
#
# Cases:
#   1. life boat seed   — pipeline runs end-to-end, ship is loaded.
#   2. small seed       — independent seed also loads with geometry.
#   3. determinism      — two calls with identical seed/size/condition
#                         produce identical room id sets and child counts.
#
# Prints a single `SHIP GENERATOR PASS ...` line on success; on any
# failure pushes an error and quits with code 1 (quit-on-first-failure).
# Every generated ship is freed before the next case so the strict
# ERROR/WARNING bundle check sees no leaked RIDs at exit.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")


func _init() -> void:
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()

	# --- Case 1: life boat -----------------------------------------
	var ship_life: Node3D = generator.generate_from_seed(
			42,
			ShipBlueprintScript.Size.LIFE_BOAT,
			ShipBlueprintScript.Condition.DAMAGED)
	if not _assert_ship("life_boat", ship_life):
		_free_node(ship_life)
		quit(1)
		return
	var life_rooms: int = _room_count(ship_life)
	_free_node(ship_life)

	# --- Case 2: small ship ----------------------------------------
	var ship_small: Node3D = generator.generate_from_seed(
			123,
			ShipBlueprintScript.Size.SMALL,
			ShipBlueprintScript.Condition.PRISTINE)
	if not _assert_ship("small", ship_small):
		_free_node(ship_small)
		quit(1)
		return
	var small_rooms: int = _room_count(ship_small)
	_free_node(ship_small)
	if small_rooms < 1:
		push_error("SHIP GENERATOR FAIL small room_count=%d expected >=1" % small_rooms)
		quit(1)
		return

	# --- Case 3: determinism ---------------------------------------
	var ship_same1: Node3D = generator.generate_from_seed(
			4242,
			ShipBlueprintScript.Size.SMALL,
			ShipBlueprintScript.Condition.DAMAGED)
	var ship_same2: Node3D = generator.generate_from_seed(
			4242,
			ShipBlueprintScript.Size.SMALL,
			ShipBlueprintScript.Condition.DAMAGED)

	if not _assert_ship("determinism_a", ship_same1) or not _assert_ship("determinism_b", ship_same2):
		_free_node(ship_same1)
		_free_node(ship_same2)
		quit(1)
		return

	var rooms1: Array[String] = _room_ids(ship_same1)
	var rooms2: Array[String] = _room_ids(ship_same2)
	var struct1: Node = ship_same1.get_node_or_null("StructuralRoot")
	var struct2: Node = ship_same2.get_node_or_null("StructuralRoot")
	var struct_children_match: bool = struct1 != null and struct2 != null \
		and struct1.get_child_count() == struct2.get_child_count()
	rooms1.sort()
	rooms2.sort()
	var ids_match: bool = str(rooms1) == str(rooms2)
	_free_node(ship_same1)
	_free_node(ship_same2)

	if not ids_match:
		push_error("SHIP GENERATOR FAIL determinism room_ids mismatch a=%s b=%s" % [
			str(rooms1), str(rooms2),
		])
		quit(1)
		return
	if not struct_children_match:
		push_error("SHIP GENERATOR FAIL determinism structural child count mismatch")
		quit(1)
		return

	# --- Pass ------------------------------------------------------
	print("SHIP GENERATOR PASS life_boat=true small=true deterministic=true life_rooms=%d small_rooms=%d" % [
		life_rooms, small_rooms,
	])
	quit(0)


# Asserts that `ship` is a non-null Node3D named "GeneratedShip" that has
# fully loaded: it must report has_loaded_ship(), carry a populated
# "StructuralRoot" child (geometry instantiated), an "ObjectiveRoot" child,
# a finite spawn transform, and at least one objective.
func _assert_ship(label: String, ship: Node3D) -> bool:
	if ship == null:
		push_error("SHIP GENERATOR FAIL %s ship is null" % label)
		return false
	if String(ship.name) != "GeneratedShip":
		push_error("SHIP GENERATOR FAIL %s ship.name=%s expected=GeneratedShip" % [label, str(ship.name)])
		return false
	if not ship.has_method("has_loaded_ship") or not ship.has_loaded_ship():
		push_error("SHIP GENERATOR FAIL %s ship not loaded (has_loaded_ship false)" % label)
		return false

	var structure: Node = ship.get_node_or_null("StructuralRoot")
	if structure == null:
		push_error("SHIP GENERATOR FAIL %s missing StructuralRoot child" % label)
		return false
	if structure.get_child_count() < 1:
		push_error("SHIP GENERATOR FAIL %s StructuralRoot has no geometry" % label)
		return false

	if ship.get_node_or_null("ObjectiveRoot") == null:
		push_error("SHIP GENERATOR FAIL %s missing ObjectiveRoot child" % label)
		return false

	var spawn: Vector3 = ship.get_start_transform().origin
	if spawn == Vector3.INF:
		push_error("SHIP GENERATOR FAIL %s spawn position is INF" % label)
		return false

	if ship.get_objective_specs_copy().is_empty():
		push_error("SHIP GENERATOR FAIL %s no objectives" % label)
		return false

	return true


# Number of rooms in the loaded layout document.
func _room_count(ship: Node3D) -> int:
	if ship == null:
		return 0
	var rooms: Array = ship.layout_doc.get("rooms", [])
	return rooms.size()


# Room ids from the loaded layout document.
func _room_ids(ship: Node3D) -> Array[String]:
	var ids: Array[String] = []
	if ship == null:
		return ids
	for room in ship.layout_doc.get("rooms", []):
		ids.append(str(room.get("id", "")))
	return ids


func _free_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
