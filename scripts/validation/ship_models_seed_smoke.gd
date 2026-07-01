extends SceneTree

## Phase 2b: per-ship hull/web seeding + active-ship accessor smoke.
## Validates _seed_ship_models() and the four accessor helpers added to
## PlayableGeneratedShip without performing a full travel sequence.
## Marker: SHIP MODELS SEED PASS hull_seeded=true web_attached=true timestamp_set=true active_resolves=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _validate() -> void:
	finished = true  # prevent re-entry across frames

	# --- 1. Build a derelict ShipInstance and seed it. ---
	var ShipInstanceScript = preload("res://scripts/systems/ship_instance.gd")
	var inst = ShipInstanceScript.create("ship_test", "test:1", null, null, null)
	playable._seed_ship_models(inst)

	# --- 2. hull_seeded: at least one compartment was configured. ---
	var hull_seeded: bool = inst.has_hull()

	# --- 3. web_attached: web model defaults to attached. ---
	var web_attached: bool = inst.get_web().attached_to_web

	# --- 4. timestamp_set: last_sim_time matches world_time at seed. ---
	var timestamp_set: bool = inst.last_sim_time == playable.world_time

	# --- 5. active_resolves: accessors dispatch to per-ship model when away. ---
	var saved_ship = playable.current_ship
	var saved_away: bool = playable.away_from_start

	playable.current_ship = inst
	playable.away_from_start = true
	var hull_away: bool = playable._active_hull() == inst.get_hull()
	var web_away: bool = playable._active_web() == inst.get_web()

	playable.away_from_start = false
	var hull_home: bool = playable._active_hull() == playable.hull_integrity_state
	var web_home: bool = playable._active_web() == playable.hull_web_state

	# Restore.
	playable.current_ship = saved_ship
	playable.away_from_start = saved_away

	var active_resolves: bool = hull_away and web_away and hull_home and web_home

	if hull_seeded and web_attached and timestamp_set and active_resolves:
		print("SHIP MODELS SEED PASS hull_seeded=true web_attached=true timestamp_set=true active_resolves=true")
		_cleanup_and_quit(0)
	else:
		_fail("hull_seeded=%s web_attached=%s timestamp_set=%s active_resolves=%s (hull_away=%s web_away=%s hull_home=%s web_home=%s)" % [
			str(hull_seeded), str(web_attached), str(timestamp_set), str(active_resolves),
			str(hull_away), str(web_away), str(hull_home), str(web_home)
		])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child: Node in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("SHIP MODELS SEED FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
