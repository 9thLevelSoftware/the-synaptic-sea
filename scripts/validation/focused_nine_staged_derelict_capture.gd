extends Node3D

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")

const STAGED_IMPORT_PREFIX := "res://assets/imported/structural/ship_structural_v0/"
const STAGED_WRAPPER_PREFIX := "res://scenes/wrappers/structural/ship_structural_v0/"
const STAGED_INPUT_COUNT := 17
const IMAGE_SIZE := Vector2i(1600, 900)
const DEFAULT_SEED := 17
const IMAGE_NAME := "focused-nine-staged-derelict.png"
const DEBUG_BUNDLE_NAME := "edge_map.json"
const STAGED_CAPTURE_ID := "StagedFocusedNine"
const PORTAL_KINDS: Array[String] = ["DOOR", "LOCKED", "HATCH", "BREACH"]

@onready var ship_camera: Camera3D = $DerelictCamera

var seed_value: int = DEFAULT_SEED
var output_dir: String = "artifacts/validation-previews/focused-nine"
var staged_input_count: int = STAGED_INPUT_COUNT
var generated_root: Node3D


func _ready() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("non-headless capture is required")
		return
	_parse_user_arguments()
	get_window().size = IMAGE_SIZE

	var blueprint = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.SMALL,
		ShipBlueprintScript.Condition.WRECKED,
		seed_value,
	)
	blueprint.room_count_range = Vector2i(5, 8)
	var derelict_archetype: Dictionary = _derelict_archetype()
	# Focused-nine is a structural shell preview; some deterministic templates
	# have no eligible dock zone, and treating that optional role as guaranteed
	# would turn a valid canonical layout into an unexpected warning.
	derelict_archetype["guaranteed_roles"] = []
	# The focused-nine acceptance lane is a 5-8 room shell. The compact
	# production template has six authored zones, while the legacy selector's
	# seed-17 choice is a ten-zone template and cannot satisfy that lane.
	derelict_archetype["template"] = "compact"
	var generator = ShipGeneratorScript.new()
	var generated: Node3D = generator.generate(blueprint, derelict_archetype)
	if generated == null:
		_fail("ShipGenerator returned null")
		return

	generated_root = generated
	generated_root.name = "GeneratedDerelict"
	$GeneratedShipRoot.add_child(generated_root)
	var loader = generated_root as GeneratedShipLoaderScript
	if loader == null:
		_fail("ShipGenerator did not return a GeneratedShipLoader")
		return

	var layout: Dictionary = loader.get_layout_copy()
	var structure_verdict: Dictionary = _validate_compiled_structure(layout, loader)
	if not bool(structure_verdict.get("ok", false)):
		_fail(String(structure_verdict.get("error", "compiled structure validation failed")))
		return
	_fit_camera_to_structural_bounds(layout)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_capture(layout, structure_verdict)


func _derelict_archetype() -> Dictionary:
	var archetype_path := "res://data/procgen/archetypes/derelict.json"
	if FileAccess.file_exists(archetype_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(archetype_path))
		if parsed is Dictionary:
			return (parsed as Dictionary).duplicate(true)
	return {
		"name": "Derelict",
		"type": "derelict",
		"role_weights": {"cargo": 4, "corridor": 3, "bridge": 3, "dock": 1},
		"guaranteed_roles": ["dock"],
		"max_duplicates": 3,
	}


func _parse_user_arguments() -> void:
	var user_args := OS.get_cmdline_user_args()
	var index := 0
	while index < user_args.size():
		var argument := str(user_args[index])
		if argument == "--seed" and index + 1 < user_args.size():
			seed_value = int(user_args[index + 1])
			index += 2
			continue
		if argument == "--output-dir" and index + 1 < user_args.size():
			output_dir = str(user_args[index + 1]).trim_suffix("/")
			index += 2
			continue
		if argument == "--staged-input-count" and index + 1 < user_args.size():
			staged_input_count = int(user_args[index + 1])
			index += 2
			continue
		index += 1


func _validate_compiled_structure(layout: Dictionary, loader) -> Dictionary:
	var structural_plan_variant: Variant = layout.get("structural_plan", null)
	if not (structural_plan_variant is Dictionary):
		return {"ok": false, "error": "GeneratedShipLoader has no structural_plan"}
	var structural_plan: Dictionary = structural_plan_variant
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
	if not bool(verdict.get("ok", false)):
		return {"ok": false, "error": "canonical structural validation failed: %s" % JSON.stringify(verdict.get("errors", []))}

	var edges_variant: Variant = structural_plan.get("edges", null)
	var placements_variant: Variant = structural_plan.get("placements", null)
	var occupancy_variant: Variant = structural_plan.get("occupancy", null)
	if not (edges_variant is Dictionary) or not (placements_variant is Array) or not (occupancy_variant is Dictionary):
		return {"ok": false, "error": "compiled structural metadata is incomplete"}
	var edges: Dictionary = edges_variant
	var placements: Array = placements_variant
	var occupancy: Dictionary = occupancy_variant
	var placement_by_edge: Dictionary = {}
	var wall_count := 0
	var portal_count := 0
	for placement_variant in placements:
		if not (placement_variant is Dictionary):
			return {"ok": false, "error": "compiled placement record is not a Dictionary"}
		var placement: Dictionary = placement_variant
		var edge_key := str(placement.get("edge_key", ""))
		if edge_key.is_empty():
			return {"ok": false, "error": "compiled placement has an empty edge key"}
		if placement_by_edge.has(edge_key):
			return {"ok": false, "error": "duplicate edge key in loader placement metadata: %s" % edge_key}
		placement_by_edge[edge_key] = placement
		var kind := str(placement.get("kind", ""))
		if kind == "SOLID":
			wall_count += 1
		elif PORTAL_KINDS.has(kind):
			portal_count += 1
		if not edges.has(edge_key):
			return {"ok": false, "error": "placement references missing canonical edge: %s" % edge_key}
		var edge: Dictionary = edges[edge_key]
		if PORTAL_KINDS.has(str(edge.get("kind", ""))) and kind == "SOLID":
			return {"ok": false, "error": "portal edge has wall placement: %s" % edge_key}

	for edge_key_variant in edges.keys():
		var edge_key := str(edge_key_variant)
		var edge: Dictionary = edges[edge_key_variant]
		var kind := str(edge.get("kind", ""))
		if not PORTAL_KINDS.has(kind):
			continue
		var room_ids_variant: Variant = edge.get("room_ids", [])
		var room_ids: Array = room_ids_variant if room_ids_variant is Array else []
		var endpoint_count := 0
		for room_id_variant in room_ids:
			if not str(room_id_variant).is_empty():
				endpoint_count += 1
		if endpoint_count != 2 and not bool(edge.get("exterior", false)):
			return {"ok": false, "error": "portal endpoint reciprocity failed: %s" % edge_key}
		if kind != "BREACH" and not placement_by_edge.has(edge_key):
			return {"ok": false, "error": "portal edge has no wrapper placement: %s" % edge_key}

	var wrapper_metadata: Array = _collect_structural_wrapper_metadata(loader)
	if wrapper_metadata.size() != placements.size():
		return {
			"ok": false,
			"error": "GeneratedShipLoader metadata count mismatch placements=%d wrappers=%d" % [placements.size(), wrapper_metadata.size()],
		}
	for wrapper_variant in wrapper_metadata:
		var wrapper: Dictionary = wrapper_variant
		var edge_key := str(wrapper.get("edge_key", ""))
		if edge_key.is_empty() or not placement_by_edge.has(edge_key):
			return {"ok": false, "error": "wrapper metadata is not backed by a compiled placement"}

	return {
		"ok": true,
		"structural_plan": structural_plan,
		"wrapper_metadata": wrapper_metadata,
		"placement_count": placements.size(),
		"wall_count": wall_count,
		"portal_count": portal_count,
		"room_count": (layout.get("rooms", []) as Array).size(),
		"occupancy_count": occupancy.size(),
	}


func _collect_structural_wrapper_metadata(loader) -> Array:
	var records: Array = []
	var structural_root: Node = loader.get_node_or_null("StructuralRoot")
	if structural_root == null:
		return records
	_collect_structural_wrapper_metadata_recursive(structural_root, records)
	return records


func _collect_structural_wrapper_metadata_recursive(node: Node, records: Array) -> void:
	if node.has_meta("structural_edge_key"):
		records.append({
			"name": node.name,
			"edge_key": str(node.get_meta("structural_edge_key", "")),
			"kind": str(node.get_meta("structural_kind", "")),
			"placement_id": str(node.get_meta("structural_placement_id", "")),
			"room_ids": _json_safe(node.get_meta("structural_room_ids", [])),
			"scene_path": node.get_scene_file_path(),
		})
	for child in node.get_children():
		_collect_structural_wrapper_metadata_recursive(child, records)


func _fit_camera_to_structural_bounds(layout: Dictionary) -> void:
	var structural_plan: Dictionary = layout.get("structural_plan", {})
	var bounds := {"min_x": INF, "max_x": -INF, "min_z": INF, "max_z": -INF}
	var occupancy_variant: Variant = structural_plan.get("occupancy", {})
	if occupancy_variant is Dictionary:
		for record_variant in (occupancy_variant as Dictionary).values():
			if record_variant is Dictionary:
				_include_position_in_bounds(record_variant.get("position", null), bounds)
	var placements_variant: Variant = structural_plan.get("placements", [])
	if placements_variant is Array:
		for record_variant in placements_variant:
			if record_variant is Dictionary:
				_include_position_in_bounds(record_variant.get("position", null), bounds)
	if bounds["min_x"] == INF:
		_fail("compiled structural plan has no spatial bounds")
		return

	var center := Vector3(
		(float(bounds["min_x"]) + float(bounds["max_x"])) * 0.5,
		0.0,
		(float(bounds["min_z"]) + float(bounds["max_z"])) * 0.5,
	)
	var span: float = maxf(float(bounds["max_x"]) - float(bounds["min_x"]), float(bounds["max_z"]) - float(bounds["min_z"]))
	span = maxf(span, 8.0)
	ship_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	ship_camera.size = span * 1.35
	ship_camera.position = center + Vector3(span * 0.72, span * 0.95, span * 0.72)
	ship_camera.look_at(center, Vector3.UP)


func _include_position_in_bounds(raw: Variant, bounds: Dictionary) -> void:
	var position := _read_position(raw)
	if position == Vector3.INF:
		return
	bounds["min_x"] = minf(float(bounds["min_x"]), position.x)
	bounds["max_x"] = maxf(float(bounds["max_x"]), position.x)
	bounds["min_z"] = minf(float(bounds["min_z"]), position.z)
	bounds["max_z"] = maxf(float(bounds["max_z"]), position.z)


func _read_position(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		var values: Array = raw
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	if raw is String:
		var text := String(raw).strip_edges()
		if text.begins_with("Vector3(") and text.ends_with(")"):
			text = text.substr(8, text.length() - 9)
		elif text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		var parts: PackedStringArray = text.split(",")
		if parts.size() >= 3:
			for part in parts.slice(0, 3):
				if not String(part).strip_edges().is_valid_float():
					return Vector3.INF
			return Vector3(
				float(parts[0].strip_edges()),
				float(parts[1].strip_edges()),
				float(parts[2].strip_edges()),
			)
	return Vector3.INF


func _capture(layout: Dictionary, structure_verdict: Dictionary) -> void:
	var output_path := ProjectSettings.globalize_path("res://" + output_dir.trim_prefix("res://") + "/" + IMAGE_NAME)
	var output_parent := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(output_parent)
	var debug_path := output_parent.path_join(DEBUG_BUNDLE_NAME)
	var debug_document: Dictionary = _build_debug_bundle(layout, structure_verdict)
	var debug_file: FileAccess = FileAccess.open(debug_path, FileAccess.WRITE)
	if debug_file == null:
		_fail("could not write canonical edge debug bundle")
		return
	debug_file.store_string(JSON.stringify(debug_document, "  "))
	debug_file.close()

	var image := get_viewport().get_texture().get_image()
	if image == null or image.get_size() != IMAGE_SIZE:
		_fail("viewport capture was not 1600x900")
		return
	var save_error := image.save_png(output_path)
	if save_error != OK:
		_fail("PNG capture failed with error %s" % save_error)
		return

	var inspection := _inspect_tree(generated_root)
	if int(inspection["wrapper_count"]) <= 0:
		_fail("tree inspection found no generated staged wrappers")
		return
	if int(inspection["staged_glb_count"]) <= 0:
		_fail("tree inspection found no staged GLB identities")
		return
	if int(inspection["live_reference_count"]) != 0:
		_fail("tree inspection found live imported visual references")
		return

	var logical_output := "res://" + output_dir.trim_prefix("res://") + "/" + IMAGE_NAME
	var logical_debug := "res://" + output_dir.trim_prefix("res://") + "/" + DEBUG_BUNDLE_NAME
	print(
		"%sseed=%d rooms=%d placements=%d walls=%d portals=%d staged_wrapper_count=%d staged=%d debug=%s output=%s" % [
			"FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS ",
			seed_value,
			int(structure_verdict["room_count"]),
			int(structure_verdict["placement_count"]),
			int(structure_verdict["wall_count"]),
			int(structure_verdict["portal_count"]),
			int(inspection["wrapper_count"]),
			staged_input_count,
			logical_debug,
			logical_output,
		]
	)
	get_tree().quit(0)


func _build_debug_bundle(layout: Dictionary, structure_verdict: Dictionary) -> Dictionary:
	var structural_plan: Dictionary = structure_verdict["structural_plan"]
	var edges: Array = []
	var edge_map: Dictionary = structural_plan.get("edges", {})
	var edge_keys: Array[String] = []
	for key_variant in edge_map.keys():
		edge_keys.append(str(key_variant))
	edge_keys.sort()
	for edge_key in edge_keys:
		var edge: Dictionary = edge_map[edge_key]
		var record := edge.duplicate(true)
		record["edge_key"] = edge_key
		edges.append(_json_safe(record))

	var placements: Array = []
	for placement_variant in structural_plan.get("placements", []):
		if placement_variant is Dictionary:
			placements.append(_json_safe(placement_variant))
	placements.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return str(first.get("edge_key", "")) < str(second.get("edge_key", ""))
	)

	var occupancy: Array = []
	var occupancy_map: Dictionary = structural_plan.get("occupancy", {})
	var occupancy_keys: Array[String] = []
	for key_variant in occupancy_map.keys():
		occupancy_keys.append(str(key_variant))
	occupancy_keys.sort()
	for cell_key in occupancy_keys:
		occupancy.append(_json_safe(occupancy_map[cell_key]))

	return {
		"schema": "focused_nine_canonical_edge_map_v1",
		"capture_id": STAGED_CAPTURE_ID,
		"seed": seed_value,
		"rooms": int(structure_verdict["room_count"]),
		"occupancy": occupancy,
		"edges": edges,
		"placements": placements,
		"wrapper_metadata": structure_verdict["wrapper_metadata"],
		"validation": {
			"edge_keys_unique": true,
			"portal_endpoints_valid": true,
			"no_portal_wall_overlap": true,
			"canonical_validator": true,
		},
	}


func _json_safe(value: Variant) -> Variant:
	if value is Vector2i:
		var cell: Vector2i = value
		return [cell.x, cell.y]
	if value is Vector3:
		var position: Vector3 = value
		return [position.x, position.y, position.z]
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key_variant in value.keys():
			dictionary[str(key_variant)] = _json_safe(value[key_variant])
		return dictionary
	if value is Array:
		var array: Array = []
		for child in value:
			array.append(_json_safe(child))
		return array
	return value


func _inspect_tree(node: Node) -> Dictionary:
	var result := {"wrapper_count": 0, "staged_glb_count": 0, "live_reference_count": 0}
	var scene_path := node.get_scene_file_path()
	if scene_path.begins_with(STAGED_WRAPPER_PREFIX):
		result["wrapper_count"] = int(result["wrapper_count"]) + 1
	if scene_path.ends_with(".glb"):
		if scene_path.begins_with(STAGED_IMPORT_PREFIX):
			result["staged_glb_count"] = int(result["staged_glb_count"]) + 1
		else:
			result["live_reference_count"] = int(result["live_reference_count"]) + 1
	for child in node.get_children():
		var child_result := _inspect_tree(child)
		for key in result.keys():
			result[key] = int(result[key]) + int(child_result[key])
	return result


func _fail(message: String) -> void:
	push_error("FOCUSED_NINE_STAGED_DERELICT_CAPTURE FAIL: " + message)
	get_tree().quit(1)
