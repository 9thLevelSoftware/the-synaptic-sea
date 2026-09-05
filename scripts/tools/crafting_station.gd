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
signal reverse_engineered(component_id: String, event_receipt_id: String)
signal craft_blocked(station_kind: String, reason: String)
signal pending_output_collected(station_kind: String, result: Dictionary)
signal station_destruction_requested(ship_id: String, station_instance_id: String, local_position: Vector3)
## REQ-CS-016: non-salvage interact opens the coordinator recipe picker for this kind.
signal recipe_picker_requested(station_kind: String)

const GameplayPropFactoryScript := preload("res://scripts/placement/gameplay_prop_factory.gd")

var station_kind: String = ""
var ship_id: String = ""
var station_instance_id: String = ""
var crafting_state                       # CraftingState
var material_state                       # MaterialState
var inventory_state                      # InventoryState
var deconstruction_resolver              # DeconstructionResolver
var player_progression                   # PlayerProgressionState | null
var recipe_knowledge                     # RecipeKnowledgeState | null
var pending_output_store                 # PendingOutputStore | null
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

func configure(p_station_kind: String, p_crafting_state, p_material_state, p_inventory_state, p_deconstruction_resolver, p_player_progression, world_position: Vector3, radius := 1.8, p_recipe_knowledge = null, p_ship_id: String = "", p_station_instance_id: String = "", p_pending_output_store = null) -> void:
	# Debug-build guards for the required dependencies (player_progression is intentionally
	# optional — _player_skill() null-guards it, mirroring repair_point.gd).
	assert(p_crafting_state != null, "p_crafting_state must not be null")
	assert(p_material_state != null, "p_material_state must not be null")
	assert(p_inventory_state != null, "p_inventory_state must not be null")
	assert(p_deconstruction_resolver != null, "p_deconstruction_resolver must not be null")
	assert(radius >= 0.0, "radius must be non-negative")
	station_kind = p_station_kind
	ship_id = p_ship_id
	station_instance_id = p_station_instance_id
	crafting_state = p_crafting_state
	material_state = p_material_state
	inventory_state = p_inventory_state
	deconstruction_resolver = p_deconstruction_resolver
	player_progression = p_player_progression
	recipe_knowledge = p_recipe_knowledge
	pending_output_store = p_pending_output_store
	interaction_radius = radius
	candidate_player = null
	position = world_position
	name = "CraftingStation_%s" % p_station_kind
	set_meta("crafting_station", true)
	set_meta("station_kind", station_kind)
	set_meta("crafting_ship_id", ship_id)
	set_meta("station_instance_id", station_instance_id)
	if not ship_id.is_empty() and not station_instance_id.is_empty() \
			and crafting_state.has_method("bind_station_runtime_context"):
		crafting_state.call(
			"bind_station_runtime_context", ship_id, station_instance_id, station_kind,
			inventory_state, recipe_knowledge, player_progression, pending_output_store)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_powered(value: bool) -> void:
	powered = value
	if crafting_state != null and not ship_id.is_empty() and not station_instance_id.is_empty() \
			and crafting_state.has_method("get_or_create_station_instance"):
		var station = crafting_state.call(
			"get_or_create_station_instance", ship_id, station_instance_id, station_kind)
		if station != null and station.has_method("set_power"):
			station.call("set_power", value)

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
	if _has_pending_output():
		var collected: Dictionary = collect_pending_output()
		if int(collected.get("transferred", 0)) <= 0:
			emit_signal("craft_blocked", station_kind, "output_full")
		return true
	# Single active craft (CraftingState holds one global _active_craft): if one is already
	# running, this station blocks with feedback and consumes interact (no fall-through).
	if _is_this_station_busy():
		emit_signal("craft_blocked", station_kind, "busy")
		return true
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
	if _is_this_station_busy():
		emit_signal("craft_blocked", station_kind, "busy")
		return false
	if crafting_state.get_station_kind(recipe_id) != station_kind:
		emit_signal("craft_blocked", station_kind, "wrong_station")
		return false
	if str(crafting_state.get_recipe(recipe_id).get("category", "")) == "deconstruction":
		emit_signal("craft_blocked", station_kind, "deconstruction_not_here")
		return false
	if not crafting_state.is_recipe_known(recipe_id, recipe_knowledge):
		emit_signal("craft_blocked", station_kind, "missing_recipe_knowledge")
		return false
	var station_tier: int = _station_tier()
	if not crafting_state.can_craft(recipe_id, inventory_state, recipe_knowledge, station_tier):
		emit_signal("craft_blocked", station_kind, "insufficient_tier" if station_tier < crafting_state.get_station_tier_min(recipe_id) else "missing_ingredients")
		return false
	if crafting_state.get_required_skill_level(recipe_id) > _player_skill():
		emit_signal("craft_blocked", station_kind, "insufficient_skill")
		return false
	if crafting_state.begin_craft(
			recipe_id, inventory_state, material_state, _player_skill(), recipe_knowledge,
			ship_id, station_instance_id):
		emit_signal("craft_started", station_kind, recipe_id)
		return true
	emit_signal("craft_blocked", station_kind, "begin_failed")
	return false


func _has_pending_output() -> bool:
	return pending_output_store != null \
		and pending_output_store.has_method("list_records_for_station") \
		and not (pending_output_store.call(
			"list_records_for_station", station_instance_id) as Array).is_empty()


func collect_pending_output() -> Dictionary:
	if pending_output_store == null or inventory_state == null:
		return {"ok": false, "reason": "missing_pending_output_store", "transferred": 0}
	var transferred: int = 0
	var lots: Array = []
	var remaining_records: int = 0
	var records: Array = pending_output_store.call(
		"list_records_for_station", station_instance_id) as Array
	for record_variant in records:
		var receipt_id: String = str((record_variant as Dictionary).get("receipt_id", ""))
		var result: Dictionary = pending_output_store.call(
			"collect_receipt", receipt_id, inventory_state)
		if not bool(result.get("ok", false)):
			return result
		transferred += int(result.get("transferred", 0))
		lots.append_array(result.get("lots", []) as Array)
		if not (result.get("remaining_lots", []) as Array).is_empty():
			remaining_records += 1
	var combined: Dictionary = {
		"ok": true,
		"reason": "" if transferred > 0 else "destination_full",
		"transferred": transferred,
		"lots": lots,
		"remaining_records": remaining_records,
	}
	emit_signal("pending_output_collected", station_kind, combined)
	return combined


func get_pending_output_mass() -> float:
	if pending_output_store == null or inventory_state == null \
			or not pending_output_store.has_method("get_pending_mass_for_station"):
		return 0.0
	return float(pending_output_store.call(
		"get_pending_mass_for_station", station_instance_id, inventory_state))


## The coordinator owns removal and must materialize pending records before it
## frees this node. This method only settles producer state and emits the stable
## owner/position request.
func request_destruction() -> Dictionary:
	if ship_id.is_empty() or station_instance_id.is_empty() or crafting_state == null:
		return {"ok": false, "reason": "missing_owner"}
	var settled: Dictionary = crafting_state.call(
		"settle_station_pending", ship_id, station_instance_id)
	if not bool(settled.get("ok", false)):
		return settled
	emit_signal("station_destruction_requested", ship_id, station_instance_id, position)
	return {"ok": true, "reason": ""}

## First ready recipe for this station (validation / auto-smoke path). Empty if none.
func first_ready_recipe_id() -> String:
	if station_kind == "salvage":
		return first_ready_salvage_id()
	if crafting_state == null or inventory_state == null:
		return ""
	if not crafting_state.has_method("list_recipe_entries"):
		return ""
	var entries: Array = crafting_state.list_recipe_entries(
		station_kind, inventory_state, _player_skill(), _station_tier(), recipe_knowledge,
		_player_skill(), powered, pending_output_store != null)
	for entry in entries:
		if entry is Dictionary and bool((entry as Dictionary).get("craftable", false)):
			return str((entry as Dictionary).get("recipe_id", ""))
	return ""

func first_ready_salvage_id() -> String:
	if deconstruction_resolver == null or inventory_state == null:
		return ""
	if deconstruction_resolver.has_method("first_ready_salvage_id"):
		return deconstruction_resolver.first_ready_salvage_id(
			inventory_state, pending_output_store != null)
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
		target_id, inventory_state, material_state, {
			"ship_id": ship_id,
			"station_instance_id": station_instance_id,
			"pending_output_store": pending_output_store,
		})
	if produced.is_empty():
		emit_signal("craft_blocked", station_kind, "nothing_to_salvage")
		return false
	var out_id: String = str(produced.get("item_id", ""))
	if bool(produced.get("pending", false)):
		collect_pending_output()
	# The resolver commits source consumption and all yields as one inventory
	# transaction. The station must not deliver the same output a second time.
	# The resolver has already consumed the target. Allocate the durable operation
	# receipt once here, before notifying any listener that may replay delivery.
	if recipe_knowledge != null and recipe_knowledge.has_method("allocate_event_receipt"):
		var component_id: String = _reverse_component_id(target_id)
		if not component_id.is_empty():
			var receipt: String = str(recipe_knowledge.allocate_event_receipt("reverse_engineer"))
			if not receipt.is_empty():
				emit_signal("reverse_engineered", component_id, receipt)
	emit_signal("salvage_completed", out_id, produced)
	return true

func _reverse_component_id(target_id: String) -> String:
	if target_id.begins_with("junk:"):
		return target_id.substr(5)
	var recipe: Dictionary = crafting_state.get_recipe(target_id) if crafting_state != null else {}
	var ingredients: Variant = recipe.get("ingredients", {})
	if ingredients is Dictionary and not (ingredients as Dictionary).is_empty():
		var ids: Array = (ingredients as Dictionary).keys()
		ids.sort()
		return str(ids[0])
	return ""


func _is_this_station_busy() -> bool:
	if not ship_id.is_empty() and not station_instance_id.is_empty() \
			and crafting_state.has_method("is_station_busy"):
		return bool(crafting_state.call("is_station_busy", ship_id, station_instance_id))
	return bool(crafting_state.call("is_crafting"))


func _station_tier() -> int:
	if not ship_id.is_empty() and not station_instance_id.is_empty() \
			and crafting_state.has_method("get_station_instance_tier"):
		return int(crafting_state.call(
			"get_station_instance_tier", ship_id, station_instance_id, station_kind))
	return int(crafting_state.call("get_station_tier", station_kind))

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
		var visual: Node3D = GameplayPropFactoryScript.build("workbench")
		visual.name = "GameplayPropVisual"
		add_child(visual)
		marker = visual.get_node("Mesh") as MeshInstance3D
	marker.visible = marker_visible
	marker.set_meta("debug_crafting_station_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
