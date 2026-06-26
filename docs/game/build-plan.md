# Synapse Sea Kanban Build Plan

## Board

`synapse-sea-stage-gate`

## Purpose

Convert the Synapse Sea operating model into a durable execution queue for Gate 1 and future milestone work.

## Profiles

- `synapse_sea_worker` — scoped Godot implementation worker.
- `synapse_sea_docs` — documentation/planning worker.
- `synapse_sea_review` — review and gate-check worker.
- `default` — GPT-5.5 coordinator/final integrator.

## Board strategy

The repository is currently not a git workspace, so shared-workspace concurrency must be conservative. Use explicit dependencies and avoid parallel code edits to the same files.

## Initial milestones

### M0: Framework bootstrap

- Create docs/game operating model.
- Create ADR-0001.
- Create Synapse Sea profiles.
- Create board and task graph.
- Verify MCP/tooling state.

### M1: Gate 1 missing design decisions

- Define hazard pressure loop.
- Define inventory/tool stance.
- Define hub/meta progression stance.
- Define Gate 1 vertical slice acceptance playtest.

### M2: Next runtime system

- Write feature spec.
- Add requirements.
- Implement model + scene consequences.
- Add validation smokes.
- Run regression bundle.

### M3: Gate 1 review

- Run full validation.
- Run playtest protocol.
- Update risk register.
- Decide Go / Recycle / Hold.

## Card contract

Every card must include objective, source requirements, scope, out of scope, steps, acceptance criteria, verification, dependencies, and stop/block conditions.

## Manifest

The task graph manifest lives at:

`.omh/kanban/synapse-sea-stage-gate-task-graph.json`
