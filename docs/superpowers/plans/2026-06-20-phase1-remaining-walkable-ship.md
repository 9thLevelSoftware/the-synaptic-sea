# Phase 1 Completion: Walkable Generated Ships

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close Phase 1 by making generated ships fully walkable end-to-end: generate a derelict + life boat start scenario where rooms connect, geometry loads, and a navigation agent can walk from start to goal.

**Architecture:** The layout pipeline (TemplateSelector -> RoomAssigner -> CellLayoutEngine -> WallDoorResolver -> LayoutSerializer) is complete and produces correct layout.json Dictionaries. What remains is wiring the start scenario through this pipeline, building a minimal GameplaySliceBuilder to populate the empty gameplay arrays, and proving walkability with an automated end-to-end smoke test.

**Tech Stack:** Godot 4.6.2, GDScript, RefCounted classes for pipeline stages, existing structural module kit (`data/ship_structural_v0_kit.json`)

**Spec:** `docs/superpowers/specs/2026-06-20-synapse-sea-core-systems-design.md` — System 1: "Generate life raft + one derelict type. Validate: rooms connect, geometry loads, player can walk through."

## Global Constraints

- Godot 4.6.2, GDScript only
- All new scripts in `scripts/procgen/`
- All data files in `data/procgen/`
- Existing validation smokes must continue to pass
- Deterministic: same seed = identical layout
- Ship axis: bow = +X (east), stern = -X (west), lateral = north/south
- CELL_SIZE = 4.0, DECK_HEIGHT = 4.0
- Test pattern: `extends SceneTree`, `_initialize()`, `push_error("PREFIX FAIL ...")` + `quit(1)`, `print("PREFIX PASS ...")` + `quit(0)`
- Godot binary: `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`
- Project path: `C:/Users/dasbl/Documents/The Synaptic Sea`
- Run tests: `"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/<test>.gd`
- No scene nodes in pipeline stages (RefCounted only until final scene assembly)
- Life boat is a fixed 3-room layout (airlock, cockpit, engine_bay) — not procgen
- Derelict uses the template-based layout pipeline with `data/procgen/archetypes/derelict.json`

---

## File Structure

```
scripts/procgen/
    gameplay_slice_builder.gd    # NEW: Builds gameplay_slice.json Dict from layout Dict
    start_scene_builder.gd       # MODIFY: Use new layout pipeline, wire dock connection
    life_boat.gd                 # MODIFY: Output layout.json-compatible Dict
    ship_generator.gd            # MODIFY: Use GameplaySliceBuilder instead of inline gameplay

scripts/validation/
    gameplay_slice_builder_smoke.gd    # NEW: Unit test for gameplay slice generation
    start_scenario_smoke.gd           # NEW: End-to-end walkability test for derelict+lifeboat
```

---

## Task 1: GameplaySliceBuilder

**Files:**
- Create: `scripts/procgen/gameplay_slice_builder.gd`
- Create: `scripts/validation/gameplay_slice_builder_smoke.gd`

**Interfaces:**
- Consumes: layout Dictionary (output of `ShipLayoutGenerator.generate()`)
- Produces: `GameplaySliceBuilder.build(layout: Dictionary) -> Dictionary` returning a gameplay_slice Dict with `start_room`, `goal_room`, `objectives[]`, and empty arrays for `fire_zones`, `arc_zones`, `breach_zones`

**Context:** Currently `ship_generator.gd` builds a minimal gameplay slice inline (lines 73-87). This extracts that logic into a proper RefCounted class and adds the ability to place salvage points in non-connective rooms. The layout pipeline outputs empty `blocked_links`, `fire_zones`, `arc_zones`, `breach_zones` arrays by design — GameplaySliceBuilder populates the gameplay_slice.json that sits alongside layout.json.

- [ ] **Step 1: Write the failing test**

Create `scripts/validation/gameplay_slice_builder_smoke.gd`:

```gdscript
extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")

func _initialize() -> void:
    var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
    var builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()

    var templates: Array[String] = ["spine", "bifurcated", "stacked"]
    var test_count: int = 0

    for template_id in templates:
        for seed_val in [42, 999, 7777]:
            test_count += 1
            var bp: ShipBlueprintScript = ShipBlueprintScript.new(
                ShipBlueprintScript.Size.MEDIUM,
                ShipBlueprintScript.Condition.DAMAGED,
                seed_val)
            var layout: Dictionary = generator.generate(bp, {"template": template_id})
            if layout.is_empty():
                push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d layout empty" % [template_id, seed_val])
                quit(1)
                return

            var slice: Dictionary = builder.build(layout)

            # Must have start_room and goal_room
            var start_room: String = str(slice.get("start_room", ""))
            var goal_room: String = str(slice.get("goal_room", ""))
            if start_room.is_empty():
                push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d missing start_room" % [template_id, seed_val])
                quit(1)
                return
            if goal_room.is_empty():
                push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d missing goal_room" % [template_id, seed_val])
                quit(1)
                return

            # start_room and goal_room must be different
            if start_room == goal_room:
                push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d start==goal '%s'" % [template_id, seed_val, start_room])
                quit(1)
                return

            # Must have at least one objective
            var objectives: Array = slice.get("objectives", [])
            if objectives.is_empty():
                push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d no objectives" % [template_id, seed_val])
                quit(1)
                return

            # Each objective must have id, sequence, type, room_id, approach_cell
            var expected_seq: int = 1
            for obj in objectives:
                if str(obj.get("id", "")).is_empty():
                    push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d objective missing id" % [template_id, seed_val])
                    quit(1)
                    return
                if int(obj.get("sequence", 0)) != expected_seq:
                    push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d objective seq expected=%d got=%d" % [template_id, seed_val, expected_seq, int(obj.get("sequence", 0))])
                    quit(1)
                    return
                expected_seq += 1
                var room_id: String = str(obj.get("room_id", ""))
                if room_id.is_empty():
                    push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d objective missing room_id" % [template_id, seed_val])
                    quit(1)
                    return
                var approach: Array = obj.get("approach_cell", [])
                if approach.size() < 3:
                    push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d objective approach_cell incomplete" % [template_id, seed_val])
                    quit(1)
                    return

            # Must have zone arrays (can be empty)
            for key in ["fire_zones", "arc_zones", "breach_zones"]:
                if typeof(slice.get(key, null)) != TYPE_ARRAY:
                    push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d missing %s array" % [template_id, seed_val, key])
                    quit(1)
                    return

            # start_room and goal_room must exist in layout rooms
            var room_ids: Array[String] = []
            for room in layout.get("rooms", []):
                room_ids.append(str(room.get("id", "")))
            if start_room not in room_ids:
                push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d start_room '%s' not in layout" % [template_id, seed_val, start_room])
                quit(1)
                return
            if goal_room not in room_ids:
                push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d goal_room '%s' not in layout" % [template_id, seed_val, goal_room])
                quit(1)
                return

    print("GAMEPLAY_SLICE_BUILDER PASS all %d layouts produced valid slices" % test_count)
    quit(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/gameplay_slice_builder_smoke.gd
```
Expected: FAIL — `gameplay_slice_builder.gd` does not exist yet.

- [ ] **Step 3: Write the GameplaySliceBuilder implementation**

Create `scripts/procgen/gameplay_slice_builder.gd`:

```gdscript
extends RefCounted
class_name GameplaySliceBuilder

# Builds a gameplay_slice Dictionary from a completed layout Dictionary.
# This populates start/goal rooms, objectives, and empty hazard zone arrays.
#
# The layout pipeline produces structural geometry only.
# This builder adds the gameplay layer on top.

const CONNECTIVE_ROLES: Array[String] = [
    "corridor", "main_spine", "hub", "ramp", "elevator", "airlock", "dock",
]


func build(layout: Dictionary) -> Dictionary:
    var proto: Dictionary = layout.get("prototype", {})
    var rooms: Array = layout.get("rooms", [])

    var start_room: String = str(proto.get("start_room", ""))
    var goal_room: String = str(proto.get("goal_room", ""))

    # Fallback: if prototype doesn't specify start/goal, pick from rooms
    if start_room.is_empty() or goal_room.is_empty():
        var airlock_id: String = ""
        var bridge_id: String = ""
        for room in rooms:
            var role: String = str(room.get("room_role", ""))
            var rid: String = str(room.get("id", ""))
            if role == "airlock" and airlock_id.is_empty():
                airlock_id = rid
            if role == "bridge" and bridge_id.is_empty():
                bridge_id = rid
        if start_room.is_empty():
            start_room = airlock_id if not airlock_id.is_empty() else str(rooms[0].get("id", "")) if rooms.size() > 0 else ""
        if goal_room.is_empty():
            goal_room = bridge_id if not bridge_id.is_empty() else str(rooms[rooms.size() - 1].get("id", "")) if rooms.size() > 0 else ""

    var objectives: Array = []
    var sequence: int = 1

    # Place salvage objectives in non-connective rooms (cargo, engineering, etc.)
    for room in rooms:
        var rid: String = str(room.get("id", ""))
        var role: String = str(room.get("room_role", ""))
        if rid == start_room or rid == goal_room:
            continue
        if role in CONNECTIVE_ROLES:
            continue
        var approach_cell: Array = _get_first_floor_cell(room)
        if approach_cell.is_empty():
            continue
        objectives.append({
            "id": "obj_salvage_%s" % rid,
            "sequence": sequence,
            "type": "salvage",
            "kind": "single",
            "room_id": rid,
            "approach_cell": approach_cell,
        })
        sequence += 1

    # Always add a "reach goal" objective as the final objective
    var goal_room_dict: Dictionary = _find_room(rooms, goal_room)
    var goal_approach: Array = _get_first_floor_cell(goal_room_dict)
    if goal_approach.is_empty():
        goal_approach = [0, 0, 0]
    objectives.append({
        "id": "obj_reach_goal",
        "sequence": sequence,
        "type": "interact",
        "kind": "single",
        "room_id": goal_room,
        "approach_cell": goal_approach,
    })

    return {
        "start_room": start_room,
        "goal_room": goal_room,
        "objectives": objectives,
        "fire_zones": [],
        "arc_zones": [],
        "breach_zones": [],
    }


func _find_room(rooms: Array, room_id: String) -> Dictionary:
    for room in rooms:
        if str(room.get("id", "")) == room_id:
            return room
    return {}


func _get_first_floor_cell(room: Dictionary) -> Array:
    var placements: Array = room.get("structural_placements", [])
    for placement in placements:
        var name: String = str(placement.get("name", ""))
        if not name.begins_with("floor_cell"):
            continue
        # Parse floor_cell_x{X}_z{Z} or floor_cell_d{D}_x{X}_z{Z}
        var parts: PackedStringArray = name.split("_")
        for i in range(parts.size()):
            if String(parts[i]).begins_with("x") and i + 1 < parts.size() and String(parts[i + 1]).begins_with("z"):
                var x_str: String = String(parts[i]).substr(1)
                var z_str: String = String(parts[i + 1]).substr(1)
                if x_str.is_valid_int() and z_str.is_valid_int():
                    var deck: int = int(room.get("deck", 0))
                    return [int(x_str), int(z_str), deck]
    return []
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/gameplay_slice_builder_smoke.gd
```
Expected: `GAMEPLAY_SLICE_BUILDER PASS all 9 layouts produced valid slices`

- [ ] **Step 5: Wire GameplaySliceBuilder into ShipGenerator**

Modify `scripts/procgen/ship_generator.gd` to replace the inline gameplay slice construction (lines 73-87) with a call to `GameplaySliceBuilder.build()`:

Replace the gameplay slice section in `_load_layout_as_scene()`:
```gdscript
# Before (inline):
var proto: Dictionary = layout.get("prototype", {})
var gameplay: Dictionary = {
    "start_room": str(proto.get("start_room", "")),
    ...
}

# After (using builder):
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
var gameplay_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()
var gameplay: Dictionary = gameplay_builder.build(layout)
```

- [ ] **Step 6: Run existing ship_generator_smoke to verify no regression**

Run:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/ship_generator_smoke.gd
```
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add scripts/procgen/gameplay_slice_builder.gd scripts/validation/gameplay_slice_builder_smoke.gd scripts/procgen/ship_generator.gd
git commit -m "feat(procgen): add GameplaySliceBuilder — extracts gameplay slice from layout"
```

---

## Task 2: Update LifeBoatBuilder for Layout Compatibility

**Files:**
- Modify: `scripts/procgen/life_boat.gd`
- Create: `scripts/validation/life_boat_layout_smoke.gd`

**Interfaces:**
- Consumes: nothing (fixed layout)
- Produces: `LifeBoatBuilder.build_layout() -> Dictionary` returning a layout.json-compatible Dict with 3 rooms (airlock, cockpit, engine_bay), structural_placements, room_links, and prototype

**Context:** The current `LifeBoatBuilder.build()` returns a `Node3D` by directly instantiating structural wrapper scenes. It bypasses the layout pipeline entirely. For the start scenario to work with `GeneratedShipLoader` (which loads from layout.json + gameplay_slice.json), the life boat needs a `build_layout()` method that returns a layout Dictionary in the same format as `ShipLayoutGenerator.generate()`. The existing `build()` method can remain for backward compatibility but should call `build_layout()` internally.

- [ ] **Step 1: Write the failing test**

Create `scripts/validation/life_boat_layout_smoke.gd`:

```gdscript
extends SceneTree

const LifeBoatScript := preload("res://scripts/procgen/life_boat.gd")

func _initialize() -> void:
    var builder: LifeBoatScript = LifeBoatScript.new()
    var layout: Dictionary = builder.build_layout()

    # Must have rooms array with exactly 3 rooms
    var rooms: Array = layout.get("rooms", [])
    if rooms.size() != 3:
        push_error("LIFE_BOAT_LAYOUT FAIL expected 3 rooms, got %d" % rooms.size())
        quit(1)
        return

    # Check expected roles
    var roles: Array[String] = []
    for room in rooms:
        roles.append(str(room.get("room_role", "")))
    var expected_roles: Array[String] = ["airlock", "bridge", "engineering"]
    for role in expected_roles:
        if role not in roles:
            push_error("LIFE_BOAT_LAYOUT FAIL missing role '%s', got %s" % [role, str(roles)])
            quit(1)
            return

    # Each room must have structural_placements
    for room in rooms:
        var placements: Array = room.get("structural_placements", [])
        if placements.is_empty():
            push_error("LIFE_BOAT_LAYOUT FAIL room '%s' has no structural_placements" % str(room.get("id", "")))
            quit(1)
            return
        # Each placement must have position array with 3 elements
        for p in placements:
            var pos: Variant = p.get("position", null)
            if not (pos is Array) or pos.size() < 3:
                push_error("LIFE_BOAT_LAYOUT FAIL bad position in room '%s'" % str(room.get("id", "")))
                quit(1)
                return

    # Must have room_links connecting all 3 rooms
    var links: Array = layout.get("room_links", [])
    if links.size() < 2:
        push_error("LIFE_BOAT_LAYOUT FAIL expected >=2 room_links, got %d" % links.size())
        quit(1)
        return

    # Must have prototype with start_room and goal_room
    var proto: Dictionary = layout.get("prototype", {})
    if str(proto.get("start_room", "")).is_empty():
        push_error("LIFE_BOAT_LAYOUT FAIL missing prototype.start_room")
        quit(1)
        return
    if str(proto.get("goal_room", "")).is_empty():
        push_error("LIFE_BOAT_LAYOUT FAIL missing prototype.goal_room")
        quit(1)
        return

    # Must have schema_version
    if str(layout.get("schema_version", "")).is_empty():
        push_error("LIFE_BOAT_LAYOUT FAIL missing schema_version")
        quit(1)
        return

    print("LIFE_BOAT_LAYOUT PASS 3 rooms, %d links, %d placements total" % [
        links.size(),
        rooms.reduce(func(acc, r): return acc + r.get("structural_placements", []).size(), 0)
    ])
    quit(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/life_boat_layout_smoke.gd
```
Expected: FAIL — `build_layout()` method does not exist.

- [ ] **Step 3: Add build_layout() to LifeBoatBuilder**

Modify `scripts/procgen/life_boat.gd` to add `build_layout() -> Dictionary`. This method produces a layout Dictionary matching the schema from `LayoutSerializer` output. The life boat is a fixed linear chain: `airlock_01 -> cockpit_01 -> engine_bay_01`. Each room is 1 cell (4x4m). The chain runs bow (+X) to stern (-X): cockpit at bow, airlock mid, engine_bay at stern.

Key implementation details:
- 3 rooms in a line along the X axis, each 1 cell
- Room IDs: `airlock_01`, `cockpit_01`, `engine_bay_01`
- Roles: `airlock`, `bridge`, `engineering`
- `structural_placements`: floor + walls for each cell, using the same module IDs as LayoutSerializer (`floor_1x1`, `wall_1x1`, `door_1x1`)
- `room_links`: airlock<->cockpit, airlock<->engine_bay (airlock is the central connector)
- `prototype`: start_room = `airlock_01`, goal_room = `cockpit_01`
- `schema_version`: "1.1.0" (matching LayoutSerializer)

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/life_boat_layout_smoke.gd
```
Expected: `LIFE_BOAT_LAYOUT PASS 3 rooms, 2 links, N placements total`

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/life_boat.gd scripts/validation/life_boat_layout_smoke.gd
git commit -m "feat(procgen): add LifeBoatBuilder.build_layout() for layout-compatible output"
```

---

## Task 3: Update StartSceneBuilder to Use Layout Pipeline

**Files:**
- Modify: `scripts/procgen/start_scene_builder.gd`
- Create: `scripts/validation/start_scenario_smoke.gd`

**Interfaces:**
- Consumes: `ShipGenerator.generate_layout()`, `LifeBoatBuilder.build_layout()`, `GameplaySliceBuilder.build()`, `GeneratedShipLoader.load_from_paths()`
- Produces: `StartSceneBuilder.build(seed_value: int) -> Node3D` returning a scene with the derelict + life boat loaded and positioned, connected at dock

**Context:** The current `StartSceneBuilder` (113 lines) calls `ShipGenerator.generate()` which returns a Node3D scene. It separately calls `LifeBoatBuilder.build()` which also returns a Node3D. The two are positioned side by side. The problem: the life boat doesn't go through the layout pipeline, so it doesn't get proper navigation mesh, doorways, or structural geometry from `GeneratedShipLoader`. 

The updated flow:
1. Generate derelict layout via `ShipLayoutGenerator.generate()`
2. Generate life boat layout via `LifeBoatBuilder.build_layout()`
3. Build gameplay slices for both via `GameplaySliceBuilder.build()`
4. Write both layout+gameplay pairs to temp files
5. Load both via `GeneratedShipLoader.load_from_paths()`
6. Position life boat adjacent to derelict's dock room

- [ ] **Step 1: Write the end-to-end smoke test**

Create `scripts/validation/start_scenario_smoke.gd`. This test generates the full start scenario and validates:
1. Both derelict and life boat load without errors
2. The derelict has rooms with structural placements
3. The life boat has exactly 3 rooms
4. Navigation mesh can be baked from floor cells
5. A NavigationAgent3D can find a path from start to goal within the derelict

```gdscript
extends SceneTree

const StartSceneBuilderScript := preload("res://scripts/procgen/start_scene_builder.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")

const CELL_SIZE: float = 4.0
const FLOOR_Y_OFFSET: float = 0.12
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]

func _initialize() -> void:
    # Test 1: Derelict layout generation through pipeline
    var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
    var slice_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()

    var archetype_path: String = "res://data/procgen/archetypes/derelict.json"
    var archetype_text: String = FileAccess.get_file_as_string(archetype_path)
    var archetype: Variant = JSON.parse_string(archetype_text)
    if typeof(archetype) != TYPE_DICTIONARY:
        push_error("START_SCENARIO FAIL cannot load derelict archetype")
        quit(1)
        return

    var bp: ShipBlueprintScript = ShipBlueprintScript.new(
        ShipBlueprintScript.Size.MEDIUM,
        ShipBlueprintScript.Condition.WRECKED,
        42)
    var layout: Dictionary = generator.generate(bp, archetype)
    if layout.is_empty():
        push_error("START_SCENARIO FAIL derelict layout empty")
        quit(1)
        return

    var rooms: Array = layout.get("rooms", [])
    if rooms.size() < 3:
        push_error("START_SCENARIO FAIL derelict has only %d rooms" % rooms.size())
        quit(1)
        return

    # Verify all rooms have structural placements
    for room in rooms:
        var placements: Array = room.get("structural_placements", [])
        if placements.is_empty():
            push_error("START_SCENARIO FAIL room '%s' has no placements" % str(room.get("id", "")))
            quit(1)
            return

    # Test 2: Gameplay slice builds from layout
    var gameplay: Dictionary = slice_builder.build(layout)
    if str(gameplay.get("start_room", "")).is_empty():
        push_error("START_SCENARIO FAIL gameplay slice missing start_room")
        quit(1)
        return
    if str(gameplay.get("goal_room", "")).is_empty():
        push_error("START_SCENARIO FAIL gameplay slice missing goal_room")
        quit(1)
        return
    if gameplay.get("objectives", []).is_empty():
        push_error("START_SCENARIO FAIL gameplay slice has no objectives")
        quit(1)
        return

    # Test 3: Layout can be loaded by GeneratedShipLoader
    var temp_dir: String = "user://start_scenario_smoke_temp"
    if not DirAccess.dir_exists_absolute(temp_dir):
        DirAccess.make_dir_absolute(temp_dir)

    var layout_path: String = temp_dir + "/layout.json"
    var gameplay_path: String = temp_dir + "/gameplay_slice.json"
    var kit_path: String = "res://data/ship_structural_v0_kit.json"

    var lf: FileAccess = FileAccess.open(layout_path, FileAccess.WRITE)
    lf.store_string(JSON.stringify(layout, "  "))
    lf.close()
    var gf: FileAccess = FileAccess.open(gameplay_path, FileAccess.WRITE)
    gf.store_string(JSON.stringify(gameplay, "  "))
    gf.close()

    var LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
    var loader: Node3D = LoaderScript.new()
    var success: bool = loader.load_from_paths(layout_path, kit_path, gameplay_path)
    if not success:
        push_error("START_SCENARIO FAIL GeneratedShipLoader.load_from_paths returned false")
        quit(1)
        return

    # Test 4: Navigation mesh can be baked from floor cells
    var floor_count: int = 0
    for room in rooms:
        for placement in room.get("structural_placements", []):
            var module_id: String = str(placement.get("module_id", placement.get("module", "")))
            if module_id in FLOOR_MODULES:
                floor_count += 1
    if floor_count < 3:
        push_error("START_SCENARIO FAIL only %d floor cells, need >=3" % floor_count)
        quit(1)
        return

    var nav_source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
    for room in rooms:
        for placement in room.get("structural_placements", []):
            var module_id: String = str(placement.get("module_id", placement.get("module", "")))
            if module_id not in FLOOR_MODULES:
                continue
            var pos: Array = placement.get("position", [0, 0, 0])
            if pos.size() < 3:
                continue
            var center: Vector3 = Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
            var half: float = CELL_SIZE * 0.5
            nav_source.add_faces(PackedVector3Array([
                center + Vector3(-half, 0, -half),
                center + Vector3(half, 0, -half),
                center + Vector3(half, 0, half),
                center + Vector3(-half, 0, -half),
                center + Vector3(half, 0, half),
                center + Vector3(-half, 0, half),
            ]), Transform3D())

    var nav_mesh: NavigationMesh = NavigationMesh.new()
    NavigationMeshGenerator.bake_from_source_geometry_data(nav_mesh, nav_source)
    if nav_mesh.get_polygon_count() == 0:
        push_error("START_SCENARIO FAIL nav mesh baked 0 polygons from %d floor cells" % floor_count)
        quit(1)
        return

    # Test 5: Life boat layout generation
    var LifeBoatScript := preload("res://scripts/procgen/life_boat.gd")
    var lb_builder: LifeBoatScript = LifeBoatScript.new()
    var lb_layout: Dictionary = lb_builder.build_layout()
    var lb_rooms: Array = lb_layout.get("rooms", [])
    if lb_rooms.size() != 3:
        push_error("START_SCENARIO FAIL life boat expected 3 rooms, got %d" % lb_rooms.size())
        quit(1)
        return

    # Clean up temp files
    DirAccess.remove_absolute(layout_path)
    DirAccess.remove_absolute(gameplay_path)

    print("START_SCENARIO PASS derelict=%d_rooms life_boat=3_rooms floor_cells=%d nav_polys=%d objectives=%d" % [
        rooms.size(), floor_count, nav_mesh.get_polygon_count(), gameplay.get("objectives", []).size()
    ])
    quit(0)
```

- [ ] **Step 2: Run the test to verify it fails (or identify baseline)**

Run:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/start_scenario_smoke.gd
```
Expected: May pass partially — the layout pipeline already works. The `build_layout()` call will fail if Task 2 is not yet complete. Execute Tasks 1 and 2 first.

- [ ] **Step 3: Update StartSceneBuilder to use layout pipeline**

Modify `scripts/procgen/start_scene_builder.gd` to:
1. Generate derelict layout via `ShipLayoutGenerator.generate()`
2. Generate life boat layout via `LifeBoatBuilder.build_layout()`
3. Build gameplay slices for both via `GameplaySliceBuilder.build()`
4. Write layout+gameplay pairs to temp files under `user://start_scenario/`
5. Load both via `GeneratedShipLoader.load_from_paths()`
6. Position life boat adjacent to derelict's dock room (find dock room in derelict layout, offset life boat by 6.0 units laterally)
7. Return the combined scene root

Key changes from current implementation:
- Replace `ShipGenerator.generate()` call with `ShipLayoutGenerator.generate()` + file write + `GeneratedShipLoader.load_from_paths()`
- Replace `LifeBoatBuilder.build()` with `LifeBoatBuilder.build_layout()` + same load pattern
- Keep the dock positioning logic (find dock room origin, offset life boat)

The derelict archetype is loaded from `res://data/procgen/archetypes/derelict.json` — check it has `"template"` field for the layout pipeline.

- [ ] **Step 4: Run start_scenario_smoke to verify**

Run:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/start_scenario_smoke.gd
```
Expected: `START_SCENARIO PASS ...`

- [ ] **Step 5: Run existing smoke tests for regression**

Run all relevant existing smokes:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/ship_generator_smoke.gd
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/ship_layout_generator_smoke.gd
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/ship_layout_integration_smoke.gd
```
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/start_scene_builder.gd scripts/validation/start_scenario_smoke.gd
git commit -m "feat(procgen): wire start scenario through layout pipeline"
```

---

## Task 4: End-to-End Walkability Validation

**Files:**
- Create: `scripts/validation/procgen_walkability_smoke.gd`

**Interfaces:**
- Consumes: `ShipLayoutGenerator.generate()`, `GameplaySliceBuilder.build()`, navigation mesh baking, `NavigationAgent3D` pathfinding
- Produces: A smoke test that proves Phase 1 completion criteria: "rooms connect, geometry loads, player can walk through"

**Context:** The existing `procgen_ship_walkthrough_smoke.gd` requires pre-generated layout+kit files passed as CLI args. This new test generates a layout from seed, builds the gameplay slice, bakes a nav mesh from floor cells, and walks a NavigationAgent3D from start room to each objective room to the goal room — all in one self-contained headless script. This is the definitive Phase 1 gate test.

- [ ] **Step 1: Write the walkability smoke test**

Create `scripts/validation/procgen_walkability_smoke.gd`:

```gdscript
extends SceneTree

# End-to-end walkability smoke: generates ship from seed, bakes nav mesh,
# walks NavigationAgent3D from start through objectives to goal.
# This validates Phase 1: "rooms connect, geometry loads, player can walk through."

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")

const CELL_SIZE: float = 4.0
const FLOOR_Y_OFFSET: float = 0.12
const WALK_SPEED: float = 6.0
const TIMEOUT_FRAMES: int = 1500
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]


class PathWalker:
    extends Node3D

    var agent: NavigationAgent3D
    var waypoints: Array[Vector3] = []
    var current_waypoint: int = 0
    var walk_speed: float = WALK_SPEED
    var timeout_frames: int = TIMEOUT_FRAMES
    var frame_count: int = 0
    var finished: bool = false
    var seed_label: String = ""

    func _ready() -> void:
        set_physics_process(true)

    func _physics_process(delta: float) -> void:
        if finished:
            return
        frame_count += 1
        if frame_count < 2:
            return
        if agent == null:
            _fail("no-agent")
            return

        if current_waypoint >= waypoints.size():
            finished = true
            print("WALKABILITY PASS %s frames=%d waypoints=%d" % [seed_label, frame_count, waypoints.size()])
            get_tree().quit(0)
            return

        var target: Vector3 = waypoints[current_waypoint]
        var dist: float = global_position.distance_to(target)
        if dist <= 1.0:
            current_waypoint += 1
            if current_waypoint < waypoints.size():
                agent.target_position = waypoints[current_waypoint]
            return

        var next_pos: Vector3 = agent.get_next_path_position()
        var step: Vector3 = next_pos - global_position
        if step.length_squared() > 0.000001:
            global_position = global_position.move_toward(next_pos, walk_speed * delta)

        if frame_count >= timeout_frames:
            _fail("timeout at waypoint %d/%d dist=%.2f" % [current_waypoint, waypoints.size(), dist])

    func _fail(reason: String) -> void:
        finished = true
        push_error("WALKABILITY FAIL %s frames=%d waypoint=%d/%d reason=%s" % [
            seed_label, frame_count, current_waypoint, waypoints.size(), reason])
        get_tree().quit(1)


func _initialize() -> void:
    var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
    var slice_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()

    var templates: Array[String] = ["spine", "bifurcated", "stacked"]
    var seeds: Array[int] = [42, 999]

    # Test one combination to keep the smoke fast
    var template_id: String = templates[0]
    var seed_val: int = seeds[0]
    var label: String = "%s_seed_%d" % [template_id, seed_val]

    var bp: ShipBlueprintScript = ShipBlueprintScript.new(
        ShipBlueprintScript.Size.MEDIUM,
        ShipBlueprintScript.Condition.PRISTINE,
        seed_val)
    var layout: Dictionary = generator.generate(bp, {"template": template_id})
    if layout.is_empty():
        push_error("WALKABILITY FAIL %s layout empty" % label)
        quit(1)
        return

    var rooms: Array = layout.get("rooms", [])
    var gameplay: Dictionary = slice_builder.build(layout)
    var start_room_id: String = str(gameplay.get("start_room", ""))
    var goal_room_id: String = str(gameplay.get("goal_room", ""))

    if start_room_id.is_empty() or goal_room_id.is_empty():
        push_error("WALKABILITY FAIL %s missing start/goal room" % label)
        quit(1)
        return

    # Build waypoints: start center -> each objective -> goal center
    var waypoints: Array[Vector3] = []
    for obj in gameplay.get("objectives", []):
        var room_id: String = str(obj.get("room_id", ""))
        var center: Vector3 = _room_center(rooms, room_id)
        if center != Vector3.INF:
            waypoints.append(center)

    if waypoints.is_empty():
        push_error("WALKABILITY FAIL %s no walkable waypoints" % label)
        quit(1)
        return

    var start_center: Vector3 = _room_center(rooms, start_room_id)
    if start_center == Vector3.INF:
        push_error("WALKABILITY FAIL %s start room center not found" % label)
        quit(1)
        return

    # Build nav mesh from floor cells
    var tree_root: Node = get_root()
    var ship_root: Node3D = Node3D.new()
    ship_root.name = "WalkabilityTestShip"
    tree_root.add_child(ship_root)

    var nav_region: NavigationRegion3D = _build_navigation_region(rooms, ship_root)
    if nav_region == null:
        push_error("WALKABILITY FAIL %s could not build nav mesh" % label)
        quit(1)
        return

    # Add vertical links if any
    _add_vertical_links(layout, ship_root)

    # Spawn walker at start
    var walker: PathWalker = PathWalker.new()
    walker.name = "PathWalker"
    walker.position = start_center
    walker.waypoints = waypoints
    walker.seed_label = label
    walker.timeout_frames = TIMEOUT_FRAMES
    walker.walk_speed = WALK_SPEED
    ship_root.add_child(walker)

    var agent: NavigationAgent3D = NavigationAgent3D.new()
    agent.name = "NavigationAgent3D"
    agent.path_desired_distance = 0.35
    agent.target_desired_distance = 1.0
    agent.target_position = waypoints[0]
    walker.agent = agent
    walker.add_child(agent)

    print("WALKABILITY start room=%s goal=%s waypoints=%d" % [start_room_id, goal_room_id, waypoints.size()])


func _room_center(rooms: Array, room_id: String) -> Vector3:
    for room in rooms:
        if str(room.get("id", "")) != room_id:
            continue
        var total: Vector3 = Vector3.ZERO
        var count: int = 0
        for placement in room.get("structural_placements", []):
            var module_id: String = str(placement.get("module_id", placement.get("module", "")))
            if module_id not in FLOOR_MODULES:
                continue
            var pos: Array = placement.get("position", [0, 0, 0])
            if pos.size() < 3:
                continue
            total += Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
            count += 1
        if count == 0:
            return Vector3.INF
        return total / float(count)
    return Vector3.INF


func _build_navigation_region(rooms: Array, ship_root: Node3D) -> NavigationRegion3D:
    var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
    var floor_count: int = 0
    for room in rooms:
        for placement in room.get("structural_placements", []):
            var module_id: String = str(placement.get("module_id", placement.get("module", "")))
            if module_id not in FLOOR_MODULES:
                continue
            var pos: Array = placement.get("position", [0, 0, 0])
            if pos.size() < 3:
                continue
            var center: Vector3 = Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
            var half: float = CELL_SIZE * 0.5
            source.add_faces(PackedVector3Array([
                center + Vector3(-half, 0, -half),
                center + Vector3(half, 0, -half),
                center + Vector3(half, 0, half),
                center + Vector3(-half, 0, -half),
                center + Vector3(half, 0, half),
                center + Vector3(-half, 0, half),
            ]), Transform3D())
            floor_count += 1

    if floor_count == 0:
        push_error("WALKABILITY FAIL 0 floor cells")
        return null

    var nav_mesh: NavigationMesh = NavigationMesh.new()
    NavigationMeshGenerator.bake_from_source_geometry_data(nav_mesh, source)

    var nav_region: NavigationRegion3D = NavigationRegion3D.new()
    nav_region.name = "WalkabilityNavRegion"
    nav_region.navigation_mesh = nav_mesh
    ship_root.add_child(nav_region)
    print("Nav mesh: %d floor cells -> %d polygons" % [floor_count, nav_mesh.get_polygon_count()])
    return nav_region


func _add_vertical_links(layout: Dictionary, ship_root: Node3D) -> void:
    var links: Array = layout.get("vertical_connections", [])
    for link in links:
        if typeof(link) != TYPE_DICTIONARY:
            continue
        var from_pos: Vector3 = _link_endpoint_pos(link, "from_cell", "from_room", layout)
        var to_pos: Vector3 = _link_endpoint_pos(link, "to_cell", "to_room", layout)
        if from_pos == Vector3.INF or to_pos == Vector3.INF:
            continue
        var nav_link: NavigationLink3D = NavigationLink3D.new()
        nav_link.bidirectional = true
        nav_link.start_position = from_pos
        nav_link.end_position = to_pos
        ship_root.add_child(nav_link)


func _link_endpoint_pos(link: Dictionary, cell_key: String, room_key: String, layout: Dictionary) -> Vector3:
    var cell: Array = link.get(cell_key, [])
    var room_id: String = str(link.get(room_key, ""))
    if cell.size() < 2 or room_id.is_empty():
        return Vector3.INF
    for room in layout.get("rooms", []):
        if str(room.get("id", "")) != room_id:
            continue
        for placement in room.get("structural_placements", []):
            var module_id: String = str(placement.get("module_id", placement.get("module", "")))
            if module_id not in FLOOR_MODULES:
                continue
            var name: String = str(placement.get("name", ""))
            # Match cell coordinates in placement name
            var target_x: int = int(cell[0])
            var target_z: int = int(cell[1])
            var target_deck: int = int(cell[2]) if cell.size() >= 3 else 0
            var parts: PackedStringArray = name.split("_")
            for i in range(parts.size()):
                if String(parts[i]).begins_with("x") and i + 1 < parts.size() and String(parts[i + 1]).begins_with("z"):
                    var x_str: String = String(parts[i]).substr(1)
                    var z_str: String = String(parts[i + 1]).substr(1)
                    if x_str.is_valid_int() and z_str.is_valid_int():
                        if int(x_str) == target_x and int(z_str) == target_z:
                            var pos: Array = placement.get("position", [0, 0, 0])
                            return Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
    return Vector3.INF
```

- [ ] **Step 2: Run the walkability smoke test**

Run:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/procgen_walkability_smoke.gd
```
Expected: `WALKABILITY PASS spine_seed_42 frames=N waypoints=M`

If it fails, debug: check which waypoint the walker can't reach, verify floor cells are contiguous, check nav mesh polygon count.

- [ ] **Step 3: Run the full regression suite**

Run all existing procgen smokes to verify nothing broke:
```bash
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/ship_layout_generator_smoke.gd
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/ship_layout_integration_smoke.gd
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/ship_generator_smoke.gd
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/gameplay_slice_builder_smoke.gd
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/life_boat_layout_smoke.gd
"C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea" --script res://scripts/validation/start_scenario_smoke.gd
```
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add scripts/validation/procgen_walkability_smoke.gd
git commit -m "test(procgen): add end-to-end walkability smoke — Phase 1 gate test"
```

---

## Completion Criteria

Phase 1 is done when all four of these pass:

1. `gameplay_slice_builder_smoke.gd` — PASS (gameplay slice generation works)
2. `life_boat_layout_smoke.gd` — PASS (life boat produces layout-compatible output)
3. `start_scenario_smoke.gd` — PASS (derelict + life boat load and nav mesh bakes)
4. `procgen_walkability_smoke.gd` — PASS (NavigationAgent3D walks start -> objectives -> goal)

These validate the spec's Phase 1 exit criteria: "Generate life raft + one derelict type. Validate: rooms connect, geometry loads, player can walk through."
