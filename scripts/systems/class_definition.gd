extends RefCounted
class_name ClassDefinition

## One player class: starting skill levels and per-category XP multipliers.
## Pure data; loaded from data/player/classes.json.

const DEFAULT_CLASSES_PATH := "res://data/player/classes.json"

var class_id: String = ""
var display_name: String = ""
var description: String = ""
var starting_skills: Dictionary = {}   # skill_id -> int
var xp_multipliers: Dictionary = {}    # category -> float

static func from_dict(d: Dictionary) -> ClassDefinition:
	# Self-reference to our own class_name isn't safe inside the script
	# during initial compile, so we instantiate via load() with a cached
	# reference. The result is a ClassDefinition instance.
	var script: GDScript = load("res://scripts/systems/class_definition.gd")
	var c = script.new()
	c.class_id = str(d.get("class_id", ""))
	c.display_name = str(d.get("name", ""))
	c.description = str(d.get("description", ""))
	var skills_variant: Variant = d.get("starting_skills", {})
	if typeof(skills_variant) == TYPE_DICTIONARY:
		for k in (skills_variant as Dictionary):
			c.starting_skills[str(k)] = int((skills_variant as Dictionary)[k])
	var mult_variant: Variant = d.get("xp_multipliers", {})
	if typeof(mult_variant) == TYPE_DICTIONARY:
		for k in (mult_variant as Dictionary):
			c.xp_multipliers[str(k)] = float((mult_variant as Dictionary)[k])
	return c

## Returns { class_id -> ClassDefinition }. Empty dict on a malformed file.
static func load_all(path: String = DEFAULT_CLASSES_PATH) -> Dictionary:
	var out: Dictionary = {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var classes_variant: Variant = (parsed as Dictionary).get("classes", [])
	if typeof(classes_variant) != TYPE_ARRAY:
		return out
	for entry in (classes_variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var c := from_dict(entry as Dictionary)
		if not c.class_id.is_empty():
			out[c.class_id] = c
	return out

func xp_multiplier(category: String) -> float:
	return float(xp_multipliers.get(category, 1.0))
