extends SceneTree

## Pure-model smoke: quantitied/weighted/categorized inventory + tool-shim
## backward compatibility. No scene tree.

const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

func _initialize() -> void:
	var ok_add: bool = _test_add_and_categories()
	var ok_weight: bool = _test_weight_cap()
	var ok_round: bool = _test_round_trip()
	var ok_legacy: bool = _test_legacy_compat()
	if ok_add and ok_weight and ok_round and ok_legacy:
		print("ITEM INVENTORY PASS add=true weight_cap=true round_trip=true legacy_compat=true")
	else:
		push_error("ITEM INVENTORY FAIL add=%s weight_cap=%s round_trip=%s legacy_compat=%s" % [
			str(ok_add), str(ok_weight), str(ok_round), str(ok_legacy)])
	quit(0 if (ok_add and ok_weight and ok_round and ok_legacy) else 1)

func _test_add_and_categories() -> bool:
	var inv = InventoryStateScript.new()
	# power_cell is a 'part' defined in item_definitions.json (weight 1.0, max_stack 10).
	var added: int = inv.add_item("power_cell", 3)
	if added != 3 or inv.get_quantity("power_cell") != 3:
		return false
	var parts: Array = inv.get_items_by_category("part")
	if parts.size() != 1 or int(parts[0]["quantity"]) != 3:
		return false
	# Tools still resolve through the shims and are category 'tool'.
	if not inv.add_tool("portable_oxygen_pump"):
		return false
	if not inv.has_tool("portable_oxygen_pump"):
		return false
	if inv.get_category("portable_oxygen_pump") != "tool":
		return false
	if inv.get_drain_multiplier() != 0.5:
		return false
	# Derived tool_ids excludes parts.
	if inv.tool_ids != ["portable_oxygen_pump"]:
		return false
	return true

func _test_weight_cap() -> bool:
	var inv = InventoryStateScript.new()
	# Fill near max with a heavy part, then assert a further add is rejected/partial.
	var max_w: float = inv.get_max_weight()
	# scrap_metal weight 5.0; how many fit fully:
	var fit: int = int(floor(max_w / 5.0))
	var added: int = inv.add_item("scrap_metal", fit + 5)  # request more than fits
	if added != fit:
		return false
	if inv.get_total_weight() > max_w + 0.0001:
		return false
	# A further add of any weighted item returns 0 (full).
	if inv.add_item("scrap_metal", 1) != 0:
		return false
	return true

func _test_round_trip() -> bool:
	var inv = InventoryStateScript.new()
	inv.add_item("power_cell", 2)
	inv.add_item("ration_pack", 4)   # supply
	inv.add_tool("junction_calibrator")
	var summary: Dictionary = inv.get_summary()
	var restored = InventoryStateScript.new()
	if not restored.apply_summary(summary):
		return false
	if restored.get_quantity("power_cell") != 2: return false
	if restored.get_quantity("ration_pack") != 4: return false
	if not restored.has_tool("junction_calibrator"): return false
	if abs(restored.get_total_weight() - inv.get_total_weight()) > 0.0001: return false
	return true

func _test_legacy_compat() -> bool:
	# A pre-#3 save carried only {"tool_ids": [...], "drain_multiplier": ...}.
	var legacy: Dictionary = {"tool_ids": ["portable_oxygen_pump"], "drain_multiplier": 0.5}
	var inv = InventoryStateScript.new()
	if not inv.apply_summary(legacy):
		return false
	if not inv.has_tool("portable_oxygen_pump"): return false
	if inv.get_drain_multiplier() != 0.5: return false
	if inv.tool_ids != ["portable_oxygen_pump"]: return false
	return true
