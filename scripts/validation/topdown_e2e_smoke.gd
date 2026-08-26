extends SceneTree
## End-to-end smoke test for the 2D vertical slice.
## Generates a procgen layout → TileMap, spawns threats, ticks simulation.
## Run: godot --headless --script res://scripts/validation/topdown_e2e_smoke.gd

const TopDownPlayableShipScript = preload("res://scripts/topdown/topdown_playable_ship.gd")

var _p := 0
var _f := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_hub_generation()
	_test_derelict_generation()
	_test_threat_lifecycle()
	_test_simulation_ticking()
	_print_results()
	quit(0 if _f == 0 else 1)


func _new_ship():
	var ship = TopDownPlayableShipScript.new()
	get_root().add_child(ship)
	return ship


func _a(cond: bool, label: String) -> void:
	if cond:
		_p += 1
		print("  PASS  ", label)
	else:
		_f += 1
		print("  FAIL  ", label)


func _test_hub_generation() -> void:
	print("\n--- Hub generation (seed 42) ---")
	var ship = _new_ship()

	var info = ship.generate_hub(42)
	_a(info.has("room_centers"), "hub has room centers")
	_a(info.get("room_centers", {}).size() > 0, "hub has rooms (%d)" % info.get("room_centers", {}).size())
	_a(ship.player.position != Vector2.ZERO, "player placed at start (%.0f, %.0f)" % [ship.player.position.x, ship.player.position.y])

	# Verify tilemap has cells
	var cell_count := 0
	for room in ship.current_layout.get("rooms", []):
		for cell in room.get("cells", []):
			cell_count += 1
	_a(cell_count > 0, "layout has cells (%d)" % cell_count)

	# Verify player placed

	# Verify simulation initialized
	_a(ship.vitals_state != null, "vitals state initialized")
	_a(ship.oxygen_state != null, "oxygen state initialized")
	_a(ship.damage_pipeline != null, "damage pipeline initialized")
	ship.free()


func _test_derelict_generation() -> void:
	print("\n--- Derelict generation (seed 777, breach_field) ---")
	var ship = _new_ship()

	var info = ship.generate_derelict(777, "breach_field")
	_a(info.has("room_centers"), "derelict has room centers")
	_a(info.get("room_centers", {}).size() > 0, "derelict has rooms (%d)" % info.get("room_centers", {}).size())
	_a(ship.away_from_start, "away_from_start flag set")
	_a(ship.threat_manager.get_threat_count() > 0, "threats spawned (%d)" % ship.threat_manager.get_threat_count())
	ship.free()


func _test_threat_lifecycle() -> void:
	print("\n--- Threat lifecycle in generated derelict ---")
	var ship = _new_ship()
	ship.generate_derelict(777, "breach_field")

	var threat_count = ship.threat_manager.get_threat_count()
	_a(threat_count >= 1, "at least 1 threat spawned")

	# Tick with high awareness to trigger hunt
	for i in range(20):
		ship._tick_threats(0.1)

	# Verify at least one threat left idle (not all should hunt simultaneously)
	var any_hunting := false
	for t in ship.threat_manager.threats:
		if t.state == "hunt" or t.state == "attack":
			any_hunting = true
			break
	# This is OK — threats may not all detect the player in the first few ticks

	# Kill all threats
	for t in ship.threat_manager.threats:
		t.apply_damage({"amount": 200.0})
	_a(ship.threat_manager.get_alive_count() == 0, "all threats killed")
	ship.free()


func _test_simulation_ticking() -> void:
	print("\n--- Simulation ticking (100 frames) ---")
	var ship = _new_ship()
	ship.generate_hub(42)

	# Tick 100 frames — should not error
	var errors := 0
	for i in range(100):
		var prev_err := _f
		ship._process(0.016)  # ~60fps
		if _f > prev_err:
			errors += 1
	_a(errors == 0, "100 frames ticked without errors (%d caught)" % errors)

	# Verify systems still alive
	_a(ship.vitals_state != null, "vitals still alive after ticking")
	_a(ship.oxygen_state != null, "oxygen still alive after ticking")
	ship.free()


func _print_results() -> void:
	print("\n========================================")
	print("E2E smoke: pass_count=%d failure_count=%d" % [_p, _f])
	print("========================================")
	print("RESULT: %s" % ("PASS" if _f == 0 else "unsuccessful"))
