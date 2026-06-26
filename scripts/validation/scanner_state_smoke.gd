extends SceneTree

const WorldScript := preload("res://scripts/systems/synapse_sea_world.gd")
const ScannerScript := preload("res://scripts/systems/scanner_state.gd")

func _initialize() -> void:
	var world = WorldScript.new(42, Vector3.ZERO)
	var scanner = ScannerScript.new()

	# Navigation offline -> nothing.
	var r0: Dictionary = scanner.scan(world, {"navigation": false, "scanners": true}, 10)
	if int(r0.get("detail_level", -1)) != 0 or not (r0.get("markers", [1]) as Array).is_empty():
		_fail("navigation offline should yield detail 0 + empty markers")
		return

	# Scanners offline -> detail 1, markers present, only L1 fields.
	var r1: Dictionary = scanner.scan(world, {"navigation": true, "scanners": false}, 10)
	if int(r1.get("detail_level", -1)) != 1:
		_fail("scanners offline should cap detail at 1, got %d" % int(r1.get("detail_level", -1)))
		return
	var m1: Array = r1.get("markers", [])
	if m1.is_empty():
		_fail("expected markers at detail 1")
		return
	if (m1[0] as Dictionary).has("ship_type"):
		_fail("detail 1 view should not expose ship_type")
		return
	for key in ["marker_id", "position", "distance", "size_class"]:
		if not (m1[0] as Dictionary).has(key):
			_fail("detail 1 view missing %s" % key)
			return

	# Both operational, skill 10 -> detail min(6, 1 + 10/2) = 6; full field set.
	var r6: Dictionary = scanner.scan(world, {"navigation": true, "scanners": true}, 10)
	if int(r6.get("detail_level", -1)) != 6:
		_fail("full scan should be detail 6, got %d" % int(r6.get("detail_level", -1)))
		return
	var v: Dictionary = (r6.get("markers", []) as Array)[0]
	for key in ["ship_type", "condition", "predicted_status", "predicted_offline", "loot_hint"]:
		if not v.has(key):
			_fail("detail 6 view missing %s" % key)
			return

	# Round-trip.
	scanner.range_radius = 333.0
	scanner.hardware_detail = 2
	var summary: Dictionary = scanner.get_summary()
	var scanner2 = ScannerScript.new()
	if not scanner2.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if absf(scanner2.range_radius - 333.0) > 0.001 or scanner2.hardware_detail != 2:
		_fail("scanner config not restored")
		return

	print("SCANNER STATE PASS nav_off_empty=true scanners_off_detail1=true full_detail=6 round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SCANNER STATE FAIL reason=%s" % reason)
	quit(1)
