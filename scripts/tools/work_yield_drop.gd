extends Area3D
class_name WorkYieldDrop

const ItemLotLedgerScript := preload("res://scripts/systems/item_lot_ledger.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")

## Floor drop for WorkAction yields that could not fit the cart (overload).
## Interact once to scoop items into InventoryState; then free.

signal scooped(drop_id: String, granted: Dictionary)

var drop_id: String = ""
var owning_ship_id: String = ""
var _lot_ledger
var items: Dictionary:
	get: return _lot_ledger.get_quantities() if _lot_ledger != null else {}
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
		radius: float = 1.8,
		p_owning_ship_id: String = "") -> void:
	drop_id = p_drop_id
	owning_ship_id = p_owning_ship_id
	_lot_ledger = ItemLotLedgerScript.new({}, "floor:%s" % p_drop_id)
	var ids: Array = p_items.keys()
	ids.sort()
	for item_id in ids:
		_lot_ledger.add_standard(str(item_id), int(p_items[item_id]))
	inventory_state = p_inventory_state
	interaction_radius = radius
	scooped_flag = false
	position = world_position
	name = "WorkYieldDrop_%s" % drop_id
	set_meta("work_yield_drop", true)
	_ensure_collision(radius)
	_ensure_marker()

## Restores a dropped holder without reducing its lots to aggregate quantities.
func configure_lots(p_drop_id: String, lot_summary: Dictionary, p_inventory_state, world_position: Vector3, radius: float = 1.8, p_owning_ship_id: String = "") -> bool:
	_lot_ledger = ItemLotLedgerScript.new({}, "floor:%s" % p_drop_id)
	if not _lot_ledger.apply_summary(lot_summary, "floor:%s" % p_drop_id):
		return false
	drop_id = p_drop_id
	owning_ship_id = p_owning_ship_id
	inventory_state = p_inventory_state
	interaction_radius = radius
	scooped_flag = false
	position = world_position
	name = "WorkYieldDrop_%s" % drop_id
	set_meta("work_yield_drop", true)
	_ensure_collision(radius)
	_ensure_marker()
	return true

func get_quantity(item_id: String) -> int:
	return _lot_ledger.get_quantity(item_id)

func get_acceptable_quantity(_item_id: String, qty: int) -> int:
	# Floor piles have no mass policy. Their ledger remains the authoritative
	# per-item stack guard when the complete incoming lot is deposited.
	return maxi(0, qty)

func take_lots(item_id: String, qty: int, preferred_ids: PackedStringArray = PackedStringArray()) -> Array:
	return _lot_ledger.take_lots(item_id, qty, preferred_ids)

func add_lot(lot: Dictionary) -> int:
	return _lot_ledger.add_lot(lot)

func get_lot_summary() -> Dictionary:
	return _lot_ledger.get_summary()

func get_persistence_descriptor() -> Dictionary:
	if drop_id.is_empty() or owning_ship_id.is_empty() or _lot_ledger == null:
		return {}
	var value: Transform3D = transform
	return {
		"drop_id": drop_id,
		"ship_id": owning_ship_id,
		"transform": [
			value.basis.x.x, value.basis.x.y, value.basis.x.z,
			value.basis.y.x, value.basis.y.y, value.basis.y.z,
			value.basis.z.x, value.basis.z.y, value.basis.z.z,
			value.origin.x, value.origin.y, value.origin.z,
		],
		"item_lots_v1": _lot_ledger.get_summary(),
	}


func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body


## True when the player is in scoop range of a still-live pile (stack-full deny still counts).
func is_interact_candidate(player_body: Node) -> bool:
	if scooped_flag or not is_instance_valid(player_body):
		return false
	return candidate_player == player_body or _in_range(player_body)


func try_interact(player_body: Node) -> bool:
	if scooped_flag or inventory_state == null or not is_instance_valid(player_body):
		return false
	if candidate_player != player_body and not _in_range(player_body):
		return false
	var granted: Dictionary = {}
	var item_ids: Array = items.keys()
	item_ids.sort()
	for item_id in item_ids:
		var qty: int = get_quantity(str(item_id))
		if qty <= 0:
			continue
		var added: int = CargoTransferScript.move_item(self, inventory_state, str(item_id), qty)
		if added > 0:
			granted[str(item_id)] = added
	if granted.is_empty():
		# Inventory full / cannot accept — leave drop in place for later scoop.
		return false
	# Clear fully taken stacks; keep residual for partial scoops.
	var remaining: Dictionary = items
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
