extends RefCounted
class_name RuntimePropVisualBinder

const SCENE_PATH_PREFIX: String = "res://assets/imported/props/"
const IMPORTED_VISUAL_NAME: String = "ImportedVisual"
const BINDING_DOCUMENT_KIND: String = "prop_visual_binding"
const COLLISION_POLICY: String = "none_visual_only"
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
	if root is CollisionObject3D or root is CollisionShape3D or root is Area3D:
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
	if not _is_safe_binding(binding):
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


static func _is_safe_binding(binding: Dictionary) -> bool:
	if binding.get("document_kind", "") != BINDING_DOCUMENT_KIND:
		return false
	if binding.get("collision_policy", "") != COLLISION_POLICY:
		return false
	var scene_path: Variant = binding.get("visual_scene_path", "")
	if not _is_canonical_scene_path(scene_path):
		return false
	return _is_valid_placement(binding.get("placement"))


static func _is_canonical_scene_path(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).is_empty():
		return false
	var path: String = str(value)
	if not path.begins_with(SCENE_PATH_PREFIX) or path.simplify_path() != path:
		return false
	var relative: String = path.substr(SCENE_PATH_PREFIX.length())
	var parts: PackedStringArray = relative.split("/")
	if parts.size() != 2 or not ["components", "objectives", "dressing"].has(parts[0]):
		return false
	if parts[1].is_empty() or parts[1] == ".glb" or not parts[1].ends_with(".glb"):
		return false
	return not parts.has("") and not parts.has(".") and not parts.has("..")


static func _is_valid_placement(placement_value: Variant) -> bool:
	if not (placement_value is Dictionary):
		return false
	var placement: Dictionary = placement_value as Dictionary
	if not placement.has("offset_m") or not placement.has("rotation_degrees") or not placement.has("scale"):
		return false
	if not _is_finite_vector(placement["offset_m"]):
		return false
	if not _is_finite_vector(placement["rotation_degrees"]):
		return false
	if not _is_finite_number(placement["scale"]) or float(placement["scale"]) <= 0.0:
		return false
	return true


static func _apply_transform(visual: Node3D, binding: Dictionary) -> bool:
	var placement_value: Variant = binding.get("placement")
	if not _is_valid_placement(placement_value):
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
