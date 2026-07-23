extends SceneTree

## Strip verbs pulse detection noise while progress ticks (not only on complete).
## Marker: WORK PROGRESS NOISE PASS cut=true pulse=true detection=true

const WorkActionDriverScript := preload("res://scripts/systems/work_action_driver.gd")


func _initialize() -> void:
	var driver = WorkActionDriverScript.new()
	driver.configure({})
	if not driver.start_action("cut_wall", "eng/wall_n", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {"welding_lance": 1},
	}):
		_fail("start"); return
	# Tick less than full duration so we stay ACTIVE but past progress-noise interval.
	driver.tick(0.5, {})
	if driver.last_progress_noise > 0.0:
		_fail("too early for pulse at 0.5s"); return
	driver.tick(0.6, {})
	if driver.last_progress_noise <= 0.0:
		_fail("expected progress noise after 1.1s active cut"); return
	if driver.last_noise_pulse < driver.last_progress_noise - 0.001:
		_fail("last_noise_pulse should track progress noise"); return
	# Detection apply
	var fake_mgr = {"player_noise": 0.05, "player_light": 0.3, "player_sight": 0.4, "player_crouching": false, "player_room_id": "eng"}
	var applied: float = driver.apply_noise_to_detection(fake_mgr)
	if applied <= 0.0:
		_fail("apply noise"); return
	if float(fake_mgr["player_noise"]) < driver.last_progress_noise - 0.001:
		_fail("detection not boosted"); return
	# Quiet verbs (weld) should not spam progress noise
	var driver2 = WorkActionDriverScript.new()
	driver2.configure({})
	if driver2.catalog.has_action("weld_patch"):
		driver2.start_action("weld_patch", "eng/wall_n", {
			"tool_class": "welding_lance",
			"skill_id": "repair",
			"skill_level": 0,
			"inventory": {"welding_lance": 1, "hull_plate": 1},
		})
		driver2.tick(1.2, {})
		if driver2.last_progress_noise > 0.0:
			_fail("weld should not emit progress strip noise"); return
	print("WORK PROGRESS NOISE PASS cut=true pulse=true detection=true")
	quit(0)


func _fail(msg: String) -> void:
	print("WORK PROGRESS NOISE FAIL: %s" % msg)
	quit(1)
