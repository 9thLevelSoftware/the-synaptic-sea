extends CharacterBody2D
class_name TopDownPlayerController
## 8-direction CharacterBody2D for the top-down production path.
## Replaces 3D PlayerController for 2D presentation. Projection-agnostic
## vitals/seam interfaces kept identical to the 3D controller.

signal interact_requested(player)
signal field_craft_requested(player)

const DEFAULT_MOVE_SPEED: float = 200.0
const CROUCH_SPEED_FACTOR: float = 0.5
const DEFAULT_COLLISION_RADIUS: float = 16.0

var move_speed: float = DEFAULT_MOVE_SPEED
var _speed_multiplier: float = 1.0
var _crouching: bool = false
var use_scripted_movement: bool = false
var scripted_move_direction: Vector2 = Vector2.ZERO
var marker: Sprite2D
var collision_shape: CollisionShape2D


func _ready() -> void:
	_ensure_support_nodes()
	set_physics_process(true)


## Vitals-driven action-gating seam (same interface as 3D controller).
func set_movement_speed_multiplier(m: float) -> void:
	_speed_multiplier = clampf(m, 0.0, 1.0)


func get_effective_move_speed() -> float:
	return move_speed * _speed_multiplier * (CROUCH_SPEED_FACTOR if _crouching else 1.0)


func set_crouching(c: bool) -> void:
	_crouching = c


func is_crouching() -> bool:
	return _crouching


func is_moving() -> bool:
	return velocity.length_squared() > 0.01


func _physics_process(_delta: float) -> void:
	var move_direction: Vector2 = _read_move_direction()
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()
	if InputMap.has_action("crouch"):
		set_crouching(Input.is_action_pressed("crouch"))
	var speed: float = get_effective_move_speed()
	velocity = move_direction * speed
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		request_interact()
	elif event.is_action_pressed("field_craft"):
		emit_signal("field_craft_requested", self)


func request_interact() -> void:
	emit_signal("interact_requested", self)


func _read_move_direction() -> Vector2:
	if use_scripted_movement:
		return scripted_move_direction
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	return dir


func _ensure_support_nodes() -> void:
	if collision_shape == null:
		collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = DEFAULT_COLLISION_RADIUS
		collision_shape.shape = circle
		add_child(collision_shape)
