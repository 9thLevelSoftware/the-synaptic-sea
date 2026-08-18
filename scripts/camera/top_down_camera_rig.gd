extends Node2D
class_name TopDownCameraRig
## Camera2D follow rig for the top-down production path.
## Replaces IsoCameraRig for 2D presentation. Camera2D handles zoom natively.

const DEFAULT_ZOOM: float = 1.0
const MIN_ZOOM: float = 0.6
const MAX_ZOOM: float = 1.5
const ZOOM_STEP: float = 0.1
const SMOOTH_SPEED: float = 8.0

var follow_target: Node2D
var camera: Camera2D
var _target_zoom: float = DEFAULT_ZOOM


func _ready() -> void:
	_ensure_camera()
	set_process(true)
	set_process_unhandled_input(true)


func _process(delta: float) -> void:
	_sync_camera_to_target(delta)


func set_follow_target(target: Node2D) -> void:
	follow_target = target
	_ensure_camera()
	if follow_target != null:
		_sync_camera_to_target(0.0)


func make_current() -> void:
	_ensure_camera()
	camera.make_current()


func set_zoom_level(z: float) -> void:
	_target_zoom = clampf(z, MIN_ZOOM, MAX_ZOOM)


func get_zoom_level() -> float:
	return _target_zoom


func _sync_camera_to_target(delta: float) -> void:
	if follow_target == null or camera == null:
		return
	if not is_inside_tree() or not follow_target.is_inside_tree():
		return
	if delta <= 0.0:
		global_position = follow_target.global_position
	else:
		global_position = global_position.lerp(
			follow_target.global_position, SMOOTH_SPEED * delta
		)
	camera.zoom = camera.zoom.lerp(
		Vector2(_target_zoom, _target_zoom),
		SMOOTH_SPEED * delta
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom_level(_target_zoom + ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_level(_target_zoom - ZOOM_STEP)


func _ensure_camera() -> void:
	if camera != null:
		return
	camera = Camera2D.new()
	camera.name = "TopDownCamera"
	camera.zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
	camera.position_smoothing_enabled = false  # We lerp manually in _sync_camera_to_target
	add_child(camera)
	# Defer make_current until after node enters tree
	camera.call_deferred("make_current")
