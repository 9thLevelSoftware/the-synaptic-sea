extends SceneTree
## BSA-019: headless MeshLibrary + GridMap smoke validator.
##
## Usage (relative to the project root that contains the produced .tres and
## sidecar):
##
##   /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
##       --path /Users/christopherwilloughby/the-sargasso-of-stars \
##       --script res://scripts/validation/gridmap_meshlibrary_smoke.gd -- \
##       /abs/path/to/ship_structural_v0.tres /abs/path/to/ship_structural_v0.sidecar.json
##
## The script:
##   1. Loads the MeshLibrary .tres and reads the sidecar JSON.
##   2. Asserts every sidecar entry has a matching MeshLibrary item by name.
##   3. Instantiates a GridMap, sets its cell_size to the kit's 4.0 m grid,
##      and places 2-3 representative cells.
##   4. Reports MeshLibrary item names plus GridMap.get_cell_item() results.
##   5. Emits a JSON validation report next to the .tres and exits 0 on
##      success or non-zero with a clear error message on failure.

const PLACED_CELLS: Array = [
	[Vector3i(0, 0, 0), 0],
	[Vector3i(1, 0, 0), 0],
	[Vector3i(0, 0, 1), 3],
]

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: godot --headless --script res://scripts/validation/gridmap_meshlibrary_smoke.gd -- <tres_path> <sidecar_path>")
		quit(1)
		return

	var tres_path: String = args[0]
	var sidecar_path: String = args[1]

	var tres_abs: String = _resolve_path(tres_path)
	var sidecar_abs: String = _resolve_path(sidecar_path)

	if not FileAccess.file_exists(tres_abs):
		push_error("tres not found: %s" % tres_abs)
		quit(2)
		return
	if not FileAccess.file_exists(sidecar_abs):
		push_error("sidecar not found: %s" % sidecar_abs)
		quit(2)
		return

	var library_res: Resource = load(tres_abs)
	if library_res == null:
		push_error("could not load resource at %s" % tres_abs)
		quit(3)
		return
	if not (library_res is MeshLibrary):
		push_error("expected MeshLibrary, got %s at %s" % [library_res.get_class(), tres_abs])
		quit(3)
		return

	var library: MeshLibrary = library_res
	var sidecar_text: String = FileAccess.get_file_as_string(sidecar_abs)
	var sidecar: Variant = JSON.parse_string(sidecar_text)
	if typeof(sidecar) != TYPE_DICTIONARY:
		push_error("sidecar is not a JSON object at %s" % sidecar_abs)
		quit(4)
		return
	var sidecar_dict: Dictionary = sidecar

	var expected_cell_size: float = float(sidecar_dict.get("cell_size_m", -1.0))
	var expected_entries: Array = sidecar_dict.get("entries", [])
	if expected_cell_size <= 0.0:
		push_error("sidecar missing or invalid cell_size_m: %s" % sidecar_abs)
		quit(4)
		return
	if typeof(expected_entries) != TYPE_ARRAY or expected_entries.is_empty():
		push_error("sidecar missing entries array at %s" % sidecar_abs)
		quit(4)
		return

	var reported_item_ids: PackedInt32Array = library.get_item_list()
	var reported_names: Array = []
	var name_to_id: Dictionary = {}
	for item_id in reported_item_ids:
		var item_name: String = library.get_item_name(item_id)
		reported_names.append(item_name)
		name_to_id[item_name] = item_id

	var matched_entries: Array = []
	var missing_entries: Array = []
	for entry in expected_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("sidecar entry is not a dictionary: %s" % str(entry))
			quit(5)
			return
		var entry_name: String = str(entry.get("name", ""))
		var entry_id: int = int(entry.get("item_id", -1))
		if not name_to_id.has(entry_name):
			missing_entries.append(entry_name)
			continue
		var mesh: Mesh = library.get_item_mesh(name_to_id[entry_name])
		var shapes: Array = library.get_item_shapes(name_to_id[entry_name])
		var mesh_ok: bool = mesh != null and mesh.get_class() == "BoxMesh"
		var shape_ok: bool = (shapes.size() == 2) and (shapes[0] is BoxShape3D) and (shapes[1] is Transform3D)
		matched_entries.append({
			"module_id": str(entry.get("module_id", "")),
			"name": entry_name,
			"expected_item_id": entry_id,
			"actual_item_id": int(name_to_id[entry_name]),
			"mesh_resource_type": mesh.get_class() if mesh != null else "<null>",
			"shape_count": shapes.size(),
			"shape_resource_type": (shapes[0] as Resource).get_class() if (shapes.size() >= 1 and shapes[0] != null) else "<null>",
			"mesh_ok": mesh_ok,
			"shape_ok": shape_ok,
		})
		if not mesh_ok or not shape_ok:
			push_error("entry %s has wrong mesh/shape types (mesh=%s, shape_count=%d)" % [entry_name, mesh.get_class() if mesh != null else "<null>", shapes.size()])
			quit(6)
			return

	if not missing_entries.is_empty():
		push_error("MeshLibrary is missing expected items: %s" % str(missing_entries))
		quit(7)
		return

	var gridmap: GridMap = GridMap.new()
	gridmap.cell_size = Vector3(expected_cell_size, expected_cell_size, expected_cell_size)
	gridmap.mesh_library = library

	var placed_results: Array = []
	for placement in PLACED_CELLS:
		var cell: Vector3i = placement[0]
		var item_id: int = int(placement[1])
		gridmap.set_cell_item(cell, item_id, 0)
		var got_id: int = gridmap.get_cell_item(cell)
		var got_orient: int = gridmap.get_cell_item_orientation(cell)
		placed_results.append({
			"cell": [cell.x, cell.y, cell.z],
			"requested_item_id": item_id,
			"requested_module_id": str(expected_entries[item_id].get("module_id", "")),
			"actual_item_id": got_id,
			"actual_orient": got_orient,
			"placement_ok": got_id == item_id,
		})
		if got_id != item_id:
			push_error("GridMap.get_cell_item() at %s returned %d, expected %d" % [str(cell), got_id, item_id])
			gridmap.free()
			quit(8)
			return

	gridmap.free()

	var report: Dictionary = {
		"schema_version": "1.0.0",
		"document_kind": "mesh_library_smoke_validation_report",
		"status": "ok",
		"tres_path": tres_abs,
		"sidecar_path": sidecar_abs,
		"cell_size_m": expected_cell_size,
		"expected_entry_count": expected_entries.size(),
		"reported_item_count": reported_item_ids.size(),
		"reported_item_names": reported_names,
		"matched_entries": matched_entries,
		"placed_cells": placed_results,
		"verdict": "MeshLibrary smoke created, loaded, and consumed by GridMap; names and collisions are present.",
	}

	var report_path: String = tres_abs.get_basename() + ".validation.json"
	var report_file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		push_error("could not open validation report at %s" % report_path)
		quit(9)
		return
	report_file.store_string(JSON.stringify(report, "  "))
	report_file.close()

	print("MeshLibrary smoke validation report: %s" % report_path)
	print("  cell_size_m = %.4f" % expected_cell_size)
	print("  expected_entry_count = %d" % expected_entries.size())
	print("  reported_item_count = %d" % reported_item_ids.size())
	print("  placed_cells = %d" % placed_results.size())
	print("  verdict: %s" % report["verdict"])
	quit(0)


func _resolve_path(raw_path: String) -> String:
	if raw_path.begins_with("res://") or raw_path.begins_with("user://"):
		return ProjectSettings.globalize_path(raw_path)
	if raw_path.is_absolute_path():
		return raw_path
	var cwd: String = OS.get_environment("PWD")
	if not cwd.is_empty():
		var cwd_path: String = cwd.path_join(raw_path)
		if FileAccess.file_exists(cwd_path):
			return cwd_path
	return ProjectSettings.globalize_path("res://%s" % raw_path)
