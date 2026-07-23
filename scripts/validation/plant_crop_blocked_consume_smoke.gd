extends SceneTree

## try_plant_crop soft-fails consume (busy / missing water) with production_blocked.
## Marker: PLANT CROP BLOCKED CONSUME PASS busy=true missing=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
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
	if playable.inventory_state == null:
		_fail("inventory"); return
	var st = ProductionStationScript.new()
	playable.add_child(st)
	st.station_kind = "hydroponics"
	st.inventory_state = playable.inventory_state
	st.config = {"crops": [{"crop_id": "test_crop", "water_cost": 1.0, "power_cost": 0.0, "required_skill_level": 0}]}
	var model = HydroStateScript.new()
	model.state = HydroStateScript.State.PLANTED
	st.model = model
	if not st.try_plant_crop("test_crop"):
		_fail("busy plant should return true (consume)"); return

	model.state = HydroStateScript.State.IDLE
	# No purified water.
	var q: int = int(playable.inventory_state.get_quantity("purified_water"))
	if q > 0:
		playable.inventory_state.remove_item("purified_water", q)
	if not st.try_plant_crop("test_crop"):
		_fail("missing water plant should return true (consume)"); return
	if model.state != HydroStateScript.State.IDLE:
		_fail("idle model mutated on blocked plant"); return

	print("PLANT CROP BLOCKED CONSUME PASS busy=true missing=true")
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
	print("PLANT CROP BLOCKED CONSUME FAIL: %s" % msg)
	finished = true
	quit(1)
