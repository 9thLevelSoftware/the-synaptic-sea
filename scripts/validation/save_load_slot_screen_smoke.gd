extends SceneTree

## ADR-0043 slot-screen smoke: drives the interactive save_load meta-screen
## end-to-end. Deletes TARGET_SLOT_ID first so the screen must render it as
## one of Task 7's SYNTHESIZED EMPTY placeholder rows, then drives the
## FIRST save onto that empty row entirely through the screen (verb model
## [Save] only, per spec 3.2 -- this is the specific requirement the
## coordinator's review flagged: a screen that only lists already-filled
## rows can never let the player make their first manual save). Only after
## that first save turns the row real does this smoke advance world state,
## Load the slot back (ship-only-not-world semantics per ADR-0031), then
## drive the two-step Delete-arm/confirm flow. Follows the
## meta_screens_interactive_smoke.gd pattern (boots scenes/main.tscn
## directly, not the title wrapper).
##
## Additional review-mandated assertions (Task 7/8 review rounds):
##   1. First-save-through-empty-row: the empty synthetic row must render
##      "-- empty", offer verb set exactly ["Save"], and cycling must be a
##      structural no-op, before this smoke drives the first save.
##   2. Cursor-follows-slot: after Save, _save_load_row_index must point at
##      the saved slot's (now-front) row; after Delete, at the same
##      slot_id's re-synthesized empty row.
##   3. Frozen-row UI gate: a second manual slot with a recorded death must
##      render "DEAD", refuse Load/Delete dispatch (action "none"/ok=false),
##      and never offer a verb.
##   4. Ship-only-not-world: a manual Save/Load round trip through the
##      screen must revert current_objective_sequence but leave
##      visited_ships untouched.
##   5. World-row Load (PR #57 Codex P2): the world row's on-disk file is a
##      WorldSnapshot, not a RunSnapshot, so its Load verb must dispatch as
##      action=="load_world" and be applied via PlayableGeneratedShip.
##      request_load() (not apply_manual_slot()). Seeds a distinguishing
##      current_objective_sequence fixture directly into world.json (mirrors
##      title_screen_flow_smoke.gd's Continue fixture) and asserts it lands
##      after the world row's Load confirms -- proving request_load() was
##      actually invoked rather than the dispatch silently no-op'ing.
##
## Pass marker:
##   SAVE LOAD SLOT SCREEN PASS save=true load=true delete_armed=true delete_confirmed=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const TIMEOUT_FRAMES: int = 600
const TARGET_SLOT_ID: String = "slot_01"
const FROZEN_SLOT_ID: String = "slot_02"

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

## Real-InputEvent delete drive (review fast-follow): -1 means "not started
## yet, _validate() is still running the direct-call setup"; 0/1/2 step
## through a settle frame after the ui_right verb-cycle burst, the ui_accept
## arm, and the ui_accept confirm, so each real InputEventKey has a full
## SceneTree frame to reach PlayableGeneratedShip._input before the next one
## fires (mirrors main_playable_ui_shell_smoke.gd's _drive_to_in_play/
## _validate_runtime phase split -- Input.parse_input_event queues the event
## for the engine's next input flush, it is not delivered synchronously).
var _delete_input_phase: int = -1

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
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	if _delete_input_phase >= 0:
		_tick_delete_input_phase()
		return
	_validate()

func _validate() -> void:
	if playable.menu_coordinator == null or playable.save_load_service == null:
		_fail("menu_coordinator / save_load_service missing")
		return
	var resolver := PermadeathResolverScript.new()
	playable.save_load_service.delete_slot(TARGET_SLOT_ID)
	playable.save_load_service.delete_slot(FROZEN_SLOT_ID)
	resolver.clear_death(TARGET_SLOT_ID)
	resolver.clear_death(FROZEN_SLOT_ID)
	var coord = playable.menu_coordinator

	# Record objective progress BEFORE saving, so the Load assertion can
	# prove it reverts (ship-only semantics).
	var seq_before_save: int = playable.current_objective_sequence

	coord.open_records_menu()
	coord.open_meta_screen("save_load")
	if coord.get_active_meta_screen() != "save_load":
		_fail("save_load screen did not open")
		return

	# --- FIRST SAVE, driven entirely through the screen against an EMPTY
	# synthetic row (step 7.8's placeholder for a manual slot with no
	# on-disk payload yet) -- this is the specific case the coordinator
	# flagged: a slot screen that only lists FILLED rows can never let the
	# player make their first manual save, which would recreate inventory
	# break-point 6 in a subtler form. TARGET_SLOT_ID was just deleted above,
	# so its row here MUST be one of the synthesized empty placeholders, not
	# a real on-disk row -- assert that before proceeding, so this smoke
	# actually exercises the empty-row path and does not silently degrade
	# into re-testing a filled row if some future change pre-populates it. ---
	var rows: Array = coord._save_load_rows()
	var target_index: int = _find_row_index(rows, TARGET_SLOT_ID)
	if target_index < 0:
		_fail("synthesized empty row for '%s' not found -- step 7.8's placeholder synthesis is missing or broken" % TARGET_SLOT_ID)
		return
	var empty_row = rows[target_index]
	if not String(empty_row.display_name).is_empty() or int(empty_row.saved_at_epoch) != 0 or not String(empty_row.schema_version).is_empty():
		_fail("row for '%s' is not empty before the first save -- test setup did not start from a clean empty slot" % TARGET_SLOT_ID)
		return

	# Extra assertion 1: the rendered line for the empty row must read
	# "-- empty" and offer exactly the [Save] verb; cycling in either
	# direction must be a structural no-op (a 1-element verb list always
	# wraps to itself, never landing on Load or Delete).
	coord.meta_screen_move_selection(-9999)
	for _i in range(target_index):
		coord.meta_screen_move_selection(1)
	if coord._save_load_row_index != target_index:
		_fail("cursor did not land on empty row index %d (got %d)" % [target_index, coord._save_load_row_index])
		return
	var rendered_line: String = coord._save_load_row_line(rows[coord._save_load_row_index], coord._save_load_row_index)
	if not rendered_line.contains("-- empty"):
		_fail("empty row did not render '-- empty': %s" % rendered_line)
		return
	var empty_row_verbs: Array = coord._valid_verbs_for_row(empty_row)
	if empty_row_verbs != ["Save"]:
		_fail("empty manual row verb set must be exactly [Save], got %s" % str(empty_row_verbs))
		return
	# A 1-element verb list always wraps to itself: cycling in either
	# direction must never land on anything but "Save" (there is nothing
	# else in the list to land on), so this is the no-op guarantee to
	# check -- not that _save_load_pending_verb stays unset, since
	# _cycle_save_load_verb legitimately arms the sole verb on first cycle.
	coord._cycle_save_load_verb(1)
	if coord._save_load_pending_verb != "Save":
		_fail("cycling verb on an empty row must never land off 'Save', got '%s' after ui_right" % coord._save_load_pending_verb)
		return
	coord._cycle_save_load_verb(-1)
	if coord._save_load_pending_verb != "Save":
		_fail("cycling verb on an empty row must never land off 'Save', got '%s' after ui_left" % coord._save_load_pending_verb)
		return
	coord._cycle_save_load_verb(1)
	if coord._save_load_pending_verb != "Save":
		_fail("cycling verb on an empty row must never land off 'Save', got '%s' after second ui_right" % coord._save_load_pending_verb)
		return
	# Reset to unarmed before driving the real arm/confirm sequence below,
	# so the first meta_screen_confirm() call is the one that arms it (this
	# mirrors _open_meta_screen's reset-on-open + a fresh player who has not
	# touched ui_left/ui_right yet).
	coord._save_load_pending_verb = ""
	coord._refresh_save_load_panel()

	var arm_result_empty: Dictionary = coord.meta_screen_confirm()  # arms the (only) verb
	if str(arm_result_empty.get("action", "")) != "arm":
		_fail("expected the empty row's first confirm to arm a verb: %s" % str(arm_result_empty))
		return
	if coord._save_load_pending_verb != "Save":
		_fail("empty row armed verb should be 'Save', got '%s' -- Load/Delete must never be reachable on a synthetic row" % coord._save_load_pending_verb)
		return
	var confirm_dict: Dictionary = coord.meta_screen_confirm()  # executes it
	if str(confirm_dict.get("action", "")) != "save" or not bool(confirm_dict.get("ok", false)):
		_fail("first save on an empty manual row did not execute as Save: %s" % str(confirm_dict))
		return
	# Production seam: PlayableGeneratedShip._input's menu-dispatch region
	# calls this every frame handle_ui_input returns true, reading the SAME
	# Dictionary shape meta_screen_confirm() returns (get_last_meta_screen_confirm_result()
	# just re-exposes the last one handle_ui_input's ui_accept branch stored).
	# This smoke drives meta_screen_confirm() directly rather than through
	# _input's InputEventAction plumbing, so it must call this dispatcher
	# itself to get the same _manual_slots_written_this_run bookkeeping a
	# real play session gets for free.
	playable._dispatch_save_load_confirm_result(confirm_dict)
	if not playable._manual_slots_written_this_run.has(TARGET_SLOT_ID):
		_fail("manual slot '%s' not recorded in _manual_slots_written_this_run after first Save" % TARGET_SLOT_ID)
		return
	if not playable.save_load_service.has_slot(TARGET_SLOT_ID):
		_fail("slot file for '%s' does not exist on disk after the first save" % TARGET_SLOT_ID)
		return

	# Extra assertion 2 (cursor-follows-slot, Save half): _save_load_row_index
	# must now point at the row whose slot_id == TARGET_SLOT_ID (rows re-sort
	# freshest-first, so a successful Save can move it to the front).
	var post_save_rows: Array = coord._save_load_rows()
	if coord._save_load_row_index < 0 or coord._save_load_row_index >= post_save_rows.size() or String(post_save_rows[coord._save_load_row_index].slot_id) != TARGET_SLOT_ID:
		_fail("cursor did not follow slot '%s' after Save (index=%d)" % [TARGET_SLOT_ID, coord._save_load_row_index])
		return

	# The row must now be a REAL filled row (not the synthetic placeholder)
	# when refresh() is asked again -- this is the core assertion the
	# coordinator required: the slot screen turned an empty synthetic row
	# into a real, listed, filled row through its own Save verb, with no
	# direct SaveLoadService call from this smoke.
	coord._refresh_save_load_panel()
	var rows_after_save: Array = coord._save_load_rows()
	var refilled_index: int = _find_row_index(rows_after_save, TARGET_SLOT_ID)
	if refilled_index < 0:
		_fail("slot '%s' missing from _save_load_rows() after the first save" % TARGET_SLOT_ID)
		return
	var refilled_row = rows_after_save[refilled_index]
	if int(refilled_row.saved_at_epoch) == 0 and String(refilled_row.schema_version).is_empty():
		_fail("row for '%s' still reads as an empty placeholder after the first save" % TARGET_SLOT_ID)
		return
	if not refilled_row.is_manual():
		_fail("post-save row for '%s' is not recognized as a filled manual row" % TARGET_SLOT_ID)
		return
	target_index = refilled_index

	# --- Advance objective state AFTER saving, so Load can prove it
	# reverts the ship's own progress without touching world-level state. ---
	var visited_before: int = playable.visited_ships.size()
	playable.current_objective_sequence = seq_before_save + 5

	# --- Load verb: first confirm arms it (default first verb is Load for a
	# manual row), second confirm executes it. ---
	coord._refresh_save_load_panel()
	coord.meta_screen_move_selection(-9999)
	rows = coord._save_load_rows()
	target_index = _find_row_index(rows, TARGET_SLOT_ID)
	if target_index < 0:
		_fail("slot row disappeared before Load verb drive")
		return
	for _i in range(target_index):
		coord.meta_screen_move_selection(1)
	var arm_result: Dictionary = coord.meta_screen_confirm()  # arms the first verb (Load)
	if str(arm_result.get("action", "")) != "arm":
		_fail("expected Load verb to arm first: %s" % str(arm_result))
		return
	var load_result: Dictionary = coord.meta_screen_confirm()  # executes Load
	if str(load_result.get("action", "")) != "load" or not bool(load_result.get("ok", false)):
		_fail("Load verb did not execute: %s" % str(load_result))
		return
	# Production seam: dispatch through the SAME function
	# PlayableGeneratedShip._input's menu-dispatch region calls every frame
	# handle_ui_input returns true -- it notices action=="load" and ok==true
	# and calls apply_manual_slot() with the coordinator-surfaced snapshot
	# itself (the coordinator owns no gameplay state and cannot apply it).
	# Driving this exact function (rather than calling apply_manual_slot()
	# directly from the smoke) proves the real dispatch path, not just the
	# underlying primitive it happens to call.
	var seq_before_load: int = playable.current_objective_sequence
	playable._dispatch_save_load_confirm_result(load_result)
	if playable.current_objective_sequence == seq_before_load:
		_fail("apply_manual_slot via _dispatch_save_load_confirm_result did not change objective_sequence (still %d)" % seq_before_load)
		return

	# CRITICAL: apply_manual_slot -> _apply_run_snapshot reloads the ship via
	# loader.load_from_paths(), which calls _build_hud_layer() again --
	# _build_hud_layer() unconditionally queue_free()s the PRIOR hud_layer
	# (and its child menu_coordinator) and constructs a brand-new
	# MenuCoordinator, ending on open_main_menu() (REQ-014 "rebuild the
	# HUD/tracker on every ship load, not just the first one"). The local
	# `coord` captured at the top of this function now points at a stale,
	# queue_free()'d Node -- every call below through the stale reference
	# would silently succeed against a detached object instead of the live
	# screen a real player sees. Re-fetch playable.menu_coordinator (the
	# live one) and re-open Records -> Save/Load, exactly like a player
	# would after a Load dumps them back to the main menu.
	coord = playable.menu_coordinator
	if coord == null:
		_fail("menu_coordinator missing after manual-slot Load reload")
		return
	coord.open_records_menu()
	coord.open_meta_screen("save_load")
	if coord.get_active_meta_screen() != "save_load":
		_fail("save_load screen did not re-open after the post-Load reload")
		return

	# Extra assertion 4 (ship-only-not-world, the single most important
	# assertion): objective progress (an observable that was advanced AFTER
	# the save) must revert to the saved point, while visited_ships (a
	# world-level observable untouched by a manual-slot save/load) must be
	# unchanged in size. RunSnapshot/apply_manual_slot never touch
	# visited_ships (ADR-0031) -- confirmed by inspection of
	# playable_generated_ship.gd's _build_run_snapshot/_apply_run_snapshot,
	# neither of which reference visited_ships.
	if playable.current_objective_sequence != seq_before_save:
		_fail("objective_sequence did not revert after manual-slot Load (got %d expected %d)" % [playable.current_objective_sequence, seq_before_save])
		return
	if playable.visited_ships.size() != visited_before:
		_fail("visited_ships size changed after a manual-slot Load -- ship-only semantics violated")
		return

	# Extra assertion 2 (cursor-follows-slot, Load half is implicit -- Load
	# does not reorder rows since saved_at is unchanged; already covered by
	# the Save-half check above and the Delete-half check below).

	# --- World-row Load (PR #57 Codex P2): the world row's on-disk file is a
	# WorldSnapshot, not a RunSnapshot -- select_slot_for_load()/load_from_slot()
	# would either no-op or misparse it, so the coordinator's Load arm must
	# special-case is_world() into action=="load_world" and the playable
	# dispatch must route it through request_load() (the same proven
	# world-apply path F9/title Continue use) instead of apply_manual_slot().
	# Write a real world save first, then stamp a distinguishing fixture value
	# into it directly on disk (mirrors title_screen_flow_smoke's
	# _seed_continue_fixture) so this assertion proves request_load() actually
	# applied the file rather than the dispatch merely no-op'ing into whatever
	# live state already matched. ---
	if not playable.request_save():
		_fail("request_save() failed while seeding the world-row Load fixture")
		return
	const WORLD_FIXTURE_SEQUENCE: int = 77
	var world_service = playable.save_load_service
	var ws = world_service.load_world()
	if ws == null:
		_fail("load_world() returned null right after request_save() while seeding the world-row fixture")
		return
	var fixture_home_ship: Dictionary = ws.home_ship.duplicate(true)
	if fixture_home_ship.is_empty():
		_fail("world save's home_ship slice was empty while seeding the world-row fixture")
		return
	fixture_home_ship["current_objective_sequence"] = WORLD_FIXTURE_SEQUENCE
	ws.home_ship = fixture_home_ship
	if not world_service.save_world(ws):
		_fail("save_world() failed while seeding the world-row fixture")
		return
	# Advance live state past the fixture value so request_load() applying it
	# back down is the only way the assertion below can pass.
	playable.current_objective_sequence = WORLD_FIXTURE_SEQUENCE + 5

	coord.open_records_menu()
	coord.open_meta_screen("save_load")
	if coord.get_active_meta_screen() != "save_load":
		_fail("save_load screen did not open before world-row Load drive")
		return
	coord._refresh_save_load_panel()
	coord.meta_screen_move_selection(-9999)
	rows = coord._save_load_rows()
	var world_index: int = _find_row_index(rows, "world")
	if world_index < 0:
		_fail("world row not found in save/load rows after seeding the world fixture")
		return
	for _i in range(world_index):
		coord.meta_screen_move_selection(1)
	if coord._save_load_row_index != world_index:
		_fail("cursor did not land on world row index %d (got %d)" % [world_index, coord._save_load_row_index])
		return
	var world_verbs: Array = coord._valid_verbs_for_row(rows[world_index])
	if world_verbs != ["Load"]:
		_fail("world row verb set must be exactly [Load], got %s" % str(world_verbs))
		return
	var world_arm_result: Dictionary = coord.meta_screen_confirm()  # arms Load
	if str(world_arm_result.get("action", "")) != "arm":
		_fail("expected world row's first confirm to arm Load: %s" % str(world_arm_result))
		return
	var world_confirm_result: Dictionary = coord.meta_screen_confirm()  # executes Load
	if str(world_confirm_result.get("action", "")) != "load_world" or not bool(world_confirm_result.get("ok", false)):
		_fail("world row Load did not execute as action=='load_world': %s" % str(world_confirm_result))
		return
	# Production seam: the same dispatcher _input calls every frame
	# handle_ui_input returns true. It must notice action=="load_world" and
	# call playable.request_load() itself (menu_coordinator owns no gameplay
	# state and cannot decode/apply a WorldSnapshot).
	playable._dispatch_save_load_confirm_result(world_confirm_result)
	if playable.current_objective_sequence != WORLD_FIXTURE_SEQUENCE:
		_fail("world-row Load did not apply request_load(): current_objective_sequence=%d expected=%d" % [
			playable.current_objective_sequence,
			WORLD_FIXTURE_SEQUENCE,
		])
		return

	# CRITICAL: same reload hazard as the manual-slot Load above -- request_load()
	# -> _apply_world_snapshot reloads the ship and rebuilds the HUD/MenuCoordinator.
	# Re-fetch the live instance and re-open Records -> Save/Load before continuing.
	coord = playable.menu_coordinator
	if coord == null:
		_fail("menu_coordinator missing after world-row Load reload")
		return
	coord.open_records_menu()
	coord.open_meta_screen("save_load")
	if coord.get_active_meta_screen() != "save_load":
		_fail("save_load screen did not re-open after the world-row post-Load reload")
		return

	# --- Extra assertion 3: frozen-row UI gate. Record a death for a SECOND
	# manual slot via direct service + resolver calls (never actually killing
	# the player -- record_death only writes the <slot_id>.death.json
	# side-file PermadeathResolver reads, exactly like _save_load_rows()'s
	# runtime frozen-overlay expects). Refresh the screen and assert the row
	# renders "DEAD", offers no verb, and neither Load nor Delete can be
	# dispatched on it (confirm returns action=="none"/ok==false). ---
	if not playable.save_load_service.save_to_slot(FROZEN_SLOT_ID, playable._build_run_snapshot(), "manual", false, "Frozen Slot"):
		_fail("could not write frozen-row fixture slot '%s'" % FROZEN_SLOT_ID)
		return
	resolver.record_death(FROZEN_SLOT_ID, "test_fixture", "Test epitaph", 12.0, playable.current_objective_sequence)
	coord._refresh_save_load_panel()
	rows = coord._save_load_rows()
	var frozen_index: int = _find_row_index(rows, FROZEN_SLOT_ID)
	if frozen_index < 0:
		_fail("frozen fixture row '%s' not found after death record" % FROZEN_SLOT_ID)
		return
	var frozen_row = rows[frozen_index]
	if not bool(frozen_row.frozen):
		_fail("row '%s' not marked frozen after PermadeathResolver.record_death" % FROZEN_SLOT_ID)
		return
	var frozen_line: String = coord._save_load_row_line(frozen_row, frozen_index)
	if not frozen_line.contains("DEAD"):
		_fail("frozen row did not render 'DEAD': %s" % frozen_line)
		return
	coord.meta_screen_move_selection(-9999)
	for _i in range(frozen_index):
		coord.meta_screen_move_selection(1)
	if coord._save_load_row_index != frozen_index:
		_fail("cursor did not land on frozen row index %d (got %d)" % [frozen_index, coord._save_load_row_index])
		return
	var frozen_confirm_result: Dictionary = coord.meta_screen_confirm()
	if str(frozen_confirm_result.get("action", "")) != "none" or bool(frozen_confirm_result.get("ok", false)):
		_fail("frozen row must not dispatch any verb on confirm: %s" % str(frozen_confirm_result))
		return
	# Load/Delete must not even be reachable via cycling on a frozen row.
	coord._cycle_save_load_verb(1)
	if not coord._save_load_pending_verb.is_empty():
		_fail("cycling a verb on a frozen row must be a no-op, got pending_verb='%s'" % coord._save_load_pending_verb)
		return
	# Clean up the frozen fixture's death record now (before it interferes
	# with the TARGET_SLOT_ID Delete flow below, since _save_load_rows()
	# re-resolves frozen state fresh on every call from ALL manual slot ids).
	playable.save_load_service.delete_slot(FROZEN_SLOT_ID)
	resolver.clear_death(FROZEN_SLOT_ID)

	# --- Delete: two-step arm/confirm, driven through REAL InputEvents this
	# time (not direct coordinator calls) -- this is the smoke's only
	# player-facing surface, so it must exercise the actual input-action
	# layer: handle_ui_input's is_action_pressed branching for ui_right/
	# ui_accept (menu_coordinator.gd:189-205) dispatched through
	# PlayableGeneratedShip._input (playable_generated_ship.gd:7695-7701),
	# exactly like a player pressing Right, Right, Right, Enter, Enter would.
	# Row navigation to target_index stays a direct coordinator call (only
	# the verb-cycle + confirm steps are the reviewer-flagged gap); moving
	# the cursor here also resets _save_load_pending_verb to "" (unarmed),
	# so the first real ui_right below lands on the FIRST verb ("Load").
	coord._refresh_save_load_panel()
	coord.meta_screen_move_selection(-9999)
	rows = coord._save_load_rows()
	target_index = _find_row_index(rows, TARGET_SLOT_ID)
	if target_index < 0:
		_fail("slot row disappeared before Delete verb drive")
		return
	for _i in range(target_index):
		coord.meta_screen_move_selection(1)
	_delete_input_phase = 0
	# Fire the three ui_right presses (unset -> Load -> Save -> Delete) now;
	# _tick_delete_input_phase() picks up on the NEXT SceneTree frame once
	# the engine's input flush has delivered them to PlayableGeneratedShip._input.
	_send_key(KEY_RIGHT)
	_send_key(KEY_RIGHT)
	_send_key(KEY_RIGHT)

func _tick_delete_input_phase() -> void:
	var coord = playable.menu_coordinator
	match _delete_input_phase:
		0:
			# One real SceneTree frame has passed since the three ui_right
			# InputEventKey presses were parsed -- confirm the verb cycle
			# landed on Delete via the actual handle_ui_input path before
			# arming it, so a regression in the ui_right branch (or in
			# _cycle_save_load_verb's wiring to it) fails this smoke instead
			# of silently degrading back to a direct-call test.
			if coord._save_load_pending_verb != "Delete":
				_fail("expected pending verb 'Delete' after 3 real ui_right presses, got '%s'" % coord._save_load_pending_verb)
				return
			_send_key(KEY_ENTER)  # ui_accept: arms Delete
			_delete_input_phase = 1
		1:
			# NOTE: coord.get_last_meta_screen_confirm_result() cannot be read
			# here -- _dispatch_save_load_confirm_result() (the same production
			# seam _input calls every frame handle_ui_input returns true)
			# already cleared it synchronously within the _input call that
			# processed the ui_accept press, one frame ago. Assert on the
			# durable coordinator state the arm step sets instead:
			# _pending_delete_slot_id records the armed slot until the second
			# confirm, and _save_load_pending_verb must still read "Delete".
			if coord._pending_delete_slot_id != TARGET_SLOT_ID:
				_fail("expected delete_armed (_pending_delete_slot_id='%s') after real ui_accept arm press, got '%s'" % [TARGET_SLOT_ID, coord._pending_delete_slot_id])
				return
			if coord._save_load_pending_verb != "Delete":
				_fail("pending verb should still be 'Delete' after the arming ui_accept, got '%s'" % coord._save_load_pending_verb)
				return
			_send_key(KEY_ENTER)  # ui_accept: confirms Delete
			_delete_input_phase = 2
		2:
			# Second confirm executes the delete and resets both
			# _pending_delete_slot_id and _save_load_pending_verb to "" --
			# the durable proof of a successful delete_confirmed, since (as
			# above) the transient confirm-result Dictionary is already
			# cleared by the time this phase runs.
			if not coord._pending_delete_slot_id.is_empty():
				_fail("expected _pending_delete_slot_id cleared after confirmed delete, still '%s'" % coord._pending_delete_slot_id)
				return
			if playable.save_load_service.has_slot(TARGET_SLOT_ID):
				_fail("slot '%s' still present after confirmed delete" % TARGET_SLOT_ID)
				return
			_delete_input_phase = -1
			_finish_after_delete()

func _finish_after_delete() -> void:
	var coord = playable.menu_coordinator
	# Extra assertion 2 (cursor-follows-slot, Delete half): after the
	# confirmed delete, the cursor must land on TARGET_SLOT_ID's re-synthesized
	# empty row (the slot's row identity persists across the transition from
	# real/filled to synthetic/empty).
	var post_delete_rows: Array = coord._save_load_rows()
	if coord._save_load_row_index < 0 or coord._save_load_row_index >= post_delete_rows.size() or String(post_delete_rows[coord._save_load_row_index].slot_id) != TARGET_SLOT_ID:
		_fail("cursor did not follow slot '%s' after Delete (index=%d)" % [TARGET_SLOT_ID, coord._save_load_row_index])
		return
	var post_delete_row = post_delete_rows[coord._save_load_row_index]
	if int(post_delete_row.saved_at_epoch) != 0 or not String(post_delete_row.schema_version).is_empty():
		_fail("post-delete row for '%s' is not a synthesized empty row" % TARGET_SLOT_ID)
		return

	# In-script re-verification: the index must list neither slot this smoke
	# created before finishing.
	var final_slot_ids: Array = []
	for row in playable.save_load_service.list_slots():
		final_slot_ids.append(String(row.slot_id))
	if final_slot_ids.has(TARGET_SLOT_ID):
		_fail("index still lists '%s' at end of smoke" % TARGET_SLOT_ID)
		return
	if final_slot_ids.has(FROZEN_SLOT_ID):
		_fail("index still lists '%s' at end of smoke" % FROZEN_SLOT_ID)
		return

	finished = true
	print("SAVE LOAD SLOT SCREEN PASS save=true load=true delete_armed=true delete_confirmed=true")
	_cleanup_and_quit(0)

func _send_key(keycode: int) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)

func _find_row_index(rows: Array, slot_id: String) -> int:
	for i in range(rows.size()):
		if String(rows[i].slot_id) == slot_id:
			return i
	return -1

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
	push_error("SAVE LOAD SLOT SCREEN FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if playable != null and is_instance_valid(playable) and playable.save_load_service != null:
		var resolver := PermadeathResolverScript.new()
		playable.save_load_service.delete_slot(TARGET_SLOT_ID)
		playable.save_load_service.delete_slot(FROZEN_SLOT_ID)
		resolver.clear_death(TARGET_SLOT_ID)
		resolver.clear_death(FROZEN_SLOT_ID)
		# PR #57 Codex P2 world-row Load fixture: this smoke writes a real
		# world.json (via request_save()/save_world()) that did not exist
		# before it ran -- wipe it the same way every other world-save-
		# touching smoke does (delete_current_run() removes both the
		# active-autosave AND world slot files/index/manifest entries).
		playable.save_load_service.delete_current_run()
		resolver.clear_death("world")
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
