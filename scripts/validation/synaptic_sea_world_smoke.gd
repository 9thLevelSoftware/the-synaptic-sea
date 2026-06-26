extends SceneTree

const WorldScript := preload("res://scripts/systems/synaptic_sea_world.gd")

func _initialize() -> void:
	var world = WorldScript.new(42, Vector3.ZERO)

	var near: Array = world.markers_in_range(250.0)
	if near.is_empty():
		_fail("expected markers within radius 250")
		return

	# Every returned marker is within the radius.
	for m in near:
		if m.position.distance_to(world.player_position) > 250.0 + 0.001:
			_fail("marker beyond radius returned")
			return

	# Sorted ascending by distance.
	for i in range(1, near.size()):
		var d_prev: float = near[i - 1].position.distance_to(world.player_position)
		var d_cur: float = near[i].position.distance_to(world.player_position)
		if d_cur + 0.001 < d_prev:
			_fail("markers not sorted ascending by distance")
			return

	# Monotonic: a larger radius returns at least as many markers.
	var far: Array = world.markers_in_range(500.0)
	if far.size() < near.size():
		_fail("larger radius returned fewer markers")
		return

	# No duplicate marker_ids.
	var ids: Dictionary = {}
	for m in near:
		if ids.has(m.marker_id):
			_fail("duplicate marker_id in range result")
			return
		ids[m.marker_id] = true

	# generated set.
	var first_id: String = near[0].marker_id
	if world.is_generated(first_id):
		_fail("marker should not be pre-generated")
		return
	world.mark_generated(first_id)
	if not world.is_generated(first_id):
		_fail("mark_generated did not stick")
		return

	# Round-trip.
	world.set_player_position(Vector3(123.0, 0.0, -45.0))
	var summary: Dictionary = world.get_summary()
	var world2 = WorldScript.new(0, Vector3.ZERO)
	if not world2.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if world2.world_seed != 42:
		_fail("world_seed not restored")
		return
	if world2.player_position.distance_to(Vector3(123.0, 0.0, -45.0)) > 0.001:
		_fail("player_position not restored")
		return
	if not world2.is_generated(first_id):
		_fail("generated set not restored")
		return

	print("SYNAPTIC_SEA WORLD PASS in_range_sorted=true generated=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SYNAPTIC_SEA WORLD FAIL reason=%s" % reason)
	quit(1)
