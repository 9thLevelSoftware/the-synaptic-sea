extends SceneTree
# Tranche 4 (2026-07-06 audit, ui-wiring): Audio Log panel production-path smoke.
#
# Audit findings covered:
#   [HIGH]   audio_log_panel.gd:69 — `audio_manager.has_method("audio_log")` is
#            always false (audio_log is a var property, audio_manager.gd:52), so
#            _populate_entries() bails and the Audio Log meta screen is
#            permanently empty.
#   [MEDIUM] menu_coordinator.gd:936 — meta_screen_is_populated("audio_log")
#            only checks `audio_manager != null`, masking the empty panel from
#            the bundled meta-screens reachability smoke.
#
# Boots the real playable ship (same recipe as audio_pipeline_smoke) so the
# coordinator's own _build_meta_screens/bind_meta_screens wiring is what's
# under test — no hand-built panel.
#
# Asserts:
#   1. AudioLogPanel.get_entry_count() == 6 (the authored AudioLog entries).
#   2. meta_screen_is_populated("audio_log") == (entry count > 0) — the gate
#      must track real content, mirroring the achievements pattern.
#   3. Selecting entry 0 + Play drives audio_manager.play_voice_log →
#      current_voice_log_id set + status label shows "Playing:".
#   4. Stop clears current_voice_log_id and the status label.
#
#   5. The authored clip_path is routed to the stream loader (warn-once
#      record with the assets deferred; a live stream once they land).
#
# Pass marker: AUDIO LOG PANEL PASS entries=6 play=true stop=true clip_attempted=true populated_gate=true

const PlayableShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_002/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json"
const READY_TIMEOUT_FRAMES: int = 300

var playable: Node3D
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	playable = PlayableShipScript.new()
	playable.name = "AudioLogPanelSmoke"
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
	_validate()

func _validate() -> void:
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null or not is_instance_valid(ui):
		_fail("menu_coordinator missing")
		return
	var mgr: Node = playable.get_audio_manager()
	if mgr == null:
		_fail("audio_manager missing")
		return

	var panel = ui.get_meta_screen_panel("audio_log")
	if panel == null or not is_instance_valid(panel):
		_fail("audio_log panel missing from menu_coordinator")
		return

	# --- 1. Entry count: the 6 authored AudioLog entries must be listed ---
	if not panel.has_method("get_entry_count"):
		_fail("AudioLogPanel.get_entry_count missing (public count API)")
		return
	var count: int = int(panel.get_entry_count())
	if count != 6:
		_fail("expected 6 audio log entries listed, got %d (has_method-on-var bug at audio_log_panel.gd:69)" % count)
		return

	# --- 2. Populated gate must track real content, not manager presence ---
	var populated: bool = bool(ui.meta_screen_is_populated("audio_log"))
	if populated != (count > 0):
		_fail("meta_screen_is_populated('audio_log')=%s but entry count=%d — gate masks panel content" % [str(populated), count])
		return

	# --- 3. Select + Play drives the real playback path ---
	panel._entry_list.select(0)
	var first_id: String = String(panel._entry_list.get_item_metadata(0))
	if first_id.is_empty():
		_fail("entry 0 has no metadata id")
		return
	panel._on_play_pressed()
	if String(mgr.current_voice_log_id) != first_id:
		_fail("current_voice_log_id=%s expected %s after Play" % [String(mgr.current_voice_log_id), first_id])
		return
	if not String(panel._status_label.text).begins_with("Playing:"):
		_fail("status label did not show Playing: (got '%s')" % String(panel._status_label.text))
		return
	var play_ok: bool = true

	# --- 3b. The authored clip_path must actually be attempted (Tranche 4
	# wire-don't-delete: audio_log.gd authors 6 clip_paths that play_voice_log
	# never routed to the stream loader — silently dead data, not even the
	# ADR-0044 warn-once fired). With the assets deferred (data/audio/voice/
	# absent), the honest outcome is the loader's warn-once record; when the
	# assets land, the voice bus player carries the stream instead.
	var entry: Dictionary = mgr.audio_log.get_entry(StringName(first_id))
	var clip_path: String = String(entry.get("clip_path", ""))
	if clip_path.is_empty():
		_fail("entry %s has no authored clip_path" % first_id)
		return
	var voice_player: AudioStreamPlayer = mgr.get_bus_player(&"voice")
	var clip_attempted: bool = mgr._warned_missing_paths.has(clip_path) \
			or (voice_player != null and voice_player.stream != null)
	if not clip_attempted:
		_fail("play_voice_log never attempted the authored clip_path '%s' (dead data)" % clip_path)
		return

	# --- 4. Stop clears the playing state ---
	panel._on_stop_pressed()
	if not String(mgr.current_voice_log_id).is_empty():
		_fail("current_voice_log_id not cleared after Stop (got '%s')" % String(mgr.current_voice_log_id))
		return
	if String(panel._status_label.text) != "(no entry playing)":
		_fail("status label not reset after Stop (got '%s')" % String(panel._status_label.text))
		return
	var stop_ok: bool = true

	finished = true
	print("AUDIO LOG PANEL PASS entries=%d play=%s stop=%s clip_attempted=true populated_gate=true" % [
		count, str(play_ok).to_lower(), str(stop_ok).to_lower()])
	playable.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("AUDIO LOG PANEL FAIL reason=%s" % reason)
	if playable != null and is_instance_valid(playable):
		playable.queue_free()
	quit(1)
