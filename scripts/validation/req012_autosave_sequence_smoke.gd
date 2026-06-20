extends SceneTree

## REQ-012 auto-save sequence smoke.
##
## Permanent regression assertion for the REQ-012 acceptance criterion
## that the automatic save created at an objective-completion boundary
## records the NEXT current objective sequence (after objective 1: 2),
## not the just-completed sequence.
##
## This smoke completes objective 1 and asserts the auto-saved snapshot
## BEFORE any manual request_save() call. The earlier
## `main_playable_slice_save_load_smoke.gd` called request_save() after
## completing objective 1, which masked the bug where the auto-save
## captured the just-completed sequence while the live state had already
## advanced.
##
## Pass marker: REQ012 AUTOSAVE SEQUENCE CHECK PASS live=2 snapshot=2 file=2 has_save=true
## Fail marker: REQ012 AUTOSAVE CHECK FAIL reason=...

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

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
	var service: SaveLoadService = playable.get_save_load_service()
	if service == null:
		_fail("save_load_service null")
		return
	if service.has_save():
		_fail("unexpected pre-existing save after bootstrap cleanup")
		return
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective 1 failed")
		return
	# REQ-012 acceptance check: at this point only the auto-save from
	# objective 1's completion boundary has run. Inspect the live state,
	# the in-memory last-saved snapshot, and the on-disk file BEFORE
	# any manual request_save() call.
	var live_sequence: int = playable.get_current_objective_sequence()
	var last_snapshot: RunSnapshot = playable.get_last_saved_snapshot()
	var snapshot_sequence: int = -1
	if last_snapshot != null:
		snapshot_sequence = last_snapshot.current_objective_sequence
	var loaded: RunSnapshot = service.load_current_run()
	var file_sequence: int = -1
	if loaded != null:
		file_sequence = loaded.current_objective_sequence
	var has_save: bool = service.has_save()
	if live_sequence != 2 or not has_save or snapshot_sequence != 2 or file_sequence != 2:
		_fail("AUTOSAVE SEQUENCE CHECK actual_live=%d actual_snapshot=%d actual_file=%d has_save=%s expected=2" % [live_sequence, snapshot_sequence, file_sequence, str(has_save)])
		return
	print("REQ012 AUTOSAVE SEQUENCE CHECK PASS live=2 snapshot=2 file=2 has_save=true")
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
	push_error("REQ012 AUTOSAVE CHECK FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	var service := SaveLoadService.new()
	service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
