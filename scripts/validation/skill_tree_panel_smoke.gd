extends SceneTree

## REQ-PM-003 / REQ-PM-010 / ADR-0033 skill-tree panel smoke.
##
## Pure-model test that builds a SkillTreePanel from the on-disk catalog
## and asserts its `get_status_lines()` exposes the expected structure
## for HUD + accessibility rendering.
##
## Also asserts:
##   - SkillTreeState.can_unlock respects prereqs + book requirements.
##   - The skill tree's `unlock()` is idempotent.
##   - get_skill_entries() returns every catalog skill with category +
##     prereq_count + unlocked flag.
##
## Marker: `SKILL TREE PANEL PASS`

const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")

func _initialize() -> void:
	var catalog: Dictionary = PlayerProgressionScript.load_skills_catalog()
	var books: Dictionary = PlayerProgressionScript.load_books_catalog()
	var classes: Dictionary = ClassDefinitionScript.load_all()

	if catalog.size() < 20:
		_fail("skills catalog size %d < 20" % catalog.size())
		return

	var tree = SkillTreeStateScript.new()
	tree.configure(catalog, books)
	if not tree.load_prerequisites():
		_fail("load_prerequisites failed")
		return

	# Every catalog skill is known.
	for sid in catalog:
		if not tree.is_known_skill(sid):
			_fail("skill %s should be known" % sid)
			return

	# welding_mastery requires welding>=5 + advanced_welding_schematic.
	var prog_low = PlayerProgressionScript.new()
	prog_low.configure(classes["engineer"], catalog, books)
	var low: Dictionary = tree.can_unlock("welding_mastery", prog_low)
	if bool(low.get("can", false)):
		_fail("welding_mastery should be locked without prereqs; got %s" % str(low))
		return
	if int(low.get("missing", []).size()) != 2:
		_fail("welding_mastery should have 2 missing prereqs (skill + book); got %d" % int(low.get("missing", []).size()))
		return

	# Bring welding to 5 and read the schematic.
	while prog_low.get_skill_level("welding") < 5:
		prog_low.grant_xp("welding", 1000)
	prog_low.grant_xp_from_book("advanced_welding_schematic")
	var high: Dictionary = tree.can_unlock("welding_mastery", prog_low)
	if not bool(high.get("can", false)):
		_fail("welding_mastery should now be unlockable; missing=%s" % str(high.get("missing", [])))
		return
	if not tree.unlock("welding_mastery"):
		_fail("unlock returned false")
		return
	# Idempotent.
	if tree.unlock("welding_mastery"):
		_fail("second unlock should be no-op")
		return

	# biomatter_diagnostics requires signal_analysis>=4 + biomatter_signal_analysis book.
	var prog_med = PlayerProgressionScript.new()
	prog_med.configure(classes["scientist"], catalog, books)
	while prog_med.get_skill_level("signal_analysis") < 4:
		prog_med.grant_xp("signal_analysis", 1000)
	prog_med.grant_xp_from_book("biomatter_signal_analysis")
	var biomatter_check: Dictionary = tree.can_unlock("biomatter_diagnostics", prog_med)
	if not bool(biomatter_check.get("can", false)):
		_fail("biomatter_diagnostics should be unlockable for scientist with sig_analysis>=4 + book; missing=%s" % str(biomatter_check.get("missing", [])))
		return

	# Panel status lines.
	var SkillTreePanelScript := load("res://scripts/ui/skill_tree_panel.gd")
	if SkillTreePanelScript == null:
		_fail("could not load SkillTreePanel script")
		return
	var tree_panel = SkillTreePanelScript.build_default(prog_med)
	if tree_panel == null:
		_fail("build_default returned null")
		return
	var lines: PackedStringArray = tree_panel.get_status_lines()
	if lines.size() < 5:
		_fail("skill tree panel lines should be >= 5, got %d" % lines.size())
		return
	# Header line + one line per skill (>= 20 lines).
	if lines.size() < catalog.size() + 1:
		_fail("skill tree panel should have 1 header + %d skills = %d lines, got %d" % [
			catalog.size(),
			catalog.size() + 1,
			lines.size(),
		])
		return
	# Every line should be non-empty.
	for line in lines:
		if String(line).is_empty():
			_fail("empty status line in skill tree panel")
			return

	# get_skill_entries returns every catalog skill.
	var entries: Array = tree.get_skill_entries()
	if entries.size() != catalog.size():
		_fail("get_skill_entries=%d expected %d" % [entries.size(), catalog.size()])
		return
	for entry in entries:
		var sid: String = str(entry.get("skill_id", ""))
		if not tree.is_known_skill(sid):
			_fail("entry %s not known" % sid)
			return
		if not entry.has("category") or not entry.has("display_name") or not entry.has("unlocked"):
			_fail("entry %s missing required fields" % sid)
			return

	print("SKILL TREE PANEL PASS skills=%d welding_mastery=true biomatter_diagnostics=true panel_lines=%d" % [
		catalog.size(),
		lines.size(),
	])
	tree_panel.free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("SKILL TREE PANEL FAIL reason=%s" % reason)
	quit(1)