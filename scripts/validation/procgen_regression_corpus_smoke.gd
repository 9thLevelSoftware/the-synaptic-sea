extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const DiagnosticScript := preload("res://scripts/procgen/seed_lab/procgen_diagnostic_bundle.gd")
const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")
const PREFIX := "PROCGEN REGRESSION CORPUS"
const CLASSIFICATIONS: Array[String] = ["approved_candidate", "failure_seed", "authored_fallback"]

func _init() -> void:
	var generator: Object = ClassDB.instantiate("DerelictGenerator") as Object
	if generator == null:
		_fail("adapter_missing")
		return
	var corpus_value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/corpora/procgen_regression_v1.json"))
	var build_value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
	var runtime_value: Variant = JSON.parse_string(str(generator.generator_manifest()))
	var caps_value: Variant = JSON.parse_string(str(generator.capabilities()))
	if not corpus_value is Dictionary or not build_value is Dictionary or not runtime_value is Dictionary or not caps_value is Dictionary:
		_fail("document_shape")
		return
	var corpus: Dictionary = corpus_value
	var build: Dictionary = build_value
	var runtime: Dictionary = runtime_value
	var caps: Dictionary = caps_value
	if str(corpus.get("schema_version", "")) != "procgen-regression-corpus-1" or not corpus.get("entries", null) is Array:
		_fail("corpus_shape")
		return
	if ValidatorScript.new().validate(build, generator) != ValidatorScript.OK:
		_fail("manifest")
		return
	var entries: Array = corpus.entries
	if entries.size() != 3:
		_fail("entry_count")
		return
	var seen: Dictionary = {}
	var previous_id: String = ""
	var consumer: RefCounted = ConsumerScript.new()
	var diagnostics: RefCounted = DiagnosticScript.new()
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			_fail("entry_shape")
			return
		var entry: Dictionary = entry_value
		var classification: String = str(entry.get("classification", ""))
		var candidate_id: String = str(entry.get("candidate_id", ""))
		if not CLASSIFICATIONS.has(classification) or seen.has(classification):
			_fail("classification")
			return
		seen[classification] = true
		if not previous_id.is_empty() and previous_id >= candidate_id:
			_fail("ordering")
			return
		previous_id = candidate_id
		if str(entry.get("approval_ref", "")) != "synaptic-sea-stage-gate:t_bdced4e5":
			_fail("approval")
			return
		if not entry.get("provenance", null) is Dictionary or not _provenance_matches(entry.provenance, build):
			_fail("provenance_%s" % classification)
			return
		var request: Dictionary = _integer_request(entry.get("request", {}))
		var lifecycle_json: String = str(generator.generate_bundle(JSON.stringify(request)))
		var bundle: Dictionary = consumer.consume(lifecycle_json, request, build, runtime, caps)
		var expected: Dictionary = entry.get("expected", {})
		if bundle.is_empty():
			var lifecycle_value: Variant = JSON.parse_string(lifecycle_json)
			var code: String = ""
			if lifecycle_value is Dictionary and lifecycle_value.get("failure", null) is Dictionary:
				code = str((lifecycle_value.failure as Dictionary).get("code", ""))
			if expected.get("failure_code", null) == null or code != str(expected.failure_code):
				_fail("generation_%s_%s_%s" % [classification, consumer.last_error, code])
				return
			var failure_diagnostic: Dictionary = diagnostics.build_failure(request, lifecycle_value)
			if failure_diagnostic.is_empty() or not _diagnostic_binding(entry, failure_diagnostic): return
			continue
		if expected.get("failure_code", null) != null or str(bundle.get("semantic_hash", "")) != str(expected.get("semantic_hash", "")):
			_fail("semantic_%s" % classification)
			return
		var trace: Dictionary = bundle.get("trace", {})
		if trace.get("fallback", null) != expected.get("fallback_id", null):
			_fail("fallback_%s" % classification)
			return
		var trace_code: Variant = expected.get("trace_code", null)
		if trace_code != null and not _trace_has(trace, str(trace_code)):
			_fail("trace_%s_%s" % [classification, str(trace_code)])
			return
		if classification == "approved_candidate" and (trace.get("fallback", null) != null or trace_code != null):
			_fail("approved_outcome")
			return
		if classification == "failure_seed" and trace_code == null:
			_fail("failure_seed_evidence")
			return
		if classification == "authored_fallback" and (trace.get("fallback", null) == null or trace_code != "site:selected_fallback"):
			_fail("authored_fallback_evidence")
			return
		var document: Dictionary = diagnostics.build_success(bundle, build, runtime, caps)
		if document.is_empty() or not _diagnostic_binding(entry, document): return
	if seen.size() != CLASSIFICATIONS.size():
		_fail("classification_coverage")
		return
	print(PREFIX + " PASS entries=3 classifications=3 diagnostics=true live=true")
	quit(0)

func _diagnostic_binding(entry: Dictionary, document: Dictionary) -> bool:
	var source: Dictionary = entry.get("source_diagnostic", {})
	var expected_identity: String = str(source.get("identity_hash", ""))
	if str(document.get("identity_hash", "")) != expected_identity:
		_fail("diagnostic_identity_%s_expected_%s_actual_%s_capture_%s" % [str(entry.classification), expected_identity, str(document.get("identity_hash", "")), str(document.get("capture_hash", ""))])
		return false
	if not _hex(str(source.get("capture_hash", "")), 64):
		_fail("diagnostic_capture_%s" % str(entry.classification))
		return false
	if str(entry.candidate_id) != _sha256(str(entry.classification) + ":" + expected_identity):
		_fail("candidate_binding_%s" % str(entry.classification))
		return false
	return true

func _provenance_matches(provenance: Dictionary, build: Dictionary) -> bool:
	return str(provenance.get("tool_version", "")) == "seed-lab-1" \
			and int(provenance.get("generator_version", -1)) == int(build.get("generator_version", -2)) \
			and str(provenance.get("content_manifest_hash", "")) == str(build.get("content_manifest_hash", "")) \
			and str(provenance.get("rust_source_commit", "")) == str(build.get("rust_source_commit", "")) \
			and str(provenance.get("build_target", "")) == str(build.get("target", "")) \
			and build.get("artifact", null) is Dictionary \
			and str(provenance.get("artifact_sha256", "")) == str((build.artifact as Dictionary).get("sha256", ""))

func _integer_request(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	var request: Dictionary = (value as Dictionary).duplicate(true)
	request.world_seed = int(request.world_seed)
	request.generator_version = int(request.generator_version)
	request.site.x = int(request.site.x)
	request.site.y = int(request.site.y)
	request.site.loot_richness_bp = int(request.site.loot_richness_bp)
	if request.site.intactness_override_bp != null: request.site.intactness_override_bp = int(request.site.intactness_override_bp)
	request.presentation.seed = int(request.presentation.seed)
	for signal_value: Variant in request.player_model.signals:
		if signal_value is Dictionary: (signal_value as Dictionary).value_bp = int((signal_value as Dictionary).value_bp)
	return request

func _trace_has(trace: Dictionary, code: String) -> bool:
	for field: String in ["candidate_decisions", "failed_constraints", "repairs", "retries"]:
		if trace.get(field, null) is Array and (trace[field] as Array).has(code): return true
	return false

func _hex(value: String, length: int) -> bool:
	if value.length() != length: return false
	for character: String in value:
		if not ((character >= "a" and character <= "f") or (character >= "0" and character <= "9")): return false
	return true

func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

func _fail(marker: String) -> void:
	print(PREFIX + " FAIL " + marker)
	quit(1)
