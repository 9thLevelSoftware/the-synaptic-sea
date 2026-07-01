extends Area3D
class_name SealedHatch

## A locked passage on a generated ship. Blocks traversal (a StaticBody3D collider)
## until the player bypasses it with the matching utility flag: a mechanical hatch
## needs "lockpick", an electronic one needs "hack_chip". Mirrors the LootContainer
## interaction shape (Area3D proximity + try_* + a signal). Domain 5.

signal hatch_bypassed(hatch_id: String, lock_kind: String)

const MECHANICAL: String = "mechanical"
const ELECTRONIC: String = "electronic"

var hatch_id: String = ""
var lock_kind: String = MECHANICAL
var bypassed: bool = false

var _radius: float = 1.8
var _player_in_range: bool = false
var _blocker: StaticBody3D = null

func configure(p_hatch_id: String, p_lock_kind: String, world_position: Vector3, radius: float = 1.8) -> void:
	hatch_id = p_hatch_id
	lock_kind = p_lock_kind if (p_lock_kind == MECHANICAL or p_lock_kind == ELECTRONIC) else MECHANICAL
	_radius = radius
	position = world_position
	_ensure_detection(radius)
	_ensure_blocker(radius)
	_apply_blocked_state()

func required_flag() -> String:
	return "lockpick" if lock_kind == MECHANICAL else "hack_chip"

func set_bypassed(value: bool) -> void:
	bypassed = value
	_apply_blocked_state()

func set_validation_player_in_range(value: bool) -> void:
	_player_in_range = value

## Attempts to bypass using the player's active utility flags. Returns a result dict;
## on success the collider is disabled and hatch_bypassed is emitted once.
func try_bypass(player_body: Node, active_flags: Dictionary) -> Dictionary:
	if bypassed:
		return {"ok": false, "reason": "already_open", "hatch_id": hatch_id}
	if not _is_player_in_range(player_body):
		return {"ok": false, "reason": "out_of_range", "hatch_id": hatch_id}
	var flag: String = required_flag()
	if not active_flags.has(flag):
		return {"ok": false, "reason": "locked", "hatch_id": hatch_id, "needs": flag, "lock_kind": lock_kind}
	set_bypassed(true)
	hatch_bypassed.emit(hatch_id, lock_kind)
	return {"ok": true, "hatch_id": hatch_id, "lock_kind": lock_kind, "consumed_flag": flag}

func _is_player_in_range(player_body: Node) -> bool:
	if _player_in_range:
		return true
	if player_body is Node3D:
		return global_position.distance_to((player_body as Node3D).global_position) <= _radius
	return false

func _ensure_detection(radius: float) -> void:
	monitoring = true
	for child in get_children():
		if child is CollisionShape3D:
			return
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _ensure_blocker(radius: float) -> void:
	if _blocker != null and is_instance_valid(_blocker):
		return
	_blocker = StaticBody3D.new()
	_blocker.name = "HatchBlocker"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius, radius * 2.0, 0.4)
	col.shape = box
	_blocker.add_child(col)
	add_child(_blocker)

func _apply_blocked_state() -> void:
	if _blocker == null or not is_instance_valid(_blocker):
		return
	for c in _blocker.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = bypassed

func _on_body_entered(body: Node3D) -> void:
	if body != null and body is PlayerController:
		_player_in_range = true

func _on_body_exited(body: Node3D) -> void:
	if body != null and body is PlayerController:
		_player_in_range = false
