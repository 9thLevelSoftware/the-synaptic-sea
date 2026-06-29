extends SceneTree

## Domain 1 terminal-state integrity (live scene): when the player dies
## (end_run("death") via _check_vitals_death on health<=0, driven by the real
## coordinator _process), the rotating autosave_a/b/c slots are cleared, so a
## dead run cannot be resumed from a stale autosave. Mirrors the objective-
## completion stale-resume guard (PR #35); regression guard for the PR #50
## finding that end_run cleared only current_run/world, leaving autosaves
## resumable and making death non-terminal.
##
## Pass marker:
##   MAIN PLAYABLE DEATH CLEARS AUTOSAVE PASS wrote=true died=true cleared=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
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

func _validate() -> void:
	if playable.vitals_state == null or playable.save_load_service == null:
		_fail("vitals / save_load_service missing")
		return
	# Isolate from combat damage; stay on the home branch.
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.away_from_start = false
	var service = playable.save_load_service

	# Start from a clean autosave state so the assertion is unambiguous.
	for sid in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
		service.delete_slot(sid)

	# 1) Force a rotating autosave to disk through the real coordinator path.
	var r: Dictionary = playable.force_autosave_for_validation()
	var slot: String = str(r.get("slot_id", ""))
	if not SaveSlotStateScript.AUTOSAVE_SLOT_IDS.has(slot):
		_fail("forced autosave slot=%s not in AUTOSAVE_SLOT_IDS" % slot)
		return
	if not service.has_slot(slot):
		_fail("forced autosave did not hit disk (has_slot=false for %s)" % slot)
		return

	# 2) Kill the player through the live coordinator (health<=0 -> end_run("death")).
	playable.vitals_state.health = 0.0
	_pump(0.1)
	if not playable.slice_complete:
		_fail("health=0 should have ended the run as death (slice_complete still false)")
		return

	# 3) Every autosave slot must now be cleared — a dead run is not resumable.
	for sid in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
		if service.has_slot(sid):
			_fail("autosave slot '%s' survived death — dead run still resumable" % sid)
			return

	finished = true
	print("MAIN PLAYABLE DEATH CLEARS AUTOSAVE PASS wrote=true died=true cleared=true")
	_cleanup_and_quit(0)

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
	push_error("MAIN PLAYABLE DEATH CLEARS AUTOSAVE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	# Leave no residual autosave state regardless of outcome.
	if playable != null and is_instance_valid(playable) and playable.save_load_service != null:
		for sid in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
			playable.save_load_service.delete_slot(sid)
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
