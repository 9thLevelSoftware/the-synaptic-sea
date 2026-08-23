extends SceneTree

## Verifies slice-visible status and achievement icon paths resolve to real PNG files.
##
## Marker: UI ICON PATHS PASS status_entries=8 achievement_entries=8 all_exist=true

const STATUS_CATALOG_PATH: String = "res://data/ui/status_effect_icons.json"
const ACHIEVEMENT_CATALOG_PATH: String = "res://data/release/achievement_catalog.json"

func _init() -> void:
	var status_catalog: Variant = _load_json(STATUS_CATALOG_PATH)
	if typeof(status_catalog) != TYPE_DICTIONARY:
		_fail("status catalog is not a dictionary")
		return
	var achievements_doc: Variant = _load_json(ACHIEVEMENT_CATALOG_PATH)
	if typeof(achievements_doc) != TYPE_DICTIONARY:
		_fail("achievement catalog is not a dictionary")
		return
	var achievements_variant: Variant = (achievements_doc as Dictionary).get("achievements", null)
	if typeof(achievements_variant) != TYPE_ARRAY:
		_fail("achievement catalog has no achievements array")
		return

	var missing: Array[String] = []
	for effect_id in (status_catalog as Dictionary).keys():
		var icon_path: String = str((status_catalog as Dictionary)[effect_id])
		if not _is_real_png(icon_path):
			missing.append("status:%s -> %s" % [str(effect_id), icon_path])
	for entry in (achievements_variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			missing.append("achievement:malformed entry")
			continue
		var achievement: Dictionary = entry
		var achievement_id: String = str(achievement.get("id", ""))
		var icon_path: String = str(achievement.get("icon_placeholder", ""))
		if not _is_real_png(icon_path):
			missing.append("achievement:%s -> %s" % [achievement_id, icon_path])

	if not missing.is_empty():
		_fail("missing or invalid icons: %s" % str(missing))
		return
	print("UI ICON PATHS PASS status_entries=%d achievement_entries=%d all_exist=true" % [
		(status_catalog as Dictionary).size(),
		(achievements_variant as Array).size(),
	])
	quit()

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed

func _is_real_png(path: String) -> bool:
	if not path.begins_with("res://assets/ui/") or not path.to_lower().ends_with(".png"):
		return false
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.is_empty():
		return false
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return false
	return image.get_width() > 0 and image.get_height() > 0

func _fail(reason: String) -> void:
	push_error("UI ICON PATHS FAIL reason=%s" % reason)
	quit(1)
