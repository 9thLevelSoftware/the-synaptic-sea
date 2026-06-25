# The Synaptic Sea — Complete Systems Map & Remaining Work

**Generated:** 2026-06-25
**Sources:** Architecture map, planning synthesis, 28 ADRs, 11 feature specs, web research (Godot 4.6.2, Steam/itch.io, genre references)
**Project:** ~/the-synaptic-sea (Godot 4.6.2, GDScript, Forward+)
**Scope:** Full packaged commercial game — excludes game assets (art/audio)

---

## PART 1: ARCHITECTURE OVERVIEW

### 1.1 Project Structure
```
~/the-synaptic-sea/
├── scenes/          39 .tscn (main, procgen, validation, wrappers)
├── scripts/         245 .gd (camera, export, interaction, placement,
│                            player, procgen, systems, tools, ui, validation)
├── data/            ~50 JSON files (items, kits, player, procgen, ship_systems, tools)
├── assets/imported/ Art assets
├── docs/            Specs, ADRs, plans, playtests
└── tools/           Host-side CLI helpers
```

### 1.2 Architecture Pattern
- **Pure-model RefCounted + fat coordinator**: `PlayableGeneratedShip` (5240 lines) is the god-object that owns all state objects and scene references
- **No autoloads** (except dev MCP plugin) — no GameManager singleton
- **No global event bus** — direct signal wiring from coordinator to interactables at spawn time
- **`get_summary()` / `apply_summary()` round-trip** on every state object for save/load
- **`load()`-self-reference factory** to defeat `class_name` unreliability headless
- **`extends SceneTree` smoke harness** for ~110 validation scripts
- **Deterministic procgen**: spatial hash + ordered RNG = reproducible infinite field

### 1.3 Key Class Hierarchy
```
PlayableGeneratedShip (coordinator, 5240 lines)
  ├── PlayerController (CharacterBody3D) — movement, interact raycast
  ├── IsoCameraRig (Node3D) — locked 45/30 iso, follows player
  ├── ShipSystemsManager → ShipSystem → ShipSubcomponent
  ├── InventoryState (soft-cap weight, 50 max)
  ├── EquipmentState (suit/back/waist/hands slots)
  ├── OxygenState (per-room sim, breach hazards)
  ├── FireState (timed burning/clearing cycle)
  ├── ElectricalArcState (timed arcing/discharge)
  ├── RouteControlState (gate open/closed)
  ├── ObjectiveProgressState (multi-step objectives)
  ├── PlayerVitalsModel (oxygen + health + stamina proxies)
  ├── PlayerProgressionState (class, skills)
  ├── ScannerState + TravelController
  ├── SargassoWorld + MarkerGenerator
  ├── SaveLoadService + RunSnapshot + WorldSnapshot
  ├── DockingManager + DockPorts + ShipOccupancy
  ├── ShipInstance (per-ship: blueprint + systems + access + hangar + inventory + carts)
  └── UI: ObjectiveTracker, ScannerPanel, InventoryPanel, PlayerVitalsPanel, AccessibilitySettings
```

### 1.4 Procgen Pipeline
```
MarkerGenerator (infinite cell-hash field)
  → ShipGenerator (per-marker: archetype + template + layout)
    → ShipBlueprint (seed → size, archetype, template)
      → TemplateSelector (spine|bifurcated|stacked from seed)
      → TopologyTemplate (zones + connections from JSON)
      → RoomGraphGenerator (zones → rooms + adjacency)
      → RoomAssigner (roles to zones)
      → CellLayoutEngine (zones → grid positions, 4m cells, 4m decks)
      → StructuralPlacer (instantiate module .tscn from kit)
      → GeneratedShipLoader (build full scene tree from layout JSON)
```

---

### SYSTEM STATUS MATRIX

Legend:
  ✅ BUILT     — Implemented and validated (model + smoke + regression)
  ⚠️ PARTIAL   — Core exists, significant pieces missing
  📋 SPEC'D    — Spec/ADR exists, not yet implemented
  ❌ MISSING   — Not started, not spec'd, required for commercial ship

### SYSTEM STATUS MATRIX

| System | Status | Built (evidence) | Remaining |
|--------|--------|-------------------|-----------|
| **SURVIVAL VITALS** | | | |
| Oxygen (per-room sim) | ✅ BUILT | oxygen_state.gd (16.5K), breach zones | Tuning pass |
| Health (proxy) | ⚠️ PARTIAL | player_vitals_model.gd | Full HP with damage types |
| Stamina (proxy) | ⚠️ PARTIAL | player_vitals_model.gd | Sprint cost, recovery, overexertion |
| Hunger | ❌ MISSING | — | Drain rate, starvation effects, food items |
| Thirst | ❌ MISSING | — | Drain rate, dehydration effects, water items |
| Body temperature | ❌ MISSING | — | Vacuum cooling, overheating, suit insulation |
| Radiation exposure | ❌ MISSING | — | Sources, accumulation, treatment |
| Sanity/Fear | ❌ MISSING | — | Horror mechanic, visual distortion, audio hallucinations |
| **FOOD & COOKING** | | | |
| Food item system | ❌ MISSING | — | Raw/cooked/preserved, spoilage, nutritional effects |
| Cooking station | ❌ MISSING | — | Ship upgrade, recipe execution |
| Recipe discovery | ❌ MISSING | — | Find/learn recipes, codex integration |
| Spoilage system | ❌ MISSING | — | Fresh→stale→rotten, preservation methods |
| Ship food synthesizer | ❌ MISSING | — | Basic food from power (life support upgrade) |
| Hydroponic garden | ❌ MISSING | — | Grow food over time, requires water/light |
| **CRAFTING** | | | |
| Crafting station framework | ❌ MISSING | — | Fabricator, workbench, medbay, kitchen |
| Recipe system | ❌ MISSING | — | Discovered vs known, materials, quality tiers |
| Material types | ❌ MISSING | — | Scrap, components, chemicals, biomatter, electronics |
| Quality tiers | ❌ MISSING | — | Crude→standard→refined→masterwork |
| Field crafting | ❌ MISSING | — | Limited recipes from suit inventory |
| Crafting UI | ❌ MISSING | — | Recipe browser, material preview, queue |
| Batch crafting | ❌ MISSING | — | Multiple items, time-based queue |
| **LOOT ECOSYSTEM** | | | |
| Container variety | ⚠️ PARTIAL | loot_container.gd exists | Crates, lockers, bodies, hidden caches, safes |
| Rarity tiers | ❌ MISSING | — | Common→uncommon→rare→epic→unique |
| Loot tables (biome/depth) | ⚠️ PARTIAL | loot_tables.json exists | Tier scaling, biome weights, condition classes |
| Loot distribution curve | ❌ MISSING | — | Frontloaded safe, endgame brutal, risk/reward |
| Junk items (crafting mats) | ❌ MISSING | — | Flavor items that double as materials |
| Loot feedback loop | ❌ MISSING | — | What makes looting feel rewarding vs tedious |
| **CONSUMABLES** | | | |
| Food items | ❌ MISSING | — | Restore hunger, some give buffs |
| Medicine | ❌ MISSING | — | Heal HP, cure status effects, painkillers |
| Stimulants | ❌ MISSING | — | Temporary stat boosts, addiction/withdrawal risk |
| Repair consumables | ❌ MISSING | — | Repair kits, welding fuel, spare parts |
| Ammo types | ❌ MISSING | — | Standard, incendiary, electric, etc. |
| Utility consumables | ❌ MISSING | — | Flares, lockpicks, hacking chips |
| Trade goods | ❌ MISSING | — | Valuable items for vendor/barter |
| **RESOURCE MANAGEMENT LOOP** | | | |
| Scavenge phase | ❌ MISSING | — | Explore derelicts, find containers, prioritize loot |
| Inventory triage | ⚠️ PARTIAL | InventoryState exists | Drop/mark/dismantle decisions |
| Return-to-hub cycle | ❌ MISSING | — | Deposit, craft, restock, heal |
| Run preparation | ❌ MISSING | — | Craft supplies, load out, plan route |
| Supply pressure curve | ❌ MISSING | — | Longer runs need more supplies, diminishing returns |
| **SUSTENANCE INFRASTRUCTURE (SHIP)** | | | |
| Water recycler | ❌ MISSING | — | Converts wastewater to clean water (life support) |
| Water purification | ❌ MISSING | — | Found water → clean water (crafting/medbay) |
| Medbay | ❌ MISSING | — | Craft medicine, heal injuries, cure status |
| Workshop | ❌ MISSING | — | Craft tools, repair equipment, upgrade gear |
| Storage expansion | ❌ MISSING | — | Refrigeration (perishables), cargo upgrades |
| Power→sustenance link | ❌ MISSING | — | Synthesizer/garden/recycler consume power |
| **CORE GAMEPLAY** | | | |
| Player movement (iso, WASD) | ✅ BUILT | player_controller.gd, A11Y-P1-002 | Polish: crouch, i-frames |
| Interaction (single verb) | ✅ BUILT | interactable.gd (Area3D) | Multiple verbs, context menu |
| Locked-isometric camera | ✅ BUILT | iso_camera_rig.gd, readability harness | Zoom levels, shake toggle |
| Fire hazard (timed cycle) | ✅ BUILT | fire_state.gd (8.3K), Gate 2 | Tuning pass |
| Electrical arc hazard | 📋 SPEC'D | ADR-0005, REQ-013, spec exists | Implement (Gate 4) |
| Route control (gates) | ✅ BUILT | route_control_state.gd (5.1K) | — |
| Objective system (sequence) | ✅ BUILT | objective_progress_state.gd (9K) | Graph-based (ADR-0006) |
| Save/Load (current-run) | ✅ BUILT | save_load_service.gd, RunSnapshot/WorldSnapshot | Multi-slot, auto-save, quicksave |
| Armor layers | ❌ MISSING | — | Suit integrity, damage resistances |
| Death/respawn | ❌ MISSING | — | Permadeath toggle, epitaph save |
| Damage types | ❌ MISSING | — | Physical/fire/acid/vacuum/electric/biomatter pipeline |
| Status effects | ❌ MISSING | — | Bleed/burn/slow/stun/frozen/infected/hallucinated |
| **SHIP SYSTEMS** | | | |
| Ship systems framework | ✅ BUILT | ship_systems_manager.gd (9.8K) | — |
| Ship system subcomponents | ✅ BUILT | ship_system.gd, ship_subcomponent.gd | — |
| Ship instances | ✅ BUILT | ship_instance.gd (229 lines) | — |
| Power grid (manual routing) | ❌ MISSING | — | Reactor wattage, routing UI, blackout cascade |
| Life support (O2/temp/water) | ⚠️ PARTIAL | OxygenState exists | CO2 scrubbers, temp, water, food |
| Hull integrity (breach zones) | ⚠️ PARTIAL | Oxygen breach zones exist | Compartmentalized damage, repair welds |
| Fire suppression | ⚠️ PARTIAL | FireState exists (clearing cycle) | Active suppression tools, spread model |
| Engines/propulsion | ⚠️ PARTIAL | ShipInstance.is_working_vessel() | Fuel, FTL drive, thrust model |
| Shields | ❌ MISSING | — | Bubble regen with delay |
| Sensors/scanners | ⚠️ PARTIAL | ScannerState, ScannerPanel | Long-range, motion tracker, power sig |
| Doors/airlocks (pressurization) | ⚠️ PARTIAL | DockPortBarrier exists | Pressure model, instant vacuum death |
| Gravity generator | ❌ MISSING | — | Failure = floaty physics (horror beat) |
| Medbay/clone bay | ❌ MISSING | — | Healing, respawn, status cure |
| Repair minigame | ⚠️ PARTIAL | RepairPoint interactable | Wire puzzles, tool degradation, calibration |
| **DOCKING & TRAVEL** | | | |
| Dock port system | ✅ BUILT | dock_ports.gd, docking_manager.gd | — |
| Dock port barriers | ✅ BUILT | dock_port_barrier.gd | — |
| Ship occupancy (AABB) | ✅ BUILT | ship_occupancy.gd | — |
| Hangar bay nesting | ✅ BUILT | hangar_bay.gd, ADR-0019 | — |
| Bridge terminal (claim/pilot) | ✅ BUILT | bridge_terminal.gd, ADR-0018 | — |
| Travel controller | ✅ BUILT | travel_controller.gd | Multi-derelict memory |
| Marker generator (infinite) | ✅ BUILT | marker_generator.gd | — |
| **INVENTORY & LOOT** | | | |
| Player inventory (weight-based) | ✅ BUILT | inventory_state.gd (198 lines) | Grid UI option |
| Equipment slots | ✅ BUILT | equipment_state.gd, 5 slots | Head/body slots |
| Item definitions | ✅ BUILT | item_definitions.json, equipment_definitions.json | Expand catalog |
| Tool system | ✅ BUILT | tool_definitions.json, tool_pickup.gd | More tools |
| Encumbrance (soft-cap) | ✅ BUILT | encumbrance.gd (piecewise) | — |
| Loot containers | ✅ BUILT | loot_container.gd, loot_tables.json | Expand tables |
| Ship cargo holds | ✅ BUILT | ship_inventory.gd (hard-cap 500) | — |
| Cargo transfer (conservation) | ✅ BUILT | cargo_transfer.gd | — |
| Equipment carts | ✅ BUILT | cart_state.gd, ADR-0021 | — |
| Inventory UI (drag-drop) | ✅ BUILT | inventory_panel.gd (552 lines), ADR-0022/0023 | — |
| Equip from container | ✅ BUILT | ADR-0026 | — |
| Per-container weight reduction | ✅ BUILT | ADR-0028 | — |
| Crafting | ❌ MISSING | — | Bench, field crafting, recipes, quality tiers |
| Vendor/trade | ❌ MISSING | — | Station vendors, faction rep gates |
| **PROCEDURAL GENERATION** | | | |
| Procgen pipeline (core) | ✅ BUILT | 10+ scripts, deterministic | — |
| Template A (spine) | ✅ BUILT | golden fixture, validated | — |
| Template B (bifurcated) | ✅ BUILT | layout_template_b.md, validated | — |
| Template C (stacked) | 📋 SPEC'D | layout_template_c.md | Implement ramp/elevator |
| Loot table system | ⚠️ PARTIAL | loot_tables.json, LootRoller | Tier scaling, biome weights |
| Difficulty scaling | ❌ MISSING | — | Run-level scaling, mutators |
| Module kit expansion | ⚠️ PARTIAL | 15 modules (ship_structural_v0) | More kits per room role |
| Room variant system | ❌ MISSING | — | ≥2 visual variants per prefab |
| **COMBAT / THREATS** | | | |
| Threat archetypes | ❌ MISSING | — | Swarms, puppets, stalkers, mimics, bosses |
| AI state machine | ❌ MISSING | — | Patrol/investigate/hunt/attack/flee/stun |
| Detection/stealth | ❌ MISSING | — | Vision cones, sound propagation, light level |
| Player weapons | ❌ MISSING | — | Melee, ranged, throwables, tool-as-weapon |
| Combat feedback | ❌ MISSING | — | Hitstop, recoil, ammo scarcity |
| Encounter design | ❌ MISSING | — | Set pieces, wave defense, stealth sections |
| **UI / HUD** | | | |
| Objective tracker (HUD) | ✅ BUILT | objective_tracker.gd (246 lines) | — |
| Scanner panel | ✅ BUILT | scanner_panel.gd (141 lines) | — |
| Inventory panel | ✅ BUILT | inventory_panel.gd (552 lines) | — |
| Player vitals panel | ✅ BUILT | player_vitals_panel.gd (5.6K) | Expand for new vitals |
| Accessibility settings | ✅ BUILT | accessibility_settings.gd (115 lines) | Expand |
| Main menu | ❌ MISSING | — | New/Continue/Load/Settings/Achievements/Quit |
| Pause menu | ❌ MISSING | — | Resume/Save/Load/Settings/Quit |
| Settings menu | ❌ MISSING | — | Audio/video/accessibility/controls |
| Minimap | ❌ MISSING | — | HUD corner, fog-of-war, markers |
| Map screen (sector) | ❌ MISSING | — | Interstellar node graph |
| Codex/lore viewer | ❌ MISSING | — | Unlocks on discovery |
| Ship status panel | ❌ MISSING | — | Per-system health overview |
| Tooltip system | ❌ MISSING | — | Hover, compare-tooltips |
| Tutorial popups | ❌ MISSING | — | Contextual first-encounter |
| Damage direction indicator | ❌ MISSING | — | — |
| Threat indicator | ❌ MISSING | — | Alien Isolation-style signature display |
| Crosshair (context-aware) | ❌ MISSING | — | — |
| Hotbar (6-8 slots) | ❌ MISSING | — | Ammo + cooldown display |
| **AUDIO** | | | |
| Audio system | ❌ MISSING | — | Bus layout, spatial, ambient, SFX, music |
| Dynamic music | ❌ MISSING | — | Layered tracks, tension/combat/stealth |
| Audio occlusion | ❌ MISSING | — | Raycast-based line-of-sight |
| Voice/dialog | ❌ MISSING | — | Barks, audio logs, TTS fallback |
| **SAVE/LOAD (expanded)** | | | |
| Current-run save/load | ✅ BUILT | SaveLoadService, F5/F9 | — |
| Multi-slot saves | ❌ MISSING | — | 6-10 slots |
| Auto-save | ⚠️ PARTIAL | REQ-012 spec'd | Safe room + interval auto-save |
| Quicksave/quickload | ⚠️ PARTIAL | F5/F9 exist | Confirm dialog, visual feedback |
| Steam Cloud sync | ❌ MISSING | — | GodotSteam RemoteStorage |
| **PROGRESSION** | | | |
| Current-run progression | ✅ BUILT | PlayerProgressionState, classes, skills | — |
| Meta-progression (cross-run) | ❌ MISSING | — | Currency, hub upgrades, unlockables |
| Hub ship scene | ❌ MISSING | — | ADR-0002/0003 defer; Gate 3 entry |
| Derelict selection | ❌ MISSING | — | Scanner → select → travel |
| Skill tree (per-run) | ❌ MISSING | — | — |
| Achievements | ❌ MISSING | — | 25-50 via GodotSteam |
| **ACCESSIBILITY** | | | |
| Text scale (1.0-2.0) | ✅ BUILT | AccessibilitySettings, A11Y-P1-002 | — |
| Input remapping | ⚠️ PARTIAL | Dynamic input map registered at runtime | Full remap UI |
| Colorblind modes | ❌ MISSING | — | Protan/Deutan/Tritan shader on HUD |
| Subtitle options | ❌ MISSING | — | Size, bg opacity, speaker labels, SFX captions |
| Controller support | ❌ MISSING | — | Full gamepad mapping, glyphs, vibration |
| Difficulty presets | ❌ MISSING | — | Story/Normal/Hard/Survival/Custom |
| Camera shake toggle | ❌ MISSING | — | Vestibular accessibility |
| **PERFORMANCE** | | | |
| LOD system | ❌ MISSING | — | ≥3 levels per mesh |
| Occlusion culling | ❌ MISSING | — | OccluderInstance3D per room |
| Object pooling | ❌ MISSING | — | Bullets, particles, loot, bodies |
| Shader pipeline bake | ❌ MISSING | — | Ubershader + precompile (4.4+) |
| Texture compression | ⚠️ PARTIAL | ETC2/ASTC enabled | Per-platform pass |
| MultiMesh optimization | ❌ MISSING | — | Repeated instances |
| **POLISH** | | | |
| Screen transitions | ❌ MISSING | — | Fade, loading tips, iris, title cards |
| Hit feedback (juice) | ❌ MISSING | — | Shake, hitstop, particles, slow-mo |
| Damage feedback | ❌ MISSING | — | Red vignette, audio thump |
| Surface footstep particles | ❌ MISSING | — | Metal, blood, biomatter |
| Repair feedback | ❌ MISSING | — | Sparks, weld glow, tool shake |
| Pickup feedback | ❌ MISSING | — | UI ping, item tween |
| **DISTRIBUTION** | | | |
| Export pipeline (4 platforms) | ✅ BUILT | build_release.sh (156 lines) | — |
| itch.io packaging | ⚠️ PARTIAL | Export exists | Store page, capsule art, screenshots |
| Steam integration | ❌ MISSING | — | GodotSteam, store page, achievements |
| Steam Deck verification | ❌ MISSING | — | Test on hardware |
| Controller glyphs | ❌ MISSING | — | Xbox/PS/Steam Input auto-switch |
| Localization | ❌ MISSING | — | English + 1-2 others |
| Crash reporting | ❌ MISSING | — | Telemetry, stack traces |
| Demo build | ❌ MISSING | — | Separate App ID recommended |

---

## PART 3: DEPENDENCY MAP

### 3.1 Foundational Dependencies (build order)

```
TIER 0 — NO DEPENDENCIES (can build now)
  ├── Main menu / pause menu / settings menu
  ├── Audio bus layout
  ├── Multi-slot save system (extends existing SaveLoadService)
  ├── LOD / occlusion culling pass
  ├── Object pooling framework
  ├── Screen transitions
  ├── Input remap UI
  ├── Material types definition (scrap, components, chemicals, biomatter, electronics)
  ├── Rarity tier framework (common→uncommon→rare→epic→unique)
  ├── Food item definitions (raw/cooked/preserved, hunger restore, buffs)
  └── Consumable definitions (medicine, stimulants, repair kits, ammo, utility)

TIER 1 — DEPENDS ON EXISTING SYSTEMS
  ├── Damage pipeline → extends ShipSystemsManager, player_vitals_model
  ├── Status effects → extends damage pipeline
  ├── Armor layers → extends equipment_state
  ├── Death/respawn → extends damage pipeline + save/load
  ├── Hotbar UI → extends inventory_state + equipment_state
  ├── Crosshair → extends interaction system
  ├── Minimap → extends procgen layout data
  ├── Tooltip system → extends item_defs
  ├── Difficulty presets → extends vitals, oxygen, encumbrance
  ├── Colorblind modes → extends accessibility_settings
  ├── Tutorial popups → extends interaction system
  ├── Hunger/thirst mechanics → extends player_vitals_model
  ├── Body temperature → extends player_vitals_model
  ├── Radiation exposure → extends player_vitals_model, damage pipeline
  ├── Sanity/fear system → extends player_vitals_model, audio system
  ├── Spoilage system → extends food items, inventory
  ├── Recipe system → extends material types, crafting stations
  ├── Loot rarity tiers → extends item_defs, loot tables
  └── Consumable use system → extends inventory, vitals, status effects

TIER 2 — DEPENDS ON TIER 1
  ├── Combat AI (threat archetypes) → needs damage pipeline, detection
  ├── Player weapons → needs damage pipeline, inventory
  ├── Encounter design → needs combat AI, procgen
  ├── Dynamic music → needs combat AI state hooks
  ├── Audio occlusion → needs spatial audio foundation
  ├── Juice pass → needs combat AI, damage pipeline
  ├── Hotbar/cooldown UI → needs weapons, tools
  ├── Crafting stations (fabricator, workbench, medbay, kitchen) → needs recipes, materials
  ├── Field crafting → needs recipe system, inventory
  ├── Cooking → needs food items, cooking station, spoilage
  ├── Loot table expansion → needs rarity tiers, biome/depth scaling
  ├── Container variety → needs loot tables, procgen
  ├── Supply pressure curve → needs hunger/thirst, consumables, loot
  ├── Sustenance infrastructure (synthesizer, garden, recycler, medbay, workshop) → needs crafting, recipes
  └── Resource management loop → needs all survival systems

TIER 3 — DEPENDS ON TIER 2
  ├── Meta-progression (hub ship) → needs combat, exploration, survival loop
  ├── Derelict selection → needs hub scene, scanner expansion
  ├── Crafting depth (quality tiers, batch, modular) → needs crafting stations
  ├── Achievements → needs all systems to hook
  ├── Steam integration → needs achievements, cloud saves
  └── Controller support → needs all UI finalized

TIER 4 — DEPENDS ON TIER 3
  ├── Content expansion (templates C+, module kits)
  ├── Loot table balancing (tier scaling, biome weights)
  ├── Difficulty tuning (all presets)
  ├── Localization
  ├── Performance profiling pass
  ├── Demo build
  └── Store page assets
```

### 3.2 Critical Path

```
Damage Pipeline → Combat AI → Weapons → Encounter Design → Meta-Progression → Content → Ship
      ↓               ↓           ↓            ↓                 ↓
Status Effects   Detection   Hotbar UI    Dynamic Music    Achievements
Armor Layers     Stealth     Juice Pass   Audio Occlusion  Steam Integration
Death/Respawn                                                     Controller

Hunger/Thirst → Crafting Stations → Recipe System → Resource Loop → Sustenance → Meta-Progression
      ↓               ↓                  ↓              ↓              ↓
Food Items      Material Types     Quality Tiers    Loot Tables    Ship Upgrades
Spoilage        Field Crafting     Crafting UI      Supply Curve   Storage
Consumables     Medicine/Stims     Batch Crafting   Container Var  Power Link
```

### 3.3 Parallel Workstreams (no cross-dependency until Tier 3)

**Stream A — Systems:**
  Damage pipeline → Status effects → Armor → Death → Combat AI → Weapons

**Stream B — UI/UX:**
  Main menu → Pause menu → Settings → Minimap → Map → Hotbar → Tooltips → Tutorial

**Stream C — Audio:**
  Bus layout → Spatial audio → SFX → Dynamic music → Voice

**Stream D — Polish:**
  Transitions → Juice → Feedback → Particles → Accessibility expansion

**Stream E — Infrastructure:**
  Multi-slot saves → LOD/occlusion → Pooling → Shader bake → Performance

**Stream F — Survival:**
  Vitals expansion (hunger/thirst/temp/radiation/sanity) → Food items → Crafting framework
  → Recipe system → Consumables → Loot ecosystem → Sustenance infrastructure
  → Resource management loop → Supply pressure tuning

---

## PART 4: COMPLETE REMAINING WORK (MID-LEVEL)

### 4.X — SURVIVAL SYSTEMS (NEW SECTION)

#### 4.X.1 — Survival Vitals

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| SV-01 | Hunger mechanic (drain rate, starvation effects) | PlayerVitalsModel | M | Reduced stamina, blurred vision at low |
| SV-02 | Thirst mechanic (drain rate, dehydration effects) | PlayerVitalsModel | M | Faster stamina drain, slower movement |
| SV-03 | Body temperature (ambient + vacuum + fire proximity) | PlayerVitalsModel | M | Suit insulation, hypothermia/hyperthermia |
| SV-04 | Radiation exposure (sources, accumulation, treatment) | PlayerVitalsModel, D-01 | M | Rad zones, contaminated items, meds |
| SV-05 | Sanity/fear system (horror mechanic) | PlayerVitalsModel, A-03 | L | Visual distortion, audio hallucinations, hostile UI |
| SV-06 | Stamina rework (sprint cost, recovery, overexertion) | PlayerVitalsModel | S | Currently proxy only |
| SV-07 | Vitals HUD expansion (hunger/thirst/temp/rad/sanity) | SV-01-SV-06, PlayerVitalsPanel | M | New bars/icons, color transitions |
| SV-08 | Vitals interaction (hunger affects stamina, thirst affects vision, etc.) | SV-01-SV-06 | M | Cascading effects, death spiral prevention |

#### 4.X.2 — Food & Cooking

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| FC-01 | Food item definitions (raw, cooked, preserved) | SV-01, ItemDefs | M | Hunger restore values, buff/debuff effects |
| FC-02 | Food item catalog (ration packs, alien flora, synthetic, scavenged) | FC-01 | M | 15-25 food items across rarity tiers |
| FC-03 | Spoilage system (fresh→stale→rotten, timers) | FC-01 | M | Preservation methods (smoking, salting, vacuum-seal) |
| FC-04 | Cooking station (ship upgrade, recipe execution) | FC-01, Recipe system | L | Requires power, unlocks cooked recipes |
| FC-05 | Recipe discovery (find recipes in derelicts, codex) | FC-04 | M | Codex integration, recipe items |
| FC-06 | Cooking UI (recipe browser, ingredient preview) | FC-04, Crafting UI | M | — |
| FC-07 | Ship food synthesizer (basic food from power) | FC-01, P-01 | M | Life support upgrade, low-quality food |
| FC-08 | Hydroponic garden (grow food, requires water/light) | FC-01, P-01 | L | Time-based growth, seed discovery |
| FC-09 | Food buffs/debuffs (temporary stat effects from food) | FC-01, SV-08 | M | Spice tolerance, alien food side effects |
| FC-10 | Scavenged food placement (procgen food in derelicts) | FC-02, G-06 | S | Per-room role, condition class |

#### 4.X.3 — Crafting System

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| CS-01 | Material type definitions (scrap, components, chemicals, biomatter, electronics) | ItemDefs | M | 5 base types, 3-5 subtypes each |
| CS-02 | Material catalog (30-50 materials with sources) | CS-01 | M | Scavenged, deconstructed, refined |
| CS-03 | Crafting station framework (base class for all stations) | CS-01 | M | Power-gated, upgrade levels |
| CS-04 | Fabricator station (general crafting, tools, equipment) | CS-03 | L | Ship upgrade, core crafting hub |
| CS-05 | Workbench station (field repairs, modifications) | CS-03 | M | Tool repair, equipment mods |
| CS-06 | Medbay station (medicine, healing, status cure) | CS-03 | M | Ship upgrade, medical recipes |
| CS-07 | Kitchen station (cooking, food processing) | CS-03, FC-04 | M | Ship upgrade, food recipes |
| CS-08 | Recipe system (recipe definitions, known vs discovered) | CS-01, ItemDefs | M | Recipe as Resource, codex integration |
| CS-09 | Recipe catalog (40-60 recipes across stations) | CS-08 | M | Tiered by station level |
| CS-10 | Quality tier system (crude→standard→refined→masterwork) | CS-08 | M | Affects stats, requires better materials/station |
| CS-11 | Field crafting (limited recipes from suit inventory) | CS-08 | S | Emergency repairs, basic medicine |
| CS-12 | Batch crafting (multiple items, time-based queue) | CS-03 | S | Queue management, cancel/pause |
| CS-13 | Crafting UI (recipe browser, material preview, queue) | CS-08 | L | Filter by station, search, favorites |
| CS-14 | Deconstruction (break items into materials) | CS-01 | S | Salvage yield, tool requirement |
| CS-15 | Crafting balance pass (material costs, craft times, yields) | CS-09 | M | — |

#### 4.X.4 — Loot Ecosystem

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| LE-01 | Rarity tier framework (common→uncommon→rare→epic→unique) | ItemDefs | S | Color coding, drop rate weights |
| LE-02 | Loot table expansion (per biome, depth, condition class) | LE-01, loot_tables.json | L | 6-8 biome tables, depth scaling |
| LE-03 | Container variety expansion (crates, lockers, bodies, caches, safes, hidden) | loot_container.gd | M | Different loot pools, lock difficulty |
| LE-04 | Loot distribution curve (frontloaded safe, endgame brutal) | LE-02 | M | Risk/reward ratio targets |
| LE-05 | Junk items (crafting materials disguised as flavor items) | CS-02 | M | 20-30 junk items, scrap value |
| LE-06 | Loot feedback loop (what makes looting rewarding) | LE-01, J-02 | M | Visual/audio feedback on rarity, weight feel |
| LE-07 | Loot placement in procgen (per room role, condition) | LE-02, G-06 | M | Crew quarters get food, engineering gets parts |
| LE-08 | Unique/legendary items (one-of-a-kind, lore-attached) | LE-01 | M | 5-10 unique items with backstory |
| LE-09 | Loot table balance pass (drop rates, scarcity, player feedback) | LE-02 | M | — |

#### 4.X.5 — Consumables

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| CN-01 | Consumable base class (use effect, duration, stack behavior) | ItemDefs, InventoryState | M | — |
| CN-02 | Food consumables (restore hunger, some buffs) | CN-01, FC-01 | S | Overlap with food items |
| CN-03 | Medicine consumables (heal HP, cure status, painkillers) | CN-01, D-01, D-02 | M | Bandages, antirad, antibiotics, painkillers |
| CN-04 | Stimulant consumables (temp stat boosts, addiction risk) | CN-01, SV-08 | M | Speed boost, damage resist, focus, addiction |
| CN-05 | Repair consumables (repair kits, welding fuel, spare parts) | CN-01, RepairPoint | M | Field repair items |
| CN-06 | Ammo consumables (standard, incendiary, electric, explosive) | CN-01, D-11 | M | Ammo types with damage modifiers |
| CN-07 | Utility consumables (flares, lockpicks, hacking chips, decoys) | CN-01 | M | Tactical items |
| CN-08 | Trade goods (valuable items for vendor/barter) | CN-01 | S | Currency replacement or supplement |
| CN-09 | Consumable use animation/effect (hand animation, screen effect) | CN-01, J-02 | S | Juice for using items |
| CN-10 | Consumable catalog (50-80 total across all categories) | CN-02-CN-08 | M | Balanced distribution |

#### 4.X.6 — Resource Management Loop

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| RM-01 | Scavenge phase design (explore→find→prioritize→decide) | LE-02, CN-01 | M | Player-facing loop |
| RM-02 | Inventory triage system (drop/mark/dismantle decisions) | InventoryState | M | Quick-drop, mark for pickup, dismantle in field |
| RM-03 | Return-to-hub cycle (deposit, craft, restock, heal) | CS-03, P-01 | M | Hub visit flow |
| RM-04 | Run preparation (craft supplies, load out, plan route) | RM-03, CS-08 | M | Pre-run checklist |
| RM-05 | Supply pressure curve (longer runs need more supplies) | SV-01-SV-02, CN-01 | L | Diminishing returns, oxygen/food/water pressure |
| RM-06 | Resource scarcity tuning (material drop rates, craft yields) | RM-05, CS-15 | M | Balance pass |
| RM-07 | Emergency resource events (find cache, trade with NPC, gamble) | RM-05 | S | Break glass moments |
| RM-08 | Resource management tutorial (first 5 min teaches scavenge→craft→sustain) | RM-01, U-13 | M | — |

#### 4.X.7 — Sustenance Infrastructure (Ship Systems)

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| SI-01 | Water recycler (converts wastewater to clean water) | SV-02, P-01 | M | Life support upgrade, power cost |
| SI-02 | Water purification (found water → clean water) | SI-01, CS-03 | S | Crafting recipe |
| SI-03 | Medbay (craft medicine, heal injuries, cure status) | CS-06, P-01 | L | Ship upgrade, medical hub |
| SI-04 | Workshop (craft tools, repair equipment, upgrade gear) | CS-04, CS-05, P-01 | L | Ship upgrade, crafting hub |
| SI-05 | Storage expansion (refrigeration for perishables, cargo upgrades) | P-01 | M | Ship upgrade |
| SI-06 | Power→sustenance link (synthesizer/garden/recycler consume power) | SI-01-SI-05 | M | Resource tradeoff |
| SI-07 | Sustenance upgrade tree (each station has 2-3 upgrade levels) | SI-01-SI-06 | L | Unlock better recipes, faster production |
| SI-08 | Sustenance status panel (overview of all ship sustenance systems) | SI-01-SI-06, U-11 | S | HUD integration |

### 4.1 — DAMAGE & COMBAT SYSTEM (CRITICAL PATH)

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| D-01 | Damage pipeline (types: physical/fire/acid/vacuum/electric/biomatter) | None | M | `damage_event` → hitbox → armor → vitals |
| D-02 | Status effects framework (tagged list + tick handler) | D-01 | M | Bleed/burn/slow/stun/frozen/infected/hallucinated |
| D-03 | Armor system (suit integrity + damage-type resistances) | D-01 | S | Extends EquipmentState |
| D-04 | Death/respawn system | D-01 | M | Permadeath toggle, epitaph save, death UI |
| D-05 | Threat archetype: Biomatter swarms (small/many/fast) | D-01 | M | First enemy type |
| D-06 | Threat archetype: Puppeteered corpses (humanoid/melee) | D-05 | M | Second enemy type |
| D-07 | Threat archetype: Stalkers (invisible, sound-hunt) | D-06 | L | Stealth predator |
| D-08 | AI state machine (idle→investigate→hunt→attack→flee→stun) | D-05 | L | Shared across archetypes |
| D-09 | Detection system (vision cones, sound radius, light level) | D-08 | M | Feeds AI state machine |
| D-10 | Stealth mechanics (crouch detection radius, light interaction) | D-09 | M | Player-side stealth |
| D-11 | Player weapon: melee (crowbar/blade) | D-01 | S | Inventory-integrated |
| D-12 | Player weapon: ranged hitscan (pistol/rifle) | D-11 | M | Ammo system |
| D-13 | Player weapon: throwables (grenade/flare/decoy) | D-11 | S | — |
| D-14 | Player weapon: tool-as-weapon (welder burns, scanner stun) | D-11 | S | Cross-system |
| D-15 | Combat feedback (hitstop, recoil, slow-mo) | D-11 | S | Juice pass |
| D-16 | Encounter design: set pieces | D-08,D-11 | L | Hand-authored horror beats |
| D-17 | Encounter design: wave defense during repair | D-16 | M | Tension escalation |
| D-18 | Encounter design: boss fights | D-16 | L | Attack phases, weakpoints |

### 4.2 — UI/UX SYSTEMS

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| U-01 | Main menu (New/Continue/Load/Settings/Quit) | SaveLoad | M | — |
| U-02 | Pause menu (Resume/Save/Load/Settings/Quit) | U-01 | S | — |
| U-03 | Settings menu (Audio/Video/Accessibility/Controls) | U-01 | M | All settings wired |
| U-04 | Hotbar (6-8 slots + ammo + cooldown) | InventoryState | M | — |
| U-05 | Context-aware crosshair | Interactable | S | — |
| U-06 | Threat indicator (signature display) | D-08 | M | Horror tension mechanic |
| U-07 | Damage direction indicator | D-01 | S | — |
| U-08 | Minimap (HUD corner, fog-of-war) | Procgen layout | M | — |
| U-09 | Map screen (sector node graph) | TravelController | M | — |
| U-10 | Codex/lore viewer | ItemDefs | M | Unlocks on discovery |
| U-11 | Ship status panel | ShipSystemsManager | S | Per-system health |
| U-12 | Tooltip system (hover, compare) | ItemDefs | M | — |
| U-13 | Tutorial popups (contextual first-encounter) | Interaction | M | Skip option |
| U-14 | Controller glyph auto-switch | Input system | M | Xbox/PS/Steam Input |
| U-15 | Input remap UI (full) | Input system | M | Both kbm + gamepad |
| U-16 | Loading screen (tips rotation) | Scene transitions | S | — |

### 4.3 — AUDIO SYSTEM

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| A-01 | Audio bus layout (Master→Music/SFX/Voice/UI/Ambient→sub) | None | S | Foundation |
| A-02 | Spatial audio framework (AudioStreamPlayer3D + attenuation) | A-01 | M | — |
| A-03 | Ambient system (per-biome: creaks, hums, breathing) | A-02 | M | Area3D zones |
| A-04 | SFX framework (varied footsteps, interactions, UI) | A-01 | M | Pitch/volume randomization |
| A-05 | Dynamic music (layered: base+tension+combat+boss) | A-01,D-08 | L | Crossfade triggers |
| A-06 | Audio occlusion (raycast line-of-sight) | A-02 | M | Room vs corridor |
| A-07 | Voice system (barks, audio logs, TTS fallback) | A-01 | M | — |
| A-08 | Stingers (first encounter, death, victory) | A-05 | S | — |

### 4.4 — PROGRESSION & META

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| P-01 | Hub ship scene (player's persistent base) | Gate 3 decision | L | ADR-0002/0003 defer |
| P-02 | Derelict selection (scanner → select → travel) | P-01 | M | ScannerPanel expansion |
| P-03 | Meta-currency (cores/salvage persistence) | P-01 | M | Cross-run state |
| P-04 | Hub ship upgrades (engines, storage, defenses) | P-01,P-03 | L | Unlock tree |
| P-05 | Unlockable starting gear | P-03 | S | — |
| P-06 | Codex unlocks (weaknesses, recipes, lore) | P-01 | M | — |
| P-07 | Per-run skill tree | PlayerProgression | M | — |
| P-08 | Per-weapon mastery XP | D-11 | S | — |
| P-09 | NG+ / difficulty modifiers | D-01,U-03 | M | — |
| P-10 | Cosmetics (suits, decals, ship paint) | P-03 | S | — |

### 4.5 — INVENTORY & CRAFTING EXPANSION

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| I-01 | Expand item catalog (consumables, materials, quest items) | ItemDefs | M | — |
| I-02 | Equipment slots: head + body | EquipmentState | S | — |
| I-03 | Crafting: bench-based (hub fabricator) | P-01,I-01 | L | — |
| I-04 | Crafting: field crafting (limited suit recipes) | I-03 | M | — |
| I-05 | Crafting: discovered recipes | I-03 | M | — |
| I-06 | Modular weapon/suit attachments | I-03 | L | Slot system |
| I-07 | Vendor/trade system | P-01 | M | Rotating stock |
| I-08 | Loot table tier scaling | D-01 | M | Common→Unique, biome weights |
| I-09 | ADR-0004 (Item/Tool Data Model generalization) | I-01 | S | Currently per-tool branches |

### 4.6 — PROCEDURAL GENERATION EXPANSION

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| G-01 | Layout template C (stacked, ramp/elevator) | Existing pipeline | L | Spec exists |
| G-02 | Additional layout templates (D, E, F) | G-01 | M each | Variety |
| G-03 | Module kit expansion (per room role) | Existing pipeline | L | More than 15 modules |
| G-04 | Room variant system (≥2 per prefab) | G-03 | M | Visual variety |
| G-05 | Difficulty scaling (run-level mutators) | D-01 | M | 1-3 per derelict |
| G-06 | Hazard placement per seed | Existing pipeline | M | — |
| G-07 | Loot tier scaling per depth | I-08 | M | — |
| G-08 | Loop-back corridors (reduce linearity) | Room graph gen | S | — |
| G-09 | Multi-derelict memory (cross-ship state) | P-01 | L | ADR-0012 defers |

### 4.7 — SAVE/LOAD EXPANSION

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| S-01 | Multi-slot saves (6-10 slots) | Existing SaveLoad | M | — |
| S-02 | Auto-save (safe rooms + interval) | S-01 | S | — |
| S-03 | Quick-save/load confirm dialog | S-01 | S | — |
| S-04 | Steam Cloud sync | S-01, Steam SDK | M | GodotSteam RemoteStorage |
| S-05 | Save slot UI | S-01 | M | Visual preview |

### 4.8 — ACCESSIBILITY

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| X-01 | Colorblind modes (Protan/Deutan/Tritan) | AccessibilitySettings | M | HUD shader only |
| X-02 | Subtitle options (size, bg, speaker, SFX captions) | A-07 | M | — |
| X-03 | Controller support (full gamepad) | U-15 | L | Steam Deck verified |
| X-04 | Difficulty presets (Story/Normal/Hard/Survival/Custom) | D-01,U-03 | M | — |
| X-05 | Camera shake toggle | IsoCameraRig | S | Vestibular |
| X-06 | FOV slider | IsoCameraRig | S | — |
| X-07 | Invincibility mode (accessibility) | D-01 | S | Not a cheat |
| X-08 | High-contrast mode | AccessibilitySettings | M | — |
| X-09 | Dyslexia-friendly font option | AccessibilitySettings | S | — |
| X-10 | One-handed control schemes | U-15 | S | — |

### 4.9 — PERFORMANCE

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| F-01 | LOD system (≥3 levels per mesh) | None | M | — |
| F-02 | Occlusion culling (OccluderInstance3D per room) | None | M | Bake per-room |
| F-03 | Object pooling (bullets, particles, loot, bodies) | D-11 | M | — |
| F-04 | Shader pipeline bake (Ubershader + precompile) | None | S | Forward+/Mobile |
| F-05 | MultiMesh for repeated instances | None | S | — |
| F-06 | Shadow LOD (disable casters beyond N meters) | F-01 | S | — |
| F-07 | Texture compression per-platform | None | S | S3TC/BPTC/ETC2 |
| F-08 | Profiling pass (frame budget 60fps@1080p) | All systems | M | Final pass |

### 4.10 — POLISH & JUICE

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| J-01 | Screen transitions (fade, iris, title cards) | None | S | — |
| J-02 | Hit feedback (shake, hitstop, particles, slow-mo) | D-01 | M | — |
| J-03 | Damage feedback (red vignette, audio thump) | D-01 | S | — |
| J-04 | Footstep particles (surface-specific) | A-04 | S | Metal/blood/biomatter |
| J-05 | Repair feedback (sparks, weld glow, tool shake) | RepairPoint | S | — |
| J-06 | Pickup feedback (UI ping, item tween) | InventoryState | S | — |
| J-07 | Muzzle flash + recoil | D-11 | S | Every shot |
| J-08 | Surface-specific SFX layering | A-04 | S | 2-3 stacked |

### 4.11 — DISTRIBUTION & SHIP

| ID | Work Item | Depends On | Effort | Notes |
|----|-----------|------------|--------|-------|
| R-01 | itch.io store page (capsule, screenshots, description) | All systems | S | — |
| R-02 | GodotSteam integration (achievements, cloud, rich presence) | S-04 | M | — |
| R-03 | Steam store page (capsule, 5+ screenshots, trailer) | All systems | M | — |
| R-04 | Achievement list design (25-50) | All systems | S | — |
| R-05 | Achievement implementation (hooks) | R-02 | M | — |
| R-06 | Steam Deck verification | X-03 | M | Hardware testing |
| R-07 | Mac export testing | None | S | Code signing |
| R-08 | Localization (English + 1-2 others) | All UI | L | — |
| R-09 | Crash reporting / telemetry | None | M | — |
| R-10 | Demo build (separate App ID) | All systems | M | — |
| R-11 | Trailer production | All systems | M | — |
| R-12 | Age rating (IARC) | None | S | — |

---

## PART 5: GAP ANALYSIS SUMMARY

### What's DONE (solid foundation):
- Core loop (spawn→orient→traverse→restore→extract) ✅
- Ship systems framework (power, propulsion, life support, navigation, scanners) ✅
- 3 hazard types (oxygen, fire, electrical arc spec'd) ✅
- Inventory + equipment + encumbrance + containers + carts + cargo holds ✅
- Procgen pipeline (3 templates, deterministic, modular kits) ✅
- Docking (port-to-port, hangar nesting, barriers, claim/pilot) ✅
- Save/load (current-run, snapshot round-trip) ✅
- Interaction system (single verb, Area3D) ✅
- HUD (objectives, scanner, inventory, vitals) ✅
- Validation framework (~110 smokes, 120-command regression bundle) ✅
- Export pipeline (4 platforms) ✅
- Accessibility (text scale, dynamic input registration) ✅

### What's MISSING (critical for commercial ship):
1. **COMBAT** — No enemies, no AI, no weapons, no damage types. This is the largest single gap.
2. **AUDIO** — Zero audio infrastructure. No buses, no spatial, no music, no SFX.
3. **MENUS** — No main menu, pause menu, or settings. Game boots directly into play.
4. **PROGRESSION** — No meta-progression, no hub ship, no cross-run persistence (intentionally deferred).
5. **POLISH** — No juice (hitstop, shake, particles, feedback). No transitions.
6. **DISTRIBUTION** — No Steam integration, no achievements, no controller support.

### What's MISSING — Survival Layer (NEW):
The entire survival management layer is absent. For a "space-horror survival sim," this is as critical as combat:
- **No hunger/thirst/temperature/radiation/sanity vitals** — only O2/HP/stamina proxies exist
- **No food system** — no food items, no cooking, no spoilage, no nutritional effects
- **No crafting** — no stations, no recipes, no materials, no quality tiers, no field crafting
- **No consumable ecosystem** — no medicine, stimulants, repair kits, ammo types, utility items
- **No loot depth** — no rarity tiers, no biome/depth scaling, no junk items, no unique legendaries
- **No resource management loop** — no scavenge→sustain→craft→push-further cycle
- **No sustenance infrastructure** — no synthesizer, garden, recycler, medbay, workshop upgrades

**Survival is a parallel workstream of equal weight to combat, not a subset of inventory.**

### What's PARTIAL (needs expansion):
- Player vitals (only O2/HP/stamina — needs hunger/radiation/sanity)
- Scanner (basic — needs long-range, motion tracker)
- Audio (exists as concepts only — no implementation)
- Loot tables (basic — needs tier scaling, biome weights)
- Procgen (3 templates — needs more variety)
- Input (dynamic registration — needs remap UI)
- Save/load (single slot — needs multi-slot, auto-save, Steam Cloud)

### Estimated Remaining Effort (excluding assets):
- **Critical path (damage→combat→weapons→encounters→meta→ship):** ~18-24 weeks
- **Survival systems (vitals→food→crafting→loot→consumables→sustenance):** ~16-22 weeks
- **Parallel streams (UI/Audio/Polish/Infra):** ~12-16 weeks overlap
- **Content expansion (templates, kits, loot, balance):** ~8-12 weeks
- **Distribution (Steam, achievements, controller, localization):** ~6-8 weeks
- **Total estimated:** ~32-42 weeks of focused development

Note: Survival and combat share a critical-path fork at Tier 1 (damage pipeline, status effects)
but are otherwise parallel workstreams. They converge at Tier 3 (meta-progression, content balance).

---

## PART 6: DOCUMENT CROSS-REFERENCES

### Architecture Sources
- `docs/superpowers/specs/architecture-map.md` — Full codebase architecture (958 lines)
- `docs/PLANNING_SYNTHESIS.md` — Planning document synthesis (437 lines)
- `SYNAPTIC_SEA_SYSTEMS_INVENTORY.md` — Commercial game systems inventory (web research)

### ADR Status
- 26 of 28 ADRs reviewed (0004 and 0006 missing on disk)
- ADR-0004: "Inventory/Tool Data Model" — to be authored when generalization needed
- ADR-0006: "Objective Graph Architecture" — to be authored for Gate 3 objective expansion

### Key Design Decisions Still Pending
1. Gate 3 entry decision (hub/meta scope)
2. Combat depth (how many enemy archetypes at ship?)
3. Hub ship complexity (simple menu vs explorable base?)
4. Multiplayer scope (deferred indefinitely or planned?)
5. Target price point (affects scope of content)
6. Early access vs full release

---

*End of complete systems map. Total: ~120 work items across 11 categories, with dependency ordering and effort estimates. The critical path runs through combat/damage systems — that's where the largest gap is.*