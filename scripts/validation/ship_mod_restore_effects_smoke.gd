extends SceneTree

## After run-snapshot restore, ship-mod re-applies linked sub restore + station tiers.
## Marker: SHIP MOD RESTORE EFFECTS PASS restore=true tier=true system=true

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
	playable.inventory_state.add_item("reactor_console", 1)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	if playable.inventory_state.get_quantity("wrench") <= 0:
		playable.inventory_state.add_item("wrench", 1)
	if not _free_first_profile_slot("wall_console_mount_v1"):
		_fail("no real console slot"); return
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if not panel.install_from_inventory(playable.component_catalog):
		_fail("install"); return
	if not _complete_active_work():
		_fail("install timed commit"); return
	var sum: Dictionary = playable.ship_modification_state.get_summary()
	if int(sum.get("installed", []).size() if sum.get("installed") is Array else 0) < 1:
		_fail("no installed in summary"); return
	# Damage linked sub, clear station tier, re-apply via restore path.
	var sub = playable.ship_systems_manager.systems["power"].get_subcomponent("power_distribution")
	sub.health = 0.1
	var st = playable.crafting_state.get_or_create_station("fabricator")
	st.tier = 0
	st.level = 0
	# Simulate load: apply_summary then reapply effects.
	playable.ship_modification_state.apply_summary(sum)
	if not playable._bind_ship_modification_panel_to_current_physical_slots(playable._inventory_qty_dict_for_work()):
		_fail("restore bind"); return
	playable._reapply_ship_mod_runtime_effects()
	if float(sub.health) < 0.54:
		_fail("system not restored got %s" % str(sub.health)); return
	var tier: int = int(st.effective_tier()) if st.has_method("effective_tier") else int(st.tier)
	if tier < 2:
		_fail("tier not restored got %d" % tier); return
	print("SHIP MOD RESTORE EFFECTS PASS restore=true tier=true system=true")
	quit(0)


func _free_first_profile_slot(profile_id: String) -> bool:
	var setup_returns: Dictionary = {}
	for slot_v in playable.ship_modification_state.get_physical_slots():
		if not (slot_v is Dictionary):
			continue
		var slot: Dictionary = slot_v as Dictionary
		if str(slot.get("component_slot_profile_id", "")) != profile_id:
			continue
		if not bool(slot.get("occupied", false)):
			return true
		return bool(playable.ship_modification_state.uninstall(str(slot.get("slot_id", "")), setup_returns).get("ok", false))
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


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	print("SHIP MOD RESTORE EFFECTS FAIL: %s" % msg)
	finished = true
	quit(1)
