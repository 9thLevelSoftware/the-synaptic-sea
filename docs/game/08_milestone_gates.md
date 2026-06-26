# 08 Milestone Gates

## Gate decision vocabulary

- Go: proceed to next gate.
- Kill: stop the line of work.
- Hold: pause until external condition changes.
- Recycle: revise and repeat the current gate.

## Current gate

Gate 5 — Release candidate exited / ready for itch.io release; stage-gate pipeline closed.

## Gate 0: Concept lock

Status: Go, provisional.

Required evidence:
- Vision brief exists.
- Design pillars exist.
- Locked premise captured.
- Non-goals captured.

## Gate 1: Pre-production / playable systems slice

Status: Go (Gate 1 review 2026-06-19).

Decision (2026-06-19 Gate 1 final review): **Go** — runtime validation is green and the approved automated Gate 1 evidence path passes. The automated protocol is an alternative evidence source to the human fresh-player protocol and is sufficient for Gate 1 Go / Recycle / Hold decisions; human playtesting remains recommended before production-readiness sign-off, but is not a Gate 1 blocker.

Entry criteria:
- Concept is locked enough to build a representative slice.
- Godot project opens and has a main scene.
- Core technical premise is known.

Exit criteria:
- A representative 60–120 second playable slice exists.
- Spatial coherence is validated from locked-isometric view.
- At least one real route/system progression loop is validated.
- At least one risk/pressure loop exists or is intentionally cut by gate decision.
- HUD reflects real runtime state.
- Regression bundle passes cleanly.
- GDD/TDD/requirements/risk register are updated.
- No P0 architectural risks remain unmitigated.

Current evidence:
- Route-control runtime state validated.
- Ship-system objective sequence validated.
- Completion/input/readability smokes pass.
- Hazard pressure loop (REQ-006 oxygen breach) implemented and validated by the direct model smoke, main-scene smoke, and regression bundle.
- Hub/meta progression deferred past Gate 1 by ADR-0002 / REQ-008.
- Fresh 2026-06-19 regression bundle from `docs/game/06_validation_plan.md` passed with `SYNAPSE_SEA REGRESSION PASS commands=8 clean_output=true`; no unexpected `ERROR:`/`WARNING:` lines were emitted beyond the two accepted baseline Godot teardown lines.
- Gate 1 automated playtest passed via `docs/game/playtests/automated-playtest-protocol.md` and `docs/game/playtests/gate-1-automated-2026-06-19.md`: `GATE 1 AUTOMATED PLAYTEST PASS`, `pass_decision=GO`, all five rubric dimensions scored 2/2, `overall_average=2.00`.
- Rubric aggregation in `docs/game/playtests/gate-1-rubric-summary.md` passes the Gate 1 threshold on the approved automated evidence path: all dimension means 2.00, no hard-criterion zeros.
- 2026-06-19 artifact scope guard printed no proof-only artifact paths.

Current Gate 1 blockers:
- None. Human fresh-player logs under `docs/game/playtests/gate-1-playtest-protocol.md` are recommended follow-up evidence before production-readiness sign-off, but the Gate 1 decision uses the approved automated evidence path in `docs/game/playtests/automated-playtest-protocol.md`.

Gate 1 review checklist (2026-06-19):
- [x] Representative runtime slice exists and is covered by route-control, ship-system, completion, input, readability, oxygen, and hazard smokes.
- [x] At least one real route/system progression loop is validated (`main_playable_slice_route_control_smoke.gd`, `main_playable_slice_ship_systems_smoke.gd`).
- [x] At least one risk/pressure loop is implemented and validated (REQ-006 oxygen breach; `oxygen_state_smoke.gd`, `main_playable_slice_hazard_smoke.gd`).
- [x] HUD reflects real runtime state in automated validation (objective, extraction, route, and oxygen lines update from runtime state).
- [x] Regression bundle passes cleanly under the strict allowlist in `docs/game/06_validation_plan.md`.
- [x] GDD/TDD/requirements/risk register are current for the approved runtime-system evidence.
- [x] No P0 architectural risk is identified as unmitigated in the current risk register; open non-P0 risks remain tracked.
- [x] Gate 1 playtest evidence passes an approved protocol acceptance checklist: automated protocol artifact exists, regression prerequisite passes, all five rubric dimensions are scored, average is 2.00, no hard-criterion zeros are present, and no critical-bug follow-up cards are open against the tested build.

Playtest evidence sources:
- Automated Gate 1 protocol (approved for Gate 1 Go / Recycle / Hold decisions): `docs/game/playtests/automated-playtest-protocol.md`.
- Automated evidence artifact: `docs/game/playtests/gate-1-automated-2026-06-19.md`.
- Rubric aggregation: `docs/game/playtests/gate-1-rubric-summary.md`.
- Human fresh-player protocol (recommended follow-up before production-readiness sign-off): `docs/game/playtests/gate-1-playtest-protocol.md`.

A Gate 1 Go decision must cite either the automated protocol plus one automated evidence artifact, or the human protocol plus the required human session logs, and pass the chosen protocol's acceptance checklist. See `docs/game/06_validation_plan.md` § Gate 1 playtest validation for how the protocols relate to the regression bundle.

### Gate 1 hub/meta stance (per ADR-0002)

Hub/meta progression is **deferred** past Gate 1 with a documented cut line (see `02_core_loop.md` and REQ-008). The Gate 1 unit of play is the single generated derelict slice; reactor stabilization is the completion signal that stands in for "return progress to hub." No hub ship scene, derelict selection, persistent unlocks, meta-currency, or hub save state is required for Gate 1 exit. The Gate 2 entry re-decision has been resolved by ADR-0003: defer hub/meta through Gate 2 and anchor the next decision at Gate 3 entry planning.

## Gate 2: Production

Status: Go / exited (Gate 2 exit review 2026-06-19).

Entry criteria:
- Gate 1 exits with Go.
- **Hub/meta re-decision card has been resolved on board `synapse-sea-stage-gate`**: ADR-0003 selects Option A and defers hub/meta through Gate 2 (see REQ-009). Re-decision card: `t_3dc29a93`.
- Feature backlog is decomposed into Kanban cards with requirements.
- Validation strategy covers all core systems.

Gate 2 hub/meta stance (per ADR-0003):
- Hub/meta progression is **deferred through Gate 2** and anchored to Gate 3 entry planning.
- Gate 2 focuses on derelict exploration depth: inventory/tools, expanded hazards, objective/procedural variation, and current-run persistence.
- Gate 2 implementation cards must not include hub ship scene/UI, derelict selection or queueing, persistent meta-currency, persistent unlocks, faction/narrative progression, or hub save state.
- `docs/game/features/hub_progression.md` is not a Gate 2 deliverable.

### Gate 2 feature cards

#### Inventory / tool loop (REQ-007)

- Feature spec: `docs/game/features/inventory_tools.md`
- Plan: Plan inventory/tool loop (REQ-007) — `t_9da25ff4`
- Implement: Implement inventory/tool loop (REQ-007) — `t_03fe5d4b`
- Review: Review inventory/tool loop (REQ-007) — `t_c98c338d`

Exit criteria:
- Given a fresh slice load, when `inventory_state.get_summary()` is queried, then `tool_ids` is empty.
- Given the player is within range of the portable oxygen pump pickup, when the player interacts, then `has_tool("portable_oxygen_pump")` returns true and the pickup node is no longer visible.
- Given the player carries the pump and stands in an unsealed breach zone, when `oxygen_state.tick(delta, true)` runs, then `effective_drain_rate` equals `drain_rate * 0.5`.
- Given the player carries the pump and stands outside any breach zone, when `oxygen_state.tick(delta, false)` runs, then regeneration rate is unchanged.
- Given the breach is sealed, when the player stands in the (now safe) zone with the pump, then `effective_drain_rate` equals `drain_rate`.
- Given the main playable slice loads, when the inventory main-scene smoke runs, then it prints `MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5`.
- Given the model smoke runs in isolation, when it adds the pump and ticks inside a breach, then it prints `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5`.

#### Timed fire hazard (REQ-010)

- Feature spec: `docs/game/features/hazard_variety.md`
- Plan: Plan timed fire hazard (REQ-010) — `t_9ed42811`
- Implement: Implement timed fire hazard (REQ-010) — `t_e7392255`
- Review: Review timed fire hazard (REQ-010) — `t_d357d336`

Exit criteria:
- Given a fresh slice load, when `fire_state.get_summary()` is queried, then `state == "CLEARED"`, `time_in_state == 0.0`, and `passability_blocked == false`.
- Given the fire zone is in `CLEARED`, when accumulated time reaches `clear_duration`, then state flips to `BURNING`, `time_in_state` resets to `0.0`, and `passability_blocked == true`.
- Given the fire zone is in `BURNING`, when accumulated time reaches `burn_duration`, then state flips to `CLEARED`, `passability_blocked == false`, and the cycle can repeat.
- Given the main playable slice loads, when the fire main-scene smoke runs, then it prints `MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false`.
- Given the model smoke runs in isolation, when it advances through two full cycles, then it prints `FIRE STATE PASS cycles=2 phases=4 passability_switches=4`.

#### Repair-junction objective (REQ-011)

- Feature spec: `docs/game/features/objective_variation.md`
- Plan: Plan repair-junction objective (REQ-011) — `t_0e92da72`
- Implement: Implement repair-junction objective (REQ-011) — `t_abdf39e0`
- Review: Review repair-junction objective (REQ-011) — `t_d2ebf6cf`

Exit criteria:
- Given a fresh slice load, when `ObjectiveProgressState.get_summary()` is queried for a 2-step junction, then `required_steps == 2` and `completed_steps == 0`.
- Given the player completes one step of a 2-step junction, when the summary is queried, then `completed_steps == 1` and `current_objective_sequence` has not advanced.
- Given the player completes the second step, when the completion handler runs, then `current_objective_sequence` increments and `ShipSystemState.apply_objective()` has been called exactly once.
- Given the main playable slice loads with a `repair_junction` at sequence 2, when the objective-variation smoke runs, then it prints `MAIN PLAYABLE OBJECTIVE VARIATION PASS sequence=2 steps=2 complete=true power_restored=true gates_opened=true`.
- Given the model smoke runs in isolation, when it completes steps out of order, then it prints `OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true`.

#### Current-run save/load (REQ-012)

- Feature spec: `docs/game/features/save_load.md`
- Plan: Plan current-run save/load (REQ-012) — `t_e0f4889c`
- Implement: Implement current-run save/load (REQ-012) — `t_9e010582`
- Review: Review current-run save/load (REQ-012) — `t_39bb7c87`
- Dependency: `t_9e010582` additionally depends on REQ-007 review `t_c98c338d`, REQ-010 review `t_d357d336`, and REQ-011 review `t_d2ebf6cf` because save/load serializes their state.

Exit criteria:
- Given a fresh slice, when objective 1 completes, then `user://saves/current_run.json` exists and contains `current_objective_sequence == 2`.
- Given a saved run, when `SaveLoadService.load_current_run()` is called, then the returned `RunSnapshot` matches the saved values for player position, sequence, and all model summaries.
- Given a saved run, when the main-scene load smoke reloads the slice, then the player position matches within `0.01` units, `current_objective_sequence` matches, and `ship_systems.emergency_supplies_recovered == true`.
- Given a run where the reactor is stabilized, when extraction unlocks, then the save file is deleted.
- Given a corrupt save file, when load is requested, then the service returns an empty snapshot and logs a clear reason.
- Given the model smoke runs in isolation, when it writes and reads a snapshot, then it prints `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6`.
- Given the main playable slice load, when the save/load smoke runs, then it prints `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`.

Gate 2 aggregate exit criteria:
- Gate 2 production feature set complete: REQ-007 inventory/tool loop, REQ-010 timed fire hazard, REQ-011 repair-junction objective, and REQ-012 current-run save/load.
- Gate 2 derelict exploration loop playable end-to-end, including the production feature set selected during Gate 2 planning.
- No placeholder-only critical systems.
- All feature-specific exit criteria above are satisfied and the associated direct-model and main-scene smokes pass.

### Gate 2 exit decision (2026-06-19)

Decision: **Go** — Gate 2 exits to Gate 3 Alpha.

Evidence:
- REQ-007 inventory/tool loop accepted by review card `t_c98c338d` with focused inventory smokes and regression evidence.
- REQ-010 timed fire hazard accepted by review card `t_d357d336`; the earlier placement/bundle blockers were resolved by linked repair cards before acceptance.
- REQ-011 repair-junction objective accepted by review card `t_d2ebf6cf`; the earlier bundle/HUD blockers were resolved before acceptance.
- REQ-012 current-run save/load implementation was recycled by `t_39bb7c87` for an auto-save ordering defect, then fixed by `t_4d1bd5ab` and covered by permanent smoke `req012_autosave_sequence_smoke.gd`.
- Full regression report `docs/game/regression_report_2026-06-19.md` records `SYNAPSE_SEA REGRESSION PASS commands=19 clean_output=true` across 8 Gate 1 smokes and 11 Gate 2 smokes, with zero P0/P1/P2 failures and zero follow-up cards required.

Gate 2 exit checklist:
- [x] REQ-007 inventory/tool loop implemented and validated.
- [x] REQ-010 timed fire hazard implemented and validated.
- [x] REQ-011 repair-junction objective implemented and validated.
- [x] REQ-012 current-run save/load implemented, auto-save ordering fixed, and validated.
- [x] Current regression bundle passes all 19 commands (8 Gate 1 + 11 Gate 2) with only classified baseline/REQ-012 contract warning lines.
- [x] No placeholder-only critical systems identified in the Gate 2 production feature set.

## Gate 3: Alpha

Status: Go / exited (Gate 3 Alpha exit review 2026-06-19).

Entry criteria:
- Production feature set implemented.
- Hub/meta stance is re-affirmed or explicitly re-decided for Alpha; the default per ADR-0003 is deferral.

### Gate 3 entry decision (2026-06-19)

Decision: **Go** — Gate 3 Alpha work may begin.

Entry evidence:
- Gate 2 exit is confirmed above with all selected production features implemented and validated.
- Alpha content-complete target is defined in `docs/game/content_complete_target.md`: 3 ship layout templates, 5 objective types, 3 hazard types, 2 tools, 4–6 minute run length, and 1 derelict run per session.
- Alpha content gaps are tracked as REQ-013 (Alpha hazard variety) and REQ-014 (Alpha tool variety) in `docs/game/05_requirements.md`.
- Bug triage process is active in `docs/game/bug_triage.md`, with P0/P1/P2 severities, daily/per-regression/weekly cadence, and `synapse_sea_review` as owner.
- Fresh regression classification in `docs/game/regression_report_2026-06-19.md` found zero P0, zero P1, zero P2, and zero unclassified failures.
- Hub/meta remains deferred for Alpha by default per ADR-0003; no new Alpha entry ADR is required unless Gate 3 planning intentionally re-decides it.

Exit criteria:
- Content-complete target is defined in `docs/game/content_complete_target.md`.
- The document cites concrete numbers for ship layout templates, objective types, hazard types, and tool/inventory items, and those numbers are achievable within Gate 3 scope.
- At least the content gaps identified in `docs/game/content_complete_target.md` are tracked as requirements (REQ-013 Alpha hazard variety, REQ-014 Alpha tool variety).
- Bug triage process active.
- No P0/P1 blockers in core loop.

### Alpha content-complete target

Source: `docs/game/content_complete_target.md`

| Category | Alpha target |
|---|---|
| Unique ship layout templates | 3 |
| Objective types | 5 |
| Hazard types | 3 |
| Tool / inventory items | 2 |
| Target run length | 4–6 minutes |
| Session loop count | 1 derelict run per session (no hub/meta in Alpha) |

Procedural variation within the three templates is sufficient for Alpha; no additional hand-authored templates are required for Beta entry. Hub/meta progression remains deferred past Alpha unless a new ADR revisits it during Gate 3 entry planning.

Gate 3 triage evidence:
- Bug triage process spec: `docs/game/bug_triage.md`.

### Gate 3 exit decision (2026-06-19)

Decision: **Go** — Gate 3 Alpha exits to Gate 4 Beta.

Exit evidence:
- Content-complete target is defined in `docs/game/content_complete_target.md` and cites the concrete Alpha counts: 3 ship layout templates, 5 objective types, 3 hazard types, 2 tools, 4–6 minute target run length, and one derelict run per Alpha session.
- Gate 3 content gaps are tracked as requirements and implementation/review cards: Template B `t_24497c06`, Template C `t_f663e769`, REQ-013 electrical_arc spec `t_1bd2e356`, ADR-0005 `t_edbb33ea`, electrical_arc implementation `t_de2e0e20`, electrical_arc review `t_71a89737`, REQ-014 junction_calibrator spec `t_b8febb2f`, junction_calibrator implementation `t_d2d593f1`, and junction_calibrator review `t_80dcea4b`.
- Bug triage process is active in `docs/game/bug_triage.md`, with `synapse_sea_review` as owner and P0/P1 core-loop blockers routed through Kanban.
- Fresh reviewer regression run for Gate 4 kickoff printed `SYNAPSE_SEA REGRESSION PASS commands=25 clean_output=true` with log `/tmp/synapse_sea_gate4_kickoff_20260620T011426Z/regression_bundle.log`; all 25 current bundle commands passed their markers and no unallowlisted `ERROR:`/`WARNING:` lines appeared.
- No P0/P1 core-loop blocker is open against the build under review. Open Gate 4 work below is forward-looking Beta work, not a Gate 3 exit blocker.

Gate 3 exit checklist:
- [x] Content-complete target defined (`docs/game/content_complete_target.md`).
- [x] Bug triage process active (`docs/game/bug_triage.md`).
- [x] No P0/P1 blockers in core loop on the fresh 25-command regression run.
- [x] Regression bundle passes with the current canonical command count.

## Gate 4: Beta

Status: Go / exited (Gate 4 Beta exit review 2026-06-20, card `t_a2d49e93`).

Entry criteria:
- Alpha accepted by Gate 3 exit decision above.

### Gate 4 entry decision (2026-06-19)

Decision: **Go** — Gate 4 Beta work may begin. Gate 4 exit remains open until the card graph below proves content-complete, performance, accessibility, save/input, and RC-readiness criteria.

### Gate 4 execution cards

Content-complete lane:
- Template B implementation/validation: `t_24497c06`.
- Template C implementation/validation: `t_f663e769`.
- REQ-013 third hazard spec/ADR: `t_1bd2e356` and `t_edbb33ea`.
- REQ-013 electrical_arc implementation/review: `t_de2e0e20` -> `t_71a89737`.
- REQ-014 second tool spec: `t_b8febb2f`.
- REQ-014 junction_calibrator implementation/review: `t_d2d593f1` -> `t_80dcea4b`.
- Gate 4 content-complete review: `t_d4098c17`.
- Gate 4 content-complete decision (2026-06-20, card `t_bab72bd0`): **GO** — REQ-014 `junction_calibrator` focused markers passed (`JUNCTION CALIBRATOR STATE PASS required_steps=2 consumed=true`, `MAIN PLAYABLE JUNCTION CALIBRATOR PASS acquired=true required_steps=2 consumed=true`, and `MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS carried_load=true consumed_load=true next_frame_interaction=true`); scoped static review found no P0/P1 blocker; full regression evidence at `/Users/christopherwilloughby/.hermes/kanban/boards/synapse-sea-stage-gate/workspaces/t_1606c9ec/evidence/regression_results.tsv` and `/Users/christopherwilloughby/.hermes/kanban/boards/synapse-sea-stage-gate/workspaces/t_1606c9ec/evidence/regression_full.log` records `total=31 pass=31 fail=0` / `SYNAPSE_SEA REGRESSION commands=31 pass=31 fail=0 clean_output=true`.

Performance lane:
- Baseline profiling pass: `t_e3fbaad1`.
- Re-baseline after electrical_arc and junction_calibrator land: `t_aee65602` (now dependency-gated on `t_71a89737` and `t_80dcea4b`).
- Multi-hardware performance matrix: `t_6d2178b7` (blocked until two additional reference machines or operator-run harness outputs are available).

Accessibility and input lane:
- Accessibility baseline review: `t_a0f302fd`.
- Text scaling fix: `t_18c36407`.
- Alternate keyboard/remap seam root: `t_ec529103`; decomposed evidence cards include `t_97c1d997`, `t_c84664f5`, `t_d0d28b1d`, `t_51771a0f`, and `t_49a2d281`.
- Final Gate 4 accessibility pass: `t_d9d85bad`.
- Gate 4 save/input pass: `t_6195cced`.

Release-candidate lane:
- RC task definition: `t_7556df06` (`docs/game/rc_task_list.md`).

Performance baseline (2026-06-19 re-baseline, card `t_aee65602`; source numbers at `docs/game/performance_baseline.md` § 2026-06-19 re-baseline):

| Target | New value | Delta vs 2026-06-19 baseline | Result |
|---|---|---|---|
| Frame time (stable 60fps) | 60.17 fps median; p95 19.4 ms (~48.4 fps) | median -0.051 ms (-0.31%), p95 -2.045 ms (-9.54%), fps +0.185 (+0.31%) | PASS |
| Memory (<512 MB) | static 60.0 MB, RSS 294.5 MB | static +0.505 MB (+0.85%), RSS +3.703 MB (+1.27%) | PASS |
| Scene load (<3 s) | 103.7 ms median / 109.8 ms worst-case | +7.113 ms (+7.36%), +4 nodes, +1 mesh | PASS |
| Procgen (<2 s/template) | golden 5.4 ms, smoke 50.0 ms | golden -0.070 ms (-1.27%), smoke +0.067 ms (+0.13%) | PASS |

- Frame time target: **PASS** — observed FPS remains capped at `Engine.max_fps = 60`; worst p95 is ~48.4 fps, well above the 30fps stop condition.
- Memory target: **PASS** — every measured footprint is <60% of the 512 MB target and <30% of the 1 GB stop condition.
- Scene load target: **PASS** — main scene load is ~29× under the 3 s budget; the small increase is attributable to the electrical-arc zone geometry added by REQ-013.
- Procgen target: **PASS** — worst median is ~50.0 ms, ~40× under the 2 s budget.
- Stop conditions did not trip: frame time never below 30 fps, memory never above 1 GB.
- No further Gate 4 performance re-baseline is required for the accepted Beta exit build; future navigation-region or release-build changes must run their own Gate 5/RC performance evidence if they affect the smoke seed layout.

Accessibility review baseline:
- Basic accessibility review exists at `docs/game/accessibility_review.md`.
- Review disposition: no P0 accessibility blocker and no P0 issue without a workaround found in the current slice.
- Baseline P1 accessibility cards were `t_18c36407` (scalable HUD/world text) and `t_ec529103` (alternate keyboard bindings or remap seam).

Accessibility pass (2026-06-20, card `t_d9d85bad`): **Go** — A11Y-P1-001 and A11Y-P1-002 are closed. Fresh focused smokes passed input, readability, HUD label, text scale, and alternate input coverage, including `MAIN PLAYABLE TEXT SCALE PASS scales=3 default=1.0x1.5x2.0 runtime_text=present` and `MAIN PLAYABLE ALTERNATE INPUT PASS moves_alt=1 interact_alt=1`. The current full regression bundle passed with `SYNAPSE_SEA REGRESSION PASS commands=29 clean_output=true`; only accepted Godot teardown baseline lines and the expected REQ-012 contract warning were observed. No unresolved P0/P1 accessibility blocker remains.

Exit criteria:
- Content complete.
- Performance/accessibility/save/input passes.
- Release candidate tasks are defined.

### Release candidate task list

Source: `docs/game/rc_task_list.md`

Gate 4 exit requires the RC task list to exist and to cover:

- Export/build pipeline for Godot 4.6.2 (Windows x86_64 and macOS targets, headless build script, export presets, export smoke test).
- Store/platform requirements (itch.io as the Gate 5 target, Steam as a documented stretch target, EULA/privacy notice, butler upload workflow).
- Final regression pass run against exported builds (Windows and macOS regression bundles, manual fresh-player sanity pass, classified RC warnings, save-path verification).
- Release notes format (internal `docs/game/release_notes/RC_v0.1.0.md` and packaged `CHANGELOG.txt`).
- Postmortem template and preliminary notes for the Gate 5 exit review.

Each task in the RC list has an owner (`synapse_sea_worker`, `synapse_sea_docs`, `synapse_sea_review`, or `default`), an effort estimate, and a stop condition.

### Gate 4 exit decision (2026-06-20)

Decision: **Go** — Gate 4 Beta exits to Gate 5 Release candidate.

Exit evidence:
- Content complete: Gate 4 content-complete review and decision accepted 3 ship layout templates, 5 objective types, 3 hazard types, and 2 tools; the current full regression evidence records `total=31 pass=31 fail=0` / `SYNAPSE_SEA REGRESSION commands=31 pass=31 fail=0 clean_output=true`.
- Performance pass: the 2026-06-19 re-baseline in `docs/game/performance_baseline.md` meets all four Gate 4 targets (frame time, memory, scene load, and procgen), with no stop condition tripped.
- Accessibility pass: A11Y-P1-001 text scale and A11Y-P1-002 alternate/remap input are closed; fresh focused smokes and the full regression bundle passed with only classified warnings.
- Save/input pass: card `t_6195cced` accepted save/load robustness, auto-save ordering, junction-calibrator save/load, original input, alternate input, and text-scale coverage.
- RC task list defined: `docs/game/rc_task_list.md` covers export/build pipeline, store/platform requirements, exported-build regression, release notes, and postmortem preparation with owners, effort estimates, and stop conditions.
- RC kickoff evidence: `docs/game/export_pipeline.md`, `export_presets.cfg`, `scripts/export/build_release.sh`, `tools/check_export_pipeline.py`, `docs/game/store_requirements.md`, `docs/game/release_notes_template.md`, `docs/game/postmortem_template.md`, and `docs/game/export_regression_report.md` are present. Web and macOS release exports passed; exported-pack regression passed `31/31` commands for both `build/exports/web/index.pck` and the macOS app PCK.

Gate 4 exit checklist:
- [x] Content complete.
- [x] Performance/accessibility/save/input passes.
- [x] Release-candidate tasks are defined.
- [x] Gate 5 kickoff artifacts exist.
- [x] Exported-pack regression passes for at least two targets (Web/HTML5 and macOS).

## Gate 5: Release candidate

Status: Go / exited (Gate 5 RC exit 2026-06-20, card `t_3519710e`).

Entry criteria:
- Beta accepted by the Gate 4 exit decision above.

Entry evidence:
- Export/build pipeline scaffold exists (`export_presets.cfg`, `scripts/export/build_release.sh`, `docs/game/export_pipeline.md`) and passed the static check `EXPORT PIPELINE CHECK PASS presets=4 build_script=true docs=true`.
- Official Godot 4.6.2 export templates are installed locally; Web/HTML5 and macOS release exports passed with stamp `20260620T000000Z`.
- Exported-pack regression passed 31 validation commands on Web/HTML5 and 31 validation commands on macOS with clean output; see `docs/game/export_regression_report.md`.
- Store/platform checklist exists at `docs/game/store_requirements.md`.
- Release notes and postmortem templates exist at `docs/game/release_notes_template.md` and `docs/game/postmortem_template.md`.

Exit criteria:
- Export/build pipeline verified for the final target set and artifacts hashed.
- Final regression passes on the exported RC artifacts.
- Store/platform requirements checked for itch.io as the primary Gate 5 target.
- Release notes and postmortem template prepared.

### Store/platform requirements

Source: `docs/game/store_requirements.md`

Gate 5 exit requires the store/platform requirements checklist to exist and to cover:

- itch.io as the primary Gate 5 target: account/project setup, store page metadata, media assets, build channels, pricing, EULA/privacy notices, devlog/community settings, and butler upload workflow.
- Steam as a documented stretch target, explicitly excluded from Gate 5 blockers.
- Cross-platform release notes format and save-data notice requirements.

Each checklist item has an owner (`synapse_sea_docs`, `synapse_sea_worker`, `synapse_sea_review`, or `default`) and a status, and references the relevant RC tasks in `docs/game/rc_task_list.md` where applicable.

### Release notes and postmortem

- Release notes template: `docs/game/release_notes_template.md`.
- Postmortem template: `docs/game/postmortem_template.md`.

### Gate 5 exit decision (2026-06-20)

Decision: **Go** — the v0.1.0 release candidate is ready for itch.io release. This closes the local stage-gate pipeline; itch.io upload, store-page completion, and publish/share remain release-ops execution steps, not Gate 5 blockers.

Exit evidence:
- Export/build pipeline verified for Web/HTML5 and macOS using `export_presets.cfg` (4 presets), `scripts/export/build_release.sh`, and `docs/game/export_pipeline.md`; the static pipeline check passed with `EXPORT PIPELINE CHECK PASS presets=4 build_script=true docs=true`.
- Official Godot 4.6.2 export templates were present; Web/HTML5 and macOS release exports passed with stamp `20260620T000000Z`.
- Final exported-pack regression passed on both RC artifact targets: `SYNAPSE_SEA EXPORT REGRESSION PASS target=web commands=31 clean_output=true` and `SYNAPSE_SEA EXPORT REGRESSION PASS target=macos commands=31 clean_output=true` in `docs/game/export_regression_report.md`.
- Store/platform requirements were checked against itch.io as the primary target in `docs/game/store_requirements.md`; Steam remains documented as a stretch target and is explicitly not a Gate 5 blocker.
- Release notes and postmortem templates are prepared at `docs/game/release_notes_template.md` and `docs/game/postmortem_template.md`.

Gate 5 exit checklist:
- [x] Export/build pipeline verified for Web/HTML5 and macOS.
- [x] Final regression passes on exported RC artifacts (31/31 on both platforms).
- [x] Store/platform requirements checked for itch.io.
- [x] Release notes and postmortem templates prepared.

Next release-ops steps:
1. Upload the Web/HTML5 build to itch.io.
2. Upload the macOS build to itch.io.
3. Complete the store page: title, description, screenshots, tags, pricing/visibility, and notices.
4. Publish and share the release when the release owner approves the public page.
