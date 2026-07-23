extends SceneTree

## Crossing load_ratio > 1.0 routes UI_VITALS_LOW rising-edge Heavy Load cue.
## Marker: ENCUMBRANCE OVERLOAD SFX PASS overload=true sfx=true

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
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	if playable.inventory_state == null:
		_fail("inventory"); return
	var mgr: Node = playable.audio_manager
	# Drop weight under capacity first so the rising edge is clean.
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
	# Flood inventory with scrap to force overload (scrap_metal weight 5 → 40*5=200).
	playable.inventory_state.add_item("scrap_metal", 40)
	playable._prev_encumbrance_overloaded = false
	playable._recompute_player_encumbrance()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_VITALS_LOW))
	if float(playable.inventory_state.get_load_ratio()) <= 1.0:
		_fail("expected overload load_ratio>1 got %s" % str(playable.inventory_state.get_load_ratio())); return
	if after <= before:
		_fail("UI_VITALS_LOW not routed before=%d after=%d ratio=%s" % [before, after, str(playable.inventory_state.get_load_ratio())]); return
	# Second recompute while still overloaded must not re-fire.
	mgr.sfx_router.configure({})
	var b2: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_VITALS_LOW))
	playable._recompute_player_encumbrance()
	var a2: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_VITALS_LOW))
	if a2 != b2:
		_fail("overload SFX re-fired while still overloaded"); return
	print("ENCUMBRANCE OVERLOAD SFX PASS overload=true sfx=true")
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
	print("ENCUMBRANCE OVERLOAD SFX FAIL: %s" % msg)
	finished = true
	quit(1)
