# 09 System Roadmap — Final E2E Currency Ledger

Date: 2026-06-26
Status: Living roadmap updated by Task 15 (`t_c7ac4d08`). This supersedes earlier roadmap language that predated Tasks 01-14.

## Current answer to “what is built?”

The E2E systems wave has validated runtime/doc packages for survival, food/cooking, crafting, loot, consumables, combat, ship systems, progression/meta, UI/accessibility, audio, save/load, procgen expansion, release scaffold, integration audit, and final doc/manifest currency.

| Lane | Task ids | Status | Next planned work |
| --- | --- | --- | --- |
| M1 Survival Foundation | t_34d0483b, t_d569eba2 | Validated | Balance/content tuning only; core runtime and save/load evidence exist. |
| M2 Production Economy | t_be88f847, t_af66b721, t_67389b76 | Validated | Vendor/barter economy and broader content catalog are future expansions. |
| M3 Hostile Derelicts | t_cbe56420 | Validated | Bespoke enemy behaviors, bosses, final VFX/audio polish. |
| M4 Ship Survival Infrastructure | t_290ec958 | Validated | Facility-upgrade UI/deeper pressure consequences as future polish. |
| M5 Long-Arc Progression | t_02146c59 | Validated | Explorable hub ship and long-term economy content. |
| M6 Presentation & Operability | t_7a6849cb, t_9e328a9f | Validated | Full remap UI, final assets, platform controller certification. |
| M7 Persistence & Platform Reliability | t_2d267b26 | Validated | Live cloud-provider integration and external platform validation. |
| M8 World Variety | t_4faf58cf | Validated | More room art/content sets and encounter tables. |
| M9 Release Readiness | t_3b217838 | Validated local scaffold | Store pages, signed exports, external release checklist evidence. |
| M10 Integration Gate | t_12bf9f4a, t_cc483347, t_4e47145d | Validated | Cross-system audit, rigid-pair recovery, and live controller-path probe all have board-backed PASS evidence. |
| M11 Documentation Currency | t_c7ac4d08 | Validated by focused validators | Keep validators updated whenever packages or board links change. |

## "Validated" means unit-tested, not player-reachable

A reachability audit of the E2E batch (commit `5445480`) found that **30 of the
102 new runtime scripts are not reachable from the live main scene** — they have
passing model/smokes but are never mounted in the actual derelict run. "Validated"
in the table above therefore means *unit-tested*, not *player-reachable*. As of
2026-06-26 the crafting/salvage economy (Bucket 2), the menu/meta-screen UI shell
(Bucket 3), the timed/rotating autosave loop (`autosave_policy`), and the lifeboat's
biome-skinned structural kits (`kit_catalog`) are all wired into the live run; a fresh
reachability audit reports **94 reachable / 8 unreachable** (the 8 are genuine infra/audit
tooling + `junk_yield_resolver` — no borderline player-facing systems remain).

> **Update — crafting/salvage now player-reachable (ADR-0038, Bucket 2).** The
> crafting/salvage economy is wired into the live run: `playable_generated_ship.gd`
> owns and ticks `CraftingState` / `MaterialState` / `FieldCraftingState` /
> `DeconstructionResolver`, builds player-reachable `CraftingStation` nodes on the home
> ship, drives station power from the `stations` power channel, persists via the existing
> `crafting_summary` / `material_summary` snapshot fields (no new `RunSnapshot` field), and
> binds emergency field crafting to `C`. Proven coordinator-driven (not just unit-tested) by
> `scripts/validation/main_playable_slice_station_craft_smoke.gd` →
> `MAIN PLAYABLE STATION CRAFT PASS crafted=true salvaged=true field=true reachable=true`.
> MVP limits: one active craft at a time; no recipe-picker UI (auto-selects first craftable);
> powered-station crafts pause while away from home. See
> [integration_debt.md](integration_debt.md) for the residual debt.

> **Update — menu/meta-screen shell now player-reachable (Bucket 3).** The ten
> built-but-dark screens (achievements, audio log, audio settings, skill tree, hub
> upgrades, class roster, language, save/load, build info, credits) are reachable from
> a new **Records** submenu on the live in-run `MenuCoordinator`, which mounts them and
> injects each screen's coordinator-owned dependency (`bind_meta_screens()`).
> `playable_generated_ship.gd` constructs the previously-missing deps
> (`LocalizationCatalog`, `BuildMetadataState`, `SaveLoadMenu`, and a live per-run
> `AchievementState`). No new `RunSnapshot` field, no new ADR, no new keybind. Proven by
> `scripts/validation/main_playable_meta_screens_smoke.gd` →
> `MAIN PLAYABLE META SCREENS PASS screens=10 reachable=true`. MVP limits: screens are
> read-only on open; reached from the in-run pause menu (no separate pre-run main-menu
> shell yet).

> **Update — timed/rotating autosave now live (`autosave_policy`).** The run previously
> autosaved only at objective-completion checkpoints; the borderline-unreachable
> `AutosavePolicy` is now owned + ticked every frame by `playable_generated_ship.gd`
> (home and away), writing rotating `autosave_a/b/c` slots (surfaced by the Bucket-3
> `SaveLoadMenu`) on a 90 s / 8-event cadence. Purely additive — the REQ-012
> `current_run.json` checkpoint path and its resume smokes are untouched (no new
> `RunSnapshot` field, no new ADR, no new keybind); the policy is reseeded on reload and its
> rotating slots are cleared on run completion so finished runs leave no resumable rows.
> Proven by `scripts/validation/main_playable_meta_autosave_smoke.gd` →
> `MAIN PLAYABLE META AUTOSAVE PASS slot_rotated=true reachable=true`. MVP limit: manual
> quicksave is not yet wired (no quicksave keybind).

> **Update — lifeboat structure now biome-skinned via `kit_catalog`.** The previously-orphaned
> `KitCatalog` (role → structural-module registry, `data/kits/*.json`) now drives the lifeboat's
> modules: `StructuralPlacer` consults it (with a `biome` param) instead of a hardcoded const,
> `LifeBoatBuilder.build(biome)` threads it through, and the coordinator passes the run's
> deterministic biome. The floorplan stays fixed; only the per-role module kit changes
> (`breach_field` → hazard, `dead_fleet` → industrial, `abyssal_synaptic_sea` → v0). Determinism
> preserved (v0 `role_modules` mirror the old const), plus a latent KitCatalog parse bug fixed.
> Proven by `scripts/validation/main_playable_lifeboat_biome_skin_smoke.gd` →
> `MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=3 live_match=true reachable=true`. Derelict structural variety
> (the `layout.json` pipeline) is out of scope. **This closes the last borderline player-facing
> integration-debt item.**

> **Update — live derelicts now run the procgen encounter/biome/difficulty pipeline.** The
> system-completion audit ([system_completion_audit.md](system_completion_audit.md)) found that
> while traveled-to derelicts are procgen (`ShipGenerator` → `ShipLayoutGenerator`), they were
> generated with **empty biome/difficulty ids**, so the Task-12 Stage-6 `EncounterInjector`,
> `room_variant_selector`, and biome/difficulty stamping were all skipped — derelict combat fell
> back to a hardcoded 5-archetype set. The coordinator now resolves a deterministic per-derelict
> biome (`BiomeProfileScript.select_biome` on the marker seed) + difficulty (depth-banded) and
> hands them to `ShipGenerator.configure_run_context()` before travel, lighting up all four
> dormant systems. Threat spawning consumes the injected `layout.encounters`
> (`threat_manager._normalize_encounter_kind` already maps injector kinds → real archetypes).
> Determinism/saves unchanged (encounters derive from the marker seed; revisits restore the
> retained combat summary). Proven by
> `scripts/validation/main_playable_derelict_encounter_injection_smoke.gd` →
> `MAIN PLAYABLE DERELICT ENCOUNTER INJECTION PASS injected_threats=true reachable=true`. Known
> follow-up: room-accurate threat placement. (The `encounter_injector.gd` density-clamp balance
> bug — which neutered biome/difficulty density > 1.0 — has since been fixed so `deep_dive` /
> `breach_field` actually raise the spawn rate.)

See [integration_debt.md](integration_debt.md) for the full classification and the
integration actions required before depth/content work builds on these foundations.

## Roadmap principles after Task 15

1. Treat Tasks 01-15 as the source-backed baseline; do not re-open “missing system” language unless a validator or smoke proves a regression. **Exception:** integration debt proven by the reachability audit ([integration_debt.md](integration_debt.md)) is a documented gap, not a regression — un-integrated systems may be wired into the live scene without a new ADR re-opening the system itself.
2. `t_4e47145d` completed the live main-scene/controller-path e2e strengthening probe with marker `LIVE MAIN PREPARE UPGRADE PROBE PASS stages=7`; it complements, rather than replaces, Task 14's model/composite integration gate.
3. External release evidence remains intentionally separate from local release scaffolding. Task 13 validates export/readiness models; release ops must still provide real signed/platform/store evidence.
4. Future content should expand depth (art/audio/content/bosses/hub/vendor/faction/store assets) rather than rebuild the validated system foundations.

## Source-of-truth files

- Systems map: `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`
- Requirements: `docs/game/05_requirements.md` — uses numeric `REQ-001..REQ-014`. NOTE: `REQ-DOC-001..008` is referenced by the Task 15 doc set (this roadmap, ADR-0040, build-plans, systems map, `doc_currency_validators.py`) but was **never added to this requirements file**. See "Documentation-currency caveats" below.
- Validation plan: `docs/game/06_validation_plan.md` — NOTE: the Task 15 Python doc-currency validators (`scripts/validation/{doc_currency_validators,requirement_trace_smoke,systems_map_currency_smoke,kanban_manifest_smoke}.py`) are **not registered here** and are **not** part of the 30-command regression bundle. See caveats below.
- ADR index: `docs/game/adr/README.md`
- Build plan: `docs/game/build-plan.md`
- Manifest: `.omh/kanban/synaptic-sea-e2e-systems-task-graph.json`

## Board currency snapshot

- Board: `synaptic-sea-e2e-systems`
- Tasks: 18
- Links: 44
- Status counts: pre-completion `{"done": 17, "running": 1}`; expected after Task 15 completion `{"done": 18}`
- Manifest validation marker: `KANBAN MANIFEST PASS`

## Documentation-currency caveats (verified 2026-06-26)

A direct check of the claims above against the working tree found that the M11
"Documentation Currency — Validated by focused validators" lane did not hold up.
These were tracked defects, not regressions.

> **Resolution — PR #30 (`fix/doc-currency-validators`).** Defects
> (1)–(3) below are fixed there: the validators auto-detect the repo root and gate
> `kanban-manifest` on board-DB availability; all 57 requirement entries are authored
> into `05_requirements.md`; and `systems-map` / `requirement-trace` / `kanban-manifest`
> are registered in the regression bundle (`commands 30 → 33`). Verified there:
> `SYSTEMS MAP CURRENCY PASS`, `REQUIREMENT TRACE PASS`, `KANBAN MANIFEST SKIP`,
> `SYNAPTIC_SEA REGRESSION PASS commands=33`. Defect (4) is inherent: the live board
> SQLite DB is not on this machine, so `kanban-manifest` skips here by design and runs
> as a full check only where the board DB exists (or via `KANBAN_DB`). The original
> defect list is kept below for the audit trail.

1. **`05_requirements.md` is missing the entire E2E requirements taxonomy.** When
   `doc_currency_validators.py requirement-trace` is run with `ROOT` set, it reports
   **57 missing requirement entries**: `REQ-DOC-001..008` (8) plus **49 matrix
   requirements** across 14 families (`REQ-SV/FC/CS/LE/CN/D/SS/PM/UI/AU/SL/PG/RL/INT-*`)
   that `data/integration/cross_system_integration_matrix.json` references but were
   never written into the requirements document (which still holds only the numeric
   `REQ-001..REQ-014` from Gate 1/2). Fix: author the missing entries (large), or
   reconcile the matrix/validator against a smaller intended set.
2. **The Python doc-currency validators are not registered in the regression
   bundle.** `06_validation_plan.md` references them zero times, so they never run
   as part of the gate. The validator itself flags this (the three Task-15 markers
   `SYSTEMS MAP CURRENCY PASS` / `REQUIREMENT TRACE PASS` / `KANBAN MANIFEST PASS`
   are absent from the validation plan).
3. **The validators default to the original macOS root path.** `ROOT_DEFAULT` is
   `/Users/christopherwilloughby/the-synaptic-sea`, so run bare on this machine they
   raise `FileNotFoundError`. They **do** honor a `ROOT` env override and **exit
   non-zero on failure** (they are not fail-open — an earlier note here claimed
   "exit 0", which was a measurement artifact of piping to `tail`; corrected).
   `systems-map` passes today with `ROOT` set; `requirement-trace` fails on the 57
   gaps in (1); `kanban-manifest` cannot pass here because it needs the live board
   SQLite DB (see (4)).
4. **The board snapshot is a frozen point-in-time capture, unverifiable here.**
   `board_currency.board_db_path` is a macOS path
   (`/Users/christopherwilloughby/.hermes/...`) not present on this machine, and the
   snapshot is fixed at `{"done": 17, "running": 1}`. The "`{"done": 18}`" state is
   aspirational and cannot be confirmed from this checkout. The `kanban-manifest`
   validator therefore cannot run as a gate here without the board DB.

Real fix (implemented in PR #30): auto-detect the repo root in the
validators, register the host-only `systems-map` and `requirement-trace` in
`06_validation_plan.md`, gate `kanban-manifest` on board-DB availability, and author
the missing requirement entries from (1). See the resolution note at the top of this
section.
