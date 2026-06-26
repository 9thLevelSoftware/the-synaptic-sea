extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > 300:
			print("TIMEOUT")
			quit(1)
		return
	# Configure with non-default values, zero drain
	playable.vitals_state.configure({
		"health": 72.0, "stamina": 55.0, "hunger": 25.0, "thirst": 18.0,
		"health_drain_rate": 0.0, "stamina_drain_rate": 0.0,
		"hunger_drain_rate": 0.0, "thirst_drain_rate": 0.0,
	})
	print("after configure: health=" + str(playable.vitals_state.health))
	var snapshot = playable._build_run_snapshot()
	print("snapshot vitals_summary health=" + str(snapshot.vitals_summary.get("health")))
	playable.vitals_state.configure({})
	print("after reset: health=" + str(playable.vitals_state.health))
	playable.vitals_state.apply_summary(snapshot.vitals_summary)
	print("after apply: health=" + str(playable.vitals_state.health))
	quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null
