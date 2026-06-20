# ADR-0001: Adopt Stage-Gate + Kanban + Godot Validation as the Sargasso Operating Model

## Status

Accepted

## Context

The project has repeatedly risked drifting into proof artifacts, visual mockups, and ad-hoc agent decisions. The user explicitly wants a rigid, source-backed game-design and development structure.

Web research found:

- Stage-Gate provides a risk-managed stage/gate governance model.
- Empirical game-development research shows games require iteration/prototyping because requirements are soft and emergent.
- Game-development Agile/Kanban sources support iterative playable increments.
- Modern GDD guidance recommends living, searchable, concise documents rather than monolithic design bibles.
- Godot documentation recommends scene independence, explicit dependencies, data as Resources, and typed GDScript.

## Decision

Use this operating model for Sargasso:

1. Stage-Gate governance for milestone decisions.
2. Kanban board `sargasso-stage-gate` for execution.
3. Living docs under `docs/game/`.
4. ADRs under `docs/game/adr/` for architecture/process decisions.
5. Feature specs under `docs/game/features/` before implementation.
6. Headless Godot validation before completion claims.
7. No proof-only deliverables unless explicitly scoped.

## Consequences

Positive:
- Reduces ad-hoc agent decisions.
- Makes every system traceable to design pillars and requirements.
- Gives future agents a clear project contract.
- Keeps focus on runtime gameplay behavior.

Negative/tradeoffs:
- More upfront documentation overhead.
- More gates before implementation.
- Requires ongoing discipline to keep docs current.

## Verification

- `docs/game/` scaffold exists.
- `AGENTS.md` points future agents to the operating model.
- Kanban board and Sargasso profiles exist.
- Future cards reference requirements/specs/validation.
