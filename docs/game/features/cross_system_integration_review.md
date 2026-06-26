# Feature: Cross-System Integration Review

## Status

Validated by Task 14 after focused smoke evidence and the full 163-command regression bundle.

## Design pillar alignment

- Spatial coherence first: every dependency row ties the loop stage back to a runtime system or player-visible consequence.
- Runtime systems over proof artifacts: the package adds pure RefCounted audit models and headless smokes instead of screenshot or mockup proof.
- Every action has visible consequence: the automated rubric requires visible consequences for prepare, derelict, survive, loot, craft, return, and upgrade stages.
- Source-backed structure: the integration matrix points to requirements, feature specs, ADRs, code files, data files, and validation markers.

## Player fantasy

The player fantasy is no longer a set of isolated systems. A successful short run should read as: prepare a loadout, board a derelict, survive pressure, loot useful material, craft or repair something, return progress home, and convert the outcome into an upgrade or future advantage.

## Gameplay problem

Tasks 01-13 landed many systems independently. Task 14 proves the pieces interlock, identifies contradictions, and turns remaining product gaps into explicit fix cards.

## Core behavior

Task 14 introduces five pure models:

- `IntegrationMatrix`: normalizes the package dependency matrix.
- `DependencyValidator`: verifies code, docs, requirement, and validation marker evidence.
- `BalanceLedger`: checks deterministic balance thresholds for integrated scenarios.
- `AutomatedPlaytestRubric`: scores scripted e2e scenario summaries.
- `ProductAuditReport`: validates the GPT-5.5 product audit and links findings to fix cards.

## Inputs

- `data/integration/cross_system_integration_matrix.json`
- `data/integration/balance_ledger.json`
- `data/integration/automated_playtest_rubric.json`
- `data/integration/product_audit_report.json`
- `data/integration/known_issue_fix_manifest.json`
- Existing Task 01-13 requirements, feature specs, ADRs, code, data, and smoke markers.

## Outputs

- `CROSS SYSTEM DEPENDENCY PASS`
- `E2E SURVIVAL LOOP PASS`
- `E2E COMBAT LOOT CRAFT PASS`
- `E2E SHIP META LOOP PASS`
- `PRODUCT AUDIT PASS`
- Explicit Kanban follow-up for the live main-scene/controller-path e2e probe (`t_4e47145d`, now complete).
- Full-bundle marker `SYNAPTIC_SEA REGRESSION PASS commands=163 clean_output=true` after resolving the tracked rigid-pair/adjacent validation preconditions.

## Rules

- Matrix rows must cite real files that exist in the checkout.
- Requirement ids must appear as headings in `docs/game/05_requirements.md`.
- Smoke markers must be registered in `docs/game/06_validation_plan.md`.
- Known contradictions must link to a task/card id, not prose-only caveats.
- Balance checks are sanity gates, not final tuning claims.

## Non-goals

- This package does not replace Task 15's systems-map/manifest final currency pass.
- This package does not create final art/audio/polish assets.
- This package does not claim a human fresh-player playtest or a full controller-path playable e2e run; a follow-up card tracks that stronger probe.

## Technical design

Affected files:

- `scripts/systems/integration_matrix.gd`
- `scripts/systems/dependency_validator.gd`
- `scripts/systems/balance_ledger.gd`
- `scripts/systems/automated_playtest_rubric.gd`
- `scripts/systems/product_audit_report.gd`
- `scripts/validation/cross_system_dependency_smoke.gd`
- `scripts/validation/e2e_survival_loop_smoke.gd`
- `scripts/validation/e2e_combat_loot_craft_smoke.gd`
- `scripts/validation/e2e_ship_meta_loop_smoke.gd`
- `scripts/validation/product_audit_smoke.gd`

## Acceptance criteria

- Given the cross-system integration matrix, when `cross_system_dependency_smoke.gd` runs, then every cited package dependency has existing code/docs/smoke evidence and registered markers.
- Given the seven-stage scenario, when `e2e_survival_loop_smoke.gd` runs, then prepare -> derelict -> survive -> loot -> craft -> return -> upgrade coverage passes the rubric and balance ledger.
- Given combat, loot, inventory, material, and crafting models, when `e2e_combat_loot_craft_smoke.gd` runs, then a damage event, deterministic loot roll, and `power_cell` craft all compose in one smoke.
- Given power routing, meta payout, and hub upgrade models, when `e2e_ship_meta_loop_smoke.gd` runs, then a repaired/returned run can buy `hub_storage_basic`.
- Given the product audit report, when `product_audit_smoke.gd` runs, then all contradictions have linked fix cards and no untracked blockers remain.
- Given the full regression bundle in `docs/game/06_validation_plan.md`, when it runs against the Task 14 retry workspace, then it emits `SYNAPTIC_SEA REGRESSION PASS commands=163 clean_output=true` with no unallowlisted `ERROR:`/`WARNING:` lines.

## Validation

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cross_system_dependency_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/e2e_survival_loop_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/e2e_combat_loot_craft_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/e2e_ship_meta_loop_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/product_audit_smoke.gd
```

## Risks

- A matrix can go stale after future packages; Task 15 owns final board/source-map currency.
- Composite smokes can miss real input/HUD regressions; follow-up `t_4e47145d` added a live main-scene/controller probe.

## ADRs

- `docs/game/adr/0039-cross-system-integration-audit-architecture.md`
