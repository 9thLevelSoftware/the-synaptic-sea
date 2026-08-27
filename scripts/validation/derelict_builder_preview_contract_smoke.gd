extends SceneTree

const PreviewScript := preload("res://scripts/procgen/derelict_builder_preview.gd")

var _root := ""


func _initialize() -> void:
	_root = "user://derelict_builder_preview_contract_%d" % Time.get_ticks_usec()
	if not DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root)) in [OK, ERR_ALREADY_EXISTS]:
		_fail("could not create temporary contract directory")
		return
	var source_path := _write("source.json", {"document_kind": "golden_area"})
	var layout_path := _write("layout.json", {"schema_version": "layout", "kit_id": "kit_a"})
	var gameplay_path := _write("gameplay.json", {"schema_version": "gameplay"})
	var kit_path := _write("kit.json", {"kit_id": "kit_a"})
	var preview := PreviewScript.new()
	preview.manifest_path = ProjectSettings.globalize_path(_root.path_join("manifest.json"))
	var manifest := {
		"document_kind": "derelict_builder_bundle",
		"validation_result": "passed",
		"source_path": source_path,
		"layout_path": layout_path,
		"gameplay_slice_path": gameplay_path,
		"kit_path": kit_path,
		"source_hash": _hash(source_path),
		"layout_hash": _hash(layout_path),
		"gameplay_slice_hash": _hash(gameplay_path),
		"layout_schema": "layout",
		"gameplay_schema": "gameplay",
		"kit_id": "kit_a",
	}
	var errors: Array[String] = preview._validate_manifest(manifest)
	if not errors.is_empty():
		_fail("matching kit rejected: %s" % str(errors))
		return
	_write("kit.json", {"kit_id": "kit_b"})
	manifest["kit_path"] = kit_path
	errors = preview._validate_manifest(manifest)
	if not errors.has("kit kit_id does not match manifest") or not errors.has("kit kit_id does not match layout"):
		_fail("kit identity mismatch was not diagnosed: %s" % str(errors))
		return
	var checks := {}
	for key in PreviewScript.REQUIRED_CHECKS:
		checks[key] = true
	var marker := preview._canonical_success_marker(checks)
	var expected := "DERELICT BUILDER PREVIEW PASS collision=true navigation=true verticals=true objectives=true props=true loot=true fire=true arc=true breach=true radiation=true atmosphere=true"
	if marker != expected:
		_fail("canonical marker changed: %s" % marker)
		return
	print("DERELICT BUILDER PREVIEW CONTRACT PASS kit_identity=true marker=true")
	quit(0)


func _write(name: String, value: Dictionary) -> String:
	var path := _root.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(value) + "\n")
	file.close()
	return ProjectSettings.globalize_path(path)


func _hash(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_string(path).to_utf8_buffer())
	return context.finish().hex_encode()


func _fail(message: String) -> void:
	push_error("DERELICT BUILDER PREVIEW CONTRACT FAIL %s" % message)
	quit(1)
