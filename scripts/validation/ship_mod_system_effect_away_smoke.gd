extends SceneTree

## Ship-mod install restores linked hub sub; uninstall damages it; catalog power_draw bites.
## Marker: SHIP MOD SYSTEM EFFECT AWAY PASS restore=true power=true uninstall_damage=true

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
	var home_placement_before: Dictionary = home.get_live_component_placement().get_summary().duplicate(true)
	var home_draw_before: float = float(home.get_live_ship_modification().total_power_draw())
	if not _travel_to_owned_derelict():
		_fail("actual away owner travel"); return
	var target = playable.get_current_ship()
	var mgr = target.systems_manager
	if mgr == null:
		_fail("no systems manager"); return
	var sub = mgr.systems["life_support"].get_subcomponent("air_recycler")
	if sub == null:
		_fail("air_recycler missing"); return
	sub.health = 0.1
	if playable.inventory_state.get_quantity("wrench") <= 0:
		playable.inventory_state.add_item("wrench", 1)
	var modification = target.get_live_ship_modification()
	var placement = target.get_live_component_placement()
	var draw_before: float = float(modification.total_power_draw())
	playable.inventory_state.add_item("air_recycler_unit", 1)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	if not _prepare_first_profile_slot(panel, "deck_machinery_mount_v1", target):
		_fail("no real machinery slot"); return
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if not panel.install_from_inventory(playable.component_catalog):
		_fail("install status=%s" % "\n".join(panel.get_status_lines())); return
	if not _complete_active_work():
		_fail("install timed commit"); return
	if float(sub.health) < 0.54:
		_fail("expected restore floor got %s" % str(sub.health)); return
	if float(sub.health) > 0.56:
		_fail("should not full-heal got %s" % str(sub.health)); return
	var draw_after: float = float(modification.total_power_draw())
	if draw_after <= draw_before + 0.5:
		_fail("expected power_draw increase before=%s after=%s" % [str(draw_before), str(draw_after)]); return
	# Catalog-authored draw for air_recycler_unit is 10.0
	if absf(draw_after - draw_before - 10.0) > 0.01:
		_fail("expected +10 power_draw got delta=%s" % str(draw_after - draw_before)); return
	panel.refresh()
	if not panel.uninstall_selected():
		_fail("uninstall"); return
	if not _complete_active_work():
		_fail("uninstall timed commit"); return
	if float(sub.health) > 0.1:
		_fail("expected uninstall damage got %s" % str(sub.health)); return
	if placement == home.get_live_component_placement() \
			or home.get_live_component_placement().get_summary() != home_placement_before \
			or absf(float(home.get_live_ship_modification().total_power_draw()) - home_draw_before) > 0.0001:
		_fail("away system effect crossed into home component/power owner"); return
	if playable != null and (not bool(playable.away_from_start) or target == home):
		_fail("away cleared"); return
	print("SHIP MOD SYSTEM EFFECT AWAY PASS away=true restore=true power=true uninstall_damage=true")
	quit(0)


func _prepare_first_profile_slot(panel, profile_id: String, owner) -> bool:
	var modification = owner.get_live_ship_modification()
	var placement = owner.get_live_component_placement()
	var context = playable._ship_work_context_for(str(owner.ship_id))
	for slot_v in modification.get_physical_slots():
		if not (slot_v is Dictionary):
			continue
		var slot: Dictionary = slot_v as Dictionary
		if str(slot.get("component_slot_profile_id", "")) != profile_id:
			continue
		var slot_id: String = str(slot.get("slot_id", ""))
		if not panel.select_slot_id(slot_id):
			return false
		var position_v: Variant = playable._component_slot_world_position(slot_id, context)
		if not (position_v is Vector3):
			return false
		playable.player.global_position = position_v as Vector3
		playable.recompute_occupancy()
		if playable.get_current_occupancy_for_validation() != owner:
			return false
		if bool(slot.get("occupied", false)):
			if not panel.uninstall_selected() or not _complete_active_work():
				return false
			panel.refresh()
			if not panel.select_slot_id(slot_id):
				return false
		panel.set_inventory(playable._inventory_qty_dict_for_work())
		return not placement.is_mounted(slot_id)
	return false


func _travel_to_owned_derelict() -> bool:
	playable.force_repair_all_for_validation()
	playable.board_piloted_ship_for_validation()
	playable.recompute_occupancy()
	var markers: Array = playable.scannable_marker_ids_for_validation()
	if markers.is_empty() or not bool(playable.travel_to_marker_id(str(markers[0])).get("success", false)):
		return false
	var target = playable.get_current_ship()
	if target == null or not playable.open_active_dock_barrier_for_validation() \
			or not playable.board_host_for_validation():
		return false
	playable.recompute_occupancy()
	return playable.get_current_occupancy_for_validation() == target \
		and target.get_access().claim("player_local")


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
	print("SHIP MOD SYSTEM EFFECT AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
