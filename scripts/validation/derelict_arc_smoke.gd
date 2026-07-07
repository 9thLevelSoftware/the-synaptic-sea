extends SceneTree

## Tranche 1 (audit): the electrical-arc hazard is live on a BOARDED DERELICT.
##
## Two audited defects, same regression class as PRs #42/#43/#44:
##  1. `electrical_arc_state.tick` + `_refresh_arc_state` ran only on the HOME
##     branch of _process — the away branch returned first, so arc phase never
##     advanced while boarded (the primary gameplay context).
##  2. Derelict arc zones were never instantiated: the coordinator built the
##     arc zone node once against the HOME loader, and generated derelicts
##     never even carried arc_zones data (gameplay_slice_builder emitted []).
##
## This smoke drives the REAL boarding path (travel_to_marker_id, no
## away_from_start flag-flip): after boarding a derelict whose layout declares
## arc zones, an arc zone node must exist under the derelict's scene_root, the
## model must cycle DISCHARGED->ARCING through _process away ticks, and the
## zone's collision must block while arcing.
##
## Pass marker: DERELICT ARC PASS boarded=true zone_on_derelict=true away_ticks=<n> arcing_observed=true collision_blocked=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const MAX_MARKERS: int = 4
const MAX_AWAY_TICKS: int = 40  # 40 * 0.5s = 20s sim >> 4s arc cycle

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

func _find_arc_zone_under(node: Node) -> Node:
	if node.has_meta("arc_zone_kind"):
		return node
	for child in node.get_children():
		var found: Node = _find_arc_zone_under(child)
		if found != null:
			return found
	return null

func _validate() -> void:
	finished = true
	_all_operational(playable.get_ship_systems_manager())

	# --- Board a derelict whose layout declares arc zones (real travel path) ---
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	var boarded_with_arc: bool = false
	var tried: int = 0
	for m in in_range:
		if tried >= MAX_MARKERS:
			break
		tried += 1
		if not bool(playable.travel_to_marker_id(String(m.marker_id)).get("success", false)):
			continue
		var root: Node = playable.get_current_ship().scene_root
		if root != null and root.has_method("get_arc_zone_specs") and not (root.get_arc_zone_specs() as Array).is_empty():
			boarded_with_arc = true
			break
	if not boarded_with_arc:
		_fail("no derelict among first %d markers declares arc zones (gameplay_slice_builder arc population missing?)" % tried)
		return
	if not playable.away_from_start:
		_fail("travel succeeded but away_from_start is false")
		return

	# --- Zone node must live under the derelict's scene_root ---
	var derelict_root: Node = playable.get_current_ship().scene_root
	var zone: Node = _find_arc_zone_under(derelict_root)
	if zone == null:
		_fail("no arc zone node under the boarded derelict's scene_root")
		return

	# --- Model must cycle and block on the away branch (real _process ticks) ---
	var arcing_observed: bool = false
	var collision_blocked: bool = false
	var ticks: int = 0
	for i in range(MAX_AWAY_TICKS):
		if playable.vitals_state != null:
			playable.vitals_state.hunger = playable.vitals_state.max_hunger
			playable.vitals_state.thirst = playable.vitals_state.max_thirst
			playable.vitals_state.health = playable.vitals_state.max_health
		playable._process(0.5)
		ticks += 1
		var summary: Dictionary = playable.get_arc_summary()
		if bool(summary.get("arcing", false)):
			arcing_observed = true
			if str(zone.get_meta("arc_zone_phase", "")) == "ARCING":
				for child in zone.get_children():
					if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
						collision_blocked = true
			break
	if not arcing_observed:
		_fail("arc model never reached ARCING across %d away ticks (%.1fs sim) — away branch not ticking the arc" % [ticks, ticks * 0.5])
		return
	if not collision_blocked:
		_fail("model is ARCING but the derelict zone node did not block (scene state not refreshed on away branch)")
		return

	print("DERELICT ARC PASS boarded=true zone_on_derelict=true away_ticks=%d arcing_observed=true collision_blocked=true" % ticks)
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
	push_error("DERELICT ARC FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
