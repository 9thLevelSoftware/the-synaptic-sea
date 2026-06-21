extends SceneTree

## Unit smoke for WorldSnapshot: round-trip + version-mismatch rejection.

const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")

func _initialize() -> void:
	var godot_version: String = Engine.get_version_info()["string"]

	var ws = WorldSnapshotScript.new()
	ws.world_summary = {"world_seed": 99, "player_position": [1.0, 0.0, 2.0], "generated_marker_ids": ["3:1:0"]}
	ws.home_ship = {"slice_version": "gate2-current-run-1", "player_position": [5.0, 1.0, 5.0]}
	ws.visited_ships = {
		"3:1:0": {"ship_id": "ship_3:1:0", "marker_id": "3:1:0", "blueprint": {"size": 1, "condition": 2, "seed": 7}, "systems": {"k": "v"}},
	}
	ws.current_location = "3:1:0"
	ws.player_position_in_ship = [10.0, 2.0, 3.0]
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = godot_version
	ws.saved_at = "2026-06-21T00:00:00"

	var dict: Dictionary = ws.to_dict()
	var rebuilt = WorldSnapshotScript.from_dict(dict, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	if rebuilt == null:
		_fail("from_dict returned null on a valid dict")
		return
	if int(rebuilt.world_summary.get("world_seed", -1)) != 99:
		_fail("world_summary not restored")
		return
	if String(rebuilt.current_location) != "3:1:0":
		_fail("current_location not restored")
		return
	if not rebuilt.visited_ships.has("3:1:0"):
		_fail("visited_ships key not restored")
		return
	if String(rebuilt.home_ship.get("slice_version", "")) != "gate2-current-run-1":
		_fail("home_ship dict not restored")
		return
	if rebuilt.player_position_in_ship.size() != 3 or float(rebuilt.player_position_in_ship[0]) != 10.0:
		_fail("player_position_in_ship not restored")
		return

	# Version mismatch → null.
	if WorldSnapshotScript.from_dict(dict, "world-999", godot_version) != null:
		_fail("from_dict should reject mismatched world version")
		return
	if WorldSnapshotScript.from_dict(dict, WorldSnapshotScript.WORLD_SLICE_VERSION, "0.0.0") != null:
		_fail("from_dict should reject mismatched godot version")
		return
	# Non-dict / empty → null.
	if WorldSnapshotScript.from_dict(null, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version) != null:
		_fail("from_dict should reject null")
		return
	if WorldSnapshotScript.from_dict({}, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version) != null:
		_fail("from_dict should reject empty dict")
		return

	print("WORLD SNAPSHOT PASS round_trip=true version_gated=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("WORLD SNAPSHOT FAIL reason=%s" % reason)
	quit(1)
