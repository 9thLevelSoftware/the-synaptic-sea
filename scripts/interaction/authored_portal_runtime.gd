extends Area3D
class_name AuthoredPortalRuntime

signal portal_state_changed(portal_id: String, is_open: bool)
signal unsafe_triggered(portal_id: String)
signal exterior_exit_triggered(portal_id: String)

const DOOR := "DOOR"
const LOCKED := "LOCKED"
const LOCKED_PORTAL := "LOCKED_PORTAL"
const HATCH := "HATCH"
const BREACH := "BREACH"

var portal_id := ""
var portal_kind := DOOR
var portal_spec: Dictionary = {}
var is_open := false
var is_unsafe := false
var is_exterior := false
var _player_in_range := false
var _blocker: StaticBody3D
var _structural_blocker: Node3D
var _visual: MeshInstance3D

func configure(spec: Dictionary, world_position: Vector3) -> void:
	portal_spec = spec.duplicate(true)
	portal_id = str(spec.get("id", spec.get("portal_id", "portal")))
	portal_kind = str(spec.get("kind", spec.get("state", spec.get("type", spec.get("portal_type", DOOR))))).to_upper()
	if portal_kind == LOCKED_PORTAL:
		portal_kind = LOCKED
	is_exterior = bool(spec.get("exterior", false))
	is_unsafe = portal_kind == BREACH
	is_open = portal_kind == BREACH or (is_exterior and portal_kind not in [DOOR, LOCKED, HATCH])
	position = world_position
	var from_position: Variant = spec.get("from_position", Vector3.INF)
	var to_position: Variant = spec.get("to_position", Vector3.INF)
	if spec.has("yaw_degrees"):
		rotation_degrees.y = float(spec.get("yaw_degrees", 0.0))
	elif from_position is Vector3 and to_position is Vector3 \
			and from_position != Vector3.INF and to_position != Vector3.INF:
		var endpoint_delta: Vector3 = (to_position as Vector3) - (from_position as Vector3)
		if absf(endpoint_delta.x) > absf(endpoint_delta.z):
			rotation_degrees.y = 90.0
	monitoring = true
	monitorable = true
	collision_layer = 0
	collision_mask = 1
	_ensure_detection()
	_ensure_blocker()
	_ensure_visual()
	_apply_state()
	set_meta("authored_portal", portal_spec.duplicate(true))
	set_meta("portal_id", portal_id)
	set_meta("portal_kind", portal_kind)
	set_meta("unsafe", is_unsafe)
	set_meta("exterior", is_exterior)

func set_validation_player_in_range(value: bool) -> void:
	_player_in_range = value

func required_flag() -> String:
	var lock_kind := str(portal_spec.get("lock_kind", portal_spec.get("lock", "mechanical"))).to_lower()
	return "hack_chip" if lock_kind in ["electronic", "hack", "hack_chip"] else "lockpick"

func get_blocker_collision_shape() -> CollisionShape3D:
	if not is_instance_valid(_blocker):
		return null
	for child in _blocker.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null

func bind_structural_blocker(wrapper: Node3D) -> void:
	_structural_blocker = wrapper
	_apply_state()

func get_structural_blocker_collision_enabled_count() -> int:
	return _count_enabled_collision_shapes(_structural_blocker)

func is_structural_blocker_visible() -> bool:
	return is_instance_valid(_structural_blocker) and _structural_blocker.visible

func try_interact(active_flags: Dictionary = {}, player_body: Node = null) -> Dictionary:
	if not _is_player_in_range(player_body):
		return {"ok": false, "reason": "out_of_range", "portal_id": portal_id}
	if portal_kind == BREACH:
		is_unsafe = true
		emit_signal("unsafe_triggered", portal_id)
		return {"ok": true, "unsafe": true, "reason": "unsafe_breach", "portal_id": portal_id}
	if is_exterior:
		emit_signal("exterior_exit_triggered", portal_id)
		if portal_kind not in [LOCKED, HATCH]:
			if portal_kind == DOOR:
				var exterior_result := _toggle_open()
				exterior_result["exterior"] = true
				return exterior_result
			return {"ok": true, "exterior": true, "portal_id": portal_id}
	if portal_kind == LOCKED:
		if is_open:
			is_open = false
			_apply_state()
			emit_signal("portal_state_changed", portal_id, false)
			return {"ok": true, "open": false, "portal_id": portal_id}
		var flag := required_flag()
		if not active_flags.has(flag) or not bool(active_flags.get(flag, false)):
			return {"ok": false, "reason": "locked", "needs": flag, "portal_id": portal_id}
	return _toggle_open()

func _toggle_open() -> Dictionary:
	is_open = not is_open
	_apply_state()
	emit_signal("portal_state_changed", portal_id, is_open)
	return {"ok": true, "open": is_open, "portal_id": portal_id}

func _is_player_in_range(player_body: Node) -> bool:
	if _player_in_range:
		return true
	return is_instance_valid(player_body) and player_body is Node3D and global_position.distance_to((player_body as Node3D).global_position) <= 2.2

func _ensure_detection() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2
	shape.shape = sphere
	add_child(shape)

func _ensure_blocker() -> void:
	_blocker = StaticBody3D.new()
	_blocker.name = "PortalBlocker"
	_blocker.collision_layer = 1
	_blocker.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.4, 0.4)
	shape.shape = box
	shape.position.y = 1.2
	_blocker.add_child(shape)
	add_child(_blocker)

func _apply_state() -> void:
	var passable := is_open or is_unsafe
	_set_collision_shapes_disabled(_blocker, passable)
	_set_collision_shapes_disabled(_structural_blocker, passable)
	if is_instance_valid(_structural_blocker):
		_structural_blocker.visible = not passable
	if is_instance_valid(_visual):
		_visual.visible = not passable

func _set_collision_shapes_disabled(node: Node, disabled: bool) -> void:
	if not is_instance_valid(node):
		return
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = disabled
	for child in node.get_children():
		_set_collision_shapes_disabled(child, disabled)

func _count_enabled_collision_shapes(node: Node) -> int:
	if not is_instance_valid(node):
		return 0
	var count := 1 if node is CollisionShape3D and not (node as CollisionShape3D).disabled else 0
	for child in node.get_children():
		count += _count_enabled_collision_shapes(child)
	return count

func _ensure_visual() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "PortalVisual"
	var box := BoxMesh.new()
	box.size = Vector3(2.2, 2.4, 0.12)
	mesh.mesh = box
	mesh.position.y = 1.2
	var material := StandardMaterial3D.new()
	material.albedo_color = _kind_color()
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.25
	mesh.material_override = material
	add_child(mesh)
	_visual = mesh

func _kind_color() -> Color:
	match portal_kind:
		LOCKED: return Color(0.8, 0.55, 0.12, 1.0)
		HATCH: return Color(0.2, 0.65, 0.9, 1.0)
		BREACH: return Color(0.95, 0.18, 0.12, 0.85)
		_: return Color(0.5, 0.7, 0.75, 1.0)
