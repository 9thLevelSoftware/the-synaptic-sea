extends SceneTree

## Domain 6 class-catalog smoke: the 8 base classes remain always-available, the
## 3 unlockable classes exist with valid data and unlockable=true, and each
## registry class-unlock carries a class_id that matches a real class.
##
## Marker: `CLASS CATALOG PASS`

const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

const BASE_CLASSES := ["engineer", "mechanic", "medic", "pilot", "scientist", "cook", "security", "communications"]
const UNLOCKABLE_CLASSES := ["salvage_captain", "field_medic", "signal_specialist"]

func _initialize() -> void:
	var classes: Dictionary = ClassDefinitionScript.load_all()
	if classes.size() != 11:
		_fail("expected 11 classes, got %d" % classes.size())
		return
	for cid in BASE_CLASSES:
		if not classes.has(cid):
			_fail("missing base class %s" % cid)
			return
		if bool(classes[cid].unlockable):
			_fail("base class %s should NOT be unlockable" % cid)
			return
	for cid in UNLOCKABLE_CLASSES:
		if not classes.has(cid):
			_fail("missing unlockable class %s" % cid)
			return
		if not bool(classes[cid].unlockable):
			_fail("class %s should be unlockable" % cid)
			return
		if (classes[cid].xp_multipliers as Dictionary).is_empty():
			_fail("unlockable class %s has no xp_multipliers" % cid)
			return

	# Registry class-category entries carry a class_id that resolves to a real class.
	var text: String = FileAccess.get_file_as_string("res://data/player/unlock_tables.json")
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("unlock_tables.json parse failed")
		return
	var class_entries: int = 0
	for entry in ((parsed as Dictionary).get("unlocks", []) as Array):
		if str((entry as Dictionary).get("category", "")) != "class":
			continue
		class_entries += 1
		var cid: String = str((entry as Dictionary).get("class_id", ""))
		if cid.is_empty() or not classes.has(cid):
			_fail("class unlock %s has invalid class_id '%s'" % [str((entry as Dictionary).get("unlock_id","")), cid])
			return
	if class_entries != 3:
		_fail("expected 3 class-category unlocks, got %d" % class_entries)
		return

	print("CLASS CATALOG PASS base=8 unlockable=3 registry_class_ids=ok")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CLASS CATALOG FAIL reason=%s" % reason)
	quit(1)
