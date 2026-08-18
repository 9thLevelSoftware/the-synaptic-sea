extends Node2D
class_name PlaceholderThreat2D
## Parameterized placeholder for any threat archetype.
## Replaces three near-identical files (biomatter_swarm_2d, stalker_2d, hull_tendril_2d).
## When real art arrives, subclass or swap the sprite.

var color: Color = Color.WHITE
var size: Vector2 = Vector2(32, 32)
var is_moving: bool = false
var is_attacking: bool = false
var _placeholder: ColorRect


func _init(p_color: Color = Color.WHITE, p_size: Vector2 = Vector2(32, 32)) -> void:
	color = p_color
	size = p_size


func _ready() -> void:
	_setup_placeholder()


func _setup_placeholder() -> void:
	_placeholder = ColorRect.new()
	_placeholder.name = "Placeholder"
	_placeholder.color = color
	_placeholder.size = size
	_placeholder.position = -size / 2.0
	add_child(_placeholder)


func flash_hit() -> void:
	if _placeholder:
		var original := _placeholder.color
		_placeholder.color = Color.WHITE
		get_tree().create_timer(0.1).timeout.connect(func(): _placeholder.color = original)
