extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const DiagnosticScript := preload("res://scripts/procgen/seed_lab/procgen_diagnostic_bundle.gd")
const StoreScript := preload("res://scripts/procgen/seed_lab/procgen_diagnostic_store.gd")
const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")

const PREFIX := "PROCGEN DIAGNOSTIC BUNDLE"

func _init() -> void:
	var generator: Object = ClassDB.instantiate("DerelictGenerator") as Object
	if generator == null:
		_fail("adapter_missing")
		return
	var build_value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
	var runtime_value: Variant = JSON.parse_string(str(generator.generator_manifest()))
	var caps_value: Variant = JSON.parse_string(str(generator.capabilities()))
	if not build_value is Dictionary or not runtime_value is Dictionary or not caps_value is Dictionary:
		_fail("context_shape")
		return
	var build: Dictionary = build_value
	var runtime: Dictionary = runtime_value
	var caps: Dictionary = caps_value
	if ValidatorScript.new().validate(build, generator) != ValidatorScript.OK:
		_fail("manifest")
		return
	var consumer: RefCounted = ConsumerScript.new()
	var request: Dictionary = consumer.build_request(
		424242, 2, 2, runtime, "standard", "frigate",
		"gate5-diagnostic", 4096, -4096, [], 42, "it-IT")
	if request.is_empty():
		_fail("request_%s" % consumer.last_error)
		return
	var lifecycle: String = str(generator.generate_bundle(JSON.stringify(request)))
	var bundle: Dictionary = consumer.consume(lifecycle, request, build, runtime, caps)
	if bundle.is_empty():
		_fail("consumer_%s" % consumer.last_error)
		return

	var builder: RefCounted = DiagnosticScript.new()
	var first: Dictionary = builder.build_success(bundle, build, runtime, caps)
	if not _expect(not first.is_empty() and builder.validate(first), "live_%s" % builder.last_error): return
	if not _expect(first.adaptive_decisions.size() == 3, "adaptive_count"): return
	if not _expect(int(first.counts.world_markers) > 0 and int(first.counts.topology_rooms) > 0 \
			and int(first.counts.mission_nodes) > 0 and int(first.counts.navigation_nodes) > 0 \
			and int(first.counts.encounter_spawns) > 0 and int(first.counts.items) > 0 \
			and int(first.counts.creature_blueprints) > 0, "meaningful_counts"): return
	if not _expect(_bounded_codes(first.candidate_decisions) and _bounded_codes(first.failed_constraints) \
			and _bounded_codes(first.repairs) and _bounded_codes(first.retries) \
			and _bounded_codes(first.rng_channels), "trace_codes"): return

	var second: Dictionary = builder.build_success(bundle, build, runtime, caps)
	if not _expect(first.identity_hash == second.identity_hash and first.capture_hash == second.capture_hash, "deterministic_capture"): return
	var timed_bundle: Dictionary = bundle.duplicate(true)
	timed_bundle.trace.stage_timings_micros["assemble"] = int(timed_bundle.trace.stage_timings_micros.get("assemble", 0)) + 1
	timed_bundle.metrics.stage_timings_micros["assemble"] = int(timed_bundle.metrics.stage_timings_micros.get("assemble", 0)) + 1
	var timed: Dictionary = builder.build_success(timed_bundle, build, runtime, caps)
	if not _expect(not timed.is_empty() and first.identity_hash == timed.identity_hash \
			and first.capture_hash != timed.capture_hash, "timing_identity_%s" % builder.last_error): return

	var failure_payload := {
		"schema_version": "procgen-failure-1", "code": "timeout", "stage": "adapter",
		"message": "sensitive free form text is deliberately discarded", "retryable": true,
		"fallback_id": null,
	}
	var failure: Dictionary = builder.build_failure(request, failure_payload)
	if not _expect(not failure.is_empty() and builder.validate(failure), "failure_%s" % builder.last_error): return
	if not _expect(not JSON.stringify(failure).contains("sensitive free form"), "failure_message_redaction"): return

	if not _rejects(builder, first, "root_shape", func(value: Dictionary) -> void: value.unknown = true): return
	if not _rejects(builder, first, "metrics", func(value: Dictionary) -> void: value.metrics.entity_count = "1"): return
	if not _rejects(builder, first, "count_value", func(value: Dictionary) -> void: value.counts.items = -1): return
	if not _rejects(builder, first, "success_hashes", func(value: Dictionary) -> void: value.hashes.semantic_hash = "x"): return
	if not _rejects(builder, first, "adaptive_shape", func(value: Dictionary) -> void: value.adaptive_decisions[0] = "bad"): return
	if not _rejects(builder, first, "privacy_key", func(value: Dictionary) -> void: value.timings["device_id"] = 1): return
	if not _rejects(builder, first, "collection_candidate_decisions", func(value: Dictionary) -> void:
		value.candidate_decisions = []
		for index: int in range(65): value.candidate_decisions.append("trace:%064d" % index)
	): return

	var oversized: Dictionary = first.duplicate(true)
	var long_codes: Array = []
	for index: int in range(64):
		long_codes.append("trace:%s" % ("a".repeat(114) + "%08d" % index))
	for key: String in ["candidate_decisions", "failed_constraints", "repairs", "retries", "rng_channels", "fallbacks"]:
		oversized[key] = long_codes.duplicate()
	oversized.adaptive_decisions = []
	for index: int in range(64): oversized.adaptive_decisions.append(first.adaptive_decisions[0].duplicate(true))
	_rehash(builder, oversized)
	if not _expect(not builder.validate(oversized) and builder.last_error == "byte_cap", "byte_cap_%s" % builder.last_error): return

	var unique_timing: int = int(Time.get_ticks_usec() % 3000000000) + 1
	var stored_bundle: Dictionary = bundle.duplicate(true)
	stored_bundle.trace.stage_timings_micros["assemble"] = unique_timing
	stored_bundle.metrics.stage_timings_micros["assemble"] = unique_timing
	var stored_document: Dictionary = builder.build_success(stored_bundle, build, runtime, caps)
	if not _expect(not stored_document.is_empty(), "store_document"): return
	var store: RefCounted = StoreScript.new()
	var saved: Dictionary = store.save(stored_document)
	if not _expect(bool(saved.get("saved", false)) and store.validate_path(str(saved.get("path", ""))), "store_save_%s" % store.last_error): return
	var idempotent: Dictionary = store.save(stored_document)
	if not _expect(bool(idempotent.get("saved", false)) and bool(idempotent.get("idempotent", false)), "store_idempotent"): return
	if not _expect(not bool(store.save(stored_document, "unexpected").get("saved", true)) and store.last_error == "scope_not_supported", "store_scope"): return
	var path: String = str(saved.path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _expect(file != null, "store_conflict_open"): return
	file.store_string("{}")
	file.close()
	if not _expect(not bool(store.save(stored_document).get("saved", true)) and store.last_error == "conflict", "store_conflict"): return
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not _expect(DirAccess.remove_absolute(absolute_path) == OK, "store_cleanup"): return

	print(PREFIX + " PASS deterministic=true timing_capture=true caps=true privacy=true conflict=true live=true")
	quit(0)

func _rejects(builder: RefCounted, source: Dictionary, code: String, mutate: Callable) -> bool:
	var value: Dictionary = source.duplicate(true)
	mutate.call(value)
	return _expect(not builder.validate(value) and builder.last_error == code, "reject_%s_got_%s" % [code, builder.last_error])

func _rehash(builder: RefCounted, document: Dictionary) -> void:
	var identity_copy: Dictionary = document.duplicate(true)
	identity_copy.erase("identity_hash")
	identity_copy.erase("capture_hash")
	document.identity_hash = builder._hash(builder._canonical(identity_copy, false))
	var capture_copy: Dictionary = document.duplicate(true)
	capture_copy.capture_hash = ""
	document.capture_hash = builder._hash(builder._canonical(capture_copy, true))

func _bounded_codes(values: Array) -> bool:
	if values.size() > 64: return false
	for value: Variant in values:
		if not value is String or str(value).to_utf8_buffer().size() > 128: return false
	return true

func _expect(condition: bool, marker: String) -> bool:
	if condition: return true
	_fail(marker)
	return false

func _fail(marker: String) -> void:
	print(PREFIX + " FAIL " + marker)
	quit(1)
