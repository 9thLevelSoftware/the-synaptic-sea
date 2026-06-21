extends SceneTree

## REQ-012 main-scene save/load smoke.
##
## Loads the main playable scene via MAIN_SCENE.instantiate(), waits for
## the ship loader to finish, completes objective 1, calls request_save(),
## then calls request_load() and asserts the player position, objective
## sequence, and emergency_supplies_recovered flag are all restored.
## Finally completes all objectives and confirms the save slot was
## deleted on run completion.
##
## Pass marker: MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
const POSITION_TOLERANCE: float = 0.01

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	# Clean any leftover save from a prior run.
	var bootstrap_service := SaveLoadService.new()
	bootstrap_service.delete_current_run()

	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	# Surface missing API explicitly so RED output is unambiguous.
	if not playable.has_method("get_save_load_service"):
		_fail("get_save_load_service missing")
		return
	if not playable.has_method("get_last_saved_snapshot"):
		_fail("get_last_saved_snapshot missing")
		return
	if not playable.has_method("request_save"):
		_fail("request_save missing")
		return
	if not playable.has_method("request_load"):
		_fail("request_load missing")
		return

	var service: SaveLoadService = playable.get_save_load_service()
	if service == null:
		_fail("save_load_service null")
		return

	# Complete objective 1 and force a manual save.
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective 1 failed")
		return
	if playable.get_current_objective_sequence() != 2:
		_fail("expected sequence 2 after objective 1, got %d" % playable.get_current_objective_sequence())
		return

	var saved_pos: Vector3 = playable.player.global_position
	if not playable.request_save():
		_fail("request_save returned false")
		return
	var last_snapshot: RunSnapshot = playable.get_last_saved_snapshot()
	if last_snapshot == null:
		_fail("last saved snapshot null")
		return
	if last_snapshot.current_objective_sequence != 2:
		_fail("saved snapshot sequence=%d expected 2" % last_snapshot.current_objective_sequence)
		return
	# The snapshot persists the authoritative objective record; the
	# flag-shaped fields (emergency_supplies_recovered, etc.) are derived
	# live from it via _manager_compat_summary(), not stored.
	var saved_types: Array = last_snapshot.ship_systems_summary.get("completed_objective_types", [])
	if not saved_types.has("recover_supplies"):
		_fail("saved snapshot missing completed_objective_types=recover_supplies")
		return

	# Move the player so the load has somewhere to teleport back from.
	playable.player.teleport_to(saved_pos + Vector3(10.0, 0.0, 0.0))
	var moved_pos: Vector3 = playable.player.global_position
	if moved_pos.distance_to(saved_pos) < 1.0:
		_fail("player teleport did not actually move")
		return

	# Load and assert restored state.
	if not playable.request_load():
		_fail("request_load returned false")
		return
	if playable.get_current_objective_sequence() != 2:
		_fail("loaded sequence=%d expected 2" % playable.get_current_objective_sequence())
		return
	var loaded_pos: Vector3 = playable.player.global_position
	if loaded_pos.distance_to(saved_pos) > POSITION_TOLERANCE:
		_fail("loaded position distance=%f > tolerance" % loaded_pos.distance_to(saved_pos))
		return
	var ship_summary: Dictionary = playable.get_ship_systems_summary()
	if not bool(ship_summary.get("emergency_supplies_recovered", false)):
		_fail("emergency_supplies_recovered not restored after load")
		return

	# Run completion must delete the save.
	if not playable.complete_all_objectives_for_validation():
		_fail("complete_all_objectives_for_validation failed")
		return
	if service.has_save():
		_fail("save file still exists after run completion")
		return

	finished = true
	print("MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true")
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE SAVE LOAD FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	var service := SaveLoadService.new()
	service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
