# Synaptic Sea Agent Instructions

These instructions apply to all work in this repository.

## Operating model

The Synaptic Sea uses a rigid, source-backed game-development operating system:

1. Stage-Gate governance for milestone decisions.
2. Kanban for execution cards and multi-agent coordination.
3. Living GDD/TDD/requirements/risk-register documentation.
4. ADRs for architecture or workflow decisions.
5. Godot headless validation before claiming completion.

Do not make ad-hoc implementation decisions when a feature spec, requirement, ADR, or gate document is needed.

## Non-negotiables

- Build actual in-engine gameplay/runtime systems, not proof-only artifacts.
- Do not substitute HTML mockups, PNG/contact sheets, screenshot galleries, or proof docs for gameplay behavior unless the active card explicitly asks for visual-proof work.
- Every implementation card must cite a requirement or feature spec, list allowed files, list non-goals, and include verification commands.
- Every architecture decision requires an ADR under `docs/game/adr/`.
- Every feature must define acceptance criteria before implementation.
- Every completion claim requires fresh validation output.
- Unexpected Godot `ERROR:` or `WARNING:` lines block completion unless explicitly classified and accepted by the coordinator.
- Godot `--script` parse/load errors can return exit code 0; validate RED phases by output markers and absence of pass markers, not exit code alone.

## Canonical workflow

1. Update or create a feature spec under `docs/game/features/`.
2. Add or update requirement rows in `docs/game/05_requirements.md`.
3. Add ADRs for architecture decisions.
4. Create or update Kanban cards on board `synaptic-sea-stage-gate`.
5. Implement with scoped files only.
6. Run the feature smoke plus the regression bundle in `docs/game/06_validation_plan.md`.
7. Update docs and the no-git ledger if the workspace is not a git repository.

## Godot technical rules

- Godot version: 4.6.2 at `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Keep pure gameplay state in `RefCounted` or `Resource` classes where practical.
- Scene nodes apply scene consequences; pure models do not reach into the scene tree.
- Use typed GDScript for new systems.
- Prefer signals or explicit dependency injection over hardcoded parent/sibling paths.
- Autoloads are services only, not god-objects.
- Resources are data; Nodes are behavior.

## Current board, agents, and live tooling

- Board: `synaptic-sea-stage-gate`.
- Default assignee: `synaptic_sea_worker` (bulk execution).
- Implementation worker: `synaptic_sea_worker` on `MiniMax-M3`.
- Documentation/planning worker: `synaptic_sea_docs` on `kimi-k2.7-code` (OpenCode Go).
- Review/gate worker: `synaptic_sea_review` on `gpt-5.5` (OpenAI Codex).

Primary conversation/architecture model is `mimo-v2.5-pro` (Xiaomi token plan). Senior review, validation, and auxiliary vision/default assistant second-opinion use `gpt-5.5`. Complex but scoped implementation delegation uses `kimi-k2.7-code`. Routine worker, documentation, and compression work uses `MiniMax-M3`.

Use explicit `--board synaptic-sea-stage-gate` in CLI scripts. Do not rely on whatever board is currently active.

Godot automation:
- `godot_coding_solo` is available for editor-free Godot automation.
- `gdai` is available for live editor state when the Synaptic Sea Godot editor is running with the GDAI plugin active on port `3571`.
- `blender_mcp` is available for Blender asset tooling.
- Do not commit/publish `addons/gdai-mcp-plugin-godot/`; it is paid/local tooling and is ignored by `.gitignore`.
