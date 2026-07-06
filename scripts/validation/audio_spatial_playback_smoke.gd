extends SceneTree
# Spatial audio playback smoke (REQ-AU-005 / ADR-0044).
#
# Proves the AudioStreamPlayer3D spatial path actually EMITS audio, contract-
# consistent with the non-spatial _play_via_bus path:
# 1. Catalogued spatial proof: play_sfx(&"sfx.tool.pickup", P1) leaves the
#    event's pooled AudioStreamPlayer3D with stream != null, playing == true,
#    global_position == P1, bus == "sfx".
# 2. Honest fallback (ADR-0044): play_sfx(&"sfx.door.open", ...) — an
#    UNcatalogued event — creates/positions its spatial player but assigns no
#    stream and does not play (volume-push-only, identical to _play_via_bus's
#    deferred-asset fallback).
# 3. Production callsite proof: a corpse loot container spawned through the
#    REAL _on_threat_killed path, searched through the REAL try_interact path
#    (search_loot_container_for_validation), repositions the tool-pickup
#    spatial player to the container's global_position and plays it — proving
#    the coordinator passes a world position into play_sfx (spatial audio is
#    live in production, not a dead flow).
#
# Pass marker: AUDIO SPATIAL PASS catalogued_playing=true fallback_honest=true production_pickup=true position_tracked=true
#
# Writes nothing to disk. Frees the scene in both pass and fail exit paths.

const PlayableShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_002/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json"
const READY_TIMEOUT_FRAMES: int = 300
const DIRECT_POS: Vector3 = Vector3(3.0, 0.0, 2.0)
const FALLBACK_POS: Vector3 = Vector3(1.0, 0.0, 1.0)
const CORPSE_POS: Vector3 = Vector3(6.0, 0.5, -4.0)
const MAX_CORPSE_TRIES: int = 5

var playable: Node3D
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	playable = PlayableShipScript.new()
	playable.name = "AudioSpatialPlaybackSmoke"
	playable.layout_path = LAYOUT_PATH
	playable.kit_path = KIT_PATH
	playable.gameplay_slice_path = GAMEPLAY_SLICE_PATH
	get_root().add_child(playable)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if not is_instance_valid(playable):
		_fail("playable freed unexpectedly")
		return
	if not playable.playable_started:
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _spatial_player_for(mgr: Node, event_id: String) -> AudioStreamPlayer3D:
	# Node names cannot contain '.', so Godot sanitizes the pool player's
	# name ("AudioStreamPlayer3D_sfx.tool.pickup" -> dots replaced). Match on
	# the same sanitization rather than the raw event id.
	var want: String = ("AudioStreamPlayer3D_%s" % event_id).validate_node_name()
	for child in mgr.get_children():
		if child is AudioStreamPlayer3D and String(child.name) == want:
			return child
	return null

func _validate() -> void:
	if not playable.has_method("get_audio_manager"):
		_fail("get_audio_manager missing")
		return
	var mgr: Node = playable.get_audio_manager()
	if not is_instance_valid(mgr):
		_fail("audio_manager is invalid")
		return

	# --- Criterion 1: catalogued event plays spatially ---
	if not mgr.play_sfx(&"sfx.tool.pickup", DIRECT_POS):
		_fail("play_sfx(sfx.tool.pickup, pos) returned false")
		return
	var sp: AudioStreamPlayer3D = _spatial_player_for(mgr, "sfx.tool.pickup")
	if sp == null:
		_fail("no spatial player allocated for sfx.tool.pickup")
		return
	if sp.stream == null:
		_fail("catalogued spatial player has no stream assigned")
		return
	if not sp.playing:
		_fail("catalogued spatial player is not playing")
		return
	if String(sp.bus) != "sfx":
		_fail("catalogued spatial player on bus '%s', expected 'sfx'" % String(sp.bus))
		return
	if sp.global_position.distance_to(DIRECT_POS) > 0.01:
		_fail("catalogued spatial player at %s, expected %s" % [str(sp.global_position), str(DIRECT_POS)])
		return
	var catalogued_playing_ok: bool = true

	# --- Criterion 2: uncatalogued event stays an honest volume-push fallback ---
	if not mgr.play_sfx(&"sfx.door.open", FALLBACK_POS):
		_fail("play_sfx(sfx.door.open, pos) returned false")
		return
	var fb: AudioStreamPlayer3D = _spatial_player_for(mgr, "sfx.door.open")
	if fb == null:
		_fail("no spatial player allocated for sfx.door.open")
		return
	if fb.stream != null or fb.playing:
		_fail("uncatalogued spatial player must not stream/play (ADR-0044 honest fallback)")
		return
	if fb.global_position.distance_to(FALLBACK_POS) > 0.01:
		_fail("fallback spatial player at %s, expected %s" % [str(fb.global_position), str(FALLBACK_POS)])
		return
	var fallback_honest_ok: bool = true

	# --- Criterion 3: production corpse-loot pickup emits at the container position ---
	if not is_instance_valid(playable.player):
		_fail("player missing")
		return
	# Wait out the router cooldown so the pickup event re-routes.
	mgr.tick(0.5)
	var production_ok: bool = false
	var position_tracked_ok: bool = false
	var tries: int = 0
	for i in range(MAX_CORPSE_TRIES):
		tries += 1
		var iid: String = "smoke_sp_%d" % i
		var pos: Vector3 = CORPSE_POS + Vector3(float(i), 0.0, 0.0)
		playable._on_threat_killed({
			"archetype_id": "smoke_archetype",
			"instance_id": iid,
			"position": pos,
			"loot_table": "combat_drop_common",
		})
		if not playable.search_loot_container_for_validation("corpse_%s" % iid):
			_fail("try_interact failed for corpse_%s" % iid)
			return
		# The grant may deterministically roll empty for a given seed; only a
		# non-empty grant reaches the audio callsite. Retry with the next seed.
		if String(playable._last_loot_feedback_line).ends_with("empty"):
			mgr.tick(0.5)
			continue
		if sp.global_position.distance_to(pos) > 0.01:
			_fail("production pickup did not reposition spatial player: at %s, expected %s (tries=%d)" % [str(sp.global_position), str(pos), tries])
			return
		position_tracked_ok = true
		if sp.stream == null or not sp.playing:
			_fail("production pickup spatial player not streaming/playing (tries=%d)" % tries)
			return
		production_ok = true
		break
	if not production_ok:
		_fail("all %d corpse loot rolls came back empty; cannot exercise production pickup path" % tries)
		return

	finished = true
	print("AUDIO SPATIAL PASS catalogued_playing=%s fallback_honest=%s production_pickup=%s position_tracked=%s" % [
		str(catalogued_playing_ok).to_lower(),
		str(fallback_honest_ok).to_lower(),
		str(production_ok).to_lower(),
		str(position_tracked_ok).to_lower(),
	])
	playable.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("AUDIO SPATIAL FAIL reason=%s" % reason)
	if is_instance_valid(playable):
		playable.queue_free()
	quit(1)
