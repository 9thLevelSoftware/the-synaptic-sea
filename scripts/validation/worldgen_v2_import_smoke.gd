extends SceneTree
## Acceptance gate for the worldgen v2 generator: load a worldgen-exported
## layout.json + gameplay_slice.json through the UNMODIFIED GeneratedShipLoader
## (which re-runs StructuralPlanValidator and preflights every wrapper scene).
##
## Export first:
##   cd D:\world_gen && cargo run -p derelict_cli -- --seed 17 --archetype corvette --export-dir target\export
## Then run:
##   godot --headless --path . --script res://scripts/validation/worldgen_v2_import_smoke.gd
## Optionally set WORLDGEN_EXPORT_DIR to point at a different export.
##
## PASS marker: WORLDGEN V2 IMPORT PASS

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")

func _initialize() -> void:
	var export_dir := OS.get_environment("WORLDGEN_EXPORT_DIR")
	if export_dir.is_empty():
		export_dir = "D:/world_gen/target/export"
	var layout_path := export_dir + "/layout.json"
	var slice_path := export_dir + "/gameplay_slice.json"
	var kit_path := "res://data/kits/ship_structural_v0.json"

	if not FileAccess.file_exists(layout_path):
		push_error("WORLDGEN V2 IMPORT FAIL: missing %s (run the worldgen export first)" % layout_path)
		quit(1)
		return

	var loader: Node3D = LoaderScript.new()
	root.add_child(loader)
	var ok: bool = loader.load_from_paths(layout_path, kit_path, slice_path, true)
	if not ok:
		push_error("WORLDGEN V2 IMPORT FAIL: GeneratedShipLoader rejected the worldgen layout")
		quit(1)
		return

	# Count what actually got instantiated.
	var structural := 0
	var stack: Array[Node] = [loader as Node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.has_meta("structural_kind"):
			structural += 1
	var layout_doc: Dictionary = loader.layout_doc if "layout_doc" in loader else {}
	var rooms: int = (layout_doc.get("rooms", []) as Array).size()
	print("WORLDGEN V2 IMPORT PASS rooms=%d structural_nodes=%d" % [rooms, structural])
	quit(0)
