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
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")

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
	var home_ship = playable.get_current_ship()
	if home_ship == null:
		_fail("home current_ship missing before travel")
		return
	var home_root: Node = home_ship.scene_root

	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	var selected_marker = in_range[0]
	var selected_marker_id: String = String(selected_marker.marker_id)
	# ADR-0067 fail-closed probe: the only offered candidate has a native
	# LOCKED critical crossing. Rejection must happen before travel mutates the
	# marker, world, ship registry, or active scene.
	var preferred_before: Array = playable.first_run_contract.contract.get("preferred_seeds", []).duplicate()
	playable.first_run_contract.contract["preferred_seeds"] = [777]
	var marker_seed_before: int = int(selected_marker.seed_value)
	var world_position_before: Vector3 = world.player_position
	var generated_before: bool = world.is_generated(selected_marker_id)
	var visited_before: int = playable.visited_ships.size()
	var rejected: Dictionary = playable.travel_to(selected_marker)
	if bool(rejected.get("success", false)) or str(rejected.get("reason", "")) != "first_run_contract_unsatisfied":
		_fail("locked-only first-run contract was not denied explicitly: %s" % str(rejected))
		return
	if int(selected_marker.seed_value) != marker_seed_before \
			or world.player_position != world_position_before \
			or world.is_generated(selected_marker_id) != generated_before \
			or playable.visited_ships.size() != visited_before \
			or playable.get_current_ship() != home_ship \
			or playable.away_from_start:
		_fail("rejected first-run contract mutated marker/world/ship state")
		return
	playable.first_run_contract.contract["preferred_seeds"] = preferred_before
	var travel_result: Dictionary = playable.travel_to_marker_id(selected_marker_id)
	if not bool(travel_result.get("success", false)):
		_fail("travel to derelict failed")
		return
	if not playable.away_from_start:
		_fail("travel succeeded but away_from_start is false")
		return

	var cur = playable.get_current_ship()
	if cur == null:
		_fail("current_ship missing after travel")
		return
	if cur == home_ship or cur.scene_root == home_root:
		_fail("travel retained the pre-travel home ship/root")
		return
	if String(cur.marker_id).is_empty() or String(cur.marker_id) != selected_marker_id:
		_fail("current marker_id=%s expected selected marker_id=%s" % [String(cur.marker_id), selected_marker_id])
		return
	if playable.visited_ships.get(selected_marker_id, null) != cur:
		_fail("selected marker did not resolve to the active visited ShipInstance")
		return
	if travel_result.get("ship", null) != cur.scene_root:
		_fail("travel result ship does not match active ShipInstance scene_root")
		return
	if cur.blueprint == null:
		_fail("active selected ShipInstance has no blueprint")
		return
	# FirstRunContract may replace the transient scanner seed inside
	# travel_to_marker_id. The active blueprint is the persisted resolved identity
	# passed to ShipGenerator for this selected marker.
	var selected_seed: int = int(cur.blueprint.seed_value)
	var selected_size: int = int(cur.blueprint.size)
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
	var loader_layout: Dictionary = loader.get_layout_copy()
	if not layout.recursive_equal(loader_layout, 32):
		_fail("active ShipInstance built_layout differs from GeneratedShipLoader layout")
		return
	var identity_reason: String = _worldgen_identity_error(layout, selected_seed, selected_size)
	if not identity_reason.is_empty():
		_fail(identity_reason)
		return
	var wrong_seed_layout: Dictionary = layout.duplicate(true)
	var wrong_generator: Dictionary = wrong_seed_layout.get("generator", {})
	wrong_generator["seed"] = selected_seed + 1
	wrong_seed_layout["generator"] = wrong_generator
	if _worldgen_identity_error(wrong_seed_layout, selected_seed, selected_size).is_empty():
		_fail("wrong-seed worldgen identity was accepted")
		return
	var home_layout: Dictionary = layout.duplicate(true)
	home_layout["program_id"] = "coherent-proof-ship-001"
	if _worldgen_identity_error(home_layout, selected_seed, selected_size).is_empty():
		_fail("home golden program identity was accepted")
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
	if wreck_expected and not _wreck_evidence_present(layout, loader, selected_seed, selected_size, condition):
		_fail("DAMAGED/WRECKED boarded layout missing preserved native breach or fallback wreck overlay condition=%d kinds=%s generator=%s" % [
			condition, str(_structural_edge_kind_counts(layout)), str(layout.get("generator", {}))])
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

	if playable.first_run_contract == null:
		_fail("first_run_contract missing after travel")
		return
	var contract: Dictionary = playable.first_run_contract.contract
	if contract.is_empty():
		_fail("first_run_contract empty after travel")
		return
	var preferred: Array = contract.get("preferred_seeds", []) as Array
	if preferred.is_empty():
		_fail("first-run preferred_seeds empty")
		return
	var seed_n: int = playable._ship_seed(cur)
	var seed_ok := false
	for seed_variant in preferred:
		if int(seed_variant) == seed_n:
			seed_ok = true
			break
	if not seed_ok:
		_fail("boarded seed=%d is not in first-run preferred_seeds %s" % [seed_n, str(preferred)])
		return
	var gameplay: Dictionary = loader.gameplay_doc.duplicate(true) if typeof(loader.gameplay_doc) == TYPE_DICTIONARY else {}
	var loot_v: Variant = gameplay.get("loot_containers", [])
	if not (loot_v is Array) or (loot_v as Array).is_empty():
		gameplay["loot_containers"] = loader.get_loot_container_specs_copy()
	if not bool(playable.first_run_contract.validate(layout, gameplay)):
		_fail("boarded layout failed FirstRunContract.validate biome=%s difficulty=%s" % [
			str(layout.get("biome_id", "")), str(layout.get("difficulty_id", ""))])
		return
	print("GENERATED SEED BOARDED SLICE PASS away=true nav=true slots=true wreck=true objectives=true away_ticks=30 seed=%d" % seed_n)
	_cleanup(0)


func _worldgen_identity_error(layout: Dictionary, expected_seed: int, expected_size: int) -> String:
	var expected_archetype: String = _worldgen_archetype_for_size(expected_size)
	if expected_archetype.is_empty():
		return "unsupported selected size_class=%d" % expected_size
	var generator_v: Variant = layout.get("generator", {})
	if not (generator_v is Dictionary):
		return "boarded layout generator metadata missing"
	var generator: Dictionary = generator_v as Dictionary
	if str(generator.get("name", "")) != "worldgen" or int(generator.get("generator_version", -1)) != 2:
		return "boarded layout is not worldgen v2"
	if int(generator.get("seed", -1)) != expected_seed:
		return "worldgen seed=%s expected selected seed=%d" % [str(generator.get("seed", "")), expected_seed]
	if str(generator.get("archetype_id", "")) != expected_archetype:
		return "worldgen archetype=%s expected size-%d archetype=%s" % [
			str(generator.get("archetype_id", "")), expected_size, expected_archetype]
	var expected_program_id: String = "worldgen-%s-%d" % [expected_archetype, expected_seed]
	if str(layout.get("program_id", "")) != expected_program_id:
		return "program_id=%s expected=%s" % [str(layout.get("program_id", "")), expected_program_id]
	return ""


func _worldgen_archetype_for_size(size_class: int) -> String:
	match size_class:
		ShipBlueprintScript.Size.LIFE_BOAT:
			return "shuttle"
		ShipBlueprintScript.Size.SMALL:
			return "corvette"
		ShipBlueprintScript.Size.MEDIUM:
			return "freighter"
		_:
			return ""


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
	var start_node: String = _nearest_node_in_room(graph, start_pos, start_id)
	var goal_node: String = _nearest_node_in_room(graph, goal_pos, goal_id)
	if start_node.is_empty() or graph.get_node_room(start_node) != start_id:
		return "standing start node missing in start_room=%s nodes=%d" % [start_id, node_n]
	if start_id == goal_id:
		return ""
	if goal_node.is_empty() or graph.get_node_room(goal_node) != goal_id:
		var occ_n: int = 0
		var plan_v: Variant = layout.get("structural_plan", {})
		if plan_v is Dictionary:
			var occ_v: Variant = (plan_v as Dictionary).get("occupancy", {})
			if occ_v is Dictionary:
				occ_n = (occ_v as Dictionary).size()
		var rooms_n: int = (layout.get("rooms", []) as Array).size() if layout.get("rooms", []) is Array else 0
		var rooms_seen: Array = []
		for key in graph.nodes:
			var rid: String = graph.get_node_room(str(key))
			if not rooms_seen.has(rid):
				rooms_seen.append(rid)
		return "standing goal node missing in goal_room=%s nodes=%d occupancy=%d rooms=%d graph_rooms=%s" % [
			goal_id, node_n, occ_n, rooms_n, str(rooms_seen)]
	var path: Array = ThreatPathfinderScript.find_path(
		graph, graph.get_node_pos(start_node), graph.get_node_pos(goal_node))
	if path.is_empty():
		return "standing start→goal empty nodes=%d start_room=%s goal_room=%s" % [node_n, start_id, goal_id]
	return ""


func _nearest_node_in_room(graph, world_pos: Vector3, room_id: String) -> String:
	var best: String = ""
	var best_d: float = INF
	for key in graph.nodes:
		var nid: String = str(key)
		if graph.get_node_room(nid) != room_id:
			continue
		var p: Vector3 = graph.get_node_pos(nid)
		var d: float = p.distance_squared_to(world_pos)
		if d < best_d:
			best_d = d
			best = nid
	return best


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


func _wreck_evidence_present(
		layout: Dictionary,
		loader: GeneratedShipLoader,
		seed_value: int,
		size: int,
		condition: int) -> bool:
	var generator_variant: Variant = layout.get("generator", {})
	if generator_variant is Dictionary \
			and str((generator_variant as Dictionary).get("name", "")) == "worldgen":
		return _native_breach_preserved_and_loaded(layout, loader, seed_value, size, condition)
	return _fallback_wreck_overlay_present(layout)


func _native_breach_preserved_and_loaded(
		layout: Dictionary,
		loader: GeneratedShipLoader,
		seed_value: int,
		size: int,
		condition: int) -> bool:
	if not ClassDB.class_exists("DerelictGenerator"):
		return false
	if not ShipGeneratorScript.WORLDGEN_ARCHETYPE_BY_SIZE.has(size) \
			or not ShipGeneratorScript.WORLDGEN_INTACTNESS_BY_CONDITION.has(condition):
		return false
	var generator = ClassDB.instantiate("DerelictGenerator")
	if generator == null or not generator.has_method("export_layout_json"):
		return false
	var source_text: String = str(generator.export_layout_json(
		seed_value,
		{
			"archetype_id": str(ShipGeneratorScript.WORLDGEN_ARCHETYPE_BY_SIZE[size]),
			"intactness_override": int(ShipGeneratorScript.WORLDGEN_INTACTNESS_BY_CONDITION[condition]),
		},
		ShipGeneratorScript.WORLDGEN_KIT_ID))
	var source_variant: Variant = JSON.parse_string(source_text)
	if not (source_variant is Dictionary):
		return false
	var source_breaches: Dictionary = _structural_edges_of_kind(source_variant as Dictionary, "BREACH")
	var loaded_breaches: Dictionary = _structural_edges_of_kind(layout, "BREACH")
	if source_breaches.is_empty() or not source_breaches.recursive_equal(loaded_breaches, 32):
		return false

	var portal_specs_by_edge: Dictionary = {}
	for spec_variant in loader.get_authored_portal_specs_copy():
		if not (spec_variant is Dictionary):
			continue
		var spec: Dictionary = spec_variant as Dictionary
		portal_specs_by_edge[str(spec.get("edge_key", ""))] = spec
	var portal_nodes_by_edge: Dictionary = {}
	for node_variant in loader.get_authored_portal_nodes():
		if not is_instance_valid(node_variant):
			continue
		var portal_spec_variant: Variant = node_variant.get("portal_spec")
		if not (portal_spec_variant is Dictionary):
			continue
		portal_nodes_by_edge[str((portal_spec_variant as Dictionary).get("edge_key", ""))] = node_variant
	for edge_key_variant in source_breaches.keys():
		var edge_key: String = str(edge_key_variant)
		var source_edge: Dictionary = source_breaches[edge_key_variant] as Dictionary
		var spec_variant: Variant = portal_specs_by_edge.get(edge_key, null)
		var node_variant: Variant = portal_nodes_by_edge.get(edge_key, null)
		if not (spec_variant is Dictionary) or not is_instance_valid(node_variant):
			return false
		var spec: Dictionary = spec_variant as Dictionary
		if str(spec.get("kind", spec.get("state", ""))).to_upper() != "BREACH" \
				or not bool(spec.get("exterior", false)) \
				or bool(spec.get("exterior", false)) != bool(source_edge.get("exterior", false)):
			return false
		if str(node_variant.get("portal_kind")).to_upper() != "BREACH" \
				or not bool(node_variant.get("is_unsafe")) \
				or not bool(node_variant.get("is_open")) \
				or not bool(node_variant.get("is_exterior")):
			return false
		var blocker_shape: CollisionShape3D = node_variant.call("get_blocker_collision_shape") as CollisionShape3D
		if blocker_shape == null or not blocker_shape.disabled:
			return false
	return true


func _structural_edges_of_kind(layout: Dictionary, required_kind: String) -> Dictionary:
	var result: Dictionary = {}
	var plan_variant: Variant = layout.get("structural_plan", {})
	if not (plan_variant is Dictionary):
		return result
	var edges_variant: Variant = (plan_variant as Dictionary).get("edges", {})
	if not (edges_variant is Dictionary):
		return result
	for edge_key_variant in (edges_variant as Dictionary).keys():
		var edge_variant: Variant = (edges_variant as Dictionary)[edge_key_variant]
		if edge_variant is Dictionary \
				and str((edge_variant as Dictionary).get("kind", "")).to_upper() == required_kind:
			result[str(edge_key_variant)] = (edge_variant as Dictionary).duplicate(true)
	return result


func _fallback_wreck_overlay_present(layout: Dictionary) -> bool:
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


func _structural_edge_kind_counts(layout: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	var plan_variant: Variant = layout.get("structural_plan", {})
	if not (plan_variant is Dictionary):
		return counts
	var edges_variant: Variant = (plan_variant as Dictionary).get("edges", {})
	if not (edges_variant is Dictionary):
		return counts
	for edge_variant in (edges_variant as Dictionary).values():
		if not (edge_variant is Dictionary):
			continue
		var kind: String = str((edge_variant as Dictionary).get("kind", "")).to_upper()
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


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
