extends SceneTree

## Meta hull groan SFX works with away_from_start true.
## Marker: META HULL GROAN AWAY PASS away=true breach=true sfx=true

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
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_HULL_GROAN))
	var cid: String = "engineering"
	if playable.hull_integrity_state != null:
		for k in playable.hull_integrity_state.compartments.keys():
			cid = str(k)
			break
	if not playable.force_hull_breach_for_validation(cid, 0.8):
		_fail("breach failed away cid=%s" % cid); return
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_HULL_GROAN))
	if after <= before:
		_fail("META_HULL_GROAN missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("META HULL GROAN AWAY PASS away=true breach=true sfx=true")
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
	print("META HULL GROAN AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
