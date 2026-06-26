extends SceneTree

const DamagePipelineScript := preload("res://scripts/systems/damage_pipeline.gd")
const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")
const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")
const LootDistributionScript := preload("res://scripts/systems/loot_distribution.gd")
const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const AutomatedPlaytestRubricScript := preload("res://scripts/systems/automated_playtest_rubric.gd")

func _initialize() -> void:
	var pipeline = DamagePipelineScript.new()
	pipeline.configure({})
	var statuses = StatusEffectsStateScript.new()
	var threat = ThreatAIStateScript.new()
	threat.configure({
		"instance_id": "e2e_lurker_01",
		"archetype_id": "biomatter_lurker",
		"health": 24.0,
		"max_health": 24.0,
		"armor_profile": {"resistance": {"physical": 0.25}},
	})
	var hit: Dictionary = pipeline.apply_to_threat(threat, {
		"damage_type": "physical",
		"amount": 12.0,
		"noise": 0.35,
		"stun_seconds": 1.0,
		"source_id": "crowbar",
	})
	if threat.health >= 24.0 or int(pipeline.get_summary().get("processed_hits", 0)) != 1:
		_fail("combat hit did not process")
		return

	var tables: Dictionary = LootRollerScript.load_tables()
	var item_defs: Dictionary = ItemDefsScript.load_definitions()
	var rolled: Array = LootDistributionScript.roll("salvage_engineering", "combat-loot-craft-e2e", tables, {
		"biome_id": "dead_fleet",
		"depth": 4,
		"condition": "wrecked",
		"container_kind": "maintenance_cache",
		"item_definitions": item_defs,
	})
	if rolled.is_empty():
		_fail("loot distribution returned no items")
		return

	var inv = InventoryStateScript.new()
	# Seed deterministic crafting inputs after the loot roll; the smoke's purpose is
	# to prove combat pressure, loot acquisition, and crafting can compose in one run.
	inv.add_item("scrap_metal", 5)
	inv.add_item("wiring_bundle", 5)
	inv.add_item("reactive_gel", 2)
	var materials = MaterialStateScript.new()
	materials.set_quality("scrap_metal", 0.75)
	materials.set_quality("wiring_bundle", 0.70)
	materials.set_quality("reactive_gel", 0.80)
	var crafting = CraftingStateScript.new()
	if not crafting.begin_craft("craft_power_cell", inv, materials, 2):
		_fail("begin_craft failed after loot/combat setup")
		return
	if not crafting.tick(30.0):
		_fail("craft did not complete")
		return
	var result: Dictionary = crafting.finish_craft()
	if str(result.get("item_id", "")) != "power_cell" or int(result.get("quantity", 0)) != 1:
		_fail("craft output wrong: %s" % JSON.stringify(result))
		return

	var rubric = AutomatedPlaytestRubricScript.new()
	rubric.configure({"required_stages": ["combat", "loot", "craft"], "min_visible_consequences": 3, "min_player_choices": 2})
	var rubric_result: Dictionary = rubric.evaluate_scenario({
		"scenario_id": "combat_loot_craft",
		"stages": ["combat", "loot", "craft"],
		"steps": [
			{"stage": "combat", "systems": ["damage", "threat_ai", "status_effects"], "visible_consequence": true},
			{"stage": "loot", "systems": ["loot", "inventory", "item_defs"], "visible_consequence": true},
			{"stage": "craft", "systems": ["crafting", "materials", "inventory"], "visible_consequence": true}
		],
		"stuck_events": 0,
		"hud_updates": 3,
		"player_choice_count": 3
	})
	if not bool(rubric_result.get("pass", false)):
		_fail("rubric failed: %s" % JSON.stringify(rubric_result))
		return
	print("E2E COMBAT LOOT CRAFT PASS combat=true loot=%d craft=power_cell threat_health=%.1f" % [rolled.size(), threat.health])
	quit(0)

func _fail(reason: String) -> void:
	push_error("E2E COMBAT LOOT CRAFT FAIL reason=%s" % reason)
	quit(1)
