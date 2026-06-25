extends Area3D
class_name RepairPoint

## A spatial, parts-gated, timed repair node bound to one (system_id, subcomponent_id)
## of a specific ship's ShipSystemsManager. Interacting starts a Project-Zomboid-style
## channel that ticks in this node's OWN _process (independent of the coordinator's frozen
## per-frame loop). Leaving range cancels with no part loss; completing consumes the parts
## and restores the subcomponent.

signal repair_completed(system_id: String, subcomponent_id: String)
signal repair_blocked(system_id: String, subcomponent_id: String, reason: String)

var system_id: String = ""
var subcomponent_id: String = ""
var target_manager                       # ShipSystemsManager
var inventory_state                      # InventoryState
var player_progression                   # PlayerProgressionState | null
var interaction_radius: float = 1.8
var repair_seconds: float = 8.0
var min_skill: int = 0

var channeling: bool = false
var progress: float = 0.0                # 0..1
var repaired: bool = false
var _channel_player: Node = null
var _scaled_seconds: float = 1.0
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

func configure(p_system_id: String, p_subcomponent_id: String, p_target_manager, p_inventory_state, p_player_progression, world_position: Vector3, p_repair_seconds: float, p_min_skill: int, radius := 1.8) -> void:
	system_id = p_system_id
	subcomponent_id = p_subcomponent_id
	target_manager = p_target_manager
	inventory_state = p_inventory_state
	player_progression = p_player_progression
	repair_seconds = p_repair_seconds
	min_skill = p_min_skill
	interaction_radius = radius
	channeling = false
	progress = 0.0
	repaired = false
	candidate_player = null
	position = world_position
	name = "RepairPoint_%s_%s" % [p_system_id, p_subcomponent_id]
	set_meta("repair_point", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_repaired(value: bool) -> void:
	repaired = value
	channeling = false
	progress = 1.0 if value else 0.0
	set_marker_visible(marker_visible)
	if collision_shape != null:
		collision_shape.disabled = repaired

func set_marker_visible(is_visible: bool) -> void:
	marker_visible = is_visible
	if marker != null:
		marker.visible = marker_visible and not repaired

func _player_skill() -> int:
	if player_progression != null and player_progression.has_method("get_skill_level"):
		return int(player_progression.get_skill_level("repair"))
	return 0

## Begins the channel if the player is in range and a dry-run of the gated repair
## would succeed (carries parts/tools, meets skill). Returns true if the channel started.
func try_start(player_body: Node) -> bool:
	if repaired or channeling or not is_instance_valid(player_body) or target_manager == null:
		return false
	# Pure range gate (no candidate_player bypass): the player must be at the point to
	# start. The validation seam teleports the player here, so tests pass the same gate.
	if not _is_player_in_direct_range(player_body):
		return false
	# Dry-run precheck WITHOUT consuming (repair() only mutates on success; we check parts/tools/skill).
	var sub = target_manager.get_system(system_id).get_subcomponent(subcomponent_id) if target_manager.get_system(system_id) != null else null
	if sub == null:
		return false
	if sub.is_functional():
		emit_signal("repair_blocked", system_id, subcomponent_id, "already_functional")
		return false
	var skill: int = _player_skill()
	var reason: String = _precheck_reason(sub, skill)
	if reason != "ok":
		emit_signal("repair_blocked", system_id, subcomponent_id, reason)
		return false
	_channel_player = player_body
	channeling = true
	progress = 0.0
	var factor: float = 1.0 + 0.1 * float(maxi(0, skill - min_skill))
	_scaled_seconds = maxf(0.01, repair_seconds / factor)
	return true

## Returns "ok" or a rejection reason, without mutating anything.
func _precheck_reason(sub, skill: int) -> String:
	var parts: Array = []
	var tools: Array = []
	if inventory_state != null:
		for entry in inventory_state.get_items_by_category("part"):
			parts.append(String(entry["id"]))
		for entry in inventory_state.get_items_by_category("tool"):
			tools.append(String(entry["id"]))
	for part in sub.required_parts:
		if not parts.has(String(part)):
			return "missing_parts"
	for tool in sub.required_tools:
		if not tools.has(String(tool)):
			return "missing_tools"
	if skill < min_skill:
		return "insufficient_skill"
	return "ok"

func _process(delta: float) -> void:
	if not channeling:
		return
	# Cancel if the channelling player was freed or left range (PZ-style: walking away
	# aborts with no part loss). Pure range check — no candidate_player bypass.
	if not is_instance_valid(_channel_player):
		_cancel()
		return
	if not _is_player_in_direct_range(_channel_player):
		_cancel()
		return
	advance_channel(delta)

## Pumps the channel by delta; completes the repair when progress reaches 1.0.
## Exposed so a validation smoke can drive the channel deterministically.
func advance_channel(delta: float) -> void:
	if not channeling:
		return
	progress = clampf(progress + delta / _scaled_seconds, 0.0, 1.0)
	if progress >= 1.0:
		_complete()

func _complete() -> void:
	channeling = false
	var skill: int = _player_skill()
	var result: Dictionary = target_manager.repair_with_inventory(system_id, subcomponent_id, inventory_state, skill)
	if bool(result.get("success", false)):
		set_repaired(true)
		if player_progression != null and player_progression.has_method("grant_xp"):
			player_progression.grant_xp("repair", 25)
		emit_signal("repair_completed", system_id, subcomponent_id)
	else:
		# Lost the parts/tools mid-channel (shouldn't normally happen); reset to idle.
		progress = 0.0
		emit_signal("repair_blocked", system_id, subcomponent_id, String(result.get("reason", "failed")))

func _cancel() -> void:
	channeling = false
	progress = 0.0
	_channel_player = null

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var player_node: Node3D = player_body as Node3D
	# Compare global positions only; mixing local/global across coordinate spaces yields
	# wrong distances, so an out-of-tree node is simply treated as not in range.
	if not is_inside_tree() or not player_node.is_inside_tree():
		return false
	return global_position.distance_to(player_node.global_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "RepairPointCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = repaired

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "RepairPointMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.45, 0.15, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible and not repaired
	marker.set_meta("debug_repair_point_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
