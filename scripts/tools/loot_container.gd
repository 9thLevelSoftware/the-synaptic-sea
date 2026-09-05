extends Area3D
class_name LootContainer

## Searchable loot container. On first interaction it grants `loot_context.contents`
## when that key is present (authored stacks, including explicit empty), otherwise
## rolls its table deterministically (seed = container's seed_source) into the
## player InventoryState, then marks itself searched. Mirrors ToolPickup's
## interaction/range contract.

const LootDistributionScript := preload("res://scripts/systems/loot_distribution.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")
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
		var normalized: Dictionary = stack.duplicate(true)
		normalized["item_id"] = item_id
		normalized["qty"] = qty
		normalized["quantity"] = qty
		out.append(normalized)
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
	if loot_context.has("contents"):
		if not _can_accept_contents(normalized_contents(loot_context)):
			return false
		granted = _grant_authored_contents()
	else:
		var rolled: Array = LootDistributionScript.roll(loot_table, seed_source, tables, loot_context)
		if not _can_accept_contents(rolled):
			return false
		granted = _grant_rolled_contents(rolled)
	# A full inventory must not consume a reachable source. The caller can free
	# stack room and interact again; no quality/provenance is discarded.
	if granted.is_empty():
		return false
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
	var index: int = 0
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
		var added: int = _deposit_lot(item_id, qty, stack, index)
		index += 1
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

## Guard every stack together before the first atomic lot deposit. This prevents
## a container from consuming itself after accepting only an early stack.
func _can_accept_contents(contents: Array) -> bool:
	if inventory_state == null or not inventory_state.has_method("can_accept"):
		return true
	var totals: Dictionary = {}
	for entry_v in contents:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v as Dictionary
		var item_id: String = str(entry.get("item_id", ""))
		var qty: int = int(entry.get("quantity", entry.get("qty", 0)))
		if not item_id.is_empty() and qty > 0:
			totals[item_id] = int(totals.get(item_id, 0)) + qty
	for item_id_v in totals:
		if not inventory_state.can_accept(str(item_id_v), int(totals[item_id_v])):
			return false
	return true

func _grant_rolled_contents(rolled: Array = []) -> Array:
	var granted: Array = []
	if rolled.is_empty():
		rolled = LootDistributionScript.roll(loot_table, seed_source, tables, loot_context)
	var index: int = 0
	for entry in rolled:
		var item_id: String = str((entry as Dictionary).get("item_id", ""))
		var qty: int = int((entry as Dictionary).get("quantity", 0))
		if item_id.is_empty() or qty <= 0:
			continue
		var added: int = _deposit_lot(item_id, qty, entry as Dictionary, index)
		index += 1
		if added > 0:
			var grant_entry: Dictionary = (entry as Dictionary).duplicate(true)
			grant_entry["quantity"] = added
			granted.append(grant_entry)
	return granted

## Loot is born as a real lot, including corpse/container provenance. Scalar
## inventories remain supported only for old fixtures that predate P03.
func _deposit_lot(item_id: String, qty: int, entry: Dictionary, index: int) -> int:
	if inventory_state == null:
		return 0
	if inventory_state.has_method("add_lot"):
		var score: float = clampf(float(entry.get("quality_score", entry.get("quality", 0.5))), 0.0, 1.0)
		var raw_origin: Variant = entry.get("origin", {})
		var origin: Dictionary = (raw_origin as Dictionary).duplicate(true) if raw_origin is Dictionary else {}
		if origin.is_empty():
			origin = {"loot_container": container_id, "seed_source": seed_source}
		return int(inventory_state.add_lot({
			"lot_id": str(entry.get("lot_id", "loot:%s:%03d" % [seed_source, index])),
			"item_id": item_id, "quantity": qty, "quality_score": score,
			"quality_tier": QualityTierResolverScript.tier_for_score(score),
			"condition": clampf(float(entry.get("condition_score", 1.0)), 0.0, 1.0),
			"origin": origin,
		}))
	return int(inventory_state.add_item(item_id, qty)) if inventory_state.has_method("add_item") else 0

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
