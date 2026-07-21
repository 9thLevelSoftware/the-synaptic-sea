extends SceneTree

## Asserts data/ui/status_effect_icons.json paths resolve to on-disk resources
## (Stream C content pass: placeholder PNGs under assets/placeholder/).
##
## Marker: STATUS EFFECT ICONS PASS entries=8 all_exist=true

func _init() -> void:
	var path: String = "res://data/ui/status_effect_icons.json"
	if not FileAccess.file_exists(path):
		_fail("catalog missing")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("catalog not a dict")
		return
	var catalog: Dictionary = parsed
	if catalog.is_empty():
		_fail("catalog empty")
		return
	var missing: Array = []
	for effect_id in catalog.keys():
		var icon_path: String = str(catalog[effect_id])
		if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
			# FileAccess.file_exists works for res:// after import; also try raw.
			if not FileAccess.file_exists(icon_path):
				missing.append("%s -> %s" % [str(effect_id), icon_path])
	if not missing.is_empty():
		_fail("missing icons: %s" % str(missing))
		return
	print("STATUS EFFECT ICONS PASS entries=%d all_exist=true" % catalog.size())
	quit()

func _fail(reason: String) -> void:
	push_error("STATUS EFFECT ICONS FAIL reason=%s" % reason)
	quit(1)
