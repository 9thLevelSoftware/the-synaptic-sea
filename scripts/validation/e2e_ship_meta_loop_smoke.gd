extends SceneTree

const PowerGridStateScript := preload("res://scripts/systems/power_grid_state.gd")
const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const HubUpgradeStateScript := preload("res://scripts/systems/hub_upgrade_state.gd")
const AutomatedPlaytestRubricScript := preload("res://scripts/systems/automated_playtest_rubric.gd")

func _initialize() -> void:
	var grid = PowerGridStateScript.new()
	grid.configure({
		"total_supply_units": 100.0,
		"min_operational_ratio": 0.5,
		"subsystem_order": ["life_support", "propulsion", "stations", "sustenance"],
		"baseline_demand_units": {"life_support": 22.0, "propulsion": 30.0, "stations": 12.0, "sustenance": 10.0}
	})
	grid.set_manual_route("propulsion", 0.0)
	grid.rebalance(1.0)
	if grid.is_system_powered("propulsion"):
		_fail("propulsion should be offline before repair")
		return
	grid.set_manual_route("propulsion", 30.0)
	grid.rebalance(1.0)
	if not grid.is_system_powered("propulsion"):
		_fail("propulsion should recover after repair/power allocation")
		return

	var meta = MetaProgressionStateScript.new()
	meta.configure({})
	var payout: int = meta.apply_meta_payout({
		"completed_objectives": 4,
		"skill_levels": {"repair": 5, "navigation": 4},
		"discoveries": 5,
		"reason": "extraction"
	})
	if payout < 50:
		_fail("meta payout too low for first upgrade: %d" % payout)
		return
	var hub = HubUpgradeStateScript.new()
	if not hub.configure({}):
		_fail("hub upgrade catalog failed to load")
		return
	if not hub.purchase("hub_storage_basic", meta):
		_fail("hub_storage_basic purchase failed after return payout")
		return
	if not meta.is_hub_upgrade_unlocked("hub_storage_basic"):
		_fail("hub_storage_basic not unlocked")
		return

	var rubric = AutomatedPlaytestRubricScript.new()
	rubric.configure({"required_stages": ["repair", "return", "upgrade"], "min_visible_consequences": 3, "min_player_choices": 2})
	var rubric_result: Dictionary = rubric.evaluate_scenario({
		"scenario_id": "ship_meta_loop",
		"stages": ["repair", "return", "upgrade"],
		"steps": [
			{"stage": "repair", "systems": ["ship_systems", "power_grid"], "visible_consequence": true},
			{"stage": "return", "systems": ["travel", "meta_progression"], "visible_consequence": true},
			{"stage": "upgrade", "systems": ["hub_upgrades", "meta_progression"], "visible_consequence": true}
		],
		"stuck_events": 0,
		"hud_updates": 3,
		"player_choice_count": 2
	})
	if not bool(rubric_result.get("pass", false)):
		_fail("rubric failed: %s" % JSON.stringify(rubric_result))
		return
	print("E2E SHIP META LOOP PASS propulsion=true payout=%d upgrade=hub_storage_basic" % payout)
	quit(0)

func _fail(reason: String) -> void:
	push_error("E2E SHIP META LOOP FAIL reason=%s" % reason)
	quit(1)
