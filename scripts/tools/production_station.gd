extends Area3D
class_name ProductionStation

## A spatial, range-gated production station bound to one stateful production model
## (HydroponicsState or WaterRecyclerState) on the home ship. Unlike CraftingStation
## (single-active, stateless, auto-deposit), this drives a persistent model: the first
## interact STARTS production (consuming inputs), and a later interact HARVESTS the produce
## once the model reports ready. The coordinator ticks the model per-frame; this node only
## starts and collects. Mirrors the range/interact/marker contract of crafting_station.gd.

signal production_started(station_kind: String, input_id: String)
signal production_harvested(station_kind: String, item_id: String, qty: int)
signal production_blocked(station_kind: String, reason: String)

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

## Range-gated interact. Returns true when it started or harvested production.
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
	var HydroState = load("res://scripts/systems/hydroponics_state.gd")
	if model.state == HydroState.State.HARVESTABLE:
		var out: Dictionary = model.harvest()
		return _deposit(str(out.get("item_id", "")), int(out.get("quantity", 0)))
	if model.state == HydroState.State.PLANTED:
		emit_signal("production_blocked", station_kind, "in_progress")
		return false
	# IDLE -> plant the first affordable crop.
	var crops: Array = config.get("crops", []) as Array
	var skill: int = _skill()
	var power: float = _avail_power()
	for crop in crops:
		var c: Dictionary = crop as Dictionary
		var water_cost: float = float(c.get("water_cost", 0.0))
		if int(c.get("required_skill_level", 0)) > skill:
			continue
		if float(inventory_state.get_quantity("purified_water")) < water_cost:
			continue
		if power < float(c.get("power_cost", 0.0)):
			continue
		var res: Dictionary = model.plant(c, skill, float(inventory_state.get_quantity("purified_water")), power)
		if res.get("ok", false):
			inventory_state.remove_item("purified_water", int(ceil(water_cost)))
			emit_signal("production_started", station_kind, str(c.get("crop_id", "")))
			return true
	emit_signal("production_blocked", station_kind, "no_affordable_crop")
	return false

func _interact_recycler() -> bool:
	var RecyclerState = load("res://scripts/systems/water_recycler_state.gd")
	if model.output_ready > 0:
		var out: Dictionary = model.collect_output()
		return _deposit(str(out.get("item_id", "")), int(out.get("quantity", 0)))
	if model.state == RecyclerState.State.RECYCLING:
		emit_signal("production_blocked", station_kind, "in_progress")
		return false
	# IDLE -> load contaminated_water.
	var qty: int = inventory_state.get_quantity("contaminated_water")
	if qty <= 0:
		emit_signal("production_blocked", station_kind, "no_input")
		return false
	if _avail_power() < model.power_cost:
		emit_signal("production_blocked", station_kind, "insufficient_power")
		return false
	var res: Dictionary = model.load_input("contaminated_water", qty, _avail_power())
	if res.get("ok", false):
		inventory_state.remove_item("contaminated_water", qty)
		emit_signal("production_started", station_kind, "contaminated_water")
		return true
	emit_signal("production_blocked", station_kind, str(res.get("reason", "load_failed")))
	return false

func _deposit(item_id: String, qty: int) -> bool:
	if item_id.is_empty() or qty <= 0:
		return false
	var added: int = inventory_state.add_item(item_id, qty)
	if added < qty:
		print("PRODUCTION OVERFLOW item=%s lost=%d reason=stack_full" % [item_id, qty - added])
	emit_signal("production_harvested", station_kind, item_id, qty)
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
