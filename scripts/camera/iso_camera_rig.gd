extends Node3D
class_name IsoCameraRig

const DEFAULT_OFFSET: Vector3 = Vector3(16.0, 18.0, 16.0)
const DEFAULT_SIZE: float = 22.0

var follow_target: Node3D
var offset: Vector3 = DEFAULT_OFFSET
var camera: Camera3D
var _current_activation_deferred: bool = false
var _current_requested: bool = false


func configure_restore_staging() -> bool:
	if is_inside_tree() or camera != null:
		return false
	_current_activation_deferred = true
	return true


func activate_deferred_current() -> void:
	if not _current_activation_deferred:
		return
	_current_activation_deferred = false
	if _current_requested:
		make_current()


func _ready() -> void:
	_ensure_camera()
	set_process(true)


func _process(_delta: float) -> void:
	_sync_camera_to_target()


func set_follow_target(target: Node3D) -> void:
	follow_target = target
	_ensure_camera()
	_sync_camera_to_target()


func _sync_camera_to_target() -> void:
	if follow_target == null or camera == null:
		return
	if not is_inside_tree() or not follow_target.is_inside_tree() or not camera.is_inside_tree():
		return
	global_position = follow_target.global_position + offset
	camera.global_position = global_position
	camera.look_at(follow_target.global_position, Vector3.UP)


func make_current() -> void:
	_ensure_camera()
	_current_requested = true
	if _current_activation_deferred:
		return
	camera.current = true


func _ensure_camera() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "PlayableIsoCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = DEFAULT_SIZE
	camera.current = not _current_activation_deferred
	add_child(camera)
