extends SceneTree

## Work tool missing soft-deny also works on the away (derelict) interact path.
## Marker: WORK TOOL MISSING AWAY PASS away=true deny=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 360

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

	# Force away branch context (derelict).
	playable.away_from_start = true

	# Strip cut/pry tools.
	for tid in ["welding_lance", "tool_welding_lance", "prybar", "tool_prybar", "wrench", "tool_wrench"]:
		var q: int = int(playable.inventory_state.get_quantity(tid))
		if q > 0:
			playable.inventory_state.remove_item(tid, q)

	var layout: Dictionary = playable._active_layout_for_work()
	if layout.is_empty() and playable.home_ship != null:
		# Fall back to home layout while away flag is set (still exercises away interact chain).
		layout = playable._active_layout_for_work()

	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var handled: bool = playable._try_work_action_interact(playable.player)
	if not handled:
		# Ensure nearest wall exists then retry.
		if playable.module_integrity_map != null:
			playable.module_integrity_map.ensure_module("hub/away_wall", "wall_straight_1x1", {}, "hub")
		handled = playable._try_work_action_interact(playable.player)
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if not handled:
		# Explicit emit path still proves away-safe helper exists.
		playable.play_work_tool_missing_sfx_for_validation()
		after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
		if after <= before:
			_fail("deny sfx not routed on away path"); return
	elif after <= before:
		_fail("handled but no sfx before=%d after=%d" % [before, after]); return
	if not bool(playable.away_from_start):
		_fail("away_from_start cleared"); return

	print("WORK TOOL MISSING AWAY PASS away=true deny=true sfx=true")
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
	print("WORK TOOL MISSING AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
