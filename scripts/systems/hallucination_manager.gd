extends Node3D
class_name HallucinationManager

## Scene driver for sanity hallucinations. Renders the HallucinationDirector's active
## events. THIS TASK: the phantom-threat channel only (HUD/ambient/FX added in Task 5).
## Phantoms are this node's OWN children, never in ThreatManager — real combat math is
## untouched. Phantoms deal no damage; they dissipate on attack or melee proximity.

const ThreatPlaceholderRendererScript := preload("res://scripts/tools/threat_placeholder_renderer.gd")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")

var director  # HallucinationDirector
var melee_range: float = 1.2
var _phantom_nodes: Dictionary = {}   # event_id (int) -> Node3D
const PHANTOM_ARCHETYPE := "stalker"  # neutral phantom look; deterministic, no real id leak

# Task 5 channels: false-HUD lines, ambient cues, and screen FX.
var _audio_manager = null
var _fx_overlay = null   # a CanvasItem/Node carrying a hallucination_intensity meta, or null
var _ambient_cooldown: float = 0.0
var _prev_hud_active: bool = false

func configure(p_director) -> void:
	director = p_director

## Wire the non-phantom channels. audio_manager drives ambient cues (play_sfx);
## fx_overlay receives a continuous hallucination_intensity (0..1). Either may be null.
func set_channels(audio_manager, fx_overlay) -> void:
	_audio_manager = audio_manager
	_fx_overlay = fx_overlay

## False-HUD readouts (phantom blips / wrong bearings) for the coordinator to merge
## into the tracker status lines. Derived deterministically from the director's hud events.
func get_hallucinated_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if director == null:
		return lines
	for e in director.get_active_events("hud"):
		lines.append("CONTACT? bearing %d" % (int(e["id"]) * 37 % 360))
	return lines

func render(delta: float, player_position: Vector3) -> void:
	if director == null:
		clear_all()
		return
	var events: Array = director.get_active_events("phantom")
	var live_ids: Dictionary = {}
	for e in events:
		var id: int = int(e["id"])
		live_ids[id] = true
		if not _phantom_nodes.has(id):
			var pos: Vector3 = e["position"]
			var node := ThreatPlaceholderRendererScript.build_placeholder(PHANTOM_ARCHETYPE, ["phantom"], pos)
			node.name = "Phantom_%d" % id
			node.set_meta("is_phantom", true)
			add_child(node)
			_phantom_nodes[id] = node
			# New phantom spawn — prefer pool audio_event, else SFX_SANITY_PHANTOM.
			if _audio_manager != null and _audio_manager.has_method("play_sfx"):
				var ae: String = str(e.get("audio_event", ""))
				if ae.is_empty():
					_audio_manager.play_sfx(AudioEventSeamScript.SFX_SANITY_PHANTOM)
				else:
					_audio_manager.play_sfx(StringName(ae))
	# Free phantom nodes whose event expired.
	for id in _phantom_nodes.keys():
		if not live_ids.has(id):
			_free_phantom(id)
	# Dissipate phantoms the player has walked into.
	for id in _phantom_nodes.keys():
		var n = _phantom_nodes[id]
		if is_instance_valid(n) and (n as Node3D).global_position.distance_to(player_position) <= melee_range:
			_free_phantom(id)

	# Ambient cues (cooldown-gated so a long tier-3 stay doesn't spam the router).
	_ambient_cooldown = maxf(0.0, _ambient_cooldown - delta)
	if _audio_manager != null and not director.get_active_events("ambient").is_empty() and _ambient_cooldown <= 0.0:
		if _audio_manager.has_method("play_sfx"):
			# Whisper (legacy ambient) + dedicated sanity ambient catalog id.
			_audio_manager.play_sfx(_ambient_sfx_id())
			_audio_manager.play_sfx(AudioEventSeamScript.SFX_SANITY_AMBIENT)
		_ambient_cooldown = 2.0

	# False-HUD glitch once per rising edge into active HUD hallucinations.
	var hud_active: bool = not director.get_active_events("hud").is_empty()
	if hud_active and not _prev_hud_active and _audio_manager != null and _audio_manager.has_method("play_sfx"):
		_audio_manager.play_sfx(AudioEventSeamScript.SFX_SANITY_HUD)
	_prev_hud_active = hud_active

	# Screen FX intensity from tier.
	if _fx_overlay != null and is_instance_valid(_fx_overlay):
		_fx_overlay.set_meta("hallucination_intensity", director.get_fx_intensity())

## Vanish the nearest phantom within attack_range; returns whether one was dissipated.
func dissipate_phantom_in_range(player_position: Vector3, attack_range: float = 1.6) -> bool:
	var best_id: int = -1
	var best_d: float = attack_range
	for id in _phantom_nodes.keys():
		var n = _phantom_nodes[id]
		if not is_instance_valid(n):
			continue
		var d: float = (n as Node3D).global_position.distance_to(player_position)
		if d <= best_d:
			best_d = d
			best_id = id
	if best_id >= 0:
		_free_phantom(best_id)
		return true
	return false

func phantom_count() -> int:
	var n: int = 0
	for id in _phantom_nodes.keys():
		if is_instance_valid(_phantom_nodes[id]):
			n += 1
	return n

func clear_all() -> void:
	for id in _phantom_nodes.keys():
		_free_phantom(id)
	_phantom_nodes.clear()
	if _fx_overlay != null and is_instance_valid(_fx_overlay):
		_fx_overlay.set_meta("hallucination_intensity", 0.0)

## Resolve the ambient hallucination SFX id from the audio seam (single source of
## truth for audio ids). Falls back to a literal only if the constant is absent.
func _ambient_sfx_id() -> StringName:
	# Single source of truth for the audio id. The constant is defined on the seam and the
	# sfx_event_router has a matching catalog entry, so reference it directly — the previous
	# `"X" in SeamScript` check always returned false (script constants are not properties),
	# which silently used a wrong id the router could not resolve.
	return AudioEventSeamScript.SFX_HALLUCINATION_WHISPER

func _free_phantom(id: int) -> void:
	var n = _phantom_nodes.get(id, null)
	if is_instance_valid(n):
		if is_instance_valid(n.get_parent()):
			n.get_parent().remove_child(n)
		n.queue_free()
	_phantom_nodes.erase(id)
	# Remove the director event too, else render() rebuilds the phantom next frame and the
	# commit-to-reveal counterplay is defeated (the phantom reappears until its TTL).
	if is_instance_valid(director) and director.has_method("remove_event"):
		director.remove_event(id)
