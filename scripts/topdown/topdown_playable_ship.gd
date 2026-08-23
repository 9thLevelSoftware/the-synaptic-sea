extends Node2D
class_name TopDownPlayableShip
## 2D coordinator — replaces the 11K-line PlayableGeneratedShip for top-down.
## Wires core simulation systems (projection-agnostic RefCounted) to TileMap presentation.
## Scope: move, interact, vitals, threats, loot, travel, audio. Deferred: cargo, hallucination, ship mods.

const LayoutTilemapAdapterScript = preload("res://scripts/topdown/layout_tilemap_adapter.gd")
const TopDownThreatManagerScript = preload("res://scripts/threats/topdown_threat_manager.gd")
const TopDownCameraRigScript = preload("res://scripts/camera/top_down_camera_rig.gd")
const TopDownPlayerControllerScript = preload("res://scripts/player/top_down_player_controller.gd")
const TopDownTravelControllerScript = preload("res://scripts/topdown/td_travel_controller.gd")
const SfxEventRouterScript = preload("res://scripts/systems/sfx_event_router.gd")

# Simulation systems (all RefCounted, reused from 3D path)
const PlayerVitalsModelScript = preload("res://scripts/systems/player_vitals_model.gd")
const OxygenStateScript = preload("res://scripts/systems/oxygen_state.gd")
const PowerGridStateScript = preload("res://scripts/systems/power_grid_state.gd")
const VitalsStateScript = preload("res://scripts/systems/vitals_state.gd")
const StatusEffectsStateScript = preload("res://scripts/systems/status_effects_state.gd")
const ThreatManagerScript = preload("res://scripts/systems/threat_manager.gd")
const InventoryStateScript = preload("res://scripts/systems/inventory_state.gd")
const AudioManagerScript = preload("res://scripts/audio/audio_manager.gd")
const CraftingStateScript = preload("res://scripts/systems/crafting_state.gd")
const DamagePipelineScript = preload("res://scripts/systems/damage_pipeline.gd")
const ShipGeneratorScript = preload("res://scripts/procgen/ship_generator.gd")
const GameplaySliceBuilderScript = preload("res://scripts/procgen/gameplay_slice_builder.gd")
const ShipBlueprintScript = preload("res://scripts/procgen/ship_blueprint.gd")
const FirstRunContractScript = preload("res://scripts/procgen/first_run_contract.gd")

# Scene nodes
var tilemap: TileMapLayer
var camera_rig  # TopDownCameraRig
var player      # TopDownPlayerController
var threat_manager  # TopDownThreatManager

# Simulation state
var vitals_state
var oxygen_state
var power_grid_state
var status_effects
var inventory_state
var audio_manager
var crafting_state
var damage_pipeline
var sfx_router
var travel_controller  # TopDownTravelController
var vitals_panel  # PlayerVitalsPanel

# Procgen
var layout_adapter = LayoutTilemapAdapterScript.new()
var ship_generator = ShipGeneratorScript.new()
var gameplay_slice_builder = GameplaySliceBuilderScript.new()

# State
var current_layout: Dictionary = {}
var current_gameplay_slice: Dictionary = {}
var room_centers: Dictionary = {}
var playable_started: bool = false
var away_from_start: bool = false


func _ready() -> void:
	_ensure_nodes()
	_init_systems()


func _ensure_nodes() -> void:
	tilemap = get_node_or_null("TileMapLayer")
	camera_rig = get_node_or_null("TopDownCameraRig")
	player = get_node_or_null("Player")

	if tilemap == null:
		tilemap = TileMapLayer.new()
		tilemap.name = "TileMapLayer"
		add_child(tilemap)

	if camera_rig == null:
		camera_rig = TopDownCameraRigScript.new()
		camera_rig.name = "TopDownCameraRig"
		add_child(camera_rig)

	if player == null:
		player = TopDownPlayerControllerScript.new()
		player.name = "Player"
		add_child(player)

	threat_manager = TopDownThreatManagerScript.new()
	threat_manager.name = "ThreatManager"
	add_child(threat_manager)

	# Travel controller
	travel_controller = TopDownTravelControllerScript.new()
	travel_controller.name = "TravelController"
	add_child(travel_controller)

	# HUD
	var hud_scene: PackedScene = load("res://scenes/topdown/topdown_hud.tscn") as PackedScene
	if hud_scene:
		var hud := hud_scene.instantiate()
		hud.name = "HUD"
		add_child(hud)
		vitals_panel = hud.get_node_or_null("PlayerVitalsPanel")


func _init_systems() -> void:
	# Vitals
	vitals_state = PlayerVitalsModelScript.new()
	oxygen_state = OxygenStateScript.new()
	power_grid_state = PowerGridStateScript.new()
	status_effects = StatusEffectsStateScript.new()
	inventory_state = InventoryStateScript.new()
	crafting_state = CraftingStateScript.new()
	damage_pipeline = DamagePipelineScript.new()

	# Audio
	audio_manager = AudioManagerScript.new()
	add_child(audio_manager)
	sfx_router = SfxEventRouterScript.new()
	sfx_router.configure({}) if sfx_router.has_method("configure") else null

	# Configure systems with defaults
	damage_pipeline.configure({})
	oxygen_state.configure({}) if oxygen_state.has_method("configure") else null
	power_grid_state.configure({}) if power_grid_state.has_method("configure") else null

	# Wire travel controller
	if travel_controller:
		travel_controller.setup(self)

	# Wire vitals panel
	if vitals_panel and vitals_panel.has_method("set_vitals_state"):
		vitals_panel.set_vitals_state(vitals_state)


func generate_hub(seed_value: int = 42) -> Dictionary:
	## Generate and display the hub ship layout.
	var blueprint = ShipBlueprintScript.new(ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.DAMAGED, seed_value)
	blueprint.room_count_range = Vector2i(6, 8)

	var layout = ship_generator.generate_layout(blueprint)
	current_layout = layout
	current_gameplay_slice = gameplay_slice_builder.build(layout)

	# Build tilemap from layout
	var build_info = layout_adapter.build(tilemap, layout)
	room_centers = build_info.get("room_centers", {})

	# Place player at start room center
	var start_room: String = str(current_gameplay_slice.get("start_room", ""))
	var start_pos := Vector2(100, 100)
	if not start_room.is_empty() and room_centers.has(start_room):
		start_pos = room_centers[start_room]
	player.position = start_pos

	# Wire camera
	if camera_rig.has_method("set_follow_target"):
		camera_rig.set_follow_target(player)

	# Spawn loot containers from gameplay_slice
	_spawn_loot_containers(current_gameplay_slice)

	playable_started = true
	return build_info


func generate_derelict(seed_value: int = 777, biome_id: String = "breach_field") -> Dictionary:
	## Generate and display a derelict layout.
	var blueprint = ShipBlueprintScript.new(ShipBlueprintScript.Size.SMALL, ShipBlueprintScript.Condition.DAMAGED, seed_value)
	blueprint.room_count_range = Vector2i(4, 6)

	ship_generator.configure_run_context(biome_id, "standard")
	var layout = ship_generator.generate_layout(blueprint)
	current_layout = layout
	current_gameplay_slice = gameplay_slice_builder.build(layout)

	# Rebuild tilemap
	var build_info = layout_adapter.build(tilemap, layout)
	room_centers = build_info.get("room_centers", {})

	# Place player at start
	var start_room: String = str(current_gameplay_slice.get("start_room", ""))
	var start_pos := Vector2(100, 100)
	if not start_room.is_empty() and room_centers.has(start_room):
		start_pos = room_centers[start_room]
	player.position = start_pos

	# Spawn threats from gameplay_slice encounters
	_spawn_derelict_threats(current_gameplay_slice)

	away_from_start = true
	return build_info


func _process(delta: float) -> void:
	if not playable_started:
		return

	# Tick core simulation systems
	_tick_oxygen(delta)
	_tick_vitals(delta)
	_tick_threats(delta)
	_tick_audio(delta)
	_update_hud()


func _tick_oxygen(delta: float) -> void:
	if oxygen_state == null:
		return
	# Oxygen ticks based on breach status (simplified for 2D)
	oxygen_state.tick(delta, {"breach_open": false}) if oxygen_state.has_method("tick") else null


func _tick_vitals(delta: float) -> void:
	if vitals_state == null:
		return
	vitals_state.tick(delta)


func _tick_threats(delta: float) -> void:
	if threat_manager == null or player == null:
		return
	var ctx := {
		"noise_level": 0.5,
		"light_level": 0.6,
		"sight_level": 0.8,
		"crouching": player.is_crouching() if player.has_method("is_crouching") else false,
	}
	threat_manager.tick_threats(delta, player.position, ctx)


func _tick_audio(delta: float) -> void:
	if audio_manager == null:
		return
	audio_manager.tick(delta) if audio_manager.has_method("tick") else null


func _spawn_loot_containers(gameplay_slice: Dictionary) -> void:
	var containers: Array = gameplay_slice.get("loot_containers", [])
	for container_spec in containers:
		var room_id: String = str(container_spec.get("room_id", ""))
		if room_centers.has(room_id):
			var pos: Vector2 = room_centers[room_id]
			# Create a visual loot marker (placeholder)
			var marker := ColorRect.new()
			marker.name = "Loot_" + str(container_spec.get("id", ""))
			marker.color = Color(1.0, 0.8, 0.2, 0.8)
			marker.size = Vector2(24, 24)
			marker.position = pos - Vector2(12, 12)
			add_child(marker)


func _spawn_derelict_threats(gameplay_slice: Dictionary) -> void:
	# Spawn 3 threats at different rooms (vertical slice contract)
	var encounters: Array = gameplay_slice.get("encounters", [])
	if encounters.is_empty():
		# Fallback: spawn at room centers
		var center_keys := room_centers.keys()
		if center_keys.size() >= 1:
			threat_manager.spawn_threat("biomatter_swarm", room_centers[center_keys[0]], "swarm_01")
		if center_keys.size() >= 2:
			threat_manager.spawn_threat("stalker", room_centers[center_keys[1]], "stalker_01")
		if center_keys.size() >= 3:
			threat_manager.spawn_threat("hull_tendril", room_centers[center_keys[2]], "tendril_01")
	else:
		for i in range(mini(encounters.size(), 3)):
			var enc: Dictionary = encounters[i]
			var room_id: String = str(enc.get("room_id", ""))
			var archetype: String = str(enc.get("archetype_id", "biomatter_swarm"))
			var pos := Vector2.ZERO
			if room_centers.has(room_id):
				pos = room_centers[room_id]
			threat_manager.spawn_threat(archetype, pos, "threat_%d" % i)


func get_player_position() -> Vector2:
	if player:
		return player.position
	return Vector2.ZERO


func get_simulation_summary() -> Dictionary:
	return {
		"playable_started": playable_started,
		"away_from_start": away_from_start,
		"threats_alive": threat_manager.get_alive_count() if threat_manager else 0,
		"rooms": room_centers.size(),
		"location": travel_controller.get_current_location() if travel_controller else "hub",
	}


func _update_hud() -> void:
	if vitals_panel and vitals_panel.has_method("refresh"):
		vitals_panel.refresh()


func play_sfx(event_id: String) -> void:
	if audio_manager and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx(event_id)


func get_travel_controller():
	return travel_controller
