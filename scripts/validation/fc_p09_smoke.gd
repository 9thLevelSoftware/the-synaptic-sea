extends SceneTree

## P09 scene proof: a cold run acquires its opening repair part from authored
## loot, then drives exact owner-scoped station jobs through the real picker
## input path on home and away ships. Queue, power pause, cancellation, pending
## collection, range, owner and binding-generation gates are all exercised.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 900

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var exercised: bool = false


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
	if playable == null or playable.loader == null \
			or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	if exercised:
		return
	exercised = true
	_validate(playable)


func _validate(playable) -> void:
	if not _validate_cold_opening(playable):
		return
	var home = playable.get_home_ship_for_validation()
	if home == null or str(home.ship_id).is_empty():
		_fail("home owner missing")
		return
	# The player boots aboard the docked ride. Cross the authored dock seam onto
	# the home host before using the host-owned physical station.
	if playable.get_current_occupancy_for_validation() != home:
		if playable.has_closed_dock_barrier_for_validation() \
				and not playable.open_active_dock_barrier_for_validation():
			_fail("home dock seam did not open")
			return
		if not playable.board_host_for_validation():
			_fail("could not occupy the home station owner")
			return
		playable.recompute_occupancy()
	if playable.get_current_occupancy_for_validation() != home:
		_fail("home station owner is not occupied")
		return
	var home_workbench = _station_for(playable, str(home.ship_id), "workbench")
	var home_fabricator = _station_for(playable, str(home.ship_id), "fabricator")
	if home_workbench == null or home_fabricator == null:
		_fail("home physical stations missing")
		return
	if home_workbench.get_parent() != home.scene_root \
			or home_fabricator.get_parent() != home.scene_root:
		_fail("home station parent is not its ship owner")
		return
	if home_workbench.crafting_state != playable.crafting_state:
		_fail("home station created a private crafting scheduler")
		return

	# Dismiss the headless boot menu, then interact with the exact node. This
	# proves that one interaction retains the physical owner instead of being
	# overwritten by the station's legacy kind-only signal.
	var menu = playable.get_menu_coordinator_for_validation()
	if menu != null:
		if menu.has_method("dismiss_boot_menu"):
			menu.dismiss_boot_menu()
		if menu.menu_state != null and menu.menu_state.has_method("close_all"):
			menu.menu_state.close_all()
	var legacy_requests: Array = []
	var context_requests: Array = []
	home_workbench.recipe_picker_requested.connect(
		func(kind: String) -> void: legacy_requests.append(kind))
	home_workbench.recipe_picker_context_requested.connect(
		func(kind: String, ship_id: String, station_id: String, generation: int) -> void:
			context_requests.append([kind, ship_id, station_id, generation]))
	if not _open_station(playable, home_workbench):
		var context = playable.call("_ship_work_context_for", str(home.ship_id))
		var detail: Dictionary = playable.call(
			"_physical_crafting_station_preflight", "workbench", str(home.ship_id),
			str(home_workbench.station_instance_id), int(home_workbench.binding_generation), false)
		_fail("home workbench picker did not open preflight=%s station_gen=%d owner_gen=%d context_match=%s selected=%s occupied=%s" % [
			str(detail.get("reason", "?")), int(home_workbench.binding_generation),
			int(home.get_live_binding_generation()),
			str(context != null and context.matches_binding(home)),
			str(playable.get_selected_ship_id_for_validation()),
			str(playable.get_current_occupancy_for_validation() == home)])
		return
	if legacy_requests.size() != 1 or context_requests.size() != 1:
		_fail("one station interaction did not emit one owner context")
		return
	if not _panel_matches(playable, home_workbench):
		_fail("home picker lost its exact owner or generation")
		return
	playable.dispatch_recipe_picker_input_for_validation("ui_cancel")

	var inventory = playable.inventory_state
	if inventory == null or playable.crafting_state == null:
		_fail("crafting authority missing")
		return
	if playable.player_progression != null:
		playable.player_progression.skills["fabrication"] = 6
	_ensure_quantity(inventory, "scrap_metal", 16)
	_ensure_quantity(inventory, "adhesive_paste", 8)
	_ensure_quantity(inventory, "sensor_array", 2)
	_ensure_quantity(inventory, "optical_lens", 2)
	_ensure_quantity(inventory, "circuit_board", 4)

	# Exact blockers are returned by the real owner-scoped listing. A book-gated
	# recipe stays unknown and a starter recipe above the base station tier stays
	# unavailable even when all materials and skill are present.
	if not _open_station(playable, home_fabricator):
		_fail("home fabricator exact interaction failed")
		return
	var fabricator_entries: Array = playable.list_station_recipe_entries(
		"fabricator", str(home_fabricator.ship_id),
		str(home_fabricator.station_instance_id), int(home_fabricator.binding_generation))
	if _entry_status(fabricator_entries, "craft_thruster_nozzle") != "missing_recipe_knowledge":
		_fail("knowledge blocker not exposed")
		return
	var station_tier: int = int(playable.get_station_crafting_projection(
		"fabricator", str(home_fabricator.ship_id),
		str(home_fabricator.station_instance_id), int(home_fabricator.binding_generation)
	).get("station_tier", -1))
	if station_tier == 0 \
			and _entry_status(fabricator_entries, "craft_sensor_module") != "insufficient_tier":
		_fail("tier blocker not exposed at the base station")
		return
	playable.dispatch_recipe_picker_input_for_validation("ui_cancel")
	if not _validate_home_queue_and_pending(playable, home_workbench):
		return
	if not _validate_crafted_tool_consumers(playable, home_workbench, home_fabricator):
		return
	if not _validate_away_owner_and_lifetime(playable, home_workbench):
		return

	finished = true
	print("FC P09 PASS")
	_teardown_and_quit(0)


func _validate_cold_opening(playable) -> bool:
	var manager = playable.get_ship_systems_manager()
	if manager == null or manager.is_operational("propulsion"):
		_fail("cold run did not start with propulsion blocked")
		return false
	# The opening contract intentionally leaves power/navigation repairs to the
	# objective loop; nav_linkage remains the single propulsion blocker proved here.
	for system_id in ["power", "navigation"]:
		var system = manager.get_system(system_id)
		if system == null:
			_fail("opening system missing: %s" % system_id)
			return false
		for subcomponent in system.subcomponents:
			manager.force_repair(system_id, subcomponent.subcomponent_id)
	if playable.loot_containers.is_empty():
		_fail("authored starter containers missing")
		return false
	for container in playable.loot_containers:
		playable.search_loot_container_for_validation(str(container.container_id))
	var before: int = playable.inventory_state.get_quantity("circuit_board")
	if before < 1:
		_fail("authored starter loot did not yield circuit_board")
		return false
	if not playable.repair_subcomponent_for_validation("propulsion", "nav_linkage"):
		_fail("timed opening repair did not start")
		return false
	playable.advance_repair_channels_for_validation(0.01)
	if manager.get_system("propulsion").get_subcomponent("nav_linkage").is_functional():
		_fail("opening repair completed instantly")
		return false
	playable.advance_repair_channels_for_validation(999.0)
	if not manager.is_operational("propulsion") \
			or playable.inventory_state.get_quantity("circuit_board") != before - 1:
		_fail("opening repair did not commit exactly one acquired circuit board")
		return false
	return true


func _validate_home_queue_and_pending(playable, station) -> bool:
	var inventory = playable.inventory_state
	var ship_id: String = str(station.ship_id)
	var station_id: String = str(station.station_instance_id)
	var generation: int = int(station.binding_generation)
	if not _open_station(playable, station) \
			or not _select_with_input(playable, "weld_plating"):
		_fail("could not select home recipe through UI input")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	if playable.recipe_picker_panel.is_open():
		_fail("first paid craft did not close the picker")
		return false
	var first: Dictionary = playable.get_station_crafting_projection(
		"workbench", ship_id, station_id, generation)
	if not bool(first.get("ok", false)) or int(first.get("queue_depth", 0)) != 1:
		_fail("first physical job missing from projection")
		return false
	playable.crafting_state.tick(1.0)
	var progressed: Dictionary = playable.get_station_crafting_projection(
		"workbench", ship_id, station_id, generation)
	var running_job: Dictionary = _first_job_in_state(progressed, "running")
	if running_job.is_empty() or float(running_job.get("progress_ratio", 0.0)) <= 0.0 \
			or float(running_job.get("progress_ratio", 0.0)) >= 1.0:
		_fail("physical progress was not normalized")
		return false
	station.set_powered(false)
	playable.crafting_state.tick(0.25)
	var paused: Dictionary = playable.get_station_crafting_projection(
		"workbench", ship_id, station_id, generation)
	if not bool(paused.get("power_paused", false)) \
			or _first_job_in_state(paused, "paused_power").is_empty():
		_fail("power pause not exposed for the exact job")
		return false
	station.set_powered(true)
	playable.crafting_state.tick(0.25)

	# A second confirm while the same exact station is busy enqueues a paid job.
	var scrap_before_queue: int = inventory.get_quantity("scrap_metal")
	var adhesive_before_queue: int = inventory.get_quantity("adhesive_paste")
	if not _open_station(playable, station) \
			or not _select_with_input(playable, "weld_plating"):
		_fail("could not select queued recipe through UI input")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	if not playable.recipe_picker_panel.is_open():
		_fail("queued craft did not retain queue UI")
		return false
	var queued_projection: Dictionary = playable.get_station_crafting_projection(
		"workbench", ship_id, station_id, generation)
	var queued_job: Dictionary = _first_job_in_state(queued_projection, "queued")
	if queued_job.is_empty() or int(queued_projection.get("queue_depth", 0)) != 2 \
			or int(queued_projection.get("max_queue", 0)) <= 1:
		_fail("queue depth/capacity projection is inaccurate")
		return false
	var queued_id: String = str(queued_job.get("job_id", ""))
	if not _select_with_input(playable, "cancel:%s" % queued_id):
		_fail("queued cancellation row was not input reachable")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	var cancelled: Dictionary = playable.crafting_state.get_craft_job_scheduler().get_job(queued_id)
	if str(cancelled.get("state", "")) != "cancelled" \
			or inventory.get_quantity("scrap_metal") != scrap_before_queue \
			or inventory.get_quantity("adhesive_paste") != adhesive_before_queue:
		_fail("queued UI cancellation did not refund exact inputs")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_cancel")

	# Fill the result stack while the paid job runs. Completion must remain as a
	# recoverable station-owned pending receipt rather than silently dropping it.
	_ensure_quantity(inventory, "plating", 10)
	playable.advance_crafting_for_validation(999.0)
	var pending: Dictionary = playable.get_station_crafting_projection(
		"workbench", ship_id, station_id, generation)
	if int(pending.get("pending_record_count", 0)) != 1:
		_fail("full destination did not retain one pending receipt")
		return false
	if not _open_station(playable, station) \
			or playable.recipe_picker_panel.get_selected_id() != "collect_pending":
		_fail("pending collection was not the selected physical action")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	if not playable.recipe_picker_panel.is_open() \
			or not playable.recipe_picker_panel.get_status().contains("destination_full") \
			or station.pending_output_store.list_records_for_station(station_id).size() != 1:
		_fail("blocked collection was not recoverable")
		return false
	playable.dispatch_recipe_picker_input_for_validation("toggle_inventory")
	if playable.recipe_picker_panel.is_open() or not playable.inventory_panel.is_open():
		_fail("inventory recovery action is not input reachable")
		return false
	playable.inventory_panel.close()
	if inventory.remove_item("plating", 1) != 1:
		_fail("could not make one output slot")
		return false
	if not _open_station(playable, station):
		_fail("could not reopen pending station")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	if station.pending_output_store.list_records_for_station(station_id).size() != 0 \
			or inventory.get_quantity("plating") != 10:
		_fail("pending UI collection was not exact-once")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_cancel")
	return true


func _validate_crafted_tool_consumers(playable, workbench, fabricator) -> bool:
	var inventory = playable.inventory_state
	_remove_all(inventory, "welder")
	_remove_all(inventory, "welding_lance")
	_remove_all(inventory, "plasma_cutter")
	_remove_all(inventory, "prybar")
	_remove_all(inventory, "tool_prybar")
	_ensure_quantity(inventory, "scrap_metal", 3)
	_ensure_quantity(inventory, "power_cell", 1)
	_ensure_quantity(inventory, "circuit_board", 1)
	workbench.set_powered(true)
	if not _open_station(playable, workbench) \
			or not _select_with_input(playable, "craft_welder"):
		_fail("crafted welder recipe was not input reachable")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	playable.advance_crafting_for_validation(999.0)
	var welder_lot: Dictionary = _single_lot_for_item(inventory, "welder")
	if inventory.get_quantity("welder") != 1 \
			or str(welder_lot.get("item_id", "")) != "welder" \
			or str(welder_lot.get("lot_id", "")).is_empty() \
			or not _has_craft_job_origin(welder_lot):
		_fail("crafted welder did not retain production-lot provenance")
		return false
	if not _validate_timed_tool_work(playable, "weld_patch", welder_lot, true):
		return false

	_ensure_quantity(inventory, "titanium_ingot", 2)
	_ensure_quantity(inventory, "fusion_igniter", 1)
	_ensure_quantity(inventory, "power_cell", 1)
	_ensure_quantity(inventory, "circuit_board", 2)
	fabricator.set_powered(true)
	if not _open_station(playable, fabricator) \
			or not _select_with_input(playable, "craft_plasma_cutter"):
		_fail("crafted cutter recipe was not input reachable")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	playable.advance_crafting_for_validation(999.0)
	var cutter_lot: Dictionary = _single_lot_for_item(inventory, "plasma_cutter")
	if inventory.get_quantity("plasma_cutter") != 1 \
			or str(cutter_lot.get("item_id", "")) != "plasma_cutter" \
			or str(cutter_lot.get("lot_id", "")).is_empty() \
			or not _has_craft_job_origin(cutter_lot):
		_fail("crafted cutter did not retain production-lot provenance")
		return false
	if not _validate_timed_tool_work(playable, "cut_wall", cutter_lot, false):
		return false
	return true


func _validate_timed_tool_work(playable, action_id: String, crafted_lot: Dictionary, needs_damage: bool) -> bool:
	var inventory = playable.inventory_state
	if needs_damage:
		# Keep the incompatible cut admission check free of any repair material;
		# otherwise the welder would correctly select weld_patch instead of reaching
		# the cut gate. The material fixture is restored only for the weld proof.
		_remove_all(inventory, "plating_plate")
		_remove_all(inventory, "hull_plate")
		_remove_all(inventory, "hull_plate_kit")
	var target: Dictionary = _prepare_live_work_target(playable, needs_damage)
	if target.is_empty():
		_fail("%s production target was unavailable" % action_id)
		return false
	if needs_damage:
		# Only the welder remains, so this is the live incompatible-tool denial for
		# the cut path. It must not reserve a target or mutate any inventory lot.
		var denied_target: Dictionary = _prepare_live_work_target(playable, false)
		if denied_target.is_empty():
			_fail("cut denial target was unavailable")
			return false
		var denied_module_id: String = str(denied_target.get("module_id", ""))
		var denied_before: Dictionary = _module_snapshot(playable, denied_module_id)
		var inventory_before: Dictionary = inventory.get_lot_summary().duplicate(true)
		if not playable.try_work_action_interact_for_validation() \
				or playable.has_active_ship_work_for_validation() \
				or _module_snapshot(playable, denied_module_id) != denied_before \
				or inventory.get_lot_summary() != inventory_before:
			_fail("incompatible crafted welder mutated the cut entrypoint")
			return false
		# Restore the actual weld target after the negative cut admission attempt.
		if not _move_player_to_work_target(playable, target):
			_fail("could not return to weld target")
			return false
		_ensure_quantity(inventory, "plating_plate", 1)
	if not playable.try_work_action_interact_for_validation() \
			or not playable.has_active_ship_work_for_validation() \
			or playable.work_action_driver == null or playable.work_action_driver.work == null:
		_fail("%s did not enter production timed work" % action_id)
		return false
	var active = playable.work_action_driver.work
	var work_id: String = str(playable.get_active_ship_work_record_for_validation().get("work_id", ""))
	if work_id.is_empty():
		_fail("%s started without a transaction work id" % action_id)
		return false
	var expected_multiplier: float = _quality_multiplier_for_lot(crafted_lot)
	var accepted_tool: Dictionary = playable.work_action_driver.get_active_selected_tool_projection()
	if str(active.get("action_id")) != action_id \
			or str(active.get("target_id")) != str(target.get("module_id", "")) \
			or str(accepted_tool.get("item_id", "")) != str(crafted_lot.get("item_id", "")) \
			or str(accepted_tool.get("lot_id", "")) != str(crafted_lot.get("lot_id", "")) \
			or not is_equal_approx(
				float(accepted_tool.get("quality_multiplier", 0.0)), expected_multiplier) \
			or not is_equal_approx(
				float(playable.work_action_driver.get_active_start_speed_multiplier()), expected_multiplier):
		_fail("%s did not retain its exact crafted-lot quality effect" % action_id)
		return false
	var duration: float = float(active.get("duration"))
	if duration <= 0.0 or expected_multiplier <= 0.0 \
			or is_equal_approx(expected_multiplier, 1.0):
		_fail("%s reported an invalid quality-derived duration" % action_id)
		return false
	# This is a quantitative live-driver assertion, rather than a receipt-only
	# check. _tick_work_action applies wound/stamina speed before forwarding it
	# to WorkActionDriver; the driver must multiply that real base by the frozen
	# crafted-lot quality multiplier. If `_active_start_speed_mult` is ignored,
	# the measured delta is smaller than this expected value even though the
	# selected-tool projection can still look correct.
	var first_tick_delta: float = 0.05
	var progress_before_tick: float = float(active.get("progress"))
	var live_base_speed: float = _live_work_base_speed(playable)
	var expected_progress_delta: float = first_tick_delta * live_base_speed * expected_multiplier
	playable.advance_active_ship_work_for_validation(first_tick_delta)
	var measured_progress_delta: float = float(active.get("progress")) - progress_before_tick
	if not playable.has_active_ship_work_for_validation() \
			or measured_progress_delta <= 0.0 \
			or float(active.get("progress")) >= duration \
			or absf(measured_progress_delta - expected_progress_delta) > 0.0001:
		_fail("%s first live tick ignored its quality multiplier measured=%f expected=%f base=%f quality=%f" % [
			action_id, measured_progress_delta, expected_progress_delta, live_base_speed, expected_multiplier])
		return false
	# The driver keeps the catalog duration and applies the tool multiplier to
	# elapsed work. This is the actual effective duration, not a private helper
	# calculation.
	var effective_duration: float = duration / expected_multiplier
	playable.advance_active_ship_work_for_validation(effective_duration + 1.0)
	# Live stamina can reduce the final tick below the catalog's nominal
	# quality-adjusted duration. Continue through the same production tick until
	# the transaction commits; a bounded loop detects a paused/stalled action.
	for _completion_tick in range(16):
		if not playable.has_active_ship_work_for_validation():
			break
		playable.advance_active_ship_work_for_validation(0.5)
	var after: Dictionary = _module_snapshot(playable, str(target.get("module_id", "")))
	var completion: Dictionary = playable.get_last_ship_work_result_for_validation()
	var transaction = playable.get_ship_work_transaction_for_validation()
	var record: Dictionary = transaction.get_record(work_id) if transaction != null else {}
	var receipt: Dictionary = record.get("receipt", {}) as Dictionary if record.get("receipt", {}) is Dictionary else {}
	if playable.has_active_ship_work_for_validation() \
			or not bool(completion.get("ok", false)) \
			or str(completion.get("work_id", "")) != work_id \
			or str(receipt.get("commit_receipt_id", "")) != "%s:commit" % work_id \
			or bool(receipt.get("already_committed", true)):
		_fail("%s did not commit through the production transaction result=%s record=%s" % [
			action_id, str(completion), str(record)])
		return false
	var before_v: Variant = target.get("before", {})
	var before: Dictionary = before_v as Dictionary if before_v is Dictionary else {}
	if needs_damage and float(after.get("integrity", 0.0)) <= float(before.get("integrity", 0.0)):
		_fail("weld_patch did not improve its terminal target")
		return false
	if not needs_damage and after == before:
		_fail("cut_wall did not change its terminal target")
		return false
	return true


func _prepare_live_work_target(playable, damaged: bool) -> Dictionary:
	var layout: Dictionary = playable.call("_active_layout_for_work")
	if layout.is_empty() or playable.module_integrity_map == null or playable.player == null:
		return {}
	var target: Dictionary = playable.call(
		"_nearest_workable_wall_module", layout,
		(playable.player as Node3D).global_position, 999.0,
		playable.module_integrity_map, playable.current_ship)
	var module_id: String = str(target.get("module_id", ""))
	if module_id.is_empty():
		return {}
	if not _move_player_to_work_target(playable, {"module_id": module_id}):
		return {}
	if damaged:
		var hit: Dictionary = playable.apply_threat_structure_damage_for_validation(module_id, 0.55)
		if not bool(hit.get("ok", false)):
			return {}
	return {"module_id": module_id, "before": _module_snapshot(playable, module_id)}


func _move_player_to_work_target(playable, target: Dictionary) -> bool:
	var module_id: String = str(target.get("module_id", ""))
	var position: Variant = playable.call(
		"_compiled_wrapper_world_position", module_id, playable.current_ship)
	if not (position is Vector3) or position == Vector3.INF:
		return false
	if playable.player.has_method("teleport_to"):
		playable.player.teleport_to(position as Vector3)
	else:
		(playable.player as Node3D).global_position = position as Vector3
	return true


func _module_snapshot(playable, module_id: String) -> Dictionary:
	if playable.module_integrity_map == null or module_id.is_empty():
		return {}
	var module = playable.module_integrity_map.get_module(module_id)
	if module == null:
		return {}
	return {
		"state": str(module.get("state")),
		"integrity": float(module.get("integrity")),
	}


func _single_lot_for_item(inventory, item_id: String) -> Dictionary:
	var matching: Array = []
	for lot_v in inventory.get_lot_summary().get("lots", []) as Array:
		if lot_v is Dictionary and str((lot_v as Dictionary).get("item_id", "")) == item_id:
			matching.append((lot_v as Dictionary).duplicate(true))
	return (matching[0] as Dictionary) if matching.size() == 1 else {}


func _has_craft_job_origin(lot: Dictionary) -> bool:
	var origin: Variant = lot.get("origin", {})
	return origin is Dictionary and not str((origin as Dictionary).get("job_id", "")).is_empty()


func _quality_multiplier_for_lot(lot: Dictionary) -> float:
	var tier: String = str(lot.get("quality_tier", "standard"))
	return {
		"poor": 0.7,
		"standard": 1.0,
		"good": 1.25,
		"excellent": 1.6,
		"masterwork": 2.0,
	}.get(tier, 1.0)


func _validate_away_owner_and_lifetime(playable, home_station) -> bool:
	playable.board_piloted_ship_for_validation()
	playable.recompute_occupancy()
	var world = playable.get_synaptic_sea_world()
	var markers: Array = world.markers_in_range(playable.scanner_state.range_radius) \
		if world != null else []
	if markers.is_empty():
		_fail("no reachable first-away marker")
		return false
	var marker_id: String = str(markers[0].marker_id)
	var traveled: Dictionary = playable.travel_to_marker_id(marker_id)
	if not bool(traveled.get("success", false)):
		_fail("first-away route failed: %s" % str(traveled.get("reason", "unknown")))
		return false
	if not playable.open_active_dock_barrier_for_validation() \
			or not playable.board_host_for_validation():
		_fail("could not occupy the attached away ship")
		return false
	playable.recompute_occupancy()
	var away = playable.get_current_host_for_validation()
	if away == null or away == playable.get_home_ship_for_validation() \
			or playable.get_current_occupancy_for_validation() != away \
			or playable.get_selected_ship_id_for_validation() != str(away.ship_id):
		_fail("away station owner was not selected and occupied")
		return false
	var away_station = _station_for(playable, str(away.ship_id), "workbench")
	if away_station == null or away_station.get_parent() != away.scene_root \
			or away_station.crafting_state != playable.crafting_state:
		_fail("away station is not attached to the shared owner scheduler")
		return false
	if not is_instance_valid(home_station) \
			or home_station.get_parent() != playable.get_home_ship_for_validation().scene_root:
		_fail("home station lifetime ended while away")
		return false
	var home_remote: Dictionary = playable.get_station_crafting_projection(
		"workbench", str(home_station.ship_id), str(home_station.station_instance_id),
		int(home_station.binding_generation))
	if bool(home_remote.get("ok", false)):
		_fail("remote home station became an away fallback")
		return false

	_ensure_quantity(playable.inventory_state, "scrap_metal", 12)
	_ensure_quantity(playable.inventory_state, "adhesive_paste", 6)
	if not _open_station(playable, away_station) or not _panel_matches(playable, away_station) \
			or not _select_with_input(playable, "weld_plating"):
		_fail("actual away station picker was not usable")
		return false
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	var away_projection: Dictionary = playable.get_station_crafting_projection(
		"workbench", str(away.ship_id), str(away_station.station_instance_id),
		int(away_station.binding_generation))
	var away_job: Dictionary = _first_job_in_state(away_projection, "running")
	if away_job.is_empty():
		_fail("away paid job did not start")
		return false
	var away_job_id: String = str(away_job.get("job_id", ""))
	var stable_station_id: String = str(away_station.station_instance_id)
	if not _open_station(playable, away_station):
		_fail("away job picker did not reopen")
		return false
	var stale_generation: int = int(away_station.binding_generation)
	var before_stale: Dictionary = playable.crafting_state.get_craft_job_scheduler().get_job(
		away_job_id).duplicate(true)
	if not playable.call("_bind_current_ship_restoration_owners") \
			or int(away.get_live_binding_generation()) <= stale_generation:
		_fail("away binding generation did not advance")
		return false
	playable.call("_ensure_crafting_stations_for_owner", away)
	# The retained panel still holds the same ship/station IDs and old generation.
	# Its actual accept input must fail closed without cancelling the real job.
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	if playable.recipe_picker_panel.is_open() \
			or playable.crafting_state.get_craft_job_scheduler().get_job(away_job_id) != before_stale:
		_fail("same-ID stale picker mutated the rebound owner")
		return false
	var rebound_station = _station_for(playable, str(away.ship_id), "workbench")
	if rebound_station == null or str(rebound_station.station_instance_id) != stable_station_id \
			or int(rebound_station.binding_generation) <= stale_generation:
		_fail("away station did not retain stable ID across a fresh binding")
		return false

	# Revalidate range after open. Moving away invalidates the next request and
	# closes the retained panel without touching the owner-keyed scheduler.
	if not _open_station(playable, rebound_station):
		_fail("rebound away station did not reopen")
		return false
	# Step beyond the 1.8u station radius while remaining inside the same room,
	# so this proves the range gate without accidentally leaving ship occupancy.
	(playable.player as Node3D).global_position = \
		rebound_station.global_position + Vector3(2.25, 0.0, 0.0)
	var before_range: Dictionary = playable.crafting_state.get_craft_job_scheduler().get_job(
		away_job_id).duplicate(true)
	playable.dispatch_recipe_picker_input_for_validation("ui_accept")
	if playable.recipe_picker_panel.is_open() \
			or playable.crafting_state.get_craft_job_scheduler().get_job(away_job_id) != before_range:
		_fail("out-of-range picker mutation did not fail closed")
		return false

	# Leaving frees only the away scene node. The exact job remains in the one
	# shared scheduler and the station is recreated with the same stable ID.
	if not playable.travel_home():
		_fail("travel_home failed with an unattended away job")
		return false
	if playable.crafting_state.get_craft_job_scheduler().get_job(away_job_id).is_empty():
		_fail("unattended away job was discarded on leave")
		return false
	playable.board_piloted_ship_for_validation()
	playable.recompute_occupancy()
	var revisit: Dictionary = playable.travel_to_marker_id(marker_id)
	if not bool(revisit.get("success", false)) \
			or not playable.open_active_dock_barrier_for_validation() \
			or not playable.board_host_for_validation():
		_fail("away owner could not be revisited")
		return false
	playable.recompute_occupancy()
	var revisited_owner = playable.get_current_host_for_validation()
	var revisited_station = _station_for(playable, str(revisited_owner.ship_id), "workbench")
	if revisited_station == null or str(revisited_station.station_instance_id) != stable_station_id \
			or playable.crafting_state.get_craft_job_scheduler().get_job(away_job_id).is_empty():
		_fail("away station/job identity did not survive leave and revisit")
		return false
	return true


func _open_station(playable, station) -> bool:
	if station == null or not is_instance_valid(station) or not station.is_inside_tree():
		return false
	if playable.recipe_picker_panel.is_open():
		playable.recipe_picker_panel.close()
	if playable.inventory_panel.is_open():
		playable.inventory_panel.close()
	if playable.player.has_method("teleport_to"):
		playable.player.teleport_to(station.global_position)
	playable.recompute_occupancy()
	station.try_interact(playable.player)
	return playable.recipe_picker_panel.is_open()


func _select_with_input(playable, expected_id: String) -> bool:
	var panel = playable.recipe_picker_panel
	for _i in range(panel.get_entry_count() + 1):
		if panel.get_selected_id() == expected_id:
			return true
		playable.dispatch_recipe_picker_input_for_validation("ui_down")
	return false


func _panel_matches(playable, station) -> bool:
	var panel = playable.recipe_picker_panel
	return panel.is_open() \
		and panel.get_station_kind() == str(station.station_kind) \
		and panel.get_ship_id() == str(station.ship_id) \
		and panel.get_station_instance_id() == str(station.station_instance_id) \
		and panel.get_binding_generation() == int(station.binding_generation)


func _station_for(playable, ship_id: String, station_kind: String):
	for station in playable.crafting_stations:
		if is_instance_valid(station) and station.is_inside_tree() \
				and str(station.ship_id) == ship_id \
				and str(station.station_kind) == station_kind:
			return station
	return null


func _entry_status(entries: Array, recipe_id: String) -> String:
	for entry_variant in entries:
		if entry_variant is Dictionary \
				and str((entry_variant as Dictionary).get("recipe_id", "")) == recipe_id:
			return str((entry_variant as Dictionary).get("status", ""))
	return "missing_entry"


func _first_job_in_state(projection: Dictionary, state: String) -> Dictionary:
	for job_variant in projection.get("jobs", []) as Array:
		if job_variant is Dictionary \
				and str((job_variant as Dictionary).get("state", "")) == state:
			return (job_variant as Dictionary).duplicate(true)
	return {}


func _live_work_base_speed(playable) -> float:
	# Mirror PlayableGeneratedShip._tick_work_action's pre-driver speed exactly.
	# This intentionally excludes tool quality: WorkActionDriver owns its frozen
	# application, which is what the paired measured/expected tick asserts.
	var speed: float = 1.0
	if playable.wound_state != null and playable.wound_state.has_method("work_speed_multiplier"):
		speed = float(playable.wound_state.call("work_speed_multiplier"))
	if playable.vitals_state != null:
		var stamina: float = float(playable.vitals_state.stamina)
		if stamina <= 0.001:
			return 0.0
		var max_stamina: float = maxf(1.0, float(playable.vitals_state.max_stamina))
		var stamina_ratio: float = clampf(stamina / max_stamina, 0.0, 1.0)
		speed *= clampf(0.35 + stamina_ratio * 0.65, 0.35, 1.0)
	return speed


func _ensure_quantity(inventory, item_id: String, minimum: int) -> void:
	var missing: int = maxi(0, minimum - int(inventory.get_quantity(item_id)))
	if missing > 0:
		inventory.add_item(item_id, missing)


func _remove_all(inventory, item_id: String) -> void:
	var quantity: int = int(inventory.get_quantity(item_id))
	if quantity > 0:
		inventory.remove_item(item_id, quantity)


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


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("FC P09 FAIL reason=%s" % reason)
	_teardown_and_quit(1)


func _teardown_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	call_deferred("_do_quit", code)


func _do_quit(code: int) -> void:
	quit(code)
