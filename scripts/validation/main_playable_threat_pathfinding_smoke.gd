extends SceneTree

## ADR-0049 live-scene: threats path on the main ship layout graph.
## Marker: MAIN PLAYABLE THREAT PATHFINDING PASS graph=true advanced=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
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
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() \
			or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()

func _validate() -> void:
	finished = true
	if playable.threat_manager == null:
		_fail("threat_manager missing")
		return
	var layout: Dictionary = playable._combat_layout_for_current_ship()
	if layout.is_empty():
		_fail("combat layout empty")
		return
	if playable.threat_manager.nav_graph == null or playable.threat_manager.nav_graph.node_count() == 0:
		playable.threat_manager.configure_nav_graph(layout)
	var n: int = playable.threat_manager.nav_graph.node_count() if playable.threat_manager.nav_graph != null else 0
	if n < 4:
		_fail("nav graph too small nodes=%d" % n)
		return
	# Inject a hunting threat at a far floor node.
	var graph = playable.threat_manager.nav_graph
	var keys: Array = graph.nodes.keys()
	keys.sort()
	var start_id: String = str(keys[0])
	var end_id: String = str(keys[keys.size() - 1])
	var start_pos: Vector3 = graph.get_node_pos(start_id)
	var end_pos: Vector3 = graph.get_node_pos(end_id)
	var threat = ThreatAIStateScript.new()
	threat.configure({
		"instance_id": "path_probe",
		"archetype_id": "biomatter_swarm",
		"display_name": "Probe",
		"max_health": 30.0,
		"health": 30.0,
		"world_position": [start_pos.x, start_pos.y, start_pos.z],
		"room_id": graph.get_node_room(start_id),
		"state": "hunt",
		"move_speed": 6.0,
		"hunt_speed_mult": 1.0,
		"attack_range": 0.4,
	})
	playable.threat_manager.threats.append(threat)
	var before: float = start_pos.distance_to(end_pos)
	for i in range(40):
		playable.threat_manager._advance_threat_motion(threat, 0.15, end_pos)
	var after_pos := Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
	var after: float = after_pos.distance_to(end_pos)
	if after >= before - 0.5:
		_fail("threat did not close distance (before=%.2f after=%.2f)" % [before, after])
		return
	# Position remains near some graph node (not through empty space far from graph).
	var nearest: String = graph.nearest_node(after_pos)
	var np: Vector3 = graph.get_node_pos(nearest)
	if after_pos.distance_to(np) > 3.0:
		_fail("threat drifted off graph (dist=%.2f)" % after_pos.distance_to(np))
		return
	print("MAIN PLAYABLE THREAT PATHFINDING PASS graph=true advanced=true nodes=%d" % n)
	_cleanup(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for c in node.get_children():
		var f := _find_playable(c)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("MAIN PLAYABLE THREAT PATHFINDING FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
