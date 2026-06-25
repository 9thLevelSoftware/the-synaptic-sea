# The Sargasso of Stars — Architectural Reference

A complete architectural map of the Godot 4.6.2 project at `~/the-synaptic-sea`.
Generated 2026-06-25. Read this end-to-end for onboarding, refactoring, or planning.

The project is a **locked-isometric 3D space-horror survival sim**: the player
repairs a hub ship trapped in a biomatter web and explores procedurally
generated derelicts. All gameplay code lives in `scripts/`; data and asset
descriptors in `data/` and `assets/`; the bootable scene graph in `scenes/`.

---

## 1. TOP-LEVEL STRUCTURE

```
~/the-synaptic-sea/
├── AGENTS.md                         Agent operating manual (project conventions)
├── README.md                         Project description, controls, build info
├── project.godot                     Godot 4.6.2 project config (785 bytes)
├── export_presets.cfg                Headless export preset definitions
├── icon.svg / icon.svg.import        App icon
├── .gitignore
│
├── scenes/                           Bootable scene tree (.tscn)
│   ├── main.tscn                     Main scene — instances PlayableGeneratedShip
│   ├── generated/                    Pre-baked sample ship scenes (debug)
│   ├── procgen/                      Templates for runtime procedural ships
│   ├── validation/                   Validation harnesses (readability, M7 proofs)
│   └── wrappers/structural/ship_structural_v0/   15 module scenes + per-module contracts
│
├── scripts/                          All GDScript (245 files)
│   ├── main.gd                       SceneTree-level boot coordinator
│   ├── camera/                       IsoCameraRig
│   ├── export/                       build_release.sh
│   ├── interaction/                  Interactable (Area3D)
│   ├── placement/                    ModularAssetSpec (.tres schema)
│   ├── player/                       PlayerController
│   ├── procgen/                      Blueprint / layout / template pipeline
│   ├── systems/                      Pure-model state + ship-system manager
│   ├── tools/                        In-world interactable tools
│   ├── ui/                           HUD / panels
│   └── validation/                   ~110 smoke/validation harnesses
│
├── data/                             Authored content (JSON; not code)
│   ├── items/                        item_definitions.json + equipment_definitions.json
│   ├── kits/ship_structural_v0.json  Module kit (47 entries, 40.7K)
│   ├── placement/contracts/structural/ship_structural_v0/  15 .tres contracts
│   ├── player/                       classes.json, skills.json
│   ├── procgen/                      archetypes/, templates/, golden/, smoke/
│   ├── ship_systems/systems.json     Ship-system definitions
│   └── tools/tool_definitions.json   Portable tool defs
│
├── assets/imported/                  Imported art assets
├── docs/                             Specs, plans, design notes
├── artifacts/                        Build artifacts
└── tools/                            Host-side CLI helpers
```

### Convention observed across the codebase

- **Pure-model first**: most state objects (`class_name X`, `extends RefCounted`)
  hold no scene-tree references; they round-trip via `get_summary() /
  apply_summary()` for save/load. This makes them testable from
  `--headless --script` smokes (which use `extends SceneTree`, no Main loop).
- **Coordinator scripts** own scene-tree references; pure models are owned by
  the coordinator and passed in via factory `create()` or `preload()` constants.
- **`load()`-self-reference factory**: most state objects expose
  `static func create(): script = load("res://..."); return script.new()` because
  `class_name` globals are unreliable under `--headless --script`.

---

## 2. PROJECT CONFIG (`project.godot`)

Full contents (30 lines, 785 bytes):

```
config_version=5

[application]
config/name="The Sargasso of Stars"
config/description="Locked-isometric 3D space-horror survival sim: ..."
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.6", "Forward Plus")
config/icon="res://icon.svg"

[autoload]
GDAIMCPRuntime="*uid://dcne7ryelpxmn"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720

[rendering]
textures/vram_compression/import_etc2_astc=true
```

### Important: there are no game autoloads.

The `[autoload]` section only registers `GDAIMCPRuntime`, which is the MCP
plugin's runtime (external, used for IDE-assisted development). All game
singletons live in **dedicated scripts** referenced through `preload()` and
constructed at runtime by `PlayableGeneratedShip` (see §3). There is no
`GameManager` autoload.

### Engine / input / physics / layer config

- **Engine**: Godot 4.6.2 (`config_version=5`, feature set "4.6" +
  "Forward Plus" — Vulkan renderer).
- **Viewport**: 1280×720 fixed.
- **Input map**: not declared in `project.godot`. Inputs are registered
  dynamically in `scripts/procgen/playable_generated_ship.gd` (the playable
  build registers `move_left/right/up/down`, `interact`, `scanner_toggle`,
  `inventory_toggle`, `save`, `load`, `flashlight_toggle`, etc., with both
  WASD and Arrow / Enter / Space alternates — see A11Y-P1-002 references in
  the codebase).
- **Physics layers**: not declared in `project.godot`. The code uses raw
  layer values (`collision_layer = 1`, `collision_mask = 1`) and comments
  refer to a default 3D layer convention.
- **Rendering**: ETC2/ASTC VRAM compression enabled (Forward+ mobile-friendly
  texture path).

---

## 3. AUTOLOADS / SINGLETONS

There is **one** project-level autoload (`GDAIMCPRuntime`) and it is an MCP IDE
plugin, not gameplay. The "singletons" in this game are **scene-local
references** owned by the `PlayableGeneratedShip` root and accessed via
`preload()` constants inside the same script.

### `scripts/main.gd` — Boot entry point

`scenes/main.tscn` instances `PlayableGeneratedShip` (via `scripts/main.gd`,
which is a thin scene-level boot). The flow:

1. Engine boots → loads `scenes/main.tscn`.
2. `main.tscn` (386 bytes) holds a single `Node` root with `scripts/main.gd`
   attached.
3. `main.gd` instantiates the `PlayableGeneratedShip` scene and adds it as a
   child.

### `scripts/procgen/playable_generated_ship.gd` — The actual game coordinator

**5240 lines, ~245 KB**. This is the de-facto singleton: it owns every state
object and UI panel. Key responsibilities:

- Loads the home-ship layout, builds the home ship via `GeneratedShipLoader`.
- Constructs and persists: `InventoryState`, `EquipmentState`,
  `ShipSystemsManager`, `PlayerProgressionState`, `RouteControlState`,
  `OxygenState`, `ObjectiveProgressState`, `SargassoWorld`, `ScannerState`,
  `TravelController`, `PlayerVitalsModel`, `SaveLoadService`, `RunSnapshot`,
  `WorldSnapshot`.
- Manages `current_ship`, `home_ship`, `lifeboat_ship`, `piloted_ship`,
  `visited_ships: Dictionary[marker_id -> ShipInstance]`.
- Builds the HUD: `scanner_panel`, `inventory_panel`, `tracker`
  (ObjectiveTracker), `vitals_panel`, accessibility settings.
- Wires all signals (tool pickup, repair, breach, fire, arc, dock-barrier,
  hangar, cargo, cart, bridge-terminal).
- Handles save/load (F5/F9), autosave (REQ-012), input map registration,
  snapshot round-trip.

### Inter-coordinator dependencies (a partial view)

```
PlayableGeneratedShip
  ├── PlayerController            (scripts/player/player_controller.gd)
  ├── IsoCameraRig                (scripts/camera/iso_camera_rig.gd)
  ├── ScannerPanel                (scripts/ui/scanner_panel.gd)
  ├── InventoryPanel              (scripts/ui/inventory_panel.gd)
  ├── ObjectiveTracker            (scripts/ui/objective_tracker.gd)
  ├── PlayerVitalsPanel           (scripts/ui/player_vitals_panel.gd)
  ├── AccessibilitySettings       (scripts/ui/accessibility_settings.gd)
  ├── ShipSystemsManager          (scripts/systems/ship_systems_manager.gd)
  ├── InventoryState              (scripts/systems/inventory_state.gd)
  ├── EquipmentState              (scripts/systems/equipment_state.gd)
  ├── OxygenState                 (scripts/systems/oxygen_state.gd)
  ├── RouteControlState           (scripts/systems/route_control_state.gd)
  ├── FireState                   (scripts/systems/fire_state.gd)
  ├── ElectricalArcState          (scripts/systems/electrical_arc_state.gd)
  ├── ObjectiveProgressState      (scripts/systems/objective_progress_state.gd)
  ├── SargassoWorld               (scripts/systems/sargasso_world.gd)
  ├── ScannerState                (scripts/systems/scanner_state.gd)
  ├── TravelController            (scripts/systems/travel_controller.gd)
  ├── PlayerProgressionState      (scripts/systems/player_progression_state.gd)
  ├── PlayerVitalsModel           (scripts/systems/player_vitals_model.gd)
  ├── SaveLoadService             (scripts/systems/save_load_service.gd)
  ├── RunSnapshot                 (scripts/systems/run_snapshot.gd)
  ├── WorldSnapshot               (scripts/systems/world_snapshot.gd)
  ├── ShipInstance (home)         (scripts/systems/ship_instance.gd)
  ├── ShipInstance (lifeboat)     (scripts/procgen/life_boat.gd)
  ├── DockingManager              (scripts/systems/docking_manager.gd)
  ├── DockPorts (static)          (scripts/systems/dock_ports.gd)
  └── ShipOccupancy (static)      (scripts/systems/ship_occupancy.gd)
```

This is a "fat coordinator" pattern — almost everything is reachable from one
root, which is convenient for save/load round-trip and `smoke` validation but
means it is by far the most complex file in the codebase (5240 lines).

---

## 4. SCENE TREE

39 `.tscn` files total, organized as follows:

### `scenes/main.tscn`
- Root: `Node` with `scripts/main.gd` attached.
- Sole purpose: instantiate `PlayableGeneratedShip` and let it run.

### `scenes/procgen/`
| File | Root node | Script | Purpose |
|---|---|---|---|
| `playable_generated_ship.tscn` | Node3D | PlayableGeneratedShip | The playable "main" scene |
| `playable_coherent_ship.tscn` / `_002.tscn` | Node3D | PlayableGeneratedShip | Curated showcase ships (deterministic golden fixtures) |
| `generated_ship_demo.tscn` | Node3D | GeneratedShipDemo | Demo runner (signal-based) |

### `scenes/generated/`
Pre-baked sample ships and HTML/SVG visualizations used by the HTML ship
layout viewer.

| File | Purpose |
|---|---|
| `ship_data.json` | Snapshot of generated ships (4.7K) |
| `ship_layouts.html` / `.svg` / `_screenshot.png` | Visualizations |
| `start_scene_seed_*.tscn` | Pre-baked start scenes (3 seeds: 42, 999, 7777) |
| `derelict_seed_42.tscn`, `life_boat.tscn` | Pre-baked derelicts |

### `scenes/validation/`
Validation harnesses — debug scenes that spawn a fixed layout of representative
prefabs to test rendering and gameplay contracts.

| File | Script | Purpose |
|---|---|---|
| `locked_iso_readability_harness.tscn` | LockedIsoReadabilityHarness | Spawns 4 readability samples in fixed grid |
| `m7_web_breached_encounter_proof.tscn` | M7WebBreachedEncounterProof | M7 milestone: web-breached corridor proof |
| `samples/` | 4 sample .tscn prefabs | Structural web brace, maintenance workbench, dressing tendril, EVA suit |
| `generated/m7_web_breached_corridor/` | Auto-generated zone assembly | plan.json + scene_slop_report.json + 8 dressing manifests |

### `scenes/wrappers/structural/ship_structural_v0/`
15 module prefabs (floor_1x1, floor_2x1, corridor_floor_1x1/1x2, walls,
doorways, pillars, ramps, ceiling, bulkhead-portal). Each is a `.tscn` plus
a paired `.input.json` (intake contract) and `.manifest.json` (output spec).
The 15 paired `.tres` files in `data/placement/contracts/...` formalize the
schema (see §13).

### Scene instantiation patterns

- **Packed-scene placement**: `StructuralPlacer.place_structure()` instantiates
  module scenes from `res://scenes/wrappers/structural/ship_structural_v0/`
  for each room role.
- **`add_child` runtime assembly**: `PlayableGeneratedShip` programmatically
  constructs its `interaction_root`, `affordance_root`, `route_control_root`,
  `loot_container_root`, `repair_point_root` as Node3D containers and
  `add_child()`s the in-world interactables.
- **`change_scene` / scene transitions**: NOT used. The game keeps a single
  `PlayableGeneratedShip` instance and travels between ships by **scene-graph
  manipulation** (add/remove generated ship roots) rather than changing the
  main scene.

---

## 5. SIGNAL FLOW

### Major signal buses (defined as `signal` declarations)

| Signal | File:line | Emitter | Used by |
|---|---|---|---|
| `interact_requested(player)` | `player_controller.gd:4` | PlayerController | Coordinator dispatches raycast hit |
| `interaction_completed(interaction_id, objective_id, sequence, objective_type, room_id, step_id)` | `interactable.gd:4` | Interactable | Coordinator records objective progress |
| `playable_ready(summary)` | `playable_generated_ship.gd:52` | PlayableGeneratedShip | Tests / loading screens |
| `playable_failed(reason)` | `playable_generated_ship.gd:53` | PlayableGeneratedShip | Tests |
| `playable_interaction_completed(...)` | `playable_generated_ship.gd:54` | PlayableGeneratedShip | Coordinator mirror |
| `playable_slice_completed(summary)` | `playable_generated_ship.gd:55` | PlayableGeneratedShip | Coordinator / tests |
| `tool_acquired(tool_id)` | `tool_pickup.gd:13` | ToolPickup | Coordinator updates HUD |
| `repair_completed(system_id, subcomponent_id)` | `repair_point.gd:10` | RepairPoint | Coordinator routes into ShipSystemsManager |
| `repair_blocked(system_id, subcomponent_id, reason)` | `repair_point.gd:11` | RepairPoint | Coordinator shows prompt |
| `container_searched(container_id, granted)` | `loot_container.gd:10` | LootContainer | Coordinator applies loot |
| `breach_opened(marker_id)` | `dock_port_barrier.gd:9` | DockPortBarrier | Coordinator unblocks player |
| `login_requested(ship_id)` | `bridge_terminal.gd:9` | BridgeTerminal | Coordinator claims ship |
| `cargo_deposit_requested(carrier_id)` | `cargo_hold_control.gd:9` | CargoHoldControl | Coordinator bulk-deposits |
| `cargo_withdraw_requested(carrier_id, category)` | `cargo_hold_control.gd:10` | CargoHoldControl | Coordinator bulk-withdraws |
| `bay_dock_requested(carrier_id, slot_index)` | `hangar_bay_control.gd:11` | HangarBayControl | Coordinator docks |
| `bay_launch_requested(carrier_id, slot_index)` | `hangar_bay_control.gd:12` | HangarBayControl | Coordinator launches |
| `cart_grab_requested(cart_id)` | `cart_control.gd:9` | CartControl | Coordinator grabs cart |
| `cart_load_requested(cart_id)` | `cart_control.gd:10` | CartControl | Coordinator bulk-loads |
| `cart_unload_requested(cart_id, category)` | `cart_control.gd:11` | CartControl | Coordinator bulk-unloads |
| `panel_closed` | `scanner_panel.gd:12`, `inventory_panel.gd:10` | ScannerPanel / InventoryPanel | Coordinator restores player control |
| `transfer_completed` | `inventory_panel.gd:11` | InventoryPanel | Coordinator recomputes encumbrance bonus |
| `objective_completed(...)` | `gameplay_objective_volume.gd:4` | GameplayObjectiveVolume | Coordinator advances sequence |
| `ship_loaded(summary)` | `generated_ship_loader.gd:6` | GeneratedShipLoader | Coordinator spawns scene |
| `load_failed(reason)` | `generated_ship_loader.gd:7` | GeneratedShipLoader | Coordinator error path |

### Event pattern

This project uses **direct signal connections from coordinator to in-world
interactables**, not a global event bus. The `PlayableGeneratedShip` connects
to each `Interactable.interaction_completed`, each `ToolPickup.tool_acquired`,
each `RepairPoint.repair_completed`, each `LootContainer.container_searched`,
etc., at the time the interactable is spawned.

Pure-model state objects (`InventoryState`, `ShipSystemsManager`, etc.) do
**not** emit signals — they expose synchronous getters (`get_quantity`,
`is_operational`, `get_status_lines`). The coordinator polls them per-frame
and pushes string summaries to UI panels.

### Input signal flow

`PlayerController._input(event)` translates `InputEvent`s to action names
and emits `interact_requested(player)`. Coordinator raycasts forward from the
camera and dispatches to the hit `Interactable`.

---

## 6. DATA ARCHITECTURE

### `.tres` resource files (15 total)

All 15 live in `data/placement/contracts/structural/ship_structural_v0/` —
one contract per module scene, mirroring the 15 `.tscn` files in
`scenes/wrappers/structural/ship_structural_v0/`:

```
bulkhead_portal_2x1_contract.tres
ceiling_cap_1x1_contract.tres
corridor_floor_1x1_contract.tres
corridor_floor_1x2_contract.tres
doorway_frame_blocked_1x1_contract.tres
doorway_frame_open_1x1_contract.tres
floor_1x1_contract.tres
floor_2x1_contract.tres
pillar_support_1x1_contract.tres
ramp_up_1x2_contract.tres
wall_end_cap_contract.tres
wall_inner_corner_contract.tres
wall_outer_corner_contract.tres
wall_straight_1x1_contract.tres
wall_t_junction_contract.tres
```

Schema: `class_name ModularAssetSpec` (`scripts/placement/modular_asset_spec.gd`)
— `extends Resource` with `@export` fields `schema_version`, `asset_id`,
`module_id`, `category`, `kit_id`, `module_family`, `grid_step_m`,
`footprint_cells: Array[int]`, `bounds: Dictionary`, `sockets: Array[Dictionary]`,
`collision: Dictionary`, `provenance: Dictionary`, `source_asset_path`,
`wrapper_scene`, `contract_path`, `inspection_path`, `asset: Dictionary`.

These are design-time documentation rather than runtime-loadable assets;
the runtime placer reads the JSON kit instead.

### JSON data files (50 total)

| Path | Loader | Purpose |
|---|---|---|
| `data/items/item_definitions.json` | `ItemDefs.load_definitions` | Player carryable items (category, weight, max_stack) |
| `data/items/equipment_definitions.json` | `ItemDefs.load_definitions` | Equip slot, container capacity, weight reduction |
| `data/tools/tool_definitions.json` | `ItemDefs.load_definitions` | Portable tools (synthetic `category="tool"`) |
| `data/items/loot_tables.json` | `LootRoller` | Loot-table references for containers |
| `data/kits/ship_structural_v0.json` | `GeneratedShipLoader` | Module kit (47 entries) |
| `data/player/classes.json` | `ClassDefinition.load` | Player starting classes (engineer, ...) |
| `data/player/skills.json` | `PlayerProgressionState` | Skill definitions |
| `data/ship_systems/systems.json` | `ShipSystemsManager.load_definitions` | System + subcomponent definitions |
| `data/procgen/archetypes/*.json` | `TemplateSelector.select` | Ship archetype descriptors (4: life_boat, derelict, medium_cruiser, small_freighter) |
| `data/procgen/templates/*.json` | `TopologyTemplate.from_dict` | Zone/connection topology templates (3: spine, bifurcated, stacked) |
| `data/procgen/golden/coherent_ship_001/*.json` | Manual fixtures | blueprint.json + layout.json + gameplay_slice.json |
| `data/procgen/smoke/seed_000017/*.json` | `PlayableGeneratedShip` defaults | layout.json + gameplay_slice.json (smoke baseline) |
| `scenes/wrappers/structural/ship_structural_v0/*.input.json` / `*.manifest.json` | Module import tooling | Per-module input + manifest |
| `user://` (runtime) | `SaveLoadService` | Save files (not in repo) |

### Save / load data architecture

`SaveLoadService` (4.9K) writes a `RunSnapshot` + `WorldSnapshot` pair to
`user://saves/<name>.save`. Snapshots are pure JSON dicts with versioning.

- `RunSnapshot`: player inventory, equipment, progression, current objective
  sequence, oxygen, vitals, fire/arc/breach state.
- `WorldSnapshot`: `SargassoWorld` (world_seed + player_position + generated
  marker ids), `visited_ships` dict (per-`ShipInstance` summary),
  `lifeboat_ship` summary, `dock_barriers`.

Each `ShipInstance` round-trips through `get_summary()` / `apply_summary()`:
blueprint dict, systems dict, objective, looted_containers, access, hangar,
inventory, carts. Pure-model classes (`InventoryState`, `EquipmentState`,
`ShipSystemsManager`, etc.) all implement the same pair.

---

## 7. PLAYER SYSTEMS

### `scripts/player/player_controller.gd` (PlayerController)

- `extends CharacterBody3D` (assumed; not re-read in detail)
- **Signal**: `interact_requested(player: PlayerController)` (line 4)
- **Responsibilities**: WASD/Arrow movement, gravity, floor snap, interact
  raycast, jump (or lack thereof)
- **Dependencies**: reads `InventoryState.bonus_capacity`,
  `EquipmentState` worn gear, `Encumbrance.move_speed_multiplier` for
  Heavy Load penalty, `ShipOccupancy.resolve` for current ship.
- **Key methods**: `_physics_process(delta)`, `_input(event)`,
  `_try_interact()`.

### `scripts/systems/inventory_state.gd` (InventoryState, 198 lines)

- `extends RefCounted`
- Player-global inventory. `MAX_WEIGHT = 50.0`. **PZ-style soft cap**: over-
  capacity is allowed and penalized via Heavy Load, not refused.
- Public: `add_item(id, qty) -> int`, `remove_item(id, qty) -> int`,
  `get_quantity`, `get_total_weight`, `get_capacity`,
  `get_load_ratio`, `get_effective_weight`, `is_over_capacity`,
  `get_items_by_category(cat)`.
- Tool shims (REQ-007): `tool_ids`, `add_tool(id)`, `has_tool(id)`,
  `remove_tool(id)`, `get_drain_multiplier()` (0.5 if has
  `portable_oxygen_pump` else 1.0).
- `get_status_lines()` returns HUD-ready lines including `tool=…`,
  `item=… x N`, `weight=…/…`.

### `scripts/systems/equipment_state.gd` (EquipmentState, 96 lines)

- `extends RefCounted`
- Worn items keyed by slot. `SLOTS = ["suit", "back", "waist",
  "primary_hand", "secondary_hand"]`.
- Public: `can_equip(id)`, `equip(id) -> {ok, displaced}`, `unequip(slot)`,
  `get_equipped(slot)`, `is_slot_occupied(slot)`.
- Aggregate helpers: `get_carry_capacity_bonus()` (sum of
  `container_capacity` across worn items), `get_container_reductions()`
  (for `Encumbrance.weight_reduction_saved`), `get_oxygen_drain_multiplier()`
  (product of `oxygen_drain` effects; suit modifies oxygen drain).

### `scripts/systems/encumbrance.gd` (Encumbrance, 38 lines)

- Static-only. `move_speed_multiplier(load_ratio) -> float` piecewise:
  ≤1.0 → 1.0, ≤1.25 → lerp 1.0→0.63, ≤1.75 → lerp 0.63→0.25, else 0.25.
- `weight_reduction_saved(total_weight, container_reductions) -> float`:
  best-first capacity-share across worn containers.

### `scripts/systems/inventory_selection_model.gd` (InventorySelectionModel)

- Pure per-list selection state (anchor + dict[int→true]). Static
  `context_actions(item_id, defs, in_transfer_mode, row_is_container, is_equipped_slot)`
  → `PackedStringArray` of `"transfer" | "transfer_all" | "split" | "equip" |
  "unequip"`.

### `scripts/systems/item_defs.gd` (ItemDefs, 87 lines)

- All-static. Reads `data/items/item_definitions.json`,
  `data/tools/tool_definitions.json`, `data/items/equipment_definitions.json`
  in that order (tools merge with synthetic `category="tool"` and default
  weight 2.0; item defs override).
- Lookups: `weight_each(id)`, `max_stack(id)`, `display_name(id)`,
  `equip_slot(id)`, `container_capacity(id)`, `weight_reduction(id)`,
  `effects(id)`, `icon(id)`, `category(id)`.

### `scripts/systems/player_vitals_model.gd` (PlayerVitalsModel)

- Pure model: oxygen + health + stamina proxies. Owned by coordinator.
- Used by `PlayerVitalsPanel`.

---

## 8. SHIP SYSTEMS

### `scripts/systems/ship_systems_manager.gd` (ShipSystemsManager, ~9.8K)

- `extends RefCounted`
- Owns a registry of `ShipSystem` instances (`power`, `propulsion`,
  `life_support`, `navigation`, `scanners`).
- `configure(definitions, hull_hp, oxygen_seed)` populates systems and their
  `ShipSubcomponent`s.
- Public: `is_operational(system_id)`, `repair(system_id, subcomponent_id)`,
  `damage(...)`, `tick(delta)`, `get_status_lines() -> PackedStringArray`
  (consumed by `ObjectiveTracker.set_system_status_lines`),
  `apply_summary(dict)` for save round-trip.

### `scripts/systems/ship_system.gd` (ShipSystem, 2.7K)

- One system (e.g. `power`). Has `id`, `operational: bool`, list of
  `ShipSubcomponent`s. Determines operational status from the health of its
  subcomponents.

### `scripts/systems/ship_subcomponent.gd` (ShipSubcomponent, 3.2K)

- Sub-element of a system (e.g. `power_distribution`, `battery_cells`,
  `reactor_core`, `nav_computer`). Holds `health: float`, `operational: bool`,
  `effect_when_active` references.

### `scripts/systems/ship_instance.gd` (ShipInstance, 229 lines)

- Per-ship handle: identity + blueprint + systems manager + scene root.
- Lazily creates `access: ShipAccessState`, `hangar: HangarBay`,
  `inventory: ShipInventory`, `carts: Array[CartState]`,
  `objective_controller: DerelictObjectiveController`.
- Static factory `create(...)` via `load("...").new()` (class_name unreliable
  headless).
- `get_summary()` / `apply_summary()` for save/load.
- `interior_aabb()` computes world-space AABB from `ShipStructure` room nodes.
- `is_working_vessel()` returns true iff `propulsion` is operational.

### `scripts/systems/docking_manager.gd` (DockingManager, 6.1K)

- Coordinates docking between two `ShipInstance`s.
- Uses `DockPorts` (static) to derive port descriptors from layouts.
- Uses `ShipOccupancy.resolve(player_pos, entries)` to determine current ship.
- Dock-seam barriers (`DockPortBarrier`) spawn when piloted ship docks to
  a host; player breaches one to board.

### `scripts/systems/dock_ports.gd` (DockPorts, 162 lines)

- Static helpers: `for_lifeboat(layout)`, `for_derelict(layout, seed,
  condition_class)`, `for_hangar(layout, seed)`,
  `bridge_center(layout)`, `condition_from_seed(seed, condition_class)`,
  `ports_compatible(a, b)`.
- Airlock-to-airlock: same size_class symmetric. Hangar asymmetric (slot
  size gates). Two hangars cannot dock.

### `scripts/systems/ship_occupancy.gd` (ShipOccupancy, 19 lines)

- One static method: `resolve(player_pos, entries)` returns first `ShipInstance`
  whose AABB (grown 0.001) contains the player. Entry order = priority
  (host ship first).

### `scripts/systems/hangar_bay.gd` (HangarBay, 79 lines)

- Per-ship hangar: fixed slots that store other `ShipInstance`s.
- `slot_count`, `slot_size_class`, `slots: Array[String]`.
- `free_slot_for(size_class)`, `dock(ship_id, size_class)`, `launch(slot)`.

### `scripts/systems/ship_inventory.gd` (ShipInventory, 106 lines)

- Per-ship cargo hold. **Hard weight cap** (`MAX_WEIGHT_DEFAULT = 500.0`).
- Public: `add_item(id, qty)`, `remove_item(id, qty)`, `get_quantity`,
  `get_total_weight`, `get_items_by_category`.

### `scripts/systems/cargo_transfer.gd` (CargoTransfer, 88 lines)

- Pure-static. Conservation contract: `move_item(src, dst, id, qty)` removes
  EXACTLY what dst's `add_item` accepted.
- `HAULABLE_CATEGORIES = ["part", "supply"]` (tools intentionally excluded).
- `deposit_all(player, hold)`, `withdraw_category(hold, player, cat)`,
  `move_items(src, dst, id_to_qty_dict)`.

### `scripts/systems/cart_state.gd` (CartState, 57 lines)

- Pushable cart wrapping a `ShipInventory` (`MAX_WEIGHT_DEFAULT = 200.0`,
  `PUSH_SPEED_MULTIPLIER_DEFAULT = 0.7`). Cart contents NOT in player
  encumbrance.

### Hazard / lifecycle state objects

- `fire_state.gd` (FireState, 8.3K): timed fire zones with clearable/burning
  lifecycle.
- `electrical_arc_state.gd` (ElectricalArcState, 8.0K): timed arc hazards.
- `route_control_state.gd` (RouteControlState, 5.1K): route gate open/closed.
- `oxygen_state.gd` (OxygenState, 16.5K): per-room oxygen simulation with
  breach hazards and equipment drain.
- `objective_progress_state.gd` (ObjectiveProgressState, 9.0K): multi-step
  objective tracking.

### `scripts/systems/save_load_service.gd` (SaveLoadService, 5.8K)

- `extends RefCounted`
- Handles F5/F9 + autosave (REQ-012). Reads/writes
  `RunSnapshot` + `WorldSnapshot` JSON to `user://saves/<name>.save`.
- Coordinates `PlayableGeneratedShip._capture_full_snapshot()` →
  `RunSnapshot.from_dict` → `apply_summary`.

---

## 9. PROCEDURAL GENERATION

### Pipeline overview

```
MarkerGenerator           (deterministic infinite marker field)
  → ShipGenerator         (per-marker: archetype + template + layout)
    → ShipBlueprint       (deterministic seed -> ShipBlueprint)
      → TemplateSelector  (archetype.template OR random pick from AVAILABLE_TEMPLATES)
      → TopologyTemplate  (zones + connections + deck config, from JSON)
      → RoomAssigner      (assign roles to zones)
      → CellLayoutEngine  (zone/footprint -> grid positions)
      → ShipLayoutGenerator (room placement record)
      → StructuralPlacer  (instantiate module .tscn under ShipStructure)
      → GeneratedShipLoader (build scene tree from layout JSON)
```

### `scripts/procgen/marker_generator.gd` — handled in `systems/`

Actually lives under `scripts/systems/marker_generator.gd` (despite being a
procgen dependency). `CELL_SIZE = 100.0`, `MARKERS_PER_CELL = 3`. Weighted
size (40% LIFE_BOAT, 40% SMALL, 20% MEDIUM) and condition (15% PRISTINE, 45%
DAMAGED, 40% WRECKED).

### `scripts/procgen/ship_blueprint.gd` (ShipBlueprint, 3.5K)

- `extends RefCounted`
- `seed_value`, `size_class`, `archetype_id`, `template_id`. `to_dict()` /
  `from_dict(dict)`.

### `scripts/procgen/ship_generator.gd` (ShipGenerator, 4.5K)

- `extends RefCounted`
- `generate_from_seed(seed, size_class, condition) -> ShipInstance`.
- Glues: blueprint → archetype → template → room graph → cell layout →
  layout dict → ship instance (with systems manager + scene root).

### `scripts/procgen/room_graph.gd` (RoomGraph, 5.9K)

- Pure data: rooms (`{id, role, ...}`) and adjacency edges.
- Used by `RoomGraphGenerator` and the placer.

### `scripts/procgen/room_graph_generator.gd` (RoomGraphGenerator, 12.9K)

- Template-driven room graph synthesis. Produces a `RoomGraph` from a
  `TopologyTemplate`.

### `scripts/procgen/room_assigner.gd` (RoomAssigner, 4.8K)

- Assigns room roles to template zones based on `role_pool` and count.

### `scripts/procgen/cell_layout_engine.gd` (CellLayoutEngine, 16K)

- Places rooms on a 2D grid (`CELL_SIZE = 4.0`, `DECK_HEIGHT = 4.0`).
- Bow = +X (east). Direction preferences per role.
- Hazardous roles (`reactor`, `engineering`) must not share walls with crew
  comfort roles (`crew_quarters`, `medical`, `mess_hall`, `bridge`).
- 3 fallback strategies: rotation, alternate anchor, push_error.

### `scripts/procgen/structural_placer.gd` (StructuralPlacer, 13K)

- Builds the `ShipStructure` Node3D tree.
- `place_structure(graph, seed) -> Node3D`.
- v3 features: directional preferences, airlock separation (≥3 cells from
  bridge on non-life-boat ships), post-layout swap, branching BFS.
- Module lists per role (ROOM_MODULES dict) drive `.tscn` instantiation from
  `res://scenes/wrappers/structural/ship_structural_v0/`.

### `scripts/procgen/topology_template.gd` (TopologyTemplate, 80 lines)

- `from_dict(data)` parses JSON templates. `get_zone(id)`,
  `get_zones_attached_to(parent_zone_id)`.

### `scripts/procgen/template_selector.gd` (TemplateSelector, 40 lines)

- Picks template: explicit `archetype.template` OR random from
  `["spine", "bifurcated", "stacked"]` keyed off blueprint seed.

### `scripts/procgen/ship_layout_generator.gd` (ShipLayoutGenerator, 2.3K)

- Generates the final per-room module placement dict consumed by
  `StructuralPlacer` / `GeneratedShipLoader`.

### `scripts/procgen/life_boat.gd` (LifeBoatBuilder, 5.7K)

- Builds the lifeboat as a docked ship at boot.

### `scripts/procgen/generated_ship_loader.gd` (GeneratedShipLoader, 40K)

- Loads a layout JSON and instantiates the full Node3D tree, wiring
  affordances, hazards, interactables.
- `signal ship_loaded(summary)`, `signal load_failed(reason)`.

### `scripts/procgen/readability_prop_factory.gd` (13K)

- Builds affordance props (signage, lighting props) on the ship for visual
  readability under locked-iso camera.

### `scripts/procgen/start_scene_builder.gd` (8.2K)

- Builds the "starting scene" snapshot used for golden fixtures.

### `scripts/procgen/layout_serializer.gd` (10K)

- Layout dict <-> JSON round-trip.

### `scripts/procgen/gameplay_objective_volume.gd` (1.9K)

- `signal objective_completed(objective_id, sequence, objective_type, room_id)`.
- Volume trigger for advancing objective sequence.

### `scripts/procgen/wall_door_resolver.gd` (4.9K)

- Resolves wall / door placement from room adjacency edges.

### Procgen scenes

- `scenes/procgen/playable_generated_ship.tscn` — runtime ship loader.
- `scenes/procgen/playable_coherent_ship{,_002}.tscn` — golden fixtures.
- `scenes/procgen/generated_ship_demo.tscn` — demo scene.

---

## 10. UI SYSTEMS

All UI panels are `Control` (or `CanvasLayer` wrappers) instantiated by the
coordinator.

### `scripts/ui/accessibility_settings.gd` (AccessibilitySettings, 115 lines)

- `extends RefCounted`
- Pure model. `_text_scale` ∈ [1.0, 2.0]. Sources: env
  `SARGASSO_TEXT_SCALE` → project setting `sargasso/accessibility/text_scale`
  → default 1.0.
- Helpers: `scaled_hud_font_size(base)`, `scaled_hud_minimum_size(base)`,
  `scaled_hud_panel_size(base)`, `scaled_world_pixel_size(base)` (divides
  Label3D pixel_size by scale).
- `resolve_text_scale()` static for headless validation.

### `scripts/ui/objective_tracker.gd` (ObjectiveTracker, 246 lines)

- `extends Control`. Top-left HUD panel.
- Public API: `set_objectives(list)`, `set_system_status_lines(lines)`,
  `set_current_sequence(seq)`, `set_step_progress(seq, dict)`,
  `set_interaction_prompt(text)`, `mark_completed(seq)`,
  `mark_run_complete()`, `get_completed_count()`,
  `is_sequence_completed(seq)`, `get_hud_text()`, `apply_accessibility_settings(settings)`.
- Shows "Controls: WASD or Arrows move / E or Enter or Space interact /
  F5 save / F9 load" line.

### `scripts/ui/scanner_panel.gd` (ScannerPanel, 141 lines)

- `extends Control`. `signal panel_closed`.
- `bind(coordinator)` wires scan() + travel_to_marker_id().
- `open()`, `close()`, `toggle()`, `move_selection(dir)`,
  `confirm_selection()` → returns `{success, reason, ship}`.
- `get_status()`, `get_row_texts()` for headless validation.

### `scripts/ui/inventory_panel.gd` (InventoryPanel, 552 lines)

- `extends Control`. Dark-teal panel. **Largest UI file.**
- `signal panel_closed`, `signal transfer_completed`.
- Public API: `open_self(inv, equip)`, `open_transfer(player_inv, hold,
  label, equip)`, `close()`, `select_row(pane, idx, additive, range_sel)`,
  `transfer_selected(from_pane)`, `transfer_all_from(pane)`,
  `deposit_all_to_container()`, `equip_selected()`, `equip_from_container(id)`,
  `unequip_slot(slot_id)`, `get_load_badge()`, `zone_can_accept(target,
  data)`, `zone_drop(target, data)`.
- Builds real widget tree: `InventoryRow` + `InventoryDropZone` for
  drag-and-drop.

### `scripts/ui/inventory_row.gd` (InventoryRow, 2.9K)

- Row UI element; emits clicks/drags/context to `InventoryPanel`.

### `scripts/ui/inventory_drop_zone.gd` (InventoryDropZone, 1.3K)

- Drop target for inventory rows.

### `scripts/ui/player_vitals_panel.gd` (PlayerVitalsPanel, 5.6K)

- `extends Control`. Renders `PlayerVitalsModel` (oxygen, health proxies).

---

## 11. CAMERA

### `scripts/camera/iso_camera_rig.gd` (IsoCameraRig, 1.5K)

- `extends Node3D` (or Camera3D + pivot — single file)
- **Locked isometric camera**: fixed 45°/30° pitch, follows player, no free
  rotation. Damping enabled.
- Public API: follows player, queries `PlayerController.global_position`.
- The "locked-isometric" decision is enforced by the rig itself (no free-orbit
  input registered).

The `locked_iso_readability_harness` validation scene verifies that
representative readability props read clearly under the locked camera angle.

---

## 12. INTERACTION

### `scripts/interaction/interactable.gd` (Interactable, 6.2K)

- `extends Area3D`
- **Signal**: `interaction_completed(interaction_id, objective_id, sequence,
  objective_type, room_id, step_id)` (line 4).
- Public fields: `interaction_id`, `objective_id`, `sequence`,
  `objective_type`, `room_id`, `step_id`, `interaction_radius`, prompt text.
- Public API: `try_interact(player) -> bool`, `set_validation_player_in_range(player)`,
  `get_interaction_prompt()`.
- Internally uses Area3D `body_entered` / `body_exited` to track candidate
  player. Direct-range fallback (`_is_player_in_direct_range`) prevents stale
  candidates after teleports.

### Interaction dispatch

```
PlayerController._input(interact) 
  → emits interact_requested(player)
  → coordinator raycasts forward from camera
  → if hit Interactable, calls try_interact(player)
  → on success, Interactable emits interaction_completed(...)
  → coordinator records objective progress, advances sequence
```

There is **no dedicated raycast script** — raycasting is inlined in the
coordinator's `_input` / `_physics_process` handler. The `Interactable`'s
Area3D also supports proximity (collision layers).

---

## 13. PLACEMENT

### `scripts/placement/modular_asset_spec.gd` (ModularAssetSpec, 21 lines)

- `extends Resource`, 15 `@export` fields (see §6).
- The .tres contracts in `data/placement/contracts/structural/ship_structural_v0/`
  are instances of this Resource.

### `scripts/validation/validate_wrapper_scenes.gd` (20K)

- Static validator that scans the kit + scenes and asserts every
  module_id in the JSON kit has a matching wrapper scene, contract .tres,
  input.json, and manifest.json, and that footprints match.

### Grid system

- `CELL_SIZE = 4.0`, `ROOM_GAP = 2.0` (in `StructuralPlacer`).
- Module footprints `Vector2i(2, 1)` for ship roles (engineering, bridge,
  cargo, life_support, bay); `Vector2i(1, 1)` for floor modules.
- Multi-deck support via `DECK_HEIGHT = 4.0` (CellLayoutEngine).
- Placement is **deterministic from seed**: same seed → same layout.

---

## 14. VALIDATION

### Test harness pattern

All validation scripts live in `scripts/validation/` (~110 files). They all
follow the same pattern:

```gdscript
extends SceneTree

const X := preload("res://scripts/.../x.gd")

func _initialize() -> void:
    # 1. construct pure-model instance
    # 2. exercise API
    # 3. assert invariants
    # 4. print("X PASS ...") and quit(0) OR push_error("X FAIL ...") and quit(1)
```

Invocation pattern:
```
godot-4.6.2 --headless --path ~/the-synaptic-sea --script res://scripts/validation/<name>.gd
```

### Validation scenes

- `scenes/validation/locked_iso_readability_harness.tscn` — instantiates 4
  prefabs in a fixed grid for readability testing under the locked iso cam.
- `scenes/validation/m7_web_breached_encounter_proof.tscn` — milestone 7 proof
  scene for a web-breached corridor encounter.

### Notable smoke coverage

Smokes cover every subsystem and end-to-end flow:
- `main_playable_slice_*` (40+ files) — every flow in the playable slice
  (input, inventory, fire, arc, hazards, save/load, route control, vitals,
  HUD, text scale, template B completion, alternate input, junction calibrator,
  etc.)
- `coherent_*` (10+ files) — golden-fixture playback
- `procgen_*` (15+ files) — generation pipeline
- `derelict_*` (5+ files) — derelict gameplay
- `ship_*`, `cargo_*`, `equipment_*`, `cart_*`, `hangar_*`, `dock_*` (50+ files) —
  per-system unit smokes
- `a11y_p1_002_idempotency_smoke.gd` — accessibility idempotency
- `gate1_automated_playtest.gd` — full automated playtest gate

### `_layout_visual_capture.gd`, `performance_profiler.gd`

Visual capture and perf instrumentation. `main_playable_slice_v2_contact_sheet.py`
is a Python helper that orchestrates capture screenshots.

---

## 15. EXPORT

### `scripts/export/build_release.sh` (156 lines, 4.4K)

- Bash script that exports the game for **web, linux, macos, windows**
  via `godot --headless --export-release`.
- Steps:
  1. **Backup `project.godot`** → `mktemp` file.
  2. **Strip `GDAIMCPRuntime=` autoload line** via Python (release build has
     no MCP runtime).
  3. For each requested preset, run `godot --export-release <preset>
     <output>` and tee log to `build/logs/export_<preset>.log`.
  4. **Fail on `ERROR:` or `SCRIPT ERROR:`** lines.
  5. Package outputs:
     - **web**: zip `build/exports/web/`
     - **linux**: chmod +x + zip the .x86_64 binary
     - **macos**: copy the .zip directly
     - **windows**: zip the .exe
  6. Generate `build/release/artifacts.sha256` (shasum -a 256).
- **Trap `restore_project` on EXIT** to restore the original project.godot
  even on failure.
- Defaults: `SARGASSO_VERSION=v0.1.0`, `BUILD_STAMP=$(date -u +...)`.
- Output: `build/release/sargasso-of-stars-<version>-<stamp>-<target>.<ext>`.

### `export_presets.cfg` (6K)

- Headless export preset definitions for web/linux/macos/windows. Referenced
  by `build_release.sh`.

---

## Summary cheat-sheet

| Concern | Where |
|---|---|
| **Boot scene** | `scenes/main.tscn` → `scripts/main.gd` → `PlayableGeneratedShip` |
| **Coordinator (god-object)** | `scripts/procgen/playable_generated_ship.gd` (5240 lines) |
| **Player movement** | `scripts/player/player_controller.gd` |
| **Inventory / encumbrance** | `scripts/systems/inventory_state.gd`, `encumbrance.gd` |
| **Equipment** | `scripts/systems/equipment_state.gd` |
| **Ship systems** | `scripts/systems/ship_systems_manager.gd`, `ship_system.gd`, `ship_subcomponent.gd` |
| **Hazards** | `oxygen_state.gd`, `fire_state.gd`, `electrical_arc_state.gd` |
| **Docking** | `docking_manager.gd`, `dock_ports.gd`, `ship_occupancy.gd`, `dock_port_barrier.gd` |
| **World / travel** | `sargasso_world.gd`, `marker_generator.gd`, `travel_controller.gd`, `scanner_state.gd` |
| **Procgen** | `scripts/procgen/ship_generator.gd` + `room_graph*.gd` + `cell_layout_engine.gd` + `structural_placer.gd` |
| **UI** | `scripts/ui/{objective_tracker,scanner_panel,inventory_panel,player_vitals_panel,accessibility_settings}.gd` |
| **Interaction** | `scripts/interaction/interactable.gd` |
| **Tools** | `scripts/tools/{tool_pickup,repair_point,loot_container,bridge_terminal,hangar_bay_control,cargo_hold_control,cart_control,dock_port_barrier}.gd` |
| **Camera** | `scripts/camera/iso_camera_rig.gd` |
| **Save/load** | `scripts/systems/save_load_service.gd` + `run_snapshot.gd` + `world_snapshot.gd` |
| **Data definitions** | `data/items/*.json`, `data/ship_systems/systems.json`, `data/player/{classes,skills}.json`, `data/procgen/{archetypes,templates,golden,smoke}/*.json` |
| **Module kit** | `data/kits/ship_structural_v0.json` (47 modules) + `scenes/wrappers/structural/ship_structural_v0/*.tscn` |
| **Validation** | `scripts/validation/*.gd` (~110 files, `extends SceneTree`) |
| **Export pipeline** | `scripts/export/build_release.sh` + `export_presets.cfg` |
| **Autoloads** | Only `GDAIMCPRuntime` (MCP IDE plugin, not gameplay) |
| **No globals / no GameManager** | Everything constructed by `PlayableGeneratedShip._ready()` |

### Key cross-cutting patterns

1. **Pure-model RefCounted + coordinator**: every state object is a pure data
   model that doesn't touch the scene tree; the coordinator owns all scene
   references.
2. **`get_summary()` / `apply_summary()` round-trip**: every state object
   serializes to a JSON dict; `SaveLoadService` composites them.
3. **`load()`-self-reference factory**: `static func create(): script =
   load(...); return script.new()` to defeat `class_name` unreliability
   under `--headless --script`.
4. **`extends SceneTree` smoke harness**: validation scripts are standalone
   `SceneTree` derivatives — no Main loop, no autoloads required.
5. **Direct signal wiring from coordinator**: in-world interactables connect
   their completion signal to the coordinator at spawn time. No global event
   bus.
6. **Deterministic procgen**: `world_seed ^ (cell.x * 73856093) ^ (cell.y *
   19349663)` spatial hash + ordered RNG consumption = reproducible
   infinite field.

---

*End of architectural reference. For onboarding, start with
`scripts/procgen/playable_generated_ship.gd::_ready()` and follow the
construction order of state objects; for refactoring, use the
`get_summary()`/`apply_summary()` contract as the persistence boundary.*