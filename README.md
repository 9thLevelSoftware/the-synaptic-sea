# The Synaptic Sea

> **Locked-isometric 3D space-horror survival sim.**
> Godot 4.6.2 · GDScript · Stage-Gate driven development

Your hub ship is trapped in a vast biomatter web — a cosmic Synaptic Sea. From a
readable locked-isometric view, you pilot your lifeboat to procedurally
generated derelict spacecraft, dock, board, loot, repair, survive hazards,
and ship out again. The end-game is wiring a fleet of physically-docked,
nested ships that can carry each other.

This repository is the canonical engine project.

> ⚠️ **For current project status, read [`/STATUS.md`](STATUS.md).** Several older
> roadmap docs (a "Gate 0–5 / shipped RC" narrative and conflicting milestone tables)
> were found to be inaccurate and moved to [`docs/archive/`](docs/archive/README.md) on
> 2026-06-28. The authoritative, code-anchored status lives in
> [`docs/game/system_completion_audit.md`](docs/game/system_completion_audit.md). Treat
> any "released / all-complete" claim elsewhere with suspicion until reconciled.

---

## Project state

**Mid-development / pre-alpha.** This is an actively-built deep survival sim, not a
shipped release. The "Stage-Gate pipeline closed / v0.1.0 RC" language in older docs was
fictional — feature work (fire, sanity, item economy) is landing as of 2026-06-28.

See **[`/STATUS.md`](STATUS.md)** for the authoritative "what's built / what's left"
summary, and **[`docs/game/system_completion_audit.md`](docs/game/system_completion_audit.md)**
for the per-system, code-traced grades. The real milestone scheme is the M-lane /
sub-project naming (e.g. M7 = Ship systems & sustenance) used in `docs/superpowers/specs/`
and the git history — **not** the archived Gate 0–5 or M1–M11 schemes.

---

## Core loop

A single playable derelict slice, repeatable per run:

1. **Read** the locked-isometric ship space.
2. **Move** through coherent rooms and corridors.
3. **Identify** an affordance, obstacle, hazard, or objective.
4. **Interact** — game state changes visibly: collision, passability, route
   state, ship systems, HUD, hazard pressure, save data.
5. **Reassess** the ship layout with new options unlocked.

The four-objective sequence walks the player from breach to reactor
stabilization. Route-control gates actually disable collision when opened.
Oxygen pressure is a real, observable state. The piloted ship is the
player's ride — travel is a real undock→dock loop, not a menu teleport.

Hub/meta progression is deferred past Gate 2
([ADR-0002](docs/game/adr/0002-defer-hub-meta-past-gate-1.md)).

---

## What's in the box

### Engine & runtime
- **Godot 4.6.2** (`Forward Plus`, `1280×720` viewport).
- **GDScript** (typed) — **241 script files** across runtime, procgen,
  systems, player, UI, tooling, and validation.

### Procedural generation (System 1 + 7)
A full blueprint-driven pipeline that produces navigable, readable derelict
interiors — not pretty but untraversable scenes.

- `scripts/procgen/ship_generator.gd` — orchestrator
- `scripts/procgen/ship_blueprint.gd` — size / condition / seed
- `scripts/procgen/room_graph_generator.gd` — deterministic room layout
- `scripts/procgen/structural_placer.gd` — module-based room construction
- `scripts/procgen/playable_generated_ship.gd` — runtime coordinator
- Data: `data/procgen/` (archetypes, templates, golden ships, kit data)
- Library: `scenes/wrappers/structural/ship_structural_v0/`

### Runtime systems (`scripts/systems/`, 46 files)
Pure models — `RefCounted` / `Resource` — that own state but never reach
into the scene tree. Scene nodes apply scene consequences.

**Survival & hazards**
- `oxygen_state` — Gate 1 hazard pressure loop; live equipment-suit
  multiplier (ADR-0024).
- `fire_state` / `electrical_arc_state` — Gate 2 hazard variety
  (ADR-0005).
- `route_control_state` — gate open/closed, extraction unlock.
- `life_support_system` — system-level pressure modelling.

**Ship systems & repair**
- `ship_systems_manager` + `ship_system` + `ship_subcomponent` — six
  ship systems with dependency cascades (ADR-0008, ADR-0009).
- `repair_point` + `repair_with_inventory` — timed, parts-gated repair
  (ADR-0015).

**Player progression & travel**
- `player_progression_state` + `class_definition` — XP, repair-skill
  integration (ADR-0010).
- `scanner_state`, `travel_controller`, `marker_generator`, `ship_marker`
  — scanner + travel loop (ADR-0011).

**Docking, ship-in-ship, hangar (System 5, complete)**
- `docking_manager`, `dock_ports`, `ship_occupancy`, `dock_port_barrier`
  — physical dock-port-aligned docking with typed ports + welding breach
  (ADR-0016, ADR-0017).
- `ship_instance` — parent/child ship forest with real `interior_aabb`.
- `ship_access_state`, `bridge_terminal` — ownership + pilot-switch
  (ADR-0018).
- `hangar_bay`, `hangar_bay_control` — nested fleet of arbitrary depth
  (ADR-0019).

**Inventory, equipment, cargo (System 6, ~88%)**
- `inventory_state` — PZ soft-cap, categorized player inventory.
- `loot_roller` + `loot_container` + `item_defs` — loot tables.
- `ship_inventory` + `cargo_transfer` + `cargo_hold_control` — ship cargo
  holds, weight-capped 500 (ADR-0020).
- `equipment_state` + `encumbrance` — worn slots, PZ soft-cap, Heavy Load
  move penalty (ADR-0021).
- `cart_state` + `cart_control` — pushable zero-encumbrance mobile
  containers.
- `inventory_selection_model` + `inventory_panel` + `inventory_row` +
  `inventory_drop_zone` — interactive widget layer (ADR-0022, ADR-0023).

**Persistence & world**
- `world_snapshot` + `save_load_service` + `run_snapshot` — disk save/load
  of world + per-ship slices; geometry regenerates from seed (ADR-0012).
- `synaptic_sea_world` + `world_snapshot` — Synaptic Sea spatial registry.
- `derelict_objective_controller` — boarded derelicts run the same
  objective/hazard/loot loop as the home ship (ADR-0013).

### Player, camera, UI
- `scripts/player/player_controller.gd` — `CharacterBody3D` movement + input.
- `scripts/camera/iso_camera_rig.gd` — locked-isometric rig.
- `scripts/ui/objective_tracker.gd` — live HUD from real runtime state.
- `scripts/ui/inventory_panel.gd` + `inventory_row.gd` +
  `inventory_drop_zone.gd` — interactive inventory/transfer UI.
- `scripts/ui/scanner_panel.gd` — Synaptic Sea scanner.
- `scripts/ui/accessibility_settings.gd` — accessibility toggles.

### Validation
**240 headless smoke + capture scripts** under `scripts/validation/`,
orchestrated by [`docs/game/06_validation_plan.md`](docs/game/06_validation_plan.md).
The latest green regression report is
[`docs/game/regression_report_2026-06-19.md`](docs/game/regression_report_2026-06-19.md).

---

## Getting started

### Prerequisites
- **Godot 4.6.2** — install via the [Godot download page](https://godotengine.org/download)
  or use the local toolchain at `~/.local/bin/godot-4.6.2`.
- For export builds: Godot export templates for `4.6.2.stable` and Python 3
  (see [`docs/game/export_pipeline.md`](docs/game/export_pipeline.md)).

### Run the game
```sh
godot --path .                                         # opens the editor
godot --path . --headless                              # headless boot
godot --path . res://scenes/main.tscn                  # run the main playable slice
```

Main scene: `res://scenes/main.tscn` → bootstraps
`res://scenes/procgen/playable_coherent_ship.tscn`.

### Run validation
The validation plan is in
[`docs/game/06_validation_plan.md`](docs/game/06_validation_plan.md).
Individual smokes live as `*_smoke.gd` files under `scripts/validation/`
and can be run with `godot --headless --script <path>`. Validation is
done-ness: every smoke prints exactly one `... PASS ...` marker line —
trust the marker, not the exit code.

### Build release exports
```sh
python3 tools/check_export_pipeline.py
```
Targets: HTML5/Web (itch.io embed), Linux x86_64, macOS, Windows x86_64. See
[`docs/game/export_pipeline.md`](docs/game/export_pipeline.md) for the full
pipeline.

---

## Project layout

```
the-synaptic-sea/
├── project.godot                # Godot project (config_version=5)
├── export_presets.cfg           # Release export presets
├── icon.svg                     # Project icon
├── AGENTS.md                    # Synaptic Sea operating model (read first)
├── scenes/                      # .tscn scenes
│   ├── main.tscn                # Entry point
│   ├── procgen/                 # Playable generated ship scenes
│   ├── wrappers/structural/     # Structural wrapper scene library
│   ├── generated/               # Generated ship artifacts + layout viz
│   └── validation/              # Validation test scenes
├── scripts/                     # GDScript sources (241 files)
│   ├── main.gd
│   ├── camera/   player/   interaction/   placement/
│   ├── procgen/   systems/   tools/   ui/
│   ├── export/                            # Export pipeline scripts
│   └── validation/                        # Headless smokes + captures
├── data/                        # Procgen data, kits, items, systems
│   ├── procgen/                 # Archetypes, templates, golden ships
│   ├── items/                   # Item + loot table definitions
│   ├── ship_systems/            # System definitions
│   ├── tools/                   # Tool definitions
│   ├── kits/                    # Structural kit data
│   ├── placement/  player/
├── tools/                       # Python export/check tooling
├── artifacts/                   # Validation preview outputs
└── docs/
    └── game/                    # Design system, GDD/TDD, ADRs, gates, roadmap
        ├── 00_vision.md
        ├── 01_design_pillars.md
        ├── 02_core_loop.md
        ├── 03_gdd.md
        ├── 04_tdd.md
        ├── 05_requirements.md
        ├── 06_validation_plan.md
        ├── 07_risk_register.md
        ├── system_completion_audit.md    # CANONICAL roadmap (code-anchored loop grades)
        ├── integration_debt.md           # Reachability ledger
        ├── adr/                          # Architecture Decision Records
        ├── features/                     # One spec per feature
        └── playtests/                    # Playtest protocols + logs
    ├── archive/                 # Quarantined inaccurate docs (Gate 0–5, old roadmaps)
    └── superpowers/             # Recent sub-project specs + plans (trustworthy)
└── STATUS.md                    # Source-of-truth entry point
```

---

## Design pillars

These are decision filters — if a feature does not support at least one, it
should be cut, deferred, or rewritten. Full text:
[`docs/game/01_design_pillars.md`](docs/game/01_design_pillars.md).

1. **Spatial coherence first** — the locked-isometric view must let the player
   read layout, routes, and affordances.
2. **Runtime systems over proof artifacts** — gameplay progress must change
   live game state (collision, HUD, system state, save data).
3. **Every action has visible consequence** — no hidden counters or ambiguous
   state changes.
4. **Small vertical slices before broad systems** — one coherent loop before
   scaling content.
5. **Source-backed structure, not ad-hoc taste** — major choices cite specs,
   requirements, or ADRs.

The engineering corollary: *isolate each system the game needs, build each
one completely in isolation behind a clean interface, then wire them
together at the end.* That's why System 6 (inventory) and System 5
(docking) are each delivered in their own phase before being wired into
the integrated Phase 7 build.

---

## Contributing

The full operating model is in [`AGENTS.md`](AGENTS.md) and
[`docs/game/README.md`](docs/game/README.md). The short version:

1. Update or create a feature spec under `docs/game/features/` (or
   `docs/superpowers/specs/` for current sub-project cadence).
2. Add or update requirement rows in `docs/game/05_requirements.md`.
3. Add an ADR under `docs/game/adr/` for any architecture decision.
4. Implement with scoped files only — pure gameplay state in
   `RefCounted`/`Resource`; scene nodes own scene consequences.
5. Run the feature smoke plus the regression bundle in
   `docs/game/06_validation_plan.md`.
6. No commit claims "done" without fresh validation output.

---

## License

No license file is currently published. The repository is public but
**all rights reserved** by default until a `LICENSE` file is added. Please
contact the maintainers before redistributing or building on this work.
