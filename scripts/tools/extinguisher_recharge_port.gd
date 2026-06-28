extends Area3D
class_name ExtinguisherRechargePort

## Stationary recharge station for the player's fire extinguisher (ADR-0041).
## Refills ExtinguisherState charge while powered AND a player is in range. The
## coordinator drives `powered` each frame from the "stations" power channel
## (same precedent as CraftingStation.set_powered).

var extinguisher_state                  # ExtinguisherState
var interaction_radius: float = 1.8
var powered: bool = false
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	set_process(true)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_extinguisher_state, world_position: Vector3, radius := 1.8) -> void:
	extinguisher_state = p_extinguisher_state
	interaction_radius = radius
	candidate_player = null
	powered = false
	position = world_position
	name = "ExtinguisherRechargePort"
	set_meta("extinguisher_recharge_port", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_powered(value: bool) -> void:
	powered = value

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func _process(delta: float) -> void:
	if not powered or extinguisher_state == null:
		return
	if not _player_in_range():
		return
	extinguisher_state.recharge(delta)

func _player_in_range() -> bool:
	if not is_instance_valid(candidate_player) or not (candidate_player is Node3D):
		return false
	var p: Node3D = candidate_player as Node3D
	if not is_inside_tree() or not p.is_inside_tree():
		return false
	return global_position.distance_to(p.global_position) <= interaction_radius

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "RechargePortCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "RechargePortMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.6, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_recharge_port_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
