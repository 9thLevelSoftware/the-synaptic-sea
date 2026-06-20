extends SceneTree

const PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_generated_ship.tscn")
const DEFAULT_TIMEOUT_FRAMES: int = 9000
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]
const FLOOR_COLLISION_HALF_HEIGHT: float = 0.125
const MIN_PLAYER_FLOOR_CLEARANCE: float = 0.05
const MAX_FIRST_OBJECTIVE_VERTICAL_DELTA: float = 1.0

var timeout_frames: int = DEFAULT_TIMEOUT_FRAMES
var frame_count: int = 0
var finished: bool = false
var playable_ship
var playable_ready: bool = false
var interaction_completed: bool = false
var objectives_completed: int = 0

func _initialize() -> void:
	timeout_frames = _parse_timeout_frames(OS.get_cmdline_user_args())
	playable_ship = PLAYABLE_SHIP_SCENE.instantiate()
	playable_ship.playable_ready.connect(_on_playable_ready)
	playable_ship.playable_failed.connect(_on_playable_failed)
	playable_ship.playable_interaction_completed.connect(_on_playable_interaction_completed)
	get_root().add_child(playable_ship)
	physics_frame.connect(_on_physics_frame)

func _parse_timeout_frames(args: PackedStringArray) -> int:
	var parsed_timeout: int = DEFAULT_TIMEOUT_FRAMES
	var index: int = 0
	while index < args.size():
		var token: String = args[index]
		if token == "--":
			index += 1
			continue
		if token == "--timeout-frames":
			if index + 1 >= args.size():
				push_error("missing value for --timeout-frames")
				quit(1)
				return DEFAULT_TIMEOUT_FRAMES
			var value: String = args[index + 1]
			if not value.is_valid_int():
				push_error("--timeout-frames must be an integer")
				quit(1)
				return DEFAULT_TIMEOUT_FRAMES
			parsed_timeout = int(value)
			index += 2
			continue
		index += 1
	return parsed_timeout

func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable_ready and not interaction_completed:
		var completed_now: bool = playable_ship.complete_first_interaction_for_validation()
		if completed_now:
			interaction_completed = true
			_validate_and_pass()
			return
	if frame_count > timeout_frames:
		_fail("timeout frames=%d" % frame_count)

func _on_playable_ready(summary: Dictionary) -> void:
	playable_ready = true
	var player_spawned: bool = bool(summary.get("player_spawned", false))
	var collision_shape_count: int = int(summary.get("collision_shape_count", 0))
	var objective_count: int = int(summary.get("objective_count", 0))
	if not player_spawned:
		_fail("player not spawned")
		return
	if collision_shape_count <= 0:
		_fail("collision shape count is zero")
		return
	if objective_count != 4:
		_fail("expected 4 objectives got %d" % objective_count)
		return
	var player_position: Vector3 = playable_ship.player.global_position
	var nearest_floor_top_y: float = _nearest_floor_collision_top_y(player_position)
	if nearest_floor_top_y == INF:
		_fail("could not find nearest floor under player")
		return
	if player_position.y < nearest_floor_top_y + MIN_PLAYER_FLOOR_CLEARANCE:
		_fail(
			"player starts inside/below floor collision player_y=%.3f floor_top_y=%.3f"
			% [player_position.y, nearest_floor_top_y]
		)
		return
	var first_objective_y: float = _first_interactable_y()
	if first_objective_y != INF and absf(first_objective_y - player_position.y) > MAX_FIRST_OBJECTIVE_VERTICAL_DELTA:
		_fail(
			"first objective is on a different playable deck player_y=%.3f objective_y=%.3f"
			% [player_position.y, first_objective_y]
		)
		return

func _nearest_floor_collision_top_y(world_position: Vector3) -> float:
	if playable_ship == null or playable_ship.loader == null:
		return INF
	var best_distance: float = INF
	var best_top_y: float = INF
	var rooms_variant: Variant = playable_ship.loader.layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return INF
	for room_variant in rooms_variant:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var placements_variant: Variant = room.get("structural_placements", [])
		if typeof(placements_variant) != TYPE_ARRAY:
			continue
		for placement_variant in placements_variant:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if not FLOOR_MODULES.has(module_id):
				continue
			var pos_variant: Variant = placement.get("position", [])
			if typeof(pos_variant) != TYPE_ARRAY:
				continue
			var pos: Array = pos_variant
			if pos.size() < 3:
				continue
			var placement_position: Vector3 = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			var distance: float = Vector2(placement_position.x - world_position.x, placement_position.z - world_position.z).length_squared()
			if distance < best_distance:
				best_distance = distance
				best_top_y = placement_position.y + FLOOR_COLLISION_HALF_HEIGHT
	return best_top_y

func _first_interactable_y() -> float:
	if playable_ship == null or playable_ship.interactables.is_empty():
		return INF
	return playable_ship.interactables[0].global_position.y

func _on_playable_failed(reason: String) -> void:
	_fail(reason)

func _on_playable_interaction_completed(_interaction_id: String, _objective_id: String, _sequence: int, _objective_type: String, _room_id: String) -> void:
	objectives_completed += 1

func _validate_and_pass() -> void:
	var summary: Dictionary = playable_ship.get_playable_summary()
	var player_spawned: bool = bool(summary.get("player_spawned", false))
	var collision_shape_count: int = int(summary.get("collision_shape_count", 0))
	var objective_count: int = int(summary.get("objective_count", 0))
	var completed_count: int = int(summary.get("objectives_completed", 0))
	if not player_spawned:
		_fail("player_spawned=false")
		return
	if collision_shape_count <= 0:
		_fail("collision_checked=false")
		return
	if not interaction_completed or completed_count < 1:
		_fail("interaction_completed=false")
		return
	if objective_count != 4:
		_fail("objective_count=%d" % objective_count)
		return
	finished = true
	print("PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=%d objective_count=%d collision_shapes=%d frames=%d" % [completed_count, objective_count, collision_shape_count, frame_count])
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("PLAYABLE SHIP SMOKE FAIL reason=%s" % reason)
	quit(1)
