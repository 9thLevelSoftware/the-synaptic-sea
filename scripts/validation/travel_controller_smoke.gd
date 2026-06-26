extends SceneTree

const WorldScript := preload("res://scripts/systems/synaptic_sea_world.gd")
const TravelScript := preload("res://scripts/systems/travel_controller.gd")
const GeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const MarkerScript := preload("res://scripts/systems/ship_marker.gd")

func _initialize() -> void:
	var world = WorldScript.new(42, Vector3.ZERO)
	var travel = TravelScript.new()
	var generator = GeneratorScript.new()

	var in_range: Array = world.markers_in_range(250.0)
	if in_range.is_empty():
		_fail("no markers in range to travel to")
		return
	var target = in_range[0]

	# Propulsion offline -> rejected, world unchanged.
	var r_prop: Dictionary = travel.attempt_travel(target, {"propulsion": false}, world, generator, 250.0)
	if bool(r_prop.get("success", true)) or str(r_prop.get("reason", "")) != "propulsion_offline":
		_fail("propulsion offline should reject, got %s" % str(r_prop))
		return
	if world.is_generated(target.marker_id):
		_fail("world mutated on rejected travel")
		return

	# Out of range -> rejected (a marker id that is not in range).
	var bogus = MarkerScript.new()
	bogus.marker_id = "9999:9999:0"
	bogus.position = Vector3(1000000.0, 0.0, 0.0)
	bogus.seed_value = 7
	var r_range: Dictionary = travel.attempt_travel(bogus, {"propulsion": true}, world, generator, 250.0)
	if bool(r_range.get("success", true)) or str(r_range.get("reason", "")) != "out_of_range":
		_fail("out-of-range marker should reject, got %s" % str(r_range))
		return

	# Valid jump -> success, real ship Node3D, world updated.
	var r_ok: Dictionary = travel.attempt_travel(target, {"propulsion": true}, world, generator, 250.0)
	if not bool(r_ok.get("success", false)):
		_fail("valid travel should succeed, got %s" % str(r_ok))
		return
	var ship = r_ok.get("ship", null)
	if ship == null or not (ship is Node3D):
		_fail("travel did not return a Node3D ship")
		return
	if not world.is_generated(target.marker_id):
		_fail("world did not record generated marker")
		return
	if world.player_position.distance_to(target.position) > 0.001:
		_fail("player_position not updated to target")
		return

	# Free the generated ship to avoid leak noise beyond the allowlisted baseline.
	ship.queue_free()

	print("TRAVEL CONTROLLER PASS propulsion_gate=true range_gate=true generated_node=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("TRAVEL CONTROLLER FAIL reason=%s" % reason)
	quit(1)
