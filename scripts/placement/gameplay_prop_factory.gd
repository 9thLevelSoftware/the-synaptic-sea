extends RefCounted
class_name GameplayPropFactory

## Shared catalog-backed builder for slice interactable visuals. Every prop keeps a
## direct MeshInstance3D child named Mesh so callers can replace a legacy marker
## without changing interaction or collision ownership.

const DEFAULT_KIT_PATH: String = "res://data/kits/gameplay_prop_v0.json"

static var _catalog: Dictionary = {}
static var _catalog_path: String = ""

static func load_catalog(path: String = DEFAULT_KIT_PATH) -> Dictionary:
	if path == _catalog_path and not _catalog.is_empty():
		return _catalog
	_catalog_path = path
	_catalog = {}
	if path.is_empty() or not FileAccess.file_exists(path):
		return _catalog
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _catalog
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and (parsed as Dictionary).get("props", {}) is Dictionary:
		_catalog = parsed as Dictionary
	return _catalog

static func build(prop_id: String, world_position: Vector3 = Vector3.ZERO) -> Node3D:
	var catalog: Dictionary = load_catalog()
	var props: Dictionary = catalog.get("props", {}) as Dictionary
	var prop: Dictionary = props.get(prop_id, {}) as Dictionary
	var node := Node3D.new()
	node.name = "GameplayProp_%s" % prop_id
	node.position = world_position + Vector3.UP * float(prop.get("y_offset", 0.0))
	node.set_meta("gameplay_prop_id", prop_id)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh_resource: Resource = _load_mesh_resource(prop)
	if mesh_resource is Mesh:
		mesh_instance.mesh = mesh_resource as Mesh
	else:
		mesh_instance.mesh = _primitive_mesh(str(prop.get("primitive", "box")), float(prop.get("height_hint", 1.0)))
	var scale_value: float = float(prop.get("scale", 1.0))
	mesh_instance.scale = Vector3.ONE * scale_value
	var material := StandardMaterial3D.new()
	material.albedo_color = _catalog_color(prop)
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mesh_instance)

	if mesh_resource is PackedScene:
		var packed_instance := (mesh_resource as PackedScene).instantiate()
		packed_instance.name = "CatalogMesh"
		if packed_instance is Node3D:
			(packed_instance as Node3D).scale = Vector3.ONE * scale_value
		node.add_child(packed_instance)
	return node

static func build_from_catalog(prop_id: String, world_position: Vector3 = Vector3.ZERO) -> Node3D:
	return build(prop_id, world_position)

static func _load_mesh_resource(prop: Dictionary) -> Resource:
	var mesh_path: String = str(prop.get("mesh_path", ""))
	if mesh_path.is_empty() or not ResourceLoader.exists(mesh_path):
		return null
	return load(mesh_path)

static func _primitive_mesh(primitive: String, height_hint: float) -> Mesh:
	var height: float = maxf(0.1, height_hint)
	match primitive:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.height = height
			sphere.radius = height * 0.5
			return sphere
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.height = height
			capsule.radius = height * 0.28
			return capsule
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.height = height
			cylinder.top_radius = height * 0.32
			cylinder.bottom_radius = height * 0.38
			return cylinder
		_:
			var box := BoxMesh.new()
			box.size = Vector3(height * 0.9, height, height * 0.75)
			return box

static func _catalog_color(prop: Dictionary) -> Color:
	var albedo: String = str(prop.get("albedo", ""))
	return Color.from_string(albedo, Color(0.7, 0.7, 0.7)) if not albedo.is_empty() else Color(0.7, 0.7, 0.7)
