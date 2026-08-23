extends SceneTree

## REQ-FILL-001: loot/components/dressing land on interior_zones slots.
## Marker: ENCLOSED SLOT FILL PASS loot_on_slot=true no_floor_dump=true components_on_cell=true dressing=true

const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")


func _initialize() -> void:
	if not _check_serializer_cells():
		return
	if not _check_extract_interior_zones():
		return
	if not _check_string_cell_parse():
		return
	if not _check_synthetic_fill():
		return
	if not _check_generated_fill():
		return
	if not _check_dressing_props():
		return
	print("ENCLOSED SLOT FILL PASS loot_on_slot=true no_floor_dump=true components_on_cell=true dressing=true")
	quit(0)


func _fail(msg: String) -> bool:
	push_error("ENCLOSED SLOT FILL FAIL: %s" % msg)
	print("ENCLOSED SLOT FILL FAIL: %s" % msg)
	quit(1)
	return false


func _check_serializer_cells() -> bool:
	var serializer: LayoutSerializerScript = LayoutSerializerScript.new()
	var zones: Dictionary = {
		"reserved_cells": [Vector2i(0, 0)],
		"center_slots": [Vector2i(1, 1)],
		"wall_slots": [
			{"cell": Vector2i(1, 0), "against_wall": true},
		],
	}
	var serialized: Dictionary = serializer._serialize_interior_zones(zones)
	var reparsed: Variant = JSON.parse_string(JSON.stringify(serialized))
	if not (reparsed is Dictionary):
		return _fail("interior_zones JSON round-trip failed")
	var walls: Array = (reparsed as Dictionary).get("wall_slots", [])
	if walls.is_empty() or typeof(walls[0]) != TYPE_DICTIONARY:
		return _fail("wall_slots missing after serialize")
	var cell_v: Variant = (walls[0] as Dictionary).get("cell", null)
	if not (cell_v is Array) or (cell_v as Array).size() < 2 or int((cell_v as Array)[0]) != 1 or int((cell_v as Array)[1]) != 0:
		return _fail("wall slot cell not [x,z] after JSON, got %s" % str(cell_v))
	var centers: Array = (reparsed as Dictionary).get("center_slots", [])
	if centers.is_empty() or not (centers[0] is Array) or int((centers[0] as Array)[0]) != 1:
		return _fail("center_slots not [x,z] after JSON, got %s" % str(centers))
	var reserved: Array = (reparsed as Dictionary).get("reserved_cells", [])
	if reserved.is_empty() or not (reserved[0] is Array) or int((reserved[0] as Array)[0]) != 0:
		return _fail("reserved_cells not [x,z] after JSON")
	return true


func _check_extract_interior_zones() -> bool:
	var place = ComponentPlacementStateScript.new()
	var room: Dictionary = {
		"id": "eng_1",
		"room_role": "engineering",
		"interior_zones": {
			"wall_slots": [{"cell": [2, 3], "against_wall": true}],
			"center_slots": [[4, 5]],
			"reserved_cells": [[0, 0]],
		},
		"wall_slots": [{"cell": "(9, 9)"}],
		"structural_placements": [
			{"name": "floor_cell_x0_z0", "module": "floor_1x1"},
		],
	}
	var walls: Array = place._extract_slots(room, "wall_slots")
	if walls.size() != 1:
		return _fail("interior_zones wall_slots not preferred, got %d" % walls.size())
	var wcell: Variant = (walls[0] as Dictionary).get("cell", [])
	var parsed: Array = LayoutSerializerScript.parse_slot_cell(wcell)
	if parsed.size() < 2 or int(parsed[0]) != 2 or int(parsed[1]) != 3:
		return _fail("interior_zones wall cell expected [2,3] got %s" % str(wcell))
	var centers: Array = place._extract_slots(room, "center_slots")
	if centers.size() != 1:
		return _fail("interior_zones center_slots size %d" % centers.size())
	var cparsed: Array = LayoutSerializerScript.parse_slot_cell((centers[0] as Dictionary).get("cell", []))
	if cparsed.size() < 2 or int(cparsed[0]) != 4:
		return _fail("interior_zones center cell expected [4,5] got %s" % str(cparsed))
	return true


func _check_string_cell_parse() -> bool:
	var a: Array = LayoutSerializerScript.parse_slot_cell("(1, 0)")
	if a.size() < 2 or int(a[0]) != 1 or int(a[1]) != 0:
		return _fail("parse '(1, 0)' failed got %s" % str(a))
	var b: Array = LayoutSerializerScript.parse_slot_cell([3, 4])
	if b.size() < 2 or int(b[0]) != 3 or int(b[1]) != 4:
		return _fail("parse [3,4] failed")
	return true


func _synthetic_room() -> Dictionary:
	return {
		"id": "cargo_01",
		"room_role": "cargo",
		"variant": "biomatter_crusted",
		"deck": 0,
		"interior_zones": {
			"reserved_cells": [[0, 0]],
			"center_slots": [[1, 1]],
			"wall_slots": [
				{"cell": [1, 0], "against_wall": true},
				{"cell": [2, 0], "against_wall": true},
				{"cell": [0, 1], "against_wall": true},
			],
		},
		"structural_placements": [
			{"name": "floor_cell_x0_z0", "module": "floor_1x1", "world_position": [0.0, 0.0, 0.0]},
			{"name": "floor_cell_x1_z0", "module": "floor_1x1", "world_position": [4.0, 0.0, 0.0]},
			{"name": "floor_cell_x2_z0", "module": "floor_1x1", "world_position": [8.0, 0.0, 0.0]},
			{"name": "floor_cell_x0_z1", "module": "floor_1x1", "world_position": [0.0, 0.0, 4.0]},
			{"name": "floor_cell_x1_z1", "module": "floor_1x1", "world_position": [4.0, 0.0, 4.0]},
		],
	}


func _check_synthetic_fill() -> bool:
	var cargo: Dictionary = _synthetic_room()
	var start_room: Dictionary = {
		"id": "airlock_01",
		"room_role": "airlock",
		"deck": 0,
		"interior_zones": {
			"reserved_cells": [[0, 0]],
			"center_slots": [],
			"wall_slots": [{"cell": [1, 0], "against_wall": true}],
		},
		"structural_placements": [
			{"name": "floor_cell_x0_z0", "module": "floor_1x1", "world_position": [0.0, 0.0, 0.0]},
		],
	}
	var goal_room: Dictionary = {
		"id": "bridge_01",
		"room_role": "bridge",
		"deck": 0,
		"interior_zones": {
			"reserved_cells": [],
			"center_slots": [[2, 2]],
			"wall_slots": [],
		},
		"structural_placements": [
			{"name": "floor_cell_x2_z2", "module": "floor_1x1", "world_position": [8.0, 0.0, 8.0]},
		],
	}
	var layout: Dictionary = {
		"program_id": "procgen-derelict-seed-42",
		"prototype": {"start_room": "airlock_01", "goal_room": "bridge_01"},
		"rooms": [start_room, cargo, goal_room],
		"room_links": [],
		"critical_path": ["airlock_01", "cargo_01", "bridge_01"],
	}
	var builder = GameplaySliceBuilderScript.new()
	var slice: Dictionary = builder.build(layout)
	var loot: Array = slice.get("loot_containers", [])
	if loot.is_empty():
		return _fail("synthetic slice has no loot")
	var first_loot: Dictionary = loot[0]
	var approach: Array = first_loot.get("approach_cell", [])
	if approach.size() < 2:
		return _fail("loot approach_cell incomplete")
	if int(approach[0]) == 0 and int(approach[1]) == 0:
		return _fail("loot dumped on first floor cell")
	if not _cell_in_slots(cargo, approach):
		return _fail("loot not on a wall/center slot, got %s" % str(approach))
	var salvage_cell: Array = []
	for obj_v in slice.get("objectives", []):
		if typeof(obj_v) != TYPE_DICTIONARY:
			continue
		if str((obj_v as Dictionary).get("type", "")) != "salvage":
			continue
		salvage_cell = (obj_v as Dictionary).get("approach_cell", [])
		break
	if salvage_cell.size() >= 2 and int(salvage_cell[0]) == int(approach[0]) and int(salvage_cell[1]) == int(approach[1]):
		return _fail("loot shared salvage slot %s" % str(approach))
	var occupied: Dictionary = {
		"cargo_01|%d|%d" % [int(approach[0]), int(approach[1])]: true,
	}
	if salvage_cell.size() >= 2:
		occupied["cargo_01|%d|%d" % [int(salvage_cell[0]), int(salvage_cell[1])]] = true
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		return _fail("catalog load")
	var place = ComponentPlacementStateScript.new()
	place.populate(layout, cat, 42, occupied)
	if place.placed.is_empty():
		return _fail("components did not place on synthetic slots")
	var on_cell: bool = false
	for entry_v in place.placed:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry_v
		if str(e.get("room_id", "")) != "cargo_01":
			continue
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(e.get("cell", null))
		if parsed.size() < 2:
			return _fail("component cell not parsed: %s" % str(e.get("cell", "")))
		var ckey: String = "cargo_01|%d|%d" % [int(parsed[0]), int(parsed[1])]
		if occupied.has(ckey):
			return _fail("component shared occupied slot %s" % ckey)
		on_cell = true
	if not on_cell:
		return _fail("no cargo component on a slot cell")
	return true


func _first_floor_xz(room: Dictionary) -> Array:
	var placements: Array = room.get("structural_placements", [])
	for placement in placements:
		if typeof(placement) != TYPE_DICTIONARY:
			continue
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(str((placement as Dictionary).get("name", "")))
		if parsed.size() >= 2:
			return parsed
	return []


func _room_by_id(rooms: Array, room_id: String) -> Dictionary:
	for room_v in rooms:
		if typeof(room_v) == TYPE_DICTIONARY and str((room_v as Dictionary).get("id", "")) == room_id:
			return room_v
	return {}


func _cell_in_slots(room: Dictionary, cell: Array) -> bool:
	if cell.size() < 2:
		return false
	var interior: Variant = room.get("interior_zones", {})
	if not (interior is Dictionary):
		return false
	var zones: Dictionary = interior
	var buckets: Array = [zones.get("center_slots", []), zones.get("wall_slots", [])]
	for bucket_v in buckets:
		if not (bucket_v is Array):
			continue
		for item in (bucket_v as Array):
			var parsed: Array = LayoutSerializerScript.parse_slot_cell(item)
			if parsed.size() >= 2 and int(parsed[0]) == int(cell[0]) and int(parsed[1]) == int(cell[1]):
				return true
	return false


func _check_generated_fill() -> bool:
	var generator = ShipLayoutGeneratorScript.new()
	var bp = ShipBlueprintScript.new(ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.DAMAGED, 42)
	var layout: Dictionary = generator.generate(bp, {"template": "spine"})
	if layout.is_empty():
		return _fail("generated layout empty")
	var rooms: Array = layout.get("rooms", [])
	var has_zones: bool = false
	for room_v in rooms:
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var iz: Variant = (room_v as Dictionary).get("interior_zones", {})
		if iz is Dictionary and not (iz as Dictionary).is_empty():
			has_zones = true
			break
	if not has_zones:
		return _fail("generated layout missing interior_zones")
	var builder = GameplaySliceBuilderScript.new()
	var slice: Dictionary = builder.build(layout)
	var loot: Array = slice.get("loot_containers", [])
	if loot.is_empty():
		return _fail("generated slice has no loot")
	var loot_on_slot: bool = false
	var floor_dump: bool = false
	for loot_v in loot:
		if typeof(loot_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = loot_v
		var rid: String = str(row.get("room_id", ""))
		var room: Dictionary = _room_by_id(rooms, rid)
		var approach: Array = row.get("approach_cell", [])
		var first: Array = _first_floor_xz(room)
		var on_slot: bool = _cell_in_slots(room, approach)
		if on_slot:
			loot_on_slot = true
		elif first.size() >= 2 and approach.size() >= 2 and int(approach[0]) == int(first[0]) and int(approach[1]) == int(first[1]):
			floor_dump = true
	if not loot_on_slot:
		return _fail("generated loot not on interior_zones slots")
	if floor_dump:
		return _fail("generated loot dumped on first floor_cell")
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		return _fail("catalog load generated")
	var occupied: Dictionary = {}
	for loot_v2 in loot:
		if typeof(loot_v2) != TYPE_DICTIONARY:
			continue
		var row2: Dictionary = loot_v2
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(row2.get("approach_cell", []))
		if parsed.size() >= 2:
			occupied["%s|%d|%d" % [str(row2.get("room_id", "")), int(parsed[0]), int(parsed[1])]] = true
	var place = ComponentPlacementStateScript.new()
	place.populate(layout, cat, 42, occupied)
	var components_on_cell: bool = false
	for entry_v in place.placed:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry_v
		var parsed_c: Array = LayoutSerializerScript.parse_slot_cell(e.get("cell", null))
		if parsed_c.size() < 2:
			continue
		var room_c: Dictionary = _room_by_id(rooms, str(e.get("room_id", "")))
		if _cell_in_slots(room_c, parsed_c):
			components_on_cell = true
			break
	if not components_on_cell:
		return _fail("generated components not on slot cells")
	return true


func _check_dressing_props() -> bool:
	var cargo: Dictionary = _synthetic_room()
	var layout: Dictionary = {
		"program_id": "procgen-derelict-seed-42",
		"prototype": {"start_room": "airlock_01", "goal_room": "bridge_01"},
		"rooms": [cargo],
		"cell_size": 4.0,
		"structural_plan": {
			"floor_placements": [
				{"cell_key": "0|1|0", "room_id": "cargo_01", "world_position": [4.0, 0.0, 0.0]},
				{"cell_key": "0|2|0", "room_id": "cargo_01", "world_position": [8.0, 0.0, 0.0]},
				{"cell_key": "0|0|1", "room_id": "cargo_01", "world_position": [0.0, 0.0, 4.0]},
				{"cell_key": "0|1|1", "room_id": "cargo_01", "world_position": [4.0, 0.0, 4.0]},
			],
		},
	}
	var loader: Node3D = GeneratedShipLoaderScript.new()
	get_root().add_child(loader)
	loader.layout_doc = layout
	loader.gameplay_doc = {
		"start_room": "airlock_01",
		"loot_containers": [{
			"id": "loot_cargo_01",
			"room_id": "cargo_01",
			"approach_cell": [1, 1, 0],
		}],
	}
	loader.loot_container_specs = [{
		"id": "loot_cargo_01",
		"room_id": "cargo_01",
		"approach_cell": [1, 1, 0],
	}]
	loader._build_room_variant_descriptors()
	if loader.room_variant_descriptors.is_empty():
		loader.free()
		return _fail("dressing descriptors empty for biomatter_crusted")
	var root := Node3D.new()
	get_root().add_child(root)
	loader._apply_dressing_visuals(layout, root)
	var dressing_root: Node = root.get_node_or_null("DressingVisuals")
	if dressing_root == null:
		root.free()
		loader.free()
		return _fail("DressingVisuals missing")
	if dressing_root.get_node_or_null("DressingLight_cargo_01") == null:
		root.free()
		loader.free()
		return _fail("dressing light left room center missing")
	var prop_count: int = 0
	var bad_name: bool = false
	for child in dressing_root.get_children():
		var n: String = str(child.name)
		if n.begins_with("DressingProp_cargo_01_"):
			prop_count += 1
			if str(child.get_meta("collision_policy", "")) != "none_visual_only":
				root.free()
				loader.free()
				return _fail("dressing prop missing none_visual_only")
			if child is CollisionObject3D:
				root.free()
				loader.free()
				return _fail("dressing prop has collision body")
		if n.begins_with("ObjectiveAffordance_") or n.begins_with("BlockedAffordance_"):
			bad_name = true
	root.free()
	loader.free()
	if bad_name:
		return _fail("dressing used ReadabilityPropFactory names")
	if prop_count < 1:
		return _fail("no DressingProp_cargo_01_* instances")
	return true
