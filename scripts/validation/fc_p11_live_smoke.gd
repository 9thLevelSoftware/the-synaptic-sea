extends SceneTree

## FC-13 live path: panel mutation, physical placement, marker, revisit and save agree.
## Marker: FC P11 LIVE PASS

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var playable
var frames: int = 0
var finished: bool = false


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if finished:
		return
	frames += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		if frames > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	finished = true
	_validate()


func _validate() -> void:
	if not playable.open_ship_modification_panel_for_validation():
		_fail("live physical slot bind denied")
		return
	var panel = playable.ship_modification_panel
	var state = playable.ship_modification_state
	var placement = playable.component_placement_state
	if playable.inventory_state.get_quantity("wrench") <= 0:
		playable.inventory_state.add_item("wrench", 1)
	var slots: Array = state.get_physical_slots()
	if slots.is_empty():
		_fail("no active-ship physical descriptors")
		return
	var installed_before: int = state.installed_count()
	var power_before: float = state.total_power_draw()
	playable.inventory_state.add_item("purified_water", 1)
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if panel.install_from_inventory(playable.component_catalog):
		_fail("panel accepted purified water")
		return
	if state.installed_count() != installed_before or absf(state.total_power_draw() - power_before) > 0.001 \
			or int(playable.inventory_state.get_quantity("purified_water")) != 1:
		_fail("water path mutated state or inventory")
		return

	var target_id: String = _select_first_occupied_profile(panel, state, "wall_utility_mount_v1")
	if target_id.is_empty():
		target_id = _select_first_occupied_profile(panel, state, "wall_console_mount_v1")
	if target_id.is_empty():
		_fail("no mounted physical wall slot selectable")
		return
	if not panel.uninstall_selected():
		_fail("panel physical uninstall")
		return
	if not placement.is_mounted(target_id):
		_fail("uninstall mutated placement before timed commit")
		return
	if not _complete_active_work():
		_fail("uninstall timed commit")
		return
	await process_frame
	if placement.is_mounted(target_id) or _has_marker(target_id):
		_fail("uninstall left placement or marker mounted")
		return

	var target_slot: Dictionary = placement.get_physical_slot(target_id)
	var profile_id: String = str(target_slot.get("component_slot_profile_id", ""))
	var install_component: String = "locker_wall" if profile_id == "wall_utility_mount_v1" else "reactor_console"
	var install_form: String = "wall_locker" if install_component == "locker_wall" else "reactor_console"
	_remove_catalogued_forms_from_live_inventory()
	playable.inventory_state.add_item(install_form, 1)
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if not panel.install_from_inventory(playable.component_catalog):
		_fail("catalog-driven live install: %s" % "\n".join(panel.get_status_lines()))
		return
	if placement.is_mounted(target_id):
		_fail("install mutated placement before timed commit")
		return
	if not _complete_active_work():
		_fail("install timed commit")
		return
	await process_frame
	var installed_entry: Dictionary = placement.get_entry(target_id)
	if not placement.is_mounted(target_id) or str(installed_entry.get("component_id", "")) != install_component:
		_fail("panel install did not update authoritative placement")
		return
	if not _has_marker(target_id) or int(playable.inventory_state.get_quantity(install_form)) != 0:
		_fail("panel install did not update marker/inventory")
		return
	if state.installed_count() != installed_before + 1:
		_fail("derived ship-mod view disagrees with placement")
		return

	playable.force_repair_all_for_validation()
	playable.board_piloted_ship_for_validation()
	playable.recompute_occupancy()
	var marker_ids: Array = playable.scannable_marker_ids_for_validation()
	if marker_ids.is_empty() or not bool(playable.travel_to_marker_id(str(marker_ids[0])).get("success", false)):
		_fail("leave ship for revisit")
		return
	if not playable.travel_home():
		_fail("return for revisit")
		return
	await process_frame
	placement = playable.component_placement_state
	if not placement.is_mounted(target_id) or str(placement.get_entry(target_id).get("component_id", "")) != install_component or not _has_marker(target_id):
		_fail("physical install did not survive leave/revisit")
		return
	if not playable.request_save() or not playable.request_load():
		_fail("save/load")
		return
	await process_frame
	placement = playable.component_placement_state
	if not placement.is_mounted(target_id) or str(placement.get_entry(target_id).get("component_id", "")) != install_component or not _has_marker(target_id):
		_fail("physical install did not survive save/load")
		return
	print("FC P11 LIVE PASS")
	quit(0)


func _select_first_occupied_profile(panel, state, profile_id: String) -> String:
	var slots: Array = state.get_physical_slots()
	for index in range(slots.size()):
		var slot: Dictionary = slots[index] as Dictionary
		if bool(slot.get("occupied", false)) and str(slot.get("component_slot_profile_id", "")) == profile_id:
			panel.move_selection(index - panel.get_selected_index())
			return str(slot.get("slot_id", ""))
	return ""


func _remove_catalogued_forms_from_live_inventory() -> void:
	for item_form in [
		"console_unit", "conduit_segment", "pump_assembly", "wall_locker",
		"machinery_block", "reactor_console", "air_recycler_unit", "nav_console",
		"thruster_control", "sensor_rack", "plating_plate",
	]:
		var quantity: int = int(playable.inventory_state.get_quantity(item_form))
		if quantity > 0:
			playable.inventory_state.remove_item(item_form, quantity)


func _has_marker(instance_id: String) -> bool:
	for marker in playable.get_component_markers_for_validation():
		if is_instance_valid(marker) and str(marker.get_meta("component_instance_id", "")) == instance_id:
			return true
	return false


func _complete_active_work() -> bool:
	if not playable.has_active_ship_work_for_validation():
		return false
	playable.vitals_state.stamina = playable.vitals_state.max_stamina
	if not playable.move_player_to_active_ship_work_target_for_validation():
		return false
	for _step in range(200):
		playable.advance_active_ship_work_for_validation(0.5)
		if not playable.has_active_ship_work_for_validation():
			return bool(playable.get_last_ship_work_result_for_validation().get("ok", false))
	return false


func _find_playable(node: Node):
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	push_error("FC P11 LIVE FAIL: %s" % message)
	finished = true
	quit(1)
