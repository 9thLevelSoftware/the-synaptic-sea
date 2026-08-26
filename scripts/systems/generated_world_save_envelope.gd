extends RefCounted
class_name GeneratedWorldSaveEnvelope

const SiteIdentityScript := preload("res://scripts/systems/generated_world_site_identity.gd")
const MutationDeltaScript := preload("res://scripts/systems/procgen_mutation_delta.gd")
const SCHEMA := "generated-world-save-1"
const MAX_SEED := 9007199254740991
const MAX_SITES := 256
const MAX_BYTES := 1048576
const EXPORT_KEYS := ["procgen_request", "procgen_bundle", "world_ir", "site_ir", "gameplay_ir", "presentation_ir", "generation_trace", "adaptive_proposal"]

var world_seed: int = 0
var platform_generator_version: int = 1
var content_manifest_hash: String = ""
var export_schema_map: Dictionary = {}
var sites: Array[Dictionary] = []

static func integer(value: Variant, minimum: int, maximum: int) -> Variant:
	if typeof(value) == TYPE_BOOL or (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT): return null
	if typeof(value) == TYPE_FLOAT and (not is_finite(value) or value != floor(value)): return null
	var number := int(value)
	return number if number >= minimum and number <= maximum else null

func configure(seed: Variant, platform: Variant, content: Variant, schemas: Variant, site_values: Variant) -> bool:
	var world: Variant = integer(seed, 0, MAX_SEED)
	var version: Variant = integer(platform, 1, MAX_SEED)
	if world == null or version == null or not SiteIdentityScript.valid_hash(content) or typeof(schemas) != TYPE_DICTIONARY or typeof(site_values) != TYPE_ARRAY: return false
	if schemas.size() != EXPORT_KEYS.size() or site_values.size() > MAX_SITES: return false
	for key in EXPORT_KEYS:
		if not schemas.has(key) or not SiteIdentityScript.valid_id(schemas[key]): return false
	var identities := {}
	var parsed_sites: Array[Dictionary] = []
	for raw in site_values:
		if typeof(raw) != TYPE_DICTIONARY or raw.size() != 2 or not raw.has("identity") or not raw.has("mutation_delta"): return false
		var identity: Variant = SiteIdentityScript.from_dict(raw.identity)
		var delta: Variant = MutationDeltaScript.from_dict(raw.mutation_delta)
		if identity == null or delta == null or identities.has(identity.site_id) or delta.base_site_id != identity.site_id or delta.base_semantic_hash != identity.base_bundle_semantic_hash: return false
		identities[identity.site_id] = true
		parsed_sites.append({"identity": identity.to_dict(), "mutation_delta": delta.to_dict()})
	world_seed = world; platform_generator_version = version; content_manifest_hash = content; export_schema_map = schemas.duplicate(true); sites = parsed_sites
	return JSON.stringify(to_dict()).to_utf8_buffer().size() <= MAX_BYTES

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA, "world_seed": world_seed, "platform_generator_version": platform_generator_version, "content_manifest_hash": content_manifest_hash, "export_schema_map": export_schema_map.duplicate(true), "sites": sites.duplicate(true)}

static func from_dict(value: Variant):
	if typeof(value) != TYPE_DICTIONARY: return null
	var data: Dictionary = value
	var required := ["schema_version", "world_seed", "platform_generator_version", "content_manifest_hash", "export_schema_map", "sites"]
	for key in required:
		if not data.has(key): return null
	if data.size() != required.size() or data.schema_version != SCHEMA: return null
	var result = load("res://scripts/systems/generated_world_save_envelope.gd").new()
	return result if result.configure(data.world_seed, data.platform_generator_version, data.content_manifest_hash, data.export_schema_map, data.sites) else null
