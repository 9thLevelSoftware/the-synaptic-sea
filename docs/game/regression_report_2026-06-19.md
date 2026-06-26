# Regression Report — 2026-06-19

## Summary

- **Result:** PASS — all smokes green, no failures to classify.
- **Bundle source:** `docs/game/06_validation_plan.md` regression bundle script.
- **Bundle result line:** `SYNAPSE_SEA REGRESSION PASS commands=19 clean_output=true`.
- **Allowlist sweep:** 19/19 smokes emit only the three allowlisted lines
  (`ERROR: Capture not registered: 'gdaimcp'.`,
  `WARNING: ObjectDB instances leaked at exit ...`,
  `WARNING: SaveLoadService: save file rejected by from_dict ...`).
- **Environment:** Godot 4.6.2.stable.official.71f334935 at
  `/Users/christopherwilloughby/.local/bin/godot-4.6.2` invoked headless against
  project root `/Users/christopherwilloughby/the-synapse-sea-of-stars`.
- **Triage owner:** `synapse_sea_review` (per `docs/game/bug_triage.md`).
- **Outcome:** No P0, P1, or P2 defects to record. No follow-up Kanban cards
  required for this run. Stop conditions in the kickoff body are not
  triggered.

## Gate 3 entry reviewer rerun

- **Runner:** `synapse_sea_review` for `t_f4c0c74e` Gate 3 Alpha entry.
- **Result:** PASS — `GATE3_ENTRY_REGRESSION_SUMMARY commands=19 failures=0 p0=0 p1=0 p2=0 unclassified=0`.
- **Bundle result line:** `SYNAPSE_SEA REGRESSION PASS commands=19 clean_output=true`.
- **Log:** `/tmp/synapse_sea_gate3_entry_20260620T001642Z/regression_bundle.log`.
- **Classification:** zero failures, zero P0, zero P1, zero P2, zero unclassified `ERROR:`/`WARNING:` lines.
- **Follow-up cards:** none required.

## Acceptance criteria check

- [x] All 17 smokes executed (19 actually executed — see "Count note" below).
- [x] Each failure classified with severity — N/A, zero failures.
- [x] P0/P1 items have Kanban cards — N/A, zero P0/P1 items.
- [x] Regression report artifact saved — this file.

## Count note (17 vs 19)

The task body specifies 17 smokes (8 Gate 1 + 9 Gate 2). The current
regression bundle in `docs/game/06_validation_plan.md` has 19 commands because
two Gate 2 smokes were added by later hardening/fix cards after the
"17 (8+9)" framing was written:

- `golden_fire_zone_source_marker_smoke.gd` was added by `t_480a1087`
  (Harden fire smoke to reject critical-path fallback, 2026-06-19) and is
  reviewed under REQ-010 (t_d357d336).
- `req012_autosave_sequence_smoke.gd` was added by `t_4d1bd5ab`
  (Fix REQ-012 auto-save snapshot sequence, 2026-06-19) as a permanent
  regression for the auto-save ordering bug.

Both additions are listed under REQ-010 and REQ-012 in
`docs/game/06_validation_plan.md`'s "Future validation additions" checklist.
The "17 (8+9)" framing is therefore stale by exactly these two additional
Gate 2 smokes. This report classifies all 19 by gate below so the
Gate 3 reviewer can see both the original 8+9 and the current 8+11 split.

## Smoke-by-smoke results

### Gate 1 (8 smokes — all PASS)

| # | Smoke | Pass marker observed | Gate 1 role | Severity if fail |
|---|---|---|---|---|
| 1 | `route_control_state_smoke.gd` | `ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true` | REQ-001 model — route gates as runtime blockers | P0 |
| 2 | `main_playable_slice_route_control_smoke.gd` | `MAIN PLAYABLE ROUTE CONTROL PASS gates=1 opened=1 blockers=0 extraction=true` | REQ-001/002/003 scene — gates open on power restore, extraction unlocks on reactor | P0 |
| 3 | `oxygen_state_smoke.gd` | `OXYGEN STATE PASS oxygen=100.0 breach_open=false breach_sealed=true passability_blocked=false recovery_threshold=30.0` | REQ-006 model — hazard pressure loop on oxygen breach | P0 |
| 4 | `main_playable_slice_hazard_smoke.gd` | `MAIN PLAYABLE HAZARD PASS oxygen=0.035 breach_open=false breach_sealed=true passability_blocked=false drain_consumed=7.23992155555558 regen_recovered=6.47986779629618` | REQ-006 scene — main-scene hazard smoke | P0 |
| 5 | `main_playable_slice_ship_systems_smoke.gd` | `MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4` | REQ-002/003 scene — ship systems progression | P0 |
| 6 | `main_playable_slice_completion_smoke.gd` | `MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true` | REQ-003 scene — full slice completion | P0 |
| 7 | `main_playable_slice_input_smoke.gd` | `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2` | REQ-005 scene — input loop / interaction path | P0 |
| 8 | `main_playable_slice_readability_smoke.gd` | `MAIN PLAYABLE SLICE READABILITY PASS objective_props=5 blocked=1 ramp=1 entry=1 destination=1 route_cues=4 labels=0` | REQ-005 scene — locked-iso readability harness | P0 |

### Gate 2 (11 smokes — all PASS; original 9 + 2 hardening additions)

| # | Smoke | Pass marker observed | REQ | Severity if fail |
|---|---|---|---|---|
| 9 | `inventory_state_smoke.gd` | `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5` | REQ-007 model | P0 |
| 10 | `main_playable_slice_inventory_smoke.gd` | `MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5` | REQ-007 scene | P0 |
| 11 | `fire_state_smoke.gd` | `FIRE STATE PASS cycles=2 phases=4 passability_switches=4` | REQ-010 model | P0 |
| 12 | `main_playable_slice_fire_smoke.gd` | `MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false` | REQ-010 scene | P0 |
| 13 | `golden_fire_zone_source_marker_smoke.gd` | `GOLDEN FIRE ZONE SOURCE MARKER PASS marker_room=cargo_01 kind=timed_fire breach_room=medbay_01<->reactor_01 target_on_critical_path=false` | REQ-010 hardening (added by `t_480a1087`) | P0 |
| 14 | `main_playable_slice_objective_variation_smoke.gd` | `MAIN PLAYABLE OBJECTIVE VARIATION PASS sequence=2 steps=2 complete=true power_restored=true gates_opened=true` | REQ-011 scene | P0 |
| 15 | `objective_progress_state_smoke.gd` | `OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true` | REQ-011 model | P0 |
| 16 | `objective_progress_hud_label_smoke.gd` | `OBJECTIVE PROGRESS HUD LABEL PASS repair_junction=Repair_junction restore_systems_suppressed=true sequence_3=Download_Logs` | REQ-011 HUD label | P0 |
| 17 | `save_load_service_smoke.gd` | `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6` | REQ-012 model | P0 |
| 18 | `main_playable_slice_save_load_smoke.gd` | `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true` | REQ-012 scene | P0 |
| 19 | `req012_autosave_sequence_smoke.gd` | `REQ012 AUTOSAVE SEQUENCE CHECK PASS live=2 snapshot=2 file=2 has_save=true` | REQ-012 autosave regression (added by `t_4d1bd5ab`) | P0 |

## Severity classification (per `docs/game/bug_triage.md`)

- **P0 failures:** 0
- **P1 failures:** 0
- **P2 failures:** 0
- **Baseline allowlisted noise:** 3 lines × 19 smokes as expected.
  Specifically, the `SaveLoadService: save file rejected by from_dict ...`
  WARNING was emitted once during `save_load_service_smoke.gd` (smoke #17)
  and is the contract test for the rejection path; it is allowlisted in
  `06_validation_plan.md`.
- **Unclassified regressions:** 0

### Default-severity mapping confirmation

Per `docs/game/bug_triage.md` § Regression integration, all 19 smokes are
classified as "core loop regression" — if any of them had emitted a
non-allowlisted `ERROR:`/`WARNING:` line, the bundle would have exited 1
and the line would default to P0. None did.

## Stop conditions check (per task body)

- [x] Not blocked: no P0 failure, so no "workaround required" gate triggers.
- [x] Not blocked: zero P1 failures, well under the "more than 3 P1"
      threshold.

## Reproduction command

The exact bundle that produced this report:

```bash
ROOT=/Users/christopherwilloughby/the-synapse-sea-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
BASELINE_ERROR="^ERROR: Capture not registered: 'gdaimcp'\\.$"
BASELINE_WARNING="^WARNING: ObjectDB instances leaked at exit \\(run with --verbose for details\\)\\.$"
REQ012_WARNING="^WARNING: SaveLoadService: save file rejected by from_dict \\(missing fields or version mismatch\\)$"

run_clean() {
  label="$1"; marker="$2"; shift 2
  echo "=== $label ==="
  OUT=$("$@" 2>&1)
  printf '%s\n' "$OUT"
  printf '%s\n' "$OUT" | grep -q "$marker"
  FILTERED=$(printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' \
    | grep -Ev "$BASELINE_ERROR|$BASELINE_WARNING|$REQ012_WARNING" || true)
  if [ -n "$FILTERED" ]; then
    printf '%s\n' "$FILTERED"
    echo "UNEXPECTED_ERROR_OR_WARNING in $label"; exit 1
  fi
}

run_clean 'route control model smoke'           'ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/route_control_state_smoke.gd
run_clean 'main route control smoke'            'MAIN PLAYABLE ROUTE CONTROL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
run_clean 'oxygen model smoke'                  'OXYGEN STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_state_smoke.gd
run_clean 'inventory model smoke'               'INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_state_smoke.gd
run_clean 'main inventory smoke'                'MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_inventory_smoke.gd
run_clean 'main hazard smoke'                   'MAIN PLAYABLE HAZARD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hazard_smoke.gd
run_clean 'fire model smoke'                    'FIRE STATE PASS cycles=2 phases=4 passability_switches=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_state_smoke.gd
run_clean 'main fire smoke'                     'MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_fire_smoke.gd
run_clean 'golden fire zone source marker'      'GOLDEN FIRE ZONE SOURCE MARKER PASS marker_room=cargo_01' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/golden_fire_zone_source_marker_smoke.gd
run_clean 'ship systems smoke'                  'MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
run_clean 'completion smoke'                    'MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
run_clean 'input smoke'                         'MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
run_clean 'readability smoke'                   'MAIN PLAYABLE SLICE READABILITY PASS objective_props=5 blocked=1 ramp=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
run_clean 'main objective variation smoke'      'MAIN PLAYABLE OBJECTIVE VARIATION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
run_clean 'objective progress state smoke'      'OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_state_smoke.gd
run_clean 'objective progress hud label smoke'  'OBJECTIVE PROGRESS HUD LABEL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_hud_label_smoke.gd
run_clean 'save/load service smoke'             'SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
run_clean 'main save/load smoke'                'MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_save_load_smoke.gd
run_clean 'REQ-012 auto-save sequence smoke'    'REQ012 AUTOSAVE SEQUENCE CHECK PASS live=2 snapshot=2 file=2 has_save=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/req012_autosave_sequence_smoke.gd
echo 'SYNAPSE_SEA REGRESSION PASS commands=19 clean_output=true'
```

## Disposition for downstream `t_f4c0c74e` (KICKOFF: Gate 3 Alpha entry)

- The regression-failure-to-severity mapping in `docs/game/bug_triage.md` has
  no data to act on: every smoke that defaulted to P0-if-failed is currently
  green, so no card was created.
- The "No open P0/P1 blockers in core loop" Gate 3 exit criterion is met on
  the build under review as of 2026-06-19 (run by `@synapse_sea_worker`).
- The bundle count drift (17 vs 19) is the only structural observation; the
  reviewer may want to update the kickoff card body / `08_milestone_gates.md`
  Gate 2 exit language from "8 Gate 1 + 9 Gate 2" to "8 Gate 1 + 11 Gate 2"
  to match the current `06_validation_plan.md`. No code change required.
