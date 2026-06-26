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
- Requirements: `docs/game/05_requirements.md` (`REQ-DOC-001..008` added by Task 15)
- Validation plan: `docs/game/06_validation_plan.md` (Task 15 Python doc-currency smokes registered)
- ADR index: `docs/game/adr/README.md`
- Build plan: `docs/game/build-plan.md`
- Manifest: `.omh/kanban/synaptic-sea-e2e-systems-task-graph.json`

## Board currency snapshot

- Board: `synaptic-sea-e2e-systems`
- Tasks: 18
- Links: 44
- Status counts: pre-completion `{"done": 17, "running": 1}`; expected after Task 15 completion `{"done": 18}`
- Manifest validation marker: `KANBAN MANIFEST PASS`
