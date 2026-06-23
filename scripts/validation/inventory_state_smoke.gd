extends SceneTree

func _initialize() -> void:
	var inventory := InventoryState.new()
	var initial: Dictionary = inventory.get_summary()
	if not initial.has("tool_ids"):
		_fail("initial summary missing tool_ids")
		return
	if (initial.get("tool_ids") as Array).size() != 0:
		_fail("initial tool_ids should be empty")
		return

	if not inventory.add_tool("portable_oxygen_pump"):
		_fail("add_tool(portable_oxygen_pump) should return true on first add")
		return
	if not inventory.has_tool("portable_oxygen_pump"):
		_fail("has_tool(portable_oxygen_pump) should be true after add")
		return
	if inventory.add_tool("portable_oxygen_pump"):
		_fail("duplicate add_tool should return false")
		return

	var after_add: Dictionary = inventory.get_summary()
	var tool_ids: Array = after_add.get("tool_ids", []) as Array
	if tool_ids.size() != 1:
		_fail("tool_ids should contain exactly one tool")
		return
	if str(tool_ids[0]) != "portable_oxygen_pump":
		_fail("tool_ids[0] should be portable_oxygen_pump, got %s" % str(tool_ids[0]))
		return
	# Snapshot "pump carried" state at the moment we are asserting the
	# multiplier in the same tick — the spec marker wants pump=true here
	# while the pump effect is in force.
	var pump_carried_at_multiplier: bool = inventory.has_tool("portable_oxygen_pump")

	var status_lines: PackedStringArray = inventory.get_status_lines()
	var found_tool_line: bool = false
	for line in status_lines:
		if String(line) == "Tool: Portable Oxygen Pump":
			found_tool_line = true
			break
	if not found_tool_line:
		_fail("status lines missing 'Tool: Portable Oxygen Pump', got %s" % str(status_lines))
		return

	# Verify OxygenState honors the inventory summary.
	var oxygen := OxygenState.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary.
	oxygen.configure({
		"zone_ids": ["corridor_to_reactor"],
		"max_oxygen": 100.0,
		"drain_rate": 6.0,
		"regen_rate": 3.5,
		"recovery_threshold": 30.0,
		"safe_threshold": 35.0,
	})
	oxygen.apply_inventory_summary(inventory.get_summary())
	oxygen.tick(1.0, true)
	var after_pump: Dictionary = oxygen.get_summary()
	var effective_drain_rate: float = float(after_pump.get("effective_drain_rate", -1.0))
	if absf(effective_drain_rate - 3.0) > 0.001:
		_fail("effective_drain_rate with pump should be 3.0, got %s" % str(effective_drain_rate))
		return
	var oxygen_after_pump: float = float(after_pump.get("oxygen", -1.0))
	if absf(oxygen_after_pump - 97.0) > 0.001:
		_fail("oxygen after one pumped tick should be 97.0, got %s" % str(oxygen_after_pump))
		return

	# Remove the pump and confirm full drain returns.
	if not inventory.remove_tool("portable_oxygen_pump"):
		_fail("remove_tool(portable_oxygen_pump) should return true")
		return
	oxygen.apply_inventory_summary(inventory.get_summary())
	oxygen.tick(1.0, true)
	var after_remove: Dictionary = oxygen.get_summary()
	effective_drain_rate = float(after_remove.get("effective_drain_rate", -1.0))
	if absf(effective_drain_rate - 6.0) > 0.001:
		_fail("effective_drain_rate without pump should be 6.0, got %s" % str(effective_drain_rate))
		return

	# Final summary must include the keys called out in the spec.
	var final_inventory: Dictionary = inventory.get_summary()
	for key in ["tool_ids", "active_effects", "drain_multiplier"]:
		if not final_inventory.has(key):
			_fail("inventory summary missing key: %s" % key)
			return

	# The multiplier OxygenState consumes must come from InventoryState,
	# not be re-derived in OxygenState. The summary key is the contract.
	var summary_multiplier_no_pump: float = float(final_inventory.get("drain_multiplier", -1.0))
	if absf(summary_multiplier_no_pump - 1.0) > 0.001:
		_fail("inventory summary drain_multiplier without pump should be 1.0, got %s" % str(summary_multiplier_no_pump))
		return
	if not inventory.add_tool("portable_oxygen_pump"):
		# Already carried (re-add would be a duplicate). Re-create the model
		# for a clean carrier-positive read.
		inventory = InventoryState.new()
		if not inventory.add_tool("portable_oxygen_pump"):
			_fail("could not add portable_oxygen_pump to fresh inventory")
			return
	var summary_multiplier_with_pump: float = float(inventory.get_summary().get("drain_multiplier", -1.0))
	if absf(summary_multiplier_with_pump - 0.5) > 0.001:
		_fail("inventory summary drain_multiplier with pump should be 0.5, got %s" % str(summary_multiplier_with_pump))
		return

	# --- PZ soft-cap (slice 2): weight never refuses; capacity/load queries ---
	var sc := InventoryState.new()
	sc.add_item("scrap_metal", 20)        # 20 * 5.0 = 100.0 weight, base cap 50.0
	assert(sc.get_quantity("scrap_metal") == 20, "soft-cap accepted a full stack over weight")
	assert(sc.is_over_capacity(), "over capacity after overload")
	assert(sc.get_load_ratio() > 1.0, "load ratio > 1 when overloaded")
	sc.bonus_capacity = 60.0              # a worn container raises the budget
	assert(not sc.is_over_capacity(), "container bonus lifts player back under capacity")

	print("INVENTORY STATE PASS tools=%d pump=%s drain_multiplier=%s" % [
		tool_ids.size(),
		str(pump_carried_at_multiplier).to_lower(),
		str(float(after_pump.get("drain_multiplier", -1.0))),
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("INVENTORY STATE FAIL reason=%s" % reason)
	quit(1)