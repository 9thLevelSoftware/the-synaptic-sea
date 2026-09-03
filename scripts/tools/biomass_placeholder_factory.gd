extends RefCounted

## Deterministic primitive part factory for biomass assembly.
##
## Builds one Node3D root per part occurrence with:
##   - exactly one MeshInstance3D per catalog fallback (box / sphere / capsule)
##   - exactly one Node3D per catalog socket, positioned in the part's local frame
##   - no collision nodes (collision is owned by BiomassThreatVisual)
##
## Empty `wrapper_scene_path` uses this factory directly; non-empty paths are
## routed through BiomassThreatVisual which may delegate to the catalog's
## wrapper scene (subject to the contract validation in the visual).
##
## Capsule meshes receive a +90° rotation around local X so that the canonical
## catalog "long-Y" capsule axis maps to the catalog's authoritative local +Z
## forward direction. Sphere meshes use a unit-diameter primitive scaled to all
## three dimensions.

const SHAPE_KINDS: Array[String] = ["box", "capsule", "sphere"]

## Builds a deterministic primitive part root for the given catalog entry.
## The returned Node3D contains one MeshInstance3D child and one Node3D child
## per catalog socket, in that order. No children of any other type.
static func build(part_id: String, entry: Dictionary) -> Node3D:
	if not entry is Dictionary or entry.is_empty():
		return null
	var fallback_value: Variant = entry.get("fallback", {})
	if not fallback_value is Dictionary:
		return null
	var fallback: Dictionary = fallback_value
	var primitive: String = String(fallback.get("primitive", ""))
	if not SHAPE_KINDS.has(primitive):
		return null
	var dimensions_value: Variant = fallback.get("dimensions_m", [])
	if not dimensions_value is Array or (dimensions_value as Array).size() != 3:
		return null
	var albedo: String = String(fallback.get("albedo", ""))
	var sockets_value: Variant = entry.get("sockets", [])
	if not sockets_value is Array or (sockets_value as Array).is_empty():
		return null
	var part_root: Node3D = Node3D.new()
	part_root.name = StringName("Part_%s" % part_id)
	part_root.set_meta("biomass_part_id", part_id)
	part_root.set_meta("biomass_category", String(entry.get("category", "")))
	part_root.set_meta("biomass_placeholder", true)
	var mesh: MeshInstance3D = _build_mesh(primitive, dimensions_value as Array, albedo)
	if mesh == null:
		part_root.free()
		return null
	part_root.add_child(mesh)
	var sockets: Array = sockets_value
	for socket_value in sockets:
		if not socket_value is Dictionary:
			part_root.free()
			return null
		var socket_node: Node3D = _build_socket_node(socket_value as Dictionary)
		if socket_node == null:
			part_root.free()
			return null
		part_root.add_child(socket_node)
	return part_root

static func _build_mesh(primitive: String, dimensions: Array, albedo: String) -> MeshInstance3D:
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	mesh_node.name = StringName("Mesh")
	match primitive:
		"box":
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2]))
			mesh_node.mesh = box
		"sphere":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			mesh_node.mesh = sphere
			# Sphere primitive has unit diameter; scale each axis to the
			# requested dimensions so x/y/z diameters remain exact.
			mesh_node.scale = Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2]))
		"capsule":
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = 0.5
			capsule.height = 1.0
			mesh_node.mesh = capsule
			# Capsule primitive long axis is local Y. Catalog dimensions are
			# [diam_x, diam_y, length_z]; map (x, z, y) onto the mesh axes so
			# the resulting local Y maps onto the catalog's authoritative +Z
			# after the additional +90° X rotation below.
			mesh_node.scale = Vector3(float(dimensions[0]), float(dimensions[2]), float(dimensions[1]))
			mesh_node.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
		_:
			return null
	if not albedo.is_empty():
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = _color_from_albedo(albedo)
		mesh_node.material_override = material
	return mesh_node

static func _build_socket_node(socket: Dictionary) -> Node3D:
	var position_value: Variant = socket.get("position_m", [0, 0, 0])
	var rotation_value: Variant = socket.get("rotation_deg", [0, 0, 0])
	if not position_value is Array or (position_value as Array).size() != 3:
		return null
	if not rotation_value is Array or (rotation_value as Array).size() != 3:
		return null
	var node: Node3D = Node3D.new()
	node.name = StringName(String(socket.get("name", "")))
	node.set_meta("biomass_socket_name", node.name)
	var position: Array = position_value
	var rotation: Array = rotation_value
	node.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	node.rotation_degrees = Vector3(float(rotation[0]), float(rotation[1]), float(rotation[2]))
	return node

static func _color_from_albedo(albedo: String) -> Color:
	if albedo.length() != 7 or not albedo.begins_with("#"):
		return Color(1.0, 1.0, 1.0)
	return Color.from_string(albedo, Color(1.0, 1.0, 1.0))