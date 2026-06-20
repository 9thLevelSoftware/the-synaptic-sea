extends Node3D
class_name IsoCameraRig

const DEFAULT_OFFSET: Vector3 = Vector3(16.0, 18.0, 16.0)
const DEFAULT_SIZE: float = 22.0

var follow_target: Node3D
var offset: Vector3 = DEFAULT_OFFSET
var camera: Camera3D


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
	camera.current = true


func _ensure_camera() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "PlayableIsoCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = DEFAULT_SIZE
	camera.current = true
	add_child(camera)
