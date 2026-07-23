extends Area3D
class_name WorkYieldDrop

## Floor drop for WorkAction yields that could not fit the cart (overload).
## Interact once to scoop items into InventoryState; then free.

signal scooped(drop_id: String, granted: Dictionary)

var drop_id: String = ""
var items: Dictionary = {}  # item_id -> qty
var inventory_state = null
var interaction_radius: float = 1.8
var scooped_flag: bool = false
var candidate_player: Node = null
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


func configure(
		p_drop_id: String,
		p_items: Dictionary,
		p_inventory_state,
		world_position: Vector3,
		radius: float = 1.8) -> void:
	drop_id = p_drop_id
	items = p_items.duplicate(true)
	inventory_state = p_inventory_state
	interaction_radius = radius
	scooped_flag = false
	position = world_position
	name = "WorkYieldDrop_%s" % drop_id
	set_meta("work_yield_drop", true)
	_ensure_collision(radius)
	_ensure_marker()


func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body


func try_interact(player_body: Node) -> bool:
	if scooped_flag or inventory_state == null or not is_instance_valid(player_body):
		return false
	if candidate_player != player_body and not _in_range(player_body):
		return false
	var granted: Dictionary = {}
	for item_id in items.keys():
		var qty: int = int(items[item_id])
		if qty <= 0:
			continue
		var added: int = 0
		if inventory_state.has_method("add_item"):
			added = int(inventory_state.call("add_item", str(item_id), qty))
		if added > 0:
			granted[str(item_id)] = added
			items[item_id] = qty - added
	if granted.is_empty():
		# Inventory full / cannot accept — leave drop in place for later scoop.
		return false
	# Clear fully taken stacks; keep residual for partial scoops.
	var remaining: Dictionary = {}
	for item_id2 in items.keys():
		var left: int = int(items[item_id2])
		if left > 0:
			remaining[str(item_id2)] = left
	items = remaining
	if remaining.is_empty():
		scooped_flag = true
		scooped.emit(drop_id, granted)
		if marker != null:
			marker.visible = false
		if collision_shape != null:
			collision_shape.disabled = true
		queue_free()
	else:
		# Partial scoop: keep the pile, emit granted portion.
		scooped.emit(drop_id, granted)
	return true


func _ensure_collision(radius: float) -> void:
	if collision_shape != null:
		return
	collision_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	add_child(collision_shape)


func _ensure_marker() -> void:
	if marker != null:
		return
	marker = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.25, 0.35)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.25, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	marker.position = Vector3(0, 0.2, 0)
	add_child(marker)


func _in_range(player_body: Node) -> bool:
	if not (player_body is Node3D):
		return false
	return global_position.distance_to((player_body as Node3D).global_position) <= interaction_radius + 0.15


func _on_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		candidate_player = body


func _on_body_exited(body: Node) -> void:
	if body == candidate_player:
		candidate_player = null
