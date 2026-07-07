extends SceneTree

## Tranche 6 (corrected "UnlockRegistry.grant" audit item): the unlock
## pipeline (TrainingEventBus log -> _apply_meta_payout_and_persist ->
## UnlockRegistry.unlock_for_trigger / class_ids_for_trigger) has been wired
## since Domain 6, but 22 of 23 catalog entries in
## data/player/unlock_tables.json could NEVER fire because production only
## emitted 3 training events (fabricate_part, threat_killed,
## repair_full_system) and the catalog referenced a different vocabulary.
##
## User decision 2026-07-07 (retarget + flagship wire):
##  - catalog retargets: hub_scene_bridge defeat_enemy -> threat_killed;
##    codex_repair_intro repair_subcomponent -> repair_full_system
##  - ONE new production emission: scavenge_container at the loot-container
##    search completion handler (_on_loot_container_searched) — the authored
##    +50 scavenging XP and the salvage_captain class unlock finally fire
##  - everything else stays ledger-documented content-pending
##
## This smoke drives the PRODUCTION paths end-to-end: a threat kill spawns a
## corpse container, the real interact path searches it, run-end payout
## resolves the bus log into the registry, and the unlocks persist.
## user://unlock_registry.json and user://meta_progression.json are deleted
## before boot (clean unlock state) and byte-restored afterward.
##
## Pass marker: UNLOCK TRIGGER PRODUCTION PASS triggers_valid=true scavenge_emitted=true codex_unlocked=true class_unlocked=true bridge_unlocked=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const META_PROGRESSION_PATH: String = "user://meta_progression.json"
const UNLOCK_REGISTRY_PATH: String = "user://unlock_registry.json"

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var _files_restored: bool = false
var _meta_snapshot: PackedByteArray
var _meta_existed: bool = false
var _registry_snapshot: PackedByteArray
var _registry_existed: bool = false

func _initialize() -> void:
	# Snapshot then DELETE both cross-run files so the boot's load_from_disk
	# starts from a clean unlock state (a pre-unlocked registry would mask a
	# broken pipeline as a false PASS).
	_meta_existed = FileAccess.file_exists(META_PROGRESSION_PATH)
	if _meta_existed:
		_meta_snapshot = FileAccess.get_file_as_bytes(META_PROGRESSION_PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(META_PROGRESSION_PATH))
	_registry_existed = FileAccess.file_exists(UNLOCK_REGISTRY_PATH)
	if _registry_existed:
		_registry_snapshot = FileAccess.get_file_as_bytes(UNLOCK_REGISTRY_PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UNLOCK_REGISTRY_PATH))
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if not is_instance_valid(playable):
		playable = _find_playable(main_node)
	if not is_instance_valid(playable) or not is_instance_valid(playable.loader) \
			or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _validate() -> void:
	finished = true

	# --- Structural guard: every catalog trigger_event is a real training
	# action id (keeps future retargets inside the emitted vocabulary) ---
	var actions: Dictionary = _load_json("res://data/player/training_actions.json")
	var known_events: Dictionary = {}
	for entry in actions.get("training_actions", []):
		known_events[str((entry as Dictionary).get("event_id", ""))] = true
	var catalog: Dictionary = _load_json("res://data/player/unlock_tables.json")
	var rows: Array = catalog.get("unlocks", catalog.get("entries", []))
	if rows.is_empty():
		# Fall back: find the first Array value in the catalog dict.
		for k in catalog:
			if catalog[k] is Array and not (catalog[k] as Array).is_empty():
				rows = catalog[k]
				break
	if rows.is_empty():
		_fail("unlock_tables.json has no unlock rows")
		return
	for row in rows:
		var trig: String = str((row as Dictionary).get("trigger_event", ""))
		if trig.is_empty() or not known_events.has(trig):
			_fail("unlock '%s' trigger_event '%s' is not a training action" % [
				str((row as Dictionary).get("unlock_id", "?")), trig])
			return

	if playable.unlock_registry == null or playable.training_event_bus == null \
			or playable.meta_progression_state == null:
		_fail("unlock pipeline dependencies missing")
		return
	if playable.unlock_registry.get_unlock_count() != 0:
		_fail("registry not clean at boot (count=%d)" % playable.unlock_registry.get_unlock_count())
		return

	# --- Production kill -> corpse container -> REAL interact search ---
	playable._on_threat_killed({
		"archetype_id": "smoke_archetype",
		"instance_id": "unlock_probe",
		"position": Vector3(4.0, 0.5, -3.0),
		"loot_table": "combat_drop_common",
	})
	if not playable.search_loot_container_for_validation("corpse_unlock_probe"):
		_fail("try_interact failed for corpse_unlock_probe")
		return

	# --- The flagship emission: the production loot search must have logged
	# scavenge_container on the training bus ---
	var saw_scavenge: bool = false
	var saw_kill: bool = false
	for entry in playable.training_event_bus.get_log():
		match str(entry.get("event_id", "")):
			"scavenge_container":
				saw_scavenge = true
			"threat_killed":
				saw_kill = true
	if not saw_kill:
		_fail("threat kill did not log threat_killed")
		return
	if not saw_scavenge:
		_fail("production loot search emitted no scavenge_container training event (authored XP + unlocks dead)")
		return

	# --- Run-end payout resolves the bus log into the registry ---
	playable._apply_meta_payout_and_persist("completion")
	if not playable.unlock_registry.is_unlocked("codex_scavenging_intro"):
		_fail("codex_scavenging_intro not unlocked by a production scavenge")
		return
	if not playable.unlock_registry.is_unlocked("class_unlock_salvage_captain"):
		_fail("class_unlock_salvage_captain not unlocked by a production scavenge")
		return
	if not ("salvage_captain" in playable.meta_progression_state.unlocked_class_ids):
		_fail("salvage_captain not bridged into the meta class roster")
		return
	if not playable.unlock_registry.is_unlocked("hub_scene_bridge"):
		_fail("hub_scene_bridge not unlocked by a production kill (defeat_enemy trigger never fires; catalog must target threat_killed)")
		return

	print("UNLOCK TRIGGER PRODUCTION PASS triggers_valid=true scavenge_emitted=true codex_unlocked=true class_unlocked=true bridge_unlocked=true")
	_cleanup(0)

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _restore_files() -> void:
	if _files_restored:
		return
	_files_restored = true
	if _meta_existed:
		var f := FileAccess.open(META_PROGRESSION_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_meta_snapshot)
			f.close()
	elif FileAccess.file_exists(META_PROGRESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(META_PROGRESSION_PATH))
	if _registry_existed:
		var f2 := FileAccess.open(UNLOCK_REGISTRY_PATH, FileAccess.WRITE)
		if f2 != null:
			f2.store_buffer(_registry_snapshot)
			f2.close()
	elif FileAccess.file_exists(UNLOCK_REGISTRY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UNLOCK_REGISTRY_PATH))

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("UNLOCK TRIGGER PRODUCTION FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	_restore_files()
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
