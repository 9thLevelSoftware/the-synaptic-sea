extends Area3D
class_name CraftingStation

## A spatial, range-gated crafting/salvage station bound to a station_kind on the home
## ship. Interaction hands work to the coordinator-owned models:
##  - a normal station (fabricator/medbay/kitchen/synthesizer/workbench) requests the
##    recipe picker (REQ-CS-016); the player chooses a recipe, then try_craft_recipe
##    begins it via CraftingState (the coordinator ticks the global craft to completion
##    and deposits the output — this node does NOT channel in _process, unlike RepairPoint,
##    because CraftingState is single-active and ticked globally).
##  - a "salvage" station opens the same picker with deconstruct + junk targets
##    (REQ-CS-017); try_salvage_target runs DeconstructionResolver (instantaneous).
## Never advances crafting itself; it only starts work and reports it. Mirrors the
## interaction/range contract of repair_point.gd / loot_container.gd.

signal craft_started(station_kind: String, recipe_id: String)
signal salvage_completed(item_id: String, yields: Dictionary)
signal craft_blocked(station_kind: String, reason: String)
## REQ-CS-016: non-salvage interact opens the coordinator recipe picker for this kind.
signal recipe_picker_requested(station_kind: String)

var station_kind: String = ""
var crafting_state                       # CraftingState
var material_state                       # MaterialState
var inventory_state                      # InventoryState
var deconstruction_resolver              # DeconstructionResolver
var player_progression                   # PlayerProgressionState | null
## Optional coordinator ref for medbay surgery (Stream F). When set and
## station_kind == "medbay", try_interact prefers try_medbay_surgery first.
var surgery_provider = null
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

## Range-gated interact. Returns true if it opened the recipe picker, started a craft
## (validation path), completed a salvage, or ran medbay surgery.
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
	# Stream F: medbay field surgery when the patient is critical (before crafts).
	if station_kind == "medbay" and surgery_provider != null \
			and surgery_provider.has_method("try_medbay_surgery"):
		if surgery_provider.try_medbay_surgery(player_body):
			return true
	# REQ-CS-016 / REQ-CS-017: open the recipe/salvage picker (no auto-select).
	emit_signal("recipe_picker_requested", station_kind)
	return true

## Explicit craft for a chosen recipe_id (picker confirm + validation seams).
## Reuses the same gates as the former auto-select loop.
func try_craft_recipe(recipe_id: String) -> bool:
	if recipe_id.is_empty() or crafting_state == null or inventory_state == null:
		emit_signal("craft_blocked", station_kind, "no_craftable_recipe")
		return false
	if crafting_state.is_crafting():
		emit_signal("craft_blocked", station_kind, "busy")
		return false
	if crafting_state.get_station_kind(recipe_id) != station_kind:
		emit_signal("craft_blocked", station_kind, "wrong_station")
		return false
	if str(crafting_state.get_recipe(recipe_id).get("category", "")) == "deconstruction":
		emit_signal("craft_blocked", station_kind, "deconstruction_not_here")
		return false
	if not crafting_state.can_craft(recipe_id, inventory_state):
		emit_signal("craft_blocked", station_kind, "missing_ingredients")
		return false
	if crafting_state.get_required_skill_level(recipe_id) > _player_skill():
		emit_signal("craft_blocked", station_kind, "insufficient_skill")
		return false
	var produces: Dictionary = crafting_state.get_produces(recipe_id)
	if not inventory_state.can_accept(str(produces.get("item_id", "")), int(produces.get("quantity", 0))):
		emit_signal("craft_blocked", station_kind, "output_full")
		return false
	if crafting_state.begin_craft(recipe_id, inventory_state, material_state, _player_skill()):
		emit_signal("craft_started", station_kind, recipe_id)
		return true
	emit_signal("craft_blocked", station_kind, "begin_failed")
	return false

## First ready recipe for this station (validation / auto-smoke path). Empty if none.
func first_ready_recipe_id() -> String:
	if station_kind == "salvage":
		return first_ready_salvage_id()
	if crafting_state == null or inventory_state == null:
		return ""
	if not crafting_state.has_method("list_recipe_entries"):
		return ""
	var entries: Array = crafting_state.list_recipe_entries(station_kind, inventory_state, _player_skill())
	for entry in entries:
		if entry is Dictionary and bool((entry as Dictionary).get("craftable", false)):
			return str((entry as Dictionary).get("recipe_id", ""))
	return ""

func first_ready_salvage_id() -> String:
	if deconstruction_resolver == null or inventory_state == null:
		return ""
	if deconstruction_resolver.has_method("first_ready_salvage_id"):
		return deconstruction_resolver.first_ready_salvage_id(inventory_state)
	return ""

## REQ-CS-017: execute a chosen salvage target (deconstruct recipe_id or junk:<item>).
func try_salvage_target(target_id: String) -> bool:
	if station_kind != "salvage":
		emit_signal("craft_blocked", station_kind, "not_salvage")
		return false
	if target_id.is_empty() or deconstruction_resolver == null or material_state == null:
		emit_signal("craft_blocked", station_kind, "no_resolver")
		return false
	if not deconstruction_resolver.has_method("execute_salvage_target"):
		emit_signal("craft_blocked", station_kind, "no_resolver")
		return false
	var produced: Dictionary = deconstruction_resolver.execute_salvage_target(
		target_id, inventory_state, material_state)
	if produced.is_empty():
		emit_signal("craft_blocked", station_kind, "nothing_to_salvage")
		return false
	var out_id: String = str(produced.get("item_id", ""))
	var out_qty: int = int(produced.get("quantity", 0))
	# Deconstruct returns produces without depositing; junk already deposited materials.
	if not target_id.begins_with("junk:"):
		if not out_id.is_empty() and out_qty > 0:
			inventory_state.add_item(out_id, out_qty)
	emit_signal("salvage_completed", out_id, produced)
	return true

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
