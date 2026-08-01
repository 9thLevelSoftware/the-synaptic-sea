extends RefCounted
class_name RuntimePropVisualBinder

const SCENE_PATH_PREFIX: String = "res://assets/imported/props/"
const IMPORTED_VISUAL_NAME: String = "ImportedVisual"


static func mount_component_visual(marker: Node3D, binding: Dictionary) -> bool:
	if marker == null or binding.is_empty():
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


static func clear_imported_visuals(root: Node) -> void:
	if root == null:
		return
	for child_variant in root.get_children():
		var child: Node = child_variant as Node
		if child == null:
			continue
		if child.name == IMPORTED_VISUAL_NAME and str(child.get_meta("visual_source", "")) == "imported":
			root.remove_child(child)
			child.free()
			continue
		clear_imported_visuals(child)


static func _create_imported_visual(binding: Dictionary) -> Node3D:
	var scene_path: Variant = binding.get("visual_scene_path", "")
	if typeof(scene_path) != TYPE_STRING:
		return null
	var path: String = str(scene_path)
	if path.is_empty() or not path.begins_with(SCENE_PATH_PREFIX):
		return null

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var instance: Node = packed.instantiate()
	var visual: Node3D = instance as Node3D
	if visual == null:
		if instance != null:
			instance.free()
		return null
	if not _apply_transform(visual, binding):
		visual.free()
		return null
	visual.name = IMPORTED_VISUAL_NAME
	visual.set_meta("visual_source", "imported")
	return visual


static func _apply_transform(visual: Node3D, binding: Dictionary) -> bool:
	var placement_value: Variant = binding.get("placement", {})
	if placement_value == null:
		return false
	if not (placement_value is Dictionary):
		return false
	var placement: Dictionary = placement_value as Dictionary

	var offset: Vector3 = Vector3.ZERO
	var rotation_degrees: Vector3 = Vector3.ZERO
	var uniform_scale: float = 1.0
	if placement.has("offset_m"):
		var offset_result: Dictionary = _read_finite_vector(placement["offset_m"])
		if not bool(offset_result.get("valid", false)):
			return false
		offset = offset_result["value"]
	if placement.has("rotation_degrees"):
		var rotation_result: Dictionary = _read_finite_vector(placement["rotation_degrees"])
		if not bool(rotation_result.get("valid", false)):
			return false
		rotation_degrees = rotation_result["value"]
	if placement.has("scale"):
		if not _is_finite_number(placement["scale"]):
			return false
		uniform_scale = float(placement["scale"])

	visual.position = offset
	visual.rotation_degrees = rotation_degrees
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


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))
