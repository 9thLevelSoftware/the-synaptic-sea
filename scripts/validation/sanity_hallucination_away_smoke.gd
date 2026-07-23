extends SceneTree

## Sanity hallucination SFX works with away_from_start true.
## Marker: SANITY HALLUCINATION AWAY PASS away=true phantom=true hud=true ambient=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()


func _validate() -> void:
	finished = true
	playable.away_from_start = true
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	var mgr_h = playable.get_hallucination_manager_for_validation()
	var dir = playable.get_hallucination_director_for_validation()
	if mgr_h == null or dir == null:
		_fail("hallucination runtime"); return
	if not dir.has_method("force_trigger"):
		_fail("no force_trigger"); return
	if dir.pool == null and dir.has_method("configure"):
		dir.configure({"seed": 1})
	var router = playable.audio_manager.sfx_router
	router.configure({})
	dir.active_events.clear()
	var p_id: int = int(dir.force_trigger("phantom_crew_silhouette", Vector3(2, 0, 2), 10.0))
	var h_id: int = int(dir.force_trigger("hud_false_oxygen", null, 10.0))
	var a_id: int = int(dir.force_trigger("ambient_static_hiss", null, 10.0))
	if p_id < 0 or h_id < 0 or a_id < 0:
		_fail("force_trigger failed away p=%d h=%d a=%d" % [p_id, h_id, a_id]); return
	mgr_h._prev_hud_active = false
	mgr_h._ambient_cooldown = 0.0
	mgr_h.clear_all()
	mgr_h.set_channels(playable.audio_manager, null)
	var p_before: int = int(router.get_routed_count(AudioEventSeamScript.SFX_SANITY_PHANTOM))
	var h_before: int = int(router.get_routed_count(AudioEventSeamScript.SFX_SANITY_HUD))
	var a_before: int = int(router.get_routed_count(AudioEventSeamScript.SFX_SANITY_AMBIENT))
	mgr_h.render(0.5, Vector3.ZERO)
	var p_after: int = int(router.get_routed_count(AudioEventSeamScript.SFX_SANITY_PHANTOM))
	var h_after: int = int(router.get_routed_count(AudioEventSeamScript.SFX_SANITY_HUD))
	var a_after: int = int(router.get_routed_count(AudioEventSeamScript.SFX_SANITY_AMBIENT))
	if p_after <= p_before:
		_fail("phantom sfx missing away"); return
	if h_after <= h_before:
		_fail("hud sfx missing away"); return
	if a_after <= a_before:
		_fail("ambient sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("SANITY HALLUCINATION AWAY PASS away=true phantom=true hud=true ambient=true")
	quit(0)


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	print("SANITY HALLUCINATION AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
