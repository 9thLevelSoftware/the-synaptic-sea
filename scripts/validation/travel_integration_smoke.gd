extends SceneTree

## Live-coordinator scanner/travel integration smoke. Proves: starting ship is
## wrapped as current_ship; scan() is gated by the current ship's systems;
## travel is gated by propulsion; a successful travel swaps current_ship,
## re-homes the player into the new ship, records the world position, and
## preserves the player_progression instance across the swap.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

# Subcomponents whose repair brings each system to full health (from
# data/ship_systems/systems.json). Repairing power+navigation+scanners+propulsion
# makes all four operational (propulsion/scanners also depend on power+navigation).
const SUBS := {
	"power": ["reactor_core", "power_distribution", "battery_cells"],
	"navigation": ["star_charts", "nav_computer", "sensor_array"],
	"scanners": ["scanner_dish", "signal_processor", "power_coupling"],
	"propulsion": ["thruster_array", "fuel_injection", "nav_linkage"],
}

var main_node: Node
var frame_count: int = 0
var finished: bool = false
# Holds the starting-ship root once a travel detaches it. travel_to()
# intentionally does NOT free the starting ship (Approach A: it is retained to
# return to), so it becomes orphaned in this smoke (no longer under main_node)
# and its nav/physics/render resource tree leaks at exit unless teardown frees
# it explicitly. Captured before the real travel in _validate.
var orphaned_start_root: Node = null
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

func _set_all_operational(mgr) -> void:
	for sid in SUBS.keys():
		for sub_id in SUBS[sid]:
			mgr.force_repair(sid, sub_id)

func _validate(playable: PlayableGeneratedShip) -> void:
	# 1. Starting ship wrapped.
	var start_ship = playable.get_current_ship()
	if start_ship == null or String(start_ship.marker_id) != "":
		_fail("current_ship not wrapped as starting ship (marker_id must be empty)")
		return
	var start_root = start_ship.scene_root

	var mgr = playable.get_ship_systems_manager()
	_set_all_operational(mgr)

	# 2. scan() gated by navigation: nav online -> markers; nav broken -> empty/detail 0.
	var scan_on: Dictionary = playable.scan()
	if int(scan_on.get("detail_level", 0)) < 1 or (scan_on.get("markers", []) as Array).is_empty():
		_fail("scan with systems online returned no markers")
		return
	# Break navigation and rescan.
	mgr.get_system("navigation").get_subcomponent("nav_computer").health = 0.0
	var scan_off: Dictionary = playable.scan()
	if int(scan_off.get("detail_level", -1)) != 0 or not (scan_off.get("markers", []) as Array).is_empty():
		_fail("scan with navigation offline should be detail 0 / empty")
		return
	_set_all_operational(mgr)  # restore

	# 3. Pick a real in-range marker id from the world.
	var world = playable.get_sargasso_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range of the starting position")
		return
	var target_id: String = String(in_range[0].marker_id)

	# 4. Propulsion gate: break propulsion -> travel rejected, no swap.
	mgr.get_system("propulsion").get_subcomponent("thruster_array").health = 0.0
	var rej: Dictionary = playable.travel_to_marker_id(target_id)
	if bool(rej.get("success", true)) or String(rej.get("reason", "")) != "propulsion_offline":
		_fail("travel with propulsion offline should reject with propulsion_offline")
		return
	if playable.get_current_ship() != start_ship:
		_fail("current_ship changed on a rejected travel")
		return

	# 5. Capture the progression instance, repair propulsion, travel for real.
	# Remember the starting-ship root so teardown can free the orphan that
	# travel_to() detaches-but-does-not-free (otherwise its resource tree leaks).
	orphaned_start_root = start_root
	var progression_before = playable.get_player_progression()
	_set_all_operational(mgr)
	var ok: Dictionary = playable.travel_to_marker_id(target_id)
	if not bool(ok.get("success", false)):
		_fail("travel failed after propulsion repaired: reason=%s" % String(ok.get("reason", "")))
		return

	# 6. Swap happened: current_ship is the new ship with the target marker id.
	var new_ship = playable.get_current_ship()
	if new_ship == start_ship:
		_fail("current_ship did not change after successful travel")
		return
	if String(new_ship.marker_id) != target_id:
		_fail("new current_ship marker_id mismatch")
		return
	if new_ship.scene_root == null or not is_instance_valid(new_ship.scene_root):
		_fail("new ship scene_root invalid")
		return
	if new_ship.scene_root.get_parent() != playable:
		_fail("new ship root not parented under the coordinator")
		return

	# 7. World recorded the generated marker and advanced player position.
	if not world.is_generated(target_id):
		_fail("world did not record generated marker")
		return

	# 8. Player preserved (same instance) and re-homed into the new ship.
	if playable.get_player_progression() != progression_before:
		_fail("player_progression instance changed across travel (must persist)")
		return
	if playable.player == null or not is_instance_valid(playable.player):
		_fail("player freed across travel")
		return

	# 9. Starting ship detached but not freed (retains persistent sim).
	if not is_instance_valid(start_root):
		_fail("starting ship root was freed (should be detached-not-freed)")
		return
	if start_root.get_parent() == playable:
		_fail("starting ship root still attached after travel (should be removed)")
		return

	finished = true
	print("TRAVEL INTEGRATION PASS start_wrapped=true scan_gated=true propulsion_gate=true swapped=true progression_persists=true world_recorded=true")
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
	push_error("TRAVEL INTEGRATION FAIL reason=%s" % reason)
	_teardown_and_quit(1)

## Frees the whole scene tree — main_node (which covers the traveled ship, since
## it is parented under the coordinator) and the orphaned starting-ship root that
## travel_to() detached-but-did-not-free. Uses immediate free() + a one-idle-frame
## defer of quit() so the engine flushes the frees before exit; a deferred
## queue_free() can fail to run before quit(), leaving the resources leaked at
## exit and dirtying the clean-output bundle.
func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if orphaned_start_root != null and is_instance_valid(orphaned_start_root):
		orphaned_start_root.free()
		orphaned_start_root = null
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	# Defer quit one idle frame so the freed nodes' resources are released before
	# the engine shuts down.
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
