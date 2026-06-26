extends RefCounted
class_name DamagePipeline

const ArmorResolverScript := preload("res://scripts/systems/armor_resolver.gd")
const STATUS_DEFINITIONS_PATH: String = "res://data/combat/status_effect_definitions.json"

var armor_resolver = ArmorResolverScript.new()
var status_effect_definitions: Dictionary = {}
var processed_hits: int = 0
var total_damage_applied: float = 0.0
var total_noise_generated: float = 0.0
var last_result: Dictionary = {}

func configure(config: Dictionary = {}) -> void:
	armor_resolver.configure(config.get("armor_profile", {}))
	status_effect_definitions = _load_status_defs(str(config.get("status_defs_path", STATUS_DEFINITIONS_PATH)))
	processed_hits = 0
	total_damage_applied = 0.0
	total_noise_generated = 0.0
	last_result = {}

func apply_to_vitals(vitals_state, status_effects_state, armor_profile: Dictionary, event: Dictionary) -> Dictionary:
	var resolved: Dictionary = armor_resolver.resolve_damage(event, armor_profile)
	_apply_vitals_damage(vitals_state, float(resolved.get("final_damage", 0.0)))
	_apply_status(status_effects_state, str(event.get("status_effect_id", "")), float(event.get("status_duration", -1.0)))
	return _finalize_result(event, resolved)

func apply_to_threat(threat_state, event: Dictionary) -> Dictionary:
	if threat_state == null:
		return {}
	var resolved: Dictionary = armor_resolver.resolve_damage(event, threat_state.armor_profile if "armor_profile" in threat_state else {})
	resolved["stun_seconds"] = maxf(0.0, float(event.get("stun_seconds", 0.0)))
	threat_state.apply_damage(resolved)
	return _finalize_result(event, resolved)

func get_summary() -> Dictionary:
	return {
		"processed_hits": processed_hits,
		"total_damage_applied": total_damage_applied,
		"total_noise_generated": total_noise_generated,
		"last_result": last_result.duplicate(true),
		"armor_resolver": armor_resolver.get_summary(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	processed_hits = int(summary.get("processed_hits", processed_hits))
	total_damage_applied = float(summary.get("total_damage_applied", total_damage_applied))
	total_noise_generated = float(summary.get("total_noise_generated", total_noise_generated))
	last_result = summary.get("last_result", {}) if summary.get("last_result", {}) is Dictionary else {}
	if summary.get("armor_resolver", null) is Dictionary:
		armor_resolver.apply_summary(summary.get("armor_resolver", {}))
	return true

func get_status_lines() -> PackedStringArray:
	return PackedStringArray([
		"Damage: hits=%d total=%.1f" % [processed_hits, total_damage_applied],
		"Noise emitted: %.2f" % total_noise_generated,
	])

func _finalize_result(event: Dictionary, resolved: Dictionary) -> Dictionary:
	processed_hits += 1
	var final_damage: float = float(resolved.get("final_damage", 0.0))
	var noise: float = maxf(0.0, float(event.get("noise", 0.0)))
	total_damage_applied += final_damage
	total_noise_generated += noise
	last_result = resolved.duplicate(true)
	last_result["source_id"] = str(event.get("source_id", ""))
	last_result["status_effect_id"] = str(event.get("status_effect_id", ""))
	last_result["noise"] = noise
	return last_result.duplicate(true)

func _apply_vitals_damage(vitals_state, damage: float) -> void:
	if vitals_state == null or damage <= 0.0:
		return
	vitals_state.health = maxf(0.0, float(vitals_state.health) - damage)

func _apply_status(status_effects_state, effect_id: String, explicit_duration: float) -> void:
	if status_effects_state == null or effect_id.is_empty():
		return
	var effect_def: Dictionary = status_effect_definitions.get(effect_id, {}) if status_effect_definitions.get(effect_id, {}) is Dictionary else {}
	var duration: float = explicit_duration if explicit_duration > 0.0 else float(effect_def.get("duration", 0.0))
	var stacks: int = int(effect_def.get("stacks", 1))
	if duration > 0.0:
		status_effects_state.add_effect(effect_id, duration, stacks)

func _load_status_defs(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
