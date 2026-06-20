extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240
const MIN_HUD_WIDTH: float = 520.0
const MIN_LABEL_WIDTH: float = 480.0

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	_validate_hud(playable)

func _validate_hud(playable: PlayableGeneratedShip) -> void:
	var hud_layer = playable.get("hud_layer")
	if hud_layer == null or not (hud_layer is CanvasLayer):
		_fail("tracker is not parented through CanvasLayer")
		return
	if playable.tracker == null or not (playable.tracker is ObjectiveTracker):
		_fail("tracker is missing or wrong type")
		return
	var tracker: ObjectiveTracker = playable.tracker as ObjectiveTracker
	if tracker.get_parent() != hud_layer:
		_fail("tracker parent is not hud_layer")
		return
	if tracker.size.x < MIN_HUD_WIDTH:
		_fail("tracker width %.1f below %.1f" % [tracker.size.x, MIN_HUD_WIDTH])
		return
	if tracker.label == null:
		_fail("tracker label missing")
		return
	if tracker.label.custom_minimum_size.x < MIN_LABEL_WIDTH:
		_fail("label min width %.1f below %.1f" % [tracker.label.custom_minimum_size.x, MIN_LABEL_WIDTH])
		return
	var hud_text: String = tracker.get_hud_text()
	var required: Array[String] = [
		"Sargasso First Playable",
		"Current: 01 Recover Supplies",
		"Controls: WASD move / E interact",
		"Progress: 0/4",
	]
	for token in required:
		if not hud_text.contains(token):
			_fail("HUD missing token: %s" % token)
			return
	if hud_text.contains("O\nb\nj\ne\nc\nt\ni\nv\ne\ns"):
		_fail("HUD text is wrapping one character per line")
		return
	finished = true
	print("MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=%d current_sequence=1" % int(tracker.size.x))
	quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE SLICE HUD FAIL reason=%s" % reason)
	quit(1)
