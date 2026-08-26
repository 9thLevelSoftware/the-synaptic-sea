extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const FallbackPolicyScript := preload("res://scripts/procgen/procgen_fallback_policy.gd")
const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")
const CanonicalJsonScript := preload("res://scripts/procgen/procgen_canonical_json.gd")

const SAFE_RETURN_ID: String = "site:authored-safe-return"

func _init() -> void:
	var failures: Array[String] = []
	var generator: Object = ClassDB.instantiate("DerelictGenerator") as Object
	_expect(generator != null, failures, "adapter")
	if generator == null:
		_finish(failures)
		return
	var build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
	var runtime: Dictionary = JSON.parse_string(str(generator.generator_manifest()))
	var caps: Dictionary = JSON.parse_string(str(generator.capabilities()))
	_expect(ValidatorScript.new().validate(build, generator) == ValidatorScript.OK, failures, "manifest")
	var consumer: RefCounted = ConsumerScript.new()
	var fixture: Dictionary = _find_safe_return_fixture(generator, consumer, runtime)
	var request: Dictionary = fixture.get("request", {})
	var fallback_raw: String = str(fixture.get("lifecycle", ""))
	_expect(not fallback_raw.is_empty(), failures, "fallback_bundle_fixture")
	if fallback_raw.is_empty():
		_finish(failures)
		return
	var valid_context: Dictionary = {
		"lifecycle": fallback_raw,
		"build_manifest": build,
		"runtime_manifest": runtime,
		"capabilities": caps,
	}
	var selected: RefCounted = FallbackPolicyScript.new()
	var original_site_id: String = str((request.site as Dictionary).site_id)
	selected.configure(SAFE_RETURN_ID, func(provider_request: Dictionary) -> Dictionary:
		(provider_request.site as Dictionary).site_id = "provider-mutated"
		return valid_context)
	var selected_bundle: Dictionary = selected.resolve(request, consumer)
	_expect(not selected_bundle.is_empty(), failures, "selected_bundle")
	_expect(selected.last_outcome == "selected" and selected.last_error.is_empty(), failures, "selected_outcome")
	_expect(str((request.site as Dictionary).site_id) == original_site_id, failures, "provider_request_isolated")

	var identity: RefCounted = FallbackPolicyScript.new()
	identity.configure("world:safe-world-v3", func(_request: Dictionary) -> Dictionary: return valid_context)
	_expect(identity.resolve(request, consumer).is_empty(), failures, "identity_rejected")
	_expect(identity.last_outcome == "invalid" and identity.last_error == "fallback_identity", failures, "identity_outcome")

	var malformed: RefCounted = FallbackPolicyScript.new()
	malformed.configure(SAFE_RETURN_ID, func(_request: Dictionary) -> Dictionary: return {"lifecycle": fallback_raw})
	_expect(malformed.resolve(request, consumer).is_empty(), failures, "malformed_rejected")
	_expect(malformed.last_outcome == "invalid" and malformed.last_error == "fallback_invalid", failures, "malformed_outcome")

	var malformed_context: RefCounted = FallbackPolicyScript.new()
	var wrong_context_types: Dictionary = valid_context.duplicate(true)
	wrong_context_types.build_manifest = "not-a-dictionary"
	malformed_context.configure(SAFE_RETURN_ID, func(_request: Dictionary) -> Dictionary: return wrong_context_types)
	_expect(malformed_context.resolve(request, consumer).is_empty(), failures, "malformed_context_rejected")
	_expect(malformed_context.last_outcome == "invalid" and malformed_context.last_error == "fallback_invalid", failures, "malformed_context_outcome")

	var validation: RefCounted = FallbackPolicyScript.new()
	var invalid_context: Dictionary = valid_context.duplicate(true)
	invalid_context.lifecycle = fallback_raw.replace("\"semantic_hash\":\"", "\"semantic_hash\":\"0")
	validation.configure(SAFE_RETURN_ID, func(_request: Dictionary) -> Dictionary: return invalid_context)
	_expect(validation.resolve(request, consumer).is_empty(), failures, "validation_rejected")
	_expect(validation.last_outcome == "invalid" and validation.last_error.begins_with("fallback_validation_"), failures, "validation_outcome")

	var unconfigured: RefCounted = FallbackPolicyScript.new()
	_expect(unconfigured.resolve(request, consumer).is_empty(), failures, "unconfigured_rejected")
	_expect(unconfigured.last_outcome == "unconfigured" and unconfigured.last_error == "fallback_unconfigured", failures, "unconfigured_outcome")
	_finish(failures)


func _find_safe_return_fixture(generator: Object, consumer: RefCounted, runtime: Dictionary) -> Dictionary:
	for seed_value in 192:
		var request: Dictionary = consumer.build_request(seed_value, 0, 1, runtime, "standard")
		if request.is_empty():
			continue
		var raw: String = str(generator.generate_bundle(JSON.stringify(request)))
		var fallback_raw: String = _safe_return_fixture(raw)
		if not fallback_raw.is_empty():
			return {"request": request, "lifecycle": fallback_raw}
	return {}


# Test-only construction of the complete ungated safe-return layer produced by
# Rust's SiteIR fallback compiler. The production bridge never rewrites a
# bundle. A survey SiteIR and the authored safe-return SiteIR are mechanically
# identical except for the manifest-owned mission identity and trace evidence.
func _safe_return_fixture(raw: String) -> String:
	var lifecycle_value: Variant = JSON.parse_string(raw)
	if not lifecycle_value is Dictionary:
		return ""
	var lifecycle: Dictionary = lifecycle_value
	var bundle_value: Variant = lifecycle.get("bundle", null)
	if not bundle_value is Dictionary:
		return ""
	var bundle: Dictionary = bundle_value
	var site_ir_value: Variant = bundle.get("site_ir", null)
	var trace_value: Variant = bundle.get("trace", null)
	if not site_ir_value is Dictionary or not trace_value is Dictionary:
		return ""
	var site_ir: Dictionary = site_ir_value
	var mission_value: Variant = site_ir.get("mission_graph", null)
	if not mission_value is Dictionary:
		return ""
	var mission: Dictionary = mission_value
	if str(mission.get("mission_id", "")) != "survey" \
			or not (mission.get("gates", []) as Array).is_empty():
		return ""
	mission.mission_id = "authored-safe-return"
	var trace: Dictionary = trace_value
	if trace.get("fallback", null) != null:
		return ""
	var decisions_value: Variant = trace.get("candidate_decisions", null)
	if not decisions_value is Array:
		return ""
	var decisions: Array = decisions_value
	decisions.append("site:rejected_candidate")
	decisions.append("site:selected_fallback")
	trace.fallback = SAFE_RETURN_ID

	# The semantic projection excludes trace diagnostics but includes SiteIR.
	# Recompute it after selecting the complete authored layer.
	var fixture_without_hash: String = JSON.stringify(lifecycle)
	var semantic_hash: String = CanonicalJsonScript.new().semantic_hash(fixture_without_hash)
	if semantic_hash.is_empty():
		return ""
	bundle.semantic_hash = semantic_hash
	return JSON.stringify(lifecycle)

func _finish(failures: Array[String]) -> void:
	if not failures.is_empty():
		for failure in failures:
			print("TASK5 FALLBACK FAIL:%s" % failure)
		quit(1)
		return
	print("TASK5 FALLBACK PASS selected=true identity=true invalid=true validation=true unconfigured=true")
	quit(0)

func _expect(ok: bool, failures: Array[String], label: String) -> void:
	if not ok:
		failures.append(label)
