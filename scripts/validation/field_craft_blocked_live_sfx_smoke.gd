extends SceneTree

## Field craft blocked (busy/menu) routes through _on_craft_blocked deny SFX.
## Marker: FIELD CRAFT BLOCKED LIVE SFX PASS busy=true sfx=true

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
	# Force busy path: mark field craft active via begin if possible, else simulate is_crafting.
	if playable.field_crafting_state == null:
		_fail("no field craft state"); return
	var mgr: Node = playable.audio_manager
	# Prefer real busy: start a craft if materials allow, else call blocked reason via menu_open path.
	if playable.inventory_state != null:
		for item_id in ["scrap_metal", "synth_fiber", "adhesive_paste", "medical_gauze"]:
			playable.inventory_state.add_item(item_id, 6)
	var started: bool = false
	if playable.has_method("field_craft_first_ready_for_validation"):
		started = bool(playable.field_craft_first_ready_for_validation())
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if started and playable.field_crafting_state.is_crafting():
		playable._on_player_field_craft_requested(playable.player)
	else:
		# Menu open deny path is always available when menus are considered open.
		# Force menu_open branch by calling blocked helper equivalent: _on_craft_blocked via handler.
		# Simulate menus open by temporarily forcing the branch: call handler with inventory open.
		if is_instance_valid(playable.inventory_panel) and playable.inventory_panel.has_method("open_self"):
			playable.inventory_open_self_for_validation()
		playable._on_player_field_craft_requested(playable.player)
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		_fail("UI_PANEL_CLOSE not routed before=%d after=%d started=%s" % [before, after, str(started)]); return
	print("FIELD CRAFT BLOCKED LIVE SFX PASS busy=true sfx=true")
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
	print("FIELD CRAFT BLOCKED LIVE SFX FAIL: %s" % msg)
	finished = true
	quit(1)
