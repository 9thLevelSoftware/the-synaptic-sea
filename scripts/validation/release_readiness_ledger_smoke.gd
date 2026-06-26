extends SceneTree

## REQ-RL-007 / REQ-RL-008 / REQ-RL-010 release readiness ledger smoke.
##
## Pure-model test for `ReleaseReadinessLedger` + `CrashReportBundle`.
## Asserts:
##  - the checklist loads with >= 1 check per category (pre_launch,
##    launch_day, post_launch)
##  - local evidence is accepted for known check ids
##  - external evidence requires a non-empty evidence_path
##  - the empty-evidence-path external call returns false (rejected)
##  - the ledger's local-vs-external count summary is correct
##  - the crash bundle captures, flushes to disk, round-trips through
##    `load_from_disk`, and respects the cap
##  - the ledger status lines split rows by category

const ReleaseReadinessLedgerScript := preload("res://scripts/systems/release_readiness_ledger.gd")
const CrashReportBundleScript := preload("res://scripts/systems/crash_report_bundle.gd")
const ROOT_DEFAULT: String = "/Users/christopherwilloughby/the-synaptic-sea"
const TEST_CRASH_PATH: String = "user://release_crash_bundle_test.json"

func _initialize() -> void:
	var root_path: String = OS.get_environment("ROOT")
	if root_path.is_empty():
		root_path = ROOT_DEFAULT
	var checklist_path: String = root_path + "/data/release/release_checklist.json"
	if not FileAccess.file_exists(checklist_path):
		_fail("checklist unreadable: %s" % checklist_path)
		return
	var file := FileAccess.open(checklist_path, FileAccess.READ)
	if file == null:
		_fail("checklist open failed: %s" % checklist_path)
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_fail("checklist parse failed: %s" % checklist_path)
		return

	var ledger := ReleaseReadinessLedgerScript.new()
	ledger.configure(parsed)

	# >= 1 check per category.
	var category_counts: Dictionary = {}
	for cid in ledger.get_check_ids():
		var cat: String = ledger.get_check_category(cid)
		category_counts[cat] = int(category_counts.get(cat, 0)) + 1
	for required in ["pre_launch", "launch_day", "post_launch"]:
		if int(category_counts.get(required, 0)) < 1:
			_fail("checklist missing required category: %s" % required)
			return

	# Local evidence for a known check id succeeds.
	var first_check: String = str(ledger.get_check_ids()[0])
	if not ledger.record_local_evidence(first_check, "pass", "scripts/validation/achievement_state_smoke.gd"):
		_fail("record_local_evidence rejected a known check_id + valid status")
		return

	# Unknown check id is rejected.
	if ledger.record_local_evidence("totally_made_up_check", "pass"):
		_fail("unknown check_id should be rejected")
		return

	# Invalid status is rejected.
	if ledger.record_local_evidence(first_check, "WAT"):
		_fail("invalid status should be rejected")
		return

	# External evidence requires a non-empty evidence_path.
	if ledger.record_external_evidence(first_check, "pass", ""):
		_fail("external evidence with empty evidence_path should be rejected")
		return
	if not ledger.record_external_evidence(first_check, "pass", "build/release/synaptic-sea-of-stars-v0.1.0-web.zip"):
		_fail("external evidence with valid evidence_path should be accepted")
		return

	# Summary asserts the local-vs-external discrimination.
	var summary: Dictionary = ledger.get_summary()
	if int(summary.get("local_count", -1)) != 1:
		_fail("summary local_count should be 1, got %d" % int(summary.get("local_count", -1)))
		return
	if int(summary.get("external_count", -1)) != 1:
		_fail("summary external_count should be 1, got %d" % int(summary.get("external_count", -1)))
		return
	if int(summary.get("row_count", -1)) != 2:
		_fail("summary row_count should be 2, got %d" % int(summary.get("row_count", -1)))
		return

	# Status lines carry the category split.
	var status_lines: PackedStringArray = ledger.get_status_lines()
	var found_pre_launch: bool = false
	var found_launch_day: bool = false
	var found_post_launch: bool = false
	for line in status_lines:
		var text_line: String = String(line)
		if text_line.begins_with("  pre_launch="):
			found_pre_launch = true
		if text_line.begins_with("  launch_day="):
			found_launch_day = true
		if text_line.begins_with("  post_launch="):
			found_post_launch = true
	if not (found_pre_launch and found_launch_day and found_post_launch):
		_fail("status lines missing category split: %s" % "\n".join(status_lines))
		return

	# Crash bundle captures, flushes, round-trips.
	var bundle := CrashReportBundleScript.new()
	bundle.capture("test message 1", {"frame": 1}, ["stack-line-1"])
	bundle.capture("test message 2", {"frame": 2}, ["stack-line-2"])
	if bundle.size() != 2:
		_fail("bundle size should be 2 after two captures, got %d" % bundle.size())
		return
	if not bundle.flush(TEST_CRASH_PATH):
		_fail("bundle flush failed for %s" % TEST_CRASH_PATH)
		return
	var reloaded_bundle := CrashReportBundleScript.new()
	if not reloaded_bundle.load_from_disk(TEST_CRASH_PATH):
		_fail("bundle load_from_disk failed for %s" % TEST_CRASH_PATH)
		return
	if reloaded_bundle.size() != 2:
		_fail("reloaded bundle size should be 2, got %d" % reloaded_bundle.size())
		return

	# Cap behavior.
	var cap_bundle := CrashReportBundleScript.new()
	for i in range(CrashReportBundleScript.MAX_BUNDLE_ENTRIES + 50):
		cap_bundle.capture("entry-%d" % i, {}, [])
	if cap_bundle.size() != CrashReportBundleScript.MAX_BUNDLE_ENTRIES:
		_fail("bundle should cap at %d, got %d" % [CrashReportBundleScript.MAX_BUNDLE_ENTRIES, cap_bundle.size()])
		return

	# Cleanup the test crash file.
	if FileAccess.file_exists(TEST_CRASH_PATH):
		var rm_err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CRASH_PATH))
		if rm_err != OK:
			push_warning("release_readiness_ledger_smoke: failed to remove test crash path, error=%d" % rm_err)

	print("RELEASE READINESS LEDGER PASS rows=%d local=%d external=%d external_evidence_required=true categories_ok=true crash_round_trip=true crash_cap=%d" % [
		int(summary.get("row_count", 0)),
		int(summary.get("local_count", 0)),
		int(summary.get("external_count", 0)),
		CrashReportBundleScript.MAX_BUNDLE_ENTRIES,
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("RELEASE READINESS LEDGER FAIL reason=%s" % reason)
	quit(1)