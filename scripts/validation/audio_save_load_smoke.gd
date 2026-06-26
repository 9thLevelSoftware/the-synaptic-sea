extends SceneTree
# REQ-AU-010 / ADR-0029: audio summary save/load round-trip smoke.
#
# Drives the playable scene through:
# 1. Initial state — bus volumes at defaults, ambient at docking role,
#    music at EXPLORATION, no sfx routed, no meta events fired.
# 2. Mutate every sub-model (change bus volume, move ambient role,
#    route several SFX events, transition music to TENSION, fire one
#    meta event).
# 3. Snapshot the audio_summary via get_audio_summary().
# 4. Build a fresh RunSnapshot, save + load via SaveLoadService,
#    confirm audio_summary round-trips.
# 5. Apply the loaded summary to a fresh AudioManager and confirm
#    every sub-model restored.
#
# Pass marker: AUDIO SAVE LOAD PASS summary_keys=6 round_trip=true
#
# Headless:
#   /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless
#     --path /Users/christopherwilloughby/the-synaptic-sea
#     --script res://scripts/validation/audio_save_load_smoke.gd

const PlayableShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_002/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json"
const READY_TIMEOUT_FRAMES: int = 300

var playable: Node3D
var frame_count: int = 0
var phase: String = "waiting_ready"
var finished: bool = false

func _initialize() -> void:
	# Clean any leftover autosave file before the test so has_save() is
	# unambiguous. The save smoke that runs in the same suite may leave
	# a stale file under user://saves.
	var dir_path: String = "user://saves"
	if DirAccess.dir_exists_absolute(dir_path):
		var stale_path: String = "user://saves/current_run.json"
		if FileAccess.file_exists(stale_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(stale_path))
	playable = PlayableShipScript.new()
	playable.name = "PlayableAudioSaveLoadSmoke"
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
	if phase == "waiting_ready":
		_run_round_trip()

func _run_round_trip() -> void:
	var mgr: Node = playable.get_audio_manager()
	if mgr == null:
		_fail("audio_manager null")
		return

	# Mutate every sub-model.
	mgr.set_bus_volume(&"sfx", -8.0)
	mgr.set_bus_muted(&"voice", true)
	mgr.ambient_zone_state.set_room_role(&"engine", true)
	mgr.play_sfx(&"sfx.tool.pickup")
	mgr.play_sfx(&"sfx.door.open", Vector3(1.0, 0.0, 2.0))
	mgr.play_sfx(&"ui.inventory.open")
	mgr.update_music_flags(false, true, false)
	mgr.tick(2.0)
	mgr.tick(60.0)  # drain default meta-event schedule

	var summary: Dictionary = playable.get_audio_summary()
	var required_keys: Array = ["bus_config", "ambient", "sfx_router", "music", "spatial", "meta_event"]
	for key in required_keys:
		if not summary.has(key):
			_fail("audio_summary missing key: %s" % key)
			return

	# Save + load via SaveLoadService. Build a RunSnapshot with the audio
	# summary filled in and the rest as defaults — the smoke asserts only
	# audio_summary round-trips, not the other sub-summaries.
	var service: RefCounted = SaveLoadServiceScript.new()
	var original: RunSnapshot = RunSnapshotScript.new()
	original.layout_path = LAYOUT_PATH
	original.kit_path = KIT_PATH
	original.gameplay_slice_path = GAMEPLAY_SLICE_PATH
	original.slice_version = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	original.godot_version = Engine.get_version_info()["string"]
	original.saved_at = Time.get_datetime_string_from_system(true)
	original.audio_summary = summary
	if not service.save_current_run(original):
		_fail("save_current_run returned false")
		return
	var loaded: RunSnapshot = service.load_current_run()
	if loaded == null:
		_fail("load_current_run returned null")
		return
	if loaded.audio_summary.is_empty():
		_fail("loaded audio_summary is empty")
		return
	for key in required_keys:
		if not loaded.audio_summary.has(key):
			_fail("loaded audio_summary missing key: %s" % key)
			return

	# JSON round-trip via the loaded summary to confirm persistence shape.
	var json: String = JSON.stringify(loaded.audio_summary)
	var parsed: Variant = JSON.parse_string(json)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("audio_summary did not JSON-round-trip")
		return
	for key in required_keys:
		if not (parsed as Dictionary).has(key):
			_fail("JSON round-tripped audio_summary missing key: %s" % key)
			return

	# Apply the loaded summary to a fresh AudioManager and verify the
	# bus volume we set (-8.0 on sfx) is restored.
	var manager_script := load("res://scripts/audio/audio_manager.gd")
	var fresh: Node = manager_script.new()
	fresh.name = "FreshAudioManager"
	get_root().add_child(fresh)
	fresh.apply_summary(loaded.audio_summary)
	if absf(fresh.bus_config.get_volume_db(&"sfx") - (-8.0)) > 0.001:
		_fail("fresh.bus_config.sfx volume not restored, got %s" % str(fresh.bus_config.get_volume_db(&"sfx")))
		return
	if not fresh.bus_config.is_muted(&"voice"):
		_fail("fresh.bus_config.voice should be muted after apply")
		return
	if String(fresh.ambient_zone_state.get_current_role()) != "engine":
		_fail("fresh ambient role not restored, got %s" % String(fresh.ambient_zone_state.get_current_role()))
		return
	if fresh.sfx_router.get_routed_count(&"sfx.tool.pickup") < 1:
		_fail("fresh sfx_router routed_count not restored, got %d" % fresh.sfx_router.get_routed_count(&"sfx.tool.pickup"))
		return
	if String(fresh.music_state.get_state()) != "TENSION":
		_fail("fresh music state not restored, got %s" % String(fresh.music_state.get_state()))
		return
	if fresh.meta_event_state.get_fired_count() < 1:
		_fail("fresh meta_event_state fired_count not restored, got %d" % fresh.meta_event_state.get_fired_count())
		return

	# Cleanup.
	service.delete_current_run()
	fresh.queue_free()

	finished = true
	print("AUDIO SAVE LOAD PASS summary_keys=%d round_trip=true" % required_keys.size())
	playable.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("AUDIO SAVE LOAD FAIL reason=%s" % reason)
	if playable != null and is_instance_valid(playable):
		playable.queue_free()
	quit(1)
