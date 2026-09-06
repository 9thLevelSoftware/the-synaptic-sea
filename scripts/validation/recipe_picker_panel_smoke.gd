extends SceneTree

## REQ-CS-016 panel unit smoke against a stub coordinator. Proves open, rows,
## move_selection, blocked confirm stays open, ready confirm succeeds + closes.

const RecipePickerPanelScript := preload("res://scripts/ui/recipe_picker_panel.gd")

class StubCoordinator extends RefCounted:
	var last_begin_kind: String = ""
	var last_begin_id: String = ""
	var last_ship_id: String = ""
	var last_station_instance_id: String = ""
	var last_binding_generation: int = -1
	var last_cancel_job_id: String = ""
	var collected: int = 0
	var cancelled: int = 0
	var accepted_generation: int = 7
	var no_recipes: bool = false
	var cancel_policy: String = "refund"
	var force_fail: bool = false
	func list_station_recipe_entries(
			station_kind: String, ship_id: String = "", station_instance_id: String = "", binding_generation: int = -1) -> Array:
		last_ship_id = ship_id
		last_station_instance_id = station_instance_id
		last_binding_generation = binding_generation
		if no_recipes:
			return []
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
	func begin_craft_from_picker(
			station_kind: String, recipe_id: String, ship_id: String = "", station_instance_id: String = "", binding_generation: int = -1) -> Dictionary:
		last_begin_kind = station_kind
		last_begin_id = recipe_id
		last_ship_id = ship_id
		last_station_instance_id = station_instance_id
		last_binding_generation = binding_generation
		if force_fail:
			return {"ok": false, "reason": "forced", "recipe_id": recipe_id}
		return {"ok": true, "reason": "started", "recipe_id": recipe_id}
	func get_station_crafting_projection(
			station_kind: String, ship_id: String, station_instance_id: String, binding_generation: int) -> Dictionary:
		last_ship_id = ship_id
		last_station_instance_id = station_instance_id
		last_binding_generation = binding_generation
		if binding_generation != accepted_generation:
			return {"ok": false, "reason": "stale_binding"}
		return {
			"ok": true, "queue_depth": 1, "max_queue": 2, "powered": false, "pending_mass": 2.5,
			"power_paused": true, "pending_record_count": 1,
			"jobs": [{"job_id": "ship-a/fabricator-01/job-000001", "state": "crafting", "progress_ratio": 0.25, "cancel_policy": cancel_policy, "cancellable": true}],
		}
	func collect_station_pending_output(
			station_kind: String, ship_id: String, station_instance_id: String, binding_generation: int) -> Dictionary:
		last_ship_id = ship_id
		last_station_instance_id = station_instance_id
		last_binding_generation = binding_generation
		if binding_generation != accepted_generation:
			return {"ok": false, "reason": "stale_binding"}
		collected += 1
		return {"ok": true, "transferred": 1}
	func cancel_station_craft_from_picker(
			station_kind: String, ship_id: String, station_instance_id: String, job_id: String, binding_generation: int) -> Dictionary:
		last_ship_id = ship_id
		last_station_instance_id = station_instance_id
		last_binding_generation = binding_generation
		last_cancel_job_id = job_id
		if binding_generation != accepted_generation:
			return {"ok": false, "reason": "stale_binding"}
		cancelled += 1
		return {"ok": true, "result": "refunded"}

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

	# Physical picker calls carry the exact owner pair through listing, projection,
	# confirmation, explicit collection, and cancellation. Its live status text
	# exposes queue/power/pending state instead of leaving it in a hidden model.
	if not panel.open_for_station("fabricator", "ship-a", "fabricator-01", 7):
		_fail("owner picker did not open")
		return
	if panel.get_ship_id() != "ship-a" or panel.get_station_instance_id() != "fabricator-01" \
			or panel.get_binding_generation() != 7:
		_fail("owner context not retained")
		return
	var status_lines: PackedStringArray = panel.get_status_lines()
	var rendered: String = "\n".join(status_lines)
	if not rendered.contains("Owner: ship-a / fabricator-01") \
			or not rendered.contains("Queue: 1/2") \
			or not rendered.contains("crafting 25%") \
			or not rendered.contains("Paused: station power unavailable") \
			or not rendered.contains("Output waiting: collect from this station"):
		_fail("owner projection not rendered: %s" % rendered)
		return
	if not rendered.contains("(refund)"):
		_fail("refund cancellation policy not rendered")
		return
	# Selectable action rows must route exact collection/cancellation, never a
	# hidden helper or a defaulted first job.
	if panel.get_selected_id() != "collect_pending":
		_fail("collect action was not selected first")
		return
	var collected: Dictionary = panel.confirm_selection()
	if not bool(collected.get("ok", false)) or stub.collected != 1 \
			or stub.last_ship_id != "ship-a" or stub.last_station_instance_id != "fabricator-01" \
			or stub.last_binding_generation != 7:
		_fail("owner-scoped collection not routed")
		return
	panel.move_selection(1)
	if panel.get_selected_id() != "cancel:ship-a/fabricator-01/job-000001":
		_fail("exact cancellation action was not selectable")
		return
	var cancelled: Dictionary = panel.confirm_selection()
	if not bool(cancelled.get("ok", false)) \
			or stub.last_cancel_job_id != "ship-a/fabricator-01/job-000001" \
			or stub.cancelled != 1 or stub.last_binding_generation != 7:
		_fail("owner-scoped cancellation not routed")
		return
	# The same station ID under a new binding generation is stale: projection
	# fail-closes the panel before it can begin, collect, or cancel anything.
	stub.accepted_generation = 8
	var begin_before: String = stub.last_begin_id
	var collect_before: int = stub.collected
	var cancel_before: int = stub.cancelled
	if panel.open_for_station("fabricator", "ship-a", "fabricator-01", 7):
		_fail("stale generation reopened physical picker")
		return
	if panel.is_open() or stub.last_begin_id != begin_before \
			or stub.collected != collect_before or stub.cancelled != cancel_before:
		_fail("stale generation mutated station state")
		return
	stub.accepted_generation = 7
	if not panel.open_for_station("fabricator", "ship-a", "fabricator-01", 7):
		_fail("fresh generation did not reopen picker")
		return
	# Choose recipe beta after two action rows, then verify all owner arguments.
	for _i in range(panel.get_entry_count() + 3):
		if panel.get_selected_id() == "craft_beta":
			break
		panel.move_selection(1)
	var owner_result: Dictionary = panel.confirm_selection()
	if not bool(owner_result.get("ok", false)) or stub.last_begin_kind != "fabricator" \
			or stub.last_begin_id != "craft_beta" or stub.last_ship_id != "ship-a" \
			or stub.last_station_instance_id != "fabricator-01" or stub.last_binding_generation != 7:
		_fail("owner-scoped confirmation not routed")
		return

	# A physical action remains selectable when recipes are empty, and it keeps
	# the actual cancellation policy rather than promising a refund unconditionally.
	stub.no_recipes = true
	stub.cancel_policy = "forfeit"
	if not panel.open_for_station("fabricator", "ship-a", "fabricator-01", 7):
		_fail("no-recipe physical picker did not open")
		return
	if panel.get_entry_count() != 2 or not "\n".join(panel.get_row_texts()).contains("(forfeit)"):
		_fail("no-recipe physical action rows not rendered")
		return
	var no_recipe_collect: Dictionary = panel.confirm_selection()
	if not bool(no_recipe_collect.get("ok", false)) or stub.collected != 2:
		_fail("no-recipe pending action did not dispatch")
		return
	panel.close()

	# A partial owner pair cannot degrade into a portable/kind-only request and
	# must not emit a panel-close signal for a panel that never opened.
	var close_before_partial: int = closed_count[0]
	if panel.open_for_station("fabricator", "ship-a", "", 7):
		_fail("partial station owner opened picker")
		return
	if closed_count[0] != close_before_partial:
		_fail("partial owner emitted a false close")
		return

	print("RECIPE PICKER PANEL PASS rows=3 actions=true generation_fail_closed=true no_recipe_action=true projection=true collection=true cancellation=true")
	quit()
