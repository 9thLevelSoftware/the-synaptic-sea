extends RefCounted
class_name ThreatPlaceholderRenderer

## Shared builder for threat-shaped placeholder nodes. Used by ThreatManager (real
## threats) and HallucinationManager (phantoms) so both look identical. Behavior is the
## exact visual previously inlined in ThreatManager._spawn_placeholder.

static func build_placeholder(archetype_id: String, tags: Array, world_position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = world_position
	var mesh_instance := MeshInstance3D.new()
	if tags.has("swarm"):
		mesh_instance.mesh = SphereMesh.new()
	elif tags.has("anchored"):
		mesh_instance.mesh = CylinderMesh.new()
	else:
		mesh_instance.mesh = CapsuleMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_for_archetype(archetype_id)
	mesh_instance.material_override = mat
	node.add_child(mesh_instance)
	return node

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
