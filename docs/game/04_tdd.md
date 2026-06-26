# 04 Living Technical Design Document

## Engine and runtime

- Engine: Godot 4.6.2.
- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Project root: `/Users/christopherwilloughby/the-synaptic-sea-of-stars`.
- Current workspace is not a git repository; use no-git ledgers until that changes.

## Architecture principles

- Pure gameplay state belongs in `RefCounted` or `Resource` models where practical.
- Scene nodes own scene-tree consequences such as collision, visuals, HUD, and instantiated nodes.
- Data-driven generated ship information lives under `data/procgen/`.
- Validation scripts live under `scripts/validation/` and run headless.
- Avoid global state unless it is a true service.

## Existing major systems

- `scripts/procgen/generated_ship_loader.gd` — generated ship data loader.
- `scripts/procgen/playable_generated_ship.gd` — main playable ship runtime coordinator.
- `scripts/systems/ship_system_state.gd` — pure ship-system progression model.
- `scripts/systems/route_control_state.gd` — pure route-control progression model.
- `scripts/systems/oxygen_state.gd` — pure oxygen/breach hazard pressure model.
- `scripts/player/player_controller.gd` — player movement/control.
- `scripts/interaction/interactable.gd` — interaction baseline.
- `scripts/ui/objective_tracker.gd` — HUD/objective/status display.

## Validation strategy

See `06_validation_plan.md` for commands. New systems should add:

1. A pure model smoke when possible.
2. A main-scene smoke when scene consequences are required.
3. Regression inclusion before the feature is considered done.

## MCP/tooling

Enabled and useful:
- Serena MCP for code-symbol navigation.
- CuaDriver MCP for macOS UI automation.
- `godot_coding_solo` MCP for editor-free Godot project automation.
- `blender_mcp` MCP for Blender asset/scene tooling.
- `gdai` MCP for live Godot editor state, screenshots, scene/script manipulation, errors, and simulated input.

GDAI notes:
- Synaptic Sea-local addon path: `res://addons/gdai-mcp-plugin-godot/`.
- Hermes config runs `/Users/christopherwilloughby/.local/bin/uv run /Users/christopherwilloughby/the-synaptic-sea-of-stars/addons/gdai-mcp-plugin-godot/gdai_mcp_server.py`.
- Godot editor must be running with the plugin active; otherwise `hermes mcp test gdai` can time out or show no tools.
- GDAI listens on `127.0.0.1:3571` by default.
- The addon is paid/local tooling and is ignored by `.gitignore`; do not publish it in a public repository.

## Future technical decisions requiring ADRs

- Adopt GUT unit testing or continue headless SceneTree smokes only.
- Introduce formal save/load service.
- Introduce inventory/tool data model.
- Define generalized multi-hazard system architecture for Alpha (resolved by ADR-0005).
- Define hub/meta progression model.
- Define asset pipeline from Blender/generated assets to Godot wrappers.
