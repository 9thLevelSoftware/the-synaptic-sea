extends SceneTree
## Smoke test: verify GeneratedShipLoader can load a ship using the ithappy kit.

const SEED := 17

func _init() -> void:
	var ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
	var generator: RefCounted = ShipGeneratorScript.new()
	var blueprint = preload("res://scripts/procgen/ship_blueprint.gd").new(0, 1, SEED)
	var layout_gen = generator.layout_generator

	# Generate layout
	var layout: Dictionary = layout_gen.generate(blueprint)
	if layout.is_empty():
		print("ITHAPPY_KIT_SMOKE FAIL: empty layout")
		quit(1)
		return

	# Compile structural plan
	var compiler = preload("res://scripts/procgen/structural_edge_compiler.gd").new()
	var structural_plan: Dictionary = compiler.compile(layout)
	layout["structural_plan"] = structural_plan

	# Write layout to temp
	var temp_dir := "user://procgen_ithappy_smoke"
	if not DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.make_dir_absolute(temp_dir)

	var layout_path := temp_dir + "/layout.json"
	var kit_path := "res://data/kits/ithappy_scifi_v0.json"
	var gameplay_path := temp_dir + "/gameplay_slice.json"

	# Write layout
	var layout_json := JSON.stringify(layout, "  ")
	var f := FileAccess.open(layout_path, FileAccess.WRITE)
	f.store_string(layout_json)
	f.close()

	# Build gameplay slice
	var gameplay_builder = preload("res://scripts/procgen/gameplay_slice_builder.gd").new()
	var gameplay: Dictionary = gameplay_builder.build(layout)
	var gameplay_json := JSON.stringify(gameplay, "  ")
	f = FileAccess.open(gameplay_path, FileAccess.WRITE)
	f.store_string(gameplay_json)
	f.close()

	# Load via GeneratedShipLoader with ithappy kit
	var loader = preload("res://scripts/procgen/generated_ship_loader.gd").new()
	var success: bool = loader.load_from_paths(layout_path, kit_path, gameplay_path)
	if not success:
		print("ITHAPPY_KIT_SMOKE FAIL: loader returned false")
		quit(1)
		return

	# Count instantiated nodes
	var structural_root = loader.get_node_or_null("StructuralRoot")
	var wrapper_count := 0
	if structural_root:
		for child in structural_root.get_children():
			if child is Node3D:
				wrapper_count += 1

	print("ITHAPPY_KIT_SMOKE PASS seed=%d wrappers=%d" % [SEED, wrapper_count])
	quit(0)
