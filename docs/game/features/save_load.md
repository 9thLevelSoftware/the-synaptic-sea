# Feature: Save / Load, Persistence, Multi-Slot, Auto-Save, and Cloud Readiness

## Status
Approved for Gate 2 implementation and Task 11 E2E validation.

## Package source of truth
- `docs/game/build-plans/11-save-load-persistence-e2e.md`
- `docs/game/adr/0007-save-load-service-scope.md`
- `docs/game/adr/0031-multi-slot-save-architecture.md`
- `docs/game/adr/0032-migration-permadeath-cloud-manifest.md`
- `docs/game/05_requirements.md` REQ-SL-001..012

## Requirement cross-reference
- REQ-SL-001 Save slot identity and manual/autosave/quicksave distinction
- REQ-SL-002 Save index lists and resolves slots
- REQ-SL-003 Corruption detection backs up rather than loads
- REQ-SL-004 Manual saves are listed, loadable, and versioned
- REQ-SL-005 Quicksave overwrites a single dedicated slot
- REQ-SL-006 Autosave policy fires on cadence + event triggers
- REQ-SL-007 Save migration service moves old saves forward
- REQ-SL-008 Meta / world / run scopes do not leak
- REQ-SL-009 Permadeath resolver freezes the run and blocks invalid reloads
- REQ-SL-010 Cloud-ready manifest captures build + device + sync eligibility
- REQ-SL-011 Save/load menu UI seam reads the slot index
- REQ-SL-012 Main-scene multi-slot save flow is end-to-end

## Design pillar alignment
- Runtime systems over proof artifacts: the package writes and restores production runtime state through Godot services and pure models.
- Pure-model-first gameplay state: slot rows, the index, migrations, autosave policy, cloud manifests, and permadeath records are headlessly testable models or services.
- No scope leakage: current-run state, world state, and future meta progression remain explicitly separated.

## Player fantasy
The player can suspend a doomed boarding run, resume it from a named slot, rely on autosaves during tense progress, inspect failed/corrupt saves instead of losing them silently, and carry the consequences of death forward through a frozen run record.

## Gameplay problem
The original Gate 2 save/load slice only supported a single current-run save. Task 11 requires a production persistence package: distinct manual/autosave/quicksave slots, slot listing, corruption handling, migration, death freeze, and cloud-ready sidecars without accidentally turning the system into hub/meta persistence.

## Core behavior
- Manual saves write to named slots `slot_01`..`slot_06`.
- Autosaves rotate across `autosave_a`..`autosave_c` with cadence, event-pressure, and forced-save triggers.
- Legacy/current-run autosave compatibility is preserved through `user://saves/current_run.json` as the active autosave alias.
- Quicksave writes to a dedicated `quicksave` slot with a 10 s cooldown.
- World persistence writes to `user://saves/world.json` and stays separate from run-slot payloads.
- Every saved slot writes a cloud-ready manifest sidecar under `user://saves/.cloud/<slot_id>.manifest.json`.
- Corrupt, malformed, or version-incompatible slot files are backed up to `user://saves/.corrupt/` and flagged in the slot index instead of being silently loaded.
- Older save payloads are migrated forward deterministically on load and the migrated form is written to `<slot_id>.migrated.json`.
- Death freezes a slot through `user://saves/<slot_id>.death.json`; frozen slots cannot be loaded until the death record is cleared.
- Loading a manual slot restores the active run without overwriting world/meta state outside the run snapshot scope.

## Inputs
- Objective-completion autosave triggers from `PlayableGeneratedShip`.
- Manual save/load and quicksave/quickload UI actions.
- Runtime state from `PlayableGeneratedShip`, `RunSnapshot`, `WorldSnapshot`, and pure-model summaries.
- Existing slot files, index rows, migrated siblings, death records, and cloud manifests.

## Outputs
- `user://saves/current_run.json` active autosave alias.
- `user://saves/<slot_id>.json` manual/autosave/quicksave payloads.
- `user://saves/world.json` world payload.
- `user://saves/index.json` slot index.
- `user://saves/.cloud/<slot_id>.manifest.json` cloud-ready manifests.
- `user://saves/.corrupt/<slot_id>.<epoch>.<basename>.bak` corruption backups.
- `user://saves/<slot_id>.migrated.json` migrated payloads.
- `user://saves/<slot_id>.death.json` death/epitaph records.

## Rules
- Save payloads must contain `slot_id` and `slot_kind` for every persisted slot.
- Manual, autosave, quicksave, and world slots are distinct families; they must never collide on disk.
- The slot index is a cache and review surface, not the authoritative payload; slot files remain the source of truth.
- Loading rejects malformed JSON, incompatible versions, and manifest SHA mismatches.
- Corrupt slot files are moved aside before returning `null`.
- Migration is forward-only and deterministic; newer-than-current saves are rejected rather than downgraded.
- Manual run loads may restore active run state but must not trample world or meta persistence boundaries.
- Completion/death flow may clear the active run alias while preserving intended manual-slot review data.

## Non-goals
- No live networked cloud adapter, sync transport, account auth, or provider SDK integration yet.
- No hub/meta progression persistence inside `RunSnapshot`.
- No encryption/compression pipeline in this package.
- No broad persistence rewrite outside the Task 11 ADR boundaries.
- No silent salvage of malformed saves beyond explicit migration/defaulting rules.

## Technical design
- `scripts/systems/save_load_service.gd`: current-run + multi-slot persistence service with index, corruption backup, world slot, manifest writes, and migration hooks.
- `scripts/systems/save_slot_state.gd`: one slot row summary for menu/index use.
- `scripts/systems/save_index_state.gd`: on-disk slot index.
- `scripts/systems/save_migration_service.gd`: deterministic forward-only migration table.
- `scripts/systems/autosave_policy.gd`: cadence/event/force autosave policy with rotation and quicksave cooldown.
- `scripts/systems/permadeath_resolver.gd`: death/epitaph record service.
- `scripts/systems/cloud_manifest_state.gd`: cloud-ready manifest sidecar model.
- `scripts/ui/save_load_menu.gd`: pure UI seam over the slot index.
- `scripts/procgen/playable_generated_ship.gd`: integration owner for save/load service and runtime triggers.

## Acceptance criteria
- Given manual/autosave/quicksave/world writes, when the index is listed, then each slot family appears with stable identity and expected ordering.
- Given a malformed slot payload, when it is loaded, then the service returns `null`, writes a `.corrupt` backup, and leaves a `corrupt=true` review row.
- Given an old save payload, when it is loaded, then the migration service upgrades it deterministically and writes `<slot_id>.migrated.json`.
- Given a death-frozen slot, when it is loaded, then the load is rejected and the epitaph record remains available.
- Given a main-scene playable run that writes manual save `slot_01`, quicksave, and world save, when the end-to-end smoke runs, then the slot reload succeeds and the corruption backup path is exercised.

## Validation
Focused Task 11 markers:
- `SAVE SLOT STATE PASS`
- `SAVE MIGRATION SERVICE PASS`
- `AUTOSAVE POLICY PASS`
- `MAIN PLAYABLE MULTISLOT SAVE PASS`

Bundle registration and strict warning/error handling live in `docs/game/06_validation_plan.md`.

## Risks
- Corrupt-save review UX could silently regress if corrupt rows disappear from the index; `save_slot_state_smoke.gd` locks the contract.
- Cleanup between validation runs can pollute slot counts; Task 11 smokes now explicitly remove their owned slots before and after running.
- Persistence scope creep could leak world/meta state into run slots; ADR-0007, ADR-0031, and REQ-SL-008 remain the cut line.

## ADRs
- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md`
- `docs/game/adr/0007-save-load-service-scope.md`
- `docs/game/adr/0031-multi-slot-save-architecture.md`
- `docs/game/adr/0032-migration-permadeath-cloud-manifest.md`
