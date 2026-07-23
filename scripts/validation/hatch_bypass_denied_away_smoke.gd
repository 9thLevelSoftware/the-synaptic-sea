extends SceneTree

## Locked hatch deny SFX works on away (derelict) context.
## Marker: HATCH BYPASS DENIED AWAY PASS away=true locked=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SealedHatchScript := preload("res://scripts/interaction/sealed_hatch.gd")
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
	if playable.player == null:
		_fail("player"); return

	var hatch = SealedHatchScript.new()
	var pos: Vector3 = (playable.player as Node3D).global_position
	hatch.configure("deny_hatch_away", SealedHatchScript.MECHANICAL, pos, 1.8, "a", "b")
	playable.add_child(hatch)
	playable.sealed_hatches.append(hatch)
	if playable.utility_item_state != null:
		playable.utility_item_state.active_flags.clear()

	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var handled: bool = playable._try_bypass_nearest_hatch()
	if not handled:
		_fail("locked hatch did not consume interact away"); return
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		_fail("deny sfx missing away"); return
	if bool(hatch.bypassed):
		_fail("hatch opened without flag"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return

	print("HATCH BYPASS DENIED AWAY PASS away=true locked=true sfx=true")
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
	print("HATCH BYPASS DENIED AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
