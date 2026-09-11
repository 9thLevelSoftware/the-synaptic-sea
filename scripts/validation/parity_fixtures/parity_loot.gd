extends RefCounted

## Loot fixtures: LootDistribution.roll (production path used by
## scripts/tools/loot_container.gd and playable_generated_ship.gd salvage
## grants) and the legacy LootRoller.roll, for every loot table id.

const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")
const LootDistributionScript := preload("res://scripts/systems/loot_distribution.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const SEED_SOURCES: Array = ["a", "salvage|m1|c1", "marker_7|room_3|crate_2", "x", "derelict_42|cargo|0"]

var summary: Dictionary = {}


func _contexts() -> Array:
	return [
		{
			"id": "default",
			"description": "empty context: LootDistribution defaults biome_id=abyssal_synaptic_sea, depth=0, condition=damaged, container_kind=<table.container_kind or table id> (seed string) / generic_crate (weights), loot_quality_modifier=1.0, item_definitions=ItemDefs.load_definitions(), unique_state=null",
			"context": {},
		},
		{
			"id": "dead_fleet_wrecked_depth3",
			"description": "every key LootDistribution.roll reads except item_definitions/unique_state (same shape as the playable_generated_ship.gd salvage grant context)",
			"context": {
				"biome_id": "dead_fleet",
				"loot_quality_modifier": 1.4,
				"depth": 3,
				"condition": "wrecked",
				"container_kind": "salvage_objective",
			},
		},
	]


func run(writer) -> bool:
	var tables: Dictionary = LootRollerScript.load_tables()
	if tables.is_empty():
		writer.errors.append("loot: LootRoller.load_tables() returned no tables")
		return false
	var table_ids: Array = tables.keys()
	table_ids.sort()
	var item_defs: Dictionary = ItemDefsScript.load_definitions()
	var contexts: Array = _contexts()
	var distribution_rolls: Array = []
	var roller_rolls: Array = []
	for table_variant in table_ids:
		var table_id: String = str(table_variant)
		var table: Dictionary = tables[table_id] if tables[table_id] is Dictionary else {}
		for seed_variant in SEED_SOURCES:
			var seed_source: String = str(seed_variant)
			var roller_result: Array = LootRollerScript.roll(table_id, seed_source, tables)
			roller_rolls.append({
				"table_id": table_id,
				"seed_source": seed_source,
				"rng_seed": LootRollerScript._stable_seed(seed_source),
				"result": roller_result,
			})
			for context_variant in contexts:
				var context_spec: Dictionary = context_variant
				var context: Dictionary = (context_spec["context"] as Dictionary).duplicate(true)
				var seed_string: String = "%s|%s|%s|%s|%s" % [
					table_id,
					seed_source,
					str(context.get("biome_id", "abyssal_synaptic_sea")),
					str(context.get("depth", 0)),
					str(context.get("container_kind", str(table.get("container_kind", table_id)))),
				]
				var result: Array = LootDistributionScript.roll(table_id, seed_source, tables, context)
				distribution_rolls.append({
					"table_id": table_id,
					"seed_source": seed_source,
					"context_id": context_spec["id"],
					"rng_seed_string": seed_string,
					"rng_seed": LootRollerScript._stable_seed(seed_string),
					"result": result,
				})
	var fixture: Dictionary = {
		"schema": "parity.loot.rolls.v1",
		"sources": {
			"tables": LootRollerScript.LOOT_TABLES_PATH,
			"tables_copy": "loot/inputs/loot_tables.json",
			"item_definitions": "ItemDefs.load_definitions() (merged; dumped to loot/inputs/item_definitions_resolved.json)",
			"distribution": "res://scripts/systems/loot_distribution.gd LootDistribution.roll(table_key, seed_source, tables, context)",
			"roller": "res://scripts/systems/loot_roller.gd LootRoller.roll(table_key, seed_source, tables)",
		},
		"notes": [
			"LootDistribution seeds RandomNumberGenerator with abs(\"<table>|<seed_source>|<biome_id>|<depth>|<container_kind>\".hash()); LootRoller seeds with abs(seed_source.hash()).",
			"unique_state is null in every roll (no world-unique claim filtering).",
			"Results are post-merge (by unique_id or item_id) and sorted by that key.",
		],
		"seed_sources": SEED_SOURCES,
		"contexts": contexts,
		"table_ids": table_ids,
		"loot_distribution_rolls": distribution_rolls,
		"loot_roller_rolls": roller_rolls,
	}
	summary = {"tables": table_ids.size(), "distribution_rolls": distribution_rolls.size(), "roller_rolls": roller_rolls.size()}
	var ok: bool = writer.write_json("loot/loot_rolls_fixture.json", fixture)
	ok = writer.copy_file_abs(ProjectSettings.globalize_path(LootRollerScript.LOOT_TABLES_PATH), "loot/inputs/loot_tables.json") and ok
	ok = writer.write_json("loot/inputs/item_definitions_resolved.json", item_defs) and ok
	return ok
