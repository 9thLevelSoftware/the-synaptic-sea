# Phase 5c — Claim & Pilot-Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the 5b `piloted_ship` pointer so the player can repair a derelict's propulsion, log in at its bridge terminal to take command, switch which ship they pilot, and fly it with the lifeboat docked to it travelling along as a rigid pair.

**Architecture:** A pure `ShipAccessState` (owner_id + access set) is owned by each `ShipInstance` (the multiplayer-forward seam). A `BridgeTerminal` Area3D interactable in each pilotable ship's bridge room emits a login signal; the coordinator (`playable_generated_ship.gd`) gates login on the ship being a *working vessel* (its own `systems_manager.is_operational("propulsion")`), claims it, and re-points `piloted_ship`. Travel is generalized so the piloted ship — whatever it is — is never freed, docks to the target using its own port type, and carries its direct dock children rigidly. Ownership + dock edges persist.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes.

## Global Constraints

- Godot binary: `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`; project root: `C:/Users/dasbl/Documents/The Synaptic Sea`. Run smokes headless: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd`.
- A smoke's single `... PASS ...` marker line IS the contract. `--script` exits 0 even on parse errors — never trust exit code alone; confirm the PASS marker and that no parse/other ERROR/WARNING appears.
- Allowlisted teardown noise (ignore): `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`. Anything else (esp. `resources still in use at exit`) blocks completion.
- The working-tree `project.godot` drift adds an `MCPRuntime` autoload that fails headless. For the FULL bundle / Gate-1 only: `git stash push -- project.godot`, run, then `git stash pop`. Do NOT revert the drift; do NOT stash for single-smoke runs (single smokes don't load project autoloads).
- Class-cache portability: never rely on a bare `ClassName.new()` / `: ClassName` across files headless. Use a `preload("res://…")` const + `.new()` / static factory via `load(...)`. New `class_name` declarations are allowed but must not be the headless access path.
- Typed GDScript for all new code.
- **`PLAYER_LOCAL_ID := "player_local"`** — the single local player id this cycle. The access *model* generalizes to N players; no multiplayer UI/netcode is built.
- **Working vessel** = `ShipInstance.is_working_vessel()` = `systems_manager != null and systems_manager.is_operational("propulsion")`.
- **Home ship is never pilotable** — no bridge terminal is spawned for `home_ship`.
- **One-level rigid pair only** — travel moves the piloted ship's DIRECT dock children. No recursive/arbitrary-depth nesting (that is the deferred 5d cycle).
- Ship summaries gain an `"access"` sub-dict; `WORLD_SLICE_VERSION` bumps `"world-2"` → `"world-3"`.
- Commit style: Conventional Commits, body trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Selective `git add <paths>` only — NEVER `git add -A`. NEVER stage/commit `project.godot`, `.godot/`, `*.uid`, or `addons/`.
- `06_validation_plan.md` command count goes 88 → 94 (six new smokes).

---

### Task 1: `ShipAccessState` pure model

**Files:**
- Create: `scripts/systems/ship_access_state.gd`
- Create: `scripts/validation/ship_access_smoke.gd`

**Interfaces:**
- Produces: `ShipAccessState` with `owner_id: String`, `access_ids: Array[String]`, static `create() -> ShipAccessState`, `claim(player_id: String) -> bool` (returns whether caller now owns it), `grant(player_id: String) -> void`, `revoke(player_id: String) -> void` (refuses to remove owner), `has_access(player_id: String) -> bool`, `get_summary() -> Dictionary`, `apply_summary(summary) -> bool`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/ship_access_smoke.gd`:

```gdscript
extends SceneTree

## Pure-model smoke for ShipAccessState: claim/grant/revoke/has_access semantics,
## owner cannot be revoked, and summary round-trip.

const ShipAccessStateScript := preload("res://scripts/systems/ship_access_state.gd")

func _init() -> void:
	var a = ShipAccessStateScript.create()
	assert(a.owner_id == "", "fresh access has no owner")
	assert(not a.has_access("player_local"), "no access before claim")

	# claim sets owner + grants access; idempotent for same owner; rejects new owner.
	assert(a.claim("player_local") == true, "first claim succeeds")
	assert(a.owner_id == "player_local", "owner recorded")
	assert(a.has_access("player_local"), "owner has access")
	assert(a.claim("player_local") == true, "re-claim by owner is idempotent true")
	assert(a.claim("player_2") == false, "claim by non-owner of owned ship fails")
	assert(a.owner_id == "player_local", "owner unchanged after failed claim")

	# grant/revoke for additional players; owner cannot be revoked.
	a.grant("player_2")
	assert(a.has_access("player_2"), "granted player has access")
	a.revoke("player_2")
	assert(not a.has_access("player_2"), "revoked player loses access")
	a.revoke("player_local")
	assert(a.has_access("player_local"), "owner cannot be revoked")

	# summary round-trip.
	a.grant("player_3")
	var summary: Dictionary = a.get_summary()
	var b = ShipAccessStateScript.create()
	assert(b.apply_summary(summary) == true, "apply_summary accepts valid dict")
	assert(b.owner_id == "player_local", "owner round-trips")
	assert(b.has_access("player_3"), "granted access round-trips")
	assert(b.apply_summary("not a dict") == false, "apply_summary rejects non-dict")

	print("SHIP ACCESS SMOKE PASS owner=%s access=%d" % [b.owner_id, b.access_ids.size()])
	quit()
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_access_smoke.gd`
Expected: parse/load error or assertion failure (no `SHIP ACCESS SMOKE PASS` line) because `ship_access_state.gd` does not exist yet.

- [ ] **Step 3: Implement `ShipAccessState`**

Create `scripts/systems/ship_access_state.gd`:

```gdscript
extends RefCounted
class_name ShipAccessState

## Per-ship ownership + access list. Pure data (no scene tree). The multiplayer
## forward seam: one local player this cycle, but owner_id + access_ids + the
## grant/revoke methods generalize to N players. Persisted as a ship-summary
## sub-dict. class_name is declared for tooling; headless callers preload + create().

var owner_id: String = ""
var access_ids: Array[String] = []

static func create() -> ShipAccessState:
	var script: GDScript = load("res://scripts/systems/ship_access_state.gd")
	return script.new()

## Claims an unowned ship for player_id (sets owner + grants access). Returns
## whether player_id now owns it: true if it just claimed or already owned it,
## false if a different player already owns it.
func claim(player_id: String) -> bool:
	if player_id == "":
		return false
	if owner_id == "":
		owner_id = player_id
		_add_access(player_id)
		return true
	return owner_id == player_id

func grant(player_id: String) -> void:
	if player_id != "":
		_add_access(player_id)

func revoke(player_id: String) -> void:
	if player_id == owner_id:
		return   # the owner always retains access
	access_ids.erase(player_id)

func has_access(player_id: String) -> bool:
	return player_id != "" and access_ids.has(player_id)

func _add_access(player_id: String) -> void:
	if not access_ids.has(player_id):
		access_ids.append(player_id)

func get_summary() -> Dictionary:
	return {"owner_id": owner_id, "access_ids": access_ids.duplicate()}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY:
		return false
	owner_id = str((summary as Dictionary).get("owner_id", ""))
	access_ids = []
	var raw: Variant = (summary as Dictionary).get("access_ids", [])
	if typeof(raw) == TYPE_ARRAY:
		for a in (raw as Array):
			_add_access(String(a))
	return true
```

- [ ] **Step 4: Run the smoke to confirm it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_access_smoke.gd`
Expected: a line `SHIP ACCESS SMOKE PASS owner=player_local access=2` and no unexpected ERROR/WARNING.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ship_access_state.gd scripts/validation/ship_access_smoke.gd
git commit -m "feat(docking): ShipAccessState pure model + smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `ShipInstance` access integration

**Files:**
- Modify: `scripts/systems/ship_instance.gd`
- Modify: `scripts/validation/ship_access_smoke.gd` (append a ShipInstance round-trip + is_working_vessel section)

**Interfaces:**
- Consumes: `ShipAccessState` (Task 1).
- Produces: `ShipInstance.get_access() -> ShipAccessState` (lazy), `ShipInstance.is_working_vessel() -> bool`; `get_summary()` now includes `"access"`; `apply_summary()` restores it.

- [ ] **Step 1: Extend the smoke (failing)**

In `scripts/validation/ship_access_smoke.gd`, add a preload near the top:

```gdscript
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
```

Then, immediately before the final `print(...)` line, insert:

```gdscript
	# ShipInstance owns a ShipAccessState that round-trips through its summary.
	var inst = ShipInstanceScript.create("ship_test", "cell:cell:1", null, null, null)
	assert(inst.get_access().owner_id == "", "fresh ship unowned")
	inst.get_access().claim("player_local")
	var inst_summary: Dictionary = inst.get_summary()
	assert(inst_summary.has("access"), "ship summary carries access")
	var inst2 = ShipInstanceScript.create("ship_test", "cell:cell:1", null, null, null)
	inst2.apply_summary(inst_summary)
	assert(inst2.get_access().owner_id == "player_local", "ship access round-trips")

	# is_working_vessel reads the ship's own propulsion operational status.
	assert(inst.is_working_vessel() == false, "no systems manager -> not working")
	var mgr = ShipSystemsManagerScript.new()
	mgr.configure(mgr.load_definitions(), 0, 0)   # condition 0 = pristine -> all operational
	var working_inst = ShipInstanceScript.create("ship_ok", "cell:cell:2", null, mgr, null)
	assert(working_inst.is_working_vessel() == true, "operational propulsion -> working vessel")
```

Update the final marker line to reflect the extra coverage:

```gdscript
	print("SHIP ACCESS SMOKE PASS owner=%s access=%d ship_owner=%s" % [b.owner_id, b.access_ids.size(), inst2.get_access().owner_id])
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_access_smoke.gd`
Expected: failure (no PASS line) — `get_access`/`is_working_vessel` do not exist and `get_summary` lacks `"access"`.

- [ ] **Step 3: Implement on `ShipInstance`**

In `scripts/systems/ship_instance.gd`, add a preload const next to the existing ones (after line 13):

```gdscript
const ShipAccessStateScript := preload("res://scripts/systems/ship_access_state.gd")
```

Add a field next to the other Phase 5 fields (after `var docking_ports`):

```gdscript
# Sub-project 5c: per-ship ownership/access. Lazily created; persisted under "access".
var access = null                        # ShipAccessState | null
```

Add these methods (e.g. after `get_objective_controller`):

```gdscript
## Returns this ship's ShipAccessState, creating it on first access.
func get_access():
	if access == null:
		access = ShipAccessStateScript.create()
	return access

## A "working vessel" can be piloted: its own propulsion system is operational.
func is_working_vessel() -> bool:
	return systems_manager != null and systems_manager.is_operational("propulsion")
```

In `get_summary()`, before `return result`, add:

```gdscript
	if access != null:
		result["access"] = access.get_summary()
```

In `apply_summary()`, before the final `return true`, add:

```gdscript
	var access_summary: Variant = summary.get("access", null)
	if typeof(access_summary) == TYPE_DICTIONARY and not (access_summary as Dictionary).is_empty():
		get_access().apply_summary(access_summary as Dictionary)
```

- [ ] **Step 4: Run the smoke to confirm it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_access_smoke.gd`
Expected: `SHIP ACCESS SMOKE PASS owner=player_local access=2 ship_owner=player_local`, no unexpected ERROR/WARNING.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ship_instance.gd scripts/validation/ship_access_smoke.gd
git commit -m "feat(docking): ShipInstance owns ShipAccessState + is_working_vessel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `BridgeTerminal` interactable + node smoke

**Files:**
- Create: `scripts/tools/bridge_terminal.gd`
- Create: `scripts/validation/bridge_terminal_smoke.gd`

**Interfaces:**
- Produces: `BridgeTerminal extends Area3D`; `configure(p_ship_id: String, world_position: Vector3, radius := 1.8) -> void`; `try_login(player_body) -> bool` (strict in-range gate; emits and returns true only when in range); signal `login_requested(ship_id: String)`.

- [ ] **Step 1: Write the failing node smoke**

Create `scripts/validation/bridge_terminal_smoke.gd`:

```gdscript
extends SceneTree

## Node-level smoke for BridgeTerminal: strict in-range gate + login_requested signal.
## Mirrors dock_breach_smoke's structure (real Area3D in a real tree).

const BridgeTerminalScript := preload("res://scripts/tools/bridge_terminal.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

var _fired_id: String = ""

func _on_login(ship_id: String) -> void:
	_fired_id = ship_id

func _init() -> void:
	var term = BridgeTerminalScript.new()
	root.add_child(term)
	term.configure("ship_test", Vector3.ZERO, 1.8)
	term.login_requested.connect(_on_login)

	var player = PlayerControllerScript.new()
	root.add_child(player)

	# Out of range -> refused, no signal.
	player.teleport_to(Vector3(10.0, 0.0, 0.0))
	assert(term.try_login(player) == false, "out-of-range login refused")
	assert(_fired_id == "", "no signal out of range")

	# In range -> consumed + signal carries the ship id.
	player.teleport_to(Vector3.ZERO)
	assert(term.try_login(player) == true, "in-range login consumed")
	assert(_fired_id == "ship_test", "login_requested fired with ship id")

	print("BRIDGE TERMINAL SMOKE PASS ship=%s" % _fired_id)
	quit()
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bridge_terminal_smoke.gd`
Expected: failure (no PASS line) — `bridge_terminal.gd` does not exist.

- [ ] **Step 3: Implement `BridgeTerminal`**

Create `scripts/tools/bridge_terminal.gd` (mirrors `DockPortBarrier`'s in-range pattern; no channel — login is a single instant interaction):

```gdscript
extends Area3D
class_name BridgeTerminal

## The bridge command terminal of a pilotable ship. Interacting = "log in". The
## terminal is a sensor + signal only: it does NOT decide whether login is allowed
## (working-vessel / access gating lives in the coordinator). Mirrors the strict
## in-range interaction gate of DockPortBarrier / RepairPoint.

signal login_requested(ship_id: String)

var ship_id: String = ""
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

func configure(p_ship_id: String, world_position: Vector3, radius := 1.8) -> void:
	assert(radius >= 0.0, "BridgeTerminal.configure: radius must be non-negative")
	ship_id = p_ship_id
	interaction_radius = radius
	position = world_position
	name = "BridgeTerminal_%s" % p_ship_id
	set_meta("bridge_terminal", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

## Emits login_requested(ship_id) and returns true iff the player is in direct range.
func try_login(player_body: Node) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("login_requested", ship_id)
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
		collision_shape.name = "BridgeTerminalCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		marker.name = "BridgeTerminalMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.4, radius, radius * 0.4)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.7, 0.95, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_bridge_terminal_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Run the smoke to confirm it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bridge_terminal_smoke.gd`
Expected: `BRIDGE TERMINAL SMOKE PASS ship=ship_test`, no unexpected ERROR/WARNING.

- [ ] **Step 5: Commit**

```bash
git add scripts/tools/bridge_terminal.gd scripts/validation/bridge_terminal_smoke.gd
git commit -m "feat(docking): BridgeTerminal interactable + node smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Guarantee a `bridge` room on derelicts

**Files:**
- Modify: `data/procgen/archetypes/derelict.json`
- Modify: `scripts/validation/derelict_generator_smoke.gd`

**Interfaces:**
- Produces: `bridge` is now a *possible* (weighted, NOT guaranteed) derelict room role. SOME derelicts generate a bridge room; those are claimable. Derelicts without one are just loot/explore areas (Task 5 spawns no terminal when there's no bridge). No new code symbols.

**Design decision (adjudicated):** Claimability requires an actual `bridge` room. Derelicts are variable — some have a bridge (claimable, that's where you take command), some don't (loot only). So `bridge` goes in `role_weights` (probabilistic), NOT `guaranteed_roles` (which would force EVERY derelict to be claimable and contradicts "some derelicts are in pieces"). The existing `derelict_generator_smoke` invariant "derelicts never carry system roles" forbade `bridge` entirely; the user has explicitly decided derelicts MAY now carry a bridge, so removing `bridge` from that smoke's deny-list is an AUTHORIZED invariant change (record it in the task report). The other system roles (airlock/engineering/life_support/cargo/crew_quarters/medical/maintenance) stay denied.

- [ ] **Step 1: Add `bridge` to derelict role weights**

In `data/procgen/archetypes/derelict.json`, change the `role_weights` block from:

```json
    "role_weights": {
        "compartment": 4,
        "corridor": 3,
        "bay": 2,
        "quarters": 2
    },
    "guaranteed_roles": ["dock"],
```

to (add `"bridge": 3` — common but not universal — and leave `guaranteed_roles` as `["dock"]`):

```json
    "role_weights": {
        "compartment": 4,
        "corridor": 3,
        "bridge": 3,
        "bay": 2,
        "quarters": 2
    },
    "guaranteed_roles": ["dock"],
```

- [ ] **Step 2: Allow `bridge` as a derelict role in the generator smoke (authorized invariant change)**

In `scripts/validation/derelict_generator_smoke.gd`, remove `"bridge"` from the `SYSTEM_ROLES` deny-list constant. Change:

```gdscript
const SYSTEM_ROLES: Array[String] = [
	"airlock", "engineering", "life_support", "bridge",
	"cargo", "crew_quarters", "medical", "maintenance",
]
```

to:

```gdscript
# Phase 5c: `bridge` removed from the deny-list — derelicts may now carry a bridge
# room (the claim/pilot helm). All other system roles remain forbidden on a shell.
const SYSTEM_ROLES: Array[String] = [
	"airlock", "engineering", "life_support",
	"cargo", "crew_quarters", "medical", "maintenance",
]
```

- [ ] **Step 2b: Fix the pre-existing stale assertion in `derelict_generator_smoke` (authorized)**

`derelict_generator_smoke` check 5 (lines ~83-84) fails on EVERY seed even on pristine HEAD — verified independently, and it is NOT in the regression bundle (so it never blocked prior runs). It compares `ship.get_child(0).get_child_count()` (structural GEOMETRY modules, ~104 per ship under the `ShipLayoutGenerator` v4 pipeline) against `graph.rooms.size()` (~10) — categorically different quantities since the loader rewrite. This is a stale assertion to CORRECT, not loosen (per-room structural integrity is already covered by the passing loader/playable contract smokes). Replace:

```gdscript
		var structure: Node = ship.get_child(0)
		if structure == null or structure.get_child_count() != graph.rooms.size():
			failures.append("seed=%d structure mismatch" % seed_val)
			continue
```

with:

```gdscript
		var structure: Node = ship.get_child(0)
		# Phase 5c fix: the ShipGenerator pipeline (ShipLayoutGenerator v4) emits structural
		# GEOMETRY modules under the structure root — many per room — so the old assertion
		# `child_count == graph.rooms.size()` compared incomparable quantities (geometry
		# modules vs rooms) and failed every seed post-loader-rewrite. Correct intent: the
		# pipeline produced a non-null ship with a non-empty structure root. Per-room
		# structural integrity is covered by the loader/playable contract smokes.
		if structure == null or structure.get_child_count() <= 0:
			failures.append("seed=%d empty structure" % seed_val)
			continue
```

- [ ] **Step 3: Verify the derelict generator smoke + the broader procgen set**

Run `derelict_generator_smoke` first (the directly affected one), then the broader set. For any whose marker you don't know, grep the smoke's `.gd` for its `print(...)` line.

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_generator_smoke.gd`
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_generator_smoke.gd`  (marker `SHIP GENERATOR PASS`)
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_assigner_smoke.gd`
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_graph_generator_smoke.gd`  (marker `ROOM GRAPH GENERATOR PASS`)
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_walkability_smoke.gd`  (marker `WALKABILITY PASS`)
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_layout_stress_smoke.gd`
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_ship_gameplay_smoke.gd`
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_loader_playable_contract_smoke.gd`
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_playable_ship_smoke.gd`

Expected: each prints its PASS marker, no new ERROR/WARNING. (Known pre-existing, IGNORE: `main_coherent_boot_smoke` fails baseline "expected 4 got 5" — not in the bundle, unrelated.) If any OTHER smoke fails on a room-composition assertion, STOP and report — do not loosen it without adjudication.

- [ ] **Step 4: Commit**

```bash
git add data/procgen/archetypes/derelict.json scripts/validation/derelict_generator_smoke.gd
git commit -m "feat(docking): allow a weighted bridge room on derelicts (claimable helm)

Adds bridge to derelict role_weights and removes bridge from the
derelict_generator_smoke deny-list (authorized invariant change). Also corrects
a pre-existing stale check-5 assertion in the same smoke (geometry-module count
vs room count) that failed every seed since the loader rewrite; unrelated to the
bridge change but required for the smoke to verify and in the same file.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Coordinator — bridge terminals, login handler, `set_piloted_ship`

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/bridge_terminal_login_smoke.gd`

**Interfaces:**
- Consumes: `BridgeTerminal` (Task 3), `ShipInstance.get_access()` / `is_working_vessel()` (Task 2).
- Produces (on the coordinator):
  - `const PLAYER_LOCAL_ID := "player_local"`, `var bridge_terminals: Array = []`.
  - `_command_room_local_center(loader) -> Vector3` — local center of the ship's `bridge` room, fallback to `get_start_transform().origin`, else `Vector3.ZERO`.
  - `_spawn_bridge_terminal(inst) -> void`, `_clear_bridge_terminals() -> void`.
  - `_on_login_requested(ship_id: String) -> void`.
  - `set_piloted_ship(inst) -> Dictionary` — `{success, reason}`; gates on `has_access(PLAYER_LOCAL_ID)`.
  - Validation seams: `login_at_terminal_for_validation(ship_id: String) -> bool`, `make_ship_working_for_validation(ship_id: String) -> void`, `piloted_ship_id_for_validation() -> String`.

- [ ] **Step 1: Write the failing coordinator smoke**

Create `scripts/validation/bridge_terminal_login_smoke.gd`:

```gdscript
extends SceneTree

## Coordinator smoke: logging in at a working vessel's bridge terminal claims it
## and makes it piloted; logging in at a non-working vessel is refused.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)              # _ready() boots the home + lifeboat complex
	# Pump a couple of idle frames so deferred builds settle.
	for _i in range(3):
		await process_frame

	var lifeboat = ship.get_lifeboat_ship_for_validation()
	assert(lifeboat != null, "lifeboat exists at boot")
	assert(lifeboat.get_access().owner_id == "player_local", "lifeboat owned at boot")
	assert(ship.piloted_ship_id_for_validation() == String(lifeboat.ship_id), "lifeboat piloted at boot")

	# A non-working vessel refuses login (propulsion offline -> not a working vessel).
	# Use a fresh derelict-like ShipInstance registered for the test.
	var offline_id: String = ship.register_offline_test_ship_for_validation()
	assert(ship.login_at_terminal_for_validation(offline_id) == false, "offline vessel login refused")
	assert(ship.piloted_ship_id_for_validation() == String(lifeboat.ship_id), "piloted unchanged after refused login")

	# Make it working, then login claims + pilots it.
	ship.make_ship_working_for_validation(offline_id)
	assert(ship.login_at_terminal_for_validation(offline_id) == true, "working vessel login succeeds")
	assert(ship.piloted_ship_id_for_validation() == offline_id, "piloted flips to the claimed ship")

	print("BRIDGE TERMINAL LOGIN SMOKE PASS piloted=%s" % ship.piloted_ship_id_for_validation())
	quit()
```

> The smoke uses three coordinator seams added in Step 3 (`get_lifeboat_ship_for_validation`, `register_offline_test_ship_for_validation`, plus the ones in the Interfaces block). `get_lifeboat_ship_for_validation` may already exist — check before adding; if it does, reuse it.

- [ ] **Step 2: Run it to confirm it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bridge_terminal_login_smoke.gd`
Expected: failure (no PASS line) — the seams/handlers do not exist yet.

- [ ] **Step 3: Implement the coordinator changes**

In `scripts/procgen/playable_generated_ship.gd`:

(a) Add a preload const with the other tool preloads (near `DockPortBarrierScript`):

```gdscript
const BridgeTerminalScript := preload("res://scripts/tools/bridge_terminal.gd")
```

(b) Add the id constant and the terminal registry near the other coordinator vars (next to `var dock_barriers: Array = []`):

```gdscript
const PLAYER_LOCAL_ID := "player_local"
var bridge_terminals: Array = []
```

(c) Add the bridge-room locator + spawn/clear helpers (place them next to `_spawn_dock_barrier` / `_clear_dock_barriers`):

```gdscript
## Local-space center of `loader`'s bridge room (role == "bridge"), or Vector3.INF
## if the ship has NO bridge room. Claimability requires a real bridge: a ship
## without one is not pilotable (just a loot/explore space), so there is deliberately
## NO entry-room fallback here. Positions are ship-local (the terminal is parented
## under the ship's scene_root).
func _command_room_local_center(loader) -> Vector3:
	if loader == null or not loader.has_method("get_layout_copy") or not loader.has_method("get_room_center"):
		return Vector3.INF
	var layout: Dictionary = loader.get_layout_copy()
	var rooms_v: Variant = layout.get("rooms", [])
	if typeof(rooms_v) != TYPE_ARRAY:
		return Vector3.INF
	for room_v in (rooms_v as Array):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		if str((room_v as Dictionary).get("room_role", "")) == "bridge":
			var c: Vector3 = loader.get_room_center(str((room_v as Dictionary).get("id", "")))
			if c != Vector3.INF:
				return c
	return Vector3.INF

## Spawns the bridge terminal for a pilotable ship at its bridge room (ship-local),
## parented under the ship's scene_root so it inherits the ship transform and is
## freed with it. The home ship is never pilotable -> no terminal. A ship with NO
## bridge room gets NO terminal (it cannot be claimed/piloted — loot space only).
func _spawn_bridge_terminal(inst) -> void:
	if inst == null or inst == home_ship or not is_instance_valid(inst.scene_root):
		return
	var local_center: Vector3 = _command_room_local_center(inst.scene_root)
	if local_center == Vector3.INF:
		return   # no bridge room -> not claimable
	var terminal = BridgeTerminalScript.new()
	(inst.scene_root as Node3D).add_child(terminal)
	terminal.configure(String(inst.ship_id), local_center, 1.8)
	terminal.login_requested.connect(_on_login_requested)
	bridge_terminals.append(terminal)

func _clear_bridge_terminals() -> void:
	for t in bridge_terminals:
		if is_instance_valid(t):
			if t.get_parent() != null:
				t.get_parent().remove_child(t)
			t.queue_free()
	bridge_terminals.clear()
```

(d) Add the login handler + the pilot setter (place near `recompute_occupancy`):

```gdscript
## A bridge terminal fired login_requested. Gate on the ship being a working
## vessel, then claim it for the local player and take command. Refused logins
## leave piloted_ship unchanged.
func _on_login_requested(ship_id: String) -> void:
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return
	if not inst.is_working_vessel():
		push_warning("PlayableGeneratedShip: login refused (vessel_not_operational) for %s" % ship_id)
		return
	inst.get_access().claim(PLAYER_LOCAL_ID)
	set_piloted_ship(inst)

## Re-points piloted_ship to `inst` (the player's active ride). Gated on the local
## player having access. Recomputes occupancy. Returns {success, reason}.
func set_piloted_ship(inst) -> Dictionary:
	if inst == null:
		return {"success": false, "reason": "unknown_ship"}
	if not inst.get_access().has_access(PLAYER_LOCAL_ID):
		return {"success": false, "reason": "no_access"}
	piloted_ship = inst
	recompute_occupancy()
	return {"success": true, "reason": "ok"}
```

(e) Wire the terminal interact pass into `_on_player_interact_requested`, immediately AFTER the `dock_barriers` loop (so a closed boarding barrier still takes precedence) and BEFORE the `if away_from_start:` branch:

```gdscript
	for t in bridge_terminals:
		if is_instance_valid(t) and t.try_login(player_body):
			return
```

(f) Spawn the lifeboat's terminal + claim it for the local player. In `_build_lifeboat_at_home()`, immediately after `lifeboat_ship = ShipInstanceScript.create("lifeboat", "", null, ship_systems_manager, lb_root)` (line ~1923), add:

```gdscript
	lifeboat_ship.get_access().claim(PLAYER_LOCAL_ID)
	_spawn_bridge_terminal(lifeboat_ship)
```

(g) Spawn a derelict's terminal when it becomes active. In `_attach_derelict_active`, after the `_spawn_dock_barrier(inst)` call (line ~1208), add:

```gdscript
	_spawn_bridge_terminal(inst)
```

(h) Clear terminals wherever dock barriers are cleared on teardown/reload. Find each call site of `_clear_dock_barriers()` and add `_clear_bridge_terminals()` directly after it. (At minimum: the reload/reset path. Use `grep -n "_clear_dock_barriers" scripts/procgen/playable_generated_ship.gd` to find them all.)

(i) Add the validation seams (place with the other `*_for_validation` seams):

> `get_lifeboat_ship_for_validation()` ALREADY EXISTS (line ~999) — reuse it, do NOT redefine it (a duplicate `func` is a parse error). Add only the seams below.

```gdscript
## 5c seam: drives the real login path for ship_id — teleports the player to that
## ship's bridge terminal and calls try_login (so the real in-range gate admits it).
func login_at_terminal_for_validation(ship_id: String) -> bool:
	for t in bridge_terminals:
		if is_instance_valid(t) and String(t.ship_id) == ship_id:
			if is_instance_valid(player) and player.has_method("teleport_to") and t.is_inside_tree():
				player.teleport_to(t.global_position)
			return t.try_login(player)
	return false

## 5c seam: force-repair every subcomponent of ship_id's OWN systems manager so its
## propulsion reads operational (makes it a working vessel for tests).
func make_ship_working_for_validation(ship_id: String) -> void:
	var inst = _find_ship_by_id(ship_id)
	if inst == null or inst.systems_manager == null:
		return
	for sid in inst.systems_manager.systems.keys():
		var sys = inst.systems_manager.get_system(sid)
		if sys == null:
			continue
		for sub in sys.subcomponents:
			inst.systems_manager.force_repair(sid, sub.subcomponent_id)

## 5c seam: the current piloted ship's id ("" if none).
func piloted_ship_id_for_validation() -> String:
	return String(piloted_ship.ship_id) if piloted_ship != null else ""

## 5c seam: registers an offline derelict-like ship that HAS a bridge room (so it is
## claimable), with its own systems manager and a spawned bridge terminal, parented at
## a distinct world offset, for login tests. Loops candidate seeds until the generated
## layout contains a bridge room (bridge is weighted, not guaranteed). Returns its id,
## or "" if no bridge-bearing layout was found in the search budget.
func register_offline_test_ship_for_validation() -> String:
	if ship_generator == null:
		return ""
	var built = null
	var chosen_seed := -1
	for seed_try in range(0, 200):
		var candidate = ship_generator.generate_from_seed(seed_try, 1, 2)   # size 1, condition 2 (wrecked -> propulsion offline)
		if candidate == null:
			continue
		if candidate.has_method("get_layout_copy") and _layout_has_bridge(candidate.get_layout_copy()):
			built = candidate
			chosen_seed = seed_try
			break
		# Not claimable -> discard this candidate root so it does not leak.
		candidate.queue_free()
	if built == null:
		return ""
	var bp = ShipBlueprintScript.new(1, 2, chosen_seed)
	var mgr = ShipSystemsManagerScript.new()
	mgr.configure(mgr.load_definitions(), bp.condition, bp.seed_value)
	var inst = ShipInstanceScript.create("ship_offline_test", "cell:cell:%d" % chosen_seed, bp, mgr, null)
	inst.scene_root = built
	add_child(built)
	(built as Node3D).position = Vector3(0.0, 0.0, 60.0)
	if inst.built_layout.is_empty() and built.has_method("get_layout_copy"):
		inst.built_layout = built.get_layout_copy()
	visited_ships[String(inst.marker_id)] = inst
	_spawn_bridge_terminal(inst)
	return String(inst.ship_id)

## True iff a layout dict contains a room with room_role == "bridge".
func _layout_has_bridge(layout: Dictionary) -> bool:
	var rooms_v: Variant = layout.get("rooms", [])
	if typeof(rooms_v) != TYPE_ARRAY:
		return false
	for room_v in (rooms_v as Array):
		if typeof(room_v) == TYPE_DICTIONARY and str((room_v as Dictionary).get("room_role", "")) == "bridge":
			return true
	return false

## 5c seam: true iff the current active ship has a bridge room (is claimable).
func current_ship_has_bridge_for_validation() -> bool:
	if current_ship == null or not is_instance_valid(current_ship.scene_root):
		return false
	if not current_ship.scene_root.has_method("get_layout_copy"):
		return false
	return _layout_has_bridge(current_ship.scene_root.get_layout_copy())
```

> `generate_from_seed(seed, size, condition)` is the confirmed API (used by `travel_controller.attempt_travel`). Because `bridge` is weighted (not guaranteed), the seam loops seeds until it finds a bridge-bearing layout so login tests are deterministic. Condition 2 keeps propulsion offline so the ship starts as a non-working vessel.

- [ ] **Step 4: Run the smoke to confirm it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bridge_terminal_login_smoke.gd`
Expected: `BRIDGE TERMINAL LOGIN SMOKE PASS piloted=ship_offline_test`, no unexpected ERROR/WARNING.

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/bridge_terminal_login_smoke.gd
git commit -m "feat(docking): bridge-terminal login claims + pilots a working vessel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Pilot-switch + travel reads the piloted ship's systems

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/pilot_switch_smoke.gd`

**Interfaces:**
- Consumes: `set_piloted_ship` / login seams (Task 5).
- Produces: `_current_systems_ops()` now reads `piloted_ship.systems_manager` (falling back to the coordinator's `ship_systems_manager` when `piloted_ship` is null); `set_piloted_ship` refuses `no_access`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/pilot_switch_smoke.gd`:

```gdscript
extends SceneTree

## Switching the piloted ship by logging in at different bridges, and the no_access guard.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	var lifeboat = ship.get_lifeboat_ship_for_validation()
	var lb_id: String = String(lifeboat.ship_id)
	assert(ship.piloted_ship_id_for_validation() == lb_id, "lifeboat piloted at boot")

	# Claim + pilot a second working vessel.
	var other_id: String = ship.register_offline_test_ship_for_validation()
	ship.make_ship_working_for_validation(other_id)
	assert(ship.login_at_terminal_for_validation(other_id) == true, "claim other ship")
	assert(ship.piloted_ship_id_for_validation() == other_id, "piloted is the other ship")

	# Switch back by logging in at the lifeboat terminal.
	assert(ship.login_at_terminal_for_validation(lb_id) == true, "switch back to lifeboat")
	assert(ship.piloted_ship_id_for_validation() == lb_id, "piloted back to lifeboat")

	# set_piloted_ship to a ship the player has no access to is refused.
	var no_access_id: String = ship.register_offline_test_ship_for_validation()
	var res: Dictionary = ship.set_piloted_ship_by_id_for_validation(no_access_id)
	assert(res.get("success", true) == false and res.get("reason", "") == "no_access", "no_access guard")
	assert(ship.piloted_ship_id_for_validation() == lb_id, "piloted unchanged after no_access")

	print("PILOT SWITCH SMOKE PASS piloted=%s" % ship.piloted_ship_id_for_validation())
	quit()
```

> Add the tiny seam `set_piloted_ship_by_id_for_validation` in Step 3 (the smoke needs to call `set_piloted_ship` without going through login, to hit the `no_access` path).

- [ ] **Step 2: Run it to confirm it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/pilot_switch_smoke.gd`
Expected: failure (no PASS line).

- [ ] **Step 3: Implement**

(a) Generalize `_current_systems_ops()` (line ~1149) to read the piloted ship's own systems manager:

```gdscript
func _current_systems_ops() -> Dictionary:
	# Travel capability comes from the ship the player is PILOTING (5c: that may be a
	# claimed derelict, not just the lifeboat). Fall back to the coordinator's starting
	# manager before a piloted ship exists.
	var mgr = piloted_ship.systems_manager if piloted_ship != null and piloted_ship.systems_manager != null else ship_systems_manager
	return {
		"navigation": mgr != null and mgr.is_operational("navigation"),
		"scanners": mgr != null and mgr.is_operational("scanners"),
		"propulsion": mgr != null and mgr.is_operational("propulsion"),
	}
```

> Note: the lifeboat's `systems_manager` IS the coordinator's `ship_systems_manager` (they are the same object — see `_build_lifeboat_at_home`), so when the lifeboat is piloted this is behavior-identical to before.

(b) Add the test seam (with the other seams):

```gdscript
## 5c seam: calls set_piloted_ship for ship_id without the login/claim path
## (used to exercise the no_access guard directly).
func set_piloted_ship_by_id_for_validation(ship_id: String) -> Dictionary:
	return set_piloted_ship(_find_ship_by_id(ship_id))
```

- [ ] **Step 4: Run the smoke to confirm it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/pilot_switch_smoke.gd`
Expected: `PILOT SWITCH SMOKE PASS piloted=lifeboat`, no unexpected ERROR/WARNING.

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/pilot_switch_smoke.gd
git commit -m "feat(docking): pilot-switch via login + travel reads piloted ship systems

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Rigid-pair travel + never-free-the-piloted-ship

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/rigid_pair_travel_smoke.gd`

**Interfaces:**
- Consumes: pilot-switch (Task 6), existing `DockingManager`, `_dock_piloted_to`, `_attach_derelict_active`, `_capture_player_carry`/`_apply_player_carry`.
- Produces: `_piloted_port_local() -> Dictionary` (the piloted ship's own dock port, lifeboat vs derelict); `_dock_piloted_to` uses it; the dock-incompat precheck in `travel_to` uses it; `travel_to` never frees the piloted ship even when it equals `current_ship`; `_reposition_docked_children(piloted) -> void` carries direct dock children rigidly across a dock move.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/rigid_pair_travel_smoke.gd`:

```gdscript
extends SceneTree

## Piloting a claimed derelict with the lifeboat docked to it: travelling moves the
## whole rigid pair. The lifeboat ends flush against the (moved) piloted ship and the
## piloted ship is never freed.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# Make the lifeboat travel-capable and jump to a CLAIMABLE (bridge-bearing) derelict.
	# bridge is weighted (not guaranteed), so iterate in-range markers until one has a bridge.
	ship.force_repair_all_for_validation()
	var ids: Array = ship.scannable_marker_ids_for_validation()
	assert(ids.size() > 0, "a derelict is in scanner range")
	var landed := false
	for mid in ids:
		var res: Dictionary = ship.travel_to_marker_id(String(mid))
		if not res.get("success", false):
			continue
		for _i in range(2):
			await process_frame
		if ship.current_ship_has_bridge_for_validation():
			landed = true
			break
	assert(landed, "found and travelled to a claimable (bridge-bearing) derelict")

	# Claim the derelict and take command (its propulsion repaired so it is a working vessel).
	var derelict_id: String = ship.current_ship_id_for_validation()
	ship.make_ship_working_for_validation(derelict_id)
	assert(ship.login_at_terminal_for_validation(derelict_id) == true, "claim derelict")
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "piloting the derelict")

	# The lifeboat is still docked to the derelict (the rigid pair).
	assert(ship.lifeboat_docked_to_piloted_for_validation() == true, "lifeboat docked to piloted ship")

	# Travel to another derelict piloting the derelict; the lifeboat must come along flush.
	var ids2: Array = ship.scannable_marker_ids_for_validation()
	var target := ""
	for m in ids2:
		if String(m) != derelict_id and not ship.is_marker_current_for_validation(String(m)):
			target = String(m)
			break
	assert(target != "", "a second distinct target is in range")
	var res2: Dictionary = ship.travel_to_marker_id(target)
	assert(res2.get("success", false), "rigid-pair travel succeeded")
	for _i in range(2):
		await process_frame

	# The piloted derelict still exists (never freed) and the lifeboat is flush to it.
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "still piloting the same derelict")
	assert(ship.lifeboat_flush_to_piloted_for_validation() == true, "lifeboat flush to moved piloted ship")

	print("RIGID PAIR TRAVEL SMOKE PASS piloted=%s" % ship.piloted_ship_id_for_validation())
	quit()
```

> Seams used: `current_ship_id_for_validation`, `is_marker_current_for_validation`, `lifeboat_docked_to_piloted_for_validation`, `lifeboat_flush_to_piloted_for_validation`. Add any that don't already exist in Step 3. `force_repair_all_for_validation`, `scannable_marker_ids_for_validation`, `travel_to_marker_id` already exist.

- [ ] **Step 2: Run it to confirm it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/rigid_pair_travel_smoke.gd`
Expected: failure (no PASS line).

- [ ] **Step 3: Implement**

(a) Add the piloted-port resolver (place near `_dock_piloted_to`):

```gdscript
## The piloted ship's OWN dock port (ship-local). The lifeboat exposes an airlock
## port; a claimed derelict exposes its dock-room port. Used both to dock the piloted
## ship to a target and to pre-check compatibility before committing a travel.
func _piloted_port_local() -> Dictionary:
	if piloted_ship == null:
		return {}
	if piloted_ship == lifeboat_ship:
		return DockPortsScript.for_lifeboat(piloted_ship.built_layout)
	return DockPortsScript.for_derelict(piloted_ship.built_layout, _ship_seed(piloted_ship), _ship_condition_class(piloted_ship))
```

(b) Generalize `_dock_piloted_to` (line ~1940): replace the hardcoded
`var mobile_local: Dictionary = DockPortsScript.for_lifeboat(piloted_ship.built_layout)` with:

```gdscript
	var mobile_local: Dictionary = _piloted_port_local()
```

(c) Generalize the dock-incompat precheck in `travel_to` (line ~1646): replace
`var lb_local: Dictionary = DockPortsScript.for_lifeboat(piloted_ship.built_layout)` with:

```gdscript
		var lb_local: Dictionary = _piloted_port_local()
```

(d) Never free the piloted ship in `travel_to`. The "leaving" branch (line ~1668) frees a derelict's `scene_root`. Guard it so the piloted ship is never freed even when `leaving == piloted_ship` (the player is flying the very derelict they were at):

```gdscript
	else:
		if leaving == piloted_ship:
			# 5c: the player is piloting this ship — it is the ride, not a host to abandon.
			# It will be re-docked to the new target below; do NOT free it.
			pass
		elif leaving.scene_root != null and is_instance_valid(leaving.scene_root):
			if leaving.scene_root.get_parent() == self:
				remove_child(leaving.scene_root)
			leaving.scene_root.queue_free()
			leaving.scene_root = null  # retained instance, scene dropped
```

> Note the original code also runs `leaving.scene_root = null` after the free; keep that ONLY on the free branch (as shown), not when `leaving == piloted_ship`.

(e) Add the rigid-pair child carry (place near `_capture_player_carry`/`_apply_player_carry`):

```gdscript
## Captures each direct dock child's transform RELATIVE to the piloted ship's root,
## BEFORE a dock move repositions that root. Returns [{inst, local_xform}, ...].
func _capture_docked_children() -> Array:
	var out: Array = []
	if piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return out
	var root: Node3D = piloted_ship.scene_root as Node3D
	if not root.is_inside_tree():
		return out
	var inv: Transform3D = root.global_transform.affine_inverse()
	for child in piloted_ship.docked_ships:
		if child == null or not is_instance_valid(child.scene_root):
			continue
		var cr: Node3D = child.scene_root as Node3D
		if not cr.is_inside_tree():
			continue
		out.append({"inst": child, "local_xform": inv * cr.global_transform})
	return out

## Re-applies captured child relatives AFTER the piloted ship root moved, so each
## direct dock child rides rigidly with it (the "rigid pair"). One level deep.
func _reposition_docked_children(captured: Array) -> void:
	if piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return
	var root: Node3D = piloted_ship.scene_root as Node3D
	if not root.is_inside_tree():
		return
	for entry_v in captured:
		var entry: Dictionary = entry_v
		var child = entry.get("inst", null)
		if child == null or not is_instance_valid(child.scene_root):
			continue
		(child.scene_root as Node3D).global_transform = root.global_transform * (entry["local_xform"] as Transform3D)
```

(f) Hook the child carry into `_attach_derelict_active`. Around the existing piloted dock move (the `if piloted_ship != null:` block at line ~1197), capture children BEFORE the undock/dock and reposition them AFTER `_apply_player_carry(carry)`:

```gdscript
	if piloted_ship != null:
		var carry := _capture_player_carry()
		var child_carry := _capture_docked_children()
		DockingManagerScript.undock(piloted_ship)
		var dock_res: Dictionary = _dock_piloted_to(inst)
		if not bool(dock_res.get("success", false)):
			push_error("PlayableGeneratedShip: travel dock failed (%s) — re-docking piloted ship to home" % str(dock_res.get("reason", "?")))
			_dock_piloted_to(home_ship)
		_apply_player_carry(carry)
		_reposition_docked_children(child_carry)
```

> Subtlety: when the player pilots a claimed derelict D and travels, `_attach_derelict_active` is called with `inst = the NEW target T`. `_dock_piloted_to(inst)` docks D (piloted) to T using D's own port (via `_piloted_port_local`). The lifeboat, a direct dock child of D, is carried by `_reposition_docked_children`. When the player pilots the lifeboat (the 5b case), `piloted_ship.docked_ships` is empty, so `_capture_docked_children` returns `[]` and behavior is unchanged.

(g) Apply the same never-free guard + child carry to `travel_home()` (line ~1705 onward): it also frees `current_ship` and undocks the piloted ship. Capture children before the undock, reposition after the home re-dock, and guard the free so the piloted ship is never freed. Concretely, mirror the `_attach_derelict_active` pattern: add `var child_carry := _capture_docked_children()` before `DockingManagerScript.undock(piloted_ship)`, guard the `leaving.scene_root` free with `if leaving == piloted_ship: pass`, and after the piloted ship is re-docked to home call `_reposition_docked_children(child_carry)`. (Read the full `travel_home` body first; preserve its existing player-carry and home-restore logic.)

(h) Add the validation seams (with the other seams):

```gdscript
## 5c seams for rigid-pair travel.
func current_ship_id_for_validation() -> String:
	return String(current_ship.ship_id) if current_ship != null else ""

func is_marker_current_for_validation(marker_id: String) -> bool:
	return current_ship != null and String(current_ship.marker_id) == marker_id

func lifeboat_docked_to_piloted_for_validation() -> bool:
	return lifeboat_ship != null and piloted_ship != null and lifeboat_ship.parent_ship == piloted_ship

## True iff the lifeboat's lifted airlock port is within 0.5u of the piloted ship's
## lifted dock port — i.e. the lifeboat is flush against the (moved) piloted ship.
func lifeboat_flush_to_piloted_for_validation() -> bool:
	if lifeboat_ship == null or piloted_ship == null:
		return false
	if not is_instance_valid(lifeboat_ship.scene_root) or not is_instance_valid(piloted_ship.scene_root):
		return false
	if not (lifeboat_ship.scene_root as Node3D).is_inside_tree() or not (piloted_ship.scene_root as Node3D).is_inside_tree():
		return false
	var piloted_local: Dictionary = _piloted_port_local()
	var piloted_world: Dictionary = DockingManagerScript.host_port_to_world(piloted_ship, piloted_local)
	if piloted_world.is_empty():
		return false
	var lb_local: Dictionary = DockPortsScript.for_lifeboat(lifeboat_ship.built_layout)
	var lb_world: Vector3 = (lifeboat_ship.scene_root as Node3D).global_transform * (lb_local["position"] as Vector3)
	return lb_world.distance_to(piloted_world["position"] as Vector3) <= 0.5
```

- [ ] **Step 4: Run the smoke to confirm it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/rigid_pair_travel_smoke.gd`
Expected: `RIGID PAIR TRAVEL SMOKE PASS piloted=ship_<marker>`, no unexpected ERROR/WARNING.

- [ ] **Step 5: Run the 5b travel/occupancy smokes to confirm no regression**

The lifeboat-piloted path must still behave as in 5b. Run:

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/physical_travel_smoke.gd`
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/boarding_flip_smoke.gd`
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/boot_dock_aligned_smoke.gd`
Expected: each prints its existing PASS marker, no new ERROR/WARNING.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/rigid_pair_travel_smoke.gd
git commit -m "feat(docking): rigid-pair travel + never free the piloted ship

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Persistence — access + general dock-edge set + version bump

**Files:**
- Modify: `scripts/systems/world_snapshot.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/claim_persistence_smoke.gd`

**Interfaces:**
- Consumes: ship summaries now carry `"access"` (Task 2); `_apply_docking_snapshot` / `_dock_piloted_to` (existing); `_piloted_port_local` (Task 7).
- Produces: `WORLD_SLICE_VERSION = "world-3"`; `_current_dock_edges()` emits an edge for EVERY ship with a `parent_ship` (not just the piloted one), so the lifeboat→claimed-derelict edge persists.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/claim_persistence_smoke.gd`:

```gdscript
extends SceneTree

## Claiming a derelict and piloting it (lifeboat docked to it) round-trips through
## save -> load: owner, piloted pointer, and the lifeboat->derelict dock edge survive.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	ship.force_repair_all_for_validation()
	var ids: Array = ship.scannable_marker_ids_for_validation()
	assert(ids.size() > 0, "a derelict is in range")
	# Land on a CLAIMABLE (bridge-bearing) derelict (bridge is weighted, not guaranteed).
	var landed := false
	for mid in ids:
		if not ship.travel_to_marker_id(String(mid)).get("success", false):
			continue
		for _i in range(2):
			await process_frame
		if ship.current_ship_has_bridge_for_validation():
			landed = true
			break
	assert(landed, "travelled to a claimable derelict")

	var derelict_id: String = ship.current_ship_id_for_validation()
	ship.make_ship_working_for_validation(derelict_id)
	assert(ship.login_at_terminal_for_validation(derelict_id) == true, "claimed derelict")
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "piloting derelict")

	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _i in range(3):
		await process_frame

	# Owner, piloted pointer, and the lifeboat->derelict edge survive the round-trip.
	assert(ship.ship_owner_for_validation(derelict_id) == "player_local", "derelict ownership persisted")
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "piloted pointer persisted")
	assert(ship.lifeboat_docked_to_piloted_for_validation() == true, "lifeboat->derelict edge persisted")

	print("CLAIM PERSISTENCE SMOKE PASS piloted=%s owner=%s" % [ship.piloted_ship_id_for_validation(), ship.ship_owner_for_validation(derelict_id)])
	quit()
```

> New seam: `ship_owner_for_validation(ship_id)`. Add in Step 3.

- [ ] **Step 2: Run it to confirm it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/claim_persistence_smoke.gd`
Expected: failure (no PASS line) — version not bumped / edges incomplete / seam missing.

- [ ] **Step 3: Implement**

(a) Bump the version in `scripts/systems/world_snapshot.gd`:

```gdscript
const WORLD_SLICE_VERSION: String = "world-3"
```

(b) Generalize `_current_dock_edges()` (line ~3589) to emit every dock edge across all known ships, not just the piloted ship's host edge:

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
		edges.append({
			"host": String(inst.parent_ship.marker_id),
			"mobile": String(inst.ship_id),
			"port_type": "airlock",
		})
	return edges

## Every ShipInstance the coordinator currently tracks (home, lifeboat, current,
## and all visited), de-duplicated.
func _all_known_ships() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for inst in [home_ship, lifeboat_ship, current_ship]:
		if inst != null and not seen.has(inst):
			seen[inst] = true
			out.append(inst)
	for mid in visited_ships:
		var inst = visited_ships[mid]
		if inst != null and not seen.has(inst):
			seen[inst] = true
			out.append(inst)
	return out
```

> Why this matters: when the player pilots a claimed derelict D with the lifeboat L docked to it, the live edge is L→D. The old `_current_dock_edges` only looked at `piloted_ship.parent_ship` (D's host), so it would NOT record L→D and the rigid pair would not survive a reload. `_apply_docking_snapshot` already re-establishes each edge idempotently via `_dock_piloted_to` (which now uses `_piloted_port_local`, so it docks each mobile with its own port type).

(c) Add the validation seam (with the other seams):

```gdscript
## 5c seam: the owner_id recorded on ship_id ("" if unknown/unowned).
func ship_owner_for_validation(ship_id: String) -> String:
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return ""
	return inst.get_access().owner_id
```

- [ ] **Step 4: Run the smoke to confirm it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/claim_persistence_smoke.gd`
Expected: `CLAIM PERSISTENCE SMOKE PASS piloted=ship_<marker> owner=player_local`, no unexpected ERROR/WARNING.

- [ ] **Step 5: Run the 5b persistence smoke to confirm no regression**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/docking_persistence_smoke.gd`
Expected: its existing PASS marker, no new ERROR/WARNING. (If it pins the old `WORLD_SLICE_VERSION` string, that is an authorized contract update — change the expected string to `world-3` and note it in the report.)

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/world_snapshot.gd scripts/procgen/playable_generated_ship.gd scripts/validation/claim_persistence_smoke.gd
git commit -m "feat(docking): persist ownership + general dock-edge set (world-3)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Docs — ADR-0018, roadmap, validation registry

**Files:**
- Create: `docs/game/adr/0018-claim-and-pilot-switch.md`
- Modify: `docs/game/09_system_roadmap.md`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/superpowers/specs/2026-06-22-phase5c-claim-and-pilot-switch-design.md` (testing count 5 → 6)

**Interfaces:** none (documentation only).

- [ ] **Step 1: Write ADR-0018**

Create `docs/game/adr/0018-claim-and-pilot-switch.md` documenting: the login-based ownership model (`ShipAccessState` owner_id + access set; `PLAYER_LOCAL_ID` single-player slice with the N-player seam), the `BridgeTerminal` working-vessel gate, `set_piloted_ship`, one-level rigid-pair travel (`_capture_docked_children`/`_reposition_docked_children`) and the never-free-piloted-ship rule, the general dock-edge persistence (`world-3`), and the **claimability rule**: `bridge` is a weighted (not guaranteed) derelict role — derelicts with a bridge are claimable at that helm, derelicts without one are loot/explore spaces only (the adjudicated design + the authorized `derelict_generator_smoke` deny-list change). Cross-reference ADR-0016 and ADR-0017. State the deferrals explicitly: full hangar nesting → 5d; multiplayer netcode/UI → post-Phase-7.

- [ ] **Step 2: Update the roadmap**

In `docs/game/09_system_roadmap.md`, update the System 5 row + the Phase 5 crosswalk row + the "What remains — B" section: 5c (claim + pilot-switch + rigid-pair travel) is now built; the only remaining System 5 work is **5d — full hangar nesting** (recursive/arbitrary-depth ship-in-ship). Note multiplayer access UI remains a post-Phase-7 seam.

- [ ] **Step 3: Register the six new smokes**

In `docs/game/06_validation_plan.md`, add `run_clean` lines (matching the existing format) for each new smoke with its exact marker, and bump the final count:
- `ship_access_smoke` → `SHIP ACCESS SMOKE PASS`
- `bridge_terminal_smoke` → `BRIDGE TERMINAL SMOKE PASS`
- `bridge_terminal_login_smoke` → `BRIDGE TERMINAL LOGIN SMOKE PASS`
- `pilot_switch_smoke` → `PILOT SWITCH SMOKE PASS`
- `rigid_pair_travel_smoke` → `RIGID PAIR TRAVEL SMOKE PASS`
- `claim_persistence_smoke` → `CLAIM PERSISTENCE SMOKE PASS`

Change the closing line from `commands=88` to `commands=94` (`echo 'SARGASSO REGRESSION PASS commands=94 clean_output=true'`).

- [ ] **Step 4: Reconcile the spec testing count**

In `docs/superpowers/specs/2026-06-22-phase5c-claim-and-pilot-switch-design.md`, update the Testing section: it now lists **six** smokes (add `bridge_terminal_smoke`, the node-level range/signal test) and the count is 88 → 94.

- [ ] **Step 5: Run the FULL regression bundle + Gate-1 (drift stashed)**

```bash
git stash push -- project.godot
# Extract and run the bundle from 06_validation_plan.md with GODOT/ROOT set to the Windows values.
# Expected tail: SARGASSO REGRESSION PASS commands=94 clean_output=true
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd
# Expected: GATE 1 AUTOMATED PLAYTEST PASS, pass_decision=GO, overall_average=2.00
git stash pop
```

Expected: bundle ends `SARGASSO REGRESSION PASS commands=94 clean_output=true`; Gate-1 prints GO. If any smoke fails, fix the root cause before continuing — do not loosen an assertion to make it pass.

- [ ] **Step 6: Commit**

```bash
git add docs/game/adr/0018-claim-and-pilot-switch.md docs/game/09_system_roadmap.md docs/game/06_validation_plan.md docs/superpowers/specs/2026-06-22-phase5c-claim-and-pilot-switch-design.md
git commit -m "docs(docking): ADR-0018 + roadmap 5c + register 5c smokes (88->94)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Ownership/access model (`ShipAccessState`) → Tasks 1–2. ✅
- Working-vessel gate + bridge terminal → Tasks 3, 5. ✅
- Pilot-switch (login, no menu) → Tasks 5–6. ✅
- Home ship never pilotable → Task 5 (`_spawn_bridge_terminal` early-returns on `home_ship`). ✅
- Rigid-pair (one-level) travel → Task 7. ✅
- Persistence (access + dock edges + `world-3`) → Task 8. ✅
- Derelict bridge gap (integration risk surfaced during planning) → Task 4. ✅
- Six smokes + bundle 88→94 → Task 9. ✅
- Scope boundaries (5d nesting, post-Phase-7 multiplayer) → ADR/roadmap in Task 9. ✅

**Type/name consistency:** `is_working_vessel`, `get_access`, `claim/grant/revoke/has_access`, `set_piloted_ship`, `_piloted_port_local`, `_capture_docked_children`/`_reposition_docked_children`, `_command_room_local_center`, `PLAYER_LOCAL_ID`, `WORLD_SLICE_VERSION="world-3"` are used identically across tasks.

**Known soft spots flagged for the implementer (not placeholders — explicit adaptation points):** `register_offline_test_ship_for_validation` depends on the exact `ship_generator` instantiation API; the implementer must adapt it to the real call used by `travel_to`. `get_lifeboat_ship_for_validation` may already exist — reuse if so. `_attach_derelict_active`/`travel_home` edits must be made against the real current bodies (read them first); the plan shows the precise insertions but the surrounding lines must be preserved.
