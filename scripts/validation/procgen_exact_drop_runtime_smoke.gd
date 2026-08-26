extends SceneTree

const LootContainerScript := preload("res://scripts/tools/loot_container.gd")

class MockInventory:
	var items: Dictionary = {}

	func add_item(item_id: String, quantity: int) -> int:
		items[item_id] = int(items.get(item_id, 0)) + quantity
		return quantity


func _initialize() -> void:
	var failures: Array[String] = []
	var player := Node3D.new()
	var inventory := MockInventory.new()
	var tables: Dictionary = {
		"fallback": {"entries": [{"item_id": "random_fallback", "qty_min": 1, "qty_max": 1}], "rolls": 1}
	}

	var exact := LootContainerScript.new()
	exact.configure("exact", "fallback", "exact-seed", inventory, tables, Vector3.ZERO, 1.8, {
		"generated_items": [{"item_id": "generated_tool", "quantity": 1, "blueprint_id": "bp-7"}, {"item_id": "generated_part", "quantity": 1}],
	})
	exact.set_validation_player_in_range(player)
	var exact_grants: Array = []
	exact.container_searched.connect(func(_id: String, granted: Array) -> void: exact_grants.append_array(granted))
	_expect(exact.try_interact(player), failures, "exact first interaction")
	_expect(inventory.items.get("generated_tool", 0) == 1 and inventory.items.get("generated_part", 0) == 1, failures, "exact inventory grants")
	_expect(inventory.items.get("random_fallback", 0) == 0, failures, "exact bypasses distribution")
	_expect(exact_grants.size() == 2 and exact_grants[0].get("blueprint_id", "") == "bp-7", failures, "exact metadata preserved")
	_expect(not exact.try_interact(player), failures, "exact single-use")

	var malformed_inventory := MockInventory.new()
	var malformed := LootContainerScript.new()
	malformed.configure("malformed", "fallback", "malformed-seed", malformed_inventory, tables, Vector3.ZERO, 1.8, {
		"generated_items": [{"item_id": "bad", "quantity": 0}],
	})
	malformed.set_validation_player_in_range(player)
	_expect(malformed.try_interact(player), failures, "malformed interaction consumed")
	_expect(malformed_inventory.items.is_empty(), failures, "malformed fails closed")
	_expect(malformed_inventory.items.get("random_fallback", 0) == 0, failures, "malformed no random fallback")

	var oversized_entries: Array = []
	for index in 65:
		oversized_entries.append({"item_id": "item-%d" % index, "quantity": 1})
	var oversized_inventory := MockInventory.new()
	var oversized := LootContainerScript.new()
	oversized.configure("oversized", "fallback", "oversized-seed", oversized_inventory, tables, Vector3.ZERO, 1.8, {"generated_items": oversized_entries})
	oversized.set_validation_player_in_range(player)
	_expect(oversized.try_interact(player), failures, "oversized interaction consumed")
	_expect(oversized_inventory.items.is_empty(), failures, "oversized fails closed")

	var legacy_inventory := MockInventory.new()
	var legacy := LootContainerScript.new()
	legacy.configure("legacy", "fallback", "legacy-seed", legacy_inventory, tables, Vector3.ZERO, 1.8)
	legacy.set_validation_player_in_range(player)
	_expect(legacy.try_interact(player), failures, "legacy interaction")
	_expect(legacy_inventory.items.get("random_fallback", 0) == 1, failures, "legacy table path")

	exact.free()
	malformed.free()
	oversized.free()
	legacy.free()
	player.free()
	if failures.is_empty():
		print("PROCGEN EXACT DROP RUNTIME PASS exact=true malformed_fail_closed=true single_use=true legacy_table=true")
		quit(0)
	else:
		push_error("PROCGEN EXACT DROP RUNTIME FAIL reasons=%s" % str(failures))
		quit(1)


func _expect(condition: bool, failures: Array[String], label: String) -> void:
	if not condition:
		failures.append(label)
