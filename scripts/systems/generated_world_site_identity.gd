extends RefCounted
class_name GeneratedWorldSiteIdentity

const SCHEMA := "generated-world-site-1"
const MAX_ID := 128
const MAX_HASH := 256
const MAX_SEED := 9007199254740991

var site_id: String = ""
var x: int = 0
var y: int = 0
var derived_site_seed: int = 0
var structural_generator_version: String = ""
var base_bundle_semantic_hash: String = ""

func configure(id: String, px: int, py: int, seed: int, structural: String, semantic: String) -> bool:
	if id.is_empty() or id.length() > MAX_ID or structural.is_empty() or structural.length() > MAX_ID:
		return false
	if semantic.is_empty() or semantic.length() > MAX_HASH or seed < 0 or seed > MAX_SEED:
		return false
	site_id = id; x = px; y = py; derived_site_seed = seed
	structural_generator_version = structural; base_bundle_semantic_hash = semantic
	return true

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "site_id": site_id, "x": x, "y": y, "derived_site_seed": derived_site_seed,
		"structural_generator_version": structural_generator_version, "base_bundle_semantic_hash": base_bundle_semantic_hash}

static func from_dict(value: Variant):
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = value
	var result = load("res://scripts/systems/generated_world_site_identity.gd").new()
	if not result.configure(str(d.get("site_id", "")), int(d.get("x", 0)), int(d.get("y", 0)), int(d.get("derived_site_seed", -1)), str(d.get("structural_generator_version", "")), str(d.get("base_bundle_semantic_hash", ""))):
		return null
	if str(d.get("schema", "")) != SCHEMA or d.size() != 7:
		return null
	return result

func matches(other: RefCounted) -> bool:
	return other != null and to_dict() == other.to_dict()
