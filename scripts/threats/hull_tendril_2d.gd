extends SpriteAnimDriver
class_name HullTendril2D
## 2D driver for the hull_tendril threat archetype.
## Cyan-tinted placeholder. Anchored — doesn't move, attacks in range.
## Applies structure_damage on hit.

const COLOR := Color(0.55, 0.9, 1.0)
const SIZE := Vector2(40, 40)

var _placeholder: ColorRect


func _ready() -> void:
	super._ready()
	_setup_placeholder()


func _setup_placeholder() -> void:
	if sprite == null:
		return
	sprite.visible = false
	_placeholder = ColorRect.new()
	_placeholder.name = "Placeholder"
	_placeholder.color = COLOR
	_placeholder.size = SIZE
	_placeholder.position = -SIZE / 2.0
	add_child(_placeholder)


func _setup_animations() -> void:
	pass


func flash_hit() -> void:
	if _placeholder:
		_placeholder.color = Color.WHITE
		get_tree().create_timer(0.1).timeout.connect(func(): _placeholder.color = COLOR)
