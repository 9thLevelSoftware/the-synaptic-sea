extends SceneTree

## Main-scene cooking integration smoke.
## Loads the playable scene, starts a cook, ticks to completion, and asserts
## the cooking state is present in the run snapshot. Exits quickly; does not
## walk the full objective chain.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if not playable.playable_started:
		return

	# Seed inventory with cooking ingredients once
	if playable.inventory_state != null and playable.inventory_state.get_quantity("ration_pack") < 2:
		playable.inventory_state.add_item("ration_pack", 2)
		playable.inventory_state.add_item("purified_water", 2)

	# Configure and start cooking once
	if playable.cooking_state != null and playable.cooking_state.state == 0:  # IDLE
		playable.cooking_state.configure({
			"recipe_id": "cooked_meal_basic",
			"display_name": "Basic Cooked Meal",
			"ingredients": {"ration_pack": 1, "purified_water": 1},
			"produces": {"item_id": "cooked_meal", "quantity": 1},
			"power_cost": 5.0,
			"cook_time_seconds": 2.0,
			"required_skill_level": 0,
			"station_kind": "galley",
		})
		var inv_summary: Dictionary = playable.inventory_state.get_summary() if playable.inventory_state != null else {"items": {}}
		var result: Dictionary = playable.cooking_state.start_cooking(inv_summary, 0, 10.0)
		if not result.get("ok", false):
			_fail("cooking start failed: %s" % result.get("reason", ""))
			return

	# Wait for completion (2.0s cook time)
	if playable.cooking_state != null and playable.cooking_state.is_complete():
		var collect_result: Dictionary = playable.cooking_state.collect_result()
		if not collect_result.get("ok", false):
			_fail("collect_result failed")
			return
		if collect_result.get("item_id", "") != "cooked_meal":
			_fail("collect_result item_id mismatch")
			return

		# Verify the snapshot captures cooking state
		var snapshot = playable._build_run_snapshot()
		if snapshot == null:
			_fail("snapshot is null")
			return
		if snapshot.cooking_summary.is_empty():
			_fail("cooking_summary missing from snapshot")
			return
		if snapshot.spoilage_summary.is_empty():
			_fail("spoilage_summary missing from snapshot")
			return

		finished = true
		print("MAIN PLAYABLE COOKING PASS cooking_started=true completed=true item=cooked_meal snapshot=ok")
		quit(0)

	if frame_count > TIMEOUT_FRAMES:
		_fail("timeout waiting for cooking completion")

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
	push_error("MAIN PLAYABLE COOKING FAIL reason=%s" % reason)
	quit(1)
