extends SceneTree
## Static analysis smoke: scan scripts/systems/ for Vector3 usage in loop bodies.
## If any Vector3 math exists in the simulation core, the pivot will break it.
## Run: godot --headless --script res://scripts/validation/sim_vector3_smoke.gd

var _pass_count: int = 0
var _fail_count: int = 0
var _scan_dir: String = "res://scripts/systems/"


func _init() -> void:
	print("\n--- Sim Vector3 static analysis ---")
	var findings := _scan_for_vector3(_scan_dir)
	for finding in findings:
		_fail_count += 1
		print("  FAIL  Vector3 found: ", finding)
	if findings.is_empty():
		_pass_count += 1
		print("  PASS  No Vector3 usage in scripts/systems/")

	print("\n========================================")
	print("Sim Vector3 smoke: %d PASS / %d FAIL" % [_pass_count, _fail_count])
	print("========================================")
	quit(0 if _fail_count == 0 else 1)


func _scan_for_vector3(dir_path: String) -> Array[String]:
	var results: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return results
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				results.append_array(_scan_for_vector3(full_path + "/"))
		elif file_name.ends_with(".gd") and not file_name.ends_with(".gd.uid"):
			var findings := _check_file_for_vector3(full_path)
			results.append_array(findings)
		file_name = dir.get_next()
	dir.list_dir_end()
	return results


func _check_file_for_vector3(path: String) -> Array[String]:
	var results: Array[String] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return results
	var line_no := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_no += 1
		# Check for Vector3 usage (not in comments)
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if "Vector3" in line:
			results.append("%s:%d — %s" % [path, line_no, stripped])
	return results
