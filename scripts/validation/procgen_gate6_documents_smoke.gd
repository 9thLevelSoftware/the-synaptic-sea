extends SceneTree

const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const StartSceneBuilderScript := preload("res://scripts/procgen/start_scene_builder.gd")

const EXACT_KEYS: Array[String] = [
	"bundle", "request", "layout", "gameplay_slice", "kit",
	"semantic_hash", "fallback_selected",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var before_temp: Dictionary = _files_under("user://procgen_temp")
	var before_start: Dictionary = _files_under("user://start_scenario")
	var generator: RefCounted = ShipGeneratorScript.new()
	generator.configure_run_context("breach_field", "standard")
	generator.configure_procgen_site("site-gate6-42", 4, -2)
	var documents: Dictionary = generator.generate_documents_from_seed(42, 1, 2, "freighter")
	if documents.is_empty():
		_fail("generation %s" % str(generator.last_error))
		return
	var keys: Array = documents.keys()
	keys.sort()
	var expected: Array = EXACT_KEYS.duplicate()
	expected.sort()
	if keys != expected:
		_fail("document shape")
		return
	var metrics: Variant = (documents.bundle as Dictionary).get("metrics", null)
	if not metrics is Dictionary or int((metrics as Dictionary).get("pipeline_executions", 0)) != 1:
		_fail("pipeline execution count")
		return
	var semantic_hash: String = str(documents.semantic_hash)
	if semantic_hash.length() != 64:
		_fail("semantic hash")
		return
	var replay: Dictionary = generator.generate_documents_from_request(
		(documents.request as Dictionary).duplicate(true), semantic_hash)
	if replay.is_empty() or str(replay.get("semantic_hash", "")) != semantic_hash:
		_fail("exact request replay")
		return
	var assembled: Node3D = generator.instantiate_documents(documents, true)
	if assembled == null or not assembled.has_meta("procgen_request") \
			or str(assembled.get_meta("procgen_semantic_hash", "")) != semantic_hash:
		if assembled != null:
			assembled.free()
		_fail("document assembly metadata")
		return
	assembled.free()
	var start_scene: Node3D = StartSceneBuilderScript.build(42)
	if start_scene == null or start_scene.get_child_count() != 2 \
			or not start_scene.has_meta("procgen_request") \
			or str(start_scene.get_meta("procgen_semantic_hash", "")).length() != 64:
		if start_scene != null:
			start_scene.free()
		_fail("start scene in-memory bundle")
		return
	start_scene.free()
	if _has_new_files(before_temp, _files_under("user://procgen_temp")) \
			or _has_new_files(before_start, _files_under("user://start_scenario")):
		_fail("fixed temporary file created")
		return
	print("PROCGEN GATE6 DOCUMENTS PASS bundle=true single_execution=true replay=true loader=true start_scene=true no_temp_files=true")
	quit(0)


func _files_under(path: String) -> Dictionary:
	var found: Dictionary = {}
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return found
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."] and not directory.current_is_dir():
			found[entry] = true
		entry = directory.get_next()
	directory.list_dir_end()
	return found


func _has_new_files(before: Dictionary, after: Dictionary) -> bool:
	for path in after:
		if not before.has(path):
			return true
	return false


func _fail(reason: String) -> void:
	push_error("PROCGEN GATE6 DOCUMENTS FAIL reason=%s" % reason)
	quit(1)
