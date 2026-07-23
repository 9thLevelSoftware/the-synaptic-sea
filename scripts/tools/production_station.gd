extends Area3D
class_name ProductionStation

## A spatial, range-gated production station bound to one stateful production model
## (HydroponicsState or WaterRecyclerState) on the home ship. Unlike CraftingStation
## (single-active, timed craft), this drives a persistent model: the first interact
## STARTS production (consuming inputs), and a later interact HARVESTS the produce
## once the model reports ready. Hydroponics IDLE interact opens the crop picker
## (REQ-CS-018) instead of auto-planting the first affordable crop.
## The coordinator ticks the model per-frame; this node only starts and collects.

signal production_started(station_kind: String, input_id: String)
signal production_harvested(station_kind: String, item_id: String, qty: int)
signal production_blocked(station_kind: String, reason: String)
## REQ-CS-018: hydro IDLE interact opens the shared recipe picker for crop choice.
signal crop_picker_requested(station_kind: String)

const HydroStateScript := preload("res://scripts/systems/hydroponics_state.gd")
const RecyclerStateScript := preload("res://scripts/systems/water_recycler_state.gd")

var station_kind: String = ""
var model                                  # HydroponicsState | WaterRecyclerState
var inventory_state                        # InventoryState
var power_available: Callable = Callable()  # () -> float
var player_skill: Callable = Callable()     # () -> int
var config: Dictionary = {}                 # hydroponics: {"crops": [...]}
var interaction_radius: float = 1.8

var candidate_player: Object  # Node3D in-game; Object allows SceneTree bypass in headless tests
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

func configure(p_station_kind: String, p_model, p_inventory_state, p_power_available: Callable, p_player_skill: Callable, p_config: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	assert(p_model != null, "p_model must not be null")
	assert(p_inventory_state != null, "p_inventory_state must not be null")
	assert(radius >= 0.0, "radius must be non-negative")
	station_kind = p_station_kind
	model = p_model
	inventory_state = p_inventory_state
	power_available = p_power_available
	player_skill = p_player_skill
	config = p_config
	interaction_radius = radius
	candidate_player = null
	position = world_position
	name = "ProductionStation_%s" % p_station_kind
	set_meta("production_station", true)
	set_meta("station_kind", station_kind)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Object) -> void:
	candidate_player = player_body

func _avail_power() -> float:
	return float(power_available.call()) if power_available.is_valid() else 0.0

func _skill() -> int:
	return int(player_skill.call()) if player_skill.is_valid() else 0

## Range-gated interact. Returns true when it opened the crop picker, started, or harvested.
func try_interact(player_body: Object) -> bool:
	if not is_instance_valid(player_body) or model == null or inventory_state == null:
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	if station_kind == "hydroponics":
		return _interact_hydro()
	if station_kind == "water_recycler":
		return _interact_recycler()
	emit_signal("production_blocked", station_kind, "unknown_kind")
	return false

func _interact_hydro() -> bool:
	if model.state == HydroStateScript.State.HARVESTABLE:
		# Guard BEFORE harvest(): harvest() resets the model to IDLE, so if the produce
		# can't fit we'd silently lose both the crop and the produce. Check capacity first
		# and leave the crop HARVESTABLE so the player can free space and retry.
		if not inventory_state.can_accept(model.produce_item_id, model.produce_quantity):
			emit_signal("production_blocked", station_kind, "output_full")
			return true  # consume — leave crop harvestable for retry
		var out: Dictionary = model.harvest()
		return _deposit(str(out.get("item_id", "")), int(out.get("quantity", 0)))
	if model.state == HydroStateScript.State.PLANTED:
		# Growing crop — soft block + consume interact (no fall-through to other handlers).
		emit_signal("production_blocked", station_kind, "in_progress")
		return true
	# IDLE -> open crop picker (REQ-CS-018); no auto-plant.
	emit_signal("crop_picker_requested", station_kind)
	return true

## REQ-CS-018: list crop catalog rows for the picker (shape matches craft list entries).
func list_crop_entries() -> Array:
	var out: Array = []
	if station_kind != "hydroponics" or inventory_state == null:
		return out
	var crops: Array = config.get("crops", []) as Array
	var skill: int = _skill()
	var power: float = _avail_power()
	var water: float = float(inventory_state.get_quantity("purified_water"))
	# Sort by crop_id for deterministic picker order.
	var sorted_crops: Array = crops.duplicate()
	sorted_crops.sort_custom(func(a, b): return str(a.get("crop_id", "")) < str(b.get("crop_id", "")))
	for crop in sorted_crops:
		if not (crop is Dictionary):
			continue
		var c: Dictionary = crop as Dictionary
		var cid: String = str(c.get("crop_id", ""))
		if cid.is_empty():
			continue
		var need_skill: int = int(c.get("required_skill_level", 0))
		var water_cost: float = float(c.get("water_cost", 0.0))
		var power_cost: float = float(c.get("power_cost", 0.0))
		var produce_id: String = str(c.get("produce_item_id", ""))
		var produce_qty: int = int(c.get("produce_quantity", 0))
		var status: String = "ready"
		if model != null and int(model.state) != HydroStateScript.State.IDLE:
			status = "busy"
		elif need_skill > skill:
			status = "insufficient_skill"
		elif water < water_cost:
			status = "missing_ingredients"
		elif power < power_cost:
			status = "insufficient_power"
		out.append({
			"recipe_id": cid,
			"display_name": str(c.get("display_name", cid)),
			"category": "hydroponics",
			"required_skill_level": need_skill,
			"ingredients": {"purified_water": int(ceil(water_cost))},
			"produces": {"item_id": produce_id, "quantity": produce_qty},
			"craft_time_seconds": float(c.get("growth_seconds", 0.0)),
			"status": status,
			"craftable": status == "ready",
			"crop_config": c.duplicate(true),
		})
	return out

func first_ready_crop_id() -> String:
	for entry in list_crop_entries():
		if entry is Dictionary and bool((entry as Dictionary).get("craftable", false)):
			return str((entry as Dictionary).get("recipe_id", ""))
	return ""

func _find_crop_config(crop_id: String) -> Dictionary:
	for crop in config.get("crops", []) as Array:
		if crop is Dictionary and str((crop as Dictionary).get("crop_id", "")) == crop_id:
			return (crop as Dictionary).duplicate(true)
	return {}

## REQ-CS-018: plant a chosen crop_id (picker confirm + validation seams).
func try_plant_crop(crop_id: String) -> bool:
	if station_kind != "hydroponics" or model == null or inventory_state == null:
		emit_signal("production_blocked", station_kind, "not_hydro")
		return false
	if crop_id.is_empty():
		emit_signal("production_blocked", station_kind, "no_crop")
		return false
	if model.state != HydroStateScript.State.IDLE:
		emit_signal("production_blocked", station_kind, "in_progress" if model.state == HydroStateScript.State.PLANTED else "busy")
		return false
	var c: Dictionary = _find_crop_config(crop_id)
	if c.is_empty():
		emit_signal("production_blocked", station_kind, "unknown_crop")
		return false
	var water_cost: float = float(c.get("water_cost", 0.0))
	var skill: int = _skill()
	var power: float = _avail_power()
	if int(c.get("required_skill_level", 0)) > skill:
		emit_signal("production_blocked", station_kind, "insufficient_skill")
		return false
	if float(inventory_state.get_quantity("purified_water")) < water_cost:
		emit_signal("production_blocked", station_kind, "missing_ingredients")
		return false
	if power < float(c.get("power_cost", 0.0)):
		emit_signal("production_blocked", station_kind, "insufficient_power")
		return false
	var res: Dictionary = model.plant(c, skill, float(inventory_state.get_quantity("purified_water")), power)
	if res.get("ok", false):
		inventory_state.remove_item("purified_water", int(ceil(water_cost)))
		emit_signal("production_started", station_kind, crop_id)
		return true
	emit_signal("production_blocked", station_kind, str(res.get("reason", "plant_failed")))
	return false

func _interact_recycler() -> bool:
	if model.output_ready > 0:
		# Guard BEFORE collect_output(): it clears output_ready, so a full inventory would
		# lose the purified water. Check capacity first and leave the output ready for a retry.
		if not inventory_state.can_accept(model.output_item_id, model.output_ready):
			emit_signal("production_blocked", station_kind, "output_full")
			return true  # consume — leave output ready for retry
		var out: Dictionary = model.collect_output()
		return _deposit(str(out.get("item_id", "")), int(out.get("quantity", 0)))
	if model.state == RecyclerStateScript.State.RECYCLING:
		# Recycling in progress — soft block + consume interact.
		emit_signal("production_blocked", station_kind, "in_progress")
		return true
	# IDLE -> load contaminated_water.
	var qty: int = inventory_state.get_quantity("contaminated_water")
	if qty <= 0:
		emit_signal("production_blocked", station_kind, "no_input")
		return true  # consume — soft deny at the station
	var power := _avail_power()
	if power < model.power_cost:
		emit_signal("production_blocked", station_kind, "insufficient_power")
		return true
	var res: Dictionary = model.load_input("contaminated_water", qty, power)
	if res.get("ok", false):
		inventory_state.remove_item("contaminated_water", qty)
		emit_signal("production_started", station_kind, "contaminated_water")
		return true
	emit_signal("production_blocked", station_kind, str(res.get("reason", "load_failed")))
	return true

func _deposit(item_id: String, qty: int) -> bool:
	if item_id.is_empty() or qty <= 0:
		return false
	var added: int = inventory_state.add_item(item_id, qty)
	if added < qty:
		print("PRODUCTION OVERFLOW item=%s lost=%d reason=stack_full" % [item_id, qty - added])
	emit_signal("production_harvested", station_kind, item_id, added)
	return true

func _interaction_radius() -> float:
	if is_instance_valid(collision_shape) and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Object) -> bool:
	# Headless validation injects candidate_player via set_validation_player_in_range to
	# bypass the spatial gate (mirrors CraftingStation's validation seam path).
	if candidate_player == player_body:
		return true
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var pn: Node3D = player_body as Node3D
	if not is_inside_tree() or not pn.is_inside_tree():
		return false
	return global_position.distance_to(pn.global_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "ProductionStationCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		marker.name = "ProductionStationMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.85, 0.45, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_production_station_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
