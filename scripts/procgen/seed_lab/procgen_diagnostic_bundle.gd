extends RefCounted
class_name ProcgenDiagnosticBundle

const SCHEMA_VERSION := "procgen-diagnostic-1"
const MAX_BYTES := 65536
const MAX_ITEMS := 64
const MAX_DEPTH := 10
const MAX_TEXT_BYTES := 128
const MAX_SAFE_JSON_INTEGER := 9007199254740991
const MAX_TIMING_MICROS := 3600000000
const DOMAINS: Array[String] = ["world", "site", "gameplay", "presentation"]
const EXPORT_SCHEMAS := {
	"procgen_request": "procgen-request-2", "procgen_bundle": "procgen-bundle-5",
	"world_ir": "world-ir-2", "site_ir": "site-ir-2", "gameplay_ir": "gameplay-ir-3",
	"presentation_ir": "presentation-ir-2", "generation_trace": "generation-trace-4",
	"adaptive_proposal": "adaptive-proposal-2",
}
const ROOT_KEYS: Array[String] = [
	"schema_version", "kind", "identity_hash", "capture_hash", "identity",
	"versions", "hashes", "counts", "adaptive_decisions", "candidate_decisions",
	"failed_constraints", "repairs", "retries", "rng_channels", "metrics",
	"timings", "fallbacks", "failures",
]
const IDENTITY_KEYS: Array[String] = [
	"world_seed", "site_id", "site_x", "site_y", "archetype_id", "difficulty_id",
	"generator_version", "content_manifest_hash", "requested_domains",
]
const SUCCESS_VERSION_KEYS: Array[String] = [
	"generator_version", "bundle_schema", "trace_schema", "export_schemas",
	"build_manifest_schema", "runtime_manifest_schema", "capabilities_schema",
	"build_target", "runtime_target", "capabilities_target",
]
const FAILURE_VERSION_KEYS: Array[String] = ["generator_version", "lifecycle_schema"]
const SUCCESS_HASH_KEYS: Array[String] = [
	"semantic_hash", "content_manifest_hash", "build_source_commit",
	"runtime_source_commit", "artifact_sha256",
]
const FAILURE_HASH_KEYS: Array[String] = ["content_manifest_hash"]
const COUNT_KEYS: Array[String] = [
	"world_markers", "mission_nodes", "mission_edges", "topology_rooms",
	"topology_portals", "topology_verticals", "navigation_nodes", "navigation_edges",
	"encounter_spawns", "items", "creature_blueprints", "candidate_decisions",
	"failed_constraints", "repairs", "retries", "rng_channels",
]
const METRIC_KEYS: Array[String] = [
	"schema_version", "pipeline_executions", "room_count", "entity_count",
	"structural_placement_count", "stage_timings_micros",
]
const ADAPTIVE_KEYS: Array[String] = [
	"decision_id", "kind", "rule_version", "selected_candidate_id", "applied",
	"fallback", "proposal_action", "proposal_score", "proposal_confidence_bp",
	"rationale_codes",
]
const FAILURE_KEYS: Array[String] = ["code", "stage", "retryable"]
const FAILURE_PAYLOAD_KEYS: Array[String] = [
	"schema_version", "code", "stage", "message", "retryable", "fallback_id",
]
const LIFECYCLE_KEYS: Array[String] = [
	"schema_version", "status", "request_id", "bundle", "failure", "events",
]

var last_error := ""

func build_success(
		bundle: Dictionary,
		build_manifest: Dictionary,
		runtime_manifest: Dictionary,
		capabilities: Dictionary) -> Dictionary:
	last_error = ""
	if not _validate_success_inputs(bundle, build_manifest, runtime_manifest, capabilities):
		return {}
	var request: Dictionary = bundle.request
	var trace: Dictionary = bundle.trace
	var metrics: Dictionary = bundle.metrics
	if not _same_json(trace.stage_timings_micros, metrics.stage_timings_micros):
		return _fail_document("timing_mismatch")
	var document := _base_document("bundle", _identity_from_request(request))
	document.versions = {
		"generator_version": int(bundle.version.generator_version),
		"bundle_schema": str(bundle.schema_version),
		"trace_schema": str(trace.schema_version),
		"export_schemas": (bundle.version.export_schemas as Dictionary).duplicate(true),
		"build_manifest_schema": str(build_manifest.manifest_schema),
		"runtime_manifest_schema": str(runtime_manifest.schema_version),
		"capabilities_schema": str(capabilities.schema_version),
		"build_target": str(build_manifest.target),
		"runtime_target": str(runtime_manifest.target),
		"capabilities_target": str(capabilities.target),
	}
	document.hashes = {
		"semantic_hash": str(bundle.semantic_hash),
		"content_manifest_hash": str(build_manifest.content_manifest_hash),
		"build_source_commit": str(build_manifest.rust_source_commit),
		"runtime_source_commit": str(runtime_manifest.rust_source_commit),
		"artifact_sha256": str((build_manifest.artifact as Dictionary).sha256),
	}
	document.counts = _counts(bundle)
	document.adaptive_decisions = _summarize_adaptive(trace.adaptive_decisions)
	document.candidate_decisions = _summarize_codes(trace.candidate_decisions)
	document.failed_constraints = _summarize_codes(trace.failed_constraints)
	document.repairs = _summarize_codes(trace.repairs)
	document.retries = _summarize_codes(trace.retries)
	document.rng_channels = _summarize_codes(trace.rng_channels)
	document.metrics = metrics.duplicate(true)
	document.timings = trace.stage_timings_micros.duplicate(true)
	document.fallbacks = [] if trace.fallback == null else [str(trace.fallback)]
	document.failures = []
	return _finalize(document)

func build_failure(request: Dictionary, lifecycle_or_failure: Dictionary) -> Dictionary:
	last_error = ""
	if not _validate_request_identity(request):
		return {}
	var failure: Dictionary = {}
	if _exact_keys(lifecycle_or_failure, LIFECYCLE_KEYS):
		if str(lifecycle_or_failure.schema_version) != "procgen-lifecycle-result-5" \
				or str(lifecycle_or_failure.status) != "failed" \
				or lifecycle_or_failure.bundle != null \
				or not lifecycle_or_failure.failure is Dictionary \
				or not lifecycle_or_failure.events is Array:
			return _fail_document("lifecycle_shape")
		failure = lifecycle_or_failure.failure
	else:
		failure = lifecycle_or_failure
	if not _valid_failure_payload(failure):
		return _fail_document("failure_payload")
	var document := _base_document("lifecycle_failure", _identity_from_request(request))
	document.versions = {
		"generator_version": int(request.generator_version),
		"lifecycle_schema": "procgen-lifecycle-result-5",
	}
	document.hashes = {"content_manifest_hash": str(request.content_manifest_hash)}
	document.counts = _zero_counts()
	document.failures = [{
		"code": str(failure.code), "stage": str(failure.stage),
		"retryable": bool(failure.retryable),
	}]
	document.fallbacks = [] if failure.fallback_id == null else [str(failure.fallback_id)]
	return _finalize(document)

func validate(document: Dictionary) -> bool:
	last_error = ""
	if not _exact_keys(document, ROOT_KEYS):
		return _reject("root_shape")
	if document.schema_version != SCHEMA_VERSION or not document.kind is String \
			or not ["bundle", "lifecycle_failure"].has(str(document.kind)):
		return _reject("root_identity")
	if not document.identity_hash is String or not _is_hex(str(document.identity_hash), 64) \
			or not document.capture_hash is String or not _is_hex(str(document.capture_hash), 64):
		return _reject("document_hash_shape")
	if not document.identity is Dictionary or not _validate_identity(document.identity):
		return false
	if not document.versions is Dictionary or not document.hashes is Dictionary \
			or not document.counts is Dictionary or not document.metrics is Dictionary \
			or not document.timings is Dictionary:
		return _reject("object_types")
	for key: String in [
		"adaptive_decisions", "candidate_decisions", "failed_constraints", "repairs",
		"retries", "rng_channels", "fallbacks", "failures",
	]:
		if not document[key] is Array or (document[key] as Array).size() > MAX_ITEMS:
			return _reject("collection_%s" % key)
	if not _validate_counts(document.counts) or not _validate_timing_map(document.timings):
		return false
	if not _validate_code_array(document.candidate_decisions, true) \
			or not _validate_code_array(document.failed_constraints, true) \
			or not _validate_code_array(document.repairs, true) \
			or not _validate_code_array(document.retries, true) \
			or not _validate_code_array(document.rng_channels, true) \
			or not _validate_fallback_array(document.fallbacks):
		return false
	if document.kind == "bundle":
		if not _validate_success_document(document):
			return false
	else:
		if not _validate_failure_document(document):
			return false
	if not _validate_privacy_and_caps(document):
		return false
	var identity_copy: Dictionary = document.duplicate(true)
	identity_copy.erase("identity_hash")
	identity_copy.erase("capture_hash")
	if str(document.identity_hash) != _hash(_canonical(identity_copy, false)):
		return _reject("identity_hash")
	var capture_copy: Dictionary = document.duplicate(true)
	var expected_capture := str(capture_copy.capture_hash)
	capture_copy.capture_hash = ""
	if expected_capture != _hash(_canonical(capture_copy, true)):
		return _reject("capture_hash")
	if JSON.stringify(document).to_utf8_buffer().size() > MAX_BYTES:
		return _reject("byte_cap")
	return true

func _validate_success_inputs(bundle: Dictionary, build: Dictionary, runtime: Dictionary, caps: Dictionary) -> bool:
	var bundle_keys := ["schema_version", "version", "request", "world_ir", "site_ir", "gameplay_ir", "presentation_ir", "semantic_hash", "metrics", "trace"]
	if not _exact_keys(bundle, bundle_keys) or str(bundle.schema_version) != "procgen-bundle-5" \
			or not bundle.version is Dictionary or not bundle.request is Dictionary \
			or not bundle.metrics is Dictionary or not bundle.trace is Dictionary:
		return _reject("bundle_shape")
	if not _validate_request_identity(bundle.request):
		return false
	if not _exact_keys(bundle.version, ["generator_version", "content_manifest_hash", "export_schemas"]) \
			or not _same_json(bundle.version.export_schemas, EXPORT_SCHEMAS) \
			or str(bundle.trace.get("schema_version", "")) != "generation-trace-4":
		return _reject("bundle_version")
	if str(build.get("manifest_schema", "")) != "procgen-build-manifest-4" \
			or str(runtime.get("schema_version", "")) != "procgen-generator-manifest-4" \
			or str(caps.get("schema_version", "")) != "procgen-capabilities-4" \
			or not build.get("artifact", null) is Dictionary:
		return _reject("context_shape")
	var generator_version := int(bundle.request.generator_version)
	var content_hash := str(bundle.request.content_manifest_hash)
	var source_commit := str(build.get("rust_source_commit", ""))
	if int(bundle.version.generator_version) != generator_version \
			or int(build.get("generator_version", -1)) != generator_version \
			or int(runtime.get("generator_version", -1)) != generator_version \
			or str(bundle.version.content_manifest_hash) != content_hash \
			or str(build.get("content_manifest_hash", "")) != content_hash \
			or str(runtime.get("content_manifest_hash", "")) != content_hash \
			or str(runtime.get("rust_source_commit", "")) != source_commit \
			or str(build.get("target", "")) != str(runtime.get("target", "")) \
			or str(build.get("target", "")) != str(caps.get("target", "")):
		return _reject("context_identity")
	if not _is_hex(source_commit, 40) \
			or not _is_hex(str((build.artifact as Dictionary).get("sha256", "")), 64) \
			or not _is_hex(str(bundle.semantic_hash), 64):
		return _reject("context_hashes")
	return true

func _validate_request_identity(request: Dictionary) -> bool:
	if not _exact_keys(request, ["schema_version", "world_seed", "site", "difficulty_id", "player_model", "requested_domains", "generator_version", "content_manifest_hash", "presentation"]) \
			or str(request.schema_version) != "procgen-request-2" or not request.site is Dictionary:
		return _reject("request_shape")
	var site: Dictionary = request.site
	if not _exact_keys(site, ["site_id", "x", "y", "archetype_id", "kit_id", "intactness_override_bp", "cause_of_loss", "loot_richness_bp"]):
		return _reject("request_site_shape")
	return _validate_identity(_identity_from_request(request))

func _identity_from_request(request: Dictionary) -> Dictionary:
	var site: Dictionary = request.get("site", {})
	return {
		"world_seed": _normalized_integer(request.get("world_seed", null)), "site_id": site.get("site_id", null),
		"site_x": _normalized_integer(site.get("x", null)), "site_y": _normalized_integer(site.get("y", null)),
		"archetype_id": site.get("archetype_id", null),
		"difficulty_id": request.get("difficulty_id", null),
		"generator_version": _normalized_integer(request.get("generator_version", null)),
		"content_manifest_hash": request.get("content_manifest_hash", null),
		"requested_domains": (request.get("requested_domains", []) as Array).duplicate(true) if request.get("requested_domains", null) is Array else null,
	}

func _validate_identity(identity: Dictionary) -> bool:
	if not _exact_keys(identity, IDENTITY_KEYS):
		return _reject("identity_shape")
	if not _bounded_int(identity.world_seed, 0, MAX_SAFE_JSON_INTEGER) \
			or not _bounded_int(identity.site_x, -2147483647, 2147483646) \
			or not _bounded_int(identity.site_y, -2147483647, 2147483646) \
			or not _bounded_int(identity.generator_version, 0, 4294967295):
		return _reject("identity_bounds")
	for key: String in ["site_id", "archetype_id", "difficulty_id"]:
		if not identity[key] is String or not _is_code(str(identity[key])):
			return _reject("identity_code")
	if not identity.content_manifest_hash is String or not _is_hex(str(identity.content_manifest_hash), 64):
		return _reject("identity_content_hash")
	if not identity.requested_domains is Array or (identity.requested_domains as Array).is_empty() \
			or (identity.requested_domains as Array).size() > DOMAINS.size():
		return _reject("identity_domains")
	var canonical: Array[String] = []
	for domain: String in DOMAINS:
		if (identity.requested_domains as Array).has(domain):
			canonical.append(domain)
	if not _same_json(canonical, identity.requested_domains):
		return _reject("identity_domains")
	return true

func _validate_success_document(document: Dictionary) -> bool:
	if not _exact_keys(document.versions, SUCCESS_VERSION_KEYS) \
			or not _exact_keys(document.hashes, SUCCESS_HASH_KEYS) \
			or not _exact_keys(document.metrics, METRIC_KEYS):
		return _reject("success_shape")
	if document.versions.bundle_schema != "procgen-bundle-5" \
			or document.versions.trace_schema != "generation-trace-4" \
			or document.versions.build_manifest_schema != "procgen-build-manifest-4" \
			or document.versions.runtime_manifest_schema != "procgen-generator-manifest-4" \
			or document.versions.capabilities_schema != "procgen-capabilities-4" \
			or not _same_json(document.versions.export_schemas, EXPORT_SCHEMAS):
		return _reject("success_versions")
	if not _bounded_int(document.versions.generator_version, 0, 4294967295) \
			or int(document.identity.generator_version) != int(document.versions.generator_version):
		return _reject("success_generator")
	for key: String in ["build_target", "runtime_target", "capabilities_target"]:
		if not document.versions[key] is String or not _is_code(str(document.versions[key])):
			return _reject("success_target")
	if document.versions.build_target != document.versions.runtime_target \
			or document.versions.build_target != document.versions.capabilities_target:
		return _reject("success_target_mismatch")
	if not _is_hex(str(document.hashes.semantic_hash), 64) \
			or not _is_hex(str(document.hashes.content_manifest_hash), 64) \
			or not _is_hex(str(document.hashes.build_source_commit), 40) \
			or not _is_hex(str(document.hashes.runtime_source_commit), 40) \
			or not _is_hex(str(document.hashes.artifact_sha256), 64) \
			or document.hashes.build_source_commit != document.hashes.runtime_source_commit \
			or document.identity.content_manifest_hash != document.hashes.content_manifest_hash:
		return _reject("success_hashes")
	if not _validate_metrics(document.metrics):
		return false
	if document.failures.size() != 0:
		return _reject("success_failures")
	for decision: Variant in document.adaptive_decisions:
		if not _validate_adaptive_summary(decision):
			return false
	return true

func _validate_failure_document(document: Dictionary) -> bool:
	if not _exact_keys(document.versions, FAILURE_VERSION_KEYS) \
			or not _exact_keys(document.hashes, FAILURE_HASH_KEYS) \
			or not document.metrics.is_empty() or not document.timings.is_empty() \
			or not document.adaptive_decisions.is_empty() \
			or not document.candidate_decisions.is_empty() \
			or not document.failed_constraints.is_empty() or not document.repairs.is_empty() \
			or not document.retries.is_empty() or not document.rng_channels.is_empty():
		return _reject("failure_shape")
	if document.versions.lifecycle_schema != "procgen-lifecycle-result-5" \
			or not _bounded_int(document.versions.generator_version, 0, 4294967295) \
			or int(document.versions.generator_version) != int(document.identity.generator_version) \
			or not _is_hex(str(document.hashes.content_manifest_hash), 64) \
			or document.hashes.content_manifest_hash != document.identity.content_manifest_hash:
		return _reject("failure_identity")
	if document.failures.size() != 1 or not _validate_failure_summary(document.failures[0]):
		return _reject("failure_record")
	return true

func _counts(bundle: Dictionary) -> Dictionary:
	var site: Dictionary = bundle.site_ir
	var ship: Dictionary = site.get("ship", {})
	var topology: Dictionary = ship.get("topology", {})
	var mission: Dictionary = site.get("mission_graph", {})
	var navigation: Dictionary = site.get("navigation", {})
	var gameplay: Dictionary = bundle.gameplay_ir
	var encounter: Dictionary = gameplay.get("encounter", {})
	var trace: Dictionary = bundle.trace
	return {
		"world_markers": _array_count(bundle.world_ir.get("markers", null)),
		"mission_nodes": _array_count(mission.get("nodes", null)),
		"mission_edges": _array_count(mission.get("edges", null)),
		"topology_rooms": _array_count(topology.get("rooms", null)),
		"topology_portals": _array_count(topology.get("portals", null)),
		"topology_verticals": _array_count(topology.get("verticals", null)),
		"navigation_nodes": _array_count(navigation.get("nodes", null)),
		"navigation_edges": _array_count(navigation.get("edges", null)),
		"encounter_spawns": _array_count(encounter.get("spawns", null)),
		"items": _array_count(gameplay.get("items", null)),
		"creature_blueprints": _array_count(gameplay.get("creature_blueprints", null)),
		"candidate_decisions": _array_count(trace.get("candidate_decisions", null)),
		"failed_constraints": _array_count(trace.get("failed_constraints", null)),
		"repairs": _array_count(trace.get("repairs", null)),
		"retries": _array_count(trace.get("retries", null)),
		"rng_channels": _array_count(trace.get("rng_channels", null)),
	}

func _zero_counts() -> Dictionary:
	var result := {}
	for key: String in COUNT_KEYS:
		result[key] = 0
	return result

func _summarize_adaptive(value: Variant) -> Array:
	if not value is Array:
		return []
	var output: Array = []
	for raw: Variant in (value as Array).slice(0, mini((value as Array).size(), MAX_ITEMS)):
		if not raw is Dictionary or not raw.get("proposal", null) is Dictionary:
			return []
		var proposal: Dictionary = raw.proposal
		var action := _action_code(proposal.get("action", null))
		if action.is_empty():
			return []
		output.append({
			"decision_id": raw.get("decision_id", null), "kind": raw.get("kind", null),
			"rule_version": raw.get("rule_version", null),
			"selected_candidate_id": raw.get("selected_candidate_id", null),
			"applied": raw.get("applied", null), "fallback": raw.get("fallback", null),
			"proposal_action": action, "proposal_score": proposal.get("score", null),
			"proposal_confidence_bp": proposal.get("confidence_bp", null),
			"rationale_codes": _summarize_codes(proposal.get("rationale_codes", [])),
		})
	return output

func _summarize_codes(value: Variant) -> Array:
	if not value is Array:
		return []
	var output: Array = []
	for item: Variant in (value as Array).slice(0, mini((value as Array).size(), MAX_ITEMS)):
		if not item is String:
			return []
		var text := str(item)
		output.append(text if _is_code(text) else "trace:%s" % _hash(text))
	return output

func _action_code(value: Variant) -> String:
	if value is String and str(value) == "no_op":
		return "no_op"
	if value is Dictionary and (value as Dictionary).size() == 1:
		for key: String in ["select_candidate", "adjust_encounter"]:
			if (value as Dictionary).has(key):
				return key
	return ""

func _validate_counts(counts: Dictionary) -> bool:
	if not _exact_keys(counts, COUNT_KEYS):
		return _reject("count_shape")
	for key: String in COUNT_KEYS:
		if not _bounded_int(counts[key], 0, 1000000):
			return _reject("count_value")
	return true

func _validate_metrics(metrics: Dictionary) -> bool:
	if metrics.schema_version != "generation-metrics-1" \
			or not _bounded_int(metrics.pipeline_executions, 1, 1) \
			or not _bounded_int(metrics.room_count, 0, 1000000) \
			or not _bounded_int(metrics.entity_count, 0, 1000000) \
			or not _bounded_int(metrics.structural_placement_count, 0, 1000000) \
			or not metrics.stage_timings_micros is Dictionary \
			or not _validate_timing_map(metrics.stage_timings_micros):
		return _reject("metrics")
	return true

func _validate_timing_map(value: Dictionary) -> bool:
	if value.size() > MAX_ITEMS:
		return _reject("timing_cap")
	for key: Variant in value:
		if not key is String or not _is_code(str(key)) \
				or not _bounded_int(value[key], 0, MAX_TIMING_MICROS):
			return _reject("timing_value")
	return true

func _validate_adaptive_summary(value: Variant) -> bool:
	if not value is Dictionary or not _exact_keys(value, ADAPTIVE_KEYS):
		return _reject("adaptive_shape")
	for key: String in ["decision_id", "kind", "rule_version", "proposal_action"]:
		if not value[key] is String or not _is_code(str(value[key])):
			return _reject("adaptive_code")
	for key: String in ["selected_candidate_id", "fallback"]:
		if value[key] != null and (not value[key] is String or not _is_code(str(value[key]))):
			return _reject("adaptive_optional_code")
	if value.applied is not bool \
			or not _bounded_int(value.proposal_score, -10000, 10000) \
			or not _bounded_int(value.proposal_confidence_bp, 0, 10000) \
			or not value.rationale_codes is Array \
			or (value.rationale_codes as Array).is_empty() \
			or not _validate_code_array(value.rationale_codes, false):
		return _reject("adaptive_values")
	return true

func _valid_failure_payload(value: Dictionary) -> bool:
	return _exact_keys(value, FAILURE_PAYLOAD_KEYS) \
			and value.schema_version == "procgen-failure-1" \
			and value.code is String and _is_code(str(value.code)) \
			and value.stage is String and _is_code(str(value.stage)) \
			and value.message is String and value.retryable is bool \
			and (value.fallback_id == null or (value.fallback_id is String and _is_code(str(value.fallback_id))))

func _validate_failure_summary(value: Variant) -> bool:
	return value is Dictionary and _exact_keys(value, FAILURE_KEYS) \
			and value.code is String and _is_code(str(value.code)) \
			and value.stage is String and _is_code(str(value.stage)) \
			and value.retryable is bool

func _validate_code_array(value: Array, allow_empty: bool) -> bool:
	if value.size() > MAX_ITEMS or (not allow_empty and value.is_empty()):
		return _reject("code_array_cap")
	for item: Variant in value:
		if not item is String or not _is_code(str(item)):
			return _reject("code_array_value")
	return true

func _validate_fallback_array(value: Array) -> bool:
	if value.size() > MAX_ITEMS:
		return _reject("fallback_cap")
	for item: Variant in value:
		if not item is String or not _is_fallback(str(item)):
			return _reject("fallback_value")
	return true

func _is_fallback(value: String) -> bool:
	if _is_code(value):
		return true
	if value.to_utf8_buffer().size() > MAX_TEXT_BYTES:
		return false
	var parts: PackedStringArray = value.split("|")
	return parts.size() == 2 and parts[0].begins_with("world:") and parts[1].begins_with("site:") \
			and _is_code(parts[0]) and _is_code(parts[1])

func _validate_privacy_and_caps(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH:
		return _reject("depth_cap")
	if value is String:
		return value.to_utf8_buffer().size() <= MAX_TEXT_BYTES or _reject("text_cap")
	if value is Array:
		if (value as Array).size() > MAX_ITEMS:
			return _reject("array_cap")
		for item: Variant in value:
			if not _validate_privacy_and_caps(item, depth + 1):
				return false
	elif value is Dictionary:
		if (value as Dictionary).size() > MAX_ITEMS:
			return _reject("object_cap")
		for key: Variant in value:
			if not key is String or str(key).to_utf8_buffer().size() > MAX_TEXT_BYTES:
				return _reject("key_cap")
			var lowered := str(key).to_lower()
			for denied: String in ["locale", "path", "host", "device", "account", "network", "stack", "username", "personal", "message"]:
				if lowered.contains(denied):
					return _reject("privacy_key")
			if not _validate_privacy_and_caps(value[key], depth + 1):
				return false
	return true

func _base_document(kind: String, identity: Dictionary) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION, "kind": kind, "identity_hash": "",
		"capture_hash": "", "identity": identity, "versions": {}, "hashes": {},
		"counts": {}, "adaptive_decisions": [], "candidate_decisions": [],
		"failed_constraints": [], "repairs": [], "retries": [], "rng_channels": [],
		"metrics": {}, "timings": {}, "fallbacks": [], "failures": [],
	}

func _finalize(document: Dictionary) -> Dictionary:
	var identity_copy: Dictionary = document.duplicate(true)
	identity_copy.erase("identity_hash")
	identity_copy.erase("capture_hash")
	document.identity_hash = _hash(_canonical(identity_copy, false))
	document.capture_hash = _hash(_canonical(document, true))
	return document if validate(document) else {}

func _array_count(value: Variant) -> int:
	return (value as Array).size() if value is Array else 0

func _bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	return _is_json_integer(value) and int(value) >= minimum and int(value) <= maximum

func _is_json_integer(value: Variant) -> bool:
	if value is int:
		return int(value) >= -MAX_SAFE_JSON_INTEGER and int(value) <= MAX_SAFE_JSON_INTEGER
	return value is float and is_finite(float(value)) \
			and float(value) == floor(float(value)) \
			and absf(float(value)) <= float(MAX_SAFE_JSON_INTEGER)

func _normalized_integer(value: Variant) -> Variant:
	return int(value) if _is_json_integer(value) else value

func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if not expected.has(str(key)):
			return false
	return true

func _is_code(value: String) -> bool:
	if value.is_empty() or value.to_utf8_buffer().size() > MAX_TEXT_BYTES:
		return false
	for character: String in value:
		if not ((character >= "a" and character <= "z") \
				or (character >= "0" and character <= "9") \
				or ".:_-".contains(character)):
			return false
	return true

func _is_hex(value: String, length: int) -> bool:
	if value.length() != length:
		return false
	for character: String in value:
		if not ((character >= "a" and character <= "f") or (character >= "0" and character <= "9")):
			return false
	return true

func _same_json(left: Variant, right: Variant) -> bool:
	return _canonical(left, true) == _canonical(right, true)

func _hash(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

func _canonical(value: Variant, include_timings: bool) -> String:
	if value is Dictionary:
		var keys: Array[String] = []
		for key: Variant in value:
			if include_timings or (str(key) != "timings" and str(key) != "stage_timings_micros"):
				keys.append(str(key))
		keys.sort()
		var fields: Array[String] = []
		for key: String in keys:
			fields.append(JSON.stringify(key) + ":" + _canonical(value[key], include_timings))
		return "{" + ",".join(fields) + "}"
	if value is Array:
		var items: Array[String] = []
		for item: Variant in value:
			items.append(_canonical(item, include_timings))
		return "[" + ",".join(items) + "]"
	return JSON.stringify(value)

func _fail_document(code: String) -> Dictionary:
	last_error = code
	return {}

func _reject(code: String) -> bool:
	last_error = code
	return false
