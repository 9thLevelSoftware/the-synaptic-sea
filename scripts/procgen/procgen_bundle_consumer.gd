extends RefCounted
class_name ProcgenBundleConsumer

const GENERATOR_VERSION: int = 2
const CONTENT_HASH: String = "e45770cf36ca296644b291a1c12d750281c8fcd3e520430b3ae2995d03ab14d2"
const DOMAINS: Array[String] = ["world", "site", "gameplay", "presentation"]
const SCHEMAS: Dictionary = {
	"procgen_bundle": "procgen-bundle-1", "world_ir": "world-ir-1",
	"site_ir": "site-ir-1", "gameplay_ir": "gameplay-ir-1",
	"presentation_ir": "presentation-ir-1", "generation_trace": "generation-trace-1",
	"metrics": "generation-metrics-1", "request": "procgen-request-1"
}

var last_error: String = ""

func build_request(seed_value: int, size: int, condition: int, runtime_manifest: Dictionary = {}) -> Dictionary:
	if seed_value < 0 or seed_value > 9007199254740991:
		last_error = "json_unsafe_seed"
		return {}
	var archetypes: Dictionary = {0: "shuttle", 1: "corvette", 2: "freighter"}
	var intactness: Dictionary = {0: 9500, 1: 6000, 2: 2000}
	if not archetypes.has(size) or not intactness.has(condition):
		last_error = "unsupported_ship_parameters"
		return {}
	var unsigned_seed: int = seed_value
	var site_id: String = "site_%s_%s_%s" % [str(unsigned_seed), str(size), str(condition)]
	var generator_version: int = int(runtime_manifest.get("generator_version", GENERATOR_VERSION))
	var content_hash: String = str(runtime_manifest.get("content_manifest_hash", CONTENT_HASH))
	return {"schema_version": "procgen-request-1", "world_seed": unsigned_seed,
		"site": {"site_id": site_id, "x": 0, "y": 0, "archetype_id": archetypes[size],
			"kit_id": "ship_structural_v0", "intactness_override_bp": intactness[condition],
			"cause_of_loss": null, "loot_richness_bp": 5000},
		"difficulty_id": "standard", "player_model": {"schema_version": "player-model-1", "signals": []},
		"requested_domains": DOMAINS.duplicate(), "generator_version": generator_version,
		"content_manifest_hash": content_hash, "presentation": {"seed": unsigned_seed, "locale": "en-US"}}

func consume(result_json: String, request: Dictionary, build_manifest: Dictionary = {}, runtime_manifest: Dictionary = {}, capabilities: Dictionary = {}) -> Dictionary:
	last_error = ""
	if request.is_empty() or result_json.is_empty(): return _fail("missing_bundle")
	var parsed: Variant = JSON.parse_string(result_json)
	if not parsed is Dictionary: return _fail("malformed_bundle_json")
	var lifecycle: Dictionary = parsed
	if str(lifecycle.get("status", "")) != "completed": return _fail("lifecycle_not_completed")
	if lifecycle.get("failure", null) != null: return _fail("unexpected_failure_payload")
	var bundle: Variant = lifecycle.get("bundle", null)
	if not bundle is Dictionary: return _fail("missing_bundle")
	var doc: Dictionary = bundle
	if build_manifest.is_empty() or str(build_manifest.get("manifest_schema", "")) != "procgen-build-manifest-1": return _fail("build_manifest_mismatch")
	if runtime_manifest.is_empty() or str(runtime_manifest.get("schema_version", "")) != "procgen-generator-manifest-1": return _fail("runtime_manifest_mismatch")
	if not capabilities.is_empty() and str(capabilities.get("schema_version", "")) != "procgen-capabilities-1": return _fail("capabilities_schema")
	if int(runtime_manifest.get("generator_version", -1)) != int(build_manifest.get("generator_version", -2)) or str(runtime_manifest.get("content_manifest_hash", "")) != str(build_manifest.get("content_manifest_hash", "")): return _fail("manifest_identity")
	if bool(runtime_manifest.get("dirty_development", true)): return _fail("dirty_runtime")
	if str(runtime_manifest.get("target", "")) != str(build_manifest.get("target", "")): return _fail("target_mismatch")
	if not _validate_capabilities(capabilities, runtime_manifest): return {}
	if not _validate(doc, request, build_manifest, capabilities): return {}
	return doc.duplicate(true)

func _validate(bundle: Dictionary, request: Dictionary, manifest: Dictionary, capabilities: Dictionary) -> bool:
	for field in ["schema_version", "version", "request", "world_ir", "site_ir", "gameplay_ir", "presentation_ir", "semantic_hash", "metrics", "trace"]:
		if not bundle.has(field): _fail("missing_%s" % field); return false
	if str(bundle.schema_version) != SCHEMAS.procgen_bundle: _fail("bundle_schema"); return false
	var version: Dictionary = bundle.version
	if int(version.get("generator_version", -1)) != int(request.get("generator_version", -2)) or str(version.get("content_manifest_hash", "")) != str(request.get("content_manifest_hash", "")): _fail("version_mismatch"); return false
	for layer in ["world_ir", "site_ir", "gameplay_ir", "presentation_ir"]:
		if str((bundle[layer] as Dictionary).get("schema_version", "")) != SCHEMAS[layer]: _fail("%s_schema" % layer); return false
	if str((bundle.metrics as Dictionary).get("schema_version", "")) != SCHEMAS.metrics or str((bundle.trace as Dictionary).get("schema_version", "")) != SCHEMAS.generation_trace: _fail("diagnostic_schema"); return false
	var returned_request: Dictionary = bundle.request
	if JSON.stringify(_canonical(returned_request)) != JSON.stringify(_canonical(request)): _fail("request_identity"); return false
	var world: Dictionary = bundle.world_ir
	var site: Dictionary = request.site
	if str(world.get("site_id", "")) != str(site.site_id) or int(world.get("world_seed", -1)) != int(request.world_seed) or int(world.get("x", 99)) != 0 or int(world.get("y", 99)) != 0: _fail("world_identity"); return false
	var presentation: Dictionary = bundle.presentation_ir
	if str(presentation.get("kit_id", "")) != "ship_structural_v0" or str(presentation.get("locale", "")) != "en-US" or int(presentation.get("seed", -1)) != int(request.world_seed): _fail("presentation_identity"); return false
	if int((bundle.metrics as Dictionary).get("pipeline_executions", 0)) != 1: _fail("pipeline_count"); return false
	var trace: Dictionary = bundle.trace
	if trace.get("rng_channels", []).size() != 16: _fail("trace_channels"); return false
	if not _verify_hash(bundle): return false
	return true

func _validate_capabilities(caps: Dictionary, runtime_manifest: Dictionary) -> bool:
	if caps.is_empty() or str(caps.get("adapter_kind", "")) != "native" or not bool(caps.get("supports_sync", false)): _fail("capability_sync"); return false
	if str(caps.get("target", "")) != str(runtime_manifest.get("target", "")): _fail("capability_target"); return false
	if str(caps.get("worker_mode", "")) != "thread_pool": _fail("capability_worker_mode"); return false
	var domains: Variant = caps.get("supported_domains", [])
	if domains is not Array or (domains as Array) != DOMAINS: _fail("capability_domains"); return false
	var schemas: Variant = caps.get("schemas", {})
	if not schemas is Dictionary or str((schemas as Dictionary).get("procgen_bundle", "")) != SCHEMAS.procgen_bundle: _fail("capability_schemas"); return false
	for key in ["max_request_bytes", "max_entities", "max_trace_entries", "max_events", "deadline_ms"]:
		if int(caps.get(key, 0)) <= 0: _fail("capability_%s" % key); return false
	return true

func _verify_hash(bundle: Dictionary) -> bool:
	var mechanical: Dictionary = {"version": bundle.version.duplicate(true), "request": bundle.request.duplicate(true), "world_ir": bundle.world_ir.duplicate(true), "site_ir": bundle.site_ir.duplicate(true), "gameplay_ir": bundle.gameplay_ir.duplicate(true)}
	(mechanical.request as Dictionary).erase("presentation")
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_canonical(mechanical)).to_utf8_buffer())
	var actual: String = context.finish().hex_encode()
	if actual != str(bundle.semantic_hash): _fail("semantic_hash"); return false
	return true

func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array[String] = []
		for key in value.keys(): keys.append(str(key))
		keys.sort()
		for key in keys: result[key] = _canonical(value[key])
		return result
	if value is Array:
		var output: Array = []
		for item in value: output.append(_canonical(item))
		return output
	return value

func _fail(code: String) -> Dictionary:
	last_error = code
	return {}
