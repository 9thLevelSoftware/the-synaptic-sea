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
## Meta-progression pollution guard (review fast-follow): this smoke drives
## two REAL vitals deaths per run, and death payouts persist into the
## developer's real user://meta_progression.json and user://unlock_registry.json
## (confirmed live via total_runs_deaths climbing across bundle runs). Neither
## file's contents are load-bearing to this smoke's assertions, so at startup
## snapshot both files' raw bytes (or record their absence), and in the
## unconditional cleanup path (_cleanup_and_quit, reached on both success and
## failure) restore the original bytes, or delete the file if it did not
## exist before this run. Byte-for-byte restore, not JSON-aware -- this smoke
## asserts nothing about either file's content, only that running it leaves
## them exactly as found.
##
## RECLAIM stage (final-review C1 fix): after the away-branch death leaves
## "world" and its autosave slot frozen, simulate the NEXT run's first
## system write into those same slot ids and assert the freeze is lifted --
## save_world()/save_to_slot() now clear the slot's death record before
## writing (reclaim-on-write, ADR-0043), so a fresh run is never permanently
## bricked out of Continue/that autosave slot by a prior death.
##
## Pass marker:
##   PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true reclaim=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const TitleSaveQueryScript := preload("res://scripts/systems/title_save_query.gd")
const TIMEOUT_FRAMES: int = 600
const META_PROGRESSION_PATH: String = "user://meta_progression.json"
const UNLOCK_REGISTRY_PATH: String = "user://unlock_registry.json"

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var _meta_snapshot_restored: bool = false
## Raw bytes captured at startup, or null if the file did not exist yet --
## PoolByteArray("") vs "file absent" must stay distinguishable so an
## absent file is deleted (not recreated empty) on restore.
var _meta_progression_snapshot: PackedByteArray
var _meta_progression_existed: bool = false
var _unlock_registry_snapshot: PackedByteArray
var _unlock_registry_existed: bool = false

func _initialize() -> void:
	_snapshot_meta_progression_files()
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

## Reads the raw bytes of both cross-run meta-progression files before this
## smoke's real deaths can write payouts into them. Records absence
## explicitly (rather than treating a read failure as "empty bytes") so
## _restore_meta_progression_files() can delete a file that did not exist
## before this run instead of leaving behind an empty one.
func _snapshot_meta_progression_files() -> void:
	_meta_progression_existed = FileAccess.file_exists(META_PROGRESSION_PATH)
	if _meta_progression_existed:
		_meta_progression_snapshot = FileAccess.get_file_as_bytes(META_PROGRESSION_PATH)
	_unlock_registry_existed = FileAccess.file_exists(UNLOCK_REGISTRY_PATH)
	if _unlock_registry_existed:
		_unlock_registry_snapshot = FileAccess.get_file_as_bytes(UNLOCK_REGISTRY_PATH)

## Restores both files to their pre-run state: byte-identical if they
## existed, deleted if they did not. Idempotent (guarded by
## _meta_snapshot_restored) so both the success and failure cleanup paths
## can call it unconditionally without double-restoring.
func _restore_meta_progression_files() -> void:
	if _meta_snapshot_restored:
		return
	_meta_snapshot_restored = true
	if _meta_progression_existed:
		var f := FileAccess.open(META_PROGRESSION_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_meta_progression_snapshot)
			f.close()
	elif FileAccess.file_exists(META_PROGRESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(META_PROGRESSION_PATH))
	if _unlock_registry_existed:
		var f2 := FileAccess.open(UNLOCK_REGISTRY_PATH, FileAccess.WRITE)
		if f2 != null:
			f2.store_buffer(_unlock_registry_snapshot)
			f2.close()
	elif FileAccess.file_exists(UNLOCK_REGISTRY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UNLOCK_REGISTRY_PATH))

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
	if playable.vitals_state == null or playable.save_load_service == null:
		_fail("vitals / save_load_service missing")
		return
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	# ready() leaves menu_coordinator parked on "main_menu" (menu_coordinator.gd
	# calls open_main_menu() during setup); real play dismisses it via the
	# "start" confirm (menu_state.close_all()) before any gameplay input runs.
	# Mirror that here so the pause-menu assertions below exercise the real
	# in-play -> pause_menu transition instead of the main-menu -> in-play one.
	if is_instance_valid(playable.menu_coordinator):
		playable.menu_coordinator.menu_state.close_all()
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

	# --- RECLAIM: next run's first save reclaims the frozen slots ---
	# Reset to a live state the same way the smoke resets between its
	# home/away phases (slice_complete=false, health restored), simulating
	# the next run starting up after the away-branch death above froze
	# "world" and autosave_slot2.
	playable.slice_complete = false
	playable.vitals_state.health = 100.0
	playable._manual_slots_written_this_run.clear()

	if not playable.request_save():
		_fail("reclaim: next-run request_save() (world) should succeed")
		return
	var run_snapshot: RunSnapshot = playable._build_run_snapshot()
	if run_snapshot == null:
		_fail("reclaim: _build_run_snapshot() returned null for next-run autosave")
		return
	if not service.save_to_slot(autosave_slot2, run_snapshot, SaveSlotStateScript.SLOT_KIND_AUTO, false, "Autosave"):
		_fail("reclaim: save_to_slot(%s) should succeed for next-run autosave" % autosave_slot2)
		return
	if resolver.has_died_in("world"):
		_fail("reclaim: world slot still shows has_died_in=true after next-run save_world()")
		return
	if resolver.has_died_in(autosave_slot2):
		_fail("reclaim: autosave slot '%s' still shows has_died_in=true after next-run save_to_slot()" % autosave_slot2)
		return
	if service.load_world() == null:
		_fail("reclaim: load_world() returned null after reclaim -- slot should be loadable again")
		return
	if not TitleSaveQueryScript.is_continue_available(service, resolver):
		_fail("reclaim: TitleSaveQuery.is_continue_available() should be true after reclaim")
		return

	finished = true
	print("PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true reclaim=true")
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
	_restore_meta_progression_files()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
