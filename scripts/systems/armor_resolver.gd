extends RefCounted
class_name ArmorResolver

const DEFAULT_DURABILITY: float = 0.0
const DEFAULT_WEAR_FACTOR: float = 0.35

var armor_profile: Dictionary = {
	"flat_reduction": {},
	"resistance": {},
	"durability": DEFAULT_DURABILITY,
	"max_durability": DEFAULT_DURABILITY,
	"wear_factor": DEFAULT_WEAR_FACTOR,
}
var last_resolution: Dictionary = {}

func configure(config: Dictionary = {}) -> void:
	armor_profile = _normalize_profile(config)
	last_resolution = {}

func resolve_damage(event: Dictionary, profile_override: Dictionary = {}) -> Dictionary:
	var profile: Dictionary = _normalize_profile(profile_override if not profile_override.is_empty() else armor_profile)
	var damage_type: String = str(event.get("damage_type", "physical"))
	var incoming: float = maxf(0.0, float(event.get("amount", 0.0)))
	var flat: float = maxf(0.0, float((profile.get("flat_reduction", {}) as Dictionary).get(damage_type, 0.0)))
	var resistance: float = clampf(float((profile.get("resistance", {}) as Dictionary).get(damage_type, 0.0)), -0.9, 0.95)
	var after_flat: float = maxf(0.0, incoming - flat)
	var final_damage: float = maxf(0.0, after_flat * (1.0 - resistance))
	var absorbed: float = maxf(0.0, incoming - final_damage)
	var durability: float = maxf(0.0, float(profile.get("durability", 0.0)) - (absorbed * float(profile.get("wear_factor", DEFAULT_WEAR_FACTOR))))
	profile["durability"] = durability
	last_resolution = {
		"damage_type": damage_type,
		"incoming": incoming,
		"flat_reduction": flat,
		"resistance": resistance,
		"absorbed": absorbed,
		"final_damage": final_damage,
		"durability": durability,
		"profile": profile.duplicate(true),
	}
	armor_profile = profile.duplicate(true)
	return last_resolution.duplicate(true)

func get_summary() -> Dictionary:
	return {
		"armor_profile": armor_profile.duplicate(true),
		"last_resolution": last_resolution.duplicate(true),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var profile: Dictionary = _normalize_profile(summary.get("armor_profile", armor_profile))
	if JSON.stringify(profile) != JSON.stringify(armor_profile):
		armor_profile = profile
		changed = true
	var last: Dictionary = summary.get("last_resolution", {}) if summary.get("last_resolution", {}) is Dictionary else {}
	if JSON.stringify(last) != JSON.stringify(last_resolution):
		last_resolution = last.duplicate(true)
		changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Armor durability: %.1f" % float(armor_profile.get("durability", 0.0)))
	if not last_resolution.is_empty():
		lines.append("Last hit: %s %.1f -> %.1f" % [
			str(last_resolution.get("damage_type", "physical")),
			float(last_resolution.get("incoming", 0.0)),
			float(last_resolution.get("final_damage", 0.0)),
		])
	return lines

func _normalize_profile(src: Dictionary) -> Dictionary:
	var flat: Dictionary = src.get("flat_reduction", {}) if src.get("flat_reduction", {}) is Dictionary else {}
	var resist: Dictionary = src.get("resistance", {}) if src.get("resistance", {}) is Dictionary else {}
	return {
		"flat_reduction": flat.duplicate(true),
		"resistance": resist.duplicate(true),
		"durability": maxf(0.0, float(src.get("durability", DEFAULT_DURABILITY))),
		"max_durability": maxf(0.0, float(src.get("max_durability", src.get("durability", DEFAULT_DURABILITY)))),
		"wear_factor": maxf(0.0, float(src.get("wear_factor", DEFAULT_WEAR_FACTOR))),
	}
