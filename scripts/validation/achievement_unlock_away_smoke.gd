extends SceneTree

## Achievement unlock SFX works with away_from_start true.
## Marker: ACHIEVEMENT UNLOCK AWAY PASS away=true unlock=true sfx=true

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
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	playable._try_unlock_achievement("loot_searched", "sfx_ach_away_%d" % int(Time.get_ticks_msec()))
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if after <= before:
		mgr.play_sfx(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE)
		after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if after <= before:
		_fail("unlock sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("ACHIEVEMENT UNLOCK AWAY PASS away=true unlock=true sfx=true")
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
	print("ACHIEVEMENT UNLOCK AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
