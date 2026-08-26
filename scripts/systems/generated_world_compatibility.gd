extends RefCounted
class_name GeneratedWorldCompatibility

const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const Site := preload("res://scripts/systems/generated_world_site_identity.gd")
const Delta := preload("res://scripts/systems/procgen_mutation_delta.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")
var current_platform: Variant = 1
var current_content_hash: Variant = ""
var current_schema_map: Variant = {}
var bundle_provider: Object = null
var applier: Object = null

func configure(platform: Variant, content_hash: Variant, schemas: Variant, provider: Object, mutation_applier: Object) -> void:
	current_platform = platform; current_content_hash = content_hash; current_schema_map = schemas.duplicate(true) if typeof(schemas) == TYPE_DICTIONARY else {}; bundle_provider = provider; applier = mutation_applier

func evaluate(document: Variant, source_path: String = ""):
	var envelope: Variant = Envelope.from_dict(document)
	if envelope == null: return Result.make(Result.CORRUPT, "malformed_envelope", source_path)
	var summary := {"world_seed": envelope.world_seed, "platform_generator_version": envelope.platform_generator_version, "content_manifest_hash": envelope.content_manifest_hash, "export_schema_map": envelope.export_schema_map.duplicate(true)}
	if typeof(current_platform) != TYPE_INT or current_platform <= 0 or typeof(current_content_hash) != TYPE_STRING or not Site.valid_hash(current_content_hash) or not _valid_schema_map(current_schema_map): return Result.make(Result.IO_FAILURE, "configuration_invalid", source_path, summary)
	if envelope.platform_generator_version != current_platform: return Result.make(Result.NEW_WORLD_REQUIRED, "platform_generator_mismatch", source_path, summary)
	if envelope.content_manifest_hash != current_content_hash: return Result.make(Result.NEW_WORLD_REQUIRED, "content_manifest_mismatch", source_path, summary)
	if envelope.export_schema_map != current_schema_map: return Result.make(Result.NEW_WORLD_REQUIRED, "export_schema_mismatch", source_path, summary)
	if not is_instance_valid(bundle_provider) or not is_instance_valid(applier): return Result.make(Result.IO_FAILURE, "provider_unavailable", source_path, summary)
	if not bundle_provider.has_method("regenerate_site") or not applier.has_method("validate_mutation") or not applier.has_method("apply_batch"): return Result.make(Result.IO_FAILURE, "provider_contract_missing", source_path, summary)
	var pending: Array[Dictionary] = []
	for entry in envelope.sites:
		var identity: Variant = Site.from_dict(entry.identity)
		var delta: Variant = Delta.from_dict(entry.mutation_delta)
		if identity == null or delta == null: return Result.make(Result.CORRUPT, "malformed_site", source_path, summary)
		var bundle: Variant = bundle_provider.regenerate_site(identity)
		var normalized: Variant = _normalize_bundle(bundle)
		if normalized == null: return Result.make(Result.NEW_WORLD_REQUIRED, "bundle_unavailable", source_path, summary)
		if not _identity_matches(normalized.identity, identity): return Result.make(Result.NEW_WORLD_REQUIRED, "bundle_identity_mismatch", source_path, summary)
		if not delta.validate_targets(normalized.targets): return Result.make(Result.NEW_WORLD_REQUIRED, "mutation_target_mismatch", source_path, summary)
		for operation in delta.operations:
			pending.append({"identity": identity, "operation": operation.duplicate(true), "bundle": normalized})
	for item in pending:
		if applier.validate_mutation(item.identity, item.operation, item.bundle) != true: return Result.make(Result.NEW_WORLD_REQUIRED, "mutation_rejected", source_path, summary)
	if applier.apply_batch(pending) != true: return Result.make(Result.IO_FAILURE, "mutation_apply_failed", source_path, summary)
	var result: Variant = Result.make(Result.COMPATIBLE, "validated", source_path, summary)
	result.envelope = envelope
	return result

func _normalize_bundle(bundle: Variant) -> Variant:
	var identity: Variant
	var targets: Variant
	if typeof(bundle) == TYPE_DICTIONARY:
		if bundle.size() != 7 or not bundle.has_all(["site_id", "x", "y", "site_seed", "structural_generator_version", "semantic_hash", "targets"]): return null
		identity = {"site_id": bundle.site_id, "x": bundle.x, "y": bundle.y, "site_seed": bundle.site_seed, "structural_generator_version": bundle.structural_generator_version, "semantic_hash": bundle.semantic_hash}
		targets = bundle.targets
	elif typeof(bundle) == TYPE_OBJECT and is_instance_valid(bundle) and bundle.has_method("procgen_identity") and bundle.has_method("mutation_targets"):
		identity = bundle.procgen_identity(); targets = bundle.mutation_targets()
	else: return null
	if typeof(identity) != TYPE_DICTIONARY or identity.size() != 6 or not identity.has_all(["site_id", "x", "y", "site_seed", "structural_generator_version", "semantic_hash"]): return null
	var site := Site.new()
	if not site.configure(identity.site_id, identity.x, identity.y, identity.site_seed, identity.structural_generator_version, identity.semantic_hash): return null
	var delta := Delta.new()
	if not delta.validate_targets(targets): return null
	return {"identity": site, "targets": targets}

func _identity_matches(actual: Variant, expected: RefCounted) -> bool:
	return actual.site_id == expected.site_id and actual.x == expected.x and actual.y == expected.y and actual.derived_site_seed == expected.derived_site_seed and actual.structural_generator_version == expected.structural_generator_version and actual.base_bundle_semantic_hash == expected.base_bundle_semantic_hash

func _valid_schema_map(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != Envelope.EXPORT_KEYS.size(): return false
	for key in Envelope.EXPORT_KEYS:
		if not value.has(key) or not Site.valid_id(value[key]): return false
	return true
