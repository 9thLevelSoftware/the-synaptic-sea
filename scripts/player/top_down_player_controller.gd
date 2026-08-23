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
	# Use same action names as 3D PlayerController for consistency
	var left := Input.get_action_strength("move_left") if InputMap.has_action("move_left") else 0.0
	var right := Input.get_action_strength("move_right") if InputMap.has_action("move_right") else 0.0
	var up := Input.get_action_strength("move_forward") if InputMap.has_action("move_forward") else 0.0
	var down := Input.get_action_strength("move_back") if InputMap.has_action("move_back") else 0.0
	# Fallback to ui_ actions if custom ones don't exist
	if left == 0.0 and right == 0.0 and up == 0.0 and down == 0.0:
		left = Input.get_action_strength("ui_left")
		right = Input.get_action_strength("ui_right")
		up = Input.get_action_strength("ui_up")
		down = Input.get_action_strength("ui_down")
	dir.x = right - left
	dir.y = down - up
	return dir


func _ensure_support_nodes() -> void:
	if collision_shape == null:
		collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = DEFAULT_COLLISION_RADIUS
		collision_shape.shape = circle
		add_child(collision_shape)
	# Add visible player sprite
	if marker == null:
		var sprite := Sprite2D.new()
		sprite.name = "PlayerSprite"
		# Create a simple colored square texture
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.6, 1.0, 1.0))
		# Draw a border
		for x in range(32):
			for y in range(32):
				if x < 2 or x >= 30 or y < 2 or y >= 30:
					img.set_pixel(x, y, Color(0.1, 0.3, 0.7, 1.0))
				elif x >= 12 and x < 20 and y >= 4 and y < 12:
					# "Visor" detail
					img.set_pixel(x, y, Color(0.4, 0.8, 1.0, 1.0))
		var tex := ImageTexture.create_from_image(img)
		sprite.texture = tex
		sprite.scale = Vector2(1.5, 1.5)
		add_child(sprite)
		marker = sprite
