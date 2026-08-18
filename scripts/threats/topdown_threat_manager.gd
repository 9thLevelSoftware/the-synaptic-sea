extends Node2D
class_name TopDownThreatManager
## 2D threat manager for the top-down production path.
## Uses CellOccupancy instead of 3D spatial queries.
## Reuses ThreatAIState and DamagePipeline (both RefCounted, projection-agnostic).

const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")
const DamagePipelineScript := preload("res://scripts/systems/damage_pipeline.gd")
const GridCoordinateScript := preload("res://scripts/world/grid_coordinate.gd")
const CellOccupancyScript := preload("res://scripts/world/cell_occupancy.gd")
const THREAT_ARCHETYPE_PATH: String = "res://data/combat/threat_archetypes.json"

const PlaceholderThreat2DScript := preload("res://scripts/threats/placeholder_threat_2d.gd")

# Threat archetype visual configs
const THREAT_COLORS := {
	"biomatter_swarm": Color(0.55, 1.0, 0.45),
	"stalker": Color(0.7, 0.7, 1.0),
	"hull_tendril": Color(0.55, 0.9, 1.0),
}
const THREAT_SIZES := {
	"biomatter_swarm": Vector2(32, 32),
	"stalker": Vector2(36, 36),
	"hull_tendril": Vector2(40, 40),
}

signal threat_killed(record: Dictionary)

var threat_archetypes: Dictionary = {}
var threats: Array[ThreatAIState] = []
var damage_pipeline = DamagePipelineScript.new()
var cell_occupancy = CellOccupancyScript.new()
var threat_nodes: Dictionary = {}  # instance_id -> Node2D
var _initialized: bool = false


func _ready() -> void:
	_init_systems()


func _init_systems() -> void:
	if _initialized:
		return
	_initialized = true
	threat_archetypes = _load_json_dict(THREAT_ARCHETYPE_PATH)
	damage_pipeline.configure({})


func spawn_threat(archetype_id: String, world_pos: Vector2, instance_id: String = "") -> ThreatAIState:
	_init_systems()
	if instance_id.is_empty():
		instance_id = "threat_%d" % threats.size()

	var archetype: Dictionary = threat_archetypes.get(archetype_id, {})
	if archetype.is_empty():
		push_warning("TopDownThreatManager: unknown archetype " + archetype_id)
		return null

	var threat = ThreatAIStateScript.new()
	threat.configure({
		"instance_id": instance_id,
		"archetype_id": archetype_id,
		"display_name": archetype.get("display_name", archetype_id),
		"world_position": [world_pos.x, world_pos.y, 0.0],
		"state": "idle",
		"max_health": archetype.get("max_health", 20.0),
		"health": archetype.get("max_health", 20.0),
		"attack_damage": archetype.get("attack_damage", 5.0),
		"attack_type": archetype.get("attack_type", "physical"),
		"attack_noise": archetype.get("attack_noise", 0.4),
		"attack_interval": archetype.get("attack_interval", 1.4),
		"noise_sensitivity": archetype.get("noise_sensitivity", 1.0),
		"light_sensitivity": archetype.get("light_sensitivity", 1.0),
		"sight_sensitivity": archetype.get("sight_sensitivity", 1.0),
		"memory_seconds": archetype.get("memory_seconds", 5.0),
		"flee_threshold": archetype.get("flee_threshold", 0.15),
		"move_speed": archetype.get("move_speed", 2.5),
		"hunt_speed_mult": archetype.get("hunt_speed_mult", 1.0),
		"flee_speed_mult": archetype.get("flee_speed_mult", 1.35),
		"investigate_speed_mult": archetype.get("investigate_speed_mult", 0.7),
		"attack_range": archetype.get("attack_range", 1.4),
		"structure_damage": archetype.get("structure_damage", 0.0),
		"tags": archetype.get("tags", []),
		"armor": archetype.get("armor", {}),
		"status_on_hit": archetype.get("status_on_hit", ""),
		"behavior": archetype.get("behavior", {}),
	})

	threats.append(threat)

	# Spawn 2D visual node
	var node := _create_threat_node(archetype_id, world_pos)
	if node:
		threat_nodes[instance_id] = node
		add_child(node)

	# Mark cell as occupied
	var grid_pos := GridCoordinateScript.world_to_grid(world_pos)
	cell_occupancy.occupy(grid_pos, StringName(instance_id))

	return threat


func tick_threats(delta: float, player_position: Vector2, context: Dictionary = {}) -> void:
	for threat_state: ThreatAIState in threats:
		if threat_state.health <= 0.0:
			continue

		# Compute distance to player
		var threat_pos := _threat_world_pos(threat_state)
		var dist := threat_pos.distance_to(player_position)

		# Build tick context
		var tick_ctx := {
			"noise_level": context.get("noise_level", 0.1),
			"light_level": context.get("light_level", 0.35),
			"sight_level": context.get("sight_level", 0.5),
			"crouching": context.get("crouching", false),
			"same_room": dist < 300.0,  # ~6 tiles at 48px
			"detect_threshold": context.get("detect_threshold", 0.85),
			"player_distance": dist / float(GridCoordinateScript.TILE_SIZE),  # in tiles
			"room_id": context.get("room_id", ""),
			"player_position": Vector3(player_position.x, player_position.y, 0.0),
		}

		var old_state := threat_state.state
		threat_state.tick(delta, tick_ctx)

		# Move threat based on AI state
		_move_threat(threat_state, delta, player_position)

		# Update visual node
		var node = threat_nodes.get(threat_state.instance_id)
		if node:
			node.position = _threat_world_pos(threat_state)
			node.is_moving = threat_state.effective_move_speed() > 0.0
			node.is_attacking = threat_state.state == "attack"

		# Check for death
		if threat_state.state == "dead" and old_state != "dead":
			_on_threat_died(threat_state)


func apply_damage_to_threat(instance_id: String, event: Dictionary) -> Dictionary:
	var threat_state: ThreatAIState = _find_threat(instance_id)
	if threat_state == null:
		return {}
	var result := damage_pipeline.apply_to_threat(threat_state, event)
	var node = threat_nodes.get(instance_id)
	if node and node.has_method("flash_hit"):
		node.flash_hit()
	return result


func _move_threat(threat_state: ThreatAIState, delta: float, player_pos: Vector2) -> void:
	var speed := threat_state.effective_move_speed()
	if speed <= 0.0:
		return

	var threat_pos := _threat_world_pos(threat_state)
	var direction := Vector2.ZERO

	match threat_state.state:
		"hunt", "attack":
			direction = (player_pos - threat_pos).normalized()
		"flee":
			direction = (threat_pos - player_pos).normalized()
		"investigate":
			if threat_state.last_known_position.size() >= 2:
				var lkp := Vector2(threat_state.last_known_position[0], threat_state.last_known_position[1])
				direction = (lkp - threat_pos).normalized()
			else:
				direction = (player_pos - threat_pos).normalized() * 0.5
		_:
			# idle, stun, dead, telegraph — no movement
			return

	if direction.length_squared() > 0.0:
		var movement := direction * speed * float(GridCoordinateScript.TILE_SIZE) * delta
		var new_pos := threat_pos + movement
		threat_state.world_position = [new_pos.x, new_pos.y, 0.0]

		# Update cell occupancy
		var old_grid := GridCoordinateScript.world_to_grid(threat_pos)
		var new_grid := GridCoordinateScript.world_to_grid(new_pos)
		if old_grid != new_grid:
			cell_occupancy.release(old_grid, StringName(threat_state.instance_id))
			if cell_occupancy.is_walkable(new_grid):
				cell_occupancy.occupy(new_grid, StringName(threat_state.instance_id))
			else:
				# Blocked — revert position
				threat_state.world_position = [threat_pos.x, threat_pos.y, 0.0]
				cell_occupancy.occupy(old_grid, StringName(threat_state.instance_id))


func _on_threat_died(threat_state: ThreatAIState) -> void:
	var grid_pos := GridCoordinateScript.world_to_grid(_threat_world_pos(threat_state))
	cell_occupancy.release(grid_pos, StringName(threat_state.instance_id))
	var node = threat_nodes.get(threat_state.instance_id)
	if node:
		node.queue_free()
		threat_nodes.erase(threat_state.instance_id)
	threat_killed.emit(threat_state.get_summary())


func _create_threat_node(archetype_id: String, pos: Vector2) -> Node2D:
	var color: Color = THREAT_COLORS.get(archetype_id, Color(1.0, 0.35, 0.35))
	var sz: Vector2 = THREAT_SIZES.get(archetype_id, Vector2(32, 32))
	var node := PlaceholderThreat2DScript.new(color, sz)
	node.position = pos
	return node


func _threat_world_pos(threat_state: ThreatAIState) -> Vector2:
	var wp: Array = threat_state.world_position
	if wp.size() >= 2:
		return Vector2(float(wp[0]), float(wp[1]))
	return Vector2.ZERO


func _find_threat(instance_id: String) -> ThreatAIState:
	for t in threats:
		if t.instance_id == instance_id:
			return t
	return null


func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func get_threat_count() -> int:
	return threats.size()


func get_alive_count() -> int:
	var count := 0
	for t in threats:
		if t.health > 0.0:
			count += 1
	return count
