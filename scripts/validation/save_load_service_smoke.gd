extends SceneTree

const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const ShipSystemStateScript := preload("res://scripts/systems/ship_system_state.gd")
const RouteControlStateScript := preload("res://scripts/systems/route_control_state.gd")
const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const FireStateScript := preload("res://scripts/systems/fire_state.gd")
const ElectricalArcStateScript := preload("res://scripts/systems/electrical_arc_state.gd")
const ObjectiveProgressStateScript := preload("res://scripts/systems/objective_progress_state.gd")

func _initialize() -> void:
	# Direct service smoke (REQ-012).
	# Builds a RunSnapshot from a freshly configured set of Gate 2 models,
	# writes it via SaveLoadService, reads it back, and asserts all
	# summary fields round-trip cleanly with the canonical 6 summary
	# entries. The marker line below is the spec contract.

	var service := SaveLoadServiceScript.new()
	service.delete_current_run()

	# Build real model instances and seed them with a known state.
	var ship := ShipSystemStateScript.new()
	ship.apply_objective(1, "recover_supplies", "obj1", "cargo_01")

	var route := RouteControlStateScript.new()
	route.configure_from_blocked_routes(["powered_route_gate_01"])

	var oxygen := OxygenStateScript.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary.
	oxygen.configure({
		"zone_ids": ["corridor_to_reactor"],
		"max_oxygen": OxygenStateScript.DEFAULT_MAX_OXYGEN,
		"drain_rate": OxygenStateScript.DEFAULT_DRAIN_RATE,
		"regen_rate": OxygenStateScript.DEFAULT_REGEN_RATE,
		"recovery_threshold": OxygenStateScript.DEFAULT_RECOVERY_THRESHOLD,
		"safe_threshold": OxygenStateScript.DEFAULT_SAFE_THRESHOLD,
	})
	# Force a non-default oxygen value so the round-trip proves we captured
	# the runtime number (not just the default).
	oxygen.tick(2.0, true)

	var inventory := InventoryStateScript.new()
	inventory.add_tool("portable_oxygen_pump")

	var fire := FireStateScript.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary.
	fire.configure({
		"zone_ids": ["side_corridor_fire"],
		"burn_duration": FireStateScript.DEFAULT_BURN_DURATION,
		"clear_duration": FireStateScript.DEFAULT_CLEAR_DURATION,
	})

	# REQ-013: include the electrical-arc summary in the round-trip so the
	# smoke proves all seven SUMMARY_FIELDS survive a save / load cycle.
	# Force a non-default state by ticking halfway through the arcing
	# phase, so the round-trip proves we captured the runtime number.
	var arc := ElectricalArcStateScript.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary.
	arc.configure({
		"zone_ids": ["side_corridor_arc"],
		"arcing_duration": ElectricalArcStateScript.DEFAULT_ARCING_DURATION,
		"discharged_duration": ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION,
	})
	arc.tick(ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION + 0.6)

	var progress := ObjectiveProgressStateScript.new()
	progress.register_objective(1, "restore_systems", 2)
	progress.complete_step(1, "step_a")

	var original := RunSnapshotScript.new()
	original.layout_path = "res://data/procgen/smoke/seed_000017/layout.json"
	original.kit_path = "res://data/kits/ship_structural_v0.json"
	original.gameplay_slice_path = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
	original.player_position = [1.25, 2.5, 3.75]
	original.current_objective_sequence = 2
	original.ship_systems_summary = ship.get_summary()
	original.route_control_summary = route.get_summary()
	original.oxygen_summary = oxygen.get_summary()
	original.inventory_summary = inventory.get_summary()
	original.fire_summary = fire.get_summary()
	original.electrical_arc_summary = arc.get_summary()
	original.objective_progress_summary = progress.get_summary()
	original.slice_version = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	original.godot_version = Engine.get_version_info()["string"]
	original.saved_at = Time.get_datetime_string_from_system(true)

	if not service.save_current_run(original):
		_fail("save_current_run returned false")
		return
	if not service.has_save():
		_fail("has_save false after save")
		return

	var loaded: RunSnapshot = service.load_current_run()
	if loaded == null:
		_fail("load_current_run returned null")
		return

	if loaded.layout_path != original.layout_path:
		_fail("layout_path mismatch")
		return
	if loaded.kit_path != original.kit_path:
		_fail("kit_path mismatch")
		return
	if loaded.gameplay_slice_path != original.gameplay_slice_path:
		_fail("gameplay_slice_path mismatch")
		return
	if loaded.player_position != original.player_position:
		_fail("player_position mismatch")
		return
	if loaded.current_objective_sequence != original.current_objective_sequence:
		_fail("current_objective_sequence mismatch")
		return
	if loaded.get_summary_count() != 7:
		_fail("summary_count=%d expected 7" % loaded.get_summary_count())
		return
	if loaded.slice_version != original.slice_version:
		_fail("slice_version mismatch")
		return
	if loaded.godot_version != original.godot_version:
		_fail("godot_version mismatch")
		return
	if not _dicts_equal(loaded.ship_systems_summary, original.ship_systems_summary):
		_fail("ship_systems_summary mismatch: got=%s expected=%s" % [JSON.stringify(loaded.ship_systems_summary), JSON.stringify(original.ship_systems_summary)])
		return
	if not _dicts_equal(loaded.route_control_summary, original.route_control_summary):
		_fail("route_control_summary mismatch")
		return
	if not _dicts_equal(loaded.oxygen_summary, original.oxygen_summary):
		_fail("oxygen_summary mismatch")
		return
	if not _dicts_equal(loaded.inventory_summary, original.inventory_summary):
		_fail("inventory_summary mismatch")
		return
	if not _dicts_equal(loaded.fire_summary, original.fire_summary):
		_fail("fire_summary mismatch")
		return
	if not _dicts_equal(loaded.electrical_arc_summary, original.electrical_arc_summary):
		_fail("electrical_arc_summary mismatch")
		return
	if not _dicts_equal(loaded.objective_progress_summary, original.objective_progress_summary):
		_fail("objective_progress_summary mismatch")
		return

	# Version mismatch rejection: write a snapshot with the wrong slice_version
	# and confirm load returns null instead of accepting it.
	var bad := RunSnapshotScript.new()
	bad.slice_version = "incompatible-version"
	bad.godot_version = Engine.get_version_info()["string"]
	bad.layout_path = original.layout_path
	bad.current_objective_sequence = 1
	bad.ship_systems_summary = ship.get_summary()
	bad.route_control_summary = route.get_summary()
	bad.oxygen_summary = oxygen.get_summary()
	bad.inventory_summary = inventory.get_summary()
	bad.fire_summary = fire.get_summary()
	bad.electrical_arc_summary = arc.get_summary()
	bad.objective_progress_summary = progress.get_summary()
	# save_current_run should accept the snapshot (it is well-formed JSON);
	# load_current_run must reject it because of the slice_version mismatch.
	if not service.save_current_run(bad):
		_fail("saving incompatible-version snapshot failed unexpectedly")
		return
	var rejected: RunSnapshot = service.load_current_run()
	if rejected != null:
		_fail("incompatible slice_version was accepted: %s" % str(rejected.slice_version))
		return

	# Cleanup
	service.delete_current_run()
	if service.has_save():
		_fail("delete_current_run did not remove the file")
		return

	print("SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=7")
	quit(0)

func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	# Type-tolerant compare: Godot's JSON parser decodes every JSON number
	# as float, so an int 1 in the original becomes 1.0 on round-trip. The
	# values match semantically; cast both sides through float() before
	# comparing.
	return JSON.stringify(_normalize(a)) == JSON.stringify(_normalize(b))

func _normalize(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var out: Dictionary = {}
		for k in (value as Dictionary).keys():
			out[k] = _normalize((value as Dictionary)[k])
		return out
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = []
		for item in (value as Array):
			arr.append(_normalize(item))
		return arr
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return value

func _fail(reason: String) -> void:
	push_error("SAVE LOAD SERVICE FAIL reason=%s" % reason)
	quit(1)
