extends Area3D
class_name ToolPickup

## REQ-007 pickup node. Carries a single tool id; interacting with the
## player body adds the id to InventoryState exactly once, hides the
## marker + collision, and emits tool_acquired so the coordinator can
## refresh the HUD and log the event.
##
## The node never reaches into the inventory data model on its own
## besides add_tool: it asks the inventory_state (owned by the
## coordinator) to record the tool, then announces.

signal tool_acquired(tool_id: String)

var tool_id: String = ""
var inventory_state: InventoryState
var interaction_radius: float = 1.8
var acquired: bool = false
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D
var marker_visible: bool = true

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_tool_id: String, p_inventory_state: InventoryState, world_position: Vector3, radius := 1.8) -> void:
	tool_id = p_tool_id
	inventory_state = p_inventory_state
	interaction_radius = radius
	acquired = false
	candidate_player = null
	position = world_position
	name = "ToolPickup_%s" % p_tool_id
	set_meta("tool_id", tool_id)
	set_meta("tool_pickup", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_marker_visible(is_visible: bool) -> void:
	marker_visible = is_visible
	if marker != null:
		marker.visible = marker_visible and not acquired

## True when the player is in range of a still-live pickup (already-owned deny still counts).
func is_interact_candidate(player_body: Node) -> bool:
	if acquired or player_body == null:
		return false
	return _is_player_in_direct_range(player_body)


func try_interact(player_body: Node) -> bool:
	if acquired:
		return false
	if player_body == null:
		return false
	# Always require the player to be within direct range at the moment of
	# the interaction. We do not trust candidate_player alone because the
	# player can be teleported (e.g. by a validation seam) without firing
	# body_exited, leaving a stale candidate_player set.
	if not _is_player_in_direct_range(player_body):
		return false
	if inventory_state == null:
		return false
	if not inventory_state.add_tool(tool_id):
		return false
	acquired = true
	set_marker_visible(false)
	if collision_shape != null:
		collision_shape.disabled = true
	emit_signal("tool_acquired", tool_id)
	return true

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		var sphere_shape: SphereShape3D = collision_shape.shape as SphereShape3D
		return sphere_shape.radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not (player_body is Node3D):
		return false
	var player_node: Node3D = player_body as Node3D
	var pickup_position: Vector3 = global_position if is_inside_tree() else position
	var player_position: Vector3 = player_node.global_position if player_node.is_inside_tree() else player_node.position
	return pickup_position.distance_to(player_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "ToolPickupCollisionShape3D"
		add_child(collision_shape)
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = radius
	collision_shape.shape = sphere_shape

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "ToolPickupMarker"
		add_child(marker)
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = Vector3(radius * 0.6, radius * 0.6, radius * 0.6)
	marker.mesh = box_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.75, 0.95, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible and not acquired
	marker.set_meta("debug_tool_pickup_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null