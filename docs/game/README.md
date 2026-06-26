# Synaptic Sea Game Development Operating System

This folder is the canonical source of truth for The Synaptic Sea design, technical structure, gates, requirements, and validation.

The operating model is:

- Stage-Gate governance for milestone decisions.
- Kanban execution on the `synaptic-sea-stage-gate` board.
- Living GDD/TDD/requirements documents.
- ADRs for architecture decisions.
- Godot validation gates for every completion claim.

## Document map

- `00_vision.md` — one-page project north star.
- `01_design_pillars.md` — non-negotiable decision filters.
- `02_core_loop.md` — moment/minute/session progression loops.
- `03_gdd.md` — living master Game Design Document.
- `04_tdd.md` — living Technical Design Document.
- `05_requirements.md` — implementation-ready requirements with acceptance criteria.
- `06_validation_plan.md` — smoke/regression/playtest gates.
- `07_risk_register.md` — project risks, mitigations, and status.
- `08_milestone_gates.md` — gate entry/exit criteria and current gate state.
- `build-plan.md` — Kanban board strategy and task graph summary.
- `adr/` — Architecture Decision Records.
- `features/` — one feature spec per gameplay/system feature.
- `playtests/` — playtest protocol and logs.
- `templates/` — copyable feature/spec/playtest templates.

## Source basis

This framework is based on current research and source verification from:

- Stage-Gate governance: https://www.stage-gate.com/blog/the-stage-gate-model-an-overview/
- Empirical game development research: https://link.springer.com/article/10.1007/s40869-019-00085-1
- Agile/Kanban game development: https://www.mountaingoatsoftware.com/books/agile-game-development-build-play-repeat
- Modern GDD practice: https://www.gamedeveloper.com/design/how-to-write-a-game-design-document
- GDD master + feature-doc split: https://gamedesignskills.com/game-design/document/
- Double Diamond discovery framing: https://www.designcouncil.org.uk/our-resources/the-double-diamond/
- ADRs: https://github.com/architecture-decision-record/architecture-decision-record
- Acceptance criteria: https://www.atlassian.com/work-management/project-management/acceptance-criteria
- Godot scene organization: https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html
- Godot project organization: https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html
- Godot resources: https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html
- Godot autoloads: https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html
- Godot static typing: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html
