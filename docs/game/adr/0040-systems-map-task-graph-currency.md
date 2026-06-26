# ADR-0040: Systems Map and Task Graph Currency Validators

## Status

Accepted for Task 15.

## Context

The E2E systems board produced a large set of runtime packages, validation smokes, documentation updates, and follow-up cards. The highest remaining process risk is stale source-of-truth drift: a roadmap can continue to say audio/combat/UI/survival are missing after they have real code and validation evidence, or a task-graph manifest can preserve old board counts after recovery cards are added.

## Decision

Use deterministic host-side validators for final documentation/manifest currency:

- `SystemsMapCurrencyValidator` checks systems-map package evidence and stale in-scope deferral language.
- `RequirementTraceValidator` checks `REQ-DOC-001..008` and matrix-cited requirement headings.
- `AdrIndexValidator` checks the ADR index against current package ADRs and shipped artifact references.
- `KanbanManifestValidator` checks the active manifest against the live Kanban SQLite board.

These validators live in `scripts/validation/doc_currency_validators.py` and are invoked by small smoke wrappers under `scripts/validation/`.

## Consequences

- Task 15 can validate docs and board state without booting the Godot scene tree.
- Future docs/manifest drift becomes a failing smoke instead of a prose caveat.
- The active execution board for this package is recorded as `synaptic-sea-e2e-systems`, while the older `synapse-sea-stage-gate` manifest remains historical.
- External release evidence and the live controller-path e2e probe remain explicit follow-up surfaces, not hidden blockers.

## Validation

- `scripts/validation/systems_map_currency_smoke.py`
- `scripts/validation/requirement_trace_smoke.py`
- `scripts/validation/kanban_manifest_smoke.py`
