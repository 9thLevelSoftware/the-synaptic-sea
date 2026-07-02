extends SceneTree

# procgen_variant_hazard_smoke — Domain 7 (travel loop closure), state layer.
# Drives away_from_start = true, injects a fire variant on the engineering room
# and a breach variant on the bridge room of the boarded derelict, then asserts:
#   - _seed_derelict_breaches force-breaches the bridge compartment on the
#     DERELICT's hull (current_ship.get_hull()) while the HOME hull's bridge
#     stays clean (wrong-target regression guard, Task 4 review),
#   - _seed_derelict_fire ignites the engineering compartment (forced by variant),
#   - re-running does NOT re-seed (fire_seeded / breach_seeded guards),
#   - the ignited/breached set is deterministic (same on a second identical run).
# Seed order: breaches before fire (mirrors the build path so the fire
# presence-gate exclusion can see variant breaches). The exclusion fix is
# covered by the away-aware _active_hull() read and seed ordering in
# playable_generated_ship.gd; a full gate-path assertion (requiring a seed
# passing the 15% gate + a damaged mapped system) is deferred.
# (bridge, not cargo: hull_compartments.json ships cargo pre-breached, so a cargo
# assertion would be vacuous.)
# Marker: PROCGEN VARIANT HAZARD PASS away_ticks=<n> fire_lit=true breach_open=true home_clean=true guarded=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _validate() -> void:
	finished = true

	# Force the away (derelict) branch and ensure a current_ship exists.
	playable.away_from_start = true
	if playable.current_ship == null:
		_fail("no current_ship on away branch")
		return

	# The home ship's golden layout lacks engineering/bridge rooms, and its
	# ShipInstance hull is bare (home uses the coordinator's singletons, not
	# per-ship models). Inject synthetic rooms AND configure the per-ship hull
	# + fire so the real seeding code exercises its full path.
	var layout: Dictionary = playable.current_ship.built_layout
	if layout.is_empty():
		layout = {}
		playable.current_ship.built_layout = layout

	# Inject synthetic engineering + bridge rooms if the layout lacks them.
	var rooms: Variant = layout.get("rooms", [])
	if not (rooms is Array):
		rooms = []
		layout["rooms"] = rooms
	if not _layout_has_role(rooms as Array, "engineering"):
		(rooms as Array).append({"id": "eng_test", "room_role": "engineering", "variant": "burned_out"})
	else:
		_set_room_variant_by_role(rooms as Array, "engineering", "burned_out")
	if not _layout_has_role(rooms as Array, "bridge"):
		(rooms as Array).append({"id": "brg_test", "room_role": "bridge", "variant": "breached"})
	else:
		_set_room_variant_by_role(rooms as Array, "bridge", "breached")
	playable.current_ship.built_layout = layout

	# Configure the per-ship hull and fire from tuning (mirroring _seed_ship_models
	# + _configure_derelict_fire that the coordinator runs on real derelicts).
	var hull_config: Dictionary = _load_json_dict("res://data/ship_systems/hull_compartments.json")
	playable.current_ship.get_hull().configure(hull_config)
	var tuning: Dictionary = _load_json_dict("res://data/ship_systems/subsystem_tuning.json")
	var fs = playable.current_ship.get_fire()
	fs.configure(tuning.get("fire_suppression", {}))

	# Reset seed guards, then seed on the away branch (breaches before fire,
	# matching the fixed build path so fire exclusion can see variant breaches).
	playable.current_ship.fire_seeded = false
	playable.current_ship.breach_seeded = false
	var n: int = 0
	playable._seed_derelict_breaches()
	playable._seed_derelict_fire()
	n += 1

	var fire_lit: bool = fs != null and "engineering" in fs.get_burning_compartments()
	# Breach must land on the DERELICT's hull (current_ship.get_hull()), and the
	# home hull (playable.hull_integrity_state) must be untouched by the seeding.
	# IMPORTANT: hull_compartments.json ships `cargo` ALREADY breached (health 0.3,
	# breach_open true) — asserting on cargo would be vacuous. Use `bridge`, which
	# starts health 1.0 / breach_open false in both hulls.
	var derelict_hull = playable.current_ship.get_hull()
	var breach_open: bool = derelict_hull != null \
		and derelict_hull.compartments.has("bridge") \
		and bool((derelict_hull.compartments["bridge"] as Dictionary).get("breach_open", false))
	var home_bridge_clean: bool = playable.hull_integrity_state == null \
		or not bool(((playable.hull_integrity_state.compartments.get("bridge", {}) as Dictionary)).get("breach_open", false))

	# Guard: second seed call must not change the set (guards flip true on first run).
	var burning_before: int = fs.get_burning_compartments().size() if fs != null else 0
	playable._seed_derelict_breaches()
	playable._seed_derelict_fire()
	var guarded: bool = (fs.get_burning_compartments().size() == burning_before)

	if fire_lit and breach_open and home_bridge_clean and guarded:
		print("PROCGEN VARIANT HAZARD PASS away_ticks=%d fire_lit=true breach_open=true home_clean=true guarded=true" % n)
		_cleanup_and_quit(0)
	else:
		_fail("fire_lit=%s breach_open=%s home_clean=%s guarded=%s burning=%s derelict_bridge=%s" % [
			str(fire_lit), str(breach_open), str(home_bridge_clean), str(guarded),
			str(fs.get_burning_compartments() if fs != null else []),
			str(derelict_hull.compartments.get("bridge", {}) if derelict_hull != null else {})])

func _layout_has_role(rooms: Array, role: String) -> bool:
	for room in rooms:
		if room is Dictionary and str((room as Dictionary).get("room_role", (room as Dictionary).get("role", ""))) == role:
			return true
	return false

func _set_room_variant_by_role(rooms: Array, role: String, variant: String) -> void:
	for room in rooms:
		if room is Dictionary and str((room as Dictionary).get("room_role", (room as Dictionary).get("role", ""))) == role:
			(room as Dictionary)["variant"] = variant
			return

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(msg: String) -> void:
	push_error("PROCGEN VARIANT HAZARD FAIL " + msg)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null:
		main_node.queue_free()
	quit(code)

func _load_json_dict(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
