extends SceneTree

## Task9 structural parity evidence.
##
## The staged edge_map.json is the committed result of the disposable staged
## overlay capture. This smoke regenerates the same seed through the live
## ShipGenerator/GeneratedShipLoader wrappers, then compares only the
## canonical structural inventory. GLB/material and scene-path differences are
## visual-only and intentionally excluded from the structural comparison.
## Marker: PROCGEN GOLDEN PARITY PASS seed=17 placements=48 wrappers=48 structural=true visual_only=GLB,material

const ShipBlueprintScript: GDScript = preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript: GDScript = preload("res://scripts/procgen/ship_generator.gd")
const GeneratedShipLoaderScript: GDScript = preload("res://scripts/procgen/generated_ship_loader.gd")

const SEED: int = 17
const STAGED_OVERLAY_EVIDENCE: String = "res://artifacts/validation-previews/focused-nine/edge_map.json"
const STAGED_SCHEMA: String = "focused_nine_canonical_edge_map_v1"
const STAGED_CAPTURE_ID: String = "StagedFocusedNine"
const STRUCTURAL_FIELDS: Array[String] = [
	"placement_id",
	"edge_key",
	"kind",
	"state",
	"module_id",
	"position",
	"yaw_degrees",
	"room_ids",
]
const VISUAL_ONLY_FIELDS: Array[String] = ["GLB", "material", "scene_path"]

var live_loader: Node = null


func _initialize() -> void:
	var live_result: Dictionary = _generate_live_wrappers(SEED)
	if not bool(live_result.get("ok", false)):
		_fail(str(live_result.get("error", "live wrapper generation failed")))
		return
	live_loader = live_result.get("loader", null) as Node

	var staged_overlay: Dictionary = _load_json(STAGED_OVERLAY_EVIDENCE)
	if staged_overlay.is_empty():
		_fail("staged overlay evidence could not be loaded")
		return
	var staged_error := _validate_staged_overlay_evidence(staged_overlay, SEED)
	if not staged_error.is_empty():
		_fail(staged_error)
		return

	var live_plan: Dictionary = live_result["plan"]
	var live_inventory: Array = _placement_inventory(live_plan)
	var staged_inventory: Array = _placement_inventory(staged_overlay)
	var plan_error := _compare_inventories(live_inventory, staged_inventory, "structural plan")
	if not plan_error.is_empty():
		_fail("structural plan drift: " + plan_error)
		return

	var live_wrapper_inventory: Array = _live_wrapper_inventory(live_loader, live_plan)
	if live_wrapper_inventory.is_empty() and not live_inventory.is_empty():
		_fail("live wrappers emitted no structural metadata")
		return
	var staged_wrapper_inventory: Array = _staged_wrapper_inventory(staged_overlay)
	var wrapper_error := _compare_inventories(
		live_wrapper_inventory,
		staged_wrapper_inventory,
		"wrapper inventory",
	)
	if not wrapper_error.is_empty():
		_fail("structural plan drift: " + wrapper_error)
		return

	var placement_count := live_inventory.size()
	var wrapper_count := live_wrapper_inventory.size()
	print(
		"PROCGEN GOLDEN PARITY PASS seed=%d placements=%d wrappers=%d structural=true visual_only=GLB,material"
		% [SEED, placement_count, wrapper_count]
	)
	_cleanup_and_quit(0)


func _generate_live_wrappers(seed_value: int) -> Dictionary:
	var blueprint = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.SMALL,
		ShipBlueprintScript.Condition.WRECKED,
		seed_value,
	)
	blueprint.room_count_range = Vector2i(5, 8)
	var archetype := _derelict_archetype()
	# This is the exact deterministic input used by the staged overlay capture.
	archetype["guaranteed_roles"] = []
	archetype["template"] = "compact"
	var generator = ShipGeneratorScript.new()
	var generated: Node3D = generator.generate(blueprint, archetype)
	if generated == null:
		return {"ok": false, "error": "ShipGenerator returned null for live wrapper path"}
	var loader := generated as GeneratedShipLoaderScript
	if loader == null:
		generated.free()
		return {"ok": false, "error": "live wrapper path did not return GeneratedShipLoader"}
	var layout: Dictionary = loader.get_layout_copy()
	var plan_variant: Variant = layout.get("structural_plan", null)
	if not (plan_variant is Dictionary):
		loader.free()
		return {"ok": false, "error": "live wrapper path has no structural plan"}
	var plan: Dictionary = plan_variant
	return {"ok": true, "loader": loader, "plan": plan}


func _derelict_archetype() -> Dictionary:
	var path := "res://data/procgen/archetypes/derelict.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return (parsed as Dictionary).duplicate(true)
	return {
		"name": "Derelict",
		"type": "derelict",
		"role_weights": {"cargo": 4, "corridor": 3, "bridge": 3, "dock": 1},
		"guaranteed_roles": [],
		"max_duplicates": 3,
		"template": "compact",
	}


func _validate_staged_overlay_evidence(document: Dictionary, seed_value: int) -> String:
	if str(document.get("schema", "")) != STAGED_SCHEMA:
		return "staged overlay evidence schema is invalid"
	if str(document.get("capture_id", "")) != STAGED_CAPTURE_ID:
		return "staged overlay evidence capture_id is invalid"
	if int(document.get("seed", -1)) != seed_value:
		return "staged overlay evidence seed differs from live generation"
	for collection_name in ["placements", "wrapper_metadata"]:
		if not (document.get(collection_name, null) is Array):
			return "staged overlay evidence %s is not an Array" % collection_name
	var validation: Variant = document.get("validation", null)
	if not (validation is Dictionary):
		return "staged overlay evidence validation record is missing"
	for field in ["edge_keys_unique", "portal_endpoints_valid", "no_portal_wall_overlap", "canonical_validator"]:
		if (validation as Dictionary).get(field, false) != true:
			return "staged overlay evidence failed validation field %s" % field
	return ""


func _placement_inventory(source: Dictionary) -> Array:
	var records: Array = []
	var placements_variant: Variant = source.get("placements", null)
	if not (placements_variant is Array):
		return records
	for record_variant in placements_variant:
		if not (record_variant is Dictionary):
			return []
		records.append(_normalise_structural_record(record_variant as Dictionary))
	_sort_inventory(records)
	return records


func _normalise_structural_record(record: Dictionary) -> Dictionary:
	var room_ids: Array = []
	var room_ids_variant: Variant = record.get("room_ids", [])
	if room_ids_variant is Array:
		for room_id in room_ids_variant:
			room_ids.append(str(room_id))
	return {
		"placement_id": str(record.get("placement_id", "")),
		"edge_key": str(record.get("edge_key", "")),
		"kind": str(record.get("kind", "")),
		"state": str(record.get("state", record.get("kind", ""))),
		"module_id": str(record.get("module_id", "")),
		"position": _normalise_position(record.get("position", null)),
		"yaw_degrees": float(record.get("yaw_degrees", 0.0)),
		"room_ids": room_ids,
	}


func _normalise_position(raw: Variant) -> Array:
	if raw is Vector3:
		var vector: Vector3 = raw
		return [vector.x, vector.y, vector.z]
	if raw is Array:
		var values: Array = raw
		if values.size() < 3:
			return []
		return [float(values[0]), float(values[1]), float(values[2])]
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
					return []
			return [
				float(parts[0].strip_edges()),
				float(parts[1].strip_edges()),
				float(parts[2].strip_edges()),
			]
	return []


func _live_wrapper_inventory(loader: Node, plan: Dictionary) -> Array:
	var records: Array = []
	var structural_root := loader.get_node_or_null("StructuralRoot")
	if structural_root == null:
		return records
	var placements_by_id: Dictionary = {}
	for placement_variant in plan.get("placements", []):
		if placement_variant is Dictionary:
			var placement: Dictionary = placement_variant
			placements_by_id[str(placement.get("placement_id", ""))] = placement
	_collect_live_wrappers(structural_root, placements_by_id, records)
	_sort_inventory(records)
	return records


func _collect_live_wrappers(node: Node, placements_by_id: Dictionary, records: Array) -> void:
	if node.has_meta("structural_placement_id"):
		var placement_id := str(node.get_meta("structural_placement_id", ""))
		var placement_variant: Variant = placements_by_id.get(placement_id, null)
		if not (placement_variant is Dictionary):
			return
		var placement: Dictionary = placement_variant
		var expected_position: Array = _normalise_position(placement.get("position", null))
		var actual_position: Vector3 = (node as Node3D).position
		if expected_position.size() != 3 or not actual_position.is_equal_approx(
			Vector3(expected_position[0], expected_position[1], expected_position[2])
		):
			return
		if not is_equal_approx(
			float((node as Node3D).rotation_degrees.y),
			float(placement.get("yaw_degrees", 0.0)),
		):
			return
		if str(node.get_meta("module_kind", "")) != str(placement.get("module_id", "")):
			return
		var record := _normalise_structural_record(placement)
		if str(node.get_meta("structural_edge_key", "")) != str(record["edge_key"]):
			return
		if str(node.get_meta("structural_kind", "")) != str(record["kind"]):
			return
		if not _string_array_equal(node.get_meta("structural_room_ids", []), record["room_ids"]):
			return
		records.append(record)
	for child in node.get_children():
		_collect_live_wrappers(child, placements_by_id, records)


func _staged_wrapper_inventory(document: Dictionary) -> Array:
	var records: Array = []
	var placements_by_id: Dictionary = {}
	for placement_variant in document.get("placements", []):
		if placement_variant is Dictionary:
			var placement: Dictionary = placement_variant
			placements_by_id[str(placement.get("placement_id", ""))] = placement
	for wrapper_variant in document.get("wrapper_metadata", []):
		if not (wrapper_variant is Dictionary):
			return []
		var wrapper: Dictionary = wrapper_variant
		var placement_id := str(wrapper.get("placement_id", ""))
		var placement_variant: Variant = placements_by_id.get(placement_id, null)
		if not (placement_variant is Dictionary):
			return []
		var placement: Dictionary = placement_variant
		if str(wrapper.get("edge_key", "")) != str(placement.get("edge_key", "")):
			return []
		if str(wrapper.get("kind", "")) != str(placement.get("kind", "")):
			return []
		if not _string_array_equal(wrapper.get("room_ids", []), _normalise_structural_record(placement)["room_ids"]):
			return []
		# scene_path/GLB/material are visual-only and intentionally ignored here.
		records.append(_normalise_structural_record(placement))
	_sort_inventory(records)
	return records


func _compare_inventories(expected: Array, actual: Array, label: String) -> String:
	if expected.size() != actual.size():
		return "%s count changed expected=%d actual=%d" % [label, expected.size(), actual.size()]
	for index in expected.size():
		var left: Dictionary = expected[index]
		var right: Dictionary = actual[index]
		for field in STRUCTURAL_FIELDS:
			if field == "position":
				if not _position_equal(left.get(field, []), right.get(field, [])):
					return "%s %s position changed at index=%d" % [label, str(left.get("placement_id", "")), index]
				continue
			if left.get(field) != right.get(field):
				return "%s %s field=%s expected=%s actual=%s" % [
					label,
					str(left.get("placement_id", "")),
					field,
					str(left.get(field)),
					str(right.get(field)),
				]
	return ""


func _sort_inventory(records: Array) -> void:
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key := "%s|%s" % [str(left.get("placement_id", "")), str(left.get("edge_key", ""))]
		var right_key := "%s|%s" % [str(right.get("placement_id", "")), str(right.get("edge_key", ""))]
		return left_key < right_key
	)


func _position_equal(left: Variant, right: Variant) -> bool:
	if not (left is Array) or not (right is Array):
		return false
	var left_values: Array = left
	var right_values: Array = right
	if left_values.size() < 3 or right_values.size() < 3:
		return false
	for index in 3:
		if not is_equal_approx(float(left_values[index]), float(right_values[index])):
			return false
	return true


func _string_array_equal(left: Variant, right: Variant) -> bool:
	if not (left is Array) or not (right is Array):
		return false
	var left_values: Array = left
	var right_values: Array = right
	if left_values.size() != right_values.size():
		return false
	for index in left_values.size():
		if str(left_values[index]) != str(right_values[index]):
			return false
	return true


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _fail(reason: String) -> void:
	print("PROCGEN GOLDEN PARITY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)


func _cleanup_and_quit(exit_code: int) -> void:
	if live_loader != null and is_instance_valid(live_loader):
		live_loader.free()
	live_loader = null
	quit(exit_code)
