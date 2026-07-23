extends SceneTree

## Cargo hold bulk deposit/withdraw routes drop/pickup SFX when items move.
## Marker: CARGO BULK TRANSFER SFX PASS deposit=true withdraw=true

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
	if playable.home_ship == null or playable.inventory_state == null:
		_fail("home/inventory missing"); return
	var mgr: Node = playable.audio_manager
	var ship_id: String = str(playable.home_ship.ship_id)

	playable.inventory_state.add_item("scrap_metal", 3)
	mgr.sfx_router.configure({})
	var dep_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DROP_ITEM))
	var moved: int = int(playable.cargo_deposit_for_validation(ship_id))
	var dep_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DROP_ITEM))
	if moved <= 0:
		_fail("cargo deposit moved=0"); return
	if dep_after <= dep_before:
		_fail("deposit SFX missing before=%d after=%d" % [dep_before, dep_after]); return

	mgr.sfx_router.configure({})
	var w_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_PICKUP))
	# scrap_metal is category "part" (haulable).
	var withdrawn: int = int(playable.cargo_withdraw_for_validation(ship_id, "part"))
	var w_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_PICKUP))
	if withdrawn <= 0:
		_fail("cargo withdraw moved=0"); return
	if w_after <= w_before:
		_fail("withdraw SFX missing before=%d after=%d" % [w_before, w_after]); return

	print("CARGO BULK TRANSFER SFX PASS deposit=true withdraw=true")
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
	print("CARGO BULK TRANSFER SFX FAIL: %s" % msg)
	finished = true
	quit(1)
