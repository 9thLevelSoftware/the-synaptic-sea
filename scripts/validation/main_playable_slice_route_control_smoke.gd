extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const EXPECTED_OBJECTIVE_COUNT: int = 4

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
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
	if not playable.has_method("get_route_control_summary"):
		_fail("get_route_control_summary missing")
		return
	if not playable.has_method("get_route_gate_nodes"):
		_fail("get_route_gate_nodes missing")
		return
	if not playable.has_method("get_route_gate_collision_enabled_count"):
		_fail("get_route_gate_collision_enabled_count missing")
		return
	if playable.get("route_control_state") == null:
		_fail("route_control_state null")
		return

	var initial: Dictionary = playable.get_route_control_summary()
	var gate_count: int = int(initial.get("route_gate_count", -1))
	if gate_count < 1:
		_fail("initial route_gate_count=%d expected >=1" % gate_count)
		return
	if int(initial.get("active_blocker_count", -1)) < 1:
		_fail("initial active_blocker_count=%d expected >=1" % int(initial.get("active_blocker_count", -1)))
		return
	if int(initial.get("opened_gate_count", -1)) != 0:
		_fail("initial opened_gate_count=%d expected 0" % int(initial.get("opened_gate_count", -1)))
		return
	if bool(initial.get("extraction_unlocked", true)):
		_fail("initial extraction_unlocked=true expected false")
		return
	if playable.get_route_gate_collision_enabled_count() < 1:
		_fail("initial route gate collision enabled count < 1")
		return

	var gate_nodes: Array = playable.get_route_gate_nodes()
	if gate_nodes.size() < 1:
		_fail("get_route_gate_nodes returned empty array")
		return
	var first_gate: Node = gate_nodes[0]
	if bool(first_gate.get_meta("route_gate_open", true)):
		_fail("initial route_gate_open meta should be false")
		return
	if str(first_gate.get_meta("required_system", "")) != "main_power_restored":
		_fail("initial route gate required_system should be main_power_restored")
		return

	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective 1 failed")
		return
	var after_one: Dictionary = playable.get_route_control_summary()
	if int(after_one.get("opened_gate_count", -1)) != 0:
		_fail("after objective 1 opened_gate_count=%d expected 0" % int(after_one.get("opened_gate_count", -1)))
		return
	if bool(after_one.get("extraction_unlocked", true)):
		_fail("after objective 1 extraction_unlocked=true expected false")
		return
	if playable.get_route_gate_collision_enabled_count() < 1:
		_fail("after objective 1 collision enabled count < 1")
		return

	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete objective 2 failed")
		return
	var ship_after_two: Dictionary = playable.get_ship_systems_summary()
	if not bool(ship_after_two.get("main_power_restored", false)):
		_fail("after objective 2 main_power_restored=false")
		return
	var after_two: Dictionary = playable.get_route_control_summary()
	if not bool(after_two.get("powered_gates_open", false)):
		_fail("after objective 2 powered_gates_open=false")
		return
	if int(after_two.get("active_blocker_count", -1)) != 0:
		_fail("after objective 2 active_blocker_count=%d expected 0" % int(after_two.get("active_blocker_count", -1)))
		return
	if int(after_two.get("opened_gate_count", -1)) < 1:
		_fail("after objective 2 opened_gate_count=%d expected >=1" % int(after_two.get("opened_gate_count", -1)))
		return
	if playable.get_route_gate_collision_enabled_count() != 0:
		_fail("after objective 2 route gate collision enabled count should be 0")
		return
	gate_nodes = playable.get_route_gate_nodes()
	first_gate = gate_nodes[0]
	if not bool(first_gate.get_meta("route_gate_open", false)):
		_fail("after objective 2 route_gate_open meta should be true")
		return
	if not bool(first_gate.get_meta("system_cleared", false)):
		_fail("after objective 2 system_cleared meta should be true")
		return

	if not playable.complete_objective_sequence_for_validation(3):
		_fail("complete objective 3 failed")
		return
	var after_three: Dictionary = playable.get_route_control_summary()
	if int(after_three.get("active_blocker_count", -1)) != 0:
		_fail("after objective 3 active_blocker_count=%d expected 0" % int(after_three.get("active_blocker_count", -1)))
		return
	if bool(after_three.get("extraction_unlocked", true)):
		_fail("after objective 3 extraction_unlocked=true expected false")
		return

	if not playable.complete_objective_sequence_for_validation(4):
		_fail("complete objective 4 failed")
		return
	var after_four: Dictionary = playable.get_route_control_summary()
	if not bool(after_four.get("extraction_unlocked", false)):
		_fail("after objective 4 extraction_unlocked=false")
		return
	if not bool(playable.get_slice_completion_summary().get("run_complete", false)):
		_fail("after objective 4 run_complete=false")
		return
	if int(after_four.get("opened_gate_count", -1)) < 1:
		_fail("after objective 4 opened_gate_count=%d expected >=1" % int(after_four.get("opened_gate_count", -1)))
		return
	if int(after_four.get("active_blocker_count", -1)) != 0:
		_fail("after objective 4 active_blocker_count=%d expected 0" % int(after_four.get("active_blocker_count", -1)))
		return

	if not _direct_route_control_model_check():
		return

	finished = true
	print("MAIN PLAYABLE ROUTE CONTROL PASS gates=%d opened=%d blockers=0 extraction=true" % [
		int(after_four.get("route_gate_count", gate_count)),
		int(after_four.get("opened_gate_count", 0)),
	])
	_cleanup_and_quit(0)

func _direct_route_control_model_check() -> bool:
	var model := RouteControlState.new()
	model.configure_from_blocked_routes(["direct_gate_01"])
	var initial: Dictionary = model.get_summary()
	if int(initial.get("active_blocker_count", -1)) != 1:
		_fail("direct model initial active_blocker_count should be 1")
		return false
	if bool(initial.get("extraction_unlocked", true)):
		_fail("direct model initial extraction_unlocked should be false")
		return false
	var changed_power_only: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": false,
		"extraction_unlocked": false,
	})
	if changed_power_only:
		_fail("direct model power-only summary should not open gates")
		return false
	if model.is_gate_open("direct_gate_01"):
		_fail("direct model gate opened without blocked_routes_cleared")
		return false
	var changed_open: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": true,
		"extraction_unlocked": false,
	})
	if not changed_open:
		_fail("direct model open summary should report changed")
		return false
	if not model.is_gate_open("direct_gate_01"):
		_fail("direct model gate did not open")
		return false
	var duplicate_open: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": true,
		"extraction_unlocked": false,
	})
	if duplicate_open:
		_fail("direct model duplicate open should be unchanged")
		return false
	var changed_extraction: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": true,
		"extraction_unlocked": true,
	})
	if not changed_extraction:
		_fail("direct model extraction unlock should report changed")
		return false
	if not model.is_extraction_unlocked():
		_fail("direct model extraction did not unlock")
		return false
	return true

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
	push_error("MAIN PLAYABLE ROUTE CONTROL FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
