# Domain 8: Save / Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the `save` completion-roadmap loop (Domain 8) by wiring the dead multi-slot LOAD path, permadeath (freeze-not-delete), a real title screen with Continue/New Game/Quit, an interactive save/load slot screen, and a Save & Exit action — without touching `scripts/main.gd`/`scenes/main.tscn` (every existing main-scene smoke keeps booting them unmodified).

**Architecture:** `scenes/title_main.tscn` (new `run/main_scene`) wraps `scenes/main.tscn` (unchanged) as a child, instantiated lazily on New Game/Continue/return-from-gameplay. `MenuCoordinator` gains a `"save_load"` interactive meta-screen arm (cursor + verb-cycling + two-step delete) mirroring the existing `hub_upgrades`/`skill_tree`/`class` pattern, plus a `snapshot_builder: Callable` seam so it can request a `RunSnapshot` from `PlayableGeneratedShip` without owning gameplay state. `PlayableGeneratedShip.end_run` branches on `reason`: death now freezes every slot written this run (via `PermadeathResolver.record_death`) instead of deleting; `SaveLoadService.load_world`/`load_from_slot` refuse frozen slots. A new pure model `TitleSaveQuery` decides Continue-availability headlessly. `_input`'s post-death dead-zone is fixed by moving the `menu_coordinator` dispatch ahead of the `slice_complete` early-return, unblocking epitaph browsing after death.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless validation smokes

## Global Constraints
- GODOT binary: `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`
- ROOT: `C:/Users/dasbl/Documents/The Synaptic Sea`
- Run pattern: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd`
- Godot `--script` can exit 0 on parse errors — the PASS marker line printed to stdout is the contract; never trust the process exit code alone, always grep the marker.
- Allowlisted teardown noise (may appear in ANY smoke's output, ignore it): `ERROR: Capture not registered: 'gdaimcp'.` + `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).` + the save/load smoke's existing expected `WARNING: SaveLoadService: slot rejected by migration (newer than current), slot_id=...` rejection line. Any OTHER `ERROR:`/`WARNING:` line fails the task.
- All GDScript is typed (explicit `-> ReturnType`, typed `var x: Type`) matching the surrounding file's existing style.
- Maintain strict Model (RefCounted, no scene-tree access) / Node (Control/Node3D, scene-tree + signals) separation — new pure logic (`TitleSaveQuery`) goes in `scripts/systems/`, never in a Node script.
- Conventional commits (`feat:`, `fix:`, `test:`, `docs:`) for every commit step.
- NEVER stage `.godot/`, `*.uid`, or `addons/` in any commit in this plan.
- `project.godot` may ONLY be touched for the single `run/main_scene` line (Task 4) — no other line in that file changes.
- Every new smoke that writes to `user://saves/` MUST delete every file it wrote (`world.json`, every `*.death.json`, `*.manifest.json`, slot `.json`/`.migrated.json`, `index.json` rows) in BOTH the success (`_cleanup_and_quit(0)`) and failure (`_fail(...)` -> `_cleanup_and_quit(1)`) exit paths — mirror the unconditional-cleanup convention in `scripts/validation/main_playable_death_clears_autosave_smoke.gd` / `scripts/validation/world_save_anywhere_smoke.gd`. A leaked `world.death.json` permanently disables Continue for a human running the game after tests.
- The exact PASS marker strings quoted in this plan (spec section 5) are byte-contracts — the regression bundle's `run_clean` invocation greps for them verbatim; do not paraphrase, reorder fields, or change spacing.
- Troubleshooting note (not a task step): if a smoke fails with unexpected parse/class errors after adding a new `class_name`, Godot's script-class cache may be stale. Run `"$GODOT" --editor --path "$ROOT" --quit` once first (a teardown segfault / exit code 139 from this command is benign — ignore it) and re-run the smoke.
- The regression bundle lives in `docs/game/06_validation_plan.md`'s "Regression bundle" bash block; it honors `ROOT`/`GODOT` env-var overrides — do not hardcode paths inside `run_clean` lines beyond what already exists there.
- `docs/game/06_validation_plan.md` currently has paths for a different machine (`/Users/christopherwilloughby/...`) baked into its header prose (`## Godot binary`, `## Project root`) — these are pre-existing and OUT OF SCOPE for this plan; do not "fix" them. Only touch the `run_clean` lines (add 5, remove 1) and the final `commands=` echo line, per Task 11.

## Task sequence rationale

Tasks 1-2 land the highest-blast-radius change first (per spec Risk 1) so any fallout is caught early, not at the end. Tasks 3-6 build the title screen bottom-up (pure model -> scene/script -> signal wiring -> smoke). Tasks 7-9 build the interactive slot screen. Task 10 adds Save & Exit. Tasks 11-12 close out docs/inventory and run the full bundle.

---

### Task 1: Permadeath freeze -- end_run, SaveLoadService freeze-gate, new smoke, delete old smoke

**Files:**
- Modify: scripts/procgen/playable_generated_ship.gd (end_run at line 1604; add _freeze_run_on_death + _build_epitaph_text helpers nearby)
- Modify: scripts/systems/save_load_service.gd (load_world() at line 113; load_from_slot() already gates at line 249 -- verify only, do not duplicate)
- Delete: scripts/validation/main_playable_death_clears_autosave_smoke.gd and its .uid sibling
- Create: scripts/validation/permadeath_freeze_smoke.gd
- Modify: scripts/validation/save_load_service_smoke.gd (append one assertion before the final print/quit(0))

**Interfaces:**
- Consumes: PermadeathResolver.record_death(slot_id, cause, epitaph, run_time_seconds, final_objective_sequence) -> Dictionary (existing, scripts/systems/permadeath_resolver.gd:37), PermadeathResolver.has_died_in(slot_id) -> bool (existing, line 20), SaveLoadService.has_slot(slot_id) -> bool (existing, line 328), SaveSlotState.AUTOSAVE_SLOT_IDS/QUICKSAVE_SLOT_ID (existing, scripts/systems/save_slot_state.gd:21-22), SaveLoadService.ACTIVE_AUTOSAVE_SLOT_ID (existing, line 38).
- Produces: PlayableGeneratedShip._freeze_run_on_death() -> void (private helper, called only from end_run), PlayableGeneratedShip._manual_slots_written_this_run: Dictionary (new run-local instance var, empty dict at declaration -- Task 8 populates it; this task only declares and freezes from it), SaveLoadService.load_world() now returns null when PermadeathResolver.has_died_in("world") is true -- later tasks (Task 4's TitleSaveQuery) depend on this gate.

**Steps:**

- [ ] 1.1 Read the current end_run body to confirm no drift from the verified text below.

  Run: grep -n -A 20 "^func end_run" "scripts/procgen/playable_generated_ship.gd"

  Confirm it matches (whitespace uses tabs):
  ```gdscript
  func end_run(reason: String = "extraction") -> int:
  	if slice_complete:
  		return 0
  	slice_complete = true
  	tracker.mark_run_complete()
  	var payout: int = int(_apply_meta_payout_and_persist(reason))
  	if save_load_service != null:
  		save_load_service.delete_current_run()
  		for slot_id in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
  			save_load_service.delete_slot(slot_id)
  	emit_signal("playable_slice_completed", get_slice_completion_summary())
  	return payout
  ```
  If the body has drifted (different line numbers are fine; different logic is not), STOP and re-derive this task's diff against the actual text before proceeding -- do not blindly apply the replacement below over materially different code.

- [ ] 1.2 Replace end_run with the freeze-branching version, and add _freeze_run_on_death/_build_epitaph_text immediately after it. Also add the _manual_slots_written_this_run instance var right above func end_run.

  Old (immediately above func end_run):
  ```gdscript
  func end_run(reason: String = "extraction") -> int:
  ```
  New:
  ```gdscript
  # Domain 8 (ADR-0043): slot ids the slot screen's Save verb has written to
  # THIS run. Permadeath freeze must also freeze these -- a mid-run manual
  # save must not be a save-scumming escape hatch from permadeath. Cleared
  # implicitly by process restart / fresh PlayableGeneratedShip; never
  # persisted itself (it is a run-local bookkeeping set, not save data).
  var _manual_slots_written_this_run: Dictionary = {}

  func end_run(reason: String = "extraction") -> int:
  ```

  Old:
  ```gdscript
  func end_run(reason: String = "extraction") -> int:
  	if slice_complete:
  		return 0
  	slice_complete = true
  	tracker.mark_run_complete()
  	var payout: int = int(_apply_meta_payout_and_persist(reason))
  	if save_load_service != null:
  		save_load_service.delete_current_run()
  		for slot_id in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
  			save_load_service.delete_slot(slot_id)
  	emit_signal("playable_slice_completed", get_slice_completion_summary())
  	return payout
  ```
  New:
  ```gdscript
  func end_run(reason: String = "extraction") -> int:
  	if slice_complete:
  		return 0
  	slice_complete = true
  	tracker.mark_run_complete()
  	var payout: int = int(_apply_meta_payout_and_persist(reason))
  	if save_load_service != null:
  		if reason == "death":
  			# ADR-0043: permadeath freezes, it does not delete. world.json and
  			# every slot written this run stay on disk; a death record gates
  			# every future load of them (SaveLoadService.load_world /
  			# load_from_slot), and the slot screen renders them DEAD with an
  			# epitaph (ADR-0032's original browse-the-epitaph intent).
  			_freeze_run_on_death()
  		else:
  			# Extraction/completion path UNCHANGED -- still deletes. A finished
  			# successful run has nothing to "continue"; this is not permadeath.
  			save_load_service.delete_current_run()
  			for slot_id in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
  				save_load_service.delete_slot(slot_id)
  	emit_signal("playable_slice_completed", get_slice_completion_summary())
  	return payout
  ```

  Also add these two new helper functions immediately after end_run's closing return payout line:
  ```gdscript
  ## ADR-0043: freeze every slot that represents "the state at/after death"
  ## instead of deleting it. Manual slot_01..06 the player saved THIS run are
  ## included (via _manual_slots_written_this_run) -- a mid-run manual save
  ## must not be a permadeath escape hatch. world.json itself is never
  ## deleted; PermadeathResolver.has_died_in("world") gates future loads.
  func _freeze_run_on_death() -> void:
  	var resolver := PermadeathResolverScript.new()
  	var epitaph_text: String = _build_epitaph_text()
  	var run_time: float = world_time
  	var final_seq: int = current_objective_sequence
  	var slots_to_freeze: Array = [SaveLoadServiceScript.ACTIVE_AUTOSAVE_SLOT_ID, "world"]
  	slots_to_freeze.append_array(SaveSlotStateScript.AUTOSAVE_SLOT_IDS)
  	if save_load_service.has_slot(SaveSlotStateScript.QUICKSAVE_SLOT_ID):
  		slots_to_freeze.append(SaveSlotStateScript.QUICKSAVE_SLOT_ID)
  	for manual_slot_id in _manual_slots_written_this_run.keys():
  		slots_to_freeze.append(String(manual_slot_id))
  	for slot_id in slots_to_freeze:
  		resolver.record_death(slot_id, "death", epitaph_text, run_time, final_seq)

  ## ADR-0043: short human-readable epitaph text for the frozen slot rows /
  ## death record. Cause is always "death" today (the only end_run reason
  ## that freezes); location comes from the current ship's marker_id (empty
  ## string = home ship).
  func _build_epitaph_text() -> String:
  	var location: String = ""
  	var cur = get_current_ship()
  	if cur != null:
  		location = String(cur.marker_id)
  	var location_label: String = location if not location.is_empty() else "the home ship"
  	return "Died aboard %s at objective %d (run time %.0fs)" % [location_label, current_objective_sequence, world_time]
  ```

- [ ] 1.3 Confirm PermadeathResolverScript and SaveLoadServiceScript constants are already preloaded in this file (both are referenced above without a new const). Run:

  grep -n "PermadeathResolverScript\|SaveLoadServiceScript" "scripts/procgen/playable_generated_ship.gd" | head -5

  If PermadeathResolverScript is NOT already a top-of-file const, add it next to the other const ...Script := preload(...) declarations near the top of the file (search for "const SaveSlotStateScript" and add directly below it):
  ```gdscript
  const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
  ```
  (If it is already preloaded, skip this step; do not double-declare a const, which is a parse error.)

- [ ] 1.4 Add the load_world() death-gate in scripts/systems/save_load_service.gd. Read the current body first:

  grep -n -A 32 "^func load_world" "scripts/systems/save_load_service.gd"

  Old:
  ```gdscript
  func load_world():
  	var path: String = WORLD_SLOT_FILE
  	if not FileAccess.file_exists(path):
  		return null
  	var file := FileAccess.open(path, FileAccess.READ)
  ```
  New:
  ```gdscript
  func load_world():
  	var path: String = WORLD_SLOT_FILE
  	if not FileAccess.file_exists(path):
  		return null
  	# ADR-0043 permadeath gate -- mirrors the load_from_slot:249 gate. Old
  	# saves have no world.death.json, so has_died_in defaults false and
  	# legacy loads are unaffected.
  	if PermadeathResolverScript.new().has_died_in("world"):
  		return null
  	var file := FileAccess.open(path, FileAccess.READ)
  ```

- [ ] 1.5 Delete the old smoke (its cleared=true contract is now factually inverted) and create the replacement.

  Run: git rm scripts/validation/main_playable_death_clears_autosave_smoke.gd scripts/validation/main_playable_death_clears_autosave_smoke.gd.uid

  Create scripts/validation/permadeath_freeze_smoke.gd:
  ```gdscript
  extends SceneTree

  ## Domain 8 (ADR-0043) permadeath freeze: when the player dies
  ## (end_run("death") via _check_vitals_death, driven by the real
  ## coordinator _process on BOTH branches), every slot written this run
  ## freezes instead of being deleted -- world.json, the active autosave
  ## alias, every AUTOSAVE_SLOT_IDS row, the quickslot if present, and any
  ## manual slot the player saved this run. Replaces the deleted
  ## main_playable_death_clears_autosave_smoke.gd (its cleared=true
  ## contract inverted under freeze-not-delete).
  ##
  ## Drives death on BOTH away_from_start branches (the historically-
  ## regressive pattern per project conventions) and asserts the pause
  ## menu is still reachable post-death (the _input dead-zone fix, Task 2).
  ##
  ## Pass marker:
  ##   PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true

  const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
  const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
  const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
  const TIMEOUT_FRAMES: int = 600

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
  ```

  ```gdscript
  func _validate() -> void:
  	if playable.vitals_state == null or playable.save_load_service == null:
  		_fail("vitals / save_load_service missing")
  		return
  	if playable.threat_manager != null:
  		playable.threat_manager.threats.clear()
  	var service = playable.save_load_service
  	var resolver := PermadeathResolverScript.new()

  	# Clean slate for every slot family this smoke touches.
  	_wipe_all(service, resolver)

  	# --- HOME-BRANCH DEATH ---
  	playable.away_from_start = false
  	if not playable.request_save():
  		_fail("home request_save should succeed before home-branch death")
  		return
  	var r: Dictionary = playable.force_autosave_for_validation()
  	var autosave_slot: String = str(r.get("slot_id", ""))
  	if not SaveSlotStateScript.AUTOSAVE_SLOT_IDS.has(autosave_slot):
  		_fail("forced autosave slot=%s not in AUTOSAVE_SLOT_IDS (home branch)" % autosave_slot)
  		return
  	playable.vitals_state.health = 0.0
  	_pump(0.1)
  	if not playable.slice_complete:
  		_fail("home-branch health=0 should have ended the run as death")
  		return
  	if not service.has_slot("world"):
  		_fail("world.json was deleted on death (home branch) -- freeze contract requires it stay on disk")
  		return
  	if not resolver.has_died_in("world"):
  		_fail("world slot has no death record after home-branch death")
  		return
  	if not resolver.has_died_in(autosave_slot):
  		_fail("autosave slot '%s' has no death record after home-branch death" % autosave_slot)
  		return
  	for sid in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
  		if not service.has_slot(sid):
  			continue
  		if not resolver.has_died_in(sid):
  			_fail("autosave slot '%s' survived death un-frozen (home branch)" % sid)
  			return
  	if service.load_world() != null:
  		_fail("load_world() returned non-null for a frozen world slot (home branch)")
  		return
  	var epitaph: Dictionary = resolver.load_epitaph("world")
  	if str(epitaph.get("epitaph", "")).is_empty():
  		_fail("world epitaph text is empty after home-branch death")
  		return
  	if not is_instance_valid(playable.menu_coordinator):
  		_fail("menu_coordinator missing post-death (home branch)")
  		return
  	var pause_event := InputEventAction.new()
  	pause_event.action = "ui_pause"
  	pause_event.pressed = true
  	playable._input(pause_event)
  	if playable.menu_coordinator.get_current_menu() != "pause_menu":
  		_fail("pause menu did not open post-death (home branch) -- _input dead-zone regression")
  		return
  	playable.menu_coordinator.menu_state.close_all()
  ```

  ```gdscript
  	# Reset for a fresh away-branch run on the SAME instance (mirrors the
  	# established pattern in main_playable_survival_away_smoke.gd, which
  	# never needs a second scene instance to prove the away branch).
  	_wipe_all(service, resolver)
  	playable.slice_complete = false
  	playable.vitals_state.health = 100.0
  	playable._manual_slots_written_this_run.clear()

  	# --- AWAY-BRANCH DEATH ---
  	playable.away_from_start = true
  	if not playable.request_save():
  		_fail("away request_save should succeed before away-branch death")
  		return
  	var r2: Dictionary = playable.force_autosave_for_validation()
  	var autosave_slot2: String = str(r2.get("slot_id", ""))
  	if not SaveSlotStateScript.AUTOSAVE_SLOT_IDS.has(autosave_slot2):
  		_fail("forced autosave slot=%s not in AUTOSAVE_SLOT_IDS (away branch)" % autosave_slot2)
  		return
  	playable.vitals_state.health = 0.0
  	_pump(0.1)
  	if not playable.slice_complete:
  		_fail("away-branch health=0 should have ended the run as death")
  		return
  	if not resolver.has_died_in("world"):
  		_fail("world slot has no death record after away-branch death")
  		return
  	if not resolver.has_died_in(autosave_slot2):
  		_fail("autosave slot '%s' has no death record after away-branch death" % autosave_slot2)
  		return
  	if service.load_world() != null:
  		_fail("load_world() returned non-null for a frozen world slot (away branch)")
  		return
  	var pause_event2 := InputEventAction.new()
  	pause_event2.action = "ui_pause"
  	pause_event2.pressed = true
  	playable._input(pause_event2)
  	if playable.menu_coordinator.get_current_menu() != "pause_menu":
  		_fail("pause menu did not open post-death (away branch) -- _input dead-zone regression")
  		return
  	playable.menu_coordinator.menu_state.close_all()

  	finished = true
  	print("PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true")
  	_cleanup_and_quit(0)

  func _wipe_all(service, resolver) -> void:
  	for sid in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
  		service.delete_slot(sid)
  	service.delete_slot(SaveSlotStateScript.QUICKSAVE_SLOT_ID)
  	for sid in SaveSlotStateScript.MANUAL_SLOT_IDS:
  		service.delete_slot(sid)
  	service.delete_current_run()
  	resolver.clear_death("world")
  	resolver.clear_death(service.ACTIVE_AUTOSAVE_SLOT_ID)
  	for sid in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
  		resolver.clear_death(sid)
  	resolver.clear_death(SaveSlotStateScript.QUICKSAVE_SLOT_ID)
  	for sid in SaveSlotStateScript.MANUAL_SLOT_IDS:
  		resolver.clear_death(sid)

  func _pump(seconds: float) -> void:
  	var step: float = 1.0 / 30.0
  	var elapsed: float = 0.0
  	while elapsed < seconds:
  		playable._process(step)
  		elapsed += step

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
  	push_error("PERMADEATH FREEZE FAIL reason=%s" % reason)
  	_cleanup_and_quit(1)

  func _cleanup_and_quit(code: int) -> void:
  	if playable != null and is_instance_valid(playable) and playable.save_load_service != null:
  		_wipe_all(playable.save_load_service, PermadeathResolverScript.new())
  	if main_node != null and is_instance_valid(main_node):
  		main_node.queue_free()
  	quit(code)
  ```

  NOTE for the implementing subagent: this smoke calls playable._input(pause_event) directly BEFORE Task 2's fix lands. If run standalone right now (before Task 2), the pause-menu assertions in this smoke WILL fail because _input still hard-returns on slice_complete. That is expected and correct -- Task 1's own scope is the freeze logic; do NOT weaken this smoke's pause-menu assertions to make Task 1 pass in isolation. Commit the FULL smoke text above unchanged even if the pause-menu assertion is red until Task 2 lands; Task 2's own verification step (2.4) is where this smoke must go fully green. If your task runner requires a fully green smoke before moving on, do Task 1 and Task 2 as one combined work session before running the smoke for the first time -- the task boundary exists for review/commit granularity, not for gating a green run mid-way.

- [ ] 1.6 Extend scripts/validation/save_load_service_smoke.gd in place with one new assertion. Read the current tail first:

  grep -n "SAVE LOAD SERVICE PASS\|func _fail" "scripts/validation/save_load_service_smoke.gd"

  Insert the new assertion immediately BEFORE the existing print("SAVE LOAD SERVICE PASS ...") / quit(0) lines (do not change that print line -- it is an existing bundle marker):

  Old (end of _initialize):
  ```gdscript
  	# Cleanup
  	service.delete_current_run()
  	if service.has_save():
  		_fail("delete_current_run did not remove the file")
  		return

  	print("SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27")
  	quit(0)
  ```
  New:
  ```gdscript
  	# Cleanup
  	service.delete_current_run()
  	if service.has_save():
  		_fail("delete_current_run did not remove the file")
  		return

  	# ADR-0043 permadeath freeze-gate: load_world() must refuse a frozen slot.
  	var resolver_script := load("res://scripts/systems/permadeath_resolver.gd")
  	var resolver = resolver_script.new()
  	resolver.clear_death("world")
  	var world_script := load("res://scripts/systems/world_snapshot.gd")
  	var ws = world_script.new()
  	ws.current_objective_sequence = 1
  	if not service.save_world(ws):
  		_fail("save_world failed while seeding the permadeath-gate assertion")
  		return
  	resolver.record_death("world", "death", "test epitaph", 12.0, 1)
  	if service.load_world() != null:
  		_fail("load_world() returned non-null for a frozen world slot")
  		return
  	resolver.clear_death("world")
  	service.delete_current_run()
  	if service.load_world() != null:
  		_fail("cleanup: load_world() should be null after delete_current_run")
  		return

  	print("SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27")
  	quit(0)
  ```
  If WorldSnapshot requires more than current_objective_sequence to construct validly for save_world, inspect scripts/systems/world_snapshot.gd's fields and set any other required non-default fields the same way world_save_service_smoke.gd does (grep that smoke first for its minimal-construction pattern before writing this step's final code).

- [ ] 1.7 Run the new/changed smokes directly and confirm the exact marker strings.

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/permadeath_freeze_smoke.gd

  Expect stdout to contain exactly: PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true (this will only fully pass after Task 2 lands per the note in 1.5).

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/save_load_service_smoke.gd

  Expect stdout to contain exactly: SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27

- [ ] 1.8 Commit.

  ```
  git add scripts/procgen/playable_generated_ship.gd scripts/systems/save_load_service.gd scripts/validation/permadeath_freeze_smoke.gd scripts/validation/save_load_service_smoke.gd scripts/validation/main_playable_death_clears_autosave_smoke.gd scripts/validation/main_playable_death_clears_autosave_smoke.gd.uid
  git commit -m "feat: permadeath freeze-not-delete (ADR-0043); replace death-clears-autosave smoke"
  ```

---

### Task 2: _input post-death menu-access fix (highest blast radius -- full bundle immediately after)

**Files:** Modify scripts/procgen/playable_generated_ship.gd (_input at line 7548)

**Interfaces:**
- Consumes: MenuCoordinator.handle_ui_input(event: InputEvent) -> bool (existing, scripts/ui/menu_coordinator.gd:145).
- Produces: no new public API -- _input's internal control flow changes so the menu_coordinator dispatch runs BEFORE the slice_complete gate; only the gameplay-input tail (hotbar keys, attack, save/load keybinds) stays gated on slice_complete.

**Steps:**

- [ ] 2.1 Read the current _input body to confirm no drift.

  grep -n -A 80 "^func _input" "scripts/procgen/playable_generated_ship.gd" | head -90

  Confirm the structure matches: hard-return on "not playable_started or slice_complete", then scanner-panel handling, inventory-panel handling, menu_coordinator.handle_ui_input dispatch, then a "save_load_service == null" return and the gameplay-input tail (hotbar 1/2/3, attack, reload, save_run/load_run).

- [ ] 2.2 Move the slice_complete gate so it only blocks the gameplay-input tail, not the scanner/inventory/menu dispatch.

  Old:
  ```gdscript
  func _input(event: InputEvent) -> void:
  	if not playable_started or slice_complete:
  		return
  	# Phase 4.5: scanner panel toggle + navigation. Opening the panel freezes
  	# player movement/interaction so the shared arrow/Enter keys drive the panel.
  	# Control is restored on close by the panel_closed signal handler, which
  	# covers every close path -- not just toggle-close / confirm-success.
  	if scanner_panel != null:
  ```
  New:
  ```gdscript
  func _input(event: InputEvent) -> void:
  	if not playable_started:
  		return
  	# ADR-0043: slice_complete no longer hard-gates the whole function. Death
  	# ends the run but must not lock the player out of the menu (epitaph
  	# browsing on the frozen slot screen is the whole point of the freeze).
  	# Only the gameplay-input tail below (hotbar/attack/reload/save/load) is
  	# still gated on slice_complete -- see the "if slice_complete: return"
  	# inserted right after the menu_coordinator dispatch block.
  	# Phase 4.5: scanner panel toggle + navigation. Opening the panel freezes
  	# player movement/interaction so the shared arrow/Enter keys drive the panel.
  	# Control is restored on close by the panel_closed signal handler, which
  	# covers every close path -- not just toggle-close / confirm-success.
  	if scanner_panel != null:
  ```

  Then insert a new slice_complete gate immediately after the menu_coordinator dispatch block and before the gameplay-input tail. Old (the block right after the menu dispatch):
  ```gdscript
  		for action_name in ["move_forward", "move_back", "move_left", "move_right"]:
  			if event.is_action_pressed(action_name):
  				menu_coordinator.trigger_tutorial("player_moved", "any")
  				break
  	if save_load_service == null:
  		return
  ```
  New:
  ```gdscript
  		for action_name in ["move_forward", "move_back", "move_left", "move_right"]:
  			if event.is_action_pressed(action_name):
  				menu_coordinator.trigger_tutorial("player_moved", "any")
  				break
  	# ADR-0043: everything below this point is live gameplay input (hotbar,
  	# attack, reload, manual save/load keys) -- correctly still locked out
  	# once the run has ended (death or extraction). Only the menu dispatch
  	# above this line must survive slice_complete.
  	if slice_complete:
  		return
  	if save_load_service == null:
  		return
  ```

- [ ] 2.3 Verify the scanner-panel and inventory-panel blocks (which sit ABOVE the menu dispatch, between the new top-of-function guard and the menu dispatch) are unchanged -- they now run whenever playable_started is true, regardless of slice_complete. This is intended: scanner/inventory toggling post-death is harmless (both panels no-op gracefully if their backing state is stale) and was never the target of this fix; the fix's actual requirement is only that menu_coordinator.handle_ui_input runs pre-slice_complete, which it now does.

- [ ] 2.4 Re-run permadeath_freeze_smoke.gd and confirm it is now fully green (both branches' pause-menu assertions pass).

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/permadeath_freeze_smoke.gd

  Expect: PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true with no unexpected ERROR:/WARNING: lines (allowlist per Global Constraints).

- [ ] 2.5 HIGH BLAST RADIUS -- run the FULL regression bundle immediately (do not defer to Task 12). This change touches every input-path smoke in the project.

  Copy the fenced bash block under the "## Regression bundle" heading in docs/game/06_validation_plan.md into a temp script, override ROOT and GODOT:
  ```bash
  export ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  export GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  bash /path/to/extracted_regression_bundle.sh
  ```
  Confirm the final line printed is SYNAPTIC_SEA REGRESSION PASS commands=107 clean_output=true (still 107 at this point -- the bundle's own registration update happens in Task 11; this run is PURELY to catch _input-fix fallout across all ~107 existing commands using the CURRENT bundle text, which still references the now-deleted main_playable_death_clears_autosave_smoke.gd -- see 2.6).

- [ ] 2.6 The current 06_validation_plan.md bundle still has a run_clean line for the deleted main_playable_death_clears_autosave_smoke.gd (Task 1 deleted the file but this task's job is ONLY the _input fix + regression check -- do not do the full bundle-registration edit here). To make the 2.5 regression run possible without a hard file-not-found failure, temporarily note which line references the deleted smoke (grep -n "death_clears_autosave" docs/game/06_validation_plan.md) and skip only that single run_clean invocation when running the bundle manually in this task (comment it out in your local copy of the extracted script, NOT in the committed doc -- Task 11 is the sanctioned place to edit 06_validation_plan.md itself). If any OTHER command in the bundle fails or produces a new unexpected ERROR/WARNING, treat it as fallout from the _input change and fix it before proceeding -- do not move to Task 3 with a red bundle.

- [ ] 2.7 Commit.

  ```
  git add scripts/procgen/playable_generated_ship.gd
  git commit -m "fix: run menu_coordinator input dispatch before slice_complete gate (post-death menu access)"
  ```

---

### Task 3: TitleSaveQuery pure model + smoke

**Files:**
- Create: scripts/systems/title_save_query.gd
- Create: scripts/validation/title_save_query_smoke.gd

**Interfaces:**
- Consumes: SaveLoadService.has_slot(slot_id) -> bool (existing), PermadeathResolver.has_died_in(slot_id) -> bool (existing).
- Produces: TitleSaveQuery.is_continue_available(service, resolver) -> bool (static, pure) -- consumed by Task 4's scripts/title_main.gd.

**Steps:**

- [ ] 3.1 Verify SaveLoadService.has_slot("world") correctly resolves to the world file path (already confirmed: _slot_path special-cases slot_kind == SLOT_KIND_WORLD or slot_id == "world" to WORLD_SLOT_FILE, and _indexed_kind_for("world") returns SLOT_KIND_WORLD even with an empty index -- scripts/systems/save_load_service.gd:363-378). No change needed here; this step is a read-only confirmation before writing the model.

  grep -n -A 4 "^func has_slot" "scripts/systems/save_load_service.gd"

- [ ] 3.2 Create scripts/systems/title_save_query.gd:
  ```gdscript
  extends RefCounted
  class_name TitleSaveQuery

  ## ADR-0043: pure decision model for the title screen's Continue item.
  ## No scene-tree access -- headlessly smokeable. Continue is available
  ## when a world save exists AND the world slot has not been permadeath-
  ## frozen. Old (pre-Domain-8) saves have no world.death.json, so
  ## has_died_in defaults false and legacy saves are unaffected.

  const WORLD_SLOT_ID: String = "world"

  static func is_continue_available(service: Object, resolver: Object) -> bool:
  	if service == null or resolver == null:
  		return false
  	if not service.has_slot(WORLD_SLOT_ID):
  		return false
  	return not resolver.has_died_in(WORLD_SLOT_ID)
  ```

- [ ] 3.3 Create scripts/validation/title_save_query_smoke.gd:
  ```gdscript
  extends SceneTree

  ## ADR-0043 TitleSaveQuery pure-model smoke: no-save, has-save, and
  ## permadeath-frozen-blocks-continue cases, all against the REAL
  ## user://saves/ dir (no test-scoped save root exists in this codebase --
  ## mirrors every other save-touching smoke's cleanup discipline).
  ##
  ## Pass marker:
  ##   TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true

  const TitleSaveQueryScript := preload("res://scripts/systems/title_save_query.gd")
  const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
  const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
  const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")

  func _initialize() -> void:
  	var service := SaveLoadServiceScript.new()
  	var resolver := PermadeathResolverScript.new()
  	_wipe(service, resolver)

  	# Case 1: no save at all.
  	var no_save: bool = not TitleSaveQueryScript.is_continue_available(service, resolver)
  	if not no_save:
  		_fail("expected Continue unavailable with no world save")
  		return

  	# Case 2: a world save exists and is not frozen.
  	var ws := WorldSnapshotScript.new()
  	ws.current_objective_sequence = 1
  	if not service.save_world(ws):
  		_fail("save_world failed while seeding has-save case")
  		return
  	var has_save: bool = TitleSaveQueryScript.is_continue_available(service, resolver)
  	if not has_save:
  		_fail("expected Continue available with an unfrozen world save")
  		return

  	# Case 3: the world slot is permadeath-frozen -- Continue must be blocked
  	# even though world.json is still present on disk (freeze-not-delete).
  	resolver.record_death("world", "death", "test epitaph", 30.0, 2)
  	var frozen_blocks: bool = not TitleSaveQueryScript.is_continue_available(service, resolver)
  	if not frozen_blocks:
  		_fail("expected Continue unavailable when world slot is frozen")
  		return

  	_wipe(service, resolver)
  	print("TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true")
  	quit(0)

  func _wipe(service, resolver) -> void:
  	service.delete_current_run()
  	resolver.clear_death("world")

  func _fail(reason: String) -> void:
  	push_error("TITLE SAVE QUERY FAIL reason=%s" % reason)
  	var service := SaveLoadServiceScript.new()
  	var resolver := PermadeathResolverScript.new()
  	_wipe(service, resolver)
  	quit(1)
  ```

- [ ] 3.4 Run the smoke.

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/title_save_query_smoke.gd

  Expect: TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true

- [ ] 3.5 Commit.

  ```
  git add scripts/systems/title_save_query.gd scripts/validation/title_save_query_smoke.gd
  git commit -m "feat: TitleSaveQuery pure model for title-screen Continue availability"
  ```

---

### Task 4: scenes/title_main.tscn + scripts/title_main.gd + project.godot main-scene swap

**Files:**
- Create: scripts/title_main.gd
- Create: scenes/title_main.tscn
- Modify: project.godot (run/main_scene line only, currently line 15)

**Interfaces:**
- Consumes: MenuState.configure(catalog) -> bool, MenuState.open_menu(menu_id) -> bool, MenuState.set_item_enabled(menu_id, item_id, enabled) -> void, MenuState.confirm() -> String, MenuState.navigate(dx, dy) -> int (all existing, scripts/systems/menu_state.gd); MenuPanel.set_content(title, lines) -> void (existing, scripts/ui/menu_panel.gd:30); TitleSaveQuery.is_continue_available (Task 3); scenes/main.tscn (unchanged) exposing Main.playable_instance: PlayableGeneratedShip (existing, scripts/main.gd:7); PlayableGeneratedShip.playable_started: bool (existing field), PlayableGeneratedShip.request_load() -> bool (existing, line 6613), PlayableGeneratedShip.get_save_load_service() -> SaveLoadService (existing, line 6596).
- Produces: title_main.gd root node with _on_title_start(), _on_title_continue(), _on_title_quit(), _on_gameplay_return_to_title() -- Task 5 wires the last handler to the new return_to_title_requested signal; Task 6's smoke drives this scene directly.

**Steps:**

- [ ] 4.1 Create scripts/title_main.gd:
  ```gdscript
  extends Node

  ## ADR-0043 title screen bootstrap. project.godot run/main_scene points
  ## here; scripts/main.gd / scenes/main.tscn stay byte-identical so every
  ## existing main-scene smoke (which preloads res://scenes/main.tscn
  ## directly) is unaffected. This node instantiates scenes/main.tscn
  ## itself, lazily, only on New Game / Continue.

  const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
  const MenuStateScript := preload("res://scripts/systems/menu_state.gd")
  const MenuPanelScript := preload("res://scripts/ui/menu_panel.gd")
  const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
  const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
  const TitleSaveQueryScript := preload("res://scripts/systems/title_save_query.gd")

  var menu_state
  var menu_panel
  var main_node: Node = null
  var playable_instance: PlayableGeneratedShip = null
  var _save_load_service = null
  var _resolver = null

  func _ready() -> void:
  	_save_load_service = SaveLoadServiceScript.new()
  	_resolver = PermadeathResolverScript.new()
  	_build_title_ui()

  func _build_title_ui() -> void:
  	menu_state = MenuStateScript.new()
  	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/menu_definitions.json"))
  	if typeof(catalog) != TYPE_DICTIONARY or not menu_state.configure(catalog as Dictionary):
  		push_error("TitleMain: failed to configure MenuState from menu_definitions.json")
  		return
  	menu_panel = MenuPanelScript.new()
  	menu_panel.name = "TitleMenuPanel"
  	add_child(menu_panel)
  	menu_state.menu_changed.connect(_on_menu_changed)
  	menu_state.focus_changed.connect(_on_focus_changed)
  	_refresh_continue_enabled()
  	menu_state.open_menu("main_menu")
  	_refresh_panel()

  func _refresh_continue_enabled() -> void:
  	var available: bool = TitleSaveQueryScript.is_continue_available(_save_load_service, _resolver)
  	menu_state.set_item_enabled("main_menu", "continue", available)
  ```

  ```gdscript
  func _unhandled_input(event: InputEvent) -> void:
  	if main_node != null:
  		return  # gameplay owns input once it exists
  	if event.is_action_pressed("ui_down"):
  		menu_state.navigate(0, 1)
  		_refresh_panel()
  		get_viewport().set_input_as_handled()
  	elif event.is_action_pressed("ui_up"):
  		menu_state.navigate(0, -1)
  		_refresh_panel()
  		get_viewport().set_input_as_handled()
  	elif event.is_action_pressed("ui_accept"):
  		_confirm()
  		get_viewport().set_input_as_handled()

  func _confirm() -> void:
  	var item_id: String = menu_state.confirm()
  	if item_id.is_empty():
  		return
  	match item_id:
  		"start": _on_title_start()
  		"continue": _on_title_continue()
  		"settings": pass  # out of scope for this domain's title screen (spec 3.1)
  		"quit": _on_title_quit()

  func _on_title_start() -> void:
  	_instantiate_gameplay(false)

  func _on_title_continue() -> void:
  	_instantiate_gameplay(true)

  func _instantiate_gameplay(should_load: bool) -> void:
  	main_node = MAIN_SCENE.instantiate()
  	add_child(main_node)
  	if menu_panel != null:
  		menu_panel.visible = false
  	_poll_for_playable_started(should_load)

  func _poll_for_playable_started(should_load: bool) -> void:
  	if main_node == null:
  		return
  	playable_instance = main_node.playable_instance
  	if playable_instance == null or not playable_instance.playable_started:
  		call_deferred("_poll_for_playable_started", should_load)
  		return
  	if not playable_instance.return_to_title_requested.is_connected(_on_gameplay_return_to_title):
  		playable_instance.return_to_title_requested.connect(_on_gameplay_return_to_title)
  	if should_load:
  		playable_instance.request_load()

  func _on_title_quit() -> void:
  	get_tree().quit()

  func _on_gameplay_return_to_title() -> void:
  	if main_node != null and is_instance_valid(main_node):
  		main_node.queue_free()
  	main_node = null
  	playable_instance = null
  	if menu_panel != null and is_instance_valid(menu_panel):
  		menu_panel.queue_free()
  	menu_panel = null
  	_build_title_ui()

  func _on_menu_changed(_new_menu_id: String, _previous_menu_id: String) -> void:
  	_refresh_panel()

  func _on_focus_changed(_new_index: int) -> void:
  	_refresh_panel()

  func _refresh_panel() -> void:
  	if menu_panel == null or menu_state == null:
  		return
  	var current_menu: String = menu_state.get_current_menu()
  	if current_menu.is_empty():
  		menu_panel.visible = false
  		return
  	menu_panel.visible = true
  	var lines := PackedStringArray()
  	var items: Array = menu_state.get_items(current_menu)
  	for index in range(items.size()):
  		var item: Dictionary = items[index]
  		var item_id: String = str(item.get("id", ""))
  		var label_text: String = str(item.get("label", item_id))
  		var prefix: String = "> " if index == menu_state.get_focus_index() else "  "
  		var enabled_suffix: String = "" if menu_state.is_item_enabled(current_menu, item_id) else " (disabled)"
  		lines.append(prefix + label_text + enabled_suffix)
  	menu_panel.set_content("The Synaptic Sea", lines)
  ```

  This is the final, corrected version of title_main.gd -- New Game passes should_load=false, Continue passes should_load=true, and BOTH paths connect return_to_title_requested inside the SAME polling helper (_poll_for_playable_started), so the signal is reliably wired regardless of which path was taken.

- [ ] 4.2 Create scenes/title_main.tscn:
  ```
  [gd_scene load_steps=2 format=3 uid="uid://synaptic_sea_title_main"]

  [ext_resource type="Script" path="res://scripts/title_main.gd" id="1_title"]

  [node name="TitleMain" type="Node"]
  script = ExtResource("1_title")
  ```

- [ ] 4.3 Swap project.godot's run/main_scene line. Read the current line first:

  grep -n "run/main_scene" project.godot

  Old (line 15):
  ```
  run/main_scene="res://scenes/main.tscn"
  ```
  New:
  ```
  run/main_scene="res://scenes/title_main.tscn"
  ```
  This is the ONLY line in project.godot this plan touches -- do not reformat or reorder any other line in the file.

- [ ] 4.4 Validate the new scene parses. Task 5 has not landed yet, so PlayableGeneratedShip.return_to_title_requested does not exist yet -- _poll_for_playable_started's .connect(...) call will raise at runtime if a New Game/Continue is actually driven through to that line before Task 5 lands. The script itself must still PARSE cleanly. Run a quick boot-and-quit check:
  ```
  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --quit-after 1
  ```
  Inspect stdout/stderr for parse errors referencing title_main.gd or title_main.tscn. A runtime error about a missing return_to_title_requested signal at THIS point (before Task 5) is expected and acceptable -- do not attempt to fix it in this task; Task 5 supplies the signal. Do not drive an actual New-Game/Continue click yet -- that is Task 6's job, after Task 5 lands.

- [ ] 4.5 Commit.

  ```
  git add scripts/title_main.gd scenes/title_main.tscn project.godot
  git commit -m "feat: title screen bootstrap (title_main.tscn/gd); project.godot main-scene swap"
  ```

---

### Task 5: return_to_title_requested signal + pause-menu quit_main rewire

**Files:** Modify scripts/procgen/playable_generated_ship.gd (add signal near line 111-114; _on_ui_quit_requested at line 4505)

**Interfaces:**
- Produces: signal return_to_title_requested on PlayableGeneratedShip -- consumed by Task 4's title_main.gd (_poll_for_playable_started's .connect(_on_gameplay_return_to_title) call, already written in Task 4) and Task 10's Save & Exit handler.
- Consumes: MenuCoordinator.quit_requested signal (existing, scripts/ui/menu_coordinator.gd:8, emitted from _confirm_current_item's pause_menu.quit_main arm at line 323 -- unchanged in this task).

**Steps:**

- [ ] 5.1 Add the new signal. Read the current signal block first:

  grep -n "^signal " "scripts/procgen/playable_generated_ship.gd"

  Old:
  ```gdscript
  signal playable_ready(summary: Dictionary)
  signal playable_failed(reason: String)
  signal playable_interaction_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String)
  signal playable_slice_completed(summary: Dictionary)
  ```
  New:
  ```gdscript
  signal playable_ready(summary: Dictionary)
  signal playable_failed(reason: String)
  signal playable_interaction_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String)
  signal playable_slice_completed(summary: Dictionary)
  ## ADR-0043: emitted when the player chooses to leave gameplay back to the
  ## title screen (pause menu "Quit to Main Menu" or Save & Exit). title_main.gd
  ## connects to this on every gameplay instantiation (New Game and Continue
  ## both wire it via _poll_for_playable_started).
  signal return_to_title_requested
  ```

- [ ] 5.2 Rewire _on_ui_quit_requested. Read the current body first:

  grep -n -A 3 "^func _on_ui_quit_requested" "scripts/procgen/playable_generated_ship.gd"

  Old:
  ```gdscript
  func _on_ui_quit_requested() -> void:
  	if is_instance_valid(menu_coordinator):
  		menu_coordinator.open_main_menu()
  ```
  New:
  ```gdscript
  func _on_ui_quit_requested() -> void:
  	# ADR-0043: "Quit to Main Menu" now really returns to the title screen
  	# instead of reopening the in-scene main_menu overlay (the old stub
  	# behavior -- there was no real title/quit path before this domain).
  	emit_signal("return_to_title_requested")
  ```

- [ ] 5.3 Confirm main_menu's own "quit" item (the in-scene overlay that opens automatically at the end of _build_runtime_nodes via menu_coordinator.open_main_menu() at line 4103, still present and UNCHANGED -- this is a separate, pre-existing surface from the new title screen and out of scope to remove per spec 3.1's "main.tscn UNCHANGED") also routes through quit_requested -> _on_ui_quit_requested. This is correct and requires no code change -- read-only confirmation:

  grep -n "quit_requested.emit\|\"quit\": quit_requested" "scripts/ui/menu_coordinator.gd"

  Both main_menu.quit and pause_menu.quit_main already emit the same quit_requested signal (_confirm_current_item lines 315 and 323), which now correctly triggers return_to_title_requested on PlayableGeneratedShip for either overlay. No menu_coordinator.gd change needed in this task.

- [ ] 5.4 Boot-smoke sanity check: confirm the file still parses and the signal is reachable via any existing lightweight main-scene smoke, e.g.:

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/main_coherent_boot_smoke.gd

  Confirm its existing marker still prints and no new ERROR/WARNING appears.

- [ ] 5.5 Commit.

  ```
  git add scripts/procgen/playable_generated_ship.gd
  git commit -m "feat: return_to_title_requested signal; rewire pause-menu quit_main to leave gameplay"
  ```

---

### Task 6: title_screen_flow_smoke.gd -- New Game / Continue / Quit-signal / teardown-reinstantiate

**Files:** Create scripts/validation/title_screen_flow_smoke.gd

**Interfaces:**
- Consumes: scenes/title_main.tscn (Task 4), PlayableGeneratedShip.return_to_title_requested (Task 5), PlayableGeneratedShip.request_load()/request_save() (existing).
- Produces: nothing new -- this is a pure verification smoke.

**Steps:**

- [ ] 6.1 Create scripts/validation/title_screen_flow_smoke.gd:
  ```gdscript
  extends SceneTree

  ## ADR-0043 title screen flow smoke: boots scenes/title_main.tscn (the new
  ## run/main_scene), drives New Game to a live playable slice, drives
  ## return-to-title (pause menu quit_main -> return_to_title_requested),
  ## then drives Continue against a pre-seeded world.json, and finally
  ## drives the Quit path's signal wiring. Includes the teardown/
  ## reinstantiate double-boot check (Risk 2): a second PlayableGeneratedShip
  ## must cleanly reach playable_started in the SAME process after the first
  ## is queue_free()'d.
  ##
  ## Pass marker:
  ##   TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true

  const TITLE_SCENE: PackedScene = preload("res://scenes/title_main.tscn")
  const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
  const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
  const TIMEOUT_FRAMES: int = 900

  var title_node: Node
  var frame_count: int = 0
  var finished: bool = false
  var _stage: String = "new_game_boot"

  func _initialize() -> void:
  	_wipe_saves()
  	title_node = TITLE_SCENE.instantiate()
  	get_root().add_child(title_node)
  	process_frame.connect(_on_process_frame)

  func _on_process_frame() -> void:
  	if finished:
  		return
  	frame_count += 1
  	if frame_count > TIMEOUT_FRAMES:
  		_fail("timed out in stage=%s" % _stage)
  		return
  	match _stage:
  		"new_game_boot":
  			_drive_new_game()
  		"await_new_game_playable":
  			_await_new_game_playable()
  		"return_to_title":
  			_drive_return_to_title()
  		"await_title_rebuilt":
  			_await_title_rebuilt()
  		"continue_boot":
  			_drive_continue()
  		"await_continue_playable":
  			_await_continue_playable()
  		"quit_signal_check":
  			_drive_quit_signal()
  ```

  ```gdscript
  func _drive_new_game() -> void:
  	if title_node.menu_state == null:
  		return
  	if title_node.menu_state.get_current_menu() != "main_menu":
  		return
  	# Move cursor to "start" (index 0 per menu_definitions.json ordering) and confirm.
  	title_node._confirm()  # focus_index defaults to 0 == "start"
  	_stage = "await_new_game_playable"

  func _await_new_game_playable() -> void:
  	var playable: PlayableGeneratedShip = title_node.playable_instance
  	if playable == null or not playable.playable_started:
  		return
  	# Save a real world.json through the live instance so Continue (later
  	# stage, after a fresh title rebuild) has something to load.
  	if not playable.request_save():
  		_fail("request_save failed after New Game boot")
  		return
  	_stage = "return_to_title"

  func _drive_return_to_title() -> void:
  	var playable: PlayableGeneratedShip = title_node.playable_instance
  	if playable == null:
  		_fail("playable_instance missing before return-to-title drive")
  		return
  	# Simulate the pause-menu "Quit to Main Menu" path directly through the
  	# signal (the exact producer _on_ui_quit_requested now emits).
  	playable.emit_signal("return_to_title_requested")
  	_stage = "await_title_rebuilt"

  func _await_title_rebuilt() -> void:
  	if title_node.main_node != null:
  		return  # still tearing down
  	if title_node.menu_state == null or title_node.menu_state.get_current_menu() != "main_menu":
  		return
  	_stage = "continue_boot"

  func _drive_continue() -> void:
  	if not title_node.menu_state.is_item_enabled("main_menu", "continue"):
  		_fail("Continue should be enabled after a fresh world.json save")
  		return
  	title_node.menu_state.set_focus_index(1)  # "continue" is index 1
  	title_node._confirm()
  	_stage = "await_continue_playable"

  func _await_continue_playable() -> void:
  	var playable: PlayableGeneratedShip = title_node.playable_instance
  	if playable == null or not playable.playable_started:
  		return
  	# Continue's request_load() call happens synchronously inside
  	# _poll_for_playable_started once playable_started flips true; by the
  	# time we observe playable_started here it has already fired. Confirm
  	# the world save is intact (freeze-not-delete means load did not
  	# consume it).
  	if not playable.get_save_load_service().has_save():
  		_fail("world save missing after Continue")
  		return
  	_stage = "quit_signal_check"

  func _drive_quit_signal() -> void:
  	var playable: PlayableGeneratedShip = title_node.playable_instance
  	if playable == null:
  		_fail("playable_instance missing before quit-signal drive")
  		return
  	var received: bool = false
  	var cb := func(): received = true
  	playable.return_to_title_requested.connect(cb)
  	playable.emit_signal("return_to_title_requested")
  	if not received:
  		_fail("return_to_title_requested signal did not fire its own listener")
  		return
  	finished = true
  	print("TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true")
  	_cleanup_and_quit(0)

  func _wipe_saves() -> void:
  	var service := SaveLoadServiceScript.new()
  	service.delete_current_run()
  	var resolver := PermadeathResolverScript.new()
  	resolver.clear_death("world")

  func _fail(reason: String) -> void:
  	if finished:
  		return
  	finished = true
  	push_error("TITLE SCREEN FLOW FAIL reason=%s" % reason)
  	_cleanup_and_quit(1)

  func _cleanup_and_quit(code: int) -> void:
  	_wipe_saves()
  	if title_node != null and is_instance_valid(title_node):
  		title_node.queue_free()
  	call_deferred("_do_quit", code)

  func _do_quit(code: int) -> void:
  	quit(code)
  ```

- [ ] 6.2 Run the smoke and iterate on any timing/staging bugs (the stage machine above is a first-pass sequencing; if _confirm() or menu_state field access needs adjustment because title_main.gd's actual field names differ slightly from Task 4's final code, fix the SMOKE to match the REAL title_main.gd public surface -- do not change title_main.gd's already-committed behavior to fit the smoke).

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/title_screen_flow_smoke.gd

  Expect: TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true with no unexpected ERROR/WARNING lines. Pay special attention to the Risk-2 teardown/reinstantiate check (this stage machine drives exactly this: New Game boots a PlayableGeneratedShip, it's freed via return_to_title_requested, then Continue boots a SECOND PlayableGeneratedShip in the same process) -- if the second boot ever hangs or errors, that is the highest-uncertainty risk in the whole plan; debug it here, not later.

- [ ] 6.3 Commit.

  ```
  git add scripts/validation/title_screen_flow_smoke.gd
  git commit -m "test: title screen flow smoke (new game, continue, quit signal, teardown/reinstantiate)"
  ```

---

### Task 7: Slot-screen interactive arm in menu_coordinator.gd

**Files:** Modify scripts/ui/menu_coordinator.gd (interactive set at line 174; bind_meta_screens at line 452; _refresh_save_load_panel at line 517; meta_screen_move_selection/meta_screen_confirm at line 578/595)

**Interfaces:**
- Consumes: SaveLoadMenu.refresh() -> Array (existing, scripts/ui/save_load_menu.gd:16), SaveLoadMenu.select_slot_for_load(slot_id) -> Object (existing, line 21), SaveLoadMenu.confirm_save_to_slot(slot_id, snapshot, slot_kind, display_name) -> bool (existing, line 26), SaveLoadMenu.confirm_delete(slot_id) -> bool (existing, line 36), SaveSlotState.is_world()/is_manual()/is_auto()/is_quick()/frozen (existing, scripts/systems/save_slot_state.gd).
- Produces: MenuCoordinator.bind_meta_screens(..., p_unlock_registry = null, p_snapshot_builder: Callable = Callable()) -- 12th parameter appended at the end. MenuCoordinator.meta_screen_move_selection/meta_screen_confirm gain a "save_load" match arm. MenuCoordinator._pending_delete_slot_id / _save_load_pending_verb new private state.

**Steps:**

- [ ] 7.1 Find every call site of bind_meta_screens before changing its signature.

  grep -rn "bind_meta_screens(" "scripts/" "docs/"

  Expected hits: scripts/procgen/playable_generated_ship.gd:4087 (the real call site) and scripts/validation/meta_screens_interactive_smoke.gd:74 (the smoke call site, verified: _coord.bind_meta_screens(ach, _audio, tree, prog, hub, meta, loc, build_meta, slmenu, null, reg)). Update ANY other hit found by the grep the same way as these two examples below -- do not skip a hit because it "looks similar", verify each one's exact argument list against the new signature.

- [ ] 7.2 Add "save_load" to the interactive-screen set in handle_ui_input. Read current text first:

  grep -n -A 10 "if _active_meta_screen in" "scripts/ui/menu_coordinator.gd"

  Old:
  ```gdscript
  		if _active_meta_screen in ["hub_upgrades", "skill_tree", "class"]:
  			if event.is_action_pressed("ui_up"):
  				meta_screen_move_selection(-1)
  				return true
  			if event.is_action_pressed("ui_down"):
  				meta_screen_move_selection(1)
  				return true
  			if event.is_action_pressed("ui_accept"):
  				meta_screen_confirm()
  				return true
  		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
  				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
  				or event.is_action_pressed("ui_accept"):
  			return true
  		return false
  ```
  New:
  ```gdscript
  		if _active_meta_screen in ["hub_upgrades", "skill_tree", "class", "save_load"]:
  			if event.is_action_pressed("ui_up"):
  				meta_screen_move_selection(-1)
  				return true
  			if event.is_action_pressed("ui_down"):
  				meta_screen_move_selection(1)
  				return true
  			if event.is_action_pressed("ui_accept"):
  				_last_meta_screen_confirm_result = meta_screen_confirm()
  				return true
  			if _active_meta_screen == "save_load":
  				if event.is_action_pressed("ui_left"):
  					_cycle_save_load_verb(-1)
  					return true
  				if event.is_action_pressed("ui_right"):
  					_cycle_save_load_verb(1)
  					return true
  		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
  				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
  				or event.is_action_pressed("ui_accept"):
  			return true
  		return false
  ```
  NOTE: this replacement already includes the "_last_meta_screen_confirm_result" assignment that Task 8.2 needs -- write it now (do not defer to Task 8) so this file only needs ONE edit to this exact block across the whole plan. "_last_meta_screen_confirm_result" itself is declared in step 7.3 below.

- [ ] 7.3 Add the new private state vars near the other Domain-6/slot-screen state. Read current context:

  grep -n "_meta_bound: bool = false" "scripts/ui/menu_coordinator.gd"

  Old:
  ```gdscript
  var save_load_menu                       # SaveLoadMenu (RefCounted model)
  var _save_load_panel: RichTextLabel
  var _meta_panels: Dictionary = {}        # screen_id -> CanvasItem (visibility-toggled)
  var _active_meta_screen: String = ""     # "" when the records list (or no menu) is shown
  var _meta_bound: bool = false
  ```
  New:
  ```gdscript
  var save_load_menu                       # SaveLoadMenu (RefCounted model)
  var _save_load_panel: RichTextLabel
  var _meta_panels: Dictionary = {}        # screen_id -> CanvasItem (visibility-toggled)
  var _active_meta_screen: String = ""     # "" when the records list (or no menu) is shown
  var _meta_bound: bool = false
  # Domain 8 (ADR-0043): slot-screen cursor/verb state. Row index reuses the
  # existing menu focus concept but the save_load screen is not a MenuState
  # menu -- it is a meta-screen with its OWN cursor over SaveLoadMenu.refresh()
  # rows, so it needs its own index.
  var _save_load_row_index: int = 0
  var _save_load_pending_verb: String = ""
  var _pending_delete_slot_id: String = ""
  var _snapshot_builder: Callable = Callable()
  # Domain 8: last Dictionary returned by a save_load meta_screen_confirm()
  # dispatched through handle_ui_input's ui_accept branch. PlayableGeneratedShip
  # reads this via get_last_meta_screen_confirm_result() to notice a slot Load
  # result it must apply itself (this Node owns no gameplay state).
  var _last_meta_screen_confirm_result: Dictionary = {}
  ```

- [ ] 7.4 Extend bind_meta_screens's signature with p_snapshot_builder: Callable and store it. Read current signature + body tail first:

  grep -n -A 5 "^func bind_meta_screens" "scripts/ui/menu_coordinator.gd"

  Old:
  ```gdscript
  func bind_meta_screens(p_achievement_state, p_audio_manager, p_skill_tree_state, p_player_progression, p_hub_upgrade_state, p_meta_progression_state, p_localization_catalog, p_build_metadata_state, p_save_load_menu, p_a11y, p_unlock_registry = null) -> void:
  ```
  New:
  ```gdscript
  func bind_meta_screens(p_achievement_state, p_audio_manager, p_skill_tree_state, p_player_progression, p_hub_upgrade_state, p_meta_progression_state, p_localization_catalog, p_build_metadata_state, p_save_load_menu, p_a11y, p_unlock_registry = null, p_snapshot_builder: Callable = Callable()) -> void:
  ```
  And near the end of the function body (just before _refresh_save_load_panel() / _meta_bound = true), read:

  grep -n -A 4 "_refresh_save_load_panel()" "scripts/ui/menu_coordinator.gd"

  Old:
  ```gdscript
  	_refresh_save_load_panel()
  	_meta_bound = true
  ```
  New:
  ```gdscript
  	_snapshot_builder = p_snapshot_builder
  	_refresh_save_load_panel()
  	_meta_bound = true
  ```

- [ ] 7.5 Update the FIRST call site (playable_generated_ship.gd:4087), passing _build_run_snapshot as the new trailing arg. Read current text first:

  grep -n -A 12 "menu_coordinator.bind_meta_screens(" "scripts/procgen/playable_generated_ship.gd"

  Old:
  ```gdscript
  	menu_coordinator.bind_meta_screens(
  		achievement_state,
  		audio_manager,
  		skill_tree_state,
  		player_progression,
  		hub_upgrade_state,
  		meta_progression_state,
  		localization_catalog,
  		build_metadata_state,
  		save_load_menu,
  		accessibility_settings,
  		unlock_registry,
  	)
  ```
  New:
  ```gdscript
  	menu_coordinator.bind_meta_screens(
  		achievement_state,
  		audio_manager,
  		skill_tree_state,
  		player_progression,
  		hub_upgrade_state,
  		meta_progression_state,
  		localization_catalog,
  		build_metadata_state,
  		save_load_menu,
  		accessibility_settings,
  		unlock_registry,
  		_build_run_snapshot,
  	)
  ```

- [ ] 7.6 Update the SECOND call site (scripts/validation/meta_screens_interactive_smoke.gd:74). Read current text first:

  grep -n "bind_meta_screens(" "scripts/validation/meta_screens_interactive_smoke.gd"

  Old:
  ```gdscript
  	_coord.bind_meta_screens(ach, _audio, tree, prog, hub, meta, loc, build_meta, slmenu, null, reg)
  ```
  New:
  ```gdscript
  	_coord.bind_meta_screens(ach, _audio, tree, prog, hub, meta, loc, build_meta, slmenu, null, reg, Callable())
  ```
  (This smoke does not exercise the slot screen's Save verb, so an empty Callable() is correct and safe -- meta_screen_confirm's save arm below null-guards on _snapshot_builder.is_valid().)

- [ ] 7.7 Add const PermadeathResolverScriptForCoordinator AND const SaveSlotStateScriptForCoordinator next to the other const ...Script := preload(...) declarations at the top of the file. The second const is required by the empty-manual-slot row synthesis in step 7.8 below (menu_coordinator.gd does not currently preload save_slot_state.gd at all -- verified: grep -n "SaveSlotState" scripts/ui/menu_coordinator.gd only matches a comment, not a preload). Read current preload block first:

  grep -n "const CreditsScreenScript\|PermadeathResolverScript\|SaveSlotState" "scripts/ui/menu_coordinator.gd"

  Old:
  ```gdscript
  const CreditsScreenScript := preload("res://scripts/ui/credits_screen.gd")
  ```
  New:
  ```gdscript
  const CreditsScreenScript := preload("res://scripts/ui/credits_screen.gd")
  const PermadeathResolverScriptForCoordinator := preload("res://scripts/systems/permadeath_resolver.gd")
  const SaveSlotStateScriptForCoordinator := preload("res://scripts/systems/save_slot_state.gd")
  ```
  (Named distinctly to avoid any future collision with a differently-named preload of the same script elsewhere in this file; verify with the grep above that no such const already exists under a different name before adding -- if one does, reuse it instead of adding a duplicate.)

- [ ] 7.8 Replace _refresh_save_load_panel with a cursor/verb-aware renderer. Read current body first (lines 517-543). Old:
  ```gdscript
  func _refresh_save_load_panel() -> void:
  	if not is_instance_valid(_save_load_panel):
  		return
  	var lines := PackedStringArray()
  	lines.append("SAVE / LOAD")
  	var rows: Array = []
  	if save_load_menu != null:
  		var refreshed: Variant = save_load_menu.refresh()
  		if typeof(refreshed) == TYPE_ARRAY:
  			rows = refreshed
  	if rows.is_empty():
  		lines.append("(no save slots)")
  	else:
  		for row in rows:
  			var d: Dictionary = {}
  			if typeof(row) == TYPE_DICTIONARY:
  				d = row
  			elif row != null and (row as Object).has_method("to_dict"):
  				d = (row as Object).to_dict()
  			if d.is_empty():
  				lines.append("- %s" % str(row))
  			else:
  				lines.append("- %s | %s" % [str(d.get("slot_id", "?")), str(d.get("display_name", ""))])
  	_save_load_panel.text = "\n".join(lines)
  ```
  New:
  ```gdscript
  func _refresh_save_load_panel() -> void:
  	if not is_instance_valid(_save_load_panel):
  		return
  	var lines := PackedStringArray()
  	lines.append("SAVE / LOAD")
  	var rows: Array = _save_load_rows()
  	if rows.is_empty():
  		lines.append("(no save slots)")
  	else:
  		if _save_load_row_index >= rows.size():
  			_save_load_row_index = rows.size() - 1
  		if _save_load_row_index < 0:
  			_save_load_row_index = 0
  		for index in range(rows.size()):
  			var row = rows[index]
  			var prefix: String = "> " if index == _save_load_row_index else "  "
  			lines.append(prefix + _save_load_row_line(row, index))
  	_save_load_panel.text = "\n".join(lines)

  ## Normalizes SaveLoadMenu.refresh() rows (real SaveSlotState instances,
  ## one per slot PRESENT in the on-disk index) plus synthesized placeholder
  ## SaveSlotState rows for every MANUAL_SLOT_IDS entry that has no row yet
  ## (an empty manual slot the player has never saved to). This is required
  ## so the player can make their FIRST manual save from the slot screen --
  ## spec 3.2's "Empty manual slot (slot_01..06): [Save]" verb model demands
  ## a cursor-able row for empty slots, not just filled ones. save_load_menu.gd
  ## itself is NOT touched (spec 4: "No signature changes") -- the synthesis
  ## happens entirely here at the coordinator level, using the SAME
  ## SaveSlotState class SaveLoadMenu.refresh() already returns (a plain
  ## RefCounted with public vars -- scripts/systems/save_slot_state.gd), so
  ## every existing accessor (is_manual()/is_world()/.frozen/.display_name/
  ## .slot_id) behaves identically on a synthetic row as on a real one; no
  ## duck-typed dict and no extra guarding is needed anywhere else in this
  ## file. Order: real rows first (in SaveLoadMenu.refresh()'s existing
  ## saved_at-desc order), then one synthetic row per empty manual slot id,
  ## in MANUAL_SLOT_IDS order.
  func _save_load_rows() -> Array:
  	var rows: Array = []
  	if save_load_menu != null:
  		var refreshed: Variant = save_load_menu.refresh()
  		if typeof(refreshed) == TYPE_ARRAY:
  			rows = (refreshed as Array).duplicate()
  	var present_manual_ids: Dictionary = {}
  	for row in rows:
  		if row != null and bool(row.is_manual()):
  			present_manual_ids[String(row.slot_id)] = true
  	for slot_id in SaveSlotStateScriptForCoordinator.MANUAL_SLOT_IDS:
  		if not present_manual_ids.has(String(slot_id)):
  			rows.append(_synthesize_empty_manual_row(String(slot_id)))
  	return rows

  ## Builds a placeholder SaveSlotState for a manual slot id that has no
  ## on-disk row yet. Every field is a safe, never-frozen, empty-payload
  ## default so it passes through _save_load_row_line/_valid_verbs_for_row/
  ## the delete-arm/load-arm guards exactly like a real row would -- the
  ## only special-cased field is slot_kind (stamped SLOT_KIND_MANUAL so
  ## is_manual() reads true) and slot_id/display_name (so the row is
  ## identifiable and selectable).
  func _synthesize_empty_manual_row(slot_id: String):
  	var row = SaveSlotStateScriptForCoordinator.new()
  	row.slot_id = slot_id
  	row.slot_kind = SaveSlotStateScriptForCoordinator.SLOT_KIND_MANUAL
  	row.display_name = ""
  	row.frozen = false
  	row.corrupt = false
  	return row

  func _save_load_row_line(row, index: int) -> String:
  	if row == null:
  		return "?"
  	var slot_id: String = String(row.slot_id)
  	var display_name: String = String(row.display_name)
  	if bool(row.frozen):
  		var resolver := PermadeathResolverScriptForCoordinator.new()
  		var epitaph: Dictionary = resolver.load_epitaph(slot_id)
  		return "%s | DEAD -- %s" % [slot_id, str(epitaph.get("epitaph", "unknown"))]
  	if bool(row.is_manual()) and display_name.is_empty() and not _save_load_row_has_payload(row):
  		var empty_verb_text: String = ""
  		if index == _save_load_row_index and not _save_load_pending_verb.is_empty():
  			empty_verb_text = " | verb=%s" % _save_load_pending_verb
  		return "%s -- empty%s" % [slot_id, empty_verb_text]
  	var verb_text: String = ""
  	if index == _save_load_row_index and not _save_load_pending_verb.is_empty():
  		verb_text = " | verb=%s" % _save_load_pending_verb
  		if _pending_delete_slot_id == slot_id and _save_load_pending_verb == "Delete":
  			verb_text = " | verb=Delete (confirm again to delete)"
  	return "%s | %s%s" % [slot_id, display_name, verb_text]

  ## True when a row came from SaveLoadMenu.refresh() (a real on-disk slot)
  ## rather than being one of this coordinator's synthesized empty-manual
  ## placeholders. Synthesized rows always have saved_at_epoch == 0 AND
  ## schema_version == "" (a real save_to_slot call always stamps both --
  ## see SaveLoadService._index_run_slot); this is a safe, cheap
  ## distinguishing check that does not require tracking row identity.
  func _save_load_row_has_payload(row) -> bool:
  	return int(row.saved_at_epoch) != 0 or not String(row.schema_version).is_empty()
  ```

- [ ] 7.9 Extend meta_screen_move_selection with the "save_load" arm. Read current body first (lines 578-591). Old:
  ```gdscript
  func meta_screen_move_selection(direction: int) -> void:
  	match _active_meta_screen:
  		"hub_upgrades":
  			if is_instance_valid(hub_upgrade_panel):
  				hub_upgrade_panel.move_selection(direction)
  				hub_upgrade_panel.render()
  		"skill_tree":
  			if is_instance_valid(skill_tree_panel):
  				skill_tree_panel.move_selection(direction)
  				skill_tree_panel.render()
  		"class":
  			if is_instance_valid(class_panel):
  				class_panel.move_selection(direction)
  				class_panel.render()
  ```
  New:
  ```gdscript
  func meta_screen_move_selection(direction: int) -> void:
  	match _active_meta_screen:
  		"hub_upgrades":
  			if is_instance_valid(hub_upgrade_panel):
  				hub_upgrade_panel.move_selection(direction)
  				hub_upgrade_panel.render()
  		"skill_tree":
  			if is_instance_valid(skill_tree_panel):
  				skill_tree_panel.move_selection(direction)
  				skill_tree_panel.render()
  		"class":
  			if is_instance_valid(class_panel):
  				class_panel.move_selection(direction)
  				class_panel.render()
  		"save_load":
  			var rows: Array = _save_load_rows()
  			if rows.is_empty():
  				return
  			_save_load_row_index = clampi(_save_load_row_index + direction, 0, rows.size() - 1)
  			_save_load_pending_verb = ""
  			_pending_delete_slot_id = ""
  			_refresh_save_load_panel()
  ```

- [ ] 7.10 Extend meta_screen_confirm with the "save_load" arm (whole-function replacement -- every other arm is byte-identical to today, reproduced in full because GDScript match statements are one function). Read current body first (lines 595-627). Old:
  ```gdscript
  func meta_screen_confirm() -> Dictionary:
  	match _active_meta_screen:
  		"hub_upgrades":
  			var sel: String = hub_upgrade_panel.get_selected_id() if is_instance_valid(hub_upgrade_panel) else ""
  			var ok: bool = false
  			if _hub_upgrade_state != null and _meta_progression_state != null and not sel.is_empty():
  				if _hub_upgrade_state.purchase(sel, _meta_progression_state):
  					ok = _meta_progression_state.save_to_disk()
  			if is_instance_valid(hub_upgrade_panel):
  				hub_upgrade_panel.render()
  			return {"screen": "hub_upgrades", "action": "purchase", "ok": ok, "detail": sel}
  		"skill_tree":
  			var sel_s: String = skill_tree_panel.get_selected_id() if is_instance_valid(skill_tree_panel) else ""
  			var ok_s: bool = false
  			if _skill_tree_state != null and not sel_s.is_empty():
  				var chk: Dictionary = _skill_tree_state.can_unlock(sel_s, _player_progression, _meta_progression_state)
  				if bool(chk.get("can", false)):
  					ok_s = _skill_tree_state.unlock(sel_s)
  			if is_instance_valid(skill_tree_panel):
  				skill_tree_panel.render()
  			return {"screen": "skill_tree", "action": "unlock", "ok": ok_s, "detail": sel_s}
  		"class":
  			var sel_c: String = class_panel.get_selected_id() if is_instance_valid(class_panel) else ""
  			var ok_c: bool = false
  			if _meta_progression_state != null and not sel_c.is_empty() and class_panel.is_available(sel_c):
  				_meta_progression_state.set_selected_class(sel_c)
  				ok_c = _meta_progression_state.save_to_disk()
  				if is_instance_valid(class_panel):
  					class_panel.set_selected_class(sel_c)
  			if is_instance_valid(class_panel):
  				class_panel.render()
  			return {"screen": "class", "action": "select", "ok": ok_c, "detail": sel_c}
  	return {"screen": _active_meta_screen, "action": "none", "ok": false, "detail": ""}
  ```

  New:
  ```gdscript
  func meta_screen_confirm() -> Dictionary:
  	match _active_meta_screen:
  		"hub_upgrades":
  			var sel: String = hub_upgrade_panel.get_selected_id() if is_instance_valid(hub_upgrade_panel) else ""
  			var ok: bool = false
  			if _hub_upgrade_state != null and _meta_progression_state != null and not sel.is_empty():
  				if _hub_upgrade_state.purchase(sel, _meta_progression_state):
  					ok = _meta_progression_state.save_to_disk()
  			if is_instance_valid(hub_upgrade_panel):
  				hub_upgrade_panel.render()
  			return {"screen": "hub_upgrades", "action": "purchase", "ok": ok, "detail": sel}
  		"skill_tree":
  			var sel_s: String = skill_tree_panel.get_selected_id() if is_instance_valid(skill_tree_panel) else ""
  			var ok_s: bool = false
  			if _skill_tree_state != null and not sel_s.is_empty():
  				var chk: Dictionary = _skill_tree_state.can_unlock(sel_s, _player_progression, _meta_progression_state)
  				if bool(chk.get("can", false)):
  					ok_s = _skill_tree_state.unlock(sel_s)
  			if is_instance_valid(skill_tree_panel):
  				skill_tree_panel.render()
  			return {"screen": "skill_tree", "action": "unlock", "ok": ok_s, "detail": sel_s}
  		"class":
  			var sel_c: String = class_panel.get_selected_id() if is_instance_valid(class_panel) else ""
  			var ok_c: bool = false
  			if _meta_progression_state != null and not sel_c.is_empty() and class_panel.is_available(sel_c):
  				_meta_progression_state.set_selected_class(sel_c)
  				ok_c = _meta_progression_state.save_to_disk()
  				if is_instance_valid(class_panel):
  					class_panel.set_selected_class(sel_c)
  			if is_instance_valid(class_panel):
  				class_panel.render()
  			return {"screen": "class", "action": "select", "ok": ok_c, "detail": sel_c}
  		"save_load":
  			return _confirm_save_load_row()
  	return {"screen": _active_meta_screen, "action": "none", "ok": false, "detail": ""}

  ## Domain 8 (ADR-0043) slot-screen confirm dispatch. Returns
  ## {screen:"save_load", action, ok, detail, snapshot} -- snapshot is only
  ## populated on a successful Load action; the RunSnapshot cannot be applied
  ## here (this Node has no gameplay state), so the caller (PlayableGeneratedShip's
  ## _input dispatch site) notices action=="load" and ok==true and calls
  ## apply_manual_slot(snapshot) itself (Task 8).
  func _confirm_save_load_row() -> Dictionary:
  	var rows: Array = _save_load_rows()
  	if rows.is_empty() or _save_load_row_index >= rows.size():
  		return {"screen": "save_load", "action": "none", "ok": false, "detail": ""}
  	var row = rows[_save_load_row_index]
  	var slot_id: String = String(row.slot_id)
  	if bool(row.frozen):
  		return {"screen": "save_load", "action": "none", "ok": false, "detail": slot_id}
  	var verbs: Array = _valid_verbs_for_row(row)
  	if verbs.is_empty():
  		return {"screen": "save_load", "action": "none", "ok": false, "detail": slot_id}
  	if _save_load_pending_verb.is_empty():
  		_save_load_pending_verb = String(verbs[0])
  		_refresh_save_load_panel()
  		return {"screen": "save_load", "action": "arm", "ok": true, "detail": slot_id}
  	var verb: String = _save_load_pending_verb
  	if verb == "Delete":
  		if _pending_delete_slot_id != slot_id:
  			_pending_delete_slot_id = slot_id
  			_refresh_save_load_panel()
  			return {"screen": "save_load", "action": "delete_armed", "ok": true, "detail": slot_id}
  		var deleted: bool = save_load_menu.confirm_delete(slot_id)
  		_pending_delete_slot_id = ""
  		_save_load_pending_verb = ""
  		_refresh_save_load_panel()
  		return {"screen": "save_load", "action": "delete", "ok": deleted, "detail": slot_id}
  	if verb == "Save":
  		var display_name: String = String(row.display_name) if not String(row.display_name).is_empty() else slot_id
  		var ok: bool = false
  		if _snapshot_builder.is_valid():
  			var snap = _snapshot_builder.call()
  			if snap != null:
  				ok = save_load_menu.confirm_save_to_slot(slot_id, snap, "manual", display_name)
  		_save_load_pending_verb = ""
  		_refresh_save_load_panel()
  		return {"screen": "save_load", "action": "save", "ok": ok, "detail": slot_id}
  	if verb == "Load":
  		var snapshot = save_load_menu.select_slot_for_load(slot_id)
  		_save_load_pending_verb = ""
  		_refresh_save_load_panel()
  		return {"screen": "save_load", "action": "load", "ok": snapshot != null, "detail": slot_id, "snapshot": snapshot}
  	return {"screen": "save_load", "action": "none", "ok": false, "detail": slot_id}
  ```

  Also add these two helper functions immediately after _confirm_save_load_row:
  ```gdscript
  ## Verb model per row state (spec 3.2, unconditional -- not deferrable):
  ## empty manual [Save] only; filled manual [Load, Save, Delete]; world row
  ## [Load] only; autosave rows display-only (empty array); frozen rows are
  ## handled before this is called. "Empty manual" is distinguished from
  ## "filled manual" via _save_load_row_has_payload (step 7.8's synthesized
  ## rows never have a saved_at_epoch/schema_version stamp; every real
  ## save_to_slot call always sets both).
  func _valid_verbs_for_row(row) -> Array:
  	if bool(row.is_world()):
  		return ["Load"]
  	if bool(row.is_auto()) or bool(row.is_quick()):
  		return []
  	if bool(row.is_manual()):
  		if not _save_load_row_has_payload(row):
  			# Empty manual slot (never saved to, or this is one of step 7.8's
  			# synthesized placeholder rows): only Save is offered. Load/Delete
  			# on a slot with no payload on disk would be meaningless/unsafe --
  			# select_slot_for_load would return null and confirm_delete would
  			# no-op on a missing file, so excluding them here is not just
  			# cosmetic, it prevents a dead-end verb cycle.
  			return ["Save"]
  		# A filled manual row (real payload on disk): offer the full verb set.
  		return ["Load", "Save", "Delete"]
  	return []

  func _cycle_save_load_verb(direction: int) -> void:
  	var rows: Array = _save_load_rows()
  	if rows.is_empty() or _save_load_row_index >= rows.size():
  		return
  	var row = rows[_save_load_row_index]
  	if bool(row.frozen):
  		return
  	var verbs: Array = _valid_verbs_for_row(row)
  	if verbs.is_empty():
  		return
  	var current_index: int = verbs.find(_save_load_pending_verb)
  	if current_index < 0:
  		current_index = 0
  	else:
  		current_index = wrapi(current_index + direction, 0, verbs.size())
  	_save_load_pending_verb = String(verbs[current_index])
  	_pending_delete_slot_id = ""
  	_refresh_save_load_panel()
  ```

  Also add the getter/clear pair Task 8 needs, right next to get_active_meta_screen():
  ```gdscript
  ## Domain 8 seam: the Dictionary returned by the last meta_screen_confirm()
  ## call driven through handle_ui_input's ui_accept branch. Used by
  ## PlayableGeneratedShip's _input dispatch to notice a slot-screen Load
  ## result (which this Node cannot apply itself -- it has no gameplay state).
  func get_last_meta_screen_confirm_result() -> Dictionary:
  	return _last_meta_screen_confirm_result

  func clear_last_meta_screen_confirm_result() -> void:
  	_last_meta_screen_confirm_result = {}
  ```

  Verification of the spec 3.2 "empty manual slot: [Save] only" requirement, now unconditionally implemented (not deferred): step 7.8's _save_load_rows() synthesizes one placeholder SaveSlotState row for every MANUAL_SLOT_IDS entry absent from SaveLoadMenu.refresh(). _valid_verbs_for_row (above) checks _save_load_row_has_payload BEFORE returning the manual-row verb set, so a synthesized/never-saved row gets exactly ["Save"] and a real/filled row gets ["Load", "Save", "Delete"] -- this is the same function for both cases, distinguished purely by data, so there is no separate "synthetic row" code path to keep in sync. _confirm_save_load_row (above) is unmodified by this fix: it already asks _valid_verbs_for_row for the row's verb set and only ever offers verbs from that list, so an empty row's arm/execute flow naturally only ever reaches the "Save" branch -- Load and Delete are structurally unreachable for an empty row without any additional guard in _confirm_save_load_row itself. The Delete two-step arm (_pending_delete_slot_id) and the Load branch's save_load_menu.select_slot_for_load call are therefore never invoked against a synthetic row, satisfying requirement 4 (two-step-delete/load must not be offered on a synthetic empty row) by construction.

- [ ] 7.11 Reset pending verb/delete-arm state whenever a meta screen closes, so stale arm state doesn't leak into the next save_load visit. Read _close_meta_screen current text:

  grep -n -A 3 "^func _close_meta_screen" "scripts/ui/menu_coordinator.gd"

  Old:
  ```gdscript
  func _close_meta_screen() -> void:
  	_active_meta_screen = ""
  	_refresh_all()
  ```
  New:
  ```gdscript
  func _close_meta_screen() -> void:
  	_active_meta_screen = ""
  	_save_load_pending_verb = ""
  	_pending_delete_slot_id = ""
  	_refresh_all()
  ```

- [ ] 7.12 Run the existing interactive meta-screens smoke to confirm no regression from the bind_meta_screens signature change or the meta_screen_move_selection/meta_screen_confirm edits.

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/meta_screens_interactive_smoke.gd

  Expect: META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true registry_reader=true class_select=true unchanged, with no new ERROR/WARNING.

- [ ] 7.13 Commit.

  ```
  git add scripts/ui/menu_coordinator.gd scripts/procgen/playable_generated_ship.gd scripts/validation/meta_screens_interactive_smoke.gd
  git commit -m "feat: interactive save_load meta-screen (cursor, verb cycling, two-step delete, snapshot_builder seam)"
  ```

---

### Task 8: apply_manual_slot seam + _input/confirm-result dispatch wiring + written-slot tracking

**Files:** Modify scripts/procgen/playable_generated_ship.gd (_apply_run_snapshot at line 6632 stays unchanged; new apply_manual_slot added near it; _input's menu_coordinator.handle_ui_input dispatch block gains load-result handling)

**Interfaces:**
- Consumes: MenuCoordinator.get_last_meta_screen_confirm_result() -> Dictionary (Task 7), MenuCoordinator.clear_last_meta_screen_confirm_result() -> void (Task 7), PlayableGeneratedShip._apply_run_snapshot(snapshot) -> bool (existing, line 6632).
- Produces: PlayableGeneratedShip.apply_manual_slot(snapshot: RunSnapshot) -> bool -- public seam, also directly callable by Task 9's smoke. Populates _manual_slots_written_this_run (declared in Task 1) whenever the slot screen's Save verb succeeds.

**Steps:**

- [ ] 8.1 Add apply_manual_slot immediately after _apply_run_snapshot. First locate the end of _apply_run_snapshot:

  grep -n -A 5 "PLAYABLE SHIP LOADED" "scripts/procgen/playable_generated_ship.gd"

  Old (the tail of _apply_run_snapshot):
  ```gdscript
  	last_saved_snapshot = snapshot
  	_is_reloading = false
  	print("PLAYABLE SHIP LOADED sequence=%d position=(%.2f,%.2f,%.2f)" % [
  		current_objective_sequence,
  		snapshot.player_position[0],
  		snapshot.player_position[1],
  		snapshot.player_position[2],
  	])
  	return true
  ```
  New:
  ```gdscript
  	last_saved_snapshot = snapshot
  	_is_reloading = false
  	print("PLAYABLE SHIP LOADED sequence=%d position=(%.2f,%.2f,%.2f)" % [
  		current_objective_sequence,
  		snapshot.player_position[0],
  		snapshot.player_position[1],
  		snapshot.player_position[2],
  	])
  	return true

  ## ADR-0031/0043 slot-screen seam: apply a manual-slot RunSnapshot onto the
  ## currently-active (already-booted) ship only. Does NOT touch
  ## visited_ships/world_time/dock topology/current_location -- manual slots
  ## are ship-only side-saves, exactly ADR-0031's original text. Returns
  ## true on success; false on a null snapshot or an _apply_run_snapshot
  ## failure (e.g. not yet playable_started).
  func apply_manual_slot(snapshot: RunSnapshot) -> bool:
  	if snapshot == null:
  		return false
  	var applied: bool = _apply_run_snapshot(snapshot)
  	if applied and is_instance_valid(menu_coordinator):
  		menu_coordinator.trigger_tutorial("manual_slot_loaded", "any")
  	return applied
  ```

- [ ] 8.2 Wire the _input dispatch site to notice a "load" result from meta_screen_confirm() (surfaced via MenuCoordinator.get_last_meta_screen_confirm_result(), Task 7) and call apply_manual_slot, and to populate _manual_slots_written_this_run on a successful Save. Read the current post-Task-2 _input text first:

  grep -n -A 10 "if is_instance_valid(menu_coordinator):" "scripts/procgen/playable_generated_ship.gd"

  Old (post-Task-2 state):
  ```gdscript
  	if is_instance_valid(menu_coordinator):
  		if menu_coordinator.handle_ui_input(event):
  			if event.is_action_pressed("ui_open_map"):
  				menu_coordinator.reveal_room(menu_coordinator.map_fog_state.get_tracked_room_id())
  			get_viewport().set_input_as_handled()
  			return
  		for action_name in ["move_forward", "move_back", "move_left", "move_right"]:
  			if event.is_action_pressed(action_name):
  				menu_coordinator.trigger_tutorial("player_moved", "any")
  				break
  ```
  New:
  ```gdscript
  	if is_instance_valid(menu_coordinator):
  		if menu_coordinator.handle_ui_input(event):
  			if event.is_action_pressed("ui_open_map"):
  				menu_coordinator.reveal_room(menu_coordinator.map_fog_state.get_tracked_room_id())
  			_dispatch_save_load_confirm_result(menu_coordinator.get_last_meta_screen_confirm_result())
  			get_viewport().set_input_as_handled()
  			return
  		for action_name in ["move_forward", "move_back", "move_left", "move_right"]:
  			if event.is_action_pressed(action_name):
  				menu_coordinator.trigger_tutorial("player_moved", "any")
  				break
  ```

  Then add _dispatch_save_load_confirm_result as a new private method near apply_manual_slot (added in 8.1):
  ```gdscript
  ## ADR-0043: notices a slot-screen confirm result surfaced through
  ## MenuCoordinator.get_last_meta_screen_confirm_result() and applies the
  ## gameplay-side consequence the coordinator itself cannot (it owns no
  ## gameplay state). Called every frame handle_ui_input returns true; a
  ## non-save_load or action=="none"/"arm"/"delete_armed" result is a no-op.
  ## Clears the coordinator's stored result after handling so a later
  ## handle_ui_input==true call (e.g. for ui_pause) never re-applies a stale
  ## confirm Dictionary from a previous, unrelated event.
  func _dispatch_save_load_confirm_result(result: Dictionary) -> void:
  	if str(result.get("screen", "")) != "save_load":
  		return
  	var action: String = str(result.get("action", ""))
  	var ok: bool = bool(result.get("ok", false))
  	var detail: String = str(result.get("detail", ""))
  	if action == "load" and ok:
  		var snapshot = result.get("snapshot", null)
  		apply_manual_slot(snapshot)
  	elif action == "save" and ok:
  		_manual_slots_written_this_run[detail] = true
  	if not action.is_empty():
  		menu_coordinator.clear_last_meta_screen_confirm_result()
  ```

- [ ] 8.3 Run the existing interactive meta-screens smoke again (it never touches save_load, but confirm the new _input/coordinator wiring didn't break the hub/skill/class arms) plus a quick boot smoke.

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/meta_screens_interactive_smoke.gd
  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/main_coherent_boot_smoke.gd

  Confirm both existing markers still print unchanged with no new ERROR/WARNING.

- [ ] 8.4 Commit.

  ```
  git add scripts/procgen/playable_generated_ship.gd scripts/ui/menu_coordinator.gd
  git commit -m "feat: apply_manual_slot seam; slot-screen load/save dispatch wiring in _input"
  ```

---

### Task 9: save_load_slot_screen_smoke.gd -- save/load/delete round trip + ship-only-not-world assertion

**Files:** Create scripts/validation/save_load_slot_screen_smoke.gd

**Interfaces:**
- Consumes: MenuCoordinator.open_meta_screen("save_load") (existing), MenuCoordinator.meta_screen_move_selection/meta_screen_confirm (Task 7), MenuCoordinator._save_load_rows/_cycle_save_load_verb (Task 7, the empty-manual-row synthesis and verb-model these expose), PlayableGeneratedShip.apply_manual_slot (Task 8), PlayableGeneratedShip._manual_slots_written_this_run (Task 1/8).
- Produces: nothing new -- pure verification smoke.

**Steps:**

- [ ] 9.1 Create scripts/validation/save_load_slot_screen_smoke.gd:
  ```gdscript
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
  ## Pass marker:
  ##   SAVE LOAD SLOT SCREEN PASS save=true load=true delete_armed=true delete_confirmed=true

  const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
  const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
  const TIMEOUT_FRAMES: int = 600
  const TARGET_SLOT_ID: String = "slot_01"

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
  ```

  ```gdscript
  func _validate() -> void:
  	if playable.menu_coordinator == null or playable.save_load_service == null:
  		_fail("menu_coordinator / save_load_service missing")
  		return
  	playable.save_load_service.delete_slot(TARGET_SLOT_ID)
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
  	coord.meta_screen_move_selection(-9999)
  	for _i in range(target_index):
  		coord.meta_screen_move_selection(1)

  	# Verb model for an empty manual row must be [Save] ONLY (spec 3.2,
  	# unconditional): confirm arms Save on the very first ui_accept without
  	# needing any ui_left/ui_right cycling, and cycling in either direction
  	# must be a structural no-op (a 1-element verb list always wraps to
  	# itself), never landing on Load or Delete. Assert this directly rather
  	# than only inferring it from the eventual action=="save" result below --
  	# requirement 4 (Load/Delete must not be offered on a synthetic empty
  	# row) is checked here explicitly, not just implied by construction.
  	var empty_row_verbs: Array = coord._valid_verbs_for_row(empty_row)
  	if empty_row_verbs != ["Save"]:
  		_fail("empty manual row verb set must be exactly [Save], got %s" % str(empty_row_verbs))
  		return
  	coord._cycle_save_load_verb(1)
  	coord._cycle_save_load_verb(-1)
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
  	if not playable._manual_slots_written_this_run.has(TARGET_SLOT_ID):
  		_fail("manual slot '%s' not recorded in _manual_slots_written_this_run after first Save" % TARGET_SLOT_ID)
  		return
  	if not playable.save_load_service.has_slot(TARGET_SLOT_ID):
  		_fail("slot file for '%s' does not exist on disk after the first save" % TARGET_SLOT_ID)
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
  ```

  ```gdscript
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
  	var loaded_snapshot = load_result.get("snapshot", null)
  	if not playable.apply_manual_slot(loaded_snapshot):
  		_fail("apply_manual_slot returned false for a valid Load result")
  		return
  	if playable.current_objective_sequence != seq_before_save:
  		_fail("objective_sequence did not revert after manual-slot Load (got %d expected %d)" % [playable.current_objective_sequence, seq_before_save])
  		return
  	if playable.visited_ships.size() != visited_before:
  		_fail("visited_ships size changed after a manual-slot Load -- ship-only semantics violated")
  		return
  ```

  ```gdscript
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
  	coord._cycle_save_load_verb(1)  # Load -> Save
  	coord._cycle_save_load_verb(1)  # Save -> Delete
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
  		playable.save_load_service.delete_slot(TARGET_SLOT_ID)
  	if main_node != null and is_instance_valid(main_node):
  		main_node.queue_free()
  	quit(code)
  ```

- [ ] 9.2 Run the smoke and iterate on any sequencing mismatches against Task 7/8's ACTUAL final method names/behavior (this smoke calls several coordinator-internal helpers like _save_load_rows(), _cycle_save_load_verb(), _refresh_save_load_panel() directly -- GDScript does not enforce privacy across files, so this works, but if Task 7's final implementation named anything differently, fix the SMOKE to match, not the reverse).

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/save_load_slot_screen_smoke.gd

  Expect: SAVE LOAD SLOT SCREEN PASS save=true load=true delete_armed=true delete_confirmed=true with no unexpected ERROR/WARNING.

- [ ] 9.3 Commit.

  ```
  git add scripts/validation/save_load_slot_screen_smoke.gd
  git commit -m "test: interactive save_load slot screen smoke (save/load/delete + ship-only-not-world)"
  ```

---

### Task 10: Save & Exit

**Files:** Modify data/ui/menu_definitions.json (pause_menu.items), scripts/ui/menu_coordinator.gd (signal save_and_exit_requested; _confirm_current_item's pause_menu arm at line 316-323), scripts/procgen/playable_generated_ship.gd (connect the new signal near line 4067; add _on_save_and_exit_requested; comment-only touch at DEFAULT_SAVE_RUN_BINDINGS/DEFAULT_LOAD_RUN_BINDINGS lines 459-460). Create scripts/validation/save_and_exit_smoke.gd.

**Interfaces:**
- Consumes: PlayableGeneratedShip.request_save() -> bool (existing, line 6576), PlayableGeneratedShip.return_to_title_requested (Task 5), MenuCoordinator.trigger_tutorial(event_id, target_id) -> String (existing, line 253).
- Produces: MenuCoordinator.save_and_exit_requested signal -- consumed only by PlayableGeneratedShip._on_save_and_exit_requested.

**Steps:**

- [ ] 10.1 Add the save_and_exit item to pause_menu in data/ui/menu_definitions.json. Read current block first. Old:
  ```json
      {
        "id": "pause_menu",
        "title": "Paused",
        "items": [
          { "id": "resume",     "label": "Resume",            "enabled": true, "kind": "command" },
          { "id": "settings",   "label": "Settings",          "enabled": true, "kind": "command" },
          { "id": "codex",      "label": "Codex",             "enabled": true, "kind": "command" },
          { "id": "records",    "label": "Records",           "enabled": true, "kind": "command" },
          { "id": "save",       "label": "Save",              "enabled": true, "kind": "command" },
          { "id": "quit_main",  "label": "Quit to Main Menu", "enabled": true, "kind": "command" }
        ]
      },
  ```
  New:
  ```json
      {
        "id": "pause_menu",
        "title": "Paused",
        "items": [
          { "id": "resume",        "label": "Resume",            "enabled": true, "kind": "command" },
          { "id": "settings",      "label": "Settings",          "enabled": true, "kind": "command" },
          { "id": "codex",         "label": "Codex",             "enabled": true, "kind": "command" },
          { "id": "records",       "label": "Records",           "enabled": true, "kind": "command" },
          { "id": "save",          "label": "Save",              "enabled": true, "kind": "command" },
          { "id": "save_and_exit", "label": "Save & Exit",       "enabled": true, "kind": "command" },
          { "id": "quit_main",     "label": "Quit to Main Menu", "enabled": true, "kind": "command" }
        ]
      },
  ```

- [ ] 10.2 Add the signal and _confirm_current_item arm in scripts/ui/menu_coordinator.gd. Read current signal block + _confirm_current_item's pause_menu arm first. Old signal block:
  ```gdscript
  signal modal_opened(menu_id: String)
  signal modal_closed(previous_menu_id: String)
  signal save_requested
  signal load_requested
  signal quit_requested
  signal settings_changed(summary: Dictionary)
  ```
  New:
  ```gdscript
  signal modal_opened(menu_id: String)
  signal modal_closed(previous_menu_id: String)
  signal save_requested
  signal load_requested
  signal quit_requested
  signal save_and_exit_requested
  signal settings_changed(summary: Dictionary)
  ```

  Old (_confirm_current_item's pause_menu arm):
  ```gdscript
  		"pause_menu":
  			match item_id:
  				"resume": menu_state.close_all()
  				"settings": menu_state.open_menu("settings_menu")
  				"codex": menu_state.open_menu("codex")
  				"records": menu_state.open_menu("records_menu")
  				"save": save_requested.emit()
  				"quit_main": quit_requested.emit()
  ```
  New:
  ```gdscript
  		"pause_menu":
  			match item_id:
  				"resume": menu_state.close_all()
  				"settings": menu_state.open_menu("settings_menu")
  				"codex": menu_state.open_menu("codex")
  				"records": menu_state.open_menu("records_menu")
  				"save": save_requested.emit()
  				"save_and_exit": save_and_exit_requested.emit()
  				"quit_main": quit_requested.emit()
  ```

- [ ] 10.3 Connect the signal and add the handler in scripts/procgen/playable_generated_ship.gd. Read the current connect block first. Old:
  ```gdscript
  	menu_coordinator.save_requested.connect(request_save)
  	menu_coordinator.load_requested.connect(request_load)
  	menu_coordinator.quit_requested.connect(_on_ui_quit_requested)
  	menu_coordinator.settings_changed.connect(_on_ui_settings_changed)
  ```
  New:
  ```gdscript
  	menu_coordinator.save_requested.connect(request_save)
  	menu_coordinator.load_requested.connect(request_load)
  	menu_coordinator.quit_requested.connect(_on_ui_quit_requested)
  	menu_coordinator.save_and_exit_requested.connect(_on_save_and_exit_requested)
  	menu_coordinator.settings_changed.connect(_on_ui_settings_changed)
  ```

  Add the handler right after _on_ui_quit_requested (from Task 5):
  ```gdscript
  func _on_ui_quit_requested() -> void:
  	# ADR-0043: "Quit to Main Menu" now really returns to the title screen
  	# instead of reopening the in-scene main_menu overlay (the old stub
  	# behavior -- there was no real title/quit path before this domain).
  	emit_signal("return_to_title_requested")

  ## ADR-0043 Save & Exit: request_save() the SAME guarded path F5/autosave
  ## already use (world.json write), then leave to the title screen only on
  ## success. Deliberately does NOT reuse AutosavePolicy.try_quicksave's
  ## cooldown -- that guard exists to stop autosave-cadence thrashing during
  ## active play, not to gate a terminal "I am leaving" action; a cooldown
  ## that could silently skip the write on the player's exit is a
  ## correctness footgun. On failure, surface a toast and do NOT exit --
  ## never silently lose progress on a leave action.
  func _on_save_and_exit_requested() -> void:
  	var ok: bool = request_save()
  	if ok:
  		emit_signal("return_to_title_requested")
  	else:
  		if is_instance_valid(menu_coordinator):
  			menu_coordinator.trigger_tutorial("save_and_exit_failed", "any")
  ```

- [ ] 10.4 Comment-only touch at DEFAULT_SAVE_RUN_BINDINGS/DEFAULT_LOAD_RUN_BINDINGS. Read current text first:

  grep -n -B 2 -A 2 "DEFAULT_SAVE_RUN_BINDINGS\|DEFAULT_LOAD_RUN_BINDINGS" "scripts/procgen/playable_generated_ship.gd"

  Old:
  ```gdscript
  const DEFAULT_SAVE_RUN_BINDINGS: Array[Key] = [KEY_F5]
  const DEFAULT_LOAD_RUN_BINDINGS: Array[Key] = [KEY_F9]
  ```
  New:
  ```gdscript
  # ADR-0043: F5/F9 keep their pre-Domain-8 world.json save/load behavior
  # unchanged (request_save/request_load), now documented as dev/debug
  # keys -- the player-facing save surfaces are the pause menu's Save /
  # Save & Exit items and the interactive save_load slot screen.
  const DEFAULT_SAVE_RUN_BINDINGS: Array[Key] = [KEY_F5]
  const DEFAULT_LOAD_RUN_BINDINGS: Array[Key] = [KEY_F9]
  ```

- [ ] 10.5 Check whether _confirm_current_item's "pause_menu" match is the ONLY place a pause_menu item id needs registering (e.g. tutorial triggers or UI-bindings tables that enumerate item ids explicitly) before writing the smoke.

  grep -rn "quit_main\|\"save\":" "scripts/ui/menu_coordinator.gd" "data/ui/tutorial_triggers.json"

  If data/ui/tutorial_triggers.json has a schema that validates unknown trigger ids strictly, confirm "save_and_exit_failed" either already exists as a trigger id or add a minimal new entry mirroring an existing pause-menu-adjacent trigger's shape (e.g. copy the "run_saved" trigger's structure, renaming id/title/body). Do this only if the grep/schema check shows it's required -- if trigger_tutorial silently no-ops on an unknown id (check scripts/systems/tutorial_state.gd's trigger() method), no data file change is needed.

  grep -n -A 10 "^func trigger" "scripts/systems/tutorial_state.gd"

- [ ] 10.6 Create scripts/validation/save_and_exit_smoke.gd:
  ```gdscript
  extends SceneTree

  ## ADR-0043 Save & Exit smoke: drives the pause menu's new "Save & Exit"
  ## item end-to-end -- request_save() succeeds, world.json is fresh (not
  ## consumed/frozen), and return_to_title_requested fires.
  ##
  ## Pass marker:
  ##   SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true

  const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
  const TIMEOUT_FRAMES: int = 600

  var main_node: Node
  var playable: PlayableGeneratedShip
  var frame_count: int = 0
  var finished: bool = false
  var _return_signal_received: bool = false

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
  	playable.save_load_service.delete_current_run()
  	playable.return_to_title_requested.connect(_on_return_to_title)

  	var coord = playable.menu_coordinator
  	coord.open_records_menu()  # ensures we start from a known state
  	coord.menu_state.close_all()
  	coord.menu_state.open_menu("pause_menu")
  	var items: Array = coord.menu_state.get_items("pause_menu")
  	var target_index: int = -1
  	for i in range(items.size()):
  		if str((items[i] as Dictionary).get("id", "")) == "save_and_exit":
  			target_index = i
  			break
  	if target_index < 0:
  		_fail("save_and_exit item not found in pause_menu catalog")
  		return
  	coord.menu_state.set_focus_index(target_index)
  	coord._confirm_current_item()

  	if not playable.save_load_service.has_save():
  		_fail("world save missing after Save & Exit")
  		return
  	if not _return_signal_received:
  		_fail("return_to_title_requested did not fire after a successful Save & Exit")
  		return

  	finished = true
  	print("SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true")
  	_cleanup_and_quit(0)

  func _on_return_to_title() -> void:
  	_return_signal_received = true

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
  	push_error("SAVE AND EXIT FAIL reason=%s" % reason)
  	_cleanup_and_quit(1)

  func _cleanup_and_quit(code: int) -> void:
  	if playable != null and is_instance_valid(playable) and playable.save_load_service != null:
  		playable.save_load_service.delete_current_run()
  	if main_node != null and is_instance_valid(main_node):
  		main_node.queue_free()
  	quit(code)
  ```

- [ ] 10.7 Run the smoke.

  "C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/save_and_exit_smoke.gd

  Expect: SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true with no unexpected ERROR/WARNING.

- [ ] 10.8 Commit.

  ```
  git add data/ui/menu_definitions.json scripts/ui/menu_coordinator.gd scripts/procgen/playable_generated_ship.gd scripts/validation/save_and_exit_smoke.gd
  git commit -m "feat: Save & Exit pause-menu action (request_save then return_to_title_requested)"
  ```

---

### Task 11: Docs pass -- ADR-0043, 06_validation_plan.md bundle registration, roadmap amendment, CLAUDE.md note, run_snapshot.gd comment

**Files:**
- Create: docs/game/adr/0043-title-screen-permadeath-freeze-save-and-exit.md
- Modify: docs/game/06_validation_plan.md (remove the deleted smoke's run_clean line, add 5 new run_clean lines, bump commands=107 -> commands=111)
- Modify: docs/superpowers/specs/2026-06-28-completion-roadmap-design.md (Domain 8's "Definition of CLOSED" item 4)
- Modify: CLAUDE.md (run-the-game note)
- Modify: scripts/systems/run_snapshot.gd (parent_world_slot comment only)

**Interfaces:** Docs-only task; no code interfaces produced or consumed.

**Steps:**

- [ ] 11.1 Create docs/game/adr/0043-title-screen-permadeath-freeze-save-and-exit.md:
  ```markdown
  # ADR-0043: Title Screen, Permadeath Freeze, and Save & Exit

  **Status:** Accepted
  **Date:** 2026-07-01
  **Domain:** Completion roadmap Domain 8 (save loop, closes: "partial" -> "closed")

  ## Context

  The save subsystem's write half was live (autosave rotation, world.json via F5)
  but the read half and the death-gate were dead code: load_from_slot had no
  live caller, PermadeathResolver.record_death was never called, no title
  screen existed anywhere, and AutosavePolicy.try_quicksave /
  SaveLoadMenu.confirm_quicksave were unwired. See
  docs/superpowers/specs/2026-07-01-domain8-save-persistence-design.md for
  the full design.

  ## Decisions

  ### 1. Title screen is a new bootstrap wrapper; main.tscn is unchanged

  scenes/title_main.tscn / scripts/title_main.gd become the new
  run/main_scene. They instantiate scenes/main.tscn (unchanged) as a child
  only on New Game / Continue. This means every existing main-scene smoke
  (which preloads res://scenes/main.tscn directly, not via project.godot's
  run/main_scene setting) is entirely unaffected by this domain's boot-
  sequence change.

  ### 2. Permadeath freezes, it does not delete

  end_run("death") now calls _freeze_run_on_death() instead of deleting
  world.json/autosaves. Every slot written this run -- the active-autosave
  alias, world, every AUTOSAVE_SLOT_IDS row, the quickslot if present, and
  any manual slot the player saved to this run (tracked in the new run-local
  _manual_slots_written_this_run set) -- gets a PermadeathResolver.record_death
  entry. world.json and every slot's payload file stay on disk; a
  <slot_id>.death.json record gates future loads (SaveLoadService.load_world /
  load_from_slot both refuse a frozen slot).

  **Why freeze instead of delete:** deleting the save would destroy the epitaph
  browsing UX ADR-0032 explicitly designed for
  (PermadeathResolver.load_epitaph) but never wired up. Freezing costs one
  extra gate check (already-proven at load_from_slot:249) and lets the slot
  screen render "DEAD -- <epitaph>" rows.

  **Manual slots freeze too.** A mid-run manual save is a valid save of a run
  that was alive at that moment, but the user-locked decision for this domain
  is that permadeath must have no escape hatch: a manual save right before a
  fatal encounter must not let the player reload past their death. Every
  manual slot the slot screen's Save verb wrote to during the run that just
  ended freezes along with the autosave family.

  **Extraction/completion is unaffected** -- that path still deletes
  (delete_current_run + autosave wipe), unchanged from before this domain. A
  successfully finished run has nothing to "continue"; that is not permadeath.

  **_apply_meta_payout_and_persist(reason) still runs unconditionally on
  death.** This is deliberate and must not be "fixed" away in a future change:
  meta progression (currency, unlocks, class gates) is explicitly cross-run
  state per ADR-0007/ADR-0033 and survives permadeath by design -- only the
  RUN's own save freezes, not the player's meta progress.

  **New Game after a death does not touch the frozen slot.** A "forget this
  death" action remains explicitly out of scope (ADR-0032 already scoped this
  out as a seam, not a requirement); Domain 8 wires the freeze and the
  epitaph-read path only.
  ```

  ```markdown
  ### 3. _input's post-death dead-zone is fixed

  playable_generated_ship.gd:7548-7550 used to hard-return from _input
  whenever slice_complete was true, which meant the player could not open
  ANY menu after death -- including the frozen-slot epitaph screen this domain
  adds. The fix moves the menu_coordinator.handle_ui_input(event) dispatch
  ahead of the slice_complete gate; only the gameplay-input tail (hotbar,
  attack, reload, F5/F9) stays gated on a completed run. This is a
  pre-existing bug (present since slice_complete was introduced, not
  something this domain's other changes caused), fixed here because Domain 8
  is the first feature that needs post-death menu access to work.

  ### 4. Manual-slot loads are ship-only, not full-world (ADR-0031, implemented
  at last)

  Loading a manual slot from the interactive slot screen restores the active
  ship's RunSnapshot only (apply_manual_slot -> _apply_run_snapshot). It
  does **not** touch visited_ships, dock edges, world_time, or
  current_location -- exactly ADR-0031's original text, never implemented
  until now. RunSnapshot.parent_world_slot stays reserved/unused; resurrecting
  it to validate a manual slot against a compatible world.json (schema for
  compatibility, refusal UX, location-drift edge cases) is real additional
  scope, explicitly deferred.

  ### 5. Save & Exit repurposes the pause menu, not quicksave

  A new save_and_exit pause-menu item calls request_save() (the same
  guarded world.json write path F5/autosave already use) and, on success,
  emits return_to_title_requested. On failure it surfaces a tutorial toast
  and does **not** leave -- silently losing progress on an exit action is
  unacceptable.

  Save & Exit deliberately does **not** reuse AutosavePolicy.try_quicksave's
  cooldown: that cooldown exists to stop autosave-cadence thrashing during
  active play, not to gate a terminal "I am leaving" action. Gating the
  player's exit-save behind a cooldown that could silently skip the write
  would be a correctness footgun.

  **Quicksave stays dead-but-harmless.** The roadmap's original Domain 8
  "definition of closed" item 4 called for wiring
  AutosavePolicy.try_quicksave/SaveLoadMenu.confirm_quicksave to a
  keybinding. This is superseded: the game is heading toward a
  multiplayer / Project-Zomboid-like persistent-world direction where
  quicksave/quickload does not fit the design (see
  docs/superpowers/specs/2026-06-28-completion-roadmap-design.md's amended
  item 4). try_quicksave/confirm_quicksave remain small, model-smoked, and
  available if a future package ships a real quicksave key.

  **F5/F9 stay as dev/debug keys**, unchanged behavior, documentation-only
  comment added at DEFAULT_SAVE_RUN_BINDINGS/DEFAULT_LOAD_RUN_BINDINGS.

  ## Known migration behavior

  Pre-Domain-7 ShipInstance summaries lack breach_seeded/fire_seeded
  fields (default false on load -> benign re-seed on revisit), and Domain 7's
  variant-list additions shift deterministic pick() results, so a
  pre-Domain-7 world.json loaded through Title-Continue may re-roll room
  variants on ships it had already visited. This is expected and
  cosmetic-only -- cross-ref scripts/systems/ship_instance.gd:213-214. Domain
  8 does not attempt to freeze historical variant rolls or force *_seeded
  flags true on legacy loads.

  ## Consequences

  - save.closes flips from "partial" to "closed" in
    docs/game/inventory/system_inventory.json.
  - The roadmap's Domain 8 definition-of-closed item 4 is amended from
    "Quicksave keybinding/UI fires try_quicksave/confirm_quicksave" to
    "Save & Exit (pause menu) fires request_save and returns to the title
    screen; quicksave stays intentionally unwired per the multiplayer/PZ-like
    direction."
  - main_playable_death_clears_autosave_smoke.gd is deleted (its
    cleared=true contract inverted) and replaced by
    permadeath_freeze_smoke.gd.
  ```

- [ ] 11.2 Update docs/game/06_validation_plan.md's regression bundle. First remove the deleted smoke's run_clean line. Read current text:

  grep -n "death_clears_autosave" docs/game/06_validation_plan.md

  Old (the exact line, currently at line 115):
  ```
  run_clean 'Domain 1 death clears autosave smoke' 'MAIN PLAYABLE DEATH CLEARS AUTOSAVE PASS wrote=true died=true cleared=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_death_clears_autosave_smoke.gd
  ```
  Delete this line entirely (do not replace it in place -- the new permadeath smoke is added alongside the other Domain 8 smokes below, not as a like-for-like swap in this exact spot, since the new smoke supersedes it functionally but the plan groups all-new Domain 8 lines together for reviewability).

- [ ] 11.3 Add the 5 new run_clean lines. Insert them immediately after the last existing line in the bundle (currently the Domain 7 procgen variant hazard smoke line, right before the final echo line). Read the current tail first:

  grep -n "procgen_variant_hazard_smoke\|^echo 'SYNAPTIC_SEA" docs/game/06_validation_plan.md

  Old (the last two lines of the fenced bash block):
  ```
  run_clean 'Domain 7 procgen variant hazard smoke' 'PROCGEN VARIANT HAZARD PASS away_ticks=1 fire_lit=true breach_open=true home_clean=true seal_point=true guarded=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_variant_hazard_smoke.gd
  echo 'SYNAPTIC_SEA REGRESSION PASS commands=107 clean_output=true'
  ```
  New:
  ```
  run_clean 'Domain 7 procgen variant hazard smoke' 'PROCGEN VARIANT HAZARD PASS away_ticks=1 fire_lit=true breach_open=true home_clean=true seal_point=true guarded=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_variant_hazard_smoke.gd
  run_clean 'Domain 8 permadeath freeze smoke' 'PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/permadeath_freeze_smoke.gd
  run_clean 'Domain 8 title save query smoke' 'TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/title_save_query_smoke.gd
  run_clean 'Domain 8 title screen flow smoke' 'TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/title_screen_flow_smoke.gd
  run_clean 'Domain 8 save load slot screen smoke' 'SAVE LOAD SLOT SCREEN PASS save=true load=true delete_armed=true delete_confirmed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_slot_screen_smoke.gd
  run_clean 'Domain 8 save and exit smoke' 'SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_and_exit_smoke.gd
  echo 'SYNAPTIC_SEA REGRESSION PASS commands=111 clean_output=true'
  ```
  Arithmetic check: 107 existing minus 1 (deleted death-clears-autosave line) plus 5 (new Domain 8 lines) = 111. Confirm by counting run_clean occurrences after editing:

  grep -c "^run_clean" docs/game/06_validation_plan.md

  Must print 111.

- [ ] 11.4 Amend the roadmap spec's Domain 8 "Definition of CLOSED" item 4. Read current text first (lines 378-383). Old:
  ```
  **Definition of CLOSED:**
  1. `SaveLoadMenu.select_slot_for_load` is **wired** so the multi-slot LOAD path runs in real play.
  2. `record_death` is **called** on player death (ties to Domain 1) and freezes the run's slot;
     `load_from_slot` honors the permadeath gate.
  3. Boot-time auto-resume offers the latest autosave (or an explicit "continue" entry).
  4. Quicksave keybinding/UI fires `try_quicksave`/`confirm_quicksave`.
  ```
  New:
  ```
  **Definition of CLOSED:**
  1. `SaveLoadMenu.select_slot_for_load` is **wired** so the multi-slot LOAD path runs in real play.
  2. `record_death` is **called** on player death (ties to Domain 1) and freezes the run's slot;
     `load_from_slot` honors the permadeath gate.
  3. Boot-time auto-resume offers the latest autosave (or an explicit "continue" entry).
  4. **Amended 2026-07-01 (ADR-0043):** the game is heading multiplayer / Project-Zomboid-like, where
     quicksave/quickload doesn't fit the design. Item 4 is satisfied instead by **Save & Exit** (a
     new pause-menu action that calls `request_save()` and returns to the title screen).
     `AutosavePolicy.try_quicksave`/`SaveLoadMenu.confirm_quicksave` stay intentionally unwired --
     dead-but-harmless, model-smoked, available if a future package ships a real quicksave key.
  ```

- [ ] 11.5 Update CLAUDE.md's run-the-game note. Read current line first:

  grep -n "Run the game" CLAUDE.md

  Old:
  ```
  - **Run the game (windowed):** `"$GODOT" --path "$ROOT"` -- main scene is `res://scenes/main.tscn`.
  ```
  New:
  ```
  - **Run the game (windowed):** `"$GODOT" --path "$ROOT"` -- main scene is `res://scenes/title_main.tscn` (title screen; New Game/Continue instantiate `res://scenes/main.tscn`, which is unchanged and still what every headless main-scene smoke preloads directly).
  ```

- [ ] 11.6 Update run_snapshot.gd's parent_world_slot comment. Read current context first:

  grep -n -B 1 "var parent_world_slot" scripts/systems/run_snapshot.gd

  Old:
  ```gdscript
  var parent_world_slot: String = ""
  ```
  New:
  ```gdscript
  # ADR-0043: reserved/unused. Manual-slot loads (the interactive slot
  # screen's Load verb, PlayableGeneratedShip.apply_manual_slot) apply the
  # RunSnapshot onto the currently-active ship only and never read this
  # field -- full world-coherent slot pairing (validating a manual slot
  # against a compatible world.json) is explicitly out of scope; see
  # ADR-0043 section 4.
  var parent_world_slot: String = ""
  ```

- [ ] 11.7 Commit.

  ```
  git add docs/game/adr/0043-title-screen-permadeath-freeze-save-and-exit.md docs/game/06_validation_plan.md docs/superpowers/specs/2026-06-28-completion-roadmap-design.md CLAUDE.md scripts/systems/run_snapshot.gd
  git commit -m "docs: ADR-0043; bundle registration (commands=111); roadmap Domain 8 definition-of-closed amendment"
  ```

---

### Task 12: Inventory update + --check pass + full regression bundle

**Files:** Modify docs/game/inventory/system_inventory.json (regenerate via tools/build_system_inventory.py)

**Interfaces:** None -- verification/closure task.

**Steps:**

- [ ] 12.1 Read docs/game/inventory/system_inventory.json's current save loop entry and the three affected system rows (save_load_service, save_load_menu, permadeath_resolver) to confirm the exact JSON shape before editing (do not trust any excerpt from earlier design analysis -- re-read the live file, since another task may have touched it, and its stale embedded line-number citations like "playable_generated_ship.gd:6039" must be corrected to REAL current line numbers, not copied forward).

  ```
  python3 -c "
  import json
  d = json.load(open('docs/game/inventory/system_inventory.json', encoding='utf-8'))
  for loop in d['loops']:
      if loop['id'] == 'save':
          print(json.dumps(loop, indent=2))
  for s in d['systems']:
      if s['id'] in ('save_load_service','save_load_menu','permadeath_resolver'):
          print(json.dumps(s, indent=2))
  "
  ```

- [ ] 12.2 Re-derive the REAL current line numbers for every citation this task will write, by grepping the actual files (do not reuse any line number from this plan's own text -- code has shifted across Tasks 1-11):

  ```
  grep -n "^func end_run\|^func _freeze_run_on_death\|^func apply_manual_slot" scripts/procgen/playable_generated_ship.gd
  grep -n "^func load_world\|^func load_from_slot" scripts/systems/save_load_service.gd
  grep -n "^func record_death\|^func has_died_in" scripts/systems/permadeath_resolver.gd
  grep -n "\"save_load\"\|^func meta_screen_confirm\|^func bind_meta_screens" scripts/ui/menu_coordinator.gd
  grep -n "^func _ready\|^func _refresh_continue_enabled" scripts/title_main.gd
  ```

- [ ] 12.3 Edit docs/game/inventory/system_inventory.json:
  - loops[] entry id "save": change "closes": "partial" to "closes": "closed". First check how build_system_inventory.py treats closed loops with residual break_points entries:

    grep -n "closes\|break_points" tools/build_system_inventory.py | head -20

    If closed loops may still carry documented deferrals, keep exactly one bullet: "Cloud manifest sync remains a documented stub deferral (cloud_provider='stub'); out of scope for this domain." Remove every other bullet (the LOAD path, permadeath-hollow, no-boot-resume, and SaveLoadMenu-dispatch-dead bullets are all now closed by this plan's work) and reword the quicksave bullet to: "Quicksave guards (AutosavePolicy.try_quicksave / SaveLoadMenu.confirm_quicksave) are intentionally unwired -- Save & Exit uses request_save directly (ADR-0043); the multiplayer/PZ-like direction does not use quicksave/quickload."

  - systems[] row id "save_load_service": output.live stays true; update output.desc to note manual-slot load_from_slot is now live via the slot screen (menu_coordinator's save_load interactive arm calling save_load_menu.select_slot_for_load -> PlayableGeneratedShip.apply_manual_slot); update the permadeath_resolver integration's health from "broken" to "healthy" (record_death now has a live producer via end_run and both load_from_slot/load_world are live consumers of has_died_in); update driven_at and input.at/output.at citations to the REAL line numbers from 12.2.

  - systems[] row id "save_load_menu": change output.live from false to true; update output.desc to state select_slot_for_load/confirm_save_to_slot/confirm_delete are now live-dispatched from menu_coordinator's save_load interactive arm (Task 7/8), not just refresh(); update the save_load_service integration's health from "weak" to "healthy".

  - systems[] row id "permadeath_resolver": change driven from false to true; set driven_at to the real end_run/_freeze_run_on_death line from 12.2; change input.live from false to true and update input.desc; change output.live from false to true and update output.desc to note both load_from_slot and load_world are now live-reachable consumers; change the save_load_service integration's health from "broken" to "healthy".

  - Add a new systems[] row for title_save_query:
    ```json
    {
      "id": "title_save_query",
      "file": "scripts/systems/title_save_query.gd",
      "name": "Title Save Query",
      "domain": "save",
      "kind": "simulation",
      "model_exists": true,
      "smoke": "scripts/validation/title_save_query_smoke.gd",
      "reachable": true,
      "driven": true,
      "driven_at": "scripts/title_main.gd:<REAL_LINE_FROM_12.2>",
      "input": {
        "live": true,
        "desc": "title_main.gd calls TitleSaveQuery.is_continue_available(service, resolver) at _ready() and again on every gameplay-teardown-back-to-title.",
        "at": "scripts/title_main.gd:<REAL_LINE_FROM_12.2>"
      },
      "output": {
        "live": true,
        "desc": "Result drives menu_state.set_item_enabled('main_menu', 'continue', value) on the title screen.",
        "at": "scripts/title_main.gd:<REAL_LINE_FROM_12.2>"
      },
      "confidence": "V",
      "loops": ["save"],
      "integrations": [
        {
          "to": "save_load_service",
          "via": "has_slot('world') existence check",
          "at": "scripts/systems/title_save_query.gd",
          "health": "healthy"
        },
        {
          "to": "permadeath_resolver",
          "via": "has_died_in('world') freeze check",
          "at": "scripts/systems/title_save_query.gd",
          "health": "healthy"
        }
      ],
      "content": "none",
      "content_note": "Pure static-method decision model; no data files.",
      "functional": null,
      "gaps": [],
      "subsystems": []
    }
    ```
    Replace every <REAL_LINE_FROM_12.2> placeholder with the actual grepped line number before saving -- do not commit a literal placeholder string.

- [ ] 12.4 Regenerate and check.

  ```
  python3 tools/build_system_inventory.py
  python3 tools/build_system_inventory.py --check
  ```
  The --check invocation must print SYSTEM INVENTORY CHECK PASS (with whatever systems=/verified= suffix it computes). If it fails, read the specific validation error it prints (missing cited file, dangling integration id, confidence "?" on a kind:"simulation" row, or stale rendered output) and fix the JSON edit from 12.3 accordingly -- do not silently loosen the check.

- [ ] 12.5 Run the FULL regression bundle (now commands=111) end to end.

  ```bash
  export ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  export GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  # Extract the fenced bash block under "## Regression bundle" in
  # docs/game/06_validation_plan.md verbatim (it now has 111 run_clean
  # lines + the final echo) into a temp script and run it:
  bash /path/to/extracted_regression_bundle.sh
  ```
  Expect the final line: SYNAPTIC_SEA REGRESSION PASS commands=111 clean_output=true. If ANY command in the bundle fails or emits an unexpected (non-allowlisted) ERROR:/WARNING: line, fix the root cause and re-run the FULL bundle again (not just the failing command in isolation) before considering this task complete -- a full green run is the closure gate for this entire domain.

- [ ] 12.6 Commit.

  ```
  git add docs/game/inventory/system_inventory.json
  git commit -m "docs: close save loop in inventory (closes=closed); title_save_query row; permadeath_resolver driven=true"
  ```
