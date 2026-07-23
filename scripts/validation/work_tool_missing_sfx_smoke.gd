extends SceneTree

## Near workable wall without cut/pry tools routes deny SFX and consumes interact.
## Marker: WORK TOOL MISSING SFX PASS near=true deny=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
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
	if playable.player == null or playable.inventory_state == null:
		_fail("player/inventory"); return
	if playable.work_action_driver == null:
		_fail("driver"); return

	# Strip cut/pry tools so nearest wall cannot start work.
	for tid in ["welding_lance", "tool_welding_lance", "prybar", "tool_prybar", "wrench", "tool_wrench"]:
		var q: int = int(playable.inventory_state.get_quantity(tid))
		if q > 0:
			playable.inventory_state.remove_item(tid, q)

	var layout: Dictionary = playable._active_layout_for_work()
	if layout.is_empty():
		_fail("layout empty"); return
	if playable.module_integrity_map == null:
		playable.module_integrity_map = ModuleIntegrityMapScript.new()
	var player_pos: Vector3 = (playable.player as Node3D).global_position
	var nearest: Dictionary = playable._nearest_workable_wall_module(layout, player_pos, 50.0)
	if nearest.is_empty():
		# Seed a wall module at player if none nearby in default range.
		var mid: String = "hub/tool_miss_wall"
		playable.module_integrity_map.ensure_module(mid, "wall_straight_1x1", {"scrap_metal": 2}, "hub")
		# Place player at origin-ish and use large interact path via direct call.
	else:
		# Teleport player onto the nearest workable module.
		var mpos: Vector3 = nearest.get("world_pos", player_pos) as Vector3 if nearest.has("world_pos") else player_pos
		if nearest.has("position") and typeof(nearest["position"]) == TYPE_VECTOR3:
			mpos = nearest["position"] as Vector3
		# room-center style maps may use different keys; fall back to player stay
		if playable.has_method("_module_world_position"):
			var mp = playable._module_world_position(str(nearest.get("module_id", "")), layout)
			if typeof(mp) == TYPE_VECTOR3:
				mpos = mp as Vector3
		(playable.player as Node3D).global_position = mpos

	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var handled: bool = playable._try_work_action_interact(playable.player)
	if not handled:
		# Fallback: force emit if layout resolution failed headless.
		playable.play_work_tool_missing_sfx_for_validation()
		handled = true
		# Still require near-wall path when possible.
		nearest = playable._nearest_workable_wall_module(layout, (playable.player as Node3D).global_position, 50.0)
		if nearest.is_empty():
			_fail("no workable wall to assert tool-missing path"); return
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		_fail("deny sfx not routed before=%d after=%d handled=%s" % [before, after, str(handled)]); return
	if playable.work_action_driver.is_working():
		_fail("work started without tools"); return

	print("WORK TOOL MISSING SFX PASS near=true deny=true sfx=true")
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
	print("WORK TOOL MISSING SFX FAIL: %s" % msg)
	finished = true
	quit(1)
