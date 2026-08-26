extends RefCounted
class_name ProcgenSeedLabModel

const MAX_NODES: int = 256
const MAX_EDGES: int = 512
const MAX_TRACE_ENTRIES: int = 64
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991
const REQUEST_DOMAINS: Array[String] = ["world", "site", "gameplay", "presentation"]
const EXPORT_SCHEMAS: Dictionary = {
	"procgen_request": "procgen-request-2", "procgen_bundle": "procgen-bundle-5",
	"world_ir": "world-ir-2", "site_ir": "site-ir-2", "gameplay_ir": "gameplay-ir-3",
	"presentation_ir": "presentation-ir-2", "generation_trace": "generation-trace-4",
	"adaptive_proposal": "adaptive-proposal-2",
}
const LOCKABLE_FIELDS: Array[String] = ["world_seed", "site.site_id", "site.x", "site.y", "site.archetype_id", "site.kit_id", "site.intactness_override_bp", "site.loot_richness_bp", "site.cause_of_loss", "difficulty_id", "player_model", "presentation.seed", "presentation.locale"]
const GRAPH_SOURCES: Dictionary = {
	"world": ["world_ir"], "mission": ["site_ir", "mission_graph"],
	"topology": ["site_ir", "ship"], "navigation": ["site_ir", "navigation"],
	"encounter": ["gameplay_ir", "encounter"], "item": ["gameplay_ir", "items"],
	"creature": ["gameplay_ir", "creature_blueprints"],
}

var slots: Array[Dictionary] = [{}, {}]
var locks: Dictionary = {}
var lock_snapshots: Dictionary = {}
var last_error: String = ""
var last_generation: Dictionary = {}

func clear() -> void:
	slots = [{}, {}]
	last_error = ""
	last_generation = {}

func load_lifecycle(slot: int, lifecycle: Variant, request: Dictionary = {}) -> bool:
	last_error = ""
	if slot < 0 or slot > 1:
		return _reject("slot")
	var document: Variant = _deep_copy(lifecycle)
	if document is String:
		var parser := JSON.new()
		if parser.parse(document as String) != OK:
			return _reject("json")
		document = parser.data
	if not document is Dictionary:
		return _reject("document")
	var root := document as Dictionary
	if root.has("bundle"):
		var bundle: Variant = root.get("bundle")
		if not bundle is Dictionary or not _validate_bundle_shape(bundle as Dictionary):
			return _reject("bundle_version")
		if not (bundle as Dictionary).has("semantic_hash"):
			return _reject("semantic_hash")
		var view := _build_slot(bundle as Dictionary, false, request)
		slots[slot] = view
		return true
	var failure: Variant = root.get("failure", null) if root.get("failure", null) is Dictionary else root
	if failure is Dictionary and (
			(str((failure as Dictionary).get("schema_version", "")) == "procgen-failure-1" \
			and str((failure as Dictionary).get("code", "")).length() > 0)
			or str((failure as Dictionary).get("failure_code", "")).length() > 0):
		slots[slot] = {
			"valid": false, "failure": _deep_copy(failure), "request": _deep_copy(request),
			"graphs": {}, "metrics": {}, "trace": {}, "validation_failures": [str((failure as Dictionary).get("code", (failure as Dictionary).get("failure_code", "generation_failed")))],
		}
		return true
	return _reject("lifecycle_shape")

func load_bundle(slot: int, bundle: Dictionary, request: Dictionary = {}) -> bool:
	return load_lifecycle(slot, {"bundle": bundle}, request)

func get_slot(slot: int) -> Dictionary:
	if slot < 0 or slot > 1:
		return {}
	return _deep_copy(slots[slot])

func compare() -> Dictionary:
	if not bool(slots[0].get("valid", false)) or not bool(slots[1].get("valid", false)):
		return {"valid": false, "reason": "both_slots_required"}
	var left: Dictionary = slots[0]
	var right: Dictionary = slots[1]
	var graph_counts: Dictionary = {}
	for domain in GRAPH_SOURCES.keys():
		var a: Dictionary = left.graphs.get(domain, {})
		var b: Dictionary = right.graphs.get(domain, {})
		graph_counts[domain] = {"a_nodes": (a.get("nodes", []) as Array).size(), "b_nodes": (b.get("nodes", []) as Array).size(), "a_edges": (a.get("edges", []) as Array).size(), "b_edges": (b.get("edges", []) as Array).size()}
	return {"valid": true, "a_hash": left.get("semantic_hash", ""), "b_hash": right.get("semantic_hash", ""), "same_hash": left.get("semantic_hash", "") == right.get("semantic_hash", ""), "graph_counts": graph_counts, "metrics_delta": _numeric_delta(left.get("metrics", {}), right.get("metrics", {})), "request_delta": _request_delta(left.get("request", {}), right.get("request", {}))}

func set_lock(field: String, locked: bool = true) -> bool:
	if not LOCKABLE_FIELDS.has(field):
		last_error = "lock_field"
		return false
	locks[field] = locked
	if not locked: lock_snapshots.erase(field)
	return true

func capture_locks(request: Dictionary) -> void:
	for field in LOCKABLE_FIELDS:
		if bool(locks.get(field, false)):
			var value: Variant = _path_get(request, field)
			if value != null: lock_snapshots[field] = _deep_copy(value)

func is_locked(field: String) -> bool:
	return bool(locks.get(field, false))

func lock_state() -> Dictionary:
	return _deep_copy(locks)


func selective_request(request: Dictionary, domains: Array[String], base_request: Dictionary = {}) -> Dictionary:
	last_error = ""
	var valid_domains: Array[String] = ["world", "site", "gameplay", "presentation"]
	if domains.is_empty() or domains.size() != domains.duplicate().size():
		last_error = "requested_domains"
		return {}
	for domain in domains:
		if not valid_domains.has(domain):
			last_error = "requested_domains"
			return {}
	var result: Dictionary = _deep_copy(request)
	var canonical: Array[String] = []
	for domain in valid_domains:
		if domains.has(domain):
			canonical.append(domain)
	result["requested_domains"] = canonical
	if base_request.is_empty(): base_request = request
	capture_locks(base_request)
	for field in LOCKABLE_FIELDS:
		if is_locked(field) and lock_snapshots.has(field):
			_path_set(result, field, _deep_copy(lock_snapshots[field]))
	return result

func inspect_trace(slot: int) -> Dictionary:
	var source: Dictionary = get_slot(slot)
	var trace: Dictionary = source.get("trace", {})
	var result: Dictionary = {}
	for key in ["candidate_decisions", "failed_constraints", "repairs", "retries", "rng_channels", "adaptive_decisions", "fallback", "stage_timings_micros"]:
		var values: Array = trace.get(key, []) if trace is Dictionary and trace.get(key, []) is Array else []
		result[key] = values.slice(0, mini(values.size(), MAX_TRACE_ENTRIES)) if trace is Dictionary and trace.get(key, null) is Array else (_deep_copy(trace[key]) if trace is Dictionary and trace.has(key) else [])
	result["truncated"] = _trace_size(trace) > MAX_TRACE_ENTRIES
	return result

func build_promotion_candidate(classification: String, diagnostic: Dictionary, request: Dictionary = {}) -> Dictionary:
	last_error = ""
	if not ["approved_candidate", "failure_seed", "authored_fallback"].has(classification):
		_reject("classification")
		return {}
	if str(diagnostic.get("schema_version", "")) != "procgen-diagnostic-1" \
			or not diagnostic.get("identity", null) is Dictionary \
			or not diagnostic.get("versions", null) is Dictionary \
			or not diagnostic.get("hashes", null) is Dictionary:
		_reject("diagnostic_shape")
		return {}
	var identity_hash := str(diagnostic.get("identity_hash", ""))
	var capture_hash := str(diagnostic.get("capture_hash", ""))
	if not _is_hex_hash(identity_hash) or not _is_hex_hash(capture_hash):
		_reject("diagnostic_identity")
		return {}
	if request.is_empty() or not _request_matches_diagnostic(request, diagnostic.identity):
		_reject("request_identity")
		return {}
	var kind: String = str(diagnostic.get("kind", ""))
	var hashes: Dictionary = diagnostic.hashes
	var versions: Dictionary = diagnostic.versions
	var semantic_hash: Variant = str(hashes.get("semantic_hash", "")) if kind == "bundle" else null
	if semantic_hash is String and not _is_hex_hash(str(semantic_hash)): semantic_hash = null
	var failure_code: Variant = null
	if kind == "lifecycle_failure" and diagnostic.get("failures", []) is Array \
			and not (diagnostic.failures as Array).is_empty() and diagnostic.failures[0] is Dictionary:
		failure_code = str((diagnostic.failures[0] as Dictionary).get("code", ""))
	var fallback_id: Variant = null
	if diagnostic.get("fallbacks", []) is Array and not (diagnostic.fallbacks as Array).is_empty():
		fallback_id = str(diagnostic.fallbacks[0])
	var trace_code: Variant = null
	if classification == "failure_seed" and kind == "bundle":
		for field: String in ["repairs", "failed_constraints", "retries"]:
			if diagnostic.get(field, []) is Array and not (diagnostic[field] as Array).is_empty():
				trace_code = str(diagnostic[field][0])
				break
	elif classification == "authored_fallback" and diagnostic.get("candidate_decisions", []) is Array \
			and (diagnostic.candidate_decisions as Array).has("site:selected_fallback"):
		trace_code = "site:selected_fallback"
	var expected: Dictionary = {
		"semantic_hash": semantic_hash, "failure_code": failure_code,
		"fallback_id": fallback_id, "trace_code": trace_code,
	}
	if classification == "approved_candidate" and (semantic_hash == null or failure_code != null or fallback_id != null):
		_reject("classification_outcome")
		return {}
	if classification == "failure_seed" and failure_code == null and (semantic_hash == null or trace_code == null):
		_reject("classification_outcome")
		return {}
	if classification == "authored_fallback" and (semantic_hash == null or fallback_id == null or failure_code != null or trace_code != "site:selected_fallback"):
		_reject("classification_outcome")
		return {}
	var content_hash: String = str(hashes.get("content_manifest_hash", diagnostic.identity.get("content_manifest_hash", "")))
	var provenance: Dictionary = {
		"tool_version": "seed-lab-1", "generator_version": int(versions.get("generator_version", 0)),
		"content_manifest_hash": content_hash, "rust_source_commit": str(hashes.get("build_source_commit", "")),
		"build_target": str(versions.get("build_target", "")), "artifact_sha256": str(hashes.get("artifact_sha256", "")),
		"technical_validation_codes": ["bundle_valid", "consumer_valid"] if kind == "bundle" else ["lifecycle_failure_valid"],
	}
	var candidate_id := _sha256(classification + ":" + identity_hash)
	return {
		"schema_version": "procgen-promotion-candidate-1", "candidate_id": candidate_id,
		"classification": classification, "request": _deep_copy(request), "expected": expected,
		"source_diagnostic": {"identity_hash": identity_hash, "capture_hash": capture_hash},
		"provenance": provenance,
	}

func _request_matches_diagnostic(request: Dictionary, identity: Dictionary) -> bool:
	if not request.get("site", null) is Dictionary or not request.get("requested_domains", null) is Array:
		return false
	var site: Dictionary = request.site
	return int(request.get("world_seed", -1)) == int(identity.get("world_seed", -2)) \
			and str(site.get("site_id", "")) == str(identity.get("site_id", "")) \
			and int(site.get("x", 0)) == int(identity.get("site_x", 1)) \
			and int(site.get("y", 0)) == int(identity.get("site_y", 1)) \
			and str(site.get("archetype_id", "")) == str(identity.get("archetype_id", "")) \
			and str(request.get("difficulty_id", "")) == str(identity.get("difficulty_id", "")) \
			and int(request.get("generator_version", -1)) == int(identity.get("generator_version", -2)) \
			and str(request.get("content_manifest_hash", "")) == str(identity.get("content_manifest_hash", "")) \
			and _same_json(request.requested_domains, identity.get("requested_domains", []))

func _build_slot(bundle: Dictionary, failure: bool, request: Dictionary = {}) -> Dictionary:
	var graphs: Dictionary = {}
	for domain in GRAPH_SOURCES.keys():
		graphs[domain] = _project_graph(domain, bundle)
	var trace: Dictionary = bundle.get("trace", {}) if bundle.get("trace", {}) is Dictionary else {}
	var preserved_request: Dictionary = request if not request.is_empty() else bundle.get("request", {})
	return {"valid": true, "bundle": _deep_copy(bundle), "request": _deep_copy(preserved_request), "semantic_hash": str(bundle.get("semantic_hash", "")), "metrics": _deep_copy(bundle.get("metrics", {})), "trace": _cap_trace(trace), "graphs": graphs, "validation_failures": []}

func _project_graph(domain: String, bundle: Dictionary) -> Dictionary:
	var nodes: Array = []
	var edges: Array = []
	var source: Variant = bundle
	for key in GRAPH_SOURCES[domain]:
		if source is Dictionary:
			source = (source as Dictionary).get(key, {})
		else:
			source = {}
	_walk_graph(source, "", domain, domain, nodes, edges)
	for node: Dictionary in nodes: node["metadata"] = {}
	for index in range(edges.size()): edges[index]["id"] = "%s:edge:%05d" % [domain, index]
	return {"domain": domain, "nodes": nodes, "edges": edges, "truncated": nodes.size() >= MAX_NODES or edges.size() >= MAX_EDGES}

func _walk_graph(value: Variant, parent: String, path: String, domain: String, nodes: Array, edges: Array) -> void:
	if nodes.size() >= MAX_NODES: return
	var id := domain + ":" + path
	nodes.append({"id": id, "kind": "object" if value is Dictionary else "value", "label": path.get_file() if path.contains("/") else path, "metadata": {}})
	if not parent.is_empty() and edges.size() < MAX_EDGES:
		edges.append({"from": parent, "to": id, "kind": "contains"})
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		for key in keys:
			if nodes.size() >= MAX_NODES: break
			_walk_graph((value as Dictionary)[key], id, path + "/" + str(key), domain, nodes, edges)
	elif value is Array:
		for index in range((value as Array).size()):
			if nodes.size() >= MAX_NODES: break
			_walk_graph((value as Array)[index], id, path + "/%03d" % index, domain, nodes, edges)

func _cap_trace(trace: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["candidate_decisions", "failed_constraints", "repairs", "retries", "rng_channels", "adaptive_decisions", "fallback", "stage_timings_micros"]:
		var values: Array = trace.get(key, []) if trace.get(key, []) is Array else []
		result[key] = values.slice(0, mini(values.size(), MAX_TRACE_ENTRIES)) if trace.get(key, null) is Array else (_deep_copy(trace[key]) if trace.has(key) else [])
	return result

func _trace_size(trace: Dictionary) -> int:
	var total := 0
	for value in trace.values():
		if value is Array: total += (value as Array).size()
	return total

func _validate_bundle_shape(bundle: Dictionary) -> bool:
	for key in ["schema_version", "version", "request", "world_ir", "site_ir", "gameplay_ir", "presentation_ir", "trace", "metrics", "semantic_hash"]:
		if not bundle.has(key): return false
	if str(bundle.schema_version) != "procgen-bundle-5" or not bundle.version is Dictionary or not bundle.request is Dictionary or not _is_hex_hash(str(bundle.semantic_hash)): return false
	var version: Dictionary = bundle.version
	if version.keys().size() != 3 or not version.has_all(["generator_version", "content_manifest_hash", "export_schemas"]): return false
	if int(version.generator_version) != 3 or not _is_hex_hash(str(version.content_manifest_hash)) \
			or not version.export_schemas is Dictionary or not _same_json(version.export_schemas, EXPORT_SCHEMAS): return false
	var layer_schemas: Dictionary = {"world_ir": "world-ir-2", "site_ir": "site-ir-2", "gameplay_ir": "gameplay-ir-3", "presentation_ir": "presentation-ir-2"}
	for layer: String in layer_schemas:
		if not bundle[layer] is Dictionary or str((bundle[layer] as Dictionary).get("schema_version", "")) != str(layer_schemas[layer]): return false
	if not bundle.trace is Dictionary or not bundle.metrics is Dictionary: return false
	var trace: Dictionary = bundle.trace
	for field: String in ["candidate_decisions", "failed_constraints", "repairs", "retries", "rng_channels", "adaptive_decisions"]:
		if not trace.get(field, null) is Array: return false
	if str(trace.get("schema_version", "")) != "generation-trace-4" or not trace.get("stage_timings_micros", null) is Dictionary \
			or (trace.get("fallback", null) != null and not trace.get("fallback") is String): return false
	var metrics: Dictionary = bundle.metrics
	if str(metrics.get("schema_version", "")) != "generation-metrics-1" or int(metrics.get("pipeline_executions", -1)) != 1 \
			or not metrics.get("stage_timings_micros", null) is Dictionary: return false
	for field: String in ["room_count", "entity_count", "structural_placement_count"]:
		if not metrics.get(field, null) is int and not metrics.get(field, null) is float: return false
	var request: Dictionary = bundle.request
	if not _has_exact_keys(request, ["schema_version", "world_seed", "site", "difficulty_id", "player_model", "presentation", "requested_domains", "generator_version", "content_manifest_hash"]): return false
	if str(request.schema_version) != "procgen-request-2" or not _json_integer(request.world_seed) \
			or int(request.world_seed) < 0 or int(request.world_seed) > MAX_SAFE_JSON_INTEGER \
			or not ["standard", "hardened", "deep_dive"].has(str(request.difficulty_id)): return false
	if not request.site is Dictionary or not _has_exact_keys(request.site, ["site_id", "x", "y", "archetype_id", "kit_id", "intactness_override_bp", "cause_of_loss", "loot_richness_bp"]): return false
	var site: Dictionary = request.site
	if str(site.site_id).is_empty() or not ["shuttle", "corvette", "freighter", "frigate"].has(str(site.archetype_id)) \
			or str(site.kit_id) != "ship_structural_v0" or not _json_integer(site.x) or not _json_integer(site.y) \
			or not _json_integer(site.loot_richness_bp) or int(site.loot_richness_bp) < 0 or int(site.loot_richness_bp) > 30000: return false
	if site.intactness_override_bp != null and (not _json_integer(site.intactness_override_bp) or int(site.intactness_override_bp) < 0 or int(site.intactness_override_bp) > 10000): return false
	if site.cause_of_loss != null and not site.cause_of_loss is String: return false
	if not request.player_model is Dictionary or not _has_exact_keys(request.player_model, ["schema_version", "signals"]) \
			or str(request.player_model.schema_version) != "player-model-2" or not request.player_model.signals is Array \
			or (request.player_model.signals as Array).size() > 4: return false
	var previous_signal: int = -1
	var signal_kinds: Array[String] = ["combat_mastery", "damage_pressure", "resource_pressure", "objective_pace"]
	for signal_value: Variant in request.player_model.signals:
		if not signal_value is Dictionary or not _has_exact_keys(signal_value, ["kind", "value_bp"]): return false
		var signal_index: int = signal_kinds.find(str((signal_value as Dictionary).kind))
		if signal_index <= previous_signal or not _json_integer((signal_value as Dictionary).value_bp) \
				or int((signal_value as Dictionary).value_bp) < 0 or int((signal_value as Dictionary).value_bp) > 10000: return false
		previous_signal = signal_index
	if not request.presentation is Dictionary or not _has_exact_keys(request.presentation, ["seed", "locale"]) \
			or not _json_integer(request.presentation.seed) or int(request.presentation.seed) < 0 \
			or int(request.presentation.seed) > MAX_SAFE_JSON_INTEGER or str(request.presentation.locale).is_empty(): return false
	if not request.requested_domains is Array or (request.requested_domains as Array).is_empty(): return false
	var canonical_domains: Array[String] = []
	for domain: String in REQUEST_DOMAINS:
		if (request.requested_domains as Array).has(domain): canonical_domains.append(domain)
	if not _same_json(canonical_domains, request.requested_domains): return false
	return int(request.generator_version) == 3 \
			and int(request.generator_version) == int(version.generator_version) \
			and str(request.content_manifest_hash) == str(version.content_manifest_hash) \
			and _is_hex_hash(str(request.content_manifest_hash))

func _has_exact_keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or (value as Dictionary).size() != expected.size(): return false
	for key: Variant in expected:
		if not (value as Dictionary).has(key): return false
	return true

func _json_integer(value: Variant) -> bool:
	if value is int: return int(value) >= -MAX_SAFE_JSON_INTEGER and int(value) <= MAX_SAFE_JSON_INTEGER
	return value is float and is_finite(float(value)) and float(value) == floor(float(value)) \
			and absf(float(value)) <= float(MAX_SAFE_JSON_INTEGER)

func _is_hex_hash(value: String) -> bool:
	if value.length() != 64: return false
	for character in value:
		if not "0123456789abcdef".contains(character): return false
	return true

func _path_get(root: Dictionary, path: String) -> Variant:
	var value: Variant = root
	for key in path.split("."):
		if not value is Dictionary or not (value as Dictionary).has(key): return null
		value = (value as Dictionary)[key]
	return value

func _path_set(root: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var cursor := root
	for index in range(parts.size() - 1):
		if not cursor.has(parts[index]) or not cursor[parts[index]] is Dictionary: cursor[parts[index]] = {}
		cursor = cursor[parts[index]]
	cursor[parts[parts.size() - 1]] = value

func _request_delta(a: Dictionary, b: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	for key in b.keys():
		if not _same_json(a.get(key), b[key]): delta[str(key)] = {"a": _deep_copy(a.get(key)), "b": _deep_copy(b[key])}
	return delta

func _numeric_delta(a: Dictionary, b: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in b.keys():
		if a.get(key) is int or a.get(key) is float:
			if b[key] is int or b[key] is float: result[str(key)] = float(b[key]) - float(a[key])
	return result

func _sorted_strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	result.sort()
	return result

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func _same_json(a: Variant, b: Variant) -> bool:
	return JSON.stringify(_canonical_value(a)) == JSON.stringify(_canonical_value(b))

func _canonical_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		for key in keys:
			result[str(key)] = _canonical_value((value as Dictionary)[key])
		return result
	if value is Array:
		var array: Array = []
		for item in value:
			array.append(_canonical_value(item))
		return array
	return value

func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

func _reject(code: String) -> bool:
	last_error = code
	return false
