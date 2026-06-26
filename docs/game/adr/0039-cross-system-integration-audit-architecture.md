# ADR-0039: Cross-System Integration Audit Architecture

## Status

Accepted for Task 14.

## Context

Tasks 01-13 added survival, food, crafting, loot, consumables, combat, ship systems, progression/meta, UI, audio, save/load, procgen, and release/distribution packages. Each package has its own model and smoke evidence, but Task 14 needs to prove that the package set is source-backed and product-coherent.

The risky failure mode is a checklist-only review: each subsystem passes alone while the player loop still has missing links, stale docs, or untracked contradictions.

## Decision

Use pure data-backed audit models rather than another scene coordinator:

- `IntegrationMatrix` owns package rows and loop-stage coverage.
- `DependencyValidator` checks cited source files, requirement headings, docs, and registered smoke markers.
- `BalanceLedger` stores deterministic safe ranges for integrated scenarios.
- `AutomatedPlaytestRubric` scores scripted scenario summaries and can accept future main-scene or human logs.
- `ProductAuditReport` validates product findings and requires fix-card links for tracked contradictions.

The five Task 14 smokes are the authoritative validation surface for this package. They are registered in the regression bundle but do not mutate gameplay state.

## Consequences

- The integration audit remains headless, deterministic, and cheap to run.
- The package can catch stale source evidence without needing the full playable scene to boot.
- The e2e survival-loop smoke proves stage coverage and balance sanity, while `e2e_combat_loot_craft_smoke.gd` and `e2e_ship_meta_loop_smoke.gd` compose live production models for the highest-risk links.
- A true controller/HUD main-scene e2e remains a separate follow-up because conflating it with Task 14 would make this review package too broad.

## Alternatives considered

1. **Full main-scene mega-smoke only.** Rejected because it would be brittle and would not validate docs/requirements/ADR evidence.
2. **Docs-only product audit.** Rejected because it would violate the repo rule against proof-only milestone substitutes.
3. **Per-package rerun only.** Rejected because it would not prove loop-stage coverage or contradiction handling.

## Validation

- `scripts/validation/cross_system_dependency_smoke.gd`
- `scripts/validation/e2e_survival_loop_smoke.gd`
- `scripts/validation/e2e_combat_loot_craft_smoke.gd`
- `scripts/validation/e2e_ship_meta_loop_smoke.gd`
- `scripts/validation/product_audit_smoke.gd`
