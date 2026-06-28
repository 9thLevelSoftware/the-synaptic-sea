extends SceneTree

## Live-scene proof that derelict fire ticks on the away branch: the fire model
## spreads/damages derelict systems, hurts the player standing in it, the recharge
## port is power-gated by the derelict's own power system, and manual extinguish
## works via the real interaction path.
##
## Requires a REAL boarding (travel_to_marker_id) so current_ship is a genuine
## derelict instance — setting away_from_start=true alone falls back to the home
## fire model and does not test the derelict path.
##
## Marker: MAIN PLAYABLE DERELICT FIRE PASS away_ticks=<n> seeded=true ticked=true hurt=true port_gated=true extinguished=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const MAX_TRAVEL_ATTEMPTS: int = 6

# Sub-systems repaired so travel is not gated (mirrors derelict_encounter_injection_smoke).
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
	# --- Board a real derelict ---
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
		var res: Dictionary = playable.travel_to_marker_id(String(marker.marker_id))
		if bool(res.get("success", false)):
			boarded = true
			break

	if not boarded:
		_fail("could not board any derelict in %d attempts" % MAX_TRAVEL_ATTEMPTS); return
	if not playable.away_from_start:
		_fail("away_from_start not true after travel"); return
	var current_ship = playable.get_current_ship()
	if current_ship == null:
		_fail("current_ship is null after travel"); return

	var seeded: bool = current_ship.fire_seeded

	# --- Set up derelict fire state ---
	var derelict_mgr = current_ship.systems_manager
	if derelict_mgr == null:
		_fail("derelict systems_manager is null"); return
	if derelict_mgr.get_system("power") == null:
		_fail("derelict has no 'power' system"); return

	# Clear any fires that were seeded at boarding so we start deterministic.
	var afs = playable.get_active_fire_state_for_validation()
	if afs == null:
		_fail("get_active_fire_state_for_validation returned null"); return
	afs.active_fires.clear()
	afs.ignition_progress.clear()
	afs.spread_progress.clear()
	# Disable arc cascade to keep the test clean (arc state is home-side anyway).
	afs.cascade_rate_per_second = 0.0

	# Set derelict power subcomponents to 0.1 (below 0.5 operational threshold):
	# - Port reads UNPOWERED (derelict power not operational)
	# - System has room to drop further from fire damage (ticked assertion)
	for sub in derelict_mgr.get_system("power").subcomponents:
		sub.health = 0.1

	# Ignite engineering (mapped to "power") on the derelict.
	var ok: bool = playable.force_ignite_active_compartment_for_validation("engineering", 1.0)
	if not ok:
		_fail("force_ignite_active_compartment_for_validation failed"); return

	# --- Assert fire zones built on the derelict ---
	var zones: Array = playable.get_fire_zone_nodes_for_validation()
	if zones.is_empty():
		_fail("no fire zones built on derelict after ignition (positions may be empty)"); return

	# Find the engineering fire zone to stand in.
	var ez: Node3D = _find_fire_zone(zones, "engineering")
	if ez == null:
		_fail("no 'engineering' fire zone (map key mismatch?)"); return

	# Clear threats so combat damage cannot mask the fire-health result.
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()

	# Teleport player into the engineering fire zone.
	if playable.player != null and playable.player is Node3D:
		(playable.player as Node3D).global_position = ez.global_position

	playable.vitals_state.health = 90.0

	# --- Drive 60 frames while away; count away_ticks ---
	var sys_health_before: float = derelict_mgr.get_system("power").health()
	var health_before: float = playable.vitals_state.health
	var away_ticks: int = 0
	var step: float = 1.0 / 30.0
	for _i in range(60):
		playable._process(step)
		if playable.away_from_start:
			away_ticks += 1

	var ticked: bool = derelict_mgr.get_system("power").health() < sys_health_before
	var hurt: bool = playable.vitals_state.health < health_before

	# --- Recharge port gating ---
	var port = playable.get_extinguisher_recharge_port_for_validation()
	if port == null:
		_fail("no recharge port present"); return

	# Drive one frame to let the away-branch fire loop set the port power state.
	playable._process(step)
	away_ticks += 1

	# Port is UNPOWERED because derelict "power" is below operational threshold.
	var port_unpowered: bool = not port.powered

	# Repair derelict power; drive one frame; port should become POWERED.
	for sub in derelict_mgr.get_system("power").subcomponents:
		sub.health = 1.0
	playable._process(step)
	away_ticks += 1
	var port_powered: bool = port.powered
	var port_gated: bool = port_unpowered and port_powered

	# --- Manual extinguish via the REAL interaction path ---
	var ext = playable.get_extinguisher_state()
	if ext == null:
		_fail("extinguisher_state missing"); return
	ext.charge = ext.max_charge
	if int(playable.inventory_state.get_quantity("fire_extinguisher")) < 1:
		playable.inventory_state.add_item("fire_extinguisher", 1)

	var points: Array = playable.get_fire_suppression_points_for_validation()
	if points.is_empty():
		_fail("no fire suppression points on derelict (zones may not attach properly)"); return
	var fp = null
	for p in points:
		if str(p.compartment_id) == "engineering":
			fp = p
	if fp == null:
		fp = points[0]  # fallback: extinguish whatever is burning

	# Fire must still be burning for try_start to succeed.
	if not afs.is_burning(str(fp.compartment_id)):
		_fail("fire in '%s' is no longer burning before the extinguish step" % fp.compartment_id); return

	playable.teleport_player_to_fire_suppression_point_for_validation(fp)
	playable._on_player_interact_requested(playable.player)
	if not (fp.channeling or fp.extinguished):
		_fail("interact dispatch did not start the extinguish channel on the derelict"); return
	fp.advance_channel(10.0)

	var extinguished: bool = not afs.is_burning(str(fp.compartment_id))

	# --- Final checks and marker ---
	if away_ticks <= 0:
		_fail("no away_ticks recorded"); return
	if not seeded:
		_fail("fire_seeded is false after boarding"); return
	if not ticked:
		_fail("fire did not tick (derelict power health did not decrease; was=%.3f)" % sys_health_before); return
	if not hurt:
		_fail("player health did not drop while standing in derelict fire (was=%.1f now=%.1f)" % [health_before, playable.vitals_state.health]); return
	if not port_gated:
		_fail("port power gate failed: unpowered=%s powered=%s" % [port_unpowered, port_powered]); return
	if not extinguished:
		_fail("manual extinguish did not clear the derelict fire in '%s'" % fp.compartment_id); return

	finished = true
	print("MAIN PLAYABLE DERELICT FIRE PASS away_ticks=%d seeded=true ticked=true hurt=true port_gated=true extinguished=true" % away_ticks)
	_teardown_and_quit(0)

func _find_fire_zone(zones: Array, cid: String) -> Node3D:
	for z in zones:
		if str(z.get_meta("fire_compartment_id", "")) == cid and z is Node3D:
			return z as Node3D
	return null

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
	push_error("MAIN PLAYABLE DERELICT FIRE FAIL reason=%s" % reason)
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
