extends Area3D
class_name GameplayObjectiveVolume

signal objective_completed(objective_id: String, sequence: int, objective_type: String, room_id: String)

var objective_id: String = ""
var sequence: int = 0
var objective_type: String = ""
var room_id: String = ""
var completed: bool = false


func configure(objective: Dictionary, world_position: Vector3, radius := 1.5) -> void:
	objective_id = str(objective.get("id", ""))
	sequence = int(objective.get("sequence", 0))
	objective_type = str(objective.get("type", "objective"))
	room_id = str(objective.get("room_id", ""))
	completed = false

	name = "ObjectiveVolume_seq%d_%s_%s" % [sequence, objective_type, objective_id]
	position = world_position
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	set_meta("objective_id", objective_id)
	set_meta("objective_sequence", sequence)
	set_meta("objective_type", objective_type)
	set_meta("room_id", room_id)

	for child in get_children():
		remove_child(child)
		child.free()

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = float(radius)
	collision_shape.shape = sphere_shape
	add_child(collision_shape)

	var marker: MeshInstance3D = MeshInstance3D.new()
	marker.name = "MarkerMesh"
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = float(radius)
	marker.mesh = sphere_mesh

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.95, 0.45, 0.25)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)


func complete() -> void:
	if completed:
		return
	completed = true
	emit_signal("objective_completed", objective_id, sequence, objective_type, room_id)
