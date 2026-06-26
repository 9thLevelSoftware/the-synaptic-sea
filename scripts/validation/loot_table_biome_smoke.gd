extends SceneTree

func _initialize() -> void:
	var dist_script := load("res://scripts/systems/loot_distribution.gd")
	var item_defs_script := load("res://scripts/systems/item_defs.gd")
	var roller_script := load("res://scripts/systems/loot_roller.gd")
	if dist_script == null or item_defs_script == null or roller_script == null:
		_fail("required loot scripts failed to load")
		return
	var tables: Dictionary = roller_script.load_tables()
	var item_defs: Dictionary = item_defs_script.load_definitions()
	var base_seed: String = "biome-smoke-seed"
	var a: Array = dist_script.roll("salvage_cargo", base_seed, tables, {
		"biome_id": "abyssal_synapse_sea",
		"depth": 0,
		"condition": "damaged",
		"container_kind": "industrial_crate",
		"item_definitions": item_defs,
	})
	var b: Array = dist_script.roll("salvage_cargo", base_seed, tables, {
		"biome_id": "dead_fleet",
		"depth": 6,
		"condition": "wrecked",
		"container_kind": "hidden_cache",
		"item_definitions": item_defs,
	})
	if a.is_empty() or b.is_empty():
		_fail("expected both comparison rolls to produce loot")
		return
	if JSON.stringify(a) == JSON.stringify(b):
		_fail("biome/depth/container modifiers should change the rolled result")
		return
	print("LOOT TABLE BIOME PASS variants=2 changed=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("LOOT TABLE BIOME FAIL reason=%s" % reason)
	quit(1)
