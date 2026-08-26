extends RefCounted
class_name GeneratedWorldCompatibility

const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const Site := preload("res://scripts/systems/generated_world_site_identity.gd")
const Delta := preload("res://scripts/systems/procgen_mutation_delta.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")

var current_platform: Variant = 3
var current_content_hash := ""
var current_schema_map: Dictionary = {}
var bundle_provider: Object = null
var applier: Object = null

func configure(platform: Variant, content_hash: String, schemas: Dictionary, provider: Object, mutation_applier: Object) -> void:
	current_platform = platform; current_content_hash = content_hash; current_schema_map = schemas.duplicate(true)
	bundle_provider = provider; applier = mutation_applier

func evaluate(document: Variant, source_path := ""):
	var envelope: Variant = Envelope.from_dict(document)
	if envelope == null:
		return Result.make(Result.CORRUPT, "malformed_envelope", source_path)
	var summary: Dictionary = envelope.to_dict()
	if envelope.platform_generator_version != current_platform:
		return Result.make(Result.NEW_WORLD_REQUIRED, "platform_generator_mismatch", source_path, summary)
	if envelope.content_manifest_hash != current_content_hash:
		return Result.make(Result.NEW_WORLD_REQUIRED, "content_manifest_mismatch", source_path, summary)
	if envelope.export_schema_map != current_schema_map:
		return Result.make(Result.NEW_WORLD_REQUIRED, "export_schema_mismatch", source_path, summary)
	if bundle_provider == null or applier == null:
		return Result.make(Result.IO_FAILURE, "provider_unavailable", source_path, summary)
	if not applier.has_method("validate_mutation") or not applier.has_method("apply_mutation"):
		return Result.make(Result.IO_FAILURE, "applier_contract_missing", source_path, summary)
	var pending: Array[Dictionary] = []
	for entry in envelope.sites:
		var identity: Variant = Site.from_dict(entry["identity"])
		var delta: Variant = Delta.from_dict(entry["mutation_delta"])
		var bundle: Variant = _regenerate(identity)
		if bundle == null:
			return Result.make(Result.NEW_WORLD_REQUIRED, "bundle_unavailable", source_path, summary)
		if not _bundle_matches(bundle, identity):
			return Result.make(Result.NEW_WORLD_REQUIRED, "bundle_identity_mismatch", source_path, summary)
		var targets: Array = _bundle_targets(bundle)
		if not delta.validate_targets(targets):
			return Result.make(Result.NEW_WORLD_REQUIRED, "mutation_target_mismatch", source_path, summary)
		pending.append({"identity": identity, "delta": delta, "bundle": bundle})
	for item in pending:
		for operation in item.delta.operations:
			if not applier.validate_mutation(item.identity, operation, item.bundle):
				return Result.make(Result.NEW_WORLD_REQUIRED, "mutation_rejected", source_path, summary)
	for item in pending:
		for operation in item.delta.operations:
			if not applier.apply_mutation(item.identity, operation, item.bundle):
				return Result.make(Result.IO_FAILURE, "mutation_apply_failed", source_path, summary)
	var result: Variant = Result.make(Result.COMPATIBLE, "validated", source_path, summary)
	result.envelope = envelope
	return result

func _regenerate(identity: RefCounted) -> Variant:
	if bundle_provider.has_method("regenerate_site"):
		return bundle_provider.regenerate_site(identity)
	if bundle_provider.has_method("regenerate"):
		return bundle_provider.regenerate(identity)
	return null

func _bundle_matches(bundle: Variant, identity: RefCounted) -> bool:
	if typeof(bundle) == TYPE_DICTIONARY:
		return bundle.size() == 7 and str(bundle.get("site_id", "")) == identity.site_id and typeof(bundle.get("x")) == TYPE_INT and int(bundle.get("x")) == identity.x and typeof(bundle.get("y")) == TYPE_INT and int(bundle.get("y")) == identity.y and typeof(bundle.get("site_seed")) == TYPE_INT and int(bundle.get("site_seed")) == identity.derived_site_seed and typeof(bundle.get("structural_generator_version")) == TYPE_INT and int(bundle.get("structural_generator_version")) == identity.structural_generator_version and str(bundle.get("semantic_hash", "")) == identity.base_bundle_semantic_hash and typeof(bundle.get("targets")) == TYPE_ARRAY
	return bundle != null and bundle.get("site_id") == identity.site_id

func _bundle_targets(bundle: Variant) -> Array:
	if typeof(bundle) == TYPE_DICTIONARY and typeof(bundle.get("targets", [])) == TYPE_ARRAY:
		return bundle["targets"]
	if bundle != null and bundle.has_method("mutation_targets"):
		return bundle.mutation_targets()
	return []
