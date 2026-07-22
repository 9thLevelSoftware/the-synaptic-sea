extends Area3D
class_name FireSuppressionPoint

## Spatial, tool-gated, timed extinguish node bound to one burning compartment of a
## FireSuppressionState. Modeled on BreachSealPoint: interacting starts a channel that
## ticks in this node's OWN _process; leaving range cancels with no cost; completing
## consumes one extinguisher use and extinguishes the compartment.
##
## PKG-B2.5: progress/interrupt rides WorkActionChannel (action suppress_fire).

const WorkActionChannelScript := preload("res://scripts/systems/work_action_channel.gd")
const WORK_ACTION_ID: String = "suppress_fire"

signal fire_extinguished(compartment_id: String)
signal extinguish_blocked(compartment_id: String, reason: String)
## Fire B2: deliberate vacuum vent (no extinguisher required; decompression danger).
signal compartment_vented(compartment_id: String)

var compartment_id: String = ""
var fire_state                          # FireSuppressionState
var extinguisher_state                  # ExtinguisherState
var inventory_state                     # InventoryState
var player_progression                  # PlayerProgressionState | null
var interaction_radius: float = 1.8
var extinguish_seconds: float = 4.0
var required_tool: String = "fire_extinguisher"

var channeling: bool = false
var progress: float = 0.0
var extinguished: bool = false
var _channel_player: Node = null
var _work_channel: RefCounted = null ## WorkActionChannel while channeling
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D
var marker_visible: bool = true

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

func configure(p_compartment_id: String, p_fire_state, p_extinguisher_state, p_inventory_state, p_player_progression, world_position: Vector3, p_extinguish_seconds: float, p_required_tool: String, radius := 1.8) -> void:
	compartment_id = p_compartment_id
	fire_state = p_fire_state
	extinguisher_state = p_extinguisher_state
	inventory_state = p_inventory_state
	player_progression = p_player_progression
	extinguish_seconds = maxf(0.01, p_extinguish_seconds)
	required_tool = p_required_tool
	interaction_radius = radius
	channeling = false
	progress = 0.0
	extinguished = false
	candidate_player = null
	position = world_position
	name = "FireSuppressionPoint_%s" % p_compartment_id
	set_meta("fire_suppression_point", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func try_start(player_body: Node) -> bool:
	if extinguished or channeling or not is_instance_valid(player_body) or fire_state == null:
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	if not fire_state.is_burning(compartment_id):
		emit_signal("extinguish_blocked", compartment_id, "not_burning")
		return false
	# Fire B2: no extinguisher / empty charge → deliberate vent (instant vacuum).
	# Decompression danger is the trade-off for extinguishing without a tool.
	if not _has_required_tool() or extinguisher_state == null or not extinguisher_state.has_charge_for_use():
		return try_vent(player_body)
	var channel = WorkActionChannelScript.new()
	if not channel.begin(WORK_ACTION_ID, compartment_id, extinguish_seconds, {}):
		emit_signal("extinguish_blocked", compartment_id, "work_action")
		return false
	_work_channel = channel
	_channel_player = player_body
	channeling = true
	progress = 0.0
	return true

## Fire B2 deliberate vent: open vacuum in this compartment (kills fire, costs air).
func try_vent(player_body: Node) -> bool:
	if fire_state == null or not is_instance_valid(player_body):
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	if fire_state.has_method("is_vented") and fire_state.is_vented(compartment_id):
		emit_signal("extinguish_blocked", compartment_id, "already_vented")
		return false
	if not fire_state.has_method("deliberate_vent") or not fire_state.deliberate_vent(compartment_id):
		emit_signal("extinguish_blocked", compartment_id, "vent_failed")
		return false
	extinguished = true
	_set_extinguished_visual()
	emit_signal("compartment_vented", compartment_id)
	return true

func _has_required_tool() -> bool:
	if required_tool.is_empty():
		return true
	if inventory_state == null:
		return false
	return int(inventory_state.get_quantity(required_tool)) > 0

func _process(delta: float) -> void:
	if not channeling:
		return
	if not is_instance_valid(_channel_player) or not _is_player_in_direct_range(_channel_player):
		_cancel()
		return
	advance_channel(delta)

func advance_channel(delta: float) -> void:
	if not channeling or _work_channel == null:
		return
	var st: String = str(_work_channel.call("tick", delta, {}))
	progress = float(_work_channel.call("progress_ratio"))
	if st == "completed" or progress >= 1.0:
		_complete()

func _complete() -> void:
	channeling = false
	if _work_channel != null:
		_work_channel.call("cancel")
		_work_channel = null
	if extinguisher_state == null or not extinguisher_state.has_charge_for_use():
		progress = 0.0
		emit_signal("extinguish_blocked", compartment_id, "no_charge")
		return
	if not _has_required_tool():
		progress = 0.0
		emit_signal("extinguish_blocked", compartment_id, "missing_extinguisher")
		return
	extinguisher_state.consume_use()
	if fire_state.extinguish(compartment_id):
		extinguished = true
		_set_extinguished_visual()
		if player_progression != null and player_progression.has_method("grant_xp"):
			player_progression.grant_xp("repair", 10)
		emit_signal("fire_extinguished", compartment_id)
	else:
		progress = 0.0
		emit_signal("extinguish_blocked", compartment_id, "extinguish_failed")

func _cancel() -> void:
	channeling = false
	progress = 0.0
	_channel_player = null
	if _work_channel != null:
		_work_channel.call("cancel")
		_work_channel = null


## PKG-B2.5: catalog action driving this channel (empty when idle).
func get_work_action_id() -> String:
	if _work_channel != null:
		return str(_work_channel.get("action_id"))
	return ""

func _set_extinguished_visual() -> void:
	if collision_shape != null:
		collision_shape.disabled = true
	if marker != null:
		marker.visible = false

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var player_node: Node3D = player_body as Node3D
	if not is_inside_tree() or not player_node.is_inside_tree():
		return false
	return global_position.distance_to(player_node.global_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "FireSuppressionCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = extinguished

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "FireSuppressionMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.45, 0.1, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible and not extinguished
	marker.set_meta("debug_fire_suppression_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
