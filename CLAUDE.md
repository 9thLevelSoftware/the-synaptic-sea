# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**The Sargasso of Stars** — a locked-isometric 3D space-horror survival sim built in **Godot 4.6.2** (GDScript, Forward+). The player repairs a hub ship trapped in a biomatter web and explores procedurally generated derelicts. The repo folder on disk is named `The Synaptic Sea`; the in-engine project is "The Sargasso of Stars".

## Environment drift — read this first

The `docs/` tree and `AGENTS.md` were authored on the original developer's **macOS** machine and hardcode paths that **do not exist here**:

- Docs say Godot lives at `/Users/christopherwilloughby/.local/bin/godot-4.6.2` and the project root is `/Users/christopherwilloughby/the-sargasso-of-stars`.
- Docs (`04_tdd.md`, `AGENTS.md`) claim "the workspace is not a git repository; use no-git ledgers." **This is now a real git repo** (`main` branch). Use normal git; ignore the no-git-ledger instruction.

On this machine:

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (use the `_console` build for headless runs so stdout/markers are captured).
- **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.

When following any command from `docs/`, substitute the real binary and root paths. The validation bundle in `docs/game/06_validation_plan.md` is a bash script that honors `GODOT` and `ROOT` env overrides — set them rather than editing the doc.

## Commands

Run all validation **headless** from the project root. Pattern:

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke_name>.gd
```

- **Run one smoke:** the command above. Each smoke prints a single `... PASS ...` marker line; that marker is the contract (see expected markers in `06_validation_plan.md`).
- **Full regression bundle (38 smokes):** run the bash block in `docs/game/06_validation_plan.md` with `GODOT`/`ROOT` set to the Windows values above. It greps for each PASS marker and fails on any unexpected `ERROR:`/`WARNING:` line. Success ends with `SARGASSO REGRESSION PASS commands=38 clean_output=true`.
- **Automated Gate 1 playtest:** `--script res://scripts/validation/gate1_automated_playtest.gd` (run on top of, not instead of, the regression bundle).
- **Run the game (windowed):** `"$GODOT" --path "$ROOT"` — main scene is `res://scenes/main.tscn`.
- **Release export:** `scripts/export/build_release.sh [web|linux|macos|windows]` — note this script also hardcodes macOS paths/templates; set `GODOT=` and provide export templates before relying on it.
- **Parse-check a script:** add it as a validation smoke, or run a one-off `--script`. Note: **Godot `--script` can exit 0 even on parse/load errors** — never trust exit code alone. Confirm the PASS marker is present and no parse error appears in output.

### Baseline output noise (not failures)

Every headless `--script` run emits these two lines on teardown; they are allowlisted and must be ignored:

```
ERROR: Capture not registered: 'gdaimcp'.
WARNING: ObjectDB instances leaked at exit (run with --verbose for details).
```

The save/load service smoke additionally emits one expected `WARNING: SaveLoadService: save file rejected by from_dict ...` (it deliberately tests the rejection path). **Any other `ERROR:`/`WARNING:` line blocks completion** — classify it in `06_validation_plan.md` before adding/removing a smoke.

## Architecture

### Model / Node separation (strict)

The core rule across the codebase: **Resources are data, Nodes are behavior.**

- **Pure gameplay state** → `RefCounted`/`Resource` classes that never touch the scene tree (`scripts/systems/*`, e.g. `oxygen_state.gd`, `fire_state.gd`, `route_control_state.gd`, `inventory_state.gd`, `objective_progress_state.gd`, `ship_system_state.gd`). These have `get_summary()` / `apply_summary()` round-trip methods for save/load and validation.
- **Scene nodes** apply scene consequences only — collision, visuals, HUD, instantiating nodes (`scripts/player/`, `scripts/ui/`, `scripts/interaction/`, `scripts/camera/`).
- The runtime coordinator `scripts/procgen/playable_generated_ship.gd` owns the pure model instances and drives them; `scripts/main.gd` just instantiates the playable ship scene.
- Prefer signals / explicit dependency injection over hardcoded parent/sibling node paths.
- **Autoloads are services only**, never god-objects. The only autoloads are the two MCP runtimes (`GDAIMCPRuntime`, `MCPRuntime`); `GDAIMCPRuntime` is stripped from `project.godot` at release export.

### Coordinator `_process` has TWO branches — wire BOTH

`playable_generated_ship.gd::_process(delta)` has an early `if away_from_start:` branch (boarded on a derelict) that **returns before** the home/hub branch. Any new per-frame system (a model `tick()`, a hazard/teeth feed into the vitals tick, an audio/HUD refresh, a manager `render()`) must be wired into **both** branches, or it silently runs at home only and is dead in the field — the derelict run is the primary gameplay context. This away-path early-return has caused three shipped regressions (PR #42 fire zones, #43 audio/combat-music, #44 sanity hallucinations + sanity drain). When adding a `_process` system: wire the away branch too, and give its validation smoke an `away_ticks=`-style assertion that drives `away_from_start = true`.

### Procgen layout pipeline

The procedural ship generator is a chain of pure-data `RefCounted` stages (no scene nodes until the loader runs), fully deterministic per seed. Flow:

```
ShipBlueprint + archetype
  → TemplateSelector   (template_selector.gd)   picks spine/bifurcated/stacked
  → RoomAssigner       (room_assigner.gd)        fills template zones with room roles
  → CellLayoutEngine   (cell_layout_engine.gd)   places rooms on a 2D grid, resolves adjacency
  → WallDoorResolver   (wall_door_resolver.gd)   walls/portals/interior zones
  → LayoutSerializer   (layout_serializer.gd)    emits layout.json (schema 1.1.0)
  → GeneratedShipLoader (generated_ship_loader.gd) instantiates the scene
```

- `ship_layout_generator.gd` orchestrates the layout-only path; `gameplay_slice_builder.gd` populates the gameplay arrays (`blocked_links`, `fire_zones`, `arc_zones`, `breach_zones`) that the layout stage leaves empty.
- **Output format is the same `layout.json` schema as the hand-authored golden layouts** (`data/procgen/golden/coherent_ship_001/002/003`) — procgen and golden ships load through one identical code path. When changing the schema, update golden files and the loader together.
- Templates: `data/procgen/templates/{spine,bifurcated,stacked}.json`. Archetypes: `data/procgen/archetypes/*.json`. Grid: `CELL_SIZE = 4.0`, `DECK_HEIGHT = 4.0`.
- Design spec: `docs/superpowers/specs/2026-06-20-procgen-layout-pipeline-design.md`.

### Hazards (ADR-0005)

Hazard models share a uniform contract: each owns a `PhaseTimer` (where phase-based) and translates its `Phase.A/B` into its own enum; every `get_summary()` carries a `hazard_kind` discriminator that `apply_summary()` validates. `hazard_contract_smoke.gd` enforces this structurally. Oxygen is intentionally a non-timer resource-drain hazard.

## Working conventions (from AGENTS.md / docs)

This project runs a deliberately rigid, document-backed process. Honor it unless the user overrides:

- **Validation is the definition of done.** No completion claim without fresh PASS-marker output. When adding a system: write (1) a pure-model smoke, (2) a main-scene smoke if scene consequences exist, then (3) add both to the regression bundle in `06_validation_plan.md`.
- **Typed GDScript** for new systems.
- Implementation work should cite a feature spec (`docs/game/features/`) or requirement (`docs/game/05_requirements.md`); architecture decisions get an ADR under `docs/game/adr/`. Don't make ad-hoc architectural calls when a spec/ADR is the expected vehicle.
- Build real in-engine runtime systems, not proof-only artifacts (HTML mockups / screenshot galleries) unless a card explicitly asks for visual-proof work.
- Commit style: Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`) — matches existing history.

## Do not touch / commit

- `addons/gdai-mcp-plugin-godot/` — paid/local MCP tooling, gitignored. Never commit or publish it.
- `.godot/` and `*.uid` are gitignored but some were committed earlier and show as modified; do not add new ones.
- **Project status source of truth:** `/STATUS.md` → `docs/game/system_completion_audit.md` (canonical, code-anchored roadmap) + `docs/game/integration_debt.md`. The old Gate 0–5 / "all-validated" roadmaps (`08_milestone_gates.md`, `09_system_roadmap.md`, `PLANNING_SYNTHESIS.md`, `build-plan.md`, `PROJECT_WORKSPACE.md`) were quarantined to `docs/archive/` on 2026-06-28 as inaccurate — do not cite them.
- `docs/game/` holds the living design source of truth (vision, GDD `03_gdd.md`, TDD `04_tdd.md`, requirements `05_requirements.md`, validation `06_validation_plan.md`, ADRs). Keep these updated when behavior changes.
