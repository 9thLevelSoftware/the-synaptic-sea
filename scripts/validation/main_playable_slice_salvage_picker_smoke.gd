extends SceneTree

## REQ-CS-017 main-scene: open salvage picker, select a non-first ready target, confirm.

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
	var inv = playable.inventory_state
	if inv == null or playable.deconstruction_resolver == null:
		_fail("models missing")
		return
	if not is_instance_valid(playable.recipe_picker_panel):
		_fail("recipe_picker_panel missing")
		return

	# Seed enough deconstructables so ≥2 salvage targets are ready.
	inv.add_item("plating", 4)
	inv.add_item("power_cell", 4)
	inv.add_item("sensor_module", 2)
	inv.add_item("scrap_metal", 8)
	inv.add_item("wiring_bundle", 4)
	inv.add_item("circuit_board", 2)

	var entries: Array = playable.list_station_recipe_entries("salvage")
	var ready_ids: Array = []
	for e in entries:
		if bool((e as Dictionary).get("craftable", false)):
			ready_ids.append(str((e as Dictionary).get("recipe_id", "")))
	if ready_ids.size() < 2:
		_fail("need >=2 ready salvage targets, got %d" % ready_ids.size())
		return
	var first: String = str(ready_ids[0])
	var chosen: String = str(ready_ids[1])

	if not playable.open_recipe_picker_for_validation("salvage"):
		_fail("salvage picker did not open")
		return
	var panel = playable.recipe_picker_panel
	if panel.get_station_kind() != "salvage":
		_fail("picker not in salvage mode")
		return
	if playable.crafting_state != null and playable.crafting_state.is_crafting():
		_fail("salvage must not start a timed craft")
		return

	var found: bool = false
	for _i in range(panel.get_entry_count() + 2):
		if panel.get_selected_id() == chosen:
			found = true
			break
		panel.move_selection(1)
	if not found:
		_fail("could not select salvage target %s" % chosen)
		return

	# Snapshot inventory for chosen target's primary produce.
	var chosen_entry: Dictionary = {}
	for e in entries:
		if str((e as Dictionary).get("recipe_id", "")) == chosen:
			chosen_entry = e as Dictionary
			break
	var produces: Dictionary = chosen_entry.get("produces", {}) as Dictionary if chosen_entry.get("produces", {}) is Dictionary else {}
	var out_id: String = str(produces.get("item_id", ""))
	var before: int = inv.get_quantity(out_id) if not out_id.is_empty() else 0

	var result: Dictionary = panel.confirm_selection()
	if not bool(result.get("ok", false)):
		_fail("confirm failed: %s" % str(result.get("reason", "")))
		return
	if panel.is_open():
		_fail("panel should close after salvage confirm")
		return
	if chosen == first:
		_fail("chosen_not_first broken")
		return
	if not out_id.is_empty() and inv.get_quantity(out_id) <= before:
		_fail("salvage output not deposited: %s" % out_id)
		return

	finished = true
	print("MAIN PLAYABLE SALVAGE PICKER PASS target=%s chosen_not_first=true salvaged=true" % chosen)
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
