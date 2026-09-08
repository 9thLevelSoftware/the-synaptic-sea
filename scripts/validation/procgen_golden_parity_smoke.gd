extends SceneTree

## Task9 structural parity evidence.
##
## The staged edge_map.json is the committed result of the disposable staged
## overlay capture. This smoke regenerates the same seed through the live
## ShipGenerator/GeneratedShipLoader wrappers, then compares only the
## canonical structural inventory. GLB/material and scene-path differences are
## visual-only and intentionally excluded from the structural comparison.
## Marker: PROCGEN CURRENT TOPOLOGY PARITY PASS seed=17 placements=<n> wrappers=<n> portals=<n> structural=true visual_only=GLB,material

const ShipBlueprintScript: GDScript = preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript: GDScript = preload("res://scripts/procgen/ship_generator.gd")
const GeneratedShipLoaderScript: GDScript = preload("res://scripts/procgen/generated_ship_loader.gd")

const SEED: int = 17
const STAGED_OVERLAY_EVIDENCE: String = "res://data/procgen/golden/compact_seed17_halfspan/edge_map.json"
const PROVENANCE_EVIDENCE: String = "res://data/procgen/golden/compact_seed17_halfspan/provenance.json"
const STAGED_SCHEMA: String = "compact_seed17_halfspan_v1"
const STAGED_CAPTURE_ID: String = "CompactSeed17Halfspan"
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
var evidence_path: String = STAGED_OVERLAY_EVIDENCE


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 1:
		_fail("expected zero or one fixture path")
		return
	if args.size() == 1:
		evidence_path = str(args[0])
	var live_result: Dictionary = _generate_live_wrappers(SEED)
	if not bool(live_result.get("ok", false)):
		_fail(str(live_result.get("error", "live wrapper generation failed")))
		return
	live_loader = live_result.get("loader", null) as Node

	var staged_overlay: Dictionary = _load_json(evidence_path)
	if staged_overlay.is_empty():
		_fail("staged overlay evidence could not be loaded")
		return
	var staged_error := _validate_staged_overlay_evidence(staged_overlay, SEED)
	if not staged_error.is_empty():
		_fail(staged_error)
		return
	var provenance_error := _validate_provenance()
	if not provenance_error.is_empty():
		_fail(provenance_error)
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
	var wrapper_probe_error := _wrapper_field_mutation_probes(staged_overlay, staged_wrapper_inventory)
	if not wrapper_probe_error.is_empty():
		_fail(wrapper_probe_error)
		return

	var topology_error := _compare_canonical_topology(live_plan, staged_overlay)
	if not topology_error.is_empty():
		_fail("canonical topology drift: " + topology_error)
		return
	var placement_count := live_inventory.size()
	var wrapper_count := live_wrapper_inventory.size()
	var portal_count := _portal_count(live_plan)
	print(
		"PROCGEN CURRENT TOPOLOGY PARITY PASS seed=%d placements=%d wrappers=%d portals=%d structural=true visual_only=GLB,material"
		% [SEED, placement_count, wrapper_count, portal_count]
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
	for collection_name in ["placements", "wrapper_metadata"]:
		if not (document.get(collection_name, null) is Array):
			return "staged overlay evidence %s is not an Array" % collection_name
	for collection_name in ["occupancy", "edges"]:
		if not (document.get(collection_name, null) is Dictionary):
			return "staged overlay evidence %s is not a Dictionary" % collection_name
	for placement_variant in document.get("placements", []) as Array:
		if not (placement_variant is Dictionary) or not _valid_structural_record(placement_variant as Dictionary):
			return "staged overlay evidence placement record is malformed"
	var validation: Variant = document.get("validation", null)
	if not (validation is Dictionary):
		return "staged overlay evidence validation record is missing"
	for field in ["placement_ids_unique", "solid_half_span_coverage", "portal_endpoints_valid", "no_portal_wall_overlap", "canonical_validator", "negative_duplicate_placement_probe", "negative_portal_wall_probe", "negative_endpoint_probe", "real_wrapper_checks"]:
		if (validation as Dictionary).get(field, false) != true:
			return "staged overlay evidence failed validation field %s" % field
	var half_span_error := _validate_fixture_half_span_coverage(document)
	if not half_span_error.is_empty():
		return half_span_error
	if not _is_integral_json_number(document.get("seed", null)) or not _json_integer_equals(document["seed"], seed_value):
		return "staged overlay evidence seed differs from live generation"
	if str(document.get("size", "")) != "SMALL" or str(document.get("condition", "")) != "WRECKED":
		return "staged overlay evidence size or condition is invalid"
	var range_value: Variant = document.get("room_count_range", null)
	if not (range_value is Array) or (range_value as Array).size() != 2 or not _is_integral_json_number((range_value as Array)[0]) or not _is_integral_json_number((range_value as Array)[1]) or not _json_integer_equals((range_value as Array)[0], 5) or not _json_integer_equals((range_value as Array)[1], 8):
		return "staged overlay evidence room_count_range is invalid"
	var archetype: Variant = document.get("archetype", null)
	if not (archetype is Dictionary) or str((archetype as Dictionary).get("template", "")) != "compact" or not ((archetype as Dictionary).get("guaranteed_roles", null) is Array) or not ((archetype as Dictionary).get("guaranteed_roles", []) as Array).is_empty():
		return "staged overlay evidence archetype is invalid"
	if not _is_integral_json_number(document.get("rooms", null)) or not _json_integer_equals(document["rooms"], _occupancy_room_count(document.get("occupancy", {}) as Dictionary)):
		return "staged overlay evidence rooms is inconsistent"
	var placement_count: Variant = (validation as Dictionary).get("placement_count", null)
	var wrapper_count: Variant = (validation as Dictionary).get("wrapper_count", null)
	if not _is_integral_json_number(placement_count) or not _is_integral_json_number(wrapper_count) or not _json_integer_equals(placement_count, (document.get("placements", []) as Array).size()) or not _json_integer_equals(wrapper_count, (document.get("wrapper_metadata", []) as Array).size()):
		return "staged overlay evidence count metadata is inconsistent"
	return ""


func _validate_fixture_half_span_coverage(document: Dictionary) -> String:
	var edges: Dictionary = document.get("edges", {}) as Dictionary
	var placement_ids: Dictionary = {}
	var span_owners: Dictionary = {}
	for placement_variant in document.get("placements", []) as Array:
		if not placement_variant is Dictionary:
			return "half-span fixture placement is malformed"
		var placement: Dictionary = placement_variant
		var placement_id: String = str(placement.get("placement_id", ""))
		if placement_id.is_empty() or placement_ids.has(placement_id):
			return "half-span fixture has duplicate physical placement_id=%s" % placement_id
		placement_ids[placement_id] = true
		var covered_variant: Variant = placement.get("covered_half_spans", null)
		if not covered_variant is Array:
			return "half-span fixture placement has no coverage=%s" % placement_id
		for span_variant in covered_variant as Array:
			var span_id: String = str(span_variant)
			var edge_key: String = span_id.get_slice("@", 0)
			if span_id.is_empty() or span_owners.has(span_id) or not edges.has(edge_key):
				return "half-span fixture has invalid or duplicate span=%s" % span_id
			var edge: Dictionary = edges[edge_key] as Dictionary
			if str(edge.get("kind", "")) != "SOLID" \
					or not (edge.get("half_span_ids", []) as Array).has(span_id):
				return "half-span fixture span is not canonical=%s" % span_id
			span_owners[span_id] = placement_id
	for edge_key_variant in edges.keys():
		var edge_key: String = str(edge_key_variant)
		var edge: Dictionary = edges[edge_key_variant] as Dictionary
		if str(edge.get("kind", "")) != "SOLID":
			continue
		var spans: Variant = edge.get("half_span_ids", null)
		if not spans is Array or (spans as Array).size() != 2 \
				or str((spans as Array)[0]) != "%s@a" % edge_key \
				or str((spans as Array)[1]) != "%s@b" % edge_key:
			return "half-span fixture SOLID edge has malformed @a/@b authority=%s" % edge_key
		for span_variant in spans as Array:
			if not span_owners.has(str(span_variant)):
				return "half-span fixture SOLID edge is uncovered=%s" % str(span_variant)
	return ""


func _validate_provenance() -> String:
	var provenance: Dictionary = _load_json(PROVENANCE_EVIDENCE)
	if provenance.is_empty():
		return "half-span fixture provenance could not be loaded"
	if str(provenance.get("schema", "")) != "compact_seed17_halfspan_provenance_v1" \
			or str(provenance.get("fixture", "")) != "edge_map.json":
		return "half-span fixture provenance schema is invalid"
	if str(provenance.get("fixture_sha256", "")).to_upper() != _sha256_file(STAGED_OVERLAY_EVIDENCE):
		return "half-span fixture provenance hash differs from edge_map.json"
	var input: Variant = provenance.get("generator_input", null)
	if not input is Dictionary or int((input as Dictionary).get("seed", -1)) != SEED \
			or str((input as Dictionary).get("size", "")) != "SMALL" \
			or str((input as Dictionary).get("condition", "")) != "WRECKED":
		return "half-span fixture provenance generator input is invalid"
	var source_hashes: Variant = provenance.get("source_hashes", null)
	if not source_hashes is Dictionary or (source_hashes as Dictionary).is_empty():
		return "half-span fixture provenance source hashes are missing"
	for source_path_variant in (source_hashes as Dictionary).keys():
		var source_path: String = str(source_path_variant)
		var expected_hash: String = str((source_hashes as Dictionary)[source_path_variant]).to_upper()
		if source_path.is_empty() or expected_hash.length() != 64:
			return "half-span fixture provenance source hash is malformed path=%s" % source_path
	return ""


func _sha256_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode().to_upper()



func _is_json_number(value: Variant) -> bool:
	if not (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT):
		return false
	return is_finite(float(value))


func _is_integral_json_number(value: Variant) -> bool:
	return _is_json_number(value) and float(value) == floor(float(value))


func _json_integer_equals(value: Variant, expected: int) -> bool:
	return _is_integral_json_number(value) and float(value) == float(expected)


func _occupancy_room_count(occupancy: Dictionary) -> int:
	var rooms: Dictionary = {}
	for record_variant in occupancy.values():
		if record_variant is Dictionary:
			var room_id: String = str((record_variant as Dictionary).get("room_id", ""))
			if not room_id.is_empty():
				rooms[room_id] = true
	return rooms.size()


func _compare_canonical_topology(live_plan: Dictionary, fixture: Dictionary) -> String:
	for collection_name in ["occupancy", "edges"]:
		var live_value: Variant = live_plan.get(collection_name, null)
		var fixture_value: Variant = fixture.get(collection_name, null)
		if not (live_value is Dictionary) or not (fixture_value is Dictionary):
			return "%s is missing" % collection_name
		if _canonical_json_value(live_value) != _canonical_json_value(fixture_value):
			return "%s changed" % collection_name
	return ""


func _canonical_json_value(value: Variant) -> Variant:
	## Capture persists grid/vector values as JSON arrays. Normalize only runtime
	## representations at this boundary; every key and array element remains in
	## the comparison, so topology drift cannot be hidden by serialization.
	if value is Vector2i:
		var vector2i: Vector2i = value
		return [float(vector2i.x), float(vector2i.y)]
	if value is Vector3:
		var vector3: Vector3 = value
		return [float(vector3.x), float(vector3.y), float(vector3.z)]
	if value is Dictionary:
		var canonical: Dictionary = {}
		for key_variant in (value as Dictionary).keys():
			canonical[str(key_variant)] = _canonical_json_value((value as Dictionary)[key_variant])
		return canonical
	if value is Array:
		var canonical_array: Array = []
		for item in value as Array:
			canonical_array.append(_canonical_json_value(item))
		return canonical_array
	# JSON.parse_string represents every numeric scalar as float. Convert native
	# integer fields to that same lossless representation so Dictionary equality
	# compares values rather than their serialization types. Do not round, reorder,
	# or discard any topology field.
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return value


func _portal_count(plan: Dictionary) -> int:
	var count: int = 0
	var edges: Dictionary = plan.get("edges", {})
	for edge_variant in edges.values():
		if edge_variant is Dictionary and bool((edge_variant as Dictionary).get("portal", false)):
			count += 1
	return count


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


func _valid_structural_record(record: Dictionary) -> bool:
	for field in ["placement_id", "edge_key", "kind", "state", "module_id"]:
		if not record.has(field) or typeof(record[field]) != TYPE_STRING:
			return false
	if not record.has("position") or not (record["position"] is Array) or (record["position"] as Array).size() != 3:
		return false
	for coordinate in record["position"] as Array:
		if not _is_json_number(coordinate):
			return false
	if not record.has("yaw_degrees") or not _is_json_number(record["yaw_degrees"]):
		return false
	if not record.has("room_ids") or not (record["room_ids"] is Array):
		return false
	for room_id in record["room_ids"] as Array:
		if typeof(room_id) != TYPE_STRING:
			return false
	return true


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
		if placement_variant is Dictionary and _valid_structural_record(placement_variant as Dictionary):
			var placement: Dictionary = placement_variant
			placements_by_id[str(placement.get("placement_id", ""))] = placement
		else:
			return []
	for wrapper_variant in document.get("wrapper_metadata", []):
		if not (wrapper_variant is Dictionary):
			return []
		var wrapper: Dictionary = wrapper_variant
		if not _valid_structural_record(wrapper):
			return []
		var placement_id := str(wrapper.get("placement_id", ""))
		var placement_variant: Variant = placements_by_id.get(placement_id, null)
		if not (placement_variant is Dictionary) or not _valid_structural_record(placement_variant as Dictionary):
			return []
		var placement: Dictionary = placement_variant
		if str(wrapper.get("edge_key", "")) != str(placement.get("edge_key", "")):
			return []
		if str(wrapper.get("kind", "")) != str(placement.get("kind", "")):
			return []
		if not _string_array_equal(wrapper.get("room_ids", []), _normalise_structural_record(placement)["room_ids"]):
			return []
		var wrapper_record := _normalise_structural_record(wrapper)
		# Capture evidence is authoritative for wrapper fields. Only visual-only
		# fields are intentionally excluded from this comparison.
		records.append(wrapper_record)
	_sort_inventory(records)
	return records


func _wrapper_field_mutation_probes(document: Dictionary, baseline: Array) -> String:
	var fields: Array[String] = ["module_id", "position", "yaw_degrees", "state"]
	for field in fields:
		var mutant: Dictionary = document.duplicate(true)
		var wrappers: Array = mutant.get("wrapper_metadata", [])
		if wrappers.is_empty() or not (wrappers[0] is Dictionary):
			return "wrapper mutation probe fixture is malformed"
		var wrapper: Dictionary = wrappers[0]
		match field:
			"module_id": wrapper[field] = "mutated_module"
			"position": wrapper[field] = [999.0, 999.0, 999.0]
			"yaw_degrees": wrapper[field] = float(wrapper.get(field, 0.0)) + 1.0
			"state": wrapper[field] = "MUTATED"
		var mutated_inventory := _staged_wrapper_inventory(mutant)
		if _compare_inventories(baseline, mutated_inventory, "wrapper %s mutation" % field).is_empty():
			return "wrapper mutation was not rejected field=%s" % field
	return ""

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
	print("PROCGEN CURRENT TOPOLOGY PARITY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)


func _cleanup_and_quit(exit_code: int) -> void:
	if live_loader != null and is_instance_valid(live_loader):
		live_loader.free()
	live_loader = null
	quit(exit_code)
