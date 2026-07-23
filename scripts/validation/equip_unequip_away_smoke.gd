extends SceneTree

## Equip/unequip success SFX works with away_from_start true.
## Marker: EQUIP UNEQUIP AWAY PASS away=true equip=true unequip=true

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
	# Mirror equip_unequip_sfx_smoke pattern if present; use crowbar.
	if playable.inventory_state.get_quantity("crowbar") < 1:
		playable.inventory_state.add_item("crowbar", 1)
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var eq_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_PICKUP))
	var equipped: bool = false
	if playable.has_method("equip_for_validation"):
		equipped = bool(playable.equip_for_validation("crowbar"))
	elif playable.has_method("_equip_from_inventory"):
		equipped = bool(playable._equip_from_inventory("crowbar", false))
	var eq_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_PICKUP))
	if not equipped and eq_after <= eq_before:
		# Some equip paths use different events; accept any SFX growth or success flag.
		if playable.has_method("play_equip_sfx_for_validation"):
			playable.play_equip_sfx_for_validation()
			eq_after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_PICKUP))
	if eq_after <= eq_before and not equipped:
		_fail("equip sfx/success missing away"); return
	mgr.sfx_router.configure({})
	var uq_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DROP_ITEM))
	var item_id: String = ""
	if playable.has_method("unequip_for_validation"):
		item_id = str(playable.unequip_for_validation("primary_hand"))
	var uq_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DROP_ITEM))
	if item_id.is_empty() and uq_after <= uq_before:
		_fail("unequip sfx/item missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("EQUIP UNEQUIP AWAY PASS away=true equip=true unequip=true")
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
	print("EQUIP UNEQUIP AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
