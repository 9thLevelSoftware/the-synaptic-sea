extends SceneTree

## Cart grab SFX works with away_from_start true.
## Marker: CART GRAB AWAY PASS away=true grab=true sfx=true

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
	var ship_id: String = ""
	if playable.home_ship != null:
		ship_id = str(playable.home_ship.ship_id) if playable.home_ship.get("ship_id") != null else str(playable.home_ship.marker_id)
	if ship_id.is_empty():
		ship_id = "home"
	var cart_id: String = playable.spawn_cart_for_validation(ship_id)
	if cart_id.is_empty():
		_fail("spawn cart ship=%s" % ship_id); return
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_PICKUP))
	playable._on_cart_grab_requested(cart_id)
	if playable.grabbed_cart == null:
		_fail("grab failed cart=%s away" % cart_id); return
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_PICKUP))
	if after <= before:
		_fail("grab sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("CART GRAB AWAY PASS away=true grab=true sfx=true")
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
	print("CART GRAB AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
