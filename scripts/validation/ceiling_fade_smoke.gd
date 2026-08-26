extends SceneTree
## Zomboid-style ceiling fade smoke.
## Marker: CEILING FADE PASS near_visible=N far_hidden=M

const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"

func _initialize():
	assert(ClassDB.class_exists("DerelictGenerator"), "extension not loaded")
	var gen = ClassDB.instantiate("DerelictGenerator")
	var params = {"archetype_id": "shuttle", "intactness_override": 9500}
	var layout_doc = JSON.parse_string(str(gen.export_layout_json(42, params, "ship_structural_v0"))) as Dictionary
	var gameplay_doc = JSON.parse_string(str(gen.export_gameplay_slice_json(42, params))) as Dictionary
	var kit_doc = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH)) as Dictionary

	var loader = preload("res://scripts/procgen/generated_ship_loader.gd").new()
	root.add_child(loader)
	var ok = loader.load_from_documents(layout_doc, kit_doc, gameplay_doc, false)
	assert(ok, "load_from_documents must succeed")

	var ceilings := _collect_ceilings(loader)
	assert(ceilings.size() > 0, "loader must produce ceiling nodes (prefix Ceiling_)")

	var player := Node3D.new()
	player.name = "SmokePlayer"
	root.add_child(player)

	# Teleport player near the first ceiling
	player.global_position = ceilings[0].global_position + Vector3(2.0, 0.0, 2.0)

	var controller_script := load("res://scripts/procgen/ceiling_fade_controller.gd")
	assert(controller_script != null, "controller script must exist")

	var controller = controller_script.new()
	root.add_child(controller)
	controller.configure(loader, player)

	# Step a few frames
	var frames := 0
	var t := 0.0
	while frames < 3:
		t += 1.0 / 60.0
		controller._process(t)
		frames += 1

	var near_visible := 0
	var far_hidden := 0
	var player_pos: Vector3 = player.global_position
	for c in ceilings:
		var d: float = c.global_position.distance_to(player_pos)
		if d <= 12.0:
			if c.visible:
				near_visible += 1
		else:
			if not c.visible:
				far_hidden += 1

	print("CEILING FADE PASS near_visible=", near_visible, " far_hidden=", far_hidden)
	quit(0)


func _collect_ceilings(node: Node) -> Array:
	var out: Array = []
	if node is Node3D and (node as Node3D).name.begins_with("Ceiling_"):
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_ceilings(child))
	return out