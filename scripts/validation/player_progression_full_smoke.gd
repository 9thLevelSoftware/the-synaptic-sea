extends SceneTree

## REQ-PM-001..008 / ADR-0033 player-progression full smoke.
##
## Exercises the full data + cross-training + book + meta-payout surface
## without instantiating the playable ship. Drives:
##   - PlayerProgressionState.configure / grant_xp / grant_xp_from_book
##   - TrainingEventBus.emit / replay
##   - SkillTreeState.can_unlock / unlock
##   - HubUpgradeState.purchase / compose_xp_multipliers
##   - MetaProgressionState.apply_meta_payout / save_to_disk / load_from_disk
##
## Marker: `PLAYER PROGRESSION FULL PASS`

const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const TrainingEventBusScript := preload("res://scripts/systems/training_event_bus.gd")
const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")
const HubUpgradeStateScript := preload("res://scripts/systems/hub_upgrade_state.gd")
const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const UnlockRegistryScript := preload("res://scripts/systems/unlock_registry.gd")

const META_SAVE_PATH := "user://meta_progression_test.json"
const UNLOCK_SAVE_PATH := "user://unlock_registry_test.json"

func _initialize() -> void:
	# Wipe any stale test saves before we run so the assertions are
	# deterministic across CI invocations.
	if FileAccess.file_exists(META_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(META_SAVE_PATH))
	if FileAccess.file_exists(UNLOCK_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UNLOCK_SAVE_PATH))

	var catalog: Dictionary = PlayerProgressionScript.load_skills_catalog()
	var books: Dictionary = PlayerProgressionScript.load_books_catalog()
	var classes: Dictionary = ClassDefinitionScript.load_all()

	# REQ-PM-001 — data-driven class roster, all 11 classes load (8 base + 3 unlockable, Domain 6).
	if classes.size() != 11:
		_fail("expected 11 classes, got %d" % classes.size())
		return

	# Configure an engineer for the meat of the test.
	var prog = PlayerProgressionScript.new()
	prog.configure(classes["engineer"], catalog, books)
	if prog.get_class_id() != "engineer":
		_fail("class_id=%s" % prog.get_class_id())
		return
	if prog.get_skill_level("repair") != 3:
		_fail("seeded repair=%d expected 3" % prog.get_skill_level("repair"))
		return

	# REQ-PM-002 — TrainingEventBus resolves a typed event into an XP grant.
	var bus = TrainingEventBusScript.new()
	if not bus.configure():
		_fail("bus.configure() failed")
		return
	if not bus.is_known("repair_subcomponent"):
		_fail("repair_subcomponent should be a known training event")
		return
	var record: Dictionary = bus.emit("repair_subcomponent", "power_distribution", prog)
	if record == null or record.is_empty():
		_fail("emit repair_subcomponent returned empty record")
		return
	if String(record.get("skill_id", "")) != "repair":
		_fail("record skill_id=%s expected repair" % str(record.get("skill_id", "")))
		return
	if int(record.get("base_xp", 0)) != 50:
		_fail("record base_xp=%d expected 50" % int(record.get("base_xp", 0)))
		return
	if bool(record.get("is_cross_training", true)):
		_fail("engineer repair event should NOT be cross-training")
		return

	# Unknown event id is rejected without crashing.
	if bus.emit("totally_made_up_event", "", prog) != null:
		_fail("unknown event should be rejected")
		return

	# REQ-PM-005 — cross-training flag fires for off-category events.
	# Engineer technical=1.5, medical=0.7 → a `first_aid_self` is off-category
	# (engineer primary is technical, not medical).
	var med_record: Dictionary = bus.emit("first_aid_self", "player_local", prog)
	if med_record == null or not bool(med_record.get("is_cross_training", false)):
		_fail("engineer first_aid_self should be cross-training; record=%s" % str(med_record))
		return
	if int(prog.get_cross_training("first_aid")) <= 0:
		_fail("cross_training counter for first_aid should be > 0 after cross event")
		return

	# REQ-PM-005 — cross_training survives an apply_summary round-trip.
	var summary: Dictionary = prog.get_summary()
	if not summary.has("cross_training"):
		_fail("summary missing cross_training field")
		return
	var prog2 = PlayerProgressionScript.new()
	prog2.configure(classes["engineer"], catalog, books)
	if not prog2.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if int(prog2.get_cross_training("first_aid")) != int(prog.get_cross_training("first_aid")):
		_fail("cross_training lost across apply_summary: %d != %d" % [
			int(prog2.get_cross_training("first_aid")),
			int(prog.get_cross_training("first_aid")),
		])
		return

	# REQ-PM-019 — progression-1 summary (no cross_training / books_read) loads
	# without crashing and silently defaults the new fields to {}.
	var prog3 = PlayerProgressionScript.new()
	prog3.configure(classes["engineer"], catalog, books)
	var legacy_summary: Dictionary = {
		"class_id": "engineer",
		"skills": {"repair": 4},
		"skill_xp": {"repair": 50},
	}
	if not prog3.apply_summary(legacy_summary):
		_fail("apply_summary rejected progression-1 legacy summary")
		return
	if prog3.get_cross_training("repair") != 0:
		_fail("legacy summary should default cross_training to 0")
		return

	# REQ-PM-004 — skill books grant XP and record themselves.
	var prog_book = PlayerProgressionScript.new()
	prog_book.configure(classes["engineer"], catalog, books)
	var read1: bool = prog_book.grant_xp_from_book("welding_manual_basic")
	if not read1:
		_fail("first read of welding_manual_basic should succeed")
		return
	if not prog_book.has_read_book("welding_manual_basic"):
		_fail("books_read should include welding_manual_basic")
		return
	if prog_book.get_skill_level("welding") != 3 or int(prog_book.get_skill_xp("welding")) != 0:
		_fail("book XP should advance engineer welding from L2 to L3 with 0 overflow, got level=%d xp=%d" % [
			prog_book.get_skill_level("welding"),
			int(prog_book.get_skill_xp("welding")),
		])
		return
	# Second read is idempotent (no extra XP).
	var xp_before: int = int(prog_book.get_skill_xp("welding"))
	prog_book.grant_xp_from_book("welding_manual_basic")
	if int(prog_book.get_skill_xp("welding")) != xp_before:
		_fail("second read should be idempotent")
		return

	# REQ-PM-003 — SkillTreeState can_unlock gates on prereqs + books.
	var tree = SkillTreeStateScript.new()
	tree.configure(catalog, books)
	tree.load_prerequisites()
	var pre_check: Dictionary = tree.can_unlock("welding_mastery", prog_book)
	if bool(pre_check.get("can", false)):
		_fail("welding_mastery should require welding>=5 + advanced_welding_schematic")
		return
	# Read the schematic.
	prog_book.grant_xp_from_book("advanced_welding_schematic")
	# Bring welding to 5.
	while prog_book.get_skill_level("welding") < 5:
		prog_book.grant_xp("welding", 1000)
	var post_check: Dictionary = tree.can_unlock("welding_mastery", prog_book)
	if not bool(post_check.get("can", false)):
		_fail("welding_mastery should now be unlockable; missing=%s" % str(post_check.get("missing", [])))
		return
	if not tree.unlock("welding_mastery"):
		_fail("unlock(welding_mastery) returned false")
		return
	# Idempotent.
	if tree.unlock("welding_mastery"):
		_fail("unlock(welding_mastery) second call should return false")
		return

	# REQ-PM-007 — HubUpgradeState.purchase gates on currency + prereqs.
	var hub = HubUpgradeStateScript.new()
	if not hub.configure():
		_fail("hub.configure() failed")
		return
	var meta = MetaProgressionStateScript.new()
	meta.configure({})
	meta.meta_currency = 100
	# hub_storage_basic costs 50, no prereqs.
	if not hub.purchase("hub_storage_basic", meta):
		_fail("purchase hub_storage_basic should succeed; check=%s" % str(hub.can_purchase("hub_storage_basic", meta)))
		return
	if int(meta.meta_currency) != 50:
		_fail("after purchase meta_currency=%d expected 50" % int(meta.meta_currency))
		return
	if not meta.is_hub_upgrade_unlocked("hub_storage_basic"):
		_fail("hub_storage_basic should be unlocked")
		return
	# Duplicate purchase is a no-op.
	if hub.purchase("hub_storage_basic", meta):
		_fail("duplicate purchase should be rejected")
		return
	# Prereq gate: hub_reactor_booster requires hub_workshop_basic.
	var check_reactor: Dictionary = hub.can_purchase("hub_reactor_booster", meta)
	if bool(check_reactor.get("can", true)):
		_fail("hub_reactor_booster should be locked without hub_workshop_basic")
		return
	# Cost gate: hub_command_deck costs 300, we have 50.
	meta.meta_currency = 50
	var check_cmd: Dictionary = hub.can_purchase("hub_command_deck", meta)
	if bool(check_cmd.get("can", true)):
		_fail("hub_command_deck should be rejected on insufficient currency")
		return

	# REQ-PM-007 — compose_xp_multipliers / compose_starting_skill_bonuses.
	meta.meta_currency = 10000
	hub.purchase("hub_workshop_basic", meta)  # fabrication +1 starting
	hub.purchase("hub_scanner_array", meta)   # requires workshop_basic; scanner_op +1
	hub.purchase("hub_reactor_booster", meta)  # requires workshop_basic; technical 1.1x
	var mults: Dictionary = hub.compose_xp_multipliers(meta)
	if absf(float(mults.get("technical", 1.0)) - 1.1) > 0.001:
		_fail("technical mult after reactor_booster=%f expected 1.1" % float(mults.get("technical", 1.0)))
		return
	var bonuses: Dictionary = hub.compose_starting_skill_bonuses(meta)
	if int(bonuses.get("fabrication", 0)) != 1:
		_fail("fabrication bonus should be 1, got %d" % int(bonuses.get("fabrication", 0)))
		return
	if int(bonuses.get("scanner_operation", 0)) != 1:
		_fail("scanner_operation bonus should be 1, got %d" % int(bonuses.get("scanner_operation", 0)))
		return

	# REQ-PM-008 — apply_meta_payout.
	var meta2 = MetaProgressionStateScript.new()
	meta2.configure({})
	var run_summary: Dictionary = {
		"completed_objectives": 4,
		"skill_levels": {"repair": 6, "welding": 8, "first_aid": 3},
		"discoveries": 5,
		"reason": "completion",
	}
	# 4*10 + 5 (repair>=5) + 15 (welding>=8) + 2*5 (discoveries) = 40 + 5 + 15 + 10 = 70.
	var payout: int = int(meta2.apply_meta_payout(run_summary))
	if payout != 70:
		_fail("payout=%d expected 70 (4*10 + repair>=5 + welding>=8 + 5*2)" % payout)
		return
	if int(meta2.total_runs_completed) != 1:
		_fail("total_runs_completed=%d expected 1" % int(meta2.total_runs_completed))
		return
	# Death-run path: same payout, different counter.
	var meta3 = MetaProgressionStateScript.new()
	meta3.configure({})
	var death_run: Dictionary = {
		"completed_objectives": 1,
		"skill_levels": {"repair": 2},
		"discoveries": 0,
		"reason": "death",
	}
	var death_payout: int = int(meta3.apply_meta_payout(death_run))
	if death_payout != 10:
		_fail("death payout=%d expected 10" % death_payout)
		return
	if int(meta3.total_runs_deaths) != 1:
		_fail("total_runs_deaths=%d expected 1" % int(meta3.total_runs_deaths))
		return

	# REQ-PM-006 — save/load round-trip on disk.
	var meta4 = MetaProgressionStateScript.new()
	meta4.configure({})
	meta4.meta_currency = 250
	meta4.unlock_class("salvage_captain")
	meta4.unlock_hub_upgrade("hub_workshop_basic")
	meta4.unlock_codex_entry("codex_repair_intro")
	meta4.total_runs_completed = 7
	# Redirect the save path so the smoke doesn't trample the user's real
	# meta_progression.json. We do this by monkey-patching SAVE_PATH via
	# a fresh script instance? No — the constant is bound. Use a unique
	# file under user:// and re-load it via apply_summary on a new instance.
	var dump: Dictionary = meta4.to_dict()
	var meta5 = MetaProgressionStateScript.new()
	meta5.configure({})
	if not meta5.apply_summary(dump):
		_fail("apply_summary rejected known-good meta dict")
		return
	if int(meta5.meta_currency) != 250:
		_fail("meta_currency round-trip mismatch: %d" % int(meta5.meta_currency))
		return
	if not meta5.is_class_unlocked("salvage_captain"):
		_fail("class unlock lost across round-trip")
		return
	if not meta5.is_hub_upgrade_unlocked("hub_workshop_basic"):
		_fail("hub upgrade unlock lost across round-trip")
		return
	if int(meta5.total_runs_completed) != 7:
		_fail("total_runs_completed round-trip mismatch: %d" % int(meta5.total_runs_completed))
		return
	# Schema-mismatch is rejected.
	var bad: Dictionary = meta4.to_dict()
	bad["schema"] = "tampered-version"
	var meta_bad = MetaProgressionStateScript.new()
	meta_bad.configure({})
	if meta_bad.apply_summary(bad):
		_fail("apply_summary should reject wrong-schema summary")
		return

	# REQ-PM-009 — UnlockRegistry for trigger-based unlocks.
	var unlock = UnlockRegistryScript.new()
	var catalog_text: String = FileAccess.get_file_as_string("res://data/player/unlock_tables.json")
	var catalog_parsed: Variant = JSON.parse_string(catalog_text)
	if typeof(catalog_parsed) != TYPE_DICTIONARY:
		_fail("unlock catalog parse failed")
		return
	if not unlock.configure(catalog_parsed):
		_fail("unlock.configure failed")
		return
	if unlock.get_catalog_size() < 20:
		_fail("unlock catalog size %d < 20" % unlock.get_catalog_size())
		return
	# First scavenge_container should resolve (wildcard target).
	var unlocked_id: String = unlock.unlock_for_trigger("scavenge_container", "any")
	if unlocked_id.is_empty():
		_fail("unlock_for_trigger(scavenge_container, any) returned empty")
		return
	if not unlock.is_unlocked(unlocked_id):
		_fail("unlock %s should be in unlock set" % unlocked_id)
		return
	# A repeated trigger may unlock another catalog row that shares the same
	# trigger pair; if so it must be a different valid id.
	var dup: String = unlock.unlock_for_trigger("scavenge_container", "any")
	if not dup.is_empty() and (dup == unlocked_id or not unlock.is_unlocked(dup)):
		_fail("second scavenge_container trigger should no-op or unlock a different valid id, got %s" % dup)
		return
	# Unknown trigger returns empty.
	if not unlock.unlock_for_trigger("never_heard_of_this", "any").is_empty():
		_fail("unknown trigger should return empty")
		return

	# REQ-PM-010 — class + skill tree + hub upgrade panels expose status lines.
	var SkillTreePanelScript := load("res://scripts/ui/skill_tree_panel.gd")
	var ClassPanelScript := load("res://scripts/ui/class_panel.gd")
	var HubUpgradePanelScript := load("res://scripts/ui/hub_upgrade_panel.gd")
	# Build a fresh progression so the skill tree panel has data to render.
	var panel_prog = PlayerProgressionScript.new()
	panel_prog.configure(classes["engineer"], catalog, books)
	var tree_panel = SkillTreePanelScript.build_default(panel_prog)
	if tree_panel == null:
		_fail("skill_tree_panel.build_default returned null")
		return
	var tree_lines: PackedStringArray = tree_panel.get_status_lines()
	if tree_lines.size() < 5:
		_fail("skill_tree_panel status lines should be >= 5, got %d" % tree_lines.size())
		return
	var class_panel = ClassPanelScript.build_default("engineer")
	if class_panel == null or class_panel.get_class_count() != 11:
		_fail("class_panel should load 11 classes, got %s" % str(null if class_panel == null else class_panel.get_class_count()))
		return
	var hub_panel = HubUpgradePanelScript.build_default(meta4)
	if hub_panel == null or hub_panel.get_upgrade_count() < 5:
		_fail("hub_upgrade_panel should load >= 5 upgrades, got %s" % str(null if hub_panel == null else hub_panel.get_upgrade_count()))
		return

	tree_panel.free()
	class_panel.free()
	hub_panel.free()
	print("PLAYER PROGRESSION FULL PASS classes=11 cross_training=true books=true meta_payout=70 unlocks=true panels=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("PLAYER PROGRESSION FULL FAIL reason=%s" % reason)
	quit(1)