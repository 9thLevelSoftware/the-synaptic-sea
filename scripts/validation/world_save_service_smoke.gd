extends SceneTree

## Disk round-trip smoke for SaveLoadService world save/load.

const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const CURRENT_WORLD_FIXTURE: String = \
	"res://tests/fixtures/feature_completion/p10_world_v5_transactional.json"

func _initialize() -> void:
	var svc = SaveLoadServiceScript.new()
	svc.delete_current_run()  # start clean

	var ws = _current_world_fixture(svc)
	if ws == null:
		_fail("current fixture could not be prepared")
		return
	ws.world_summary = {
		"world_seed": 5,
		"player_position": [0.0, 0.0, 0.0],
		"generated_marker_ids": ["marker-away"],
	}
	ws.current_location = ""
	ws.player_position_in_ship = [4.0, 1.0, 6.0]
	ws.saved_at = "2026-06-21T00:00:00"
	svc.set_active_run_id(str(ws.run_id))

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
	if String(loaded.current_location) != "":
		_fail("current_location not round-tripped through disk")
		return
	if not loaded.visited_ships.has("marker-away") \
			or str((loaded.visited_ships["marker-away"] as Dictionary).get("ship_id", "")).is_empty():
		_fail("visited_ships not round-tripped through disk")
		return
	if int(loaded.world_summary.get("world_seed", -1)) != 5:
		_fail("world_summary not round-tripped through disk")
		return
	if loaded.player_position_in_ship != [4.0, 1.0, 6.0]:
		_fail("player_position_in_ship not round-tripped through disk")
		return

	# Reject null snapshot.
	var rejected_null: Dictionary = svc._coherent_world_for_write(
		null, "world", "manual", false)
	if bool(rejected_null.get("ok", false)) \
			or str(rejected_null.get("reason", "")) != "invalid_snapshot":
		_fail("save_world(null) should return false")
		return

	svc.delete_current_run()
	if svc.load_world() != null:
		_fail("load_world should return null when no save exists")
		return

	print("WORLD SAVE SERVICE PASS disk_round_trip=true rejects_null=true")
	quit(0)


func _current_world_fixture(svc: RefCounted):
	var source: String = FileAccess.get_file_as_string(CURRENT_WORLD_FIXTURE)
	if source.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(source)
	if not parsed is Dictionary:
		return null
	_replace_fixture_version(parsed)
	source = JSON.stringify(parsed, "", true, true)
	var saves_dir: String = SaveLoadServiceScript.SAVES_DIR
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves_dir)) != OK:
		return null
	var file := FileAccess.open(SaveLoadServiceScript.WORLD_SLOT_FILE, FileAccess.WRITE)
	if file == null:
		return null
	file.store_string(source)
	file.close()
	var prepared: Dictionary = svc.prepare_world_load()
	if not bool(prepared.get("ok", false)):
		return null
	var token: String = str(prepared.get("token", ""))
	var seal: String = str(prepared.get("seal", ""))
	var current_dict: Dictionary = svc.inspect_prepared_world_for_validation(token, seal)
	svc.discard_prepared_load(token)
	return WorldSnapshotScript.from_dict(
		current_dict, WorldSnapshotScript.WORLD_SLICE_VERSION,
		Engine.get_version_info()["string"])


func _replace_fixture_version(value: Variant) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		for key in dict.keys():
			if str(key) == "godot_version" and str(dict[key]) == "fixture-current":
				dict[key] = Engine.get_version_info()["string"]
			else:
				_replace_fixture_version(dict[key])
	elif value is Array:
		for item in value as Array:
			_replace_fixture_version(item)

func _fail(reason: String) -> void:
	push_error("WORLD SAVE SERVICE FAIL reason=%s" % reason)
	quit(1)
