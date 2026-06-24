extends SceneTree

## Cross-model smoke for the suit->oxygen wiring (Phase 7 sub-project B):
## EquipmentState.get_oxygen_drain_multiplier() feeds OxygenState via
## apply_equipment_summary, stacking multiplicatively with the inventory
## (pump) multiplier and gated to 1.0 when the breach is sealed/closed.

const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")

func _initialize() -> void:
	# --- EquipmentState side: worn-suit multiplier (already implemented) ---
	var eq = EquipmentStateScript.create()
	if eq.get_oxygen_drain_multiplier() != 1.0:
		_fail("empty equipment should be neutral 1.0, got %s" % str(eq.get_oxygen_drain_multiplier()))
		return
	eq.equip("hardsuit")
	if eq.get_oxygen_drain_multiplier() != 0.75:
		_fail("hardsuit should give 0.75, got %s" % str(eq.get_oxygen_drain_multiplier()))
		return

	# --- OxygenState side: combined multiplier in an open, unsealed breach ---
	var ox = OxygenStateScript.new()
	ox.configure({
		"zone_ids": ["corridor_to_reactor"],
		"max_oxygen": 100.0,
		"drain_rate": 6.0,
		"regen_rate": 0.0,
		"recovery_threshold": 30.0,
		"safe_threshold": 35.0,
	})

	# Suit only (inventory neutral): effective drain = 6.0 * 0.75 = 4.5
	ox.apply_equipment_summary({"drain_multiplier": eq.get_oxygen_drain_multiplier()})
	ox.tick(1.0, true)
	var suit_only: Dictionary = ox.get_summary()
	if absf(float(suit_only.get("effective_drain_rate", -1.0)) - 4.5) > 0.001:
		_fail("suit-only effective_drain_rate should be 4.5, got %s" % str(suit_only.get("effective_drain_rate", -1.0)))
		return
	if absf(float(suit_only.get("equipment_drain_multiplier", -1.0)) - 0.75) > 0.001:
		_fail("equipment_drain_multiplier should be 0.75, got %s" % str(suit_only.get("equipment_drain_multiplier", -1.0)))
		return
	if absf(float(suit_only.get("drain_multiplier", -1.0)) - 0.75) > 0.001:
		_fail("suit-only combined drain_multiplier should be 0.75, got %s" % str(suit_only.get("drain_multiplier", -1.0)))
		return

	# Suit + pump: 0.75 * 0.5 = 0.375 -> effective 6.0 * 0.375 = 2.25
	ox.apply_inventory_summary({"drain_multiplier": 0.5})
	ox.tick(1.0, true)
	var combined: Dictionary = ox.get_summary()
	if absf(float(combined.get("drain_multiplier", -1.0)) - 0.375) > 0.001:
		_fail("suit+pump combined drain_multiplier should be 0.375, got %s" % str(combined.get("drain_multiplier", -1.0)))
		return
	if absf(float(combined.get("effective_drain_rate", -1.0)) - 2.25) > 0.001:
		_fail("suit+pump effective_drain_rate should be 2.25, got %s" % str(combined.get("effective_drain_rate", -1.0)))
		return

	# Sealing the breach forces the multiplier back to 1.0 (drain suppressed there).
	ox.seal_breach("corridor_to_reactor")
	var sealed: Dictionary = ox.get_summary()
	if absf(float(sealed.get("drain_multiplier", -1.0)) - 1.0) > 0.001:
		_fail("sealed breach should force drain_multiplier to 1.0, got %s" % str(sealed.get("drain_multiplier", -1.0)))
		return

	print("OXYGEN EQUIPMENT DRAIN SMOKE PASS suit=0.75 combined=0.375")
	quit(0)

func _fail(reason: String) -> void:
	push_error("OXYGEN EQUIPMENT DRAIN SMOKE FAIL reason=%s" % reason)
	quit(1)
