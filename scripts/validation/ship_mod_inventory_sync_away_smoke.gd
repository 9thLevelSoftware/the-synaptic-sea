extends SceneTree

## Ship-mod panel install/uninstall mirrors InventoryState.
## Marker: SHIP MOD INVENTORY SYNC AWAY PASS install=true uninstall=true inv=true

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
	var home = playable.get_home_ship_for_validation()
	if home == null or home.get_live_component_placement() == null:
		_fail("home component owner"); return
	var home_before: Dictionary = home.get_live_component_placement().get_summary().duplicate(true)
	if not _travel_to_owned_derelict():
		_fail("actual away owner travel"); return
	var target = playable.get_current_ship()
	var context = playable._ship_work_context_for(str(target.ship_id))
	if context == null or context.ship != target or context.component_placement == null \
			or context.ship_modification == null:
		_fail("away context owners"); return
	if playable.inventory_state.get_quantity("wrench") <= 0:
		playable.inventory_state.add_item("wrench", 1)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	var placement = context.component_placement
	var modification = context.ship_modification
	var mounted_fixture: Dictionary = _select_mounted_component(
		panel, placement, context, target)
	var target_slot: String = str(mounted_fixture.get("slot_id", ""))
	var component_id: String = str(mounted_fixture.get("component_id", ""))
	var item_form: String = str(mounted_fixture.get("item_form", ""))
	if target_slot.is_empty() or component_id.is_empty() or item_form.is_empty():
		_fail("no occupied compatible physical slot"); return
	var existing_items: int = playable.inventory_state.get_quantity(item_form)
	if existing_items > 0:
		playable.inventory_state.remove_item(item_form, existing_items)
	# Establish a legitimate empty slot by completing the same timed uninstall
	# path a player uses. Its exact returned lot becomes part of `before`.
	if not panel.uninstall_selected() or not _complete_active_work():
		_fail("fixture timed dismount"); return
	if placement.is_mounted(target_slot):
		_fail("fixture slot remained mounted"); return
	panel.select_slot_id(target_slot)
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	var before: int = int(playable.inventory_state.get_quantity(item_form))
	if not panel.install_into_selected(component_id, item_form, 5.0, 12.0, false):
		_fail("install"); return
	# The request reserves one exact lot immediately, but physical placement waits
	# for the legitimate timed completion.
	var mid: int = int(playable.inventory_state.get_quantity(item_form))
	if mid != before - 1:
		_fail("install inv %d -> %d" % [before, mid]); return
	if placement.is_mounted(target_slot) or not _complete_active_work():
		_fail("install timed commit"); return
	if modification.installed_count() < 1:
		_fail("mod state empty"); return
	panel.refresh()
	if not panel.uninstall_selected():
		_fail("uninstall"); return
	if not _complete_active_work():
		_fail("uninstall timed commit"); return
	var after: int = int(playable.inventory_state.get_quantity(item_form))
	if after != before:
		_fail("uninstall inv %d want %d" % [after, before]); return
	if home.get_live_component_placement() == placement \
			or home.get_live_component_placement().get_summary() != home_before:
		_fail("away inventory work crossed into home owner"); return
	if playable != null and (not bool(playable.away_from_start) \
			or playable.get_current_occupancy_for_validation() != target):
		_fail("away cleared"); return
	print("SHIP MOD INVENTORY SYNC AWAY PASS away=true install=true uninstall=true inv=true")
	quit(0)


func _select_mounted_component(
		panel, placement, context, owner) -> Dictionary:
	for entry_v in placement.placed:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v as Dictionary
		if bool(entry.get("mounted", false)):
			var slot_id: String = str(entry.get("component_instance_id", ""))
			if panel.select_slot_id(slot_id):
				var position_v: Variant = playable._component_slot_world_position(slot_id, context)
				if position_v is Vector3:
					playable.player.global_position = position_v as Vector3
					playable.recompute_occupancy()
					if playable.get_current_occupancy_for_validation() == owner:
						return {
							"slot_id": slot_id,
							"component_id": str(entry.get("component_id", "")),
							"item_form": str(entry.get("item_form", "")),
						}
	return {}


func _travel_to_owned_derelict() -> bool:
	playable.force_repair_all_for_validation()
	playable.board_piloted_ship_for_validation()
	playable.recompute_occupancy()
	var markers: Array = playable.scannable_marker_ids_for_validation()
	if markers.is_empty() \
			or not bool(playable.travel_to_marker_id(str(markers[0])).get("success", false)):
		return false
	var target = playable.get_current_ship()
	if target == null or not playable.open_active_dock_barrier_for_validation() \
			or not playable.board_host_for_validation():
		return false
	playable.recompute_occupancy()
	return playable.get_current_occupancy_for_validation() == target \
		and target.get_access().claim("player_local") \
		and bool(playable.select_ship_for_modification_for_validation(
			str(target.ship_id)).get("ok", false))


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


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	print("SHIP MOD INVENTORY SYNC AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
