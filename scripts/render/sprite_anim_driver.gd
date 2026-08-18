extends Node2D
class_name SpriteAnimDriver
## Base class for 4-direction sprite animations, replacing 3D threat renderers.
## Each threat archetype extends this and provides idle/move/attack frames.

enum Direction { DOWN, LEFT, RIGHT, UP }

var sprite: AnimatedSprite2D
var facing: Direction = Direction.DOWN
var is_moving: bool = false
var is_attacking: bool = false


func _ready() -> void:
	_ensure_sprite()
	_setup_animations()
	set_process(true)


func _process(_delta: float) -> void:
	_update_animation()


func set_facing(dir: Direction) -> void:
	facing = dir


func set_moving(moving: bool) -> void:
	is_moving = moving


func set_attacking(attacking: bool) -> void:
	is_attacking = attacking


func _update_animation() -> void:
	if sprite == null:
		return
	var prefix := _direction_prefix(facing)
	if is_attacking:
		sprite.play(prefix + "_attack")
	elif is_moving:
		sprite.play(prefix + "_walk")
	else:
		sprite.play(prefix + "_idle")


func _direction_prefix(dir: Direction) -> String:
	match dir:
		Direction.DOWN: return "down"
		Direction.LEFT: return "left"
		Direction.RIGHT: return "right"
		Direction.UP: return "up"
	return "down"


func _ensure_sprite() -> void:
	if sprite != null:
		return
	sprite = AnimatedSprite2D.new()
	sprite.name = "ThreatSprite"
	add_child(sprite)


func _setup_animations() -> void:
	# Override in subclass to configure SpriteFrames with actual art.
	pass
