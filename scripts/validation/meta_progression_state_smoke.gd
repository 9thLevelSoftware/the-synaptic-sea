extends SceneTree

## REQ-PM-006 / REQ-PM-009 / ADR-0033 meta-progression state smoke.
##
## Pure-model test for MetaProgressionState + UnlockRegistry. Asserts:
##   - meta_currency add / spend / unlock paths
##   - schema-gated apply_summary (older schemas rejected)
##   - run-end payout counters increment correctly
##   - UnlockRegistry trigger-based unlocks + idempotency
##   - Missing / corrupted file defaults to zeroed state
##
## Marker: `META PROGRESSION STATE PASS`

const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const UnlockRegistryScript := preload("res://scripts/systems/unlock_registry.gd")

const TEST_META_PATH := "user://meta_progression_test_state.json"
const TEST_UNLOCK_PATH := "user://unlock_registry_test_state.json"

func _initialize() -> void:
	# Wipe any stale test files.
	if FileAccess.file_exists(TEST_META_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_META_PATH))
	if FileAccess.file_exists(TEST_UNLOCK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_UNLOCK_PATH))

	# --- MetaProgressionState ---
	var meta = MetaProgressionStateScript.new()
	meta.configure({})

	# add_meta_currency / spend_meta_currency gates.
	if not meta.add_meta_currency(100):
		_fail("add_meta_currency(100) should succeed")
		return
	if int(meta.meta_currency) != 100:
		_fail("meta_currency=%d expected 100" % int(meta.meta_currency))
		return
	if meta.spend_meta_currency(50) != true:
		_fail("spend_meta_currency(50) should succeed on 100")
		return
	if int(meta.meta_currency) != 50:
		_fail("after spend meta_currency=%d expected 50" % int(meta.meta_currency))
		return
	if meta.spend_meta_currency(100) != false:
		_fail("spend_meta_currency(100) should fail on 50")
		return

	# Unlock paths.
	if not meta.unlock_class("salvage_captain"):
		_fail("first unlock_class should succeed")
		return
	if meta.unlock_class("salvage_captain"):
		_fail("duplicate unlock_class should be no-op")
		return
	if not meta.unlock_hub_upgrade("hub_storage_basic"):
		_fail("first unlock_hub_upgrade should succeed")
		return
	if not meta.unlock_codex_entry("codex_repair_intro"):
		_fail("first unlock_codex_entry should succeed")
		return
	if int(meta.get_unlock_count()) != 3:
		_fail("get_unlock_count=%d expected 3" % int(meta.get_unlock_count()))
		return

	# Empty class id rejected.
	if meta.unlock_class(""):
		_fail("empty class id should be rejected")
		return

	# --- apply_meta_payout counters ---
	var meta2 = MetaProgressionStateScript.new()
	meta2.configure({})
	var sum: Dictionary = {
		"completed_objectives": 3,
		"skill_levels": {"repair": 5, "welding": 4},
		"discoveries": 2,
		"reason": "completion",
	}
	# 3*10 + repair>=5 (5) + 2*2 = 30 + 5 + 4 = 39.
	var payout: int = int(meta2.apply_meta_payout(sum))
	if payout != 39:
		_fail("payout=%d expected 39" % payout)
		return
	if int(meta2.total_runs_completed) != 1:
		_fail("total_runs_completed=%d expected 1" % int(meta2.total_runs_completed))
		return
	if int(meta2.highest_skill_level_seen) != 5:
		_fail("highest_skill_level_seen=%d expected 5" % int(meta2.highest_skill_level_seen))
		return

	# start_new_run() resets per-run fields, not currency/unlocks.
	meta2.start_new_run()
	if int(meta2.last_payout_currency) != 0:
		_fail("start_new_run should reset last_payout_currency")
		return
	if int(meta2.meta_currency) != 39:
		_fail("start_new_run should NOT reset meta_currency")
		return

	# --- Disk persistence: missing file → load returns false, state stays default. ---
	var meta3 = MetaProgressionStateScript.new()
	meta3.configure({})
	if meta3.load_from_disk(TEST_META_PATH):
		# Should be false because the test path is empty.
		_fail("load_from_disk on missing file should return false")
		return
	if int(meta3.meta_currency) != 0:
		_fail("after failed load, meta_currency should be 0, got %d" % int(meta3.meta_currency))
		return
	if not meta.save_to_disk(TEST_META_PATH):
		_fail("save_to_disk should write the test meta file")
		return
	var meta_disk = MetaProgressionStateScript.new()
	meta_disk.configure({})
	if not meta_disk.load_from_disk(TEST_META_PATH):
		_fail("load_from_disk should round-trip the saved test meta file")
		return
	if int(meta_disk.meta_currency) != int(meta.meta_currency):
		_fail("disk round-trip meta_currency=%d expected %d" % [int(meta_disk.meta_currency), int(meta.meta_currency)])
		return

	# --- UnlockRegistry ---
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
	# Trigger-based unlocks.
	var u1: String = unlock.unlock_for_trigger("scavenge_container", "any")
	if u1.is_empty():
		_fail("unlock_for_trigger(scavenge_container, any) returned empty")
		return
	if not unlock.is_unlocked(u1):
		_fail("unlock %s should be recorded" % u1)
		return
	# A repeated trigger may unlock another catalog row that shares the same
	# trigger pair; if so, it must still record a valid unlock and never repeat
	# the same id.
	var u2: String = unlock.unlock_for_trigger("scavenge_container", "any")
	if not u2.is_empty() and (u2 == u1 or not unlock.is_unlocked(u2)):
		_fail("second trigger should either no-op or unlock a different valid id; got %s" % u2)
		return
	# Round-trip via to_dict / apply_summary.
	var dump: Dictionary = unlock.to_dict()
	var unlock2 = UnlockRegistryScript.new()
	unlock2.configure(catalog_parsed)
	if not unlock2.apply_summary(dump):
		_fail("apply_summary rejected known-good unlock dump")
		return
	if int(unlock2.get_unlock_count()) != int(unlock.get_unlock_count()):
		_fail("unlock count drifted across round-trip: %d != %d" % [
			int(unlock2.get_unlock_count()),
			int(unlock.get_unlock_count()),
		])
		return
	if not unlock.save_to_disk(TEST_UNLOCK_PATH):
		_fail("unlock.save_to_disk should write the test unlock file")
		return
	var unlock_disk = UnlockRegistryScript.new()
	unlock_disk.configure(catalog_parsed)
	if not unlock_disk.load_from_disk(TEST_UNLOCK_PATH):
		_fail("unlock.load_from_disk should round-trip the saved test unlock file")
		return
	# Schema mismatch.
	var tampered: Dictionary = unlock.to_dict()
	tampered["schema"] = "tampered"
	var unlock_bad = UnlockRegistryScript.new()
	unlock_bad.configure(catalog_parsed)
	if unlock_bad.apply_summary(tampered):
		_fail("apply_summary should reject wrong-schema summary")
		return

	# Reset path wipes everything.
	var meta_reset = MetaProgressionStateScript.new()
	meta_reset.configure({})
	meta_reset.meta_currency = 500
	meta_reset.total_runs_completed = 9
	meta_reset.reset_all()
	if int(meta_reset.meta_currency) != 0:
		_fail("reset_all should clear meta_currency")
		return
	if int(meta_reset.total_runs_completed) != 0:
		_fail("reset_all should clear total_runs_completed")
		return

	# --- selected_class_id (Domain 6): default empty, set, persist, reset ---
	var meta_cls = MetaProgressionStateScript.new()
	meta_cls.configure({})
	if meta_cls.get_selected_class() != "":
		_fail("selected_class default should be empty")
		return
	meta_cls.set_selected_class("field_medic")
	if meta_cls.get_selected_class() != "field_medic":
		_fail("set_selected_class did not stick")
		return
	var cls_dump: Dictionary = meta_cls.to_dict()
	var meta_cls2 = MetaProgressionStateScript.new()
	meta_cls2.configure({})
	if not meta_cls2.apply_summary(cls_dump):
		_fail("apply_summary rejected selected_class dump")
		return
	if meta_cls2.get_selected_class() != "field_medic":
		_fail("selected_class did not round-trip through apply_summary")
		return
	meta_cls2.reset_all()
	if meta_cls2.get_selected_class() != "":
		_fail("reset_all should clear selected_class")
		return

	print("META PROGRESSION STATE PASS payout=39 unlocks=true persistence=true reset=true selected_class=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("META PROGRESSION STATE FAIL reason=%s" % reason)
	quit(1)