# The Sargasso of Stars — Architecture Analysis

Generated: 2026-08-07 | Source fingerprint: `38c1bde7` | 462 source files

## Project identity

**The Sargasso of Stars** is a locked-isometric 3D space-horror deep survival sim ("Project Zomboid in space") built in **Godot 4.6.2** (GDScript, Forward+). The player repairs a hub ship trapped in a biomatter web and explores procedurally generated derelicts. Pre-alpha with all 18 simulation loops closed; remaining work is content, polish, and documented deferrals.

- **Engine:** Godot 4.6.2, Forward+ renderer
- **Language:** GDScript (typed for new systems)
- **Main scene:** `res://scenes/title_main.tscn` → `res://scenes/main.tscn` → `PlayableGeneratedShip`
- **No autoloads** in production (MCP runtimes stripped at export)

---

## Codebase metrics

| Category | Count | Lines |
|----------|------:|------:|
| GDScript files | 1,008 | 131,576 |
| ├─ `scripts/systems/` (pure models) | 141 | 22,441 |
| ├─ `scripts/procgen/` (generation + coordinator) | 29 | 19,466 |
| ├─ `scripts/ui/` (panels/HUD) | 29 | 5,072 |
| ├─ `scripts/tools/` (interactable nodes) | 15 | 2,311 |
| ├─ `scripts/validation/` (smoke tests) | 777 | 79,606 |
| ├─ `scripts/audio/` | 3 | 788 |
| ├─ `scripts/schemas/` | 5 | 458 |
| ├─ Other (camera, player, interaction, placement, release, main) | 9 | 934 |
| JSON data files | 111 | — |
| Scene files (.tscn) | 40 | — |
| ADRs | 55 | — |
| Feature specs | 32 | — |
| Build plans | 17 | — |
| Balance/tuning docs | 12 | — |

---

## Architecture narrative

### Core principle: Resources are data, Nodes are behavior

The codebase enforces a strict model/node separation. Of 141 files in `scripts/systems/`, **138 extend `RefCounted` or `Resource`** (pure data, no scene tree access). Only `HallucinationManager` and `ThreatManager` extend `Node`/`Node3D` (they own scene children). Pure models expose `get_summary() → Dictionary` and `apply_summary(Dictionary) → bool` for serialization round-trips.

### Composition root: PlayableGeneratedShip

`scripts/procgen/playable_generated_ship.gd` (11,456 lines) is the single composition root and runtime coordinator. It:

- Constructs and owns ~100+ pure-model systems via `preload()` constants
- Drives per-frame simulation in `_process(delta)` with a **dual-branch architecture**
- Manages the scene tree (collision, visuals, HUD, interaction dispatch)
- Coordinates save/load, travel, docking, and objective completion

`scripts/main.gd` (19 lines) is a thin bootstrap that instantiates the playable ship scene.

### Dual-branch `_process` (the critical invariant)

The coordinator's `_process` has two execution branches gated by `away_from_start: bool`:

```
_process(delta):
  world_time += delta
  run_play_time_seconds += delta  (if playable and not complete)

  if away_from_start:        ← boarded on a derelict (primary gameplay)
    oxygen → threat → sanity → fire → survival → vitals → tracker
    field_craft → audio → present_ships → food → ammo → arc → work
    return                   ← EARLY RETURN: home branch never runs

  [home branch:]             ← at hub ship
    autosave → threat → present_ships → fire → field_craft → oxygen
    arc → ammo → survival → sanity → food → audio → work
```

**Every new per-frame system must be wired into BOTH branches.** The away-path early return has caused three shipped regressions (PRs #42–#44: fire zones, audio/combat music, sanity hallucinations).

### Boot sequence

```
project.godot
  └→ scenes/title_main.tscn (TitleMain: title screen, New Game / Continue)
       └→ scenes/main.tscn (Main: instantiates playable ship scene)
            └→ scenes/procgen/playable_coherent_ship.tscn
                 └→ PlayableGeneratedShip._ready():
                      1. ensure_default_input_actions()
                      2. _build_runtime_nodes()  ← constructs all systems
                      3. loader.load_from_paths() ← loads layout JSON
```

---

## Module structure

### Domain clusters (13 domains, 191 systems)

| Domain | Key systems | Description |
|--------|-------------|-------------|
| **audio** | AudioManager, DynamicMusicState, SfxEventRouter, MetaEventState, AmbientZoneState | Bus layout, spatial audio, music state machine, SFX routing |
| **combat** | ThreatManager, ThreatAIState, DamagePipeline, ArmorResolver, DetectionState | 6-state AI (IDLE→INVESTIGATE→HUNT→ATTACK→STUN→FLEE→DEAD), perception, pathfinding |
| **consumables** | ConsumableState, EffectDispatcher, MedicineState, StimulantState, AddictionState, AmmoState, UtilityItemResolver | Eat/drink/inject/equip pipelines, sealed hatches |
| **food** | FoodState, SpoilageState, SustenanceState, HydroponicsState, WaterRecyclerState, CookingState, ProductionStation | Freshness/spoilage ticks, hydroponics trays, water recycler, production stations |
| **infra** | BuildMetadataState, LocalizationCatalog, DemoScopeGate, CrashReportBundle, BalanceLedger, IntegrationMatrix | Release/meta infrastructure (not gameplay-critical) |
| **inventory** | InventoryState, EquipmentState, CartState, Encumbrance, CargoTransfer, ItemDefs, MaterialState | Quantified bag, equipment slots, carts, weight/encumbrance, cargo holds |
| **loot** | LootRoller, LootDistribution, RarityTier, UniqueItemState, JunkYieldResolver | Weighted loot tables, rarity tiers, unique items, junk salvage |
| **objectives** | ObjectiveProgressState, DerelictObjectiveController | Objective sequences, derelict parallel objectives |
| **procgen** | ShipLayoutGenerator, TemplateSelector, RoomAssigner, CellLayoutEngine, WallDoorResolver, LayoutSerializer, EncounterInjector, GeneratedShipLoader, GameplaySliceBuilder | 6-stage deterministic pipeline, biome/difficulty profiles, encounter injection |
| **progression** | PlayerProgressionState, SkillTreeState, ClassDefinition, HubUpgradeState, MetaProgressionState, UnlockRegistry, TrainingEventBus | XP, skills, classes, hub upgrades, meta-progression, unlock catalog |
| **save** | SaveLoadService, RunSnapshot, WorldSnapshot, SaveSlotState, SaveIndexState, SaveMigrationService, AutosavePolicy, PermadeathResolver, CloudManifestState | Multi-slot saves, autosave rotation, permadeath freeze, world persistence |
| **ship_systems** | ShipSystemsManager, ShipRuntime, ShipInstance, PowerGridState, HullIntegrityState, LifeSupportState, WebInfestationState, FireSuppressionState, PropulsionState, ModuleIntegrityMap, ModuleDamageRouter | Data-driven systems with derived cascade, parameterized repair, module integrity |
| **survival** | OxygenState, VitalsState, SanityState, RadiationState, BodyTemperatureState, StatusEffectsState, WoundState, PlayerVitalsModel, HallucinationDirector | O2, health, hunger, thirst, stamina, sanity, radiation, temperature, wounds |
| **travel** | TravelController, SynapticSeaWorld, SeaGraph, ShipMarker, DockingManager, DockPorts, ShipOccupancy, HangarBay, ShipAccessState, ShipNavGraph | World graph, ship docking (typed ports, occupancy), hangar nesting, A* pathfinding |
| **ui** | MenuCoordinator, InventoryPanel, ObjectiveTracker, PlayerVitalsPanel, ScannerPanel, RecipePickerPanel, WorkActionHudPanel, WoundsPanel, ShipModificationPanel, ChartPanel, HotbarPanel, TooltipPanel, TutorialOverlay | In-game HUD, menus, panels; all driven by pure-model state |

### Largest files (risk hotspots)

| File | Lines | Role |
|------|------:|------|
| `playable_generated_ship.gd` | 11,456 | Coordinator / composition root |
| `generated_ship_loader.gd` | 1,242 | Layout JSON → scene tree |
| `menu_coordinator.gd` | 1,210 | UI state machine (pause, settings, save/load, codex) |
| `encounter_injector.gd` | 670 | Encounter table → gameplay slice |
| `inventory_panel.gd` | 629 | Inventory UI (drag/drop, transfer, equip) |
| `save_load_service.gd` | 610 | Multi-slot save/load orchestration |
| `threat_manager.gd` | 533 | Threat lifecycle, spawn, tick, combat |
| `cell_layout_engine.gd` | 535 | Room placement on 2D grid |

---

## Procgen layout pipeline

Fully deterministic per seed, producing the same `layout.json` schema as hand-authored golden layouts:

```
ShipBlueprint + Archetype
  → TemplateSelector         picks spine/bifurcated/stacked/ring/radial/...
  → RoomAssigner             fills template zones with room roles
  → CellLayoutEngine         places rooms on 2D grid, resolves adjacency
  → WallDoorResolver         walls/portals/interior zones
  → LayoutSerializer         emits layout.json (schema 1.2.0)
  → EncounterInjector        populates encounters from authoritative tables
  → GeneratedShipLoader      instantiates the 3D scene from layout + kit
```

- **Templates:** 13 topology templates (`data/procgen/templates/`)
- **Archetypes:** 4 ship archetypes (`data/procgen/archetypes/`)
- **Biomes:** 3 biome profiles (`data/procgen/biomes/`)
- **Difficulty:** 3 difficulty profiles (`data/procgen/difficulty/`)
- **Golden layouts:** 3 hand-authored (`data/procgen/golden/coherent_ship_001/002/003`)
- **Grid:** `CELL_SIZE = 4.0`, `DECK_HEIGHT = 4.0`

---

## Hazard system (ADR-0005)

Three hazards share a uniform contract: each owns a `PhaseTimer` (where phase-based), translates `Phase.A/B` to its own enum, carries `hazard_kind` in `get_summary()`. Enforced by `hazard_contract_smoke.gd`.

| Hazard | Model | Phases | Teeth |
|--------|-------|--------|-------|
| **Oxygen** | `OxygenState` | Resource drain (no timer) | Suffocation damage, breach decompression |
| **Fire** | `FireSuppressionState` | Compartment-keyed persistent (ADR-0041) | O2 drain, module damage, 3 extinguish paths |
| **Electrical Arc** | `ElectricalArcState` | Phase timer (discharged ↔ arcing) | Direct damage in arcing phase |

Hull breach drives decompression damage via `ModuleDamageRouter`. Derelict hazard placement is seed-deterministic (ADR-0050, `hazard_source=runtime`).

---

## Persistence model

### Save structure (ADR-0007, ADR-0012, ADR-0031)

```
WorldSnapshot                         ← top-level save DTO
  ├── SynapticSeaWorld summary        ← world graph (ShipMarkers, SeaGraph edges)
  ├── RunSnapshot                     ← current-run state
  │     ├── inventory, equipment, vitals, oxygen, progression, ...
  │     ├── ship_systems summaries
  │     └── slot metadata (play_time, location, world_seed — ADR-0046)
  ├── home_ship (ShipInstance summary) ← hub ship mutable state
  ├── visited_ships[]                 ← derelict ShipInstance summaries
  └── docking state                   ← port assignments, occupancy
```

- **Save path:** `user://saves/world.json` (default), multi-slot via `SaveIndexState`
- **Autosave:** rotating a/b/c slots via `AutosavePolicy`
- **Quicksave:** F6 with cooldown
- **Permadeath:** `PermadeathResolver` freezes the slot on death
- **Migration:** `SaveMigrationService` handles schema evolution
- **Cloud:** stub manifest only (ADR-0032)

---

## Data / configuration map

All gameplay data is externalized as JSON under `data/`:

| Directory | Files | Purpose |
|-----------|------:|---------|
| `data/balance/` | 2 | Shell tuning, balance README |
| `data/combat/` | 4 | Weapon, ammo, status effect, threat archetype definitions |
| `data/components/` | 1 | Component catalog (280 lines) |
| `data/crops/` | 1 | Hydroponics crop definitions |
| `data/integration/` | 5 | Cross-system matrix, balance ledger, audit report, fix manifest |
| `data/items/` | 12 | Items, equipment, medicine, stimulants, junk, trade, unique items, loot tables |
| `data/kits/` | 4 | Structural kit (1,096-line master + materials + hazard/industrial variants) |
| `data/materials/` | 1 | Material definitions (303 lines) |
| `data/placement/` | 15 | Per-piece placement contracts (bulkheads, walls, floors, ramps, corners) |
| `data/player/` | 8 | Classes, skills, skill books/effects/tree, hub upgrades, training actions, unlock tables |
| `data/procgen/` | 25 | Templates, archetypes, biomes, difficulty, encounter tables, golden/smoke layouts |
| `data/recipes/` | 1 | Recipe definitions (750 lines) |
| `data/release/` | 6 | Achievements, build metadata, credits, demo scope, localization, release checklist |
| `data/sanity/` | 1 | Manifestation pool (hallucination table) |
| `data/ship_systems/` | 6 | Systems, subsystem tuning, power budget, hull compartments, web infestation, facility upgrades |
| `data/tools/` | 1 | Tool definitions |
| `data/ui/` | 8 | Accessibility presets, codex, input glyphs, menus, rarity palette, status icons, tooltips, tutorials |
| `data/work_actions/` | 1 | Work action catalog (168 lines) |

---

## Test and validation map

**777 validation smoke scripts** forming a regression bundle of **627 PASS-marker commands**. Final contract: `SYNAPTIC_SEA REGRESSION PASS commands=627 clean_output=true`.

### Smoke categories

- **Pure model smokes:** Unit-level tests of each state machine (`oxygen_state_smoke.gd`, `vitals_state_smoke.gd`, etc.)
- **Main playable smokes:** Integration tests that boot the full coordinator and exercise live production seams (slice completion, save/load, hazards, combat, food, crafting, travel, etc.)
- **Dual-branch smokes:** Every SFX callsite, training XP emission, interact path, work action, and ship modification has both home and away (derelict) counterparts
- **Procgen smokes:** 16-seed × biome/difficulty quality gate, golden parity, determinism, connectivity, nav-graph, encounter injection
- **Doc/infra validators:** Systems map currency, requirement trace, system inventory anti-drift (Python-based)

### Validation contract

- Each smoke prints a single `... PASS ...` marker line
- The `run_clean` harness enforces zero unexpected `ERROR:`/`WARNING:` lines
- Two allowlisted teardown lines (capture unregistered, ObjectDB leak) are ignored
- Exit code alone is untrustworthy (Godot `--script` can exit 0 on parse errors)

---

## Dependency graph (high fan-in files)

Files most depended on (imported/preloaded by others):

| File | Fan-in | Role |
|------|-------:|------|
| `playable_generated_ship.gd` | — | Coordinator (depends on everything; nothing depends on it except `main.gd` and scenes) |
| `audio_event_seam.gd` | ~50+ | SFX/music event ID catalog (constants only) |
| `item_defs.gd` | ~30+ | Item definition lookup service |
| `phase_timer.gd` | ~10 | Shared hazard timer primitive |
| `run_snapshot.gd` | ~10 | Save/load DTO |
| `ship_instance.gd` | ~10 | Per-ship mutable state container |
| `sim_keys.gd` | ~20+ | Simulation key constants (pre-polish PKG-A2) |
| `tuning_catalog.gd` | ~15+ | Externalized gameplay numbers (pre-polish PKG-A4) |

No multi-node import cycles exist; apparent feedback loops are child signals returning to their owner.

---

## Route / API surface

This is a single-player desktop game with no network API. The "API surface" is:

- **Input actions:** WASD/arrows (move), E/Enter/Space (interact), F (attack), R (reload), C (field craft), Tab (scanner), I (inventory), U (ship mod), O (wounds), M (map), F1 (codex), F5 (save), F6 (quicksave), F9 (load), Escape (pause)
- **Save/load:** `user://saves/` directory, JSON format
- **Procgen:** layout.json schema 1.2.0 (shared between golden and generated ships)
- **Data-driven:** all gameplay tuning via `data/**/*.json`

---

## Risk hotspots

| Risk | Severity | File(s) | Mitigation |
|------|----------|---------|------------|
| **Coordinator size** | High | `playable_generated_ship.gd` (11,456 lines) | `ShipRuntime` strangler extraction started (PKG-A1); file remains large. Dual-branch invariant is the primary regression vector. |
| **Dual-branch drift** | High | `playable_generated_ship.gd::_process` | Dual-branch smoke tests cover every SFX/training/interact path. Three prior regressions (PRs #42–#44) drove the "wire both branches" convention. |
| **Ambient/spatial audio** | Medium | `ambient_zone_state.gd`, `spatial_audio_resolver.gd` | Lowest completion % in inventory (45–50%). Content-deferred, not structurally broken. |
| **Cloud saves** | Low | `cloud_manifest_state.gd` | Stub only (ADR-0032). Intentionally deferred. |
| **Kit art fidelity** | Low | `data/kits/ship_structural_v0.json` | Single structural kit; damaged/breached variants are content work. |

---

## Setup / runbook

### Prerequisites

- Godot 4.6.2 console build (Windows: `Godot_v4.6.2-stable_win64_console.exe`)
- Git (repo on `main` branch)

### Run the game

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --path "$ROOT"
```

### Run validation

```bash
# Single smoke
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke_name>.gd

# Full regression bundle (627 commands)
# Run the bash block in docs/game/06_validation_plan.md with GODOT/ROOT set
```

### System inventory check

```bash
python tools/build_system_inventory.py --check
```

---

## Conventions

- **Typed GDScript** for new systems
- **Conventional Commits:** `feat:`, `fix:`, `refactor:`, `test:`, `docs:`
- **Validation is the definition of done** — no completion claim without PASS-marker output
- **Feature specs** (`docs/game/features/`) and **ADRs** (`docs/game/adr/`) are the decision vehicles
- **Data-driven tuning** via `data/**/*.json` — not hardcoded constants
- **No autoloads** except MCP debug runtimes (stripped at export)
- **Signals / dependency injection** over hardcoded node paths

---

## Exhaustive references

- **System inventory:** `docs/game/inventory/SYSTEM_INVENTORY.md` (191 systems, code-verified)
- **Interactive map:** `docs/game/inventory/system_map.html` (card grid + integration matrix)
- **Architecture diagrams:** `docs/game/architecture/` (5 C4/sequence/state/component diagrams)
- **ADR index:** `docs/game/adr/README.md` (55 ADRs, current through ADR-0051)
- **Validation plan:** `docs/game/06_validation_plan.md` (627-command regression bundle)
- **Integration debt:** `docs/game/integration_debt.md` (reachability ledger)
- **Feature specs:** `docs/game/features/` (32 specs)
- **Balance/tuning:** `docs/game/balance/` (12 tuning docs)
- **Status:** `STATUS.md` (project-level status source of truth)
