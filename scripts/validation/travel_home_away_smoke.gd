extends SceneTree

## travel_home success SFX with explicit dual-branch marker (home smoke already forces away).
## Marker: TRAVEL HOME AWAY PASS away=true home=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 360

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
	if playable.home_ship == null:
		_fail("no home ship"); return
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DOCK_LAND))
	var ok: bool = bool(playable.travel_home())
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DOCK_LAND))
	if not ok:
		_fail("travel_home returned false"); return
	if after <= before:
		_fail("SFX_DOCK_LAND not routed"); return
	print("TRAVEL HOME AWAY PASS away=true home=true sfx=true")
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
	print("TRAVEL HOME AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
