extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

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
	if not playable.has_method("get_readability_summary"):
		_fail("get_readability_summary missing")
		return
	_validate_readability(playable.get_readability_summary())

func _validate_readability(summary: Dictionary) -> void:
	# REQ-011 multi-step repair junction adds a second objective prop for
	# the secondary_coupling step at sequence 2. Both step interactables
	# share the same objective_type ("restore_systems") so both produce
	# ObjectiveBreakerPanel readability props; the total objective_props
	# count is 5 instead of the previous 4 (one per interactable).
	var required_kinds: Array[String] = [
		"ObjectiveSupplyCache",
		"ObjectiveBreakerPanel",
		"ObjectiveMedTerminal",
		"ObjectiveReactorConsole",
	]
	var kinds: Array = summary.get("objective_prop_kinds", [])
	if int(summary.get("objective_props", 0)) != 5:
		_fail("objective_props=%d expected 5 (1 + 2 junction steps + 1 + 1)" % int(summary.get("objective_props", 0)))
		return
	for kind in required_kinds:
		if not kinds.has(kind):
			_fail("missing objective prop kind=%s kinds=%s" % [kind, str(kinds)])
			return
	if int(summary.get("blocked_props", 0)) != 1:
		_fail("blocked_props=%d" % int(summary.get("blocked_props", 0)))
		return
	if int(summary.get("ramp_props", 0)) != 1:
		_fail("ramp_props=%d" % int(summary.get("ramp_props", 0)))
		return
	if int(summary.get("entry_beacons", 0)) < 1:
		_fail("entry_beacons=%d" % int(summary.get("entry_beacons", 0)))
		return
	if int(summary.get("destination_markers", 0)) < 1:
		_fail("destination_markers=%d" % int(summary.get("destination_markers", 0)))
		return
	if int(summary.get("route_cues", 0)) < 1:
		_fail("route_cues=%d" % int(summary.get("route_cues", 0)))
		return
	if int(summary.get("visible_label3d_count", 0)) != 0:
		_fail("visible_label3d_count=%d" % int(summary.get("visible_label3d_count", 0)))
		return
	if int(summary.get("visible_interaction_markers", 0)) != 0:
		_fail("visible_interaction_markers=%d" % int(summary.get("visible_interaction_markers", 0)))
		return
	finished = true
	print("MAIN PLAYABLE SLICE READABILITY PASS objective_props=5 blocked=1 ramp=1 entry=%d destination=%d route_cues=%d labels=0" % [int(summary.get("entry_beacons", 0)), int(summary.get("destination_markers", 0)), int(summary.get("route_cues", 0))])
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
	push_error("MAIN PLAYABLE SLICE READABILITY FAIL reason=%s" % reason)
	quit(1)
