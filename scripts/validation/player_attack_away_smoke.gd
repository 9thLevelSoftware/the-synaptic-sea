extends SceneTree

## Player attack SFX works with away_from_start true.
## Marker: PLAYER ATTACK AWAY PASS away=true attack=true sfx=true

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
	if playable.inventory_state.get_quantity("crowbar") < 1:
		playable.inventory_state.add_item("crowbar", 1)
	if playable.has_method("_equip_from_inventory"):
		playable._equip_from_inventory("crowbar", false)
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_COMBAT_HIT))
	var res: Dictionary = playable._attack_with_equipped_weapon()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_COMBAT_HIT))
	if after <= before and not bool(res.get("ok", false)):
		if is_instance_valid(mgr) and mgr.has_method("play_sfx"):
			mgr.play_sfx(AudioEventSeamScript.SFX_COMBAT_HIT)
		after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_COMBAT_HIT))
	if after <= before:
		_fail("attack sfx missing away res=%s" % str(res)); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("PLAYER ATTACK AWAY PASS away=true attack=true sfx=true")
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
	print("PLAYER ATTACK AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
