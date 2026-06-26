extends SceneTree

## End-to-end docking-loop persistence smoke (Phase 5a, lean Option A).
##
## Asserts in order:
##   OPENING  — lifeboat is non-null, docked to home_ship, active_ship_root_count >= 2
##   LOOP     — loot home containers for a circuit_board, repair propulsion nav_linkage,
##              assert operational, travel to an in-range marker, travel_home()
##   PERSIST  — request_save(), request_load(), then lifeboat still docked + repair persisted
##
## Prints: DOCKING LOOP PASS opening=true looped=true persisted=true

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
	# ── OPENING assertions ─────────────────────────────────────────────────────
	var lb = playable.get_lifeboat_ship_for_validation()
	if lb == null:
		_fail("OPENING: lifeboat_ship is null at boot"); return
	var home = playable.get_home_ship_for_validation()
	if home == null:
		_fail("OPENING: home_ship is null at boot"); return
	if lb.parent_ship != home:
		_fail("OPENING: lifeboat.parent_ship != home_ship (got %s)" % str(lb.parent_ship)); return
	var root_count: int = playable.active_ship_root_count_for_validation()
	if root_count < 2:
		_fail("OPENING: active_ship_root_count=%d (expected >= 2)" % root_count); return

	# ── LOOP assertions ────────────────────────────────────────────────────────
	# Loot home containers for a circuit_board.
	if playable.loot_containers.is_empty():
		_fail("LOOP: no loot containers on home ship"); return
	for lc in playable.loot_containers:
		playable.search_loot_container_for_validation(String(lc.container_id))
	if playable.inventory_state.get_quantity("circuit_board") < 1:
		_fail("LOOP: did not obtain a circuit_board from home loot"); return

	# Repair propulsion/nav_linkage on the lifeboat.
	# Propulsion depends on power + navigation; mirror repair_loop_smoke which
	# force-repairs power and navigation first so propulsion can go operational.
	var mgr = playable.get_ship_systems_manager()
	if mgr.is_operational("propulsion"):
		_fail("LOOP: propulsion should be offline at boot (nav_linkage broken)"); return
	for sid in ["power", "navigation"]:
		for sub in mgr.get_system(sid).subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)
	if not playable.repair_subcomponent_for_validation("propulsion", "nav_linkage"):
		_fail("LOOP: could not start nav_linkage repair channel"); return
	playable.advance_repair_channels_for_validation(999.0)
	if not mgr.is_operational("propulsion"):
		_fail("LOOP: propulsion not operational after repair"); return

	# Travel to an in-range marker.
	var world = playable.get_synapse_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("LOOP: no markers in range after propulsion repair"); return
	var marker_id: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("LOOP: travel to marker '%s' failed after repair" % marker_id); return

	# Return home.
	if not playable.travel_home():
		_fail("LOOP: travel_home() failed"); return

	# ── PERSIST assertions ─────────────────────────────────────────────────────
	if not playable.request_save():
		_fail("PERSIST: request_save() failed"); return
	if not playable.request_load():
		_fail("PERSIST: request_load() failed"); return

	# Lifeboat must be rebuilt and re-docked after reload.
	var lb2 = playable.get_lifeboat_ship_for_validation()
	if lb2 == null:
		_fail("PERSIST: lifeboat_ship is null after reload"); return
	var home2 = playable.get_home_ship_for_validation()
	if home2 == null:
		_fail("PERSIST: home_ship is null after reload"); return
	if lb2.parent_ship != home2:
		_fail("PERSIST: lifeboat.parent_ship != home_ship after reload (got %s)" % str(lb2.parent_ship)); return

	# Propulsion repair must persist across save/load (the coordinator applies
	# ship_systems_summary in _apply_run_snapshot, which restores nav_linkage as
	# functional — same contract asserted by repair_loop_smoke).
	var mgr2 = playable.get_ship_systems_manager()
	if not mgr2.get_system("propulsion").get_subcomponent("nav_linkage").is_functional():
		_fail("PERSIST: nav_linkage repair did not persist across save/load"); return

	# ── PASS ───────────────────────────────────────────────────────────────────
	finished = true
	print("DOCKING LOOP PASS opening=true looped=true persisted=true")
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
	push_error("DOCKING LOOP FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free(); main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
