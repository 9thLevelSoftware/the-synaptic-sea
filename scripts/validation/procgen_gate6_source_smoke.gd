extends SceneTree

## Gate 6 static guard for production, save, and debug/capture entry points.
## The legacy GDScript generator remains inside ShipGenerator only as an
## explicitly named migration oracle until all external retirement gates pass.

const FORBIDDEN_BY_SOURCE: Dictionary = {
	"res://scripts/procgen/ship_generator.gd": [
		"user://procgen_temp", "load_from_paths(",
	],
	"res://scripts/topdown/topdown_playable_ship.gd": [
		"ShipLayoutGenerator", "GameplaySliceBuilder",
		"generate_layout_migration_oracle", "user://procgen_temp",
	],
	"res://scripts/procgen/start_scene_builder.gd": [
		"ShipLayoutGenerator", "GameplaySliceBuilder", "load_from_paths(",
		"generate_layout_migration_oracle", "user://start_scenario",
	],
	"res://scripts/procgen/playable_generated_ship.gd": [
		"ShipLayoutGeneratorScript.new", "GameplaySliceBuilderScript.new",
		"generate_layout_migration_oracle", "generate_migration_oracle",
		"user://procgen_temp",
	],
	"res://scripts/procgen/generated_ship_demo.gd": [
		"load_from_paths(", "DEFAULT_LAYOUT_PATH", "DEFAULT_GAMEPLAY_SLICE_PATH",
		"generate_migration_oracle", "generate_layout_migration_oracle",
	],
	"res://scripts/validation/ship_visualize.gd": [
		"generate_migration_oracle", "generate_layout_migration_oracle",
		"ShipLayoutGenerator", "GameplaySliceBuilder", "user://procgen_temp",
	],
	"res://scripts/validation/ship_data_export.gd": [
		"generate_migration_oracle", "generate_layout_migration_oracle",
		"ShipLayoutGenerator", "GameplaySliceBuilder", "user://procgen_temp",
	],
}

const REQUIRED_BY_SOURCE: Dictionary = {
	"res://scripts/procgen/ship_generator.gd": ["load_from_documents("],
	"res://scripts/topdown/topdown_playable_ship.gd": ["generate_documents_from_seed"],
	"res://scripts/procgen/start_scene_builder.gd": [
		"generate_documents_from_seed", "instantiate_documents", "load_from_documents",
	],
	"res://scripts/procgen/playable_generated_ship.gd": [
		"configure_procgen_start", "configure_procgen_replay",
		"generate_documents_from_seed",
		"generate_documents_from_request", "load_from_documents",
		"snapshot.procgen_request", "snapshot.procgen_semantic_hash",
	],
	"res://scripts/procgen/generated_ship_demo.gd": [
		"generate_documents_from_seed", "load_from_documents",
	],
	"res://scripts/validation/ship_visualize.gd": [
		"generate_documents_from_seed", "instantiate_documents",
	],
	"res://scripts/validation/ship_data_export.gd": ["StartSceneBuilderScript.build"],
	"res://scripts/main.gd": [
		"configure_procgen_start", "configure_procgen_replay",
		"add_child(playable_instance)",
	],
	"res://scripts/title_main.gd": [
		"configure_procgen_start", "configure_procgen_replay", "add_child(main_node)",
		"Start a new world; profile and settings are preserved.",
	],
	"res://scripts/systems/run_snapshot.gd": [
		"procgen_request", "procgen_semantic_hash",
	],
	"res://scripts/systems/ship_instance.gd": [
		"procgen_request", "procgen_semantic_hash",
	],
}


func _initialize() -> void:
	for path: String in REQUIRED_BY_SOURCE:
		if not FileAccess.file_exists(path):
			_fail("missing source %s" % path)
			return
		var source: String = FileAccess.get_file_as_string(path)
		for token: String in REQUIRED_BY_SOURCE[path]:
			if not source.contains(token):
				_fail("canonical token missing path=%s token=%s" % [path, token])
				return
		for token: String in FORBIDDEN_BY_SOURCE.get(path, []):
			if source.contains(token):
				_fail("forbidden token path=%s token=%s" % [path, token])
				return
	var title_source: String = FileAccess.get_file_as_string("res://scripts/title_main.gd")
	if not _appears_before(title_source, "main_node.configure_procgen_start", "add_child(main_node)"):
		_fail("title must configure bundle start before adding main node")
		return
	var main_source: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	if not _appears_before(main_source, "playable_instance.configure_procgen_start", "add_child(playable_instance)"):
		_fail("main must configure playable before adding it")
		return
	print("PROCGEN GATE6 SOURCE PASS sources=11 save_identity=true temp_dirs=true title_order=true")
	quit(0)


func _appears_before(source: String, first: String, second: String) -> bool:
	var first_index: int = source.find(first)
	var second_index: int = source.find(second)
	return first_index >= 0 and second_index > first_index


func _fail(reason: String) -> void:
	push_error("PROCGEN GATE6 SOURCE FAIL reason=%s" % reason)
	quit(1)
