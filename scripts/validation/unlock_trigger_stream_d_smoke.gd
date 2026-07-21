extends SceneTree

## Stream D (2026-07-21): training emissions for player actions that already
## exist in production but never fired unlocks / skill XP.
##
## Exercises the LIVE coordinator seams (not bus.emit only):
##   - scanner_panel.open()           → scan_derelict
##   - use_hotbar medicine            → first_aid_self
##   - kitchen station craft complete → cook_meal
##   - fabricator craft complete      → fabricate_part
##   - _on_repair_completed           → repair_subcomponent
##   - _on_breach_sealed              → weld_panel
##   - travel_to success              → plot_course + complete_astrogation
##
## Marker: UNLOCK TRIGGER STREAM D PASS scan=true first_aid=true cook=true
##         fabricate=true repair=true weld=true travel=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 400

const SUBS := {
	"power": ["reactor_core", "power_distribution", "battery_cells"],
	"navigation": ["star_charts", "nav_computer", "sensor_array"],
	"scanners": ["scanner_dish", "signal_processor", "power_coupling"],
	"propulsion": ["thruster_array", "fuel_injection", "nav_linkage"],
}

var main_node: Node
var playable: PlayableGeneratedShip
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
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() \
			or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _log_has(event_id: String) -> bool:
	if playable.training_event_bus == null:
		return false
	for entry in playable.training_event_bus.get_log():
		if str(entry.get("event_id", "")) == event_id:
			return true
	return false

func _set_all_operational(mgr) -> void:
	for sid in SUBS.keys():
		for sub_id in SUBS[sid]:
			mgr.force_repair(sid, sub_id)

func _validate() -> void:
	finished = true
	if playable.training_event_bus == null or playable.inventory_state == null:
		_fail("training bus or inventory missing")
		return

	# --- scan_derelict via real scanner panel open ---
	if playable.scanner_panel == null:
		_fail("scanner_panel missing")
		return
	playable.scanner_panel.open()
	if not _log_has("scan_derelict"):
		_fail("scanner_panel.open did not emit scan_derelict")
		return
	playable.scanner_panel.close()

	# --- first_aid_self via medicine hotbar use ---
	playable.inventory_state.add_item("bandage_kit", 1)
	playable.assign_hotbar_slot_for_validation(0, "bandage_kit")
	var med: Dictionary = playable.use_hotbar_slot_for_validation(0)
	if not bool(med.get("ok", false)):
		_fail("bandage_kit hotbar use failed: %s" % str(med))
		return
	if not _log_has("first_aid_self"):
		_fail("medicine use did not emit first_aid_self")
		return

	# --- cook_meal via kitchen station craft ---
	var inv = playable.inventory_state
	inv.add_item("scrap_metal", 8)
	inv.add_item("wiring_bundle", 8)
	inv.add_item("reactive_gel", 6)
	inv.add_item("circuit_board", 6)
	inv.add_item("synth_fiber", 8)
	inv.add_item("medical_gauze", 4)
	inv.add_item("purified_water", 6)
	inv.add_item("ration_pack", 4)  # cook_basic_meal ingredient
	inv.add_item("plating", 4)
	if playable.player_progression != null:
		playable.player_progression.skills["fabrication"] = 6
		playable.player_progression.skills["cooking"] = 6
	if not playable.craft_at_station_for_validation("kitchen"):
		_fail("kitchen station craft did not start")
		return
	playable.advance_crafting_for_validation(180.0)
	if not _log_has("cook_meal"):
		_fail("kitchen craft complete did not emit cook_meal")
		return

	# --- fabricate_part via fabricator station craft ---
	if not playable.craft_at_station_for_validation("fabricator"):
		_fail("fabricator station craft did not start")
		return
	playable.advance_crafting_for_validation(180.0)
	if not _log_has("fabricate_part"):
		_fail("fabricator craft complete did not emit fabricate_part")
		return

	# --- repair_subcomponent via production repair-completed handler ---
	playable._on_repair_completed("power", "battery_cells")
	if not _log_has("repair_subcomponent"):
		_fail("_on_repair_completed did not emit repair_subcomponent")
		return

	# --- weld_panel via breach seal handler ---
	playable._on_breach_sealed("engineering")
	if not _log_has("weld_panel"):
		_fail("_on_breach_sealed did not emit weld_panel")
		return

	# --- plot_course + complete_astrogation via real travel ---
	var mgr = playable.get_ship_systems_manager()
	if mgr == null:
		_fail("ship systems manager missing")
		return
	_set_all_operational(mgr)
	# Occupancy: player must be aboard piloted ship for travel.
	if playable.player != null and playable.player is Node3D and playable.piloted_ship != null \
			and playable.piloted_ship.scene_root != null and playable.piloted_ship.scene_root is Node3D:
		(playable.player as Node3D).global_position = (playable.piloted_ship.scene_root as Node3D).global_position
	playable.recompute_occupancy()
	var world = playable.get_synaptic_sea_world()
	if world == null:
		_fail("synaptic_sea_world missing")
		return
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range for travel")
		return
	var target = in_range[0]
	var travel: Dictionary = playable.travel_to(target)
	if not bool(travel.get("success", false)):
		_fail("travel_to failed: %s" % str(travel.get("reason", travel)))
		return
	if not _log_has("plot_course"):
		_fail("successful travel did not emit plot_course")
		return
	if not _log_has("complete_astrogation"):
		_fail("successful travel did not emit complete_astrogation")
		return

	print("UNLOCK TRIGGER STREAM D PASS scan=true first_aid=true cook=true fabricate=true repair=true weld=true travel=true")
	_cleanup(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("UNLOCK TRIGGER STREAM D FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
