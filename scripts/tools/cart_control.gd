extends Area3D
class_name CartControl

## A pushable cart's walk-up control. Walk up and interact to grab (push) it, or
## load/unload salvage. Sensor + signal only: it never moves items or reparents
## itself (the coordinator owns cart state + scene lifecycle). Mirrors the strict
## in-range gate + marker of CargoHoldControl.

signal cart_grab_requested(cart_id: String)
signal cart_load_requested(cart_id: String)
signal cart_unload_requested(cart_id: String, category: String)

var cart_id: String = ""
var interaction_radius: float = 1.8
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_cart_id: String, world_position: Vector3, radius := 1.8) -> void:
	assert(radius >= 0.0, "CartControl.configure: radius must be non-negative")
	cart_id = p_cart_id
	interaction_radius = radius
	position = world_position
	name = "CartControl_%s" % p_cart_id
	set_meta("cart_control", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func try_grab(player_body: Node) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("cart_grab_requested", cart_id)
	return true

func try_load(player_body: Node) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("cart_load_requested", cart_id)
	return true

func try_unload(player_body: Node, category: String) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("cart_unload_requested", cart_id, category)
	return true

func _interaction_radius() -> float:
	if is_instance_valid(collision_shape) and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var pn: Node3D = player_body as Node3D
	if not is_inside_tree() or not pn.is_inside_tree():
		return false
	return global_position.distance_to(pn.global_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CartControlCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		marker.name = "CartControlMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.4, radius * 0.7)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.2, 0.7)   # amber, distinct from hold cyan / hangar orange
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_cart_control_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	# Guard the freed-object comparison (Godot 4 throws on == with a freed object).
	if is_instance_valid(candidate_player) and body == candidate_player:
		candidate_player = null
