extends SceneTree

## REQ-CS-016 panel unit smoke against a stub coordinator. Proves open, rows,
## move_selection, blocked confirm stays open, ready confirm succeeds + closes.

const RecipePickerPanelScript := preload("res://scripts/ui/recipe_picker_panel.gd")

class StubCoordinator extends RefCounted:
	var last_begin_kind: String = ""
	var last_begin_id: String = ""
	var force_fail: bool = false
	func list_station_recipe_entries(station_kind: String) -> Array:
		return [
			{
				"recipe_id": "craft_alpha",
				"display_name": "Alpha",
				"category": "fabrication",
				"required_skill_level": 0,
				"ingredients": {"scrap_metal": 1},
				"produces": {"item_id": "plating", "quantity": 1},
				"craft_time_seconds": 5.0,
				"status": "ready",
				"craftable": true,
			},
			{
				"recipe_id": "craft_beta",
				"display_name": "Beta",
				"category": "fabrication",
				"required_skill_level": 0,
				"ingredients": {"scrap_metal": 1},
				"produces": {"item_id": "power_cell", "quantity": 1},
				"craft_time_seconds": 5.0,
				"status": "ready",
				"craftable": true,
			},
			{
				"recipe_id": "craft_gamma",
				"display_name": "Gamma",
				"category": "fabrication",
				"required_skill_level": 5,
				"ingredients": {"scrap_metal": 1},
				"produces": {"item_id": "sensor_module", "quantity": 1},
				"craft_time_seconds": 5.0,
				"status": "insufficient_skill",
				"craftable": false,
			},
		]
	func begin_craft_from_picker(station_kind: String, recipe_id: String) -> Dictionary:
		last_begin_kind = station_kind
		last_begin_id = recipe_id
		if force_fail:
			return {"ok": false, "reason": "forced", "recipe_id": recipe_id}
		return {"ok": true, "reason": "started", "recipe_id": recipe_id}

func _fail(msg: String) -> void:
	print("FAIL: %s" % msg)
	quit()

func _initialize() -> void:
	var stub := StubCoordinator.new()
	var panel = RecipePickerPanelScript.new()
	get_root().add_child(panel)
	panel.bind(stub)

	var closed_count: Array = [0]
	panel.panel_closed.connect(func() -> void: closed_count[0] += 1)

	if panel.is_open():
		_fail("panel should start closed")
		return
	panel.open_for_station("fabricator")
	if not panel.is_open():
		_fail("open_for_station did not open")
		return
	if panel.get_station_kind() != "fabricator":
		_fail("station kind not set")
		return
	var rows: Array = panel.get_row_texts()
	if rows.size() != 3:
		_fail("expected 3 rows, got %d" % rows.size())
		return
	# Default cursor is first ready (index 0).
	if panel.get_selected_index() != 0:
		_fail("initial selection should be first ready (0)")
		return
	if panel.get_selected_id() != "craft_alpha":
		_fail("initial id should be craft_alpha")
		return

	panel.move_selection(1)
	if panel.get_selected_index() != 1 or panel.get_selected_id() != "craft_beta":
		_fail("move_selection did not select craft_beta")
		return
	panel.move_selection(1)
	if panel.get_selected_id() != "craft_gamma":
		_fail("move did not reach craft_gamma")
		return

	# Blocked confirm stays open and does not call begin (craftable=false short-circuits).
	var blocked: Dictionary = panel.confirm_selection()
	if bool(blocked.get("ok", false)):
		_fail("blocked recipe should not confirm ok")
		return
	if not panel.is_open():
		_fail("panel should stay open after blocked confirm")
		return
	if stub.last_begin_id != "":
		_fail("begin should not be called for blocked recipe")
		return

	# Select second ready and confirm.
	panel.move_selection(-1)  # back to beta
	if panel.get_selected_id() != "craft_beta":
		_fail("expected craft_beta before successful confirm")
		return
	var ok_result: Dictionary = panel.confirm_selection()
	if not bool(ok_result.get("ok", false)):
		_fail("confirm should succeed for ready recipe")
		return
	if stub.last_begin_id != "craft_beta" or stub.last_begin_kind != "fabricator":
		_fail("begin invoked with wrong args: %s / %s" % [stub.last_begin_kind, stub.last_begin_id])
		return
	if panel.is_open():
		_fail("panel should close after successful confirm")
		return
	if closed_count[0] != 1:
		_fail("panel_closed not emitted, count=%d" % closed_count[0])
		return

	print("RECIPE PICKER PANEL PASS rows=3 move=true confirm=true closed=true")
	quit()
