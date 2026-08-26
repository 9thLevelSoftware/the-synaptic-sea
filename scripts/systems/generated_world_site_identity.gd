extends RefCounted
class_name GeneratedWorldSiteIdentity

const SCHEMA := "generated-world-site-1"
const MAX_SEED := 9007199254740991
const MAX_ID := 128
var site_id: String = ""
var x: int = 0
var y: int = 0
var derived_site_seed: int = 0
var structural_generator_version: int = 1
var base_bundle_semantic_hash: String = ""

static func _integer(value: Variant, minimum: int, maximum: int) -> Variant:
	if typeof(value) == TYPE_BOOL or (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT): return null
	if typeof(value) == TYPE_FLOAT and (not is_finite(value) or value != floor(value)): return null
	var number := int(value)
	return number if number >= minimum and number <= maximum else null

static func valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > MAX_ID: return false
	for index in value.length():
		var character: String = value.substr(index, 1)
		var allowed: bool = character >= "a" and character <= "z" or character >= "0" and character <= "9" or character == "." or character == "_" or character == "-"
		if not allowed or (index == 0 and not (character >= "a" and character <= "z" or character >= "0" and character <= "9")): return false
	return true

static func valid_hash(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 64: return false
	for character in value:
		if not (character >= "0" and character <= "9" or character >= "a" and character <= "f"): return false
	return true

func configure(identifier: Variant, px: Variant, py: Variant, seed: Variant, structural: Variant, semantic: Variant) -> bool:
	var nx = _integer(px, -2147483648, 2147483647)
	var ny = _integer(py, -2147483648, 2147483647)
	var ns = _integer(seed, 0, MAX_SEED)
	var nv = _integer(structural, 1, MAX_SEED)
	if not valid_id(identifier) or nx == null or ny == null or ns == null or nv == null or not valid_hash(semantic): return false
	site_id = identifier; x = nx; y = ny; derived_site_seed = ns; structural_generator_version = nv; base_bundle_semantic_hash = semantic
	return true

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA, "site_id": site_id, "x": x, "y": y, "derived_site_seed": derived_site_seed, "structural_generator_version": structural_generator_version, "base_bundle_semantic_hash": base_bundle_semantic_hash}

static func from_dict(value: Variant):
	if typeof(value) != TYPE_DICTIONARY: return null
	var data: Dictionary = value
	var expected := ["schema_version", "site_id", "x", "y", "derived_site_seed", "structural_generator_version", "base_bundle_semantic_hash"]
	for key in expected:
		if not data.has(key): return null
	if data.size() != expected.size() or data.schema_version != SCHEMA: return null
	var result = load("res://scripts/systems/generated_world_site_identity.gd").new()
	return result if result.configure(data.site_id, data.x, data.y, data.derived_site_seed, data.structural_generator_version, data.base_bundle_semantic_hash) else null
