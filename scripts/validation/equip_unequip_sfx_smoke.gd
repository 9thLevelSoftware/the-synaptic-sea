extends SceneTree

## Equip routes SFX_TOOL_PICKUP; unequip routes SFX_DROP_ITEM.
## Marker: EQUIP UNEQUIP SFX PASS equip=true unequip=true

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
	if playable.equipment_state == null or playable.inventory_state == null:
		_fail("equipment/inventory"); return
	var mgr: Node = playable.audio_manager
	# Find an equippable item from inventory or inject a known tool.
	var item_id: String = "welding_lance"
	if playable.inventory_state.get_quantity(item_id) < 1:
		playable.inventory_state.add_item(item_id, 1)
	# Clear slot if occupied so equip succeeds.
	if playable.equipment_state.is_slot_occupied("primary_hand"):
		playable._unequip_to_inventory("primary_hand")
	mgr.sfx_router.configure({})
	var e_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_PICKUP))
	if not playable._equip_from_inventory(item_id, false):
		_fail("equip failed"); return
	var e_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_PICKUP))
	if e_after <= e_before:
		_fail("equip sfx before=%d after=%d" % [e_before, e_after]); return
	mgr.sfx_router.configure({})
	var u_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DROP_ITEM))
	var unequipped: String = playable._unequip_to_inventory("primary_hand")
	if unequipped.is_empty():
		# Try any occupied slot.
		for slot in ["primary_hand", "secondary_hand", "suit", "tool_belt"]:
			unequipped = playable._unequip_to_inventory(str(slot))
			if not unequipped.is_empty():
				break
	if unequipped.is_empty():
		_fail("unequip empty"); return
	var u_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DROP_ITEM))
	if u_after <= u_before:
		_fail("unequip sfx before=%d after=%d" % [u_before, u_after]); return
	print("EQUIP UNEQUIP SFX PASS equip=true unequip=true")
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
	print("EQUIP UNEQUIP SFX FAIL: %s" % msg)
	finished = true
	quit(1)
