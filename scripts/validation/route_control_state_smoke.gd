extends SceneTree

func _initialize() -> void:
	var model := RouteControlState.new()
	model.configure_from_blocked_routes(["gate_alpha", "gate_beta"])

	var initial: Dictionary = model.get_summary()
	if int(initial.get("route_gate_count", -1)) != 2:
		_fail("initial route_gate_count should be 2")
		return
	if int(initial.get("active_blocker_count", -1)) != 2:
		_fail("initial active_blocker_count should be 2")
		return
	if int(initial.get("opened_gate_count", -1)) != 0:
		_fail("initial opened_gate_count should be 0")
		return
	if bool(initial.get("powered_gates_open", true)):
		_fail("initial powered_gates_open should be false")
		return
	if bool(initial.get("extraction_unlocked", true)):
		_fail("initial extraction_unlocked should be false")
		return
	if model.is_gate_open("gate_alpha"):
		_fail("gate_alpha should start closed")
		return

	var power_only_changed: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": false,
		"extraction_unlocked": false,
	})
	if power_only_changed:
		_fail("power-only summary should not open gates")
		return
	if model.is_gate_open("gate_alpha"):
		_fail("gate_alpha opened before blocked_routes_cleared")
		return

	var open_changed: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": true,
		"extraction_unlocked": false,
	})
	if not open_changed:
		_fail("open summary should report changed")
		return
	var opened: Dictionary = model.get_summary()
	if int(opened.get("active_blocker_count", -1)) != 0:
		_fail("active_blocker_count should be 0 after open")
		return
	if int(opened.get("opened_gate_count", -1)) != 2:
		_fail("opened_gate_count should be 2 after open")
		return
	if not bool(opened.get("powered_gates_open", false)):
		_fail("powered_gates_open should be true after open")
		return
	if not model.is_gate_open("gate_alpha") or not model.is_gate_open("gate_beta"):
		_fail("both gates should be open after open summary")
		return

	var duplicate_open_changed: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": true,
		"extraction_unlocked": false,
	})
	if duplicate_open_changed:
		_fail("duplicate open summary should report unchanged")
		return

	var extraction_changed: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": true,
		"extraction_unlocked": true,
	})
	if not extraction_changed:
		_fail("extraction unlock should report changed")
		return
	if not model.is_extraction_unlocked():
		_fail("extraction should be unlocked")
		return
	var final_summary: Dictionary = model.get_summary()
	if not bool(final_summary.get("extraction_unlocked", false)):
		_fail("summary extraction_unlocked should be true")
		return

	var status_lines: PackedStringArray = model.get_status_lines()
	if not status_lines.has("Routes: POWERED OPEN"):
		_fail("status lines missing Routes: POWERED OPEN")
		return
	if not status_lines.has("Extraction: UNLOCKED"):
		_fail("status lines missing Extraction: UNLOCKED")
		return

	print("ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("ROUTE CONTROL STATE FAIL reason=%s" % reason)
	quit(1)