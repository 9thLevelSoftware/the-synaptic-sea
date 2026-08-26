extends Area3D
class_name LootContainer

## Searchable loot container. On first interaction it grants `loot_context.contents`
## when present (authored stacks), otherwise rolls its table deterministically
## (seed = container's seed_source) into the player InventoryState, then marks
## itself searched. Mirrors ToolPickup's interaction/range contract.

const LootDistributionScript := preload("res://scripts/systems/loot_distribution.gd")
const GameplayPropFactoryScript := preload("res://scripts/placement/gameplay_prop_factory.gd")

signal container_searched(container_id: String, granted: Array)

var container_id: String = ""
var loot_table: String = ""
var seed_source: String = ""
var inventory_state                       # InventoryState
var tables: Dictionary = {}
var loot_context: Dictionary = {}
var interaction_radius: float = 1.8
var searched: bool = false
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

func configure(p_container_id: String, p_loot_table: String, p_seed_source: String, p_inventory_state, p_tables: Dictionary, world_position: Vector3, radius := 1.8, p_loot_context: Dictionary = {}) -> void:
	container_id = p_container_id
	loot_table = p_loot_table
	seed_source = p_seed_source
	inventory_state = p_inventory_state
	tables = p_tables
	loot_context = p_loot_context.duplicate(true)
	interaction_radius = radius
	searched = false
	candidate_player = null
	position = world_position
	name = "LootContainer_%s" % p_container_id
	set_meta("loot_container", true)
	set_meta("container_id", container_id)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_searched(value: bool) -> void:
	searched = value
	set_marker_visible(marker_visible)
	if collision_shape != null:
		collision_shape.disabled = searched

func set_marker_visible(is_visible: bool) -> void:
	marker_visible = is_visible
	if marker != null:
		marker.visible = marker_visible and not searched

## Explicit authored stacks (`contents` on the slice spec / loot_context).
## Accepts `qty` or `quantity`. Empty / invalid stacks are dropped.
static func normalized_contents(spec: Dictionary) -> Array:
	var raw: Variant = spec.get("contents", [])
	if not (raw is Array):
		return []
	var out: Array = []
	for stack_v in (raw as Array):
		if not (stack_v is Dictionary):
			continue
		var stack: Dictionary = stack_v
		var item_id: String = str(stack.get("item_id", ""))
		var qty: int = int(stack.get("qty", stack.get("quantity", 0)))
		if item_id.is_empty() or qty <= 0:
			continue
		out.append({"item_id": item_id, "qty": qty, "quantity": qty})
	return out

func try_interact(player_body: Node) -> bool:
	if searched or not is_instance_valid(player_body) or inventory_state == null:
		return false
	# Mirrors Interactable's validation bypass (derelict-placed sibling), not ToolPickup's
	# stricter always-check. Accepts risk of stale candidate_player after teleport-without-
	# body_exited (false bypass: one-time early search from out of range), because a
	# container is single-use, and the validation seam also relies on this pattern.
	if candidate_player != player_body and not _is_player_in_direct_range(player_body):
		return false
	var granted: Array = []
	var authored: Array = normalized_contents(loot_context)
	if not authored.is_empty():
		for stack_v in authored:
			var stack: Dictionary = stack_v
			var item_id: String = str(stack.get("item_id", ""))
			var qty: int = int(stack.get("quantity", stack.get("qty", 0)))
			if item_id.is_empty() or qty <= 0:
				continue
			var added: int = inventory_state.add_item(item_id, qty)
			if added > 0:
				granted.append({"item_id": item_id, "quantity": added})
	else:
		var rolled: Array = LootDistributionScript.roll(loot_table, seed_source, tables, loot_context)
		for entry in rolled:
			var item_id: String = str((entry as Dictionary).get("item_id", ""))
			var qty: int = int((entry as Dictionary).get("quantity", 0))
			if item_id.is_empty() or qty <= 0:
				continue
			var added: int = inventory_state.add_item(item_id, qty)
			if added > 0:
				var grant_entry: Dictionary = (entry as Dictionary).duplicate(true)
				grant_entry["quantity"] = added
				granted.append(grant_entry)
	# Searching consumes the container even if the bag was full (no re-roll on revisit).
	set_searched(true)
	emit_signal("container_searched", container_id, granted)
	return true

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var player_node: Node3D = player_body as Node3D
	var here: Vector3 = global_position if is_inside_tree() else position
	var there: Vector3 = player_node.global_position if player_node.is_inside_tree() else player_node.position
	return here.distance_to(there) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "LootContainerCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = searched

func _ensure_marker(radius: float) -> void:
	if marker == null:
		var prop_id: String = "corpse_bag" if container_id.begins_with("corpse_") else "loot_crate"
		var visual: Node3D = GameplayPropFactoryScript.build(prop_id)
		visual.name = "GameplayPropVisual"
		add_child(visual)
		marker = visual.get_node("Mesh") as MeshInstance3D
	marker.visible = marker_visible and not searched
	marker.set_meta("debug_loot_container_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
