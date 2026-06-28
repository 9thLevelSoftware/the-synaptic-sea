extends Area3D
class_name CraftingStation

## A spatial, range-gated crafting/salvage station bound to a station_kind on the home
## ship. Interacting auto-selects work and hands it to the coordinator-owned models:
##  - a normal station (fabricator/medbay/kitchen/synthesizer/workbench) begins the first
##    craftable recipe for its kind via CraftingState (the coordinator ticks the global
##    craft to completion and deposits the output — this node does NOT channel in _process,
##    unlike RepairPoint, because CraftingState is single-active and ticked globally).
##  - a "salvage" station runs DeconstructionResolver on the first inventory item that has
##    a deconstruction recipe (instantaneous; no timed channel).
## Never advances crafting itself; it only starts work and reports it. Mirrors the
## interaction/range contract of repair_point.gd / loot_container.gd.

signal craft_started(station_kind: String, recipe_id: String)
signal salvage_completed(item_id: String, yields: Dictionary)
signal craft_blocked(station_kind: String, reason: String)

var station_kind: String = ""
var crafting_state                       # CraftingState
var material_state                       # MaterialState
var inventory_state                      # InventoryState
var deconstruction_resolver              # DeconstructionResolver
var player_progression                   # PlayerProgressionState | null
var interaction_radius: float = 1.8
var powered: bool = true                 # mirrors the model station; gates feedback only

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

func configure(p_station_kind: String, p_crafting_state, p_material_state, p_inventory_state, p_deconstruction_resolver, p_player_progression, world_position: Vector3, radius := 1.8) -> void:
	# Debug-build guards for the required dependencies (player_progression is intentionally
	# optional — _player_skill() null-guards it, mirroring repair_point.gd).
	assert(p_crafting_state != null, "p_crafting_state must not be null")
	assert(p_material_state != null, "p_material_state must not be null")
	assert(p_inventory_state != null, "p_inventory_state must not be null")
	assert(p_deconstruction_resolver != null, "p_deconstruction_resolver must not be null")
	assert(radius >= 0.0, "radius must be non-negative")
	station_kind = p_station_kind
	crafting_state = p_crafting_state
	material_state = p_material_state
	inventory_state = p_inventory_state
	deconstruction_resolver = p_deconstruction_resolver
	player_progression = p_player_progression
	interaction_radius = radius
	candidate_player = null
	position = world_position
	name = "CraftingStation_%s" % p_station_kind
	set_meta("crafting_station", true)
	set_meta("station_kind", station_kind)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_powered(value: bool) -> void:
	powered = value

func set_marker_visible(is_visible: bool) -> void:
	marker_visible = is_visible
	if is_instance_valid(marker):
		marker.visible = marker_visible

func _player_skill() -> int:
	if player_progression != null and player_progression.has_method("get_skill_level"):
		return int(player_progression.get_skill_level("fabrication"))
	return 0

## Range-gated interact. Returns true if it started a craft or completed a salvage.
func try_interact(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or crafting_state == null or inventory_state == null:
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	# Single active craft (CraftingState holds one global _active_craft): if one is already
	# running, this station no-ops rather than clobbering it.
	if crafting_state.is_crafting():
		emit_signal("craft_blocked", station_kind, "busy")
		return false
	if station_kind == "salvage":
		return _try_salvage()
	return _try_craft()

func _try_craft() -> bool:
	var recipes: Array = crafting_state.get_recipes_for_station(station_kind)
	# Deterministic order: catalog order is dictionary-key order, so sort by recipe_id.
	recipes.sort_custom(func(a, b): return str(a.get("recipe_id", "")) < str(b.get("recipe_id", "")))
	var blocked_by_full: bool = false
	for recipe in recipes:
		var rid: String = str(recipe.get("recipe_id", ""))
		if rid.is_empty():
			continue
		# Deconstruction belongs to the dedicated salvage bench (DeconstructionResolver), not
		# normal stations — some deconstruction recipes share a normal station_kind (e.g.
		# deconstruct_scrap is station_kind "workbench"), so skip them here.
		if str(recipe.get("category", "")) == "deconstruction":
			continue
		if not crafting_state.can_craft(rid, inventory_state):
			continue
		# Skip recipes the player lacks the skill for, so selection falls through to a
		# craftable one rather than picking a too-high-skill recipe that begin_craft rejects.
		if crafting_state.get_required_skill_level(rid) > _player_skill():
			continue
		# Don't consume ingredients for an output that won't fit (begin_craft consumes
		# immediately; add_item silently drops over-stack overflow). Try the next recipe.
		var produces: Dictionary = crafting_state.get_produces(rid)
		if not inventory_state.can_accept(str(produces.get("item_id", "")), int(produces.get("quantity", 0))):
			blocked_by_full = true
			continue
		if crafting_state.begin_craft(rid, inventory_state, material_state, _player_skill()):
			emit_signal("craft_started", station_kind, rid)
			return true
	emit_signal("craft_blocked", station_kind, "output_full" if blocked_by_full else "no_craftable_recipe")
	return false

func _try_salvage() -> bool:
	if deconstruction_resolver == null or material_state == null:
		emit_signal("craft_blocked", station_kind, "no_resolver")
		return false
	for recipe in deconstruction_resolver.get_deconstruction_recipes():
		var rid: String = str(recipe.get("recipe_id", ""))
		if rid.is_empty():
			continue
		if not deconstruction_resolver.can_deconstruct(rid, inventory_state):
			continue
		var produced: Dictionary = deconstruction_resolver.deconstruct(rid, inventory_state, material_state)
		if not produced.is_empty():
			var out_id: String = str(produced.get("item_id", ""))
			var out_qty: int = int(produced.get("quantity", 0))
			if not out_id.is_empty() and out_qty > 0:
				inventory_state.add_item(out_id, out_qty)
			emit_signal("salvage_completed", out_id, produced)
			return true
	emit_signal("craft_blocked", station_kind, "nothing_to_salvage")
	return false

func _interaction_radius() -> float:
	if is_instance_valid(collision_shape) and collision_shape.shape is SphereShape3D:
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
	assert(radius >= 0.0, "radius must be non-negative")
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CraftingStationCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	assert(radius >= 0.0, "radius must be non-negative")
	if not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		marker.name = "CraftingStationMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.65, 0.95, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible
	marker.set_meta("debug_crafting_station_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
