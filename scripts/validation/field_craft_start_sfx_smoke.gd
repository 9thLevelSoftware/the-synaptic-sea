extends SceneTree

## Field craft begin routes SFX_TOOL_USE when craft starts.
## Marker: FIELD CRAFT START SFX PASS start=true sfx=true

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
	var mgr: Node = playable.audio_manager
	# Seed field-recipe ingredients (field_splint / field_patch / field_bandage).
	if playable.inventory_state != null:
		for item_id in ["scrap_metal", "adhesive_paste", "synth_fiber", "medical_gauze", "ceramic_plate"]:
			playable.inventory_state.add_item(item_id, 8)
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	var started: bool = false
	if playable.has_method("field_craft_first_ready_for_validation"):
		started = bool(playable.field_craft_first_ready_for_validation())
	if not started and playable.has_method("begin_field_craft_recipe"):
		started = bool(playable.begin_field_craft_recipe("field_splint"))
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if not started:
		_fail("field craft did not start (no ready recipe)"); return
	if after <= before:
		_fail("SFX_TOOL_USE not routed before=%d after=%d" % [before, after]); return
	print("FIELD CRAFT START SFX PASS start=true sfx=true")
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
	print("FIELD CRAFT START SFX FAIL: %s" % msg)
	finished = true
	quit(1)
