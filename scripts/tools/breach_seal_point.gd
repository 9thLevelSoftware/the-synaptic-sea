extends Area3D
class_name BreachSealPoint

## A spatial, item-gated, timed seal node bound to one hull compartment of a
## HullIntegrityState. Modeled on RepairPoint: interacting starts a channel that ticks in
## this node's OWN _process; leaving range cancels with no item loss; completing consumes
## the sealant and seals the compartment.
##
## PKG-B2.5: progress/interrupt rides WorkActionChannel (action patch_breach).

const WorkActionChannelScript := preload("res://scripts/systems/work_action_channel.gd")
const WORK_ACTION_ID: String = "patch_breach"

signal breach_sealed(compartment_id: String)
signal seal_blocked(compartment_id: String, reason: String)

var compartment_id: String = ""
var hull_state                          # HullIntegrityState
var inventory_state                     # InventoryState
var player_progression                  # PlayerProgressionState | null
var interaction_radius: float = 1.8
var seal_seconds: float = 4.0
var required_item: String = "hull_sealant"
var seal_amount: float = 1.0

var channeling: bool = false
var progress: float = 0.0
var sealed: bool = false
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

func configure(p_compartment_id: String, p_hull_state, p_inventory_state, p_player_progression, world_position: Vector3, p_seal_seconds: float, p_required_item: String, p_seal_amount: float, radius := 1.8) -> void:
	compartment_id = p_compartment_id
	hull_state = p_hull_state
	inventory_state = p_inventory_state
	player_progression = p_player_progression
	seal_seconds = maxf(0.01, p_seal_seconds)
	required_item = p_required_item
	seal_amount = maxf(0.0, p_seal_amount)
	interaction_radius = radius
	channeling = false
	progress = 0.0
	sealed = false
	candidate_player = null
	position = world_position
	name = "BreachSealPoint_%s" % p_compartment_id
	set_meta("breach_seal_point", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_sealed(value: bool) -> void:
	sealed = value
	channeling = false
	progress = 1.0 if value else 0.0
	if collision_shape != null:
		collision_shape.disabled = sealed
	if marker != null:
		marker.visible = marker_visible and not sealed

## Begins the channel if the player is in range and a dry-run would succeed.
func try_start(player_body: Node) -> bool:
	if channeling:
		# Already sealing — consume interact so lower-priority handlers do not fire.
		return true
	if sealed or not is_instance_valid(player_body) or hull_state == null:
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	if not hull_state.compartments.has(compartment_id):
		return false
	if not bool((hull_state.compartments[compartment_id] as Dictionary).get("breach_open", false)):
		emit_signal("seal_blocked", compartment_id, "not_breached")
		return false
	if not _has_required_item():
		emit_signal("seal_blocked", compartment_id, "missing_sealant")
		return false
	var sealant_qty: int = 0
	if inventory_state != null:
		sealant_qty = int(inventory_state.get_quantity(required_item))
	var ctx: Dictionary = {
		"tool_class": "sealant",
		"skill_id": "repair",
		"skill_level": 0,
		"inventory": {required_item: sealant_qty},
	}
	var channel = WorkActionChannelScript.new()
	if not channel.begin(WORK_ACTION_ID, compartment_id, seal_seconds, ctx):
		emit_signal("seal_blocked", compartment_id, "work_action")
		return false
	_work_channel = channel
	_channel_player = player_body
	channeling = true
	progress = 0.0
	return true

func _has_required_item() -> bool:
	if inventory_state == null:
		return false
	if required_item.is_empty():
		return true
	return int(inventory_state.get_quantity(required_item)) > 0

func _process(delta: float) -> void:
	if not channeling:
		return
	if not is_instance_valid(_channel_player) or not _is_player_in_direct_range(_channel_player):
		_cancel()
		return
	advance_channel(delta)

## Pumps the channel by delta; seals when progress reaches 1.0. Exposed for smokes.
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
	if not _has_required_item():
		progress = 0.0
		emit_signal("seal_blocked", compartment_id, "missing_sealant")
		return
	if not required_item.is_empty():
		inventory_state.remove_item(required_item, 1)
	if hull_state.seal_compartment(compartment_id, seal_amount):
		set_sealed(true)
		if player_progression != null and player_progression.has_method("grant_xp"):
			player_progression.grant_xp("repair", 15)
		emit_signal("breach_sealed", compartment_id)
	else:
		progress = 0.0
		emit_signal("seal_blocked", compartment_id, "seal_failed")

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
		collision_shape.name = "BreachSealCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = sealed

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "BreachSealMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.95, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible and not sealed
	marker.set_meta("debug_breach_seal_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
