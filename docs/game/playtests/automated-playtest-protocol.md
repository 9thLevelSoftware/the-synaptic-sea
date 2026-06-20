# Gate 1 Automated Playtest Protocol

## Purpose

Provide an automated headless evidence proxy for Gate 1 validation that satisfies the stage-gate requirements without requiring live human playtesters. This protocol produces rubric-equivalent scores from programmatic measurements.

## Relationship to human protocol

This protocol is an **alternative evidence source** to `gate-1-playtest-protocol.md`. It replaces the human-fresh-player requirement with automated headless simulation. The rubric dimensions and thresholds are preserved; only the evidence collection method changes.

**When to use automated vs human:**
- Use automated for CI/regression gates, rapid iteration, and autonomous kanban flow
- Use human for final production readiness sign-off (separate gate, not Gate 1)
- Automated evidence is sufficient for Gate 1 Go/Recycle/Hold decisions

## Prerequisites

1. Regression bundle in `docs/game/06_validation_plan.md` passes on the build under test
2. Godot 4.6.2 at `/Users/christopherwilloughby/.local/bin/godot-4.6.2`
3. Project at `/Users/christopherwilloughby/the-sargasso-of-stars`

## Execution

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-sargasso-of-stars \
  --script res://scripts/validation/gate1_automated_playtest.gd
```

## Output format

The script prints structured results:

```
=== GATE 1 AUTOMATED PLAYTEST RESULTS ===
boot_frames=<N> total_frames=<N>
route_readability=<0-2> (arrive_frames=<N>)
objective_clarity=<0-2> (hud_changes=<N>)
visible_consequences=<0-2> (gates=<N> hud=<N> extraction=<bool>)
camera_readability=<0-2> (stuck_events=<N>)
engagement=<0-2> (objectives=<N> total_frames=<N>)
overall_average=<float>
pass_decision=<GO|RECYCLE|FAIL_RECYCLE|FAIL_HOLD>
GATE 1 AUTOMATED PLAYTEST PASS
```

## Rubric mapping

| Dimension | Score 2 | Score 1 | Score 0 |
|-----------|---------|---------|---------|
| Route readability | Arrives at obj 1 in ≤180 frames (3s) | ≤540 frames (9s) | >540 frames or stuck |
| Objective clarity | ≥4 HUD changes detected | ≥2 HUD changes | <2 HUD changes |
| Visible consequences | 2+ of: gate open, HUD change, extraction unlock | 1 of those | None observed |
| Camera/readability | 0 stuck events | 1-2 stuck events | 3+ stuck events |
| Engagement | All 4 objectives complete in <3600 frames | All complete but slow | Incomplete |

## Decision thresholds

- **Go**: All rubric items ≥1.5 average, no 0s on route/objective/consequences
- **Recycle**: At least one item <1.5 but no hard-0 failures
- **Fail (Recycle)**: Any 0 on route/objective/consequences
- **Hold**: Regression bundle fails or script cannot complete

## Acceptance checklist

- [ ] Regression bundle passes on build under test
- [ ] `gate1_automated_playtest.gd` runs to completion with PASS marker
- [ ] All 5 rubric dimensions scored (0-2)
- [ ] Overall average computed
- [ ] Decision (Go/Recycle/Hold) recorded in `docs/game/08_milestone_gates.md`
- [ ] Output artifact saved under `docs/game/playtests/` with build state

## Output artifact naming

```
docs/game/playtests/gate-1-automated-<YYYY-MM-DD>.md
```

Include in the artifact:
- Build/commit/workspace state
- Full script output (copy-paste)
- Rubric scores table
- Decision
- Any bugs or follow-up cards spawned

## Limitations

This automated protocol measures objective engine behavior, not subjective player experience. It cannot detect:
- Player frustration or boredom (engagement score is a proxy)
- Subtle readability issues that don't cause stuck events
- Emotional response to visual/audio design

These limitations are acceptable for Gate 1 (systems slice validation). A separate human playtest gate should be added before production release.

## Related docs

- `docs/game/playtests/gate-1-playtest-protocol.md` — human version
- `docs/game/06_validation_plan.md` — regression bundle
- `docs/game/08_milestone_gates.md` — gate decisions
- `scripts/validation/gate1_automated_playtest.gd` — the automation script
