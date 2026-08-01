extends RefCounted
class_name RuntimePropVisualBinder

const SCENE_PATH_PREFIX: String = "res://assets/imported/props/"
const IMPORTED_VISUAL_NAME: String = "ImportedVisual"
const BINDING_DOCUMENT_KIND: String = "prop_visual_binding"
const COLLISION_POLICY: String = "none_visual_only"
const BINDING_FIELDS: Array[String] = [
	"asset_id", "binding", "bounds", "collision_policy", "document_kind", "extensions",
	"placement", "prop_kind", "provenance", "schema_version", "source", "visual_scene_path",
]
const BINDING_META_FIELDS: Array[String] = ["namespace", "ids"]
const PLACEMENT_FIELDS: Array[String] = ["origin", "offset_m", "rotation_degrees", "allowed_yaw_deg", "scale"]
const SOURCE_FIELDS: Array[String] = ["sha256", "byte_size", "mesh_count", "gltf_version"]
const BOUNDS_FIELDS: Array[String] = ["local_min_m", "local_max_m"]
const PROVENANCE_FIELDS: Array[String] = ["license_state", "source_platform"]
const ALLOWED_ORIGINS: Array[String] = ["scene_origin", "marker_anchor"]
const ALLOWED_SURFACES: Array[String] = ["floor", "wall", "ceiling"]
const INTERACTABLE_SCRIPT: Script = preload("res://scripts/interaction/interactable.gd")
const OBJECTIVE_VOLUME_SCRIPT: Script = preload("res://scripts/procgen/gameplay_objective_volume.gd")
const FORBIDDEN_SCRIPT_PATHS: Array[String] = [
	"res://scripts/interaction/interactable.gd",
	"res://scripts/procgen/gameplay_objective_volume.gd",
	"res://scripts/procgen/procgen_debug_runner.gd",
]
const FORBIDDEN_SCRIPT_METHODS: Array[String] = [
	"_ready", "_process", "_physics_process", "_input", "_unhandled_input",
	"_unhandled_key_input", "_notification", "start_run", "try_interact",
	"configure", "configure_from_objective", "configure_from_step", "complete",
	"set_active", "set_validation_player_in_range",
]
const FORBIDDEN_SCRIPT_SIGNALS: Array[String] = [
	"interaction_completed", "objective_completed", "objective_reached", "run_completed", "run_failed",
]
const IMPORTED_ROOT_META: String = "_runtime_prop_visual_imported"
const GODOT_GLTF_META_KEYS: Array[String] = [
	"gltf_imported", "gltf_source", "gltf_node", "gltf_parent",
]
const IMPORTER_SCRIPT_PREFIXES: Array[String] = [
	"res://.godot/imported/",
	"res://assets/imported/",
	"res://addons/godot_gltf/",
	"res://addons/godot-gltf/",
	"res://addons/gltf/",
]


static func mount_component_visual(marker: Node3D, binding: Dictionary) -> bool:
	if marker == null or binding.is_empty():
		return false
	if not _is_safe_binding(binding, "component"):
		return false
	if _has_imported_visual(marker):
		return false
	var visual: Node3D = _create_imported_visual(binding)
	if visual == null:
		return false
	marker.add_child(visual)
	return true


static func create_objective_visual(binding: Dictionary) -> Node3D:
	if binding.is_empty():
		return null
	if not _is_safe_binding(binding, "objective"):
		return null
	return _create_imported_visual(binding)


static func _instantiate_visual_scene(path: String) -> Node:
	if not FileAccess.file_exists(path):
		return null
	# Prefer Godot's imported PackedScene when the editor/import preflight has
	# populated the current state. Protected state-isolated smokes may not retain
	# that generated cache between invocations, so load the canonical GLB directly
	# as the deterministic fallback instead of treating a valid asset as missing.
	if ResourceLoader.exists(path, "PackedScene"):
		var packed: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed != null:
			return packed.instantiate()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		return null
	return document.generate_scene(state)


static func clear_imported_visuals(root: Node) -> void:
	if root == null:
		return
	for child_variant in root.get_children():
		var child: Node = child_variant as Node
		if child == null:
			continue
		if str(child.get_meta("visual_source", "")) == "imported":
			root.remove_child(child)
			child.free()
			continue
		clear_imported_visuals(child)


static func validate_visual_tree(root: Node) -> bool:
	return _validate_visual_tree(root, false)


static func _validate_visual_tree(root: Node, inherited_import_provenance: bool) -> bool:
	if root == null:
		return false
	if _is_forbidden_visual_node(root):
		return false
	var imported_provenance: bool = inherited_import_provenance or _has_import_provenance(root)
	if _has_forbidden_visual_behavior(root, imported_provenance):
		return false
	for child_variant in root.get_children():
		var child: Node = child_variant as Node
		if child == null or not _validate_visual_tree(child, imported_provenance):
			return false
	return true


static func _create_imported_visual(binding: Dictionary) -> Node3D:
	if not _is_safe_binding(binding, str(binding.get("prop_kind", ""))):
		return null
	var path: String = str(binding["visual_scene_path"])
	var instance: Node = _instantiate_visual_scene(path)
	if instance == null:
		return null
	var visual: Node3D = instance as Node3D
	if visual == null:
		instance.free()
		return null
	# The marker is trusted only because this node came from a canonical binding
	# path. It lets the validator distinguish importer-owned script resources from
	# arbitrary user scripts while the behavior denylist remains authoritative.
	visual.set_meta(IMPORTED_ROOT_META, path)
	if not validate_visual_tree(visual):
		visual.free()
		return null
	if not _apply_transform(visual, binding):
		visual.free()
		return null
	visual.name = IMPORTED_VISUAL_NAME
	visual.set_meta("visual_source", "imported")
	return visual


static func _is_safe_binding(binding: Dictionary, expected_prop_kind: String) -> bool:
	if not _has_exact_fields(binding, BINDING_FIELDS):
		return false
	if not _is_exact_schema_version(binding.get("schema_version")):
		return false
	if binding.get("document_kind", "") != BINDING_DOCUMENT_KIND:
		return false
	if binding.get("collision_policy", "") != COLLISION_POLICY:
		return false
	if binding.get("prop_kind", "") != expected_prop_kind:
		return false
	if not _is_asset_id(binding.get("asset_id")):
		return false
	var expected_namespace: String = {
		"component": "component_id",
		"objective": "gameplay_placement_id",
	}.get(expected_prop_kind, "")
	if expected_namespace.is_empty():
		return false
	var binding_meta: Variant = binding.get("binding")
	if not _has_exact_fields(binding_meta, BINDING_META_FIELDS):
		return false
	var binding_dictionary: Dictionary = binding_meta as Dictionary
	if binding_dictionary.get("namespace", "") != expected_namespace:
		return false
	var ids_value: Variant = binding_dictionary.get("ids")
	if not (ids_value is Array) or (ids_value as Array).is_empty():
		return false
	var ids: Array = ids_value as Array
	var seen_ids: Dictionary = {}
	for id_value in ids:
		if typeof(id_value) != TYPE_STRING or str(id_value).strip_edges().is_empty():
			return false
		var id: String = str(id_value)
		if seen_ids.has(id):
			return false
		seen_ids[id] = true
	if expected_prop_kind == "component":
		var asset_id: Variant = binding.get("asset_id")
		if typeof(asset_id) != TYPE_STRING or ids.size() != 1 or ids[0] != asset_id:
			return false
	var scene_path: Variant = binding.get("visual_scene_path", "")
	if not _is_canonical_scene_path(scene_path, expected_prop_kind + "s"):
		return false
	if str(scene_path).get_file().trim_suffix(".glb") != str(binding.get("asset_id", "")):
		return false
	if not _is_valid_placement(binding.get("placement"), expected_prop_kind):
		return false
	if not _is_valid_source(binding.get("source")):
		return false
	if not _is_valid_bounds(binding.get("bounds")):
		return false
	if not _is_valid_provenance(binding.get("provenance")):
		return false
	return binding.get("extensions") is Dictionary


static func _is_canonical_scene_path(value: Variant, expected_group: String = "") -> bool:
	if typeof(value) != TYPE_STRING or str(value).is_empty():
		return false
	var path: String = str(value)
	if not path.begins_with(SCENE_PATH_PREFIX) or path.simplify_path() != path:
		return false
	var relative: String = path.substr(SCENE_PATH_PREFIX.length())
	var parts: PackedStringArray = relative.split("/")
	if parts.size() != 2 or not ["components", "objectives", "dressing"].has(parts[0]):
		return false
	if not expected_group.is_empty() and parts[0] != expected_group:
		return false
	if parts[1].is_empty() or parts[1] == ".glb" or not parts[1].ends_with(".glb"):
		return false
	return not parts.has("") and not parts.has(".") and not parts.has("..")


static func _is_valid_placement(placement_value: Variant, expected_prop_kind: String) -> bool:
	if not (placement_value is Dictionary):
		return false
	var placement: Dictionary = placement_value as Dictionary
	var expected_fields: Array[String] = PLACEMENT_FIELDS.duplicate()
	if expected_prop_kind == "objective":
		expected_fields.append("surface")
	for key in placement.keys():
		if not expected_fields.has(str(key)):
			return false
	if expected_prop_kind == "component" and placement.has("surface"):
		return false
	if placement.size() < PLACEMENT_FIELDS.size() or placement.size() > expected_fields.size():
		return false
	for field_name in PLACEMENT_FIELDS:
		if not placement.has(field_name):
			return false
	if placement.has("surface") and not ALLOWED_SURFACES.has(placement.get("surface")):
		return false
	if not ALLOWED_ORIGINS.has(placement.get("origin")):
		return false
	if not placement.has("offset_m") or not placement.has("rotation_degrees") or not placement.has("scale"):
		return false
	if not _is_finite_vector(placement["offset_m"]):
		return false
	if not _is_finite_vector(placement["rotation_degrees"]):
		return false
	if not _is_finite_number(placement["scale"]) or float(placement["scale"]) <= 0.0:
		return false
	var yaw_values: Variant = placement["allowed_yaw_deg"]
	if not (yaw_values is Array) or (yaw_values as Array).is_empty():
		return false
	var seen_yaws: Dictionary = {}
	for yaw in yaw_values as Array:
		if not _is_finite_number(yaw):
			return false
		var yaw_number: float = float(yaw)
		if seen_yaws.has(yaw_number):
			return false
		seen_yaws[yaw_number] = true
	return true


static func _is_valid_source(source_value: Variant) -> bool:
	if not _has_exact_fields(source_value, SOURCE_FIELDS):
		return false
	var source: Dictionary = source_value as Dictionary
	if not _is_sha256(source.get("sha256")):
		return false
	if not _is_nonnegative_integer_value(source.get("byte_size")):
		return false
	if not _is_positive_integer_value(source.get("mesh_count")):
		return false
	return source.get("gltf_version") == "2.0"


static func _is_valid_bounds(bounds_value: Variant) -> bool:
	if not _has_exact_fields(bounds_value, BOUNDS_FIELDS):
		return false
	var bounds: Dictionary = bounds_value as Dictionary
	var local_min: Variant = bounds.get("local_min_m")
	var local_max: Variant = bounds.get("local_max_m")
	if not _is_finite_vector(local_min) or not _is_finite_vector(local_max):
		return false
	var min_values: Array = local_min as Array
	var max_values: Array = local_max as Array
	for index in 3:
		if float(min_values[index]) > float(max_values[index]):
			return false
	return true


static func _is_valid_provenance(provenance_value: Variant) -> bool:
	if not _has_exact_fields(provenance_value, PROVENANCE_FIELDS):
		return false
	var provenance: Dictionary = provenance_value as Dictionary
	return _is_nonempty_string(provenance.get("license_state")) \
		and _is_nonempty_string(provenance.get("source_platform"))


static func _has_exact_fields(value: Variant, expected_fields: Array[String]) -> bool:
	if not (value is Dictionary):
		return false
	var object_value: Dictionary = value as Dictionary
	if object_value.size() != expected_fields.size():
		return false
	for key in object_value.keys():
		if not expected_fields.has(str(key)):
			return false
	for field_name in expected_fields:
		if not object_value.has(field_name):
			return false
	return true


static func _is_exact_schema_version(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var parts: PackedStringArray = str(value).split(".")
	return parts.size() == 3 and parts[0] == "1" \
		and _is_semver_number(parts[1]) and _is_semver_number(parts[2])


static func _is_semver_number(value: String) -> bool:
	if value.is_empty() or (value.length() > 1 and value.begins_with("0")):
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return true


static func _is_asset_id(value: Variant) -> bool:
	if not _is_nonempty_string(value):
		return false
	var identifier: String = str(value)
	for index in identifier.length():
		var code: int = identifier.unicode_at(index)
		var is_lowercase_letter: bool = code >= 97 and code <= 122
		var is_digit: bool = code >= 48 and code <= 57
		if index == 0 and not is_lowercase_letter and not is_digit:
			return false
		if not is_lowercase_letter and not is_digit and code != 95 and code != 45:
			return false
	return true


static func _is_nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty()


static func _is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).length() != 64 or str(value) == "0".repeat(64):
		return false
	for index in str(value).length():
		var code: int = str(value).unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _is_nonnegative_integer_value(value: Variant) -> bool:
	if not _is_finite_number(value):
		return false
	var number: float = float(value)
	return number >= 0.0 and is_equal_approx(number, round(number))


static func _is_positive_integer_value(value: Variant) -> bool:
	if not _is_finite_number(value):
		return false
	var number: float = float(value)
	return number >= 1.0 and is_equal_approx(number, round(number))


static func _apply_transform(visual: Node3D, binding: Dictionary) -> bool:
	var placement_value: Variant = binding.get("placement")
	if not _is_valid_placement(placement_value, str(binding.get("prop_kind", ""))):
		return false
	var placement: Dictionary = placement_value as Dictionary
	var offset_result: Dictionary = _read_finite_vector(placement["offset_m"])
	var rotation_result: Dictionary = _read_finite_vector(placement["rotation_degrees"])
	if not bool(offset_result.get("valid", false)) or not bool(rotation_result.get("valid", false)):
		return false
	var uniform_scale: float = float(placement["scale"])
	visual.position = offset_result["value"]
	visual.rotation_degrees = rotation_result["value"]
	visual.scale = Vector3.ONE * uniform_scale
	return true


static func _read_finite_vector(value: Variant) -> Dictionary:
	if not (value is Array):
		return {"valid": false}
	var values: Array = value as Array
	if values.size() != 3:
		return {"valid": false}
	for item in values:
		if not _is_finite_number(item):
			return {"valid": false}
	return {
		"valid": true,
		"value": Vector3(float(values[0]), float(values[1]), float(values[2])),
	}


static func _is_finite_vector(value: Variant) -> bool:
	return bool(_read_finite_vector(value).get("valid", false))


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func _is_forbidden_visual_node(node: Node) -> bool:
	return node is CollisionObject3D \
		or node is CollisionShape3D \
		or node is CollisionPolygon3D \
		or node is Area3D \
		or node is NavigationRegion3D \
		or node is NavigationObstacle3D \
		or node is NavigationAgent3D \
		or node is NavigationLink3D \
		or node is RayCast3D \
		or node is ShapeCast3D \
		or node is SpringArm3D \
		or node is Joint3D


static func _has_forbidden_visual_behavior(node: Node, imported_provenance: bool) -> bool:
	if _is_interaction_node(node):
		return true
	var attached_script: Variant = node.get_script()
	if attached_script == null:
		return false
	if not (attached_script is Script):
		return true
	var script: Script = attached_script as Script
	if not _is_allowed_import_script(node, script, imported_provenance):
		return true
	return _has_forbidden_script_behavior(node, script)


static func _is_allowed_import_script(node: Node, script: Script, imported_provenance: bool) -> bool:
	if not imported_provenance and not _has_import_provenance(node):
		return false
	var script_path: String = str(script.resource_path)
	if script_path.is_empty():
		return true
	for prefix in IMPORTER_SCRIPT_PREFIXES:
		if script_path.begins_with(prefix):
			return true
	return false


static func _has_import_provenance(node: Node) -> bool:
	if node.has_meta(IMPORTED_ROOT_META):
		return true
	for metadata_key in GODOT_GLTF_META_KEYS:
		if node.has_meta(metadata_key):
			return true
	return false


static func _has_forbidden_script_behavior(node: Node, script: Script) -> bool:
	var script_path: String = str(script.resource_path)
	if FORBIDDEN_SCRIPT_PATHS.has(script_path) or script_path.begins_with("res://scripts/"):
		return true
	for method_variant in script.get_script_method_list():
		if not (method_variant is Dictionary):
			continue
		var method_name: String = str((method_variant as Dictionary).get("name", ""))
		if FORBIDDEN_SCRIPT_METHODS.has(method_name):
			return true
	for signal_variant in script.get_script_signal_list():
		if not (signal_variant is Dictionary):
			continue
		var signal_name: String = str((signal_variant as Dictionary).get("name", ""))
		if FORBIDDEN_SCRIPT_SIGNALS.has(signal_name):
			return true
	for signal_variant in node.get_signal_list():
		if not (signal_variant is Dictionary):
			continue
		var signal_name: String = str((signal_variant as Dictionary).get("name", ""))
		if FORBIDDEN_SCRIPT_SIGNALS.has(signal_name):
			return true
	return false


static func _is_interaction_node(node: Node) -> bool:
	if node is Area3D:
		return true
	var attached_script: Variant = node.get_script()
	return attached_script == INTERACTABLE_SCRIPT \
		or attached_script == OBJECTIVE_VOLUME_SCRIPT \
		or node.has_meta("interaction_id") \
		or node.has_meta("objective_id")


static func _has_imported_visual(root: Node) -> bool:
	if root == null:
		return false
	for child_variant in root.get_children():
		var child: Node = child_variant as Node
		if child == null:
			continue
		if child.name == IMPORTED_VISUAL_NAME or str(child.get_meta("visual_source", "")) == "imported":
			return true
		if _has_imported_visual(child):
			return true
	return false
