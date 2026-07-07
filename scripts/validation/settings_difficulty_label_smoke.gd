extends SceneTree
# Tranche 4 (2026-07-06 audit MEDIUM, menu_coordinator.gd:1003): the settings
# menu's difficulty line always rendered "(x1.0)" because it probed a
# nonexistent AccessibilitySettings.get_difficulty_multiplier() behind a
# has_method guard. No single multiplier exists — difficulty is a string id
# whose canonical dial values live in the procgen layer
# (ship_layout_generator._resolve_difficulty: hardened hazard 1.4, deep_dive
# hazard 1.7, standard 1.0). The fix centralizes that mapping as
# DifficultyProfile.for_id() and renders the REAL hazard dial.
#
# Pure-model smoke: MenuCoordinator is constructed but never added to the
# tree (_settings_line touches only settings_state), so no panels build.
#
# Pass marker: SETTINGS DIFFICULTY LABEL PASS standard=x1.0 hardened=x1.4 deep_dive=x1.7 delegation=true

const MenuCoordinatorScript := preload("res://scripts/ui/menu_coordinator.gd")
const DifficultyProfileScript := preload("res://scripts/procgen/difficulty_profile.gd")

const EXPECTED := {
	"standard": "hazard x1.0",
	"hardened": "hazard x1.4",
	"deep_dive": "hazard x1.7",
}

func _initialize() -> void:
	var coord = MenuCoordinatorScript.new()

	for difficulty_id in ["standard", "hardened", "deep_dive"]:
		if not coord.settings_state.set_difficulty(difficulty_id):
			_fail(coord, "set_difficulty(%s) rejected" % difficulty_id)
			return
		var line: String = str(coord._settings_line("difficulty", "Difficulty"))
		if line.find(str(EXPECTED[difficulty_id])) == -1:
			_fail(coord, "difficulty label for '%s' must show the real dial '%s'; got '%s'" % [
				difficulty_id, str(EXPECTED[difficulty_id]), line])
			return
		if line.find(difficulty_id) == -1:
			_fail(coord, "difficulty label lost the difficulty id '%s': '%s'" % [difficulty_id, line])
			return

	# Delegation: for_id must expose the same canonical dials the generator
	# consumes (resolve_dict moved verbatim from _resolve_difficulty).
	var hardened = DifficultyProfileScript.for_id("hardened")
	if float(hardened.hazard_modifier) != 1.4 or float(hardened.loot_quality_modifier) != 0.85 \
			or float(hardened.encounter_density_modifier) != 1.3:
		_fail(coord, "for_id('hardened') dials drifted from the canonical mapping: %s" % str(hardened.to_dict()))
		return
	var deep = DifficultyProfileScript.for_id("deep_dive")
	if float(deep.hazard_modifier) != 1.7 or float(deep.loot_quality_modifier) != 1.1 \
			or float(deep.encounter_density_modifier) != 1.6:
		_fail(coord, "for_id('deep_dive') dials drifted from the canonical mapping: %s" % str(deep.to_dict()))
		return
	# Unknown / empty ids resolve to the standard profile (generator parity).
	if str(DifficultyProfileScript.for_id("nightmare_mode").id) != "standard" \
			or str(DifficultyProfileScript.for_id("").id) != "standard":
		_fail(coord, "unknown/empty difficulty ids must resolve to standard")
		return

	coord.free()
	print("SETTINGS DIFFICULTY LABEL PASS standard=x1.0 hardened=x1.4 deep_dive=x1.7 delegation=true")
	quit(0)

func _fail(coord, reason: String) -> void:
	if coord != null and is_instance_valid(coord):
		coord.free()
	push_error("SETTINGS DIFFICULTY LABEL FAIL reason=%s" % reason)
	quit(1)
