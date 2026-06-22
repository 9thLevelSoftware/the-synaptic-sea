extends SceneTree

## Pure-model: occupancy resolves which ship interior contains the player,
## with first-entry (host) priority on overlap and null when outside all.

const ShipOccupancyScript := preload("res://scripts/systems/ship_occupancy.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""
	var host = ShipInstanceScript.create("host", "", null, null, null)
	var mobile = ShipInstanceScript.create("mobile", "", null, null, null)
	# Host occupies x in [0,10]; mobile occupies x in [9,19] (overlap at [9,10]).
	var host_aabb := AABB(Vector3(0, -1, -5), Vector3(10, 2, 10))
	var mobile_aabb := AABB(Vector3(9, -1, -5), Vector3(10, 2, 10))
	var entries := [{"inst": host, "aabb": host_aabb}, {"inst": mobile, "aabb": mobile_aabb}]

	if ShipOccupancyScript.resolve(Vector3(2, 0, 0), entries) != host:
		ok = false; msg = "point in host not resolved to host"
	if ok and ShipOccupancyScript.resolve(Vector3(15, 0, 0), entries) != mobile:
		ok = false; msg = "point in mobile not resolved to mobile"
	if ok and ShipOccupancyScript.resolve(Vector3(9.5, 0, 0), entries) != host:
		ok = false; msg = "seam overlap did not tiebreak to host (first entry)"
	if ok and ShipOccupancyScript.resolve(Vector3(100, 0, 0), entries) != null:
		ok = false; msg = "point outside all did not resolve to null"
	# Malformed-entry regression: defensive guards must skip bad entries.
	if ok and ShipOccupancyScript.resolve(Vector3(2, 0, 0), [42, {"inst": host, "aabb": host_aabb}]) != host:
		ok = false; msg = "non-dict entry not skipped (host should still match)"
	if ok and ShipOccupancyScript.resolve(Vector3(15, 0, 0), [{"inst": host, "aabb": "notanaabb"}, {"inst": mobile, "aabb": mobile_aabb}]) != mobile:
		ok = false; msg = "wrong-type aabb not skipped (mobile should match)"

	if ok:
		print("SHIP OCCUPANCY PASS contained=true tiebreak=host outside=null malformed=true")
		quit(0)
	else:
		push_error("SHIP OCCUPANCY FAIL reason=%s" % msg)
		quit(1)
