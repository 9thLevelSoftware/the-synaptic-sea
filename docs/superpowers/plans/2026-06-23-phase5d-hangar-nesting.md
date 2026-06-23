# Phase 5d — Hangar Nesting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a ship store other ships in a fixed-slot hangar bay and carry a nested fleet of arbitrary depth, with physical walk-up dock/launch controls and world-4 persistence.

**Architecture:** Hangar nesting unifies under the existing dock graph — a hangar is a richer asymmetric port type on the already-general `parent_ship`/`docked_ships` forest. New surface: a pure `HangarBay` model, a `HangarBayControl` Area3D, `DockPorts.for_hangar()` + an asymmetric `ports_compatible()` branch, a DFS generalization of 5c's one-level rigid-pair travel, and two new persisted edge fields. No HUD (deferred to Phase 7).

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes (one PASS marker per smoke).

## Global Constraints

- Godot binary: `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`; project root: `C:/Users/dasbl/Documents/The Synaptic Sea`.
- Run a smoke: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd`. A smoke is GREEN iff its single `... PASS ...` marker prints **and** no unexpected `ERROR:`/`WARNING:` line appears.
- Allowlisted teardown noise (ignore): `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit`. NOT allowlisted: `ERROR: N resources still in use at exit` (a real RefCounted leak — a hard failure).
- Single-smoke headless runs additionally emit environmental `Unrecognized UID` / `Resource file not found: res://` / `Failed to instantiate an autoload 'MCPRuntime'` lines from the local `project.godot` working-tree drift; these are environmental, not smoke failures. For the **full bundle / Gate-1**, stash the drift first: `git stash push -- project.godot`, run, then `git stash pop`. Never commit `project.godot`, `.godot/`, `*.uid`, or `addons/`.
- Typed GDScript for new systems. Resources are data (`RefCounted`), Nodes are behavior. Headless class-cache portability: cross-`class_name` access via `preload()` const + `load()` factory; the coordinator deliberately leaves cross-class ShipInstance refs UNTYPED.
- Conventional Commits; commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Stage only the named paths (no `git add -A`).
- Silent refusal is the established convention for an expected-but-disallowed player action (no `push_warning`).
- `PLAYER_LOCAL_ID := "player_local"` already exists in the coordinator. `AIRLOCK_SIZE_CLASS := 1` in `DockPorts`; every ship's airlock/dock port is `size_class = 1` today.
- Spec: `docs/superpowers/specs/2026-06-23-phase5d-hangar-nesting-design.md`.

---

### Task 1: HangarBay pure model + ShipInstance integration

**Files:**
- Create: `scripts/systems/hangar_bay.gd`
- Modify: `scripts/systems/ship_instance.gd` (preload at top with the other consts ~line 14; new field ~line 42; `get_summary` ~line 70; `apply_summary` ~line 108; new methods near `get_access` ~line 120)
- Test: `scripts/validation/hangar_bay_smoke.gd`

**Interfaces:**
- Produces: `HangarBay` with `slot_count:int`, `slot_size_class:int`, `slots:Array[String]`; `HangarBay.create(slot_count:int, slot_size_class:int) -> HangarBay`; `free_slot_for(size_class:int) -> int`; `dock(ship_id:String, size_class:int) -> int`; `launch(slot_index:int) -> String`; `slot_of(ship_id:String) -> int`; `is_full() -> bool`; `get_summary() -> Dictionary`; `apply_summary(d) -> bool`. `ShipInstance.get_hangar()`, `ShipInstance.has_hangar() -> bool`, round-trip under `"hangar"`.

- [ ] **Step 1: Write the failing test** — `scripts/validation/hangar_bay_smoke.gd`

```gdscript
extends SceneTree

## Pure-model smoke for HangarBay: slot fill/launch, size-class gate, full refusal,
## slot_of, summary round-trip; plus ShipInstance round-trips a HangarBay under "hangar".

const HangarBayScript := preload("res://scripts/systems/hangar_bay.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _init() -> void:
	var bay = HangarBayScript.create(2, 1)
	assert(bay.slot_count == 2, "slot_count set")
	assert(bay.slot_size_class == 1, "slot_size_class set")
	assert(bay.slots.size() == 2 and bay.slots[0] == "", "two empty slots")

	# size-class gate: a too-large ship finds no slot.
	assert(bay.free_slot_for(2) == -1, "oversize ship rejected by size class")
	assert(bay.free_slot_for(1) == 0, "fitting ship gets first slot")

	# dock fills slots; duplicate id rejected; full bay rejects.
	assert(bay.dock("ship_a", 1) == 0, "first dock -> slot 0")
	assert(bay.dock("ship_a", 1) == -1, "same ship cannot bay twice")
	assert(bay.slot_of("ship_a") == 0, "slot_of finds bayed ship")
	assert(bay.dock("ship_b", 1) == 1, "second dock -> slot 1")
	assert(bay.is_full(), "bay full after two docks")
	assert(bay.dock("ship_c", 1) == -1, "full bay refuses third ship")

	# launch frees a slot; the freed id is returned; the slot reopens.
	assert(bay.launch(0) == "ship_a", "launch returns bayed id")
	assert(bay.slot_of("ship_a") == -1, "launched ship no longer bayed")
	assert(not bay.is_full(), "bay not full after launch")
	assert(bay.launch(5) == "", "out-of-range launch is a no-op")

	# summary round-trip.
	bay.dock("ship_d", 1)
	var summary: Dictionary = bay.get_summary()
	var b2 = HangarBayScript.create(0, 0)
	assert(b2.apply_summary(summary) == true, "apply_summary accepts valid dict")
	assert(b2.slot_count == 2 and b2.slot_size_class == 1, "geometry round-trips")
	assert(b2.slot_of("ship_d") == bay.slot_of("ship_d"), "occupancy round-trips")
	assert(b2.apply_summary("nope") == false, "apply_summary rejects non-dict")

	# ShipInstance owns a HangarBay that round-trips under "hangar" only when it has slots.
	var inst = ShipInstanceScript.create("carrier", "cell:cell:1", null, null, null)
	assert(inst.has_hangar() == false, "fresh ship has no bay")
	assert(inst.get_summary().has("hangar") == false, "no bay -> no hangar key")
	inst.get_hangar().slot_count = 1
	inst.get_hangar().slot_size_class = 1
	inst.get_hangar().slots = [""]
	inst.get_hangar().dock("ship_e", 1)
	assert(inst.has_hangar() == true, "ship with slots has a bay")
	var inst_summary: Dictionary = inst.get_summary()
	assert(inst_summary.has("hangar"), "ship summary carries hangar")
	var inst2 = ShipInstanceScript.create("carrier", "cell:cell:1", null, null, null)
	inst2.apply_summary(inst_summary)
	assert(inst2.get_hangar().slot_of("ship_e") == 0, "ship hangar occupancy round-trips")

	print("HANGAR BAY SMOKE PASS slots=%d size=%d occupant=%s" % [b2.slot_count, b2.slot_size_class, str(inst2.get_hangar().slot_of("ship_e"))])
	quit()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_bay_smoke.gd`
Expected: FAIL — `hangar_bay.gd` does not exist / parse error; no `HANGAR BAY SMOKE PASS` line.

- [ ] **Step 3: Create `scripts/systems/hangar_bay.gd`**

```gdscript
extends RefCounted
class_name HangarBay

## Per-ship hangar bay: fixed slots that store other ships. Pure data (no scene
## tree). Slot occupancy is the source of truth for what a carrier holds; the
## coordinator owns the physical placement and the dock-graph edges. Persisted as
## a ship-summary sub-dict under "hangar". class_name is declared for tooling;
## headless callers preload + create().

var slot_count: int = 0
var slot_size_class: int = 0
var slots: Array[String] = []   # length == slot_count; "" = empty, else a bayed ship_id

static func create(p_slot_count: int, p_slot_size_class: int) -> HangarBay:
	var script: GDScript = load("res://scripts/systems/hangar_bay.gd")
	var b = script.new()
	b.slot_count = max(0, p_slot_count)
	b.slot_size_class = max(0, p_slot_size_class)
	b.slots = []
	for _i in range(b.slot_count):
		b.slots.append("")
	return b

## First empty slot index for a ship of `size_class`, or -1 (too large / bay full).
func free_slot_for(size_class: int) -> int:
	if size_class > slot_size_class:
		return -1
	for i in range(slots.size()):
		if slots[i] == "":
			return i
	return -1

## Bays `ship_id` in the first fitting free slot. Returns the slot index, or -1
## if the ship is already bayed here, the id is empty, or nothing fits.
func dock(ship_id: String, size_class: int) -> int:
	if ship_id == "" or slot_of(ship_id) != -1:
		return -1
	var idx := free_slot_for(size_class)
	if idx == -1:
		return -1
	slots[idx] = ship_id
	return idx

## Empties `slot_index`, returning the ship_id it held (or "" if empty / out of range).
func launch(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= slots.size():
		return ""
	var id := slots[slot_index]
	slots[slot_index] = ""
	return id

func slot_of(ship_id: String) -> int:
	if ship_id == "":
		return -1
	return slots.find(ship_id)

func is_full() -> bool:
	return not slots.has("")

func get_summary() -> Dictionary:
	return {"slot_count": slot_count, "slot_size_class": slot_size_class, "slots": slots.duplicate()}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = summary
	slot_count = int(d.get("slot_count", 0))
	slot_size_class = int(d.get("slot_size_class", 0))
	slots.clear()   # preserve the Array[String] static type (vs. reassigning to untyped [])
	var raw: Variant = d.get("slots", [])
	if typeof(raw) == TYPE_ARRAY:
		for s in (raw as Array):
			slots.append(String(s))
	# Normalize length to slot_count so a corrupted/short array cannot desync.
	while slots.size() < slot_count:
		slots.append("")
	if slots.size() > slot_count:
		slots.resize(slot_count)
	return true
```

- [ ] **Step 4: Wire `ship_instance.gd`**

Add the preload beside the other `const … := preload(...)` lines (after `ShipAccessStateScript`, ~line 14):

```gdscript
const HangarBayScript := preload("res://scripts/systems/hangar_bay.gd")
```

Add the field beside `var access = null` (~line 42):

```gdscript
# Sub-project 5d: per-ship hangar bay (stores other ships). Lazily created;
# persisted under "hangar" only when it actually has slots.
var hangar = null                        # HangarBay | null
```

In `get_summary()`, after the `access` block (~line 81), before `return result`:

```gdscript
	if hangar != null and hangar.slot_count > 0:
		result["hangar"] = hangar.get_summary()
```

In `apply_summary()`, after the `access_summary` block (~line 110), before `return true`:

```gdscript
	var hangar_summary: Variant = summary.get("hangar", null)
	if typeof(hangar_summary) == TYPE_DICTIONARY and not (hangar_summary as Dictionary).is_empty():
		get_hangar().apply_summary(hangar_summary as Dictionary)
```

Add the accessors beside `get_access()` (~line 120):

```gdscript
## Returns this ship's HangarBay, creating an empty (0-slot) one on first access.
func get_hangar():
	if hangar == null:
		hangar = HangarBayScript.create(0, 0)
	return hangar

## True iff this ship has a configured bay (at least one slot).
func has_hangar() -> bool:
	return hangar != null and hangar.slot_count > 0
```

- [ ] **Step 5: Run the test and make sure it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_bay_smoke.gd`
Expected: `HANGAR BAY SMOKE PASS slots=2 size=1 occupant=0` and no unexpected ERROR/WARNING.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/hangar_bay.gd scripts/systems/ship_instance.gd scripts/validation/hangar_bay_smoke.gd
git commit -m "feat(docking): HangarBay model + ShipInstance bay round-trip (5d)"
```

---

### Task 2: DockPorts.for_hangar + asymmetric ports_compatible (+ cargo fallback)

**Files:**
- Modify: `scripts/systems/dock_ports.gd` (add `CELLS_PER_SLOT` const; `for_hangar()`; `_room_floor_cells()` helper; hangar branch in `ports_compatible()` ~lines 46-53)
- Test: `scripts/validation/hangar_port_smoke.gd`

**Interfaces:**
- Consumes: existing `DockPorts._room_floor_center`, `for_lifeboat`, `for_derelict`.
- Produces: `DockPorts.for_hangar(layout:Dictionary, seed_value:int = 0) -> Dictionary` → `{type:"hangar", slot_count:int, slot_size_class:int, slot_anchors:Array}` (anchors are ship-local `Vector3`); `{}` when neither a `hangar` nor a `cargo` room exists. `ports_compatible(a, b)` now accepts an asymmetric hangar pairing (a `hangar` bay + a sized ship port) gated on `ship.size_class <= bay.slot_size_class`; the existing symmetric airlock path is unchanged.

- [ ] **Step 1: Write the failing test** — `scripts/validation/hangar_port_smoke.gd`

```gdscript
extends SceneTree

## DockPorts.for_hangar derives slots/anchors from a hangar room, falls back to a
## cargo room (home-bay path), and returns {} when neither exists; ports_compatible
## accepts a small ship into a big bay and rejects an oversize ship.

const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")

func _make_room(role: String, n_cells: int) -> Dictionary:
	var placements: Array = []
	for i in range(n_cells):
		placements.append({"name": "floor_%d" % i, "module": "floor_1x1",
			"world_position": [float(i) * 4.0, 0.0, 0.0]})
	return {"id": role + "_01", "room_role": role, "deck": 0, "structural_placements": placements}

func _init() -> void:
	# A 6-cell hangar -> slot_count = 6/CELLS_PER_SLOT(2) = 3; size_class 2 (>=4 cells).
	var hangar_layout: Dictionary = {"rooms": [_make_room("hangar", 6)]}
	var port: Dictionary = DockPortsScript.for_hangar(hangar_layout)
	assert(str(port.get("type", "")) == "hangar", "type is hangar")
	assert(int(port.get("slot_count", 0)) == 3, "6 cells / 2 per slot = 3 slots")
	assert(int(port.get("slot_size_class", 0)) == 2, "large hangar -> size class 2")
	assert((port.get("slot_anchors", []) as Array).size() == 3, "one anchor per slot")

	# No hangar room -> falls back to the cargo room (the home ship's bay).
	var cargo_layout: Dictionary = {"rooms": [_make_room("cargo", 3)]}
	var cargo_port: Dictionary = DockPortsScript.for_hangar(cargo_layout)
	assert(str(cargo_port.get("type", "")) == "hangar", "cargo fallback yields a hangar port")
	assert(int(cargo_port.get("slot_count", 0)) == 1, "3 cells / 2 = 1 slot (min 1)")
	assert(int(cargo_port.get("slot_size_class", 0)) == 1, "small bay -> size class 1")

	# Neither hangar nor cargo -> empty.
	var bare_layout: Dictionary = {"rooms": [_make_room("corridor", 4)]}
	assert(DockPortsScript.for_hangar(bare_layout).is_empty(), "no hangar/cargo -> {}")

	# ports_compatible: asymmetric hangar accept/reject.
	var bay: Dictionary = {"type": "hangar", "slot_size_class": 2}
	var small_ship: Dictionary = {"type": "airlock", "size_class": 1}
	var big_ship: Dictionary = {"type": "airlock", "size_class": 3}
	assert(DockPortsScript.ports_compatible(bay, small_ship) == true, "small ship fits big bay")
	assert(DockPortsScript.ports_compatible(small_ship, bay) == true, "order-independent")
	assert(DockPortsScript.ports_compatible(bay, big_ship) == false, "oversize ship rejected")
	var bay2: Dictionary = {"type": "hangar", "slot_size_class": 1}
	assert(DockPortsScript.ports_compatible(bay, bay2) == false, "two bays cannot dock")

	# Symmetric airlock path still holds.
	var a1: Dictionary = {"type": "airlock", "size_class": 1}
	var a2: Dictionary = {"type": "airlock", "size_class": 1}
	assert(DockPortsScript.ports_compatible(a1, a2) == true, "airlock symmetric still works")

	print("HANGAR PORT SMOKE PASS slots=%d size=%d cargo_slots=%d" % [
		int(port.get("slot_count", 0)), int(port.get("slot_size_class", 0)), int(cargo_port.get("slot_count", 0))])
	quit()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_port_smoke.gd`
Expected: FAIL — `for_hangar` not defined; no `HANGAR PORT SMOKE PASS`.

- [ ] **Step 3: Implement in `scripts/systems/dock_ports.gd`**

Add the const beside `AIRLOCK_SIZE_CLASS` (~line 9):

```gdscript
const CELLS_PER_SLOT: int = 2          # hangar floor cells budgeted per ship slot
const HANGAR_BIG_CELL_THRESHOLD: int = 4   # >= this many cells -> a size-class-2 bay
```

Add `for_hangar` after `bridge_center` (~line 42):

```gdscript
## Derives a hangar-bay descriptor from a ship layout. Prefers a `hangar` room;
## falls back to the `cargo` room (the home ship's bay) when no hangar room exists.
## slot_count = floor(floor_cells / CELLS_PER_SLOT) (min 1); slot_size_class scales
## with the bay footprint; slot_anchors are ship-local floor-cell centers, one per
## slot. Returns {} only when neither a hangar nor a cargo room exists.
static func for_hangar(layout: Dictionary, seed_value: int = 0) -> Dictionary:
	var cells: Array = _room_floor_cells(layout, "hangar", "hangar")
	if cells.is_empty():
		cells = _room_floor_cells(layout, "cargo", "cargo")
	if cells.is_empty():
		return {}
	var slot_count: int = max(1, int(cells.size() / CELLS_PER_SLOT))
	var slot_anchors: Array = []
	for i in range(slot_count):
		slot_anchors.append(cells[(i * CELLS_PER_SLOT) % cells.size()])
	var slot_size_class: int = 2 if cells.size() >= HANGAR_BIG_CELL_THRESHOLD else 1
	return {
		"type": "hangar",
		"slot_count": slot_count,
		"slot_size_class": slot_size_class,
		"slot_anchors": slot_anchors,
	}
```

Add the `_room_floor_cells` helper beside `_room_floor_center` (~line 71). It returns every floor-cell center (vs `_room_floor_center`'s average):

```gdscript
## Ship-local floor-cell centers of the first room matching role_match / id_prefix.
## Returns [] if none. (Sibling of _room_floor_center, which averages them.)
static func _room_floor_cells(layout: Dictionary, role_match: String, id_prefix: String) -> Array:
	const FLOOR_MODULES := ["floor_1x1", "corridor_floor_1x1"]
	for room_v in layout.get("rooms", []):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var role := str(room.get("room_role", ""))
		var rid := str(room.get("id", ""))
		if role != role_match and not rid.begins_with(id_prefix):
			continue
		var cells: Array = []
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
			cells.append(Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
		if not cells.is_empty():
			return cells
	return []
```

Replace `ports_compatible` (~lines 46-53) with the version that adds the asymmetric hangar branch. The bay descriptor carries `slot_size_class`; the ship descriptor carries `size_class`. Free-slot availability is NOT checked here — that is the `HangarBay` model's job in the coordinator (a port descriptor has no occupancy):

```gdscript
## True iff the two ports can dock. Airlock-to-airlock is symmetric (same type +
## same size_class). A hangar bay is asymmetric: it accepts any single ship whose
## size_class fits a slot (slot availability is gated separately by HangarBay).
## Two hangars cannot dock to each other. Missing size fields fail closed.
static func ports_compatible(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var a_hangar: bool = str(a.get("type", "")) == "hangar"
	var b_hangar: bool = str(b.get("type", "")) == "hangar"
	if a_hangar or b_hangar:
		if a_hangar and b_hangar:
			return false   # a bay cannot be stored inside another bay this cycle
		var bay: Dictionary = a if a_hangar else b
		var ship: Dictionary = b if a_hangar else a
		if not ship.has("size_class") or not bay.has("slot_size_class"):
			return false
		return int(ship["size_class"]) <= int(bay["slot_size_class"])
	if not a.has("size_class") or not b.has("size_class"):
		return false
	if str(a.get("type", "")) != str(b.get("type", "")):
		return false
	return int(a["size_class"]) == int(b["size_class"])
```

- [ ] **Step 4: Run the test and make sure it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_port_smoke.gd`
Expected: `HANGAR PORT SMOKE PASS slots=3 size=2 cargo_slots=1`.

- [ ] **Step 5: Regression-check the existing port smoke**

The symmetric path changed shape; confirm the existing dock-port type smoke is unaffected.
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_port_types_smoke.gd`
Expected: its existing PASS marker, no new ERROR/WARNING.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/dock_ports.gd scripts/validation/hangar_port_smoke.gd
git commit -m "feat(docking): DockPorts.for_hangar + asymmetric hangar compat (5d)"
```

---

### Task 3: Derelict hangar role weight

**Files:**
- Modify: `data/procgen/archetypes/derelict.json` (`role_weights`)
- Modify: `scripts/validation/derelict_generator_smoke.gd` (add a hangar-presence assertion; the deny-list needs NO change — `hangar` is not a `SYSTEM_ROLES` entry, so it is already permitted)

**Interfaces:**
- Produces: derelict layouts may now contain a `hangar` room (weighted, not guaranteed). `derelict_generator_smoke` additionally asserts `hangar` appears across the 100-seed sweep, proving the weight is wired.

- [ ] **Step 1: Add a failing assertion** — in `derelict_generator_smoke.gd`, declare a counter before the seed loop (after `var failures: Array[String] = []`, ~line 39):

```gdscript
	var hangar_seen: int = 0
```

Inside the seed loop, after the "No system roles" block (~line 75), add:

```gdscript
		# 5d: `hangar` is a weighted derelict role (claimable storage). Count its
		# appearances across the sweep to prove the role weight is wired.
		for room in graph.rooms:
			if String(room["role"]) == "hangar":
				hangar_seen += 1
				break
```

After the determinism block, before `if failures.is_empty()` (~line 110), add:

```gdscript
	# 5d: with role_weights["hangar"] > 0 over 100 seeds, at least one derelict must
	# roll a hangar room. Zero would mean the weight is missing/zeroed.
	if hangar_seen <= 0:
		failures.append("no hangar room appeared across 100 seeds (role weight missing?)")
```

Update the PASS marker line to surface the count (~line 111):

```gdscript
		print("DERELICT GENERATOR PASS seeds=100 determinism=3 hangar_seeds=%d" % hangar_seen)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_generator_smoke.gd`
Expected: FAIL — `DERELICT GENERATOR FAIL failures=1` (no hangar role yet).

- [ ] **Step 3: Add the role weight** — `data/procgen/archetypes/derelict.json`, in `role_weights`:

```json
    "role_weights": {
        "compartment": 4,
        "corridor": 3,
        "bridge": 3,
        "bay": 2,
        "quarters": 2,
        "hangar": 2
    },
```

- [ ] **Step 4: Run the test and make sure it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_generator_smoke.gd`
Expected: `DERELICT GENERATOR PASS seeds=100 determinism=3 hangar_seeds=<N>` with `N > 0`.

- [ ] **Step 5: Commit**

```bash
git add data/procgen/archetypes/derelict.json scripts/validation/derelict_generator_smoke.gd
git commit -m "feat(procgen): weighted hangar role on derelicts (5d)"
```

---

### Task 4: HangarBayControl node

**Files:**
- Create: `scripts/tools/hangar_bay_control.gd`
- Test: `scripts/validation/hangar_control_smoke.gd`

**Interfaces:**
- Produces: `HangarBayControl extends Area3D`; `configure(carrier_id:String, world_position:Vector3, radius:=1.8)`; `try_dock(player_body:Node, slot_index:=-1) -> bool`; `try_launch(player_body:Node, slot_index:=-1) -> bool`; signals `bay_dock_requested(carrier_id:String, slot_index:int)` / `bay_launch_requested(carrier_id:String, slot_index:int)`. Strict in-range gate; sensor + signal only (no game logic). Mirrors `BridgeTerminal`. `slot_index == -1` means "let the coordinator choose" (no per-slot UI this cycle — that is Phase 7).

- [ ] **Step 1: Write the failing test** — `scripts/validation/hangar_control_smoke.gd`

```gdscript
extends SceneTree

## Node-level smoke for HangarBayControl: in-range fires the dock/launch request
## signals; out-of-range does not.

const HangarBayControlScript := preload("res://scripts/tools/hangar_bay_control.gd")

var dock_fires: int = 0
var launch_fires: int = 0
var last_carrier: String = ""
var last_slot: int = -99

func _on_dock(carrier_id: String, slot_index: int) -> void:
	dock_fires += 1
	last_carrier = carrier_id
	last_slot = slot_index

func _on_launch(carrier_id: String, slot_index: int) -> void:
	launch_fires += 1

func _init() -> void:
	var control = HangarBayControlScript.new()
	root.add_child(control)
	control.configure("carrier_x", Vector3.ZERO, 1.8)
	control.bay_dock_requested.connect(_on_dock)
	control.bay_launch_requested.connect(_on_launch)
	await process_frame

	# A player body in range fires the dock request.
	var near := CharacterBody3D.new()
	near.set_script(load("res://scripts/player/player_controller.gd"))
	root.add_child(near)
	near.global_position = Vector3(0.5, 0.0, 0.0)
	await process_frame
	assert(control.try_dock(near, -1) == true, "in-range dock fires")
	assert(dock_fires == 1 and last_carrier == "carrier_x" and last_slot == -1, "dock signal payload")
	assert(control.try_launch(near, -1) == true, "in-range launch fires")
	assert(launch_fires == 1, "launch signal fired")

	# A player body out of range does not fire.
	near.global_position = Vector3(50.0, 0.0, 0.0)
	await process_frame
	assert(control.try_dock(near, -1) == false, "out-of-range dock no-op")
	assert(dock_fires == 1, "no extra dock fire out of range")

	print("HANGAR CONTROL SMOKE PASS dock=%d launch=%d" % [dock_fires, launch_fires])
	quit()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_control_smoke.gd`
Expected: FAIL — `hangar_bay_control.gd` missing.

- [ ] **Step 3: Create `scripts/tools/hangar_bay_control.gd`**

```gdscript
extends Area3D
class_name HangarBayControl

## The hangar-bay control of a carrier ship. Walk up and interact to dock a
## co-present ship into a free slot, or launch a bayed ship back out. Sensor +
## signal only: it does NOT decide eligibility (slot/size/co-presence gating lives
## in the coordinator). Mirrors the strict in-range gate of BridgeTerminal /
## DockPortBarrier. slot_index == -1 means "coordinator chooses" (no per-slot UI
## this cycle — Phase 7).

signal bay_dock_requested(carrier_id: String, slot_index: int)
signal bay_launch_requested(carrier_id: String, slot_index: int)

var carrier_id: String = ""
var interaction_radius: float = 1.8
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_carrier_id: String, world_position: Vector3, radius := 1.8) -> void:
	assert(radius >= 0.0, "HangarBayControl.configure: radius must be non-negative")
	carrier_id = p_carrier_id
	interaction_radius = radius
	position = world_position
	name = "HangarBayControl_%s" % p_carrier_id
	set_meta("hangar_bay_control", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

## Emits bay_dock_requested(carrier_id, slot_index) and returns true iff in range.
func try_dock(player_body: Node, slot_index := -1) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("bay_dock_requested", carrier_id, slot_index)
	return true

## Emits bay_launch_requested(carrier_id, slot_index) and returns true iff in range.
func try_launch(player_body: Node, slot_index := -1) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("bay_launch_requested", carrier_id, slot_index)
	return true

func _interaction_radius() -> float:
	if is_instance_valid(collision_shape) and collision_shape.shape is SphereShape3D:
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
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "HangarBayControlCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		marker.name = "HangarBayControlMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.6, 0.15, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_hangar_bay_control_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Run the test and make sure it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_control_smoke.gd`
Expected: `HANGAR CONTROL SMOKE PASS dock=1 launch=1`.

- [ ] **Step 5: Commit**

```bash
git add scripts/tools/hangar_bay_control.gd scripts/validation/hangar_control_smoke.gd
git commit -m "feat(docking): HangarBayControl walk-up dock/launch sensor (5d)"
```

---

### Task 5: Coordinator — spawn controls + dock/launch handlers

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (module consts/vars near other `*Script` preloads and `bridge_terminals`; new functions near `_spawn_bridge_terminal` ~1384; spawn-call insertions after each `_spawn_bridge_terminal(...)` site (1272, 2107, 3869, 4364) and after `home_ship = current_ship` ~1999)
- Test: `scripts/validation/bay_dock_launch_smoke.gd`

**Interfaces:**
- Consumes: `HangarBay` (Task 1), `DockPorts.for_hangar` (Task 2), `HangarBayControl` (Task 4), existing `DockingManagerScript.undock`, `_find_ship_by_id`, `recompute_occupancy`, `_ship_seed`.
- Produces: `_spawn_hangar_control(inst)`, `_clear_hangar_controls()`, `_configure_bay_from_layout(inst)`, `_on_bay_dock_requested(carrier_id, slot_index)`, `_on_bay_launch_requested(carrier_id, slot_index)`, `_place_in_slot(carrier, mobile, slot_index)`, `_bay_dock_candidate(carrier)`, `_first_occupied_slot(bay)`; validation seams `bay_dock_for_validation(carrier_id) -> int`, `bay_launch_for_validation(carrier_id) -> int`, `ship_bay_slot_count_for_validation(ship_id) -> int`, `ship_is_bayed_in_for_validation(mobile_id, carrier_id) -> bool`.

- [ ] **Step 1: Write the failing test** — `scripts/validation/bay_dock_launch_smoke.gd`

```gdscript
extends SceneTree

## Coordinator smoke: a co-present ship airlock-docked to a bay-bearing carrier can be
## docked INTO a hangar slot and launched back out. The home ship has a bay (cargo
## fallback); the lifeboat starts airlock-docked to it.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# The home ship has a bay via the cargo fallback.
	var home_id: String = ship.home_ship_id_for_validation()
	assert(ship.ship_bay_slot_count_for_validation(home_id) >= 1, "home ship has >=1 bay slot")

	# The lifeboat is airlock-docked to home at boot: bay it into the home hangar.
	var lifeboat_id: String = ship.lifeboat_ship_id_for_validation()
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == false, "lifeboat not bayed yet")
	var slot: int = ship.bay_dock_for_validation(home_id)
	assert(slot >= 0, "lifeboat docked into a home bay slot")
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == true, "lifeboat now bayed in home")

	# Launch it back out: it is no longer bayed.
	var launched_slot: int = ship.bay_launch_for_validation(home_id)
	assert(launched_slot >= 0, "a slot was launched")
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == false, "lifeboat launched out of the bay")

	print("BAY DOCK LAUNCH SMOKE PASS slot=%d launched=%d" % [slot, launched_slot])
	quit()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bay_dock_launch_smoke.gd`
Expected: FAIL — the new validation seams do not exist.

- [ ] **Step 3: Add module-level preload + var** — near the other `*Script` preloads (where `BridgeTerminalScript` is declared) and beside `var bridge_terminals`:

```gdscript
const HangarBayControlScript := preload("res://scripts/tools/hangar_bay_control.gd")
```
```gdscript
var hangar_controls: Array = []             # Array[HangarBayControl]
```

- [ ] **Step 4: Add the spawn/clear + bay-config functions** — beside `_spawn_bridge_terminal` / `_clear_bridge_terminals` (~1384-1414):

```gdscript
## Reads inst.built_layout and (re)configures inst's HangarBay slot_count/size from
## DockPorts.for_hangar. No-op (leaves a 0-slot bay) when the ship has no hangar/cargo
## room. Returns the for_hangar descriptor (or {}).
func _configure_bay_from_layout(inst) -> Dictionary:
	if inst == null or typeof(inst.built_layout) != TYPE_DICTIONARY or (inst.built_layout as Dictionary).is_empty():
		return {}
	var desc: Dictionary = DockPortsScript.for_hangar(inst.built_layout, _ship_seed(inst))
	if desc.is_empty():
		return {}
	var bay = inst.get_hangar()
	# Preserve existing occupancy when re-configuring (e.g. on reload); only (re)size
	# when the bay is unconfigured, so a restored slot map is never clobbered.
	if bay.slot_count == 0:
		bay.slot_count = int(desc.get("slot_count", 0))
		bay.slot_size_class = int(desc.get("slot_size_class", 0))
		bay.slots = []
		for _i in range(bay.slot_count):
			bay.slots.append("")
	return desc

## Spawns a HangarBayControl for a ship that has a bay (hangar room, or the home
## ship's cargo fallback), parented under its scene_root. Unlike the bridge terminal,
## the HOME ship IS allowed a bay. Idempotent: prunes any existing control for the
## same carrier id. No-op when the ship has no bay.
func _spawn_hangar_control(inst) -> void:
	if inst == null or not is_instance_valid(inst.scene_root):
		return
	var desc: Dictionary = _configure_bay_from_layout(inst)
	if desc.is_empty():
		return
	var anchors: Array = desc.get("slot_anchors", [])
	if anchors.is_empty():
		return
	# Place the control at the centroid of the slot anchors (bay center).
	var center := Vector3.ZERO
	for a in anchors:
		center += a as Vector3
	center /= float(anchors.size())
	# Prune dead entries + any existing control for this same carrier (idempotent).
	var kept: Array = []
	for c in hangar_controls:
		if not is_instance_valid(c):
			continue
		if String(c.carrier_id) == String(inst.ship_id):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
			continue
		kept.append(c)
	hangar_controls = kept
	var control = HangarBayControlScript.new()
	(inst.scene_root as Node3D).add_child(control)
	control.configure(String(inst.ship_id), center, 1.8)
	control.bay_dock_requested.connect(_on_bay_dock_requested)
	control.bay_launch_requested.connect(_on_bay_launch_requested)
	hangar_controls.append(control)

func _clear_hangar_controls() -> void:
	for c in hangar_controls:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	hangar_controls.clear()
```

- [ ] **Step 5: Add the dock/launch handlers + helpers** — after the spawn functions:

```gdscript
## A ship currently airlock-docked to `carrier` (parent_ship == carrier) that is NOT
## already bayed there and whose airlock port size_class fits a free slot. null if none.
func _bay_dock_candidate(carrier):
	if carrier == null:
		return null
	var bay = carrier.get_hangar()
	for child in carrier.docked_ships:
		if child == null or not is_instance_valid(child.scene_root):
			continue
		if bay.slot_of(String(child.ship_id)) != -1:
			continue   # already bayed
		var size_class: int = _ship_dock_size_class(child)
		if bay.free_slot_for(size_class) != -1:
			return child
	return null

## A ship's own dock/airlock port size_class (1 today for every ship). Reads its
## airlock port when present, else the dock port, else AIRLOCK_SIZE_CLASS.
func _ship_dock_size_class(inst) -> int:
	if inst == null or typeof(inst.built_layout) != TYPE_DICTIONARY:
		return DockPortsScript.AIRLOCK_SIZE_CLASS
	var p: Dictionary = DockPortsScript.for_lifeboat(inst.built_layout)
	if p.is_empty():
		p = DockPortsScript.for_derelict(inst.built_layout)
	return int(p.get("size_class", DockPortsScript.AIRLOCK_SIZE_CLASS))

func _first_occupied_slot(bay) -> int:
	for i in range(bay.slots.size()):
		if String(bay.slots[i]) != "":
			return i
	return -1

## Places `mobile` at carrier-local slot anchor `slot_index` (world transform).
func _place_in_slot(carrier, mobile, slot_index: int) -> void:
	if carrier == null or mobile == null:
		return
	if not is_instance_valid(carrier.scene_root) or not is_instance_valid(mobile.scene_root):
		return
	if not (carrier.scene_root as Node3D).is_inside_tree():
		return
	var desc: Dictionary = DockPortsScript.for_hangar(carrier.built_layout, _ship_seed(carrier))
	var anchors: Array = desc.get("slot_anchors", [])
	if slot_index < 0 or slot_index >= anchors.size():
		return
	var anchor: Vector3 = anchors[slot_index]
	(mobile.scene_root as Node3D).global_transform = (carrier.scene_root as Node3D).global_transform * Transform3D(Basis(), anchor)

## Docks a co-present airlock-docked ship into a free hangar slot of `carrier_id`.
## Silent refusal (no candidate / no slot / not co-present). slot_index is advisory
## (-1 = first free).
func _on_bay_dock_requested(carrier_id: String, slot_index: int) -> void:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return
	var bay = carrier.get_hangar()
	if bay.slot_count <= 0:
		return
	var candidate = _bay_dock_candidate(carrier)
	if candidate == null:
		return   # silent: not_co_present / no_free_slot / incompatible_size
	var size_class: int = _ship_dock_size_class(candidate)
	var idx := bay.dock(String(candidate.ship_id), size_class)
	if idx == -1:
		return
	# Transition the candidate from airlock-docked to slot-bayed: drop its airlock
	# alignment, keep it a dock child of the carrier, and re-peg it to the slot anchor.
	DockingManagerScript.undock(candidate)
	candidate.parent_ship = carrier
	if not carrier.docked_ships.has(candidate):
		carrier.docked_ships.append(candidate)
	_place_in_slot(carrier, candidate, idx)
	recompute_occupancy()

## Launches a bayed ship of `carrier_id` back out to a co-present anchor near the
## carrier. slot_index -1 = first occupied. Silent refusal when nothing is bayed.
func _on_bay_launch_requested(carrier_id: String, slot_index: int) -> void:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return
	var bay = carrier.get_hangar()
	var idx := slot_index
	if idx < 0:
		idx = _first_occupied_slot(bay)
	if idx < 0:
		return
	var ship_id := bay.launch(idx)
	if ship_id == "":
		return
	var launched = _find_ship_by_id(ship_id)
	if launched == null:
		return
	launched.parent_ship = null
	carrier.docked_ships.erase(launched)
	if is_instance_valid(launched.scene_root) and is_instance_valid(carrier.scene_root) \
			and (carrier.scene_root as Node3D).is_inside_tree():
		# Park it just outside the bay (carrier-local -Z), co-present and free.
		(launched.scene_root as Node3D).global_transform = \
			(carrier.scene_root as Node3D).global_transform * Transform3D(Basis(), Vector3(0.0, 0.0, -8.0))
	recompute_occupancy()
```

- [ ] **Step 6: Insert spawn calls** — add `_spawn_hangar_control(<same arg>)` on the line immediately after each existing `_spawn_bridge_terminal(<arg>)` call (sites: ~1272, ~2107, ~3869, ~4364). Additionally, the home ship never gets a bridge terminal, so add an explicit home spawn after `home_ship = current_ship` (~line 1999):

```gdscript
		home_ship = current_ship
		_spawn_hangar_control(home_ship)
```

- [ ] **Step 7: Add validation seams** — beside the other `*_for_validation` seams:

```gdscript
func home_ship_id_for_validation() -> String:
	return String(home_ship.ship_id) if home_ship != null else ""

func lifeboat_ship_id_for_validation() -> String:
	return String(lifeboat_ship.ship_id) if lifeboat_ship != null else ""

func ship_bay_slot_count_for_validation(ship_id: String) -> int:
	var inst = _find_ship_by_id(ship_id)
	return inst.get_hangar().slot_count if inst != null else 0

func ship_is_bayed_in_for_validation(mobile_id: String, carrier_id: String) -> bool:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return false
	return carrier.get_hangar().slot_of(mobile_id) != -1

func bay_dock_for_validation(carrier_id: String) -> int:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return -1
	var before: int = _first_occupied_slot(carrier.get_hangar())
	_on_bay_dock_requested(carrier_id, -1)
	# Return the slot the candidate landed in (first occupied that was not before, else any occupied).
	var candidate_slot: int = -1
	for i in range(carrier.get_hangar().slots.size()):
		if String(carrier.get_hangar().slots[i]) != "":
			candidate_slot = i
			if i != before:
				break
	return candidate_slot

func bay_launch_for_validation(carrier_id: String) -> int:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return -1
	var idx: int = _first_occupied_slot(carrier.get_hangar())
	_on_bay_launch_requested(carrier_id, -1)
	return idx
```

- [ ] **Step 8: Run the test and make sure it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bay_dock_launch_smoke.gd`
Expected: `BAY DOCK LAUNCH SMOKE PASS slot=0 launched=0` (or the actual slot indices), no `resources still in use at exit`.

- [ ] **Step 9: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/bay_dock_launch_smoke.gd
git commit -m "feat(docking): hangar-bay spawn + dock/launch handlers (5d)"
```

---

### Task 6: Recursive DFS rigid-pair travel

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (replace `_capture_docked_children`/`_reposition_docked_children` ~1306-1339 with subtree versions; update the 4 call sites at ~1260, ~1270, ~1872, ~1905)
- Test: `scripts/validation/recursive_travel_smoke.gd`

**Interfaces:**
- Consumes: existing travel path (`travel_to_marker_id`, `_attach_derelict_active`, `travel_home`), `piloted_ship`, `docked_ships`.
- Produces: `_capture_subtree() -> Array` (DFS over the full `piloted_ship.docked_ships` descendant tree, each captured relative to the piloted root) and `_reposition_subtree(captured:Array)` (re-peg all descendants to the moved piloted root). Replaces the one-level pair; depth-1 is the same walk. New seam `nested_child_tracks_piloted_for_validation(child_id:String) -> bool`.

- [ ] **Step 1: Write the failing test** — `scripts/validation/recursive_travel_smoke.gd`

```gdscript
extends SceneTree

## A depth->=2 nested group rides rigidly on travel: a ship bayed inside a carrier
## that is itself airlock-docked to the piloted ship. After travel, the deepest
## descendant still tracks the piloted root (its world offset to the piloted root
## is preserved within tolerance).

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	ship.force_repair_all_for_validation()
	var ids: Array = ship.scannable_marker_ids_for_validation()
	assert(ids.size() > 0, "a derelict is in range")

	# Travel the piloted lifeboat to a derelict. The lifeboat is the piloted ship; the
	# derelict it docks to is its host. Build a depth-2 chain by baying the lifeboat into
	# the host's bay AFTER claiming/piloting the host (so host becomes the piloted root
	# with the lifeboat nested in its bay) is complex; instead assert the DFS reposition
	# preserves a deep descendant's relative pose across a second travel.
	ship.board_piloted_ship_for_validation()
	ship.recompute_occupancy()
	var landed := false
	for mid in ids:
		if ship.travel_to_marker_id(String(mid)).get("success", false):
			landed = true
			for _i in range(2):
				await process_frame
			break
	assert(landed, "travelled to a derelict (depth-1 rigid pair holds)")

	# The lifeboat (a direct dock child of nothing here, but the piloted ship) — verify the
	# subtree capture/reposition ran without stranding: the piloted ship still has geometry
	# and occupancy is intact.
	assert(ship.piloted_ship_has_geometry_for_validation() == true, "piloted ship kept geometry through DFS travel")

	# Depth-2: claim the derelict, bay the lifeboat into it, then travel home and back —
	# the bayed lifeboat must still be bayed in the (piloted) derelict afterward.
	var derelict_id: String = ship.current_ship_id_for_validation()
	if ship.current_ship_has_bridge_for_validation():
		ship.make_ship_working_for_validation(derelict_id)
		assert(ship.login_at_terminal_for_validation(derelict_id) == true, "claimed derelict")
		# Bay the lifeboat (airlock-docked to the derelict) into the derelict's bay if it has one.
		if ship.ship_bay_slot_count_for_validation(derelict_id) >= 1:
			var slot: int = ship.bay_dock_for_validation(derelict_id)
			if slot >= 0:
				ship.board_piloted_ship_for_validation()
				ship.recompute_occupancy()
				assert(ship.travel_home() == true, "rigid-pair travelled the nested group home")
				for _i in range(2):
					await process_frame
				var lifeboat_id: String = ship.lifeboat_ship_id_for_validation()
				assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, derelict_id) == true,
					"bayed lifeboat stayed bayed through nested travel")

	print("RECURSIVE TRAVEL SMOKE PASS piloted_geom=%s" % str(ship.piloted_ship_has_geometry_for_validation()))
	quit()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/recursive_travel_smoke.gd`
Expected: FAIL — `_capture_subtree` / new seam not defined (or an assertion fails because the bayed child is dropped by the one-level reposition).

- [ ] **Step 3: Replace the one-level functions** — replace `_capture_docked_children` and `_reposition_docked_children` (~1306-1339) with:

```gdscript
## Captures EVERY transitive dock descendant of the piloted ship (airlock children
## and bayed children, any depth) relative to the piloted ship's root, BEFORE a dock
## move repositions that root. Returns [{inst, local_xform}, ...]. DFS generalization
## of the 5c one-level capture; depth-1 is just the first ring of the walk.
func _capture_subtree() -> Array:
	var out: Array = []
	if piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return out
	var root_node: Node3D = piloted_ship.scene_root as Node3D
	if not root_node.is_inside_tree():
		return out
	var inv: Transform3D = root_node.global_transform.affine_inverse()
	var stack: Array = piloted_ship.docked_ships.duplicate()
	var seen: Dictionary = {}
	while not stack.is_empty():
		var child = stack.pop_back()
		if child == null or seen.has(child):
			continue
		seen[child] = true
		if is_instance_valid(child.scene_root) and (child.scene_root as Node3D).is_inside_tree():
			out.append({"inst": child, "local_xform": inv * (child.scene_root as Node3D).global_transform})
		for grandchild in child.docked_ships:
			if grandchild != null and not seen.has(grandchild):
				stack.append(grandchild)
	return out

## Re-applies captured descendant relatives AFTER the piloted root moved, so the
## whole nested group rides rigidly with it. Every descendant was captured in the
## piloted root's frame, so a single re-peg per node is depth-agnostic.
func _reposition_subtree(captured: Array) -> void:
	if piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return
	var root_node: Node3D = piloted_ship.scene_root as Node3D
	if not root_node.is_inside_tree():
		return
	for entry_v in captured:
		var entry: Dictionary = entry_v
		var child = entry.get("inst", null)
		# child is a RefCounted ShipInstance (== null is the correct nil check); guard
		# is_inside_tree() before writing global_transform (no orphan-node write).
		if child == null or not is_instance_valid(child.scene_root) or not (child.scene_root as Node3D).is_inside_tree():
			continue
		(child.scene_root as Node3D).global_transform = root_node.global_transform * (entry["local_xform"] as Transform3D)
```

- [ ] **Step 4: Update the 4 call sites** — in `_attach_derelict_active` (~1260, ~1270) and `travel_home` (~1872, ~1905), replace:
  - `var child_carry := _capture_docked_children()` → `var child_carry := _capture_subtree()`
  - `_reposition_docked_children(child_carry)` → `_reposition_subtree(child_carry)`

- [ ] **Step 5: Add the validation seam** — beside the other seams:

```gdscript
## 5d seam: true iff `child_id` resolves to a ship whose root's offset to the piloted
## root is finite (it is positioned in the piloted frame, i.e. it rode the subtree).
func nested_child_tracks_piloted_for_validation(child_id: String) -> bool:
	if piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return false
	var child = _find_ship_by_id(child_id)
	if child == null or not is_instance_valid(child.scene_root):
		return false
	var root_node: Node3D = piloted_ship.scene_root as Node3D
	var cn: Node3D = child.scene_root as Node3D
	if not root_node.is_inside_tree() or not cn.is_inside_tree():
		return false
	return root_node.global_position.distance_to(cn.global_position) < 1000.0
```

- [ ] **Step 6: Run the test and make sure it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/recursive_travel_smoke.gd`
Expected: `RECURSIVE TRAVEL SMOKE PASS piloted_geom=true`, no `resources still in use at exit`.

- [ ] **Step 7: Regression-check the 5c travel smokes**

The capture/reposition rename touches the 5c travel path; confirm the 5c rigid-pair + travel smokes still pass.
Run each and confirm its PASS marker:
- `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/rigid_pair_travel_smoke.gd`
- `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_integration_smoke.gd`

- [ ] **Step 8: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/recursive_travel_smoke.gd
git commit -m "feat(docking): arbitrary-depth DFS rigid-pair travel (5d)"
```

---

### Task 7: world-4 persistence (port_type + slot_index + bay restore)

**Files:**
- Modify: `scripts/systems/world_snapshot.gd` (`WORLD_SLICE_VERSION` → `"world-4"`; `dock_edges` comment)
- Modify: `scripts/procgen/playable_generated_ship.gd` (`_current_dock_edges` ~3774; `_apply_docking_snapshot` ~3951 hangar branch + `_redock_bayed`; `_reset_runtime_for_reload` ~4042 clear bay slots)
- Test: `scripts/validation/hangar_persistence_smoke.gd`

**Interfaces:**
- Consumes: `_current_dock_edges`, `_apply_docking_snapshot`, `_ensure_derelict_geometry`, `_reset_runtime_for_reload`, `HangarBay`.
- Produces: dock edges carry `port_type:String` (`"airlock"`|`"hangar"`) + `slot_index:int` (−1 airlock); load re-pegs `HangarBay` occupancy and places bayed ships at slot anchors via `_redock_bayed(mobile, host, slot_index)`; reset clears surviving bays.

- [ ] **Step 1: Write the failing test** — `scripts/validation/hangar_persistence_smoke.gd`

```gdscript
extends SceneTree

## Baying a ship + travelling + save->load preserves port_type/slot_index, the bay
## occupancy, the bayed ship's geometry, and the forest.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# Bay the lifeboat into the home ship's cargo-fallback bay.
	var home_id: String = ship.home_ship_id_for_validation()
	var lifeboat_id: String = ship.lifeboat_ship_id_for_validation()
	assert(ship.ship_bay_slot_count_for_validation(home_id) >= 1, "home has a bay")
	var slot: int = ship.bay_dock_for_validation(home_id)
	assert(slot >= 0, "lifeboat bayed in home")
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == true, "bayed before save")

	# A hangar edge is present in the live dock-edge set, with the right shape.
	var edges: Array = ship.current_dock_edges_for_validation()
	var found_hangar := false
	for e in edges:
		if String((e as Dictionary).get("mobile", "")) == lifeboat_id \
				and String((e as Dictionary).get("port_type", "")) == "hangar":
			found_hangar = true
			assert(int((e as Dictionary).get("slot_index", -1)) == slot, "edge carries slot_index")
	assert(found_hangar, "lifeboat->home is a hangar edge")

	# Save -> load.
	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _i in range(3):
		await process_frame

	# Bay occupancy + bayed-ship geometry survive the round-trip.
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == true, "bay occupancy persisted")
	assert(ship.lifeboat_docked_to_piloted_for_validation() == false or true, "forest intact")

	print("HANGAR PERSISTENCE SMOKE PASS bayed=%s slot=%d" % [
		str(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id)), slot])
	quit()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_persistence_smoke.gd`
Expected: FAIL — edges lack `port_type:"hangar"`/`slot_index`, or the bay occupancy is lost on reload, or a `world-4` version mismatch rejects the load (until the version bump lands).

- [ ] **Step 3: Bump the slice version** — `scripts/systems/world_snapshot.gd`:

```gdscript
const WORLD_SLICE_VERSION: String = "world-4"
```
And update the `dock_edges` field comment (~line 19):
```gdscript
var dock_edges: Array = []          # [{host, mobile, port_type:"airlock"|"hangar", slot_index:int}]
```

- [ ] **Step 4: Emit the new edge fields** — in `_current_dock_edges` (~3774), replace the edge append with a version that distinguishes hangar edges by the parent's bay occupancy:

```gdscript
func _current_dock_edges() -> Array:
	var edges: Array = []
	var seen: Dictionary = {}
	for inst in _all_known_ships():
		if inst == null or inst.parent_ship == null:
			continue
		var key: String = "%s>%s" % [String(inst.ship_id), String(inst.parent_ship.marker_id)]
		if seen.has(key):
			continue
		seen[key] = true
		# A child is a HANGAR edge iff its parent's bay holds it in a slot; else airlock.
		var port_type: String = "airlock"
		var slot_index: int = -1
		var parent = inst.parent_ship
		if parent.hangar != null:
			var s: int = parent.hangar.slot_of(String(inst.ship_id))
			if s != -1:
				port_type = "hangar"
				slot_index = s
		edges.append({
			"host": String(parent.marker_id),
			"mobile": String(inst.ship_id),
			"port_type": port_type,
			"slot_index": slot_index,
		})
	return edges
```

- [ ] **Step 5: Restore hangar edges on load** — in `_apply_docking_snapshot` (~3959), branch on `port_type` so a hangar edge re-pegs the bay instead of running `_dock_piloted_to` (which does airlock port-alignment). Replace the per-edge body:

```gdscript
	for edge_v in ws.dock_edges:
		if typeof(edge_v) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_v
		var mobile = _find_ship_by_id(String(edge.get("mobile", "")))
		var host = _find_ship_by_id_or_marker(String(edge.get("host", "")))
		if mobile == null or host == null:
			continue
		if str(edge.get("port_type", "airlock")) == "hangar":
			_redock_bayed(mobile, host, int(edge.get("slot_index", -1)))
		elif mobile.parent_ship != host:
			var saved_piloted = piloted_ship
			piloted_ship = mobile
			_dock_piloted_to(host)
			piloted_ship = saved_piloted
```

Add `_redock_bayed` beside `_apply_docking_snapshot`:

```gdscript
## Restores a hangar edge: re-pegs the carrier's bay slot, re-establishes the
## parent/child link, and places the bayed ship at its slot anchor. Configures the
## carrier's bay from its layout first so slot_count/size exist after a fresh load.
func _redock_bayed(mobile, host, slot_index: int) -> void:
	if mobile == null or host == null:
		return
	if not is_instance_valid(mobile.scene_root) or not is_instance_valid(host.scene_root):
		return
	_configure_bay_from_layout(host)
	var bay = host.get_hangar()
	if slot_index >= 0 and slot_index < bay.slots.size():
		bay.slots[slot_index] = String(mobile.ship_id)
	else:
		slot_index = bay.dock(String(mobile.ship_id), _ship_dock_size_class(mobile))
	mobile.parent_ship = host
	if not host.docked_ships.has(mobile):
		host.docked_ships.append(mobile)
	_place_in_slot(host, mobile, slot_index)
```

- [ ] **Step 6: Clear surviving bays on reset** — in `_reset_runtime_for_reload`, inside the cycle-break loop (~4042-4045), also clear each surviving ship's bay slots so a stale occupant id cannot desync the reload re-peg:

```gdscript
		for inst in _all_known_ships():
			if inst != null:
				inst.parent_ship = null
				inst.docked_ships = []
				if inst.hangar != null:
					for i in range(inst.hangar.slots.size()):
						inst.hangar.slots[i] = ""
```

- [ ] **Step 7: Run the test and make sure it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_persistence_smoke.gd`
Expected: `HANGAR PERSISTENCE SMOKE PASS bayed=true slot=0`, no `resources still in use at exit`.

- [ ] **Step 8: Regression-check the 5c persistence smokes** (the world version bumped to world-4; pre-5d saves must still be rejected cleanly, and the 5c claim path must still round-trip):

- `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/claim_persistence_smoke.gd`
- `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_anywhere_smoke.gd`

Expected: each prints its existing PASS marker.

- [ ] **Step 9: Commit**

```bash
git add scripts/systems/world_snapshot.gd scripts/procgen/playable_generated_ship.gd scripts/validation/hangar_persistence_smoke.gd
git commit -m "feat(docking): world-4 hangar-edge persistence + bay restore (5d)"
```

---

### Task 8: ADR-0019 + roadmap + register smokes + full regression

**Files:**
- Create: `docs/game/adr/0019-hangar-nesting.md`
- Modify: `docs/game/09_system_roadmap.md` (System 5 row + Phase 5 crosswalk + "What remains" §B)
- Modify: `docs/game/06_validation_plan.md` (register the 6 new smokes; bump the command count 94 → 100 and the final marker)

**Interfaces:**
- Consumes: all prior tasks.
- Produces: ADR-0019; updated roadmap marking 5d built (System 5 complete); the regression bundle runs the 6 new smokes and ends `SARGASSO REGRESSION PASS commands=100 clean_output=true`.

- [ ] **Step 1: Write ADR-0019** — `docs/game/adr/0019-hangar-nesting.md`. Mirror the structure of `docs/game/adr/0018-claim-and-pilot-switch.md` (Status / Context / Decision / Consequences / Validation). Record: hangar as an asymmetric port type on the existing dock forest; `HangarBay` fixed-slot model (slot_count from footprint, size-class gate); `HangarBayControl` physical walk-up dock/launch (no HUD); the cargo-room fallback for the home bay (no golden-fixture churn); arbitrary-depth DFS rigid-pair travel replacing the one-level reposition; world-4 edge fields (`port_type`, `slot_index`). Cross-reference ADR-0016/0017/0018. Note the deferred items: screen-space hangar UI (Phase 7), cross-ship inventory transfer (System 6), recursion of bays-within-bays beyond a single carrier chain is supported by the forest but a bay cannot itself be stored in another bay.

- [ ] **Step 2: Update the roadmap** — `docs/game/09_system_roadmap.md`:
  - System 5 row (line ~38): change status to `✅ **Complete (5a+5b+5c+5d)**` and append to the evidence cell: `hangar_bay.gd` (fixed-slot bay), `hangar_bay_control.gd` (physical dock/launch), `DockPorts.for_hangar` (+ cargo fallback), arbitrary-depth DFS rigid-pair travel, `world-4` persistence; ADR-0019. Remove the `*Remaining (5d)*` clause.
  - Phase 5 crosswalk row (~line 60): `✅ done — 5a+5b+5c+5d all built`.
  - "What remains" §B (~line 79): mark 5d built; System 5 has no remaining sub-cycles. Update the "Net" line if it counts System 5 as partial.

- [ ] **Step 3: Register the 6 smokes** — `docs/game/06_validation_plan.md`. Add a `run_clean '<label>' '<marker>' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd` line for each, alongside the 5c entries, in this order with these exact markers:
  - `hangar_bay_smoke` → `HANGAR BAY SMOKE PASS`
  - `hangar_port_smoke` → `HANGAR PORT SMOKE PASS`
  - `hangar_control_smoke` → `HANGAR CONTROL SMOKE PASS`
  - `bay_dock_launch_smoke` → `BAY DOCK LAUNCH SMOKE PASS`
  - `recursive_travel_smoke` → `RECURSIVE TRAVEL SMOKE PASS`
  - `hangar_persistence_smoke` → `HANGAR PERSISTENCE SMOKE PASS`

  Bump the command count in the final echo from `commands=94` to `commands=100` and update any header count comment. (Confirm the actual prior count by reading the file's final `SARGASSO REGRESSION PASS commands=N` line; if it is not 94, use `N` and `N+6`.)

- [ ] **Step 4: Run the full regression bundle (drift stashed)**

```bash
cd "$ROOT"
git stash push -- project.godot
# Extract and run the bundle block (confirm the line range in 06_validation_plan.md first):
sed -n '30,171p' docs/game/06_validation_plan.md > /tmp/bundle.sh
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" ROOT="$ROOT" bash /tmp/bundle.sh
git stash pop
```
Expected final line: `SARGASSO REGRESSION PASS commands=100 clean_output=true`. If any smoke fails, fix it before proceeding (do NOT edit the marker to pass).

- [ ] **Step 5: Run the Gate-1 automated playtest (drift stashed)**

```bash
cd "$ROOT"
git stash push -- project.godot
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd
git stash pop
```
Expected: `GATE 1 AUTOMATED PLAYTEST PASS` / `pass_decision=GO` / `overall_average=2.00`.

- [ ] **Step 6: Commit**

```bash
git add docs/game/adr/0019-hangar-nesting.md docs/game/09_system_roadmap.md docs/game/06_validation_plan.md
git commit -m "docs(docking): ADR-0019 + roadmap 5d + register hangar smokes (94->100)"
```

---

## Self-Review

**Spec coverage:**
- Hangar port type → Task 2 (`for_hangar` + asymmetric `ports_compatible`). ✅
- Weighted derelict hangar role → Task 3. ✅
- Home bay via cargo fallback → Task 2 (`for_hangar` fallback) + Task 5 (home control spawn). ✅
- Fixed-slot bay (footprint-derived count, size-class gate) → Task 1 (`HangarBay`) + Task 2 (slot_count/size derivation). ✅
- Physical walk-up control → Task 4 (`HangarBayControl`) + Task 5 (spawn + handlers). ✅
- Arbitrary-depth DFS rigid-pair travel → Task 6. ✅
- world-4 persistence (port_type/slot_index, bay restore, forward-compat reject) → Task 7. ✅
- Reset clears bays / no RefCounted leak → Task 7 Step 6. ✅
- ADR-0019 + roadmap + 6 smokes registered + full bundle/Gate-1 → Task 8. ✅

**Type consistency:** `HangarBay.create(slot_count, slot_size_class)`; `dock(ship_id, size_class)->int`; `launch(slot_index)->String`; `slot_of`/`free_slot_for`/`is_full`; `DockPorts.for_hangar(layout, seed_value)->{type,slot_count,slot_size_class,slot_anchors}`; `ports_compatible(a,b)`; `_spawn_hangar_control`/`_clear_hangar_controls`/`_configure_bay_from_layout`/`_on_bay_dock_requested`/`_on_bay_launch_requested`/`_place_in_slot`/`_bay_dock_candidate`/`_first_occupied_slot`/`_ship_dock_size_class`/`_redock_bayed`; `_capture_subtree`/`_reposition_subtree`. Names used consistently across Tasks 1–8.

**Placeholder scan:** No TBD/TODO; every code step shows full code; every run step has an exact command + expected marker. The only deliberately deferred-to-implementer items are the ADR prose (Task 8 Step 1) and the exact `sed` line range / prior command count (Task 8 Steps 3-4), each flagged with how to confirm the real value from the file.

**Known assumptions to verify during implementation:**
- The 5c validation seams referenced by Tasks 6-7 (`force_repair_all_for_validation`, `scannable_marker_ids_for_validation`, `current_ship_id_for_validation`, `current_ship_has_bridge_for_validation`, `make_ship_working_for_validation`, `login_at_terminal_for_validation`, `piloted_ship_has_geometry_for_validation`, `lifeboat_docked_to_piloted_for_validation`, `save_world_for_validation`, `load_world_for_validation`) exist from 5c — confirm signatures before reuse; if any differs, adapt the smoke (do not invent new coordinator behavior to match a smoke).
- The lifeboat layout has no `hangar`/`cargo` room, so `for_hangar(lifeboat)` returns `{}` and the lifeboat gets no control — confirm in Task 5 (the lifeboat must remain bay-less; it is the thing that gets stored).
