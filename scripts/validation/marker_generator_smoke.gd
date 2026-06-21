extends SceneTree

const GenScript := preload("res://scripts/systems/marker_generator.gd")
const MarkerScript := preload("res://scripts/systems/ship_marker.gd")

func _initialize() -> void:
	var gen = GenScript.new()

	# Determinism: same (world_seed, cell) -> identical markers.
	var a: Array = gen.markers_for_cell(42, Vector2i(3, -1))
	var b: Array = gen.markers_for_cell(42, Vector2i(3, -1))
	if a.size() != GenScript.MARKERS_PER_CELL:
		_fail("expected %d markers per cell, got %d" % [GenScript.MARKERS_PER_CELL, a.size()])
		return
	for i in range(a.size()):
		if a[i].to_dict() != b[i].to_dict():
			_fail("non-deterministic marker at index %d" % i)
			return

	# Different cell -> different marker set (ids differ at least).
	var c: Array = gen.markers_for_cell(42, Vector2i(4, -1))
	if c[0].marker_id == a[0].marker_id and c[0].seed_value == a[0].seed_value:
		_fail("different cell produced identical first marker")
		return

	# Marker positions fall inside the cell's world span; seeds are distinct.
	var seeds: Dictionary = {}
	for m in a:
		var base_x: float = float(3) * GenScript.CELL_SIZE
		var base_z: float = float(-1) * GenScript.CELL_SIZE
		if m.position.x < base_x or m.position.x > base_x + GenScript.CELL_SIZE:
			_fail("marker x outside cell span")
			return
		if m.position.z < base_z or m.position.z > base_z + GenScript.CELL_SIZE:
			_fail("marker z outside cell span")
			return
		if absf(m.position.y) > 0.0001:
			_fail("marker y should be 0")
			return
		seeds[m.seed_value] = true
	if seeds.size() != a.size():
		_fail("marker seed_values not distinct")
		return

	# ShipMarker round-trip.
	var rt = MarkerScript.from_dict(a[0].to_dict())
	if rt.to_dict() != a[0].to_dict():
		_fail("ShipMarker round-trip mismatch")
		return

	print("MARKER GENERATOR PASS deterministic=true per_cell=%d round_trip=true" % GenScript.MARKERS_PER_CELL)
	quit(0)

func _fail(reason: String) -> void:
	push_error("MARKER GENERATOR FAIL reason=%s" % reason)
	quit(1)
