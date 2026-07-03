extends Area3D
class_name Interactable

signal interaction_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String, step_id: String)

var interaction_id: String = ""
var objective_id: String = ""
var sequence: int = 0
var objective_type: String = ""
var room_id: String = ""
var prompt_text: String = "Interact"
var tooltip_subject_id: String = ""
var completed: bool = false
var active: bool = true
var interaction_radius: float = 1.8
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D
var marker_visible: bool = false
var step_id: String = ""
var is_step: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func configure_from_objective(objective: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	objective_id = str(objective.get("id", ""))
	sequence = int(objective.get("sequence", 0))
	objective_type = str(objective.get("type", "objective"))
	room_id = str(objective.get("room_id", ""))
	interaction_id = "objective:%02d:%s" % [sequence, objective_id]
	prompt_text = "Interact: %s" % objective_type
	tooltip_subject_id = objective_type
	active = true
	interaction_radius = radius
	completed = false
	candidate_player = null
	name = "Interactable_seq%d_%s" % [sequence, objective_type]
	position = world_position
	set_meta("interaction_id", interaction_id)
	set_meta("objective_id", objective_id)
	set_meta("objective_sequence", sequence)
	set_meta("objective_type", objective_type)
	set_meta("room_id", room_id)
	_ensure_collision(radius)
	_ensure_marker(radius)


func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body


func configure_from_step(objective: Dictionary, step: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	configure_from_objective(objective, world_position, radius)
	is_step = true
	step_id = str(step.get("step_id", ""))
	if step_id.is_empty():
		step_id = "step_%s" % interaction_id
	interaction_id = "%s:%s" % [interaction_id, step_id]
	prompt_text = "Repair: %s" % step_id
	tooltip_subject_id = "junction_step"
	name = "Interactable_seq%d_step_%s" % [sequence, step_id]
	set_meta("step_id", step_id)
	set_meta("is_step", true)


func set_active(is_active: bool) -> void:
	active = is_active
	set_meta("active", active)
	_refresh_marker_material()


func set_marker_visible(is_visible: bool) -> void:
	marker_visible = is_visible
	if marker != null:
		marker.visible = marker_visible


func try_interact(player_body: Node) -> bool:
	if completed or not active:
		return false
	if player_body == null:
		return false
	if candidate_player != player_body and not _is_player_in_direct_range(player_body):
		return false
	completed = true
	set_active(false)
	emit_signal("interaction_completed", interaction_id, objective_id, sequence, objective_type, room_id, step_id)
	return true


func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		var sphere_shape: SphereShape3D = collision_shape.shape as SphereShape3D
		return sphere_shape.radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not (player_body is Node3D):
		return false
	var player_node: Node3D = player_body as Node3D
	var interaction_position: Vector3 = global_position if is_inside_tree() else position
	var player_position: Vector3 = player_node.global_position if player_node.is_inside_tree() else player_node.position
	return interaction_position.distance_to(player_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "InteractionCollisionShape3D"
		add_child(collision_shape)
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = radius
	collision_shape.shape = sphere_shape


func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "InteractionMarker"
		add_child(marker)
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = radius
	marker.mesh = sphere_mesh
	_refresh_marker_material()
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible
	marker.set_meta("debug_interaction_marker", true)


func _refresh_marker_material() -> void:
	if marker == null:
		return
	var material: StandardMaterial3D = StandardMaterial3D.new()
	if completed:
		material.albedo_color = Color(0.4, 0.4, 0.4, 0.16)
	elif active:
		material.albedo_color = Color(0.25, 0.95, 0.45, 0.32)
	else:
		material.albedo_color = Color(0.25, 0.55, 0.95, 0.12)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body


func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
