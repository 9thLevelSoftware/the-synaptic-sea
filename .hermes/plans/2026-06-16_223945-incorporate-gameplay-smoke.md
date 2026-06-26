# In-Game Procgen Gameplay Smoke Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Turn the current headless procgen gameplay-smoke validation into a visible, in-engine Godot prototype that can be launched from the actual game scene, not merely viewed through an HTML proof.
**Architecture:** Keep the existing headless validation scripts as tests, but extract their useful behavior into runtime Godot scripts: a generated-ship loader, objective-volume spawner, debug runner/player, and simple objective tracker UI. The main game scene will load a deterministic seed-17 demo fixture by default for now, while validation scripts will launch the same runtime scene headlessly to prove that the visible in-game path and the smoke test are exercising the same code.
**Tech Stack:** Godot 4.6.2 GDScript, existing `ship_structural_v0` wrapper scenes, generated `layout.json` / `gameplay_slice.json`, Python/pytest validation in `/Users/christopherwilloughby/off-the-rails-ai-infra`.

---

## Current Context / Honest Baseline

The current state is real validation, not real playable game UI:

- Real today:
  - `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_ship_gameplay_smoke.gd` loads `layout.json`, kit JSON, and `gameplay_slice.json`.
  - It instantiates structural wrappers in Godot.
  - It bakes a navmesh from generated floor/corridor cells.
  - It adds vertical `NavigationLink3D` records.
  - It spawns debug `Area3D` interaction volumes.
  - It drives a scripted `NavigationAgent3D` through all objectives and goal.
  - Fresh evidence: `GAMEPLAY SMOKE PASS objectives=4 interactions=4 frames=4318 final_distance=0.766`.
- Not real in the playable game yet:
  - `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/main.tscn` only has a root, camera, and light.
  - `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd` only prints a bootstrap message.
  - No runtime ship loader is used by `main.tscn`.
  - No visible player/debug actor exists in the normal game scene.
  - No in-game objective tracker exists.
  - No player input or interaction prompt exists.
- HTML proof caveat:
  - `/tmp/procgen_gameplay_smoke_seen/gameplay_smoke_actual_corridor_route.html` is useful, but it is a visualization artifact derived from validation data. It is not an in-engine gameplay view.

## Acceptance Criteria

This plan is complete only when all criteria below are true:

1. Running the Godot main scene displays the generated ship prototype in the actual viewport.
2. The visible scene contains a clear placeholder runner/player, objective markers, and basic objective status text.
3. The visible runner follows real Godot navigation through generated corridors/cells, including vertical links where present.
4. Objective volumes are actual Godot nodes in the runtime scene, not only validation-script locals.
5. The same runtime loader/controller are used by both:
   - the playable/demo main scene, and
   - a headless validation script.
6. A headless runtime smoke proves the in-game demo reaches all objectives and goal.
7. A screenshot or viewport-capture proof is produced from Godot itself, not from HTML.
8. Existing `procgen_ship_gameplay_smoke.gd` and `procgen_ship_walkthrough_smoke.gd` stay backward-compatible until the runtime smoke fully supersedes them.

## Non-Goals

Do not do these in this implementation pass:

- Do not add production art.
- Do not implement inventory, combat, save/load, or mission narrative systems.
- Do not rewrite the procgen topology solver.
- Do not replace the existing validation smoke until the runtime demo is proven.
- Do not add complex input remapping or character animation.
- Do not make the demo generic for every future mission type; support the current generated gameplay slice first.

## Repositories / Workspaces

Primary Godot project:

- `/Users/christopherwilloughby/the-synaptic-sea-of-stars`

Procgen / tests / bundle project:

- `/Users/christopherwilloughby/off-the-rails-ai-infra`

The implementation crosses both. Save Godot runtime code in the Godot project; save pytest integration tests and optional bundle export helpers in the infra project.

---

## Proposed Runtime Architecture

```text
main.tscn
  Main (scripts/main.gd)
    GeneratedShipDemo (scenes/procgen/generated_ship_demo.tscn)
      GeneratedShipLoader (scripts/procgen/generated_ship_loader.gd)
        StructuralRoot
        GameplayObjectiveRoot
          GameplayObjectiveVolume x N
        NavigationRegion3D
        NavigationLink3D x N
      ProcgenDebugRunner (scripts/procgen/procgen_debug_runner.gd)
        NavigationAgent3D
        visible capsule/marker mesh
      ObjectiveTracker UI (scripts/ui/objective_tracker.gd)
```

Data flow:

```text
res://data/procgen/smoke/seed_000017/layout.json
res://data/procgen/smoke/seed_000017/gameplay_slice.json
res://data/kits/ship_structural_v0.json
      ↓
GeneratedShipLoader
      ↓
Node3D structure + objective specs + start/goal positions
      ↓
ProcgenDebugRunner auto-runs objective route
      ↓
ObjectiveTracker updates visible status
      ↓
Runtime validation script proves same path headlessly
```

---

## Files Likely To Change

Godot project:

- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/gameplay_objective_volume.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/procgen_debug_runner.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_demo.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/ui/objective_tracker.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/procgen/generated_ship_demo.tscn`
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd`
- Optional modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/main.tscn`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_runtime_demo_smoke.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_runtime_demo_capture.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/data/kits/ship_structural_v0.json`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/layout.json`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/gameplay_slice.json`

Infra project:

- Create: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`
- Optional create: `/Users/christopherwilloughby/off-the-rails-ai-infra/tools/export_ship_runtime_demo_fixture.py`
- Optional modify: `/Users/christopherwilloughby/off-the-rails-ai-infra/tools/build_ship_prototype_bundle.py` only if fixture export should become a first-class bundle flag.

---

# Implementation Tasks

## Task 1: Add a red test for the runtime demo contract

**Objective:** Establish a failing integration test that defines the desired in-game runtime behavior before any runtime implementation.

**Files:**

- Create: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`
- Expected missing for RED: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_runtime_demo_smoke.gd`

**Step 1: Write failing test**

Create this test file:

```python
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

GODOT = Path("/Users/christopherwilloughby/.local/bin/godot-4.6.2")
GODOT_PROJECT = Path("/Users/christopherwilloughby/the-synaptic-sea-of-stars")
SCRIPT = GODOT_PROJECT / "scripts" / "validation" / "procgen_runtime_demo_smoke.gd"


def test_runtime_demo_smoke_script_exists() -> None:
    assert SCRIPT.exists()


def test_runtime_demo_smoke_mentions_real_runtime_scene() -> None:
    script = SCRIPT.read_text(encoding="utf-8")

    assert "generated_ship_demo.tscn" in script
    assert "RUNTIME GAMEPLAY DEMO PASS" in script
    assert "objective_completed" in script


def test_runtime_demo_smoke_runs_if_godot_available() -> None:
    if not GODOT.exists():
        pytest.skip(f"Godot binary not found: {GODOT}")

    proc = subprocess.run(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(GODOT_PROJECT),
            "--script",
            "res://scripts/validation/procgen_runtime_demo_smoke.gd",
            "--",
            "--timeout-frames",
            "9000",
        ],
        cwd=GODOT_PROJECT,
        text=True,
        capture_output=True,
        timeout=180,
    )

    combined = proc.stdout + proc.stderr
    assert proc.returncode == 0, combined
    assert "RUNTIME GAMEPLAY DEMO PASS" in combined
    assert "objectives=4" in combined
    assert "interactions=4" in combined
```

**Step 2: Run test to verify failure**

Run from infra repo:

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py -q
```

Expected: FAIL because `procgen_runtime_demo_smoke.gd` does not exist yet.

**Step 3: Commit**

If the workspace is a git repository:

```bash
git add tests/test_godot_procgen_runtime_demo.py
git commit -m "test: define procgen runtime gameplay demo smoke"
```

If not a git repository, record the diff path in the implementation notes and continue.

---

## Task 2: Add deterministic runtime fixture data to the Godot project

**Objective:** Make the demo launchable from the Godot project without depending on `/tmp` paths or an HTML artifact.

**Files:**

- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/data/kits/ship_structural_v0.json`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/layout.json`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/gameplay_slice.json`

**Step 1: Write failing fixture existence test**

Add this to `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`:

```python

def test_runtime_demo_fixture_data_exists() -> None:
    assert (GODOT_PROJECT / "data" / "kits" / "ship_structural_v0.json").exists()
    assert (GODOT_PROJECT / "data" / "procgen" / "smoke" / "seed_000017" / "layout.json").exists()
    assert (GODOT_PROJECT / "data" / "procgen" / "smoke" / "seed_000017" / "gameplay_slice.json").exists()
```

**Step 2: Run test to verify failure**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_runtime_demo_fixture_data_exists -q
```

Expected: FAIL until the fixture files are copied/generated.

**Step 3: Generate/copy the fixture data**

Use the already proven bundle command as the source of truth:

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
rm -rf /tmp/synaptic_sea_runtime_demo_fixture
python3 tools/build_ship_prototype_bundle.py \
  --seed 17 \
  --room-count 8 \
  --deck-count 2 \
  --vertical-transition-count 1 \
  --output-root /tmp/synaptic_sea_runtime_demo_fixture \
  --skip-render \
  --gameplay-smoke

mkdir -p /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/kits
mkdir -p /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017
cp data/kits/ship_structural_v0.json \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/kits/ship_structural_v0.json
cp /tmp/synaptic_sea_runtime_demo_fixture/seed_000017/layout.json \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/layout.json
cp /tmp/synaptic_sea_runtime_demo_fixture/seed_000017/gameplay_slice.json \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/gameplay_slice.json
```

Expected: bundle exit 0 and three fixture files copied.

**Step 4: Run fixture test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_runtime_demo_fixture_data_exists -q
```

Expected: PASS.

**Step 5: Commit**

```bash
git add \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/kits/ship_structural_v0.json \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/layout.json \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/gameplay_slice.json \
  /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py
git commit -m "test: add runtime procgen demo fixture"
```

---

## Task 3: Create runtime objective volume script

**Objective:** Represent each generated objective as a reusable in-game `Area3D`, not as a validation-script-only node.

**Files:**

- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/gameplay_objective_volume.gd`
- Test: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Add failing text-level test**

Add:

```python

def test_runtime_objective_volume_script_declares_area_metadata() -> None:
    script_path = GODOT_PROJECT / "scripts" / "procgen" / "gameplay_objective_volume.gd"
    assert script_path.exists()
    script = script_path.read_text(encoding="utf-8")

    assert "extends Area3D" in script
    assert "objective_completed" in script
    assert "objective_id" in script
    assert "objective_sequence" in script
    assert "CollisionShape3D" in script
```

**Step 2: Run test to verify failure**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_runtime_objective_volume_script_declares_area_metadata -q
```

Expected: FAIL because the script does not exist.

**Step 3: Implement script**

Create `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/gameplay_objective_volume.gd`:

```gdscript
extends Area3D
class_name GameplayObjectiveVolume

signal objective_completed(objective_id: String, sequence: int, objective_type: String, room_id: String)

const DEFAULT_RADIUS: float = 1.5

var objective_id: String = ""
var sequence: int = 0
var objective_type: String = "unknown"
var room_id: String = ""
var completed: bool = false

func configure(objective: Dictionary, world_position: Vector3, radius: float = DEFAULT_RADIUS) -> void:
    objective_id = str(objective.get("id", ""))
    sequence = int(objective.get("sequence", 0))
    objective_type = str(objective.get("type", "unknown"))
    room_id = str(objective.get("room_id", ""))

    name = "ObjectiveVolume_seq%d_%s" % [sequence, objective_id]
    position = world_position
    monitoring = true
    monitorable = true
    collision_layer = 0
    collision_mask = 0

    set_meta("objective_id", objective_id)
    set_meta("objective_sequence", sequence)
    set_meta("objective_type", objective_type)
    set_meta("room_id", room_id)

    var sphere := SphereShape3D.new()
    sphere.radius = radius

    var shape := CollisionShape3D.new()
    shape.name = "ObjectiveCollisionShape"
    shape.shape = sphere
    add_child(shape)

    var marker := MeshInstance3D.new()
    marker.name = "DebugObjectiveMarker"
    var mesh := SphereMesh.new()
    mesh.radius = 0.45
    mesh.height = 0.9
    marker.mesh = mesh
    marker.position = Vector3(0.0, 0.65, 0.0)
    add_child(marker)

func complete() -> void:
    if completed:
        return
    completed = true
    emit_signal("objective_completed", objective_id, sequence, objective_type, room_id)
```

**Step 4: Run test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_runtime_objective_volume_script_declares_area_metadata -q
```

Expected: PASS.

**Step 5: Commit**

```bash
git add \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/gameplay_objective_volume.gd \
  /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py
git commit -m "feat: add runtime gameplay objective volume"
```

---

## Task 4: Create the generated ship runtime loader

**Objective:** Move structural instancing, navmesh baking, vertical-link creation, and objective-volume spawning into a runtime loader that can be used by the main scene.

**Files:**

- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd`
- Use as source reference only: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_ship_gameplay_smoke.gd`
- Test: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Add failing text-level test**

Add:

```python

def test_generated_ship_loader_reuses_real_layout_primitives() -> None:
    script_path = GODOT_PROJECT / "scripts" / "procgen" / "generated_ship_loader.gd"
    assert script_path.exists()
    script = script_path.read_text(encoding="utf-8")

    assert "class_name GeneratedShipLoader" in script
    assert "ship_loaded" in script
    assert "load_from_paths" in script
    assert "_instance_structural_wrappers" in script
    assert "NavigationMeshGenerator.bake_from_source_geometry_data" in script
    assert "NavigationLink3D" in script
    assert "GameplayObjectiveVolume" in script
```

**Step 2: Run test to verify failure**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_generated_ship_loader_reuses_real_layout_primitives -q
```

Expected: FAIL.

**Step 3: Implement minimal runtime loader**

Create `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd`.

Use this structure and copy the proven helper bodies from `procgen_ship_gameplay_smoke.gd` rather than inventing new behavior:

```gdscript
extends Node3D
class_name GeneratedShipLoader

signal ship_loaded(summary: Dictionary)
signal load_failed(reason: String)

const CELL_SIZE: float = 4.0
const FLOOR_Y_OFFSET: float = 0.12
const OBJECTIVE_TRIGGER_RADIUS: float = 1.5
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]

var layout_doc: Dictionary = {}
var kit_doc: Dictionary = {}
var gameplay_doc: Dictionary = {}
var objective_specs: Array = []
var objective_volumes: Array[GameplayObjectiveVolume] = []
var start_position: Vector3 = Vector3.ZERO
var goal_position: Vector3 = Vector3.ZERO

var structural_root: Node3D
var objective_root: Node3D

func load_from_paths(layout_path: String, kit_path: String, gameplay_slice_path: String) -> bool:
    clear_loaded_ship()

    layout_doc = _load_json_dict(_resolve_path(layout_path), "layout")
    kit_doc = _load_json_dict(_resolve_path(kit_path), "kit")
    gameplay_doc = _load_json_dict(_resolve_path(gameplay_slice_path), "gameplay slice")
    if layout_doc.is_empty() or kit_doc.is_empty() or gameplay_doc.is_empty():
        emit_signal("load_failed", "missing-or-invalid-json")
        return false

    var rooms: Array = layout_doc.get("rooms", [])
    var prototype: Dictionary = layout_doc.get("prototype", {})
    var start_room_id: String = str(gameplay_doc.get("start_room", prototype.get("start_room", "")))
    var goal_room_id: String = str(gameplay_doc.get("goal_room", prototype.get("goal_room", "")))

    structural_root = Node3D.new()
    structural_root.name = "StructuralRoot"
    add_child(structural_root)

    objective_root = Node3D.new()
    objective_root.name = "GameplayObjectiveRoot"
    add_child(objective_root)

    var module_to_scene: Dictionary = _build_module_scene_map(kit_doc, kit_path)
    var instantiated_count: int = _instance_structural_wrappers(layout_doc, module_to_scene, structural_root)

    start_position = _room_center(rooms, start_room_id)
    goal_position = _room_center(rooms, goal_room_id)
    if start_position == Vector3.INF or goal_position == Vector3.INF:
        emit_signal("load_failed", "missing-start-or-goal-room")
        return false

    var nav_region := _build_navigation_region(rooms, self)
    if nav_region == null:
        emit_signal("load_failed", "navigation-region-failed")
        return false

    var vertical_link_count: int = _add_vertical_links(layout_doc, self)
    objective_specs = _build_objective_specs(layout_doc, gameplay_doc, gameplay_slice_path)
    if objective_specs.is_empty():
        emit_signal("load_failed", "no-objectives")
        return false

    for objective in objective_specs:
        var volume := GameplayObjectiveVolume.new()
        volume.configure(objective, objective.get("position", Vector3.ZERO), OBJECTIVE_TRIGGER_RADIUS)
        objective_root.add_child(volume)
        objective_volumes.append(volume)

    emit_signal("ship_loaded", {
        "instantiated_count": instantiated_count,
        "vertical_link_count": vertical_link_count,
        "objective_count": objective_specs.size(),
        "start_position": start_position,
        "goal_position": goal_position,
    })
    return true

func clear_loaded_ship() -> void:
    for child in get_children():
        child.queue_free()
    objective_specs.clear()
    objective_volumes.clear()

# Copy these proven helper functions from procgen_ship_gameplay_smoke.gd with only mechanical adjustments:
# - _resolve_path
# - _load_json_dict
# - _build_module_scene_map
# - _build_objective_specs
# - _spawn_objective_volume is NOT copied; use GameplayObjectiveVolume instead
# - _find_room
# - _cell_name_candidates
# - _room_cell_world
# - _instance_structural_wrappers
# - _parse_prefixed_int
# - _cell_signature_from_placement_name
# - _placement_matches_endpoint_cell
# - _cell_world_from_link_endpoint
# - _add_vertical_links
# - _build_navigation_region
# - _room_center
```

Important implementation detail:

- Do not leave `_spawn_objective_volume` duplicated in the loader. The loader should create `GameplayObjectiveVolume` nodes using the new script.
- Keep helper behavior identical to the validation script first; refactor after tests pass.

**Step 4: Run test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_generated_ship_loader_reuses_real_layout_primitives -q
```

Expected: PASS.

**Step 5: Commit**

```bash
git add \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd \
  /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py
git commit -m "feat: add generated ship runtime loader"
```

---

## Task 5: Add a visible debug runner that uses NavigationAgent3D

**Objective:** Replace invisible validation movement with a visible in-engine placeholder actor that traverses the loaded objective sequence.

**Files:**

- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/procgen_debug_runner.gd`
- Test: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Add failing text-level test**

Add:

```python

def test_procgen_debug_runner_is_visible_and_uses_navigation_agent() -> None:
    script_path = GODOT_PROJECT / "scripts" / "procgen" / "procgen_debug_runner.gd"
    assert script_path.exists()
    script = script_path.read_text(encoding="utf-8")

    assert "class_name ProcgenDebugRunner" in script
    assert "NavigationAgent3D" in script
    assert "MeshInstance3D" in script
    assert "objective_reached" in script
    assert "run_completed" in script
    assert "active_target_position" in script
```

**Step 2: Run test to verify failure**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_procgen_debug_runner_is_visible_and_uses_navigation_agent -q
```

Expected: FAIL.

**Step 3: Implement debug runner**

Create `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/procgen_debug_runner.gd`:

```gdscript
extends Node3D
class_name ProcgenDebugRunner

signal objective_reached(objective_id: String, sequence: int, objective_type: String, room_id: String)
signal run_completed(objective_count: int, interaction_count: int, frame_count: int, final_distance: float)
signal run_failed(reason: String, frame_count: int, interaction_count: int)

const WALK_SPEED: float = 4.5
const TARGET_DISTANCE: float = 0.8
const OBJECTIVE_TRIGGER_RADIUS: float = 1.5

var agent: NavigationAgent3D
var objective_specs: Array = []
var objective_volumes: Array[GameplayObjectiveVolume] = []
var goal_position: Vector3 = Vector3.ZERO
var current_objective_index: int = 0
var interaction_count: int = 0
var frame_count: int = 0
var timeout_frames: int = 9000
var running: bool = false
var active_target_position: Vector3 = Vector3.INF
var last_distance: float = 0.0

func _ready() -> void:
    _build_visible_marker()
    agent = NavigationAgent3D.new()
    agent.name = "NavigationAgent3D"
    agent.path_desired_distance = 0.35
    agent.target_desired_distance = TARGET_DISTANCE
    add_child(agent)
    set_physics_process(false)

func start_run(start: Vector3, objectives: Array, volumes: Array[GameplayObjectiveVolume], goal: Vector3, timeout: int = 9000) -> void:
    global_position = start
    objective_specs = objectives
    objective_volumes = volumes
    goal_position = goal
    timeout_frames = timeout
    current_objective_index = 0
    interaction_count = 0
    frame_count = 0
    running = true
    active_target_position = Vector3.INF
    if objective_specs.is_empty():
        _fail("no-objectives")
        return
    _set_agent_target(objective_specs[0].get("position", goal_position))
    set_physics_process(true)

func _physics_process(delta: float) -> void:
    if not running:
        return
    frame_count += 1
    if frame_count < 2:
        return
    if frame_count >= timeout_frames:
        _fail("timeout")
        return

    if current_objective_index < objective_specs.size():
        var objective: Dictionary = objective_specs[current_objective_index]
        var target: Vector3 = objective.get("position", Vector3.INF)
        _set_agent_target(target)
        _advance(delta)
        last_distance = global_position.distance_to(target)
        if last_distance <= OBJECTIVE_TRIGGER_RADIUS:
            _complete_current_objective(last_distance)
        return

    _set_agent_target(goal_position)
    _advance(delta)
    last_distance = global_position.distance_to(goal_position)
    if last_distance <= TARGET_DISTANCE:
        running = false
        set_physics_process(false)
        emit_signal("run_completed", objective_specs.size(), interaction_count, frame_count, last_distance)

func _set_agent_target(target: Vector3) -> void:
    if active_target_position == target:
        return
    active_target_position = target
    agent.target_position = target

func _advance(delta: float) -> void:
    var next_position: Vector3 = agent.get_next_path_position()
    if next_position == Vector3.ZERO and global_position.distance_to(active_target_position) > 1.0:
        return
    global_position = global_position.move_toward(next_position, WALK_SPEED * delta)

func _complete_current_objective(distance: float) -> void:
    var objective: Dictionary = objective_specs[current_objective_index]
    var volume: GameplayObjectiveVolume = objective_volumes[current_objective_index]
    volume.complete()
    interaction_count += 1
    emit_signal(
        "objective_reached",
        str(objective.get("id", "")),
        int(objective.get("sequence", interaction_count)),
        str(objective.get("type", "unknown")),
        str(objective.get("room_id", ""))
    )
    current_objective_index += 1
    if current_objective_index < objective_specs.size():
        _set_agent_target(objective_specs[current_objective_index].get("position", goal_position))
    else:
        _set_agent_target(goal_position)

func _fail(reason: String) -> void:
    running = false
    set_physics_process(false)
    emit_signal("run_failed", reason, frame_count, interaction_count)

func _build_visible_marker() -> void:
    var body := MeshInstance3D.new()
    body.name = "DebugRunnerMarker"
    var mesh := CapsuleMesh.new()
    mesh.radius = 0.35
    mesh.height = 1.4
    body.mesh = mesh
    body.position = Vector3(0.0, 0.8, 0.0)
    add_child(body)
```

**Step 4: Run test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_procgen_debug_runner_is_visible_and_uses_navigation_agent -q
```

Expected: PASS.

**Step 5: Commit**

```bash
git add \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/procgen_debug_runner.gd \
  /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py
git commit -m "feat: add visible procgen debug runner"
```

---

## Task 6: Add simple objective tracker UI

**Objective:** Make objective progress visible in the game viewport.

**Files:**

- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/ui/objective_tracker.gd`
- Test: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Add failing text-level test**

Add:

```python

def test_objective_tracker_displays_current_objective_progress() -> None:
    script_path = GODOT_PROJECT / "scripts" / "ui" / "objective_tracker.gd"
    assert script_path.exists()
    script = script_path.read_text(encoding="utf-8")

    assert "extends Control" in script
    assert "set_objectives" in script
    assert "mark_completed" in script
    assert "Label" in script
```

**Step 2: Run test to verify failure**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_objective_tracker_displays_current_objective_progress -q
```

Expected: FAIL.

**Step 3: Implement UI script**

Create `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/ui/objective_tracker.gd`:

```gdscript
extends Control
class_name ObjectiveTracker

var label: Label
var objectives: Array = []
var completed_sequences: Dictionary = {}

func _ready() -> void:
    label = Label.new()
    label.name = "ObjectiveTrackerLabel"
    label.position = Vector2(20, 20)
    label.size = Vector2(760, 220)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(label)
    _refresh()

func set_objectives(new_objectives: Array) -> void:
    objectives = new_objectives
    completed_sequences.clear()
    _refresh()

func mark_completed(sequence: int) -> void:
    completed_sequences[sequence] = true
    _refresh()

func mark_run_complete() -> void:
    _refresh("Run complete: all objectives reached; proceed to reactor goal.")

func _refresh(extra: String = "") -> void:
    if label == null:
        return
    var lines: Array[String] = ["Procgen Gameplay Smoke"]
    for objective_variant in objectives:
        if typeof(objective_variant) != TYPE_DICTIONARY:
            continue
        var objective: Dictionary = objective_variant
        var sequence: int = int(objective.get("sequence", 0))
        var marker: String = "✓" if completed_sequences.has(sequence) else "•"
        lines.append(
            "%s %d. %s / %s" % [
                marker,
                sequence,
                str(objective.get("type", "unknown")).replace("_", " "),
                str(objective.get("room_id", "unknown")),
            ]
        )
    if not extra.is_empty():
        lines.append(extra)
    label.text = "\n".join(lines)
```

**Step 4: Run test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_objective_tracker_displays_current_objective_progress -q
```

Expected: PASS.

**Step 5: Commit**

```bash
git add \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/ui/objective_tracker.gd \
  /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py
git commit -m "feat: add procgen objective tracker UI"
```

---

## Task 7: Create the generated ship demo scene/controller

**Objective:** Create the actual in-game scene that loads the generated ship, starts the visible runner, and updates UI.

**Files:**

- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_demo.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/procgen/generated_ship_demo.tscn`
- Test: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Add failing text-level test**

Add:

```python

def test_generated_ship_demo_scene_wires_loader_runner_and_ui() -> None:
    scene_path = GODOT_PROJECT / "scenes" / "procgen" / "generated_ship_demo.tscn"
    script_path = GODOT_PROJECT / "scripts" / "procgen" / "generated_ship_demo.gd"
    assert scene_path.exists()
    assert script_path.exists()

    scene = scene_path.read_text(encoding="utf-8")
    script = script_path.read_text(encoding="utf-8")

    assert "GeneratedShipDemo" in scene
    assert "generated_ship_demo.gd" in scene
    assert "GeneratedShipLoader" in script
    assert "ProcgenDebugRunner" in script
    assert "ObjectiveTracker" in script
    assert "demo_completed" in script
```

**Step 2: Run test to verify failure**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_generated_ship_demo_scene_wires_loader_runner_and_ui -q
```

Expected: FAIL.

**Step 3: Implement demo controller**

Create `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_demo.gd`:

```gdscript
extends Node3D
class_name GeneratedShipDemo

signal demo_completed(objective_count: int, interaction_count: int, frame_count: int, final_distance: float)
signal demo_failed(reason: String)

const DEFAULT_LAYOUT_PATH := "res://data/procgen/smoke/seed_000017/layout.json"
const DEFAULT_KIT_PATH := "res://data/kits/ship_structural_v0.json"
const DEFAULT_GAMEPLAY_SLICE_PATH := "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
const DEFAULT_TIMEOUT_FRAMES := 9000

var loader: GeneratedShipLoader
var runner: ProcgenDebugRunner
var tracker: ObjectiveTracker
var camera: Camera3D

func _ready() -> void:
    _build_scene_nodes()
    _load_and_start(DEFAULT_LAYOUT_PATH, DEFAULT_KIT_PATH, DEFAULT_GAMEPLAY_SLICE_PATH)

func _build_scene_nodes() -> void:
    loader = GeneratedShipLoader.new()
    loader.name = "GeneratedShipLoader"
    add_child(loader)

    runner = ProcgenDebugRunner.new()
    runner.name = "ProcgenDebugRunner"
    add_child(runner)

    tracker = ObjectiveTracker.new()
    tracker.name = "ObjectiveTracker"
    add_child(tracker)

    camera = Camera3D.new()
    camera.name = "GeneratedShipDemoCamera"
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 80.0
    camera.current = true
    camera.position = Vector3(60.0, 80.0, 80.0)
    camera.look_at(Vector3(60.0, 0.0, 8.0), Vector3.UP)
    add_child(camera)

    var light := DirectionalLight3D.new()
    light.name = "GeneratedShipDemoLight"
    light.light_energy = 1.5
    light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
    add_child(light)

func _load_and_start(layout_path: String, kit_path: String, gameplay_slice_path: String) -> void:
    loader.load_failed.connect(_on_loader_failed)
    loader.ship_loaded.connect(_on_ship_loaded)
    var ok := loader.load_from_paths(layout_path, kit_path, gameplay_slice_path)
    if not ok:
        return

func _on_loader_failed(reason: String) -> void:
    emit_signal("demo_failed", reason)

func _on_ship_loaded(summary: Dictionary) -> void:
    tracker.set_objectives(loader.objective_specs)
    runner.objective_reached.connect(_on_objective_reached)
    runner.run_completed.connect(_on_run_completed)
    runner.run_failed.connect(_on_run_failed)
    runner.start_run(
        loader.start_position,
        loader.objective_specs,
        loader.objective_volumes,
        loader.goal_position,
        DEFAULT_TIMEOUT_FRAMES
    )

func _on_objective_reached(objective_id: String, sequence: int, objective_type: String, room_id: String) -> void:
    print("RUNTIME INTERACTION objective=%s sequence=%d type=%s room=%s" % [objective_id, sequence, objective_type, room_id])
    tracker.mark_completed(sequence)

func _on_run_completed(objective_count: int, interaction_count: int, frame_count: int, final_distance: float) -> void:
    tracker.mark_run_complete()
    print("RUNTIME GAMEPLAY DEMO PASS objectives=%d interactions=%d frames=%d final_distance=%.3f" % [objective_count, interaction_count, frame_count, final_distance])
    emit_signal("demo_completed", objective_count, interaction_count, frame_count, final_distance)

func _on_run_failed(reason: String, frame_count: int, interaction_count: int) -> void:
    push_error("RUNTIME GAMEPLAY DEMO FAIL reason=%s frames=%d interactions=%d" % [reason, frame_count, interaction_count])
    emit_signal("demo_failed", reason)
```

**Step 4: Create demo scene**

Create `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/procgen/generated_ship_demo.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/procgen/generated_ship_demo.gd" id="1_demo"]

[node name="GeneratedShipDemo" type="Node3D"]
script = ExtResource("1_demo")
```

**Step 5: Run test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_generated_ship_demo_scene_wires_loader_runner_and_ui -q
```

Expected: PASS.

**Step 6: Commit**

```bash
git add \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_demo.gd \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/procgen/generated_ship_demo.tscn \
  /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py
git commit -m "feat: add generated ship gameplay demo scene"
```

---

## Task 8: Wire the demo into the actual main scene

**Objective:** Make the normal game launch show the generated ship gameplay smoke instead of only printing a bootstrap line.

**Files:**

- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd`
- Optional modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/main.tscn`
- Test: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Add failing text-level test**

Add:

```python

def test_main_scene_loads_generated_ship_demo() -> None:
    main_script = (GODOT_PROJECT / "scripts" / "main.gd").read_text(encoding="utf-8")
    assert "generated_ship_demo.tscn" in main_script
    assert "GeneratedShipDemo" in main_script
```

**Step 2: Run test to verify failure**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_main_scene_loads_generated_ship_demo -q
```

Expected: FAIL.

**Step 3: Replace minimal bootstrap with demo loader**

Modify `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd`:

```gdscript
extends Node3D

const GENERATED_SHIP_DEMO_SCENE := preload("res://scenes/procgen/generated_ship_demo.tscn")

func _ready() -> void:
    print("The Synaptic Sea project bootstrap loaded.")
    var demo := GENERATED_SHIP_DEMO_SCENE.instantiate()
    demo.name = "GeneratedShipDemo"
    add_child(demo)
```

**Step 4: Run test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_main_scene_loads_generated_ship_demo -q
```

Expected: PASS.

**Step 5: Commit**

```bash
git add \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd \
  /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py
git commit -m "feat: launch procgen gameplay demo from main scene"
```

---

## Task 9: Add the headless runtime demo smoke script

**Objective:** Prove the actual runtime demo scene, not the old validation-only script, reaches all objectives and the final goal.

**Files:**

- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_runtime_demo_smoke.gd`
- Test: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Confirm RED still fails**

Run:

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_runtime_demo_smoke_runs_if_godot_available -q
```

Expected: FAIL until this script exists and runtime code works.

**Step 2: Implement runtime smoke script**

Create `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_runtime_demo_smoke.gd`:

```gdscript
extends SceneTree

const DEFAULT_TIMEOUT_FRAMES: int = 9000
const DEMO_SCENE := preload("res://scenes/procgen/generated_ship_demo.tscn")

var frame_count: int = 0
var timeout_frames: int = DEFAULT_TIMEOUT_FRAMES
var finished: bool = false

func _initialize() -> void:
    timeout_frames = _parse_timeout(OS.get_cmdline_user_args())

    var demo := DEMO_SCENE.instantiate()
    demo.name = "GeneratedShipDemoRuntimeSmoke"
    demo.demo_completed.connect(_on_demo_completed)
    demo.demo_failed.connect(_on_demo_failed)
    get_root().add_child(demo)

func _process(_delta: float) -> void:
    if finished:
        return
    frame_count += 1
    if frame_count >= timeout_frames:
        finished = true
        push_error("RUNTIME GAMEPLAY DEMO FAIL reason=timeout frames=%d" % frame_count)
        quit(1)

func _on_demo_completed(objective_count: int, interaction_count: int, runner_frames: int, final_distance: float) -> void:
    finished = true
    print(
        "RUNTIME GAMEPLAY DEMO PASS objectives=%d interactions=%d frames=%d final_distance=%.3f"
        % [objective_count, interaction_count, runner_frames, final_distance]
    )
    quit(0)

func _on_demo_failed(reason: String) -> void:
    finished = true
    push_error("RUNTIME GAMEPLAY DEMO FAIL reason=%s frames=%d" % [reason, frame_count])
    quit(1)

func _parse_timeout(args: PackedStringArray) -> int:
    var index := 0
    while index < args.size():
        if args[index] == "--timeout-frames" and index + 1 < args.size():
            var raw := args[index + 1]
            if raw.is_valid_int():
                return int(raw)
        index += 1
    return DEFAULT_TIMEOUT_FRAMES
```

**Step 3: Run runtime smoke test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_runtime_demo_smoke_runs_if_godot_available -q
```

Expected: PASS and output contains `RUNTIME GAMEPLAY DEMO PASS objectives=4 interactions=4`.

**Step 4: Commit**

```bash
git add \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_runtime_demo_smoke.gd \
  /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py
git commit -m "test: add runtime gameplay demo smoke"
```

---

## Task 10: Add a real Godot viewport capture proof

**Objective:** Produce a visual proof from the Godot viewport itself so the user is not relying on HTML overlays.

**Files:**

- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_runtime_demo_capture.gd`
- Test: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Add failing test**

Add:

```python

def test_runtime_demo_capture_produces_png_if_godot_available(tmp_path: Path) -> None:
    if not GODOT.exists():
        pytest.skip(f"Godot binary not found: {GODOT}")

    output_png = tmp_path / "runtime_demo.png"
    proc = subprocess.run(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(GODOT_PROJECT),
            "--script",
            "res://scripts/validation/procgen_runtime_demo_capture.gd",
            "--",
            "--output",
            str(output_png),
            "--capture-frame",
            "240",
        ],
        cwd=GODOT_PROJECT,
        text=True,
        capture_output=True,
        timeout=180,
    )

    combined = proc.stdout + proc.stderr
    assert proc.returncode == 0, combined
    assert output_png.exists()
    assert output_png.stat().st_size > 10_000
    assert "RUNTIME DEMO CAPTURE PASS" in combined
```

**Step 2: Run test to verify failure**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_runtime_demo_capture_produces_png_if_godot_available -q
```

Expected: FAIL because capture script does not exist.

**Step 3: Implement capture script**

Create `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_runtime_demo_capture.gd`:

```gdscript
extends SceneTree

const DEMO_SCENE := preload("res://scenes/procgen/generated_ship_demo.tscn")

var output_path: String = ""
var capture_frame: int = 240
var frame_count: int = 0

func _initialize() -> void:
    var parsed := _parse_args(OS.get_cmdline_user_args())
    output_path = str(parsed.get("output", ""))
    capture_frame = int(parsed.get("capture_frame", 240))
    if output_path.is_empty():
        push_error("Usage: --output <png> [--capture-frame <n>]")
        quit(1)
        return

    var demo := DEMO_SCENE.instantiate()
    get_root().add_child(demo)

func _process(_delta: float) -> void:
    frame_count += 1
    if frame_count < capture_frame:
        return

    var image := get_root().get_texture().get_image()
    var err := image.save_png(output_path)
    if err != OK:
        push_error("failed to write runtime demo capture: %s" % output_path)
        quit(1)
        return
    print("RUNTIME DEMO CAPTURE PASS output=%s frame=%d" % [output_path, frame_count])
    quit(0)

func _parse_args(args: PackedStringArray) -> Dictionary:
    var result: Dictionary = {}
    var index := 0
    while index < args.size():
        var token := args[index]
        if token == "--output" and index + 1 < args.size():
            result["output"] = args[index + 1]
            index += 2
            continue
        if token == "--capture-frame" and index + 1 < args.size() and args[index + 1].is_valid_int():
            result["capture_frame"] = int(args[index + 1])
            index += 2
            continue
        index += 1
    return result
```

**Step 4: Run capture test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_runtime_demo_capture_produces_png_if_godot_available -q
```

Expected: PASS, PNG exists and is non-trivial in size.

**Step 5: Create a human-viewable capture manually**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_runtime_demo_capture.gd -- \
  --output /tmp/synaptic_sea_runtime_gameplay_demo.png \
  --capture-frame 240
open /tmp/synaptic_sea_runtime_gameplay_demo.png
```

Expected: PNG opens and shows the generated ship scene from the Godot viewport.

**Step 6: Commit**

```bash
git add \
  /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_runtime_demo_capture.gd \
  /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py
git commit -m "test: add runtime gameplay demo viewport capture"
```

---

## Task 11: Keep the old validation smoke green

**Objective:** Ensure the new runtime code does not break existing procgen validation guarantees.

**Files:**

- No production file changes expected unless tests reveal a real regression.
- Test targets:
  - `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_procgen_ship_gameplay_smoke.py`
  - `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_procgen_ship_walkthrough_smoke.py`
  - `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_build_ship_prototype_bundle.py`
  - `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Run focused smoke tests**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest \
  tests/test_godot_procgen_runtime_demo.py \
  tests/test_procgen_ship_gameplay_smoke.py \
  tests/test_procgen_ship_walkthrough_smoke.py \
  tests/test_build_ship_prototype_bundle.py \
  -q
```

Expected: all pass.

**Step 2: If old smoke fails**

Do not delete the old scripts. Fix shared assumptions or fixture data. The old scripts remain useful as independent validation until runtime demo coverage is stable.

**Step 3: Commit fixes only if needed**

```bash
git add <changed files>
git commit -m "fix: preserve existing procgen smoke validation"
```

---

## Task 12: Add optional fixture export helper for repeatability

**Objective:** Make refreshing the Godot demo fixture deterministic and one-command, without requiring someone to remember the copy sequence.

**Files:**

- Create: `/Users/christopherwilloughby/off-the-rails-ai-infra/tools/export_ship_runtime_demo_fixture.py`
- Test: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_runtime_demo.py`

**Step 1: Add failing helper test**

Add:

```python

def test_export_runtime_demo_fixture_helper_has_expected_paths() -> None:
    helper = REPO_ROOT / "tools" / "export_ship_runtime_demo_fixture.py"
    assert helper.exists()
    text = helper.read_text(encoding="utf-8")

    assert "build_ship_prototype_bundle.py" in text
    assert "the-synaptic-sea-of-stars" in text
    assert "data/procgen/smoke/seed_000017" in text
    assert "ship_structural_v0.json" in text
```

Add `REPO_ROOT` near the test top if not already defined:

```python
REPO_ROOT = Path(__file__).resolve().parents[1]
```

**Step 2: Run test to verify failure**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_export_runtime_demo_fixture_helper_has_expected_paths -q
```

Expected: FAIL.

**Step 3: Implement helper**

Create `/Users/christopherwilloughby/off-the-rails-ai-infra/tools/export_ship_runtime_demo_fixture.py`:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT_PROJECT = Path("/Users/christopherwilloughby/the-synaptic-sea-of-stars")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export deterministic generated-ship fixture into the Godot runtime demo.")
    parser.add_argument("--godot-project", type=Path, default=DEFAULT_GODOT_PROJECT)
    parser.add_argument("--seed", type=int, default=17)
    parser.add_argument("--room-count", type=int, default=8)
    parser.add_argument("--deck-count", type=int, default=2)
    parser.add_argument("--vertical-transition-count", type=int, default=1)
    parser.add_argument("--work-root", type=Path, default=Path("/tmp/synaptic_sea_runtime_demo_fixture"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.work_root.exists():
        shutil.rmtree(args.work_root)
    command = [
        sys.executable,
        str(REPO_ROOT / "tools" / "build_ship_prototype_bundle.py"),
        "--seed",
        str(args.seed),
        "--room-count",
        str(args.room_count),
        "--deck-count",
        str(args.deck_count),
        "--vertical-transition-count",
        str(args.vertical_transition_count),
        "--output-root",
        str(args.work_root),
        "--skip-render",
        "--gameplay-smoke",
    ]
    proc = subprocess.run(command, cwd=REPO_ROOT, text=True)
    if proc.returncode != 0:
        return proc.returncode

    bundle_dir = args.work_root / f"seed_{args.seed:06d}"
    data_dir = args.godot_project / "data" / "procgen" / "smoke" / f"seed_{args.seed:06d}"
    kit_dir = args.godot_project / "data" / "kits"
    data_dir.mkdir(parents=True, exist_ok=True)
    kit_dir.mkdir(parents=True, exist_ok=True)

    shutil.copy2(REPO_ROOT / "data" / "kits" / "ship_structural_v0.json", kit_dir / "ship_structural_v0.json")
    shutil.copy2(bundle_dir / "layout.json", data_dir / "layout.json")
    shutil.copy2(bundle_dir / "gameplay_slice.json", data_dir / "gameplay_slice.json")
    print(f"Exported runtime demo fixture to {data_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

**Step 4: Run helper test to verify pass**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py::test_export_runtime_demo_fixture_helper_has_expected_paths -q
```

Expected: PASS.

**Step 5: Run helper once**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
python3 tools/export_ship_runtime_demo_fixture.py
```

Expected: exit 0 and fixture files refreshed in the Godot project.

**Step 6: Commit**

```bash
git add \
  tools/export_ship_runtime_demo_fixture.py \
  tests/test_godot_procgen_runtime_demo.py
git commit -m "chore: add procgen runtime demo fixture exporter"
```

---

## Task 13: Run final verification gates

**Objective:** Prove the feature is real in-engine and did not regress existing procgen systems.

**Files:**

- No new files expected.

**Step 1: Run runtime demo tests**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_runtime_demo.py -q
```

Expected: all tests pass.

**Step 2: Run focused procgen tests**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest \
  tests/test_procgen_ship_gameplay_smoke.py \
  tests/test_procgen_ship_walkthrough_smoke.py \
  tests/test_ship_gameplay_slice.py \
  tests/test_build_ship_prototype_bundle.py \
  tests/test_run_procgen_regression.py \
  -q
```

Expected: all tests pass.

**Step 3: Run full infra suite**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest -q
```

Expected: all tests pass. Latest known baseline before this plan: `316 passed`.

**Step 4: Run procgen regression**

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
python3 tools/run_procgen_regression.py
```

Expected: `Summary: passed=5 failed=0 scenes=5`.

**Step 5: Run Godot runtime smoke directly**

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_runtime_demo_smoke.gd -- \
  --timeout-frames 9000
```

Expected:

```text
RUNTIME GAMEPLAY DEMO PASS objectives=4 interactions=4 frames=<n> final_distance=<d>
```

**Step 6: Capture real Godot viewport proof**

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_runtime_demo_capture.gd -- \
  --output /tmp/synaptic_sea_runtime_gameplay_demo.png \
  --capture-frame 240
open /tmp/synaptic_sea_runtime_gameplay_demo.png
```

Expected:

- PNG exists.
- PNG is non-trivial in size.
- Screenshot shows the generated ship in the actual Godot viewport with visible objective markers and debug runner.

**Step 7: Launch the actual game scene manually**

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars
```

Expected:

- Main scene opens.
- Generated ship appears.
- Debug runner visibly moves through the objective sequence.
- Objective tracker updates.

---

## Risks / Tradeoffs / Open Questions

### Risk: Duplicate helper code between validation and runtime loader

The quickest path copies helper functions from `procgen_ship_gameplay_smoke.gd` into `GeneratedShipLoader`. This is acceptable for the first in-game pass, but duplication should be reduced after the runtime demo is proven.

Mitigation:

- Keep copied helper behavior identical at first.
- Add a later refactor task to move shared helpers into a common `scripts/procgen/ship_layout_runtime_utils.gd` only after both old and new smoke tests pass.

### Risk: Fixture data in the Godot project can go stale

The checked-in runtime fixture may drift from the procgen pipeline.

Mitigation:

- Use `tools/export_ship_runtime_demo_fixture.py` to regenerate it.
- Keep runtime fixture tests tied to known objective count and smoke pass.

### Risk: Headless screenshots may be renderer-dependent

Godot headless capture may produce blank images on some renderer/platform combinations.

Mitigation:

- The primary proof is the runtime smoke pass.
- The screenshot is a visibility proof; if headless capture is flaky, run a foreground `godot --path` launch and use normal screenshot tooling.

### Risk: This is still auto-run, not player-controlled gameplay

This plan creates a real in-engine gameplay smoke, but not manual gameplay.

Mitigation:

- Treat this as the next legitimacy step after validation.
- Follow-up plan should replace auto-run with keyboard/mouse controlled placeholder player and `press E` interactions.

### Open question: Should the demo be default main scene behavior?

This plan wires the generated demo into `main.gd` because the current main scene is empty. If that is too invasive, gate it behind an environment variable or command-line flag.

Recommended default for this stage:

- Show the demo by default until the project has a broader hub/main menu.

---

## Final Deliverable Summary For Implementer

After implementation, report concise evidence:

- Changed files count.
- Runtime demo smoke result.
- Objective/interactions count.
- Structural wrapper count if surfaced by loader summary.
- Vertical navigation link count.
- Full test result.
- Procgen regression result.
- Godot viewport capture path.
- Clear statement:
  - “This is now visible in the actual Godot game scene.”
  - “This is still an auto-run prototype, not manual player gameplay.”

