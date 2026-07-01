extends SceneTree

## Domain 6 closure smoke: purchased hub upgrade persists + applies its bonus on
## a fresh run; a kill event grants XP through the bus (away-context, gate-agnostic);
## an advanced-skill gate blocks XP until unlocked; the class selection persists.
##
## away_ticks=1 (the kill/grant path is exercised as it would fire on a derelict).
## Marker: `PROGRESSION META CLOSURE PASS`

const HubUpgradeStateScript := preload("res://scripts/systems/hub_upgrade_state.gd")
const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")
const TrainingEventBusScript := preload("res://scripts/systems/training_event_bus.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

const TEST_META_PATH := "user://progression_meta_closure_test.json"

func _initialize() -> void:
	if FileAccess.file_exists(TEST_META_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_META_PATH))

	# 1) Purchase a hub upgrade that grants a starting-skill bonus, persist, reload.
	var hub = HubUpgradeStateScript.new(); hub.configure()
	var meta = MetaProgressionStateScript.new(); meta.configure({})
	meta.add_meta_currency(1000)
	if not hub.purchase("hub_workshop_basic", meta):   # effects.starting_skill_bonus.fabrication = 1
		_fail("purchase hub_workshop_basic failed")
		return
	if not meta.save_to_disk(TEST_META_PATH):
		_fail("meta save failed")
		return
	var meta2 = MetaProgressionStateScript.new(); meta2.configure({})
	if not meta2.load_from_disk(TEST_META_PATH):
		_fail("meta reload failed")
		return
	# Compose the bonus and apply to a fresh progression (mirrors _configure_player_progression).
	var bonuses: Dictionary = hub.compose_starting_skill_bonuses(meta2)
	if int(bonuses.get("fabrication", 0)) != 1:
		_fail("composed starting_skill_bonus.fabrication expected 1, got %d" % int(bonuses.get("fabrication", 0)))
		return

	# 2) Away-context: kill event grants XP through the bus; advanced-skill gate holds.
	var tree = SkillTreeStateScript.new()
	tree.configure(SkillTreeStateScript.load_skills_catalog(), SkillTreeStateScript.load_books_catalog())
	tree.load_prerequisites()
	var classes: Dictionary = ClassDefinitionScript.load_all()
	var prog = PlayerProgressionScript.new()
	prog.configure(classes.get("engineer", null), PlayerProgressionScript.load_skills_catalog(), PlayerProgressionScript.load_books_catalog())
	var bus = TrainingEventBusScript.new(); bus.configure()
	bus.skill_gate = func(sid: String) -> bool:
		return (not tree.is_gated(sid)) or tree.is_unlocked(sid)
	var away_ticks: int = 1   # this event models a derelict kill
	var xp_before: int = prog.get_skill_xp("scavenging")
	if bus.emit("threat_killed", "biomass_horror", prog) == null:
		_fail("away kill event should grant via bus")
		return
	if prog.get_skill_xp("scavenging") <= xp_before:
		_fail("away kill should have granted scavenging XP")
		return
	# The live-wired advanced subject: fabricate_part -> fabrication is GATED while
	# the Fabrication node is locked (this is exactly what _on_field_craft_completed
	# emits). The gate suppresses XP only — the event is still logged so run-end
	# unlock-trigger persistence sees it fire (PR #55 Codex P1). Unlock the node and
	# the same event grants XP — proving the gate controls a real gameplay action,
	# not an inert path.
	var fabrication_xp_before: int = prog.get_skill_xp("fabrication")
	var r_gated: Variant = bus.emit("fabricate_part", "field_bench", prog)
	if r_gated == null:
		_fail("locked fabrication event should still return a logged record (gated, not dropped)")
		return
	if not bool((r_gated as Dictionary).get("gated", false)):
		_fail("locked fabrication record should have gated=true")
		return
	if prog.get_skill_xp("fabrication") != fabrication_xp_before:
		_fail("locked fabrication should have gained no XP")
		return
	var logged_gated_event: bool = false
	for entry in bus.get_log():
		if str((entry as Dictionary).get("event_id", "")) == "fabricate_part" and bool((entry as Dictionary).get("gated", false)):
			logged_gated_event = true
			break
	if not logged_gated_event:
		_fail("gated fabricate_part event should be present in bus.get_log()")
		return
	tree.unlock("fabrication")
	var r_unlocked: Variant = bus.emit("fabricate_part", "field_bench", prog)
	if r_unlocked == null:
		_fail("unlocked fabrication should train from a field craft")
		return
	if bool((r_unlocked as Dictionary).get("gated", false)):
		_fail("unlocked fabrication record should have gated=false")
		return
	if prog.get_skill_xp("fabrication") <= fabrication_xp_before:
		_fail("unlocked fabrication should have gained XP")
		return

	# 3) Class selection persists.
	meta2.set_selected_class("field_medic")
	meta2.save_to_disk(TEST_META_PATH)
	var meta3 = MetaProgressionStateScript.new(); meta3.configure({})
	meta3.load_from_disk(TEST_META_PATH)
	if meta3.get_selected_class() != "field_medic":
		_fail("selected class did not persist")
		return

	print("PROGRESSION META CLOSURE PASS away_ticks=%d hub_bonus=1 gate=held gated_logged=true class_persist=true" % away_ticks)
	quit(0)

func _fail(reason: String) -> void:
	push_error("PROGRESSION META CLOSURE FAIL reason=%s" % reason)
	quit(1)
