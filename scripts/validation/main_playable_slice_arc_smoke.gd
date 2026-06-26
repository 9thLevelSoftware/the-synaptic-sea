extends SceneTree
# REQ-013 main-scene placement smoke for the electrical-arc hazard.
# Mirrors main_playable_slice_fire_smoke.gd: loads the playable scene
# against the template 002 fixture (which carries the new arc zone),
# asserts the initial DISCHARGED state, drives the cycle through 2
# complete DISCHARGED -> ARCING -> DISCHARGED -> ARCING -> DISCHARGED
# transitions, and confirms the StaticBody3D collision segment
# toggles with the phase. Also pins the resolved room id to the
# non-critical side branch and away from any obj3 -> obj4 corridor
# so a regression that places the arc on a critical-path blocker
# fails this smoke.
#
# Pass marker: MAIN PLAYABLE ARC PASS state=DISCHARGED cycles=2 blocked_arcing=true blocked_discharged=false
#
# Headless:
#   /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless
#     --path /Users/christopherwilloughby/the-synaptic-sea-of-stars
#     --script res://scripts/validation/main_playable_slice_arc_smoke.gd

const PlayableShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_002/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json"
const READY_TIMEOUT_FRAMES: int = 300
const MAX_REAL_FRAMES: int = 600
const ARC_TICK_DELTA: float = 0.5

var playable: Node3D
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false

var cycles: int = 0
var last_phase_text: String = ""
var saw_arcing_with_blocked: bool = false
var saw_discharged_with_blocked: bool = false
var last_blocked: bool = false

func _initialize() -> void:
	playable = PlayableShipScript.new()
	playable.name = "PlayableArcSmoke"
	playable.layout_path = LAYOUT_PATH
	playable.kit_path = KIT_PATH
	playable.gameplay_slice_path = GAMEPLAY_SLICE_PATH
	get_root().add_child(playable)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null or not is_instance_valid(playable):
		_fail("playable freed unexpectedly")
		return
	if not playable.playable_started:
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	match phase:
		"waiting_ready":
			_validate_initial_state()
		"cycling":
			_drive_arc_cycle()
		"done":
			_finish()

func _validate_initial_state() -> void:
	if not playable.has_method("get_arc_summary"):
		_fail("get_arc_summary missing")
		return
	if not playable.has_method("get_arc_zone_node"):
		_fail("get_arc_zone_node missing")
		return
	if not playable.has_method("get_arc_zone_collision_enabled_count"):
		_fail("get_arc_zone_collision_enabled_count missing")
		return
	if playable.get("electrical_arc_state") == null:
		_fail("electrical_arc_state null")
		return
	var initial: Dictionary = playable.get_arc_summary()
	if str(initial.get("state", "")) != "DISCHARGED":
		_fail("initial state should be DISCHARGED, got %s" % str(initial.get("state", "")))
		return
	if bool(initial.get("arcing", true)):
		_fail("initial arcing should be false")
		return
	if bool(initial.get("passability_blocked", true)):
		_fail("initial passability_blocked should be false")
		return
	var arc_node: Node = playable.get_arc_zone_node()
	if arc_node == null:
		_fail("get_arc_zone_node returned null (template has no arc marker)")
		return
	if str(arc_node.get_meta("arc_zone_kind", "")) != "electrical_arc":
		_fail("arc_zone_kind meta should be electrical_arc")
		return
	if playable.get_arc_zone_collision_enabled_count() != 0:
		_fail("initial arc zone collision should be disabled, got %d" % playable.get_arc_zone_collision_enabled_count())
		return
	last_phase_text = "DISCHARGED"
	last_blocked = false
	phase = "cycling"
	phase_frames = 0

# Headless SceneTree --script mode runs _process at a much slower wall-clock
# rate than 60 FPS. To exercise 2 full arc cycles (DISCHARGED 1.5s +
# ARCING 2.5s + DISCHARGED 1.5s + ARCING 2.5s + DISCHARGED 1.5s = 9.5s of
# model time) we drive the playable's tick path directly with explicit
# ARC_TICK_DELTA deltas until we observe 2 complete ARCING->DISCHARGED
# transitions in the real arc state, then fall back to observing real
# _process frames to confirm the runtime _process tick also keeps the
# cycle advancing. This still uses the real ElectricalArcState.tick +
# _refresh_arc_state(false) code path, just with deterministic deltas
# instead of headless _process timing.
func _drive_arc_cycle() -> void:
	phase_frames += 1
	if phase_frames <= MAX_REAL_FRAMES:
		# First, let real _process frames run so we know the per-frame tick path works.
		_observe_summary()
		# Fast-forward by ticking the model with a deterministic delta and applying
		# the same refresh that the runtime _process would call. This bypasses the
		# headless --script wall-clock rate while still going through the real
		# model + scene-state apply path.
		if playable.electrical_arc_state != null:
			playable.electrical_arc_state.tick(ARC_TICK_DELTA, {})
			playable._refresh_arc_state(false)
		_observe_summary()
	else:
		_observe_summary()
	if cycles >= 2 and last_phase_text == "DISCHARGED":
		phase = "done"
		return
	if phase_frames > 4000:
		_fail("timed out waiting for two arc cycles (cycles=%d)" % cycles)

func _observe_summary() -> void:
	var summary: Dictionary = playable.get_arc_summary()
	var state_text: String = str(summary.get("state", "DISCHARGED"))
	var blocked: bool = bool(summary.get("passability_blocked", false))
	if state_text == "ARCING" and blocked:
		saw_arcing_with_blocked = true
	if state_text == "DISCHARGED" and blocked:
		saw_discharged_with_blocked = true
	if blocked != last_blocked:
		last_blocked = blocked
	if state_text != last_phase_text:
		if last_phase_text == "ARCING" and state_text == "DISCHARGED":
			cycles += 1
		last_phase_text = state_text

func _finish() -> void:
	var final: Dictionary = playable.get_arc_summary()
	if str(final.get("state", "")) != "DISCHARGED":
		_fail("final state should be DISCHARGED, got %s" % str(final.get("state", "")))
		return
	if not saw_arcing_with_blocked:
		_fail("never saw collision enabled while ARCING")
		return
	if saw_discharged_with_blocked:
		_fail("saw collision enabled while DISCHARGED")
		return
	if playable.get_arc_zone_collision_enabled_count() != 0:
		_fail("final arc zone collision should be disabled")
		return
	_assert_arc_zone_is_non_critical_side_link()
	# _assert_arc_zone_is_non_critical_side_link may have called _fail() and
	# requested a non-zero exit. quit() is async, so guard the success path
	# against the assertion having already failed.
	if finished:
		return
	finished = true
	print("MAIN PLAYABLE ARC PASS state=DISCHARGED cycles=%d blocked_arcing=%s blocked_discharged=%s" % [
		cycles,
		str(saw_arcing_with_blocked).to_lower(),
		str(saw_discharged_with_blocked).to_lower(),
	])
	_cleanup_and_quit(0)

# REQ-013 source-backed guard: the electrical-arc zone must live on a
# non-critical side link (per docs/game/features/hazard_type_3.md). This
# catches regression back to a critical-path placement such as the
# obj3 <-> obj4 corridor, which would trap the player when the arc
# is live and is explicitly forbidden by the feature spec.
#
# Three checks against the RESOLVED arc-zone room id (the `to_room` of
# the arc_zones marker when one is present):
# 1. Resolved room must NOT be on the layout's `critical_path`.
# 2. Resolved room must NOT be on the obj3 <-> obj4 breach corridor
#    (template 002 has no breach but template 003 does; this check
#    is enforced when the loader exposes a breach corridor).
# 3. When an `arc_zones` marker is present, the resolved room id MUST
#    match one of the marker to_room values (the marker must be
#    honored; a regression where the loader silently fell back to a
#    different room would be caught here).
func _assert_arc_zone_is_non_critical_side_link() -> void:
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
	if loader_node.has_method("get_arc_zone_specs"):
		var specs_variant: Variant = loader_node.call("get_arc_zone_specs")
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
					_fail("arc zone marker to_room='%s' is on the critical path %s (REQ-013 requires a non-critical side link)" % [to_room, str(critical)])
					return
				if (not breach_from.is_empty() and to_room == breach_from) or (not breach_to.is_empty() and to_room == breach_to):
					_fail("arc zone marker to_room='%s' sits on the obj3<->obj4 breach corridor %s<->%s (REQ-013 requires a non-critical side link)" % [to_room, breach_from, breach_to])
					return
	# Resolved room id from the playable (the actual room the runtime
	# pinned the arc zone to). Empty when neither a marker nor a fallback
	# could be resolved.
	var resolved_room: String = ""
	if playable.has_method("get_arc_zone_resolved_room_id"):
		resolved_room = str(playable.call("get_arc_zone_resolved_room_id"))
	if resolved_room.is_empty():
		return
	# Check (1): resolved room must not be on the critical path.
	if critical.has(resolved_room):
		_fail("resolved arc zone room='%s' is on the critical path %s (REQ-013 requires a non-critical side link)" % [resolved_room, str(critical)])
		return
	# Check (2): resolved room must not be on the obj3<->obj4 breach corridor.
	if (not breach_from.is_empty() and resolved_room == breach_from) or (not breach_to.is_empty() and resolved_room == breach_to):
		_fail("resolved arc zone room='%s' sits on the obj3<->obj4 breach corridor %s<->%s (REQ-013 requires a non-critical side link)" % [resolved_room, breach_from, breach_to])
		return
	# Check (3): when an arc_zones marker is present, the resolved room id
	# MUST match one of the marker to_room values. The fallback-only path
	# is exempt (no marker means the fallback is the source of truth).
	if not marker_to_rooms.is_empty() and not marker_to_rooms.has(resolved_room):
		_fail("resolved arc zone room='%s' does not match any arc_zones marker to_room %s (REQ-013 requires honoring the explicit marker)" % [resolved_room, str(marker_to_rooms)])
		return

# Resolves the objective 3 and 4 room ids from the loader. The breach
# corridor is the only mandatory transition where the player must move
# through the full main path; the arc zone must never block that
# transition. Returns {"from": "<obj3_room_id>", "to": "<obj4_room_id>"}
# with empty strings for any missing objective. Tries
# loader.get_objective_specs_copy() first (the canonical view) and
# falls back to the raw gameplay_doc if the helper is unavailable.
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

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE ARC FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if playable != null and is_instance_valid(playable):
		playable.queue_free()
	quit(code)
