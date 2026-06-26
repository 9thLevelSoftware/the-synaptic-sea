# Gate 1 Regression Bundle — 2026-06-19

## Summary

| Field | Value |
|---|---|
| Date | 2026-06-19 (UTC) |
| Run timestamp | 2026-06-19T19:57:06Z |
| Godot | 4.6.2.stable.official.71f334935 at `/Users/christopherwilloughby/.local/bin/godot-4.6.2` |
| Project | `/Users/christopherwilloughby/the-synaptic-sea-of-stars` |
| Bundle source | `docs/game/06_validation_plan.md` (Regression bundle, 8 commands) |
| Pass / fail | **8 / 0** |
| Clean output | **true** (no unfiltered `ERROR:`/`WARNING:` lines) |
| Decision | **PASS** — bundle green, ready for the next Gate 1 evidence step |

**Result line:** `SYNAPTIC_SEA REGRESSION PASS commands=8 clean_output=true`

## Full command

The exact one-shot invocation is the `Regression bundle` block in
`docs/game/06_validation_plan.md` (the `set -euo pipefail` script with
`run_clean` per smoke). The runner used here is a direct port of that script
that also writes a summary and per-smoke RESULT lines; both shapes produce
the same final marker line, so the canonical pass line above is what the
gate references.

Per-smoke commands (8):

```bash
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
ROOT=/Users/christopherwilloughby/the-synaptic-sea-of-stars

$GODOT --headless --path "$ROOT" --script res://scripts/validation/route_control_state_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/oxygen_state_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hazard_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
```

## Per-smoke result table

| # | Smoke script | Expected marker | Result |
|---|---|---|---|
| 1 | `route_control_state_smoke.gd` | `ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true` | PASS |
| 2 | `main_playable_slice_route_control_smoke.gd` | `MAIN PLAYABLE ROUTE CONTROL PASS` | PASS |
| 3 | `oxygen_state_smoke.gd` | `OXYGEN STATE PASS` | PASS |
| 4 | `main_playable_slice_hazard_smoke.gd` | `MAIN PLAYABLE HAZARD PASS` | PASS |
| 5 | `main_playable_slice_ship_systems_smoke.gd` | `MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4` | PASS |
| 6 | `main_playable_slice_completion_smoke.gd` | `MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true` | PASS |
| 7 | `main_playable_slice_input_smoke.gd` | `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2` | PASS |
| 8 | `main_playable_slice_readability_smoke.gd` | `MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1` | PASS |

All eight expected markers were emitted and the post-marker
`^(ERROR|WARNING):` filter (which excludes the two baseline lines from
`docs/game/06_validation_plan.md §Baseline Godot teardown noise`,
`gdaimcp` capture and `ObjectDB instances leaked at exit`) returned zero
unexpected lines.

## Newly observed failures

**None.** No smoke failed, no marker was missing, and no
`ERROR:`/`WARNING:` line appeared outside the documented baseline
allowlist.

## Flaky tests

**None observed.** All eight smokes ran exactly once during this
regression pass; the last-run-object-leak-count artifact was not seen
to vary across runs in this session (each smoke's single run printed
one instance of the baseline `ObjectDB` warning, consistent with the
allowlist note that the leak count is identical across every smoke).
No flake-cooldown or retry was required.

## Are any failures pre-existing or introduced by recent changes?

Not applicable — there are no failures to classify. The two baseline
teardown lines are documented in `06_validation_plan.md` as present in
every smoke on this build, and they were filtered out of the strict
check as the plan specifies.

## Artifacts

- Raw run output: `docs/game/playtests/regression-run-2026-06-19.log`
  (10 KB, 138 lines, full per-smoke stdout/stderr plus per-smoke
  RESULT line and the final summary).
- This summary: `docs/game/playtests/gate-1-regression-2026-06-19.md`.

## Cross-link status vs. the new gate-1 playtest logs

The task body asks for the regression artifact to be cross-linked
**from each new playtest log** under
`docs/game/playtests/gate-1-<YYYY-MM-DD>-<player-pseudonym>.md`.
At the time of this run, that directory contains no new human
gate-1 logs (the protocol, the template, and the
`automated-playtest-protocol.md` are present, plus this regression
artifact and its raw log). The parent task (`t_99dfe5fe`,
"two fresh-player gate-1 playtest logs") was previously blocked on
the headless-worker fabrication concern; the
`docs/game/playtests/automated-playtest-protocol.md` protocol
introduced since then explicitly accepts an automated
`gate-1-automated-<YYYY-MM-DD>.md` as an alternative primary
evidence source for Gate 1, so a downstream automated playtest run
is a legitimate next step. **This regression artifact is the
required prerequisite** for either path; the cross-link will be
written by whichever log run happens next, with the line:

```
Regression prerequisite: docs/game/playtests/gate-1-regression-2026-06-19.md (PASS, 8/8)
```

## Workspace state

The Synaptic Sea project root is not a git repository
(`git status` returns "fatal: not a git repository"). Per
`AGENTS.md §Operating model`, the no-git ledger is updated via
`docs/` artifacts like this one. No source files were modified
by this regression run — every smoke script is read-only
(`--script` invocation) and no project files were edited.
