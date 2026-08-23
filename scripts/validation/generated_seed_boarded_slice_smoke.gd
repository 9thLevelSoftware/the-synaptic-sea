extends SceneTree

## REQ-SLICE-001. Real boarding path, no away_from_start flag-flip.
## Marker: GENERATED SEED BOARDED SLICE PASS away=true nav=true slots=true wreck=true objectives=true away_ticks=30

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const AWAY_TICKS: int = 30
const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")
const ThreatPathfinderScript := preload("res://scripts/systems/threat_pathfinder.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")

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
	if not is_instance_valid(playable):
		playable = _find_playable(main_node)
	if not is_instance_valid(playable) or not is_instance_valid(playable.loader) \
			or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()


func _all_operational(mgr) -> void:
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys == null:
			continue
		for sub in sys.subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)


func _validate() -> void:
	finished = true
	_all_operational(playable.get_ship_systems_manager())

	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	if not bool(playable.travel_to_marker_id(String(in_range[0].marker_id)).get("success", false)):
		_fail("travel to derelict failed")
		return
	if not playable.away_from_start:
		_fail("travel succeeded but away_from_start is false")
		return

	var cur = playable.get_current_ship()
	if cur == null:
		_fail("current_ship missing after travel")
		return
	var derelict_root = cur.scene_root
	if derelict_root == null or not is_instance_valid(derelict_root):
		_fail("derelict scene_root missing")
		return
	if not (derelict_root is GeneratedShipLoader):
		_fail("derelict scene_root is not GeneratedShipLoader")
		return
	var loader: GeneratedShipLoader = derelict_root as GeneratedShipLoader
	if not loader.has_loaded_ship():
		_fail("derelict GeneratedShipLoader has not loaded")
		return

	var layout: Dictionary = cur.built_layout if typeof(cur.built_layout) == TYPE_DICTIONARY else {}
	if layout.is_empty() and loader.has_method("get_layout_copy"):
		layout = loader.get_layout_copy()
	if layout.is_empty():
		_fail("boarded layout empty")
		return
	var program_id: String = str(layout.get("program_id", ""))
	if program_id == "coherent-proof-ship-001" or not program_id.begins_with("procgen-"):
		_fail("boarded layout is hub golden, program_id=%s" % program_id)
		return
	if str(layout.get("schema_version", "")) != "1.2.0":
		_fail("schema_version=%s expected 1.2.0" % str(layout.get("schema_version", "")))
		return

	var plan_v: Variant = layout.get("structural_plan", {})
	if not (plan_v is Dictionary) or (plan_v as Dictionary).is_empty():
		_fail("structural_plan missing")
		return
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(plan_v as Dictionary, layout)
	if not bool(verdict.get("ok", false)):
		_fail("enclosure validator failed: %s" % str(verdict.get("errors", [])))
		return

	var standing_reason: String = _standing_start_to_goal(layout, loader)
	if not standing_reason.is_empty():
		_fail(standing_reason)
		return

	var objectives: Array = loader.get_objective_specs_copy()
	if objectives.is_empty():
		_fail("no objective specs on boarded wreck")
		return

	var loot: Array = loader.get_loot_container_specs_copy()
	if not _loot_on_interior_slot(layout, loot):
		_fail("no loot spec on interior_zones center/wall slot")
		return

	var condition: int = playable._ship_condition_class(cur)
	var wreck_expected: bool = condition == ShipBlueprintScript.Condition.DAMAGED \
		or condition == ShipBlueprintScript.Condition.WRECKED
	if wreck_expected and not _wreck_overlay_present(layout):
		_fail("DAMAGED/WRECKED boarded layout missing blocked_links/LOCKED overlay or wreck_applied")
		return
	if not wreck_expected:
		_fail("boarded condition=%d is not DAMAGED/WRECKED; wreck overlay required" % condition)
		return

	var play_time_before: float = float(playable.run_play_time_seconds)
	# Decremented only inside `_tick_present_ships`, which the away `_process`
	# body calls after the early `playable_started`/`slice_complete` return.
	playable._biomatter_pulse_cooldown = 10.0
	for _i in range(AWAY_TICKS):
		playable._process(0.1)
	if not playable.away_from_start:
		_fail("away_from_start became false during away ticks")
		return
	var expected_dt: float = 0.1 * float(AWAY_TICKS)
	if float(playable.run_play_time_seconds) + 0.001 < play_time_before + expected_dt:
		_fail("run_play_time_seconds did not advance through away _process ticks")
		return
	var cooldown_after: float = float(playable._biomatter_pulse_cooldown)
	if absf(cooldown_after - (10.0 - expected_dt)) > 0.05:
		_fail("away _process did not tick present ships (cooldown=%s expected=%s)" % [
			str(cooldown_after), str(10.0 - expected_dt)])
		return
	var hud_lines: PackedStringArray = playable.get_combined_system_status_lines()
	if hud_lines.is_empty() and not bool(playable.complete_objective_sequence_for_validation(1)):
		_fail("HUD/objective surface dead after away ticks")
		return

	var seed_n: int = playable._ship_seed(cur)
	print("GENERATED SEED BOARDED SLICE PASS away=true nav=true slots=true wreck=true objectives=true away_ticks=30 seed=%d" % seed_n)
	_cleanup(0)


func _standing_start_to_goal(layout: Dictionary, loader: GeneratedShipLoader) -> String:
	var graph = ShipNavGraphScript.new()
	var node_n: int = graph.build_from_layout(layout)
	if node_n <= 0:
		return "standing nav nodes=0"
	var proto_v: Variant = layout.get("prototype", {})
	var proto: Dictionary = proto_v if proto_v is Dictionary else {}
	var start_id: String = str(proto.get("start_room", ""))
	var goal_id: String = str(proto.get("goal_room", ""))
	if start_id.is_empty() or goal_id.is_empty():
		return "prototype start/goal room missing"
	var start_pos: Vector3 = loader.start_position
	var goal_pos: Vector3 = loader.get_goal_position()
	if start_pos == Vector3.INF:
		start_pos = _standing_room_pos(layout, start_id)
	if goal_pos == Vector3.INF:
		goal_pos = _standing_room_pos(layout, goal_id)
	if start_pos == Vector3.INF or goal_pos == Vector3.INF:
		return "standing start/goal position missing start_room=%s goal_room=%s" % [start_id, goal_id]
	if start_id == goal_id:
		if graph.nearest_node(start_pos).is_empty():
			return "standing start node missing for start_room=%s nodes=%d" % [start_id, node_n]
		return ""
	var path: Array = ThreatPathfinderScript.find_path(graph, start_pos, goal_pos)
	if path.is_empty():
		return "standing start→goal empty nodes=%d start_room=%s goal_room=%s" % [node_n, start_id, goal_id]
	return ""


func _standing_room_pos(layout: Dictionary, room_id: String) -> Vector3:
	var occupancy: Dictionary = {}
	var plan_v: Variant = layout.get("structural_plan", {})
	if plan_v is Dictionary:
		var occ_v: Variant = (plan_v as Dictionary).get("occupancy", {})
		if occ_v is Dictionary:
			occupancy = occ_v
	for record_variant in occupancy.values():
		if not (record_variant is Dictionary):
			continue
		var record: Dictionary = record_variant
		if str(record.get("room_id", "")) != room_id:
			continue
		var raw: Variant = record.get("position", record.get("world_position", null))
		if raw is Vector3:
			return raw as Vector3
		if raw is Array and (raw as Array).size() >= 3:
			return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	var rooms_v: Variant = layout.get("rooms", [])
	var rooms: Array = rooms_v if rooms_v is Array else []
	var room: Dictionary = _room_by_id(rooms, room_id)
	for placement in room.get("structural_placements", []):
		if typeof(placement) != TYPE_DICTIONARY:
			continue
		var module_id: String = str((placement as Dictionary).get("module_id", (placement as Dictionary).get("module", "")))
		if not module_id.begins_with("floor_") and not module_id.begins_with("corridor_floor"):
			continue
		var wp: Variant = (placement as Dictionary).get("world_position", null)
		if wp is Vector3:
			return wp as Vector3
		if wp is Array and (wp as Array).size() >= 3:
			return Vector3(float(wp[0]), float(wp[1]), float(wp[2]))
	return Vector3.INF


func _loot_on_interior_slot(layout: Dictionary, loot: Array) -> bool:
	var rooms_v: Variant = layout.get("rooms", [])
	var rooms: Array = rooms_v if rooms_v is Array else []
	for loot_v in loot:
		if typeof(loot_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = loot_v
		var room: Dictionary = _room_by_id(rooms, str(row.get("room_id", "")))
		var approach: Array = LayoutSerializerScript.parse_slot_cell(row.get("approach_cell", []))
		if approach.size() < 2:
			continue
		if _cell_in_slots(room, approach):
			return true
	return false


func _wreck_overlay_present(layout: Dictionary) -> bool:
	if not bool(layout.get("wreck_applied", false)):
		return false
	var blocked_v: Variant = layout.get("blocked_links", [])
	if blocked_v is Array and not (blocked_v as Array).is_empty():
		return true
	var damage_v: Variant = layout.get("module_damage", [])
	if damage_v is Array and not (damage_v as Array).is_empty():
		return true
	var plan_v: Variant = layout.get("structural_plan", {})
	if plan_v is Dictionary:
		var edges_v: Variant = (plan_v as Dictionary).get("edges", {})
		if edges_v is Dictionary:
			for edge_v in (edges_v as Dictionary).values():
				if not (edge_v is Dictionary):
					continue
				var kind: String = str((edge_v as Dictionary).get("kind", "")).to_upper()
				if kind == "LOCKED" or kind == "BREACH":
					return true
	return false


func _room_by_id(rooms: Array, room_id: String) -> Dictionary:
	for room_v in rooms:
		if typeof(room_v) == TYPE_DICTIONARY and str((room_v as Dictionary).get("id", "")) == room_id:
			return room_v
	return {}


func _cell_in_slots(room: Dictionary, cell: Array) -> bool:
	if cell.size() < 2:
		return false
	var interior: Variant = room.get("interior_zones", {})
	if not (interior is Dictionary):
		return false
	for bucket_v in [interior.get("center_slots", []), interior.get("wall_slots", [])]:
		if not (bucket_v is Array):
			continue
		for item in (bucket_v as Array):
			var parsed: Array = LayoutSerializerScript.parse_slot_cell(item)
			if parsed.size() >= 2 and int(parsed[0]) == int(cell[0]) and int(parsed[1]) == int(cell[1]):
				return true
	return false


func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	push_error("GENERATED SEED BOARDED SLICE FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)


func _cleanup(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
