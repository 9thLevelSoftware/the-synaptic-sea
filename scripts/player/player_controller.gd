extends CharacterBody3D
class_name PlayerController

signal interact_requested(player: PlayerController)
signal field_craft_requested(player: PlayerController)

const DEFAULT_MOVE_SPEED: float = 6.0
const CROUCH_SPEED_FACTOR: float = 0.5
const DEFAULT_COLLISION_RADIUS: float = 0.35
const DEFAULT_COLLISION_HEIGHT: float = 1.6
const DEFAULT_FLOOR_SNAP_LENGTH: float = 0.5
const DEFAULT_FLOOR_MAX_ANGLE_DEGREES: float = 60.0

var move_speed: float = DEFAULT_MOVE_SPEED
var _speed_multiplier: float = 1.0
var _crouching: bool = false
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var scripted_move_direction: Vector3 = Vector3.ZERO
var use_scripted_movement: bool = false
var marker: MeshInstance3D
var collision_shape: CollisionShape3D


func _ready() -> void:
	_ensure_support_nodes()
	floor_snap_length = DEFAULT_FLOOR_SNAP_LENGTH
	floor_max_angle = deg_to_rad(DEFAULT_FLOOR_MAX_ANGLE_DEGREES)
	set_physics_process(true)


## Domain 1: vitals-driven action-gating seam. The coordinator pushes a
## multiplier each frame from VitalsState.get_movement_speed_multiplier().
func set_movement_speed_multiplier(m: float) -> void:
	_speed_multiplier = clampf(m, 0.0, 1.0)

## Effective per-frame move speed after the vitals gate and crouch are applied.
func get_effective_move_speed() -> float:
	return move_speed * _speed_multiplier * (CROUCH_SPEED_FACTOR if _crouching else 1.0)

## Domain 2: crouch state. Driven by the "crouch" input in _physics_process and
## settable for validation. Crouch lowers move speed and the player's emitted
## stealth signals (the coordinator reads is_crouching() for the detection feed).
func set_crouching(c: bool) -> void:
	_crouching = c

func is_crouching() -> bool:
	return _crouching

## True when the player has meaningful planar velocity. Consumed by the coordinator
## as a live runtime signal: it drives stamina drain (Domain 1 vitals `moving`) and
## emitted noise (Domain 2 stealth). Previously unimplemented, so both consumers'
## `has_method("is_moving")` guards were always false and the signal was inert.
func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length_squared() > 0.01


func _physics_process(delta: float) -> void:
	var move_direction: Vector3 = _read_move_direction()
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()
	if InputMap.has_action("crouch"):
		set_crouching(Input.is_action_pressed("crouch"))
	var speed: float = get_effective_move_speed()
	velocity.x = move_direction.x * speed
	velocity.z = move_direction.z * speed
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		request_interact()
	elif event.is_action_pressed("field_craft"):
		emit_signal("field_craft_requested", self)


func request_interact() -> void:
	emit_signal("interact_requested", self)


func teleport_to(world_position: Vector3) -> void:
	if is_inside_tree():
		global_position = world_position
	else:
		position = world_position
	velocity = Vector3.ZERO


func set_scripted_move_direction(direction: Vector3) -> void:
	use_scripted_movement = true
	scripted_move_direction = direction


func clear_scripted_move_direction() -> void:
	use_scripted_movement = false
	scripted_move_direction = Vector3.ZERO


func _read_move_direction() -> Vector3:
	if use_scripted_movement:
		return scripted_move_direction

	var input_x: float = _action_strength_or_zero("move_right") - _action_strength_or_zero("move_left")
	var input_z: float = _action_strength_or_zero("move_back") - _action_strength_or_zero("move_forward")
	return Vector3(input_x, 0.0, input_z)


func _action_strength_or_zero(action_name: String) -> float:
	if not InputMap.has_action(action_name):
		return 0.0
	return Input.get_action_strength(action_name)


func _ensure_support_nodes() -> void:
	collision_layer = 1
	collision_mask = 1

	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "PlayerCollisionShape3D"
		var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
		capsule_shape.radius = DEFAULT_COLLISION_RADIUS
		capsule_shape.height = DEFAULT_COLLISION_HEIGHT
		collision_shape.shape = capsule_shape
		collision_shape.position = Vector3(0.0, DEFAULT_COLLISION_HEIGHT * 0.5, 0.0)
		add_child(collision_shape)

	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "PlayerMarker"
		var capsule_mesh: CapsuleMesh = CapsuleMesh.new()
		capsule_mesh.radius = DEFAULT_COLLISION_RADIUS
		capsule_mesh.height = DEFAULT_COLLISION_HEIGHT
		marker.mesh = capsule_mesh
		marker.position = Vector3(0.0, DEFAULT_COLLISION_HEIGHT * 0.5, 0.0)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.15, 0.72, 1.0, 1.0)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		marker.material_override = material
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
