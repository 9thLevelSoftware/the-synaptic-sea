extends SceneTree

const AutomatedPlaytestRubricScript := preload("res://scripts/systems/automated_playtest_rubric.gd")
const BalanceLedgerScript := preload("res://scripts/systems/balance_ledger.gd")

func _initialize() -> void:
	var rubric_data: Dictionary = _load_json("res://data/integration/automated_playtest_rubric.json")
	var balance_data: Dictionary = _load_json("res://data/integration/balance_ledger.json")
	if rubric_data.is_empty() or balance_data.is_empty():
		_fail("rubric or balance ledger data missing")
		return

	var rubric = AutomatedPlaytestRubricScript.new()
	if not rubric.configure(rubric_data):
		_fail("rubric configure failed")
		return
	var scenario: Dictionary = {
		"scenario_id": "prepare_derelict_survive_loot_craft_return_upgrade",
		"stages": ["prepare", "derelict", "survive", "loot", "craft", "return", "upgrade"],
		"steps": [
			{"stage": "prepare", "systems": ["inventory", "player_progression", "ship_systems"], "visible_consequence": true, "resource_delta": {"supplies": -2}},
			{"stage": "derelict", "systems": ["procgen", "travel", "docking"], "visible_consequence": true, "resource_delta": {"distance": 1}},
			{"stage": "survive", "systems": ["vitals", "food", "ship_systems"], "visible_consequence": true, "resource_delta": {"oxygen": -18, "hunger": -9, "thirst": -12}},
			{"stage": "loot", "systems": ["loot", "inventory", "audio"], "visible_consequence": true, "resource_delta": {"scrap_metal": 5, "circuit_board": 1}},
			{"stage": "craft", "systems": ["crafting", "materials", "power"], "visible_consequence": true, "resource_delta": {"power_cell": 1, "scrap_metal": -1}},
			{"stage": "return", "systems": ["travel", "world_persistence", "save_load"], "visible_consequence": true, "resource_delta": {"home_state_restored": 1}},
			{"stage": "upgrade", "systems": ["meta_progression", "hub_upgrades", "player_progression"], "visible_consequence": true, "resource_delta": {"meta_currency": -50, "storage_slots": 25}}
		],
		"stuck_events": 0,
		"hud_updates": 7,
		"player_choice_count": 5
	}
	var scenario_result: Dictionary = rubric.evaluate_scenario(scenario)
	if not bool(scenario_result.get("pass", false)):
		_fail("scenario rubric failed: %s" % JSON.stringify(scenario_result))
		return

	var ledger = BalanceLedgerScript.new()
	if not ledger.configure(balance_data):
		_fail("balance ledger configure failed")
		return
	var balance_result: Dictionary = ledger.evaluate_scenario("prepare_derelict_survive_loot_craft_return_upgrade", {
		"oxygen_remaining_pct": 42.0,
		"hunger_remaining_pct": 61.0,
		"thirst_remaining_pct": 55.0,
		"loot_value": 7.0,
		"crafts_completed": 1.0,
		"meta_currency_delta": 64.0,
		"upgrade_cost": 50.0
	})
	if not bool(balance_result.get("pass", false)):
		_fail("balance sanity failed: %s" % JSON.stringify(balance_result))
		return

	print("E2E SURVIVAL LOOP PASS stages=%d rubric_score=%.2f balance=true" % [
		int(scenario_result.get("covered_stage_count", 0)),
		float(scenario_result.get("score", 0.0)),
	])
	quit(0)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary

func _fail(reason: String) -> void:
	push_error("E2E SURVIVAL LOOP FAIL reason=%s" % reason)
	quit(1)
