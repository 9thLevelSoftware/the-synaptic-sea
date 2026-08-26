extends RefCounted
class_name ProcgenLoadResult
const Site := preload("res://scripts/systems/generated_world_site_identity.gd")
const SCHEMA := "procgen-load-result-1"
const COMPATIBLE := "compatible"
const NEW_WORLD_REQUIRED := "new_world_required"
const CORRUPT := "corrupt"
const IO_FAILURE := "io_failure"
const STATUSES := [COMPATIBLE, NEW_WORLD_REQUIRED, CORRUPT, IO_FAILURE]
const REASONS := ["validated","malformed_envelope","configuration_invalid","platform_generator_mismatch","content_manifest_mismatch","export_schema_mismatch","provider_unavailable","provider_contract_missing","malformed_site","bundle_unavailable","bundle_identity_mismatch","mutation_target_mismatch","mutation_rejected","mutation_apply_failed","missing_file","invalid_slot","open_failed","read_failed","json_parse_failed","document_too_large","compatibility_unavailable","malformed_result"]
const EnvelopeKeys := ["procgen_request", "procgen_bundle", "world_ir", "site_ir", "gameplay_ir", "presentation_ir", "generation_trace", "adaptive_proposal"]
const MAX_PATH := 1024
var status: String = CORRUPT
var schema_version: String = SCHEMA
var reason_code: String = "malformed_result"
var preserved_path: String = ""
var identity_summary: Dictionary = {}
var envelope: RefCounted = null

static func make(value: Variant, reason: Variant, path: Variant = "", identity: Variant = {}):
	var result = load("res://scripts/systems/procgen_load_result.gd").new()
	if typeof(value) != TYPE_STRING or not STATUSES.has(value) or typeof(reason) != TYPE_STRING or not REASONS.has(reason) or typeof(path) != TYPE_STRING or path.length() > MAX_PATH or typeof(identity) != TYPE_DICTIONARY or not _valid_summary(identity): return result
	result.status = value; result.reason_code = reason; result.preserved_path = path; result.identity_summary = identity.duplicate(true)
	return result if result.validate() else load("res://scripts/systems/procgen_load_result.gd").new()

static func _valid_summary(value: Dictionary) -> bool:
	if value.is_empty(): return true
	if value.size() != 4 or not value.has_all(["world_seed", "platform_generator_version", "content_manifest_hash", "export_schema_map"]): return false
	var seed = value.world_seed; var version = value.platform_generator_version
	if typeof(seed) != TYPE_INT or seed < 0 or seed > 9007199254740991 or typeof(version) != TYPE_INT or version <= 0 or not Site.valid_hash(value.content_manifest_hash) or typeof(value.export_schema_map) != TYPE_DICTIONARY: return false
	if value.export_schema_map.size() != 8: return false
	for key in EnvelopeKeys:
		if not value.export_schema_map.has(key) or not Site.valid_id(value.export_schema_map[key]): return false
	return true

func validate() -> bool:
	if typeof(schema_version) != TYPE_STRING or typeof(status) != TYPE_STRING or typeof(reason_code) != TYPE_STRING or typeof(preserved_path) != TYPE_STRING or typeof(identity_summary) != TYPE_DICTIONARY: return false
	if schema_version != SCHEMA or status not in STATUSES or reason_code not in REASONS or not _valid_summary(identity_summary) or preserved_path.length() > MAX_PATH: return false
	var compatible_reasons := ["validated"]
	var new_world_reasons := ["platform_generator_mismatch", "content_manifest_mismatch", "export_schema_mismatch", "bundle_unavailable", "bundle_identity_mismatch", "mutation_target_mismatch", "mutation_rejected"]
	var corrupt_reasons := ["malformed_envelope", "malformed_site", "invalid_slot", "json_parse_failed", "document_too_large", "malformed_result"]
	var io_reasons := ["configuration_invalid", "provider_unavailable", "provider_contract_missing", "mutation_apply_failed", "missing_file", "open_failed", "read_failed", "compatibility_unavailable"]
	return (status == COMPATIBLE and reason_code in compatible_reasons) or (status == NEW_WORLD_REQUIRED and reason_code in new_world_reasons) or (status == CORRUPT and reason_code in corrupt_reasons) or (status == IO_FAILURE and reason_code in io_reasons)

func to_dict() -> Dictionary:
	return {"schema_version": schema_version, "status": status, "reason_code": reason_code, "preserved_path": preserved_path, "identity_summary": identity_summary.duplicate(true)}

static func from_dict(value: Variant):
	if typeof(value) != TYPE_DICTIONARY or value.size() != 5 or not value.has_all(["schema_version","status","reason_code","preserved_path","identity_summary"]) or value.schema_version != SCHEMA: return null
	var result = make(value.status, value.reason_code, value.preserved_path, value.identity_summary)
	return result if result.validate() and result.to_dict() == value else null

func is_compatible() -> bool: return status == COMPATIBLE
