extends Node3D
class_name GeneratedShipDemo

const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ProcgenDebugRunnerScript := preload("res://scripts/procgen/procgen_debug_runner.gd")
const ObjectiveTrackerScript := preload("res://scripts/ui/objective_tracker.gd")

signal demo_completed(objective_count: int, interaction_count: int, frame_count: int, final_distance: float)
signal demo_failed(reason: String)

const DEFAULT_LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const DEFAULT_KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const DEFAULT_GAMEPLAY_SLICE_PATH: String = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
const DEFAULT_TIMEOUT_FRAMES: int = 9000

var timeout_frames: int = DEFAULT_TIMEOUT_FRAMES
var loader
var runner
var tracker
var demo_started: bool = false


func _ready() -> void:
	loader = GeneratedShipLoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(_on_ship_loaded)
	loader.load_failed.connect(_on_loader_failed)
	add_child(loader)

	runner = ProcgenDebugRunnerScript.new()
	runner.name = "ProcgenDebugRunner"
	runner.objective_reached.connect(_on_objective_reached)
	runner.run_completed.connect(_on_run_completed)
	runner.run_failed.connect(_on_run_failed)
	add_child(runner)

	tracker = ObjectiveTrackerScript.new()
	tracker.name = "ObjectiveTracker"
	add_child(tracker)

	var camera: Camera3D = Camera3D.new()
	camera.name = "GeneratedShipCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	camera.current = true
	camera.look_at_from_position(Vector3(60.0, 80.0, 80.0), Vector3(60.0, 0.0, 8.0), Vector3.UP)
	add_child(camera)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "GeneratedShipLight"
	light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	light.light_energy = 1.5
	add_child(light)

	loader.load_from_paths(DEFAULT_LAYOUT_PATH, DEFAULT_KIT_PATH, DEFAULT_GAMEPLAY_SLICE_PATH)


func _on_ship_loaded(summary: Dictionary) -> void:
	if demo_started:
		return
	demo_started = true
	if runner.get_parent() != loader.structural_root:
		runner.get_parent().remove_child(runner)
		loader.structural_root.add_child(runner)
	print(
		"RUNTIME SHIP LOADED wrappers=%d vertical_links=%d objectives=%d"
		% [
			int(summary.get("instantiated_count", 0)),
			int(summary.get("vertical_link_count", 0)),
			int(summary.get("objective_count", 0)),
		]
	)
	tracker.set_objectives(loader.objective_specs)
	runner.start_run(loader.start_position, loader.objective_specs, loader.objective_volumes, loader.goal_position, timeout_frames)


func _on_loader_failed(reason: String) -> void:
	push_error("RUNTIME GAMEPLAY DEMO FAIL reason=%s" % reason)
	emit_signal("demo_failed", reason)


func _on_objective_reached(objective_id: String, sequence: int, objective_type: String, room_id: String) -> void:
	print(
		"RUNTIME INTERACTION objective=%s sequence=%d type=%s room=%s"
		% [objective_id, sequence, objective_type, room_id]
	)
	tracker.mark_completed(sequence)


func _on_run_completed(objective_count: int, interaction_count: int, frame_count: int, final_distance: float) -> void:
	tracker.mark_run_complete()
	print(
		"RUNTIME GAMEPLAY DEMO PASS objectives=%d interactions=%d frames=%d final_distance=%.3f"
		% [objective_count, interaction_count, frame_count, final_distance]
	)
	emit_signal("demo_completed", objective_count, interaction_count, frame_count, final_distance)


func _on_run_failed(reason: String) -> void:
	push_error("RUNTIME GAMEPLAY DEMO FAIL reason=%s" % reason)
	emit_signal("demo_failed", reason)
