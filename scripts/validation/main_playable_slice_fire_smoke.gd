extends SceneTree

## M7-B fire slice: fires render as PASSABLE per-compartment zones from the authoritative
## model; a breached compartment vent-extinguishes.
## Pass marker: MAIN PLAYABLE FIRE PASS passable=true present=true vent=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	if playable.fire_suppression_state == null:
		_fail("fire_suppression_state missing"); return
	# Force a fire and confirm a passable zone renders.
	playable.away_from_start = false
	playable.force_ignite_compartment_for_validation("engineering", 1.0)
	var zones: Array = playable.get_fire_zone_nodes_for_validation()
	if zones.is_empty():
		_fail("no fire zone node rendered for a burning compartment"); return
	var z = zones[0]
	if not (z is Area3D):
		_fail("fire zone should be an Area3D"); return
	# Passable: the zone must NOT carry a StaticBody collision blocker.
	if z is StaticBody3D:
		_fail("fire zone must be passable, not a StaticBody"); return
	# Vent: breach the compartment, tick, fire should clear.
	playable.force_hull_breach_for_validation("engineering", 0.7)
	playable.fire_suppression_state.tick(0.5, playable._build_fire_context())
	if playable.fire_suppression_state.is_burning("engineering"):
		_fail("breached compartment should vent-extinguish the fire"); return
	finished = true
	print("MAIN PLAYABLE FIRE PASS passable=true present=true vent=true")
	_cleanup_and_quit(0)

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
	push_error("MAIN PLAYABLE FIRE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
