extends SceneTree
# t_963ca6d7 source-backed fire zone marker smoke.
# Asserts that the golden coherent_ship_001 fire zone is declared in BOTH
# data files (layout.json + gameplay_slice.json), targets a non-critical
# side room, is not the obj3 -> obj4 breach corridor, and that the scene's
# FIRE_ZONE_FALLBACK_ROOM_ID constant points at the same room id.
#
# Headless: /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless
#   --path /Users/christopherwilloughby/the-sargasso-of-stars
#   --script res://scripts/validation/golden_fire_zone_source_marker_smoke.gd
#
# Pass marker: GOLDEN FIRE ZONE SOURCE MARKER PASS marker_room=cargo_01

const GOLDEN_LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
const GOLDEN_GAMEPLAY_SLICE_PATH: String = "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"
const EXPECTED_FIRE_ZONE_ID: String = "side_corridor_fire"
const EXPECTED_FIRE_ZONE_KIND: String = "timed_fire"

func _initialize() -> void:
	var layout_doc: Dictionary = _load_dict(GOLDEN_LAYOUT_PATH, "layout")
	if layout_doc.is_empty():
		_fail("could not load golden layout")
		return
	var slice_doc: Dictionary = _load_dict(GOLDEN_GAMEPLAY_SLICE_PATH, "gameplay_slice")
	if slice_doc.is_empty():
		_fail("could not load golden gameplay_slice")
		return

	var layout_marker: Dictionary = _find_fire_zone_marker(layout_doc, "layout.json")
	if layout_marker.is_empty():
		_fail("layout.json has no fire_zones marker")
		return
	var slice_marker: Dictionary = _find_fire_zone_marker(slice_doc, "gameplay_slice.json")
	if slice_marker.is_empty():
		_fail("gameplay_slice.json has no fire_zones marker")
		return

	# Schema consistency between the two markers.
	for key in ["id", "from_room", "to_room", "from_cell", "to_cell", "module_id", "kind"]:
		if str(layout_marker.get(key, "")) != str(slice_marker.get(key, "")):
			_fail("marker mismatch on key '%s': layout=%s slice=%s" % [
				key, str(layout_marker.get(key, "")), str(slice_marker.get(key, "")),
			])
			return
	if str(layout_marker.get("id", "")) != EXPECTED_FIRE_ZONE_ID:
		_fail("unexpected fire_zone id '%s'" % str(layout_marker.get("id", "")))
		return
	if str(layout_marker.get("kind", "")) != EXPECTED_FIRE_ZONE_KIND:
		_fail("unexpected fire_zone kind '%s'" % str(layout_marker.get("kind", "")))
		return

	# Critical-path guard: the fire zone must NOT block the main route.
	var critical_path: Array = slice_doc.get("critical_path", [])
	if critical_path.is_empty():
		_fail("gameplay_slice missing critical_path")
		return
	var target_room: String = str(layout_marker.get("to_room", ""))
	if target_room.is_empty():
		_fail("fire zone marker missing to_room")
		return
	if critical_path.has(target_room):
		_fail("fire zone target room '%s' is on critical_path %s" % [target_room, str(critical_path)])
		return

	# Breach corridor guard: obj3 -> obj4 must remain fire-free.
	var objectives: Array = slice_doc.get("objectives", [])
	var obj3: Dictionary = {}
	var obj4: Dictionary = {}
	for objective in objectives:
		var seq: int = int(objective.get("sequence", -1))
		if seq == 3:
			obj3 = objective
		elif seq == 4:
			obj4 = objective
	if obj3.is_empty() or obj4.is_empty():
		_fail("gameplay_slice missing objectives 3 or 4")
		return
	var breach_link: Dictionary = {"from": str(obj3.get("room_id", "")), "to": str(obj4.get("room_id", ""))}
	var marker_link: Dictionary = {
		"from": str(layout_marker.get("from_room", "")),
		"to": str(layout_marker.get("to_room", "")),
	}
	if (marker_link["from"] == breach_link["from"] and marker_link["to"] == breach_link["to"]) \
		or (marker_link["from"] == breach_link["to"] and marker_link["to"] == breach_link["from"]):
		_fail("fire zone marker sits on obj3<->obj4 breach corridor %s" % str(breach_link))
		return

	# Scene fallback constant must agree with the marker target room.
	var scene_script: Script = load("res://scripts/procgen/playable_generated_ship.gd") as Script
	if scene_script == null:
		_fail("could not load playable_generated_ship.gd")
		return
	var constants: Dictionary = scene_script.get_script_constant_map()
	var fallback_room: String = str(constants.get("FIRE_ZONE_FALLBACK_ROOM_ID", ""))
	if fallback_room.is_empty():
		_fail("FIRE_ZONE_FALLBACK_ROOM_ID constant missing in playable_generated_ship.gd")
		return
	if fallback_room != target_room:
		_fail("FIRE_ZONE_FALLBACK_ROOM_ID='%s' does not match marker to_room='%s'" % [fallback_room, target_room])
		return

	# critical_path arrays must not have changed (card: "Do NOT change the critical_path arrays").
	var layout_crit: Array = layout_doc.get("critical_path", [])
	if layout_crit != critical_path:
		_fail("layout critical_path %s differs from slice critical_path %s" % [str(layout_crit), str(critical_path)])
		return

	# Exactly one fire zone per file (card: "Do NOT introduce randomized or multi-fire placement").
	if (layout_doc.get("fire_zones", []) as Array).size() != 1:
		_fail("layout.json fire_zones count != 1")
		return
	if (slice_doc.get("fire_zones", []) as Array).size() != 1:
		_fail("gameplay_slice.json fire_zones count != 1")
		return

	print("GOLDEN FIRE ZONE SOURCE MARKER PASS marker_room=%s kind=%s breach_room=%s target_on_critical_path=false" % [
		target_room,
		EXPECTED_FIRE_ZONE_KIND,
		"%s<->%s" % [str(breach_link.get("from", "")), str(breach_link.get("to", ""))],
	])
	quit(0)

func _load_dict(resource_path: String, label: String) -> Dictionary:
	var abs_path: String = resource_path.trim_prefix("res://")
	if not FileAccess.file_exists(abs_path):
		push_error("file not found (%s): %s" % [label, abs_path])
		return {}
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		push_error("could not open (%s): %s" % [label, abs_path])
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("invalid JSON (%s): %s" % [label, abs_path])
		return {}
	return parsed

func _find_fire_zone_marker(doc: Dictionary, label: String) -> Dictionary:
	var zones_variant: Variant = doc.get("fire_zones", [])
	if typeof(zones_variant) != TYPE_ARRAY:
		push_error("%s fire_zones is not an array" % label)
		return {}
	var zones: Array = zones_variant
	for zone_variant in zones:
		if typeof(zone_variant) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_variant
		if str(zone.get("id", "")) == EXPECTED_FIRE_ZONE_ID:
			return zone
	return {}

func _fail(reason: String) -> void:
	push_error("GOLDEN FIRE ZONE SOURCE MARKER FAIL reason=%s" % reason)
	quit(1)
