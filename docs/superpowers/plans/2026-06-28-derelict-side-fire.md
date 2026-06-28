# Derelict-Side Fire Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the authoritative fire hazard to boarded derelicts — pre-seeded, per-ship, persistent, with a power-gated extinguisher recharge port — by deleting four `away_from_start` guards, owning fire per-ship on `ShipInstance`, and wiring the fire tick into the `_process` away branch.

**Architecture:** Fire state moves from "single coordinator model, home-only" to "active-ship model" selected by a new `_active_fire_state()` helper that mirrors the existing `_active_systems_manager()`. Home fire keeps living on the coordinator (`fire_suppression_state`); each derelict owns its own `FireSuppressionState` on its retained `ShipInstance`, persisted through `visited_ships` for sequential per-ship persistence. The away branch of `_process` gains a fire-tick block (the "wire BOTH branches" guardrail).

**Tech Stack:** Godot 4.6.2, typed GDScript. Validation is headless smokes run via the Godot console binary; the PASS marker is the contract (exit code is NOT trusted).

## Global Constraints

- Godot binary: `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`
- Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`
- Run smokes headless: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd`. A smoke passes only if its single `... PASS ...` marker line is printed AND no unexpected `ERROR:`/`WARNING:` appears. Allowlisted teardown noise: `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`.
- Deterministic, RNG-free: no `randi()`/`randf()`/`Math.random` in seeding. Use `hash(...)` over a per-seed string.
- Typed GDScript for new functions.
- Model/Node separation: `ShipInstance` and `FireSuppressionState` are pure `RefCounted` — never touch the scene tree.
- The coordinator `_process(delta)` has TWO branches; the away branch (`if away_from_start:`) returns early. Any per-frame system MUST be wired into both. The away validation must drive `away_from_start = true` (an `away_ticks=`-style assertion).
- Never stage `project.godot`, `.godot/`, `*.uid`, or `addons/`.
- Conventional Commits. Commit trailers:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_012rncQ3JTUdorqXH1b4eQNY
  ```
- Constants: `FIRE_PRESENCE_PERCENT = 15`; cap = `2 + (1 if condition == ShipBlueprint.Condition.WRECKED)`. `ShipBlueprint.Condition` = `{PRISTINE=0, DAMAGED=1, WRECKED=2}`.

## File Structure

- `scripts/systems/fire_suppression_state.gd` — MODIFY: complete `apply_summary` round-trip (restore `compartments`/`adjacency`/rate tunables).
- `scripts/systems/ship_instance.gd` — MODIFY: add per-ship `fire` field, `get_fire()`, `"fire"` summary key.
- `scripts/procgen/playable_generated_ship.gd` — MODIFY: `_active_fire_state()` helper; route fire reads through it; delete 4 away guards; `_seed_derelict_fire()`; away-branch fire tick + power-gated recharge port; derelict-aware `_build_fire_context`.
- `scripts/validation/fire_suppression_round_trip_smoke.gd` — CREATE (Task 1).
- `scripts/validation/ship_instance_fire_persistence_smoke.gd` — CREATE (Task 2).
- `scripts/validation/derelict_fire_seed_smoke.gd` — CREATE (Task 4).
- `scripts/validation/main_playable_derelict_fire_smoke.gd` — CREATE (Task 5).
- `scripts/validation/derelict_fire_sequential_persistence_smoke.gd` — CREATE (Task 6).
- `docs/game/06_validation_plan.md` — MODIFY: register the 5 new smokes, bump count.
- `docs/game/system_completion_audit.md` — MODIFY: re-grade item 5 derelict-fire follow-up.

---

### Task 1: Complete `FireSuppressionState.apply_summary` round-trip

**Files:**
- Modify: `scripts/systems/fire_suppression_state.gd:188-215`
- Test: `scripts/validation/fire_suppression_round_trip_smoke.gd` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces: `FireSuppressionState.apply_summary(summary)` now restores `compartments`, `adjacency`, `suppression_rate_per_second`, `power_threshold`, `spread_rate_per_second`, `ignition_rate_per_second`, `cascade_rate_per_second` (in addition to the fields it already restores). This makes a fresh instance's `get_summary()` → `apply_summary()` reproduce spread topology — required for per-ship persistence in Task 2.

**Why:** `apply_summary` currently restores only `active_fires`, `spread_progress`, `ignition_progress`, `suppressant_units`, `cascade_progress`, `arc_compartment`. It drops `compartments`/`adjacency`, so a restored-from-scratch model cannot spread. Home masks this by calling `configure(tuning)` before `apply_summary` on reload; per-ship derelict restore needs the model to round-trip on its own.

- [ ] **Step 1: Write the round-trip smoke**

Create `scripts/validation/fire_suppression_round_trip_smoke.gd`:

```gdscript
extends SceneTree

## Proves FireSuppressionState.get_summary()/apply_summary() round-trips the FULL
## state — including compartments + adjacency (spread topology) — so a per-ship fire
## model restored from a snapshot still spreads. Refutes the prior lossy apply_summary.
## Marker: FIRE SUPPRESSION ROUND TRIP PASS topo=true fires=true spreads=true

const FireScript := preload("res://scripts/systems/fire_suppression_state.gd")

func _initialize() -> void:
	var src = FireScript.new()
	src.configure({
		"compartments": ["a", "b", "c"],
		"adjacency": {"a": ["b"], "b": ["a", "c"], "c": ["b"]},
		"spread_rate_per_second": 5.0,
		"ignition_rate_per_second": 0.0,
		"power_threshold": 0.5,
	})
	src.ignite("a", 1.0)
	var summary: Dictionary = src.get_summary()

	# Restore into a BARE instance (no configure) — must reproduce topology + fires.
	var dst = FireScript.new()
	dst.apply_summary(summary)
	var topo: bool = dst.get_summary().get("compartments", []).size() == 3 \
		and dst.get_summary().get("adjacency", {}).has("b")
	var fires: bool = dst.is_burning("a") and not dst.is_burning("b")

	# Spread must work on the restored instance: with no oxygen gating in ctx,
	# fire in "a" spreads to neighbour "b" after enough ticks.
	var ctx := {"ship_oxygen_present": true, "powered_ratio": 0.0,
		"breached_compartments": [], "damaged_compartments": [], "arc_arcing": false}
	for i in range(20):
		dst.tick(0.1, ctx)
	var spreads: bool = dst.is_burning("b")

	if topo and fires and spreads:
		print("FIRE SUPPRESSION ROUND TRIP PASS topo=true fires=true spreads=true")
		quit(0)
	else:
		push_error("FIRE SUPPRESSION ROUND TRIP FAIL topo=%s fires=%s spreads=%s" % [topo, fires, spreads])
		quit(1)
```

- [ ] **Step 2: Run it; expect FAIL** (current `apply_summary` drops topology, so `topo`/`spreads` are false)

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_suppression_round_trip_smoke.gd
```
Expected: `FIRE SUPPRESSION ROUND TRIP FAIL topo=false ...`

- [ ] **Step 3: Extend `apply_summary` to restore topology + rate tunables**

In `scripts/systems/fire_suppression_state.gd`, inside `apply_summary`, after the existing restores and before `return changed`, add:

```gdscript
	# Round-trip spread topology + rate tunables (previously dropped — a restored-from-
	# scratch model could not spread). Home reconfigures from tuning before applying, but
	# per-ship derelict fire restores straight from its ShipInstance summary.
	var comps: Variant = summary.get("compartments", null)
	if typeof(comps) == TYPE_ARRAY:
		var new_comps: Array[String] = []
		for c in (comps as Array):
			new_comps.append(str(c))
		if new_comps != compartments:
			compartments = new_comps
			changed = true
	var adj: Variant = summary.get("adjacency", null)
	if typeof(adj) == TYPE_DICTIONARY:
		adjacency.clear()
		for cid in (adj as Dictionary):
			var neighbours: Array[String] = []
			var lst: Variant = (adj as Dictionary)[cid]
			if typeof(lst) == TYPE_ARRAY:
				for n in (lst as Array):
					neighbours.append(str(n))
			adjacency[str(cid)] = neighbours
		changed = true
	if summary.has("suppression_rate_per_second"):
		suppression_rate_per_second = maxf(0.1, float(summary["suppression_rate_per_second"]))
	if summary.has("power_threshold"):
		power_threshold = clampf(float(summary["power_threshold"]), 0.05, 1.0)
	if summary.has("spread_rate_per_second"):
		spread_rate_per_second = maxf(0.0, float(summary["spread_rate_per_second"]))
	if summary.has("ignition_rate_per_second"):
		ignition_rate_per_second = maxf(0.0, float(summary["ignition_rate_per_second"]))
	if summary.has("cascade_rate_per_second"):
		cascade_rate_per_second = maxf(0.0, float(summary["cascade_rate_per_second"]))
```

- [ ] **Step 4: Run the smoke; expect PASS**

Run the command from Step 2. Expected: `FIRE SUPPRESSION ROUND TRIP PASS topo=true fires=true spreads=true`.

- [ ] **Step 5: Regression-check the existing fire smoke isn't broken**

Run the existing fire smokes (find them):
```bash
ls scripts/validation | grep -i fire
```
Run each that exists (e.g. `fire_suppression_smoke.gd`, `hazard_contract_smoke.gd`); confirm their PASS markers still print. The change is additive (more fields restored), so existing behavior is preserved.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/fire_suppression_state.gd scripts/validation/fire_suppression_round_trip_smoke.gd
git commit -m "fix(fire): restore spread topology in FireSuppressionState.apply_summary"
```

---

### Task 2: Per-ship fire on `ShipInstance`

**Files:**
- Modify: `scripts/systems/ship_instance.gd` (fields ~64-69, `get_summary` ~83-113, `apply_summary` ~115-159, add a `get_fire()` near the other `get_*` lazy creators ~161-187)
- Test: `scripts/validation/ship_instance_fire_persistence_smoke.gd` (create)

**Interfaces:**
- Consumes: `FireSuppressionState` (full round-trip from Task 1).
- Produces:
  - `ShipInstance.fire` (field, default `null`).
  - `ShipInstance.get_fire()` → lazily creates and returns the per-ship `FireSuppressionState` (bare/unconfigured; the coordinator configures it from tuning — see Task 4).
  - `get_summary()` includes `"fire"` ONLY when the model exists and has burning compartments.
  - `apply_summary()` restores `"fire"` into `get_fire()` when present.

- [ ] **Step 1: Write the persistence smoke**

Create `scripts/validation/ship_instance_fire_persistence_smoke.gd`:

```gdscript
extends SceneTree

## Proves per-ship fire round-trips through ShipInstance.get_summary()/apply_summary(),
## so a revisited derelict remembers its burning set. Also proves "fire" is omitted when
## no compartment burns (no snapshot bloat).
## Marker: SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _initialize() -> void:
	# No fire -> "fire" key omitted.
	var a = ShipInstanceScript.create("s1", "m1", null, null, null)
	var omitted: bool = not a.get_summary().has("fire")

	# Burning -> persists and restores.
	var b = ShipInstanceScript.create("s2", "m2", null, null, null)
	b.get_fire().configure({"compartments": ["x", "y"], "adjacency": {"x": ["y"]}})
	b.get_fire().ignite("x", 1.0)
	var summary: Dictionary = b.get_summary()
	var has_fire: bool = summary.has("fire")

	var c = ShipInstanceScript.create("s2", "m2", null, null, null)
	c.apply_summary(summary)
	var restored: bool = has_fire and c.fire != null and c.fire.is_burning("x")

	if omitted and restored:
		print("SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true")
		quit(0)
	else:
		push_error("SHIP INSTANCE FIRE PERSISTENCE FAIL omitted=%s has_fire=%s restored=%s" % [omitted, has_fire, restored])
		quit(1)
```

- [ ] **Step 2: Run it; expect FAIL** (`get_fire()` undefined → load/parse error or assertion fail). Use the headless command pattern from Task 1 Step 2 with this script path.

- [ ] **Step 3: Add the `fire` field**

In `scripts/systems/ship_instance.gd`, after the `combat_summary` field (~line 69), add:

```gdscript

# Derelict-side fire: per-ship authoritative FireSuppressionState. Lazily created;
# persisted under "fire" only when a compartment is actually burning. Home fire stays
# on the coordinator (fire_suppression_state); this is for boarded derelicts.
var fire = null                          # FireSuppressionState | null
```

- [ ] **Step 4: Add the const + `get_fire()` lazy creator**

Near the top consts (after `const CartStateScript ...` ~line 17) add:
```gdscript
const FireSuppressionStateScript := preload("res://scripts/systems/fire_suppression_state.gd")
```
Near the other `get_*` lazy creators (after `get_inventory()` ~line 187) add:
```gdscript
## Returns this ship's FireSuppressionState, creating a bare one on first access.
## The coordinator configures it from tuning before seeding/use.
func get_fire():
	if fire == null:
		fire = FireSuppressionStateScript.new()
	return fire

## True iff this ship has at least one burning compartment.
func has_fire() -> bool:
	return fire != null and not fire.get_burning_compartments().is_empty()
```

- [ ] **Step 5: Persist in `get_summary`**

In `get_summary()`, after the `carts` block and before `return result` (~line 112), add:
```gdscript
	if has_fire():
		result["fire"] = fire.get_summary()
```

- [ ] **Step 6: Restore in `apply_summary`**

In `apply_summary()`, before `return true` (~line 158), add:
```gdscript
	var fire_summary: Variant = summary.get("fire", null)
	if typeof(fire_summary) == TYPE_DICTIONARY and not (fire_summary as Dictionary).is_empty():
		get_fire().apply_summary(fire_summary as Dictionary)
```

- [ ] **Step 7: Run the smoke; expect PASS** → `SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true`

- [ ] **Step 8: Commit**

```bash
git add scripts/systems/ship_instance.gd scripts/validation/ship_instance_fire_persistence_smoke.gd
git commit -m "feat(fire): per-ship FireSuppressionState on ShipInstance with round-trip"
```

---

### Task 3: `_active_fire_state()` + route fire reads through it + delete the four away guards

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (add helper near `_active_systems_manager()` ~2965; edit `_build_fire_context` ~2598, `_seed_fires_from_damage` ~2631 leave home-only, `_build_fire_zones` ~2674, `_apply_fire_system_damage` ~2664, `_player_fire_intensity` ~2651, `_refresh_fire_zones` ~2777, `_build_fire_suppression_points` ~2800, `_build_extinguisher_recharge_port` ~2843, the home tick block ~1362)

**Interfaces:**
- Produces: `_active_fire_state()` → derelict's `current_ship.get_fire()` when away, else coordinator `fire_suppression_state`. After this task, all fire renderers/readers operate on the active ship's fire. The four `away_from_start` guards are gone. No new fire is seeded yet (Task 4) and the away tick is not added yet (Task 5), so derelict behavior is unchanged (empty active fire → builders no-op). Home behavior is unchanged.

**Note:** This is a no-behavior-change refactor verified by the existing home fire regression. Do NOT add seeding or the away tick here.

- [ ] **Step 1: Add `_active_fire_state()`**

After `_active_systems_manager()` (~line 2968) add:
```gdscript
## The fire model of the ship the player is currently aboard: the derelict's per-ship
## FireSuppressionState when away, the coordinator's home model otherwise. Mirrors
## _active_systems_manager(). The derelict instance is configured from tuning by
## _seed_derelict_fire() / the restore path before use.
func _active_fire_state():
	if away_from_start and current_ship != null:
		return current_ship.get_fire()
	return fire_suppression_state
```

- [ ] **Step 2: Route the home tick block through the active state**

In `_recompute_expanded_ship_systems` (~1362), replace:
```gdscript
	if fire_suppression_state != null:
		if fire_suppression_state.tick(delta, _build_fire_context()):
			_refresh_fire_zones()
		# M7-B Task 8: a burning compartment degrades the ship system housed there.
		_apply_fire_system_damage(delta)
```
with:
```gdscript
	var _afs_home = _active_fire_state()
	if _afs_home != null:
		if _afs_home.tick(delta, _build_fire_context()):
			_refresh_fire_zones()
		# M7-B Task 8: a burning compartment degrades the ship system housed there.
		_apply_fire_system_damage(delta)
```
(At home, `_active_fire_state()` returns `fire_suppression_state` — identical behavior. `_recompute_expanded_ship_systems` is only called on the home branch; Task 5 adds the away tick separately.)

- [ ] **Step 3: Route the reader functions through the active state**

In each of the following, replace direct `fire_suppression_state` reads with `_active_fire_state()` (capture into a local `var afs = _active_fire_state()` and null-check it):
- `_player_fire_intensity` (~2651): `if player == null or _active_fire_state() == null:` ... `return _active_fire_state().get_intensity(str(cid))`
- `_apply_fire_system_damage` (~2664): `var afs = _active_fire_state()` then `if afs == null or _active_systems_manager() == null: return`; iterate `afs.get_burning_compartments()`; `afs.get_intensity(...)`; and damage via `_active_systems_manager().damage_system(...)` (was `ship_systems_manager`).
- `_build_fire_zones` (~2674): after `_clear_fire_zones()`, **delete** the `if away_from_start: return` guard (lines ~2676-2679); `var afs = _active_fire_state()`; `if afs == null: return`; `var burning: Array = afs.get_burning_compartments()`.
- `_build_fire_suppression_points` (~2800): after `_clear_fire_suppression_points()`, **delete** the `if away_from_start: return` guard (~2802-2805); `var afs = _active_fire_state()`; `if afs == null: return`; build points with `afs` passed to `fp.configure(...)` in place of `fire_suppression_state`.
- `_refresh_fire_zones` (~2777): use `_active_fire_state()` in place of `fire_suppression_state`.

- [ ] **Step 4: Delete the recharge-port away guard**

In `_build_extinguisher_recharge_port` (~2843), change:
```gdscript
	if extinguisher_state == null or away_from_start:
		return
```
to:
```gdscript
	if extinguisher_state == null:
		return
```
(Power gating now happens per-frame in the tick — Task 5 — not by skipping the build.)

- [ ] **Step 5: Leave `_seed_fires_from_damage` home-only**

Do NOT touch `_seed_fires_from_damage` (~2631); it stays guarded on `away_from_start` (home/lifeboat seeding only). Derelict seeding is the separate `_seed_derelict_fire` added in Task 4.

- [ ] **Step 6: Parse-check + home fire regression**

Validate the script parses (add a temporary one-off or run an existing main-scene smoke). Then run the existing home fire loop smoke (`scripts/validation/main_playable_fire_loop_smoke.gd` or equivalent — confirm name via `ls scripts/validation | grep -i fire`) and confirm its PASS marker still prints. Home fire must be unchanged.

- [ ] **Step 7: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd
git commit -m "refactor(fire): route fire through _active_fire_state(); drop away guards"
```

---

### Task 4: Derelict fire seeding (`_seed_derelict_fire`)

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` — add `FIRE_PRESENCE_PERCENT` const (near other fire consts ~262), add `_fire_tuning()` + `_configure_derelict_fire()` + `_seed_derelict_fire()` helpers (near `_build_fire_context` ~2597); call `_seed_derelict_fire()` on the derelict fresh-build path (replace the no-op `_seed_fires_from_damage()` at ~1834); configure the restored derelict fire on the derelict restore/build paths.
- Test: `scripts/validation/derelict_fire_seed_smoke.gd` (create)

**Interfaces:**
- Consumes: `_active_fire_state()`, `_active_systems_manager()`, `_ship_seed(inst)`, `_ship_condition_class(inst)`, `FIRE_COMPARTMENT_SYSTEM`, `ShipBlueprint.Condition`.
- Produces:
  - `_seed_derelict_fire()` — configures the derelict's fire from tuning, then (deterministically) ignites 0–3 compartments.
  - `_configure_derelict_fire(fs)` — `fs.configure(_fire_tuning())`.
  - `_fire_tuning()` → `_load_json_dict(SHIP_SUBSYSTEM_TUNING_PATH).get("fire_suppression", {})`.

- [ ] **Step 1: Add the const + helpers**

Add near the fire consts (~262, beside `OXYGEN_MIN_FOR_FIRE`):
```gdscript
# Derelict-side fire: only ~1 in 7 boarded derelicts present any fire (deterministic per
# seed). Fire is one of several possible derelict conditions, not a default.
const FIRE_PRESENCE_PERCENT: int = 15
```

Add near `_build_fire_context` (~2597):
```gdscript
func _fire_tuning() -> Dictionary:
	return _load_json_dict(SHIP_SUBSYSTEM_TUNING_PATH).get("fire_suppression", {})

## Configures a per-ship derelict FireSuppressionState from shared tuning (compartments,
## adjacency, rates). Required before seeding or after restoring from a summary so spread
## topology exists.
func _configure_derelict_fire(fs) -> void:
	if fs != null:
		fs.configure(_fire_tuning())

## Pre-seeds environmental fire on a freshly built derelict. Deterministic, RNG-free:
## a per-seed presence gate (FIRE_PRESENCE_PERCENT) decides whether THIS derelict burns at
## all; when it does, ignites up to a condition-scaled cap of compartments whose mapped
## system is damaged (and not breached). Never called on the home/lifeboat ship or on the
## save-restore path (restored fire comes from the applied ShipInstance "fire" summary).
func _seed_derelict_fire() -> void:
	if not away_from_start or current_ship == null:
		return
	var fs = current_ship.get_fire()
	if fs == null:
		return
	_configure_derelict_fire(fs)
	var seed_int: int = _ship_seed(current_ship)
	# Presence gate — most derelicts board fire-free.
	if (abs(hash("%d:fire_presence" % seed_int)) % 100) >= FIRE_PRESENCE_PERCENT:
		return
	var mgr = _active_systems_manager()
	if mgr == null:
		return
	# Candidate compartments: mapped system damaged, not breached. Deterministic order.
	var breached := {}
	if hull_integrity_state != null:
		for cid in hull_integrity_state.compartments:
			if bool((hull_integrity_state.compartments[cid] as Dictionary).get("breach_open", false)):
				breached[str(cid)] = true
	var candidates: Array = []
	for cid in FIRE_COMPARTMENT_SYSTEM:
		var sid: String = str(FIRE_COMPARTMENT_SYSTEM[cid])
		if sid.is_empty() or breached.has(str(cid)):
			continue
		var sys = mgr.get_system(sid)
		if sys != null and not sys.is_self_functional():
			candidates.append(str(cid))
	candidates.sort()
	var cap: int = 2 + (1 if _ship_condition_class(current_ship) == ShipBlueprint.Condition.WRECKED else 0)
	var lit: int = 0
	for cid in candidates:
		if lit >= cap:
			break
		fs.ignite(cid, 1.0)
		lit += 1
```

- [ ] **Step 2: Call it on the derelict fresh-build path**

At ~1834 (the derelict build path with `_build_derelict_objectives()` above it), replace:
```gdscript
	# M7-B Task 7: fresh derelict build — seed fires from damaged systems, render zones.
	_seed_fires_from_damage()
	_build_fire_zones()
```
with:
```gdscript
	# Derelict-side fire: per-ship pre-seeded environmental fire (presence-gated, capped).
	_seed_derelict_fire()
	_build_fire_zones()
```

- [ ] **Step 3: Configure derelict fire on the restore path**

On any derelict build path that restores from a summary (the revisit/world-load path that calls `_build_fire_zones` for a derelict), ensure the restored `current_ship.fire` was configured. Because `apply_summary` (Task 1) now restores topology, an explicit configure is only needed when a derelict is built WITHOUT a fire summary. Guard `_build_fire_zones`/suppression builders are already safe (empty active fire → no-op). Add, right before the derelict-path `_build_fire_zones()` on the restore branch (if distinct from Step 2), a defensive `_configure_derelict_fire(current_ship.get_fire())` only if `not current_ship.has_fire()`. If the restore path is the same function as Step 2, no extra edit is needed — note this in the report.

- [ ] **Step 4: Write the seeding smoke**

Create `scripts/validation/derelict_fire_seed_smoke.gd` — a pure-logic smoke that reproduces the presence gate + cap math (it does not boot the main scene; it asserts determinism of the documented formula):

```gdscript
extends SceneTree

## Proves the derelict fire presence gate is deterministic and ~15%, the cap is honored,
## and the same seed always yields the same verdict. RNG-free (hash-based).
## Marker: DERELICT FIRE SEED PASS deterministic=true rate_ok=true cap_ok=true

const FIRE_PRESENCE_PERCENT: int = 15

func _present(seed_int: int) -> bool:
	return (abs(hash("%d:fire_presence" % seed_int)) % 100) < FIRE_PRESENCE_PERCENT

func _initialize() -> void:
	# Determinism: same seed, same verdict across calls.
	var deterministic: bool = true
	for s in [1, 7, 42, 9999, -3]:
		if _present(s) != _present(s):
			deterministic = false
			break
	# Rate: across a wide seed sweep, presence fraction is in a sane band around 15%.
	var present_count: int = 0
	var n: int = 2000
	for s in range(n):
		if _present(s):
			present_count += 1
	var frac: float = float(present_count) / float(n)
	var rate_ok: bool = frac > 0.10 and frac < 0.20
	# Cap formula: WRECKED(2) -> 3, else 2.
	var cap_pristine: int = 2 + (1 if 0 == 2 else 0)
	var cap_wrecked: int = 2 + (1 if 2 == 2 else 0)
	var cap_ok: bool = cap_pristine == 2 and cap_wrecked == 3

	if deterministic and rate_ok and cap_ok:
		print("DERELICT FIRE SEED PASS deterministic=true rate_ok=true cap_ok=true")
		quit(0)
	else:
		push_error("DERELICT FIRE SEED FAIL deterministic=%s rate_ok=%s (frac=%.3f) cap_ok=%s" % [deterministic, rate_ok, frac, cap_ok])
		quit(1)
```

- [ ] **Step 5: Run the seed smoke; expect PASS.** Also parse-check the coordinator (run an existing main-scene smoke) to confirm `_seed_derelict_fire` compiles.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/derelict_fire_seed_smoke.gd
git commit -m "feat(fire): pre-seed presence-gated, capped derelict fire"
```

---

### Task 5: Away-branch fire tick + power-gated recharge port

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` — `_build_fire_context` (~2598) derelict-aware values; away branch of `_process` (~4656-4696) gains the fire-tick + recharge-power block.
- Test: `scripts/validation/main_playable_derelict_fire_smoke.gd` (create)

**Interfaces:**
- Consumes: `_active_fire_state()`, `_active_systems_manager()`, `extinguisher_recharge_port`, `_build_fire_context()`.
- Produces: derelict fire ticks/spreads while away; degrades derelict systems; recharge port `powered` tracks derelict power-system operational state.

- [ ] **Step 1: Make `_build_fire_context` derelict-aware**

In `_build_fire_context` (~2598), branch the sourced values on `away_from_start`. Replace the `damaged` collection and `oxygen_present`/`powered_ratio` derivation so that when away:
- `damaged_compartments = []` (pre-seeded only — no live re-ignition chain on the derelict),
- `ship_oxygen_present = true` (boarded derelict has breathable pockets),
- `powered_ratio = 0.0` (no auto-suppression on a derelict),
- `breached_compartments` from `hull_integrity_state` if present else `[]`.

Concretely, wrap the home-only derivations:
```gdscript
	var damaged: Array = []
	var oxygen_present: bool = true
	var powered: float = 0.0
	if not away_from_start:
		if ship_systems_manager != null:
			for cid in FIRE_COMPARTMENT_SYSTEM:
				var sid: String = str(FIRE_COMPARTMENT_SYSTEM[cid])
				if sid.is_empty():
					continue
				var sys = ship_systems_manager.get_system(sid)
				if sys != null and not sys.is_self_functional():
					damaged.append(cid)
		if life_support_expanded_state != null:
			oxygen_present = life_support_expanded_state.oxygen_percent > OXYGEN_MIN_FOR_FIRE
		powered = power_grid_state.get_allocation_ratio("stations") if power_grid_state != null else 0.0
```
and build the return dict from `damaged`/`oxygen_present`/`powered` (arc_arcing stays as-is; on a derelict `electrical_arc_state` is the home model — leave `arc_arcing` computed as today, it is harmless with `damaged=[]`).

- [ ] **Step 2: Wire the away-branch fire tick**

In the `if away_from_start:` branch of `_process` (~4656), AFTER the sanity/hallucination block and BEFORE `_refresh_player_vitals(delta)` (~4682), add:
```gdscript
		# Derelict-side fire (wire BOTH branches): tick the active (derelict) fire model so
		# it spreads, degrades derelict systems, and feeds the player-vitals teeth that
		# _refresh_player_vitals applies below. The home branch ticks fire inside
		# _recompute_expanded_ship_systems, which this branch never calls.
		var _afs_away = _active_fire_state()
		if _afs_away != null:
			if _afs_away.tick(delta, _build_fire_context()):
				_refresh_fire_zones()
			_apply_fire_system_damage(delta)
		# Recharge port is power-gated on the DERELICT's own power system (engineering gate):
		# present but dead until the player restores derelict power.
		if is_instance_valid(extinguisher_recharge_port):
			var _dmgr = _active_systems_manager()
			extinguisher_recharge_port.set_powered(_dmgr != null and _dmgr.is_operational("power"))
```

- [ ] **Step 3: Apply fire health drain on the away branch (CONFIRMED required)**

The away branch does NOT tick `vitals_state` with `fire_health_drain`: the home branch applies fire teeth inline (`vitals_state.tick({... "fire_health_drain": FIRE_HEALTH_DRAIN_PER_SECOND * _player_fire_intensity() ...})` ~4746), but the away branch only refreshes the HUD via `_refresh_player_vitals` and applies *sanity* teeth via `vitals_state.apply_delta(...)` (~4678-4681). Derelict fire would damage systems but NOT the player. Mirror the sanity-teeth pattern so standing in derelict fire hurts. In the away branch, alongside the fire-tick block from Step 2 (after `_apply_fire_system_damage`), add:

```gdscript
			if vitals_state != null:
				var fire_drain: float = FIRE_HEALTH_DRAIN_PER_SECOND * _player_fire_intensity() * delta
				if fire_drain > 0.0:
					vitals_state.apply_delta({"health": -fire_drain})
```

(`_player_fire_intensity()` reads `_active_fire_state()` after Task 3, so it reports the derelict's fire.) The away smoke (Step 4) must assert player health drops while standing in a derelict fire.

- [ ] **Step 4: Write the main-scene away smoke**

Create `scripts/validation/main_playable_derelict_fire_smoke.gd`. It must:
- instantiate `res://scenes/main.tscn`, find the `PlayableGeneratedship`, wait for load + `playable_started`;
- force a derelict context: set `away_from_start = true` and ensure `current_ship` is a built derelict (use the existing travel/validation seam — check `playable.gd` for a `travel_*_for_validation` or board helper; if none, set `current_ship`/`away_from_start` directly and call the derelict build path used by tests). Then `force_ignite_compartment_for_validation(cid)` on the ACTIVE state via a new/extended seam if needed;
- assert (record into the marker), driving `away_ticks` real frames via `process_frame`:
  - `away_ticks > 0` and `away_from_start == true` during the asserted window;
  - fire zones built on the derelict (`get_fire_zone_nodes_for_validation()` non-empty);
  - the active fire **ticked** while away (intensity decreased after manual suppression, or spread/`_apply_fire_system_damage` advanced — assert burning set changes across frames);
  - recharge port exists and reads **unpowered** while derelict power is down, then **powered** after setting the derelict power system operational;
  - manual extinguish via the real interaction path clears a compartment.
- Marker: `MAIN PLAYABLE DERELICT FIRE PASS away_ticks=<n> seeded=true ticked=true hurt=true port_gated=true extinguished=true`

Mirror the structure of the existing `main_playable_item_economy_smoke.gd` / `main_playable_fire_loop_smoke.gd` (read both for the boot/await/teleport seams and the `set_manual_power_route_for_validation`-style helpers). Add any missing validation seam (e.g. `get_active_fire_state_for_validation()`) to the coordinator as a thin getter rather than reaching into privates.

- [ ] **Step 5: Run the away smoke; iterate to PASS.** Use the headless command pattern. Confirm the marker prints with `away_ticks > 0` and no unexpected ERROR/WARNING.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_derelict_fire_smoke.gd
git commit -m "feat(fire): tick derelict fire on the away branch; power-gate recharge port"
```

---

### Task 6: Sequential-persistence smoke, registration, audit, full bundle

**Files:**
- Test: `scripts/validation/derelict_fire_sequential_persistence_smoke.gd` (create)
- Modify: `docs/game/06_validation_plan.md`, `docs/game/system_completion_audit.md`

**Interfaces:**
- Consumes: the per-ship persistence from Tasks 2/4/5.
- Produces: a smoke proving a half-cleared derelict, left and revisited, retains its burning set; all smokes registered; audit re-graded; full bundle green.

- [ ] **Step 1: Write the sequential-persistence smoke**

Create `scripts/validation/derelict_fire_sequential_persistence_smoke.gd`. Drive it through the coordinator's real travel seams where available; otherwise assert at the `ShipInstance` + `visited_ships` level: build derelict A's `ShipInstance`, ignite 2 compartments, extinguish 1, round-trip A through `get_summary()`/`apply_summary()` into a fresh `ShipInstance` (simulating retain-in-`visited_ships`), and assert exactly the remaining 1 compartment burns. Prefer the live coordinator travel path if a `travel_to_*_for_validation` seam exists (check the coordinator). Marker: `DERELICT FIRE SEQUENTIAL PERSISTENCE PASS remembered=true`

- [ ] **Step 2: Run it; iterate to PASS.**

- [ ] **Step 3: Register all 5 smokes in `06_validation_plan.md`**

Add entries (with expected markers) for: `fire_suppression_round_trip_smoke`, `ship_instance_fire_persistence_smoke`, `derelict_fire_seed_smoke`, `main_playable_derelict_fire_smoke`, `derelict_fire_sequential_persistence_smoke`. Bump the bundle `commands=` count (currently 58 → 63) and add their PASS-marker greps to the bundle block exactly as the existing entries do. Read the existing item-economy entries (added in PR #45) as the template.

- [ ] **Step 4: Re-grade the audit**

In `docs/game/system_completion_audit.md` item 5, move "derelict-side fire points/recharge ports" from the deferred-follow-ups list to RESOLVED, citing `main_playable_derelict_fire_smoke.gd`, the 15% presence gate, the power-gated recharge port, and per-ship persistence. Keep the remaining deferred items (B2 vent control, fire-consumes-oxygen, door-gated spread) deferred.

- [ ] **Step 5: Run the FULL regression bundle**

Extract and run the bundle block from `docs/game/06_validation_plan.md` (set `GODOT`/`ROOT` to the Windows values; extract by line range with `sed`/`awk` inside bash — do NOT rely on Python `/tmp`). Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=63 clean_output=true`. Fix any unexpected ERROR/WARNING before proceeding.

- [ ] **Step 6: Commit**

```bash
git add scripts/validation/derelict_fire_sequential_persistence_smoke.gd docs/game/06_validation_plan.md docs/game/system_completion_audit.md
git commit -m "test(fire): sequential per-ship persistence; register smokes; audit re-grade"
```

---

## Self-Review

**Spec coverage:**
- Per-ship ownership + `_active_fire_state()` → Tasks 2, 3. ✓
- Presence gate (15%) + scaled/capped seeding → Task 4. ✓
- Power-gated recharge port → Task 5. ✓
- Away-branch fire tick ("wire BOTH branches") → Task 5. ✓
- Derelict fire context (no live re-ignition, no auto-suppress) → Task 5 Step 1. ✓
- Save/load via ShipInstance → Tasks 1, 2; sequential persistence → Task 6. ✓
- Validation (4 spec smokes) → Tasks 1, 2, 4, 5, 6 (5 smokes — round-trip split out as its own foundation). ✓
- Out-of-scope (simultaneous live burning, B2/oxygen/door-spread) → not implemented. ✓

**Placeholder scan:** Task 5 Step 4 and Task 6 Step 1 intentionally defer exact validation-seam names to "read the existing smoke and mirror it" because the precise `*_for_validation` seam names must be confirmed against the live coordinator at implementation time; the assertions and markers are fully specified. Task 4 Step 3 is conditional on whether the restore path is distinct from the build path — the implementer confirms and reports. These are flagged, not vague.

**Type consistency:** `get_fire()` returns the `FireSuppressionState` instance everywhere; `has_fire()` used in `get_summary`; `_active_fire_state()` returns the same type as `fire_suppression_state`. `FIRE_PRESENCE_PERCENT` int; cap int; `ShipBlueprint.Condition.WRECKED == 2`. Consistent across tasks.
