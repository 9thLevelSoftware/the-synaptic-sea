extends RefCounted
class_name ProcgenBundleConsumer

const CanonicalJsonScript := preload("res://scripts/procgen/procgen_canonical_json.gd")

const GENERATOR_VERSION: int = 2
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991
const CONTENT_HASH: String = "e45770cf36ca296644b291a1c12d750281c8fcd3e520430b3ae2995d03ab14d2"
const DOMAINS: Array[String] = ["world", "site", "gameplay", "presentation"]
const SUPPORTED_ARCHETYPES: Array[String] = ["shuttle", "corvette", "freighter", "frigate"]
const SUPPORTED_DIFFICULTIES: Array[String] = ["standard", "hardened", "deep_dive"]
const RNG_CHANNELS: Array[String] = [
	"meta", "hull", "template", "topology", "residual_fill", "door", "furnish", "story",
	"intact", "breach", "scorch", "seal", "bodies", "fracture", "debris", "loot",
]
const EXPORT_SCHEMAS: Dictionary = {
	"procgen_request": "procgen-request-1", "procgen_bundle": "procgen-bundle-1",
	"world_ir": "world-ir-1", "site_ir": "site-ir-1", "gameplay_ir": "gameplay-ir-1",
	"presentation_ir": "presentation-ir-1", "generation_trace": "generation-trace-1",
	"adaptive_proposal": "adaptive-proposal-1",
}
const ADAPTER_SCHEMAS: Dictionary = {
	"lifecycle_result": "procgen-lifecycle-result-1",
	"capabilities": "procgen-capabilities-1",
	"generator_manifest": "procgen-generator-manifest-1",
}
const SHIP_FIELDS: Array[String] = [
	"generator_version", "seed", "archetype_id", "template_id", "intactness", "cause_of_loss",
	"topology", "plan", "entry_room", "goal_room", "critical_path", "decks", "room_graph",
	"entities", "damage_events", "fractured", "fragments",
]

var last_error: String = ""

func build_request(
		seed_value: int,
		size: int,
		condition: int,
		runtime_manifest: Dictionary = {},
		difficulty_value: String = "standard",
		archetype_override: String = "") -> Dictionary:
	last_error = ""
	if seed_value < 0 or seed_value > MAX_SAFE_JSON_INTEGER:
		return _fail("json_unsafe_seed")
	var archetypes: Dictionary = {0: "shuttle", 1: "corvette", 2: "freighter"}
	var intactness: Dictionary = {0: 9500, 1: 6000, 2: 2000}
	if not archetypes.has(size) or not intactness.has(condition):
		return _fail("unsupported_ship_parameters")
	if not SUPPORTED_DIFFICULTIES.has(difficulty_value):
		return _fail("unsupported_difficulty")
	var archetype_id: String = str(archetypes[size]) if archetype_override.is_empty() else archetype_override
	if not SUPPORTED_ARCHETYPES.has(archetype_id):
		return _fail("unsupported_archetype")
	var generator_version: int = GENERATOR_VERSION
	var content_hash: String = CONTENT_HASH
	if not runtime_manifest.is_empty():
		if str(runtime_manifest.get("schema_version", "")) != ADAPTER_SCHEMAS.generator_manifest \
				or not _is_json_integer(runtime_manifest.get("generator_version", null)) \
				or int(runtime_manifest.get("generator_version", -1)) != GENERATOR_VERSION \
				or not _is_sha256(str(runtime_manifest.get("content_manifest_hash", ""))):
			return _fail("runtime_request_identity")
		generator_version = int(runtime_manifest.generator_version)
		content_hash = str(runtime_manifest.content_manifest_hash)
	var site_id: String = "site_%d_%d_%d" % [seed_value, size, condition]
	return {
		"schema_version": EXPORT_SCHEMAS.procgen_request, "world_seed": seed_value,
		"site": {"site_id": site_id, "x": 0, "y": 0, "archetype_id": archetype_id,
			"kit_id": "ship_structural_v0", "intactness_override_bp": int(intactness[condition]),
			"cause_of_loss": null, "loot_richness_bp": 5000},
		"difficulty_id": difficulty_value,
		"player_model": {"schema_version": "player-model-1", "signals": []},
		"requested_domains": DOMAINS.duplicate(), "generator_version": generator_version,
		"content_manifest_hash": content_hash,
		"presentation": {"seed": seed_value, "locale": "en-US"},
	}

func consume(
		result_json: String,
		request: Dictionary,
		build_manifest: Dictionary = {},
		runtime_manifest: Dictionary = {},
		capabilities: Dictionary = {}) -> Dictionary:
	last_error = ""
	if request.is_empty() or result_json.is_empty(): return _fail("missing_bundle")
	if not _validate_context(request, build_manifest, runtime_manifest, capabilities): return {}
	var parser := JSON.new()
	if parser.parse(result_json) != OK or not parser.data is Dictionary: return _fail("malformed_bundle_json")
	var lifecycle: Dictionary = parser.data
	if not _has_exact_keys(lifecycle, ["schema_version", "status", "request_id", "bundle", "failure", "events"]): return _fail("lifecycle_shape")
	if str(lifecycle.get("schema_version", "")) != ADAPTER_SCHEMAS.lifecycle_result: return _fail("lifecycle_schema")
	if str(lifecycle.get("status", "")) != "completed": return _fail("lifecycle_not_completed")
	if lifecycle.get("request_id", null) != null: return _fail("lifecycle_request_id")
	if lifecycle.get("failure", null) != null: return _fail("unexpected_failure_payload")
	var events: Variant = lifecycle.get("events", null)
	if not events is Array or not _same_json(events, ["admitted", "started", "completed"]): return _fail("lifecycle_events")
	if (events as Array).size() > int(capabilities.get("max_events", 0)): return _fail("lifecycle_event_cap")
	var bundle_value: Variant = lifecycle.get("bundle", null)
	if not bundle_value is Dictionary: return _fail("missing_bundle")
	var bundle: Dictionary = bundle_value
	if not _validate_bundle(bundle, request, build_manifest, capabilities): return {}
	if not _verify_hash(result_json, bundle): return {}
	return bundle.duplicate(true)

func _validate_context(request: Dictionary, build: Dictionary, runtime: Dictionary, caps: Dictionary) -> bool:
	var build_keys: Array[String] = ["manifest_schema", "rust_source_commit", "generator_version", "content_manifest_path", "content_manifest_hash", "target", "artifact", "export_schemas"]
	if not _has_exact_keys(build, build_keys): return _reject("build_manifest_shape")
	if str(build.get("manifest_schema", "")) != "procgen-build-manifest-1": return _reject("build_manifest_schema")
	if str(build.get("content_manifest_path", "")) != "data/procgen/manifests/content_manifest.json": return _reject("build_manifest_path")
	if not _is_lower_hex(str(build.get("rust_source_commit", "")), 40): return _reject("build_manifest_source")
	if not _is_sha256(str(build.get("content_manifest_hash", ""))) \
			or str(build.get("content_manifest_hash", "")) != CONTENT_HASH: return _reject("build_manifest_content")
	if not _is_json_integer(build.get("generator_version", null)) or int(build.get("generator_version", -1)) != GENERATOR_VERSION: return _reject("build_manifest_version")
	if str(build.get("target", "")).is_empty(): return _reject("build_manifest_target")
	var artifact: Variant = build.get("artifact", null)
	if not artifact is Dictionary or not _has_exact_keys(artifact, ["kind", "path", "sha256"]): return _reject("build_manifest_artifact")
	if str((artifact as Dictionary).get("kind", "")) != "gdextension" \
			or str((artifact as Dictionary).get("path", "")).is_empty() \
			or not _is_sha256(str((artifact as Dictionary).get("sha256", ""))): return _reject("build_manifest_artifact")
	var runtime_keys: Array[String] = ["schema_version", "rust_source_commit", "generator_version", "content_manifest_hash", "export_schemas", "adapter_schemas", "target", "dirty_development"]
	if not _has_exact_keys(runtime, runtime_keys): return _reject("runtime_manifest_shape")
	if str(runtime.get("schema_version", "")) != ADAPTER_SCHEMAS.generator_manifest: return _reject("runtime_manifest_schema")
	if runtime.get("dirty_development", null) is not bool or bool(runtime.dirty_development): return _reject("dirty_runtime")
	if str(runtime.get("rust_source_commit", "")) != str(build.get("rust_source_commit", "")): return _reject("manifest_source")
	if not _is_json_integer(runtime.get("generator_version", null)) \
			or int(runtime.get("generator_version", -1)) != int(build.get("generator_version", -2)) \
			or int(runtime.get("generator_version", -1)) != int(request.get("generator_version", -3)): return _reject("manifest_version")
	if str(runtime.get("content_manifest_hash", "")) != str(build.get("content_manifest_hash", "")) \
			or str(runtime.get("content_manifest_hash", "")) != str(request.get("content_manifest_hash", "")): return _reject("manifest_content")
	if str(runtime.get("target", "")).is_empty() or str(runtime.get("target", "")) != str(build.get("target", "")): return _reject("manifest_target")
	if not _same_json(build.get("export_schemas", {}), EXPORT_SCHEMAS) \
			or not _same_json(runtime.get("export_schemas", {}), EXPORT_SCHEMAS): return _reject("manifest_export_schemas")
	if not _same_json(runtime.get("adapter_schemas", {}), ADAPTER_SCHEMAS): return _reject("manifest_adapter_schemas")
	if not _validate_capabilities(caps, runtime): return false
	if JSON.stringify(request).to_utf8_buffer().size() > int(caps.get("max_request_bytes", 0)): return _reject("request_cap")
	return true

func _validate_capabilities(caps: Dictionary, runtime_manifest: Dictionary) -> bool:
	var keys: Array[String] = ["schema_version", "adapter_kind", "target", "supports_sync", "supports_async", "supports_cancel", "worker_mode", "worker_count", "queue_capacity", "retained_results", "max_request_bytes", "max_entities", "max_trace_entries", "max_events", "deadline_ms", "supported_domains", "schemas"]
	if not _has_exact_keys(caps, keys): return _reject("capability_shape")
	if str(caps.get("schema_version", "")) != ADAPTER_SCHEMAS.capabilities: return _reject("capability_schema")
	if str(caps.get("adapter_kind", "")) != "native" or str(caps.get("worker_mode", "")) != "thread_pool": return _reject("capability_adapter")
	if str(caps.get("target", "")) != str(runtime_manifest.get("target", "")): return _reject("capability_target")
	for flag in ["supports_sync", "supports_async", "supports_cancel"]:
		if caps.get(flag, null) is not bool or not bool(caps.get(flag, false)): return _reject("capability_%s" % flag)
	var maximums: Dictionary = {"worker_count": 2, "queue_capacity": 8, "retained_results": 16, "max_request_bytes": 65536, "max_entities": 4096, "max_trace_entries": 4096, "max_events": 32, "deadline_ms": 2000}
	for key in maximums.keys():
		if not _is_json_integer(caps.get(key, null)) or int(caps.get(key, 0)) <= 0 or int(caps.get(key, 0)) > int(maximums[key]): return _reject("capability_%s" % key)
	if not _same_json(caps.get("supported_domains", []), DOMAINS): return _reject("capability_domains")
	if not _same_json(caps.get("schemas", {}), ADAPTER_SCHEMAS) \
			or not _same_json(caps.get("schemas", {}), runtime_manifest.get("adapter_schemas", {})): return _reject("capability_schemas")
	return true

func _validate_bundle(bundle: Dictionary, request: Dictionary, manifest: Dictionary, caps: Dictionary) -> bool:
	var fields: Array[String] = ["schema_version", "version", "request", "world_ir", "site_ir", "gameplay_ir", "presentation_ir", "semantic_hash", "metrics", "trace"]
	if not _has_exact_keys(bundle, fields): return _reject("bundle_shape")
	if str(bundle.get("schema_version", "")) != EXPORT_SCHEMAS.procgen_bundle: return _reject("bundle_schema")
	var version_value: Variant = bundle.get("version", null)
	if not version_value is Dictionary: return _reject("version_shape")
	var version: Dictionary = version_value
	if not _has_exact_keys(version, ["generator_version", "content_manifest_hash", "export_schemas"]): return _reject("version_shape")
	if not _is_json_integer(version.get("generator_version", null)) \
			or int(version.get("generator_version", -1)) != int(request.get("generator_version", -2)) \
			or int(version.get("generator_version", -1)) != int(manifest.get("generator_version", -3)) \
			or str(version.get("content_manifest_hash", "")) != str(request.get("content_manifest_hash", "")) \
			or not _same_json(version.get("export_schemas", {}), EXPORT_SCHEMAS): return _reject("version_mismatch")
	var returned_request: Variant = bundle.get("request", null)
	if not returned_request is Dictionary or not _same_json(returned_request, request): return _reject("request_identity")
	var world_value: Variant = bundle.get("world_ir", null)
	if not world_value is Dictionary: return _reject("world_shape")
	var world: Dictionary = world_value
	if not _has_exact_keys(world, ["schema_version", "world_seed", "site_id", "x", "y", "archetype_id"]): return _reject("world_shape")
	if str(world.get("schema_version", "")) != EXPORT_SCHEMAS.world_ir: return _reject("world_ir_schema")
	var site_request: Dictionary = request.get("site", {})
	if not _same_json(world.get("world_seed", null), request.get("world_seed", null)) or str(world.get("site_id", "")) != str(site_request.get("site_id", "")) \
			or not _same_json(world.get("x", null), site_request.get("x", null)) or not _same_json(world.get("y", null), site_request.get("y", null)) \
			or str(world.get("archetype_id", "")) != str(site_request.get("archetype_id", "")): return _reject("world_identity")
	var presentation_value: Variant = bundle.get("presentation_ir", null)
	if not presentation_value is Dictionary: return _reject("presentation_shape")
	var presentation: Dictionary = presentation_value
	if not _has_exact_keys(presentation, ["schema_version", "kit_id", "locale", "seed", "approved_bindings"]): return _reject("presentation_shape")
	if str(presentation.get("schema_version", "")) != EXPORT_SCHEMAS.presentation_ir: return _reject("presentation_ir_schema")
	var presentation_request: Dictionary = request.get("presentation", {})
	if str(presentation.get("kit_id", "")) != str(site_request.get("kit_id", "")) or str(presentation.get("locale", "")) != str(presentation_request.get("locale", "")) \
			or not _same_json(presentation.get("seed", null), presentation_request.get("seed", null)) or not presentation.get("approved_bindings", null) is Dictionary: return _reject("presentation_identity")
	var site_value: Variant = bundle.get("site_ir", null)
	if not site_value is Dictionary or not _has_exact_keys(site_value, ["schema_version", "ship"]): return _reject("site_shape")
	var site_ir: Dictionary = site_value
	if str(site_ir.get("schema_version", "")) != EXPORT_SCHEMAS.site_ir: return _reject("site_ir_schema")
	var ship_value: Variant = site_ir.get("ship", null)
	if not ship_value is Dictionary or not _validate_ship_shape(ship_value as Dictionary): return false
	var ship: Dictionary = ship_value
	if not _same_json(ship.get("generator_version", null), request.get("generator_version", null)) or not _same_json(ship.get("seed", null), request.get("world_seed", null)) \
			or str(ship.get("archetype_id", "")) != str(site_request.get("archetype_id", "")): return _reject("ship_identity")
	if (ship.entities as Array).size() > int(caps.get("max_entities", 0)): return _reject("entity_cap")
	var gameplay_value: Variant = bundle.get("gameplay_ir", null)
	if not gameplay_value is Dictionary or not _has_exact_keys(gameplay_value, ["schema_version", "legacy_slice"]): return _reject("gameplay_shape")
	var gameplay_ir: Dictionary = gameplay_value
	if str(gameplay_ir.get("schema_version", "")) != EXPORT_SCHEMAS.gameplay_ir: return _reject("gameplay_ir_schema")
	if not _validate_gameplay(gameplay_ir.get("legacy_slice", null), ship): return false
	if not _validate_metrics_trace(bundle.get("metrics", null), bundle.get("trace", null), ship, caps): return false
	if not _is_sha256(str(bundle.get("semantic_hash", ""))): return _reject("semantic_hash_shape")
	return true

func _validate_ship_shape(ship: Dictionary) -> bool:
	if not _has_exact_keys(ship, SHIP_FIELDS): return _reject("ship_shape")
	for key in ["generator_version", "seed", "intactness", "entry_room", "goal_room"]:
		if not _is_json_integer(ship.get(key, null)): return _reject("ship_shape")
	for key in ["archetype_id", "template_id", "cause_of_loss"]:
		if not ship.get(key, null) is String or str(ship.get(key, "")).is_empty(): return _reject("ship_shape")
	if ship.get("fractured", null) is not bool: return _reject("ship_shape")
	for key in ["critical_path", "decks", "entities", "damage_events", "fragments"]:
		if not ship.get(key, null) is Array: return _reject("ship_shape")
	var topology: Variant = ship.get("topology", null)
	if not topology is Dictionary or not _has_exact_keys(topology, ["rooms", "portals", "verticals"]): return _reject("topology_shape")
	for key in ["rooms", "portals", "verticals"]:
		if not (topology as Dictionary).get(key, null) is Array: return _reject("topology_shape")
	var plan: Variant = ship.get("plan", null)
	if not plan is Dictionary or not _has_exact_keys(plan, ["occupancy", "edges", "placements", "floor_placements", "ceiling_placements", "socket_bindings", "errors"]): return _reject("structural_plan_shape")
	for key in ["occupancy", "edges"]:
		if not (plan as Dictionary).get(key, null) is Dictionary: return _reject("structural_plan_shape")
	for key in ["placements", "floor_placements", "ceiling_placements", "socket_bindings", "errors"]:
		if not (plan as Dictionary).get(key, null) is Array: return _reject("structural_plan_shape")
	var graph: Variant = ship.get("room_graph", null)
	if not graph is Dictionary or not _has_exact_keys(graph, ["nodes", "edges"]): return _reject("room_graph_shape")
	if not (graph as Dictionary).get("nodes", null) is Array or not (graph as Dictionary).get("edges", null) is Array: return _reject("room_graph_shape")
	return true

func _validate_gameplay(value: Variant, ship: Dictionary) -> bool:
	if not value is Dictionary: return _reject("gameplay_slice_shape")
	var gameplay: Dictionary = value
	var keys: Array[String] = ["schema_version", "document_kind", "program_id", "start_room", "goal_room", "critical_path", "fire_zones", "objectives", "loot_containers", "summary"]
	if not _has_exact_keys(gameplay, keys): return _reject("gameplay_slice_shape")
	if str(gameplay.get("schema_version", "")) != "1.1.0" or str(gameplay.get("document_kind", "")) != "ship_gameplay_slice": return _reject("gameplay_slice_schema")
	var expected_program: String = "worldgen-%s-%d" % [str(ship.get("archetype_id", "")), int(ship.get("seed", 0))]
	if str(gameplay.get("program_id", "")) != expected_program: return _reject("gameplay_identity")
	for key in ["start_room", "goal_room", "summary"]:
		if not gameplay.get(key, null) is String or str(gameplay.get(key, "")).is_empty(): return _reject("gameplay_slice_shape")
	for key in ["critical_path", "fire_zones", "objectives", "loot_containers"]:
		if not gameplay.get(key, null) is Array: return _reject("gameplay_slice_shape")
	return true

func _validate_metrics_trace(metrics_value: Variant, trace_value: Variant, ship: Dictionary, caps: Dictionary) -> bool:
	if not metrics_value is Dictionary or not trace_value is Dictionary: return _reject("diagnostic_shape")
	var metrics: Dictionary = metrics_value
	var trace: Dictionary = trace_value
	if not _has_exact_keys(metrics, ["schema_version", "pipeline_executions", "room_count", "entity_count", "structural_placement_count", "stage_timings_micros"]): return _reject("metrics_shape")
	if not _has_exact_keys(trace, ["schema_version", "rng_channels", "candidate_decisions", "failed_constraints", "repairs", "retries", "fallback", "stage_timings_micros"]): return _reject("trace_shape")
	if str(metrics.get("schema_version", "")) != "generation-metrics-1" or str(trace.get("schema_version", "")) != EXPORT_SCHEMAS.generation_trace: return _reject("diagnostic_schema")
	for key in ["pipeline_executions", "room_count", "entity_count", "structural_placement_count"]:
		if not _is_json_integer(metrics.get(key, null)) or int(metrics.get(key, -1)) < 0: return _reject("metrics_shape")
	if int(metrics.get("pipeline_executions", 0)) != 1: return _reject("pipeline_count")
	var graph: Dictionary = ship.get("room_graph", {})
	var plan: Dictionary = ship.get("plan", {})
	var placements: int = (plan.get("placements", []) as Array).size() + (plan.get("floor_placements", []) as Array).size() + (plan.get("ceiling_placements", []) as Array).size()
	if int(metrics.get("room_count", -1)) != (graph.get("nodes", []) as Array).size() or int(metrics.get("entity_count", -1)) != (ship.get("entities", []) as Array).size() \
			or int(metrics.get("structural_placement_count", -1)) != placements: return _reject("metrics_identity")
	var trace_cap: int = int(caps.get("max_trace_entries", 0))
	for key in ["rng_channels", "candidate_decisions", "failed_constraints", "repairs", "retries"]:
		var entries: Variant = trace.get(key, null)
		if not entries is Array or (entries as Array).size() > trace_cap: return _reject("trace_cap")
		for entry in entries:
			if not entry is String or str(entry).is_empty(): return _reject("trace_shape")
	if not _same_json(trace.get("rng_channels", []), RNG_CHANNELS): return _reject("trace_channels")
	var fallback: Variant = trace.get("fallback", null)
	if fallback != null and (not fallback is String or str(fallback).is_empty()): return _reject("trace_fallback")
	var trace_timings: Variant = trace.get("stage_timings_micros", null)
	var metric_timings: Variant = metrics.get("stage_timings_micros", null)
	if not trace_timings is Dictionary or not metric_timings is Dictionary or (trace_timings as Dictionary).size() > trace_cap or not _same_json(trace_timings, metric_timings): return _reject("trace_metrics_timings")
	for key in (trace_timings as Dictionary).keys():
		var timing: Variant = (trace_timings as Dictionary)[key]
		if str(key).is_empty() or not _is_json_integer(timing) or int(timing) < 0 or int(timing) > 3600000000: return _reject("trace_timing_bounds")
	return true

func _verify_hash(result_json: String, bundle: Dictionary) -> bool:
	var helper: RefCounted = CanonicalJsonScript.new()
	var actual: String = helper.semantic_hash(result_json)
	if actual.is_empty(): return _reject("semantic_projection")
	if actual != str(bundle.get("semantic_hash", "")): return _reject("semantic_hash")
	return true

func _has_exact_keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or (value as Dictionary).size() != expected.size(): return false
	for key in expected:
		if not (value as Dictionary).has(key): return false
	return true

func _is_json_integer(value: Variant) -> bool:
	if value is int: return true
	return value is float and is_finite(float(value)) and float(value) == floor(float(value)) and absf(float(value)) <= float(MAX_SAFE_JSON_INTEGER)

func _is_lower_hex(value: String, length: int) -> bool:
	if value.length() != length or value != value.to_lower(): return false
	for code in value.to_ascii_buffer():
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)): return false
	return true

func _is_sha256(value: String) -> bool: return _is_lower_hex(value, 64)

func _same_json(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float): return float(left) == float(right)
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key in left.keys():
			if not right.has(key) or not _same_json(left[key], right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index in left.size():
			if not _same_json(left[index], right[index]): return false
		return true
	return left == right

func _reject(code: String) -> bool:
	last_error = code
	return false

func _fail(code: String) -> Dictionary:
	last_error = code
	return {}
