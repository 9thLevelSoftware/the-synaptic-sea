# Gate 1 Automated Playtest — 2026-06-19

## Build / workspace state

- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2` (Godot Engine v4.6.2.stable.official.71f334935)
- Project root: `/Users/christopherwilloughby/the-sargasso-of-stars`
- Workspace: no-git (per `docs/game/06_validation_plan.md` ledger guidance)
- Protocol: `docs/game/playtests/automated-playtest-protocol.md`
- Script: `res://scripts/validation/gate1_automated_playtest.gd`
- Regression prerequisite artifact: `docs/game/playtests/gate-1-regression-2026-06-19.md` (PASS, 8/8)
- Date (UTC): 2026-06-19

## Regression bundle prerequisite (from `docs/game/06_validation_plan.md`)

Run before the automated playtest; must pass cleanly under the strict allowlist
(`BASELINE_ERROR` and `BASELINE_WARNING` filter only the two accepted Godot
teardown lines; any other `ERROR:`/`WARNING:` blocks the bundle).

Result: **PASS** — `SARGASSO REGRESSION PASS commands=8 clean_output=true`.

All eight smokes emitted only the two baseline Godot teardown lines
(`ERROR: Capture not registered: 'gdaimcp'.` and
`WARNING: ObjectDB instances leaked at exit ...`) which are explicitly
allowlisted in `docs/game/06_validation_plan.md` § Baseline Godot teardown
noise. No parse errors, GDScript runtime errors, or unexpected validation
markers appeared.

Smoke pass markers observed:

- `ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true`
- `MAIN PLAYABLE ROUTE CONTROL PASS gates=1 opened=1 blockers=0 extraction=true`
- `OXYGEN STATE PASS oxygen=100.0 breach_open=false breach_sealed=true passability_blocked=false recovery_threshold=30.0`
- `MAIN PLAYABLE HAZARD PASS oxygen=0.03240740740741 breach_open=false breach_sealed=true passability_blocked=false drain_consumed=6.78566600000001 regen_recovered=6.59400964814826`
- `MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4`
- `MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true`
- `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2`
- `MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1 entry=1 destination=1 route_cues=4 labels=0`

## Automated playtest output (verbatim)

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org

The Sargasso of Stars coherent proof ship bootstrap loaded.
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
SHIP SYSTEM UPDATED sequence=1 type=recover_supplies power=18 reactor=22 extraction=false route_opened=0 blockers=1
PLAYABLE INTERACTION interaction=objective:01:cargo_01:cargo_supply_cache objective=cargo_01:cargo_supply_cache sequence=1 type=recover_supplies room=cargo_01
SHIP SYSTEM UPDATED sequence=2 type=restore_systems power=72 reactor=22 extraction=false route_opened=1 blockers=0
PLAYABLE INTERACTION interaction=objective:02:maintenance_01:maintenance_breaker_panel objective=maintenance_01:maintenance_breaker_panel sequence=2 type=restore_systems room=maintenance_01
SHIP SYSTEM UPDATED sequence=3 type=download_logs power=72 reactor=22 extraction=false route_opened=1 blockers=0
PLAYABLE INTERACTION interaction=objective:03:medbay_01:medbay_terminal objective=medbay_01:medbay_terminal sequence=3 type=download_logs room=medbay_01
SHIP SYSTEM UPDATED sequence=4 type=stabilize_reactor power=72 reactor=100 extraction=true route_opened=1 blockers=0
PLAYABLE INTERACTION interaction=objective:04:reactor_01:reactor_control_panel objective=reactor_01:reactor_control_panel sequence=4 type=stabilize_reactor room=reactor_01
PLAYABLE SLICE COMPLETE objectives_completed=4
=== GATE 1 AUTOMATED PLAYTEST RESULTS ===
boot_frames=1 total_frames=79
route_readability=2 (arrive_frames=1)
objective_clarity=2 (hud_changes=5)
visible_consequences=2 (gates=1 hud=5 extraction=true)
camera_readability=2 (stuck_events=0)
engagement=2 (objectives=4 total_frames=79)
overall_average=2.00
pass_decision=GO
GATE 1 AUTOMATED PLAYTEST PASS
ERROR: Capture not registered: 'gdaimcp'.
   at: unregister_message_capture (core/debugger/engine_debugger.cpp:62)
WARNING: ObjectDB instances leaked at exit (run with --verbose for details).
     at: cleanup (core/object/object.cpp:2641)
```

The trailing `ERROR:` / `WARNING:` lines are the same baseline Godot teardown
lines allowlisted in `docs/game/06_validation_plan.md` and are emitted by every
headless `--script` run; the automated playtest does not emit any additional
ERROR/WARNING of its own.

## Rubric scores

| Dimension           | Score | Evidence                            | Threshold satisfied? |
|---------------------|-------|-------------------------------------|----------------------|
| route_readability   | 2     | arrive_frames=1 (≤180 frames)       | yes — score-2 band   |
| objective_clarity   | 2     | hud_changes=5 (≥4)                  | yes — score-2 band   |
| visible_consequences| 2     | gates=1, hud=5, extraction=true     | yes — score-2 band (3 of 3 signals) |
| camera_readability  | 2     | stuck_events=0                      | yes — score-2 band   |
| engagement          | 2     | objectives=4, total_frames=79 (<3600) | yes — score-2 band |
| **overall_average** | **2.00** | mean of the five dimensions      | —                    |

All five rubric dimensions are scored. No dimension is 0 or 1; all hit the
score-2 band.

## Pass marker

`GATE 1 AUTOMATED PLAYTEST PASS` was emitted on stdout.

## Decision

**Go** — `pass_decision=GO`.

Per the protocol decision thresholds:

- Overall average 2.00 (≥1.5) ✓
- No zeros on route / objective / consequences / camera / engagement ✓
- No hard-0 failures ✓
- Regression bundle passes cleanly ✓
- Script runs to completion with PASS marker ✓

The automated proxy is sufficient evidence for a Gate 1 Go decision per the
automated protocol's "Automated evidence is sufficient for Gate 1
Go/Recycle/Hold decisions" clause. The human playtest protocol
(`docs/game/playtests/gate-1-playtest-protocol.md`) remains the recommended
follow-up before production release, but it is explicitly out of scope for
this card.

## Bugs / follow-up cards

None. The automated playtest did not surface any RECYCLE/FAIL-triggering
rubric items, so no follow-up Kanban cards are created under this task. The
pass-decision-driven follow-up clause from the card body ("If pass_decision is
RECYCLE or FAIL, create follow-up cards for the lowest-scoring rubric items")
does not apply because the decision is GO and no rubric item is below 2.

## Acceptance checklist (from automated protocol)

- [x] Regression bundle passes on build under test
- [x] `gate1_automated_playtest.gd` runs to completion with PASS marker
- [x] All 5 rubric dimensions scored (0-2)
- [x] Overall average computed (2.00)
- [x] Output artifact saved under `docs/game/playtests/` with build state (this file)
- [x] Decision (Go/Recycle/Hold) recorded in the artifact — **Go**