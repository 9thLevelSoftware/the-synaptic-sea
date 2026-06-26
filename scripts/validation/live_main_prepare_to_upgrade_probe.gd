extends SceneTree

## Future live main-scene/controller-path probe for the player-facing
## prepare -> derelict -> survive -> loot -> craft -> return -> upgrade loop.
##
## This intentionally runs inside `scenes/main.tscn` so it exercises the
## shipped bootstrap, HUD, controller/menu surfaces, world travel, docked
## derelict runtime, loot interaction, and save/load path. The final upgrade
## stage uses the current in-memory meta/hub seam (not source-map currency)
## because Task 15 owns the live currency loop.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 420
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const HubUpgradePanelScript := preload("res://scripts/ui/hub_upgrade_panel.gd")

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var stage_lines: PackedStringArray = PackedStringArray()
var _exit_code: int = 0

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
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_run_probe(playable)

func _run_probe(ship: PlayableGeneratedShip) -> void:
	if finished:
		return
	var save_service = ship.get_save_load_service()
	if save_service != null:
		save_service.delete_current_run()
	var meta = ship.get_meta_progression_state()
	if meta != null:
		meta.reset_all()

	_prepare_stage(ship)
	if finished:
		return
	var marker_id: String = _derelict_stage(ship)
	if finished:
		return
	_survive_stage(ship)
	if finished:
		return
	_loot_stage(ship)
	if finished:
		return
	_craft_stage(ship)
	if finished:
		return
	_return_stage(ship, marker_id)
	if finished:
		return
	_upgrade_stage(ship)
	if finished:
		return

	finished = true
	print("LIVE MAIN PREPARE UPGRADE PROBE PASS stages=7 marker=%s upgrade=hub_storage_basic" % marker_id)
	for line in stage_lines:
		print(line)
	_cleanup_and_quit(0)

func _prepare_stage(ship: PlayableGeneratedShip) -> void:
	if ship.tracker == null or not ship.tracker.has_method("get_hud_text"):
		_fail("prepare stage missing objective tracker")
		return
	ship.inventory_state.add_item("ration_pack", 2)
	ship.inventory_state.add_item("purified_water", 2)
	ship.inventory_state.add_item("bandage_kit", 1)
	ship.inventory_state.add_item("focus_ampoule", 1)
	ship.inventory_state.add_item("scrap_metal", 10)
	ship.inventory_state.add_item("wiring_bundle", 10)
	ship.inventory_state.add_item("reactive_gel", 5)
	ship.inventory_state.add_item("circuit_board", 5)
	ship.inventory_state.add_item("power_cell", 2)
	ship._refresh_inventory_hud()
	if not ship.complete_objective_sequence_for_validation(1):
		_fail("prepare stage could not complete home objective sequence 1")
		return
	if not ship.complete_objective_sequence_for_validation(2):
		_fail("prepare stage could not complete home objective sequence 2")
		return
	ship.force_repair_all_for_validation()
	ship.board_piloted_ship_for_validation()
	ship.recompute_occupancy()
	if not ship.inventory_open_self_for_validation():
		_fail("prepare stage could not open inventory")
		return
	var rows: Array = ship.inventory_panel._rows.get("self", [])
	var tracker_text: String = ship.tracker.get_hud_text()
	if not tracker_text.contains("Progress: 2/"):
		_fail("prepare tracker did not advance after objective interactions")
		return
	_record_stage("prepare", "tracker=%s inventory_rows=%d occupancy=%s" % [
		_tracker_summary(tracker_text),
		rows.size(),
		_ship_label(ship.get_current_occupancy_for_validation()),
	])
	ship.inventory_close_for_validation()

func _derelict_stage(ship: PlayableGeneratedShip) -> String:
	var ids: Array = ship.claimable_marker_ids_for_validation()
	if ids.is_empty():
		_fail("derelict stage found no claimable markers in range")
		return ""
	var marker_id: String = String(ids[0])
	ship.board_piloted_ship_for_validation()
	ship.recompute_occupancy()
	var result: Dictionary = ship.travel_to_marker_id(marker_id)
	if not bool(result.get("success", false)):
		_fail("derelict travel failed reason=%s" % str(result.get("reason", "unknown")))
		return ""
	if not ship.away_from_start:
		_fail("derelict stage did not leave home complex")
		return ""
	if not ship.has_closed_dock_barrier_for_validation():
		_fail("derelict stage missing closed dock barrier")
		return ""
	_record_stage("derelict", "marker=%s host=%s roots=%d dock_barrier=closed" % [
		marker_id,
		_ship_label(ship.get_current_host_for_validation()),
		ship.active_ship_root_count_for_validation(),
	])
	return marker_id

func _survive_stage(ship: PlayableGeneratedShip) -> void:
	ship.vitals_state.hunger = 5.0
	ship.vitals_state.thirst = 5.0
	ship.sanity_state.sanity = 35.0
	ship.radiation_state.radiation = 55.0
	ship.body_temperature_state.temperature = 35.0
	ship.status_effects_state.add_effect("radiation_sickness", 8.0, 1)
	ship._refresh_player_vitals(0.1)
	var before_text: String = "\n".join(ship.get_player_vitals_lines())
	for token in ["HUNGER LOW", "THIRST LOW", "RADIATION SICKNESS"]:
		if not before_text.contains(token):
			_fail("survive stage missing pre-use vitals token %s" % token)
			return
	var stim := ship.use_inventory_item_for_validation("focus_ampoule")
	if not bool(stim.get("ok", false)):
		_fail("survive stage focus_ampoule use failed")
		return
	ship._refresh_player_vitals(0.1)
	var after_text: String = "\n".join(ship.get_player_vitals_lines())
	if before_text == after_text:
		_fail("survive stage vitals HUD did not change after stimulant use")
		return
	if not ship.status_effects_state.has_effect("stim_focus"):
		_fail("survive stage missing stim_focus status effect")
		return
	_record_stage("survive", "before=%s after=%s" % [_vitals_summary(before_text), _vitals_summary(after_text)])

func _loot_stage(ship: PlayableGeneratedShip) -> void:
	if ship.loot_containers.is_empty():
		_fail("loot stage found no derelict loot containers")
		return
	var chosen = null
	for container in ship.loot_containers:
		if is_instance_valid(container) and not container.searched:
			chosen = container
			break
	if chosen == null:
		_fail("loot stage found no unsearched container")
		return
	var container_id: String = String(chosen.container_id)
	if not ship.search_loot_container_for_validation(container_id):
		_fail("loot stage search interaction failed")
		return
	if not chosen.searched:
		_fail("loot stage container did not mark searched")
		return
	var loot_line: String = String(ship._last_loot_feedback_line)
	if not loot_line.begins_with("Loot:"):
		_fail("loot stage missing loot feedback line")
		return
	var captions: Array = []
	if ship.audio_manager != null and ship.audio_manager.has_method("drain_captions"):
		captions = ship.audio_manager.drain_captions()
	if not ship.inventory_open_self_for_validation():
		_fail("loot stage could not open inventory after search")
		return
	var rows: Array = ship.inventory_panel._rows.get("self", [])
	ship.inventory_close_for_validation()
	_record_stage("loot", "container=%s feedback=%s captions=%d rows=%d" % [container_id, loot_line, captions.size(), rows.size()])

func _craft_stage(ship: PlayableGeneratedShip) -> void:
	var crafting = CraftingStateScript.new()
	var materials = MaterialStateScript.new()
	materials.set_quality("scrap_metal", 0.8)
	materials.set_quality("wiring_bundle", 0.75)
	materials.set_quality("reactive_gel", 0.9)
	if not crafting.begin_craft("craft_power_cell", ship.inventory_state, materials, 2):
		_fail("craft stage begin_craft failed")
		return
	if not crafting.tick(30.0):
		_fail("craft stage tick did not complete recipe")
		return
	var result: Dictionary = crafting.finish_craft()
	if str(result.get("item_id", "")) != "power_cell" or int(result.get("quantity", 0)) != 1:
		_fail("craft stage unexpected output %s" % JSON.stringify(result))
		return
	ship.inventory_state.add_item("power_cell", 1)
	ship._refresh_inventory_hud()
	if not ship.inventory_open_self_for_validation():
		_fail("craft stage could not open inventory")
		return
	var power_found: bool = false
	var rows: Array = ship.inventory_panel._rows.get("self", [])
	for row in rows:
		if row != null and is_instance_valid(row) and String(row.item_id) == "power_cell":
			power_found = true
			break
	ship.inventory_close_for_validation()
	if not power_found:
		_fail("craft stage inventory UI missing crafted power_cell")
		return
	_record_stage("craft", "crafted=power_cell qty=%d inventory_power_cells=%d" % [
		int(result.get("quantity", 0)),
		ship.inventory_state.get_quantity("power_cell"),
	])

func _return_stage(ship: PlayableGeneratedShip, marker_id: String) -> void:
	if not ship.travel_home():
		_fail("return stage travel_home failed from marker %s" % marker_id)
		return
	ship.recompute_occupancy()
	if ship.away_from_start:
		_fail("return stage left away_from_start true")
		return
	var power_cells_before: int = ship.inventory_state.get_quantity("power_cell")
	if not ship.request_save():
		_fail("return stage request_save failed")
		return
	ship.inventory_state.remove_item("power_cell", 1)
	if not ship.request_load():
		_fail("return stage request_load failed")
		return
	if ship.inventory_state.get_quantity("power_cell") != power_cells_before:
		_fail("return stage load did not restore crafted power cell")
		return
	var tracker_text: String = ship.tracker.get_hud_text() if ship.tracker != null and ship.tracker.has_method("get_hud_text") else ""
	_record_stage("return", "home=%s occupancy=%s tracker=%s power_cells=%d" % [
		str(String(ship.get_current_ship().marker_id).is_empty()).to_lower(),
		_ship_label(ship.get_current_occupancy_for_validation()),
		_tracker_summary(tracker_text),
		ship.inventory_state.get_quantity("power_cell"),
	])

func _upgrade_stage(ship: PlayableGeneratedShip) -> void:
	var meta = ship.get_meta_progression_state()
	var hub = ship.get_hub_upgrade_state()
	if meta == null or hub == null:
		_fail("upgrade stage missing meta or hub state")
		return
	meta.reset_all()
	var payout: int = meta.apply_meta_payout({
		"completed_objectives": 5,
		"skill_levels": {"repair": 5},
		"discoveries": 1,
		"reason": "extraction",
	})
	if payout < 50:
		_fail("upgrade stage payout too low: %d" % payout)
		return
	if not hub.purchase("hub_storage_basic", meta):
		_fail("upgrade stage hub_storage_basic purchase failed")
		return
	if not meta.is_hub_upgrade_unlocked("hub_storage_basic"):
		_fail("upgrade stage hub_storage_basic did not unlock")
		return
	var panel = HubUpgradePanelScript.build_default(meta)
	var lines: PackedStringArray = panel.get_status_lines()
	if lines.is_empty() or not String(lines[0]).contains("Hub Upgrades:"):
		_fail("upgrade stage missing hub panel status lines")
		return
	_record_stage("upgrade", "payout=%d currency=%d panel=%s" % [
		payout,
		meta.get_meta_currency(),
		String(lines[0]),
	])
	if panel is Node:
		(panel as Node).free()

func _tracker_summary(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	for line in lines:
		var line_text: String = String(line)
		if line_text.begins_with("Progress:") or line_text.begins_with("Current:"):
			return line_text
	return String(lines[0]) if not lines.is_empty() else ""

func _vitals_summary(text: String) -> String:
	var out: Array[String] = []
	for line_variant in text.split("\n"):
		var line_text: String = String(line_variant)
		if line_text.begins_with("Hunger:") or line_text.begins_with("Thirst:") or line_text.begins_with("Status:"):
			out.append(line_text)
	return " | ".join(out)

func _ship_label(inst) -> String:
	if inst == null:
		return "<null>"
	if String(inst.marker_id).is_empty():
		return String(inst.ship_id)
	return "%s@%s" % [String(inst.ship_id), String(inst.marker_id)]

func _record_stage(stage: String, feedback: String) -> void:
	stage_lines.append("LIVE MAIN PROBE STAGE %s %s" % [stage.to_upper(), feedback])

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
	push_error("LIVE MAIN PREPARE UPGRADE PROBE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	_exit_code = code
	if playable != null:
		var save_service = playable.get_save_load_service()
		if save_service != null:
			save_service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
