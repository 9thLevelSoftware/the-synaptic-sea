extends SceneTree

const StationStateScript := preload("res://scripts/systems/station_state.gd")

func _fail(msg: String) -> void:
	print("FAIL: %s" % msg)
	quit()

func _initialize() -> void:
	var station = StationStateScript.new()
	station.configure({"station_kind": "fabricator", "level": 2, "powered": true})
	if station.station_kind != "fabricator": _fail("kind mismatch")
	if station.level != 2: _fail("level mismatch")
	if station.powered != true: _fail("powered mismatch")

	# Start recipe
	if not station.start_recipe("craft_power_cell", 30.0): _fail("start_recipe failed")
	if station.status != 1: _fail("should be crafting (status=1)")
	if not station.is_crafting(): _fail("is_crafting should be true")

	# Tick partial
	if station.tick(10.0): _fail("should not complete at 10s")
	if absf(station.get_progress_ratio() - (10.0 / 30.0)) >= 0.001: _fail("progress ratio wrong")

	# Tick to completion
	if not station.tick(20.0): _fail("should complete at 30s")
	if station.status != 3: _fail("should be complete (status=3)")

	# Finish and advance
	var next: String = station.finish_and_advance()
	if next != "": _fail("no queued recipe")
	if station.status != 0: _fail("should be idle after finish (status=0)")

	# Queue behavior
	station.enqueue("craft_sensor_module")
	station.enqueue("craft_data_core")
	station.start_recipe("craft_power_cell", 30.0)
	station.tick(30.0)
	if station.status != 3: _fail("queued start should complete")
	next = station.finish_and_advance()
	if next != "craft_sensor_module": _fail("should advance to queued recipe")
	if station.active_recipe_id != "craft_sensor_module": _fail("active should be next recipe")

	# Power pause
	station.set_power(false)
	if station.status != 2: _fail("should pause when power lost (status=2)")
	station.set_power(true)
	if station.status != 1: _fail("should resume when power restored (status=1)")

	# Round-trip
	var summary: Dictionary = station.get_summary()
	var station2 = StationStateScript.new()
	if not station2.apply_summary(summary): _fail("apply_summary should return true")
	if station2.station_kind != "fabricator": _fail("round-trip kind failed")
	if station2.level != 2: _fail("round-trip level failed")
	if station2.active_recipe_id != "craft_sensor_module": _fail("round-trip active_recipe failed")

	print("STATION STATE PASS configure=true tick=true pause_resume=true queue=true round_trip=true")
	quit()
