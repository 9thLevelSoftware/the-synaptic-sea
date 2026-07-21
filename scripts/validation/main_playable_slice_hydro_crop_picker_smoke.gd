extends SceneTree

## REQ-CS-018 main-scene: open hydroponics crop picker, plant a chosen crop.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var exercised: bool = false

func _fail(msg: String) -> void:
	print("FAIL: %s" % msg)
	quit()

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable = _find_playable(main_node)
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
	if exercised:
		return
	exercised = true
	_validate(playable)

func _validate(playable) -> void:
	if playable.inventory_state == null or playable.hydroponics_state == null:
		_fail("models missing")
		return
	if not is_instance_valid(playable.recipe_picker_panel):
		_fail("recipe_picker_panel missing")
		return
	# Power the production band so crops report sufficient power.
	var home_mgr = playable.get_ship_systems_manager()
	if home_mgr != null:
		for sub: String in ["reactor_core", "power_distribution", "battery_cells"]:
			if home_mgr.has_method("force_repair"):
				home_mgr.force_repair("power", sub)
	playable.inventory_state.add_item("purified_water", 12)
	if playable.player_progression != null:
		playable.player_progression.skills["fabrication"] = 6

	var entries: Array = playable.list_station_recipe_entries("hydroponics")
	var ready_ids: Array = []
	for e in entries:
		if bool((e as Dictionary).get("craftable", false)):
			ready_ids.append(str((e as Dictionary).get("recipe_id", "")))
	if ready_ids.is_empty():
		_fail("no ready hydro crops")
		return
	# Prefer a non-first ready crop when both are ready (skill 6 + water).
	var first: String = str(ready_ids[0])
	var chosen: String = str(ready_ids[ready_ids.size() - 1]) if ready_ids.size() > 1 else first
	if not playable.open_recipe_picker_for_validation("hydroponics"):
		_fail("hydro crop picker did not open")
		return
	var panel = playable.recipe_picker_panel
	if panel.get_station_kind() != "hydroponics":
		_fail("picker not in hydroponics mode")
		return
	var found: bool = false
	for _i in range(panel.get_entry_count() + 2):
		if panel.get_selected_id() == chosen:
			found = true
			break
		panel.move_selection(1)
	if not found:
		_fail("could not select crop %s" % chosen)
		return
	var result: Dictionary = panel.confirm_selection()
	if not bool(result.get("ok", false)):
		_fail("confirm failed: %s" % str(result.get("reason", "")))
		return
	if playable.hydroponics_state.crop_id != chosen:
		_fail("planted crop is %s, expected %s" % [playable.hydroponics_state.crop_id, chosen])
		return
	var chosen_not_first: bool = chosen != first if ready_ids.size() > 1 else true
	if ready_ids.size() > 1 and not chosen_not_first:
		_fail("expected non-first crop when multiple ready")
		return

	finished = true
	print("MAIN PLAYABLE HYDRO CROP PICKER PASS crop=%s planted=true chosen_not_first=%s" % [
		chosen, str(chosen_not_first).to_lower()])
	quit()

func _find_playable(node: Node):
	if not is_instance_valid(node):
		return null
	if node.get_script() == load("res://scripts/procgen/playable_generated_ship.gd"):
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null
