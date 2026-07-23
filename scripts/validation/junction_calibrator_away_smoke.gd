extends SceneTree

## Junction calibrator SFX works with away_from_start true.
## Marker: JUNCTION CALIBRATOR AWAY PASS away=true applied=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()


func _validate() -> void:
	finished = true
	playable.away_from_start = true
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	if playable.inventory_state == null or playable.objective_progress_state == null:
		_fail("inventory/objectives missing"); return
	playable.sequence_kinds[99] = "repair_junction"
	if playable.objective_progress_state.has_method("register_sequence"):
		playable.objective_progress_state.register_sequence(99, "repair_junction", 3)
	elif playable.objective_progress_state.has_method("apply_summary"):
		playable.objective_progress_state.apply_summary({
			99: {
				"objective_type": "repair_junction",
				"required_steps": 3,
				"completed_steps": 0,
				"completed_step_ids": [],
				"complete": false,
				"calibrator_applied": false,
			}
		})
	if playable.inventory_state.has_method("add_tool"):
		playable.inventory_state.add_tool("junction_calibrator")
	else:
		playable.inventory_state.add_item("junction_calibrator", 1)
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	playable._consume_junction_calibrator_if_eligible(99)
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if after <= before:
		_fail("calibrator sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("JUNCTION CALIBRATOR AWAY PASS away=true applied=true sfx=true")
	quit(0)


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	print("JUNCTION CALIBRATOR AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
