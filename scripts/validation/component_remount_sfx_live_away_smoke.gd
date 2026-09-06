extends SceneTree

## Live timed remount commit stamps mount SFX and routes it through audio_manager.
## Marker: COMPONENT REMOUNT SFX LIVE AWAY PASS away=true remount=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false
var phase: String = "wait"
var tick_accum: float = 0.0
var instance_id: String = ""
var item_form: String = ""
var sfx_before: int = 0
var target_ship
var target_placement
var home_placement_before: Dictionary = {}


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if frame_count > TIMEOUT_FRAMES:
		_fail("whole-smoke timeout phase=%s" % phase)
		return
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		return
	match phase:
		"wait": _setup()
		"dismount_tick": _tick_until("after_dismount")
		"after_dismount": _start_remount()
		"remount_tick": _tick_until("done")
		"done": _finish()


func _setup() -> void:
	var home = playable.get_home_ship_for_validation()
	if home == null or home.get_live_component_placement() == null:
		_fail("home component owner")
		return
	home_placement_before = home.get_live_component_placement().get_summary().duplicate(true)
	playable.force_repair_all_for_validation()
	playable.board_piloted_ship_for_validation()
	playable.recompute_occupancy()
	var markers: Array = playable.scannable_marker_ids_for_validation()
	if markers.is_empty() \
			or not bool(playable.travel_to_marker_id(str(markers[0])).get("success", false)):
		_fail("actual away travel")
		return
	target_ship = playable.get_current_ship()
	if target_ship == null or not playable.open_active_dock_barrier_for_validation() \
			or not playable.board_host_for_validation():
		_fail("board away owner")
		return
	playable.recompute_occupancy()
	if playable.get_current_occupancy_for_validation() != target_ship \
			or not target_ship.get_access().claim("player_local") \
			or not bool(playable.select_ship_for_modification_for_validation(
				str(target_ship.ship_id)).get("ok", false)):
		_fail("select claimed away owner")
		return
	var context = playable._ship_work_context_for(str(target_ship.ship_id))
	if context == null or context.ship != target_ship \
			or context.component_placement == null \
			or context.ship_modification == null \
			or not bool(context.preflight_physical_mutation(
				str(target_ship.ship_id), true).get("ok", false)):
		_fail("away context authority")
		return
	target_placement = context.component_placement
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	var fixture: Dictionary = _prepare_away_component_fixture(context)
	if not bool(fixture.get("ok", false)):
		_fail("fixture: %s" % str(fixture.get("reason", ""))); return
	instance_id = str(fixture.get("instance_id", ""))
	item_form = str(fixture.get("item_form", ""))
	var panel = playable.get_ship_modification_panel_for_validation()
	if panel != null and panel.is_open():
		panel.close()
	if not playable.try_work_action_interact_for_validation():
		_fail("dismount start"); return
	if not playable.has_active_ship_work_for_validation() or playable.work_action_driver.work == null:
		_fail("dismount transaction missing"); return
	instance_id = str(playable.work_action_driver.work.get("target_id"))
	var entry: Dictionary = target_placement.get_entry(instance_id)
	if entry.is_empty():
		_fail("away placement target missing")
		return
	item_form = str(entry.get("item_form", item_form))
	phase = "dismount_tick"


func _tick_until(next_phase: String) -> void:
	playable.advance_active_ship_work_for_validation(0.5)
	tick_accum += 0.5
	if playable.has_active_ship_work_for_validation():
		if tick_accum > 40.0:
			_fail("timeout %s" % next_phase)
		return
	phase = next_phase
	tick_accum = 0.0


func _start_remount() -> void:
	if playable.inventory_state.get_quantity(item_form) < 1:
		_fail("dismount lot missing"); return
	playable.vitals_state.stamina = playable.vitals_state.max_stamina
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	playable.audio_manager.sfx_router.configure({})
	sfx_before = int(playable.audio_manager.sfx_router.get_routed_count(AudioEventSeamScript.SFX_WORK_MOUNT))
	if not playable.try_work_action_interact_for_validation():
		_fail("remount start"); return
	if not playable.has_active_ship_work_for_validation() or playable.work_action_driver.work == null:
		_fail("remount transaction missing"); return
	if str(playable.work_action_driver.work.get("action_id")) != "mount_component":
		_fail("expected mount"); return
	phase = "remount_tick"


func _finish() -> void:
	if target_ship == null or target_placement == null \
			or playable.get_current_occupancy_for_validation() != target_ship \
			or playable.get_selected_ship_id_for_validation() != str(target_ship.ship_id):
		_fail("away context changed")
		return
	if not target_placement.is_mounted(instance_id):
		_fail("component not remounted"); return
	var after: int = int(playable.audio_manager.sfx_router.get_routed_count(AudioEventSeamScript.SFX_WORK_MOUNT))
	if after <= sfx_before:
		_fail("mount sfx not routed before=%d after=%d" % [sfx_before, after]); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	var home = playable.get_home_ship_for_validation()
	if home == null or home.get_live_component_placement() == target_placement \
			or home.get_live_component_placement().get_summary() != home_placement_before:
		_fail("remount crossed into home owner")
		return
	print("COMPONENT REMOUNT SFX LIVE AWAY PASS away=true remount=true sfx=true")
	finished = true
	main_node.queue_free()
	quit(0)


func _prepare_away_component_fixture(context) -> Dictionary:
	if playable.inventory_state.get_quantity("wrench") <= 0:
		playable.inventory_state.add_item("wrench", 1)
	if not playable.open_ship_modification_panel_for_validation():
		return {"ok": false, "reason": "panel"}
	var panel = playable.get_ship_modification_panel_for_validation()
	if panel == null or panel.get_bound_ship_id() != str(target_ship.ship_id):
		return {"ok": false, "reason": "panel_owner"}
	for entry_v in target_placement.placed:
		if not (entry_v is Dictionary) or not bool((entry_v as Dictionary).get("mounted", false)):
			continue
		var entry: Dictionary = entry_v as Dictionary
		var slot_id: String = str(entry.get("component_instance_id", ""))
		var position_v: Variant = playable._component_slot_world_position(slot_id, context)
		if slot_id.is_empty() or not (position_v is Vector3):
			continue
		playable.player.global_position = position_v as Vector3
		playable.recompute_occupancy()
		if playable.get_current_occupancy_for_validation() != target_ship \
				or not panel.select_slot_id(slot_id):
			continue
		panel.set_inventory(playable._inventory_qty_dict_for_work())
		return {
			"ok": true,
			"instance_id": slot_id,
			"item_form": str(entry.get("item_form", "")),
		}
	return {"ok": false, "reason": "no_mounted_away_component"}


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	if finished:
		return
	finished = true
	print("COMPONENT REMOUNT SFX LIVE AWAY FAIL: %s" % msg)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
