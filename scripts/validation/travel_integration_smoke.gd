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

	# REQ-012: save while on the starting ship — must succeed so we have a
	# snapshot to reload from during the reload-while-away test below.
	var save_result: bool = playable.request_save()
	if not save_result:
		_fail("request_save on starting ship should return true (got false)")
		return

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

	# FIX 1 coverage: after travel, starting-ship gameplay roots must be detached
	# so their collision/interaction volumes do not overlay the boarded derelict.
	if playable.oxygen_root != null and playable.oxygen_root.get_parent() == playable:
		_fail("FIX1: oxygen_root still attached under coordinator after travel (collision volumes overlap derelict)")
		return
	if playable.interaction_root != null and playable.interaction_root.get_parent() == playable:
		_fail("FIX1: interaction_root still attached under coordinator after travel (interactables overlay derelict)")
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

	# PR #7 re-review FIX 2: derelict travel capability — no softlock.
	# While away_from_start==true, scan() and travel_to_marker_id() must work
	# regardless of the derelict's seeded systems (which may be offline).
	# 9a. scan() returns full results on the boarded derelict.
	var derelict_scan: Dictionary = playable.scan()
	if int(derelict_scan.get("detail_level", 0)) < 1 or (derelict_scan.get("markers", []) as Array).is_empty():
		_fail("derelict scan returned no markers — derelict travel-cap gate failed (FIX2)")
		return
	# 9b. Pick an in-range marker from the derelict world position and travel again.
	var world2 = playable.get_sargasso_world()
	var in_range2: Array = world2.markers_in_range(playable.scanner_state.range_radius)
	if in_range2.is_empty():
		_fail("no markers in range of the derelict position (FIX2 derelict→derelict jump)")
		return
	var target_id2: String = String(in_range2[0].marker_id)
	# The second travel frees the first derelict (non-empty marker_id → queue_free'd
	# by travel_to). The resulting second derelict root is a child of playable and is
	# freed by main_node.free() in teardown — no extra orphan tracking needed.
	var ok2: Dictionary = playable.travel_to_marker_id(target_id2)
	if not bool(ok2.get("success", false)):
		_fail("derelict→derelict travel failed: reason=%s (FIX2 softlock guard)" % String(ok2.get("reason", "")))
		return

	# PR #7 re-review FIX 1: interaction gate while aboard a derelict.
	# _on_player_interact_requested must be a no-op while away_from_start==true
	# so stale starting-ship objectives cannot be completed on a derelict.
	# 9c. objective_completion_count is unchanged after interact while away.
	var occ_before: int = playable.objective_completion_count
	playable._on_player_interact_requested(playable.player)
	if playable.objective_completion_count != occ_before:
		_fail("interact while away incremented objective_completion_count (FIX1 gate broken)")
		return

	# REQ-012: reload-while-away verification block.
	# Capture the CURRENT derelict root (second derelict after the derelict→derelict
	# jump above) so we can verify it is detached after reload. new_ship was the first
	# derelict and was already queue_free'd by the second travel.
	var derelict_root_before_reload: Node = playable.get_current_ship().scene_root

	# 10. save() while aboard a traveled derelict now SUCCEEDS (save-anywhere,
	# ADR-0012 supersedes the Phase 4.5 away-save rejection).
	var away_save: bool = playable.request_save()
	if not away_save:
		_fail("request_save while away should succeed (save-anywhere)")
		return

	# 11. reload while away: world save/load restores the full world state.
	# With save-anywhere (ADR-0012), request_load now applies a WorldSnapshot —
	# it rebuilds the home ship first (internally), then re-activates the saved
	# derelict location. The load must succeed.
	var reload_result: bool = playable.request_load()
	if not reload_result:
		_fail("request_load while away should return true (world snapshot from step 10 exists)")
		return

	# After world load, the start loader was re-attached during the home-ship
	# rebuild phase of _apply_world_snapshot, then the derelict was re-activated.
	# Clear orphaned_start_root — it is back in-tree under main_node now.
	orphaned_start_root = null

	# 12. World load restored the saved location (derelict), so away_from_start
	# is true and current_ship is the restored derelict.
	if not playable.away_from_start:
		_fail("away_from_start false after world reload-while-away (derelict location should be restored)")
		return
	if playable.player == null or not is_instance_valid(playable.player):
		_fail("player invalid after world reload-while-away")
		return
	var reloaded_ship = playable.get_current_ship()
	if reloaded_ship == null:
		_fail("current_ship is null after world reload-while-away")
		return
	if String(reloaded_ship.marker_id) == "":
		_fail("reloaded current_ship is the home ship — derelict location was not restored")
		return

	# 13. The OLD derelict scene_root (pre-reload second derelict) was freed
	# during the home-rebuild phase of _apply_world_snapshot. A NEW scene_root
	# was generated by _activate_derelict_from_instance for the restored derelict.
	# Assert the old root is detached (queue_free defers to end-of-frame).
	if derelict_root_before_reload != null and is_instance_valid(derelict_root_before_reload) and derelict_root_before_reload.get_parent() == playable:
		_fail("old derelict scene_root still parented under coordinator after world reload-while-away (should be detached)")
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
