# Phase 5b — Physical Docking & Port Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ship docking physical in the running game — replace menu-teleport travel with a runtime undock→generate→port-aligned-dock loop where the piloted ship is a real ride, and add typed dock ports with a condition-gated, welding-speeded forced-entry breach.

**Architecture:** Uniform `ShipInstance` world entities (5a model) + a `piloted_ship` pointer parameterizing travel + a general dock-edge graph for persistence. `DockingManager.dock()` (already pure, smoke-only today) is finally called from the live game at boot and travel via a local→world host-port lift. Occupancy becomes spatially real by deriving `interior_aabb()` from built room-node positions. A `DockPortBarrier` (mirrors `RepairPoint`) gates boarding.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes (one PASS marker per smoke = the contract).

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`. Run smokes headless; trust the PASS marker, never the exit code (`--script` exits 0 on parse errors).
- **Allowlisted teardown noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit`. The save/load smoke additionally emits one expected `WARNING: SaveLoadService: save file rejected by from_dict`. **Any other `ERROR:`/`WARNING:` line — including "resources still in use at exit" leaks — blocks completion.**
- **Class-cache portability:** never use a bare `ClassName.new()` or `: ClassName` annotation for a project `class_name` script across files under `--headless --script`. Construct via a `preload(...)` const + `.new()`/static call, or `load("res://…").new()` (see `ShipInstance.create`, `WorldSnapshot.from_dict`).
- **Model/Node separation:** pure logic (`DockPorts`, `ShipOccupancy`, `DockingManager`) stays `RefCounted`, scene-tree-free, unit-testable. Scene consequences live in nodes/coordinator.
- **Forward constraint (binding):** no "single active ship" assumption in the docking/travel/occupancy/persistence *interfaces*. Travel is "the **piloted ship** undocks from its host and docks to a target," never "the lifeboat travels." At-most-two-loaded is a content bound, not an architectural cap; dock relationships persist as a **general edge set** over N ships.
- **Selective commits only** (`git add <paths>`); never `git add -A`. Never commit `project.godot`, `.godot/`, `*.uid`, or `addons/`. Conventional Commits; commit-message trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **DockingManager port-space contract (already documented in `docking_manager.gd`):** `host_port` is WORLD-space; `mobile_port` is MOBILE-LOCAL. A non-origin host's local port must be lifted to world before `dock()`.
- **`project.godot` working-tree drift:** the user's local `project.godot` adds an `MCPRuntime` autoload that fails headless. Before running the full regression bundle / Gate-1, `git stash push -- project.godot`, run, then `git stash pop`. Do NOT revert or commit the drift.

---

## File Structure

- **`scripts/systems/dock_ports.gd`** (modify) — typed port descriptors + `ports_compatible` + `condition_from_seed`. Pure.
- **`scripts/systems/ship_instance.gd`** (modify) — `interior_aabb()` reworked to derive from room-node positions (robust off-tree/headless).
- **`scripts/systems/docking_manager.gd`** (modify) — add static `host_port_to_world(host_inst, local_port)` world-lift helper. Pure dock math unchanged.
- **`scripts/tools/dock_port_barrier.gd`** (create) — `DockPortBarrier extends Area3D`; the closed-seam interactable. Mirrors `RepairPoint`'s channel.
- **`scripts/procgen/playable_generated_ship.gd`** (modify) — runtime docking at boot+travel, `piloted_ship` pointer, travel re-expression, occupancy-driven context, barrier spawn + interact routing, persistence wiring.
- **`scripts/systems/world_snapshot.gd`** (modify) — dock-edge set + piloted pointer + occupancy + opened-ports; version bump.
- **`scripts/validation/*`** (create) — new smokes; register in `docs/game/06_validation_plan.md`.
- **`docs/game/adr/0017-physical-docking-and-ports.md`** (create); **`docs/game/09_system_roadmap.md`** (modify — fix stale System 5 status).

---

### Task 1: Typed DockPort descriptor + compatibility

**Files:**
- Modify: `scripts/systems/dock_ports.gd`
- Test: `scripts/validation/dock_port_types_smoke.gd` (create)

**Interfaces:**
- Produces:
  - `DockPorts.for_lifeboat(layout: Dictionary) -> Dictionary` and `for_derelict(layout: Dictionary, seed_value: int = 0, condition_class: int = 0) -> Dictionary` — each now returns `{position: Vector3, facing: Vector3, type: String, size_class: int, condition: String}`. `type` is `"airlock"` for both; lifeboat `condition` is always `"intact"`; derelict `condition` is `condition_from_seed(...)`. `size_class` is `1` for both. Returns `{}` when the room is absent (unchanged).
  - `DockPorts.ports_compatible(a: Dictionary, b: Dictionary) -> bool` — true iff both non-empty, `a.type == b.type`, and `a.size_class == b.size_class`.
  - `DockPorts.condition_from_seed(seed_value: int, condition_class: int) -> String` — `"broken"` when a derelict is in poor condition, else `"intact"`. Deterministic.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/dock_port_types_smoke.gd`:

```gdscript
extends SceneTree

const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	# Lifeboat airlock port from the fixed lifeboat layout.
	var lb_layout: Dictionary = LifeBoatBuilderScript.build_layout()
	var lb_port: Dictionary = DockPortsScript.for_lifeboat(lb_layout)
	if lb_port.is_empty() or str(lb_port.get("type", "")) != "airlock" or int(lb_port.get("size_class", -1)) != 1 or str(lb_port.get("condition", "")) != "intact":
		ok = false; msg = "lifeboat port malformed: %s" % str(lb_port)

	# condition_from_seed is deterministic and yields both values across the class range.
	if ok:
		var intact := DockPortsScript.condition_from_seed(123, 0)   # good condition -> intact
		var broken := DockPortsScript.condition_from_seed(123, 3)   # poor condition -> broken
		if intact != "intact" or broken != "broken":
			ok = false; msg = "condition_from_seed wrong: intact=%s broken=%s" % [intact, broken]
		# Determinism: same inputs, same output.
		if ok and DockPortsScript.condition_from_seed(123, 3) != broken:
			ok = false; msg = "condition_from_seed not deterministic"

	# Compatibility matrix.
	if ok:
		var airlock_a := {"type": "airlock", "size_class": 1}
		var airlock_b := {"type": "airlock", "size_class": 1}
		var hangar := {"type": "hangar", "size_class": 1}
		var big_airlock := {"type": "airlock", "size_class": 2}
		if not DockPortsScript.ports_compatible(airlock_a, airlock_b):
			ok = false; msg = "airlock<->airlock should be compatible"
		if ok and DockPortsScript.ports_compatible(airlock_a, hangar):
			ok = false; msg = "airlock<->hangar should be incompatible (type)"
		if ok and DockPortsScript.ports_compatible(airlock_a, big_airlock):
			ok = false; msg = "airlock<->airlock size mismatch should be incompatible"
		if ok and DockPortsScript.ports_compatible({}, airlock_b):
			ok = false; msg = "empty port should be incompatible"

	if ok:
		print("DOCK PORT TYPES PASS compat=true condition_from_seed=true typed=true")
		quit(0)
	else:
		push_error("DOCK PORT TYPES FAIL reason=%s" % msg)
		quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_port_types_smoke.gd`
Expected: FAIL (`DOCK PORT TYPES FAIL …` or a parse error referencing `ports_compatible`/`condition_from_seed`) — those functions and the new fields don't exist yet.

- [ ] **Step 3: Implement the typed descriptors**

In `scripts/systems/dock_ports.gd`, change `for_lifeboat`/`for_derelict` to carry the new fields and add the two new static helpers. Replace lines 10–21 with:

```gdscript
const AIRLOCK_SIZE_CLASS: int = 1

static func for_lifeboat(layout: Dictionary) -> Dictionary:
	var center: Vector3 = _room_floor_center(layout, "airlock", "airlock")
	if center == Vector3.INF:
		return {}
	# Airlock opening faces the dock (-X, away from the +X cockpit); nudge to the edge.
	return {
		"position": center + Vector3(-HALF_CELL, 0.0, 0.0),
		"facing": Vector3(-1.0, 0.0, 0.0),
		"type": "airlock",
		"size_class": AIRLOCK_SIZE_CLASS,
		"condition": "intact",
	}

static func for_derelict(layout: Dictionary, seed_value: int = 0, condition_class: int = 0) -> Dictionary:
	var center: Vector3 = _room_floor_center(layout, "dock", "dock")
	if center == Vector3.INF:
		return {}
	return {
		"position": center,
		"facing": Vector3(1.0, 0.0, 0.0),
		"type": "airlock",
		"size_class": AIRLOCK_SIZE_CLASS,
		"condition": condition_from_seed(seed_value, condition_class),
	}

## True iff both ports are non-empty, the same type, and the same size class.
## Forward-structured: hangar/cargo_clamp are valid types here, just not yet spawned.
static func ports_compatible(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if str(a.get("type", "")) != str(b.get("type", "")):
		return false
	return int(a.get("size_class", -1)) == int(b.get("size_class", -2))

## Deterministic port condition. A derelict in poor condition (condition_class >= 2,
## matching ShipBlueprint's worst tiers) has a broken dock port that needs a breach.
## condition_class 0..1 (intact/light) -> intact; 2..3 (heavy/wreck) -> broken.
static func condition_from_seed(seed_value: int, condition_class: int) -> String:
	return "broken" if condition_class >= 2 else "intact"
```

- [ ] **Step 4: Run the smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_port_types_smoke.gd`
Expected: `DOCK PORT TYPES PASS compat=true condition_from_seed=true typed=true` and no non-allowlisted ERROR/WARNING.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/dock_ports.gd scripts/validation/dock_port_types_smoke.gd
git commit -m "feat(docking): typed dock ports + compatibility + condition-from-seed

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Real interior AABB from room-node positions

**Files:**
- Modify: `scripts/systems/ship_instance.gd:122-146` (`interior_aabb` + helper)
- Test: `scripts/validation/interior_aabb_smoke.gd` (create)

**Why:** Occupancy now decides which hull the player is in (they walk across, not teleport). Today `interior_aabb()` relies on in-tree `VisualInstance3D.get_aabb()`, which yields a zero-size AABB in headless (the bug 5a worked around with the away_from_start lockstep). Derive the AABB from the `ShipStructure` room-node *positions* — robust regardless of mesh rendering or in-tree state.

**Interfaces:**
- Produces: `ShipInstance.interior_aabb() -> AABB` (same signature). Now: locate the structure container (`scene_root.get_node_or_null("ShipStructure")`, else first child with children), union a per-room box around each room `Node3D` child's local `position` (half-extent `ROOM_HALF_EXTENT` in X/Z, `ROOM_HALF_HEIGHT` in Y), then transform the merged local AABB by `scene_root`'s world transform (`global_transform` when in-tree, else identity at `position`). Null/empty scene_root or no rooms → zero-size AABB at the root origin (unchanged fallback contract).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/interior_aabb_smoke.gd`:

```gdscript
extends SceneTree

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	# Build a real lifeboat structure and place its root off-origin.
	var root: Node3D = LifeBoatBuilderScript.build()
	root.position = Vector3(-35.0, 0.0, 0.0)
	get_root().add_child(root)   # in-tree so global_transform is valid

	var inst = ShipInstanceScript.create("lb", "", null, null, root)
	var aabb: AABB = inst.interior_aabb()

	# Must be a real, non-degenerate volume (the 5a bug returned a zero-size AABB here).
	if aabb.size.x <= 0.1 or aabb.size.z <= 0.1:
		ok = false; msg = "AABB degenerate: %s" % str(aabb)

	# Must be centered near the placed world position (-35 on X), not at origin.
	if ok and absf(aabb.get_center().x - (-35.0)) > 20.0:
		ok = false; msg = "AABB not at world position: center=%s" % str(aabb.get_center())

	# A point inside the placed hull is contained; a far point is not.
	if ok and not aabb.grow(0.001).has_point(Vector3(-35.0, 0.5, 0.0)):
		ok = false; msg = "expected interior point not contained: %s" % str(aabb)
	if ok and aabb.has_point(Vector3(100.0, 0.0, 0.0)):
		ok = false; msg = "far point wrongly contained"

	root.free()

	if ok:
		print("INTERIOR AABB PASS nondegenerate=true positioned=true contains=true")
		quit(0)
	else:
		push_error("INTERIOR AABB FAIL reason=%s" % msg)
		quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/interior_aabb_smoke.gd`
Expected: FAIL `INTERIOR AABB FAIL reason=AABB degenerate …` (current implementation finds no contributing in-tree VisualInstance AABB and returns a zero-size box).

- [ ] **Step 3: Rework `interior_aabb`**

In `scripts/systems/ship_instance.gd`, replace the `interior_aabb`/`_visual_descendants` block (lines 122–146) with a room-position derivation. Keep the docstring intent but update it:

```gdscript
const ROOM_HALF_EXTENT: float = 4.0   # generous per-room half-box in X/Z (covers 2x1 rooms + module chains)
const ROOM_HALF_HEIGHT: float = 3.0   # half deck height + headroom

## World-space AABB enclosing this ship's interior, derived from the built
## ShipStructure's room-node LOCAL positions (robust off-tree / headless, where
## VisualInstance3D world AABBs are unresolved). The merged local AABB is
## transformed by scene_root's world transform.
##
## Null/empty scene_root or no room nodes -> zero-size AABB at the root origin
## (the "unbuilt retained instance" fallback).
func interior_aabb() -> AABB:
	if scene_root == null or not is_instance_valid(scene_root):
		return AABB()
	var structure: Node = scene_root.get_node_or_null("ShipStructure")
	if structure == null:
		for c in scene_root.get_children():
			if c.get_child_count() > 0:
				structure = c
				break
	var local := AABB()
	var seeded := false
	if structure != null:
		for room_node in structure.get_children():
			if not (room_node is Node3D):
				continue
			var p: Vector3 = (room_node as Node3D).position
			var box := AABB(p - Vector3(ROOM_HALF_EXTENT, ROOM_HALF_HEIGHT, ROOM_HALF_EXTENT),
				Vector3(ROOM_HALF_EXTENT, ROOM_HALF_HEIGHT, ROOM_HALF_EXTENT) * 2.0)
			if not seeded:
				local = box
				seeded = true
			else:
				local = local.merge(box)
	if not seeded:
		var o: Vector3 = scene_root.global_position if scene_root.is_inside_tree() else scene_root.position
		return AABB(o, Vector3.ZERO)
	var xform: Transform3D = scene_root.global_transform if scene_root.is_inside_tree() else Transform3D(Basis(), scene_root.position)
	return xform * local
```

(Remove the now-unused `_visual_descendants` helper.)

- [ ] **Step 4: Run the smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/interior_aabb_smoke.gd`
Expected: `INTERIOR AABB PASS nondegenerate=true positioned=true contains=true`.

- [ ] **Step 5: Re-run the existing occupancy + canonical-opening smokes (regression guard)**

The reworked AABB feeds occupancy. Confirm 5a's occupancy smokes still pass:

Run:
```
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_occupancy_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/occupancy_flip_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/canonical_opening_smoke.gd
```
Expected: each prints its existing PASS marker. If `occupancy_flip_smoke` now resolves differently, the AABB extents are wrong — adjust `ROOM_HALF_EXTENT` and re-run; do not weaken the new smoke.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/ship_instance.gd scripts/validation/interior_aabb_smoke.gd
git commit -m "feat(docking): derive interior_aabb from room-node positions (real occupancy)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: World-lift helper + runtime port-aligned dock at boot

**Files:**
- Modify: `scripts/systems/docking_manager.gd` (add `host_port_to_world`)
- Modify: `scripts/procgen/playable_generated_ship.gd:1716-1749` (`_build_lifeboat_at_home`)
- Test: `scripts/validation/boot_dock_aligned_smoke.gd` (create)

**Interfaces:**
- Consumes: `DockPorts.for_lifeboat`, `DockPorts.for_derelict` (Task 1); `DockingManager.dock` (existing).
- Produces:
  - `DockingManager.host_port_to_world(host_inst, local_port: Dictionary) -> Dictionary` (static) — lifts a ship-LOCAL port to WORLD via `host_inst.scene_root.global_transform`. Returns `{}` if the host has no in-tree scene_root or the port is empty.
  - `_build_lifeboat_at_home()` now positions the lifeboat via `DockingManager.dock(home_ship, lifeboat_ship, world_host_port, lifeboat_local_port)` instead of the fixed `LIFEBOAT_DOCK_OFFSET`. Sets `piloted_ship = lifeboat_ship` (new coordinator field; see Task 5).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/boot_dock_aligned_smoke.gd` — boots the main scene and asserts the lifeboat's airlock port is coincident (flush) with the home derelict's dock port in world space, instead of parked at the fixed -35 offset:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const DockingManagerScript := preload("res://scripts/systems/docking_manager.gd")
const TIMEOUT_FRAMES: int = 300
var main_node: Node
var frame := 0
var done := false
var code := 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if done: return
	frame += 1
	var p = _find(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame > TIMEOUT_FRAMES: _fail("no playable")
		return
	_run(p)

func _run(p) -> void:
	var home = p.get_home_ship_for_validation()
	var lb = p.get_lifeboat_ship_for_validation()
	if home == null or lb == null: _fail("missing home/lifeboat"); return
	if lb.parent_ship != home: _fail("lifeboat not docked to home"); return

	# Host dock port lifted to world, and lifeboat airlock port lifted to world via the
	# lifeboat's actual placed transform, must be coincident (flush dock — NOT the old
	# fixed -35 offset which left a ~30u gap).
	var home_local = DockPortsScript.for_derelict(home.blueprint_layout_for_validation())
	var host_world = DockingManagerScript.host_port_to_world(home, home_local)
	var lb_local = DockPortsScript.for_lifeboat(lb.blueprint_layout_for_validation())
	var lb_world: Vector3 = lb.scene_root.global_transform * (lb_local["position"] as Vector3)
	var gap: float = lb_world.distance_to(host_world["position"] as Vector3)
	if gap > 0.5:
		_fail("lifeboat airlock not flush to home dock (gap=%.2f)" % gap); return

	done = true
	print("BOOT DOCK ALIGNED PASS flush=true gap_lt_0p5=true")
	_teardown(0)

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null

func _fail(r: String) -> void:
	if done: return
	done = true
	push_error("BOOT DOCK ALIGNED FAIL reason=%s" % r)
	_teardown(1)

func _teardown(c: int) -> void:
	code = c
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(code)
```

This smoke needs two read seams on the coordinator/ShipInstance: `get_home_ship_for_validation()` and `get_lifeboat_ship_for_validation()` already exist (used by `canonical_opening_smoke`). Add a `blueprint_layout_for_validation()` seam on `ShipInstance` in Step 3 that returns the layout dict its scene_root was built from.

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/boot_dock_aligned_smoke.gd`
Expected: FAIL — either a parse error on the missing `host_port_to_world` / `blueprint_layout_for_validation`, or `gap=…` ~30 (the current fixed-offset boot leaves a large gap).

- [ ] **Step 3: Add the world-lift helper and the layout seam**

In `scripts/systems/docking_manager.gd`, append:

```gdscript
## Lifts a ship-LOCAL dock port to WORLD space via the host's placed transform.
## host_inst.scene_root must be in the scene tree for global_transform to be valid.
## Returns {} when the host has no valid in-tree scene_root or local_port is empty.
static func host_port_to_world(host_inst, local_port: Dictionary) -> Dictionary:
	if host_inst == null or local_port.is_empty():
		return {}
	if not ("scene_root" in host_inst):
		return {}
	var root = host_inst.scene_root
	if root == null or not is_instance_valid(root) or not (root is Node3D) or not (root as Node3D).is_inside_tree():
		return {}
	var x: Transform3D = (root as Node3D).global_transform
	return {
		"position": x * (local_port.get("position", Vector3.ZERO) as Vector3),
		"facing": (x.basis * (local_port.get("facing", Vector3.FORWARD) as Vector3)).normalized(),
		"type": str(local_port.get("type", "airlock")),
		"size_class": int(local_port.get("size_class", 1)),
		"condition": str(local_port.get("condition", "intact")),
	}
```

In `scripts/systems/ship_instance.gd`, add a stored layout + seam. Add field near line 19:

```gdscript
var built_layout: Dictionary = {}   # the layout dict scene_root was built from (for dock-port derivation)
```

and method:

```gdscript
## Validation/runtime seam: the layout dict this ship's scene_root was built from.
func blueprint_layout_for_validation() -> Dictionary:
	return built_layout
```

- [ ] **Step 4: Wire boot docking in the coordinator**

In `scripts/procgen/playable_generated_ship.gd`, add the preload and field near the other preloads/vars (top of file, alongside line 34/145):

```gdscript
const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const DockingManagerScript := preload("res://scripts/systems/docking_manager.gd")
```
```gdscript
var piloted_ship = null   # the ShipInstance the player currently pilots (the lifeboat this cycle)
```

Set `home_ship.built_layout` and `lifeboat_ship.built_layout` wherever each scene_root is built (home: where the home loader's layout is available — store `loader.get_layout_copy()` if such a seam exists, else the golden layout dict used to build it; lifeboat: `LifeBoatBuilderScript.build_layout()`).

Replace the fixed-offset positioning in `_build_lifeboat_at_home` (lines 1745-1749) — instead of `lb_root.position = LIFEBOAT_DOCK_OFFSET; add_child(lb_root)`, add to tree first (so transforms resolve) then dock:

```gdscript
	lifeboat_ship.built_layout = LifeBoatBuilderScript.build_layout()
	# Add to the scene tree FIRST so host/mobile global_transforms resolve, then
	# port-align the lifeboat to the home dock via DockingManager (replaces the
	# fixed LIFEBOAT_DOCK_OFFSET hack — boot is now a real port-aligned dock).
	add_child(lb_root)
	piloted_ship = lifeboat_ship
	_dock_piloted_to(home_ship)
```

Add the shared docking helper (used here and by travel in Task 5):

```gdscript
## Port-aligns piloted_ship's airlock to host's dock port and writes the dock
## relationship. host.scene_root must be in-tree. Returns the dock() result dict.
func _dock_piloted_to(host) -> Dictionary:
	if piloted_ship == null or host == null or host.scene_root == null:
		return {"success": false, "reason": "dock_failed"}
	var host_local: Dictionary = DockPortsScript.for_derelict(host.built_layout, _ship_seed(host), _ship_condition_class(host))
	var host_world: Dictionary = DockingManagerScript.host_port_to_world(host, host_local)
	var mobile_local: Dictionary = DockPortsScript.for_lifeboat(piloted_ship.built_layout)
	if not DockPortsScript.ports_compatible(host_world, mobile_local):
		return {"success": false, "reason": "dock_incompatible"}
	return DockingManagerScript.dock(host, piloted_ship, host_world, mobile_local)

func _ship_seed(inst) -> int:
	if inst != null and inst.blueprint != null and ("seed_value" in inst.blueprint):
		return int(inst.blueprint.seed_value)
	return 0

func _ship_condition_class(inst) -> int:
	if inst != null and inst.blueprint != null and ("condition" in inst.blueprint):
		return int(inst.blueprint.condition)
	return 0
```

Note: the home (starting) derelict is unfixable but its dock port to the lifeboat is the player's home dock — force its boot condition to `intact` so the player is never breach-gated out of their own home. In `_dock_piloted_to`, when `host == home_ship`, pass `condition_class = 0`. Implement by branching: `var cc := 0 if host == home_ship else _ship_condition_class(host)`.

- [ ] **Step 5: Run the boot smoke + the canonical-opening smoke**

Run:
```
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/boot_dock_aligned_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/canonical_opening_smoke.gd
```
Expected: `BOOT DOCK ALIGNED PASS flush=true gap_lt_0p5=true` and the existing `CANONICAL OPENING PASS …`. The canonical-opening smoke's repair-point-near-lifeboat-room guard must still hold (the lifeboat moved from -35 to the flush position; the repair points derive from the lifeboat's built rooms, so they move with it — confirm no regression).

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/docking_manager.gd scripts/systems/ship_instance.gd scripts/procgen/playable_generated_ship.gd scripts/validation/boot_dock_aligned_smoke.gd
git commit -m "feat(docking): port-aligned lifeboat dock at boot via DockingManager (retire fixed offset)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: DockPortBarrier breach interactable

**Files:**
- Create: `scripts/tools/dock_port_barrier.gd`
- Test: `scripts/validation/dock_breach_smoke.gd` (create)

**Interfaces:**
- Produces: `DockPortBarrier extends Area3D` with:
  - `signal breach_opened(marker_id: String)`
  - `configure(p_marker_id: String, p_condition: String, p_player_progression, world_position: Vector3, p_breach_seconds: float, radius := 1.8) -> void`
  - `try_start(player_body: Node) -> bool` — intact port: opens immediately (one interact), returns true. Broken: starts a welding-speeded channel, returns true if started. Already-open: returns false.
  - `advance_channel(delta: float) -> void` (drives the channel deterministically for tests)
  - `set_opened(value: bool) -> void`, `opened: bool`, `channeling: bool`, `progress: float`
  - Welding skill speeds the channel (mirrors `RepairPoint`'s `1.0 + 0.1 * skill` factor); no parts consumed; completing grants `welding` XP.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/dock_breach_smoke.gd` (pure node test — no main scene):

```gdscript
extends SceneTree

const DockPortBarrierScript := preload("res://scripts/tools/dock_port_barrier.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	# Intact barrier: one try_start opens immediately.
	var intact = DockPortBarrierScript.new()
	get_root().add_child(intact)
	intact.configure("m1", "intact", null, Vector3.ZERO, 6.0, 1.8)
	var player := PlayerControllerScript.new()
	get_root().add_child(player)
	player.teleport_to(Vector3.ZERO)
	if not intact.try_start(player) or not intact.opened:
		ok = false; msg = "intact barrier did not open on one interact"

	# Broken barrier: try_start begins a channel (not yet open); channel completes to open.
	if ok:
		var broken = DockPortBarrierScript.new()
		get_root().add_child(broken)
		broken.configure("m2", "broken", null, Vector3.ZERO, 6.0, 1.8)
		if not broken.try_start(player):
			ok = false; msg = "broken barrier did not start channel"
		elif broken.opened:
			ok = false; msg = "broken barrier opened without channel"
		else:
			broken.advance_channel(10.0)   # exceed breach_seconds
			if not broken.opened:
				ok = false; msg = "broken barrier did not open after channel"
		broken.free()

	intact.free()
	player.free()

	if ok:
		print("DOCK BREACH PASS intact_instant=true broken_channel=true")
		quit(0)
	else:
		push_error("DOCK BREACH FAIL reason=%s" % msg)
		quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_breach_smoke.gd`
Expected: FAIL — `dock_port_barrier.gd` does not exist (load error / parse error).

- [ ] **Step 3: Implement `DockPortBarrier`**

Create `scripts/tools/dock_port_barrier.gd` (mirrors `RepairPoint`'s range-gated channel; welding speeds it; no parts):

```gdscript
extends Area3D
class_name DockPortBarrier

## A closed dock-seam barrier at a derelict's dock port. An intact port opens in
## one interact; a broken port requires a timed, welding-speeded breach channel
## (mirrors RepairPoint's PZ-style channel — leaving range cancels with no loss).
## No parts consumed; the breach always eventually succeeds.

signal breach_opened(marker_id: String)

var marker_id: String = ""
var condition: String = "intact"          # "intact" | "broken"
var player_progression                    # PlayerProgressionState | null
var interaction_radius: float = 1.8
var breach_seconds: float = 6.0

var opened: bool = false
var channeling: bool = false
var progress: float = 0.0                  # 0..1
var _channel_player: Node = null
var _scaled_seconds: float = 1.0
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	set_process(true)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_marker_id: String, p_condition: String, p_player_progression, world_position: Vector3, p_breach_seconds: float, radius := 1.8) -> void:
	marker_id = p_marker_id
	condition = p_condition
	player_progression = p_player_progression
	breach_seconds = p_breach_seconds
	interaction_radius = radius
	opened = false
	channeling = false
	progress = 0.0
	candidate_player = null
	position = world_position
	name = "DockPortBarrier_%s" % p_marker_id
	set_meta("dock_port_barrier", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func _player_skill() -> int:
	if player_progression != null and player_progression.has_method("get_skill_level"):
		return int(player_progression.get_skill_level("welding"))
	return 0

## Intact: open immediately (one interact). Broken: start the welding-speeded
## channel. Returns true if the interaction was consumed (opened or channel started).
func try_start(player_body: Node) -> bool:
	if opened or not is_instance_valid(player_body):
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	if condition != "broken":
		set_opened(true)
		emit_signal("breach_opened", marker_id)
		return true
	if channeling:
		return false
	_channel_player = player_body
	channeling = true
	progress = 0.0
	var factor: float = 1.0 + 0.1 * float(maxi(0, _player_skill()))
	_scaled_seconds = maxf(0.01, breach_seconds / factor)
	return true

func _process(delta: float) -> void:
	if not channeling:
		return
	if not is_instance_valid(_channel_player) or not _is_player_in_direct_range(_channel_player):
		_cancel()
		return
	advance_channel(delta)

func advance_channel(delta: float) -> void:
	if not channeling:
		return
	progress = clampf(progress + delta / _scaled_seconds, 0.0, 1.0)
	if progress >= 1.0:
		_complete()

func _complete() -> void:
	channeling = false
	set_opened(true)
	if player_progression != null and player_progression.has_method("grant_xp"):
		player_progression.grant_xp("welding", 25)
	emit_signal("breach_opened", marker_id)

func _cancel() -> void:
	channeling = false
	progress = 0.0
	_channel_player = null

func set_opened(value: bool) -> void:
	opened = value
	channeling = false
	progress = 1.0 if value else 0.0
	if collision_shape != null:
		collision_shape.disabled = opened   # opening removes the blocking collider
	if marker != null:
		marker.visible = not opened

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var pn: Node3D = player_body as Node3D
	if not is_inside_tree() or not pn.is_inside_tree():
		return false
	return global_position.distance_to(pn.global_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "DockPortBarrierCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = opened

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "DockPortBarrierMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.2, 0.2, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = not opened
	marker.set_meta("debug_dock_port_barrier_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Run the smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_breach_smoke.gd`
Expected: `DOCK BREACH PASS intact_instant=true broken_channel=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/tools/dock_port_barrier.gd scripts/validation/dock_breach_smoke.gd
git commit -m "feat(docking): DockPortBarrier breach interactable (welding-speeded channel)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Travel re-expression — physical undock/dock + barrier spawn

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (`travel_to` 1459-1517, `travel_home` 1526-1553, `_attach_derelict_active` 1093-1106)
- Test: `scripts/validation/physical_travel_smoke.gd` (create)

**Interfaces:**
- Consumes: `_dock_piloted_to`, `_ship_seed`, `_ship_condition_class`, `piloted_ship` (Task 3); `DockingManager.undock` (existing); `DockPortBarrier` (Task 4).
- Produces:
  - `travel_to(marker) -> Dictionary` rewritten: precondition occupancy==piloted_ship and propulsion; `DockingManager.undock(piloted_ship)`; free old host; generate target; `add_child(new_root)` then `DockingManager.dock(target, piloted_ship, …)` (port-aligned, replaces `new_root.position = DERELICT_DOCK_OFFSET`); spawn a **closed** `DockPortBarrier`; **no** player teleport into the derelict — `recompute_occupancy()` leaves the player aboard `piloted_ship`.
  - `_spawn_dock_barrier(inst) -> void` — instantiates a `DockPortBarrier` at the derelict's dock-port world position under `inst.scene_root`, condition from the derelict's seed/condition; records it in `dock_barriers` and connects `breach_opened`.
  - `dock_barriers: Array` (new field).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/physical_travel_smoke.gd`. After repairing lifeboat propulsion and traveling to a marker, assert: (a) the player is still inside the lifeboat (piloted ship), NOT teleported into the derelict; (b) the lifeboat repositioned so its airlock is flush to the target's dock; (c) a closed dock barrier exists for the target.

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
var main_node: Node
var frame := 0
var done := false
var code := 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if done: return
	frame += 1
	var p = _find(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame > TIMEOUT_FRAMES: _fail("no playable")
		return
	_run(p)

func _run(p) -> void:
	# Repair lifeboat propulsion so travel is permitted (validation seam).
	p.force_repair_all_for_validation()
	# Board the lifeboat (validation seam: teleport into the piloted ship interior).
	p.board_piloted_ship_for_validation()
	p.recompute_occupancy()
	var lb = p.get_lifeboat_ship_for_validation()
	if p.get_current_occupancy_for_validation() != lb:
		_fail("not aboard piloted ship before travel"); return

	var ids: Array = p.scannable_marker_ids_for_validation()
	if ids.is_empty(): _fail("no scannable markers"); return
	var res: Dictionary = p.travel_to_marker_id(String(ids[0]))
	if not bool(res.get("success", false)): _fail("travel failed: %s" % str(res.get("reason",""))); return

	# (a) Player still inside the lifeboat (NOT teleported into the derelict).
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != lb:
		_fail("player not aboard lifeboat after travel (was teleported into derelict)"); return

	# (b) Lifeboat repositioned flush to the new host (gap small) — proves a real dock, not a parked offset.
	var host = p.get_current_host_for_validation()
	if host == null or host == lb: _fail("no distinct host after travel"); return
	if not p.piloted_flush_to_host_for_validation():
		_fail("lifeboat airlock not flush to target dock after travel"); return

	# (c) A closed dock barrier exists for the target.
	if not p.has_closed_dock_barrier_for_validation():
		_fail("no closed dock barrier spawned at target"); return

	done = true
	print("PHYSICAL TRAVEL PASS aboard_lifeboat=true flush=true barrier_closed=true")
	_teardown(0)

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null

func _fail(r: String) -> void:
	if done: return
	done = true
	push_error("PHYSICAL TRAVEL FAIL reason=%s" % r)
	_teardown(1)

func _teardown(c: int) -> void:
	code = c
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(code)
```

This smoke needs these coordinator validation seams (add them in Step 3, reusing existing helpers where possible):
- `force_repair_all_for_validation()` — repair the piloted ship's systems so propulsion is operational (reuse the existing repair seam used by `repair_loop_smoke`/`travel_integration_smoke`; grep for the current "force repair"/`set_repaired` seam and reuse it).
- `board_piloted_ship_for_validation()` — teleport the player to `piloted_ship.interior_aabb().get_center()`.
- `scannable_marker_ids_for_validation()` — the in-range marker ids (reuse `scan()`'s result or the existing seam used by `travel_integration_smoke`).
- `get_current_host_for_validation()` — returns `current_ship` (the piloted ship's current host derelict).
- `piloted_flush_to_host_for_validation()` — returns true iff the piloted ship's lifted airlock port is within 0.5u of the host's lifted dock port.
- `has_closed_dock_barrier_for_validation()` — true iff some entry in `dock_barriers` is valid and not `opened`.

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/physical_travel_smoke.gd`
Expected: FAIL — missing seams (parse error) or, once seams exist but travel still teleports, `player not aboard lifeboat after travel`.

- [ ] **Step 3: Rewrite the travel path**

Add the field and preload near the top:
```gdscript
const DockPortBarrierScript := preload("res://scripts/tools/dock_port_barrier.gd")
var dock_barriers: Array = []   # Array[DockPortBarrier], the active host's seam barriers
```

Rewrite `_attach_derelict_active` (1093-1106) to dock the piloted ship to the new derelict instead of parking it at `DERELICT_DOCK_OFFSET` and to spawn the barrier. The new host's scene_root is added to the tree, then the piloted ship docks to it:

```gdscript
func _attach_derelict_active(inst, new_root: Node3D) -> void:
	inst.scene_root = new_root
	add_child(new_root)
	new_root.position = DERELICT_DOCK_OFFSET   # initial world anchor; piloted ship docks TO it
	if inst.built_layout.is_empty() and new_root.has_method("get_layout_copy"):
		inst.built_layout = new_root.get_layout_copy()
	current_ship = inst
	away_from_start = true
	# Dock the piloted ship (lifeboat) to this derelict so the ride physically moves
	# with the player. The piloted ship is repositioned flush to the host's dock port.
	if piloted_ship != null:
		DockingManagerScript.undock(piloted_ship)
		_dock_piloted_to(inst)
	_spawn_dock_barrier(inst)
	current_occupancy = piloted_ship if piloted_ship != null else inst
	_build_derelict_objectives()
	_build_loot_containers()
	_build_repair_points()
```

Add the barrier spawner:

```gdscript
## Spawns the closed dock-seam barrier for `inst` at its dock-port world position,
## condition from the derelict's seed/condition. Home derelict is always intact.
func _spawn_dock_barrier(inst) -> void:
	_clear_dock_barriers()
	if inst == null or inst.scene_root == null or not is_instance_valid(inst.scene_root):
		return
	var local: Dictionary = DockPortsScript.for_derelict(inst.built_layout, _ship_seed(inst), _ship_condition_class(inst))
	if local.is_empty():
		return
	var cond: String = "intact" if inst == home_ship else str(local.get("condition", "intact"))
	var barrier = DockPortBarrierScript.new()
	# Local position under the derelict's scene_root (the port is ship-local).
	(inst.scene_root as Node3D).add_child(barrier)
	barrier.configure(String(inst.marker_id), cond, player_progression, local["position"] as Vector3, 6.0, 1.8)
	barrier.breach_opened.connect(_on_dock_barrier_opened)
	dock_barriers.append(barrier)

func _clear_dock_barriers() -> void:
	for b in dock_barriers:
		if is_instance_valid(b):
			if b.get_parent() != null:
				b.get_parent().remove_child(b)
			b.queue_free()
	dock_barriers.clear()

func _on_dock_barrier_opened(_marker_id: String) -> void:
	# Boarding the derelict is now possible; occupancy flips as the player crosses.
	recompute_occupancy()
```

Rewrite `travel_to` (1459-1517): keep the `travel_controller.attempt_travel` precondition flow, add the aboard-piloted precondition, and DELETE the player-teleport-into-derelict block (1506-1516). The player stays aboard the piloted ship:

```gdscript
func travel_to(marker) -> Dictionary:
	if current_ship == null or synapse_sea_world == null or travel_controller == null or ship_generator == null:
		return {"success": false, "reason": "not_ready", "ship": null}
	# Precondition: the player must be aboard the piloted ship to travel (the ride
	# takes them with it). Occupancy is authoritative.
	recompute_occupancy()
	if piloted_ship != null and current_occupancy != piloted_ship:
		return {"success": false, "reason": "not_aboard_ship", "ship": null}
	var ops_t: Dictionary = {"propulsion": bool(_current_systems_ops().get("propulsion", false))}
	var result: Dictionary = travel_controller.attempt_travel(
		marker, ops_t, synapse_sea_world, ship_generator, scanner_state.range_radius)
	if not bool(result.get("success", false)):
		return result
	var new_root: Node3D = result.get("ship", null)
	if new_root == null:
		return {"success": false, "reason": "generation_failed", "ship": null}

	var leaving = current_ship
	if String(leaving.marker_id) == "":
		_home_player_position = (player as Node3D).global_position if player != null and player is Node3D else _home_player_position
	else:
		if leaving.scene_root != null and is_instance_valid(leaving.scene_root):
			if leaving.scene_root.get_parent() == self:
				remove_child(leaving.scene_root)
			leaving.scene_root.queue_free()
		leaving.scene_root = null

	var mid: String = String(marker.marker_id)
	var inst
	if visited_ships.has(mid):
		inst = visited_ships[mid]
	else:
		var new_bp = ShipBlueprintScript.new(int(marker.size_class), int(marker.condition), int(marker.seed_value))
		var new_mgr = ShipSystemsManagerScript.new()
		new_mgr.configure(new_mgr.load_definitions(), new_bp.condition, new_bp.seed_value)
		inst = ShipInstanceScript.create("ship_%s" % mid, mid, new_bp, new_mgr, null)
		visited_ships[mid] = inst

	_attach_derelict_active(inst, new_root)
	# NO player teleport into the derelict: the player rides the piloted ship, which
	# docked flush to the target. They cross the (closed) dock barrier themselves.
	recompute_occupancy()
	return result
```

Rewrite `travel_home` (1526-1553) symmetrically: undock the piloted ship from the current derelict, free it, re-dock the piloted ship to `home_ship`, spawn the home barrier (intact), and leave the player aboard the piloted ship (do not set `global_position = _home_player_position` into the derelict frame). After `current_ship = home_ship; away_from_start = false`, replace the player-position line and add:

```gdscript
	if piloted_ship != null:
		DockingManagerScript.undock(piloted_ship)
		_dock_piloted_to(home_ship)
	_spawn_dock_barrier(home_ship)
	current_occupancy = piloted_ship if piloted_ship != null else home_ship
	# Player stays aboard the piloted ship (which re-docked to home). Do not teleport
	# into the home derelict's frame.
	recompute_occupancy()
	return true
```

Add the validation seams listed in Step 1 (place them near the other `*_for_validation` seams ~line 1028). Example bodies:

```gdscript
func get_current_host_for_validation():
	return current_ship

func board_piloted_ship_for_validation() -> void:
	if piloted_ship != null and player != null and player is Node3D:
		(player as Node3D).global_position = piloted_ship.interior_aabb().get_center()

func has_closed_dock_barrier_for_validation() -> bool:
	for b in dock_barriers:
		if is_instance_valid(b) and not b.opened:
			return true
	return false

func piloted_flush_to_host_for_validation() -> bool:
	if piloted_ship == null or current_ship == null or current_ship.scene_root == null:
		return false
	var host_local: Dictionary = DockPortsScript.for_derelict(current_ship.built_layout, _ship_seed(current_ship), _ship_condition_class(current_ship))
	var host_world: Dictionary = DockingManagerScript.host_port_to_world(current_ship, host_local)
	if host_world.is_empty():
		return false
	var lb_local: Dictionary = DockPortsScript.for_lifeboat(piloted_ship.built_layout)
	var lb_world: Vector3 = (piloted_ship.scene_root as Node3D).global_transform * (lb_local["position"] as Vector3)
	return lb_world.distance_to(host_world["position"] as Vector3) <= 0.5
```

For `force_repair_all_for_validation()` and `scannable_marker_ids_for_validation()`, grep the existing smokes (`travel_integration_smoke.gd`, `repair_loop_smoke.gd`) for the seams they already use and reuse/alias them rather than inventing new ones.

- [ ] **Step 4: Run the physical-travel smoke**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/physical_travel_smoke.gd`
Expected: `PHYSICAL TRAVEL PASS aboard_lifeboat=true flush=true barrier_closed=true`.

- [ ] **Step 5: Run the existing travel/integration smokes (regression)**

Run:
```
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_integration_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/docking_loop_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_copresence_smoke.gd
```
Expected: each prints its existing PASS marker. If `travel_integration_smoke` asserted the old "player teleported into derelict" behavior, update that smoke to the new ride-aboard semantics (it's testing the same travel path; the contract changed deliberately) — note the change in the commit body.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/physical_travel_smoke.gd scripts/validation/travel_integration_smoke.gd
git commit -m "feat(docking): physical travel — piloted ship undocks/redocks, no teleport into derelict

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Occupancy-driven boarding + interact routing

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (`_on_player_interact_requested` 1825-1863, `recompute_occupancy` 1016-1025, `_occupancy_entries` 1001-1011)
- Test: `scripts/validation/boarding_flip_smoke.gd` (create)

**Interfaces:**
- Consumes: `dock_barriers`, `_spawn_dock_barrier`, `piloted_ship` (Task 5).
- Produces:
  - `_on_player_interact_requested` tries `dock_barriers` (via `try_start`) ahead of derelict objectives/loot, so interacting at a closed seam opens/breaches it.
  - `_occupancy_entries()` includes the active host derelict and the piloted ship; occupancy resolves by real AABB (Task 2). Boarding the derelict (crossing the opened seam) flips `current_occupancy` to the host and activates its objective/loot HUD via the existing `_build_derelict_objectives` path already invoked in `_attach_derelict_active`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/boarding_flip_smoke.gd`. After travel: assert (a) while the barrier is closed and the player is in the lifeboat, occupancy is the lifeboat; (b) interacting at the barrier opens it (intact) or breaches it (broken via channel); (c) teleporting the player into the derelict interior flips occupancy to the host derelict.

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
var main_node: Node
var frame := 0
var done := false
var code := 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if done: return
	frame += 1
	var p = _find(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame > TIMEOUT_FRAMES: _fail("no playable")
		return
	_run(p)

func _run(p) -> void:
	p.force_repair_all_for_validation()
	p.board_piloted_ship_for_validation()
	p.recompute_occupancy()
	var ids: Array = p.scannable_marker_ids_for_validation()
	if ids.is_empty(): _fail("no markers"); return
	if not bool(p.travel_to_marker_id(String(ids[0])).get("success", false)): _fail("travel failed"); return

	var lb = p.get_lifeboat_ship_for_validation()
	var host = p.get_current_host_for_validation()

	# (a) Closed barrier + in lifeboat -> occupancy is the lifeboat.
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != lb: _fail("not in lifeboat pre-board"); return

	# (b) Open/breach the barrier deterministically (validation seam drives the channel).
	if not p.open_active_dock_barrier_for_validation(): _fail("barrier did not open"); return

	# (c) Cross into the derelict -> occupancy flips to the host.
	p.board_host_for_validation()
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != host: _fail("occupancy did not flip to host after boarding"); return

	done = true
	print("BOARDING FLIP PASS closed_in_lifeboat=true barrier_opens=true flips_to_host=true")
	_teardown(0)

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null

func _fail(r: String) -> void:
	if done: return
	done = true
	push_error("BOARDING FLIP FAIL reason=%s" % r)
	_teardown(1)

func _teardown(c: int) -> void:
	code = c
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(code)
```

Add seams: `open_active_dock_barrier_for_validation()` (find the first closed barrier; if intact call `set_opened(true)`+emit, else `advance_channel(100.0)`; return true if it ended opened) and `board_host_for_validation()` (teleport player to `current_ship.interior_aabb().get_center()`).

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/boarding_flip_smoke.gd`
Expected: FAIL — missing seams, or occupancy not flipping because `_occupancy_entries` / interact routing don't yet include the barrier and host.

- [ ] **Step 3: Wire interact routing + the seams**

In `_on_player_interact_requested`, add a barrier pass before the derelict objective/loot passes. Insert at the top of the `if away_from_start:` block (before the repair-points loop at 1831):

```gdscript
		# Phase 5b: opening/breaching the dock seam barrier takes precedence so the
		# player can board the derelict before any in-derelict interaction.
		for b in dock_barriers:
			if is_instance_valid(b) and not b.opened and b.try_start(player_body):
				return
```

Add the two validation seams near the other `*_for_validation` seams:

```gdscript
func open_active_dock_barrier_for_validation() -> bool:
	for b in dock_barriers:
		if is_instance_valid(b) and not b.opened:
			if b.condition == "broken":
				b.channeling = true
				b._scaled_seconds = 0.01
				b.advance_channel(100.0)
			else:
				b.set_opened(true)
				b.emit_signal("breach_opened", b.marker_id)
			return b.opened
	return false

func board_host_for_validation() -> void:
	if current_ship != null and player != null and player is Node3D:
		(player as Node3D).global_position = current_ship.interior_aabb().get_center()
```

(`recompute_occupancy` and `_occupancy_entries` already include `current_ship` and the piloted ship; verify the piloted ship is in `_occupancy_entries` — it is added via the `lifeboat_ship`/`current_ship` branches. If `piloted_ship` ever diverges from `lifeboat_ship`, add an explicit piloted-ship entry. For this cycle they are the same instance.)

- [ ] **Step 4: Run the boarding-flip smoke**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/boarding_flip_smoke.gd`
Expected: `BOARDING FLIP PASS closed_in_lifeboat=true barrier_opens=true flips_to_host=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/boarding_flip_smoke.gd
git commit -m "feat(docking): occupancy-driven boarding + dock-barrier interact routing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Persistence — dock-edge set + piloted pointer + occupancy + opened ports

**Files:**
- Modify: `scripts/systems/world_snapshot.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd` (save/load builders — grep `WorldSnapshotScript`, `_apply_world_snapshot`)
- Test: `scripts/validation/docking_persistence_smoke.gd` (create)

**Interfaces:**
- Produces: `WorldSnapshot` gains `dock_edges: Array` (each `{host: String, mobile: String, port_type: String}`; `host`/`mobile` are ship ids, `""`=home), `piloted_ship_id: String`, `aboard_ship_id: String`, `opened_ports: Array` (marker_ids whose barriers are opened). `WORLD_SLICE_VERSION` bumps `"world-1"` → `"world-2"` (incompatible old saves fall back to fresh, per ADR-0007/0012).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/docking_persistence_smoke.gd`: travel to a marker, breach/open its barrier, save, reload, and assert the reload restores: the dock edge (piloted docked to the same host), occupancy (aboard the piloted ship), and the opened-port flag (the barrier spawns already-open on the restored host).

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 900
var main_node: Node
var frame := 0
var done := false
var code := 0
var phase := 0
var target_id := ""

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if done: return
	frame += 1
	var p = _find(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame > TIMEOUT_FRAMES: _fail("no playable")
		return
	if phase == 0:
		p.force_repair_all_for_validation()
		p.board_piloted_ship_for_validation()
		p.recompute_occupancy()
		var ids: Array = p.scannable_marker_ids_for_validation()
		if ids.is_empty(): _fail("no markers"); return
		target_id = String(ids[0])
		if not bool(p.travel_to_marker_id(target_id).get("success", false)): _fail("travel failed"); return
		p.open_active_dock_barrier_for_validation()
		if not p.save_world_for_validation(): _fail("save failed"); return
		phase = 1
		return
	if phase == 1:
		if not p.load_world_for_validation(): _fail("load failed"); return
		phase = 2
		return
	if phase == 2:
		# Restored: piloted ship docked to the same host, aboard piloted ship, port opened.
		var host = p.get_current_host_for_validation()
		if host == null or String(host.marker_id) != target_id: _fail("host not restored"); return
		var lb = p.get_lifeboat_ship_for_validation()
		if lb == null or lb.parent_ship != host: _fail("dock edge not restored"); return
		p.recompute_occupancy()  # player restored aboard piloted ship
		if not p.restored_port_opened_for_validation(target_id): _fail("opened-port flag not restored"); return
		done = true
		print("DOCKING PERSISTENCE PASS dock_edge=true occupancy=true opened_port=true")
		_teardown(0)

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null

func _fail(r: String) -> void:
	if done: return
	done = true
	push_error("DOCKING PERSISTENCE FAIL reason=%s" % r)
	_teardown(1)

func _teardown(c: int) -> void:
	code = c
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(code)
```

Reuse the existing save/load validation seams if present (grep `save_world_for_validation`/`load_world_for_validation` in current smokes; the REQ-012 reload smokes already exercise save/load — reuse those seams). Add `restored_port_opened_for_validation(marker_id)` returning true iff the restored host's barrier is opened.

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/docking_persistence_smoke.gd`
Expected: FAIL — `WorldSnapshot` has no dock-edge/opened-port fields, so the reload restores neither.

- [ ] **Step 3: Extend `WorldSnapshot`**

In `scripts/systems/world_snapshot.gd`: bump the version and add the fields to vars, `to_dict`, and `from_dict`:

```gdscript
const WORLD_SLICE_VERSION: String = "world-2"
```
Add vars (after line 18):
```gdscript
var dock_edges: Array = []          # [{host: String, mobile: String, port_type: String}]
var piloted_ship_id: String = ""
var aboard_ship_id: String = ""
var opened_ports: Array = []        # marker_ids with an opened dock barrier
```
In `to_dict` add:
```gdscript
		"dock_edges": dock_edges.duplicate(true),
		"piloted_ship_id": piloted_ship_id,
		"aboard_ship_id": aboard_ship_id,
		"opened_ports": opened_ports.duplicate(),
```
In `from_dict` (after `ws.current_location`):
```gdscript
	var edges_v: Variant = dict.get("dock_edges", [])
	if typeof(edges_v) == TYPE_ARRAY:
		ws.dock_edges = (edges_v as Array).duplicate(true)
	ws.piloted_ship_id = str(dict.get("piloted_ship_id", ""))
	ws.aboard_ship_id = str(dict.get("aboard_ship_id", ""))
	var op_v: Variant = dict.get("opened_ports", [])
	if typeof(op_v) == TYPE_ARRAY:
		ws.opened_ports = []
		for m in (op_v as Array):
			ws.opened_ports.append(String(m))
```

- [ ] **Step 4: Wire save/load in the coordinator**

In the coordinator's snapshot-build code (grep `WorldSnapshotScript.new()` / where `current_location` is set): populate the new fields on save:
```gdscript
	ws.dock_edges = _current_dock_edges()
	ws.piloted_ship_id = piloted_ship.ship_id if piloted_ship != null else ""
	ws.aboard_ship_id = current_occupancy.ship_id if current_occupancy != null else ""
	ws.opened_ports = _opened_port_marker_ids()
```
with helpers:
```gdscript
func _current_dock_edges() -> Array:
	var edges: Array = []
	if piloted_ship != null and piloted_ship.parent_ship != null:
		var host = piloted_ship.parent_ship
		edges.append({"host": String(host.marker_id), "mobile": String(piloted_ship.ship_id), "port_type": "airlock"})
	return edges

func _opened_port_marker_ids() -> Array:
	var out: Array = []
	for b in dock_barriers:
		if is_instance_valid(b) and b.opened:
			out.append(String(b.marker_id))
	return out
```
In `_apply_world_snapshot` (load path), after the ships and the active host are rebuilt and the piloted ship re-docked (the existing load path calls `_attach_derelict_active`, which now re-docks and re-spawns the barrier), restore the opened-port flags and place the player aboard the piloted ship:
```gdscript
	for b in dock_barriers:
		if is_instance_valid(b) and ws.opened_ports.has(String(b.marker_id)):
			b.set_opened(true)
	if piloted_ship != null and player != null and player is Node3D:
		(player as Node3D).global_position = piloted_ship.interior_aabb().get_center()
	recompute_occupancy()
```
Add `restored_port_opened_for_validation`:
```gdscript
func restored_port_opened_for_validation(marker_id: String) -> bool:
	for b in dock_barriers:
		if is_instance_valid(b) and String(b.marker_id) == marker_id:
			return b.opened
	return false
```

- [ ] **Step 5: Run the persistence smoke + the existing save/load smoke**

Run:
```
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/docking_persistence_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
```
Expected: `DOCKING PERSISTENCE PASS dock_edge=true occupancy=true opened_port=true`, and the save/load service smoke still passes (its one expected `save file rejected by from_dict` WARNING is allowlisted; confirm the version bump didn't add new warnings).

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/world_snapshot.gd scripts/procgen/playable_generated_ship.gd scripts/validation/docking_persistence_smoke.gd
git commit -m "feat(docking): persist dock-edge set + piloted pointer + occupancy + opened ports

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: ADR-0017, roadmap fix, regression registration, full bundle + Gate-1

**Files:**
- Create: `docs/game/adr/0017-physical-docking-and-ports.md`
- Modify: `docs/game/09_system_roadmap.md` (fix stale System 5 status)
- Modify: `docs/game/06_validation_plan.md` (register the 7 new smokes; commands 81 → 88)

- [ ] **Step 1: Write ADR-0017**

Create `docs/game/adr/0017-physical-docking-and-ports.md` recording: runtime port-aligned docking at boot+travel (DockingManager finally called from the game, retiring the fixed-offset hack); the `piloted_ship` + general dock-edge graph model (and why — the N-ship forward constraint); real occupancy from room-node AABBs (and the headless zero-AABB bug it fixes); typed ports with airlock exercised + hangar/cargo_clamp structured; welding-speeded forced-entry breach reusing the repair-channel pattern; teleport-travel retired (objectives now activate on boarding, not arrival). Record rejected alternatives (neutral-frame re-anchoring; cosmetic docked lifeboat). Follow the format of `docs/game/adr/0016-ship-docking-foundation.md`.

- [ ] **Step 2: Fix the stale roadmap status**

In `docs/game/09_system_roadmap.md`: update the System 5 row (line ~38) from `⛔ Not started` to `🟢 Foundation (5a) + physical docking & ports (5b) built` with evidence (`docking_manager.gd`, `dock_ports.gd`, `dock_port_barrier.gd`, runtime docking in `playable_generated_ship.gd`, ADR-0016/0017); update the build-phase crosswalk (line ~60) Phase 5 status to `🟢 5a+5b built; claim-2nd-ship/hangars remain`; and in "What remains" → B, note that physical travel-docking + port types are delivered and the remaining System 5 work is claim-a-2nd-ship + hangar nesting.

- [ ] **Step 3: Register the new smokes**

In `docs/game/06_validation_plan.md`: add `run_clean` lines for the 7 new smokes with their exact PASS markers, and bump the success line `commands=81` → `commands=88`:
- `dock_port_types_smoke` → `DOCK PORT TYPES PASS compat=true condition_from_seed=true typed=true`
- `interior_aabb_smoke` → `INTERIOR AABB PASS nondegenerate=true positioned=true contains=true`
- `boot_dock_aligned_smoke` → `BOOT DOCK ALIGNED PASS flush=true gap_lt_0p5=true`
- `dock_breach_smoke` → `DOCK BREACH PASS intact_instant=true broken_channel=true`
- `physical_travel_smoke` → `PHYSICAL TRAVEL PASS aboard_lifeboat=true flush=true barrier_closed=true`
- `boarding_flip_smoke` → `BOARDING FLIP PASS closed_in_lifeboat=true barrier_opens=true flips_to_host=true`
- `docking_persistence_smoke` → `DOCKING PERSISTENCE PASS dock_edge=true occupancy=true opened_port=true`

- [ ] **Step 4: Run the full regression bundle (drift stashed)**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
git stash push -- project.godot
sed -n '30,160p' "$ROOT/docs/game/06_validation_plan.md" > /tmp/synapse_sea_bundle.sh
GODOT="$GODOT" ROOT="$ROOT" bash /tmp/synapse_sea_bundle.sh
git stash pop
```
Expected final line: `SYNAPSE_SEA REGRESSION PASS commands=88 clean_output=true`. (Adjust the `sed` range if the bundle script block moved after editing the doc.)

- [ ] **Step 5: Run Gate-1**

```bash
git stash push -- project.godot
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd
git stash pop
```
Expected: `GATE 1 AUTOMATED PLAYTEST PASS`, `pass_decision=GO`, `overall_average=2.00`.

- [ ] **Step 6: Commit**

```bash
git add docs/game/adr/0017-physical-docking-and-ports.md docs/game/09_system_roadmap.md docs/game/06_validation_plan.md
git commit -m "docs(docking): ADR-0017 + roadmap status + register 5b smokes (81->88)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review notes (for the executor)

- **Spec coverage:** physical travel (Tasks 3,5) · typed ports + compat (Task 1) · condition-gated welding breach (Tasks 1,4,6) · real occupancy (Tasks 2,6) · general dock-graph persistence (Task 7) · ADR + roadmap + regression (Task 8). All spec "Testing (definition of done)" bullets map to a smoke above.
- **Forward constraint:** travel is keyed on `piloted_ship`, never "lifeboat"; persistence stores a dock-EDGE SET; both generalize to N ships. Do not collapse `piloted_ship` back into a hardcoded lifeboat reference.
- **Type consistency:** `for_derelict(layout, seed_value, condition_class)`, `ports_compatible(a, b)`, `condition_from_seed(seed_value, condition_class)`, `host_port_to_world(host_inst, local_port)`, `DockPortBarrier.try_start/advance_channel/set_opened/breach_opened`, `built_layout`, `piloted_ship`, `dock_barriers` — used identically across tasks.
- **Open assumption to verify during Task 3:** confirm the home/golden ship exposes a layout the coordinator can store in `home_ship.built_layout` (a `get_layout_copy()` seam on the loader, or the golden layout dict). If absent, add a minimal `get_layout_copy()` to `generated_ship_loader.gd` returning the layout it loaded — fold that into Task 3 and note it in the commit.
