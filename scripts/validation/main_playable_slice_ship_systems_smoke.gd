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
	# Surface missing API explicitly so RED output is unambiguous.
	if not playable.has_method("get_ship_systems_summary"):
		_fail("get_ship_systems_summary missing")
		return
	if playable.ship_systems == null:
		_fail("ship_systems null")
		return

	# Initial state assertions ----------------------------------------------------
	var initial: Dictionary = playable.get_ship_systems_summary()
	for key in [
		"emergency_supplies_recovered",
		"main_power_restored",
		"navigation_logs_downloaded",
		"reactor_stabilized",
		"blocked_routes_cleared",
		"extraction_unlocked",
	]:
		if not initial.has(key):
			_fail("summary missing key %s" % key)
			return
		if bool(initial[key]):
			_fail("initial %s should be false" % key)
			return
	if int(initial.get("power_percent", -1)) != 18:
		_fail("initial power_percent=%d expected 18" % int(initial.get("power_percent", -1)))
		return
	if int(initial.get("reactor_stability_percent", -1)) != 22:
		_fail("initial reactor_stability_percent=%d expected 22" % int(initial.get("reactor_stability_percent", -1)))
		return
	if int(initial.get("blocked_affordance_visible_count", -1)) < 1:
		_fail("initial blocked_affordance_visible_count=%d expected >=1" % int(initial.get("blocked_affordance_visible_count", -1)))
		return

	# Objective 1: recover_supplies ----------------------------------------------
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete_objective_sequence_for_validation(1) returned false")
		return
	var s1: Dictionary = playable.get_ship_systems_summary()
	if not bool(s1.get("emergency_supplies_recovered", false)):
		_fail("after obj1 emergency_supplies_recovered=false")
		return
	if int(s1.get("completed_system_count", 0)) != 1:
		_fail("after obj1 completed_system_count=%d expected 1" % int(s1.get("completed_system_count", 0)))
		return
	var hud_text_1: String = playable.tracker.get_hud_text()
	if not hud_text_1.contains("Systems:"):
		_fail("after obj1 HUD missing 'Systems:' section")
		return

	# Objective 2: restore_systems -----------------------------------------------
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete_objective_sequence_for_validation(2) returned false")
		return
	var s2: Dictionary = playable.get_ship_systems_summary()
	if not bool(s2.get("main_power_restored", false)):
		_fail("after obj2 main_power_restored=false")
		return
	if not bool(s2.get("blocked_routes_cleared", false)):
		_fail("after obj2 blocked_routes_cleared=false")
		return
	if int(s2.get("power_percent", 0)) != 72:
		_fail("after obj2 power_percent=%d expected 72" % int(s2.get("power_percent", 0)))
		return
	if int(s2.get("blocked_affordance_visible_count", -1)) != 0:
		_fail("after obj2 blocked_affordance_visible_count=%d expected 0" % int(s2.get("blocked_affordance_visible_count", -1)))
		return

	# Objective 3: download_logs -------------------------------------------------
	if not playable.complete_objective_sequence_for_validation(3):
		_fail("complete_objective_sequence_for_validation(3) returned false")
		return
	var s3: Dictionary = playable.get_ship_systems_summary()
	if not bool(s3.get("navigation_logs_downloaded", false)):
		_fail("after obj3 navigation_logs_downloaded=false")
		return

	# Objective 4: stabilize_reactor --------------------------------------------
	if not playable.complete_objective_sequence_for_validation(4):
		_fail("complete_objective_sequence_for_validation(4) returned false")
		return
	var s4: Dictionary = playable.get_ship_systems_summary()
	if not bool(s4.get("reactor_stabilized", false)):
		_fail("after obj4 reactor_stabilized=false")
		return
	if int(s4.get("reactor_stability_percent", 0)) != 100:
		_fail("after obj4 reactor_stability_percent=%d expected 100" % int(s4.get("reactor_stability_percent", 0)))
		return
	if not bool(s4.get("extraction_unlocked", false)):
		_fail("after obj4 extraction_unlocked=false")
		return
	if not bool(playable.get_slice_completion_summary().get("run_complete", false)):
		_fail("after obj4 slice_complete=false")
		return

	# Idempotence: re-applying obj4 must not duplicate sequence or counters.
	playable.ship_systems.apply_objective(4, "stabilize_reactor", "reactor_01:reactor_01_reactor_control_panel", "reactor_01")
	var s4b: Dictionary = playable.get_ship_systems_summary()
	if int(s4b.get("completed_system_count", 0)) != 4:
		_fail("idempotent reapply completed_system_count=%d expected 4" % int(s4b.get("completed_system_count", 0)))
		return
	var seq_array: Array = s4b.get("completed_sequences", [])
	if seq_array.size() != 4:
		_fail("completed_sequences size=%d expected 4" % seq_array.size())
		return

	# Direct model-level idempotence check (independent of slice lifecycle).
	var model := ShipSystemState.new()
	model.apply_objective(1, "recover_supplies", "obj1", "cargo_01")
	model.apply_objective(1, "recover_supplies", "obj1", "cargo_01")
	model.apply_objective(2, "restore_systems", "obj2", "maintenance_01")
	if model.get_summary().get("completed_sequences", []).size() != 2:
		_fail("direct model idempotence failed: completed_sequences size=%d expected 2" % model.get_summary().get("completed_sequences", []).size())
		return
	if int(model.get_summary().get("power_percent", 0)) != 72:
		_fail("direct model idempotence: power_percent=%d expected 72 after second apply of restore_systems" % int(model.get_summary().get("power_percent", 0)))
		return
	if int(model.get_summary().get("completed_system_count", 0)) != 2:
		_fail("direct model idempotence: completed_system_count=%d expected 2" % int(model.get_summary().get("completed_system_count", 0)))
		return

	finished = true
	print("MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4")
	# Clean up the test-spawned main scene to avoid Godot leak warnings on quit.
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
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
	push_error("MAIN PLAYABLE SHIP SYSTEMS FAIL reason=%s" % reason)
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)