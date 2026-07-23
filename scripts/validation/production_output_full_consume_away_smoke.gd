extends SceneTree

## Production output full consume works with away_from_start true.
## Marker: PRODUCTION OUTPUT FULL CONSUME AWAY PASS away=true hydro=true recycler=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ProductionStationScript := preload("res://scripts/tools/production_station.gd")
const HydroStateScript := preload("res://scripts/systems/hydroponics_state.gd")
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
	playable.away_from_start = true
	if playable.player == null or playable.inventory_state == null:
		_fail("player/inventory"); return
	var pos: Vector3 = (playable.player as Node3D).global_position
	playable.inventory_state.items["purified_water"] = 20

	var hydro = ProductionStationScript.new()
	playable.add_child(hydro)
	hydro.station_kind = "hydroponics"
	hydro.inventory_state = playable.inventory_state
	var hmodel = HydroStateScript.new()
	hmodel.state = HydroStateScript.State.HARVESTABLE
	hmodel.produce_item_id = "purified_water"
	hmodel.produce_quantity = 1
	hydro.model = hmodel
	hydro.global_position = pos
	if not hydro.try_interact(playable.player):
		_fail("hydro output_full did not consume away"); return
	if hmodel.state != HydroStateScript.State.HARVESTABLE:
		_fail("hydro crop was lost on full bag away"); return

	var rec = ProductionStationScript.new()
	playable.add_child(rec)
	rec.station_kind = "water_recycler"
	rec.inventory_state = playable.inventory_state
	var rmodel = RecyclerStateScript.new()
	rmodel.output_ready = 3
	rmodel.output_item_id = "purified_water"
	rec.model = rmodel
	rec.global_position = pos
	if not rec.try_interact(playable.player):
		_fail("recycler output_full did not consume away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("PRODUCTION OUTPUT FULL CONSUME AWAY PASS away=true hydro=true recycler=true")
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
	print("PRODUCTION OUTPUT FULL CONSUME AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
