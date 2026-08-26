extends RefCounted
class_name ProcgenPromotionStore

const ROOT: String = "user://procgen/promotions/"
const CLASSIFICATIONS: Array[String] = ["approved_candidate", "failure_seed", "authored_fallback"]
const MAX_BYTES: int = 65536
const MAX_ITEMS: int = 64
const MAX_DEPTH: int = 12
const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
var last_error: String = ""

func save_pending(candidate: Dictionary) -> Dictionary:
	last_error = ""
	if not validate(candidate): return {"saved": false, "error": last_error}
	var id: String = str(candidate.candidate_id)
	var path := ROOT + id + ".json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var encoded := JSON.stringify(candidate)
	if encoded.to_utf8_buffer().size() > MAX_BYTES: return _fail("bytes")
	if FileAccess.file_exists(path):
		if FileAccess.get_file_as_string(path) == encoded: return {"saved": true, "idempotent": true, "path": path}
		return _fail("conflict")
	var temp_path: String = path + ".%d.tmp" % Time.get_ticks_usec()
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null: return _fail("open")
	file.store_string(encoded)
	file.close()
	if not FileAccess.file_exists(temp_path) or FileAccess.get_file_as_string(temp_path) != encoded:
		_remove_known_temp(temp_path)
		return _fail("readback")
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if rename_error != OK:
		_remove_known_temp(temp_path)
		if FileAccess.file_exists(path):
			if FileAccess.get_file_as_string(path) == encoded: return {"saved": true, "idempotent": true, "path": path}
			return _fail("conflict")
		return _fail("rename")
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path) != encoded: return _fail("readback")
	return {"saved": true, "idempotent": false, "path": path}

func validate(candidate: Dictionary, accept_json_numbers: bool = false) -> bool:
	last_error = ""
	var keys := ["schema_version", "candidate_id", "classification", "request", "expected", "source_diagnostic", "provenance"]
	if candidate.size() != keys.size(): return _reject("keys")
	for key: String in keys:
		if not candidate.has(key): return _reject("keys")
	if str(candidate.schema_version) != "procgen-promotion-candidate-1": return _reject("schema")
	if not _hex(str(candidate.candidate_id), 64): return _reject("candidate_id")
	if not CLASSIFICATIONS.has(str(candidate.classification)): return _reject("classification")
	if not candidate.request is Dictionary or not candidate.expected is Dictionary or not candidate.source_diagnostic is Dictionary or not candidate.provenance is Dictionary: return _reject("shape")
	var consumer: RefCounted = ConsumerScript.new()
	if not consumer._validate_request(candidate.request): return _reject("request:%s" % consumer.last_error)
	if not _integer_request_types(candidate.request, accept_json_numbers): return _reject("request_integer_types")
	if candidate.source_diagnostic.size() != 2 or not candidate.source_diagnostic.has("identity_hash") or not candidate.source_diagnostic.has("capture_hash"): return _reject("source_diagnostic")
	if not _hex(str(candidate.source_diagnostic.identity_hash), 64) or not _hex(str(candidate.source_diagnostic.capture_hash), 64): return _reject("source_hash")
	if str(candidate.candidate_id) != _sha256(str(candidate.classification) + ":" + str(candidate.source_diagnostic.identity_hash)): return _reject("candidate_binding")
	if not _validate_expected(str(candidate.classification), candidate.expected): return false
	if not _validate_provenance(candidate.provenance, accept_json_numbers): return false
	if not _validate_privacy(candidate): return false
	if JSON.stringify(candidate).to_utf8_buffer().size() > MAX_BYTES: return _reject("bytes")
	return true

func read_pending(candidate_id: String) -> Dictionary:
	if not _hex(candidate_id, 64): return {}
	var path := ROOT + candidate_id + ".json"
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary and validate(parsed, true) else {}

func _hex(value: String, length: int) -> bool:
	if value.length() != length or value != value.to_lower(): return false
	for code in value.to_ascii_buffer():
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)): return false
	return true

func _validate_expected(classification: String, expected: Dictionary) -> bool:
	if expected.size() != 4 or not expected.has_all(["semantic_hash", "failure_code", "fallback_id", "trace_code"]): return _reject("expected")
	if expected.semantic_hash != null and not _hex(str(expected.semantic_hash), 64): return _reject("expected_semantic")
	for key: String in ["failure_code", "trace_code"]:
		if expected[key] != null and (not expected[key] is String or not _code(str(expected[key]))): return _reject("expected_%s" % key)
	if expected.fallback_id != null and (not expected.fallback_id is String or not _fallback(str(expected.fallback_id))): return _reject("expected_fallback_id")
	if classification == "approved_candidate":
		return (expected.semantic_hash != null and expected.failure_code == null and expected.fallback_id == null and expected.trace_code == null) or _reject("approved_evidence")
	if classification == "failure_seed":
		return (expected.fallback_id == null and (expected.semantic_hash != null or expected.failure_code != null) and (expected.failure_code != null or expected.trace_code != null)) or _reject("failure_evidence")
	return (expected.semantic_hash != null and expected.failure_code == null and expected.fallback_id != null and expected.trace_code == "site:selected_fallback") or _reject("fallback_evidence")

func _validate_provenance(provenance: Dictionary, accept_json_numbers: bool) -> bool:
	var keys := ["tool_version", "generator_version", "content_manifest_hash", "rust_source_commit", "build_target", "artifact_sha256", "technical_validation_codes"]
	if provenance.size() != keys.size() or not provenance.has_all(keys): return _reject("provenance")
	if provenance.tool_version != "seed-lab-1" or not _integer_type(provenance.generator_version, accept_json_numbers) or int(provenance.generator_version) != 3 \
			or not _hex(str(provenance.content_manifest_hash), 64) or not _hex(str(provenance.rust_source_commit), 40) \
			or not _hex(str(provenance.artifact_sha256), 64): return _reject("provenance_identity")
	var manifest_name: String = "win64.json" if str(provenance.build_target) == "x86_64-pc-windows-msvc" else ("web.json" if str(provenance.build_target) == "wasm32-unknown-unknown" else "")
	if manifest_name.is_empty(): return _reject("provenance_target")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/" + manifest_name))
	if not parsed is Dictionary: return _reject("provenance_manifest")
	var manifest: Dictionary = parsed
	if str(manifest.get("target", "")) != str(provenance.build_target) \
			or int(manifest.get("generator_version", -1)) != int(provenance.generator_version) \
			or str(manifest.get("content_manifest_hash", "")) != str(provenance.content_manifest_hash) \
			or str(manifest.get("rust_source_commit", "")) != str(provenance.rust_source_commit) \
			or not manifest.get("artifact", null) is Dictionary \
			or str((manifest.artifact as Dictionary).get("sha256", "")) != str(provenance.artifact_sha256): return _reject("provenance_stale")
	if not provenance.technical_validation_codes is Array or (provenance.technical_validation_codes as Array).is_empty() \
			or (provenance.technical_validation_codes as Array).size() > MAX_ITEMS: return _reject("provenance_codes")
	var previous := ""
	for value: Variant in provenance.technical_validation_codes:
		if not value is String or not _code(str(value)) or (not previous.is_empty() and previous >= str(value)): return _reject("provenance_codes")
		previous = str(value)
	return true

func _integer_request_types(request: Dictionary, accept_json_numbers: bool) -> bool:
	var site: Dictionary = request.get("site", {})
	var presentation: Dictionary = request.get("presentation", {})
	if not _integer_type(request.get("world_seed", null), accept_json_numbers) or not _integer_type(request.get("generator_version", null), accept_json_numbers) \
			or not _integer_type(site.get("x", null), accept_json_numbers) or not _integer_type(site.get("y", null), accept_json_numbers) \
			or not _integer_type(site.get("loot_richness_bp", null), accept_json_numbers) or not _integer_type(presentation.get("seed", null), accept_json_numbers):
		return false
	if site.get("intactness_override_bp", null) != null and not _integer_type(site.get("intactness_override_bp"), accept_json_numbers): return false
	for signal_value: Variant in (request.get("player_model", {}) as Dictionary).get("signals", []):
		if not signal_value is Dictionary or not _integer_type((signal_value as Dictionary).get("value_bp", null), accept_json_numbers): return false
	return true

func _integer_type(value: Variant, accept_json_numbers: bool) -> bool:
	return value is int or (accept_json_numbers and value is float and is_finite(float(value)) and float(value) == floor(float(value)))

func _validate_privacy(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH: return _reject("depth")
	if value is String: return str(value).to_utf8_buffer().size() <= 128 or _reject("text")
	if value is Array:
		if (value as Array).size() > MAX_ITEMS: return _reject("collection")
		for item: Variant in value:
			if not _validate_privacy(item, depth + 1): return false
	elif value is Dictionary:
		if (value as Dictionary).size() > MAX_ITEMS: return _reject("collection")
		for key: Variant in value:
			if not key is String or str(key).to_utf8_buffer().size() > 128: return _reject("key")
			if ["username", "user_name", "account_id", "machine", "hostname", "path", "filesystem_path", "notes", "model_output", "network", "stack_trace", "personal_data", "device_id"].has(str(key).to_lower()): return _reject("privacy")
			if not _validate_privacy(value[key], depth + 1): return false
	return true

func _code(value: String) -> bool:
	if value.is_empty() or value.to_utf8_buffer().size() > 128: return false
	for character: String in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or ".:_-".contains(character)): return false
	return true

func _fallback(value: String) -> bool:
	if _code(value): return true
	if value.to_utf8_buffer().size() > 128: return false
	var parts: PackedStringArray = value.split("|")
	return parts.size() == 2 and parts[0].begins_with("world:") and parts[1].begins_with("site:") and _code(parts[0]) and _code(parts[1])

func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

func _reject(code: String) -> bool:
	last_error = code
	return false

func _fail(code: String) -> Dictionary:
	last_error = code
	return {"saved": false, "error": code}

func _remove_known_temp(path: String) -> void:
	if path.begins_with(ROOT) and path.ends_with(".tmp") and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
