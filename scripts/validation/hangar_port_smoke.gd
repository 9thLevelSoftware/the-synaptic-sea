extends SceneTree

## DockPorts.for_hangar derives slots/anchors from a hangar room, falls back to a
## cargo room (home-bay path), and returns {} when neither exists; ports_compatible
## accepts a small ship into a big bay and rejects an oversize ship.

const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")

func _make_room(role: String, n_cells: int) -> Dictionary:
	var placements: Array = []
	for i in range(n_cells):
		placements.append({"name": "floor_%d" % i, "module": "floor_1x1",
			"world_position": [float(i) * 4.0, 0.0, 0.0]})
	return {"id": role + "_01", "room_role": role, "deck": 0, "structural_placements": placements}

func _init() -> void:
	# A 6-cell hangar -> slot_count = 6/CELLS_PER_SLOT(2) = 3; size_class 2 (>=4 cells).
	var hangar_layout: Dictionary = {"rooms": [_make_room("hangar", 6)]}
	var port: Dictionary = DockPortsScript.for_hangar(hangar_layout)
	assert(str(port.get("type", "")) == "hangar", "type is hangar")
	assert(int(port.get("slot_count", 0)) == 3, "6 cells / 2 per slot = 3 slots")
	assert(int(port.get("slot_size_class", 0)) == 2, "large hangar -> size class 2")
	assert((port.get("slot_anchors", []) as Array).size() == 3, "one anchor per slot")

	# No hangar room -> falls back to the cargo room (the home ship's bay).
	var cargo_layout: Dictionary = {"rooms": [_make_room("cargo", 3)]}
	var cargo_port: Dictionary = DockPortsScript.for_hangar(cargo_layout)
	assert(str(cargo_port.get("type", "")) == "hangar", "cargo fallback yields a hangar port")
	assert(int(cargo_port.get("slot_count", 0)) == 1, "3 cells / 2 = 1 slot (min 1)")
	assert(int(cargo_port.get("slot_size_class", 0)) == 1, "small bay -> size class 1")

	# Neither hangar nor cargo -> empty.
	var bare_layout: Dictionary = {"rooms": [_make_room("corridor", 4)]}
	assert(DockPortsScript.for_hangar(bare_layout).is_empty(), "no hangar/cargo -> {}")

	# ports_compatible: asymmetric hangar accept/reject.
	var bay: Dictionary = {"type": "hangar", "slot_size_class": 2}
	var small_ship: Dictionary = {"type": "airlock", "size_class": 1}
	var big_ship: Dictionary = {"type": "airlock", "size_class": 3}
	assert(DockPortsScript.ports_compatible(bay, small_ship) == true, "small ship fits big bay")
	assert(DockPortsScript.ports_compatible(small_ship, bay) == true, "order-independent")
	assert(DockPortsScript.ports_compatible(bay, big_ship) == false, "oversize ship rejected")
	var bay2: Dictionary = {"type": "hangar", "slot_size_class": 1}
	assert(DockPortsScript.ports_compatible(bay, bay2) == false, "two bays cannot dock")

	# Symmetric airlock path still holds.
	var a1: Dictionary = {"type": "airlock", "size_class": 1}
	var a2: Dictionary = {"type": "airlock", "size_class": 1}
	assert(DockPortsScript.ports_compatible(a1, a2) == true, "airlock symmetric still works")

	print("HANGAR PORT SMOKE PASS slots=%d size=%d cargo_slots=%d" % [
		int(port.get("slot_count", 0)), int(port.get("slot_size_class", 0)), int(cargo_port.get("slot_count", 0))])
	quit()
