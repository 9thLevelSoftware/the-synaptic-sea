extends RefCounted
class_name GeneratedWorldSaveEnvelope

const SiteIdentityScript := preload("res://scripts/systems/generated_world_site_identity.gd")
const MutationDeltaScript := preload("res://scripts/systems/procgen_mutation_delta.gd")

const SCHEMA := "generated-world-save-1"
const MAX_SITES := 256
const MAX_BYTES := 1048576
const MAX_HASH := 256
const MAX_SEED := 9007199254740991
const MAX_KEYS := 128

var world_seed: int = 0
var platform_generator_version := 3
var content_manifest_hash := ""
var export_schema_map: Dictionary = {}
var sites: Array[Dictionary] = []

func configure(seed: int, platform: Variant, content: String, schemas: Dictionary, site_values: Array) -> bool:
	if seed < 0 or seed > MAX_SEED or typeof(platform) == TYPE_BOOL or (typeof(platform) != TYPE_INT and typeof(platform) != TYPE_FLOAT) or not is_finite(float(platform)) or float(platform) != 3 or not _hash64(content):
		return false
	if schemas.is_empty() or schemas.size() > MAX_KEYS or site_values.size() > MAX_SITES:
		return false
	world_seed = seed; platform_generator_version = platform; content_manifest_hash = content
	export_schema_map = schemas.duplicate(true); sites.clear()
	var ids := {}
	for raw in site_values:
		if typeof(raw) != TYPE_DICTIONARY or raw.size() != 2:
			return false
		var identity = SiteIdentityScript.from_dict(raw.get("identity"))
		var delta = MutationDeltaScript.from_dict(raw.get("mutation_delta"))
		if identity == null or delta == null or ids.has(identity.site_id) or delta.base_site_id != identity.site_id or delta.base_semantic_hash != identity.base_bundle_semantic_hash:
			return false
		ids[identity.site_id] = true
		sites.append({"identity": identity.to_dict(), "mutation_delta": delta.to_dict()})
	return JSON.stringify(to_dict()).to_utf8_buffer().size() <= MAX_BYTES

static func _hash64(v: String) -> bool:
	if v.length() != 64: return false
	for c in v:
		if not c in "0123456789abcdef": return false
	return true

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA, "world_seed": world_seed, "platform_generator_version": platform_generator_version,
		"content_manifest_hash": content_manifest_hash, "export_schema_map": export_schema_map.duplicate(true), "sites": sites.duplicate(true)}

static func from_dict(value: Variant):
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = value
	if str(d.get("schema_version", "")) != SCHEMA or d.size() != 6 or typeof(d.get("sites")) != TYPE_ARRAY or typeof(d.get("export_schema_map")) != TYPE_DICTIONARY:
		return null
	var result = load("res://scripts/systems/generated_world_save_envelope.gd").new()
	if not result.configure(int(d.get("world_seed", -1)), str(d.get("platform_generator_version", "")), str(d.get("content_manifest_hash", "")), d["export_schema_map"], d["sites"]):
		return null
	return result
