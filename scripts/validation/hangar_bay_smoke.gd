extends SceneTree

## Pure-model smoke for HangarBay: slot fill/launch, size-class gate, full refusal,
## slot_of, summary round-trip; plus ShipInstance round-trips a HangarBay under "hangar".

const HangarBayScript := preload("res://scripts/systems/hangar_bay.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _init() -> void:
	var bay = HangarBayScript.create(2, 1)
	assert(bay.slot_count == 2, "slot_count set")
	assert(bay.slot_size_class == 1, "slot_size_class set")
	assert(bay.slots.size() == 2 and bay.slots[0] == "", "two empty slots")

	# size-class gate: a too-large ship finds no slot.
	assert(bay.free_slot_for(2) == -1, "oversize ship rejected by size class")
	assert(bay.free_slot_for(1) == 0, "fitting ship gets first slot")

	# dock fills slots; duplicate id rejected; full bay rejects.
	assert(bay.dock("ship_a", 1) == 0, "first dock -> slot 0")
	assert(bay.dock("ship_a", 1) == -1, "same ship cannot bay twice")
	assert(bay.slot_of("ship_a") == 0, "slot_of finds bayed ship")
	assert(bay.dock("ship_b", 1) == 1, "second dock -> slot 1")
	assert(bay.is_full(), "bay full after two docks")
	assert(bay.dock("ship_c", 1) == -1, "full bay refuses third ship")

	# launch frees a slot; the freed id is returned; the slot reopens.
	assert(bay.launch(0) == "ship_a", "launch returns bayed id")
	assert(bay.slot_of("ship_a") == -1, "launched ship no longer bayed")
	assert(not bay.is_full(), "bay not full after launch")
	assert(bay.launch(5) == "", "out-of-range launch is a no-op")

	# summary round-trip.
	bay.dock("ship_d", 1)
	var summary: Dictionary = bay.get_summary()
	var b2 = HangarBayScript.create(0, 0)
	assert(b2.apply_summary(summary) == true, "apply_summary accepts valid dict")
	assert(b2.slot_count == 2 and b2.slot_size_class == 1, "geometry round-trips")
	assert(b2.slot_of("ship_d") == bay.slot_of("ship_d"), "occupancy round-trips")
	assert(b2.apply_summary("nope") == false, "apply_summary rejects non-dict")

	# ShipInstance owns a HangarBay that round-trips under "hangar" only when it has slots.
	var inst = ShipInstanceScript.create("carrier", "cell:cell:1", null, null, null)
	assert(inst.has_hangar() == false, "fresh ship has no bay")
	assert(inst.get_summary().has("hangar") == false, "no bay -> no hangar key")
	var bay2 = HangarBayScript.create(1, 1)
	inst.hangar = bay2
	inst.get_hangar().dock("ship_e", 1)
	assert(inst.has_hangar() == true, "ship with slots has a bay")
	var inst_summary: Dictionary = inst.get_summary()
	assert(inst_summary.has("hangar"), "ship summary carries hangar")
	var inst2 = ShipInstanceScript.create("carrier", "cell:cell:1", null, null, null)
	inst2.apply_summary(inst_summary)
	assert(inst2.get_hangar().slot_of("ship_e") == 0, "ship hangar occupancy round-trips")

	print("HANGAR BAY SMOKE PASS slots=%d size=%d occupant=%s" % [b2.slot_count, b2.slot_size_class, str(inst2.get_hangar().slot_of("ship_e"))])
	quit()
