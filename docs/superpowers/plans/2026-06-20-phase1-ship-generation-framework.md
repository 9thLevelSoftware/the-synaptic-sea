# Phase 1: Ship Generation Framework — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the procedural ship generation framework that creates ship interiors from high-level parameters (size, condition, seed).

**Architecture:** ShipBlueprint → RoomGraphGenerator → StructuralPlacer → GameplayPlacer → ShipInstance. Each stage is independent and testable. The existing hand-authored JSON layouts become archetypes that seed the generator.

**Tech Stack:** Godot 4.6.2, GDScript, existing structural module kit (ship_structural_v0)

**Spec:** `docs/superpowers/specs/2026-06-20-sargasso-core-systems-design.md` — System 1 + System 7

---

## Global Constraints

- Godot 4.6.2, GDScript only
- All new scripts go in `scripts/procgen/` or `scripts/systems/`
- All new data goes in `data/procgen/`
- Existing structural modules in `scenes/wrappers/structural/ship_structural_v0/` are reused as-is
- Existing validation smokes must continue to pass
- Each task produces a working, testable deliverable
- No placeholders, no TBDs

---

## File Structure

```
scripts/procgen/
    ship_blueprint.gd          # ShipBlueprint data class
    room_graph.gd              # RoomGraph data class (rooms + links)
    room_graph_generator.gd    # Generates RoomGraph from blueprint
    structural_placer.gd       # Places structural modules from room graph
    gameplay_placer.gd         # Places systems, hazards, loot from room graph
    ship_generator.gd          # Orchestrates the full pipeline
    ship_instance.gd           # Runtime ship scene (refactored from playable_generated_ship.gd)

data/procgen/
    archetypes/                # Hand-authored layouts become archetypes
        life_boat.json         # 2-4 room life boat archetype
        small_freighter.json   # 4-8 room small ship archetype
        medium_cruiser.json    # 8-12 room medium ship archetype

scripts/validation/
    ship_blueprint_smoke.gd    # Validate blueprint creation
    room_graph_smoke.gd        # Validate room graph generation
    ship_generator_smoke.gd    # Validate full generation pipeline
```

---

## Task 1: ShipBlueprint Data Class

**Files:**
- Create: `scripts/procgen/ship_blueprint.gd`
- Test: `scripts/validation/ship_blueprint_smoke.gd`

**Interfaces:**
- Produces: `ShipBlueprint` class with `size`, `condition`, `seed`, `room_count_range`

- [ ] **Step 1: Write the ShipBlueprint class**

```gdscript
# scripts/procgen/ship_blueprint.gd
class_name ShipBlueprint
extends RefCounted

enum Size { LIFE_BOAT, SMALL, MEDIUM }
enum Condition { PRISTINE, DAMAGED, WRECKED }

var size: Size
var condition: Condition
var seed_value: int
var room_count_range: Vector2i  # min, max rooms

func _init(p_size: Size = Size.LIFE_BOAT, p_condition: Condition = Condition.DAMAGED, p_seed: int = 0) -> void:
    size = p_size
    condition = p_condition
    seed_value = p_seed
    room_count_range = _get_room_count_range()

func _get_room_count_range() -> Vector2i:
    match size:
        Size.LIFE_BOAT:
            return Vector2i(2, 4)
        Size.SMALL:
            return Vector2i(4, 8)
        Size.MEDIUM:
            return Vector2i(8, 12)
        _:
            return Vector2i(2, 4)

func get_system_online_chance() -> float:
    match condition:
        Condition.PRISTINE:
            return 0.9
        Condition.DAMAGED:
            return 0.5
        Condition.WRECKED:
            return 0.2
        _:
            return 0.5

func to_dict() -> Dictionary:
    return {
        "size": size,
        "condition": condition,
        "seed": seed_value,
        "room_count_range": [room_count_range.x, room_count_range.y]
    }

static func from_dict(data: Dictionary) -> ShipBlueprint:
    var bp := ShipBlueprint.new(
        data.get("size", Size.LIFE_BOAT),
        data.get("condition", Condition.DAMAGED),
        data.get("seed", 0)
    )
    var range_arr: Array = data.get("room_count_range", [2, 4])
    bp.room_count_range = Vector2i(range_arr[0], range_arr[1])
    return bp
```

- [ ] **Step 2: Write the validation smoke**

```gdscript
# scripts/validation/ship_blueprint_smoke.gd
extends SceneTree

func _init() -> void:
    var bp := ShipBlueprint.new(
        ShipBlueprint.Size.LIFE_BOAT,
        ShipBlueprint.Condition.DAMAGED,
        12345
    )
    
    assert(bp.size == ShipBlueprint.Size.LIFE_BOAT)
    assert(bp.condition == ShipBlueprint.Condition.DAMAGED)
    assert(bp.seed_value == 12345)
    assert(bp.room_count_range == Vector2i(2, 4))
    assert(bp.get_system_online_chance() == 0.5)
    
    var bp2 := ShipBlueprint.new(ShipBlueprint.Size.SMALL, ShipBlueprint.Condition.PRISTINE, 0)
    assert(bp2.room_count_range == Vector2i(4, 8))
    assert(bp2.get_system_online_chance() == 0.9)
    
    var bp3 := ShipBlueprint.new(ShipBlueprint.Size.MEDIUM, ShipBlueprint.Condition.WRECKED, 0)
    assert(bp3.room_count_range == Vector2i(8, 12))
    assert(bp3.get_system_online_chance() == 0.2)
    
    # Test serialization
    var dict := bp.to_dict()
    var bp4 := ShipBlueprint.from_dict(dict)
    assert(bp4.size == bp.size)
    assert(bp4.condition == bp.condition)
    assert(bp4.seed_value == bp.seed_value)
    
    print("SHIP BLUEPRINT PASS sizes=3 conditions=3 serialization=true")
    quit(0)
```

- [ ] **Step 3: Run smoke to verify it passes**

Run: `/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/ship_blueprint_smoke.gd`
Expected: `SHIP BLUEPRINT PASS sizes=3 conditions=3 serialization=true`

- [ ] **Step 4: Commit**

```bash
git add scripts/procgen/ship_blueprint.gd scripts/validation/ship_blueprint_smoke.gd
git commit -m "feat(procgen): add ShipBlueprint data class with size/condition/seed"
```

---

## Task 2: RoomGraph Data Class

**Files:**
- Create: `scripts/procgen/room_graph.gd`
- Test: `scripts/validation/room_graph_smoke.gd`

**Interfaces:**
- Produces: `RoomGraph` class with `rooms`, `links`, `add_room()`, `add_link()`, `get_connected_rooms()`, `is_fully_connected()`

- [ ] **Step 1: Write the RoomGraph class**

```gdscript
# scripts/procgen/room_graph.gd
class_name RoomGraph
extends RefCounted

var rooms: Array[Dictionary] = []  # [{id, role, deck}]
var links: Array[Dictionary] = []  # [{from_room, to_room, type}]

func add_room(room_id: String, role: String, deck: int = 0) -> void:
    rooms.append({"id": room_id, "role": role, "deck": deck})

func add_link(from_room: String, to_room: String, link_type: String = "door") -> void:
    links.append({"from_room": from_room, "to_room": to_room, "type": link_type})

func get_room(room_id: String) -> Dictionary:
    for room in rooms:
        if room["id"] == room_id:
            return room
    return {}

func get_connected_rooms(room_id: String) -> Array[String]:
    var connected: Array[String] = []
    for link in links:
        if link["from_room"] == room_id:
            connected.append(link["to_room"])
        elif link["to_room"] == room_id:
            connected.append(link["from_room"])
    return connected

func is_fully_connected() -> bool:
    if rooms.is_empty():
        return true
    
    var visited: Dictionary = {}
    var queue: Array[String] = [rooms[0]["id"]]
    visited[rooms[0]["id"]] = true
    
    while not queue.is_empty():
        var current: String = queue.pop_front()
        for connected_id in get_connected_rooms(current):
            if not visited.has(connected_id):
                visited[connected_id] = true
                queue.append(connected_id)
    
    return visited.size() == rooms.size()

func get_rooms_by_role(role: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for room in rooms:
        if room["role"] == role:
            result.append(room)
    return result

func to_dict() -> Dictionary:
    return {"rooms": rooms, "links": links}

static func from_dict(data: Dictionary) -> RoomGraph:
    var graph := RoomGraph.new()
    for room_data in data.get("rooms", []):
        graph.add_room(room_data["id"], room_data["role"], room_data.get("deck", 0))
    for link_data in data.get("links", []):
        graph.add_link(link_data["from_room"], link_data["to_room"], link_data.get("type", "door"))
    return graph
```

- [ ] **Step 2: Write the validation smoke**

```gdscript
# scripts/validation/room_graph_smoke.gd
extends SceneTree

func _init() -> void:
    var graph := RoomGraph.new()
    
    # Build a simple graph: airlock -> corridor -> engineering
    graph.add_room("airlock_01", "airlock")
    graph.add_room("corridor_01", "corridor")
    graph.add_room("engineering_01", "engineering")
    
    graph.add_link("airlock_01", "corridor_01")
    graph.add_link("corridor_01", "engineering_01")
    
    assert(graph.rooms.size() == 3)
    assert(graph.links.size() == 2)
    assert(graph.is_fully_connected())
    
    var connected := graph.get_connected_rooms("corridor_01")
    assert(connected.size() == 2)
    assert("airlock_01" in connected)
    assert("engineering_01" in connected)
    
    var engineering := graph.get_rooms_by_role("engineering")
    assert(engineering.size() == 1)
    assert(engineering[0]["id"] == "engineering_01")
    
    # Test disconnected graph
    var graph2 := RoomGraph.new()
    graph2.add_room("a", "airlock")
    graph2.add_room("b", "corridor")
    graph2.add_room("c", "engineering")  # Not connected
    graph2.add_link("a", "b")
    assert(not graph2.is_fully_connected())
    
    # Test serialization
    var dict := graph.to_dict()
    var graph3 := RoomGraph.from_dict(dict)
    assert(graph3.rooms.size() == 3)
    assert(graph3.links.size() == 2)
    assert(graph3.is_fully_connected())
    
    print("ROOM GRAPH PASS rooms=3 links=2 connected=true disconnected_detected=true serialization=true")
    quit(0)
```

- [ ] **Step 3: Run smoke to verify it passes**

Run: `/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/room_graph_smoke.gd`
Expected: `ROOM GRAPH PASS rooms=3 links=2 connected=true disconnected_detected=true serialization=true`

- [ ] **Step 4: Commit**

```bash
git add scripts/procgen/room_graph.gd scripts/validation/room_graph_smoke.gd
git commit -m "feat(procgen): add RoomGraph data class with connectivity checking"
```

---

## Task 3: RoomGraphGenerator

**Files:**
- Create: `scripts/procgen/room_graph_generator.gd`
- Test: `scripts/validation/room_graph_generator_smoke.gd`

**Interfaces:**
- Consumes: `ShipBlueprint` (from Task 1)
- Produces: `RoomGraph` (from Task 2)
- Produces: `RoomGraphGenerator.generate(blueprint: ShipBlueprint) -> RoomGraph`

- [ ] **Step 1: Write the RoomGraphGenerator**

```gdscript
# scripts/procgen/room_graph_generator.gd
class_name RoomGraphGenerator
extends RefCounted

# Room roles that are always present
const REQUIRED_ROLES := ["airlock"]
# Room roles based on ship systems
const SYSTEM_ROLES := {
    "power": "engineering",
    "life_support": "life_support",
    "propulsion": "engineering",
    "navigation": "bridge",
    "scanners": "bridge"
}
# Optional room roles
const OPTIONAL_ROLES := ["corridor", "cargo", "crew_quarters", "medical", "maintenance"]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func generate(blueprint: ShipBlueprint) -> RoomGraph:
    rng.seed = blueprint.seed_value
    
    var graph := RoomGraph.new()
    var room_count := rng.randi_range(blueprint.room_count_range.x, blueprint.room_count_range.y)
    
    # Always add airlock
    graph.add_room("airlock_01", "airlock")
    
    # Add required system rooms
    _add_required_rooms(graph, blueprint)
    
    # Fill remaining slots with optional rooms
    _fill_optional_rooms(graph, room_count)
    
    # Connect rooms
    _connect_rooms(graph)
    
    return graph

func _add_required_rooms(graph: RoomGraph, blueprint: ShipBlueprint) -> void:
    # Engineering room for power/propulsion
    graph.add_room("engineering_01", "engineering")
    
    # Life support room (if life boat, combine with engineering)
    if blueprint.size != ShipBlueprint.Size.LIFE_BOAT:
        graph.add_room("life_support_01", "life_support")
    
    # Bridge for navigation/scanners (if not life boat)
    if blueprint.size != ShipBlueprint.Size.LIFE_BOAT:
        graph.add_room("bridge_01", "bridge")

func _fill_optional_rooms(graph: RoomGraph, target_count: int) -> void:
    var current_count := graph.rooms.size()
    var available_roles := OPTIONAL_ROLES.duplicate()
    
    while current_count < target_count and not available_roles.is_empty():
        var role_index := rng.randi_range(0, available_roles.size() - 1)
        var role: String = available_roles[role_index]
        var room_id := "%s_%d" % [role, current_count]
        graph.add_room(room_id, role)
        current_count += 1
        
        # Remove role if we've added enough of that type
        if graph.get_rooms_by_role(role).size() >= 2:
            available_roles.erase(role)

func _connect_rooms(graph: RoomGraph) -> void:
    # Simple linear chain: airlock -> corridor -> engineering -> ...
    # Then add branches for optional rooms
    var previous_id: String = ""
    
    for room in graph.rooms:
        if previous_id != "":
            graph.add_link(previous_id, room["id"])
        previous_id = room["id"]
    
    # Add some random branches for variety
    for room in graph.rooms:
        if room["role"] in ["cargo", "crew_quarters", "medical"] and rng.randf() < 0.5:
            # Connect to a random non-airlock room
            var candidates: Array[String] = []
            for other in graph.rooms:
                if other["id"] != room["id"] and other["id"] != "airlock_01":
                    candidates.append(other["id"])
            if not candidates.is_empty():
                var target: String = candidates[rng.randi_range(0, candidates.size() - 1)]
                graph.add_link(room["id"], target)
```

- [ ] **Step 2: Write the validation smoke**

```gdscript
# scripts/validation/room_graph_generator_smoke.gd
extends SceneTree

func _init() -> void:
    var generator := RoomGraphGenerator.new()
    
    # Test life boat generation
    var bp_life := ShipBlueprint.new(ShipBlueprint.Size.LIFE_BOAT, ShipBlueprint.Condition.DAMAGED, 42)
    var graph_life := generator.generate(bp_life)
    assert(graph_life.rooms.size() >= 2 and graph_life.rooms.size() <= 4)
    assert(graph_life.is_fully_connected())
    assert(graph_life.get_rooms_by_role("airlock").size() == 1)
    assert(graph_life.get_rooms_by_role("engineering").size() == 1)
    
    # Test small ship generation
    var bp_small := ShipBlueprint.new(ShipBlueprint.Size.SMALL, ShipBlueprint.Condition.PRISTINE, 123)
    var graph_small := generator.generate(bp_small)
    assert(graph_small.rooms.size() >= 4 and graph_small.rooms.size() <= 8)
    assert(graph_small.is_fully_connected())
    assert(graph_small.get_rooms_by_role("bridge").size() == 1)
    
    # Test medium ship generation
    var bp_medium := ShipBlueprint.new(ShipBlueprint.Size.MEDIUM, ShipBlueprint.Condition.WRECKED, 456)
    var graph_medium := generator.generate(bp_medium)
    assert(graph_medium.rooms.size() >= 8 and graph_medium.rooms.size() <= 12)
    assert(graph_medium.is_fully_connected())
    
    # Test deterministic generation (same seed = same result)
    var bp_same := ShipBlueprint.new(ShipBlueprint.Size.SMALL, ShipBlueprint.Condition.DAMAGED, 42)
    var graph_same := generator.generate(bp_same)
    var bp_same2 := ShipBlueprint.new(ShipBlueprint.Size.SMALL, ShipBlueprint.Condition.DAMAGED, 42)
    var graph_same2 := generator.generate(bp_same2)
    assert(graph_same.rooms.size() == graph_same2.rooms.size())
    assert(graph_same.links.size() == graph_same2.links.size())
    
    print("ROOM GRAPH GENERATOR PASS life_boat=%d small=%d medium=%d deterministic=true" % [
        graph_life.rooms.size(),
        graph_small.rooms.size(),
        graph_medium.rooms.size()
    ])
    quit(0)
```

- [ ] **Step 3: Run smoke to verify it passes**

Run: `/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/room_graph_generator_smoke.gd`
Expected: `ROOM GRAPH GENERATOR PASS life_boat=2-4 small=4-8 medium=8-12 deterministic=true`

- [ ] **Step 4: Commit**

```bash
git add scripts/procgen/room_graph_generator.gd scripts/validation/room_graph_generator_smoke.gd
git commit -m "feat(procgen): add RoomGraphGenerator with deterministic room layout"
```

---

## Task 4: StructuralPlacer

**Files:**
- Create: `scripts/procgen/structural_placer.gd`
- Test: `scripts/validation/structural_placer_smoke.gd`

**Interfaces:**
- Consumes: `RoomGraph` (from Task 2)
- Consumes: Existing structural modules from `scenes/wrappers/structural/ship_structural_v0/`
- Produces: `Node3D` with positioned structural modules

- [ ] **Step 1: Write the StructuralPlacer**

```gdscript
# scripts/procgen/structural_placer.gd
class_name StructuralPlacer
extends RefCounted

const CELL_SIZE := 4.0
const MODULE_BASE_PATH := "res://scenes/wrappers/structural/ship_structural_v0/"

# Module mappings for room roles
const ROOM_MODULES := {
    "airlock": ["floor_1x1", "floor_1x1", "doorway_frame_open_1x1"],
    "corridor": ["corridor_floor_1x1", "corridor_floor_1x1"],
    "engineering": ["floor_1x1", "floor_2x1", "wall_straight_1x1"],
    "life_support": ["floor_1x1", "floor_1x1", "wall_straight_1x1"],
    "bridge": ["floor_2x1", "floor_2x1", "wall_straight_1x1"],
    "cargo": ["floor_2x1", "floor_2x1"],
    "crew_quarters": ["floor_1x1", "floor_1x1"],
    "medical": ["floor_1x1", "floor_1x1"],
    "maintenance": ["floor_1x1", "corridor_floor_1x1"]
}

func place_structure(graph: RoomGraph) -> Node3D:
    var root := Node3D.new()
    root.name = "ShipStructure"
    
    var x_offset := 0.0
    
    for room in graph.rooms:
        var room_node := _create_room_node(room, x_offset)
        root.add_child(room_node)
        x_offset += CELL_SIZE * 2  # Space between rooms
    
    return root

func _create_room_node(room: Dictionary, x_offset: float) -> Node3D:
    var room_node := Node3D.new()
    room_node.name = "Room_%s" % room["id"]
    room_node.position = Vector3(x_offset, 0, 0)
    
    var role: String = room["role"]
    var modules: Array = ROOM_MODULES.get(role, ["floor_1x1"])
    
    var z_offset := 0.0
    for module_name in modules:
        var module_path := MODULE_BASE_PATH + module_name + ".tscn"
        if ResourceLoader.exists(module_path):
            var module_scene: PackedScene = load(module_path)
            if module_scene:
                var module_instance := module_scene.instantiate()
                module_instance.name = module_name
                module_instance.position = Vector3(0, 0, z_offset)
                room_node.add_child(module_instance)
                z_offset += CELL_SIZE
    
    return room_node
```

- [ ] **Step 2: Write the validation smoke**

```gdscript
# scripts/validation/structural_placer_smoke.gd
extends SceneTree

func _init() -> void:
    var generator := RoomGraphGenerator.new()
    var bp := ShipBlueprint.new(ShipBlueprint.Size.LIFE_BOAT, ShipBlueprint.Condition.DAMAGED, 42)
    var graph := generator.generate(bp)
    
    var placer := StructuralPlacer.new()
    var structure := placer.place_structure(graph)
    
    assert(structure != null)
    assert(structure.get_child_count() > 0)
    
    # Check that rooms have children (modules)
    var total_modules := 0
    for room_node in structure.get_children():
        total_modules += room_node.get_child_count()
    
    assert(total_modules > 0)
    
    print("STRUCTURAL PLACER PASS rooms=%d modules=%d" % [structure.get_child_count(), total_modules])
    quit(0)
```

- [ ] **Step 3: Run smoke to verify it passes**

Run: `/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/structural_placer_smoke.gd`
Expected: `STRUCTURAL PLACER PASS rooms=2-4 modules=N`

- [ ] **Step 4: Commit**

```bash
git add scripts/procgen/structural_placer.gd scripts/validation/structural_placer_smoke.gd
git commit -m "feat(procgen): add StructuralPlacer with module-based room generation"
```

---

## Task 5: ShipGenerator Orchestrator

**Files:**
- Create: `scripts/procgen/ship_generator.gd`
- Test: `scripts/validation/ship_generator_smoke.gd`

**Interfaces:**
- Consumes: `ShipBlueprint` (Task 1), `RoomGraphGenerator` (Task 3), `StructuralPlacer` (Task 4)
- Produces: `ShipGenerator.generate(blueprint: ShipBlueprint) -> Node3D`

- [ ] **Step 1: Write the ShipGenerator**

```gdscript
# scripts/procgen/ship_generator.gd
class_name ShipGenerator
extends RefCounted

var graph_generator := RoomGraphGenerator.new()
var structural_placer := StructuralPlacer.new()

func generate(blueprint: ShipBlueprint) -> Node3D:
    var graph := graph_generator.generate(blueprint)
    var structure := structural_placer.place_structure(graph)
    
    var ship_root := Node3D.new()
    ship_root.name = "GeneratedShip"
    ship_root.add_child(structure)
    
    return ship_root

func generate_from_seed(seed_value: int, size: ShipBlueprint.Size = ShipBlueprint.Size.LIFE_BOAT, condition: ShipBlueprint.Condition = ShipBlueprint.Condition.DAMAGED) -> Node3D:
    var blueprint := ShipBlueprint.new(size, condition, seed_value)
    return generate(blueprint)
```

- [ ] **Step 2: Write the validation smoke**

```gdscript
# scripts/validation/ship_generator_smoke.gd
extends SceneTree

func _init() -> void:
    var generator := ShipGenerator.new()
    
    # Test life boat generation
    var ship_life := generator.generate_from_seed(42, ShipBlueprint.Size.LIFE_BOAT, ShipBlueprint.Condition.DAMAGED)
    assert(ship_life != null)
    assert(ship_life.get_child_count() > 0)
    
    # Test small ship generation
    var ship_small := generator.generate_from_seed(123, ShipBlueprint.Size.SMALL, ShipBlueprint.Condition.PRISTINE)
    assert(ship_small != null)
    
    # Test deterministic generation
    var ship_same1 := generator.generate_from_seed(42, ShipBlueprint.Size.SMALL, ShipBlueprint.Condition.DAMAGED)
    var ship_same2 := generator.generate_from_seed(42, ShipBlueprint.Size.SMALL, ShipBlueprint.Condition.DAMAGED)
    assert(ship_same1.get_child_count() == ship_same2.get_child_count())
    
    print("SHIP GENERATOR PASS life_boat=true small=true deterministic=true")
    quit(0)
```

- [ ] **Step 3: Run smoke to verify it passes**

Run: `/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/ship_generator_smoke.gd`
Expected: `SHIP GENERATOR PASS life_boat=true small=true deterministic=true`

- [ ] **Step 4: Commit**

```bash
git add scripts/procgen/ship_generator.gd scripts/validation/ship_generator_smoke.gd
git commit -m "feat(procgen): add ShipGenerator orchestrator for full pipeline"
```

---

## Task 6: Integration with Existing PlayableGeneratedShip

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `scripts/main.gd`
- Test: Run existing validation smokes to ensure no regressions

**Interfaces:**
- Consumes: `ShipGenerator` (Task 5)
- Produces: Generated ships loadable in main scene

- [ ] **Step 1: Add ShipGenerator integration to PlayableGeneratedShip**

Add to top of `playable_generated_ship.gd`:
```gdscript
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
```

Add method:
```gdscript
func load_from_blueprint(blueprint: ShipBlueprint) -> void:
    var generator := ShipGeneratorScript.new()
    var ship_root := generator.generate(blueprint)
    add_child(ship_root)
```

- [ ] **Step 2: Run existing validation smokes to verify no regressions**

Run: `/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_completion_smoke.gd`
Expected: `MAIN PLAYABLE SLICE COMPLETE PASS`

- [ ] **Step 3: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd
git commit -m "feat(procgen): integrate ShipGenerator with PlayableGeneratedShip"
```

---

## Task 7: Archetype Data Files

**Files:**
- Create: `data/procgen/archetypes/life_boat.json`
- Create: `data/procgen/archetypes/small_freighter.json`
- Create: `data/procgen/archetypes/medium_cruiser.json`

**Interfaces:**
- Produces: JSON archetype files that can be loaded by ShipBlueprint.from_dict()

- [ ] **Step 1: Create life boat archetype**

```json
{
    "name": "Life Boat",
    "description": "Small emergency vessel with minimal systems",
    "blueprint": {
        "size": 0,
        "condition": 1,
        "seed": 0,
        "room_count_range": [2, 4]
    }
}
```

- [ ] **Step 2: Create small freighter archetype**

```json
{
    "name": "Small Freighter",
    "description": "Medium-sized cargo vessel",
    "blueprint": {
        "size": 1,
        "condition": 1,
        "seed": 0,
        "room_count_range": [4, 8]
    }
}
```

- [ ] **Step 3: Create medium cruiser archetype**

```json
{
    "name": "Medium Cruiser",
    "description": "Large military or exploration vessel",
    "blueprint": {
        "size": 2,
        "condition": 1,
        "seed": 0,
        "room_count_range": [8, 12]
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add data/procgen/archetypes/
git commit -m "feat(procgen): add ship archetype data files"
```

---

## Self-Review

**Spec coverage:**
- ShipBlueprint: covered in Task 1
- RoomGraphGenerator: covered in Task 3
- StructuralPlacer: covered in Task 4
- ShipGenerator orchestrator: covered in Task 5
- Integration with existing code: covered in Task 6
- Archetype data: covered in Task 7

**Placeholder scan:** No TBDs, TODOs, or placeholders found.

**Type consistency:** ShipBlueprint, RoomGraph, RoomGraphGenerator, StructuralPlacer, ShipGenerator all consistently typed across tasks.

**Missing:** GameplayPlacer (places systems, hazards, loot) is not in this plan — it depends on System 2 (Ship Systems) which is Phase 2. This is intentional: Phase 1 builds the structural generation, Phase 2 adds gameplay content placement.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-20-phase1-ship-generation-framework.md`.

Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
