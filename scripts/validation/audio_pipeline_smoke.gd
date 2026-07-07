extends SceneTree
# Domain 9 (audio bus + pipeline) full pipeline smoke.
#
# Verifies the roadmap CLOSED criteria in one run:
# 1. AudioBusLayout registration: AudioServer.bus_count == 7; "Master" +
#    the six lowercase children resolve via AudioManager._engine_bus_name;
#    per-bus volume agrees with AudioBusConfig.make_default().
# 2. Stream proof: play_sfx(&"sfx.tool.pickup") leaves the sfx player with
#    stream != null and playing == true; the music player (base layer,
#    always-on) also has stream != null and playing == true.
# 3. Caption pump: after driving the away branch for 30 manual _process
#    ticks, get_last_caption_line() is non-empty (the tool-pickup caption
#    reached the HUD seam through _refresh_audio_state, which both
#    _process branches already call).
# 4. Captions toggle unification (Task 5 review amendment, ADR-0044): the
#    SettingsState -> SfxEventRouter caption seam that MenuCoordinator
#    wires via apply_settings_summary() actually flips
#    audio_manager.sfx_router.captions_enabled, and with captions off a
#    freshly routed SFX event does NOT enqueue a new caption. Final-review
#    amendment: also drives AudioSettingsPanel._on_caption_toggled() directly
#    (the panel path, which must funnel through the same single seam rather
#    than writing sfx_router.captions_enabled itself) and asserts the router
#    flag follows it in both directions. PR #59 Codex P2 amendment: also
#    simulates a legacy pre-unification save whose audio_summary restore
#    left the router flag diverged from SettingsState, and asserts
#    _reconcile_captions_with_settings() snaps it back to SettingsState.
#
# 5. Voice-log toggle initial state (Tranche 4 amendment): after
#    _refresh_from_manager(), _voice_log_toggle.button_pressed is true —
#    the old has_method("audio_log") guard on a var property never set it.
#
# Pass marker: AUDIO PIPELINE PASS bus_index=true stream_playing=true caption_hud=true captions_toggle=true voice_toggle=true away_ticks=30
#
# Writes nothing to disk. Frees the scene in both the pass and fail exit paths.

const PlayableShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const AudioBusConfigScript := preload("res://scripts/systems/audio_bus_config.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_002/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json"
const READY_TIMEOUT_FRAMES: int = 300

var playable: Node3D
var frame_count: int = 0
var phase: String = "waiting_ready"
var finished: bool = false

func _initialize() -> void:
	playable = PlayableShipScript.new()
	playable.name = "AudioPipelineSmoke"
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
		_validate_and_drive()

func _validate_and_drive() -> void:
	if not playable.has_method("get_audio_manager"):
		_fail("get_audio_manager missing")
		return
	var mgr: Node = playable.get_audio_manager()
	if mgr == null:
		_fail("audio_manager is null")
		return

	# --- Criterion 1: bus registration ---
	if AudioServer.bus_count != 7:
		_fail("expected AudioServer.bus_count == 7, got %d" % AudioServer.bus_count)
		return
	if AudioServer.get_bus_index("Master") != 0:
		_fail("expected Master bus_index == 0, got %d" % AudioServer.get_bus_index("Master"))
		return
	var default_cfg = AudioBusConfigScript.make_default()
	for bus_id in ["sfx", "music", "voice", "ui", "ambient", "meta"]:
		var idx: int = AudioServer.get_bus_index(bus_id)
		if idx < 1:
			_fail("bus '%s' did not resolve (index=%d)" % [bus_id, idx])
			return
		var expected_db: float = default_cfg.get_volume_db(StringName(bus_id))
		var actual_db: float = AudioServer.get_bus_volume_db(idx)
		if absf(actual_db - expected_db) > 0.01:
			_fail("bus '%s' volume mismatch: engine=%s config=%s" % [bus_id, str(actual_db), str(expected_db)])
			return
	var bus_index_ok: bool = true

	# --- Criterion 2: stream proof ---
	if not mgr.play_sfx(&"sfx.tool.pickup"):
		_fail("play_sfx(sfx.tool.pickup) returned false")
		return
	var sfx_player: AudioStreamPlayer = mgr.get_bus_player(&"sfx")
	if sfx_player == null or sfx_player.stream == null:
		_fail("sfx player has no stream assigned after play_sfx")
		return
	if not sfx_player.playing:
		_fail("sfx player is not playing after play_sfx")
		return
	# Drive one manual tick so _apply_music_layer_gains (which lazily assigns
	# the base-layer stream on first call) has run at least once.
	mgr.tick(0.016)
	var music_player: AudioStreamPlayer = mgr.get_bus_player(&"music")
	if music_player == null or music_player.stream == null:
		_fail("music player has no stream assigned")
		return
	if not music_player.playing:
		_fail("music player is not playing")
		return
	var stream_playing_ok: bool = true

	# --- Criterion 3: caption pump on the away branch ---
	playable.away_from_start = true
	var away_ticks: int = 0
	# Per-tick delta is deliberately small (0.05s): 30 ticks * 0.05s = 1.5s
	# total elapsed, safely under SfxEventRouter.DEFAULT_CAPTION_DURATION
	# (2.5s), so the "Tool acquired" caption enqueued above is still live
	# when we assert on it below. The contract is 30 away-branch _process
	# calls, not any particular per-tick delta; using 0.1s here (3.0s total)
	# would deterministically outlive the caption's expiry and always fail.
	for i in range(30):
		playable.call("_process", 0.05)
		away_ticks += 1
	var caption: String = playable.get_last_caption_line()
	if caption.is_empty():
		_fail("expected a non-empty caption after %d away-branch ticks, got empty" % away_ticks)
		return
	var caption_hud_ok: bool = true

	# --- Criterion 4 (amendment): captions_toggle unification ---
	if not is_instance_valid(playable.menu_coordinator):
		_fail("menu_coordinator missing")
		return
	if not playable.menu_coordinator.has_method("get_settings_summary") or not playable.menu_coordinator.has_method("apply_settings_summary"):
		_fail("menu_coordinator missing settings summary seam")
		return

	# (a) capture current settings summary.
	var original_summary: Dictionary = playable.menu_coordinator.get_settings_summary()

	# (b) build a copy with captions=false and apply it.
	var disabled_summary: Dictionary = original_summary.duplicate(true)
	disabled_summary["captions"] = false
	if not playable.menu_coordinator.apply_settings_summary(disabled_summary):
		_fail("apply_settings_summary(captions=false) was rejected")
		return

	# (c) assert the router picked up captions_enabled == false.
	if mgr.sfx_router == null:
		_fail("sfx_router is null after applying settings summary")
		return
	if mgr.sfx_router.captions_enabled != false:
		_fail("expected sfx_router.captions_enabled == false after disabling captions")
		return

	# (d) wait out the 0.10s router cooldown for sfx.tool.pickup, then fire
	# it again and assert no NEW caption was enqueued.
	mgr.tick(0.2)
	if not mgr.play_sfx(&"sfx.tool.pickup"):
		_fail("play_sfx(sfx.tool.pickup) returned false during captions-disabled stage")
		return
	playable._refresh_audio_state(false, 0.0)
	if not mgr.sfx_router.get_pending_captions().is_empty():
		_fail("expected no pending captions while captions_enabled == false")
		return
	if mgr.sfx_router.captions_enabled != false:
		_fail("expected sfx_router.captions_enabled to remain false after the disabled-stage play_sfx")
		return

	# (e) restore captions=true via the same seam and assert it took effect.
	var restored_summary: Dictionary = original_summary.duplicate(true)
	restored_summary["captions"] = true
	if not playable.menu_coordinator.apply_settings_summary(restored_summary):
		_fail("apply_settings_summary(captions=true) was rejected")
		return
	if mgr.sfx_router.captions_enabled != true:
		_fail("expected sfx_router.captions_enabled == true after restoring captions")
		return

	# (f) final-review amendment: drive the AudioSettingsPanel path directly
	# (Finding 2). The panel must reach the same seam -- it mutates
	# settings_state then calls the coordinator-injected push Callable,
	# which emits settings_changed and lands back on
	# _on_ui_settings_changed, the sole sfx_router.captions_enabled writer.
	var audio_panel: Node = playable.menu_coordinator.get_meta_screen_panel("audio_settings")
	if audio_panel == null or not is_instance_valid(audio_panel):
		_fail("audio_settings_panel missing from menu_coordinator")
		return
	if not audio_panel.has_method("_on_caption_toggled"):
		_fail("audio_settings_panel missing _on_caption_toggled")
		return
	audio_panel._on_caption_toggled(false)
	if mgr.sfx_router.captions_enabled != false:
		_fail("expected sfx_router.captions_enabled == false after panel _on_caption_toggled(false)")
		return
	audio_panel._on_caption_toggled(true)
	if mgr.sfx_router.captions_enabled != true:
		_fail("expected sfx_router.captions_enabled == true after panel _on_caption_toggled(true)")
		return

	# (g) PR #59 Codex P2: simulate a legacy pre-unification save where the
	# audio_summary restore left sfx_router.captions_enabled diverged from
	# SettingsState. SettingsState.captions is true (the stage's restored
	# end state from (e)/(f)); force the router flag to false directly
	# (bypassing the seam, as a stale audio_summary write would), then call
	# the reconciliation method and assert SettingsState wins.
	if not playable.has_method("_reconcile_captions_with_settings"):
		_fail("playable missing _reconcile_captions_with_settings")
		return
	mgr.sfx_router.captions_enabled = false
	playable._reconcile_captions_with_settings()
	if mgr.sfx_router.captions_enabled != true:
		_fail("expected _reconcile_captions_with_settings to restore sfx_router.captions_enabled == true from SettingsState")
		return
	var captions_toggle_ok: bool = true

	# --- Criterion 5 (Tranche 4, 2026-07-06 audit MEDIUM): the voice-log
	# toggle's initial checked state must be set by _refresh_from_manager().
	# The old `audio_manager.has_method("audio_log")` guard was always false
	# (audio_log is a var property), so the checkbox rendered unchecked at
	# every panel open regardless of the audio_log state.
	audio_panel._refresh_from_manager()
	if audio_panel._voice_log_toggle == null:
		_fail("audio_settings_panel missing _voice_log_toggle")
		return
	if audio_panel._voice_log_toggle.button_pressed != true:
		_fail("voice-log toggle not checked after _refresh_from_manager (has_method-on-var bug at audio_settings_panel.gd:167)")
		return
	var voice_toggle_ok: bool = true

	finished = true
	print("AUDIO PIPELINE PASS bus_index=%s stream_playing=%s caption_hud=%s captions_toggle=%s voice_toggle=%s away_ticks=%d" % [
		str(bus_index_ok).to_lower(),
		str(stream_playing_ok).to_lower(),
		str(caption_hud_ok).to_lower(),
		str(captions_toggle_ok).to_lower(),
		str(voice_toggle_ok).to_lower(),
		away_ticks,
	])
	playable.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("AUDIO PIPELINE FAIL reason=%s" % reason)
	if playable != null and is_instance_valid(playable):
		playable.queue_free()
	quit(1)
