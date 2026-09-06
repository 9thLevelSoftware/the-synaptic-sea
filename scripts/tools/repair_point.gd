extends Area3D
class_name RepairPoint

## A spatial, parts-gated, timed repair node bound to one (system_id, subcomponent_id)
## of a specific ship's ShipSystemsManager. Interacting starts a Project-Zomboid-style
## channel that ticks in this node's OWN _process (independent of the coordinator's frozen
## per-frame loop). Environmental interruption pauses exact escrow and progress;
## completing commits the parts and restores the subcomponent once.
##
## PKG-B2.5: progress/interrupt rides WorkActionChannel (action repair_subcomponent).
## Domain gates and the once-only transaction commit stay here; authored repair_point
## remains the objective wrapper.

const WorkActionChannelScript := preload("res://scripts/systems/work_action_channel.gd")
const ShipWorkTransactionScript := preload("res://scripts/systems/ship_work_transaction.gd")
const WORK_ACTION_ID: String = "repair_subcomponent"

signal repair_completed(system_id: String, subcomponent_id: String)
signal repair_blocked(system_id: String, subcomponent_id: String, reason: String)
## Stream E: fired when a channel successfully begins (prechecks passed). The
## coordinator uses this for diagnose_fault training — identifying the broken
## subcomponent is the diagnostic act; completing the channel is the repair act.
signal repair_started(system_id: String, subcomponent_id: String)

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
var _work_channel: RefCounted = null ## WorkActionChannel while channeling
var _transaction: RefCounted = null ## ShipWorkTransaction
var _work_id: String = ""
var _ship_id: String = ""
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

func configure(p_system_id: String, p_subcomponent_id: String, p_target_manager, p_inventory_state, p_player_progression, world_position: Vector3, p_repair_seconds: float, p_min_skill: int, radius := 1.8, p_ship_id: String = "legacy_ship", p_transaction = null) -> void:
	system_id = p_system_id
	subcomponent_id = p_subcomponent_id
	target_manager = p_target_manager
	inventory_state = p_inventory_state
	player_progression = p_player_progression
	repair_seconds = p_repair_seconds
	min_skill = p_min_skill
	interaction_radius = radius
	_ship_id = p_ship_id if not p_ship_id.is_empty() else "legacy_ship"
	if p_transaction != null and str(p_transaction.get("ship_id")) == _ship_id:
		_transaction = p_transaction
	else:
		_transaction = ShipWorkTransactionScript.new()
		_transaction.configure(_ship_id)
	_work_id = ""
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
	if channeling:
		# Already repairing — consume interact so lower-priority handlers do not fire.
		return true
	if repaired or not is_instance_valid(player_body) or target_manager == null:
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
		return true  # consume interact (blocked SFX via signal); channel not started
	var skill: int = _player_skill()
	var reason: String = _precheck_reason(sub, skill)
	if reason != "ok":
		emit_signal("repair_blocked", system_id, subcomponent_id, reason)
		return true
	var factor: float = 1.0 + 0.1 * float(maxi(0, skill - min_skill))
	_scaled_seconds = maxf(0.01, repair_seconds / factor)
	var requirements: Dictionary = {}
	for part in sub.required_parts:
		requirements[String(part)] = int(requirements.get(String(part), 0)) + 1
	var selected_ids: PackedStringArray = _selected_part_lot_ids(requirements)
	if not requirements.is_empty() and selected_ids.is_empty():
		emit_signal("repair_blocked", system_id, subcomponent_id, "missing_parts")
		return true
	_work_id = _transaction.create_work_id("repair_subcomponent")
	var prepared: Dictionary = _transaction.prepare({
		"work_id": _work_id,
		"ship_id": _ship_id,
		"target_id": "%s/%s" % [system_id, subcomponent_id],
		"target_revision": _target_revision(),
		"action_id": WORK_ACTION_ID,
		"source_holder_id": inventory_state.get_holder_namespace(),
		"selected_lot_ids": selected_ids,
		"replacement_catalog_id": "",
	}, inventory_state, requirements)
	if not bool(prepared.get("ok", false)):
		_work_id = ""
		emit_signal("repair_blocked", system_id, subcomponent_id, str(prepared.get("reason", "reserve_failed")))
		return true
	var channel = WorkActionChannelScript.new()
	var target_key: String = "%s/%s" % [system_id, subcomponent_id]
	if not channel.begin(WORK_ACTION_ID, target_key, _scaled_seconds, {}):
		_transaction.cancel(_work_id, inventory_state, null, "work_action")
		_work_id = ""
		emit_signal("repair_blocked", system_id, subcomponent_id, "work_action")
		return true
	if not _transaction.activate(_work_id):
		_transaction.cancel(_work_id, inventory_state, null, "work_action")
		_work_id = ""
		emit_signal("repair_blocked", system_id, subcomponent_id, "work_action")
		return true
	_work_channel = channel
	_channel_player = player_body
	channeling = true
	progress = 0.0
	emit_signal("repair_started", system_id, subcomponent_id)
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
	# Environmental gates pause the paid work. Returning to a valid range/tool state
	# resumes from the same progress; only explicit cancellation refunds escrow.
	if not is_instance_valid(_channel_player):
		_pause("missing_player")
		return
	if not _is_player_in_direct_range(_channel_player):
		_pause("out_of_range")
		return
	if not _required_tools_present():
		_pause("missing_tool")
		return
	if _target_revision() != str(_transaction.get_record(_work_id).get("target_revision", "")):
		_pause("stale_target")
		return
	if _work_channel != null and bool(_work_channel.call("is_paused")) and not _resume():
		return
	advance_channel(delta)

## Pumps the channel by delta; completes the repair when progress reaches 1.0.
## Exposed so a validation smoke can drive the channel deterministically.
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
	if _transaction == null or _work_id.is_empty() or not _transaction.mark_channel_completed(_work_id):
		progress = 0.0
		emit_signal("repair_blocked", system_id, subcomponent_id, "transaction")
		return
	var receipt: Dictionary = _transaction.commit(_work_id, {
		"ship_id": _ship_id,
		"target_id": "%s/%s" % [system_id, subcomponent_id],
		"target_exists": not _target_revision().is_empty(),
		"target_revision": _target_revision(),
		"in_range": _is_player_in_direct_range(_channel_player),
		"has_required_tool": _required_tools_present(),
		"damaged": false,
		"stage": func(_record: Dictionary) -> Dictionary: return {"ok": true},
		"commit": Callable(self, "_commit_reserved_repair"),
	})
	if bool(receipt.get("ok", false)):
		set_repaired(true)
	else:
		progress = 0.0
		emit_signal("repair_blocked", system_id, subcomponent_id, String(receipt.get("reason", "failed")))
	# Keep the committed receipt addressable for idempotent retries; only the active
	# handle clears.
	if bool(receipt.get("ok", false)):
		_work_id = ""


func _cancel(reason: String = "explicit_cancel") -> void:
	if _transaction != null and not _work_id.is_empty() and inventory_state != null:
		_transaction.cancel(_work_id, inventory_state, null, reason)
	channeling = false
	progress = 0.0
	_channel_player = null
	if _work_channel != null:
		_work_channel.call("cancel")
		_work_channel = null
	_work_id = ""


func _pause(reason: String) -> bool:
	if _work_channel == null or _transaction == null or _work_id.is_empty():
		return false
	var was_paused: bool = bool(_work_channel.call("is_paused"))
	var previous_reason: String = str(_transaction.call("get_record", _work_id).get("last_reason", ""))
	if not was_paused and not bool(_work_channel.call("pause")):
		return false
	if not bool(_transaction.call("pause_channel", _work_id, progress, reason)):
		if not was_paused:
			_work_channel.call("resume", {})
		return false
	progress = float(_work_channel.call("progress_ratio"))
	if not was_paused or previous_reason != reason:
		emit_signal("repair_blocked", system_id, subcomponent_id, reason)
	return true


func _resume() -> bool:
	if _work_channel == null or _transaction == null or _work_id.is_empty():
		return false
	if not bool(_transaction.call("resume_channel", _work_id)):
		return false
	if not bool(_work_channel.call("resume", {})):
		_transaction.call("pause_channel", _work_id, progress, "resume_failed")
		return false
	return true


func cancel_work(reason: String = "explicit_cancel") -> bool:
	if not channeling:
		return false
	_cancel(reason)
	return true


func interrupt_on_damage() -> bool:
	if not channeling:
		return false
	return _pause("damaged")


func get_reserved_lots() -> Array:
	return _transaction.get_escrow(_work_id) if _transaction != null and not _work_id.is_empty() else []


func _selected_part_lot_ids(requirements: Dictionary) -> PackedStringArray:
	var selected: PackedStringArray = PackedStringArray()
	if inventory_state == null or not inventory_state.has_method("get_lot_summary"):
		return selected
	var lots: Array = inventory_state.get_lot_summary().get("lots", []) as Array
	var ids: Array = requirements.keys()
	ids.sort()
	for item_v in ids:
		var item_id: String = str(item_v)
		var candidates: Array = []
		for lot_v in lots:
			if lot_v is Dictionary and str((lot_v as Dictionary).get("item_id", "")) == item_id:
				candidates.append(lot_v as Dictionary)
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("lot_id", "")) < str(b.get("lot_id", "")))
		var remaining: int = int(requirements[item_v])
		for lot in candidates:
			if remaining <= 0:
				break
			selected.append(str((lot as Dictionary).get("lot_id", "")))
			remaining -= int((lot as Dictionary).get("quantity", 0))
		if remaining > 0:
			return PackedStringArray()
	return selected


func _target_revision() -> String:
	if target_manager == null:
		return ""
	var system = target_manager.get_system(system_id)
	var sub = system.get_subcomponent(subcomponent_id) if system != null else null
	if sub == null:
		return ""
	return "%s/%s|%.5f" % [system_id, subcomponent_id, float(sub.health)]


func _required_tools_present() -> bool:
	if target_manager == null or inventory_state == null:
		return false
	var system = target_manager.get_system(system_id)
	var sub = system.get_subcomponent(subcomponent_id) if system != null else null
	if sub == null:
		return false
	for tool in sub.required_tools:
		if inventory_state.get_quantity(String(tool)) <= 0:
			return false
	return true


func _commit_reserved_repair(record: Dictionary) -> Dictionary:
	var parts: Array = []
	for lot_v in record.get("escrow", []) as Array:
		if lot_v is Dictionary:
			parts.append(str((lot_v as Dictionary).get("item_id", "")))
	var tools: Array = []
	if inventory_state != null:
		for entry in inventory_state.get_items_by_category("tool"):
			tools.append(String(entry["id"]))
	var result: Dictionary = target_manager.repair(system_id, subcomponent_id, parts, tools, _player_skill())
	if not bool(result.get("success", false)):
		return {"ok": false, "reason": str(result.get("reason", "repair_failed"))}
	if player_progression != null and player_progression.has_method("grant_xp"):
		player_progression.grant_xp("repair", 25)
	emit_signal("repair_completed", system_id, subcomponent_id)
	return {
		"ok": true,
		"awarded_event_ids": ["repair"],
		"noise": 0.35,
		"committed_target_revision": _target_revision(),
	}


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
