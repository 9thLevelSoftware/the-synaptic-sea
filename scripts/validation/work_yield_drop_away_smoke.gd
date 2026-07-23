extends SceneTree

## Work yield drop SFX works with away_from_start true.
## Marker: WORK YIELD DROP AWAY PASS away=true drop=true sfx=true

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
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DROP_ITEM))
	playable._spawn_work_yield_drop({"scrap_metal": 2})
	var drops: Array = playable.get_work_yield_drops_for_validation()
	if drops.is_empty():
		_fail("no drop spawned away"); return
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DROP_ITEM))
	if after <= before:
		_fail("drop sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WORK YIELD DROP AWAY PASS away=true drop=true sfx=true")
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
	print("WORK YIELD DROP AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
