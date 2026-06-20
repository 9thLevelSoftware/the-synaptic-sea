# The Sargasso of Stars — Core Systems Design

Date: 2026-06-20
Status: Approved for implementation
Architecture: System-first (each system built in isolation with clean interfaces)

---

## Vision Summary

Sandbox survival in a biomatter web that traps ships. Players start on a broken life raft with randomized system states, repair what they can, then explore an infinite Sargasso of procedurally generated derelicts. Progression comes from finding and claiming better ships, each with more complex systems, better equipment, and more space. Large ships can dock smaller ships in hangars, preserving player investment.

**Core loop:** Repair → Travel → Explore → Loot → Repair → Repeat

**Win condition:** None (sandbox). Optional ultra-rare jump drive escape condition for future implementation.

---

## System Architecture

```
SYSTEM 1: Ship Generation Framework
  ShipBlueprint → RoomGraphGenerator → StructuralPlacer → GameplayPlacer → ShipInstance

SYSTEM 2: Ship Systems (6 core systems)
  Power → Life Support, Gravity, Propulsion, Navigation, Scanners
  Each with subcomponents, dependencies, repair mechanics

SYSTEM 3: Player Progression (Class + Skills)
  ClassDefinition → starting skills + XP multipliers
  SkillTree → learnable abilities, cross-training

SYSTEM 4: Scanner & Travel
  ScannerSystem → range + detail levels
  TravelSystem → menu-based travel, docking triggers generation

SYSTEM 5: Ship Docking & Ship-in-Ship
  DockingManager → airlock, hangar, cargo clamp
  ShipHierarchy → parent/child ships, nested docking

SYSTEM 6: Inventory & Equipment
  PlayerInventory + ShipInventory
  Parts, tools, supplies, equipment, salvage, data

SYSTEM 7: Procedural Generation Details
  Room roles, graph rules, structural placement, gameplay content

SYSTEM 8: Sargasso World & Scanner Display
  SargassoWorld → ShipRegistry, spatial grid
  ScannerDisplay → UI for ship discovery + travel
```

---

## System 1: Ship Generation Framework

**Purpose:** Generate ship interiors procedurally from high-level parameters.

**Architecture:**

```
ShipBlueprint (input parameters)
    ↓
RoomGraphGenerator (procedural room layout)
    ↓
StructuralPlacer (places floor/wall/ceiling modules)
    ↓
GameplayPlacer (places systems, hazards, objectives, loot)
    ↓
ShipInstance (runtime scene with all systems)
```

**ShipBlueprint — Input parameters:**
- `size`: life_boat (2-4 rooms), small (4-8 rooms), medium (8-12 rooms)
- `condition`: pristine, damaged, wrecked (determines % of systems broken)
- `seed`: deterministic generation for reproducibility

**RoomGraphGenerator — Produces room graph:**
- Generates room nodes with roles (airlock, corridor, engineering, cargo, etc.)
- Connects rooms with links (doors, corridors)
- Ensures connectivity (no isolated rooms)
- Outputs: `RoomGraph` (list of rooms + connections)

**StructuralPlacer — Places physical geometry:**
- Each room role maps to structural module patterns
- Places floor tiles, walls, ceilings, doorways
- Handles multi-deck (ramps between levels)
- Outputs: positioned 3D scene nodes

**GameplayPlacer — Places interactive elements:**
- Systems (power, life support, etc.) placed in appropriate rooms
- Hazards placed based on condition
- Loot/supplies placed based on broken systems
- Outputs: gameplay nodes attached to structural scene

**ShipInstance — Final runtime object:**
- Contains structural scene + gameplay nodes
- Exposes system interfaces for repair/interaction
- Can be instantiated/docked/undocked

**Interface:**
```gdscript
class_name ShipGenerator
func generate(blueprint: ShipBlueprint) -> ShipInstance
```

**Relationship to existing code:**
- Current hand-authored JSON layouts become archetypes/templates
- `generated_ship_loader.gd` is refactored into RoomGraphGenerator
- `playable_generated_ship.gd` becomes ShipInstance

---

## System 2: Ship Systems

**Purpose:** Model 6 core ship systems with dependencies, repair mechanics, and runtime effects.

**The 6 Systems:**

| System | Function | Dependencies | When Broken |
|--------|----------|--------------|-------------|
| Power | Distributes energy to all systems | None (foundational) | Everything offline |
| Life Support | Maintains breathable atmosphere | Power | Oxygen depletes |
| Gravity | Generates artificial gravity | Power | Float, movement impaired |
| Propulsion | Enables travel between ships | Power + Navigation | Can't travel |
| Navigation | Plots courses, shows scanner data | Power | Can't see ships on scanner |
| Scanners | Detects nearby ships + details | Power + Navigation | Blind to surroundings |

**Architecture:**

```
ShipSystemsManager (coordinates all systems)
    ├── PowerSystem
    ├── LifeSupportSystem
    ├── GravitySystem
    ├── PropulsionSystem
    ├── NavigationSystem
    └── ScannerSystem
```

**ShipSystem (base class) — Common interface:**
- `status`: online, offline, damaged, critical
- `health`: 0.0 to 1.0
- `subcomponents`: list of parts that can break/need repair
- `dependencies`: other systems required online
- `is_operational()`: checks health + dependencies
- `repair(subcomponent, parts, tools, skill_level)`: attempt repair

**ShipSystemsManager — Coordinates dependencies:**
- Checks dependency chains each tick
- Cascades failures (power offline → everything offline)
- Exposes system status for HUD

**Subcomponents per system:**
- Power: reactor_core, power_distribution, battery_cells
- Life Support: air_recycler, co2_scrubber, oxygen_tanks
- Gravity: gravity_plating, field_emitter, inertial_dampeners
- Propulsion: thruster_array, fuel_injection, nav_linkage
- Navigation: star_charts, nav_computer, sensor_array
- Scanners: scanner_dish, signal_processor, power_coupling

**Repair Flow:**
```
Diagnose (skill check) → Find parts → Acquire tools → Repair (skill + time check) → System online
```

**Runtime Effects:**
- Power offline → all systems cascade offline
- Life support offline → oxygen drain (existing oxygen_state.gd)
- Gravity offline → movement penalties, floating objects
- Propulsion offline → can't travel
- Navigation offline → scanner shows nothing
- Scanners offline → can't see ship details

**Integration with existing code:**
- `oxygen_state.gd` becomes a child of LifeSupportSystem
- `ship_system_state.gd` becomes ShipSystemsManager
- Other systems are new

---

## System 3: Player Progression (Class + Skills)

**Purpose:** Class-based starting builds with cross-training skill progression.

**Architecture:**

```
PlayerCharacter
    ├── ClassDefinition (starting template)
    ├── SkillTree (learnable abilities)
    └── ExperienceTracker (XP + leveling)
```

**Starting Classes (examples, expandable):**
- Engineer — Repair bonuses, system diagnostics, fabrication
- Medic — Healing, biological hazard resistance, medical crafting
- Pilot — Navigation bonuses, scanner range, travel efficiency
- Scientist — Analysis, research speed, alien tech compatibility
- Mechanic — Physical repair, tool proficiency, salvage expertise
- Cook — Food crafting, morale bonuses, supply efficiency
- Security — Combat bonuses, threat detection, defensive systems
- Communications — Scanner range, signal analysis, distress calls

**Class Definition:**
```gdscript
class_name ClassDefinition
var class_id: String           # "engineer"
var starting_skills: Dictionary  # {"repair": 3, "diagnostics": 2, ...}
var xp_multipliers: Dictionary   # {"repair": 1.5, "medical": 0.7, ...}
var description: String
```

**Skill Categories:**
- Technical: repair, diagnostics, fabrication, welding
- Medical: first_aid, surgery, pharmacology, quarantine
- Navigation: piloting, astrogation, scanner_operation, signal_analysis
- Survival: scavenging, cooking, construction, resource_management
- Social: leadership, negotiation, intimidation, comms

**Skill Mechanics:**
- Skills range 0-10
- Higher skill = faster repair, better diagnostics, more options
- Skills improve with use (practice) or training (books, mentors)
- Cross-training: any class can learn any skill, but non-specialty skills cost more XP

**XP Multipliers by Class (example):**

| Class | repair | medical | navigation | survival | social |
|-------|--------|---------|------------|----------|--------|
| Engineer | 1.5x | 0.7x | 1.0x | 1.0x | 0.8x |
| Medic | 0.7x | 1.5x | 0.8x | 1.0x | 1.2x |
| Pilot | 1.0x | 0.8x | 1.5x | 1.0x | 1.0x |

**Repair Skill Integration:**
- Diagnose system: skill check determines info revealed
- Repair attempt: skill level affects success chance + time
- Subcomponent complexity: some parts need higher skill
- Minimum skill thresholds: some repairs require skill 5+

---

## System 4: Scanner & Travel

**Purpose:** Ship discovery, information gathering, and menu-based travel between ships.

**Architecture:**

```
ScannerSystem
    ├── ScannerRange (how far you can see)
    ├── ScannerDetail (what info you get)
    └── ScannerDisplay (UI for showing ships)

TravelSystem
    ├── TravelMenu (ship selection UI)
    ├── TravelCalculation (fuel/time/risk)
    └── DockingSequence (arrival + generation trigger)
```

**Scanner Mechanics:**

Scanner has two stats:
- Range: how many ships visible (starts at 3-5)
- Detail: what info shown per ship (starts minimal)

**Detail Levels (upgradeable):**

| Level | Info Shown |
|-------|------------|
| 1 | Location, distance, size class |
| 2 | + Ship type (freighter, shuttle, etc.) |
| 3 | + Rough condition (pristine/wrecked) |
| 4 | + System status summary |
| 5 | + Specific systems online/offline |
| 6 | + Loot potential, tech level |

**Scanner upgrades:**
- Better scanner hardware (found on ships)
- Skill bonuses (scanner_operation skill)
- Ship-specific bonuses (science vessels have better scanners)

**Ship Generation Trigger:**
- Ships exist as "markers" in scanner range (lightweight data)
- When player selects a ship to dock with, generation happens
- Generation uses: size, condition, seed (from marker)
- Docking animation hides generation time
- Once generated, ship is "locked in" to the game world

**Travel Flow:**
```
Open Scanner → View available ships → Select target → Confirm travel → 
Docking animation (generation happens) → Board ship
```

**Ship Markers (lightweight data before generation):**
```gdscript
class_name ShipMarker
var marker_id: String
var position: Vector3        # in Sargasso space
var size_class: String       # life_boat, small, medium
var seed: int                # for deterministic generation
var distance: float          # from player
var discovered_at: float     # timestamp
```

---

## System 5: Ship Docking & Ship-in-Ship

**Purpose:** Physical docking between ships, including large ships docking smaller ships in hangars.

**Architecture:**

```
DockingManager
    ├── DockingPort (connection points on ships)
    ├── DockingSequence (animation + generation)
    └── ShipHierarchy (parent/child relationships)

DockingPort
    ├── port_type: airlock, hangar_bay, cargo_clamp
    ├── compatible_sizes: [life_boat, small, medium]
    └── status: sealed, open, broken, forced_open
```

**Docking Types:**

| Type | Where | What Can Dock | Notes |
|------|-------|---------------|-------|
| Airlock | Any ship | Same size or smaller | Standard connection |
| Hangar Bay | Medium+ ships | Life boat, small | Physical interior space |
| Cargo Clamp | Any ship | Life boat only | External attachment |

**Docking Sequence:**
```
Approach ship → Check docking ports available → Select port →
Animation plays (hiding generation) → Physical connection established →
Player can walk between ships
```

**Broken Airlock Mechanic:**
- Some airlocks are broken (jammed, welded, missing)
- Player must force entry (tools + skill check) or find alternate entry
- Forced entry may damage the airlock further

**Ship-in-Ship Hierarchy:**

When a small ship docks inside a larger ship:
- Small ship becomes a child node of large ship
- Small ship retains its own systems (can still be used)
- Player can walk between ships freely
- Small ship's inventory accessible from large ship
- When large ship travels, small ships travel with it

**Ship Hierarchy:**
```gdscript
class_name ShipInstance
var parent_ship: ShipInstance = null    # if docked inside another
var docked_ships: Array[ShipInstance]   # ships docked to this one
var docking_ports: Array[DockingPort]
```

---

## System 6: Inventory & Equipment

**Purpose:** Manage parts, tools, supplies, and equipment across ships and player.

**Architecture:**

```
InventorySystem
    ├── PlayerInventory (what player carries)
    ├── ShipInventory (what's stored on each ship)
    ├── EquipmentSlots (worn/used items)
    └── ItemDatabase (all item definitions)
```

**Item Categories:**

| Category | Examples | Use |
|----------|----------|-----|
| Parts | reactor_core, power_cell, oxygen_filter | Repair subcomponents |
| Tools | welder, scanner, plasma_cutter | Enable repair actions |
| Supplies | food, water, medkits, fuel | Consumables for survival |
| Equipment | spacesuit, tool_belt, scanner_upgrade | Worn/used items |
| Salvage | scrap_metal, circuit_board, wire_bundle | Crafting materials |
| Data | star_charts, ship_logs, research_notes | Unlock info/recipes |

**Inventory Mechanics:**
- Player has limited carry capacity (weight or slots)
- Ships have storage capacity (cargo rooms, lockers)
- Items can be transferred between player and ship inventory
- Items can be transferred between ships when docked

**Equipment Slots:**
- Head: helmet, scanner_visor
- Body: spacesuit, armor
- Hands: tool_in_hand (affects what actions available)
- Belt: tool_belt (quick-access tools)
- Backpack: extra storage

**Integration with Repair:**
- Repair requires specific parts in inventory
- Repair requires appropriate tool equipped or in inventory
- Skill check determines success + time

**Note:** Inventory/repair system will expand significantly in future iterations. Interfaces designed for growth.

---

## System 7: Procedural Generation Details

**Purpose:** How rooms are actually generated from the ShipBlueprint.

**Room Generation Flow:**

```
ShipBlueprint (size, condition, seed)
    ↓
RoomCountCalculator (determines room count from size)
    ↓
RoomRoleAssigner (picks which rooms exist)
    ↓
RoomGraphBuilder (connects rooms with links)
    ↓
RoomLayoutGenerator (places structural modules per room)
    ↓
GameplayContentPlacer (systems, hazards, loot)
```

**Room Roles:**

| Role | Purpose | Always Present? |
|------|---------|-----------------|
| airlock | Entry/exit point | Yes |
| corridor | Connection space | No (but common) |
| engineering | Power, propulsion systems | Yes (if propulsion exists) |
| life_support | Atmosphere systems | Yes (if life support exists) |
| bridge | Navigation, scanners | Yes (if nav/scanners exist) |
| cargo | Storage, supplies | No |
| crew_quarters | Living space, lockers | No |
| medical | Health supplies, healing | No |
| maintenance | Access panels, wiring | No |
| hangar | Ship-in-ship docking | Only on medium+ ships |

**Room Graph Rules:**
- Airlock always connects to at least one corridor/room
- No isolated rooms (all reachable from airlock)
- Critical path: airlock → engineering/bridge (systems must be reachable)
- Dead ends allowed for optional rooms (cargo, crew quarters)

**Structural Module Placement:**
- Each room has a "template" based on role + size
- Templates define floor grid, wall positions, doorway positions
- Structural modules fill the template (floor_1x1, wall_straight_1x1, etc.)
- Multi-deck rooms use ramps between levels

**Gameplay Content Placement:**
- Systems placed in appropriate rooms (power in engineering, etc.)
- Hazards placed based on condition (fire in damaged rooms, etc.)
- Loot placed based on what's broken (need parts for broken systems)
- Tool pickups placed in maintenance/crew areas

**Deterministic Generation:**
- Same seed + same blueprint = same ship
- Allows sharing ship discoveries between players
- Allows revisiting previously generated ships

---

## System 8: Sargasso World & Scanner Display

**Purpose:** The infinite biomatter web, how ships exist in it, and the scanner UI for navigation.

**Architecture:**

```
SargassoWorld
    ├── ShipRegistry (all discovered/generated ships)
    ├── SargassoGrid (spatial partitioning for ships)
    └── BiomatterField (the web itself, hazards)

ScannerDisplay
    ├── ScannerUI (the menu interface)
    ├── ShipMarkerRenderer (shows ships on display)
    └── DetailPanel (shows selected ship info)
```

**Sargasso World:**
- Ships exist at positions in Sargasso space (3D coordinates, but travel is menu-based)
- Ships are "trapped" in biomatter web (visual context)
- Biomatter has properties (may damage ships over time, hazards)
- Grid-based spatial partitioning for efficient ship lookup

**Ship Registry:**
```gdscript
class_name ShipRegistry
var discovered_ships: Dictionary  # marker_id → ShipMarker
var generated_ships: Dictionary   # marker_id → ShipInstance
var player_ship: ShipInstance     # current primary ship
```

**Scanner Display UI:**
- Top-down or 3D view of local Sargasso space
- Player ship at center
- Discovered ships shown as icons/markers
- Color coding by size, condition, or distance
- Select ship to view details + initiate travel

**Ship Marker Display:**
- Icon based on size class (small dot, medium diamond, large square)
- Color based on scanner detail level:
  - Level 1: white (unknown)
  - Level 2: yellow (size known)
  - Level 3: green/red (condition known)
  - Level 4+: blue (detailed info)
- Hover/select shows detail panel

**Ship Generation on Dock:**
- Player selects ship on scanner
- ShipMarker provides seed + parameters
- ShipGenerator.generate(marker.to_blueprint()) runs
- Docking animation plays during generation
- ShipInstance created and added to world
- ShipMarker updated to reference ShipInstance

---

## Integration Flow

1. Game starts → Generate life raft (ShipBlueprint with random broken systems)
2. Player repairs systems → Ship systems come online
3. Navigation + Scanners online → ScannerDisplay activates
4. Player selects ship on scanner → TravelSystem initiates
5. Docking animation → ShipGenerator creates derelict
6. Player boards derelict → Explore, loot, repair
7. Optionally dock derelict as new primary ship
8. Repeat — larger ships, more complex systems, better equipment

---

## Build Phases (System-First)

**Phase 1: Ship Generation Framework**
- Implement ShipBlueprint, RoomGraphGenerator, StructuralPlacer
- Generate life raft + one derelict type
- Validate: rooms connect, geometry loads, player can walk through

**Phase 2: Ship Systems**
- Implement ShipSystemsManager + all 6 systems
- Implement subcomponents + dependency cascades
- Validate: systems come online/offline, cascades work, repair flow functions

**Phase 3: Player Progression**
- Implement ClassDefinition + SkillTree
- Implement XP system + skill checks
- Validate: classes start with correct skills, skills improve with use

**Phase 4: Scanner & Travel**
- Implement ScannerSystem + ScannerDisplay
- Implement TravelSystem + menu-based travel
- Validate: ships appear on scanner, travel works, docking triggers generation

**Phase 5: Ship Docking & Ship-in-Ship**
- Implement DockingManager + DockingPort
- Implement ShipHierarchy for nested ships
- Validate: ships dock, player walks between, ship-in-ship works

**Phase 6: Inventory & Equipment**
- Implement PlayerInventory + ShipInventory
- Implement ItemDatabase + equipment slots
- Validate: items transfer between player/ship, equipment affects actions

**Phase 7: Integration & Polish**
- Connect all systems end-to-end
- Add UI/HUD for all systems
- Balance gameplay (repair difficulty, loot distribution, scanner upgrades)

---

## Future Expansions (Out of Scope)

- Alien ship types (different aesthetics, technology, systems)
- Ultra-rare jump drive escape condition
- NPC encounters (other survivors, traders)
- Combat systems
- Crafting system expansion
- Multiplayer
- Narrative/story elements
- Music and audio

---

## Existing Codebase

**Scripts (7,110 lines GDScript):**
- `scripts/procgen/` — Current generation system (to be refactored)
- `scripts/systems/` — Current system modules (to be integrated)
- `scripts/player/` — Player controller (to be extended)
- `scripts/camera/` — Isometric camera (to be kept)
- `scripts/ui/` — Current HUD (to be expanded)

**Data:**
- `data/procgen/golden/` — 3 hand-authored ship layouts (to become archetypes)
- `data/kits/` — Structural module definitions (to be kept)
- `data/placement/contracts/` — Module placement rules (to be kept)

**Scenes:**
- `scenes/procgen/` — Ship scenes (to be refactored)
- `scenes/wrappers/structural/` — Structural modules (to be kept)

**Validation (61 scripts):**
- Existing smokes validate current systems
- New smokes needed for each new system
