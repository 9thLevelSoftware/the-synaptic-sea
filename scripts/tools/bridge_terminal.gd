extends Area3D
class_name BridgeTerminal

## The bridge command terminal of a pilotable ship. Interacting = "log in". The
## terminal is a sensor + signal only: it does NOT decide whether login is allowed
## (working-vessel / access gating lives in the coordinator). Mirrors the strict
## in-range interaction gate of DockPortBarrier / RepairPoint.

signal login_requested(ship_id: String)

var ship_id: String = ""
var interaction_radius: float = 1.8
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_ship_id: String, world_position: Vector3, radius := 1.8) -> void:
	assert(radius >= 0.0, "BridgeTerminal.configure: radius must be non-negative")
	ship_id = p_ship_id
	interaction_radius = radius
	position = world_position
	name = "BridgeTerminal_%s" % p_ship_id
	set_meta("bridge_terminal", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

## Emits login_requested(ship_id) and returns true iff the player is in direct range.
func try_login(player_body: Node) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("login_requested", ship_id)
	return true

func _interaction_radius() -> float:
	if is_instance_valid(collision_shape) and collision_shape.shape is SphereShape3D:
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
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "BridgeTerminalCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		marker.name = "BridgeTerminalMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.4, radius, radius * 0.4)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.7, 0.95, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_bridge_terminal_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
