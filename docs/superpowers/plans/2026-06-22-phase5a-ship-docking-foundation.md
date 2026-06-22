# Phase 5a — Ship Docking Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-ship shared-origin swap with co-present, world-space ship entities physically joined at a walkable dock, and wire the canonical opening (start aboard an unfixable starting derelict with the damaged lifeboat docked).

**Architecture:** Each `ShipInstance` gets a `ship_root: Node3D` placed at a distinct world transform; its gameplay roots reparent under it. A new pure `DockingManager` computes the transform that aligns two ships at their dock ports; a new pure `ShipOccupancy` resolver derives "which ship the player is aboard" from spatial containment, driving the active systems manager / HUD / objective tracker. Travel becomes undock-here/dock-there, gated on being aboard the lifeboat. Persistence stores the docking edge + occupancy and recomputes transforms on load.

**Tech Stack:** Godot 4.6.2, GDScript (typed), headless validation smokes.

## Global Constraints

- Godot binary (headless): `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`.
- Run a smoke: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd`. **`--script` can exit 0 on parse/load errors — never trust the exit code; the single `... PASS ...` marker line IS the contract.** Confirm the marker and that no unexpected `ERROR:`/`WARNING:` appears.
- Allowlisted teardown noise (ignore): `ERROR: Capture not registered: 'gdaimcp'.`; `WARNING: ObjectDB instances leaked at exit ...`; and the save/load service's one expected `WARNING: SaveLoadService: save file rejected by from_dict ...`. Any other `ERROR:`/`WARNING:` blocks completion.
- **Class-cache portability (critical):** new `class_name` scripts are NOT in the committed `global_script_class_cache.cfg`. Under `--headless --script` the global class registry is not rebuilt, so a bare `ClassName.new()` or `: ClassName` annotation referencing a newly added class fails on a fresh checkout/CI. Construct every new class via a `preload(...)` const + `.new()`, or a `load(...)` self-reference static factory (mirror `ShipInstance.create` / `WorldSnapshot.from_dict`). Reference instances with untyped `var` + a comment, exactly as the coordinator already does (`var current_ship  # ShipInstance`).
- Typed GDScript for new systems. Conventional Commits (`feat:`/`refactor:`/`test:`/`docs:`). Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Selective `git add` of named files only — never `git add -A`. Never stage `.godot/`, `*.uid`, `project.godot`, or `addons/`.
- **Forward constraint (binding):** no "single active ship at origin" assumption may be reintroduced. Every mechanism must generalize to N co-present ships. 5a loads at most two ships (lifeboat + one docked derelict) — a load bound, not an architectural one.
- **Definition of done = fresh PASS-marker output.** Each task adds/extends a smoke; the final task registers them in `docs/game/06_validation_plan.md` and the full bundle + Gate-1 must stay green.
- Spec: `docs/superpowers/specs/2026-06-22-phase5a-ship-docking-foundation-design.md`.

## File Structure

| File | Responsibility | Tasks |
|------|----------------|-------|
| `scripts/systems/docking_manager.gd` (new) | Pure: compute dock transform from two ports; write/clear dock relationship fields. | 1 |
| `scripts/systems/ship_occupancy.gd` (new) | Pure: resolve which ship's interior AABB contains the player; host tiebreak. | 2 |
| `scripts/systems/ship_instance.gd` (modify) | Activate `ship_root`; cache interior AABB; expose dock-port descriptor. | 3 |
| `scripts/systems/dock_ports.gd` (new) | Pure: derive dock-port `{position, facing}` for lifeboat (airlock) and derelict (dock room) from a layout dict. | 4 |
| `scripts/procgen/playable_generated_ship.gd` (modify) | Per-ship positioned subtrees; occupancy-driven active context; canonical opening; travel re-expression. | 5,6,7,8 |
| `scripts/systems/world_snapshot.gd` (modify) | Persist docking edge + occupancy + starting-derelict state. | 8 |
| `data/procgen/archetypes/derelict.json` + `data/items/loot_tables.json` (modify) | Guarantee a dock room + relocate starting loot onto the derelict. | 7 |
| `scripts/validation/*` (new smokes) | One smoke per task; final integration smoke. | all |
| `docs/game/adr/0016-ship-docking-foundation.md` (new) | Record the per-ship-subtree + occupancy decision and rejected alternatives. | 9 |
| `docs/game/06_validation_plan.md` (modify) | Register new smokes; bump bundle count. | 9 |

---

### Task 1: DockingManager (pure transform + relationship logic)

**Files:**
- Create: `scripts/systems/docking_manager.gd`
- Test: `scripts/validation/docking_manager_smoke.gd`

**Interfaces:**
- Produces:
  - `class_name DockingManager`
  - `static func compute_mobile_transform(host_port: Dictionary, mobile_port: Dictionary) -> Transform3D` — `host_port`/`mobile_port` are `{"position": Vector3, "facing": Vector3}`. `host_port.position`/`.facing` are in WORLD space (the host is already placed); `mobile_port.position`/`.facing` are in the mobile ship_root's LOCAL space. Returns the world `Transform3D` to assign to `mobile.ship_root` so that, after assignment, the mobile port's world position equals `host_port.position` and the mobile port's world facing equals `-host_port.facing` (doorways face each other). Facings are unit vectors in the X-Z plane; rotation is yaw-only.
  - `static func dock(host_inst, mobile_inst, host_port: Dictionary, mobile_port: Dictionary) -> Dictionary` — computes the transform, assigns it to `mobile_inst.ship_root` when that root is a valid `Node3D`, sets `mobile_inst.parent_ship = host_inst`, appends `mobile_inst` to `host_inst.docked_ships` (no duplicates), records `{"host_port": host_port, "mobile_port": mobile_port}` in `mobile_inst.docking_ports`. Returns `{"success": true, "reason": "ok"}` or `{"success": false, "reason": "dock_failed"}` when a port is malformed or `mobile_inst.ship_root` is invalid.
  - `static func undock(mobile_inst) -> Dictionary` — clears `mobile_inst.parent_ship`, removes `mobile_inst` from its former host's `docked_ships`, clears `mobile_inst.docking_ports`. Returns `{"success": true, "reason": "ok"}`; idempotent (returns `{"success": true, "reason": "not_docked"}` when `parent_ship` is null).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/docking_manager_smoke.gd`:

```gdscript
extends SceneTree

## Pure-model: DockingManager aligns two ship ports (coincident position,
## opposing facing) and writes/clears the dock relationship. No scene tree
## traversal beyond two bare Node3D roots used as transform carriers.

const DockingManagerScript := preload("res://scripts/systems/docking_manager.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	# Host placed 20 units down +X, its dock port facing +X (outward).
	var host_root := Node3D.new()
	host_root.position = Vector3(20.0, 0.0, 0.0)
	var host = ShipInstanceScript.create("host", "", null, null, host_root)
	var host_port := {"position": Vector3(22.0, 0.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)}

	# Mobile (lifeboat) port sits at local +X edge, facing +X in local space.
	var mobile_root := Node3D.new()
	var mobile = ShipInstanceScript.create("mobile", "", null, null, mobile_root)
	var mobile_port := {"position": Vector3(2.0, 0.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)}

	var res: Dictionary = DockingManagerScript.dock(host, mobile, host_port, mobile_port)
	if not bool(res.get("success", false)):
		ok = false; msg = "dock failed: %s" % str(res.get("reason", ""))

	# Mobile port now in world space must coincide with the host port and face the opposite way.
	var mobile_port_world: Vector3 = mobile_root.transform * (mobile_port["position"] as Vector3)
	var mobile_facing_world: Vector3 = (mobile_root.transform.basis * (mobile_port["facing"] as Vector3)).normalized()
	if ok and mobile_port_world.distance_to(host_port["position"]) > 0.001:
		ok = false; msg = "ports not coincident: %s vs %s" % [str(mobile_port_world), str(host_port["position"])]
	if ok and mobile_facing_world.distance_to(-(host_port["facing"] as Vector3)) > 0.001:
		ok = false; msg = "facings not opposed: %s" % str(mobile_facing_world)
	if ok and mobile.parent_ship != host:
		ok = false; msg = "parent_ship not set"
	if ok and not host.docked_ships.has(mobile):
		ok = false; msg = "mobile not in host.docked_ships"

	# Undock clears the relationship.
	if ok:
		DockingManagerScript.undock(mobile)
		if mobile.parent_ship != null or host.docked_ships.has(mobile) or not mobile.docking_ports.is_empty():
			ok = false; msg = "undock did not clear relationship"

	host_root.free()
	mobile_root.free()

	if ok:
		print("DOCKING MANAGER PASS aligned=true relationship=true undock=true")
		quit(0)
	else:
		push_error("DOCKING MANAGER FAIL reason=%s" % msg)
		quit(1)
```

- [ ] **Step 2: Run it; verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/docking_manager_smoke.gd`
Expected: FAIL — `docking_manager.gd` does not exist (parse/load error, no PASS marker).

- [ ] **Step 3: Implement `docking_manager.gd`**

```gdscript
extends RefCounted
class_name DockingManager

## Pure docking math + relationship bookkeeping. Aligns a mobile ship's dock
## port to a host ship's dock port (coincident position, opposing facing,
## yaw-only) and writes the parent/child fields already declared on ShipInstance.
## No scene-tree ownership: callers own add_child/remove_child of ship_roots.

## Yaw (radians) that rotates `from` onto `to` in the X-Z plane.
static func _yaw_between(from: Vector3, to: Vector3) -> float:
	var a := atan2(from.x, from.z)
	var b := atan2(to.x, to.z)
	return b - a

static func compute_mobile_transform(host_port: Dictionary, mobile_port: Dictionary) -> Transform3D:
	var host_pos: Vector3 = host_port.get("position", Vector3.ZERO)
	var host_facing: Vector3 = (host_port.get("facing", Vector3.FORWARD) as Vector3).normalized()
	var local_pos: Vector3 = mobile_port.get("position", Vector3.ZERO)
	var local_facing: Vector3 = (mobile_port.get("facing", Vector3.FORWARD) as Vector3).normalized()
	# Rotate the mobile so its local port facing becomes the OPPOSITE of the host facing.
	var target_facing: Vector3 = -host_facing
	var yaw: float = _yaw_between(local_facing, target_facing)
	var basis := Basis(Vector3.UP, yaw)
	# Translate so the (rotated) local port position lands on the host port position.
	var origin: Vector3 = host_pos - (basis * local_pos)
	return Transform3D(basis, origin)

static func _port_valid(p: Dictionary) -> bool:
	return p.has("position") and p.has("facing") \
		and typeof(p["position"]) == TYPE_VECTOR3 and typeof(p["facing"]) == TYPE_VECTOR3 \
		and (p["facing"] as Vector3).length() > 0.0001

static func dock(host_inst, mobile_inst, host_port: Dictionary, mobile_port: Dictionary) -> Dictionary:
	if host_inst == null or mobile_inst == null:
		return {"success": false, "reason": "dock_failed"}
	if not _port_valid(host_port) or not _port_valid(mobile_port):
		return {"success": false, "reason": "dock_failed"}
	var root = mobile_inst.ship_root
	if root == null or not is_instance_valid(root) or not (root is Node3D):
		return {"success": false, "reason": "dock_failed"}
	(root as Node3D).transform = compute_mobile_transform(host_port, mobile_port)
	mobile_inst.parent_ship = host_inst
	if not host_inst.docked_ships.has(mobile_inst):
		host_inst.docked_ships.append(mobile_inst)
	mobile_inst.docking_ports = [{"host_port": host_port, "mobile_port": mobile_port}]
	return {"success": true, "reason": "ok"}

static func undock(mobile_inst) -> Dictionary:
	if mobile_inst == null:
		return {"success": false, "reason": "dock_failed"}
	var host = mobile_inst.parent_ship
	if host == null:
		return {"success": true, "reason": "not_docked"}
	if host.docked_ships.has(mobile_inst):
		host.docked_ships.erase(mobile_inst)
	mobile_inst.parent_ship = null
	mobile_inst.docking_ports = []
	return {"success": true, "reason": "ok"}
```

- [ ] **Step 4: Run it; verify PASS**

Run the smoke command. Expected: `DOCKING MANAGER PASS aligned=true relationship=true undock=true` and no unexpected `ERROR:`/`WARNING:`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/docking_manager.gd scripts/validation/docking_manager_smoke.gd
git commit -m "feat(docking): pure DockingManager port alignment + relationship + smoke"
```

---

### Task 2: ShipOccupancy resolver (pure spatial containment)

**Files:**
- Create: `scripts/systems/ship_occupancy.gd`
- Test: `scripts/validation/ship_occupancy_smoke.gd`

**Interfaces:**
- Produces:
  - `class_name ShipOccupancy`
  - `static func resolve(player_pos: Vector3, entries: Array) -> Variant` — `entries` is an ordered `Array` of `{"inst": <ShipInstance>, "aabb": AABB}` (world-space interior bounds). Returns the `inst` of the FIRST entry whose `aabb.has_point(player_pos)` (order = priority, so the host/home entry is listed first and wins a seam tie). Returns `null` when no entry contains the point.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/ship_occupancy_smoke.gd`:

```gdscript
extends SceneTree

## Pure-model: occupancy resolves which ship interior contains the player,
## with first-entry (host) priority on overlap and null when outside all.

const ShipOccupancyScript := preload("res://scripts/systems/ship_occupancy.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""
	var host = ShipInstanceScript.create("host", "", null, null, null)
	var mobile = ShipInstanceScript.create("mobile", "", null, null, null)
	# Host occupies x in [0,10]; mobile occupies x in [9,19] (overlap at [9,10]).
	var host_aabb := AABB(Vector3(0, -1, -5), Vector3(10, 2, 10))
	var mobile_aabb := AABB(Vector3(9, -1, -5), Vector3(10, 2, 10))
	var entries := [{"inst": host, "aabb": host_aabb}, {"inst": mobile, "aabb": mobile_aabb}]

	if ShipOccupancyScript.resolve(Vector3(2, 0, 0), entries) != host:
		ok = false; msg = "point in host not resolved to host"
	if ok and ShipOccupancyScript.resolve(Vector3(15, 0, 0), entries) != mobile:
		ok = false; msg = "point in mobile not resolved to mobile"
	if ok and ShipOccupancyScript.resolve(Vector3(9.5, 0, 0), entries) != host:
		ok = false; msg = "seam overlap did not tiebreak to host (first entry)"
	if ok and ShipOccupancyScript.resolve(Vector3(100, 0, 0), entries) != null:
		ok = false; msg = "point outside all did not resolve to null"

	if ok:
		print("SHIP OCCUPANCY PASS contained=true tiebreak=host outside=null")
		quit(0)
	else:
		push_error("SHIP OCCUPANCY FAIL reason=%s" % msg)
		quit(1)
```

- [ ] **Step 2: Run it; verify it fails** (file does not exist → no PASS marker).

- [ ] **Step 3: Implement `ship_occupancy.gd`**

```gdscript
extends RefCounted
class_name ShipOccupancy

## Pure spatial-containment resolver: returns the ShipInstance whose world-space
## interior AABB contains the player. Entry ORDER is priority — list the host
## (home) ship first so a dock-seam overlap deterministically resolves to it.

static func resolve(player_pos: Vector3, entries: Array) -> Variant:
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var aabb = entry.get("aabb", null)
		if aabb == null or typeof(aabb) != TYPE_AABB:
			continue
		# AABB.has_point is half-open on the max face; grow a hair so a player
		# exactly on a shared seam still counts as inside.
		if (aabb as AABB).grow(0.001).has_point(player_pos):
			return entry.get("inst", null)
	return null
```

- [ ] **Step 4: Run it; verify PASS** — `SHIP OCCUPANCY PASS contained=true tiebreak=host outside=null`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ship_occupancy.gd scripts/validation/ship_occupancy_smoke.gd
git commit -m "feat(docking): pure ShipOccupancy containment resolver + smoke"
```

---

### Task 3: ShipInstance — interior AABB + ship_root helpers

**Files:**
- Modify: `scripts/systems/ship_instance.gd`
- Test: `scripts/validation/ship_instance_dock_fields_smoke.gd`

**Background to read first:** `scripts/systems/ship_instance.gd` (whole file — it is 96 lines). The `ship_root` field does not exist yet (the file has `scene_root`, plus the `parent_ship`/`docked_ships`/`docking_ports` stubs). 5a uses `scene_root` as the ship's positioned root — there is no separate `ship_root` node; `ship_root` in the spec IS the ship's `scene_root` placed at a world transform. To avoid a confusing rename across the coordinator, **add a read/write alias property `ship_root` backed by `scene_root`** so DockingManager/occupancy code reads naturally and the coordinator's existing `scene_root` usage is untouched.

**Interfaces:**
- Produces (on `ShipInstance`):
  - `var ship_root: Node3D` — property alias: getter returns `scene_root`, setter assigns `scene_root`. (GDScript: implement with `get`/`set` accessors.)
  - `func interior_aabb() -> AABB` — returns the world-space AABB enclosing `scene_root`'s visual instances, or a zero AABB at `scene_root.global_position` when `scene_root` is null/empty. Used to build occupancy entries.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/ship_instance_dock_fields_smoke.gd`:

```gdscript
extends SceneTree

## ShipInstance.ship_root aliases scene_root, and interior_aabb() encloses the
## scene_root's geometry in world space.

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""
	var root := Node3D.new()
	root.position = Vector3(5, 0, 0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()   # 1x1x1 box centered at local origin
	root.add_child(mesh)
	get_root().add_child(root)   # in-tree so global transforms resolve

	var inst = ShipInstanceScript.create("s", "", null, null, null)
	inst.ship_root = root        # alias setter -> scene_root
	if inst.scene_root != root:
		ok = false; msg = "ship_root setter did not write scene_root"
	if ok and inst.ship_root != root:
		ok = false; msg = "ship_root getter did not read scene_root"

	if ok:
		var box: AABB = inst.interior_aabb()
		# The box (≈ [-0.5,0.5]^3) offset by +5 X must contain (5,0,0) and not (50,0,0).
		if not box.grow(0.01).has_point(Vector3(5, 0, 0)):
			ok = false; msg = "interior_aabb does not contain ship center"
		elif box.has_point(Vector3(50, 0, 0)):
			ok = false; msg = "interior_aabb wrongly contains a far point"

	root.queue_free()
	if ok:
		print("SHIP INSTANCE DOCK FIELDS PASS alias=true aabb=true")
		quit(0)
	else:
		push_error("SHIP INSTANCE DOCK FIELDS FAIL reason=%s" % msg)
		quit(1)
```

- [ ] **Step 2: Run it; verify it fails** (no `ship_root`/`interior_aabb` yet).

- [ ] **Step 3: Implement on `ship_instance.gd`**

Add after the `scene_root` declaration (the existing line `var scene_root: Node3D = null ...`):

```gdscript
# 5a: `ship_root` is the ship's positioned root — it IS scene_root, exposed
# under the docking-domain name. Alias so DockingManager/occupancy read
# naturally without renaming the coordinator's existing scene_root usage.
var ship_root: Node3D:
	get:
		return scene_root
	set(value):
		scene_root = value
```

Add these methods to the file:

```gdscript
## World-space AABB enclosing scene_root's visual instances. Used to build
## occupancy entries. Returns a zero-size AABB at scene_root's global origin
## when there is no geometry yet (e.g. an unbuilt retained instance).
func interior_aabb() -> AABB:
	if scene_root == null or not is_instance_valid(scene_root):
		return AABB()
	var acc := AABB()
	var seeded := false
	for node in _visual_descendants(scene_root):
		var world := node.global_transform * node.get_aabb()
		if not seeded:
			acc = world
			seeded = true
		else:
			acc = acc.merge(world)
	if not seeded:
		var o: Vector3 = scene_root.global_position if scene_root.is_inside_tree() else scene_root.position
		return AABB(o, Vector3.ZERO)
	return acc

func _visual_descendants(node: Node) -> Array:
	var out: Array = []
	if node is VisualInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_visual_descendants(child))
	return out
```

- [ ] **Step 4: Run it; verify PASS** — `SHIP INSTANCE DOCK FIELDS PASS alias=true aabb=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ship_instance.gd scripts/validation/ship_instance_dock_fields_smoke.gd
git commit -m "feat(docking): ShipInstance.ship_root alias + interior_aabb + smoke"
```

---

### Task 4: DockPorts — derive dock ports from layouts

**Files:**
- Create: `scripts/systems/dock_ports.gd`
- Test: `scripts/validation/dock_ports_smoke.gd`

**Background to read first:** `scripts/procgen/life_boat.gd` (the lifeboat layout: linear chain along X; `airlock_01` at cell x=0, `cockpit_01` at x=1, `engine_bay_01` at x=-1; `CELL_SIZE = 4.0`). `scripts/procgen/start_scene_builder.gd::_find_dock_position` (how the derelict's `dock` room center is found from `structural_placements` `world_position`). The derelict archetype guarantees a `dock` room in Task 7; Task 4 only needs the derivation helpers and can be tested against literal layout dicts.

**Interfaces:**
- Produces:
  - `class_name DockPorts`
  - `static func for_lifeboat(layout: Dictionary) -> Dictionary` — returns `{"position": Vector3, "facing": Vector3}` in the lifeboat root's LOCAL space: position = the `airlock_01` room's floor-cell `world_position`, nudged half a cell toward the derelict side along -X (the airlock faces the dock away from the cockpit at +X); facing = `Vector3(-1, 0, 0)`.
  - `static func for_derelict(layout: Dictionary) -> Dictionary` — returns `{"position": Vector3, "facing": Vector3}` in the derelict root's LOCAL space: position = the `dock` room center (same computation as `StartSceneBuilder._find_dock_position`); facing = `Vector3(1, 0, 0)` (the dock opening faces outward toward where the lifeboat parks). Returns `{}` when no dock room is found.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/dock_ports_smoke.gd`:

```gdscript
extends SceneTree

## DockPorts derives a local-space dock port for the lifeboat (airlock) and the
## derelict (dock room), with outward-facing normals on opposite axes.

const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	var lb_layout: Dictionary = LifeBoatBuilderScript.build_layout()
	var lb_port: Dictionary = DockPortsScript.for_lifeboat(lb_layout)
	if not lb_port.has("position") or not lb_port.has("facing"):
		ok = false; msg = "lifeboat port missing fields"
	elif (lb_port["facing"] as Vector3).distance_to(Vector3(-1, 0, 0)) > 0.001:
		ok = false; msg = "lifeboat facing not -X"

	# A minimal derelict layout with one dock room at world x=12.
	var der_layout := {
		"rooms": [{
			"id": "dock_01", "room_role": "dock",
			"structural_placements": [
				{"module_id": "floor_1x1", "world_position": [12.0, 0.0, 0.0]},
			],
		}],
	}
	var der_port: Dictionary = DockPortsScript.for_derelict(der_layout)
	if ok and (not der_port.has("position") or not der_port.has("facing")):
		ok = false; msg = "derelict port missing fields"
	elif ok and (der_port["position"] as Vector3).distance_to(Vector3(12, 0, 0)) > 0.001:
		ok = false; msg = "derelict port position not at dock center"
	elif ok and (der_port["facing"] as Vector3).distance_to(Vector3(1, 0, 0)) > 0.001:
		ok = false; msg = "derelict facing not +X"

	if ok and DockPortsScript.for_derelict({"rooms": []}).size() != 0:
		ok = false; msg = "missing dock room should return empty"

	if ok:
		print("DOCK PORTS PASS lifeboat=true derelict=true empty_guard=true")
		quit(0)
	else:
		push_error("DOCK PORTS FAIL reason=%s" % msg)
		quit(1)
```

- [ ] **Step 2: Run it; verify it fails** (file absent).

- [ ] **Step 3: Implement `dock_ports.gd`**

```gdscript
extends RefCounted
class_name DockPorts

## Derives dock-port descriptors {position: Vector3 (local), facing: Vector3}
## from a ship layout dict. The lifeboat docks at its airlock (-X side); the
## derelict exposes its guaranteed `dock` room opening (+X side outward).

const HALF_CELL: float = 2.0   # CELL_SIZE (4.0) / 2

static func for_lifeboat(layout: Dictionary) -> Dictionary:
	var center: Vector3 = _room_floor_center(layout, "airlock", "airlock")
	if center == Vector3.INF:
		return {}
	# Airlock opening faces the dock (-X, away from the +X cockpit); nudge to the edge.
	return {"position": center + Vector3(-HALF_CELL, 0.0, 0.0), "facing": Vector3(-1.0, 0.0, 0.0)}

static func for_derelict(layout: Dictionary) -> Dictionary:
	var center: Vector3 = _room_floor_center(layout, "dock", "dock")
	if center == Vector3.INF:
		return {}
	return {"position": center, "facing": Vector3(1.0, 0.0, 0.0)}

## Average world_position of floor placements in the first room whose room_role
## == role_match OR whose id begins with id_prefix. Returns Vector3.INF if none.
static func _room_floor_center(layout: Dictionary, role_match: String, id_prefix: String) -> Vector3:
	const FLOOR_MODULES := ["floor_1x1", "corridor_floor_1x1"]
	for room_v in layout.get("rooms", []):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var role := str(room.get("room_role", ""))
		var rid := str(room.get("id", ""))
		if role != role_match and not rid.begins_with(id_prefix):
			continue
		var sum := Vector3.ZERO
		var count := 0
		for p_v in room.get("structural_placements", []):
			if typeof(p_v) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_v
			var module := str(p.get("module_id", p.get("module", "")))
			if module not in FLOOR_MODULES:
				continue
			var pos = p.get("world_position", p.get("position", null))
			if typeof(pos) != TYPE_ARRAY or (pos as Array).size() < 3:
				continue
			sum += Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			count += 1
		if count > 0:
			return sum / float(count)
	return Vector3.INF
```

- [ ] **Step 4: Run it; verify PASS** — `DOCK PORTS PASS lifeboat=true derelict=true empty_guard=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/dock_ports.gd scripts/validation/dock_ports_smoke.gd
git commit -m "feat(docking): DockPorts layout-to-port derivation + smoke"
```

---

### Task 5: Coordinator — per-ship positioned subtrees (co-presence)

**Goal of this task:** make a traveled derelict co-present with the home ship at a DISTINCT world transform (not the shared origin), with the home ship NOT detached, and the derelict's own gameplay roots (`derelict_objective_root`, `loot_container_root`) parented under the derelict's positioned `scene_root` so their interactables align with the moved geometry. This is the keystone refactor. It does NOT yet change the opening (Task 7) or add occupancy (Task 6) — after this task the active ship is still chosen by the existing `current_ship`/`away_from_start` flags; only the SPATIAL model changes.

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/dock_copresence_smoke.gd`

**Background to read first (exact methods — line numbers are on the #4-inclusive coordinator and the file evolves, so locate each by NAME):** `_build_runtime_nodes` (~L858; note it now also creates `repair_point_root` ~L917), `_attach_derelict_active` (~L1035), `_starting_gameplay_roots`/`_detach_starting_gameplay_roots`/`_reattach_starting_gameplay_roots` (~L1017–L1029), `travel_to` (~L1324), `travel_home` (~L1380), `_reset_runtime_for_reload` (~L3220, esp. its `away_from_start` block), `_build_derelict_objectives` (~L1057), `_build_loot_containers` (~L1140), and the #4 repair-point machinery `_build_repair_points`/`_clear_repair_points` (~L1176/L1204), `repair_point_root` (~L140), `_active_systems_manager` (~L1214), `_apply_lifeboat_opening_damage` (~L1266). Note where each `add_child`es its nodes (currently to `self` / a coordinator-origin root).

**#4 IS NOW IN THE BASE (this changed since the plan was first drafted).** The coordinator already has the repair loop: repair points, lifeboat opening damage, and the loot lifted onto the home ship. `travel_home` and `_reset_runtime_for_reload` already REBUILD repair points — your co-presence edits must integrate with that, not fight it. A prior attempt at this task against a *non-#4* base exists at commit `82331ad` (+ `.superpowers/sdd/task-5-report.md`) — useful reference for the core moves, but it did NOT handle repair points; re-derive against the live #4 coordinator. Its one durable finding: `DERELICT_DOCK_OFFSET = Vector3(40,0,0)` is TOO SMALL (generated layouts extend ±~24 world units → a derelict room landed closer to home than to the derelict). Use `Vector3(100, 0, 0)`.

**Decisions for the implementer (resolve the existing single-active coupling):**
- Introduce `const DERELICT_DOCK_OFFSET := Vector3(100.0, 0.0, 0.0)` on the coordinator — a fixed world separation used until DockPorts wiring lands in Task 8. In THIS task, position the derelict `scene_root` at `DERELICT_DOCK_OFFSET` instead of origin, and STOP calling `_detach_starting_gameplay_roots()` so the home roots stay live and visible.
- Reparent the derelict's per-ship gameplay under the derelict's `scene_root` so it inherits the offset and frees with the derelict: in `_build_derelict_objectives`, `_build_loot_containers`, AND `_build_repair_points`, when the active ship is the away derelict, add the per-ship interactables/containers/repair-points under `current_ship.scene_root` instead of the coordinator-owned `derelict_objective_root`/`loot_container_root`/`repair_point_root`. Keep appending to the existing `derelict_interactables`/`loot_containers`/(repair-point array) for teardown. The HOME ship stays at the coordinator origin, so its gameplay (home loot, the lifeboat's repair point, oxygen/fire/arc) can stay under the coordinator-origin roots — only the DERELICT's roots move. (Interactable/LootContainer/RepairPoint world positions come from the derelict layout authored around origin; parenting under the offset `scene_root` shifts them to match the moved hull — verify in the smoke.)
- `travel_home`: keep freeing the derelict scene AND keep #4's repair-point/loot rebuild for the home ship; since home roots were never detached, REMOVE only the `_reattach_starting_gameplay_roots()` call. Audit `_reset_runtime_for_reload`'s `away_from_start` block similarly — remove only the now-redundant home-root reattach; preserve every other #4 behavior there (derelict-root free, loader reattach, repair-point rebuild, opening damage).
- Because home roots are never detached now, `_detach_starting_gameplay_roots`/`_reattach_starting_gameplay_roots`/`_starting_gameplay_roots` become dead; delete them and their call sites. Confirm via `grep` there are no remaining callers before deleting.

**Interfaces:**
- Produces:
  - `func active_ship_root_count_for_validation() -> int` — number of distinct in-tree ship `scene_root`s currently parented under the coordinator (home + any docked derelict). Used by the co-presence smoke.
  - `func get_home_ship_for_validation()` / `func get_current_ship_for_validation()` — return the home and current `ShipInstance` (if not already exposed; `get_current_ship` exists at L963 — reuse it; add a home accessor).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/dock_copresence_smoke.gd` — boots the main scene, travels to a marker, and asserts BOTH ship roots are co-present in-tree at distinct transforms (home near origin, derelict near the offset), and the derelict's loot interactables sit near the derelict (not origin):

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	var p = _find_playable(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("no playable/loader")
		return
	_validate(p)

func _validate(p) -> void:
	# Pick any in-range marker and travel.
	var world = p.get_sargasso_world()
	var in_range: Array = world.markers_in_range(p.scanner_state.range_radius)
	if in_range.is_empty(): _fail("no markers in range"); return
	# Force propulsion operational so travel is allowed (foundation test, not gate test).
	var mgr = p.get_ship_systems_manager()
	for sid in ["power", "navigation", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				mgr.force_repair(sid, sub.subcomponent_id)
	var res: Dictionary = p.travel_to_marker_id(String(in_range[0].marker_id))
	if not bool(res.get("success", false)): _fail("travel failed: %s" % str(res.get("reason",""))); return

	if p.active_ship_root_count_for_validation() < 2:
		_fail("home + derelict not co-present (count<2)"); return
	var home = p.get_home_ship_for_validation()
	var cur = p.get_current_ship()
	if home == null or cur == null or home == cur: _fail("home/current not distinct"); return
	var home_o: Vector3 = home.scene_root.global_position
	var der_o: Vector3 = cur.scene_root.global_position
	if home_o.distance_to(der_o) < 10.0:
		_fail("ships not spatially separated (%.1f)" % home_o.distance_to(der_o)); return
	# Derelict loot containers (if any) must sit nearer the derelict than the home origin.
	for lc in p.loot_containers:
		if lc.global_position.distance_to(der_o) > lc.global_position.distance_to(home_o):
			_fail("derelict loot not parented under moved derelict root"); return

	finished = true
	print("DOCK COPRESENCE PASS roots=%d separated=true loot_aligned=true" % p.active_ship_root_count_for_validation())
	_teardown(0)

func _find_playable(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null: return f
	return null

func _fail(r: String) -> void:
	if finished: return
	finished = true
	push_error("DOCK COPRESENCE FAIL reason=%s" % r)
	_teardown(1)

func _teardown(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_quit")

func _quit() -> void:
	quit(_exit_code)
```

- [ ] **Step 2: Run it; verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_copresence_smoke.gd`
Expected: FAIL with `count<2` or `not spatially separated` — today travel detaches home and places the derelict at origin.

- [ ] **Step 3: Implement the refactor**

Apply the decisions above to `playable_generated_ship.gd`. Locate each method by NAME (line numbers below are approximate on the #4 coordinator). Concretely:
1. Add `const DERELICT_DOCK_OFFSET := Vector3(100.0, 0.0, 0.0)` near the other consts.
2. In `_attach_derelict_active` (~L1035): delete the home-hull `remove_child` block and the `_detach_starting_gameplay_roots()` call; after `add_child(new_root)`, set `new_root.position = DERELICT_DOCK_OFFSET`.
3. In `_build_derelict_objectives` (~L1057), `_build_loot_containers` (~L1140), AND `_build_repair_points` (~L1176): when building for the away derelict, parent each created `Interactable`/`LootContainer`/`RepairPoint` under `current_ship.scene_root` instead of `derelict_objective_root`/`loot_container_root`/`repair_point_root` (keep appending to the existing teardown arrays). The home ship stays at origin → its gameplay (home loot, lifeboat repair point) may remain under the coordinator-origin roots; only the DERELICT's nodes move to the offset.
4. In `travel_to` (~L1324): delete the `_detach_starting_gameplay_roots()` and home-hull `remove_child` in the `String(leaving.marker_id) == ""` branch — the home stays in-tree. Keep recording `_home_player_position`.
5. In `travel_home` (~L1380): remove `_reattach_starting_gameplay_roots()`; the home roots were never detached. KEEP #4's repair-point/loot rebuild for the home ship.
6. In `_reset_runtime_for_reload` (~L3220): in the `away_from_start` block, remove ONLY the `_reattach_starting_gameplay_roots()` call (now a no-op/double-add risk); preserve EVERY other #4 behavior (derelict-root free, loader re-attach, `_clear_derelict_objectives`/`_clear_loot_containers`/`_clear_repair_points`, repair-point rebuild, opening damage).
7. Delete `_starting_gameplay_roots`/`_detach_starting_gameplay_roots`/`_reattach_starting_gameplay_roots` (~L1017–L1029) after confirming no remaining callers via grep.
8. Add the validation seams:

```gdscript
func active_ship_root_count_for_validation() -> int:
	var count := 0
	if home_ship != null and home_ship.scene_root != null and is_instance_valid(home_ship.scene_root) and home_ship.scene_root.get_parent() == self:
		count += 1
	if current_ship != null and current_ship != home_ship and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root) and current_ship.scene_root.get_parent() == self:
		count += 1
	return count

func get_home_ship_for_validation():
	return home_ship
```

Preserve every existing reload/persistence invariant noted in the method comments (the `away_from_start` reload block exists to avoid a wedged sim and leaked derelict root — keep its derelict-free + loader-reattach behavior; only the home-root reattach is removed).

- [ ] **Step 4: Run it; verify PASS** — `DOCK COPRESENCE PASS roots=2 separated=true loot_aligned=true`. Then run the existing travel/reload smokes to catch regressions:

```bash
for s in lifeboat_travel_gate_smoke repair_loop_smoke main_playable_slice_completion_smoke; do
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/$s.gd
done
```
Expected: each prints its existing PASS marker. If any fails, the detach/reattach removal broke an invariant — fix before committing.

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/dock_copresence_smoke.gd
git commit -m "refactor(docking): co-present per-ship positioned subtrees (kill origin swap)"
```

---

### Task 6: Coordinator — occupancy-driven active context

**Goal:** derive the active ship from player position via `ShipOccupancy` instead of the `away_from_start` flag, and expose `current_occupancy`. After this task, walking the player between the two co-present ships flips which ship is "active" for HUD/objective context.

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/occupancy_flip_smoke.gd`

**Background to read first:** `get_current_ship` (L963), `_process` (L1799), the `player.teleport_to` seam used in `repair_loop_smoke`. Note `away_from_start` is read widely (gates `_process` hazard ticking, persistence `current_location`); this task ADDS occupancy as the source of truth for "active ship" but keeps `away_from_start` derived from it (true when occupancy != home) so existing reads keep working.

**Interfaces:**
- Produces:
  - `var current_occupancy` — the `ShipInstance` the player currently occupies (defaults to `home_ship`).
  - `func _occupancy_entries() -> Array` — builds `[{inst, aabb}]` for the home ship first, then the docked derelict (host-priority order), using `ShipInstance.interior_aabb()`.
  - `func recompute_occupancy() -> void` — sets `current_occupancy` via `ShipOccupancyScript.resolve(player.global_position, _occupancy_entries())`, falling back to `home_ship` when the resolve is null; updates `away_from_start = (current_occupancy != home_ship)`.
  - `func get_current_occupancy_for_validation()` — returns `current_occupancy`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/occupancy_flip_smoke.gd` — boot, travel (co-present pair from Task 5), teleport the player to the derelict root origin → occupancy = derelict; teleport back near home origin → occupancy = home:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
var main_node: Node
var frame_count := 0
var finished := false
var _exit_code := 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	var p = _find(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("no playable")
		return
	_run(p)

func _run(p) -> void:
	var mgr = p.get_ship_systems_manager()
	for sid in ["power", "navigation", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents: mgr.force_repair(sid, sub.subcomponent_id)
	var world = p.get_sargasso_world()
	var ir: Array = world.markers_in_range(p.scanner_state.range_radius)
	if ir.is_empty(): _fail("no markers"); return
	if not bool(p.travel_to_marker_id(String(ir[0].marker_id)).get("success", false)):
		_fail("travel failed"); return

	var home = p.get_home_ship_for_validation()
	var der = p.get_current_ship()
	# Stand inside the derelict.
	p.player.teleport_to(der.scene_root.global_position)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != der: _fail("not aboard derelict after teleport"); return
	# Walk back to the home ship.
	p.player.teleport_to(home.scene_root.global_position)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != home: _fail("not aboard home after return"); return

	finished = true
	print("OCCUPANCY FLIP PASS derelict=true home=true")
	_teardown(0)

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null

func _fail(r: String) -> void:
	if finished: return
	finished = true
	push_error("OCCUPANCY FLIP FAIL reason=%s" % r)
	_teardown(1)

func _teardown(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(_exit_code)
```

- [ ] **Step 2: Run it; verify it fails** (no `recompute_occupancy`/`get_current_occupancy_for_validation`).

- [ ] **Step 3: Implement occupancy on the coordinator**

Add the preload const with the others: `const ShipOccupancyScript := preload("res://scripts/systems/ship_occupancy.gd")`. Add `var current_occupancy` near `current_ship`. Implement:

```gdscript
func _occupancy_entries() -> Array:
	var entries: Array = []
	if home_ship != null and home_ship.scene_root != null and is_instance_valid(home_ship.scene_root):
		entries.append({"inst": home_ship, "aabb": home_ship.interior_aabb()})
	if current_ship != null and current_ship != home_ship and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root):
		entries.append({"inst": current_ship, "aabb": current_ship.interior_aabb()})
	return entries

func recompute_occupancy() -> void:
	if home_ship == null:
		return
	var resolved = home_ship
	if player != null and player is Node3D:
		var r = ShipOccupancyScript.resolve((player as Node3D).global_position, _occupancy_entries())
		if r != null:
			resolved = r
	current_occupancy = resolved
	away_from_start = (current_occupancy != home_ship)

func get_current_occupancy_for_validation():
	return current_occupancy
```

Initialize `current_occupancy = home_ship` wherever `home_ship` is first assigned (in `_on_ship_loaded`, the home-wrap path). Leave `away_from_start`'s existing readers intact — `recompute_occupancy` keeps it consistent.

- [ ] **Step 4: Run it; verify PASS** — `OCCUPANCY FLIP PASS derelict=true home=true`. Re-run `repair_loop_smoke` and `lifeboat_travel_gate_smoke` to confirm `away_from_start`-dependent paths still pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/occupancy_flip_smoke.gd
git commit -m "feat(docking): occupancy-driven active ship context"
```

---

### Task 7: Canonical opening — starting derelict + lifeboat docked

**Goal (Option A, user-approved — LEAN realization):** add a physical 3-room lifeboat docked to the existing rich home ship (the golden `coherent_ship_001`, which is now "the starting derelict" the player explores and loots), relocate the repair point's PARENTING into the lifeboat, and expose the lifeboat as a co-present `ShipInstance`. Keep #4's systems/travel/opening-damage wiring intact (the home ship's `ship_systems_manager` already IS "the lifeboat's" travel/repair systems per #4's own comments). Player still spawns in the derelict. This delivers the canonical opening (explore+loot the derelict → walk to the docked lifeboat → repair its propulsion → travel) with minimal disruption; a fuller systems separation is deferred (not needed until ship-ownership in 5c).

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/canonical_opening_smoke.gd`
- (NO archetype/loot-table changes needed — `coherent_ship_001`'s gameplay slice already carries the `repair_parts_starter` loot container with a guaranteed circuit_board.)

**Background to read first (locate by NAME; ~lines on the #4+Task5/6 coordinator):** `scripts/procgen/life_boat.gd` (`LifeBoatBuilder.build()` returns a 3-room Node3D; `build_layout()` for the layout dict), `_build_runtime_nodes` (~858) and `_on_ship_loaded` (~1506, where `home_ship` is wrapped + `current_ship`/`current_occupancy` set), `_build_repair_points` (~1227; HOME branch parents repair points under `repair_point_root`), `_apply_lifeboat_opening_damage` (~1328, damages `ship_systems_manager`), `_active_systems_manager` (~1276), `active_ship_root_count_for_validation` + `_occupancy_entries` (the Task 5/6 seams). `DockingManagerScript`/`DockPortsScript` are available.

**Decisions for the implementer (LEAN Option A):**
- `home_ship` STAYS the existing `coherent_ship_001` — unchanged content (objectives, hazards, route-control, loot) and its `ship_systems_manager` (which #4 already treats as the player's travel/repair "lifeboat" systems; opening damage + travel gate + repair stay on it). `home_ship` is conceptually "the derelict" the player explores. Do NOT make it a dead shell; do NOT touch its loot/objectives.
- ADD a `var lifeboat_ship` ShipInstance: build a 3-room scene via `LifeBoatBuilder.build()` as its `scene_root`; set `lifeboat_ship.systems_manager = ship_systems_manager` (SHARED — it is the player's functional systems); place it co-present at a FIXED dock anchor offset from the home ship that does NOT collide with `coherent_ship_001`'s extent or with `DERELICT_DOCK_OFFSET` (e.g. `Vector3(-30, 0, 0)` — verify no overlap in the smoke); set `lifeboat_ship.parent_ship = home_ship` and append to `home_ship.docked_ships` (use `DockingManagerScript` if a clean port pair is available, else set the transform + relationship fields directly — `coherent_ship_001` has no `dock` room, so a fixed anchor is acceptable for the foundation). Parent `lifeboat_ship.scene_root` under the coordinator (in-tree, co-present).
- Relocate the HOME repair point INTO the lifeboat: in `_build_repair_points`, the home (non-away) branch must parent the repair point(s) under `lifeboat_ship.scene_root` instead of `repair_point_root`, so the player physically repairs in the docked lifeboat. (Opening damage still applies to `ship_systems_manager`, so the nav_linkage repair point still appears at home — now located in the lifeboat.) Keep the away-derelict branch (parents under `current_ship.scene_root`) unchanged.
- Player still spawns in the derelict (`coherent_ship_001`) — unchanged.
- Update the Task 5/6 seams to know about the lifeboat at home: `active_ship_root_count_for_validation()` must also count `lifeboat_ship.scene_root` when in-tree (so the home pair reads as 2); `_occupancy_entries()` must include `lifeboat_ship` (host order: home derelict first, then lifeboat) so occupancy can distinguish the two co-present home ships.
- Rebuild/teardown: ensure `lifeboat_ship` + its scene are rebuilt on reload and not leaked (mirror how `home_ship` is handled in `_on_ship_loaded`/`_reset_runtime_for_reload`).

**Interfaces:**
- Produces:
  - `var lifeboat_ship` + `func get_lifeboat_ship_for_validation()` — returns the lifeboat `ShipInstance`.
  - `get_home_ship_for_validation()` returns `home_ship` (the derelict `coherent_ship_001`) — unchanged.
  - `get_ship_systems_manager()` unchanged (returns `ship_systems_manager`, the shared travel/repair systems — propulsion offline at boot via opening damage).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/canonical_opening_smoke.gd`:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
var main_node: Node
var frame_count := 0
var finished := false
var _exit_code := 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	var p = _find(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("no playable")
		return
	_run(p)

func _run(p) -> void:
	var derelict = p.get_home_ship_for_validation()
	var lifeboat = p.get_lifeboat_ship_for_validation()
	if derelict == null or lifeboat == null: _fail("missing starting derelict or lifeboat"); return
	if lifeboat.parent_ship != derelict: _fail("lifeboat not docked to starting derelict"); return
	# Two ships co-present, separated.
	if p.active_ship_root_count_for_validation() < 2: _fail("pair not co-present"); return
	# Player begins aboard the derelict.
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != derelict: _fail("player not spawned in derelict"); return
	# Lifeboat propulsion offline at boot (opening damage retained).
	var mgr = p.get_ship_systems_manager()
	if mgr.is_operational("propulsion"): _fail("lifeboat propulsion should be offline at boot"); return
	# Starting loot lives on the derelict and yields a circuit_board.
	if p.loot_containers.is_empty(): _fail("no starting loot on derelict"); return
	for lc in p.loot_containers:
		p.search_loot_container_for_validation(String(lc.container_id))
	if p.inventory_state.get_quantity("circuit_board") < 1: _fail("derelict loot did not yield circuit_board"); return

	finished = true
	print("CANONICAL OPENING PASS docked=true aboard_derelict=true prop_offline=true loot=true")
	_teardown(0)

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null

func _fail(r: String) -> void:
	if finished: return
	finished = true
	push_error("CANONICAL OPENING FAIL reason=%s" % r)
	_teardown(1)

func _teardown(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(_exit_code)
```

- [ ] **Step 2: Run it; verify it fails** (boot is still lifeboat-only; no starting derelict / `get_lifeboat_ship_for_validation`).

- [ ] **Step 3: Implement the canonical opening (LEAN Option A)**

- NO data changes. `coherent_ship_001`'s gameplay slice already has the `repair_parts_starter` loot container (guaranteed circuit_board), and `home_ship` stays `coherent_ship_001` with all its content.
- Add `var lifeboat_ship` (untyped, `# ShipInstance`). In the home-wrap path of `_on_ship_loaded` (where `home_ship`/`current_ship`/`current_occupancy` are set), build the lifeboat: `var lb_root = LifeBoatBuilderScript.build()` (add a `const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")` if not already present); `lifeboat_ship = ShipInstanceScript.create("lifeboat", "", null, ship_systems_manager, lb_root)` (shares the travel/repair systems manager); position `lb_root` at a fixed anchor that does not overlap `coherent_ship_001` or `DERELICT_DOCK_OFFSET` (e.g. `Vector3(-30, 0, 0)`); set `lifeboat_ship.parent_ship = home_ship` and `home_ship.docked_ships.append(lifeboat_ship)`; `add_child(lb_root)` so it is co-present in-tree. Guard against double-build on reload (rebuild cleanly; free any prior `lifeboat_ship.scene_root`).
- In `_build_repair_points`, change the HOME (non-away) branch to parent the repair point under `lifeboat_ship.scene_root` (when valid) instead of `repair_point_root`, so the player repairs physically inside the docked lifeboat. Leave the away-derelict branch unchanged. (`_apply_lifeboat_opening_damage` still damages `ship_systems_manager` → the nav_linkage repair point still appears at home, now inside the lifeboat.)
- Update `active_ship_root_count_for_validation()` to also count `lifeboat_ship.scene_root` when it is a valid in-tree child of the coordinator (so the home pair reads as ≥2).
- Update `_occupancy_entries()` to append `{inst: lifeboat_ship, aabb: lifeboat_ship.interior_aabb()}` after the home entry (host order: derelict first, lifeboat second) so occupancy distinguishes the two co-present home ships.
- Add `func get_lifeboat_ship_for_validation(): return lifeboat_ship`. `get_home_ship_for_validation()` and `get_ship_systems_manager()` are unchanged.
- Player spawn unchanged (already spawns in the derelict / `coherent_ship_001`).

- [ ] **Step 4: Run it; verify PASS** — `CANONICAL OPENING PASS docked=true aboard_derelict=true prop_offline=true loot=true`. Then run the regression set and confirm each existing PASS marker (these should stay green because #4's systems/travel/repair semantics are unchanged — only the repair point's PARENT node moved): `repair_loop_smoke`, `lifeboat_travel_gate_smoke`, `occupancy_flip_smoke`, `dock_copresence_smoke`, `derelict_gameplay_smoke`, `world_save_anywhere_smoke`, `main_playable_slice_completion_smoke`, `travel_integration_smoke`. Run SERIALLY (procgen temp-file race under parallel main-scene smokes). If `repair_loop_smoke`/`lifeboat_travel_gate_smoke` regress because they assert the repair point's parent/location, update ONLY those locality assertions to the lifeboat (document which). If anything else regresses, STOP and report.

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/canonical_opening_smoke.gd
git commit -m "feat(docking): canonical opening — physical lifeboat docked to the explorable derelict"
```

---

### Task 8: Docking-loop persistence (lean Option A)

**Goal (RESHAPED for lean Option A):** prove the canonical docked-pair opening + the full repair→travel→home loop survive a disk save/load — specifically that the docked lifeboat is correctly rebuilt and re-docked to the home derelict after `request_load`. Add the minimal persistence wiring ONLY if the lifeboat does not already round-trip.

**Why this differs from the original plan:** the original Task 8 (a `not_aboard_ship` travel gate + "lifeboat undocks and docks to the destination derelict" + new WorldSnapshot fields) does NOT apply under the user-approved lean Option A: the lifeboat is a home-docked annex that SHARES `ship_systems_manager`, so (1) there is no separate lifeboat systems state to persist — it is deterministically rebuilt at home by `_build_lifeboat_at_home()` from `LifeBoatBuilder` + the shared (already-persisted) manager; (2) `#4`'s propulsion gate already enforces no-stranding, and an "aboard the lifeboat" gate is unimplementable here (lifeboat `interior_aabb()` is zero in headless) AND unnecessary — it is a 5c multi-ship-ownership concern; (3) travel keeps Task 5's co-present-away-derelict model (the lifeboat stays home). So Task 8 is primarily an integration+persistence SMOKE, plus a small fix only if needed.

**Files:**
- Test: `scripts/validation/docking_loop_smoke.gd` (new)
- Modify ONLY IF the lifeboat fails to round-trip: `scripts/procgen/playable_generated_ship.gd` (and/or `scripts/systems/world_snapshot.gd`) — see Step 3.

**Background to read first:** `repair_loop_smoke.gd` (the existing #4 end-to-end smoke — model the new smoke on it: it already does boot → loot → repair (via `repair_subcomponent_for_validation`/`advance_repair_channels_for_validation`) → travel → `request_save`/`request_load`), `_on_ship_loaded` + `_build_lifeboat_at_home()` (Task 7 — how the lifeboat is rebuilt), `_reset_runtime_for_reload` (sets `lifeboat_ship = null` so it rebuilds), `get_lifeboat_ship_for_validation()`/`get_home_ship_for_validation()`.

**Decisions for the implementer:**
- This task is a SMOKE FIRST. Do NOT add a `not_aboard_ship` gate, do NOT re-express travel as lifeboat-undock/dock, do NOT add WorldSnapshot fields up front. The lifeboat is rebuilt deterministically; verify that empirically.
- Write `docking_loop_smoke.gd` (below). Run it. If it PASSES with no code change, the lifeboat already round-trips — commit just the smoke.
- ONLY if the post-load assertions fail (lifeboat missing / not docked after `request_load`), make the SMALLEST fix to `_on_ship_loaded`/`_build_lifeboat_at_home`/`_reset_runtime_for_reload` so the lifeboat is rebuilt + `parent_ship`-linked after a disk load, and document exactly what you changed and why. Do not add persistence fields unless the lifeboat genuinely carries non-deterministic state (it should not).

**Interfaces:**
- Produces: `docking_loop_smoke.gd` proving the docked-pair opening + repair→travel→home loop + lifeboat survival across save/load.

- [ ] **Step 1: Write the smoke**

Create `scripts/validation/docking_loop_smoke.gd` — model on `repair_loop_smoke.gd`'s structure (the main-scene boot harness, the loot/repair/travel/save-load sequence). Assert, in order: (opening) `get_lifeboat_ship_for_validation()` is non-null and `.parent_ship == get_home_ship_for_validation()` and `active_ship_root_count_for_validation() >= 2`; (loop) loot the home derelict for a `circuit_board`, repair the lifeboat propulsion via `repair_subcomponent_for_validation`/`advance_repair_channels_for_validation`, assert `get_ship_systems_manager().is_operational("propulsion")`, travel to an in-range marker (success), `travel_home()`; (persist) `request_save()` then `request_load()`, then assert AGAIN that `get_lifeboat_ship_for_validation()` is non-null and `.parent_ship == get_home_ship_for_validation()` (lifeboat rebuilt + re-docked) and the propulsion repair persisted. Print marker `DOCKING LOOP PASS opening=true looped=true persisted=true`.

- [ ] **Step 2: Run it; observe** — it may PASS immediately (lifeboat already round-trips) or FAIL on a post-load assertion (lifeboat not rebuilt/re-docked).

- [ ] **Step 3: Fix only if needed** — if Step 2's post-load assertions failed, apply the smallest coordinator fix so the lifeboat is rebuilt + `parent_ship`-linked after `request_load`, then re-run to PASS. If Step 2 passed, no code change.

- [ ] **Step 4: Verify PASS + regressions** — `DOCKING LOOP PASS opening=true looped=true persisted=true`, then run SERIALLY: `repair_loop_smoke`, `lifeboat_travel_gate_smoke`, `dock_copresence_smoke`, `occupancy_flip_smoke`, `canonical_opening_smoke` — all keep their existing PASS markers (pristine apart from allowlisted noise incl. the known `Failed to instantiate an autoload` local-drift line).

- [ ] **Step 5: Commit**

```bash
git add scripts/validation/docking_loop_smoke.gd   # + playable_generated_ship.gd / world_snapshot.gd ONLY if Step 3 changed them
git commit -m "test(docking): end-to-end docking-loop persistence smoke (lean Option A)"
```

---

### Task 9: Regression registration + ADR-0016

**Files:**
- Modify: `docs/game/06_validation_plan.md`
- Create: `docs/game/adr/0016-ship-docking-foundation.md`

- [ ] **Step 1: Register the new smokes**

Add to the regression bundle in `docs/game/06_validation_plan.md` (follow the existing entry format — command + expected PASS marker) for: `docking_manager_smoke` (`DOCKING MANAGER PASS`), `ship_occupancy_smoke` (`SHIP OCCUPANCY PASS`), `ship_instance_dock_fields_smoke` (`SHIP INSTANCE DOCK FIELDS PASS`), `dock_ports_smoke` (`DOCK PORTS PASS`), `dock_copresence_smoke` (`DOCK COPRESENCE PASS`), `occupancy_flip_smoke` (`OCCUPANCY FLIP PASS`), `canonical_opening_smoke` (`CANONICAL OPENING PASS`), `docking_loop_smoke` (`DOCKING LOOP PASS`). Update the `commands=` count in the success line (73 → 81).

- [ ] **Step 2: Run the full bundle**

Run the bundle block from `docs/game/06_validation_plan.md` with `GODOT`/`ROOT` set to the Windows values. Expected final line: `SARGASSO REGRESSION PASS commands=81 clean_output=true`. Then Gate-1: `--script res://scripts/validation/gate1_automated_playtest.gd` → `GATE 1 AUTOMATED PLAYTEST PASS`, `pass_decision=GO`. Fix any unallowlisted `ERROR:`/`WARNING:` before proceeding.

- [ ] **Step 3: Write ADR-0016**

Create `docs/game/adr/0016-ship-docking-foundation.md` (follow the format of `adr/0015-ship-repair-loop.md`): context (the shared-origin swap dead-ends multi-ship), decision (per-ship positioned `scene_root`/`ship_root` subtrees + pure `DockingManager` + `ShipOccupancy` + canonical docked opening + relationship-based persistence), the binding forward constraint (generalize to N), rejected alternatives (minimal two-ship special-case; full ship-as-autonomous-scene), and consequences (5a loads ≤2 ships; 5b/5c build on this).

- [ ] **Step 4: Commit**

```bash
git add docs/game/06_validation_plan.md docs/game/adr/0016-ship-docking-foundation.md
git commit -m "docs(docking): register Phase 5a smokes + ADR-0016 ship docking foundation"
```

---

## Self-Review

**Spec coverage:**
- Per-ship world-space subtrees → Task 5. Occupancy → Tasks 2,6. DockingManager → Task 1. Walkable dock connector / ports → Tasks 4 (derivation) + 5/7 (placement) + the dock-port generation contract (Task 7 archetype dock room). Canonical opening + starting-loot relocation → Task 7. Travel re-expression + `not_aboard_ship` → Task 8. Relationship-based persistence → Task 8. Testing/regression → every task + Task 9. ADR → Task 9. **No uncovered spec section.**
- One spec item folded rather than split: the "guaranteed wall portal on the dock-facing side" is handled pragmatically in Task 7 (guarantee a `dock` room; the lifeboat parks at its opening) plus the `dock_copresence`/`canonical_opening` smokes asserting walkable separation — rather than a separate `wall_door_resolver` task. If the dock room is walled off in practice, Task 7 must add the portal guarantee to `wall_door_resolver.gd`; the smoke is the gate that surfaces it.

**Placeholder scan:** New isolated units (Tasks 1–4) and their smokes are complete code. Coordinator-surgery tasks (5–8) give exact methods (by name + line), the precise edits, full new-helper code, and a complete gating smoke; Task 8's end-to-end smoke is specified by reference to the existing `repair_loop_smoke.gd` structure it mirrors (full structural twin in-repo) rather than duplicated verbatim — acceptable because the pattern file exists and the assertions are enumerated. No "TBD"/"handle edge cases"/vague steps.

**Type consistency:** `ship_root` alias ↔ `scene_root` (Task 3) used consistently in Tasks 5–8. `DockingManager.dock/undock/compute_mobile_transform`, `ShipOccupancy.resolve`, `DockPorts.for_lifeboat/for_derelict` signatures are used exactly as defined. Port dict shape `{position: Vector3, facing: Vector3}` is consistent across Tasks 1/4/8. `WorldSnapshot` new fields `docked_to`/`occupancy`/`lifeboat_ship` consistent between Task 8's coordinator writes and snapshot round-trip.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-22-phase5a-ship-docking-foundation.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session with checkpoints.

Which approach?
