extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	var bootstrap := SaveLoadService.new()
	bootstrap.delete_current_run()
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
	var prog = playable.get_player_progression()
	if prog == null:
		_fail("player_progression null")
		return
	if prog.get_class_id() != "engineer":
		_fail("default class=%s expected engineer" % prog.get_class_id())
		return
	var repair_xp_before: int = int(prog.get_summary().get("skill_xp", {}).get("repair", 0))

	# Complete objective 1 (no repair XP) then objective 2 (restore_systems -> repair XP).
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete obj1 failed")
		return
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete obj2 failed")
		return

	var repair_xp_after: int = int(prog.get_summary().get("skill_xp", {}).get("repair", 0))
	if repair_xp_after <= repair_xp_before:
		_fail("repair XP did not increase after restore_systems (%d -> %d)" % [repair_xp_before, repair_xp_after])
		return
	if not playable.get_combined_system_status_lines_contains("Repair Skill:"):
		_fail("HUD missing 'Repair Skill:' line")
		return

	# Save/load round-trips progression.
	if not playable.request_save():
		_fail("request_save failed")
		return
	if not playable.request_load():
		_fail("request_load failed")
		return
	var prog_after_load = playable.get_player_progression()
	var xp_loaded: int = int(prog_after_load.get_summary().get("skill_xp", {}).get("repair", 0))
	if xp_loaded != repair_xp_after:
		_fail("repair XP not restored after load (%d != %d)" % [xp_loaded, repair_xp_after])
		return

	finished = true
	print("MAIN PLAYABLE PROGRESSION PASS class=engineer repair_xp_gained=true hud=true round_trip=true")
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	var svc := SaveLoadService.new()
	svc.delete_current_run()
	quit(0)

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
	push_error("MAIN PLAYABLE PROGRESSION FAIL reason=%s" % reason)
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
