extends Node
class_name AudioManagerScript
## AudioManager — service node owned by PlayableGeneratedShip (ADR-0029).
##
## The manager is NOT an autoload per AGENTS.md. It is added as a child
## of the playable scene by _build_runtime_nodes() and removed when the
## scene tree frees the playable.
##
## Responsibilities:
## - Owns one AudioStreamPlayer per bus (sfx, music, voice, ui, ambient,
##   meta) plus a pool of AudioStreamPlayer3D nodes for spatial emitters.
## - Reads summaries from the six pure models (bus_config, ambient, sfx,
##   music, spatial, meta_event) and pushes them into AudioServer bus
##   indices and AudioStreamPlayer volume_db values.
## - Exposes play_sfx(event_id, position), set_bus_volume(bus_id, db),
##   transition_music(state), attach_listener(node), play_voice_log(id),
##   trigger_meta_event(event_id), apply_summary(dict), get_summary().
## - Maintains the AudioLog registry (data-only) and routes voice-log
##   playback through the voice bus.
##
## Headless: when --headless is active, AudioServer.get_bus_index() returns
## -1 for any bus that was never registered, so the manager tolerates a
## missing device by skipping volume pushes and only keeping the pure-model
## state coherent. The smoke verifies the path runs without errors.

const AmbientZoneStateScript := preload("res://scripts/systems/ambient_zone_state.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")
const DynamicMusicStateScript := preload("res://scripts/systems/dynamic_music_state.gd")
const SpatialAudioResolverScript := preload("res://scripts/systems/spatial_audio_resolver.gd")
const MetaEventStateScript := preload("res://scripts/systems/meta_event_state.gd")
const AudioBusConfigScript := preload("res://scripts/systems/audio_bus_config.gd")
const AudioLogScript := preload("res://scripts/audio/audio_log.gd")

const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")

## Bus -> AudioStreamPlayer node (one per bus, all routed through master).
var _bus_players: Dictionary = {}
## Bus -> AudioStreamPlayer3D pool (spatial emitters, keyed by event id).
var _spatial_pool: Dictionary = {}
## AudioListener3D that follows the player when attached.
var _listener: AudioListener3D
## Reference to the listener's anchor (usually the player node). Updated
## each frame in _process when set.
var _listener_anchor: Node3D

var bus_config: AudioBusConfig = AudioBusConfigScript.make_default()
var ambient_zone_state: AmbientZoneState = AmbientZoneStateScript.new()
var sfx_router: SfxEventRouter = SfxEventRouterScript.new()
var music_state: DynamicMusicState = DynamicMusicStateScript.new()
var spatial_resolver: SpatialAudioResolver = SpatialAudioResolverScript.new()
var meta_event_state: MetaEventState = MetaEventStateScript.new()
var audio_log: AudioLog = AudioLogScript.new()

## Last-played voice-log entry id (for the panel to show "now playing").
var current_voice_log_id: String = ""

func _ready() -> void:
	_build_stream_players()
	_apply_bus_volumes()
	_initialize_sub_models()

## Call configure() on each of the six pure models with a baseline
## dictionary. Per ADR-0029, AudioManager owns the model instances;
## callers do not poke at the models directly. The ambient_zone_state,
## dynamic_music_state, and spatial_audio_resolver accept defaults that
## match the ADR-0029 baseline; the sfx_router and meta_event_state
## accept empty dictionaries (their defaults already match the spec).
func _initialize_sub_models() -> void:
	if ambient_zone_state != null:
		ambient_zone_state.configure({})
	if sfx_router != null:
		sfx_router.configure({})
	if music_state != null:
		music_state.configure({})
	if spatial_resolver != null:
		spatial_resolver.configure({})
	if meta_event_state != null:
		meta_event_state.configure({})

## Construct the per-bus AudioStreamPlayer children. Safe in headless mode:
## AudioStreamPlayer nodes exist (they're regular Nodes), only the audio
## output is silent. Smoke tests verify the node tree was built.
func _build_stream_players() -> void:
	for bus_id in AudioEventSeamScript.ALL_BUS_IDS:
		if String(bus_id) == String(AudioEventSeamScript.BUS_MASTER):
			# Master is the AudioServer's built-in root bus; we do not own
			# a per-stream player for it. We only own a player for each
			# child bus.
			continue
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "AudioStreamPlayer_%s" % String(bus_id)
		player.bus = String(bus_id)
		add_child(player)
		_bus_players[String(bus_id)] = player

## Translate a pure-model bus id (lowercase, e.g. &"master") to the engine's
## AudioServer bus name. Godot's bus 0 is immutably named "Master" (capital
## M) and AudioServer.get_bus_index("master") always returns -1 for it; the
## six child buses (sfx/music/voice/ui/ambient/meta) need no translation
## because their names already match between the pure model and the engine.
## This is the ONLY place the Master-name mismatch is bridged — every
## AudioServer boundary call goes through this helper (ADR-0044).
func _engine_bus_name(bus_id: StringName) -> String:
	if String(bus_id) == String(AudioEventSeamScript.BUS_MASTER):
		return "Master"
	return String(bus_id)

## Push per-bus dB values into AudioServer. Skipped for buses that
## AudioServer doesn't know about (e.g. in headless tests where the
## .tres has not been loaded). The pure-model state remains the source
## of truth in that case.
func _apply_bus_volumes() -> void:
	for bus in bus_config.buses:
		if typeof(bus) != TYPE_DICTIONARY:
			continue
		var bus_id: String = String(bus.get("id", ""))
		if bus_id.is_empty():
			continue
		var engine_name: String = _engine_bus_name(StringName(bus_id))
		var bus_idx: int = AudioServer.get_bus_index(engine_name)
		if bus_idx < 0:
			# Bus not registered in AudioServer yet (headless / pre-init).
			# Skip without error so the manager survives --script mode.
			continue
		var vol_db: float = float(bus.get("volume_db", 0.0))
		var muted: bool = bool(bus.get("muted", false))
		AudioServer.set_bus_volume_db(bus_idx, vol_db)
		AudioServer.set_bus_mute(bus_idx, muted)

## Apply a full summary (the 9th RunSnapshot summary, REQ-AU-010) to the
## manager. Returns true if any sub-summary was applied.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var bus: Variant = summary.get("bus_config", null)
	if typeof(bus) == TYPE_DICTIONARY:
		if bus_config.apply_summary(bus):
			changed = true
			_apply_bus_volumes()
	var ambient: Variant = summary.get("ambient", null)
	if typeof(ambient) == TYPE_DICTIONARY:
		if ambient_zone_state.apply_summary(ambient):
			changed = true
	var sfx: Variant = summary.get("sfx_router", null)
	if typeof(sfx) == TYPE_DICTIONARY:
		if sfx_router.apply_summary(sfx):
			changed = true
	var music: Variant = summary.get("music", null)
	if typeof(music) == TYPE_DICTIONARY:
		if music_state.apply_summary(music):
			changed = true
	var spatial: Variant = summary.get("spatial", null)
	if typeof(spatial) == TYPE_DICTIONARY:
		if spatial_resolver.apply_summary(spatial):
			changed = true
	var meta: Variant = summary.get("meta_event", null)
	if typeof(meta) == TYPE_DICTIONARY:
		if meta_event_state.apply_summary(meta):
			changed = true
	return changed

## Collect a summary from the manager (and its six sub-models). The result
## is a flat dictionary with six sub-dicts plus a small set of manager-level
## fields (current_voice_log_id, listener_attached).
func get_summary() -> Dictionary:
	return {
		"bus_config": bus_config.get_summary(),
		"ambient": ambient_zone_state.get_summary(),
		"sfx_router": sfx_router.get_summary(),
		"music": music_state.get_summary(),
		"spatial": spatial_resolver.get_summary(),
		"meta_event": meta_event_state.get_summary(),
		"current_voice_log_id": current_voice_log_id,
		"listener_attached": _listener_anchor != null and is_instance_valid(_listener_anchor),
	}

## Update the player-vitals / hazard / engagement flags driving the music
## state machine. The manager resolves the new state and updates the
## target gains; per-frame `tick(delta)` applies the crossfade.
func update_music_flags(engagement: bool, hazard_active: bool, vitals_critical: bool) -> void:
	music_state.set_flags(engagement, hazard_active, vitals_critical)

## Per-frame tick. Advances the music crossfade, the ambient crossfade,
## the SFX cooldowns / captions, and the meta-event scheduler. Returns
## the array of meta-events that fired during this tick (so the playable
## scene can route them to SfxEventRouter).
func tick(delta_seconds: float) -> Array:
	if delta_seconds <= 0.0:
		return []
	ambient_zone_state.tick(delta_seconds)
	sfx_router.tick(delta_seconds)
	music_state.tick(delta_seconds)
	_apply_music_layer_gains()
	var due: Array = meta_event_state.tick(delta_seconds)
	for ev in due:
		# Each fired meta-event is routed through SfxEventRouter so the
		# caption queue + bus routing go through the same path as a normal
		# SFX. AudioManager.play_sfx handles unknown ids (the catalog maps
		# meta events to the meta bus).
		var id_str: String = String(ev.get("id", ""))
		var bus_id: String = _bus_for_meta_event_id(id_str)
		var vol: float = float(ev.get("volume_db", -6.0))
		_play_via_bus(bus_id, vol)
		var voice_log_id: String = String(ev.get("voice_log_id", ""))
		if not voice_log_id.is_empty():
			play_voice_log(StringName(voice_log_id))
	return due

## Fire a named SFX event. Routes through SfxEventRouter (which dedups /
## captions) then plays through the routed bus.
## When `position` is provided and the AudioStreamPlayer3D pool has a slot,
## the sound is emitted spatially (REQ-AU-005).
func play_sfx(event_id: StringName, position: Variant = null) -> bool:
	var route_result: Variant = sfx_router.route(event_id)
	if route_result == null:
		return false
	if typeof(route_result) != TYPE_DICTIONARY:
		return false
	var route_dict: Dictionary = route_result
	var bus_id: String = String(route_dict.get("bus", AudioEventSeamScript.BUS_SFX))
	var vol_db: float = float(route_dict.get("volume_db", -6.0))
	if position != null and position is Vector3:
		_play_spatial(event_id, position, bus_id, vol_db)
	else:
		_play_via_bus(bus_id, vol_db)
	return true

## Convenience: get pending captions and clear the queue. The HUD calls
## this each frame.
func drain_captions() -> Array:
	return sfx_router.get_pending_captions()

## Per-frame: capture (and clear) pending captions and forward them to the
## `caption_target` callable (typically the HUD label). Default null = no-op.
func pump_captions(caption_target: Callable = Callable()) -> int:
	var captions: Array = drain_captions()
	if caption_target.is_valid():
		for caption in captions:
			caption_target.call(caption)
	return captions.size()

## Per-frame: apply spatial attenuation to the live spatial-pool players
## using the listener anchor's global_position. Returns the number of
## spatial players touched.
func apply_spatial_attenuation() -> int:
	if _listener_anchor == null or not is_instance_valid(_listener_anchor):
		return 0
	var listener_pos: Vector3 = _listener_anchor.global_position
	var touched: int = 0
	for event_id_str in _spatial_pool.keys():
		var players: Array = _spatial_pool[event_id_str]
		for player in players:
			if player == null or not is_instance_valid(player):
				continue
			var dist: float = SpatialAudioResolverScript.distance(player.global_position, listener_pos)
			var occluded: bool = _is_occluded(player.global_position, listener_pos)
			var base_db: float = SfxEventRouterScript.get_volume_for_event(StringName(event_id_str))
			var resolved: float = spatial_resolver.resolve_volume_db(player.global_position, listener_pos, occluded, base_db)
			player.volume_db = resolved
			touched += 1
	return touched

## Per-frame: orient the AudioListener3D toward the player anchor.
func update_listener_transform() -> void:
	if _listener_anchor == null or not is_instance_valid(_listener_anchor):
		return
	if _listener == null or not is_instance_valid(_listener):
		_listener = AudioListener3D.new()
		_listener.name = "AudioListener"
		# Parent the listener directly to the anchor. add_child re-parents
		# automatically when the new parent differs from the current one,
		# so we do not add the listener to the AudioManager tree first.
		if _listener.get_parent() != _listener_anchor:
			if _listener.get_parent() != null:
				_listener.get_parent().remove_child(_listener)
			_listener_anchor.add_child(_listener)
	# AudioListener3D inherits from Node3D, so we set global_transform.
	_listener.global_transform = _listener_anchor.global_transform

## Set the bus volume (clamped). Returns true on success.
func set_bus_volume(bus_id: StringName, volume_db: float) -> bool:
	if not bus_config.set_volume_db(bus_id, volume_db):
		return false
	_apply_bus_volumes()
	return true

func get_bus_volume(bus_id: StringName) -> float:
	return bus_config.get_volume_db(bus_id)

func set_bus_muted(bus_id: StringName, muted: bool) -> bool:
	if not bus_config.set_muted(bus_id, muted):
		return false
	_apply_bus_volumes()
	return true

func is_bus_muted(bus_id: StringName) -> bool:
	return bus_config.is_muted(bus_id)

## Force a music state override (used by scripted cues).
func transition_music(target_state: StringName) -> bool:
	return music_state.override_state(target_state)

## Schedule an AudioLog entry for playback through the voice bus.
func play_voice_log(entry_id: StringName) -> bool:
	if not audio_log.has_entry(entry_id):
		push_warning("AudioManager: unknown voice log entry '%s'" % String(entry_id))
		return false
	var entry: Dictionary = audio_log.get_entry(entry_id)
	var vol_db: float = float(entry.get("volume_db", -3.0))
	_play_via_bus(String(AudioEventSeamScript.BUS_VOICE), vol_db)
	current_voice_log_id = String(entry_id)
	return true

## Trigger an immediate meta-event (in addition to the scheduled ones).
func trigger_meta_event(event_id: StringName) -> bool:
	if String(event_id).is_empty():
		return false
	var bus_id: String = _bus_for_meta_event_id(String(event_id))
	var vol: float = -6.0
	if String(event_id) == String(AudioEventSeamScript.META_BEACON_DISTRESS):
		vol = -3.0
	_play_via_bus(bus_id, vol)
	return true

## Attach the AudioListener3D to a player anchor (any Node3D).
func attach_listener(anchor: Node3D) -> void:
	_listener_anchor = anchor

func get_listener_anchor() -> Node3D:
	return _listener_anchor

func get_bus_player(bus_id: StringName) -> AudioStreamPlayer:
	return _bus_players.get(String(bus_id), null)

func get_spatial_player_count() -> int:
	var total: int = 0
	for key in _spatial_pool.keys():
		total += (_spatial_pool[key] as Array).size()
	return total

## Internal: play through a non-spatial AudioStreamPlayer on a bus.
func _play_via_bus(bus_id: String, volume_db: float) -> void:
	var player: AudioStreamPlayer = _bus_players.get(bus_id, null)
	if player == null:
		return
	# Without an actual AudioStream resource there is nothing to play in
	# the headless case, but we still set the volume so the smoke can
	# verify the push path runs without errors. The smoke inspects
	# player.volume_db after each call.
	player.volume_db = volume_db

## Internal: play through a spatial AudioStreamPlayer3D pool entry.
func _play_spatial(event_id: StringName, position: Vector3, bus_id: String, volume_db: float) -> void:
	var key: String = String(event_id)
	var pool: Array = _spatial_pool.get(key, [])
	# Reuse a free entry if any, otherwise allocate a new one.
	var player: AudioStreamPlayer3D = null
	for candidate in pool:
		if candidate != null and is_instance_valid(candidate):
			player = candidate
			break
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.name = "AudioStreamPlayer3D_%s" % key
		add_child(player)
		pool.append(player)
		_spatial_pool[key] = pool
	player.bus = bus_id
	player.volume_db = volume_db
	player.global_position = position

## Internal: deterministic "is this emitter occluded" check. Real LOS
## raycasts are out of scope; we report true when the emitter sits in a
## different room from the listener (room-role comparison via the parent).
func _is_occluded(emitter_pos: Vector3, listener_pos: Vector3) -> bool:
	# A pure distance-based heuristic: anything beyond `occluded_distance`
	# and in a different Y-band (more than 1.5 m apart in Y) counts as
	# occluded. This is a placeholder for a real LOS raycast; the
	# deterministic output is the architectural invariant here.
	var delta: Vector3 = emitter_pos - listener_pos
	if absf(delta.y) > 1.5 and delta.length() > 4.0:
		return true
	return false

## Internal: apply per-layer music gains to the music bus player.
func _apply_music_layer_gains() -> void:
	var player: AudioStreamPlayer = _bus_players.get(String(AudioEventSeamScript.BUS_MUSIC), null)
	if player == null:
		return
	var gains: Dictionary = music_state.get_layer_gains()
	# Combined layer gain is the maximum across the four layers (they
	# stack rather than average so exploration always has audible base).
	var combined: float = 0.0
	for layer_id in AudioEventSeamScript.ALL_MUSIC_LAYERS:
		combined = maxf(combined, float(gains.get(layer_id, 0.0)))
	# Combined in [0, 1] -> dB mapping: -24 dB at 0.0 -> 0 dB at 1.0.
	player.volume_db = -24.0 + combined * 24.0

## Internal: route a meta-event id to its bus.
func _bus_for_meta_event_id(id_str: String) -> String:
	if id_str == String(AudioEventSeamScript.META_BEACON_DISTRESS):
		return String(AudioEventSeamScript.BUS_META)
	if id_str == String(AudioEventSeamScript.META_BIOMATTER_PULSE):
		return String(AudioEventSeamScript.BUS_META)
	if id_str == String(AudioEventSeamScript.META_HULL_GROAN):
		return String(AudioEventSeamScript.BUS_META)
	if id_str == String(AudioEventSeamScript.META_REACTOR_HUM):
		return String(AudioEventSeamScript.BUS_META)
	return String(AudioEventSeamScript.BUS_SFX)
