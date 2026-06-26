extends SceneTree

## ShipInventory pure-model smoke: add/remove, weight-cap + stack-limit gating,
## get_summary/apply_summary round-trip. ShipInventory is a plain per-ship cargo
## container (no player tool shims), weight-capped (default 500), sharing ItemDefs
## weights with the player InventoryState.

const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")

func _init() -> void:
	var hold = ShipInventoryScript.create(500.0)
	assert(hold.get_max_weight() == 500.0, "configured cap")
	assert(hold.get_total_weight() == 0.0, "starts empty")

	# add_item returns qty actually added; honors stack room.
	var added: int = hold.add_item("scrap_metal", 5)
	assert(added == 5, "added 5 scrap_metal (got %d)" % added)
	assert(hold.get_quantity("scrap_metal") == 5, "quantity tracks")

	# remove_item returns qty actually removed.
	var removed: int = hold.remove_item("scrap_metal", 2)
	assert(removed == 2, "removed 2 (got %d)" % removed)
	assert(hold.get_quantity("scrap_metal") == 3, "quantity after remove")

	# Weight cap gating: a 12.0-cap hold fits exactly 2 scrap_metal (weight 5.0 each).
	var tiny = ShipInventoryScript.create(12.0)
	var fit: int = tiny.add_item("scrap_metal", 999)
	assert(fit == 2, "weight cap limited the add to 2 (fit=%d)" % fit)
	assert(tiny.get_total_weight() <= 12.0 + 0.0001, "never exceeds cap")

	# Round-trip.
	var summary: Dictionary = hold.get_summary()
	assert(summary.has("items") and summary.has("max_weight"), "summary shape")
	var restored = ShipInventoryScript.create(1.0)
	assert(restored.apply_summary(summary) == true, "apply_summary accepts")
	assert(restored.get_quantity("scrap_metal") == 3, "items round-tripped")
	assert(restored.get_max_weight() == 500.0, "max_weight round-tripped")

	# Tolerant: empty summary rejected.
	assert(ShipInventoryScript.create().apply_summary({}) == false, "empty summary rejected")

	print("SHIP INVENTORY SMOKE PASS items=%d weight=%s" % [restored.get_quantity("scrap_metal"), str(restored.get_total_weight())])
	quit()
