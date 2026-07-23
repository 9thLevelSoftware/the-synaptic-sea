extends SceneTree

## WorkAction catalog xp_event values resolve in training_actions.json.
## Marker: WORK ACTION XP CATALOG PASS cut=true weld=true salvage=true repair=true

const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")


func _initialize() -> void:
	var wa = WorkActionCatalogScript.new()
	if not wa.load_default():
		_fail("work catalog"); return
	var text: String = FileAccess.get_file_as_string("res://data/player/training_actions.json")
	if text.is_empty():
		_fail("training file"); return
	var required: Dictionary = {
		"cut_wall": "salvage",
		"weld_patch": "weld_panel",
		"pry_panel": "salvage",
		"patch_breach": "repair",
		"unbolt_component": "salvage",
	}
	for aid in required.keys():
		if not wa.has_action(str(aid)):
			_fail("missing action %s" % aid); return
		var def: Dictionary = wa.get_action(str(aid))
		var xp: String = str(def.get("xp_event", ""))
		if xp != str(required[aid]):
			_fail("action %s expected xp %s got %s" % [aid, required[aid], xp]); return
		if text.find("\"event_id\": \"%s\"" % xp) < 0 and text.find("\"%s\"" % xp) < 0:
			# looser: event_id line contains the id
			if text.find(xp) < 0:
				_fail("training missing event %s" % xp); return
	# Explicit aliases that work catalog historically used
	for alias in ["weld", "salvage", "repair", "cooking", "weld_panel"]:
		if text.find(alias) < 0:
			_fail("training missing alias %s" % alias); return
	print("WORK ACTION XP CATALOG PASS cut=true weld=true salvage=true repair=true")
	quit(0)


func _fail(msg: String) -> void:
	print("WORK ACTION XP CATALOG FAIL: %s" % msg)
	quit(1)
