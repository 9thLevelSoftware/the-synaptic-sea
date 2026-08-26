extends RefCounted
class_name ProcgenRequestCodec

## Restores JSON integer fields to typed GDScript integers and rejects malformed
## persisted requests. Godot's JSON parser represents numbers as floats; passing
## those directly back to serde makes an otherwise exact request invalid.

const MAX_SAFE_JSON_INTEGER: int = 9007199254740991
const REQUEST_KEYS: Array[String] = [
	"schema_version", "world_seed", "site", "difficulty_id", "player_model",
	"requested_domains", "generator_version", "content_manifest_hash", "presentation",
]
const SITE_KEYS: Array[String] = [
	"site_id", "x", "y", "archetype_id", "kit_id", "intactness_override_bp",
	"cause_of_loss", "loot_richness_bp",
]


static func normalize(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var request: Dictionary = (value as Dictionary).duplicate(true)
	if not _has_exact_keys(request, REQUEST_KEYS):
		return {}
	for key: String in ["schema_version", "difficulty_id", "content_manifest_hash"]:
		if not request.get(key, null) is String or str(request.get(key, "")).is_empty():
			return {}
	if not _is_lower_hex(str(request.content_manifest_hash), 64):
		return {}
	var world_seed: Variant = _integer(request.get("world_seed", null), 0, MAX_SAFE_JSON_INTEGER)
	var generator_version: Variant = _integer(request.get("generator_version", null), 1, 4294967295)
	if world_seed == null or generator_version == null:
		return {}
	request["world_seed"] = world_seed
	request["generator_version"] = generator_version

	var site_variant: Variant = request.get("site", null)
	if not site_variant is Dictionary:
		return {}
	var site: Dictionary = (site_variant as Dictionary).duplicate(true)
	if not _has_exact_keys(site, SITE_KEYS):
		return {}
	for key: String in ["site_id", "archetype_id", "kit_id"]:
		if not site.get(key, null) is String or str(site.get(key, "")).is_empty():
			return {}
	var site_x: Variant = _integer(site.get("x", null), -2147483648, 2147483647)
	var site_y: Variant = _integer(site.get("y", null), -2147483648, 2147483647)
	var richness: Variant = _integer(site.get("loot_richness_bp", null), 0, 30000)
	if site_x == null or site_y == null or richness == null:
		return {}
	site["x"] = site_x
	site["y"] = site_y
	site["loot_richness_bp"] = richness
	if site.get("intactness_override_bp", null) != null:
		var intactness: Variant = _integer(site.intactness_override_bp, 0, 10000)
		if intactness == null:
			return {}
		site["intactness_override_bp"] = intactness
	var cause: Variant = site.get("cause_of_loss", null)
	if cause != null and not cause is String:
		return {}
	request["site"] = site

	var player_variant: Variant = request.get("player_model", null)
	if not player_variant is Dictionary:
		return {}
	var player: Dictionary = (player_variant as Dictionary).duplicate(true)
	if not _has_exact_keys(player, ["schema_version", "signals"]) \
			or not player.get("schema_version", null) is String \
			or not player.get("signals", null) is Array \
			or (player.signals as Array).size() > 4:
		return {}
	var signals: Array = []
	for signal_variant: Variant in player.signals:
		if not signal_variant is Dictionary:
			return {}
		var signal_record: Dictionary = (signal_variant as Dictionary).duplicate(true)
		if not _has_exact_keys(signal_record, ["kind", "value_bp"]) \
				or not signal_record.get("kind", null) is String:
			return {}
		var signal_value: Variant = _integer(signal_record.get("value_bp", null), 0, 10000)
		if signal_value == null:
			return {}
		signal_record["value_bp"] = signal_value
		signals.append(signal_record)
	player["signals"] = signals
	request["player_model"] = player

	var domains_variant: Variant = request.get("requested_domains", null)
	if not domains_variant is Array or (domains_variant as Array).is_empty():
		return {}
	for domain: Variant in domains_variant:
		if not domain is String or str(domain).is_empty():
			return {}

	var presentation_variant: Variant = request.get("presentation", null)
	if not presentation_variant is Dictionary:
		return {}
	var presentation: Dictionary = (presentation_variant as Dictionary).duplicate(true)
	if not _has_exact_keys(presentation, ["seed", "locale"]) \
			or not presentation.get("locale", null) is String \
			or str(presentation.locale).is_empty():
		return {}
	var presentation_seed: Variant = _integer(
		presentation.get("seed", null), 0, MAX_SAFE_JSON_INTEGER)
	if presentation_seed == null:
		return {}
	presentation["seed"] = presentation_seed
	request["presentation"] = presentation
	return request


static func _integer(value: Variant, minimum: int, maximum: int) -> Variant:
	if typeof(value) == TYPE_BOOL \
			or (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT):
		return null
	if typeof(value) == TYPE_FLOAT and (not is_finite(value) or value != floor(value)):
		return null
	var number: int = int(value)
	return number if number >= minimum and number <= maximum else null


static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true


static func _is_lower_hex(value: String, length: int) -> bool:
	if value.length() != length:
		return false
	for character: String in value:
		if not ((character >= "0" and character <= "9") \
				or (character >= "a" and character <= "f")):
			return false
	return true
