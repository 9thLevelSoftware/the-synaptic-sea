# Gate 1 Playtest Protocol

## Purpose

Validate that the current systems slice is **readable and meaningful for a fresh player**, and define how to collect the fresh-player playtest evidence called out for Gate 1 exit in `docs/game/08_milestone_gates.md`.

This protocol is a behavioral, in-engine playtest. The primary evidence is **direct observation of a fresh player running the main playable slice**, not screenshots, contact sheets, or proof artifacts. Visual artifacts are allowed only as secondary aids when paired with notes on what the player actually did.

## Scope and target

- **Target build**: the running Godot main playable slice (`scenes/main_playable_slice.tscn` via `scripts/procgen/playable_generated_ship.gd`) at the most recent commit / workspace state. The slice must already pass the regression bundle in `docs/game/06_validation_plan.md` before a playtest session starts.
- **Target player profile**: someone who has **never** played Sargasso, has **not** read the GDD or feature specs, and has **not** watched a prior playtest recording. This is the "stranger" the Gate 1 exit criteria reference.
- **Target session length**: 10–15 minutes per player. Two players per round is the minimum sample; one player is acceptable for an early directional pass but cannot by itself certify Gate 1.

## Pre-session setup

1. Confirm the regression bundle is green by re-running `docs/game/06_validation_plan.md`. If any smoke fails, **stop** and create a Kanban card to fix the regression before continuing.
2. Confirm the build being tested matches the workspace state recorded in this session's log (Godot 4.6.2 at `/Users/christopherwilloughby/.local/bin/godot-4.6.2`, project at `/Users/christopherwilloughby/the-sargasso-of-stars`).
3. Reset the player's save / objective state so the run starts at objective 1 with the reactor and route gate closed.
4. Brief the player with only what the in-game UI tells them. Do **not** explain the loop, hazards, or system order before the run.
5. Create a per-session log using `docs/game/playtests/playtest_template.md`. Filename: `playtests/gate-1-<YYYY-MM-DD>-<player-pseudonym>.md`.

## Observer roles

Each playtest session has at least two roles, both filled by humans or by agents acting in observer-only mode (no in-engine input):

- **Player** — drives the slice, may ask clarifying questions out loud.
- **Observer** — watches silently, timestamps notable moments, writes observations into the log template's `Observations` sections in real time.

A second observer is recommended so one watches the screen and one watches the player's face/body language. Recording the screen is optional but recommended.

## Session script (10–15 minutes)

Run this in order. Do not skip steps; do not pre-brief the player beyond the in-game text.

1. **Cold start (0:00–1:00)** — Player loads the slice from a clean state. Observe: does the player recognize that they can move, and do they figure out movement within 30 seconds without prompting?
2. **Orientation (1:00–3:00)** — Player explores the entry area and reads the HUD. Observe: can they state in their own words what they think the current goal is? Record the player's verbal or written answer verbatim.
3. **First objective attempt (3:00–6:00)** — Player locates and attempts objective 1. Observe: how long does it take to find the first affordance? Does the interaction feel responsive?
4. **Systems and route unlock (6:00–9:00)** — Player completes objectives 2–3. Observe: does the player notice that route state and HUD change after objective 2? Do they verbalize surprise, confusion, or satisfaction?
5. **Reactor and extraction (9:00–12:00)** — Player completes objective 4 and reaches extraction. Observe: does the player understand that extraction is now unlocked, and can they find it without prompting?
6. **Free play (12:00–15:00)** — Observer stops prompting. Player may explore, retry, or quit. Record what the player chooses to do without direction.

If the player is still engaged past 15 minutes, let them continue and note the timestamp they disengage, but the protocol's formal scoring window ends at 15:00.

## Observation rubric

Score each item during the run on a 0–2 scale. Definitions below; the same definitions are reused in the per-session log template's `Pass/fail against Gate criteria` section.

- **0 — Fails Gate 1.** Player could not complete this dimension without observer help, or could not do it at all within the 15-minute window.
- **1 — Borderline.** Player eventually succeeded but with friction (long pause, wrong turns, verbal confusion). Acceptable as a Recycle trigger but not a Go.
- **2 — Passes Gate 1.** Player completed the dimension within the expected time window without observer help and expressed no significant confusion.

### Route readability (REQ-001, REQ-002)

- 2: Player walks from entry to objective 1 in under 90 seconds and recognizes blocked routes as blocking.
- 1: Player reaches objective 1 with one or two false starts but no observer hint.
- 0: Player is stuck or wanders past objective 1 multiple times, or asks the observer for help.

### Objective clarity

- 2: Player can verbally state the current objective and the next one after completing each.
- 1: Player can state the current objective but not the next one without prompting.
- 0: Player cannot state the current objective at any point, or completes objectives by accident.

### Visible system consequences (REQ-002, REQ-003, REQ-005)

- 2: Player notices and comments on at least two of: route gate opening, HUD update, extraction unlock.
- 1: Player notices only one of those, or notices after the observer points it out.
- 0: Player does not notice any state change, or believes the run is "still broken" after completion.

### Camera and readability (locked-isometric, GDD §Camera)

- 2: Player does not request camera controls and reports no occlusion issues.
- 1: Player requests camera control once or reports mild occlusion but recovers.
- 0: Player is repeatedly blocked by occlusion or has to leave the play area to read state.

### Engagement and friction

- 2: Player chooses to continue past 12:00 or asks "can I do another one."
- 1: Player reaches extraction at 12:00 ± 90 seconds with neutral affect.
- 0: Player quits before 12:00, or expresses frustration in the friction log.

## Success / failure criteria

A Gate 1 playtest round is the aggregated result of two or more player sessions on the same build.

- **Pass (Go)**: every rubric item averages **≥ 1.5** across all players, and no player scores **0** on route readability, objective clarity, or visible system consequences.
- **Conditional pass (Recycle)**: at least one rubric item averages **< 1.5** but no player scores **0** on the three hard criteria above. The follow-up card must target the lowest-scoring rubric items specifically.
- **Fail (Recycle or Hold)**: any player scores **0** on route readability, objective clarity, or visible system consequences, **or** the engagement-and-friction average is **< 1.0**.

Per-session logs are the primary evidence. Screenshot or contact-sheet artifacts may be attached for context but cannot substitute for the rubric scores.

## Gate 1 acceptance checklist

A reviewer using this checklist can sign off Gate 1 without re-deriving the criteria. Tick each box before recommending Go.

- [ ] Regression bundle in `docs/game/06_validation_plan.md` passes on the build under test.
- [ ] At least two fresh-player sessions completed, each with a log file under `docs/game/playtests/` using `playtest_template.md`.
- [ ] Both session logs include: build/workspace state, scenario, tester profile, timestamped observations, rubric scores, pass/fail statement, and a Continue/Recycle/Hold/Cut decision.
- [ ] Aggregated rubric averages meet the Pass threshold above.
- [ ] No rubric dimension scored 0 across all players for route readability, objective clarity, or visible system consequences.
- [ ] No critical-bug follow-up cards are still open against the build that was tested.
- [ ] The decision recorded in `docs/game/08_milestone_gates.md` for Gate 1 cites this protocol by filename and at least one per-session log.

## Mapping to gate decision

- **Go** when the acceptance checklist passes.
- **Recycle** when the acceptance checklist fails but the failures are scoped (specific rubric items, no 0s on hard criteria). Spawn a Kanban card per failing rubric item, scoped to allowed files only, and re-run the protocol after the fixes ship.
- **Hold** when the regression bundle fails or the build cannot produce a 10–15 minute session at all. Resolve the regression first; the protocol is not run.
- **Cut** is reserved for the coordinator and is not produced by this protocol.

## Anti-patterns

- Treating a single screenshot of the slice as evidence that the slice is readable. Screenshots prove the slice renders; only a fresh player's actions prove the slice is readable.
- Letting the observer hint or explain the loop. Any session where the observer prompted the player must mark the prompted rubric item as 0 regardless of the outcome.
- Re-running the same player twice and counting it as two sessions. Each session log must be from a different player pseudonym, or the duplicate is invalid for the acceptance checklist.
- Using proof artifacts (`docs/superpowers/proofs`, `.superpowers`) as the primary evidence. They may be referenced in logs only when paired with the matching rubric score.

## Related docs

- `docs/game/08_milestone_gates.md` — Gate 1 entry/exit criteria and decision vocabulary.
- `docs/game/06_validation_plan.md` — Regression bundle that must pass before a playtest session starts.
- `docs/game/05_requirements.md` — REQ-001 through REQ-005 are the gameplay requirements this protocol validates against.
- `docs/game/playtests/playtest_template.md` — Per-session log template.
- `docs/game/features/route_control.md` — Feature spec for the route-control behaviors under test.