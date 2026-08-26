extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const FallbackPolicyScript := preload("res://scripts/procgen/procgen_fallback_policy.gd")
const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")

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
	var request: Dictionary = consumer.build_request(77, 1, 2, runtime, "deep_dive")
	var raw: String = str(generator.generate_bundle(JSON.stringify(request)))
	var fallback_raw: String = raw.replace("\"fallback\":null", "\"fallback\":\"fixture-safe\"")
	_expect(fallback_raw != raw, failures, "fallback_trace_fixture")
	var valid_context: Dictionary = {
		"lifecycle": fallback_raw,
		"build_manifest": build,
		"runtime_manifest": runtime,
		"capabilities": caps,
	}
	var selected: RefCounted = FallbackPolicyScript.new()
	var original_site_id: String = str((request.site as Dictionary).site_id)
	selected.configure("fixture-safe", func(provider_request: Dictionary) -> Dictionary:
		(provider_request.site as Dictionary).site_id = "provider-mutated"
		return valid_context)
	var selected_bundle: Dictionary = selected.resolve(request, consumer)
	_expect(not selected_bundle.is_empty(), failures, "selected_bundle")
	_expect(selected.last_outcome == "selected" and selected.last_error.is_empty(), failures, "selected_outcome")
	_expect(str((request.site as Dictionary).site_id) == original_site_id, failures, "provider_request_isolated")

	var identity: RefCounted = FallbackPolicyScript.new()
	identity.configure("different-safe", func(_request: Dictionary) -> Dictionary: return valid_context)
	_expect(identity.resolve(request, consumer).is_empty(), failures, "identity_rejected")
	_expect(identity.last_outcome == "invalid" and identity.last_error == "fallback_identity", failures, "identity_outcome")

	var malformed: RefCounted = FallbackPolicyScript.new()
	malformed.configure("fixture-safe", func(_request: Dictionary) -> Dictionary: return {"lifecycle": fallback_raw})
	_expect(malformed.resolve(request, consumer).is_empty(), failures, "malformed_rejected")
	_expect(malformed.last_outcome == "invalid" and malformed.last_error == "fallback_invalid", failures, "malformed_outcome")

	var validation: RefCounted = FallbackPolicyScript.new()
	var invalid_context: Dictionary = valid_context.duplicate(true)
	invalid_context.lifecycle = fallback_raw.replace("\"semantic_hash\":\"", "\"semantic_hash\":\"0")
	validation.configure("fixture-safe", func(_request: Dictionary) -> Dictionary: return invalid_context)
	_expect(validation.resolve(request, consumer).is_empty(), failures, "validation_rejected")
	_expect(validation.last_outcome == "invalid" and validation.last_error.begins_with("fallback_validation_"), failures, "validation_outcome")

	var unconfigured: RefCounted = FallbackPolicyScript.new()
	_expect(unconfigured.resolve(request, consumer).is_empty(), failures, "unconfigured_rejected")
	_expect(unconfigured.last_outcome == "unconfigured" and unconfigured.last_error == "fallback_unconfigured", failures, "unconfigured_outcome")
	_finish(failures)

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
