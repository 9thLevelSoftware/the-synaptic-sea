extends RefCounted
class_name SkillEffectsResolver

## PKG-D7: pure skill → gameplay effect consumers.
## Every catalog skill maps to live multipliers (work speed, craft quality,
## salvage yield, heal, travel, scan, etc.). No scene tree.

const DEFAULT_PATH: String = "res://data/player/skill_effects.json"
const SKILLS_PATH: String = "res://data/player/skills.json"

var _effects: Dictionary = {}       # skill_id -> effect row
var _class_kits: Dictionary = {}    # class_id -> kit hooks
var _loaded: bool = false


func load_default() -> bool:
	return load_file(DEFAULT_PATH)


func load_file(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var root: Dictionary = parsed
	var eff: Variant = root.get("effects", {})
	var kits: Variant = root.get("class_kit_hooks", {})
	if typeof(eff) != TYPE_DICTIONARY:
		return false
	_effects = (eff as Dictionary).duplicate(true)
	if typeof(kits) == TYPE_DICTIONARY:
		_class_kits = (kits as Dictionary).duplicate(true)
	_loaded = not _effects.is_empty()
	return _loaded


func is_loaded() -> bool:
	return _loaded


func effect_count() -> int:
	return _effects.size()


func has_effect(skill_id: String) -> bool:
	return _effects.has(skill_id)


func get_effect(skill_id: String) -> Dictionary:
	if not _effects.has(skill_id):
		return {}
	return (_effects[skill_id] as Dictionary).duplicate(true)


func consumers_for(skill_id: String) -> PackedStringArray:
	var e: Dictionary = get_effect(skill_id)
	var raw: Variant = e.get("consumers", [])
	var out: PackedStringArray = PackedStringArray()
	if raw is Array:
		for c in raw:
			out.append(str(c))
	return out


## Audit: every skill in skills.json must have a non-empty consumers list.
func audit_catalog_coverage(skills_catalog_path: String = SKILLS_PATH) -> Dictionary:
	var report: Dictionary = {
		"ok": false,
		"catalog_count": 0,
		"covered": 0,
		"missing": [],
		"emit_only": [],
	}
	if not FileAccess.file_exists(skills_catalog_path):
		report["missing"] = ["catalog_file"]
		return report
	var text: String = FileAccess.get_file_as_string(skills_catalog_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return report
	var skills_v: Variant = (parsed as Dictionary).get("skills", [])
	if typeof(skills_v) != TYPE_ARRAY:
		return report
	var missing: Array = []
	var emit_only: Array = []
	var covered: int = 0
	for entry in skills_v:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sid: String = str((entry as Dictionary).get("skill_id", ""))
		if sid.is_empty():
			continue
		report["catalog_count"] = int(report["catalog_count"]) + 1
		if not _effects.has(sid):
			missing.append(sid)
			continue
		var cons: PackedStringArray = consumers_for(sid)
		if cons.is_empty():
			emit_only.append(sid)
			continue
		covered += 1
	report["covered"] = covered
	report["missing"] = missing
	report["emit_only"] = emit_only
	report["ok"] = missing.is_empty() and emit_only.is_empty() and covered >= 22
	return report


static func _level_of(progression, skill_id: String) -> int:
	if progression == null:
		return 0
	if progression.has_method("get_skill_level"):
		return maxi(0, int(progression.call("get_skill_level", skill_id)))
	if typeof(progression.get("skills")) == TYPE_DICTIONARY:
		return maxi(0, int((progression.get("skills") as Dictionary).get(skill_id, 0)))
	return 0


func _per_level(skill_id: String, key: String) -> float:
	var e: Dictionary = get_effect(skill_id)
	return float(e.get(key, 0.0))


## WorkAction work_speed_mult for a verb (and optional primary skill).
func work_speed_multiplier(progression, verb: String = "", primary_skill: String = "", class_id: String = "") -> float:
	var mult: float = 1.0
	var verb_l: String = verb.to_lower()
	for sid in _effects.keys():
		var e: Dictionary = _effects[sid]
		var verbs_v: Variant = e.get("work_verbs", [])
		var matches: bool = false
		if not primary_skill.is_empty() and sid == primary_skill:
			matches = true
		elif verbs_v is Array:
			for v in verbs_v:
				if str(v) == verb_l:
					matches = true
					break
		if not matches:
			continue
		var per: float = float(e.get("work_speed_per_level", 0.0))
		if per <= 0.0:
			continue
		var lvl: int = _level_of(progression, str(sid))
		mult += per * float(lvl)
	mult += _class_flat(class_id, "work_speed_flat")
	return clampf(mult, 0.25, 3.0)


func craft_quality_bonus(progression, skill_id: String = "fabrication", class_id: String = "") -> float:
	var bonus: float = 0.0
	for sid in [skill_id, "fabrication", "welding", "welding_mastery", "cooking", "repair"]:
		var per: float = _per_level(sid, "craft_quality_bonus_per_level")
		if per <= 0.0:
			continue
		bonus += per * float(_level_of(progression, sid))
	bonus += _class_flat(class_id, "craft_quality_flat")
	return clampf(bonus, 0.0, 0.75)


func craft_speed_multiplier(progression, skill_id: String = "fabrication") -> float:
	var mult: float = 1.0
	for sid in [skill_id, "fabrication", "cooking"]:
		var per: float = _per_level(sid, "craft_speed_per_level")
		mult += per * float(_level_of(progression, sid))
	return clampf(mult, 0.5, 2.5)


func salvage_yield_multiplier(progression, class_id: String = "") -> float:
	var mult: float = 1.0
	for sid in ["scavenging", "welding", "welding_mastery"]:
		var per: float = _per_level(sid, "salvage_yield_per_level")
		mult += per * float(_level_of(progression, sid))
	mult += _class_flat(class_id, "salvage_yield_flat")
	return clampf(mult, 0.5, 2.5)


func repair_duration_factor(progression) -> float:
	## Higher skill → shorter duration (divide seconds by factor).
	var factor: float = 1.0
	var per: float = _per_level("repair", "repair_duration_factor_per_level")
	factor += per * float(_level_of(progression, "repair"))
	var per_c: float = _per_level("construction", "module_repair_per_level")
	factor += per_c * float(_level_of(progression, "construction")) * 0.5
	return clampf(factor, 1.0, 3.0)


func heal_multiplier(progression, class_id: String = "") -> float:
	var mult: float = 1.0
	for sid in ["first_aid", "surgery"]:
		var per: float = _per_level(sid, "heal_mult_per_level")
		mult += per * float(_level_of(progression, sid))
	mult += _class_flat(class_id, "heal_mult_flat")
	return clampf(mult, 1.0, 2.5)


func wound_treat_bonus(progression) -> float:
	var bonus: float = 0.0
	for sid in ["first_aid", "surgery"]:
		bonus += _per_level(sid, "wound_treat_bonus_per_level") * float(_level_of(progression, sid))
	return clampf(bonus, 0.0, 0.8)


func travel_fuel_multiplier(progression) -> float:
	## <1.0 saves fuel.
	var save: float = 0.0
	for sid in ["piloting", "astrogation"]:
		save += _per_level(sid, "travel_fuel_save_per_level") * float(_level_of(progression, sid))
	return clampf(1.0 - save, 0.5, 1.0)


func travel_food_multiplier(progression) -> float:
	var save: float = _per_level("resource_management", "travel_food_save_per_level") * float(_level_of(progression, "resource_management"))
	return clampf(1.0 - save, 0.5, 1.0)


func scan_detail_bonus(progression, class_id: String = "") -> float:
	var bonus: float = 0.0
	for sid in ["scanner_operation", "signal_analysis", "diagnostics", "astrogation", "comms", "biomatter_diagnostics"]:
		bonus += _per_level(sid, "scan_detail_bonus_per_level") * float(_level_of(progression, sid))
	bonus += _class_flat(class_id, "scan_detail_flat")
	return clampf(bonus, 0.0, 2.0)


func infection_resist(progression) -> float:
	return clampf(_per_level("quarantine", "infection_resist_per_level") * float(_level_of(progression, "quarantine")), 0.0, 0.8)


func xp_multiplier(progression) -> float:
	return clampf(1.0 + _per_level("leadership", "xp_mult_per_level") * float(_level_of(progression, "leadership")), 1.0, 1.5)


func _class_flat(class_id: String, key: String) -> float:
	if class_id.is_empty():
		return 0.0
	var kit: Variant = _class_kits.get(class_id, _class_kits.get("default", {}))
	if typeof(kit) != TYPE_DICTIONARY:
		return 0.0
	return float((kit as Dictionary).get(key, 0.0))


## Build WorkAction context fragment from progression + verb.
func build_work_context(progression, verb: String, primary_skill: String = "", class_id: String = "") -> Dictionary:
	var skill_level: int = 0
	if not primary_skill.is_empty():
		skill_level = _level_of(progression, primary_skill)
	elif not verb.is_empty():
		# Best matching skill among verb bindings
		for sid in _effects.keys():
			var verbs_v: Variant = (_effects[sid] as Dictionary).get("work_verbs", [])
			if verbs_v is Array:
				for v in verbs_v:
					if str(v) == verb:
						skill_level = maxi(skill_level, _level_of(progression, str(sid)))
	return {
		"skill_level": skill_level,
		"work_speed_mult": work_speed_multiplier(progression, verb, primary_skill, class_id),
		"salvage_yield_mult": salvage_yield_multiplier(progression, class_id),
	}


## Apply craft quality bonus into a 0..1 material quality base.
func apply_craft_quality(base_quality: float, progression, skill_id: String = "fabrication", class_id: String = "") -> float:
	return clampf(base_quality + craft_quality_bonus(progression, skill_id, class_id), 0.0, 1.0)
