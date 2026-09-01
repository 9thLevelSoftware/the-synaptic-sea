extends SceneTree

## Marker: BUILDER PLACED PROPS PASS

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const LAYOUT_PATH := "res://data/procgen/golden/coherent_ship_001/layout.json"
const KIT_PATH := "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_PATH := "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"


func _initialize() -> void:
	var layout: Dictionary = _json(LAYOUT_PATH)
	var kit: Dictionary = _json(KIT_PATH)
	var gameplay: Dictionary = _json(GAMEPLAY_PATH)
	var rooms: Array = layout.get("rooms", [])
	var floors: Array = layout.get("structural_plan", {}).get("floor_placements", [])
	if rooms.is_empty() or floors.is_empty():
		_fail("coherent fixture has no room/floor")
		return
	var room_id := str((rooms[0] as Dictionary).get("id", ""))
	var floor: Dictionary = floors[0] as Dictionary
	var cell: Array = floor.get("cell", [0, 0])
	var deck := int(floor.get("deck", 0))
	var second_cell: Array = cell
	var second_deck: int = deck
	for floor_variant in floors:
		if floor_variant is Dictionary and str((floor_variant as Dictionary).get("room_id", "")) == room_id:
			var candidate: Array = (floor_variant as Dictionary).get("cell", [])
			if candidate.size() >= 2 and (int(candidate[0]) != int(cell[0]) or int(candidate[1]) != int(cell[1])):
				second_cell = candidate
				second_deck = int((floor_variant as Dictionary).get("deck", deck))
				break
	gameplay["placed_props"] = [
		{
			"id": "builder_workbench_01",
			"kind": "Furniture",
			"visual_id": "workbench",
			"room_id": room_id,
			"cell": [int(cell[0]), int(cell[1]), deck],
			"rotation": 1,
		},
		{
			"id": "builder_container_01",
			"kind": "Container",
			"visual_id": "loot_crate",
			"room_id": room_id,
			"cell": [int(second_cell[0]), int(second_cell[1]), second_deck],
			"rotation": 2,
		},
		{
			"id": "builder_visual_binding_01",
			"kind": "Container",
			"visual_id": "generic_locker",
			"room_id": room_id,
			"cell": [int(cell[0]), int(cell[1]), deck],
			"rotation": 3,
		},
	]

	var loader = LoaderScript.new()
	root.add_child(loader)
	if not loader.load_from_documents(layout, kit, gameplay, true, {
		"layout_path": LAYOUT_PATH, "kit_path": KIT_PATH, "gameplay_slice_path": GAMEPLAY_PATH,
	}):
		_fail("loader rejected augmented gameplay")
		return
	var specs: Array = loader.get_placed_prop_specs_copy()
	var nodes: Array[Node3D] = loader.get_placed_prop_nodes()
	if specs.size() != 3 or nodes.size() != 3:
		_fail("expected three authored props specs=%d nodes=%d errors=%s" % [
			specs.size(), nodes.size(), loader.get_placed_prop_errors(),
		])
		return
	for index in range(3):
		var spec: Dictionary = specs[index]
		var node: Node3D = nodes[index]
		var expected: Vector3 = spec.get("position", Vector3.INF)
		if node.get_meta("placed_prop_id", "") != str(spec.get("id", "")):
			_fail("placement identity was not preserved")
			return
		if node.position.x != expected.x or node.position.z != expected.z:
			_fail("authored cell position was not materialized")
			return
		if not is_equal_approx(node.rotation_degrees.y, float(int(spec.get("quarter_turn", 0)) * 90)):
			_fail("quarter-turn rotation was not materialized")
			return
		if index < 2 and node.get_node_or_null("Mesh") == null:
			_fail("factory visual missing Mesh child")
			return
		if index == 2 and node.get_node_or_null("ImportedVisual") == null:
			_fail("authored visual binding did not materialize its imported GLB")
			return

	loader.clear_loaded_ship()
	if not loader.get_placed_prop_specs_copy().is_empty() or not loader.get_placed_prop_nodes().is_empty():
		_fail("clear_loaded_ship did not clear authored props")
		return
	print("BUILDER PLACED PROPS PASS count=3 furniture=true container=true imported_visual=true position=true rotation=true")
	loader.free()
	quit(0)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _fail(reason: String) -> void:
	push_error("BUILDER PLACED PROPS FAIL %s" % reason)
	quit(1)
