extends SceneTree

# A11Y-P1-002 focused validation smoke (alternate-input event path).
#
# Companion to main_playable_slice_alternate_input_smoke.gd. Where the
# other smoke proves the InputMap is populated AND that
# `Input.action_press("move_right")` (the synthetic action path) moves
# the player, THIS smoke proves that a REAL keyboard event
# (`InputEventKey` for `KEY_RIGHT`) is routed through the engine's
# normal input pipeline (`Input.parse_input_event()`) and ends up
# advancing the player — the same path a player's actual keypress
# would take. For interact, this smoke proves a real `InputEventKey`
# for KEY_ENTER / KEY_SPACE / KEY_KP_ENTER reaches the player's
# `_unhandled_input` handler and fires `interact_requested` exactly
# once per press.
#
# That makes this smoke the real-world regression for "the alternate
# bindings actually fire on the alternate keycodes" rather than just
# "the bindings are registered". Drop the alternate bindings from
# `ensure_default_input_actions()` and this smoke exits non-zero even
# though the original WASD/E smoke still passes (because the original
# bindings remain).
#
# Steps:
#   1. Static check — assert that `ensure_default_input_actions()`
#      registered BOTH the original keycodes (W/A/S/D/E/F5/F9) AND the
#      alternate keycodes (Up/Down/Left/Right/Enter/Space/KP_Enter) on
#      the right actions. This catches a silent drop of the alternates
#      even if the behavioural probes below somehow still pass.
#   2. Arrow-key move probe — clear scripted movement, then feed a
#      real `KEY_RIGHT` `InputEventKey` through `Input.parse_input_event()`
#      and let physics run. Assert the player's `global_position`
#      advanced on +X (proves `Input.get_action_strength("move_right")`
#      sampled positive while the simulated key was held).
#   3. Enter/Space/KP_Enter interact probes — for each alternate
#      interact keycode, feed a real `InputEventKey` press and assert
#      that `PlayerController.interact_requested` fired exactly once
#      (which is what `PlayerController._unhandled_input` does on
#      `event.is_action_pressed("interact")`). No need to teleport the
#      player or stage an interactable — `_unhandled_input` fires
#      `request_interact()` regardless of whether an interactable is
#      in range; the WASD/E smoke already covers the end-to-end
#      interactable-completion path.
#
# Expected marker:
#   PLAYABLE SLICE ALTERNATE INPUT EVENTS PASS static_bindings=ok moves_alt=1 interact_alt=3 enter=1 space=1 kp_enter=1

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 240
const ARROW_PROBE_FRAMES: int = 30
const SETTLE_FRAMES: int = 10
const MIN_ARROW_MOVE_DISTANCE: float = 0.5
const INTERACT_DEADLINE_FRAMES: int = 60

enum Phase {
	WAITING_READY,
	STATIC_BINDINGS,
	ARROW_MOVE_PROBE,
	ARROW_SETTLE,
	ENTER_INTERACT_PROBE,
	ENTER_SETTLE,
	SPACE_INTERACT_PROBE,
	SPACE_SETTLE,
	KP_ENTER_INTERACT_PROBE,
	KP_ENTER_SETTLE,
	DONE,
}

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase_frames: int = 0
var phase: int = Phase.WAITING_READY
var finished: bool = false

var player_start: Vector3 = Vector3.ZERO
var static_bindings_ok: bool = false
var moves_alt_ok: bool = false
var interact_alt_ok: bool = false

# Per-key event counters. The PlayerController's _unhandled_input emits
# `interact_requested` whenever it sees `event.is_action_pressed("interact")`,
# which is the proof that a real InputEventKey for an alternate-bound
# keycode (KEY_ENTER, KEY_SPACE, KEY_KP_ENTER) reached the same handler
# that fires for the original KEY_E binding.
var _enter_interact_count: int = 0
var _space_interact_count: int = 0
var _kp_enter_interact_count: int = 0
var _signals_connected: bool = false

# `_last_phase_key_label` records which alternate key the active
# interact probe most recently sent. The interact_requested listener
# increments the matching counter. Reset to "" whenever the phase
# changes out of an interact probe.
var _last_phase_key_label: String = ""


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
			_fail("playable not ready")
		return
	if not _signals_connected and playable.player != null:
		_connect_interact_signal_listeners()
	match phase:
		Phase.WAITING_READY:
			_begin_static_bindings_check()
		Phase.STATIC_BINDINGS:
			# Synchronous; one tick is enough.
			phase = Phase.ARROW_MOVE_PROBE
			phase_frames = 0
		Phase.ARROW_MOVE_PROBE:
			_tick_arrow_move_probe()
		Phase.ARROW_SETTLE:
			_tick_settle_then(_begin_enter_interact_probe)
		Phase.ENTER_INTERACT_PROBE:
			_tick_key_signal_probe()
		Phase.ENTER_SETTLE:
			_tick_settle_then(_begin_space_interact_probe)
		Phase.SPACE_INTERACT_PROBE:
			_tick_key_signal_probe()
		Phase.SPACE_SETTLE:
			_tick_settle_then(_begin_kp_enter_interact_probe)
		Phase.KP_ENTER_INTERACT_PROBE:
			_tick_key_signal_probe()
		Phase.KP_ENTER_SETTLE:
			_tick_settle_then(_finish)
		Phase.DONE:
			pass


func _begin_static_bindings_check() -> void:
	# Per-action required keycode sets. Mirrors the registration tables
	# in PlayableGeneratedShip.ensure_default_input_actions(). Each entry
	# is the union of original + alternate keycodes the contract says
	# must be present after `ensure_default_input_actions()` runs.
	# A silent drop of the alternate bindings removes those keycodes
	# from `InputMap` and this loop fails.
	var expectations: Dictionary = {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"interact": [KEY_E, KEY_ENTER, KEY_SPACE, KEY_KP_ENTER],
		"save_run": [KEY_F5],
		"load_run": [KEY_F9],
	}
	var missing: Array = []
	for action_name in expectations:
		if not InputMap.has_action(action_name):
			missing.append("action_missing:%s" % action_name)
			continue
		var registered: Array = playable.get_input_action_keycodes_for_validation(action_name)
		for expected_key in expectations[action_name]:
			if not registered.has(int(expected_key)):
				missing.append(
					"%s_missing_keycode_%d_registered=%s"
					% [action_name, int(expected_key), str(registered)]
				)
	if missing.size() > 0:
		_fail("static bindings incomplete: %s" % str(missing))
		return
	static_bindings_ok = true
	phase = Phase.STATIC_BINDINGS
	phase_frames = 0


func _tick_arrow_move_probe() -> void:
	# First tick: clear scripted movement so the input poll path drives
	# the player. Snapshot start position and send the KEY_RIGHT press.
	# Subsequent ticks: hold for ARROW_PROBE_FRAMES then release.
	if phase_frames == 0:
		# Disable scripted movement so the controller falls back to the
		# real Input.get_action_strength("move_right") poll — the same
		# path the engine takes when a registered InputEventKey fires.
		playable.player.clear_scripted_move_direction()
		player_start = playable.player.global_position
		_send_key(KEY_RIGHT, true)
	phase_frames += 1
	if phase_frames < ARROW_PROBE_FRAMES:
		return
	# Release the key and read the player's final position.
	_send_key(KEY_RIGHT, false)
	# The next ARROW_SETTLE phase gives the controller a few frames to
	# drain the released-key inertia; here we snapshot the final state.
	var player_final: Vector3 = playable.player.global_position
	var moved_distance: float = player_start.distance_to(player_final)
	# `Input.parse_input_event` populated the action state on the next
	# process frame, and the player controller's `_physics_process`
	# sampled `Input.get_action_strength("move_right")` while the key
	# was held. The horizontal distance proves the action fired from
	# the real InputEventKey — not just from `Input.action_press`.
	if moved_distance < MIN_ARROW_MOVE_DISTANCE:
		_fail(
			"arrow-key move_right did not advance player moved=%.3f expected>=%.3f start=%s final=%s"
			% [moved_distance, MIN_ARROW_MOVE_DISTANCE, str(player_start), str(player_final)]
		)
		return
	moves_alt_ok = true
	phase = Phase.ARROW_SETTLE
	phase_frames = 0


func _begin_enter_interact_probe() -> void:
	# Feed a real KEY_ENTER `InputEventKey` through the engine's input
	# pump. The PlayerController._unhandled_input handler watches
	# `event.is_action_pressed("interact")`, which is true for KEY_ENTER
	# because ensure_default_input_actions() bound KEY_ENTER to the
	# interact action. Each press emits `interact_requested` exactly once
	# (the handler does not loop), so the count after the probe proves
	# the alternate-binding keycode reached the same handler that the
	# original KEY_E binding would.
	# No need to teleport the player or stage an interactable for this
	# probe — _unhandled_input fires `request_interact()` regardless of
	# whether an interactable is in range. We are proving the input
	# layer, not the interaction-completion path (which the WASD/E smoke
	# already covers end-to-end).
	_last_phase_key_label = "KEY_ENTER"
	_send_key(KEY_ENTER, true, "parse_and_viewport")
	# Release after one frame so the press isn't held (no double-fire).
	_send_key(KEY_ENTER, false, "parse_and_viewport")
	phase = Phase.ENTER_INTERACT_PROBE
	phase_frames = 0


func _begin_space_interact_probe() -> void:
	_last_phase_key_label = "KEY_SPACE"
	_send_key(KEY_SPACE, true, "viewport")
	_send_key(KEY_SPACE, false, "viewport")
	phase = Phase.SPACE_INTERACT_PROBE
	phase_frames = 0


func _begin_kp_enter_interact_probe() -> void:
	_last_phase_key_label = "KEY_KP_ENTER"
	_send_key(KEY_KP_ENTER, true, "viewport")
	_send_key(KEY_KP_ENTER, false, "viewport")
	phase = Phase.KP_ENTER_INTERACT_PROBE
	phase_frames = 0


func _tick_key_signal_probe() -> void:
	phase_frames += 1
	# Wait a few frames for the input pump to dispatch the event to the
	# player's _unhandled_input. The WASD/E smoke fires _unhandled_input
	# synchronously when the engine receives the event, but the input
	# pump flushes queued events at the START of the next process frame,
	# so the signal may not have fired on the same tick we sent the key.
	if phase_frames < INTERACT_DEADLINE_FRAMES:
		return
	# Determine which alternate key this probe was supposed to prove.
	# After the settle frame, the engine has had ample time to dispatch.
	var expected_count: int = 0
	var key_label: String = ""
	match phase:
		Phase.ENTER_INTERACT_PROBE:
			expected_count = _enter_interact_count
			key_label = "KEY_ENTER"
		Phase.SPACE_INTERACT_PROBE:
			expected_count = _space_interact_count
			key_label = "KEY_SPACE"
		Phase.KP_ENTER_INTERACT_PROBE:
			expected_count = _kp_enter_interact_count
			key_label = "KEY_KP_ENTER"
	if expected_count != 1:
		_fail(
			"%s alternate-binding probe did not emit interact_requested exactly once; count=%d"
			% [key_label, expected_count]
		)
		return
	interact_alt_ok = true
	# Advance to the next settle phase or finish.
	if phase == Phase.ENTER_INTERACT_PROBE:
		phase = Phase.ENTER_SETTLE
	elif phase == Phase.SPACE_INTERACT_PROBE:
		phase = Phase.SPACE_SETTLE
	else:
		phase = Phase.KP_ENTER_SETTLE
	phase_frames = 0


func _tick_settle_then(next: Callable) -> void:
	phase_frames += 1
	if phase_frames >= SETTLE_FRAMES:
		next.call()


func _send_key(keycode: int, pressed: bool, dispatch_mode: String = "parse") -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = pressed
	if dispatch_mode == "viewport":
		# In a headless SceneTree smoke, Input.parse_input_event updates the
		# Input singleton's action state but does not reliably dispatch the
		# event to Viewport callbacks. Interact is handled by
		# PlayerController._unhandled_input, so push through the root
		# viewport exactly once. Do not also call parse_input_event here:
		# some keycodes (for example Space) can otherwise double-dispatch.
		get_root().push_input(ev)
	elif dispatch_mode == "parse_and_viewport":
		Input.parse_input_event(ev)
		get_root().push_input(ev)
	else:
		# The movement probe intentionally validates the polled action-state
		# path (`Input.get_action_strength`), so it needs the Input singleton
		# state updated by parse_input_event while KEY_RIGHT is held.
		Input.parse_input_event(ev)


func _finish() -> void:
	finished = true
	phase = Phase.DONE
	# `interact_alt` is the count of distinct alternate keycodes that
	# successfully triggered `interact_requested` from a real
	# InputEventKey (Enter, Space, KP_Enter). `moves_alt` is the arrow
	# keycode-driven movement probe (Right).
	print(
		"PLAYABLE SLICE ALTERNATE INPUT EVENTS PASS static_bindings=%s moves_alt=%d interact_alt=%d enter=%d space=%d kp_enter=%d"
		% [
			"ok" if static_bindings_ok else "FAIL",
			1 if moves_alt_ok else 0,
			(1 if _enter_interact_count >= 1 else 0)
				+ (1 if _space_interact_count >= 1 else 0)
				+ (1 if _kp_enter_interact_count >= 1 else 0),
			_enter_interact_count,
			_space_interact_count,
			_kp_enter_interact_count,
		]
	)
	_cleanup_and_quit(0)


func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null


func _connect_interact_signal_listeners() -> void:
	# Connect a single listener that increments the per-key counter for
	# whichever alternate key was most recently sent. We deliberately
	# don't try to read the keycode out of the signal payload — the
	# signal only carries the player reference. Phase-scoped tagging
	# via `_last_phase_key_label` is sufficient because the smoke
	# sends at most one key per interact-probe phase, separated by
	# settle frames that give the listener time to drain.
	playable.player.interact_requested.connect(_on_player_interact_requested_for_validation)
	_signals_connected = true


func _on_player_interact_requested_for_validation(player: PlayerController) -> void:
	match _last_phase_key_label:
		"KEY_ENTER":
			_enter_interact_count += 1
		"KEY_SPACE":
			_space_interact_count += 1
		"KEY_KP_ENTER":
			_kp_enter_interact_count += 1


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	phase = Phase.DONE
	push_error("PLAYABLE SLICE ALTERNATE INPUT EVENTS FAIL reason=%s" % reason)
	_cleanup_and_quit(1)


func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
