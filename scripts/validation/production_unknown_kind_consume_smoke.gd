extends SceneTree

## Unknown production station_kind soft-blocks and consumes interact.
## Marker: PRODUCTION UNKNOWN KIND CONSUME PASS blocked=true consume=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ProductionStationScript := preload("res://scripts/tools/production_station.gd")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false
var blocked: bool = false


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
	st.station_kind = "not_a_real_station"
	st.inventory_state = playable.inventory_state
	st.model = RefCounted.new()
	st.production_blocked.connect(func(_k, _r): blocked = true)
	st.global_position = (playable.player as Node3D).global_position
	if not st.try_interact(playable.player):
		_fail("unknown kind should consume interact"); return
	if not blocked:
		_fail("production_blocked not emitted"); return
	print("PRODUCTION UNKNOWN KIND CONSUME PASS blocked=true consume=true")
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
	print("PRODUCTION UNKNOWN KIND CONSUME FAIL: %s" % msg)
	finished = true
	quit(1)
