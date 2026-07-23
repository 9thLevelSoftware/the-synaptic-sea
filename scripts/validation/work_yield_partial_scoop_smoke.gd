extends SceneTree

## Floor WorkYieldDrop: stack-full deny leaves the pile; partial scoop keeps residual.
## Marker: WORK YIELD PARTIAL SCOOP PASS deny=true partial=true residual=true finish=true

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
	if playable.inventory_state == null:
		_fail("inventory"); return

	# --- Deny path: max_stack full → try_interact false, drop stays ---
	playable.inventory_state.items["scrap_metal"] = 20  # max_stack for scrap_metal
	playable._spawn_work_yield_drop({"scrap_metal": 3})
	var drops: Array = playable.get_work_yield_drops_for_validation()
	if drops.is_empty():
		_fail("no drop after spawn"); return
	var drop = drops[0]
	if not is_instance_valid(drop):
		_fail("drop invalid"); return
	drop.set_validation_player_in_range(playable.player)
	if drop.try_interact(playable.player):
		_fail("expected deny when stack full"); return
	if not is_instance_valid(drop):
		_fail("drop freed on deny"); return
	if bool(drop.scooped_flag):
		_fail("scooped_flag set on deny"); return
	var tracked: Array = playable.get_work_yield_drops_for_validation()
	if tracked.is_empty() or not is_instance_valid(tracked[0]):
		_fail("drop untracked on deny"); return
	if int(drop.items.get("scrap_metal", 0)) != 3:
		_fail("items mutated on deny items=%s" % str(drop.items)); return

	# --- Partial scoop: room for 2 of 5; residual 3 remains tracked ---
	playable.inventory_state.items["scrap_metal"] = 18
	# Clear prior drop tracking + free node so partial case is clean.
	if is_instance_valid(drop):
		drop.queue_free()
	playable.work_yield_drops.clear()
	playable._spawn_work_yield_drop({"scrap_metal": 5})
	drops = playable.get_work_yield_drops_for_validation()
	if drops.is_empty():
		_fail("no drop for partial"); return
	drop = drops[0]
	drop.set_validation_player_in_range(playable.player)
	var qty_before: int = int(playable.inventory_state.get_quantity("scrap_metal"))
	if not drop.try_interact(playable.player):
		_fail("partial scoop failed"); return
	var qty_mid: int = int(playable.inventory_state.get_quantity("scrap_metal"))
	if qty_mid != qty_before + 2:
		_fail("partial grant expected +2 got %d->%d" % [qty_before, qty_mid]); return
	if not is_instance_valid(drop):
		_fail("drop freed on partial"); return
	if bool(drop.scooped_flag):
		_fail("scooped_flag on partial"); return
	if int(drop.items.get("scrap_metal", 0)) != 3:
		_fail("residual expected 3 got %s" % str(drop.items)); return
	tracked = playable.get_work_yield_drops_for_validation()
	if tracked.is_empty():
		_fail("partial untracked residual"); return

	# --- Finish residual when stack has room ---
	playable.inventory_state.items["scrap_metal"] = 10
	if not drop.try_interact(playable.player):
		_fail("finish scoop failed"); return
	var qty_end: int = int(playable.inventory_state.get_quantity("scrap_metal"))
	if qty_end != 13:
		_fail("finish grant expected 13 got %d" % qty_end); return
	if not bool(drop.scooped_flag):
		_fail("scooped_flag not set on finish"); return
	tracked = playable.get_work_yield_drops_for_validation()
	for d in tracked:
		if is_instance_valid(d) and str(d.drop_id) == str(drop.drop_id):
			_fail("fully scooped drop still tracked"); return

	print("WORK YIELD PARTIAL SCOOP PASS deny=true partial=true residual=true finish=true")
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
	print("WORK YIELD PARTIAL SCOOP FAIL: %s" % msg)
	finished = true
	quit(1)
