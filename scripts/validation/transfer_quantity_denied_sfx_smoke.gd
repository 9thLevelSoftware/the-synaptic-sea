extends SceneTree

## Inventory panel transfer_quantity with nothing movable routes deny SFX.
## Marker: TRANSFER QUANTITY DENIED SFX PASS deny=true sfx=true

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
	if not is_instance_valid(playable.inventory_panel) or playable.home_ship == null:
		_fail("panel/home"); return
	var panel = playable.inventory_panel
	panel.set_audio_manager(playable.audio_manager)
	var hold = playable.home_ship.get_inventory()
	panel.open_transfer(playable.inventory_state, hold, "Hold", playable.equipment_state)

	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	# Request a quantity of an item that is not present / cannot move.
	var moved: int = int(panel.transfer_quantity("self", "scrap_metal_missing", 1))
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if moved != 0:
		_fail("expected moved=0 got %d" % moved); return
	if after <= before:
		_fail("deny sfx not routed before=%d after=%d" % [before, after]); return

	print("TRANSFER QUANTITY DENIED SFX PASS deny=true sfx=true")
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
	print("TRANSFER QUANTITY DENIED SFX FAIL: %s" % msg)
	finished = true
	quit(1)
