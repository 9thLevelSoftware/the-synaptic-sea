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
	gameplay["placed_props"] = [{
		"id": "unknown_builder_prop",
		"visual_id": "not_in_authoritative_prop_catalog",
		"room_id": room_id,
		"cell": [0, 0, 0],
	}]
	var placements: Array = layout.get("structural_plan", {}).get("floor_placements", [])
	if placements.is_empty():
		_fail("fixture has no floor placements")
		return
	var position := _vec3(placements[0].get("position", []))
	var from_cell: Array = [1, 1, 0]
	var to_cell: Array = [2, 0, 0]
	layout["radiation_zones"] = [{
		"id": "builder_radiation_01",
		"kind": "radiation",
		"from_room": room_id,
		"to_room": "corridor_01",
		"from_cell": from_cell,
		"to_cell": to_cell,
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
	if loader.get_placed_prop_errors().is_empty() or not loader.get_placed_prop_specs_copy().is_empty():
		_fail("unknown placed prop was counted as a materialized catalog prop")
		return
	var radiation_segments: Array = loader.get_radiation_zone_segments()
	if radiation_segments.size() != 1 or not radiation_segments[0] is Dictionary:
		_fail("radiation zone endpoint segment was not materialized")
		return
	var radiation_segment: Dictionary = radiation_segments[0]
	var radiation_from: Vector3 = radiation_segment["from"]
	var radiation_to: Vector3 = radiation_segment["to"]
	if radiation_from.distance_to(radiation_to) <= 5.0:
		_fail("radiation regression segment was not longer than five meters")
		return
	var radiation_volume := loader.find_child("RadiationZone_builder_radiation_01", true, false)
	if not radiation_volume is Area3D:
		_fail("radiation collision volume was not materialized")
		return
	var volume_axis: Vector3 = (radiation_volume as Area3D).basis.x.normalized()
	if absf(volume_axis.dot((radiation_to - radiation_from).normalized())) < 0.99:
		_fail("radiation collision volume was not aligned to its authored segment")
		return
	for endpoint in [radiation_from, radiation_to, radiation_from.lerp(radiation_to, 0.5)]:
		if loader.get_radiation_zone_at(endpoint, 0.1).is_empty():
			_fail("radiation query missed a point on the authored endpoint segment")
			return
	var perpendicular := Vector3(-(radiation_to - radiation_from).z, 0.0, (radiation_to - radiation_from).x).normalized()
	var segment_midpoint := radiation_from.lerp(radiation_to, 0.5)
	if loader.get_radiation_zone_at(segment_midpoint + perpendicular * 1.2).is_empty():
		_fail("radiation default query radius was narrower than the materialized volume")
		return
	if not loader.get_radiation_zone_at(segment_midpoint + perpendicular * 1.5).is_empty():
		_fail("radiation default query radius exceeded the materialized volume half-width")
		return
	if loader.get_radiation_zone_at(segment_midpoint + perpendicular * 1.2 + Vector3.UP * 1.2).is_empty():
		_fail("radiation query rejected a visible box corner")
		return
	var outward: Vector3 = (radiation_to - radiation_from).normalized()
	if not loader.get_radiation_zone_at(radiation_to + outward * 1.1).is_empty():
		_fail("radiation query extended beyond the authored endpoint span")
		return
	var rad = RadiationStateScript.new()
	rad.configure({"in_radiation_zone": not queried_radiation.is_empty()})
	rad.tick(1.0)
	if rad.radiation <= 0.0:
		_fail("authored radiation did not drive RadiationState")
		return

	var atmosphere_position := position + Vector3.UP * 0.12
	var atmosphere: Dictionary = loader.get_authored_atmosphere_at(atmosphere_position)
	if str(atmosphere.get("room_id", "")) != room_id or int(atmosphere.get("oxygen_bp", -1)) != 2500:
		_fail("authored atmosphere did not resolve to its room")
		return
	if atmosphere.has("temperature_c"):
		_fail("authored atmosphere synthesized an omitted temperature_c")
		return
	if loader.get_authored_atmosphere_at(atmosphere_position + Vector3(1.9, 1.2, 1.9)).is_empty():
		_fail("authored atmosphere query missed a point inside its materialized box")
		return
	if not loader.get_authored_atmosphere_at(atmosphere_position + Vector3(2.1, 0.5, -2.1)).is_empty():
		_fail("authored atmosphere query leaked beyond its materialized box")
		return
	var oxygen = OxygenStateScript.new()
	oxygen.configure({"max_oxygen": 100.0, "drain_rate": 8.0})
	oxygen.tick(1.0, {
		"field_atmosphere": true,
		"field_atmosphere_multiplier": loader.get_authored_atmosphere_drain_multiplier_at(atmosphere_position),
	})
	if oxygen.oxygen >= 100.0 or oxygen.effective_drain_rate <= 0.0:
		_fail("authored atmosphere did not drive OxygenState")
		return
	var temperature_only_layout: Dictionary = layout.duplicate(true)
	var temperature_only_room: Dictionary = temperature_only_layout["rooms"][0]
	for omitted_field in ["atmosphere_bp", "oxygen_bp", "depressurized", "vented", "radiation_bp"]:
		temperature_only_room.erase(omitted_field)
	temperature_only_room["temperature_c"] = 45.0
	temperature_only_layout["rooms"][0] = temperature_only_room
	if not loader.load_from_documents(temperature_only_layout, kit, gameplay, true, {
		"layout_path": LAYOUT_PATH, "kit_path": KIT_PATH, "gameplay_slice_path": GAMEPLAY_PATH,
	}):
		_fail("loader rejected temperature-only authored room")
		return
	var temperature_only_atmosphere: Dictionary = loader.get_authored_atmosphere_at(atmosphere_position)
	var temperature_only_multiplier := loader.get_authored_atmosphere_drain_multiplier_at(atmosphere_position)
	if str(temperature_only_atmosphere.get("room_id", "")) != room_id \
			or float(temperature_only_atmosphere.get("temperature_c", NAN)) != 45.0:
		_fail("temperature-only authored room was not materialized")
		return
	if temperature_only_atmosphere.has("oxygen_bp") or absf(temperature_only_multiplier - 1.0) > 0.001:
		_fail("temperature-only atmosphere synthesized oxygen_bp=%s or changed field_drain_multiplier=%s" % [
			str(temperature_only_atmosphere.get("oxygen_bp", "<omitted>")), str(temperature_only_multiplier)])
		return
	# Legacy authored rooms may declare only vented=true. That is an explicit
	# depressurization and must not fall back to a nominal 100% oxygen room.
	var saved_atmosphere_specs: Array = loader.authored_atmosphere_specs.duplicate(true)
	loader.authored_atmosphere_specs = [{"room_id": "vented_legacy", "position": position, "vented": true}]
	var vented_multiplier := loader.get_authored_atmosphere_drain_multiplier_at(position)
	loader.authored_atmosphere_specs = saved_atmosphere_specs
	if vented_multiplier != 1.0:
		_fail("vented atmosphere without oxygen_bp was not treated as depressurized")
	var vented_oxygen = OxygenStateScript.new()
	vented_oxygen.configure({"max_oxygen": 100.0, "drain_rate": 8.0})
	vented_oxygen.tick(1.0, {"field_atmosphere": true, "field_atmosphere_multiplier": vented_multiplier})
	if vented_oxygen.oxygen >= 100.0:
		_fail("vented atmosphere without oxygen_bp did not drain OxygenState")
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


func _fail(message: String) -> void:
	push_error("BUILDER AUTHORED RUNTIME FIELDS FAIL %s" % message)
	quit(1)
