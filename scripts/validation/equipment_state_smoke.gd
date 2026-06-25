extends SceneTree

## EquipmentState pure-model smoke: equip/unequip, slot validation, displacement,
## capacity-bonus + oxygen-multiplier aggregation, summary round-trip.

const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")

func _init() -> void:
	var eq = EquipmentStateScript.create()
	assert(eq.get_carry_capacity_bonus() == 0.0, "empty -> no capacity bonus")
	assert(eq.get_oxygen_drain_multiplier() == 1.0, "empty -> neutral oxygen multiplier")

	# Non-equippable item refused.
	assert(eq.can_equip("scrap_metal") == false, "plain item cannot equip")
	assert(eq.equip("scrap_metal").get("ok") == false, "equip of plain item fails")

	# Equip a backpack on the back slot.
	var r1: Dictionary = eq.equip("eva_backpack")
	assert(r1.get("ok") == true and str(r1.get("displaced")) == "", "backpack equipped, nothing displaced")
	assert(eq.get_equipped("back") == "eva_backpack", "back slot holds the backpack")
	assert(eq.is_slot_occupied("back"), "back slot occupied")
	assert(eq.get_carry_capacity_bonus() == 40.0, "backpack adds 40 capacity")

	# Equip a waist pack -> stacks the bonus.
	eq.equip("tool_belt")
	assert(eq.get_carry_capacity_bonus() == 52.0, "backpack + tool_belt = 52 (got %s)" % str(eq.get_carry_capacity_bonus()))

	# Equip a suit -> oxygen multiplier.
	eq.equip("hardsuit")
	assert(eq.get_oxygen_drain_multiplier() == 0.75, "hardsuit drain multiplier 0.75")

	# get_container_reductions: worn containers only (suit excluded, capacity 0).
	var reds: Array = eq.get_container_reductions()
	assert(reds.size() == 2, "two worn containers (suit excluded), got %d" % reds.size())
	var by_cap: Dictionary = {}
	for r in reds:
		by_cap[float(r["capacity"])] = float(r["reduction"])
	assert(by_cap.has(40.0) and absf(by_cap[40.0] - 0.30) < 0.0001, "backpack 40 -> 0.30")
	assert(by_cap.has(12.0) and absf(by_cap[12.0] - 0.10) < 0.0001, "tool_belt 12 -> 0.10")

	# Displacement: a second back item displaces the backpack.
	var r2: Dictionary = eq.equip("field_pack")
	assert(r2.get("ok") == true and str(r2.get("displaced")) == "eva_backpack", "field_pack displaced the backpack")
	assert(eq.get_equipped("back") == "field_pack", "back slot now holds field_pack")
	assert(eq.get_carry_capacity_bonus() == 27.0, "field_pack(15) + tool_belt(12) = 27 (got %s)" % str(eq.get_carry_capacity_bonus()))

	# Unequip returns the worn id and clears the slot.
	var removed: String = eq.unequip("waist")
	assert(removed == "tool_belt", "unequip waist returns tool_belt")
	assert(not eq.is_slot_occupied("waist"), "waist now empty")
	assert(eq.unequip("waist") == "", "unequip empty slot returns empty")

	# Round-trip.
	var summary: Dictionary = eq.get_summary()
	var clone = EquipmentStateScript.create()
	assert(clone.apply_summary(summary) == true, "apply_summary accepts")
	assert(clone.get_equipped("back") == "field_pack", "worn items round-tripped")
	assert(clone.get_oxygen_drain_multiplier() == 0.75, "suit effect round-tripped")
	assert(EquipmentStateScript.create().apply_summary({}) == false, "empty summary rejected")

	print("EQUIPMENT STATE SMOKE PASS bonus=%s oxy=%s" % [str(clone.get_carry_capacity_bonus()), str(clone.get_oxygen_drain_multiplier())])
	quit()
