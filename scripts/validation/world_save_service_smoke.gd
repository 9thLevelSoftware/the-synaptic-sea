extends SceneTree

## Disk round-trip smoke for SaveLoadService world save/load.

const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")

func _initialize() -> void:
	var svc = SaveLoadServiceScript.new()
	svc.delete_current_run()  # start clean

	var ws = WorldSnapshotScript.new()
	ws.world_summary = {"world_seed": 5, "player_position": [0.0, 0.0, 0.0], "generated_marker_ids": ["2:0:1"]}
	ws.home_ship = {"slice_version": "gate2-current-run-1"}
	ws.visited_ships = {"2:0:1": {"marker_id": "2:0:1", "blueprint": {"size": 0, "condition": 1, "seed": 11}, "systems": {}}}
	ws.current_location = "2:0:1"
	ws.player_position_in_ship = [4.0, 1.0, 6.0]
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = Engine.get_version_info()["string"]
	ws.saved_at = "2026-06-21T00:00:00"

	if not svc.save_world(ws):
		_fail("save_world returned false")
		return
	if not svc.has_save():
		_fail("has_save false after save_world")
		return

	var loaded = svc.load_world()
	if loaded == null:
		_fail("load_world returned null after a valid save")
		return
	if String(loaded.current_location) != "2:0:1":
		_fail("current_location not round-tripped through disk")
		return
	if not loaded.visited_ships.has("2:0:1"):
		_fail("visited_ships not round-tripped through disk")
		return
	if int(loaded.world_summary.get("world_seed", -1)) != 5:
		_fail("world_summary not round-tripped through disk")
		return

	# Reject null snapshot.
	if svc.save_world(null):
		_fail("save_world(null) should return false")
		return

	svc.delete_current_run()
	if svc.load_world() != null:
		_fail("load_world should return null when no save exists")
		return

	print("WORLD SAVE SERVICE PASS disk_round_trip=true rejects_null=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("WORLD SAVE SERVICE FAIL reason=%s" % reason)
	quit(1)
