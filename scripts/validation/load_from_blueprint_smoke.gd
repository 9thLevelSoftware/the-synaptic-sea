extends SceneTree

# Integration test for PlayableGeneratedShip.load_from_blueprint() (v4 pipeline).
#
# Validates the Phase 1 integration seam: building a ship from a
# ShipBlueprint and adding it to the playable scene without going through
# the layout/kit JSON loader path. The v4 ShipGenerator returns a
# GeneratedShipLoader root named "GeneratedShip" with "StructuralRoot"
# (geometry + nav) and "ObjectiveRoot" children; the loader's accessors
# (has_loaded_ship, get_start_transform, get_objective_specs_copy,
# layout_doc) are the real contract.
#
# The test:
#   1. Instantiates PlayableGeneratedShip from its scene.
#   2. Builds a ShipBlueprint (SMALL, DAMAGED, seed=42) and calls
#      load_from_blueprint(blueprint).
#   3. Verifies the returned root is named "GeneratedShip", is parented
#      under the playable ship, reports has_loaded_ship(), and has
#      populated StructuralRoot/ObjectiveRoot children plus objectives.
#   4. Verifies a null blueprint is rejected.
#   5. Verifies all three sizes produce a loaded ship.

const PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_generated_ship.tscn")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")

var finished: bool = false


func _initialize() -> void:
	var ship = PLAYABLE_SHIP_SCENE.instantiate()
	get_root().add_child(ship)

	# Build a blueprint and call the integration seam.
	var bp = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.SMALL,
		ShipBlueprintScript.Condition.DAMAGED,
		42)

	var generated: Node3D = ship.load_from_blueprint(bp)
	if not _assert_loaded("small_damaged", generated):
		return

	# The returned root must be parented under the playable ship.
	if generated.get_parent() != ship:
		_fail("generated root not parented under playable ship")
		return

	var room_count: int = int(generated.layout_doc.get("rooms", []).size())
	if room_count < 1:
		_fail("room_count=%d expected >=1" % room_count)
		return

	# Free the first ship before further calls so repeated adds to the same
	# parent don't collide on the "GeneratedShip" node name (Godot renames
	# duplicate siblings to the unreadable "@Node3D@N" form).
	ship.remove_child(generated)
	generated.free()

	# Null blueprint rejection.
	var null_result = ship.load_from_blueprint(null)
	if null_result != null:
		_fail("null blueprint should return null")
		return

	# All three sizes produce a loaded ship.
	for size_val in [0, 1, 2]:
		var bp_test = ShipBlueprintScript.new(size_val, 1, 100 + size_val)
		var ship_test: Node3D = ship.load_from_blueprint(bp_test)
		if not _assert_loaded("size_%d" % size_val, ship_test):
			return
		ship.remove_child(ship_test)
		ship_test.free()

	print("LOAD FROM BLUEPRINT INTEGRATION PASS sizes=3 room_count=%d null_rejected=true" % room_count)
	quit(0)


# Asserts `node` is a non-null GeneratedShipLoader root named "GeneratedShip"
# that reports has_loaded_ship(), carries populated StructuralRoot and
# ObjectiveRoot children, a finite spawn, and at least one objective.
func _assert_loaded(label: String, node: Node3D) -> bool:
	if node == null:
		_fail("%s load_from_blueprint returned null" % label)
		return false
	if String(node.name) != "GeneratedShip":
		_fail("%s generated.name=%s expected=GeneratedShip" % [label, str(node.name)])
		return false
	if not node.has_method("has_loaded_ship") or not node.has_loaded_ship():
		_fail("%s ship not loaded (has_loaded_ship false)" % label)
		return false
	var structure: Node = node.get_node_or_null("StructuralRoot")
	if structure == null or structure.get_child_count() < 1:
		_fail("%s StructuralRoot missing or empty" % label)
		return false
	if node.get_node_or_null("ObjectiveRoot") == null:
		_fail("%s missing ObjectiveRoot" % label)
		return false
	if node.get_start_transform().origin == Vector3.INF:
		_fail("%s spawn position is INF" % label)
		return false
	if node.get_objective_specs_copy().is_empty():
		_fail("%s no objectives" % label)
		return false
	return true


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("LOAD FROM BLUEPRINT FAIL reason=%s" % reason)
	quit(1)
