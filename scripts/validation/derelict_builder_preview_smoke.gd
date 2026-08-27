extends SceneTree

const PreviewScript := preload("res://scripts/procgen/derelict_builder_preview.gd")
const LAYOUT_SOURCE := "res://data/procgen/golden/coherent_ship_001/layout.json"
const GAMEPLAY_SOURCE := "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"
const KIT_SOURCE := "res://data/kits/ship_structural_v0.json"
const PREVIEW_SCENE := "res://scenes/procgen/derelict_builder_preview.tscn"
const TIMEOUT_SECONDS := 45.0
const REQUIRED_CHECKS := PreviewScript.REQUIRED_CHECKS

var _child_pid := -1
var _bundle_dir := ""
var _result_path := ""


func _initialize() -> void:
	var token := "%d_%d" % [Time.get_ticks_usec(), randi() & 0xffff]
	_bundle_dir = "user://derelict_builder_preview_smoke_%s" % token
	_result_path = _bundle_dir.path_join("preview_result.json")
	if not DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_bundle_dir)) in [OK, ERR_ALREADY_EXISTS]:
		_fail("could not create temporary bundle directory")
		return
	var layout := _read_json(LAYOUT_SOURCE)
	var gameplay := _read_json(GAMEPLAY_SOURCE)
	var kit := _read_json(KIT_SOURCE)
	if layout.is_empty() or gameplay.is_empty() or kit.is_empty():
		_fail("coherent fixture is unavailable")
		return
	# Exercise every authored runtime consumer with representative data. The
	# golden fixture intentionally omits some optional hazards, which previously
	# let acceptance succeed through "not applicable" branches alone.
	layout["fire_zones"] = [_zone("preview_fire", "timed_fire", "spine_01", "cargo_01", [6, 0, 1], [6, -1, 1])]
	layout["arc_zones"] = [
		_zone("preview_arc_a", "electrical_arc", "airlock_01", "corridor_01", [1, 0, 0], [2, 0, 0]),
		_zone("preview_arc_b", "electrical_arc", "corridor_01", "ramp_01", [3, 0, 0], [4, 0, 0]),
	]
	layout["breach_zones"] = [
		_zone("preview_breach_airlock", "hull_breach", "airlock_01", "corridor_01", [1, 0, 0], [2, 0, 0]),
		_zone("preview_breach_ramp", "hull_breach", "corridor_01", "ramp_01", [3, 0, 0], [4, 0, 0]),
	]
	layout["radiation_zones"] = [_zone("preview_radiation", "radiation", "corridor_01", "ramp_01", [3, 0, 0], [4, 0, 0])]
	var rooms: Array = layout.get("rooms", [])
	if not rooms.is_empty() and rooms[0] is Dictionary:
		var authored_room: Dictionary = rooms[0]
		authored_room["oxygen_bp"] = 10000
		authored_room["depressurized"] = false
		rooms[0] = authored_room
	if rooms.size() > 1 and rooms[1] is Dictionary:
		var vented_room: Dictionary = rooms[1]
		vented_room.erase("oxygen_bp")
		vented_room.erase("depressurized")
		vented_room["vented"] = true
		rooms[1] = vented_room
	if rooms.size() > 2 and rooms[2] is Dictionary:
		var irradiated_hot_room: Dictionary = rooms[2]
		irradiated_hot_room["radiation_bp"] = 5000
		irradiated_hot_room["temperature_c"] = 60
		rooms[2] = irradiated_hot_room
	layout["rooms"] = rooms
	var loot: Array = gameplay.get("loot_containers", [])
	if not loot.is_empty() and loot[0] is Dictionary:
		var authored_loot: Dictionary = loot[0]
		authored_loot["contents"] = [{"item_id": "scrap_metal", "qty": 2}]
		loot[0] = authored_loot
		gameplay["loot_containers"] = loot
	var layout_path := _write_json("layout.json", layout)
	var gameplay_path := _write_json("gameplay_slice.json", gameplay)
	var kit_path := _write_json("kit.json", kit)
	var source_path := _write_text("source.golden_area.json", JSON.stringify({
		"schema_version": "1.0.0",
		"document_kind": "golden_area",
		"kit_id": str(kit.get("kit_id", "ship_structural_v0")),
		"rooms": [],
	}, "\t") + "\n")
	if layout_path.is_empty() or gameplay_path.is_empty() or kit_path.is_empty() or source_path.is_empty():
		_fail("could not write temporary bundle")
		return
	var manifest := {
		"document_kind": "derelict_builder_bundle",
		"validation_result": "passed",
		"source_path": source_path,
		"layout_path": layout_path,
		"gameplay_slice_path": gameplay_path,
		"kit_path": kit_path,
		"source_hash": _file_hash(source_path),
		"layout_hash": _file_hash(layout_path),
		"gameplay_slice_hash": _file_hash(gameplay_path),
		"layout_schema": str(layout.get("schema_version", "")),
		"gameplay_schema": str(gameplay.get("schema_version", "")),
		"kit_id": str(layout.get("kit_id", kit.get("kit_id", ""))),
		"result_path": _result_path,
	}
	var manifest_path := _write_json("manifest.json", manifest)
	if manifest_path.is_empty():
		_fail("could not write manifest")
		return
	var godot := OS.get_environment("DERELICT_PREVIEW_GODOT")
	if godot.is_empty():
		godot = OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	_child_pid = OS.create_process(godot, [
		"--headless", "--path", project_path, "--scene", PREVIEW_SCENE,
		"--", "--manifest", ProjectSettings.globalize_path(manifest_path),
	])
	if _child_pid <= 0:
		_fail("could not launch preview process")
		return
	_poll_child()


func _poll_child() -> void:
	var elapsed := 0.0
	while elapsed < TIMEOUT_SECONDS:
		await create_timer(0.1).timeout
		if FileAccess.file_exists(_result_path):
			var result := _read_json(_result_path)
			if result.is_empty():
				_fail("preview result is invalid JSON")
				return
			if not bool(result.get("ok", false)):
				_fail("preview reported failure: %s" % JSON.stringify(result.get("errors", [])))
				return
			var checks: Dictionary = result.get("checks", {})
			for check in REQUIRED_CHECKS:
				if not bool(checks.get(check, false)):
					_fail("preview core check failed: %s" % check)
					return
			if not bool(checks.get("fire_scene_consumer", false)):
				_fail("preview fire scene consumer was not burning and visible")
				return
			if not bool(checks.get("breach_scene_consumer", false)):
				_fail("preview breach scene consumer did not drain oxygen")
				return
			print("DERELICT BUILDER PREVIEW SMOKE PASS checks=%d bundle=%s" % [REQUIRED_CHECKS.size(), _bundle_dir])
			quit(0)
			return
		elapsed += 0.1
	if _child_pid > 0 and OS.is_process_running(_child_pid):
		OS.kill(_child_pid)
	_fail("preview timed out after %.1f seconds" % TIMEOUT_SECONDS)


func _write_json(name: String, value: Dictionary) -> String:
	return _write_text(name, JSON.stringify(value, "\t") + "\n")


func _write_text(name: String, content: String) -> String:
	var path := _bundle_dir.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(content)
	file.close()
	return path


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _file_hash(path: String) -> String:
	var content := FileAccess.get_file_as_string(path)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(content.to_utf8_buffer())
	return context.finish().hex_encode()


func _zone(id: String, kind: String, from_room: String, to_room: String, from_cell: Array, to_cell: Array) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"from_room": from_room,
		"to_room": to_room,
		"from_cell": from_cell,
		"to_cell": to_cell,
		"module_id": "",
		"rationale": "builder runtime preview smoke",
	}


func _fail(message: String) -> void:
	if _child_pid > 0 and OS.is_process_running(_child_pid):
		OS.kill(_child_pid)
	push_error("DERELICT BUILDER PREVIEW SMOKE FAIL %s" % message)
	quit(1)
