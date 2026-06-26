extends SceneTree

func _initialize() -> void:
	var dist_script := load("res://scripts/systems/loot_distribution.gd")
	var unique_script := load("res://scripts/systems/unique_item_state.gd")
	var junk_script := load("res://scripts/systems/junk_yield_resolver.gd")
	var item_defs_script := load("res://scripts/systems/item_defs.gd")
	var roller_script := load("res://scripts/systems/loot_roller.gd")
	if dist_script == null or unique_script == null or junk_script == null or item_defs_script == null or roller_script == null:
		_fail("required loot scripts failed to load")
		return
	var tables: Dictionary = roller_script.load_tables()
	var item_defs: Dictionary = item_defs_script.load_definitions()
	var context := {
		"biome_id": "dead_fleet",
		"depth": 4,
		"condition": "wrecked",
		"container_kind": "maintenance_cache",
		"item_definitions": item_defs,
	}
	var deterministic_a: Array = dist_script.roll("salvage_engineering", "deterministic-seed", tables, context)
	var deterministic_b: Array = dist_script.roll("salvage_engineering", "deterministic-seed", tables, context)
	if JSON.stringify(deterministic_a) != JSON.stringify(deterministic_b):
		_fail("loot distribution should be deterministic for identical inputs")
		return
	var unique_state = unique_script.new()
	unique_state.configure()
	var found_unique: Dictionary = {}
	for i in range(0, 2000):
		var rolled: Array = dist_script.roll("salvage_engineering", "seed-%d" % i, tables, {
			"biome_id": "dead_fleet",
			"depth": 6,
			"condition": "wrecked",
			"container_kind": "maintenance_cache",
			"item_definitions": item_defs,
			"unique_state": unique_state,
		})
		for entry in rolled:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var unique_id: String = str((entry as Dictionary).get("unique_id", ""))
			if unique_id.is_empty():
				continue
			found_unique = entry as Dictionary
			break
		if not found_unique.is_empty():
			break
	if found_unique.is_empty():
		_fail("could not find a deterministic unique roll within 2000 seeds")
		return
	var unique_id: String = str(found_unique.get("unique_id", ""))
	var seed_key: String = str(found_unique.get("seed_key", ""))
	var codex_entry_id: String = str(found_unique.get("codex_entry_id", ""))
	if not unique_state.claim(unique_id, seed_key, codex_entry_id):
		_fail("claiming rolled unique should succeed")
		return
	var filtered: Array = dist_script.roll("repair_parts_rare", "post-claim", tables, {
		"biome_id": "dead_fleet",
		"depth": 6,
		"condition": "wrecked",
		"container_kind": "maintenance_cache",
		"item_definitions": item_defs,
		"unique_state": unique_state,
	})
	for entry in filtered:
		if str((entry as Dictionary).get("unique_id", "")) == unique_id:
			_fail("claimed unique should be filtered out of later rolls")
			return
	var junk_yields: Array = junk_script.yields_for_item("frayed_cable_coil")
	if junk_yields.size() < 2:
		_fail("expected frayed_cable_coil to expose salvage yields")
		return
	print("LOOT DISTRIBUTION PASS deterministic=true unique_filtered=true junk_yields=%d" % junk_yields.size())
	quit(0)

func _fail(reason: String) -> void:
	push_error("LOOT DISTRIBUTION FAIL reason=%s" % reason)
	quit(1)
