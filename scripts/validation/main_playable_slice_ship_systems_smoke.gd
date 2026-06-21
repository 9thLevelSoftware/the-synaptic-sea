extends SceneTree

## Manager-driven runtime-consequence smoke. Proves the live coordinator
## derives gates/breach/extraction/HUD from ShipSystemsManager (not the
## retired ShipSystemState). Deterministic: the smoke damages the relevant
## power subcomponents at setup, then drives objectives and asserts the
## derived consequences (independent of the blueprint's seeded damage set).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

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
	var mgr = playable.get_ship_systems_manager()
	if mgr == null:
		_fail("ship_systems_manager null")
		return

	# Deterministic setup: break the power subcomponents the objectives repair.
	mgr.get_system("power").get_subcomponent("power_distribution").health = 0.0
	mgr.get_system("power").get_subcomponent("battery_cells").health = 0.0
	mgr.get_system("power").get_subcomponent("reactor_core").health = 0.0

	var initial: Dictionary = playable.get_ship_systems_summary()
	if bool(initial.get("main_power_restored", true)):
		_fail("initial main_power_restored should be false after breaking power subs")
		return
	if bool(initial.get("extraction_unlocked", true)):
		_fail("initial extraction_unlocked should be false")
		return

	# Objective 1: recover_supplies (narrative flag, no system) -------------------
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete obj1 returned false")
		return
	if not bool(playable.get_ship_systems_summary().get("emergency_supplies_recovered", false)):
		_fail("after obj1 emergency_supplies_recovered=false")
		return

	# Objective 2: restore_systems -> power_distribution + battery_cells repaired -
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete obj2 returned false")
		return
	var s2: Dictionary = playable.get_ship_systems_summary()
	if not bool(s2.get("main_power_restored", false)):
		_fail("after obj2 main_power_restored=false")
		return
	if not bool(s2.get("blocked_routes_cleared", false)):
		_fail("after obj2 blocked_routes_cleared=false")
		return
	if int(s2.get("blocked_affordance_visible_count", -1)) != 0:
		_fail("after obj2 blocked_affordance_visible_count!=0")
		return
	# Breach must have sealed (oxygen model fed the compat summary).
	if not bool(playable.get_oxygen_summary().get("breach_sealed", false)):
		_fail("after obj2 breach_sealed=false")
		return
	# Route gates opened (route-control fed the compat summary).
	if int(playable.get_route_control_summary().get("opened_gate_count", 0)) < 1:
		_fail("after obj2 no route gates opened")
		return
	# Extraction must still be locked (reactor not yet stabilized).
	if bool(s2.get("extraction_unlocked", true)):
		_fail("after obj2 extraction_unlocked should still be false")
		return

	# Objective 3: download_logs (narrative flag) --------------------------------
	if not playable.complete_objective_sequence_for_validation(3):
		_fail("complete obj3 returned false")
		return
	if not bool(playable.get_ship_systems_summary().get("navigation_logs_downloaded", false)):
		_fail("after obj3 navigation_logs_downloaded=false")
		return

	# Objective 4: stabilize_reactor -> reactor_core full, extraction unlocks -----
	if not playable.complete_objective_sequence_for_validation(4):
		_fail("complete obj4 returned false")
		return
	var s4: Dictionary = playable.get_ship_systems_summary()
	if not bool(s4.get("reactor_stabilized", false)):
		_fail("after obj4 reactor_stabilized=false")
		return
	if not bool(s4.get("extraction_unlocked", false)):
		_fail("after obj4 extraction_unlocked=false")
		return
	if int(s4.get("power_percent", 0)) != 100:
		_fail("after obj4 power_percent=%d expected 100" % int(s4.get("power_percent", 0)))
		return
	if int(s4.get("reactor_stability_percent", 0)) != 100:
		_fail("after obj4 reactor_stability_percent=%d expected 100" % int(s4.get("reactor_stability_percent", 0)))
		return
	if not bool(playable.get_slice_completion_summary().get("run_complete", false)):
		_fail("after obj4 run_complete=false")
		return
	# Now the whole power system is operational (all subs functional).
	if not mgr.is_operational("power"):
		_fail("after obj4 is_operational(power)=false")
		return

	# HUD includes the systems section.
	if not playable.tracker.get_hud_text().contains("Systems:"):
		_fail("HUD missing 'Systems:' section")
		return

	finished = true
	print("MAIN PLAYABLE SHIP SYSTEMS PASS power=true breach_sealed=true gates_open=true logs=true reactor=true extraction=true power_pct=100")
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
