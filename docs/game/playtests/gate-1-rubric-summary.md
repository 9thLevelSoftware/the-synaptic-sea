# Gate 1 Review Rubric Summary — 2026-06-19

## Purpose

Aggregate the Gate 1 playtest rubric scores across the available fresh-player session logs and compare the per-metric and overall averages against the Gate 1 thresholds defined in `docs/game/playtests/gate-1-playtest-protocol.md`.

## Rubric definition (source)

The rubric is the same five-dimension, 0–2 scale from `docs/game/playtests/gate-1-playtest-protocol.md` § Observation rubric:

| Dimension | Hard criterion? | Score 2 | Score 1 | Score 0 |
|---|---|---|---|---|
| Route readability | Yes | Walks entry → obj 1 in < 90 s; recognizes blocked routes | One or two false starts, no hint | Stuck, wanders, or asks observer for help |
| Objective clarity | Yes | States current and next objective after each | States current but not next objective | Cannot state current objective or completes by accident |
| Visible system consequences | Yes | Notices/comments on ≥ 2 of: gate open, HUD update, extraction unlock | Notices only one, or after prompt | Notices none or thinks run is still broken |
| Camera and readability | No | No camera controls requested; no occlusion issues | Requests camera once or mild occlusion that recovers | Repeatedly blocked by occlusion or leaves play area to read state |
| Engagement and friction | No | Chooses to continue past 12:00 or asks to play again | Reaches extraction at 12:00 ± 90 s with neutral affect | Quits before 12:00 or expresses frustration |

Gate 1 decision thresholds (from protocol):

- **Go**: every rubric item averages **≥ 1.5**, and no player scores **0** on route readability, objective clarity, or visible system consequences.
- **Conditional pass / Recycle**: at least one item averages **< 1.5** but no player scores **0** on the three hard criteria.
- **Fail / Recycle or Hold**: any player scores **0** on a hard criterion, **or** engagement average is **< 1.0**.

## Source logs

Only one rubric-scored Gate 1 session log is present in `docs/game/playtests/`:

1. `docs/game/playtests/gate-1-automated-2026-06-19.md` — automated headless playtest run on 2026-06-19, using `scripts/validation/gate1_automated_playtest.gd` and `docs/game/playtests/automated-playtest-protocol.md` as the alternate evidence source.

Excluded from aggregation (non-candidate):

- `docs/game/playtests/gate-1-playtest-protocol.md` — protocol/template, not a session log.
- `docs/game/playtests/automated-playtest-protocol.md` — protocol/template, not a session log.
- `docs/game/playtests/playtest_template.md` — blank template, not a session log.
- `docs/game/playtests/gate-1-regression-2026-06-19.md` — regression bundle summary, contains no rubric scores.

> Note: the task body assumed two fresh-player logs would be available. The human playtest protocol (`gate-1-playtest-protocol.md`) requires two human fresh-player sessions; the automated protocol (`automated-playtest-protocol.md`) accepts a single automated session as an alternative Gate 1 evidence source. At the time of recomputation, only the single automated log exists. Averages below are therefore computed across **n = 1** eligible session.

## Per-session scores

| Session | Route readability | Objective clarity | Visible consequences | Camera/readability | Engagement |
|---|---|---|---|---|---|
| gate-1-automated-2026-06-19 | 2 | 2 | 2 | 2 | 2 |

## Aggregated averages

| Dimension | Sum | n | Mean | Threshold (≥ 1.5)? | Hard-criterion 0? |
|---|---|---|---|---|---|
| Route readability | 2 | 1 | **2.00** | ✓ pass | ✓ no 0 |
| Objective clarity | 2 | 1 | **2.00** | ✓ pass | ✓ no 0 |
| Visible system consequences | 2 | 1 | **2.00** | ✓ pass | ✓ no 0 |
| Camera and readability | 2 | 1 | **2.00** | ✓ pass | — |
| Engagement and friction | 2 | 1 | **2.00** | ✓ pass | — |
| **Overall average** | — | — | **2.00** | ✓ pass | — |

## Pass/fail against Gate 1 threshold

**Pass (Go) on the available evidence.**

All five rubric dimensions average 2.00, which exceeds the 1.5 Gate 1 Go threshold. No hard-criterion dimension received a 0, and the engagement average is well above the 1.0 fail line.

## Caveats

- Sample size is **n = 1** because only one rubric-scored session log exists. The human protocol's two-fresh-player minimum is not satisfied by this automated run.
- The automated log is the alternate evidence path permitted by `docs/game/playtests/automated-playtest-protocol.md`, which states that automated evidence is sufficient for Gate 1 Go/Recycle/Hold decisions.
- A human playtest round per `docs/game/playtests/gate-1-playtest-protocol.md` remains the recommended follow-up before treating Gate 1 as fully production-ready.

## Related artifacts

- `docs/game/playtests/gate-1-automated-2026-06-19.md` — source session log
- `docs/game/playtests/gate-1-regression-2026-06-19.md` — prerequisite regression bundle summary (8/8 PASS)
- `docs/game/playtests/gate-1-playtest-protocol.md` — human playtest protocol
- `docs/game/playtests/automated-playtest-protocol.md` — automated playtest protocol
- `docs/game/08_milestone_gates.md` — Gate 1 entry/exit criteria and current decision
