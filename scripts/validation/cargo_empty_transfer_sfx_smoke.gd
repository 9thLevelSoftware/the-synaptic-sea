extends SceneTree

## Empty cargo/cart bulk transfer routes deny SFX; panel deposit-all empty also denies.
## Marker: CARGO EMPTY TRANSFER SFX PASS deposit=true withdraw=true panel=true

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
		_fail("home/inventory"); return
	var mgr: Node = playable.audio_manager
	var ship_id: String = str(playable.home_ship.ship_id)

	# Strip haulables so bulk deposit has nothing to move.
	for id in playable.inventory_state.items.keys().duplicate():
		var cat: String = str(playable.inventory_state.get_category(str(id)))
		if cat == "part" or cat == "supply":
			playable.inventory_state.remove_item(str(id), int(playable.inventory_state.get_quantity(str(id))))

	mgr.sfx_router.configure({})
	var d_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var moved: int = int(playable.cargo_deposit_for_validation(ship_id))
	var d_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if moved != 0:
		_fail("expected empty deposit moved=0 got %d" % moved); return
	if d_after <= d_before:
		_fail("empty deposit deny sfx missing"); return

	mgr.sfx_router.configure({})
	var w_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var withdrawn: int = int(playable.cargo_withdraw_for_validation(ship_id, "part"))
	var w_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if withdrawn != 0:
		_fail("expected empty withdraw moved=0 got %d" % withdrawn); return
	if w_after <= w_before:
		_fail("empty withdraw deny sfx missing"); return

	# Panel deposit-all with nothing haulable.
	if not is_instance_valid(playable.inventory_panel):
		_fail("inventory_panel"); return
	playable.inventory_panel.set_audio_manager(playable.audio_manager)
	var hold = playable.home_ship.get_inventory()
	playable.inventory_panel.open_transfer(playable.inventory_state, hold, "Hold", playable.equipment_state)
	mgr.sfx_router.configure({})
	var p_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var bulk: int = int(playable.inventory_panel.deposit_all_to_container())
	var p_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if bulk != 0:
		_fail("panel deposit_all expected 0 got %d" % bulk); return
	if p_after <= p_before:
		_fail("panel empty deposit-all deny sfx missing"); return

	print("CARGO EMPTY TRANSFER SFX PASS deposit=true withdraw=true panel=true")
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
	print("CARGO EMPTY TRANSFER SFX FAIL: %s" % msg)
	finished = true
	quit(1)
