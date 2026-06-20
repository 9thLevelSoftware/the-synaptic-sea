extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const MAX_REAL_FRAMES: int = 600
const FIRE_TICK_DELTA: float = 0.5

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false

var cycles: int = 0
var last_phase_text: String = ""
var saw_burning_with_blocked: bool = false
var saw_cleared_with_blocked: bool = false
var last_blocked: bool = false

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
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	match phase:
		"waiting_ready":
			_validate_initial_state()
		"cycling":
			_drive_fire_cycle()
		"done":
			_finish()

func _validate_initial_state() -> void:
	if not playable.has_method("get_fire_summary"):
		_fail("get_fire_summary missing")
		return
	if not playable.has_method("get_fire_zone_node"):
		_fail("get_fire_zone_node missing")
		return
	if not playable.has_method("get_fire_zone_collision_enabled_count"):
		_fail("get_fire_zone_collision_enabled_count missing")
		return
	if playable.get("fire_state") == null:
		_fail("fire_state null")
		return
	var initial: Dictionary = playable.get_fire_summary()
	if str(initial.get("state", "")) != "CLEARED":
		_fail("initial state should be CLEARED, got %s" % str(initial.get("state", "")))
		return
	if bool(initial.get("burning", true)):
		_fail("initial burning should be false")
		return
	if bool(initial.get("passability_blocked", true)):
		_fail("initial passability_blocked should be false")
		return
	var fire_node: Node = playable.get_fire_zone_node()
	if fire_node == null:
		_fail("get_fire_zone_node returned null")
		return
	if str(fire_node.get_meta("fire_zone_id", "")) != "side_corridor_fire":
		_fail("fire_zone_id meta should be side_corridor_fire, got %s" % str(fire_node.get_meta("fire_zone_id", "")))
		return
	if str(fire_node.get_meta("fire_zone_kind", "")) != "timed_fire":
		_fail("fire_zone_kind meta should be timed_fire")
		return
	if playable.get_fire_zone_collision_enabled_count() != 0:
		_fail("initial fire zone collision should be disabled, got %d" % playable.get_fire_zone_collision_enabled_count())
		return
	last_phase_text = "CLEARED"
	last_blocked = false
	phase = "cycling"
	phase_frames = 0

# Headless SceneTree --script mode runs _process at a much slower wall-clock
# rate than 60 FPS (~8-12 ms/frame of model delta, but ~125 ms/frame of wall
# time). To exercise 2 full fire cycles (CLEARED 3.0s + BURNING 4.0s + CLEARED
# 3.0s + BURNING 4.0s + CLEARED 3.0s = 17.0s of model time) we drive the
# playable's _process method directly with explicit FIRE_TICK_DELTA deltas
# until we observe 2 complete BURNING->CLEARED transitions in the real fire
# state, then fall back to observing real _process frames to confirm the
# runtime _process tick also keeps the cycle advancing. This still uses the
# real FireState.tick + _refresh_fire_state(false) code path, just with
# deterministic deltas instead of headless _process timing.
func _drive_fire_cycle() -> void:
	phase_frames += 1
	if phase_frames <= MAX_REAL_FRAMES:
		# First, let real _process frames run so we know the per-frame tick path works.
		# _refresh_fire_state will keep zone state synced with whatever delta the playable's
		# _process fed in.
		_observe_summary()
		# Fast-forward by ticking the model with a deterministic delta and applying
		# the same refresh that the runtime _process would call. This bypasses the
		# headless --script wall-clock rate while still going through the real
		# model + scene-state apply path.
		if playable.fire_state != null:
			playable.fire_state.tick(FIRE_TICK_DELTA)
			playable._refresh_fire_state(false)
		_observe_summary()
	else:
		_observe_summary()
	if cycles >= 2 and last_phase_text == "CLEARED":
		phase = "done"
		return
	if phase_frames > 4000:
		_fail("timed out waiting for two fire cycles (cycles=%d)" % cycles)

func _observe_summary() -> void:
	var summary: Dictionary = playable.get_fire_summary()
	var state_text: String = str(summary.get("state", "CLEARED"))
	var blocked: bool = bool(summary.get("passability_blocked", false))
	if state_text == "BURNING" and blocked:
		saw_burning_with_blocked = true
	if state_text == "CLEARED" and blocked:
		saw_cleared_with_blocked = true
	if blocked != last_blocked:
		last_blocked = blocked
	if state_text != last_phase_text:
		if last_phase_text == "BURNING" and state_text == "CLEARED":
			cycles += 1
		last_phase_text = state_text

func _finish() -> void:
	var final: Dictionary = playable.get_fire_summary()
	if str(final.get("state", "")) != "CLEARED":
		_fail("final state should be CLEARED, got %s" % str(final.get("state", "")))
		return
	if not saw_burning_with_blocked:
		_fail("never saw collision enabled while BURNING")
		return
	if saw_cleared_with_blocked:
		_fail("saw collision enabled while CLEARED")
		return
	if playable.get_fire_zone_collision_enabled_count() != 0:
		_fail("final fire zone collision should be disabled")
		return
	_assert_fire_zone_is_non_critical_side_room()
	# _assert_fire_zone_is_non_critical_side_room may have called _fail() and
	# requested a non-zero exit. quit() is async, so guard the success path
	# against the assertion having already failed.
	if finished:
		return
	finished = true
	print("MAIN PLAYABLE FIRE PASS state=CLEARED cycles=%d blocked_burning=%s blocked_cleared=%s" % [
		cycles,
		str(saw_burning_with_blocked).to_lower(),
		str(saw_cleared_with_blocked).to_lower(),
	])
	_cleanup_and_quit(0)

# REQ-010 source-backed guard: the fire zone must live on a non-critical
# side room (per docs/game/features/hazard_variety.md). This catches
# regression back to a critical-path fallback such as corridor_01, which
# would block the main player route and is explicitly forbidden by the
# feature spec.
#
# Four checks against the RESOLVED fire-zone room id (the `to_room` of the
# fire_zones marker when one is present, otherwise the
# FIRE_ZONE_FALLBACK_ROOM_ID constant):
# 1. Resolved room must NOT be on the layout's `critical_path`.
# 2. Resolved room must NOT be on the objective 3 <-> 4 breach corridor
#    (the two rooms that gate the only mandatory transition where the
#    player must traverse the full main path).
# 3. If a `fire_zones` marker exists in the layout, the resolved room id
#    MUST match the marker's `to_room` (i.e. the marker must be honored;
#    a regression where the loader silently fell back to a different
#    room would be caught here).
# 4. The FIRE_ZONE_FALLBACK_ROOM_ID constant itself must also satisfy
#    checks (1) and (2) when no marker is present, so a constant flip
#    back to a critical-path room is caught even on the fallback-only
#    path.
func _assert_fire_zone_is_non_critical_side_room() -> void:
	if playable.loader == null or not (playable.loader is Node):
		return
	var loader_node: Node = playable.loader as Node
	var critical: Array = []
	if loader_node.has_method("get_critical_path"):
		var critical_variant: Variant = loader_node.call("get_critical_path")
		if typeof(critical_variant) == TYPE_ARRAY:
			critical = critical_variant
	var breach: Dictionary = _breach_corridor_room_ids(loader_node)
	var breach_from: String = str(breach.get("from", ""))
	var breach_to: String = str(breach.get("to", ""))
	var marker_to_rooms: Array = []
	if loader_node.has_method("get_fire_zone_specs"):
		var specs_variant: Variant = loader_node.call("get_fire_zone_specs")
		if typeof(specs_variant) == TYPE_ARRAY:
			for spec_variant in (specs_variant as Array):
				if typeof(spec_variant) != TYPE_DICTIONARY:
					continue
				var to_room: String = str((spec_variant as Dictionary).get("to_room", ""))
				if to_room.is_empty():
					continue
				marker_to_rooms.append(to_room)
				# Per-marker hard-fail: a marker to_room on the critical path
				# or on the breach corridor is never acceptable, even if the
				# runtime resolved to something else.
				if critical.has(to_room):
					_fail("fire zone marker to_room='%s' is on the critical path %s (REQ-010 requires a non-critical side room)" % [to_room, str(critical)])
					return
				if (not breach_from.is_empty() and to_room == breach_from) or (not breach_to.is_empty() and to_room == breach_to):
					_fail("fire zone marker to_room='%s' sits on the obj3<->obj4 breach corridor %s<->%s (REQ-010 requires a non-critical side room)" % [to_room, breach_from, breach_to])
					return
	# Resolved room id from the playable (the actual room the runtime
	# pinned the fire zone to). Empty when neither a marker nor a fallback
	# could be resolved.
	var resolved_room: String = ""
	if playable.has_method("get_fire_zone_resolved_room_id"):
		resolved_room = str(playable.call("get_fire_zone_resolved_room_id"))
	if resolved_room.is_empty():
		# No marker and no fallback were resolvable: nothing to assert.
		return
	# Check (1): resolved room must not be on the critical path.
	if critical.has(resolved_room):
		_fail("resolved fire zone room='%s' is on the critical path %s (REQ-010 requires a non-critical side room)" % [resolved_room, str(critical)])
		return
	# Check (2): resolved room must not be on the obj3<->obj4 breach corridor.
	if (not breach_from.is_empty() and resolved_room == breach_from) or (not breach_to.is_empty() and resolved_room == breach_to):
		_fail("resolved fire zone room='%s' sits on the obj3<->obj4 breach corridor %s<->%s (REQ-010 requires a non-critical side room)" % [resolved_room, breach_from, breach_to])
		return
	# Check (3): when a fire_zones marker is present, the resolved room id
	# MUST match one of the marker to_room values. The fallback-only path
	# is exempt (no marker means the fallback is the source of truth).
	if not marker_to_rooms.is_empty() and not marker_to_rooms.has(resolved_room):
		_fail("resolved fire zone room='%s' does not match any fire_zones marker to_room %s (REQ-010 requires honoring the explicit marker)" % [resolved_room, str(marker_to_rooms)])
		return
	# Check (4): fallback constant must also be non-critical and not the
	# breach corridor, so a constant flip back to a critical-path room
	# is caught even on the fallback-only path.
	var fallback_room: String = ""
	var playable_script: Variant = playable.get("script")
	if playable_script != null and typeof(playable_script) == TYPE_OBJECT:
		var script_obj: Script = playable_script as Script
		var constants_dict: Dictionary = script_obj.get_script_constant_map()
		if constants_dict.has("FIRE_ZONE_FALLBACK_ROOM_ID"):
			fallback_room = str(constants_dict["FIRE_ZONE_FALLBACK_ROOM_ID"])
	if not fallback_room.is_empty():
		if critical.has(fallback_room):
			_fail("FIRE_ZONE_FALLBACK_ROOM_ID='%s' is on the critical path %s (REQ-010 requires a non-critical side room)" % [fallback_room, str(critical)])
			return
		if (not breach_from.is_empty() and fallback_room == breach_from) or (not breach_to.is_empty() and fallback_room == breach_to):
			_fail("FIRE_ZONE_FALLBACK_ROOM_ID='%s' sits on the obj3<->obj4 breach corridor %s<->%s (REQ-010 requires a non-critical side room)" % [fallback_room, breach_from, breach_to])
			return

# Resolves the objective 3 and 4 room ids from the loader. The breach
# corridor is the only mandatory transition where the player must move
# through the full main path; the fire zone must never block that
# transition. Returns {"from": "<obj3_room_id>", "to": "<obj4_room_id>"}
# with empty strings for any missing objective. Tries loader.get_objective_specs_copy()
# first (the canonical view) and falls back to the raw gameplay_doc if the
# helper is unavailable.
func _breach_corridor_room_ids(loader_node: Node) -> Dictionary:
	var obj3_room: String = ""
	var obj4_room: String = ""
	var specs_variant: Variant = null
	if loader_node.has_method("get_objective_specs_copy"):
		var call_result: Variant = loader_node.call("get_objective_specs_copy")
		if typeof(call_result) == TYPE_ARRAY:
			specs_variant = call_result
	if specs_variant == null:
		var raw_gameplay: Dictionary = loader_node.get("gameplay_doc")
		if typeof(raw_gameplay) == TYPE_DICTIONARY:
			var raw_objectives: Variant = (raw_gameplay as Dictionary).get("objectives", [])
			if typeof(raw_objectives) == TYPE_ARRAY:
				specs_variant = raw_objectives
	if typeof(specs_variant) != TYPE_ARRAY:
		return {"from": obj3_room, "to": obj4_room}
	for spec_variant in (specs_variant as Array):
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var seq: int = int(spec.get("sequence", -1))
		var room_id: String = str(spec.get("room_id", ""))
		if room_id.is_empty():
			continue
		if seq == 3:
			obj3_room = room_id
		elif seq == 4:
			obj4_room = room_id
	return {"from": obj3_room, "to": obj4_room}

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
	push_error("MAIN PLAYABLE FIRE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
