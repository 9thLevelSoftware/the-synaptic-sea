extends SceneTree

## Craft busy / hydro in-progress consume interact (still emit blocked).
## Marker: STATION BUSY CONSUME PASS craft=true hydro=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const CraftingStationScript := preload("res://scripts/tools/crafting_station.gd")
const ProductionStationScript := preload("res://scripts/tools/production_station.gd")
const HydroStateScript := preload("res://scripts/systems/hydroponics_state.gd")
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

	var pos: Vector3 = (playable.player as Node3D).global_position

	# Crafting station with busy craft mock.
	var st = CraftingStationScript.new()
	playable.add_child(st)
	st.station_kind = "workbench"
	st.inventory_state = playable.inventory_state
	st.crafting_state = _BusyCraftMock.new()
	st.global_position = pos
	if st.has_method("set_validation_player_in_range"):
		st.set_validation_player_in_range(playable.player)
	if not st.try_interact(playable.player):
		_fail("craft busy did not consume interact"); return

	# Hydro planted (in progress).
	var hydro = ProductionStationScript.new()
	playable.add_child(hydro)
	hydro.station_kind = "hydroponics"
	hydro.inventory_state = playable.inventory_state
	var model = HydroStateScript.new()
	model.state = HydroStateScript.State.PLANTED
	hydro.model = model
	hydro.global_position = pos
	if hydro.has_method("set_validation_player_in_range"):
		hydro.set_validation_player_in_range(playable.player)
	if not hydro.try_interact(playable.player):
		_fail("hydro in_progress did not consume interact"); return

	print("STATION BUSY CONSUME PASS craft=true hydro=true")
	quit(0)


class _BusyCraftMock:
	extends RefCounted
	func is_crafting() -> bool:
		return true


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	print("STATION BUSY CONSUME FAIL: %s" % msg)
	finished = true
	quit(1)
