extends SceneTree

## Domain 10 (ADR-0045) end-to-end UI-polish smoke. Boots the playable slice,
## drives away_from_start = true (the derelict is the PRIMARY exploration
## context), and manually ticks _process to prove:
##  (a) walking the player into an interactable's Area3D sets the focused
##      tooltip subject + renders the tooltip panel text; tick twice more with
##      no state change and assert the payload_changed emission count only
##      ever incremented ONCE for that focus change (change-gated, not spammed).
##  (b) leaving the interactable's range clears the focus.
##  (c) selecting exactly one inventory item pushes an item tooltip.
##  (c.1) panel-stacking guard: with the inventory panel open, ui_open_map
##      (KEY_M) must NOT open the chart panel underneath it, and the
##      inventory panel must remain open/functional afterward (final-review
##      finding 1). This does not change the PASS marker's byte contract --
##      it gates PASS via the existing _fail() machinery like every other
##      assertion in this file.
##  (d) ui_open_map without a chart -> gate feedback, panel stays closed.
##  (e) granting a web_chart + scanning -> chart panel renders the recorded marker.
## Frees the scene on both the pass and fail exit paths. Writes nothing to disk.
## Marker: UI POLISH PASS away_ticks=6 focus=true clear=true inventory_tooltip=true chart_gated=true chart_recorded=true
## (away_ticks totals the _process calls in _setup_away_and_focus (3) + the
## two no-op change-gating ticks + the one clear-focus tick in
## _validate_focus_and_clear (3) = 6; if the actual run prints a different
## number, that printed value is the byte-exact contract, not this comment.
## The panel-stacking interleave added for finding 1b drives its two-phase
## send/check via inventory_panel state and KEY_M dispatch only -- it does
## NOT call playable._process(), so it does not perturb this count.)
##
## Implementation deviations from the task-8 brief, found while verifying
## against the live coordinator (both required a real fix, not a smoke-only
## workaround):
##  1. Input.parse_input_event()-queued events are NOT dispatched to _input()
##     synchronously -- they flush on the next process_frame. The brief's
##     _validate_chart_gate / _validate_chart_recording sent KEY_M and
##     asserted its effect in the SAME function call, which always observed
##     the pre-dispatch state. Split into a phase 4 (schedule 1 more later than the
##     brief) that sends the key and a phase one process_frame() later that
##     asserts the result, for both the gate-denied and gate-open probes.
##  2. scan() gates detail_level on the current ship's "navigation" system
##     being operational (see scanner_state.gd). A fresh boot's hub ship is
##     unrepaired, so scan() unconditionally returned detail_level=0 before
##     chart recording could be proven. Call the existing
##     force_repair_all_for_validation() seam (the same one
##     travel_integration_smoke.gd uses to satisfy this precondition) before
##     scanning in _send_chart_open_probe.
##  3. Strengthened the change-gating assertion beyond the brief's "focus id
##     unchanged" check: connects to TooltipPresenter.payload_changed and
##     asserts the emission count is UNCHANGED across the two no-op ticks
##     (zero new emissions), with a positive control asserting exactly one
##     emission on the subsequent clearing tick -- proving the gate suppresses
##     emissions, not just that the id happens to read the same.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var phase: int = 0
var _away_ticks: int = 0
var _payload_changed_count: int = 0
var _payload_signal_connected: bool = false

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
	match phase:
		0:
			_drive_to_in_play()
			phase = 1
		1:
			_setup_away_and_focus(playable)
			phase = 2
		2:
			_validate_focus_and_clear(playable)
			phase = 3
		3:
			_validate_inventory_tooltip(playable)
			phase = 4
		4:
			_send_chart_gate_probe(playable)
			phase = 5
		5:
			# Input.parse_input_event()-queued events are only dispatched to
			# _input() on the NEXT process_frame, not synchronously -- this
			# phase boundary is the required one-frame wait before the KEY_M
			# sent in phase 4 has actually reached PlayableGeneratedShip._input.
			_validate_chart_gate(playable)
			phase = 6
		6:
			_grant_chart_and_repair(playable)
			phase = 7
		7:
			# Panel-stacking guard (final-review finding 1). The chart is now
			# possessed, so this is the only point in the run where the
			# regression (ui_open_map ignoring an open inventory panel) is
			# actually observable -- gating this probe before the chart is
			# granted would be vacuous, since the "no chart" branch never
			# opens chart_panel regardless of the guard.
			_send_inventory_open_chart_stack_probe(playable)
			phase = 8
		8:
			# Same one-frame dispatch-delay rule as every other probe here: the
			# KEY_M sent in phase 7 is only queued, not yet delivered to
			# _input(), until this next process_frame.
			_validate_inventory_open_chart_stack_probe(playable)
			phase = 9
		9:
			_send_chart_open_probe(playable)
			phase = 10
		10:
			_validate_chart_recording(playable)
			if not finished:
				finished = true
				print("UI POLISH PASS away_ticks=%d focus=true clear=true inventory_tooltip=true chart_gated=true chart_recorded=true" % _away_ticks)
				_cleanup_and_quit(0)

func _drive_to_in_play() -> void:
	# ENTER confirms the boot main_menu's "start" arm, whose handler is
	# menu_state.close_all() -> in-play. Tranche 4 fix (pre-existing smoke
	# bug): this used to ALSO send KEY_ESCAPE, but ESC from in-play is
	# ui_pause and re-OPENED the pause menu — every later probe ran under an
	# open menu modal. Harmless while panel toggles ignored menus; exposed
	# the moment the menu-modal guard landed (the chart-gate probe was
	# correctly rejected). _send_chart_gate_probe now asserts in-play.
	_send_action(KEY_ENTER)

## Drives away_from_start = true (mandatory per CLAUDE.md's away-branch
## convention) and moves the player onto the first derelict interactable so
## candidate_player is set by the real body_entered physics callback, then
## manually ticks _process (the away branch) three times.
func _setup_away_and_focus(playable: PlayableGeneratedShip) -> void:
	playable.away_from_start = true
	var ui = playable.get_menu_coordinator_for_validation()
	if ui != null and ui.tooltip_presenter != null and not _payload_signal_connected:
		ui.tooltip_presenter.payload_changed.connect(_on_payload_changed)
		_payload_signal_connected = true
	if playable.derelict_interactables.is_empty():
		# No derelict interactables built yet in this boot path -- fall back to
		# the always-present home `interactables` set so the focus assertion
		# still has a real Area3D-driven candidate_player to find. Either
		# collection is scanned identically by _refresh_tooltip_focus.
		if playable.interactables.is_empty():
			_fail("no interactables available to focus (neither derelict nor home)")
			return
		var target = playable.interactables[0]
		target.set_validation_player_in_range(playable.player)
	else:
		var target = playable.derelict_interactables[0]
		target.set_validation_player_in_range(playable.player)
	for i in range(3):
		playable._process(0.1)
		_away_ticks += 1

func _on_payload_changed(_payload) -> void:
	_payload_changed_count += 1

func _validate_focus_and_clear(playable: PlayableGeneratedShip) -> void:
	var focused: String = playable.get_focused_tooltip_subject_for_validation()
	if focused.is_empty():
		_fail("tooltip focus empty after moving player into interactable range")
		return
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null:
		_fail("menu coordinator missing")
		return
	if ui.get_tooltip_panel_text().is_empty():
		_fail("tooltip panel text empty after focus")
		return
	# Change-gating proof: snapshot the emission count accumulated while focus
	# was first established, then tick twice more with NO state change. The
	# focused subject id must not change (still the same interactable in
	# range), AND the payload_changed emission count must not increase at all
	# across these two no-op ticks -- proving _refresh_tooltip_focus is
	# genuinely gated on _last_tooltip_focus_subject_id, not just stable by
	# coincidence.
	var count_before_noop_ticks: int = _payload_changed_count
	playable._process(0.1)
	playable._process(0.1)
	_away_ticks += 2
	if playable.get_focused_tooltip_subject_for_validation() != focused:
		_fail("tooltip focus changed across no-op ticks (spam/instability)")
		return
	if _payload_changed_count != count_before_noop_ticks:
		_fail("payload_changed fired %d times across no-op ticks; expected 0 (change-gating broken)" % (_payload_changed_count - count_before_noop_ticks))
		return
	# Clear: drop out of range on every collection's candidate_player.
	for collection in [playable.interactables, playable.derelict_interactables]:
		for it in collection:
			it.candidate_player = null
	var count_before_clear_tick: int = _payload_changed_count
	playable._process(0.1)
	_away_ticks += 1
	if not playable.get_focused_tooltip_subject_for_validation().is_empty():
		_fail("tooltip focus did not clear after leaving interactable range")
		return
	# The clear IS a real state change (subject_id: X -> ""), so exactly ONE
	# emission is expected here -- this is the positive control proving the
	# zero-emission assertion above isn't just a signal that never fires.
	if _payload_changed_count != count_before_clear_tick + 1:
		_fail("payload_changed fired %d times on the clearing tick; expected exactly 1" % (_payload_changed_count - count_before_clear_tick))

func _validate_inventory_tooltip(playable: PlayableGeneratedShip) -> void:
	if playable.inventory_state == null:
		_fail("inventory_state missing")
		return
	playable.inventory_state.add_item("circuit_board", 1)
	playable.inventory_panel.open_self(playable.inventory_state, playable.equipment_state)
	var ids: Array = playable.inventory_panel.get_pane_ids("self")
	var idx: int = ids.find("circuit_board")
	if idx < 0:
		_fail("circuit_board not found in inventory pane after add_item")
		return
	playable.inventory_panel.select_row("self", idx, false, false)
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null:
		_fail("menu coordinator missing")
		return
	if ui.get_tooltip_panel_text().find("Circuit Board") == -1:
		_fail("inventory selection did not push item tooltip")
		return
	playable.inventory_panel.close()

## Sends the gate-probe KEY_M press/release. Input.parse_input_event() only
## queues the events for dispatch on the NEXT process_frame -- the actual
## assertion happens one phase later in _validate_chart_gate, once _input has
## genuinely run.
func _send_chart_gate_probe(playable: PlayableGeneratedShip) -> void:
	if playable.inventory_state.get_quantity("web_chart") > 0:
		_fail("test setup error: web_chart already possessed before gate check")
		return
	# The gate probe must run in-play: with a menu open, the menu-modal guard
	# (Tranche 4) correctly swallows ui_open_map before the chart gate.
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null or not ui.menu_state.is_in_play():
		_fail("not in-play before the chart-gate probe (menu=%s)" % (ui.get_current_menu() if ui != null else "<none>"))
		return
	_send_action(KEY_M)

func _validate_chart_gate(playable: PlayableGeneratedShip) -> void:
	if finished:
		return
	if playable.chart_panel != null and playable.chart_panel.is_open():
		_fail("chart_panel opened without a possessed web_chart")
		return
	if playable.get_last_loot_feedback_line_for_validation() != "No web chart":
		_fail("gate feedback line missing; got '%s'" % playable.get_last_loot_feedback_line_for_validation())

## Grants the web_chart, force-repairs every ship system (scan() gates
## detail_level on the current ship's "navigation" system being operational --
## a fresh boot's hub starts unrepaired, so an ungated scan() would otherwise
## always return detail_level=0; travel_integration_smoke establishes the same
## precondition via the same seam), and scans (which auto-records the chart
## per scan()'s Domain 10 Source B contract). Split from the KEY_M open-probe
## (now sent later, in _send_chart_open_probe) so the panel-stacking guard
## below can be exercised with a chart already possessed -- that guard is
## vacuous before the chart exists, since the no-chart branch never opens
## chart_panel regardless of the guard.
func _grant_chart_and_repair(playable: PlayableGeneratedShip) -> void:
	playable.inventory_state.add_item("web_chart", 1)
	playable.force_repair_all_for_validation()
	var scan_result: Dictionary = playable.scan()
	if int(scan_result.get("detail_level", 0)) <= 0:
		_fail("scan() returned detail_level<=0 -- cannot prove chart recording")
		return
	if int(playable.web_chart_state.get_known_count()) < 1:
		_fail("web_chart_state recorded nothing after scan with chart possessed")
		return

## Final-review finding 1: panel-stacking guard. A web_chart is now possessed
## (granted by _grant_chart_and_repair above), so ui_open_map WOULD open
## chart_panel if pressed with no inventory panel open -- this is the only
## point in the run where the panel-stacking regression (ui_open_map ignoring
## an already-open inventory panel) is actually observable. Opens the
## inventory panel, then sends ui_open_map (KEY_M) while it is open. Only
## sends the key here -- the same Input.parse_input_event() dispatch-delay
## rule as every other probe in this file applies, so the assertion happens
## one phase later in _validate_inventory_open_chart_stack_probe.
func _send_inventory_open_chart_stack_probe(playable: PlayableGeneratedShip) -> void:
	if playable.inventory_state.get_quantity("web_chart") <= 0:
		_fail("test setup error: web_chart not possessed before stacking check")
		return
	playable._open_inventory_self()
	if not playable.inventory_panel.is_open():
		_fail("inventory panel did not open for the panel-stacking probe")
		return
	_send_action(KEY_M)

## Asserts the guarded chart branch (playable_generated_ship.gd _input, finding
## 1's fix) rejected the KEY_M press while the inventory panel was open, even
## though a web_chart is possessed (so the gate-without-chart path above
## cannot be masking a stacking regression here): the chart panel must NOT
## have opened, and the inventory panel must still be open and functional
## (closing it here doubles as the "still functional" proof -- a
## frozen/broken panel would leave is_open() true after close()).
func _validate_inventory_open_chart_stack_probe(playable: PlayableGeneratedShip) -> void:
	if finished:
		return
	if playable.chart_panel != null and playable.chart_panel.is_open():
		_fail("chart_panel opened while inventory panel was open (panel-stacking regression)")
		return
	if not playable.inventory_panel.is_open():
		_fail("inventory panel closed itself after the guarded KEY_M press (should have swallowed input)")
		return
	playable.inventory_panel.close()
	if playable.inventory_panel.is_open():
		_fail("inventory panel did not close on demand after the stacking probe (frozen)")
		return

## Sends the KEY_M open-probe now that the chart is possessed (granted by
## _grant_chart_and_repair) and the inventory panel is closed (by the
## stacking probe above). Same one-frame dispatch-delay rule as every other
## probe applies -- the panel-open assertion happens one phase later in
## _validate_chart_recording.
func _send_chart_open_probe(playable: PlayableGeneratedShip) -> void:
	_send_action(KEY_M)

func _validate_chart_recording(playable: PlayableGeneratedShip) -> void:
	if finished:
		return
	if playable.chart_panel == null or not playable.chart_panel.is_open():
		_fail("chart_panel did not open with a possessed web_chart")
		return
	var rows: Array = playable.chart_panel.get_row_texts()
	if rows.is_empty():
		_fail("chart_panel rendered no rows after a recorded scan")

func _send_action(keycode: int) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _cleanup_and_quit(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("UI POLISH FAIL reason=%s" % reason)
	_cleanup_and_quit(1)
