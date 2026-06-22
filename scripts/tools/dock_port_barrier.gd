extends Area3D
class_name DockPortBarrier

## A closed dock-seam barrier at a derelict's dock port. An intact port opens in
## one interact; a broken port requires a timed, welding-speeded breach channel
## (mirrors RepairPoint's PZ-style channel — leaving range cancels with no loss).
## No parts consumed; the breach always eventually succeeds.

signal breach_opened(marker_id: String)

var marker_id: String = ""
var condition: String = "intact"          # "intact" | "broken"
var player_progression                    # PlayerProgressionState | null
var interaction_radius: float = 1.8
var breach_seconds: float = 6.0

var opened: bool = false
var channeling: bool = false
var progress: float = 0.0                  # 0..1
var _channel_player: Node = null
var _scaled_seconds: float = 1.0
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	set_process(true)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_marker_id: String, p_condition: String, p_player_progression, world_position: Vector3, p_breach_seconds: float, radius := 1.8) -> void:
	marker_id = p_marker_id
	condition = p_condition
	player_progression = p_player_progression
	breach_seconds = p_breach_seconds
	interaction_radius = radius
	opened = false
	channeling = false
	progress = 0.0
	candidate_player = null
	position = world_position
	name = "DockPortBarrier_%s" % p_marker_id
	set_meta("dock_port_barrier", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func _player_skill() -> int:
	if player_progression != null and player_progression.has_method("get_skill_level"):
		return int(player_progression.get_skill_level("welding"))
	return 0

## Intact: open immediately (one interact). Broken: start the welding-speeded
## channel. Returns true if the interaction was consumed (opened or channel started).
func try_start(player_body: Node) -> bool:
	if opened or not is_instance_valid(player_body):
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	if condition != "broken":
		set_opened(true)
		emit_signal("breach_opened", marker_id)
		return true
	if channeling:
		return false
	_channel_player = player_body
	channeling = true
	progress = 0.0
	var factor: float = 1.0 + 0.1 * float(maxi(0, _player_skill()))
	_scaled_seconds = maxf(0.01, breach_seconds / factor)
	return true

func _process(delta: float) -> void:
	if not channeling:
		return
	if not is_instance_valid(_channel_player) or not _is_player_in_direct_range(_channel_player):
		_cancel()
		return
	advance_channel(delta)

func advance_channel(delta: float) -> void:
	if not channeling:
		return
	progress = clampf(progress + delta / _scaled_seconds, 0.0, 1.0)
	if progress >= 1.0:
		_complete()

func _complete() -> void:
	channeling = false
	set_opened(true)
	if player_progression != null and player_progression.has_method("grant_xp"):
		player_progression.grant_xp("welding", 25)
	emit_signal("breach_opened", marker_id)

func _cancel() -> void:
	channeling = false
	progress = 0.0
	_channel_player = null

func set_opened(value: bool) -> void:
	opened = value
	channeling = false
	progress = 1.0 if value else 0.0
	if collision_shape != null:
		collision_shape.disabled = opened   # opening removes the blocking collider
	if marker != null:
		marker.visible = not opened

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var pn: Node3D = player_body as Node3D
	if not is_inside_tree() or not pn.is_inside_tree():
		return false
	return global_position.distance_to(pn.global_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "DockPortBarrierCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = opened

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "DockPortBarrierMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.2, 0.2, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = not opened
	marker.set_meta("debug_dock_port_barrier_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
