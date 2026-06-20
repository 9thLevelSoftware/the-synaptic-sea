extends Node3D

const GENERATED_ROOT := "res://scenes/validation/generated/m7_web_breached_corridor"
const PLAN_PATH := GENERATED_ROOT + "/plan.json"
const CATEGORY_PREVIEWS := {
	"structural": {"size": Vector3(3.6, 2.8, 0.8), "color": Color(0.24, 0.58, 0.72, 1.0)},
	"gameplay-prop": {"size": Vector3(2.0, 1.2, 0.5), "color": Color(0.78, 0.61, 0.19, 1.0)},
	"dressing": {"size": Vector3(1.8, 0.3, 0.2), "color": Color(0.20, 0.76, 0.55, 1.0)},
	"character": {"size": Vector3(0.7, 1.95, 0.7), "color": Color(0.71, 0.76, 0.96, 1.0)},
}

func _ready() -> void:
	_spawn_generated_scene()


func _spawn_generated_scene() -> void:
	var plan_text := FileAccess.get_file_as_string(PLAN_PATH)
	var plan: Dictionary = JSON.parse_string(plan_text)
	if typeof(plan) != TYPE_DICTIONARY:
		push_error("M7 proof harness: could not parse plan JSON")
		return
	for zone in plan.get("zones", []):
		for placement in zone.get("placements", []):
			var scene_path := GENERATED_ROOT + "/" + String(placement["scene_path"])
			var packed := load(scene_path)
			if packed == null:
				push_error("M7 proof harness: could not load %s" % scene_path)
				continue
			var instance := packed.instantiate() as Node3D
			if instance == null:
				push_error("M7 proof harness: could not instantiate %s" % scene_path)
				continue
			instance.position = _vec3_from_array(placement["position"])
			instance.rotation_degrees = Vector3(0.0, float(placement["rotation_degrees"]), 0.0)
			add_child(instance)
			_add_preview_mesh(instance, GENERATED_ROOT + "/" + String(placement["manifest_path"]))


func _add_preview_mesh(root: Node3D, manifest_path: String) -> void:
	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var manifest: Dictionary = JSON.parse_string(manifest_text)
	if typeof(manifest) != TYPE_DICTIONARY:
		push_error("M7 proof harness: could not parse manifest %s" % manifest_path)
		return
	var category := String(manifest["asset"].get("category", "dressing"))
	var preview: Dictionary = CATEGORY_PREVIEWS.get(category, CATEGORY_PREVIEWS["dressing"])
	var visual := root.get_node_or_null("Visual")
	if visual == null:
		return
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = preview["size"]
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = preview["color"]
	material.roughness = 1.0
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(0.0, preview["size"].y * 0.5, 0.0)
	visual.add_child(mesh_instance)


func _vec3_from_array(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
