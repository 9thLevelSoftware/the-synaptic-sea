# Coherent Proof Ship Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one curated, data-driven, in-engine derelict ship fixture that proves spatial coherence: entry, connected rooms, central spine, visible elevation transition, blocked route, landmark, destination, playable traversal, and fresh Godot capture.

**Architecture:** Add a named golden fixture beside the existing seed-17 smoke fixture. Keep the existing `GeneratedShipLoader` and `PlayableGeneratedShip` runtime path, but add minimal optional metadata/accessors for coherent-room topology, landmarks, blocked routes, and visible vertical transitions. Validate the fixture in layers: static JSON topology, runtime loader output, playable traversal, visual capture, then existing regression smokes.

**Tech Stack:** Godot 4.6.2 GDScript, `SceneTree` validation scripts, existing `GeneratedShipLoader`, existing `PlayableGeneratedShip`, existing `ship_structural_v0` wrapper kit, local Godot binary `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.

## Global Constraints

- Godot project root: `/Users/christopherwilloughby/the-synaptic-sea-of-stars`.
- Approved design spec: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/specs/2026-06-17-coherent-proof-ship-design.md`.
- Godot version: `4.6.2.stable.official.71f334935`.
- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Do not mutate the seed-17 smoke fixture at `data/procgen/smoke/seed_000017/`; the coherent proof ship is a sibling under `data/procgen/golden/coherent_ship_001/`.
- Preserve the existing playable prototype path: `res://scenes/procgen/playable_generated_ship.tscn` should continue to use the seed-17 smoke fixture unless explicitly superseded by the final regression task.
- Do not implement combat, inventory, oxygen, repair mechanics, save/load, final art, broad random generation, multi-seed statistics, or production room dressing in this plan.
- The workspaces are not git repositories at plan time. Every task must use the commit-or-record fallback shown below instead of assuming `git commit` works.
- Record fallback log: `/tmp/synaptic_sea_coherent_proof_ship_no_git_changes.log`.
- The visual companion session created during brainstorming is not part of implementation; do not edit `.superpowers/brainstorm/` files.

### Commit-or-record fallback used by every task

Each task includes its own exact command with the task-specific file list and message. Use those task-local commands verbatim. They commit when this workspace is later placed under git, and otherwise append the changed paths to `/tmp/synaptic_sea_coherent_proof_ship_no_git_changes.log`.

---

## File Structure

### New data files

- `data/procgen/golden/coherent_ship_001/layout.json`
  - Defines the curated 5–8 room coherent proof ship: rooms, floor placements, explicit room links, blocked links, landmark markers, vertical transition metadata, and critical path.
- `data/procgen/golden/coherent_ship_001/gameplay_slice.json`
  - Defines start room, goal room, critical path, and ordered objective markers for the proof ship.

### Modified Godot runtime files

- `scripts/procgen/generated_ship_loader.gd`
  - Add optional metadata support while keeping existing seed-17 behavior unchanged.
  - Add public getters for room centers, roles, decks, critical path, blocked links, blocked route nodes, landmark nodes, and visible vertical transition nodes.
  - Add runtime marker creation for landmarks, blocked routes, and visible vertical transitions when metadata is present.
- `scripts/procgen/playable_generated_ship.gd`
  - Export fixture path variables so a sibling scene can override paths in `.tscn`.
  - Add `teleport_player_to_room_for_validation(room_id: String) -> bool` for traversal smokes.

### New Godot scene

- `scenes/procgen/playable_coherent_ship.tscn`
  - Sibling playable scene that uses the existing `PlayableGeneratedShip` script but points to the golden fixture paths.

### New validation scripts

- `scripts/validation/coherent_static_fixture_validator.gd`
  - Static JSON/topology validator for the golden fixture.
- `scripts/validation/coherent_loader_metadata_smoke.gd`
  - Verifies loader metadata accessors for the golden fixture.
- `scripts/validation/coherent_runtime_loader_smoke.gd`
  - Verifies loader-created runtime structure: collision, landmark, blocked route, visible vertical transition.
- `scripts/validation/coherent_playable_traversal_smoke.gd`
  - Verifies player-facing traversal across critical path, side-room reachability, blocked route collision, and at least one interaction.
- `scripts/validation/coherent_proof_ship_capture.gd`
  - Produces a fresh Godot viewport capture for the coherent proof ship.

### New documentation

- `docs/superpowers/proofs/coherent-proof-ship.md`
  - Running proof log with final commands, pass markers, capture path, and any intentional supersession notes.

---

### Task 1: Add the golden fixture data and static topology validator

**Files:**
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/golden/coherent_ship_001/layout.json`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/golden/coherent_ship_001/gameplay_slice.json`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/coherent_static_fixture_validator.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md`

**Interfaces:**
- Consumes: JSON fixture files at `res://data/procgen/golden/coherent_ship_001/layout.json` and `res://data/procgen/golden/coherent_ship_001/gameplay_slice.json`.
- Produces: Static pass marker `COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1`.
- Produces data fields consumed by later tasks:
  - `layout.rooms[].id: String`
  - `layout.rooms[].room_role: String`
  - `layout.rooms[].deck: int`
  - `layout.rooms[].structural_placements: Array[Dictionary]`
  - `layout.room_links: Array[Dictionary]`
  - `layout.blocked_links: Array[Dictionary]`
  - `layout.landmarks: Array[Dictionary]`
  - `layout.vertical_connections: Array[Dictionary]`
  - `layout.critical_path: Array[String]`
  - `gameplay.start_room: String`
  - `gameplay.goal_room: String`
  - `gameplay.objectives: Array[Dictionary]`

- [ ] **Step 1: Write the failing validator skeleton**

Create `scripts/validation/coherent_static_fixture_validator.gd` with these constants and pass/fail contract:

```gdscript
extends SceneTree

const DEFAULT_LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
const DEFAULT_GAMEPLAY_PATH: String = "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"
const REQUIRED_ROLES: Array[String] = ["airlock", "main_spine", "reactor"]

var failures: Array[String] = []

func _initialize() -> void:
	var layout_path: String = DEFAULT_LAYOUT_PATH
	var gameplay_path: String = DEFAULT_GAMEPLAY_PATH
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 2:
		layout_path = args[0]
		gameplay_path = args[1]
	var layout: Dictionary = _load_json(layout_path, "layout")
	var gameplay: Dictionary = _load_json(gameplay_path, "gameplay")
	if failures.is_empty():
		_validate(layout, gameplay, layout_path, gameplay_path)
	if not failures.is_empty():
		for failure in failures:
			push_error("COHERENT STATIC FIXTURE FAIL %s" % failure)
		quit(1)
		return
	print("COHERENT STATIC FIXTURE PASS rooms=%d traversable_links=%d blocked_links=%d vertical_connections=%d" % [
		(layout.get("rooms", []) as Array).size(),
		(layout.get("room_links", []) as Array).size(),
		(layout.get("blocked_links", []) as Array).size(),
		(layout.get("vertical_connections", []) as Array).size(),
	])
	quit(0)
```

Add helper functions in the same file with these exact names and behavior:

- `_load_json(path: String, label: String) -> Dictionary`
  - Globalizes `res://` path.
  - Fails with `"%s not found: %s" % [label, path]` if missing.
  - Fails with `"%s JSON is invalid: %s" % [label, path]` if parse result is not a dictionary.
- `_validate(layout: Dictionary, gameplay: Dictionary, layout_path: String, gameplay_path: String) -> void`
  - Calls all helper validators below.
- `_room_ids(layout: Dictionary) -> Array[String]`
- `_room_roles(layout: Dictionary) -> Dictionary`
- `_room_decks(layout: Dictionary) -> Dictionary`
- `_assert_unique_room_ids(layout: Dictionary) -> void`
- `_assert_required_roles(layout: Dictionary) -> void`
- `_assert_gameplay_rooms_exist(layout: Dictionary, gameplay: Dictionary) -> void`
- `_assert_links_reference_rooms(layout: Dictionary) -> void`
- `_assert_blocked_links_not_traversable(layout: Dictionary) -> void`
- `_assert_critical_path_reachable(layout: Dictionary, gameplay: Dictionary) -> void`
- `_assert_vertical_transition_for_deck_change(layout: Dictionary, gameplay: Dictionary) -> void`

Static validator graph rule:

```text
Traversable graph edges = every layout.room_links[] edge plus every layout.vertical_connections[] from_room/to_room edge.
Blocked graph edges = every layout.blocked_links[] edge.
Any blocked edge that also appears in traversable graph is a failure.
The gameplay.start_room must reach gameplay.goal_room through traversable graph.
Each adjacent pair in layout.critical_path must be traversable.
If any adjacent pair crosses deck values, a matching vertical_connections[] entry must exist.
```

- [ ] **Step 2: Run validator to verify RED before data exists**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/coherent_static_fixture_validator.gd
```

Expected: FAIL with both of these messages:

```text
COHERENT STATIC FIXTURE FAIL layout not found: res://data/procgen/golden/coherent_ship_001/layout.json
COHERENT STATIC FIXTURE FAIL gameplay not found: res://data/procgen/golden/coherent_ship_001/gameplay_slice.json
```

- [ ] **Step 3: Create the golden `layout.json` fixture**

Create `data/procgen/golden/coherent_ship_001/layout.json` with these exact top-level keys:

```json
{
  "schema_version": "1.1.0",
  "document_kind": "ship_layout",
  "program_id": "coherent-proof-ship-001",
  "kit_id": "ship_structural_v0",
  "design_intent": "curated coherent 5-8 room proof ship",
  "cell_size": 4.0,
  "rooms": [],
  "room_links": [],
  "blocked_links": [],
  "vertical_connections": [],
  "landmarks": [],
  "critical_path": []
}
```

Populate the arrays with the following fixture design. Use `floor_1x1` for room floors and `corridor_floor_1x1` for corridor/spine floors. Every floor placement must use a name compatible with the current loader: `floor_cell_x%d_z%d` for deck 0 or `floor_cell_d%d_x%d_z%d` for deck 1.

Room list:

```text
airlock_01      role=airlock      deck=0 floors: (0,0,0) (1,0,0) (0,1,0) (1,1,0)
corridor_01     role=corridor     deck=0 floors: (2,0,0) (3,0,0)
ramp_01         role=ramp         deck=0 floors: (4,0,0); placement ramp_up_1x2 at world (16,0,0)
spine_01        role=main_spine   deck=1 floors: (4,0,1) (5,0,1) (6,0,1) (7,0,1) (8,0,1)
cargo_01        role=cargo        deck=1 floors: (5,-1,1) (6,-1,1) (5,-2,1) (6,-2,1)
medbay_01       role=medbay       deck=1 floors: (7,-1,1) (8,-1,1)
maintenance_01  role=maintenance  deck=1 floors: (5,1,1) (6,1,1) (5,2,1) (6,2,1)
reactor_01      role=reactor      deck=1 floors: (9,0,1) (10,0,1) (9,1,1) (10,1,1)
```

World coordinate mapping for each floor cell:

```text
world_x = cell_x * 4.0
world_y = deck * 4.0
world_z = cell_z * 4.0
```

Required `room_links`:

```json
[
  {"id":"airlock_to_corridor","from_room":"airlock_01","to_room":"corridor_01","from_cell":[1,0,0],"to_cell":[2,0,0],"module_id":"doorway_frame_open_1x1"},
  {"id":"corridor_to_ramp","from_room":"corridor_01","to_room":"ramp_01","from_cell":[3,0,0],"to_cell":[4,0,0],"module_id":"doorway_frame_open_1x1"},
  {"id":"ramp_to_spine","from_room":"ramp_01","to_room":"spine_01","from_cell":[4,0,0],"to_cell":[4,0,1],"module_id":"ramp_up_1x2"},
  {"id":"spine_to_cargo","from_room":"spine_01","to_room":"cargo_01","from_cell":[5,0,1],"to_cell":[5,-1,1],"module_id":"doorway_frame_open_1x1"},
  {"id":"spine_to_medbay","from_room":"spine_01","to_room":"medbay_01","from_cell":[7,0,1],"to_cell":[7,-1,1],"module_id":"doorway_frame_open_1x1"},
  {"id":"spine_to_maintenance","from_room":"spine_01","to_room":"maintenance_01","from_cell":[5,0,1],"to_cell":[5,1,1],"module_id":"doorway_frame_open_1x1"},
  {"id":"spine_to_reactor_main","from_room":"spine_01","to_room":"reactor_01","from_cell":[8,0,1],"to_cell":[9,0,1],"module_id":"doorway_frame_open_1x1"}
]
```

Required `blocked_links`:

```json
[
  {"id":"spine_to_reactor_blocked_shortcut","from_room":"spine_01","to_room":"reactor_01","from_cell":[8,1,1],"to_cell":[9,1,1],"module_id":"doorway_frame_blocked_1x1","reason":"biomatter blockage"}
]
```

Required `vertical_connections`:

```json
[
  {"id":"ramp_01_to_spine_01","type":"ramp","module_id":"ramp_up_1x2","from_room":"ramp_01","from_cell":[4,0,0],"to_room":"spine_01","to_cell":[4,0,1]}
]
```

Required `landmarks`:

```json
[
  {"id":"spine_blue_beacon","room_id":"spine_01","kind":"orientation_beacon","position":[24.0,4.15,0.0],"color":"blue"},
  {"id":"reactor_green_core","room_id":"reactor_01","kind":"destination_core","position":[38.0,4.15,2.0],"color":"green"}
]
```

Required `critical_path`:

```json
["airlock_01", "corridor_01", "ramp_01", "spine_01", "reactor_01"]
```

- [ ] **Step 4: Create the golden `gameplay_slice.json` fixture**

Create `data/procgen/golden/coherent_ship_001/gameplay_slice.json` with exactly four ordered objectives so the current loader sequence assumptions stay compatible:

```json
{
  "schema_version": "1.1.0",
  "document_kind": "ship_gameplay_slice",
  "program_id": "coherent-proof-ship-001",
  "start_room": "airlock_01",
  "goal_room": "reactor_01",
  "critical_path": ["airlock_01", "corridor_01", "ramp_01", "spine_01", "reactor_01"],
  "objectives": [
    {
      "id": "cargo_01:cargo_supply_cache",
      "sequence": 1,
      "type": "recover_supplies",
      "room_id": "cargo_01",
      "room_role": "cargo",
      "placement_id": "cargo_supply_cache",
      "semantic": "loot_container",
      "cell": [6, -2, 1],
      "approach_cell": [6, -1, 1],
      "approach_distance_cells": 1,
      "interactable": true
    },
    {
      "id": "maintenance_01:maintenance_breaker_panel",
      "sequence": 2,
      "type": "restore_systems",
      "room_id": "maintenance_01",
      "room_role": "maintenance",
      "placement_id": "maintenance_breaker_panel",
      "semantic": "tool_locker",
      "cell": [6, 2, 1],
      "approach_cell": [6, 1, 1],
      "approach_distance_cells": 1,
      "interactable": true
    },
    {
      "id": "medbay_01:medbay_terminal",
      "sequence": 3,
      "type": "download_logs",
      "room_id": "medbay_01",
      "room_role": "medbay",
      "placement_id": "medbay_terminal",
      "semantic": "command_console",
      "cell": [8, -1, 1],
      "approach_cell": [7, -1, 1],
      "approach_distance_cells": 1,
      "interactable": true
    },
    {
      "id": "reactor_01:reactor_control_panel",
      "sequence": 4,
      "type": "stabilize_reactor",
      "room_id": "reactor_01",
      "room_role": "reactor",
      "placement_id": "reactor_control_panel",
      "semantic": "reactor_control_panel",
      "cell": [10, 1, 1],
      "approach_cell": [9, 1, 1],
      "approach_distance_cells": 1,
      "interactable": true
    }
  ],
  "summary": {
    "objective_count": 4,
    "role_count": 4,
    "roles": ["cargo", "maintenance", "medbay", "reactor"],
    "has_goal_room_objective": true,
    "passes": true
  }
}
```

- [ ] **Step 5: Run validator to verify GREEN**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/coherent_static_fixture_validator.gd
```

Expected:

```text
COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1
```

- [ ] **Step 6: Create proof log and record Task 1**

Create `docs/superpowers/proofs/coherent-proof-ship.md` with:

```markdown
# Coherent Proof Ship Evidence Log

Spec: `docs/superpowers/specs/2026-06-17-coherent-proof-ship-design.md`
Plan: `docs/superpowers/plans/2026-06-17-coherent-proof-ship.md`
Fixture: `data/procgen/golden/coherent_ship_001/`

## Task 1

Static fixture validation:

```text
COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1
```
```

Then run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add \
    data/procgen/golden/coherent_ship_001/layout.json \
    data/procgen/golden/coherent_ship_001/gameplay_slice.json \
    scripts/validation/coherent_static_fixture_validator.gd \
    docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "test: add coherent proof ship static fixture"
else
  printf '%s\n' 'NO_GIT Task 1 changed: data/procgen/golden/coherent_ship_001/layout.json data/procgen/golden/coherent_ship_001/gameplay_slice.json scripts/validation/coherent_static_fixture_validator.gd docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/synaptic_sea_coherent_proof_ship_no_git_changes.log
fi
```

---

### Task 2: Add loader metadata accessors without changing seed-17 behavior

**Files:**
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/coherent_loader_metadata_smoke.gd`
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md`

**Interfaces:**
- Consumes: golden fixture from Task 1.
- Produces these public methods on `GeneratedShipLoader`:
  - `get_room_center(room_id: String) -> Vector3`
  - `get_room_role(room_id: String) -> String`
  - `get_room_deck(room_id: String) -> int`
  - `get_critical_path() -> Array[String]`
  - `get_room_links() -> Array`
  - `get_blocked_links() -> Array`
  - `get_landmark_specs() -> Array`

- [ ] **Step 1: Write metadata smoke first**

Create `scripts/validation/coherent_loader_metadata_smoke.gd`:

```gdscript
extends SceneTree

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_PATH: String = "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"

func _initialize() -> void:
	var loader = LoaderScript.new()
	get_root().add_child(loader)
	var loaded: bool = loader.load_from_paths(LAYOUT_PATH, KIT_PATH, GAMEPLAY_PATH)
	if not loaded:
		push_error("COHERENT LOADER METADATA FAIL could not load golden fixture")
		quit(1)
		return
	if not loader.has_method("get_room_center"):
		push_error("COHERENT LOADER METADATA FAIL missing get_room_center")
		quit(1)
		return
	if loader.get_room_role("spine_01") != "main_spine":
		push_error("COHERENT LOADER METADATA FAIL expected spine_01 role main_spine got %s" % loader.get_room_role("spine_01"))
		quit(1)
		return
	if loader.get_room_deck("airlock_01") != 0 or loader.get_room_deck("spine_01") != 1:
		push_error("COHERENT LOADER METADATA FAIL deck mismatch airlock=%d spine=%d" % [loader.get_room_deck("airlock_01"), loader.get_room_deck("spine_01")])
		quit(1)
		return
	if loader.get_critical_path() != ["airlock_01", "corridor_01", "ramp_01", "spine_01", "reactor_01"]:
		push_error("COHERENT LOADER METADATA FAIL critical path mismatch %s" % str(loader.get_critical_path()))
		quit(1)
		return
	if loader.get_blocked_links().size() != 1:
		push_error("COHERENT LOADER METADATA FAIL blocked link count=%d" % loader.get_blocked_links().size())
		quit(1)
		return
	if loader.get_landmark_specs().size() < 2:
		push_error("COHERENT LOADER METADATA FAIL landmark spec count=%d" % loader.get_landmark_specs().size())
		quit(1)
		return
	var center: Vector3 = loader.get_room_center("reactor_01")
	if center == Vector3.INF:
		push_error("COHERENT LOADER METADATA FAIL reactor center unresolved")
		quit(1)
		return
	print("COHERENT LOADER METADATA PASS critical_path=%d blocked_links=%d landmarks=%d" % [loader.get_critical_path().size(), loader.get_blocked_links().size(), loader.get_landmark_specs().size()])
	loader.free()
	quit(0)
```

- [ ] **Step 2: Run metadata smoke to verify RED**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/coherent_loader_metadata_smoke.gd
```

Expected: FAIL with:

```text
COHERENT LOADER METADATA FAIL missing get_room_center
```

- [ ] **Step 3: Add metadata getters to `generated_ship_loader.gd`**

Add these public methods near existing getters after `get_objective_specs_copy()`:

```gdscript
func get_room_center(room_id: String) -> Vector3:
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return Vector3.INF
	return _room_center(rooms_variant as Array, room_id)

func get_room_role(room_id: String) -> String:
	var room: Dictionary = _find_room(layout_doc.get("rooms", []) as Array, room_id) if typeof(layout_doc.get("rooms", [])) == TYPE_ARRAY else {}
	return str(room.get("room_role", ""))

func get_room_deck(room_id: String) -> int:
	var room: Dictionary = _find_room(layout_doc.get("rooms", []) as Array, room_id) if typeof(layout_doc.get("rooms", [])) == TYPE_ARRAY else {}
	return int(room.get("deck", 0))

func get_critical_path() -> Array[String]:
	var path: Array[String] = []
	var path_variant: Variant = layout_doc.get("critical_path", gameplay_doc.get("critical_path", []))
	if typeof(path_variant) != TYPE_ARRAY:
		return path
	for room_variant in path_variant:
		path.append(str(room_variant))
	return path

func get_room_links() -> Array:
	var links_variant: Variant = layout_doc.get("room_links", [])
	return links_variant.duplicate(true) if typeof(links_variant) == TYPE_ARRAY else []

func get_blocked_links() -> Array:
	var links_variant: Variant = layout_doc.get("blocked_links", [])
	return links_variant.duplicate(true) if typeof(links_variant) == TYPE_ARRAY else []

func get_landmark_specs() -> Array:
	var landmarks_variant: Variant = layout_doc.get("landmarks", [])
	return landmarks_variant.duplicate(true) if typeof(landmarks_variant) == TYPE_ARRAY else []
```

If Godot rejects the inline typed ternary using `as Array`, split each method into explicit `if typeof(...)` branches. Do not change any existing method signature.

- [ ] **Step 4: Run metadata smoke to verify GREEN**

Run the same command as Step 2.

Expected:

```text
COHERENT LOADER METADATA PASS critical_path=5 blocked_links=1 landmarks=2
```

- [ ] **Step 5: Run existing seed-17 playable smoke as regression**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_playable_ship_smoke.gd
```

Expected output contains:

```text
PLAYABLE SHIP SMOKE PASS
```

- [ ] **Step 6: Append proof log and record Task 2**

Append the pass markers from Steps 4 and 5 to `docs/superpowers/proofs/coherent-proof-ship.md`, then run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add \
    scripts/procgen/generated_ship_loader.gd \
    scripts/validation/coherent_loader_metadata_smoke.gd \
    docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: expose coherent ship loader metadata"
else
  printf '%s\n' 'NO_GIT Task 2 changed: scripts/procgen/generated_ship_loader.gd scripts/validation/coherent_loader_metadata_smoke.gd docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/synaptic_sea_coherent_proof_ship_no_git_changes.log
fi
```

---

### Task 3: Add runtime nodes for landmarks, visible vertical transitions, and blocked routes

**Files:**
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/coherent_runtime_loader_smoke.gd`
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md`

**Interfaces:**
- Consumes: loader metadata getters from Task 2.
- Produces these public methods on `GeneratedShipLoader`:
  - `get_landmark_nodes() -> Array[Node3D]`
  - `get_blocked_route_nodes() -> Array[Node3D]`
  - `get_visible_vertical_transition_nodes() -> Array[Node3D]`
- Produces runtime node names:
  - `Landmark_<landmark_id>`
  - `BlockedRoute_<blocked_link_id>`
  - `VisibleVerticalTransition_<vertical_connection_id>`

- [ ] **Step 1: Write runtime loader smoke first**

Create `scripts/validation/coherent_runtime_loader_smoke.gd`:

```gdscript
extends SceneTree

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_PATH: String = "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"

func _initialize() -> void:
	var loader = LoaderScript.new()
	get_root().add_child(loader)
	if not loader.load_from_paths(LAYOUT_PATH, KIT_PATH, GAMEPLAY_PATH):
		push_error("COHERENT RUNTIME LOADER FAIL could not load fixture")
		quit(1)
		return
	if not loader.has_method("get_landmark_nodes"):
		push_error("COHERENT RUNTIME LOADER FAIL missing get_landmark_nodes")
		quit(1)
		return
	var landmark_count: int = loader.get_landmark_nodes().size()
	var blocked_count: int = loader.get_blocked_route_nodes().size()
	var transition_count: int = loader.get_visible_vertical_transition_nodes().size()
	if landmark_count < 2:
		push_error("COHERENT RUNTIME LOADER FAIL landmark nodes=%d" % landmark_count)
		quit(1)
		return
	if blocked_count != 1:
		push_error("COHERENT RUNTIME LOADER FAIL blocked route nodes=%d" % blocked_count)
		quit(1)
		return
	if transition_count != 1:
		push_error("COHERENT RUNTIME LOADER FAIL visible vertical transitions=%d" % transition_count)
		quit(1)
		return
	if loader.count_collision_shapes() <= 0:
		push_error("COHERENT RUNTIME LOADER FAIL collision_shapes=0")
		quit(1)
		return
	print("COHERENT RUNTIME LOADER PASS collision_shapes=%d landmarks=%d blocked_routes=%d visible_transitions=%d" % [loader.count_collision_shapes(), landmark_count, blocked_count, transition_count])
	loader.free()
	quit(0)
```

- [ ] **Step 2: Run runtime loader smoke to verify RED**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/coherent_runtime_loader_smoke.gd
```

Expected: FAIL with:

```text
COHERENT RUNTIME LOADER FAIL missing get_landmark_nodes
```

- [ ] **Step 3: Add node arrays and reset logic to `generated_ship_loader.gd`**

Add variables near existing `objective_volumes`:

```gdscript
var landmark_nodes: Array[Node3D] = []
var blocked_route_nodes: Array[Node3D] = []
var visible_vertical_transition_nodes: Array[Node3D] = []
```

Reset these in `clear_loaded_ship()`:

```gdscript
landmark_nodes = []
blocked_route_nodes = []
visible_vertical_transition_nodes = []
```

Add getters near Task 2 getters:

```gdscript
func get_landmark_nodes() -> Array[Node3D]:
	return landmark_nodes.duplicate()

func get_blocked_route_nodes() -> Array[Node3D]:
	return blocked_route_nodes.duplicate()

func get_visible_vertical_transition_nodes() -> Array[Node3D]:
	return visible_vertical_transition_nodes.duplicate()
```

- [ ] **Step 4: Create runtime marker helpers**

Add these helper methods to `generated_ship_loader.gd`:

```gdscript
func _add_coherence_runtime_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	_add_landmark_nodes(layout_doc, ship_root)
	_add_blocked_route_nodes(layout_doc, ship_root)
	_add_visible_vertical_transition_nodes(layout_doc, ship_root)

func _add_landmark_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var landmarks_variant: Variant = layout_doc.get("landmarks", [])
	if typeof(landmarks_variant) != TYPE_ARRAY:
		return
	for landmark_variant in landmarks_variant:
		if typeof(landmark_variant) != TYPE_DICTIONARY:
			continue
		var landmark: Dictionary = landmark_variant
		var pos: Vector3 = _vec3_from_array(landmark.get("position", []), Vector3.INF)
		if pos == Vector3.INF:
			continue
		var node: Node3D = _make_marker_node("Landmark_%s" % str(landmark.get("id", landmark_nodes.size())), pos, Color(0.15, 0.65, 1.0, 1.0), Vector3(0.8, 2.4, 0.8), true)
		ship_root.add_child(node)
		landmark_nodes.append(node)

func _add_blocked_route_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var links_variant: Variant = layout_doc.get("blocked_links", [])
	if typeof(links_variant) != TYPE_ARRAY:
		return
	for link_variant in links_variant:
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(link, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(link, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		var mid: Vector3 = (from_pos + to_pos) * 0.5
		var node: Node3D = _make_marker_node("BlockedRoute_%s" % str(link.get("id", blocked_route_nodes.size())), mid, Color(0.85, 0.2, 0.18, 1.0), Vector3(3.8, 2.0, 0.45), true)
		node.look_at(to_pos, Vector3.UP)
		ship_root.add_child(node)
		blocked_route_nodes.append(node)

func _add_visible_vertical_transition_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var links_variant: Variant = layout_doc.get("vertical_connections", [])
	if typeof(links_variant) != TYPE_ARRAY:
		return
	for link_variant in links_variant:
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(link, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(link, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		var mid: Vector3 = (from_pos + to_pos) * 0.5
		var node: Node3D = _make_marker_node("VisibleVerticalTransition_%s" % str(link.get("id", visible_vertical_transition_nodes.size())), mid, Color(0.9, 0.68, 0.25, 1.0), Vector3(4.0, 0.45, 5.5), true)
		node.look_at(to_pos, Vector3.UP)
		ship_root.add_child(node)
		visible_vertical_transition_nodes.append(node)

func _make_marker_node(node_name: String, world_position: Vector3, color: Color, size: Vector3, collidable: bool) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = node_name
	root.global_position = world_position
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.4
	mesh_instance.material_override = material
	mesh_instance.position.y = size.y * 0.5
	root.add_child(mesh_instance)
	if collidable:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "CollisionRoot"
		body.collision_layer = 1
		body.collision_mask = 1
		var shape_node: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = size
		shape_node.shape = box
		shape_node.position.y = size.y * 0.5
		body.add_child(shape_node)
		root.add_child(body)
	return root

func _vec3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() < 3:
		return fallback
	return Vector3(float(array[0]), float(array[1]), float(array[2]))
```

- [ ] **Step 5: Call coherence node helper after structural wrapper instantiation**

In `load_from_paths()`, after `_add_vertical_links(layout_doc, structural_root)` and before objective volume creation, add:

```gdscript
_add_coherence_runtime_nodes(layout_doc, structural_root)
```

Keep the existing `vertical_link_count` summary field unchanged.

- [ ] **Step 6: Run runtime loader smoke to verify GREEN**

Run the same command as Step 2.

Expected output contains:

```text
COHERENT RUNTIME LOADER PASS collision_shapes=
landmarks=2 blocked_routes=1 visible_transitions=1
```

The exact collision shape count can vary, but it must be greater than zero.

- [ ] **Step 7: Run static and seed-17 regressions**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/coherent_static_fixture_validator.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/procgen_playable_ship_smoke.gd
```

Expected outputs contain:

```text
COHERENT STATIC FIXTURE PASS
PLAYABLE SHIP SMOKE PASS
```

- [ ] **Step 8: Append proof log and record Task 3**

Append Task 3 pass markers to `docs/superpowers/proofs/coherent-proof-ship.md`, then run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add \
    scripts/procgen/generated_ship_loader.gd \
    scripts/validation/coherent_runtime_loader_smoke.gd \
    docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: add coherent proof runtime markers"
else
  printf '%s\n' 'NO_GIT Task 3 changed: scripts/procgen/generated_ship_loader.gd scripts/validation/coherent_runtime_loader_smoke.gd docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/synaptic_sea_coherent_proof_ship_no_git_changes.log
fi
```

---

### Task 4: Add a sibling playable scene for the coherent proof ship

**Files:**
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/playable_generated_ship.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/procgen/playable_coherent_ship.tscn`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/coherent_playable_scene_smoke.gd`
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md`

**Interfaces:**
- Consumes: runtime loader markers from Task 3.
- Produces scene: `res://scenes/procgen/playable_coherent_ship.tscn`.
- Produces method on `PlayableGeneratedShip`: `teleport_player_to_room_for_validation(room_id: String) -> bool`.

- [ ] **Step 1: Write playable scene smoke first**

Create `scripts/validation/coherent_playable_scene_smoke.gd`:

```gdscript
extends SceneTree

const PLAYABLE_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")

var playable_ship: PlayableGeneratedShip
var ready: bool = false
var failed: bool = false
var frame_count: int = 0

func _initialize() -> void:
	playable_ship = PLAYABLE_SCENE.instantiate() as PlayableGeneratedShip
	if playable_ship == null:
		push_error("COHERENT PLAYABLE SCENE FAIL could not instantiate playable_coherent_ship.tscn")
		quit(1)
		return
	playable_ship.playable_ready.connect(_on_ready)
	playable_ship.playable_failed.connect(_on_failed)
	get_root().add_child(playable_ship)
	physics_frame.connect(_on_physics_frame)

func _on_ready(summary: Dictionary) -> void:
	ready = true
	if not bool(summary.get("player_spawned", false)):
		_failed("player not spawned")
		return
	if int(summary.get("objective_count", 0)) != 4:
		_failed("expected 4 objectives got %d" % int(summary.get("objective_count", 0)))
		return
	if playable_ship.loader.get_critical_path().size() != 5:
		_failed("expected critical path size 5 got %d" % playable_ship.loader.get_critical_path().size())
		return
	if playable_ship.loader.get_landmark_nodes().size() < 2:
		_failed("expected at least 2 landmarks got %d" % playable_ship.loader.get_landmark_nodes().size())
		return
	print("COHERENT PLAYABLE SCENE READY player_spawned=true objectives=%d critical_path=%d landmarks=%d" % [int(summary.get("objective_count", 0)), playable_ship.loader.get_critical_path().size(), playable_ship.loader.get_landmark_nodes().size()])

func _on_failed(reason: String) -> void:
	_failed(reason)

func _on_physics_frame() -> void:
	frame_count += 1
	if failed:
		return
	if ready:
		print("COHERENT PLAYABLE SCENE PASS frames=%d" % frame_count)
		quit(0)
		return
	if frame_count > 180:
		_failed("timed out waiting for playable_ready")

func _failed(reason: String) -> void:
	failed = true
	push_error("COHERENT PLAYABLE SCENE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run playable scene smoke to verify RED**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/coherent_playable_scene_smoke.gd
```

Expected: FAIL because `res://scenes/procgen/playable_coherent_ship.tscn` does not exist.

- [ ] **Step 3: Export fixture path variables in `playable_generated_ship.gd`**

Change these vars:

```gdscript
var layout_path: String = DEFAULT_LAYOUT_PATH
var kit_path: String = DEFAULT_KIT_PATH
var gameplay_slice_path: String = DEFAULT_GAMEPLAY_SLICE_PATH
```

to:

```gdscript
@export var layout_path: String = DEFAULT_LAYOUT_PATH
@export var kit_path: String = DEFAULT_KIT_PATH
@export var gameplay_slice_path: String = DEFAULT_GAMEPLAY_SLICE_PATH
```

Add this validation helper after `complete_first_interaction_for_validation()`:

```gdscript
func teleport_player_to_room_for_validation(room_id: String) -> bool:
	if player == null or loader == null or not loader.has_method("get_room_center"):
		return false
	var room_center: Vector3 = loader.get_room_center(room_id)
	if room_center == Vector3.INF:
		return false
	player.teleport_to(room_center + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0))
	return true
```

- [ ] **Step 4: Create `playable_coherent_ship.tscn`**

Create `scenes/procgen/playable_coherent_ship.tscn`:

```text
[gd_scene load_steps=2 format=3 uid="uid://synaptic_sea_playable_coherent_ship"]

[ext_resource type="Script" path="res://scripts/procgen/playable_generated_ship.gd" id="1_playable_generated_ship"]

[node name="PlayableCoherentShip" type="Node3D"]
script = ExtResource("1_playable_generated_ship")
layout_path = "res://data/procgen/golden/coherent_ship_001/layout.json"
kit_path = "res://data/kits/ship_structural_v0.json"
gameplay_slice_path = "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"
```

- [ ] **Step 5: Run playable scene smoke to verify GREEN**

Run the same command as Step 2.

Expected output contains:

```text
COHERENT PLAYABLE SCENE READY player_spawned=true objectives=4 critical_path=5 landmarks=2
COHERENT PLAYABLE SCENE PASS
```

- [ ] **Step 6: Run existing playable smoke regression**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_playable_ship_smoke.gd
```

Expected output contains:

```text
PLAYABLE SHIP SMOKE PASS
```

- [ ] **Step 7: Append proof log and record Task 4**

Append Task 4 pass markers to `docs/superpowers/proofs/coherent-proof-ship.md`, then run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add \
    scripts/procgen/playable_generated_ship.gd \
    scenes/procgen/playable_coherent_ship.tscn \
    scripts/validation/coherent_playable_scene_smoke.gd \
    docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: add playable coherent proof ship scene"
else
  printf '%s\n' 'NO_GIT Task 4 changed: scripts/procgen/playable_generated_ship.gd scenes/procgen/playable_coherent_ship.tscn scripts/validation/coherent_playable_scene_smoke.gd docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/synaptic_sea_coherent_proof_ship_no_git_changes.log
fi
```

---

### Task 5: Add playable traversal validation for critical path, side room, blocker, and interaction

**Files:**
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/coherent_playable_traversal_smoke.gd`
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md`

**Interfaces:**
- Consumes: `playable_coherent_ship.tscn` from Task 4.
- Consumes: `PlayableGeneratedShip.teleport_player_to_room_for_validation(room_id: String) -> bool` from Task 4.
- Produces pass marker: `COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true`.

- [ ] **Step 1: Write traversal smoke**

Create `scripts/validation/coherent_playable_traversal_smoke.gd`:

```gdscript
extends SceneTree

const PLAYABLE_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]
const FLOOR_COLLISION_HALF_HEIGHT: float = 0.125
const MIN_PLAYER_CLEARANCE: float = 0.05

var playable_ship: PlayableGeneratedShip
var frame_count: int = 0
var ready: bool = false
var failed: bool = false

func _initialize() -> void:
	playable_ship = PLAYABLE_SCENE.instantiate() as PlayableGeneratedShip
	playable_ship.playable_ready.connect(_on_ready)
	playable_ship.playable_failed.connect(_on_failed)
	get_root().add_child(playable_ship)
	physics_frame.connect(_on_physics_frame)

func _on_ready(_summary: Dictionary) -> void:
	ready = true

func _on_failed(reason: String) -> void:
	_fail(reason)

func _on_physics_frame() -> void:
	frame_count += 1
	if failed:
		return
	if not ready:
		if frame_count > 240:
			_fail("timed out waiting for playable_ready")
		return
	_run_checks()

func _run_checks() -> void:
	var critical_path: Array[String] = playable_ship.loader.get_critical_path()
	for room_id in critical_path:
		if not playable_ship.teleport_player_to_room_for_validation(room_id):
			_fail("could not teleport to critical path room %s" % room_id)
			return
		if not _player_above_nearest_floor():
			_fail("player not above floor in critical path room %s" % room_id)
			return
	var side_rooms: Array[String] = ["cargo_01", "medbay_01", "maintenance_01"]
	for room_id in side_rooms:
		if not playable_ship.teleport_player_to_room_for_validation(room_id):
			_fail("could not teleport to side room %s" % room_id)
			return
		if not _player_above_nearest_floor():
			_fail("player not above floor in side room %s" % room_id)
			return
	if playable_ship.loader.get_blocked_route_nodes().is_empty():
		_fail("no blocked route nodes")
		return
	if not _blocked_route_has_collision(playable_ship.loader.get_blocked_route_nodes()[0]):
		_fail("blocked route has no collision")
		return
	if not playable_ship.complete_first_interaction_for_validation():
		_fail("objective interaction did not complete")
		return
	print("COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=%d side_rooms=%d blocked_route_blocked=true objective_completed=true" % [critical_path.size(), side_rooms.size()])
	quit(0)

func _player_above_nearest_floor() -> bool:
	var player_position: Vector3 = playable_ship.player.global_position
	var nearest_top: float = _nearest_floor_top_y(player_position)
	return nearest_top != INF and player_position.y >= nearest_top + MIN_PLAYER_CLEARANCE

func _nearest_floor_top_y(world_position: Vector3) -> float:
	var best_distance: float = INF
	var best_top_y: float = INF
	var rooms_variant: Variant = playable_ship.loader.layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return INF
	for room_variant in rooms_variant:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var placements_variant: Variant = room.get("structural_placements", [])
		if typeof(placements_variant) != TYPE_ARRAY:
			continue
		for placement_variant in placements_variant:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if not FLOOR_MODULES.has(module_id):
				continue
			var pos_variant: Variant = placement.get("position", [])
			if typeof(pos_variant) != TYPE_ARRAY:
				continue
			var pos: Array = pos_variant
			if pos.size() < 3:
				continue
			var placement_position: Vector3 = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			var distance: float = Vector2(placement_position.x - world_position.x, placement_position.z - world_position.z).length_squared()
			if distance < best_distance:
				best_distance = distance
				best_top_y = placement_position.y + FLOOR_COLLISION_HALF_HEIGHT
	return best_top_y

func _blocked_route_has_collision(node: Node) -> bool:
	if node is CollisionShape3D:
		var shape_node: CollisionShape3D = node as CollisionShape3D
		return shape_node.shape != null
	for child in node.get_children():
		if _blocked_route_has_collision(child):
			return true
	return false

func _fail(reason: String) -> void:
	failed = true
	push_error("COHERENT PLAYABLE TRAVERSAL FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run traversal smoke**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/coherent_playable_traversal_smoke.gd
```

Expected output:

```text
COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true
```

If it fails with `player not above floor`, fix floor placement coordinates or player spawn height in the fixture/scene. If it fails with `blocked route has no collision`, fix Task 3 blocked route marker creation.

- [ ] **Step 3: Run regression smokes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/floor_wrapper_collision_footprint_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/player_gravity_floor_snap_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/interactable_distance_fallback_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/procgen_playable_ship_smoke.gd
```

Expected pass markers:

```text
FLOOR WRAPPER COLLISION FOOTPRINT PASS checked=4
PLAYER GRAVITY FLOOR SNAP PASS
INTERACTABLE DISTANCE FALLBACK PASS completed_count=1
PLAYABLE SHIP SMOKE PASS
```

- [ ] **Step 4: Append proof log and record Task 5**

Append Task 5 pass markers to `docs/superpowers/proofs/coherent-proof-ship.md`, then run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add \
    scripts/validation/coherent_playable_traversal_smoke.gd \
    docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "test: verify coherent proof ship traversal"
else
  printf '%s\n' 'NO_GIT Task 5 changed: scripts/validation/coherent_playable_traversal_smoke.gd docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/synaptic_sea_coherent_proof_ship_no_git_changes.log
fi
```

---

### Task 6: Add fresh in-engine capture for the coherent proof ship

**Files:**
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/coherent_proof_ship_capture.gd`
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md`

**Interfaces:**
- Consumes: `res://scenes/procgen/playable_coherent_ship.tscn`.
- Produces PNG artifact at caller-provided output path.
- Produces pass marker: `COHERENT PROOF SHIP CAPTURE PASS output=/absolute/path/to/output.png frame=180 mode=viewport`.

- [ ] **Step 1: Write capture script**

Create `scripts/validation/coherent_proof_ship_capture.gd` by adapting `procgen_playable_ship_capture.gd` with these required changes:

```gdscript
const PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")
const DEFAULT_OUTPUT_PATH: String = "res://artifacts/validation-previews/coherent-proof-ship.png"
const DEFAULT_CAPTURE_FRAME: int = 180
```

The script must:

- Parse `--output PATH` and `--capture-frame N` from `OS.get_cmdline_user_args()`.
- Instantiate `PLAYABLE_SHIP_SCENE`.
- Wait for `playable_ready`.
- Advance frames until `capture_frame`.
- Capture the root viewport image.
- Save PNG to the requested output path, globalizing `res://` paths.
- Print exactly:

```text
COHERENT PROOF SHIP CAPTURE PASS output=<absolute_path> frame=<frame> mode=viewport
```

Do not overwrite or delete `procgen_playable_ship_capture.gd`.

- [ ] **Step 2: Run capture script**

Run:

```bash
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/coherent_proof_ship_capture.gd \
  -- \
  --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png \
  --capture-frame 180
```

Expected output contains:

```text
COHERENT PROOF SHIP CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png frame=180 mode=viewport
```

- [ ] **Step 3: Verify PNG metadata**

Run:

```bash
sips -g pixelWidth -g pixelHeight -g format /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png
printf '\nsha256: '
shasum -a 256 /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png | awk '{print $1}'
```

Expected:

```text
pixelWidth: 1280
pixelHeight: 720
format: png
sha256: <64 hex characters>
```

- [ ] **Step 4: Open capture for human review**

Run:

```bash
open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png
```

Human review criteria from the spec:

```text
The capture must read as one connected derelict ship area, not disconnected boxes. Preferably visible: player marker, central spine, one side branch, one landmark, and vertical transition or reactor destination.
```

- [ ] **Step 5: Append proof log and record Task 6**

Append capture command, pass marker, PNG metadata, and human review note to `docs/superpowers/proofs/coherent-proof-ship.md`, then run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add \
    scripts/validation/coherent_proof_ship_capture.gd \
    docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "test: capture coherent proof ship viewport"
else
  printf '%s\n' 'NO_GIT Task 6 changed: scripts/validation/coherent_proof_ship_capture.gd docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/synaptic_sea_coherent_proof_ship_no_git_changes.log
fi
```

---

### Task 7: Run final regression bundle and document acceptance

**Files:**
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md`

**Interfaces:**
- Consumes all validation scripts and fixtures from Tasks 1–6.
- Produces final proof log section with every pass marker and capture path.

- [ ] **Step 1: Run coherent proof validation bundle**

Run:

```bash
set -o pipefail
for script in \
  res://scripts/validation/coherent_static_fixture_validator.gd \
  res://scripts/validation/coherent_loader_metadata_smoke.gd \
  res://scripts/validation/coherent_runtime_loader_smoke.gd \
  res://scripts/validation/coherent_playable_scene_smoke.gd \
  res://scripts/validation/coherent_playable_traversal_smoke.gd; do
  echo "=== $script ==="
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 \
    --headless \
    --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
    --script "$script"
done
```

Expected pass markers:

```text
COHERENT STATIC FIXTURE PASS
COHERENT LOADER METADATA PASS
COHERENT RUNTIME LOADER PASS
COHERENT PLAYABLE SCENE PASS
COHERENT PLAYABLE TRAVERSAL PASS
```

- [ ] **Step 2: Run existing regression bundle**

Run:

```bash
set -o pipefail
for script in \
  res://scripts/validation/floor_wrapper_collision_footprint_smoke.gd \
  res://scripts/validation/player_gravity_floor_snap_smoke.gd \
  res://scripts/validation/interactable_distance_fallback_smoke.gd \
  res://scripts/validation/procgen_playable_ship_smoke.gd; do
  echo "=== $script ==="
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 \
    --headless \
    --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
    --script "$script"
done
```

Expected pass markers:

```text
FLOOR WRAPPER COLLISION FOOTPRINT PASS
PLAYER GRAVITY FLOOR SNAP PASS
INTERACTABLE DISTANCE FALLBACK PASS
PLAYABLE SHIP SMOKE PASS
```

- [ ] **Step 3: Run final capture command again**

Run the Task 6 capture command again to ensure the artifact is fresh after all code changes.

Expected:

```text
COHERENT PROOF SHIP CAPTURE PASS
```

- [ ] **Step 4: Update proof log with final acceptance checklist**

Append this checklist to `docs/superpowers/proofs/coherent-proof-ship.md` and mark each item with the evidence line from Steps 1–3:

```markdown
## Final Acceptance Checklist

- [ ] Named coherent proof ship fixture exists.
- [ ] Fixture contains 5–8 meaningful rooms or segments.
- [ ] Fixture uses existing loader/playable path.
- [ ] Player can traverse entry to reactor/destination.
- [ ] Visible elevation transition exists.
- [ ] Visible blocked route exists and has collision.
- [ ] Landmark/orientation anchor exists.
- [ ] At least one side room is reachable.
- [ ] Static fixture validation passes.
- [ ] Runtime loader validation passes.
- [ ] Playable traversal validation passes.
- [ ] Fresh Godot viewport capture exists.
- [ ] Existing seed-17 playable smoke still passes.
```

- [ ] **Step 5: Record Task 7**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "docs: record coherent proof ship acceptance"
else
  printf '%s\n' 'NO_GIT Task 7 changed: docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/synaptic_sea_coherent_proof_ship_no_git_changes.log
fi
```

---

## Plan Self-Review Checklist

Before execution begins, verify this plan against the spec:

- Spec goal maps to Tasks 1–7.
- Named fixture requirement maps to Task 1.
- Existing loader/playable path requirement maps to Tasks 2–4.
- Visible vertical transition requirement maps to Tasks 1, 3, 5, and 7.
- Visible blocked route requirement maps to Tasks 1, 3, 5, and 7.
- Landmark requirement maps to Tasks 1, 3, 4, and 7.
- Player traversal requirement maps to Tasks 4–5.
- Fresh capture requirement maps to Task 6.
- Existing regression requirement maps to Tasks 2, 3, 5, and 7.
- No broad random-generator rewrite is present.
- No combat, inventory, oxygen, repair, save/load, production art, or multi-seed statistics are included.
