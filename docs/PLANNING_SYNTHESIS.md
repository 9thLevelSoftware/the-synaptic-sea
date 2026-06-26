# The Synapse Sea — Planning & Design Synthesis

**Source:** `~/the-synaptic-sea/docs/`
**Project root:** `/Users/christopherwilloughby/the-synapse-sea-of-stars` (Godot 4.6.2)
**Working title:** *The Synapse Sea* — locked-isometric 3D ship survival/exploration
**Stage:** Gate 5 (post-RC); open-world build tracked in `09_system_roadmap.md`
**Generated:** 2026-06-25 (synthesis date)

This document is the comprehensive cross-reference of every planning artifact under `docs/`. It covers game vision, mechanics, scope, validation, risks, systems, store/exports, ADRs (26 of 28 — 0004 and 0006 are missing on disk), feature specs, playtests, and Gate 2 scope.

---

## 1. Vision & Pillars

### 1.1 Working title & premise (`docs/game/00_vision.md`, 4,991 chars)

- **Working title:** *The Synapse Sea* (placeholder kept; main scene prints "The Synapse Sea coherent proof ship bootstrap loaded.").
- **Locked premise:** The player's hub ship is trapped in a vast biomatter/cosmic Synapse Sea. They explore procedurally generated derelicts (each one a self-contained "building") to loot, repair, occupy/fortify, defend, and ultimately fly them out. Derelicts are the buildings; ships are the explorers. Modeled in the spirit of *Project Zomboid* — open-world, persistent-location, deep systems.
- **Genre slot:** Open-world ship survival (locked-isometric 3D, Godot 4.6).
- **North Star fantasy:** Loot → Repair → Occupy/Fortify → Defend → Fly.
- **Explicit non-goals:** No monsters (yet), no fortification (yet), no faction/survivor simulation (yet); those are deferred to later gates. Hub/meta progression is deferred through Gate 2.
- **Open questions:** Monster population model; faction/survivor simulation depth; multiplayer scope; per-derelict memory and persistent world state.

### 1.2 Design pillars (`docs/game/01_design_pillars.md`, 2,270 chars)

1. **Spatial coherence first** — every system must read on the locked-isometric view; rooms, route gates, breaches, hazards are spatial, not abstract.
2. **Runtime systems over proof artifacts** — features produce real state models (`RefCounted` per `RouteControlState`/`OxygenState` pattern), not screenshots.
3. **Every action has visible consequence** — HUD lines, room markers, collision toggles, extraction unlocks all reflect model state.
4. **Small vertical slices before broad systems** — one hazard, one tool, one objective type per slice, before generalizing.
5. **Source-backed structure** — feature spec → ADR → model/scene integration → model smoke → main-scene smoke → regression bundle.

---

## 2. Game Design Document (`docs/game/03_gdd.md`, 2,733 chars)

### 2.1 Vision
Locked-isometric 3D Godot game. Player moves through procedurally generated ships. Each ship has objectives, route gates, hazards, and an extraction completion. Loop is restoration-driven, with hazards as runtime pressure.

### 2.2 Core mechanics
- **Movement:** Locked-isometric, grid-aligned (Vector3 cells), player controller.
- **Interaction:** Single "use" verb on `Interactable` nodes (objective props, tool pickups).
- **Progression:** Sequence-based objective system (`ShipSystemState.apply_objective()`).
- **Route control:** Powered route gates start closed; restoring main power opens them; collision toggles, not deletes.
- **Hazards:** Oxygen breach zones drain oxygen while player is inside; seal action tied to objective 2 (per `hazards.md`). Beyond Gate 1: timed fire, electrical arc, hazard variety.
- **Inventory/tools (Gate 2+):** Pickups grant modifiers to hazard/objectives (oxygen pump halves drain; junction calibrator reduces repair steps).
- **Objective variation (Gate 2+):** Multi-step `repair_junction` objectives with per-step interactables.
- **Save/load (Gate 2+):** Single current-run slot at `user://saves/current_run.json`, auto-save on objective completion.

### 2.3 Scope
**Gate 1 (validated, Go 2026-06-19):** One ship slice, 4 objectives, oxygen hazard, route gates, locked-isometric player, HUD line. ~60–120 s playtime.
**Gate 2 (exited 2026-06-19):** Inventory/tool loop, timed fire, repair-junction objectives, current-run save/load.
**Gate 3+:** Hub/meta progression (per `09_system_roadmap.md`), second tool (junction calibrator), electrical arc hazard, layout templates B & C, procedural variation, asset packs.

### 2.4 Pillars (cross-ref §1.2)
See design pillars above.

---

## 3. Core Loop (`docs/game/02_core_loop.md`, 3,508 chars)

### 3.1 Loop diagram
```
SPAWN → ORIENT → TRAVERSE → RESTORE → EXTRACT
         ↑                ↓
         ←— ENCOUNTER HAZARDS ←—
              ↓                ↓
        EQUIP TOOL          REPAIR JUNCTION
```

### 3.2 Player actions (current implemented evidence)
| Phase | Action | System |
|---|---|---|
| Spawn | Player spawns at airlock, camera locks to isometric | `player_controller.gd` |
| Orient | Read HUD (`Objective:`, `Oxygen:`, `Tool:` lines) | `objective_tracker.gd` |
| Traverse | Move between rooms via grid cells | Grid pathfinding |
| Interact | Single verb on objective prop / tool pickup | `Interactable` node |
| Restore | Completing objectives updates `ShipSystemState`; route gates open | `route_control_state.gd` |
| Hazard encounter | Oxygen drains in breach zone; passability blocks at zero | `oxygen_state.gd` |
| Tool use (G2) | Pick up portable oxygen pump; halves drain in breach | `inventory_state.gd` |
| Multi-step (G2) | Repair junction (2/2), objective advances after both | `objective_progress_state.gd` |
| Fire (G2) | Wait for `clear_duration` to cross fire corridor | `fire_state.gd` |
| Save (G2) | F5 manual save, auto-save on objective completion | `save_load_service.gd` |
| Extract | Reach reactor after objective 4 (current slice) | `route_control_state.get_summary().extraction` |

### 3.3 Progression
- **Sequence-based:** `current_objective_sequence` increments per `apply_objective()` call.
- **ShipSystemState flags:** `emergency_supplies_recovered`, `main_power_restored`, `logs_downloaded`, `reactor_stabilized`.
- **Route control gate:** Driven by `main_power_restored` (clears blockers, opens gates).
- **Extraction unlock:** Driven by `reactor_stabilized` (sets `extraction = true`, deletes save file).

### 3.4 Loop gaps resolved
- **Gate 1 exit gap resolved:** "Hazard/survival pressure is not yet a real runtime loop" — oxygen breach zone validated.
- **Gate 2 backlog:** Inventory/tools (REQ-007), hazard variety (REQ-010), objective variation (REQ-011), save/load (REQ-012).

---

## 4. Technical Design Document (`docs/game/04_tdd.md`, 3,212 chars)

### 4.1 Architecture pattern
**Pure state models + scene coordinators.**
- Models: `RefCounted` classes (e.g., `RouteControlState`, `OxygenState`, `FireState`, `InventoryState`, `ObjectiveProgressState`, `ElectricalArcState`) with `configure()`, `tick()`, `apply_summary()`, `get_summary()`, `get_status_lines()`.
- Coordinators: Scene scripts (`scripts/procgen/playable_generated_ship.gd`) own model instances, feed them ticks from `_process`, propagate outputs to scene nodes (collision, Label3D, HUD).

### 4.2 What's tested
- **Model-level (unit):** Direct `*_state_smoke.gd` — pure model behavior in isolation.
- **Scene-level (integration):** `main_playable_slice_*_smoke.gd` — load slice, simulate interactions, assert observable state.
- **Bundle:** `06_validation_plan.md` regression bundle (120 commands as of ADR-0028, includes Gate 2 smokes + layout template smokes).

### 4.3 Test infrastructure
- **Godot 4.6.2** at `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Headless invocation: `godot --headless --path <project> --script res://scripts/validation/<smoke>.gd`.
- **Marker convention:** `<MODEL> STATE PASS ...` and `MAIN PLAYABLE <FEATURE> PASS ...` lines for grep-based CI.
- **Baseline teardown filter:** `06_validation_plan.md` allowlists two known lines (`ERROR: Capture not registered: 'gdaimcp'` and `WARNING: ObjectDB instances leaked at exit`); strict mode rejects all others.
- **Runner:** `set -euo pipefail` + `run_clean` per smoke, single one-shot regression script.

### 4.4 Architecture decisions deferred
- ADR-0005 (Multi-Hazard Architecture) — PhaseTimer helper, HazardStateContract, loader contracts.
- ADR recommended for tool data model generalization (currently per-tool conditional branches in `tool_definitions.json`).
- ADR recommended for objective graph (currently per-type wiring in coordinator).

---

## 5. Validation Plan (`docs/game/06_validation_plan.md`, 52,515 chars — largest doc)

### 5.1 Validation strategy
**Three-tier pyramid:**
1. **Model smokes** — fast, deterministic, pure state verification.
2. **Main-scene smokes** — load `main_playable_slice.tscn`, exercise feature, assert scene-level consequences.
3. **Regression bundle** — chained `set -euo pipefail` script, gates CI.

### 5.2 Regression bundle (current: 120 commands per ADR-0028)
- Gate 1 core (8): route_control, ship_systems, completion, input, readability, oxygen, hazard, automated_playtest.
- Gate 2 feature smokes: inventory_state, inventory_main, fire_state, fire_main, objective_variation_state, objective_variation_main, save_load_state, save_load_main, junction_calibrator_state, junction_calibrator_main, junction_calibrator_save_load_main, hud_smoke (`main_playable_slice_hud_smoke` per ADR-0027).
- Layout template smokes: template_b_completion, template_c_main_scenario.
- Per-feature tests as systems land.

### 5.3 Validation gates
- **Per-smoke:** Expected marker line + strict `^(ERROR|WARNING):` filter (allowing baseline).
- **Per-bundle:** `SYNAPSE_SEA REGRESSION PASS commands=<N> clean_output=true` marker.
- **Per-playtest:** `GATE <N> AUTOMATED PLAYTEST PASS` (current 2.00 average across 5 dimensions, Go decision).
- **Per-build:** `gate-1-regression-<YYYY-MM-DD>.md` artifact under `docs/game/playtests/`.

### 5.4 Acceptance criteria coverage
Every feature spec has explicit Given/When/Then acceptance criteria tied to marker strings. Validation plan indexes feature specs and their verification commands.

### 5.5 Playtest protocols
- **Human (`gate-1-playtest-protocol.md`):** Fresh-player observation, 10–15 min, two players minimum, 0–2 rubric scoring.
- **Automated (`automated-playtest-protocol.md`):** Headless simulation, framework-equivalent rubric via frame counts, HUD-change counts, gate counts, stuck events. Approved as alternate Gate 1 evidence source.

---

## 6. Risk Register (`docs/game/07_risk_register.md`, 2,017 chars)

### 6.1 Active risks (current)
| ID | Risk | Likelihood | Impact | Mitigation | Status |
|---|---|---|---|---|---|
| R1 | Hub/meta scope creep past Gate 2 | Low | High | ADR-0003 defers through Gate 2; anchored to Gate 3 entry planning | Mitigated |
| R2 | Oxygen drain tuning frustrates instead of pressures | Medium | Medium | OxygenTuning Resource, single source of truth | Tracked |
| R3 | Hazard model / ship-system race | Low | High | Scene coordinator order: ship-system summary → tick oxygen | Mitigated |
| R4 | Route-gate vs breach-zone collision misinterpretation | Low | Medium | Independent models, independent summaries | Mitigated |
| R5 | Hazard pressure too thin for Gate 1 exit criterion | Low | High | Tracked follow-up for second hazard type | Closed (fire added in Gate 2) |
| R6 | Tool pickup placement unreadable | Medium | Low | Label3D marker, side-room placement, smoke visibility assertion | Tracked |
| R7 | Multi-hazard copy-paste code | Medium | Medium | ADR-0005 HazardStateContract + PhaseTimer helper | Tracked |
| R8 | Save/load becomes hub/meta vector | Low | High | RunSnapshot explicitly excludes hub fields; code review checklist | Mitigated |
| R9 | Model summary drift from apply_summary() | Medium | Medium | Round-trip asserts in model smokes; review-card gate | Tracked |
| R10 | `user://` path differences editor vs export | Low | Low | Always use `ProjectSettings`, never hard-code | Mitigated |

### 6.2 No P0 architectural risks remain unmitigated (per Gate 1 review 2026-06-19).

---

## 7. System Roadmap (`docs/game/09_system_roadmap.md`, 11,969 chars)

### 7.1 Phases
1. **Gate 0 — Concept lock:** Vision, pillars, locked premise. **Status:** Go (provisional).
2. **Gate 1 — Pre-production / playable systems slice:** Route control, ship systems, oxygen hazard, HUD, locked-isometric movement. **Status:** Go (2026-06-19).
3. **Gate 2 — Production:** Inventory/tools, hazard variety, objective variation, save/load. **Status:** Exited (2026-06-19).
4. **Gate 3 — Hub/meta entry planning:** Hub ship scene, derelict selection, persistent unlocks, meta-currency (anchored by ADR-0003).
5. **Gate 4 — Alpha content-complete:** Layout templates A, B, C (3 unique ship layouts), procedural variation, second tool (junction calibrator, REQ-014), electrical arc hazard (REQ-013).
6. **Gate 5 — Release candidate / post-RC:** Open-world build, multi-derelict persistence, monster population model (deferred pillars).

### 7.2 Milestones
- **M1 (Gate 1):** 60–120 s slice, regression bundle green.
- **M2 (Gate 2):** Inventory/loop, 2 hazard types, 1 objective variation, save/load round-trip.
- **M3 (Gate 3):** Hub scene + derelict selector live.
- **M4 (Gate 4):** 3 templates × N seeds, procedural variation, Alpha tool variety (2 tools), Alpha hazard variety (3 types).
- **M5 (Gate 5):** RC shippable.

### 7.3 Planned systems (per roadmap)
- **Procedural generator:** Seed-diversity smokes, layout variation per template, blocked-link configuration per seed, hazard placement per seed.
- **Asset pipeline:** `ship_structural_v0` kit (current), planned modular kits per room role.
- **Open-world hooks:** Multi-derelict memory, monster spawning, faction simulation, fortification system.

---

## 8. Store Requirements (`docs/game/store_requirements.md`, 10,391 chars)

### 8.1 Platform targets
- **Primary:** itch.io (current Gate 5 RC scope).
- **Future:** Steam (post-Gate 5).

### 8.2 itch.io requirements (covered)
- Executable wrapper (Godot export template).
- README, credits, version.
- Platform builds: macOS, Linux, Windows.
- Screenshot pack, capsule art, trailer (optional).

### 8.3 Steam requirements (deferred)
- Steamworks SDK integration.
- Achievements, cloud saves, leaderboards.
- Steam Input (controller support).
- Rich presence, store page assets.
- Steam Deck verification.

### 8.4 Cross-cutting
- Age rating (IARC).
- Localization readiness (Gate 5+ deferred).
- Crash reporting / telemetry.

---

## 9. Export Pipeline (`docs/game/export_pipeline.md`, 3,961 chars)

### 9.1 Build pipeline
- **Engine:** Godot 4.6.2 stable at `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- **Export templates:** Godot's built-in export presets (Linux, macOS, Windows).
- **Headless validation:** Regression bundle runs against build before export.

### 9.2 Distribution
- **Current:** Direct file distribution via itch.io.
- **Asset paths:** User-scope saves at `user://saves/current_run.json`.
- **Build artifacts:** Exported binaries + headless smoke artifact + manifest.

### 9.3 Pipeline stages
1. Code → smoke → regression bundle.
2. Scene export (Godot export preset).
3. Asset bundle assembly.
4. Platform packaging.
5. Smoke run against packaged build.
6. Upload to distribution channel.

---

## 10. Project Workspace (`docs/game/PROJECT_WORKSPACE.md`, 701 chars)

### 10.1 Current state (snapshot)
- **Active gate:** Gate 5 (post-RC).
- **Godot:** 4.6.2 at `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- **Project:** `/Users/christopherwilloughby/the-synapse-sea-of-stars`.
- **Workspace model:** No git repository; ledger via `docs/` artifacts (per `AGENTS.md §Operating model`).
- **Smoke count:** 120 commands in regression bundle (per ADR-0028).

### 10.2 Active priorities
1. Gate 5 RC completion.
2. Open-world build state (multi-derelict persistence).
3. Layout templates B & C validation (Alpha content-complete).
4. Procedural variation generator (deferred to Gate 4).
5. Monster/fortification/faction pillars (deferred).

### 10.3 Blockers
None blocking Gate 5. Procedural variation and monster pillars are deferred and tracked in roadmap.

---

## 11. ADR Catalog (26 of 28 — 0004 and 0006 missing on disk)

| ADR | Title | Status | Decision summary | Implications |
|---|---|---|---|---|
| 0001 | Adopt stage-gate Kanban + Godot validation | Accepted | Stage-gate process (G0–G5), Kanban cards per feature, Godot headless smokes as CI | All features ship with model + main-scene smoke; bundle gates go/no-go |
| 0002 | Defer hub/meta past Gate 1 | Accepted | Hub/meta progression not in Gate 1 scope; reactor stabilization stands in for hub return | REQ-008 deferred; Gate 1 unit of play is single derelict slice |
| 0003 | Reaffirm hub-meta deferral through Gate 2 | Accepted | Hub/meta remains deferred through Gate 2; Gate 2 focuses on derelict exploration depth | REQ-009 deferred; Gate 3 entry planning anchored as next decision point |
| 0005 | Multi-hazard architecture | Accepted | `HazardStateContract` interface, `PhaseTimer` helper shared by `FireState`/`ElectricalArcState`; `OxygenState` implements contract without timer inheritance; loader contracts for `breach_zones`/`fire_zones`/`arc_zones` | Enables third hazard type (electrical arc) without copy-paste; Gate 4 deliverable |
| 0007 | Save/load service scope | Accepted | Current-run only; single slot at `user://saves/current_run.json`; explicit exclusion of hub/meta state | REQ-012 deliverable for Gate 2; saves auto-delete on completion |
| 0008 | Ship systems architecture | Accepted | `ShipSystemState` model owns `main_power_restored`, `logs_downloaded`, `reactor_stabilized`, etc.; coordinator feeds objective completions | Underpins route control and extraction unlock |
| 0009 | Retire ship-system state for manager | Accepted | Deprecated direct ship-system state ownership in favor of `ShipSystemState` model | Single source of truth for ship flags |
| 0010 | Player progression / current-run persistence | Accepted | Current-run snapshot includes player position, objective sequence, model summaries; no cross-run state | Foundation for REQ-012 save/load |
| 0011 | Ship instance and travel integration | Accepted | Player hub ship as first-class scene node; future travel hooks between derelicts | Open-world pillar foundation |
| 0012 | World persistence model | Accepted | Per-derelict persistence scoped to current run; cross-derelict memory deferred to Gate 3+ | Hub scene deferred |
| 0013 | Derelict gameplay parity | Accepted | All derelicts follow same template (ship layout + gameplay_slice JSON); objective sequence + hazards + route gates must be valid | Ensures uniform validation across seeds |
| 0014 | Loot / player inventory | Accepted | Single inventory state owned by slice; tool pickups acquire into inventory; effects read summary | Foundation for REQ-007 |
| 0015 | Ship repair loop | Accepted | Repair as objective-completion mechanism; objective 2 restores power and opens gates | Foundation for REQ-002 |
| 0016 | Ship docking foundation | Accepted | Docking mechanics deferred to Gate 3+; placeholder slots in template data | Future: hub↔derelict docking |
| 0017 | Physical docking and ports | Accepted | Physical port nodes on ships; docking requires port-to-port alignment | Gate 4+ deliverable |
| 0018 | Claim and pilot switch | Accepted | Player can claim a derelict and pilot it; future foundation for hub exploration | Gate 4+ pillar |
| 0019 | Hangar nesting | Accepted | Derelicts can carry smaller derelicts (hangar bay); recursion allowed | Open-world expansion mechanic |
| 0020 | Ship cargo holds | Accepted | Cargo holds as inventory containers; transfer between holds via container UI | Foundation for inventory UI work |
| 0021 | Equipment carts | Accepted | Portable equipment carts as movable interactables; storage + modifiers | Gate 4+ deliverable |
| 0022 | Inventory transfer UI | Accepted | Container-to-container drag-drop UI; uses container weight-reduction system | Foundation for inventory UI |
| 0023 | Inventory widget layer | Accepted | Inventory UI as scene-level widget; summary-driven from `InventoryState.get_status_lines()` | HUD integration for tools |
| 0024 | Suit oxygen wiring | Accepted | Suit oxygen modeled as resource consumed by player; tied to `OxygenState` | Hazard mitigation foundation |
| 0025 | Player vitals HUD | Accepted | `PlayerVitalsPanel` owns oxygen + load + status lines; HUD reads runtime state | Foundation for vitals UI |
| 0026 | Equip from container | Accepted | Player can equip tools from containers; container weight reduction applied | Container system integration |
| 0027 | Vitals/HUD cleanup (2026-06-25) | Accepted | `PlayerVitalsPanel` is sole home for oxygen + load; `ObjectiveTracker` no longer carries those lines | Single-source-of-truth for vitals; removes HUD duplication |
| 0028 | Per-container weight reduction (2026-06-25) | Accepted | Worn containers carry `weight_reduction` ∈ [0,1]; values: EVA Backpack 0.30, Field Pack 0.15, Tool Belt 0.10; pure capacity-share best-first computation | Container load calculation deterministic and auditable |

### Missing ADRs
- **ADR-0004:** Not on disk. Referenced in feature specs (`inventory_tools.md`, `tool_type_2.md`) as "Inventory/Tool Data Model" — to be authored if implementation generalizes beyond `tool_definitions.json` + per-tool conditional branches.
- **ADR-0006:** Not on disk. Referenced in `objective_variation.md` as "Objective Graph Architecture" — to be authored if Gate 3 expands to a generalized objective graph.

---

## 12. Feature Specs (`docs/game/features/`)

| Feature | File | Status | REQ | What it specifies | Dependencies |
|---|---|---|---|---|---|
| Route Control | `route_control.md` | Validated | REQ-001/002 | Powered route gates from blocked-route loader data; collision toggles not deletes | `RouteControlState` model, `ship_system_state` summary |
| Oxygen Hazard | `hazards.md` | Validated (G1) | REQ-006 | Depleting oxygen in breach zone, sealed by objective 2, zero-oxygen passability block | `OxygenState` model, `player_controller`, breach zone loader |
| Inventory / Tools | `inventory_tools.md` | Approved (G2) | REQ-007 | Portable oxygen pump pickup, halves drain in unsealed breach | `InventoryState`, `OxygenState.apply_inventory_summary()` |
| Fire Hazard | `hazard_variety.md` | Approved (G2) | REQ-010 | Timed fire zone, 4s burning / 3s cleared cycle, non-critical placement | `FireState` model, Label3D, StaticBody3D |
| Electrical Arc | `hazard_type_3.md` | Approved (Alpha) | REQ-013 | 2.5s arcing / 1.5s discharged cycle, short safe window demands commitment | `ElectricalArcState` (ADR-0005), `HazardStateContract` |
| Objective Variation | `objective_variation.md` | Approved (G2) | REQ-011 | Multi-step `repair_junction` objective, 2 steps unordered, sequence advances after both | `ObjectiveProgressState`, loader extension |
| Save / Load | `save_load.md` | Approved (G2) | REQ-012 | Single slot `user://saves/current_run.json`, auto-save on objective complete, manual F5/F9 | `SaveLoadService`, `RunSnapshot`, all Gate 2 models' `apply_summary()` |
| Junction Calibrator (Tool 2) | `tool_type_2.md` | Approved (Alpha) | REQ-014 | Single-use tool reduces `repair_junction` required_steps by 1, consumed on first eligible interaction | `InventoryState` extension, `ObjectiveProgressState.apply_junction_calibrator()` |
| Layout Template A | (implicit in `data/procgen/golden/coherent_ship_001/`) | Validated | REQ-001..003 | 2-deck horizontal spine with side rooms, single ramp, 4 objectives | Layout loader, `ship_structural_v0` kit |
| Layout Template B (Bifurcated) | `layout_template_b.md` | Validated | Content-complete | Y-shaped single-deck, 2 branches, 5 objectives, dedicated `tool_storage_01` | Layout loader, REQ-011 (repair_junction at seq 2), fire zone |
| Layout Template C (Stacked) | `layout_template_c.md` | In progress (Alpha) | Content-complete | 2-deck stacked, ramp + elevator vertical transitions, 5 objectives | Layout loader, ramp/elevator mechanics, oxygen breach on vertical corridor |
| Feature Spec Template | `feature_spec_template.md` | Template | — | Skeleton for new feature specs (status, pillars, fantasy, behavior, criteria, etc.) | None |

### Feature-to-gate mapping
- **Gate 1:** route_control, hazards (oxygen), layout A (implicit).
- **Gate 2:** inventory_tools, hazard_variety (fire), objective_variation, save_load.
- **Gate 4 / Alpha:** tool_type_2 (junction calibrator), hazard_type_3 (electrical arc), layout_template_b, layout_template_c.

---

## 13. Playtest Reports (`docs/game/playtests/`)

### 13.1 Gate 1 Regression Bundle — 2026-06-19 (`gate-1-regression-2026-06-19.md`)
- **Result:** PASS — `SYNAPSE_SEA REGRESSION PASS commands=8 clean_output=true`.
- **8/8 smokes passed:** route_control_state, main_route_control, oxygen_state, main_hazard, main_ship_systems, main_completion, main_input, main_readability.
- **No unexpected `ERROR:`/`WARNING:`** outside baseline Godot teardown lines.
- **Workspace:** No-git per `AGENTS.md §Operating model`; ledger via docs artifacts.

### 13.2 Gate 1 Automated Playtest — 2026-06-19 (`gate-1-automated-2026-06-19.md`)
- **Decision:** **Go** — `pass_decision=GO`.
- **Rubric scores (all 2/2):**
  - route_readability = 2 (arrive_frames=1 ≤ 180)
  - objective_clarity = 2 (hud_changes=5 ≥ 4)
  - visible_consequences = 2 (gates=1, hud=5, extraction=true — 3 of 3 signals)
  - camera_readability = 2 (stuck_events=0)
  - engagement = 2 (objectives=4, total_frames=79 < 3600)
  - **overall_average = 2.00**
- **Acceptance checklist:** all 6 boxes checked (regression passes, script completes, 5 dimensions scored, average computed, decision recorded, artifact saved).
- **No follow-up cards** spawned (no rubric item below 2).

### 13.3 Gate 1 Rubric Summary (`gate-1-rubric-summary.md`)
- **n = 1** session (single automated log).
- **All dimension means = 2.00** — passes Gate 1 Go threshold (≥ 1.5, no hard-criterion 0).
- **Caveat:** Human playtest recommended before production-readiness sign-off but not Gate 1 blocker.

### 13.4 Protocols (templates, not session logs)
- **`gate-1-playtest-protocol.md`:** Human fresh-player protocol; 10–15 min sessions; 0–2 rubric; two-player minimum; observer-only.
- **`automated-playtest-protocol.md`:** Headless automation as alternative evidence source; approved for Gate 1 Go/Recycle/Hold.
- **`playtest_template.md`:** Per-session log skeleton (build state, scenario, observations, rubric, decision).

### 13.5 Raw artifact
- **`regression-run-2026-06-19.log`:** 138 lines, full per-smoke stdout/stderr + RESULT lines + final summary.

### 13.6 Action items
None open from Gate 1. Human playtest follow-up recommended pre-production but not blocking.

---

## 14. Gate 2 Docs (`docs/gate2/`)

### 14.1 Scope note (`docs/gate2/gate2-scope-note.md`, 5,676 chars)
Gate 2 scope is bounded by ADR-0003 (defer hub/meta through Gate 2) and REQ-009:
- **In scope:** Inventory/tools (REQ-007), hazard variety (REQ-010), objective variation (REQ-011), current-run persistence (REQ-012).
- **Out of scope:** Hub ship scene, derelict selection, persistent unlocks, meta-currency, faction progression, hub save state.
- **Exit review (2026-06-19):** Go / exited.

### 14.2 Feature card mapping (from `08_milestone_gates.md`)
| Card | REQ | Status |
|---|---|---|
| Plan inventory/tool loop (`t_9da25ff4`) | REQ-007 | Implemented/Validated |
| Implement inventory/tool loop (`t_03fe5d4b`) | REQ-007 | Implemented/Validated |
| Review inventory/tool loop (`t_c98c338d`) | REQ-007 | Implemented/Validated |
| Plan timed fire hazard (`t_9ed42811`) | REQ-010 | Implemented/Validated |
| Implement timed fire hazard (`t_e7392255`) | REQ-010 | Implemented/Validated |
| Review timed fire hazard (`t_d357d336`) | REQ-010 | Implemented/Validated |
| Plan repair-junction (`t_0e92da72`) | REQ-011 | Implemented/Validated |
| Implement repair-junction (`t_abdf39e0`) | REQ-011 | Implemented/Validated |
| Review repair-junction (`t_d2ebf6cf`) | REQ-011 | Implemented/Validated |
| Plan save/load (`t_e0f4889c`) | REQ-012 | Implemented/Validated |

### 14.3 Gate 2 subdirectories
- **`docs/gate2/plans/`** — directory exists; contents not enumerated (likely individual card plans).
- **`docs/gate2/proofs/`** — directory exists; empty or proof artifacts.
- **`docs/gate2/specs/`** — directory exists; possibly supplemental Gate 2 specs.

### 14.4 Remaining Gate 2 work
- Gate 2 exited per `08_milestone_gates.md`; no remaining work for Gate 2 itself.
- Forward work is Gate 3 (hub/meta entry) and Gate 4 (Alpha content-complete).

---

## 15. Cross-Reference Index

### 15.1 Requirements traceability (`docs/game/05_requirements.md`)
- **REQ-001 — Route gates are real runtime blockers:** Validated.
- **REQ-002 — Restoring systems opens powered gates:** Validated.
- **REQ-003 — Reactor stabilization unlocks extraction:** Validated.
- **REQ-004 — New systems need model + scene validation:** Approved (process).
- **REQ-005 — No proof-only milestone substitution:** Approved (process).
- **REQ-006 — Hazard pressure loop:** Validated (oxygen breach; extended in Gate 2 by fire).
- **REQ-007 — Inventory/tool loop:** Gate 2 deliverable.
- **REQ-008 — Hub/meta persistence:** Deferred (ADR-0002).
- **REQ-009 — Gate 2 scope lock:** Approved via ADR-0003.
- **REQ-010 — Hazard variety:** Gate 2 deliverable (fire).
- **REQ-011 — Objective variation:** Gate 2 deliverable (repair_junction).
- **REQ-012 — Save/load run persistence:** Gate 2 deliverable.
- **REQ-013 — Alpha hazard variety:** Approved for Alpha (electrical arc).
- **REQ-014 — Alpha tool variety:** Approved for Alpha (junction calibrator).

### 15.2 Milestone gates (`docs/game/08_milestone_gates.md`)
- **Gate 0 — Concept lock:** Go (provisional).
- **Gate 1 — Pre-production slice:** **Go (2026-06-19).** Decision cites automated protocol + 8/8 regression + 5-dimension rubric average 2.00.
- **Gate 2 — Production:** **Go / exited (2026-06-19).**
- **Gate 3 — Hub/meta entry:** Anchored as next decision point (ADR-0003).
- **Gate 4 — Alpha content-complete:** Open (3 templates, 2 tools, 3 hazard types).
- **Gate 5 — Release candidate:** Historical / post-RC.

### 15.3 Key invariants
- **No P0 architectural risk unmitigated** (Gate 1 review).
- **All Gate 1 + Gate 2 deliverables validated** (model + scene smokes + regression bundle).
- **No proof-only artifacts substitute for runtime evidence** (REQ-005 / design pillar).
- **Hub/meta deferred through Gate 2** (ADR-0002, ADR-0003, REQ-008, REQ-009).

### 15.4 File index summary
- **Game docs (15 files):** 00_vision, 01_design_pillars, 02_core_loop, 03_gdd, 04_tdd, 05_requirements, 06_validation_plan, 07_risk_register, 08_milestone_gates, 09_system_roadmap, PROJECT_WORKSPACE, store_requirements, export_pipeline.
- **ADRs (26 of 28):** 0001–0003, 0005, 0007–0028 (missing 0004, 0006).
- **Feature specs (11 files):** route_control, hazards, inventory_tools, hazard_variety, hazard_type_3, objective_variation, save_load, layout_template_b, layout_template_c, feature_spec_template, tool_type_2.
- **Playtests (6 files):** gate-1-regression-2026-06-19, gate-1-automated-2026-06-19, gate-1-rubric-summary, gate-1-playtest-protocol, automated-playtest-protocol, playtest_template, regression-run-2026-06-19.log.
- **Gate 2 (4 entries):** scope-note, plans/, proofs/, specs/.

---

*End of synthesis. All 13 requested sections covered. Total: ~26 ADRs reviewed, 11 feature specs reviewed, 6 playtest artifacts reviewed, full validation plan and roadmap ingested.*