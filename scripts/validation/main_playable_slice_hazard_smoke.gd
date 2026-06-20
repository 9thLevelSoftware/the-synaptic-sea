extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const DRAIN_WAIT_FRAMES: int = 120
const REGEN_WAIT_FRAMES: int = 200

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false

# Snapshots captured during the runtime tick proof.
var oxygen_before_drain: float = 0.0
var oxygen_after_drain: float = 0.0
var oxygen_after_regen: float = 0.0
var hud_line_before: String = ""
var hud_line_after_drain: String = ""
var hud_line_after_zero: String = ""
var hud_line_after_seal: String = ""

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
		"complete_obj1":
			_complete_objective_1()
		"teleport_into_breach":
			_teleport_into_breach_zone()
		"draining":
			_wait_for_drain()
		"check_drain":
			_check_drain_consequence()
		"regenerating":
			_wait_for_regen()
		"check_regen":
			_check_regen_consequence()
		"drive_to_zero":
			_drive_to_zero_and_check_collision()
		"complete_obj2":
			_complete_objective_2()
		"complete_obj3_4":
			_complete_obj3_and_4()

func _validate_initial_state() -> void:
	if not playable.has_method("get_oxygen_summary"):
		_fail("get_oxygen_summary missing")
		return
	if not playable.has_method("get_breach_zone_node"):
		_fail("get_breach_zone_node missing")
		return
	if not playable.has_method("get_breach_zone_collision_enabled_count"):
		_fail("get_breach_zone_collision_enabled_count missing")
		return
	if playable.get("oxygen_state") == null:
		_fail("oxygen_state null")
		return
	var initial: Dictionary = playable.get_oxygen_summary()
	if float(initial.get("oxygen", -1.0)) <= 0.0:
		_fail("initial oxygen should be >0, got %s" % str(initial.get("oxygen", -1.0)))
		return
	if not bool(initial.get("breach_open", false)):
		_fail("initial breach_open should be true")
		return
	if bool(initial.get("breach_sealed", true)):
		_fail("initial breach_sealed should be false")
		return
	var breach_node: Node = playable.get_breach_zone_node()
	if breach_node == null:
		_fail("get_breach_zone_node returned null")
		return
	if str(breach_node.get_meta("breach_zone_id", "")) != "corridor_to_reactor":
		_fail("breach_zone_id meta should be corridor_to_reactor, got %s" % str(breach_node.get_meta("breach_zone_id", "")))
		return
	if str(breach_node.get_meta("breach_zone_kind", "")) != "oxygen_breach":
		_fail("breach_zone_kind meta should be oxygen_breach")
		return
	# Initial collision must be DISABLED: the breach is open but oxygen is at max,
	# so the corridor is passable and the player can cross (the pressure comes from
	# drain, not from a static wall). Collision only enables when oxygen reaches
	# zero (passability_blocked=true).
	if playable.get_breach_zone_collision_enabled_count() != 0:
		_fail("initial breach zone collision enabled count should be 0 (corridor passable at full oxygen), got %d" % playable.get_breach_zone_collision_enabled_count())
		return
	# HUD must already contain an Oxygen: line routed through ObjectiveTracker.
	var initial_lines: PackedStringArray = playable.get_combined_system_status_lines()
	var initial_oxygen_line: String = ""
	for line in initial_lines:
		var text := String(line)
		if text.begins_with("Oxygen:"):
			initial_oxygen_line = text
			break
	if initial_oxygen_line.is_empty():
		_fail("initial combined status lines missing Oxygen: line")
		return
	# Look for the Breach: OPEN marker separately on a different status line.
	var found_breach_open: bool = false
	for line in initial_lines:
		if String(line).begins_with("Breach:") and String(line).contains("OPEN"):
			found_breach_open = true
			break
	if not found_breach_open:
		_fail("initial status lines should report Breach: OPEN")
		return
	phase = "complete_obj1"

func _complete_objective_1() -> void:
	# Complete objective 1 first so the current objective sequence becomes 2,
	# matching the spec sequence (player would normally walk through the slice).
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective 1 failed")
		return
	phase = "teleport_into_breach"

func _teleport_into_breach_zone() -> void:
	# Capture the pre-drain HUD line so we can prove the runtime tick rewrote it.
	hud_line_before = _first_status_line_starting_with("Oxygen:")
	oxygen_before_drain = float(playable.get_oxygen_summary().get("oxygen", -1.0))
	if not playable.teleport_player_to_breach_zone_for_validation():
		_fail("could not teleport player into breach zone")
		return
	# Confirm the runtime proximity check now reports the player in the zone.
	if not playable.is_player_in_breach_zone_for_validation():
		_fail("runtime proximity check did not see player inside breach zone after teleport")
		return
	phase = "draining"
	phase_frames = 0

func _wait_for_drain() -> void:
	phase_frames += 1
	if phase_frames >= DRAIN_WAIT_FRAMES:
		phase = "check_drain"

func _check_drain_consequence() -> void:
	oxygen_after_drain = float(playable.get_oxygen_summary().get("oxygen", -1.0))
	hud_line_after_drain = _first_status_line_starting_with("Oxygen:")
	if oxygen_after_drain >= oxygen_before_drain:
		_fail(
			"runtime oxygen drain not observed across real _process frames: before=%s after=%s frames=%d"
			% [str(oxygen_before_drain), str(oxygen_after_drain), DRAIN_WAIT_FRAMES]
		)
		return
	if hud_line_after_drain == hud_line_before:
		_fail(
			"HUD oxygen line did not change after drain frames: before=%s after=%s oxygen=%s"
			% [hud_line_before, hud_line_after_drain, str(oxygen_after_drain)]
		)
		return
	if not hud_line_after_drain.begins_with("Oxygen:"):
		_fail("HUD oxygen line after drain does not start with Oxygen: (%s)" % hud_line_after_drain)
		return
	# Drain should be small but clearly positive: at drain_rate=6/sec over ~2s
	# we expect somewhere between 1 and 30 oxygen consumed (no zero without
	# explicit zero-driving step).
	var consumed: float = oxygen_before_drain - oxygen_after_drain
	if consumed < 1.0:
		_fail("drain consumed too little oxygen (%s) over %d frames" % [str(consumed), DRAIN_WAIT_FRAMES])
		return
	if oxygen_after_drain <= 0.0:
		_fail("drain unexpectedly hit zero without explicit zero-driving step, oxygen=%s" % str(oxygen_after_drain))
		return
	phase = "regenerating"
	phase_frames = 0

func _wait_for_regen() -> void:
	# Teleport player OUT of breach zone so regen kicks in for the next phase.
	if phase_frames == 0:
		# First frame of this phase: move player to a safe spot (player start).
		var safe_position: Vector3 = playable.player.global_position
		var interactable_obj1 = playable.get_interactable_by_sequence(1)
		if interactable_obj1 != null and (interactable_obj1 is Node3D):
			safe_position = (interactable_obj1 as Node3D).global_position
		playable.player.teleport_to(safe_position + Vector3(2.0, 0.0, 0.0))
		if playable.is_player_in_breach_zone_for_validation():
			_fail("player should not be in breach zone after regen teleport")
			return
	phase_frames += 1
	if phase_frames >= REGEN_WAIT_FRAMES:
		phase = "check_regen"

func _check_regen_consequence() -> void:
	oxygen_after_regen = float(playable.get_oxygen_summary().get("oxygen", -1.0))
	if oxygen_after_regen <= oxygen_after_drain:
		_fail(
			"oxygen should regenerate when player is out of breach zone, after_drain=%s after_regen=%s"
			% [str(oxygen_after_drain), str(oxygen_after_regen)]
		)
		return
	if oxygen_after_regen > oxygen_before_drain + 0.001:
		_fail(
			"oxygen regenerated above the original level, before=%s after_regen=%s"
			% [str(oxygen_before_drain), str(oxygen_after_regen)]
		)
		return
	phase = "drive_to_zero"

func _drive_to_zero_and_check_collision() -> void:
	# Re-enter the breach zone; the seam drives oxygen to zero via the same
	# OxygenState.tick() that the live runtime uses, then asks the scene tree
	# to apply the resulting passability state.
	if not playable.teleport_player_to_breach_zone_for_validation():
		_fail("could not re-enter breach zone for zero-drive")
		return
	if not playable.force_runtime_oxygen_to_zero_for_validation():
		_fail("force_runtime_oxygen_to_zero_for_validation did not flip passability_blocked")
		return
	var zero_summary: Dictionary = playable.get_oxygen_summary()
	if float(zero_summary.get("oxygen", -1.0)) > 0.001:
		_fail("after zero-drive oxygen should be 0, got %s" % str(zero_summary.get("oxygen", -1.0)))
		return
	if not bool(zero_summary.get("passability_blocked", false)):
		_fail("after zero-drive passability_blocked should be true")
		return
	if playable.get_breach_zone_collision_enabled_count() != 1:
		_fail("after zero-drive breach zone collision should be enabled (count=1), got %d" % playable.get_breach_zone_collision_enabled_count())
		return
	var breach_meta_open: bool = bool(playable.get_breach_zone_node().get_meta("breach_zone_passability_blocked", false))
	if not breach_meta_open:
		_fail("after zero-drive breach_zone_passability_blocked meta should be true")
		return
	# HUD should now show the blocked marker.
	hud_line_after_zero = _first_status_line_starting_with("Oxygen:")
	if not hud_line_after_zero.contains("BLOCKED"):
		_fail("after zero-drive HUD oxygen line should contain BLOCKED, got %s" % hud_line_after_zero)
		return
	phase = "complete_obj2"

func _complete_objective_2() -> void:
	# Now current_objective_sequence should be 2; completing it seals the
	# breach via the same OxygenState.apply_ship_systems_summary path the
	# live runtime uses (route_control_state.apply_ship_systems_summary
	# already ran in the original implementation when ship_systems updated
	# from objective 2). The completion flow also teleports the player to
	# the obj2 interactable position, which is OUT of the breach zone.
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete objective 2 failed")
		return
	var after_two: Dictionary = playable.get_oxygen_summary()
	if bool(after_two.get("breach_open", false)):
		_fail("after objective 2 breach_open should be false")
		return
	if not bool(after_two.get("breach_sealed", false)):
		_fail("after objective 2 breach_sealed should be true")
		return
	if bool(after_two.get("passability_blocked", false)):
		_fail("after objective 2 passability_blocked should be false")
		return
	if playable.get_breach_zone_collision_enabled_count() != 0:
		_fail("after objective 2 breach zone collision should be disabled, got %d" % playable.get_breach_zone_collision_enabled_count())
		return
	# Hazard must not alter route-control / extraction state.
	var route_after_two: Dictionary = playable.get_route_control_summary()
	if bool(route_after_two.get("extraction_unlocked", false)):
		_fail("hazard must not unlock extraction early")
		return
	# HUD status lines should include an oxygen line and a Breach: SEALED marker.
	var lines: PackedStringArray = playable.get_combined_system_status_lines()
	var found_oxygen: bool = false
	var found_seal: bool = false
	for line in lines:
		var text := String(line)
		if text.begins_with("Oxygen:"):
			found_oxygen = true
			hud_line_after_seal = text
		if text.begins_with("Breach:") and text.contains("SEALED"):
			found_seal = true
	if not found_oxygen:
		_fail("combined status lines missing Oxygen: line after seal")
		return
	if not found_seal:
		_fail("combined status lines missing Breach: SEALED line after seal")
		return
	phase = "complete_obj3_4"

func _complete_obj3_and_4() -> void:
	# Objectives 3 and 4 must not affect hazard state.
	if not playable.complete_objective_sequence_for_validation(3):
		_fail("complete objective 3 failed")
		return
	var after_three: Dictionary = playable.get_oxygen_summary()
	if bool(after_three.get("breach_open", false)):
		_fail("objective 3 must not reopen the breach")
		return
	if not bool(after_three.get("breach_sealed", false)):
		_fail("objective 3 must not un-seal the breach")
		return

	if not playable.complete_objective_sequence_for_validation(4):
		_fail("complete objective 4 failed")
		return
	var after_four: Dictionary = playable.get_oxygen_summary()
	if bool(after_four.get("breach_open", false)):
		_fail("objective 4 must not reopen the breach")
		return
	if not bool(after_four.get("breach_sealed", false)):
		_fail("objective 4 must not un-seal the breach")
		return
	if not bool(playable.get_slice_completion_summary().get("run_complete", false)):
		_fail("after objective 4 run_complete=false")
		return

	finished = true
	print("MAIN PLAYABLE HAZARD PASS oxygen=%s breach_open=%s breach_sealed=%s passability_blocked=%s drain_consumed=%s regen_recovered=%s" % [
		str(after_four.get("oxygen", -1.0)),
		str(after_four.get("breach_open", false)).to_lower(),
		str(after_four.get("breach_sealed", false)).to_lower(),
		str(after_four.get("passability_blocked", false)).to_lower(),
		str(oxygen_before_drain - oxygen_after_drain),
		str(oxygen_after_regen - oxygen_after_drain),
	])
	_cleanup_and_quit(0)

func _first_status_line_starting_with(prefix: String) -> String:
	var lines: PackedStringArray = playable.get_combined_system_status_lines()
	for line in lines:
		var text := String(line)
		if text.begins_with(prefix):
			return text
	return ""

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
	push_error("MAIN PLAYABLE HAZARD FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)