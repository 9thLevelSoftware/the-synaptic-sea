extends SceneTree

## Partial work-yield scoop works with away_from_start true.
## Marker: WORK YIELD PARTIAL SCOOP AWAY PASS away=true partial=true residual=true finish=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
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
	if playable.inventory_state == null:
		_fail("inventory"); return

	playable.inventory_state.items["scrap_metal"] = 18
	playable.work_yield_drops.clear()
	playable._spawn_work_yield_drop({"scrap_metal": 5})
	var drops: Array = playable.get_work_yield_drops_for_validation()
	if drops.is_empty():
		_fail("no drop"); return
	var drop = drops[0]
	drop.set_validation_player_in_range(playable.player)
	if not drop.try_interact(playable.player):
		_fail("partial scoop failed"); return
	if int(playable.inventory_state.get_quantity("scrap_metal")) != 20:
		_fail("partial grant wrong qty"); return
	if not is_instance_valid(drop) or int(drop.items.get("scrap_metal", 0)) != 3:
		_fail("residual wrong"); return
	if playable.get_work_yield_drops_for_validation().is_empty():
		_fail("partial untracked"); return

	playable.inventory_state.items["scrap_metal"] = 10
	if not drop.try_interact(playable.player):
		_fail("finish scoop failed"); return
	if int(playable.inventory_state.get_quantity("scrap_metal")) != 13:
		_fail("finish grant wrong"); return
	if not bool(drop.scooped_flag):
		_fail("not fully scooped"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return

	print("WORK YIELD PARTIAL SCOOP AWAY PASS away=true partial=true residual=true finish=true")
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
	print("WORK YIELD PARTIAL SCOOP AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
