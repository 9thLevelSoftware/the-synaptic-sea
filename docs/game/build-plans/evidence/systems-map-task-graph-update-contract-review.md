# Task 15 Contract Review — Systems Map, Task Graph, Requirements, ADR Index Currency

Date: 2026-06-26
Task: `t_c7ac4d08`

## Existing files reviewed

- `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md` — stale in-scope missing-system language found and replaced with package evidence ledger.
- `docs/game/09_system_roadmap.md` — stale System 6/audio/future-expansion language found and replaced with Task 01-15 roadmap state.
- `docs/game/05_requirements.md` — no `REQ-DOC-001..008` rows existed; Task 15 appends them.
- `docs/game/06_validation_plan.md` — no Task 15 focused validators existed; Task 15 registers three Python smokes.
- `.omh/kanban/synaptic-sea-e2e-systems-task-graph.json` — task ids and declared package edges were real; board counts needed explicit current capture.
- `.omh/kanban/synaptic-sea-stage-gate-task-graph.json` — historical bootstrap manifest; Task 15 marks the active current manifest instead of treating this as the E2E graph.

## Chosen extension seams

- Host-side Python validators in `scripts/validation/doc_currency_validators.py` because the package validates docs/JSON/SQLite, not gameplay scene state.
- Dedicated wrapper smokes for the three required PASS markers.
- `docs/game/adr/README.md` as the ADR index because no current index file existed.
- Manifest `board_currency` block records the live board counts and follow-up links.

## Live board snapshot

- Board: `synaptic-sea-e2e-systems`
- DB: `/Users/christopherwilloughby/.hermes/kanban/boards/synaptic-sea-e2e-systems/kanban.db`
- task_count=18
- link_count=44
- status_counts pre-completion={"done": 17, "running": 1}; expected post-completion={"done": 18}

## Accepted caveats

- `t_4e47145d` completed during the Task 15 window with `LIVE MAIN PREPARE UPGRADE PROBE PASS stages=7`; Task 15 records the completed card in the manifest and roadmap instead of treating it as an open caveat.
- External store/platform/signing evidence remains release-ops follow-up; Task 13 only claims the local scaffold and validators.
