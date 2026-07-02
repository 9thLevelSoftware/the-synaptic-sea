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
##
## Pass marker:
##   SAVE LOAD SLOT SCREEN PASS save=true load=true delete_armed=true delete_confirmed=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const TIMEOUT_FRAMES: int = 600
const TARGET_SLOT_ID: String = "slot_01"
const FROZEN_SLOT_ID: String = "slot_02"

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

	# --- Delete: two-step arm/confirm. Cycle the pending verb Load -> Save
	# -> Delete before the arming confirm, mirroring how a player would
	# ui_left/ui_right to Delete before pressing ui_accept twice. ---
	coord._refresh_save_load_panel()
	coord.meta_screen_move_selection(-9999)
	rows = coord._save_load_rows()
	target_index = _find_row_index(rows, TARGET_SLOT_ID)
	if target_index < 0:
		_fail("slot row disappeared before Delete verb drive")
		return
	for _i in range(target_index):
		coord.meta_screen_move_selection(1)
	# meta_screen_move_selection() above reset _save_load_pending_verb to ""
	# (unarmed), so the first cycle lands on the FIRST verb ("Load"), not the
	# second -- three cycles are needed to walk unset -> Load -> Save -> Delete.
	coord._cycle_save_load_verb(1)  # unset -> Load
	coord._cycle_save_load_verb(1)  # Load -> Save
	coord._cycle_save_load_verb(1)  # Save -> Delete
	if coord._save_load_pending_verb != "Delete":
		_fail("expected pending verb 'Delete' after 3 cycles from unset, got '%s'" % coord._save_load_pending_verb)
		return
	var delete_arm_result: Dictionary = coord.meta_screen_confirm()  # arms Delete
	if str(delete_arm_result.get("action", "")) != "delete_armed":
		_fail("expected delete_armed on first Delete confirm: %s" % str(delete_arm_result))
		return
	var delete_confirmed_result: Dictionary = coord.meta_screen_confirm()  # second confirm deletes
	if str(delete_confirmed_result.get("action", "")) != "delete" or not bool(delete_confirmed_result.get("ok", false)):
		_fail("Delete did not confirm: %s" % str(delete_confirmed_result))
		return
	if playable.save_load_service.has_slot(TARGET_SLOT_ID):
		_fail("slot '%s' still present after confirmed delete" % TARGET_SLOT_ID)
		return

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
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
