extends SceneTree

## REQ-CS-016 main-scene proof: open the live recipe picker on a fabricator,
## select a non-first ready recipe, confirm, and deposit the chosen craft output.

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
	if inv == null or playable.crafting_state == null:
		_fail("crafting models missing")
		return
	if playable.crafting_stations == null or playable.crafting_stations.is_empty():
		_fail("no crafting stations")
		return
	if not is_instance_valid(playable.recipe_picker_panel):
		_fail("recipe_picker_panel not built on HUD")
		return

	# Seed ingredients so multiple fabricator recipes are ready at skill 6.
	inv.add_item("scrap_metal", 20)
	inv.add_item("wiring_bundle", 20)
	inv.add_item("reactive_gel", 12)
	inv.add_item("circuit_board", 12)
	inv.add_item("synth_fiber", 12)
	inv.add_item("titanium_ingot", 10)
	inv.add_item("ceramic_plate", 10)
	inv.add_item("adhesive_paste", 10)
	inv.add_item("polymer_pellet", 10)
	inv.add_item("graphene_sheet", 10)
	playable.material_state.set_quality("scrap_metal", 0.8)
	playable.material_state.set_quality("wiring_bundle", 0.7)
	playable.material_state.set_quality("reactive_gel", 0.9)
	if playable.player_progression != null:
		playable.player_progression.skills["fabrication"] = 6

	var entries: Array = playable.list_station_recipe_entries("fabricator")
	var ready_ids: Array = []
	for e in entries:
		if bool((e as Dictionary).get("craftable", false)):
			ready_ids.append(str((e as Dictionary).get("recipe_id", "")))
	if ready_ids.size() < 2:
		_fail("need >=2 ready fabricator recipes, got %d" % ready_ids.size())
		return
	var first_ready: String = str(ready_ids[0])
	var chosen: String = str(ready_ids[1])
	if chosen.is_empty() or chosen == first_ready:
		_fail("could not pick a non-first ready recipe")
		return

	# Open picker (validation seam dismisses boot main_menu, then drives the
	# live interact → recipe_picker_requested path, with a same-panel fallback).
	if not playable.open_recipe_picker_for_validation("fabricator"):
		_fail("open_recipe_picker_for_validation failed")
		return
	var panel = playable.recipe_picker_panel
	if panel == null or not panel.is_open():
		_fail("recipe picker panel not open after open_recipe_picker_for_validation")
		return
	if playable.crafting_state.is_crafting():
		_fail("craft must not start until confirm")
		return

	# Move cursor to the chosen (second ready) recipe.
	var found: bool = false
	for _i in range(panel.get_entry_count() + 2):
		if panel.get_selected_id() == chosen:
			found = true
			break
		panel.move_selection(1)
	if not found:
		_fail("could not select chosen recipe %s in picker" % chosen)
		return

	var result: Dictionary = panel.confirm_selection()
	if not bool(result.get("ok", false)):
		_fail("confirm failed: %s" % str(result.get("reason", "")))
		return
	if panel.is_open():
		_fail("panel should close after successful confirm")
		return
	if playable.crafting_state.get_active_recipe_id() != chosen:
		_fail("active recipe is %s, expected %s" % [playable.crafting_state.get_active_recipe_id(), chosen])
		return
	if chosen == first_ready:
		_fail("chosen_not_first invariant broken")
		return

	var produces: Dictionary = playable.crafting_state.get_produces(chosen)
	var craft_item: String = str(produces.get("item_id", ""))
	if craft_item.is_empty():
		_fail("chosen recipe produces nothing")
		return
	var before: int = inv.get_quantity(craft_item)
	playable.advance_crafting_for_validation(120.0)
	if playable.crafting_state.is_crafting():
		_fail("craft did not complete")
		return
	if inv.get_quantity(craft_item) <= before:
		_fail("output not deposited: %s" % craft_item)
		return

	# --- Field craft picker (KEY_C residual) ------------------------------------
	inv.add_item("synth_fiber", 12)
	inv.add_item("medical_gauze", 6)
	inv.add_item("scrap_metal", 12)
	inv.add_item("adhesive_paste", 6)
	inv.add_item("ceramic_plate", 4)
	inv.add_item("reactive_gel", 4)
	var field_entries: Array = playable.list_station_recipe_entries("field_crafting")
	var field_ready: Array = []
	for e in field_entries:
		if bool((e as Dictionary).get("craftable", false)):
			field_ready.append(str((e as Dictionary).get("recipe_id", "")))
	if field_ready.size() < 2:
		_fail("need >=2 ready field recipes, got %d" % field_ready.size())
		return
	var field_first: String = str(field_ready[0])
	var field_chosen: String = str(field_ready[1])
	if not playable.open_recipe_picker_for_validation("field_crafting"):
		_fail("field recipe picker did not open")
		return
	if panel.get_station_kind() != "field_crafting":
		_fail("picker not in field_crafting mode")
		return
	var field_found: bool = false
	for _j in range(panel.get_entry_count() + 2):
		if panel.get_selected_id() == field_chosen:
			field_found = true
			break
		panel.move_selection(1)
	if not field_found:
		_fail("could not select field recipe %s" % field_chosen)
		return
	var field_result: Dictionary = panel.confirm_selection()
	if not bool(field_result.get("ok", false)):
		_fail("field confirm failed: %s" % str(field_result.get("reason", "")))
		return
	var active_field: String = playable.field_crafting_state.get_active_recipe_id()
	if active_field != field_chosen:
		_fail("active field recipe is %s, expected %s" % [active_field, field_chosen])
		return
	if field_chosen == field_first:
		_fail("field chosen_not_first broken")
		return
	var fprod: Dictionary = playable.crafting_state.get_produces(field_chosen)
	var fitem: String = str(fprod.get("item_id", ""))
	var fbefore: int = inv.get_quantity(fitem)
	playable.advance_crafting_for_validation(120.0)
	if playable.field_crafting_state.is_crafting():
		_fail("field craft did not complete")
		return
	if inv.get_quantity(fitem) <= fbefore:
		_fail("field output not deposited: %s" % fitem)
		return

	finished = true
	print("MAIN PLAYABLE RECIPE PICKER PASS station=fabricator recipe=%s crafted=true chosen_not_first=true field=%s field_crafted=true" % [chosen, field_chosen])
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
