extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const CanonicalJsonScript := preload("res://scripts/procgen/procgen_canonical_json.gd")
const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")

func _init() -> void:
	var failures: Array[String] = []
	var count: int = 0
	var generator: Object = ClassDB.instantiate("DerelictGenerator") as Object
	if generator == null:
		print("TASK5 CONSUMER FAIL adapter_missing"); quit(1); return
	var build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
	var runtime: Dictionary = JSON.parse_string(str(generator.generator_manifest()))
	var caps: Dictionary = JSON.parse_string(str(generator.capabilities()))
	if ValidatorScript.new().validate(build, generator) != ValidatorScript.OK:
		print("TASK5 CONSUMER FAIL build_manifest"); quit(1); return
	var consumer: RefCounted = ConsumerScript.new()
	var request: Dictionary = consumer.build_request(42, 0, 1, runtime)
	var raw: String = str(generator.generate_bundle(JSON.stringify(request)))
	var baseline: Dictionary = consumer.consume(raw, request, build, runtime, caps)
	count += 1
	if baseline.is_empty(): failures.append("baseline:%s" % consumer.last_error)
	count += 1; _expect(consumer.consume("not-json", request, build, runtime, caps).is_empty() and consumer.last_error == "malformed_bundle_json", failures, "malformed_json")
	var original: Dictionary = JSON.parse_string(raw)
	var cases: Array = [["lifecycle_schema", "schema_version", "wrong", "lifecycle_schema"], ["lifecycle_status", "status", "failed", "lifecycle_not_completed"], ["missing_bundle", "bundle", null, "missing_bundle"], ["bundle_schema", "bundle.schema_version", "procgen-bundle-1", "bundle_schema"], ["hash", "bundle.semantic_hash", "0".repeat(64), "semantic_hash"], ["world_schema", "bundle.world_ir.schema_version", "world-ir-1", "world_ir_schema"], ["world_identity", "bundle.world_ir.site_id", "wrong-site", "world_identity"], ["ship_seed_identity", "bundle.site_ir.ship.seed", 42, "ship_identity"], ["presentation_identity", "bundle.presentation_ir.locale", "fr-FR", "presentation_identity"], ["pipeline_count", "bundle.metrics.pipeline_executions", 2, "pipeline_count"], ["trace_schema", "bundle.trace.schema_version", "wrong", "diagnostic_schema"]]
	for item in cases:
		var mutated: Dictionary = original.duplicate(true)
		_set_path(mutated, str(item[1]), item[2])
		count += 1
		var result: Dictionary = consumer.consume(JSON.stringify(mutated), request, build, runtime, caps)
		_expect(result.is_empty() and consumer.last_error == str(item[3]), failures, str(item[0]) + ":" + consumer.last_error)
	var contexts: Array = [["build_extra", "build", "extra", true, true, "build_manifest_shape"], ["build_schema", "build", "manifest_schema", "wrong", true, "build_manifest_schema"], ["build_source", "build", "rust_source_commit", "0".repeat(40), true, "manifest_source"], ["build_version", "build", "generator_version", 9, true, "build_manifest_version"], ["build_content", "build", "content_manifest_hash", "0".repeat(64), true, "build_manifest_content"], ["build_target", "build", "target", "linux", true, "manifest_target"], ["build_exports", "build", "export_schemas", {}, true, "manifest_export_schemas"], ["runtime_extra", "runtime", "extra", true, true, "runtime_manifest_shape"], ["runtime_schema", "runtime", "schema_version", "wrong", true, "runtime_manifest_schema"], ["runtime_source", "runtime", "rust_source_commit", "0".repeat(40), true, "manifest_source"], ["runtime_dirty", "runtime", "dirty_development", true, true, "dirty_runtime"], ["runtime_adapter", "runtime", "adapter_schemas", {}, true, "manifest_adapter_schemas"], ["caps_extra", "caps", "extra", true, true, "capability_shape"], ["caps_schema", "caps", "schema_version", "wrong", true, "capability_schema"], ["caps_adapter", "caps", "adapter_kind", "web", true, "capability_adapter"], ["caps_worker", "caps", "worker_count", 0, true, "capability_worker_count"], ["caps_sync", "caps", "supports_sync", false, true, "capability_supports_sync"], ["caps_events", "caps", "max_events", 33, true, "capability_max_events"], ["caps_domains", "caps", "supported_domains", ["site"], true, "capability_domains"], ["caps_schemas", "caps", "schemas", {}, true, "capability_schemas"]]
	for item in contexts:
		var build_case: Dictionary = build.duplicate(true); var runtime_case: Dictionary = runtime.duplicate(true); var caps_case: Dictionary = caps.duplicate(true)
		var target: Dictionary = build_case if str(item[1]) == "build" else (runtime_case if str(item[1]) == "runtime" else caps_case)
		target[str(item[2])] = item[3]
		count += 1
		var result: Dictionary = consumer.consume(raw, request, build_case, runtime_case, caps_case)
		_expect(result.is_empty() and consumer.last_error == str(item[5]), failures, str(item[0]) + ":" + consumer.last_error)
	var request_cases: Array = [
		["request_extra", "extra", true, "request_shape"],
		["request_schema", "schema_version", "wrong", "request_schema"],
		["request_seed_bounds", "world_seed", 9007199254740992, "request_bounds"],
		["request_coordinate_bounds", "site.x", 9007199254740992, "request_bounds"],
		["request_coordinate_v1", "site.y", 1, "request_coordinates"],
		["request_player_signals", "player_model.signals", [1], "request_player_model"],
		["request_domains_order", "requested_domains", ["site", "world", "gameplay", "presentation"], "request_domains"],
		["request_presentation_seed", "presentation.seed", 43, "request_presentation"],
	]
	for item in request_cases:
		var request_case: Dictionary = request.duplicate(true)
		_set_path(request_case, str(item[1]), item[2])
		count += 1
		var result: Dictionary = consumer.consume(raw, request_case, build, runtime, caps)
		_expect(result.is_empty() and consumer.last_error == str(item[3]), failures, str(item[0]) + ":" + consumer.last_error)
	var nested_cases: Array = _nested_bundle_cases(original)
	for item in nested_cases:
		count += 1
		var nested_raw: String = _rehash_lifecycle(item[1] as Dictionary)
		var result: Dictionary = consumer.consume(nested_raw, request, build, runtime, caps)
		_expect(result.is_empty() and consumer.last_error == str(item[2]), failures, str(item[0]) + ":" + consumer.last_error)
	count += 1; _expect(consumer._same_json(42, 42.0), failures, "safe_mixed_numeric_identity")
	count += 1; _expect(not consumer._same_json(9007199254740992, 9007199254740993), failures, "unsafe_integer_identity")
	count += 1; _expect(consumer.build_request(9007199254740992, 0, 1, runtime).is_empty() and consumer.last_error == "json_unsafe_seed", failures, "unsafe_seed")
	count += 1; _expect(consumer.build_request(-1, 0, 1, runtime).is_empty() and consumer.last_error == "json_unsafe_seed", failures, "negative_seed")
	count += 1; _expect(consumer.build_request(42, 99, 1, runtime).is_empty() and consumer.last_error == "unsupported_ship_parameters", failures, "unsupported_size")
	count += 1; _expect(consumer.build_request(42, 0, 99, runtime).is_empty() and consumer.last_error == "unsupported_ship_parameters", failures, "unsupported_condition")
	if not failures.is_empty():
		for failure in failures: print("TASK5 CONSUMER FAIL:%s" % failure)
		quit(1); return
	print("TASK5 CONSUMER PASS live=true cases=%d baseline=true hash=true lifecycle=true identity=true build_context=true runtime_context=true caps_context=true request_bounds=true" % count)
	quit(0)

func _set_path(root: Dictionary, path: String, value: Variant) -> void:
	var parts: PackedStringArray = path.split(".")
	var current: Dictionary = root
	for index in range(parts.size() - 1):
		if not current.has(parts[index]) or not current[parts[index]] is Dictionary: return
		current = current[parts[index]]
	current[parts[-1]] = value

func _nested_bundle_cases(original: Dictionary) -> Array:
	var cases: Array = []
	var occupancy_case: Dictionary = original.duplicate(true)
	var occupancy: Dictionary = occupancy_case.bundle.site_ir.ship.plan.occupancy
	occupancy[occupancy.keys()[0]] = "not-an-occupancy-record"
	cases.append(["nested_occupancy", occupancy_case, "ship_plan_shape"])
	var edge_case: Dictionary = original.duplicate(true)
	var edges: Dictionary = edge_case.bundle.site_ir.ship.plan.edges
	edges[edges.keys()[0]] = "not-an-edge-record"
	cases.append(["nested_edge", edge_case, "ship_plan_shape"])
	var room_case: Dictionary = original.duplicate(true)
	(room_case.bundle.site_ir.ship.topology.rooms as Array)[0] = "not-a-room"
	cases.append(["nested_room", room_case, "ship_topology_shape"])
	var room_cell_case: Dictionary = original.duplicate(true)
	(((room_cell_case.bundle.site_ir.ship.topology.rooms as Array)[0] as Dictionary).cells as Array)[0] = "not-a-cell"
	cases.append(["nested_room_cell", room_cell_case, "ship_topology_shape"])
	var portal_case: Dictionary = original.duplicate(true)
	var portals: Array = portal_case.bundle.site_ir.ship.topology.portals
	if portals.is_empty(): portals.append("not-a-portal")
	else: portals[0] = "not-a-portal"
	cases.append(["nested_portal", portal_case, "ship_topology_shape"])
	var vertical_case: Dictionary = original.duplicate(true)
	var verticals: Array = vertical_case.bundle.site_ir.ship.topology.verticals
	verticals.append("not-a-vertical")
	cases.append(["nested_vertical", vertical_case, "ship_topology_shape"])
	var path_case: Dictionary = original.duplicate(true)
	(path_case.bundle.site_ir.ship.critical_path as Array)[0] = "not-a-room-id"
	cases.append(["nested_critical_path", path_case, "ship_path_shape"])
	var placement_case: Dictionary = original.duplicate(true)
	var placements: Array = placement_case.bundle.site_ir.ship.plan.placements
	if placements.is_empty(): placements.append("not-a-placement")
	else: placements[0] = "not-a-placement"
	cases.append(["nested_placement", placement_case, "ship_plan_shape"])
	var floor_case: Dictionary = original.duplicate(true)
	(floor_case.bundle.site_ir.ship.plan.floor_placements as Array)[0] = "not-a-floor-placement"
	cases.append(["nested_floor", floor_case, "ship_plan_shape"])
	var socket_case: Dictionary = original.duplicate(true)
	var bindings: Array = socket_case.bundle.site_ir.ship.plan.socket_bindings
	if bindings.is_empty(): bindings.append({"kind": "incomplete"})
	else: bindings[0] = {"kind": "incomplete"}
	cases.append(["nested_socket_binding", socket_case, "ship_plan_shape"])
	var errors_case: Dictionary = original.duplicate(true)
	(errors_case.bundle.site_ir.ship.plan.errors as Array).append(7)
	cases.append(["nested_plan_error", errors_case, "ship_plan_shape"])
	var gameplay_case: Dictionary = original.duplicate(true)
	(gameplay_case.bundle.gameplay_ir.legacy_slice.objectives as Array)[0] = "not-an-objective"
	cases.append(["nested_gameplay", gameplay_case, "gameplay_slice_shape"])
	return cases

func _rehash_lifecycle(lifecycle: Dictionary) -> String:
	lifecycle.bundle.semantic_hash = "0".repeat(64)
	var raw: String = JSON.stringify(lifecycle)
	var semantic_hash: String = CanonicalJsonScript.new().semantic_hash(raw)
	lifecycle.bundle.semantic_hash = semantic_hash
	return JSON.stringify(lifecycle)

func _expect(ok: bool, failures: Array[String], label: String) -> void:
	if not ok: failures.append(label)
