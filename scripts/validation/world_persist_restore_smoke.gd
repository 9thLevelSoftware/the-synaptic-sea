extends SceneTree

## In-session persist-and-restore smoke. Proves: travel to derelict A registers
## a ShipInstance; mutating A's systems then leaving (travel to B) keeps A's
## instance with its mutated state; revisiting A restores that state (NOT a fresh
## regenerate) with identical geometry signature; travel_home returns to the home
## ship instance.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

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
	_validate(playable)

func _all_operational(mgr) -> void:
	# Repair the four travel-relevant systems so jumps succeed from any ship.
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys == null:
			continue
		for sub in sys.subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)

func _validate(playable: PlayableGeneratedShip) -> void:
	# Home ship wrapped and registered as home_ship.
	var home = playable.get_current_ship()
	if home == null or String(home.marker_id) != "":
		_fail("home ship not wrapped (marker_id must be empty)")
		return
	if playable.home_ship != home:
		_fail("home_ship reference not set to the starting ship")
		return
	_all_operational(playable.get_ship_systems_manager())

	# Travel to derelict A.
	var world = playable.get_synapse_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.size() < 1:
		_fail("no markers in range of the home position")
		return
	var id_a: String = String(in_range[0].marker_id)
	var ra: Dictionary = playable.travel_to_marker_id(id_a)
	if not bool(ra.get("success", false)):
		_fail("travel to A failed: %s" % String(ra.get("reason", "")))
		return
	if not playable.visited_ships.has(id_a):
		_fail("derelict A not registered in visited_ships")
		return
	var inst_a = playable.visited_ships[id_a]

	# Mutate A's own systems manager to a recognisable state and snapshot it.
	inst_a.systems_manager.force_repair("power", inst_a.systems_manager.get_system("power").subcomponents[0].subcomponent_id)
	var a_summary_after_mutation: Dictionary = inst_a.systems_manager.get_summary()

	# Leave A by traveling to derelict B (from A's map position).
	var in_range2: Array = world.markers_in_range(playable.scanner_state.range_radius)
	var id_b: String = ""
	for m in in_range2:
		if String(m.marker_id) != id_a:
			id_b = String(m.marker_id)
			break
	if id_b == "":
		_fail("could not find a second distinct marker B in range of A")
		return
	var rb: Dictionary = playable.travel_to_marker_id(id_b)
	if not bool(rb.get("success", false)):
		_fail("travel to B failed: %s" % String(rb.get("reason", "")))
		return
	# A's instance is RETAINED with its mutated state; only its scene was freed.
	if not playable.visited_ships.has(id_a):
		_fail("derelict A dropped from visited_ships after leaving (state lost)")
		return
	if playable.visited_ships[id_a] != inst_a:
		_fail("derelict A instance replaced after leaving (must be the same retained object)")
		return

	# Revisit A: same retained instance, state preserved (NOT regenerated fresh).
	var ra2: Dictionary = playable.travel_to_marker_id(id_a)
	if not bool(ra2.get("success", false)):
		_fail("revisit A failed: %s" % String(ra2.get("reason", "")))
		return
	if playable.get_current_ship() != inst_a:
		_fail("revisit A did not restore the retained instance")
		return
	if inst_a.systems_manager.get_summary() != a_summary_after_mutation:
		_fail("derelict A systems state was regenerated, not preserved across revisit")
		return
	if inst_a.scene_root == null or not is_instance_valid(inst_a.scene_root):
		_fail("revisited A has no live scene_root")
		return

	# travel_home returns to the home instance with gameplay roots reattached.
	var home_ok: bool = playable.travel_home()
	if not home_ok:
		_fail("travel_home returned false")
		return
	if playable.get_current_ship() != home:
		_fail("travel_home did not restore the home ship instance")
		return
	if playable.away_from_start:
		_fail("away_from_start still true after travel_home")
		return
	if playable.oxygen_root == null or playable.oxygen_root.get_parent() != playable:
		_fail("gameplay roots not reattached after travel_home")
		return

	finished = true
	print("WORLD PERSIST RESTORE PASS registered=true state_preserved=true revisit_restores=true travel_home=true")
	_teardown_and_quit(0)

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
	push_error("WORLD PERSIST RESTORE FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
