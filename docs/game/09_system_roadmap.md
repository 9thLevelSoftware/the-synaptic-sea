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
"Documentation Currency — Validated by focused validators" lane does not hold up.
These are tracked defects, not regressions:

1. **`REQ-DOC-001..008` does not exist in `05_requirements.md`.** The family is
   referenced in six places (this roadmap, ADR-0040, build-plans, the systems map,
   and `doc_currency_validators.py`) but was never written into the requirements
   document, which uses the numeric `REQ-001..REQ-014` scheme. Fix: add the
   REQ-DOC entries, or remove the dangling references.
2. **The Python doc-currency validators are not registered in the regression
   bundle.** `06_validation_plan.md` references them zero times, so they never run
   as part of the gate.
3. **Those validators are broken on this machine and fail open.** They hardcode the
   original macOS paths (`/Users/christopherwilloughby/the-synaptic-sea/...`) and
   raise `FileNotFoundError` here — yet **exit 0 on failure**, so even if registered
   they would report false-green. This is why defects (1) went undetected: the
   "currency validators" do not run, cannot run here, and misreport their status.
4. **The board snapshot is a frozen point-in-time capture, unverifiable here.**
   `board_currency.board_db_path` is a macOS path
   (`/Users/christopherwilloughby/.hermes/...`) not present on this machine, and the
   snapshot is fixed at `{"done": 17, "running": 1}`. The "`{"done": 18}`" state is
   aspirational and cannot be confirmed from this checkout.

Real fix (separate from this roadmap edit): repair the validators' paths + non-zero
exit on failure, register them in `06_validation_plan.md`, then land the REQ-DOC
entries so the validators pass for the right reason.
