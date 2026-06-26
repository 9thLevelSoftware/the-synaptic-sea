# Task 08: Player Progression, Skills, Classes, Hub & Meta-Progression — Standalone E2E Package Plan

Generated: 2026-06-25T19:59:51-04:00

## Objective
Deliver a complete, production-grade, independently testable package for **Player Progression, Skills, Classes, Hub & Meta-Progression**.

## Source requirements
- Package requirement range: REQ-PM-001..010
- Source map: `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`
- Planning synthesis: `docs/PLANNING_SYNTHESIS.md`
- Vision/core loop: `docs/game/00_vision.md`, `docs/game/02_core_loop.md`
- Validation rules: `docs/game/06_validation_plan.md`
- Repo operating model: `AGENTS.md`

## Concept lock
Full learn-by-doing progression: class roster, skill tree, skill books/schematics, cross-training, hub upgrades, meta state, unlockables, and death/run rules.

## Project Zomboid influence, translated in-character
PZ occupations, traits, skill books, learn-by-doing, persistent world/new character loop translated to pre-collapse roles and hub ship persistence.

This is influence, not copying: every mechanic must read as locked-isometric 3D space-horror survival aboard derelict ships trapped in a biomatter Synaptic Sea field.


## Non-negotiable package contract
- This is not a stub, spike, proof-only artifact, or partial feature slice.
- The package is complete only when design docs, requirements, ADRs, data schemas, runtime code, UI/UX/audio/asset seams, persistence, smokes, regression-bundle entries, balance/tuning notes, and production acceptance evidence all exist.
- HTML mockups, PNG/contact sheets, screenshot galleries, or docs-only proof cannot substitute for in-engine runtime behavior unless this package explicitly says the output is documentation-only.
- New gameplay state must be pure-model-first (`RefCounted` or `Resource`), with Nodes applying scene consequences.
- Every new persistent model must implement `configure`, `tick` where relevant, `get_summary`, `apply_summary`, and `get_status_lines` or the package-specific equivalent.
- Every new warning/error in Godot output blocks completion unless classified in `docs/game/06_validation_plan.md` with evidence.
- Every package must use ASCII smoke markers and deterministic seeds.

## Required source-backed paperwork
1. Feature spec under `docs/game/features/` or `docs/superpowers/specs/`, citing this package plan.
2. Requirement rows in `docs/game/05_requirements.md`.
3. ADR(s) under `docs/game/adr/` for architecture/data-model decisions.
4. Risk register row in `docs/game/07_risk_register.md`.
5. Validation-plan entries in `docs/game/06_validation_plan.md`.
6. Roadmap/systems-map update after implementation evidence exists.
7. Balance/tuning note under `docs/game/balance/` when gameplay numbers are involved.

## Standard implementation sequence
1. RED: add/extend validation smoke(s) and schema checks; prove they fail for the missing system using marker absence, not exit code alone.
2. Design lock: write feature spec, requirements, ADR, data schema, and balance targets.
3. Pure model: implement deterministic model(s), summaries, and pure-model smoke(s).
4. Runtime integration: wire through `PlayableGeneratedShip`, managers, interactables, inventory/cargo/save systems as applicable.
5. UI/UX/audio/assets: add player-facing panel/feedback and placeholder assets sufficient for locked-isometric readability.
6. Persistence: prove save/load, travel, reload, and mid-action persistence for any state that can survive a frame.
7. Main-scene smoke: exercise the system through `res://scenes/main.tscn` or the package-specific scene, not only through pure models.
8. Regression bundle: register all smokes in `docs/game/06_validation_plan.md` and run the focused smoke(s) plus the appropriate bundle.
9. Product audit: describe what a player actually sees/does and why it is in-character for the Synaptic Sea/biomatter web fantasy.
10. Commit hygiene: provide changed files, commands, output markers, and if executed by Kanban worker, complete with evidence; do not block for vague human review.

## Standard verification command shape
Use the Synaptic Sea checkout explicitly even if older docs default to the Synaptic Sea path:

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2 /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea --script res://scripts/validation/<smoke>.gd
```

Then run the relevant focused bundle from `docs/game/06_validation_plan.md` with `ROOT=/Users/christopherwilloughby/the-synaptic-sea`.


## Package scope

### Required systems/models
- PlayerProgressionState expansion
- MetaProgressionState
- TrainingEventBus
- SkillTreeState
- HubUpgradeState
- UnlockRegistry

### Required data/config/resources
- classes.json expansion/audit
- skills.json full tree
- skill book/schematic definitions
- hub upgrade definitions
- unlock tables

### Required runtime integration
- training event hooks from repair/combat/crafting/discovery
- hub upgrade application
- meta snapshot service
- run-end processing

### Required UI/UX/player feedback
- skill tree panel
- class panel
- hub upgrade panel
- unlock/codex notifications

### Required asset/audio seams
- class icons
- skill category icons
- hub upgrade placeholders

### Required smoke/validation files
- player_progression_full_smoke.gd
- cross_training_smoke.gd
- training_by_item_smoke.gd
- meta_progression_state_smoke.gd
- meta_snapshot_smoke.gd
- skill_tree_panel_smoke.gd

### Required PASS markers
- PLAYER PROGRESSION FULL PASS
- META PROGRESSION STATE PASS
- META SNAPSHOT PASS
- SKILL TREE PANEL PASS

## Acceptance criteria
- All declared classes and skills are data-driven and active.
- Every major gameplay loop emits XP/training events.
- Meta progression persists separately from current-run state.
- Death/run-end rules are implemented and tested.

## Detailed development checklist

### 0. Contract and gap review
- Re-read every existing file listed under Source requirements.
- Identify existing classes/data that must be extended rather than replaced.
- Write a short `docs/game/build-plans/evidence/progression-skills-meta-contract-review.md` with existing files, missing files, and chosen extension seams.
- Stop if an existing ADR directly contradicts this package; write an ADR update rather than guessing.

### 1. Feature spec and requirements
- Create or update the feature spec for this package.
- Add requirement rows for REQ-PM-001..010 with status transitions: Proposed -> Approved -> Validated.
- Add explicit Given/When/Then acceptance criteria matching the smokes listed above.
- Add non-goals so workers cannot shrink scope into a partial slice.

### 2. ADR and data model
- Write ADR(s) for the package architecture and data model.
- Define the data/config resources listed above.
- Add schema/static validation for every new JSON/Resource field.
- Include migration/default behavior for older saves or missing optional fields.

### 3. Pure model implementation
- Implement the required systems/models as pure testable state.
- Models must not reach into the scene tree.
- Add deterministic model smokes and round-trip summary tests.
- Include boundary tests for thresholds, empty inputs, malformed data, and unknown IDs.

### 4. Runtime integration
- Wire through existing coordinators, managers, inventory/cargo/save systems, and interactables.
- Keep root manager public APIs backward compatible unless an ADR explicitly changes them.
- Add main-scene smoke(s) that exercise real gameplay path(s), not only construction.
- Ensure every player action creates visible consequence.

### 5. UI, audio, assets, and accessibility
- Add player-facing UI and feedback listed above.
- Add placeholder assets sufficient for readability; final art can replace them later, but the runtime feature cannot depend on missing art.
- Add audio event seams even if final audio assets are placeholder.
- Ensure color, icon, and text feedback have accessibility fallbacks.

### 6. Persistence and migration
- Add summary fields to RunSnapshot/WorldSnapshot/MetaSnapshot only where the state truly persists.
- Add save/load smoke for non-default state, mid-action state, and malformed/missing-field recovery.
- Prove no duplicate items, lost progress, or stale state after reload.

### 7. Balance and tuning
- Store numbers in tuning resources/data, not magic constants.
- Document safe ranges and difficulty presets.
- Add at least one automated balance sanity check or deterministic scenario.

### 8. Regression registration
- Register every smoke in `docs/game/06_validation_plan.md`.
- Run focused smokes first, then the relevant regression bundle with `ROOT=/Users/christopherwilloughby/the-synaptic-sea`.
- Capture markers and unexpected warnings/errors.

### 9. Production-grade closeout
- Update systems map, roadmap, requirements, ADR index, validation plan, and risk register with actual file evidence.
- Provide changed files, commands run, PASS markers, and any accepted caveats.
- If a Kanban worker executes this package, complete the card only after evidence is fresh; do not block for generic human review because `synaptic_seareview`/GPT-5.5 is the designated reviewer.

## Stop/block conditions
- Missing source assets or credentials that cannot be replaced with a runtime placeholder.
- A required Godot feature is unavailable in 4.6.2 and no equivalent path exists.
- An ADR conflict cannot be resolved locally.
- Regression failures unrelated to the package should be reported with evidence and, if needed, a separate unblock/fix card; do not silently mark this package done.
