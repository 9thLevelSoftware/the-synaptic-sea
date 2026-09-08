# Parallel AI coordination — 2026-09-08

This is an ownership handoff, not a completion report. The full feature-completion goal remains active.

## Current coordinator checkout

- Worktree: D:/the-synaptic-sea-feature-completion
- Branch: codex/feature-completion-resume
- Latest coordinator checkpoint: 8dc8b08e (the branch may advance; inspect current HEAD before integration).
- Significant uncommitted R10 work is present. A checkout of this commit alone does not include those changes.
- Original D:/the-synaptic-sea checkout is not this execution worktree.

## Reserved to the current AI

1. R10 physical docking: explicit exterior portal compilation; strict endpoint, placement, navigation and spawn identity; reject every positive cross-hull intersection; single validated fresh-player placement; focused runtime tests and independent review. The docking baseline is now reviewed, validated, and committed; retain ownership for dependent integration fixes.
2. Run-7/world-7 transition: exact owner-local player pose; docking and hangar attachment records; persistent active/inactive door states; historical world-6 geometry/combat migration; hallucination reset; explicit launched free-root authority. The run-7 migration/save model and world-7 pure snapshot/restore-candidate model are reviewed and committed. Two workers currently own strict current-integrity admission and frozen historical world-6 attachment projection. Historical damage migration and live capture/restore integration follow; the full transition is not complete.
3. Following that dependency chain: R04/R05 natural crafting/economy proof, R07 machinery condition, R08 paid repair, R09–R16 rebuild safety/timing/replacement/persistence/claim/pilot/travel/player journey. These are reserved, not all currently executing.
4. Shared acceptance registry, generated Kanban cards, central feature-completion specification/ADR, canonical regression integration, commits and integration for this branch.

### Reserved file families

- scripts/procgen/dock_endpoint_authoring.gd, structural_edge_compiler.gd, structural_plan_validator.gd, life_boat.gd, ship_layout_generator.gd, ship_generator.gd, playable_generated_ship.gd
- scripts/systems/dock_ports.gd, docking_manager.gd, hangar_bay.gd and ship ownership/attachment models
- scripts/systems/run_snapshot.gd, world_snapshot.gd, save_load_service.gd, save_migration_service.gd, save candidate/restore owners and new world_v6 migration helpers
- Crafting, machinery condition/repair, rebuild/replacement and related save integration owners
- scripts/validation/r10a_*.gd and docking, structural-opening, migration, rebuild and crafting integration smokes
- tools/build_feature_acceptance.py, data/validation/feature_completion_cards.json, docs/game/inventory/feature_acceptance.json
- docs/game/features/crafting_derelict_feature_completion.md, docs/game/adr/0065-structural-replacement-safety-and-scene-commit.md, STATUS.md, docs/game/06_validation_plan.md
- Current plan-local progress ledger and evidence packages
- `tools/rebuild_vertex_span_modules.py`, the inner/outer corner and T-junction source/GLB/wrapper/contract families, their collision projection in `data/kits/ship_structural_v0.json`, and `assets/_source/recovered/ship_structural_v0/.gdignore`. These are being corrected to use vertex-owned rays and complete wall half-span coverage.

## Suitable independent assignments

### Exact active implementation ownership

- Current-integrity admission: `scripts/systems/module_integrity_map.gd`, `scripts/systems/module_integrity_state.gd`, `scripts/systems/run_snapshot.gd`, `scripts/systems/world_snapshot.gd`, and `scripts/validation/r10a_integrity_admission_smoke.gd`. Final focused six-smoke bundle reported green; independent review remains.
- Historical attachment projection: `scripts/systems/world_v6_layout_projection.gd`, `data/migrations/world_v6_geometry_authority_v1.json`, and `scripts/validation/r10a_world6_layout_projection_smoke.gd`. Qualification against captured historical fallback/native outputs and independent review remain.
- Coordinator: shared governance, evidence review, integration, and the reserved dependency chain above. Reserved follow-on work is not all actively executing.

The three assignments below are held for the external AI; the current coordinator will not implement them while this ownership split is in effect.

### A. R17 UI/accessibility (recommended)

Own a bounded subset first: mouse menu navigation, settings submenu routing, binding-reflective controller glyphs, or tutorial expiry/dismissal. The reviewed source audit identifies seven concrete gaps; do not treat all fourteen audited criteria as missing implementation. Difficulty propagation and hold-to-tap touch central gameplay and need a separately coordinated integration patch.

Read docs/game/features/ui_ux_accessibility.md and the source trace at .superpowers/sdd/2026-09-05-remaining-feature-completion/r17-accessibility-exact-trace.md in the current worktree. That trace is local preparation and may not exist on a fresh branch. Implement in the relevant scripts/ui owners and focused UI tests. Use a separate branch/worktree, and return any required playable_generated_ship.gd changes as an explicitly identified integration patch. Do not change the reserved central monolith in this shared checkout.

Acceptance must demonstrate real player-facing behavior and meaningful focused tests. Reduced Motion is dormant/unproven; do not invent animation solely to disable it. Gamepad absence was not established; verify real input behavior before claiming a gap.

### B. R17 authored audio bus authority

Read .superpowers/sdd/2026-09-05-remaining-feature-completion/r17-authored-audio-config-brief.md in the current worktree. Fix AudioManager production construction so validated data/audio/audio_bus_config.tres is the default authority, detached per manager; preserve saved user overrides and reject invalid authored configuration. Own scripts/audio/audio_manager.gd and relevant audio smoke tests. Keep any central playable construction change as a separate integration patch. No broad audio rewrite.

### C. R17 threat flee-path correctness

Independently investigate and repair the established weighted-path/FIFO concern in fleeing behavior against the existing threat design and tests. First localize the production path and show a failing behavioral case; do not change threat save schemas or migration contracts. Return exact source ownership before broadening scope.

## Collaboration and verification rules

Use a separate branch/worktree for the other AI. Do not reset, clean, commit, or overwrite this execution worktree. Do not merge or push the coordinator branch. Current Godot execution in this worktree is reserved to the run-7 save-transition worker, who coordinates world-7 tests; another worktree may run tests only with its own isolated user-data roots and retained probe evidence. Never use the real/default save profile.

Follow repository Stage-Gate rules in the separate branch: feature/requirement/acceptance updates precede implementation. Return central registry/card/canonical-list changes as a separate proposed patch for integration, not edits to the live coordinator checkout. Preserve the frozen requirement scope; the newer proposed UI presentation program is not automatically admitted.

Return a concise handoff with exact commit(s), changed files, requirement IDs, commands and exit codes, PASS markers and diagnostics, evidence paths, unresolved findings, and central integration dependencies. Do not claim complete from exit code alone. The coordinator will integrate and independently review before promoting acceptance.
