extends SceneTree

## Pure smoke: loot rolls are deterministic per (table_key, seed_source) and vary by seed.

const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")

func _initialize() -> void:
	var tables: Dictionary = LootRollerScript.load_tables()
	var det: bool = _test_deterministic(tables)
	var varies: bool = _test_varies(tables)
	if det and varies:
		print("LOOT TABLE PASS deterministic=true varies_by_seed=true")
	else:
		push_error("LOOT TABLE FAIL deterministic=%s varies_by_seed=%s" % [str(det), str(varies)])
	quit(0 if (det and varies) else 1)

func _test_deterministic(tables: Dictionary) -> bool:
	var a: Array = LootRollerScript.roll("generic_crate", "marker7:crate_3", tables)
	var b: Array = LootRollerScript.roll("generic_crate", "marker7:crate_3", tables)
	if a.is_empty():
		return false
	return JSON.stringify(a) == JSON.stringify(b)

func _test_varies(tables: Dictionary) -> bool:
	var a: Array = LootRollerScript.roll("generic_crate", "marker7:crate_3", tables)
	var b: Array = LootRollerScript.roll("generic_crate", "marker9:crate_8", tables)
	# Different seed sources should (with this table) produce a different result.
	return JSON.stringify(a) != JSON.stringify(b)
