extends SceneTree

## Proves that a derelict's partial burning set is preserved across a leave-and-revisit:
## - fire_seeded gate prevents re-seeding on revisit (ShipInstance.fire_seeded=true)
## - visited_ships retains the per-ship FireSuppressionState between trips
## - a compartment extinguished on first visit is STILL extinguished on revisit
##
## Uses the LIVE coordinator revisit path (travel_to_marker_id → travel_home →
## travel_to_marker_id with same marker_id) — the exact path _seed_derelict_fire's
## guard protects. A ShipInstance-only round-trip would not catch a re-seed-on-revisit
## regression in the coordinator.
##
## Marker: DERELICT FIRE SEQUENTIAL PERSISTENCE PASS remembered=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const MAX_TRAVEL_ATTEMPTS: int = 6

## Sub-systems repaired so travel is not gated (mirrors derelict_fire_smoke pattern).
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
var _exit_code: int = 0

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
	# --- Repair home ship so travel is not gated ---
	var home_mgr = playable.get_ship_systems_manager()
	if home_mgr == null:
		_fail("home ship_systems_manager missing"); return
	for sid in SUBS.keys():
		for sub_id in SUBS[sid]:
			home_mgr.force_repair(sid, sub_id)

	var world = playable.get_synaptic_sea_world()
	if world == null:
		_fail("no synaptic sea world"); return

	# --- First visit: board a derelict ---
	var marker_id: String = ""
	for attempt in range(MAX_TRAVEL_ATTEMPTS):
		playable.scan()
		var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
		var chosen = null
		for m in in_range:
			var mid: String = String(m.marker_id)
			if mid != "" and not playable.visited_ships.has(mid):
				chosen = m
				break
		if chosen == null:
			break
		var res: Dictionary = playable.travel_to_marker_id(String(chosen.marker_id))
		if bool(res.get("success", false)):
			marker_id = String(chosen.marker_id)
			break

	if marker_id == "":
		_fail("could not board any derelict in %d attempts" % MAX_TRAVEL_ATTEMPTS); return
	if not playable.away_from_start:
		_fail("away_from_start not true after first travel"); return

	var ship_first = playable.get_current_ship()
	if ship_first == null:
		_fail("current_ship is null after first travel"); return
	if not ship_first.fire_seeded:
		_fail("fire_seeded is false after first boarding (expected _seed_derelict_fire to set it)"); return

	# --- Set up clean, deterministic fire state (override presence-gate outcome) ---
	var afs = playable.get_active_fire_state_for_validation()
	if afs == null:
		_fail("get_active_fire_state_for_validation returned null"); return
	afs.active_fires.clear()
	afs.ignition_progress.clear()
	afs.spread_progress.clear()
	afs.cascade_rate_per_second = 0.0

	# Ignite exactly 2 compartments.
	var cid_a: String = "engineering"
	var cid_b: String = "cargo"
	if not playable.force_ignite_active_compartment_for_validation(cid_a, 1.0):
		_fail("force_ignite '%s' failed" % cid_a); return
	if not playable.force_ignite_active_compartment_for_validation(cid_b, 1.0):
		_fail("force_ignite '%s' failed" % cid_b); return
	if not afs.is_burning(cid_a) or not afs.is_burning(cid_b):
		_fail("both compartments should be burning after force_ignite"); return

	# --- Extinguish cid_a via the real interaction path ---
	var ext = playable.get_extinguisher_state()
	if ext == null:
		_fail("extinguisher_state missing"); return
	ext.charge = ext.max_charge
	if int(playable.inventory_state.get_quantity("fire_extinguisher")) < 1:
		playable.inventory_state.add_item("fire_extinguisher", 1)

	var points: Array = playable.get_fire_suppression_points_for_validation()
	if points.is_empty():
		_fail("no fire suppression points on derelict"); return

	var fp_a = null
	for p in points:
		if str(p.compartment_id) == cid_a:
			fp_a = p
			break
	if fp_a == null:
		_fail("no suppression point for '%s'" % cid_a); return

	playable.teleport_player_to_fire_suppression_point_for_validation(fp_a)
	playable._on_player_interact_requested(playable.player)
	if not (fp_a.channeling or fp_a.extinguished):
		_fail("interact did not start the extinguish channel on '%s'" % cid_a); return
	fp_a.advance_channel(10.0)

	if afs.is_burning(cid_a):
		_fail("extinguish of '%s' failed — still burning" % cid_a); return
	if not afs.is_burning(cid_b):
		_fail("'%s' went out unexpectedly (should still burn)" % cid_b); return

	# Record the expected burning set after partial extinguish.
	var burning_before: Array = afs.get_burning_compartments()
	burning_before.sort()
	# Sanity: should be exactly [cid_b].
	if burning_before != [cid_b]:
		_fail("expected burning_before=[%s], got %s" % [cid_b, str(burning_before)]); return

	# --- Leave: travel home ---
	var went_home: bool = playable.travel_home()
	if not went_home:
		_fail("travel_home() returned false"); return
	if playable.away_from_start:
		_fail("still away_from_start after travel_home()"); return

	# --- Revisit: travel to the SAME derelict ---
	var res2: Dictionary = playable.travel_to_marker_id(marker_id)
	if not bool(res2.get("success", false)):
		_fail("revisit travel_to_marker_id('%s') failed" % marker_id); return
	if not playable.away_from_start:
		_fail("away_from_start not true after revisit"); return

	var ship_revisit = playable.get_current_ship()
	if ship_revisit == null:
		_fail("current_ship null after revisit"); return
	if not ship_revisit.fire_seeded:
		_fail("fire_seeded false on revisit (must remain true — not re-seeded)"); return

	# --- Assert burning set is preserved ---
	var afs2 = playable.get_active_fire_state_for_validation()
	if afs2 == null:
		_fail("no active fire state after revisit"); return

	var burning_after: Array = afs2.get_burning_compartments()
	burning_after.sort()

	# The extinguished compartment (cid_a) must still be out;
	# the unextinguished one (cid_b) must still be burning.
	var remembered: bool = (burning_before == burning_after)

	if not remembered:
		push_error("DERELICT FIRE SEQUENTIAL PERSISTENCE FAIL: burning_before=%s burning_after=%s (re-seed or state loss)" % [str(burning_before), str(burning_after)])
		_teardown_and_quit(1)
		return

	finished = true
	print("DERELICT FIRE SEQUENTIAL PERSISTENCE PASS remembered=true")
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
	push_error("DERELICT FIRE SEQUENTIAL PERSISTENCE FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
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
