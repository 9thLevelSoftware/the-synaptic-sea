extends Area3D
class_name LootContainer

## Searchable loot container. Rust-authored `generated_items` take precedence,
## followed by authored `contents` (including explicit empty); only contexts with
## neither key roll the table deterministically. The selected path grants into the
## player InventoryState and then marks the container searched. Mirrors
## ToolPickup's interaction/range contract.

const LootDistributionScript := preload("res://scripts/systems/loot_distribution.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
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

const MAX_EXACT_DROP_ENTRIES: int = 64


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
	if loot_context.has("generated_items"):
		granted = _grant_generated_items()
	elif loot_context.has("contents"):
		granted = _grant_authored_contents()
	else:
		granted = _grant_rolled_contents()
	# Searching consumes the container even if the bag was full (no re-roll on revisit).
	set_searched(true)
	emit_signal("container_searched", container_id, granted)
	return true

func _grant_authored_contents() -> Array:
	var granted: Array = []
	var item_defs: Dictionary = loot_context.get("item_definitions", ItemDefsScript.load_definitions())
	if typeof(item_defs) != TYPE_DICTIONARY:
		item_defs = ItemDefsScript.load_definitions()
	var unique_state = loot_context.get("unique_state", null)
	for stack_v in normalized_contents(loot_context):
		if not (stack_v is Dictionary):
			continue
		var stack: Dictionary = stack_v
		var item_id: String = str(stack.get("item_id", ""))
		var qty: int = int(stack.get("quantity", stack.get("qty", 0)))
		if item_id.is_empty() or qty <= 0:
			continue
		var unique_id: String = str(stack.get("unique_id", ItemDefsScript.unique_id(item_defs, item_id)))
		var seed_key: String = str(stack.get("seed_key", "%s|%s" % [seed_source, item_id]))
		var codex_entry_id: String = str(stack.get("codex_entry_id", ItemDefsScript.codex_entry_id(item_defs, item_id)))
		if unique_state != null and not unique_id.is_empty() and unique_state.has_method("can_claim"):
			if not bool(unique_state.can_claim(unique_id, seed_key)):
				continue
		var added: int = inventory_state.add_item(item_id, qty)
		if added <= 0:
			continue
		var grant_entry: Dictionary = {
			"item_id": item_id,
			"quantity": added,
			"seed_key": seed_key,
		}
		if not unique_id.is_empty():
			grant_entry["unique_id"] = unique_id
			grant_entry["world_unique"] = true
		if not codex_entry_id.is_empty():
			grant_entry["codex_entry_id"] = codex_entry_id
		granted.append(grant_entry)
	return granted

func _grant_rolled_contents() -> Array:
	var granted: Array = []
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
	return granted

func _grant_generated_items() -> Array:
	var explicit: Dictionary = _explicit_generated_items()
	var granted: Array = []
	for entry_v in (explicit.get("items", []) as Array):
		var entry: Dictionary = entry_v as Dictionary
		var item_id: String = str(entry.get("item_id", ""))
		var qty: int = int(entry.get("quantity", 0))
		if inventory_state.has_method("register_generated_item") \
				and not bool(inventory_state.call("register_generated_item", entry)):
			continue
		var added: int = inventory_state.add_item(item_id, qty)
		if added > 0:
			var grant_entry: Dictionary = entry.duplicate(true)
			grant_entry["quantity"] = added
			granted.append(grant_entry)
	return granted

func _explicit_generated_items() -> Dictionary:
	if not loot_context.has("generated_items"):
		return {"present": false, "items": []}
	var raw: Variant = loot_context.get("generated_items")
	if typeof(raw) != TYPE_ARRAY:
		return {"present": true, "items": []}
	var entries: Array = raw as Array
	if entries.size() > MAX_EXACT_DROP_ENTRIES:
		return {"present": true, "items": []}
	var validated: Array = []
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return {"present": true, "items": []}
		var entry: Dictionary = raw_entry as Dictionary
		if typeof(entry.get("item_id", null)) != TYPE_STRING or str(entry.get("item_id", "")).is_empty():
			return {"present": true, "items": []}
		var quantity: Variant = entry.get("quantity", null)
		if typeof(quantity) != TYPE_INT or int(quantity) != 1:
			return {"present": true, "items": []}
		validated.append(entry.duplicate(true))
	return {"present": true, "items": validated}

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
