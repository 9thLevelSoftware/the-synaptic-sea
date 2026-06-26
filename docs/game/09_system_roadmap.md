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
in the table above therefore means *unit-tested*, not *player-reachable*. The
crafting/salvage economy (ADR-0038) and the entire menu/settings/meta-screen UI
shell are validated-but-unreachable. See [integration_debt.md](integration_debt.md) for the
full classification and the integration actions required before depth/content work
builds on these foundations.

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

> **Resolution — PR #30 (`fix/doc-currency-validators`, pending merge).** Defects
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

Real fix (implemented in PR #30, pending merge): auto-detect the repo root in the
validators, register the host-only `systems-map` and `requirement-trace` in
`06_validation_plan.md`, gate `kanban-manifest` on board-DB availability, and author
the missing requirement entries from (1). See the resolution note at the top of this
section.
