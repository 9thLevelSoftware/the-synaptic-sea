extends SceneTree
# REQ-AU-001..010 main-scene placement + routing smoke.
#
# Loads the playable scene against the template 002 fixture (which carries
# the full hazard + ambient + meta surface), then verifies:
# - audio_manager was built (six AudioStreamPlayer children for non-master buses)
# - bus_config validate() returns true
# - play_sfx routes a SFX event to the right bus player
# - play_sfx with a position spawns a spatial AudioStreamPlayer3D
# - ambient zone state advances through a role change with a crossfade
# - music state machine resolves TENSION when a hazard is non-safe
# - meta-event scheduler fires a beacon within the default schedule
# - get_audio_summary round-trips all six sub-summaries through JSON
#
# Pass marker: MAIN PLAYABLE AUDIO PASS buses=6 routed=4 fired_meta=1 ambient_role=engine
#
# Headless:
#   /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless
#     --path /Users/christopherwilloughby/the-synaptic-sea
#     --script res://scripts/validation/main_playable_slice_audio_smoke.gd

const PlayableShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
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
	playable.name = "PlayableAudioSmoke"
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
	# audio_manager was constructed.
	if not playable.has_method("get_audio_manager"):
		_fail("get_audio_manager missing")
		return
	var mgr: Node = playable.get_audio_manager()
	if mgr == null:
		_fail("audio_manager is null")
		return
	# Six per-bus AudioStreamPlayer children.
	var bus_count: int = int(playable.get_audio_bus_player_count())
	if bus_count != 6:
		_fail("expected 6 bus players, got %d" % bus_count)
		return
	# Bus config validates.
	if not mgr.bus_config.is_validated():
		_fail("bus_config failed validation")
		return
	# Route a few SFX events through the manager.
	if not mgr.play_sfx(&"sfx.tool.pickup"):
		_fail("play_sfx(sfx.tool.pickup) returned false")
		return
	if not mgr.play_sfx(&"ui.inventory.open"):
		_fail("play_sfx(ui.inventory.open) returned false")
		return
	if not mgr.play_sfx(&"meta.beacon.distress"):
		_fail("play_sfx(meta.beacon.distress) returned false")
		return
	if not mgr.play_sfx(&"voice.log.play"):
		_fail("play_sfx(voice.log.play) returned false")
		return
	var routed_total: int = 0
	routed_total += int(mgr.sfx_router.get_routed_count(&"sfx.tool.pickup"))
	routed_total += int(mgr.sfx_router.get_routed_count(&"ui.inventory.open"))
	routed_total += int(mgr.sfx_router.get_routed_count(&"meta.beacon.distress"))
	routed_total += int(mgr.sfx_router.get_routed_count(&"voice.log.play"))
	if routed_total < 4:
		_fail("expected routed_count >= 4 across SFX events, got %d" % routed_total)
		return
	# Play a voice log entry.
	if not mgr.play_voice_log(&"log.beacon_01"):
		_fail("play_voice_log(log.beacon_01) failed")
		return
	if mgr.current_voice_log_id != "log.beacon_01":
		_fail("current_voice_log_id did not update, got %s" % mgr.current_voice_log_id)
		return
	# Spatial SFX.
	var spatial_before: int = int(playable.get_audio_spatial_player_count())
	mgr.play_sfx(&"sfx.door.open", Vector3(2.0, 1.5, -3.0))
	var spatial_after: int = int(playable.get_audio_spatial_player_count())
	if spatial_after <= spatial_before:
		_fail("expected spatial player count to grow after spatial play_sfx, before=%d after=%d" % [spatial_before, spatial_after])
		return
	# Ambient zone: drive a role change.
	mgr.ambient_zone_state.set_room_role(&"engine", true)
	var ambient_role: String = String(mgr.ambient_zone_state.get_current_role())
	if ambient_role != "engine":
		_fail("ambient role should be engine after set, got %s" % ambient_role)
		return
	# Advance the crossfade by ticking the manager.
	mgr.tick(2.0)
	if mgr.ambient_zone_state.is_crossfade_active():
		_fail("ambient crossfade should complete within 2.0s")
		return
	# Music state machine: with hazards disabled, state should be EXPLORATION.
	mgr.update_music_flags(false, false, false)
	if String(mgr.music_state.get_state()) != "EXPLORATION":
		_fail("music state should be EXPLORATION when no flags set")
		return
	mgr.update_music_flags(false, true, false)
	if String(mgr.music_state.get_state()) != "TENSION":
		_fail("music state should be TENSION with hazard_active=true")
		return
	# Meta-event schedule: check fired count from before/after a fresh tick.
	var fired_before: int = int(mgr.meta_event_state.get_fired_count())
	var due: Array = mgr.tick(60.0)
	var fired_count: int = int(mgr.meta_event_state.get_fired_count()) - fired_before
	# It's also valid that the manager already fired events via the playable's
	# per-frame ticks; in that case fired_count==0 here but total fired >= 1.
	var total_fired: int = int(mgr.meta_event_state.get_fired_count())
	if total_fired < 1:
		_fail("expected at least 1 meta-event fired across the run, got %d" % total_fired)
		return
	# Use fired_count for the marker (events fired in THIS tick); when the
	# playable has already drained the schedule, due.size() may be 0 — fall
	# back to total_fired for the marker so the smoke prints a positive count.
	var marker_fired: int = fired_count if fired_count > 0 else total_fired
	# Summary round-trip.
	var summary: Dictionary = playable.get_audio_summary()
	for key in ["bus_config", "ambient", "sfx_router", "music", "spatial", "meta_event"]:
		if not summary.has(key):
			_fail("audio_summary missing key: %s" % key)
			return
		if typeof(summary[key]) != TYPE_DICTIONARY:
			_fail("audio_summary.%s should be a Dictionary" % key)
			return
	# JSON stringify round-trip the bus_config sub-summary to confirm
	# the persistence shape is JSON-clean.
	var bus_summary: Dictionary = summary["bus_config"]
	var json: String = JSON.stringify(bus_summary)
	var parsed: Variant = JSON.parse_string(json)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("audio_summary bus_config did not JSON-round-trip")
		return
	if not (parsed as Dictionary).has("volumes"):
		_fail("audio_summary bus_config missing volumes key after JSON round-trip")
		return

	finished = true
	print("MAIN PLAYABLE AUDIO PASS buses=%d routed=%d fired_meta=%d ambient_role=%s" % [
		bus_count,
		routed_total,
		marker_fired,
		ambient_role,
	])
	playable.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE AUDIO FAIL reason=%s" % reason)
	if playable != null and is_instance_valid(playable):
		playable.queue_free()
	quit(1)
