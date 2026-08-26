extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
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
	var cases: Array = [["lifecycle_schema", "schema_version", "wrong", "lifecycle_schema"], ["lifecycle_status", "status", "failed", "lifecycle_not_completed"], ["missing_bundle", "bundle", null, "missing_bundle"], ["bundle_schema", "bundle.schema_version", "wrong", "bundle_schema"], ["hash", "bundle.semantic_hash", "0".repeat(64), "semantic_hash"], ["world_identity", "bundle.world_ir.site_id", "wrong-site", "world_identity"], ["presentation_identity", "bundle.presentation_ir.locale", "fr-FR", "presentation_identity"], ["pipeline_count", "bundle.metrics.pipeline_executions", 2, "pipeline_count"], ["trace_schema", "bundle.trace.schema_version", "wrong", "diagnostic_schema"]]
	for item in cases:
		var mutated: Dictionary = original.duplicate(true)
		_set_path(mutated, str(item[1]), item[2])
		count += 1
		var result: Dictionary = consumer.consume(JSON.stringify(mutated), request, build, runtime, caps)
		_expect(result.is_empty() and consumer.last_error == str(item[3]), failures, str(item[0]) + ":" + consumer.last_error)
	count += 1; _expect(consumer.build_request(9007199254740992, 0, 1, runtime).is_empty() and consumer.last_error == "json_unsafe_seed", failures, "unsafe_seed")
	count += 1; _expect(consumer.build_request(42, 99, 1, runtime).is_empty() and consumer.last_error == "unsupported_ship_parameters", failures, "unsupported_archetype")
	if not failures.is_empty():
		for failure in failures: print("TASK5 CONSUMER FAIL:%s" % failure)
		quit(1); return
	print("TASK5 CONSUMER PASS live=true cases=%d baseline=true hash=true lifecycle=true identity=true caps_context=true" % count)
	quit(0)

func _set_path(root: Dictionary, path: String, value: Variant) -> void:
	var parts: PackedStringArray = path.split(".")
	var current: Dictionary = root
	for index in range(parts.size() - 1):
		if not current.has(parts[index]) or not current[parts[index]] is Dictionary: return
		current = current[parts[index]]
	current[parts[-1]] = value

func _expect(ok: bool, failures: Array[String], label: String) -> void:
	if not ok: failures.append(label)
