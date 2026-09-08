extends SceneTree

const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ObjectiveTrackerScript := preload("res://scripts/ui/objective_tracker.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")

const LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
const HISTORICAL_GOAL_ID: String = "bridge_07:reach_goal"
const PREPARED_GOAL_ID: String = "obj_reach_goal"
const HISTORICAL_GOAL_ROOM: String = "bridge_07"

var loaded: bool = false
var failed_reason: String = ""


func _initialize() -> void:
	var root_node: Node3D = Node3D.new()
	root_node.name = "LoaderPlayableContractSmokeRoot"
	get_root().add_child(root_node)

	var loader = GeneratedShipLoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(_on_ship_loaded)
	loader.load_failed.connect(_on_load_failed)
	root_node.add_child(loader)

	var raw_layout: Dictionary = _load_json(LAYOUT_PATH)
	if raw_layout.is_empty():
		push_error("loader contract smoke failed: stored raw layout could not be read")
		quit(1)
		return
	var raw_gameplay: Dictionary = _load_json(GAMEPLAY_SLICE_PATH)
	if raw_gameplay.is_empty() or not _objective_ids(raw_gameplay.get("objectives", [])).has(HISTORICAL_GOAL_ID):
		push_error("loader contract smoke failed: historical gameplay goal is missing")
		quit(1)
		return
	# Keep the historical fixture immutable. Production preparation performs the
	# detached endpoint/structural compilation transaction before the loader sees it.
	var documents: Dictionary = ShipGeneratorScript.new()._prepare_layout_documents(raw_layout)
	if not bool(documents.get("ok", false)):
		push_error("loader contract smoke failed: production preparation reason=%s" % documents.get("reason", ""))
		quit(1)
		return
	var ok: bool = loader.load_from_documents(
		documents.get("layout", {}),
		documents.get("kit", {}),
		documents.get("gameplay", {}),
		false,
		{"layout": LAYOUT_PATH, "kit": KIT_PATH, "gameplay_slice": GAMEPLAY_SLICE_PATH},
	)
	if not ok or not loaded:
		push_error("loader contract smoke failed: load_failed reason=%s" % failed_reason)
		quit(1)
		return

	if not loader.has_loaded_ship():
		push_error("loader contract smoke failed: has_loaded_ship=false")
		quit(1)
		return
	if loader.get_start_transform().origin == Vector3.INF:
		push_error("loader contract smoke failed: invalid start transform")
		quit(1)
		return
	if loader.get_goal_position() == Vector3.INF:
		push_error("loader contract smoke failed: invalid goal position")
		quit(1)
		return
	var expected_objectives: Array = (documents.get("gameplay", {}) as Dictionary).get("objectives", []) as Array
	var objective_specs: Array = loader.get_objective_specs_copy()
	var objective_error: String = _objective_contract_error(expected_objectives, objective_specs)
	if not objective_error.is_empty():
		push_error("loader contract smoke failed: " + objective_error)
		quit(1)
		return
	var loaded_objectives: Dictionary = _objective_ids(objective_specs)
	if not loaded_objectives.has(PREPARED_GOAL_ID):
		push_error("loader contract smoke failed: prepared loader lost canonical goal=%s" % PREPARED_GOAL_ID)
		quit(1)
		return
	var prepared_goal: Dictionary = loaded_objectives[PREPARED_GOAL_ID] as Dictionary
	var prepared_sequence: int = int(prepared_goal.get("sequence", 0))
	if str(prepared_goal.get("room_id", "")) != HISTORICAL_GOAL_ROOM:
		push_error("loader contract smoke failed: prepared goal lost historical bridge room")
		quit(1)
		return
	if prepared_sequence <= 0:
		push_error("loader contract smoke failed: prepared bridge goal has invalid sequence")
		quit(1)
		return
	if loader.count_collision_shapes() <= 0:
		push_error("loader contract smoke failed: collision shape count is zero")
		quit(1)
		return
	var edge_wrapper_count: int = _count_wrappers_with_meta(loader.structural_root, "structural_edge_key")
	var floor_wrapper_count: int = _count_wrappers_with_meta(loader.structural_root, "structural_cell_key")
	var structural_plan: Dictionary = loader.layout_doc.get("structural_plan", {})
	var expected_edge_count: int = (structural_plan.get("placements", []) as Array).size()
	var expected_floor_count: int = (structural_plan.get("floor_placements", []) as Array).size()
	if edge_wrapper_count != expected_edge_count:
		push_error("loader contract smoke failed: edge wrappers=%d expected=%d" % [edge_wrapper_count, expected_edge_count])
		quit(1)
		return
	if floor_wrapper_count != expected_floor_count or floor_wrapper_count <= 0:
		push_error("loader contract smoke failed: floor wrappers=%d expected=%d" % [floor_wrapper_count, expected_floor_count])
		quit(1)
		return
	if _count_floor_wrappers_with_edge_meta(loader.structural_root) != 0:
		push_error("loader contract smoke failed: floor wrapper has fake edge metadata")
		quit(1)
		return

	var tracker = ObjectiveTrackerScript.new()
	tracker.name = "LoaderPlayableContractSmokeTracker"
	root_node.add_child(tracker)
	tracker.set_objectives(loader.get_objective_specs_copy())
	tracker.mark_completed(prepared_sequence)
	if tracker.get_completed_count() != 1 or not tracker.is_sequence_completed(prepared_sequence):
		push_error("loader contract smoke failed: tracker helper methods failed")
		quit(1)
		return

	print(
		"PROCGEN LOADER PLAYABLE CONTRACT PASS loaded=true objectives=%d collision_shapes=%d structural_live=true edge_wrappers=%d floor_wrappers=%d"
		% [objective_specs.size(), loader.count_collision_shapes(), edge_wrapper_count, floor_wrapper_count]
	)
	quit(0)


func _count_wrappers_with_meta(node: Node, meta_name: String) -> int:
	var count: int = 1 if node.has_meta(meta_name) else 0
	for child in node.get_children():
		count += _count_wrappers_with_meta(child, meta_name)
	return count


func _count_floor_wrappers_with_edge_meta(node: Node) -> int:
	var count: int = 0
	if node.has_meta("structural_cell_key") and node.has_meta("structural_edge_key"):
		count += 1
	for child in node.get_children():
		count += _count_floor_wrappers_with_edge_meta(child)
	return count


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _objective_ids(objectives_variant: Variant) -> Dictionary:
	var objectives: Dictionary = {}
	if not objectives_variant is Array:
		return objectives
	for objective_variant in objectives_variant as Array:
		if not objective_variant is Dictionary:
			return {}
		var objective: Dictionary = objective_variant
		var objective_id: String = str(objective.get("id", ""))
		if objective_id.is_empty() or objectives.has(objective_id):
			return {}
		objectives[objective_id] = objective
	return objectives


func _objective_contract_error(expected: Array, actual: Array) -> String:
	var expected_by_id: Dictionary = _objective_ids(expected)
	var actual_by_id: Dictionary = _objective_ids(actual)
	if expected_by_id.is_empty() or actual_by_id.is_empty():
		return "prepared objective records are malformed"
	if expected_by_id.size() != actual_by_id.size():
		return "prepared objective count differs expected=%d actual=%d" % [expected_by_id.size(), actual_by_id.size()]
	for objective_id_variant in expected_by_id.keys():
		var objective_id: String = str(objective_id_variant)
		if not actual_by_id.has(objective_id):
			return "prepared objective missing id=%s" % objective_id
		var expected_record: Dictionary = expected_by_id[objective_id] as Dictionary
		var actual_record: Dictionary = actual_by_id[objective_id] as Dictionary
		for field in ["room_id", "kind", "semantic", "sequence", "type", "interactable"]:
			if expected_record.has(field) and expected_record.get(field) != actual_record.get(field):
				return "prepared objective changed id=%s field=%s" % [objective_id, field]
	return ""


func _on_ship_loaded(_summary: Dictionary) -> void:
	loaded = true


func _on_load_failed(reason: String) -> void:
	failed_reason = reason
