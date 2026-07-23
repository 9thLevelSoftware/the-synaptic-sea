extends SceneTree

## Tool pickup already-owned deny SFX works with away_from_start true.
## Marker: TOOL PICKUP DENIED AWAY PASS away=true deny=true sfx=true remain=true

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
	if playable.tool_pickup == null or not is_instance_valid(playable.tool_pickup):
		_fail("no tool_pickup"); return
	if playable.inventory_state == null or playable.player == null:
		_fail("inventory/player"); return

	var pickup = playable.tool_pickup
	var tool_id: String = str(pickup.tool_id)
	playable.inventory_state.add_tool(tool_id)
	if not playable.inventory_state.has_tool(tool_id):
		_fail("could not pre-own tool"); return

	if pickup is Node3D and playable.player is Node3D:
		(playable.player as Node3D).global_position = (pickup as Node3D).global_position
	if pickup.has_method("set_validation_player_in_range"):
		pickup.set_validation_player_in_range(playable.player)

	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var handled: bool = playable._try_tool_pickup_interact(pickup, playable.player)
	if not handled:
		_fail("interact not consumed on already-owned deny away"); return
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		_fail("deny sfx missing away"); return
	if bool(pickup.acquired):
		_fail("pickup marked acquired on deny away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return

	print("TOOL PICKUP DENIED AWAY PASS away=true deny=true sfx=true remain=true")
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
	print("TOOL PICKUP DENIED AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
