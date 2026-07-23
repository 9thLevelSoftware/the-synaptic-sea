extends SceneTree

## Encumbrance overload rising-edge SFX works with away_from_start true.
## Marker: ENCUMBRANCE OVERLOAD AWAY PASS away=true overload=true sfx=true

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
	if playable.inventory_state == null:
		_fail("inventory"); return
	var mgr: Node = playable.audio_manager
	if playable.inventory_state.has_method("clear"):
		playable.inventory_state.clear()
	elif playable.inventory_state.has_method("remove_item"):
		for item_id in ["scrap_metal", "alloy", "wiring"]:
			var q: int = int(playable.inventory_state.get_quantity(item_id))
			if q > 0:
				playable.inventory_state.remove_item(item_id, q)
	playable._prev_encumbrance_overloaded = false
	playable._recompute_player_encumbrance()
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_VITALS_LOW))
	playable.inventory_state.add_item("scrap_metal", 40)
	playable._prev_encumbrance_overloaded = false
	playable._recompute_player_encumbrance()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_VITALS_LOW))
	if float(playable.inventory_state.get_load_ratio()) <= 1.0:
		_fail("expected overload away"); return
	if after <= before:
		_fail("UI_VITALS_LOW missing away"); return
	mgr.sfx_router.configure({})
	var b2: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_VITALS_LOW))
	playable._recompute_player_encumbrance()
	var a2: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_VITALS_LOW))
	if a2 != b2:
		_fail("overload SFX re-fired away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("ENCUMBRANCE OVERLOAD AWAY PASS away=true overload=true sfx=true")
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
	print("ENCUMBRANCE OVERLOAD AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
