extends SceneTree

## Domain 2 (PR #51 review, Codex P1): when a threat is killed on a REAL boarded
## derelict, the lootable corpse container must spawn at the threat's actual world
## position. The threat world_position is GLOBAL (bakes in the derelict's global
## anchor); the corpse parents under the derelict scene_root (offset by
## DERELICT_DOCK_OFFSET) and LootContainer stores the configured position as LOCAL,
## so the coordinator must convert global->local. Without that conversion the corpse
## double-offsets ~100u away and the range interaction can never reach it.
##
## Requires a REAL boarding (travel_to_marker_id) so current_ship.scene_root is a
## genuine offset derelict — setting away_from_start=true alone parents at origin and
## cannot exercise the bug.
##
## Marker: MAIN PLAYABLE COMBAT CORPSE POSITION PASS boarded=true corpse_global_ok=true dist=<d>

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const MAX_TRAVEL_ATTEMPTS: int = 6
const SUBS := {
	"power": ["reactor_core", "power_distribution", "battery_cells"],
	"navigation": ["star_charts", "nav_computer", "sensor_array"],
	"scanners": ["scanner_dish", "signal_processor", "power_coupling"],
	"propulsion": ["thruster_array", "fuel_injection", "nav_linkage"],
}

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	# --- Board a real derelict (mirror main_playable_derelict_fire_smoke) ---
	var home_mgr = playable.get_ship_systems_manager()
	if home_mgr == null:
		_fail("home ship_systems_manager missing"); return
	for sid in SUBS.keys():
		for sub_id in SUBS[sid]:
			home_mgr.force_repair(sid, sub_id)
	var world = playable.get_synaptic_sea_world()
	if world == null:
		_fail("no synaptic sea world"); return
	var boarded: bool = false
	var visited: Dictionary = {}
	for attempt in range(MAX_TRAVEL_ATTEMPTS):
		playable.scan()
		var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
		var marker = null
		for m in in_range:
			if not visited.has(String(m.marker_id)):
				marker = m
				break
		if marker == null:
			break
		visited[String(marker.marker_id)] = true
		if bool(playable.travel_to_marker_id(String(marker.marker_id)).get("success", false)):
			boarded = true
			break
	if not boarded:
		_fail("could not board any derelict in %d attempts" % MAX_TRAVEL_ATTEMPTS); return
	if not playable.away_from_start:
		_fail("away_from_start not true after travel"); return
	var current_ship = playable.get_current_ship()
	if current_ship == null or not is_instance_valid(current_ship.scene_root):
		_fail("current_ship / scene_root missing after travel"); return

	# --- Inject a threat at a KNOWN global world position on the derelict, then kill it. ---
	var tm = playable.threat_manager
	if tm == null:
		_fail("threat_manager missing"); return
	tm.threats.clear()
	tm.inject_validation_encounter(["stalker"], (current_ship.scene_root as Node3D).global_position)
	if tm.threats.is_empty():
		_fail("no threat injected"); return
	var target_world: Vector3 = (current_ship.scene_root as Node3D).global_position + Vector3(3.0, 0.0, 2.0)
	tm.threats[0].world_position = [target_world.x, target_world.y, target_world.z]
	var kill_id: String = String(tm.threats[0].instance_id)
	var before: int = playable.loot_containers.size()

	# Kill through the live coordinator tick (away branch).
	tm.threats[0].health = 0.0
	playable._process(1.0 / 30.0)
	if playable.loot_containers.size() <= before:
		_fail("kill did not spawn a corpse container"); return

	# Find the corpse container by id and check its GLOBAL position.
	var corpse = null
	for lc in playable.loot_containers:
		if is_instance_valid(lc) and String(lc.container_id) == "corpse_%s" % kill_id:
			corpse = lc
			break
	if corpse == null:
		_fail("corpse container not found by id corpse_%s" % kill_id); return
	var dist: float = ((corpse as Node3D).global_position - target_world).length()
	if dist > 1.0:
		_fail("corpse global pos off by %.1f (expected ~%v, got %v) — coordinate-frame bug" % [dist, target_world, (corpse as Node3D).global_position]); return

	finished = true
	print("MAIN PLAYABLE COMBAT CORPSE POSITION PASS boarded=true corpse_global_ok=true dist=%.2f" % dist)
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f: PlayableGeneratedShip = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE COMBAT CORPSE POSITION FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
