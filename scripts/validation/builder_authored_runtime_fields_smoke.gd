extends SceneTree

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")
const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const LAYOUT_PATH := "res://data/procgen/golden/coherent_ship_001/layout.json"
const KIT_PATH := "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_PATH := "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"


func _initialize() -> void:
	var layout := _json(LAYOUT_PATH)
	var kit := _json(KIT_PATH)
	var gameplay := _json(GAMEPLAY_PATH)
	var rooms: Array = layout.get("rooms", [])
	if rooms.is_empty():
		_fail("fixture has no rooms")
		return
	var room: Dictionary = rooms[0]
	room["atmosphere_bp"] = 2500
	room["depressurized"] = true
	var room_id := str(room.get("id", ""))
	var placements: Array = layout.get("structural_plan", {}).get("floor_placements", [])
	if placements.is_empty():
		_fail("fixture has no floor placements")
		return
	var position := _vec3(placements[0].get("position", []))
	layout["radiation_zones"] = [{
		"id": "builder_radiation_01",
		"kind": "radiation",
		"from_room": room_id,
		"to_room": room_id,
		"from_cell": _cell3(placements[0]),
		"to_cell": _cell3(placements[0]),
	}]

	var loader = LoaderScript.new()
	root.add_child(loader)
	if not loader.load_from_documents(layout, kit, gameplay, true, {
		"layout_path": LAYOUT_PATH, "kit_path": KIT_PATH, "gameplay_slice_path": GAMEPLAY_PATH,
	}):
		_fail("loader rejected augmented authored documents")
		return
	var radiation_specs: Array = loader.get_radiation_zone_specs()
	var radiation_markers: Array[Vector3] = loader.get_radiation_zone_markers()
	if radiation_specs.size() != 1 or radiation_markers.size() != 1:
		_fail("radiation zone was not materialized")
		return
	var queried_radiation: Dictionary = loader.get_radiation_zone_at(radiation_markers[0])
	if str(queried_radiation.get("zone_id", "")) != "builder_radiation_01":
		_fail("radiation spatial query missed its authored volume")
		return
	var rad = RadiationStateScript.new()
	rad.configure({"in_radiation_zone": not queried_radiation.is_empty()})
	rad.tick(1.0)
	if rad.radiation <= 0.0:
		_fail("authored radiation did not drive RadiationState")
		return

	var atmosphere: Dictionary = loader.get_authored_atmosphere_at(position)
	if str(atmosphere.get("room_id", "")) != room_id or int(atmosphere.get("oxygen_bp", -1)) != 2500:
		_fail("authored atmosphere did not resolve to its room")
		return
	var oxygen = OxygenStateScript.new()
	oxygen.configure({"max_oxygen": 100.0, "drain_rate": 8.0})
	oxygen.tick(1.0, {
		"field_atmosphere": true,
		"field_atmosphere_multiplier": loader.get_authored_atmosphere_drain_multiplier_at(position),
	})
	if oxygen.oxygen >= 100.0 or oxygen.effective_drain_rate <= 0.0:
		_fail("authored atmosphere did not drive OxygenState")
		return
	print("BUILDER AUTHORED RUNTIME FIELDS PASS radiation=true atmosphere=true room=%s oxygen_bp=2500" % room_id)
	loader.free()
	quit(0)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _vec3(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _cell3(placement: Dictionary) -> Array:
	var cell: Array = placement.get("cell", [0, 0])
	return [int(cell[0]), int(cell[1]), int(placement.get("deck", 0))]


func _fail(message: String) -> void:
	push_error("BUILDER AUTHORED RUNTIME FIELDS FAIL %s" % message)
	quit(1)
