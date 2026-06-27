extends SceneTree

## Procgen-expansion reachability proof: travelling to a live derelict now runs
## the Task-12 ShipLayoutGenerator extension path — EncounterInjector + room-variant
## selection + biome/difficulty stamping — instead of the bare empty-id layout.
##
## Before this wiring, ShipGenerator called the layout generator with empty
## biome/difficulty ids, so `layout.encounters` was always empty and threat spawning
## fell back to a hardcoded 5-archetype set. Now the coordinator resolves a
## deterministic per-derelict biome+difficulty from the target marker and hands them
## to ShipGenerator.configure_run_context() before travel.
##
## This drives the LIVE coordinator (not a unit test): it travels to real in-range
## derelict markers and asserts the built derelict's layout is biome/difficulty-stamped
## and that injected encounters (not the fallback) drive the threat manager.
##
## Pass marker (stable head; biome/difficulty/encounters trail as descriptive values):
##   MAIN PLAYABLE DERELICT ENCOUNTER INJECTION PASS injected_threats=true reachable=true biome=<id> difficulty=<id> encounters=N

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const MAX_TRAVEL_ATTEMPTS: int = 6

# Repairing these subcomponents brings power/navigation/scanners/propulsion online
# so scan() returns markers and travel is not propulsion-gated (mirrors
# travel_integration_smoke).
const SUBS := {
	"power": ["reactor_core", "power_distribution", "battery_cells"],
	"navigation": ["star_charts", "nav_computer", "sensor_array"],
	"scanners": ["scanner_dish", "signal_processor", "power_coupling"],
	"propulsion": ["thruster_array", "fuel_injection", "nav_linkage"],
}

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if not playable.playable_started:
		return
	_validate(playable)

func _set_all_operational(mgr) -> void:
	for sid in SUBS.keys():
		for sub_id in SUBS[sid]:
			mgr.force_repair(sid, sub_id)

func _validate(playable: PlayableGeneratedShip) -> void:
	var mgr = playable.get_ship_systems_manager()
	_set_all_operational(mgr)
	var world = playable.get_synaptic_sea_world()

	var stamped_biome: String = ""
	var stamped_difficulty: String = ""
	var encounter_count: int = 0
	var injected_threats: bool = false
	var any_travel: bool = false
	var visited: Dictionary = {}

	# Travel to derelicts and accept the first whose layout carries injected encounters.
	# The density clamp in EncounterInjector makes any single small derelict potentially
	# empty, so we iterate. IMPORTANT: re-scan from the CURRENT world position each
	# attempt — travel_to_marker_id moves the player, so the previous scan's markers may
	# no longer be in range (Codex). Pick the largest unvisited in-range marker (more
	# rooms -> more reliable encounter rolls).
	for attempt in range(MAX_TRAVEL_ATTEMPTS):
		playable.scan()
		var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
		var marker = null
		for m in in_range:
			if visited.has(String(m.marker_id)):
				continue
			if marker == null or int(m.size_class) > int(marker.size_class):
				marker = m
		if marker == null:
			break  # nothing new in range from the current position
		visited[String(marker.marker_id)] = true

		var res: Dictionary = playable.travel_to_marker_id(String(marker.marker_id))
		if not bool(res.get("success", false)):
			continue
		any_travel = true
		var ship = playable.get_current_ship()
		if ship == null or typeof(ship.built_layout) != TYPE_DICTIONARY:
			continue
		var layout: Dictionary = ship.built_layout

		# Wiring proof (deterministic): the run context threaded through, so Stage 6
		# ran and stamped biome_id/difficulty_id and emitted an encounters array.
		stamped_biome = str(layout.get("biome_id", ""))
		stamped_difficulty = str(layout.get("difficulty_id", ""))
		if stamped_biome.is_empty():
			_fail("derelict layout missing biome_id stamp (run context did not reach the generator)")
			return
		if stamped_difficulty.is_empty():
			_fail("derelict layout missing difficulty_id stamp")
			return
		if not (layout.get("encounters", null) is Array):
			_fail("derelict layout has no encounters array (EncounterInjector Stage 6 did not run)")
			return

		var encs: Array = layout.get("encounters", [])
		if encs.is_empty():
			continue  # this derelict rolled zero encounters; re-scan and try another
		encounter_count = encs.size()

		# Encounters drive combat: the threat manager spawned from the injected markers
		# (instance ids prefixed "enc_") rather than the hardcoded fallback ("fallback_").
		var tm = playable.threat_manager
		if tm == null:
			_fail("threat_manager missing after travel")
			return
		for threat in tm.threats:
			if str(threat.instance_id).begins_with("enc_"):
				injected_threats = true
				break
		if not injected_threats:
			_fail("derelict has %d injected encounters but no threat spawned from them (instance ids: %s)" % [
				encounter_count, str(_threat_ids(tm))])
			return
		break

	if not any_travel:
		_fail("no in-range marker accepted travel in %d attempts" % MAX_TRAVEL_ATTEMPTS)
		return
	if encounter_count <= 0:
		_fail("no in-range derelict produced injected encounters in %d attempts (clamp/density too low?)" % MAX_TRAVEL_ATTEMPTS)
		return

	finished = true
	print("MAIN PLAYABLE DERELICT ENCOUNTER INJECTION PASS injected_threats=%s reachable=true biome=%s difficulty=%s encounters=%d" % [
		str(injected_threats).to_lower(), stamped_biome, stamped_difficulty, encounter_count])
	_teardown_and_quit(0)

func _threat_ids(tm) -> Array:
	var out: Array = []
	for threat in tm.threats:
		out.append(str(threat.instance_id))
	return out

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE DERELICT ENCOUNTER INJECTION FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable != null:
		for mid in playable.visited_ships:
			_free_detached_ship_root(playable.visited_ships[mid])
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	call_deferred("_do_quit")

func _free_detached_ship_root(inst) -> void:
	if inst == null:
		return
	var root = inst.scene_root
	if root != null and is_instance_valid(root) and root.get_parent() == null:
		root.free()
		inst.scene_root = null

func _do_quit() -> void:
	quit(_exit_code)
