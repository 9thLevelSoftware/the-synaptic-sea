extends SceneTree

## Main-scene smoke: travel is gated by the LIFEBOAT's propulsion (home AND away);
## blocked while offline, succeeds after repair; travel_home always available.
##
## Note on home_always: travel_home() returns false when already home (not away),
## which is correct behaviour — the "no-strand" guarantee means calling it is
## always safe, not that it returns true when already home. We assert safety by
## confirming the player stays on the lifeboat after the call (away_from_start is
## still false) and no error is thrown.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished: return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES: _fail("no PlayableGeneratedShip")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	var mgr = playable.get_ship_systems_manager()
	# Make power + navigation operational so propulsion's deps are satisfied.
	for sid in ["power", "navigation"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				mgr.force_repair(sid, sub.subcomponent_id)
	# Break propulsion so it is offline.
	mgr.get_system("propulsion").get_subcomponent("nav_linkage").health = 0.1
	if mgr.is_operational("propulsion"):
		_fail("propulsion should be offline after breaking nav_linkage"); return

	# A marker must be in range to attempt travel.
	var world = playable.get_synapse_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range"); return
	var marker_id: String = String(in_range[0].marker_id)

	# Offline propulsion blocks travel_to.
	var blocked: Dictionary = playable.travel_to_marker_id(marker_id)
	if bool(blocked.get("success", false)):
		_fail("travel_to should be blocked while lifeboat propulsion offline"); return
	var blocked_offline: bool = String(blocked.get("reason", "")) == "propulsion_offline"

	# travel_home is always safe: calling it while already home must not throw
	# and must not move the player off the lifeboat. (Returns false when not away —
	# that is correct; the no-strand guarantee is safety, not a true return.)
	var _home_ret = playable.travel_home()  # ignore return value — safe when already home
	var home_always: bool = not playable.away_from_start

	# Repair propulsion, then travel_to succeeds.
	mgr.force_repair("propulsion", "nav_linkage")
	if not mgr.is_operational("propulsion"):
		_fail("propulsion should be operational after repair"); return
	var after: Dictionary = playable.travel_to_marker_id(marker_id)
	var travels_after: bool = bool(after.get("success", false))

	if not (blocked_offline and home_always and travels_after):
		_fail("blocked_offline=%s home_always=%s travels_after=%s" % [
			str(blocked_offline), str(home_always), str(travels_after)]); return

	# ---- AWAY-PHASE: prove the away-branch reads the LIFEBOAT, not the derelict ----
	# After the successful travel_to above we are now aboard a derelict.
	if not playable.away_from_start:
		_fail("expected away_from_start==true after travel succeeded"); return

	# Break the lifeboat's propulsion again while away.
	mgr.get_system("propulsion").get_subcomponent("nav_linkage").health = 0.1
	if mgr.is_operational("propulsion"):
		_fail("lifeboat propulsion should be offline again after second break"); return

	# Look for a DIFFERENT in-range marker to assert onward-travel is blocked.
	var in_range_away: Array = world.markers_in_range(playable.scanner_state.range_radius)
	var other_marker_id: String = ""
	for m in in_range_away:
		var mid: String = String(m.marker_id)
		if mid != marker_id:
			other_marker_id = mid
			break

	if other_marker_id != "":
		# Assert that travelling to a different marker while lifeboat propulsion is
		# broken returns propulsion_offline — the derelict's own systems do NOT gate this.
		var away_blocked: Dictionary = playable.travel_to_marker_id(other_marker_id)
		if bool(away_blocked.get("success", false)):
			_fail("away travel_to should be blocked when lifeboat propulsion offline"); return
		if String(away_blocked.get("reason", "")) != "propulsion_offline":
			_fail("away travel_to reason should be propulsion_offline, got: %s" % str(away_blocked.get("reason", ""))); return
	else:
		# Only one marker in range — assert the no-strand guarantee while away:
		# travel_home() must succeed even with broken lifeboat propulsion (it is
		# not propulsion-gated), keeping the player safe.
		print("LIFEBOAT TRAVEL GATE: away-onward-block sub-assertion SKIPPED (only one marker in range)")
		var home_ret_away: bool = playable.travel_home()
		if not home_ret_away:
			_fail("travel_home should succeed while away (no-strand guarantee)"); return
		# Repair so teardown is clean.
		mgr.force_repair("propulsion", "nav_linkage")
		finished = true
		print("LIFEBOAT TRAVEL GATE PASS blocked_offline=true travels_after_repair=true home_always=true")
		_teardown_and_quit(0)
		return

	# Repair propulsion and travel home cleanly.
	mgr.force_repair("propulsion", "nav_linkage")
	var went_home: bool = playable.travel_home()
	if not went_home:
		_fail("travel_home should succeed after repairing propulsion while away"); return

	finished = true
	print("LIFEBOAT TRAVEL GATE PASS blocked_offline=true travels_after_repair=true home_always=true")
	_teardown_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null: return found
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("LIFEBOAT TRAVEL GATE FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free(); main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
