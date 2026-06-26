extends SceneTree

## REQ-RL-003 / REQ-RL-004 achievement state smoke.
##
## Pure-model test that loads the achievement catalog, exercises the
## unlock / is_unlocked / get_unlocked / get_summary paths, asserts the
## catalog rejects unknown ids, asserts idempotent duplicate unlocks,
## and round-trips through `apply_summary`. Also asserts the per-run
## wipe via `start_new_run`.

const AchievementStateScript := preload("res://scripts/systems/achievement_state.gd")
const ROOT_DEFAULT: String = "/Users/christopherwilloughby/the-synaptic-sea"

func _initialize() -> void:
	var root_path: String = OS.get_environment("ROOT")
	if root_path.is_empty():
		root_path = ROOT_DEFAULT
	var catalog_path: String = root_path + "/data/release/achievement_catalog.json"
	if not FileAccess.file_exists(catalog_path):
		_fail("catalog unreadable: %s" % catalog_path)
		return
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	if file == null:
		_fail("catalog open failed: %s" % catalog_path)
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_fail("catalog parse failed: %s" % catalog_path)
		return

	var state := AchievementStateScript.new()
	state.configure(parsed)

	# Catalog must have >= 5 entries (REQ-RL-003).
	var catalog_size: int = state.get_catalog_size()
	if catalog_size < 5:
		_fail("catalog size %d < 5" % catalog_size)
		return

	# Successful unlock.
	var first_id: String = str(state.get_catalog_ids()[0])
	if not state.unlock(first_id):
		_fail("unlock of %s returned false on first call" % first_id)
		return
	if not state.is_unlocked(first_id):
		_fail("is_unlocked should be true after unlock")
		return

	# Idempotent duplicate unlock.
	if state.unlock(first_id):
		_fail("duplicate unlock should return false")
		return

	# Unknown id is rejected (catalog is the only source of truth).
	if state.unlock("totally_made_up_achievement"):
		_fail("unknown id should be rejected")
		return

	# Trigger-based unlock (uses a target that hasn't been unlocked yet).
	# junction_calibrator_used has trigger_event=tool_acquired,
	# trigger_target=junction_calibrator, distinct from first_breath.
	var trigger_unlock: String = state.unlock_for_trigger("tool_acquired", "junction_calibrator")
	if trigger_unlock.is_empty():
		_fail("trigger unlock for tool_acquired/junction_calibrator returned empty")
		return
	if trigger_unlock != "junction_calibrator_used":
		_fail("trigger unlock should resolve to junction_calibrator_used; got %s" % trigger_unlock)
		return
	if not state.is_unlocked(trigger_unlock):
		_fail("trigger unlock %s should be in unlock set" % trigger_unlock)
		return

	# Wildcard trigger target ("any") should resolve to first_repair or
	# first_loot depending on the trigger_event.
	var wildcard_unlock: String = state.unlock_for_trigger("loot_searched", "any")
	if wildcard_unlock.is_empty():
		_fail("wildcard trigger unlock for loot_searched/any returned empty")
		return

	# Trigger with unknown target returns empty.
	if not state.unlock_for_trigger("tool_acquired", "nonexistent_tool").is_empty():
		_fail("trigger with unknown target should return empty")
		return

	# Round-trip through apply_summary.
	var summary: Dictionary = state.get_summary()
	var reloaded := AchievementStateScript.new()
	reloaded.configure(parsed)
	if not reloaded.apply_summary(summary):
		_fail("apply_summary rejected a known-good summary")
		return
	if reloaded.get_unlock_count() != state.get_unlock_count():
		_fail("unlock count drifted across round-trip: %d -> %d" % [state.get_unlock_count(), reloaded.get_unlock_count()])
		return

	# Schema mismatch is rejected.
	var bad := AchievementStateScript.new()
	bad.configure(parsed)
	var tampered: Dictionary = summary.duplicate()
	tampered["schema"] = "tampered-version"
	if bad.apply_summary(tampered):
		_fail("apply_summary should reject a wrong-schema summary")
		return

	# New run wipes the unlock set.
	state.start_new_run("test-run-1")
	if state.get_unlock_count() != 0:
		_fail("start_new_run should wipe the unlock set; got %d unlocks" % state.get_unlock_count())
		return
	if not state.get_run_id().is_empty() and state.get_run_id() != "test-run-1":
		_fail("start_new_run should set run_id; got %s" % state.get_run_id())
		return

	# Final summary marker.
	print("ACHIEVEMENT STATE PASS unlocked=%d catalog=%d unknown_rejected=true round_trip=true" % [
		state.get_unlock_count(),
		catalog_size,
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("ACHIEVEMENT STATE FAIL reason=%s" % reason)
	quit(1)