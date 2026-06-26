# Cross-System Integration Review — Contract Review Evidence

Task: `t_12bf9f4a`
Plan: `docs/game/build-plans/14-cross-system-integration-review-e2e.md`
Reviewer: `synapse_seareview` / GPT-5.5

## Existing files read

- `AGENTS.md`
- `docs/game/build-plans/14-cross-system-integration-review-e2e.md`
- `docs/game/00_vision.md`
- `docs/game/02_core_loop.md`
- `docs/game/05_requirements.md`
- `docs/game/06_validation_plan.md`
- `docs/game/07_risk_register.md`
- `docs/game/09_system_roadmap.md`
- `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`
- `docs/PLANNING_SYNTHESIS.md`
- Representative package smokes and models for release readiness, crafting, loot, combat, ship systems, meta progression, and hub upgrades.

## Existing extension seams

- Pure-model scripts under `scripts/systems/` already use `configure`, `get_summary`, `apply_summary`, and `get_status_lines` patterns.
- Validation smokes under `scripts/validation/` use `extends SceneTree`, stable ASCII pass markers, and explicit `_fail(...)` helpers.
- The validation plan has a strict regression `run_clean` harness with known baseline warning allowlists.
- Kanban already has Task 15 (`t_c7ac4d08`) for final systems-map, roadmap, requirements, manifest, and board currency.

## Missing files before Task 14

- `scripts/systems/integration_matrix.gd`
- `scripts/systems/dependency_validator.gd`
- `scripts/systems/balance_ledger.gd`
- `scripts/systems/automated_playtest_rubric.gd`
- `scripts/systems/product_audit_report.gd`
- `data/integration/cross_system_integration_matrix.json`
- `data/integration/balance_ledger.json`
- `data/integration/automated_playtest_rubric.json`
- `data/integration/product_audit_report.json`
- `data/integration/known_issue_fix_manifest.json`
- Task 14 focused smokes listed in the plan.
- `docs/game/features/cross_system_integration_review.md`
- `docs/game/adr/0039-cross-system-integration-audit-architecture.md`
- `docs/game/balance/cross_system_balance_ledger.md`

## Chosen extension seams

- Add pure audit models rather than adding responsibility to `PlayableGeneratedShip`.
- Store package evidence in JSON data under `data/integration/` so it can be machine-checked.
- Register focused smokes in `docs/game/06_validation_plan.md` and requirements `REQ-INT-001..010`.
- Treat source-map/roadmap currency contradictions as tracked work under Task 15 rather than silently caveating them.
- Create follow-up `t_4e47145d` for a stronger live main-scene/controller e2e path.

## Product audit findings

- Parent packages have enough code/docs/smoke evidence to build a cross-system matrix.
- The seven-stage loop is represented by deterministic rubrics and composite model smokes.
- Some living docs still contain historical/stale status rows; Task 15 is already the explicit fix card.
- Task 14 does not claim a human playtest or live controller-path e2e proof; `t_4e47145d` tracks that follow-up.

## No ADR conflict found

No existing ADR contradicts the Task 14 model-first audit approach. ADR-0039 documents the new integration-audit layer.
