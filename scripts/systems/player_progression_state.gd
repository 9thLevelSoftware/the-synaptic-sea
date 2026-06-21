extends RefCounted
class_name PlayerProgressionState

## Pure player-progression model: skill levels (0..MAX), per-skill XP toward the
## next level, and the skill->category map used to apply class XP multipliers.
## No scene tree, no RNG. Deterministic per XP sequence.

const MAX_SKILL_LEVEL := 10
const DEFAULT_SKILLS_PATH := "res://data/player/skills.json"

var class_id: String = ""
var skills: Dictionary = {}          # skill_id -> int level
var skill_xp: Dictionary = {}        # skill_id -> int xp toward next level
var _xp_multipliers: Dictionary = {} # category -> float (from the class)
var _skill_category: Dictionary = {} # skill_id -> category (from the catalog)

## Loads skills.json into { skill_id -> {category, display_name} }.
static func load_skills_catalog(path: String = DEFAULT_SKILLS_PATH) -> Dictionary:
	var out: Dictionary = {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var skills_variant: Variant = (parsed as Dictionary).get("skills", [])
	if typeof(skills_variant) != TYPE_ARRAY:
		return out
	for entry in (skills_variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sid: String = str((entry as Dictionary).get("skill_id", ""))
		if sid.is_empty():
			continue
		out[sid] = {
			"category": str((entry as Dictionary).get("category", "")),
			"display_name": str((entry as Dictionary).get("display_name", sid)),
		}
	return out

static func xp_for_next_level(level: int) -> int:
	return (level + 1) * 100

## Seeds skills from class_def.starting_skills (every catalog skill present, default 0),
## records skill->category and the class multipliers, resets all XP to 0.
func configure(class_def, skills_catalog: Dictionary) -> void:
	skills.clear()
	skill_xp.clear()
	_skill_category.clear()
	_xp_multipliers = {}
	class_id = ""
	if class_def != null:
		class_id = str(class_def.class_id)
		_xp_multipliers = (class_def.xp_multipliers as Dictionary).duplicate()
	for sid in skills_catalog:
		_skill_category[sid] = str((skills_catalog[sid] as Dictionary).get("category", ""))
		skills[sid] = 0
		skill_xp[sid] = 0
	if class_def != null:
		for sid in (class_def.starting_skills as Dictionary):
			if skills.has(sid):
				skills[sid] = clampi(int(class_def.starting_skills[sid]), 0, MAX_SKILL_LEVEL)

func get_class_id() -> String:
	return class_id

func get_skill_level(skill_id: String) -> int:
	return int(skills.get(skill_id, 0))

## Applies the class category multiplier to `amount`, banks it, and levels the
## skill up on the curve (capped at MAX_SKILL_LEVEL). Returns true if the level
## changed. Unknown skill -> false.
func grant_xp(skill_id: String, amount: int) -> bool:
	if not skills.has(skill_id):
		return false
	var category: String = str(_skill_category.get(skill_id, ""))
	var mult: float = float(_xp_multipliers.get(category, 1.0))
	var effective: int = int(round(float(amount) * mult))
	var level: int = int(skills[skill_id])
	if level >= MAX_SKILL_LEVEL:
		skill_xp[skill_id] = 0
		return false
	skill_xp[skill_id] = int(skill_xp[skill_id]) + effective
	var changed: bool = false
	while level < MAX_SKILL_LEVEL and int(skill_xp[skill_id]) >= xp_for_next_level(level):
		skill_xp[skill_id] = int(skill_xp[skill_id]) - xp_for_next_level(level)
		level += 1
		changed = true
	skills[skill_id] = level
	if level >= MAX_SKILL_LEVEL:
		skill_xp[skill_id] = 0
	return changed

func get_summary() -> Dictionary:
	return {
		"class_id": class_id,
		"skills": skills.duplicate(),
		"skill_xp": skill_xp.duplicate(),
	}

## Restores class_id/skills/skill_xp from a get_summary() dict. Skills/xp are
## overwritten per-key (unknown keys ignored). Returns true if anything changed.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_class: String = str(summary.get("class_id", class_id))
	if new_class != class_id:
		class_id = new_class
		changed = true
	var skills_variant: Variant = summary.get("skills", {})
	if typeof(skills_variant) == TYPE_DICTIONARY:
		for sid in (skills_variant as Dictionary):
			if skills.has(sid):
				var lvl: int = clampi(int((skills_variant as Dictionary)[sid]), 0, MAX_SKILL_LEVEL)
				if lvl != int(skills[sid]):
					skills[sid] = lvl
					changed = true
	var xp_variant: Variant = summary.get("skill_xp", {})
	if typeof(xp_variant) == TYPE_DICTIONARY:
		for sid in (xp_variant as Dictionary):
			if skill_xp.has(sid):
				var xp: int = maxi(0, int((xp_variant as Dictionary)[sid]))
				if xp != int(skill_xp[sid]):
					skill_xp[sid] = xp
					changed = true
	return changed
