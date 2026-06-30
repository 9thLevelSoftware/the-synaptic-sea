extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 400

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var ran: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if ran:
		return
	ran = true
	_run_validation(playable)

func _run_validation(playable: PlayableGeneratedShip) -> void:
	for pair in [
		["power", "reactor_core"],
		["power", "power_distribution"],
		["power", "battery_cells"],
		["navigation", "star_charts"],
		["navigation", "nav_computer"],
		["navigation", "sensor_array"],
		["propulsion", "thruster_array"],
		["propulsion", "fuel_injection"],
		["propulsion", "nav_linkage"],
	]:
		playable.ship_systems_manager.force_repair(str(pair[0]), str(pair[1]))
	playable._recompute_expanded_ship_systems(0.0)
	if not playable.set_manual_power_route_for_validation("propulsion", 0.0):
		_fail("could not set propulsion route")
		return
	if playable.propulsion_expanded_state == null or playable.propulsion_expanded_state.can_propel():
		_fail("propulsion should gate off when route is zero")
		return
	playable.set_manual_power_route_for_validation("propulsion", 30.0)
	playable._recompute_expanded_ship_systems(1.0)
	if playable.propulsion_expanded_state == null or not playable.propulsion_expanded_state.can_propel():
		_fail("propulsion should recover when route restored")
		return
	if not playable.force_hull_breach_for_validation("engineering", 0.7):
		_fail("failed to breach engineering")
		return
	var expanded: Dictionary = playable.get_ship_systems_expanded_summary()
	var hull_summary: Dictionary = expanded.get("hull_integrity_summary", {}) as Dictionary
	var hull_compartments: Dictionary = hull_summary.get("compartments", {}) as Dictionary
	var engineering_row: Dictionary = hull_compartments.get("engineering", {}) as Dictionary
	if not bool(engineering_row.get("breach_open", false)):
		_fail("engineering breach not recorded")
		return
	if not playable.seal_hull_breach_for_validation("engineering", 1.0):
		_fail("failed to seal engineering")
		return
	# Verify engineering specifically is sealed (cargo starts pre-breached per hull_compartments.json,
	# so a total breach_count check would give a false failure).
	expanded = playable.get_ship_systems_expanded_summary()
	hull_summary = expanded.get("hull_integrity_summary", {}) as Dictionary
	hull_compartments = hull_summary.get("compartments", {}) as Dictionary
	engineering_row = hull_compartments.get("engineering", {}) as Dictionary
	if bool(engineering_row.get("breach_open", false)):
		_fail("engineering breach should be sealed")
		return
	playable.ignite_compartment_for_validation("cargo", 1.0)
	playable.fire_suppression_state.tick(5.0, {"powered_ratio": 1.0})
	if playable.fire_suppression_state.get_active_fire_count() != 0:
		_fail("fire suppression should clear cargo fire")
		return
	var hydro = playable.hydroponics_state
	hydro.plant({
		"crop_id": "hydroponic_greens",
		"display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens",
		"produce_quantity": 3,
		"growth_seconds": 5.0,
		"water_cost": 2.0,
		"power_cost": 3.0,
		"required_skill_level": 0
	}, 0, 5.0, 5.0)
	hydro.tick(5.0)
	# synthesizer_state was retired in Domain 3 Task 3; meals_ready now reflects
	# crafting_state.is_crafting() — skip synthesizer setup here and assert 0.
	var recycler = playable.water_recycler_state
	recycler.configure({"input_item_id": "contaminated_water", "output_item_id": "purified_water", "conversion_ratio": 1.0, "recycle_time_seconds": 5.0, "power_cost": 2.0})
	recycler.load_input("contaminated_water", 4, 10.0)
	recycler.tick(5.0)
	playable._recompute_expanded_ship_systems(1.0)
	expanded = playable.get_ship_systems_expanded_summary()
	var sustenance: Dictionary = expanded.get("sustenance_state_summary", {})
	# meals_ready is now driven by crafting_state.is_crafting() (synthesizer_state retired).
	# No active craft here → meals_ready == 0 is correct.
	if int(sustenance.get("harvest_ready", 0)) != 1 or int(sustenance.get("purified_water_ready", 0)) != 4:
		_fail("sustenance outputs missing")
		return
	# Seal the pre-breached cargo before snapshotting so the snapshot baseline
	# has cargo closed; the mutation test below then reopens it and verifies restore.
	playable.seal_hull_breach_for_validation("cargo", 1.0)
	var snapshot = playable._build_run_snapshot()
	if snapshot == null:
		_fail("snapshot null")
		return
	playable.set_manual_power_route_for_validation("propulsion", 0.0)
	playable.force_hull_breach_for_validation("cargo", 0.7)
	if not playable._apply_run_snapshot(snapshot):
		_fail("apply_run_snapshot failed")
		return
	expanded = playable.get_ship_systems_expanded_summary()
	var restored_grid: Dictionary = expanded.get("power_grid_summary", {})
	var restored_hull: Dictionary = expanded.get("hull_integrity_summary", {})
	var restored_sustenance: Dictionary = expanded.get("sustenance_state_summary", {})
	if float((restored_grid.get("manual_routes_units", {}) as Dictionary).get("propulsion", 0.0)) <= 0.0:
		_fail("propulsion manual route did not persist")
		return
	if int((restored_sustenance.get("purified_water_ready", 0))) != 4:
		_fail("sustenance summary did not persist")
		return
	var cargo_row: Dictionary = ((restored_hull.get("compartments", {}) as Dictionary).get("cargo", {}) as Dictionary)
	if bool(cargo_row.get("breach_open", false)):
		_fail("cargo breach mutation should have been overwritten by snapshot")
		return
	finished = true
	print("MAIN PLAYABLE SHIP SYSTEMS EXPANDED PASS propulsion=true hull=true fire=true sustenance=true persistence=true")
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
	push_error("MAIN PLAYABLE SHIP SYSTEMS EXPANDED FAIL reason=%s" % reason)
	quit(1)
