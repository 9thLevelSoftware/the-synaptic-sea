# Feature: Systems Map, Task Graph, Requirement, and ADR Currency

## Status

Validated by Task 15 (`t_c7ac4d08`) using focused host-side validators.

## Problem

Tasks 01-14 moved the project from planning prose into many runtime systems, validation smokes, and Kanban handoffs. Older source maps and roadmaps can become dangerous if they still say validated systems are missing, if manifests point at stale board names, or if requirement/ADR indices do not cite shipped artifacts.

## Core behavior

Task 15 introduces a deterministic documentation-currency gate:

- `SystemsMapCurrencyValidator` verifies that the final systems map contains every completed package, real Kanban ids, shipped file evidence, and no stale in-scope missing-system phrases.
- `RequirementTraceValidator` verifies `REQ-DOC-001..008` plus all matrix-cited requirements.
- `AdrIndexValidator` verifies the ADR index references shipped artifacts and current package ADRs.
- `KanbanManifestValidator` verifies the active manifest against the live Kanban board database: real ids, edge presence, status counts, task count, and link count.

The validators are host-side pure Python because Task 15 validates docs, JSON, and the Kanban SQLite board rather than gameplay scene state.

## Non-goals

- Does not implement a new gameplay mechanic.
- Does not re-implement the Task 14 live main-scene/controller-path probe (`t_4e47145d`); it records the live board status and validation marker.
- Does not claim external store/platform/signed-release evidence.
- Does not update historical archived boards except to mark the active manifest clearly.

## Acceptance criteria

- Given the final systems map, when `systems_map_currency_smoke.py` runs, then every completed package has source-backed file evidence and the smoke prints `SYSTEMS MAP CURRENCY PASS`.
- Given requirements and ADR docs, when `requirement_trace_smoke.py` runs, then `REQ-DOC-001..008` and package requirement/ADR references are present and the smoke prints `REQUIREMENT TRACE PASS`.
- Given the active Kanban DB and manifest, when `kanban_manifest_smoke.py` runs, then manifest counts/ids/links/statuses match the board and the smoke prints `KANBAN MANIFEST PASS`.

## Validation

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea python3 scripts/validation/systems_map_currency_smoke.py
ROOT=/Users/christopherwilloughby/the-synaptic-sea python3 scripts/validation/requirement_trace_smoke.py
ROOT=/Users/christopherwilloughby/the-synaptic-sea python3 scripts/validation/kanban_manifest_smoke.py
```
