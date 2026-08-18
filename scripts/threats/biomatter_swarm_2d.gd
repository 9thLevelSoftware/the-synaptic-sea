extends SpriteAnimDriver
class_name BiomatterSwarm2D
## 2D driver for the biomatter_swarm threat archetype.
## Green-tinted placeholder (no art yet). Swarm behavior from ThreatAIState.

const COLOR := Color(0.55, 1.0, 0.45)
const SIZE := Vector2(32, 32)

var _placeholder: ColorRect


func _ready() -> void:
	super._ready()
	_setup_placeholder()


func _setup_placeholder() -> void:
	if sprite == null:
		return
	# Remove default sprite visuals, add colored placeholder
	sprite.visible = false
	_placeholder = ColorRect.new()
	_placeholder.name = "Placeholder"
	_placeholder.color = COLOR
	_placeholder.size = SIZE
	_placeholder.position = -SIZE / 2.0
	add_child(_placeholder)


func _setup_animations() -> void:
	# Placeholder — no SpriteFrames yet. Will be replaced when art arrives.
	pass


func flash_hit() -> void:
	if _placeholder:
		_placeholder.color = Color.WHITE
		get_tree().create_timer(0.1).timeout.connect(func(): _placeholder.color = COLOR)
