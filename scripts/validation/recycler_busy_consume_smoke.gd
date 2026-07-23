extends SceneTree

## Water recycler RECYCLING state consumes interact with production_blocked.
## Marker: RECYCLER BUSY CONSUME PASS recycling=true consume=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ProductionStationScript := preload("res://scripts/tools/production_station.gd")
const RecyclerStateScript := preload("res://scripts/systems/water_recycler_state.gd")
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
	if playable.player == null or playable.inventory_state == null:
		_fail("player/inventory"); return
	var st = ProductionStationScript.new()
	playable.add_child(st)
	st.station_kind = "water_recycler"
	st.inventory_state = playable.inventory_state
	var model = RecyclerStateScript.new()
	model.state = RecyclerStateScript.State.RECYCLING
	st.model = model
	st.global_position = (playable.player as Node3D).global_position
	if st.has_method("set_validation_player_in_range"):
		st.set_validation_player_in_range(playable.player)
	if not st.try_interact(playable.player):
		_fail("recycler recycling did not consume interact"); return
	print("RECYCLER BUSY CONSUME PASS recycling=true consume=true")
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
	print("RECYCLER BUSY CONSUME FAIL: %s" % msg)
	finished = true
	quit(1)
