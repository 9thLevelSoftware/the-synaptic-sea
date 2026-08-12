extends RefCounted
class_name ThreatPlaceholderRenderer

## Shared catalog-backed builder for threat visual nodes. Used by ThreatManager
## (real threats) and HallucinationManager (phantoms) so both retain the same API.
## Empty or missing mesh_path entries use the catalog primitive and albedo.

const DEFAULT_CATALOG_PATH: String = "res://data/combat/threat_visual_catalog.json"

static var _catalog: Dictionary = {}
static var _catalog_path: String = ""

static func load_catalog(path: String = DEFAULT_CATALOG_PATH) -> Dictionary:
	if path == _catalog_path and not _catalog.is_empty():
		return _catalog
	_catalog_path = path
	_catalog = {}
	if path.is_empty() or not FileAccess.file_exists(path):
		return _catalog
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _catalog
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.get("archetypes", {}) is Dictionary:
		_catalog = parsed
	return _catalog

static func build_placeholder(archetype_id: String, tags: Array, world_position: Vector3) -> Node3D:
	var catalog := load_catalog()
	var archetype: Dictionary = catalog.get("archetypes", {}).get(archetype_id, {}) as Dictionary
	var node := Node3D.new()
	node.position = world_position + Vector3.UP * float(archetype.get("y_offset", 0.0))

	# Keep a direct MeshInstance3D child for the stable visual contract, even when
	# a future catalog entry mounts a PackedScene/GLB beside this fallback slot.
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var primitive: String = str(archetype.get("primitive", ""))
	var scale: float = float(archetype.get("scale", 1.0))
	var mesh_resource: Resource = _load_mesh_resource(archetype)
	if mesh_resource is Mesh:
		mesh_instance.mesh = mesh_resource as Mesh
	else:
		mesh_instance.mesh = _primitive_mesh(primitive, tags)
	mesh_instance.scale = Vector3.ONE * scale
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _catalog_color(archetype, archetype_id)
	mesh_instance.material_override = mat
	node.add_child(mesh_instance)

	if mesh_resource is PackedScene:
		var packed_instance := (mesh_resource as PackedScene).instantiate()
		packed_instance.name = "CatalogMesh"
		if packed_instance is Node3D:
			(packed_instance as Node3D).scale = Vector3.ONE * scale
		node.add_child(packed_instance)
	return node

static func build_from_catalog(archetype_id: String, world_position: Vector3) -> Node3D:
	return build_placeholder(archetype_id, [], world_position)

static func _load_mesh_resource(archetype: Dictionary) -> Resource:
	var mesh_path: String = str(archetype.get("mesh_path", ""))
	if mesh_path.is_empty() or not FileAccess.file_exists(mesh_path):
		return null
	var resource: Resource = load(mesh_path)
	return resource

static func _primitive_mesh(primitive: String, tags: Array) -> Mesh:
	match primitive:
		"sphere":
			return SphereMesh.new()
		"capsule":
			return CapsuleMesh.new()
		"cylinder":
			return CylinderMesh.new()
		"box":
			return BoxMesh.new()
		_:
			# Preserve the old tag-driven fallback for unknown/missing catalog entries.
			if tags.has("swarm"):
				return SphereMesh.new()
			if tags.has("anchored"):
				return CylinderMesh.new()
			return CapsuleMesh.new()

static func _catalog_color(archetype: Dictionary, archetype_id: String) -> Color:
	var albedo: String = str(archetype.get("albedo", ""))
	if not albedo.is_empty():
		return Color.from_string(albedo, color_for_archetype(archetype_id))
	return color_for_archetype(archetype_id)

## Compatibility helper retained for existing callers and legacy tests. The
## catalog-backed builder uses its albedo field, while unknown/fallback callers
## continue receiving the historical values.
static func color_for_archetype(archetype_id: String) -> Color:
	match archetype_id:
		"biomatter_swarm":
			return Color(0.55, 1.0, 0.45)
		"puppet_corpse":
			return Color(0.85, 0.82, 0.7)
		"stalker":
			return Color(0.7, 0.7, 1.0)
		"mimic":
			return Color(1.0, 0.55, 0.25)
		"hull_tendril":
			return Color(0.55, 0.9, 1.0)
		_:
			return Color(1.0, 0.35, 0.35)
