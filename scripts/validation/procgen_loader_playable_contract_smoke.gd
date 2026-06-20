extends SceneTree

const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ObjectiveTrackerScript := preload("res://scripts/ui/objective_tracker.gd")

const LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"

var loaded: bool = false
var failed_reason: String = ""


func _initialize() -> void:
	var root_node: Node3D = Node3D.new()
	root_node.name = "LoaderPlayableContractSmokeRoot"
	get_root().add_child(root_node)

	var loader = GeneratedShipLoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(_on_ship_loaded)
	loader.load_failed.connect(_on_load_failed)
	root_node.add_child(loader)

	var ok: bool = loader.load_from_paths(LAYOUT_PATH, KIT_PATH, GAMEPLAY_SLICE_PATH)
	if not ok or not loaded:
		push_error("loader contract smoke failed: load_failed reason=%s" % failed_reason)
		quit(1)
		return

	if not loader.has_loaded_ship():
		push_error("loader contract smoke failed: has_loaded_ship=false")
		quit(1)
		return
	if loader.get_start_transform().origin == Vector3.INF:
		push_error("loader contract smoke failed: invalid start transform")
		quit(1)
		return
	if loader.get_goal_position() == Vector3.INF:
		push_error("loader contract smoke failed: invalid goal position")
		quit(1)
		return
	if loader.get_objective_specs_copy().size() != 4:
		push_error(
			"loader contract smoke failed: expected 4 objectives got %d"
			% loader.get_objective_specs_copy().size()
		)
		quit(1)
		return
	if loader.count_collision_shapes() <= 0:
		push_error("loader contract smoke failed: collision shape count is zero")
		quit(1)
		return

	var tracker = ObjectiveTrackerScript.new()
	tracker.name = "LoaderPlayableContractSmokeTracker"
	root_node.add_child(tracker)
	tracker.set_objectives(loader.get_objective_specs_copy())
	tracker.mark_completed(1)
	if tracker.get_completed_count() != 1 or not tracker.is_sequence_completed(1):
		push_error("loader contract smoke failed: tracker helper methods failed")
		quit(1)
		return

	print(
		"PROCGEN LOADER PLAYABLE CONTRACT PASS loaded=true objectives=4 collision_shapes=%d"
		% loader.count_collision_shapes()
	)
	quit(0)


func _on_ship_loaded(_summary: Dictionary) -> void:
	loaded = true


func _on_load_failed(reason: String) -> void:
	failed_reason = reason
