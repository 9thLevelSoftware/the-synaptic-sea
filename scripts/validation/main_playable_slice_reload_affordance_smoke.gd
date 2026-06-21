extends SceneTree

## Reload regression smoke (PR #2 review finding).
##
## Completing `restore_systems` (objective 2) clears the blocked-biomatter
## affordances. A save/load reload rebuilds those affordances visible, so the
## restore-snapshot path must RE-APPLY the restore_systems consequence or the
## blocked affordances reappear after loading a game where they were cleared.
##
## Flow: complete obj1 + obj2 -> assert blocked affordances cleared live ->
## save -> reload -> assert blocked affordances STILL cleared after reload.
##
## Pass marker: MAIN PLAYABLE RELOAD AFFORDANCE PASS cleared_live=true cleared_after_reload=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
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
	# There must be at least one blocked affordance to begin with, or the test
	# proves nothing.
	if playable.get_blocked_affordance_visible_count() < 1:
		_fail("expected >=1 blocked affordance at start")
		return

	# Complete objective 1 (recover_supplies) then objective 2 (restore_systems).
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective 1 failed")
		return
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete objective 2 (restore_systems) failed")
		return

	# Live: restore_systems must have cleared the blocked affordances.
	if playable.get_blocked_affordance_visible_count() != 0:
		_fail("blocked affordances not cleared live after restore_systems (count=%d)" % playable.get_blocked_affordance_visible_count())
		return

	# Save, move the player, then reload.
	if not playable.request_save():
		_fail("request_save returned false")
		return
	playable.player.teleport_to(playable.player.global_position + Vector3(8.0, 0.0, 0.0))
	if not playable.request_load():
		_fail("request_load returned false")
		return

	# Regression assertion: reload rebuilds blocked affordances visible, so the
	# restore-snapshot path must re-clear them. Without the fix this is >= 1.
	if playable.get_blocked_affordance_visible_count() != 0:
		_fail("blocked affordances reappeared after reload (count=%d)" % playable.get_blocked_affordance_visible_count())
		return

	finished = true
	print("MAIN PLAYABLE RELOAD AFFORDANCE PASS cleared_live=true cleared_after_reload=true")
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
	push_error("MAIN PLAYABLE RELOAD AFFORDANCE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	var service := SaveLoadService.new()
	service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
