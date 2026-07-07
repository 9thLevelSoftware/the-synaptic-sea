extends SceneTree

## Tranche 1 (audit): three away-branch integrity defects, one boarding run.
##
## 1. port_frame  — _build_extinguisher_recharge_port() lacked the
##    `not away_from_start` term its fire-zone sibling has: on a derelict it
##    computed a LIFEBOAT-local position but parented under the DERELICT root
##    (wrong frame). The port must sit on one of the derelict's own room
##    positions, parented under the derelict's scene_root.
## 2. hud_refresh — home refreshes the tracker's system status lines every
##    frame via _refresh_oxygen_state; the away branch skipped them, freezing
##    Power/Reactor/Threats for the whole boarding run. A sentinel written to
##    the tracker must be overwritten by the next away _process tick.
## 3. death_guard — death away (end_run -> slice_complete) must stop the sim
##    like death at home; previously every system kept ticking on a corpse.
##    After death, sanity must stop draining across further away ticks.
##
## Real boarding path (travel_to_marker_id), no away_from_start flag-flip.
## Pass marker: AWAY BRANCH INTEGRITY PASS boarded=true port_frame=true hud_refresh=true death_guard=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if not is_instance_valid(playable):
		playable = _find_playable(main_node)
	if not is_instance_valid(playable) or not is_instance_valid(playable.loader) or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _all_operational(mgr) -> void:
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys == null:
			continue
		for sub in sys.subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)

func _validate() -> void:
	finished = true
	_all_operational(playable.get_ship_systems_manager())

	# --- Board a derelict through the real travel path ----------------------
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	if not bool(playable.travel_to_marker_id(String(in_range[0].marker_id)).get("success", false)):
		_fail("travel to derelict failed")
		return
	if not playable.away_from_start:
		_fail("travel succeeded but away_from_start is false")
		return

	# --- 1. port_frame -------------------------------------------------------
	var port = playable.get_extinguisher_recharge_port_for_validation()
	if port == null or not is_instance_valid(port):
		_fail("no extinguisher recharge port on the boarded derelict")
		return
	var derelict_root: Node = playable.get_current_ship().scene_root
	if port.get_parent() != derelict_root:
		_fail("recharge port parented under %s, expected the derelict scene_root" % str(port.get_parent()))
		return
	var derelict_positions: Array = playable._distributed_room_positions()
	var on_derelict_room: bool = false
	for p in derelict_positions:
		if p is Vector3 and (port as Node3D).position.distance_to(p) < 0.01:
			on_derelict_room = true
			break
	if not on_derelict_room:
		_fail("recharge port at %s is not on any derelict room position (lifeboat-local frame leak)" % str((port as Node3D).position))
		return

	# --- 2. hud_refresh -------------------------------------------------------
	if playable.tracker == null:
		_fail("tracker missing")
		return
	playable.tracker.set_system_status_lines(PackedStringArray(["SENTINEL_LINE"]))
	playable._process(0.1)
	var lines: PackedStringArray = playable.tracker.system_status_lines
	if lines.size() == 1 and String(lines[0]) == "SENTINEL_LINE":
		_fail("tracker status lines not refreshed by an away _process tick (sentinel survived)")
		return

	# --- 3. death_guard -------------------------------------------------------
	if playable.vitals_state == null or playable.sanity_state == null:
		_fail("vitals/sanity state missing")
		return
	playable.vitals_state.health = 0.0
	playable._process(0.5)  # death detected this frame -> end_run("death")
	if not playable.slice_complete:
		_fail("death away did not end the run (slice_complete=false)")
		return
	var sanity_at_death: float = playable.sanity_state.sanity
	for i in range(5):
		playable._process(0.5)
	if absf(playable.sanity_state.sanity - sanity_at_death) > 0.0001:
		_fail("systems kept ticking after death away: sanity %.3f -> %.3f" % [sanity_at_death, playable.sanity_state.sanity])
		return

	print("AWAY BRANCH INTEGRITY PASS boarded=true port_frame=true hud_refresh=true death_guard=true")
	_cleanup(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("AWAY BRANCH INTEGRITY FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
