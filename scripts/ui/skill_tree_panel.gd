extends Control
class_name SkillTreePanel

## REQ-PM-010 / ADR-0033 skill tree panel UI.
##
## Reads `SkillTreeState` + `PlayerProgressionState`. Renders every skill
## with its level, XP-to-next, category, prerequisite status, and unlock
## state. Provides accessibility-friendly `get_status_lines()` for HUD
## integration and screen-reader fallback.

const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")
const SkillsCatalogPath: String = "res://data/player/skills.json"
const PrereqsPath: String = "res://data/player/skill_tree.json"

var _tree = null
var _progression = null
var _list_label: RichTextLabel = null

func _ready() -> void:
	_list_label = RichTextLabel.new()
	_list_label.name = "SkillTreeList"
	_list_label.bbcode_enabled = true
	_list_label.fit_content = true
	add_child(_list_label)

func set_tree(tree) -> void:
	_tree = tree

func set_progression(prog) -> void:
	_progression = prog

func get_tree_panel():
	return _tree

func get_progression_panel():
	return _progression

## Returns the panel's status text lines. Used by the smoke and the HUD.
func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if _tree == null:
		lines.append("Skill Tree: (uninitialized)")
		return lines
	var entries: Array = _tree.get_skill_entries()
	var unlocked_count: int = _tree.get_unlocked().size()
	lines.append("Skill Tree: %d / %d unlocked" % [unlocked_count, entries.size()])
	for entry in entries:
		var sid: String = str(entry.get("skill_id", ""))
		var display: String = str(entry.get("display_name", sid))
		var cat: String = str(entry.get("category", ""))
		var book: String = str(entry.get("book_prerequisite", ""))
		var is_unlocked: bool = bool(entry.get("unlocked", false))
		var lvl: int = 0
		var xp_to_next: String = ""
		if _progression != null and _progression.has_method("get_skill_level"):
			lvl = int(_progression.get_skill_level(sid))
			if lvl < 10:
				var xp: int = int(_progression.get_skill_xp(sid))
				var needed: int = (lvl + 1) * 100
				xp_to_next = "  xp=%d/%d" % [xp, needed]
			else:
				xp_to_next = "  (max)"
		var marker: String = "[X]" if is_unlocked else "[ ]"
		lines.append("%s %s [%s] L%d%s" % [marker, display, cat, lvl, xp_to_next])
		var prereqs: Array = _tree.get_prerequisites(sid)
		if prereqs.is_empty() and book.is_empty():
			lines.append("    prereq: none")
		else:
			for prereq in prereqs:
				lines.append("    prereq: %s >= %d" % [
					str(prereq.get("skill_id", "")),
					int(prereq.get("min_level", 1)),
				])
			if not book.is_empty():
				lines.append("    prereq: read %s" % book)
	return lines

## Re-renders the BBCode list label with the current tree + progression
## state. Safe to call from a smoke after set_tree / set_progression.
func render() -> void:
	if _list_label == null:
		return
	var lines: PackedStringArray = get_status_lines()
	var bb: String = ""
	for line in lines:
		bb += String(line) + "\n"
	_list_label.text = bb

## Static factory used by the smoke: builds a fully-configured tree +
## progression from disk defaults, returns the panel ready to render.
static func build_default(progression):
	var tree := SkillTreeStateScript.new()
	tree.configure(SkillTreeStateScript.load_skills_catalog(), SkillTreeStateScript.load_books_catalog())
	tree.load_prerequisites()
	var panel = load("res://scripts/ui/skill_tree_panel.gd").new()
	panel.set_tree(tree)
	panel.set_progression(progression)
	return panel