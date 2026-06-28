# M7-B — Fire Suppression ↔ Real Fire Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the decoupled fire timer + HUD-shadow suppression with one authoritative, compartment-keyed, persist-until-extinguished fire model the player actually fights — fire as a symptom of unrepaired system damage, with three extinguish paths, spread, arc cascade, and vitals + ship-system teeth.

**Architecture:** `FireSuppressionState` (pure `RefCounted`) becomes the single source of fire truth, keyed on the 4 logical compartments. `fire_state.gd` (the cyclic PhaseTimer hazard) is retired. The coordinator (`playable_generated_ship.gd`) renders one passable fire-zone `Area3D` per burning compartment, drives the model's tick from a context dict (power, oxygen, breaches, damaged systems, arc phase), applies vitals + system damage, and hosts the manual extinguish interaction + recharge port. A small `ExtinguisherState` models the player tool's charge.

**Tech Stack:** Godot 4.6.2 (Forward+), typed GDScript. Headless `--script` validation smokes whose PASS-marker is the contract.

## Global Constraints

- **Engine:** Godot 4.6.2, **typed GDScript** for all new code.
- **Godot binary (headless runs):** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`; **project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- **PASS marker is the contract** — Godot `--script` can exit 0 on parse/load errors; never trust exit code. Confirm the exact marker line and that no unexpected `ERROR:`/`WARNING:` appears.
- **Allowlisted baseline noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`. The save/load service smoke additionally emits one expected `WARNING: SaveLoadService: save file rejected by from_dict ...`.
- **Never stage** `project.godot`, `.godot/`, `*.uid`, or `addons/`. Use **selective `git add`** of the exact files each task touches.
- **Model/Node separation:** new `*_state.gd` models are pure `RefCounted`, never touch the scene tree, and provide `get_summary()`/`apply_summary()` round-trip. Scene consequences live in the coordinator/nodes.
- **Compartments (fixed set):** `bridge`, `engineering`, `hydroponics`, `cargo`.
- **Compartment → system map:** `engineering→power`, `bridge→navigation`, `hydroponics→life_support`, `cargo→(none)`.
- **Tuning constants:** `OXYGEN_MIN_FOR_FIRE = 5.0`, `FIRE_HEALTH_DRAIN_PER_SECOND = 2.0`, `FIRE_SYSTEM_DAMAGE_PER_SECOND = 0.05` (all `×intensity`).
- **Ignition/spread/cascade are RNG-free accumulators** — smokes assert exact behavior.
- **Save/load:** fire + extinguisher summaries nest inside `ship_systems_summary`. **No top-level `SUMMARY_FIELDS` change.**
- **Interact wiring:** FireSuppressionPoints MUST be iterated in **both** the home and away branches of `_on_player_interact_requested` (the precise gap Codex flagged P1 in M7-A).
- **Commit style:** Conventional Commits. Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_012rncQ3JTUdorqXH1b4eQNY
  ```
- **Run one smoke** pattern:
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd
  ```

---

## File Structure (decomposition)

| File | Responsibility | Task |
|---|---|---|
| `scripts/systems/fire_suppression_state.gd` | **Rework** → authoritative compartment fire model | 1 |
| `scripts/validation/fire_suppression_state_smoke.gd` | **New** pure-model smoke (replaces `fire_state_smoke.gd`) | 1 |
| `scripts/validation/fire_state_smoke.gd` | **Delete** | 1 |
| `scripts/systems/extinguisher_state.gd` | **New** player tool charge model | 2 |
| `scripts/validation/extinguisher_state_smoke.gd` | **New** | 2 |
| `scripts/systems/ship_systems_manager.gd` | **Add** `damage_system()` | 3 |
| `scripts/validation/ship_systems_damage_smoke.gd` | **New** | 3 |
| `scripts/systems/vitals_state.gd` | **Add** `fire_health_drain` channel | 4 |
| `scripts/validation/vitals_state_smoke.gd` | **Extend** (or the existing vitals smoke) | 4 |
| `scripts/tools/fire_suppression_point.gd` | **New** manual extinguish interaction node | 5 |
| `scripts/validation/fire_suppression_point_smoke.gd` | **New** | 5 |
| `scripts/tools/extinguisher_recharge_port.gd` | **New** recharge station node | 6 |
| `scripts/validation/extinguisher_recharge_port_smoke.gd` | **New** | 6 |
| `scripts/procgen/playable_generated_ship.gd` | **Rework** fire wiring (retire fire_state; zones; teeth; extinguish loop; recharge; save) | 7,8,9 |
| `data/ship_systems/subsystem_tuning.json` | **Extend** `fire_suppression` block | 7 |
| `scripts/systems/fire_state.gd` | **Delete** | 7 |
| `scripts/validation/hazard_contract_smoke.gd` | **Update** (fire out of timer set) | 7 |
| `scripts/validation/main_playable_slice_fire_smoke.gd` | **Rewrite** for passable + teeth + extinguish | 7,8 |
| `scripts/validation/main_playable_fire_loop_smoke.gd` | **New** full-loop smoke | 9 |
| `docs/game/adr/0041-fire-as-persistent-compartment-hazard.md` | **New** ADR | 10 |
| `docs/game/adr/0005-multi-hazard-architecture.md` | **Amend** (fire migration note) | 10 |
| `docs/game/06_validation_plan.md` | **Register** smokes + bump count | 10 |
| `docs/game/system_completion_audit.md` | **Re-grade** fire-suppression 🔴→🟢 | 10 |

---

### Task 1: Rework `FireSuppressionState` into the authoritative fire model

**Files:**
- Modify (full rewrite): `scripts/systems/fire_suppression_state.gd`
- Create: `scripts/validation/fire_suppression_state_smoke.gd`
- Delete: `scripts/validation/fire_state_smoke.gd`

**Interfaces:**
- Consumes: nothing (pure model). `tick(delta, context)` reads context keys `powered_ratio:float`, `ship_oxygen_present:bool`, `breached_compartments:Array`, `damaged_compartments:Array`, `arc_arcing:bool`.
- Produces (used by later tasks): `ignite(cid:String, intensity:float=1.0)->bool`, `extinguish(cid:String)->bool`, `is_burning(cid:String)->bool`, `get_burning_compartments()->Array`, `get_intensity(cid:String)->float`, `tick(delta:float, context:Dictionary)->bool`, `get_summary()->Dictionary`, `apply_summary(Dictionary)->bool`. Config keys consumed by `configure`: `compartments`, `suppressant_units`, `suppression_rate_per_second`, `power_threshold`, `adjacency`, `spread_rate_per_second`, `ignition_rate_per_second`, `cascade_rate_per_second`, `arc_compartment`.

- [ ] **Step 1: Write the failing smoke** — create `scripts/validation/fire_suppression_state_smoke.gd`:

```gdscript
extends SceneTree

## Pure-model smoke for the authoritative compartment fire model (ADR-0041).
## Pass marker:
##   FIRE SUPPRESSION STATE PASS ignite=true persist=true extinguish=true auto_suppress=true vent=true spread=true reignite=true cascade=true round_trip=true

func _initialize() -> void:
	var cfg := {
		"compartments": ["bridge", "engineering", "hydroponics", "cargo"],
		"suppressant_units": 100.0,
		"suppression_rate_per_second": 25.0,
		"power_threshold": 0.5,
		"adjacency": {
			"bridge": ["engineering"],
			"engineering": ["bridge", "hydroponics", "cargo"],
			"hydroponics": ["engineering"],
			"cargo": ["engineering"],
		},
		"spread_rate_per_second": 0.15,
		"ignition_rate_per_second": 0.2,
		"cascade_rate_per_second": 0.5,
		"arc_compartment": "engineering",
	}

	# ignite + persist (no auto-clear without a cause).
	var m := FireSuppressionState.new()
	m.configure(cfg)
	m.ignite("engineering", 1.0)
	if not m.is_burning("engineering"):
		_fail("ignite did not set engineering burning"); return
	var ctx_idle := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": false}
	for i in range(20):
		m.tick(0.5, ctx_idle)
	if not m.is_burning("engineering"):
		_fail("fire did not persist with no extinguish cause"); return

	# manual extinguish.
	if not m.extinguish("engineering") or m.is_burning("engineering"):
		_fail("extinguish did not clear the fire"); return

	# powered auto-suppression clears over time.
	var sup := FireSuppressionState.new(); sup.configure(cfg)
	sup.ignite("engineering", 1.0)
	var ctx_pow := {"powered_ratio": 1.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": false}
	for i in range(60):
		sup.tick(0.1, ctx_pow)
		if not sup.is_burning("engineering"):
			break
	if sup.is_burning("engineering"):
		_fail("powered auto-suppression never cleared the fire"); return

	# vent: a breached (vacuum) compartment auto-extinguishes.
	var vent := FireSuppressionState.new(); vent.configure(cfg)
	vent.ignite("engineering", 1.0)
	vent.tick(0.1, {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": ["engineering"], "damaged_compartments": [], "arc_arcing": false})
	if vent.is_burning("engineering"):
		_fail("vent (breach) did not extinguish the fire"); return

	# spread: engineering fire spreads to an oxygenated adjacent (bridge); cargo (vented) never ignites.
	var spr := FireSuppressionState.new(); spr.configure(cfg)
	spr.ignite("engineering", 1.0)
	var ctx_spread := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": ["cargo"], "damaged_compartments": [], "arc_arcing": false}
	for i in range(200):
		spr.tick(0.5, ctx_spread)
		if spr.is_burning("bridge"):
			break
	if not spr.is_burning("bridge"):
		_fail("fire never spread to adjacent bridge"); return
	if spr.is_burning("cargo"):
		_fail("fire spread into a vented compartment (cargo) — must not"); return

	# re-ignition: damaged + oxygen re-ignites after extinguish; clearing the damage stops it.
	var rei := FireSuppressionState.new(); rei.configure(cfg)
	var ctx_dmg := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": ["engineering"], "arc_arcing": false}
	for i in range(100):
		rei.tick(0.1, ctx_dmg)
		if rei.is_burning("engineering"):
			break
	if not rei.is_burning("engineering"):
		_fail("damaged+oxygen never ignited"); return
	rei.extinguish("engineering")
	var reignited := false
	for i in range(100):
		rei.tick(0.1, ctx_dmg)
		if rei.is_burning("engineering"):
			reignited = true; break
	if not reignited:
		_fail("damaged compartment did not re-ignite after extinguish"); return
	rei.extinguish("engineering")
	var ctx_repaired := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": false}
	for i in range(100):
		rei.tick(0.1, ctx_repaired)
	if rei.is_burning("engineering"):
		_fail("repaired compartment kept re-igniting — repair must stop it"); return

	# arc cascade: arcing ignites the arc compartment.
	var cas := FireSuppressionState.new(); cas.configure(cfg)
	var ctx_arc := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": true}
	for i in range(100):
		cas.tick(0.1, ctx_arc)
		if cas.is_burning("engineering"):
			break
	if not cas.is_burning("engineering"):
		_fail("arc cascade never ignited the arc compartment"); return

	# round-trip.
	var rt := FireSuppressionState.new(); rt.configure(cfg)
	rt.ignite("bridge", 2.0)
	rt.suppressant_units = 42.0
	rt.cascade_progress = 0.3
	var summary := rt.get_summary()
	var rt2 := FireSuppressionState.new(); rt2.configure(cfg)
	if not rt2.apply_summary(summary):
		_fail("apply_summary returned false on a changed summary"); return
	if not rt2.is_burning("bridge") or absf(rt2.suppressant_units - 42.0) > 0.001 or absf(rt2.cascade_progress - 0.3) > 0.001:
		_fail("round-trip did not restore state"); return

	print("FIRE SUPPRESSION STATE PASS ignite=true persist=true extinguish=true auto_suppress=true vent=true spread=true reignite=true cascade=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("FIRE SUPPRESSION STATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run it; verify it fails** — the current model lacks `extinguish`/`is_burning`/spread/etc.
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_suppression_state_smoke.gd`
Expected: FAIL (missing methods / behavior).

- [ ] **Step 3: Rewrite `scripts/systems/fire_suppression_state.gd`** to this:

```gdscript
extends RefCounted
class_name FireSuppressionState

## Authoritative, compartment-keyed, persist-until-extinguished fire model (ADR-0041).
## Fire is a SYMPTOM of unrepaired system damage: a compartment ignites only when its
## mapped system is damaged AND it has oxygen, and re-ignites until repaired or vented.
## Pure RefCounted; the coordinator renders passable fire-zone nodes from active_fires.

const DEFAULT_SUPPRESSANT_UNITS: float = 100.0
const DEFAULT_SUPPRESSION_RATE: float = 25.0
const DEFAULT_POWER_THRESHOLD: float = 0.5
const DEFAULT_SPREAD_RATE: float = 0.15
const DEFAULT_IGNITION_RATE: float = 0.2
const DEFAULT_CASCADE_RATE: float = 0.5
const DEFAULT_ARC_COMPARTMENT: String = "engineering"
const MIN_INTENSITY: float = 0.1
const MAX_INTENSITY: float = 10.0
# Powered suppression removes this fraction of intensity per second (rate * factor).
const SUPPRESSION_INTENSITY_FACTOR: float = 0.04
const SUPPRESSANT_DRAIN_PER_SECOND: float = 0.5

var compartments: Array[String] = []
var active_fires: Dictionary = {}              # compartment_id -> intensity (float)
var suppressant_units: float = DEFAULT_SUPPRESSANT_UNITS
var suppression_rate_per_second: float = DEFAULT_SUPPRESSION_RATE
var power_threshold: float = DEFAULT_POWER_THRESHOLD
var adjacency: Dictionary = {}                 # compartment_id -> Array[String]
var spread_rate_per_second: float = DEFAULT_SPREAD_RATE
var ignition_rate_per_second: float = DEFAULT_IGNITION_RATE
var cascade_rate_per_second: float = DEFAULT_CASCADE_RATE
var arc_compartment: String = DEFAULT_ARC_COMPARTMENT

var spread_progress: Dictionary = {}           # compartment_id -> float accumulator
var ignition_progress: Dictionary = {}         # compartment_id -> float accumulator
var cascade_progress: float = 0.0

func configure(config: Dictionary) -> void:
	compartments.clear()
	for entry in config.get("compartments", []):
		compartments.append(str(entry))
	active_fires.clear()
	spread_progress.clear()
	ignition_progress.clear()
	cascade_progress = 0.0
	suppressant_units = maxf(0.0, float(config.get("suppressant_units", DEFAULT_SUPPRESSANT_UNITS)))
	suppression_rate_per_second = maxf(0.1, float(config.get("suppression_rate_per_second", DEFAULT_SUPPRESSION_RATE)))
	power_threshold = clampf(float(config.get("power_threshold", DEFAULT_POWER_THRESHOLD)), 0.05, 1.0)
	spread_rate_per_second = maxf(0.0, float(config.get("spread_rate_per_second", DEFAULT_SPREAD_RATE)))
	ignition_rate_per_second = maxf(0.0, float(config.get("ignition_rate_per_second", DEFAULT_IGNITION_RATE)))
	cascade_rate_per_second = maxf(0.0, float(config.get("cascade_rate_per_second", DEFAULT_CASCADE_RATE)))
	arc_compartment = str(config.get("arc_compartment", DEFAULT_ARC_COMPARTMENT))
	adjacency.clear()
	var adj_variant: Variant = config.get("adjacency", {})
	if typeof(adj_variant) == TYPE_DICTIONARY:
		for cid in (adj_variant as Dictionary):
			var neighbours: Array[String] = []
			var list_variant: Variant = (adj_variant as Dictionary)[cid]
			if typeof(list_variant) == TYPE_ARRAY:
				for n in (list_variant as Array):
					neighbours.append(str(n))
			adjacency[str(cid)] = neighbours

func ignite(compartment_id: String, intensity: float = 1.0) -> bool:
	if compartment_id.is_empty():
		return false
	active_fires[compartment_id] = clampf(float(active_fires.get(compartment_id, 0.0)) + intensity, MIN_INTENSITY, MAX_INTENSITY)
	return true

func extinguish(compartment_id: String) -> bool:
	if not active_fires.has(compartment_id):
		return false
	active_fires.erase(compartment_id)
	spread_progress.erase(compartment_id)
	return true

func is_burning(compartment_id: String) -> bool:
	return active_fires.has(compartment_id)

func get_burning_compartments() -> Array:
	return active_fires.keys()

func get_intensity(compartment_id: String) -> float:
	return float(active_fires.get(compartment_id, 0.0))

func get_active_fire_count() -> int:
	return active_fires.size()

func tick(delta: float, context: Dictionary) -> bool:
	if delta <= 0.0:
		return false
	var changed: bool = false
	var breached: Dictionary = _to_set(context.get("breached_compartments", []))
	var damaged: Dictionary = _to_set(context.get("damaged_compartments", []))
	var ship_oxygen: bool = bool(context.get("ship_oxygen_present", true))
	var powered_ratio: float = float(context.get("powered_ratio", 0.0))
	var arc_arcing: bool = bool(context.get("arc_arcing", false))

	# 1. Vent / oxygen-loss extinguish.
	for cid in active_fires.keys():
		if not _has_oxygen(cid, ship_oxygen, breached):
			active_fires.erase(cid)
			spread_progress.erase(cid)
			changed = true

	# 2. Powered auto-suppression.
	if powered_ratio >= power_threshold and suppressant_units > 0.0 and not active_fires.is_empty():
		for cid in active_fires.keys():
			var reduced: float = float(active_fires[cid]) - suppression_rate_per_second * SUPPRESSION_INTENSITY_FACTOR * delta
			suppressant_units = maxf(0.0, suppressant_units - SUPPRESSANT_DRAIN_PER_SECOND * delta)
			if reduced <= 0.0:
				active_fires.erase(cid)
			else:
				active_fires[cid] = reduced
			changed = true

	# 3. Spread to oxygenated, non-burning adjacent compartments.
	var spread_ignites: Array = []
	for cid in active_fires.keys():
		var intensity: float = float(active_fires[cid])
		for adj in _adjacent(cid):
			if active_fires.has(adj) or not _has_oxygen(adj, ship_oxygen, breached):
				spread_progress.erase(adj)
				continue
			var p: float = float(spread_progress.get(adj, 0.0)) + spread_rate_per_second * delta * intensity
			if p >= 1.0:
				spread_ignites.append(adj)
				spread_progress.erase(adj)
			else:
				spread_progress[adj] = p
	for adj in spread_ignites:
		if not active_fires.has(adj):
			active_fires[adj] = MIN_INTENSITY if MIN_INTENSITY > 1.0 else 1.0
			changed = true

	# 4. Ignition from unrepaired damage (re-ignites until repaired/vented).
	for cid in compartments:
		var ignitable: bool = damaged.has(cid) and _has_oxygen(cid, ship_oxygen, breached) and not active_fires.has(cid)
		if ignitable:
			var p2: float = float(ignition_progress.get(cid, 0.0)) + ignition_rate_per_second * delta
			if p2 >= 1.0:
				active_fires[cid] = 1.0
				ignition_progress.erase(cid)
				changed = true
			else:
				ignition_progress[cid] = p2
		elif ignition_progress.has(cid):
			ignition_progress.erase(cid)

	# 5. Arc cascade.
	if arc_arcing and not active_fires.has(arc_compartment) and _has_oxygen(arc_compartment, ship_oxygen, breached):
		cascade_progress += cascade_rate_per_second * delta
		if cascade_progress >= 1.0:
			active_fires[arc_compartment] = 1.0
			cascade_progress = 0.0
			changed = true
	else:
		cascade_progress = 0.0

	return changed

func get_summary() -> Dictionary:
	return {
		"compartments": compartments.duplicate(),
		"active_fires": active_fires.duplicate(true),
		"suppressant_units": suppressant_units,
		"suppression_rate_per_second": suppression_rate_per_second,
		"power_threshold": power_threshold,
		"adjacency": adjacency.duplicate(true),
		"spread_rate_per_second": spread_rate_per_second,
		"ignition_rate_per_second": ignition_rate_per_second,
		"cascade_rate_per_second": cascade_rate_per_second,
		"arc_compartment": arc_compartment,
		"spread_progress": spread_progress.duplicate(true),
		"ignition_progress": ignition_progress.duplicate(true),
		"cascade_progress": cascade_progress,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var fires: Variant = summary.get("active_fires", null)
	if typeof(fires) == TYPE_DICTIONARY and JSON.stringify(fires) != JSON.stringify(active_fires):
		active_fires = (fires as Dictionary).duplicate(true)
		changed = true
	var sp: Variant = summary.get("spread_progress", null)
	if typeof(sp) == TYPE_DICTIONARY and JSON.stringify(sp) != JSON.stringify(spread_progress):
		spread_progress = (sp as Dictionary).duplicate(true)
		changed = true
	var ip: Variant = summary.get("ignition_progress", null)
	if typeof(ip) == TYPE_DICTIONARY and JSON.stringify(ip) != JSON.stringify(ignition_progress):
		ignition_progress = (ip as Dictionary).duplicate(true)
		changed = true
	var new_suppressant: float = float(summary.get("suppressant_units", suppressant_units))
	if absf(new_suppressant - suppressant_units) > 0.001:
		suppressant_units = new_suppressant
		changed = true
	var new_cascade: float = float(summary.get("cascade_progress", cascade_progress))
	if absf(new_cascade - cascade_progress) > 0.001:
		cascade_progress = new_cascade
		changed = true
	# Tunables (round-trip but rarely change at runtime).
	if summary.has("arc_compartment") and str(summary["arc_compartment"]) != arc_compartment:
		arc_compartment = str(summary["arc_compartment"]); changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Fire Suppression fires=%d suppressant=%.1f" % [get_active_fire_count(), suppressant_units])
	for cid in active_fires.keys():
		lines.append("Fire %s intensity=%.2f" % [str(cid), float(active_fires[cid])])
	return lines

func _adjacent(compartment_id: String) -> Array:
	var v: Variant = adjacency.get(compartment_id, [])
	return v if typeof(v) == TYPE_ARRAY else []

func _has_oxygen(compartment_id: String, ship_oxygen: bool, breached: Dictionary) -> bool:
	return ship_oxygen and not breached.has(compartment_id)

func _to_set(list_variant: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(list_variant) == TYPE_ARRAY:
		for entry in (list_variant as Array):
			out[str(entry)] = true
	return out
```

- [ ] **Step 4: Delete the obsolete pure smoke** `scripts/validation/fire_state_smoke.gd` (the timer model it tests is being retired in Task 7; its replacement is this task's new smoke).

- [ ] **Step 5: Run the new smoke; verify PASS**
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_suppression_state_smoke.gd`
Expected: `FIRE SUPPRESSION STATE PASS ignite=true persist=true extinguish=true auto_suppress=true vent=true spread=true reignite=true cascade=true round_trip=true` and no unexpected `ERROR:`/`WARNING:`.

- [ ] **Step 6: Commit**
```bash
git add scripts/systems/fire_suppression_state.gd scripts/validation/fire_suppression_state_smoke.gd
git rm scripts/validation/fire_state_smoke.gd
git commit -m "feat(m7b): authoritative compartment fire model + pure smoke"
```

---

### Task 2: `ExtinguisherState` (player tool charge model)

**Files:**
- Create: `scripts/systems/extinguisher_state.gd`
- Create: `scripts/validation/extinguisher_state_smoke.gd`

**Interfaces:**
- Produces: `has_charge_for_use()->bool`, `consume_use()->bool`, `recharge(delta:float)->void`, `get_summary()->Dictionary`, `apply_summary(Dictionary)->bool`. Config keys: `charge`, `max_charge`, `charge_cost_per_use`, `recharge_per_second`.

- [ ] **Step 1: Write the failing smoke** — `scripts/validation/extinguisher_state_smoke.gd`:

```gdscript
extends SceneTree

## Pass marker: EXTINGUISHER STATE PASS consume=true recharge=true round_trip=true

func _initialize() -> void:
	var e := ExtinguisherState.new()
	e.configure({"charge": 100.0, "max_charge": 100.0, "charge_cost_per_use": 34.0, "recharge_per_second": 5.0})
	# consume: 100 -> 66 -> 32 -> blocked (32 < 34).
	if not e.has_charge_for_use() or not e.consume_use():
		_fail("first use should succeed"); return
	if not e.consume_use():
		_fail("second use should succeed"); return
	if e.has_charge_for_use() or e.consume_use():
		_fail("third use should be blocked (insufficient charge)"); return
	if absf(e.charge - 32.0) > 0.001:
		_fail("charge after two uses should be 32.0, got %.3f" % e.charge); return
	# recharge clamps to max.
	e.recharge(100.0)
	if absf(e.charge - 100.0) > 0.001:
		_fail("recharge should clamp to max_charge"); return
	# round-trip.
	e.consume_use()
	var s := e.get_summary()
	var e2 := ExtinguisherState.new()
	e2.configure({"charge": 0.0, "max_charge": 100.0})
	if not e2.apply_summary(s) or absf(e2.charge - e.charge) > 0.001:
		_fail("round-trip failed"); return
	print("EXTINGUISHER STATE PASS consume=true recharge=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("EXTINGUISHER STATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run; verify it fails** (class does not exist).
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/extinguisher_state_smoke.gd`
Expected: FAIL / parse error referencing `ExtinguisherState`.

- [ ] **Step 3: Create `scripts/systems/extinguisher_state.gd`:**

```gdscript
extends RefCounted
class_name ExtinguisherState

## Player fire-extinguisher tool charge (ADR-0041). Reusable: consumed per manual
## extinguish, refilled at a powered recharge port. Pure RefCounted.

const DEFAULT_MAX_CHARGE: float = 100.0
const DEFAULT_COST_PER_USE: float = 34.0
const DEFAULT_RECHARGE_PER_SECOND: float = 5.0

var max_charge: float = DEFAULT_MAX_CHARGE
var charge: float = DEFAULT_MAX_CHARGE
var charge_cost_per_use: float = DEFAULT_COST_PER_USE
var recharge_per_second: float = DEFAULT_RECHARGE_PER_SECOND

func configure(config: Dictionary) -> void:
	max_charge = maxf(1.0, float(config.get("max_charge", DEFAULT_MAX_CHARGE)))
	charge_cost_per_use = maxf(0.0, float(config.get("charge_cost_per_use", DEFAULT_COST_PER_USE)))
	recharge_per_second = maxf(0.0, float(config.get("recharge_per_second", DEFAULT_RECHARGE_PER_SECOND)))
	charge = clampf(float(config.get("charge", max_charge)), 0.0, max_charge)

func has_charge_for_use() -> bool:
	return charge >= charge_cost_per_use

func consume_use() -> bool:
	if not has_charge_for_use():
		return false
	charge = maxf(0.0, charge - charge_cost_per_use)
	return true

func recharge(delta: float) -> void:
	if delta <= 0.0:
		return
	charge = minf(max_charge, charge + recharge_per_second * delta)

func get_summary() -> Dictionary:
	return {
		"charge": charge,
		"max_charge": max_charge,
		"charge_cost_per_use": charge_cost_per_use,
		"recharge_per_second": recharge_per_second,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	for key in ["max_charge", "charge_cost_per_use", "recharge_per_second", "charge"]:
		if summary.has(key):
			var new_val: float = float(summary[key])
			if absf(new_val - float(get(key))) > 0.001:
				set(key, new_val)
				changed = true
	charge = clampf(charge, 0.0, max_charge)
	return changed
```

- [ ] **Step 4: Run; verify PASS** — `EXTINGUISHER STATE PASS consume=true recharge=true round_trip=true`.
- [ ] **Step 5: Commit**
```bash
git add scripts/systems/extinguisher_state.gd scripts/validation/extinguisher_state_smoke.gd
git commit -m "feat(m7b): extinguisher charge model + smoke"
```

---

### Task 3: `ShipSystemsManager.damage_system()`

**Files:**
- Modify: `scripts/systems/ship_systems_manager.gd` (add one method near `force_repair`, ~line 174)
- Create: `scripts/validation/ship_systems_damage_smoke.gd`

**Interfaces:**
- Produces: `damage_system(system_id:String, amount:float)->bool` — reduces every subcomponent's `health` by `amount` (clamp ≥0); returns false for unknown system.

- [ ] **Step 1: Write the failing smoke** — `scripts/validation/ship_systems_damage_smoke.gd`:

```gdscript
extends SceneTree

## Pass marker: SHIP SYSTEMS DAMAGE PASS damaged=true unknown_rejected=true

func _initialize() -> void:
	var mgr := ShipSystemsManager.new()
	var defs := mgr.load_definitions()
	mgr.configure(defs, ShipSystemsManager.CONDITION_PRISTINE, 1)
	var before := mgr.get_system("power").health()
	if before < 0.99:
		_fail("pristine power should start healthy"); return
	if not mgr.damage_system("power", 0.6):
		_fail("damage_system(power) should return true"); return
	var after := mgr.get_system("power").health()
	if after >= before:
		_fail("power health should drop after damage (%.2f -> %.2f)" % [before, after]); return
	if mgr.is_operational("power"):
		_fail("power should be non-operational after 0.6 damage (below threshold)"); return
	if mgr.damage_system("does_not_exist", 0.5):
		_fail("damage_system on unknown system should return false"); return
	print("SHIP SYSTEMS DAMAGE PASS damaged=true unknown_rejected=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SHIP SYSTEMS DAMAGE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run; verify it fails** (`damage_system` missing).

- [ ] **Step 3: Add the method** to `scripts/systems/ship_systems_manager.gd` immediately after `force_repair` (before `get_status_summary`):

```gdscript
## Reduces every subcomponent's health in a system by `amount` (clamp >= 0).
## Used by the coordinator to apply fire -> system degradation. Returns false
## for an unknown system.
func damage_system(system_id: String, amount: float) -> bool:
	if not systems.has(system_id) or amount <= 0.0:
		return systems.has(system_id)
	for sub in systems[system_id].subcomponents:
		sub.health = maxf(0.0, sub.health - amount)
	return true
```

- [ ] **Step 4: Run; verify PASS** — `SHIP SYSTEMS DAMAGE PASS damaged=true unknown_rejected=true`.
- [ ] **Step 5: Commit**
```bash
git add scripts/systems/ship_systems_manager.gd scripts/validation/ship_systems_damage_smoke.gd
git commit -m "feat(m7b): ShipSystemsManager.damage_system + smoke"
```

---

### Task 4: `vitals_state` `fire_health_drain` channel

**Files:**
- Modify: `scripts/systems/vitals_state.gd:52-58, 80-88`
- Modify (extend): the existing vitals pure smoke. Confirm the file name first with `ls scripts/validation/ | grep vitals`; this plan assumes `scripts/validation/vitals_state_smoke.gd`. If the project's vitals smoke has a different name, extend that one and keep its existing marker, appending the assertion below.

**Interfaces:**
- Produces: `vitals_state.tick` now consumes context key `fire_health_drain:float` (added to health drain, exactly like `atmosphere_health_drain`).

- [ ] **Step 1: Add a failing assertion** to the vitals smoke (inside its `_initialize`, before the existing success print). Use a fresh `VitalsState`:

```gdscript
	# M7-B: fire_health_drain channel adds to health drain.
	var vf := VitalsState.new()
	vf.configure({"health": 50.0, "max_health": 100.0})
	vf.tick(1.0, {"moving": false, "fire_health_drain": 4.0})
	if absf(vf.health - 46.0) > 0.001:
		push_error("VITALS ... FAIL reason=fire_health_drain not applied (expected 46.0, got %.3f)" % vf.health)
		quit(1)
		return
```
(Match the file's existing `_fail`/marker conventions; the assertion content above is the load-bearing part.)

- [ ] **Step 2: Run the vitals smoke; verify it fails** on the new assertion.

- [ ] **Step 3: Implement the channel.** In `scripts/systems/vitals_state.gd`, update the `tick` docstring channel list (after the `atmosphere_health_drain` line) to add:
```gdscript
##   "fire_health_drain" -> float (added to health drain while standing in a burning compartment)
```
and add the drain term in the Health block, immediately after the `atmosphere_health_drain` branch (~line 85):
```gdscript
	if context.has("fire_health_drain"):
		h_drain += float(context.get("fire_health_drain", 0.0)) * delta_seconds
```

- [ ] **Step 4: Run the vitals smoke; verify PASS** (its existing marker, unchanged).
- [ ] **Step 5: Commit**
```bash
git add scripts/systems/vitals_state.gd scripts/validation/vitals_state_smoke.gd
git commit -m "feat(m7b): vitals fire_health_drain channel"
```

---

### Task 5: `FireSuppressionPoint` interaction node

**Files:**
- Create: `scripts/tools/fire_suppression_point.gd`
- Create: `scripts/validation/fire_suppression_point_smoke.gd`

**Interfaces:**
- Consumes: `FireSuppressionState` (`is_burning`, `extinguish`), `ExtinguisherState` (`has_charge_for_use`, `consume_use`), `InventoryState` (`get_quantity`).
- Produces: `configure(compartment_id, fire_state_ref, extinguisher_state, inventory_state, player_progression, world_position, extinguish_seconds, required_tool, radius)`, `try_start(player)->bool`, `advance_channel(delta)->void`, signals `fire_extinguished(compartment_id)`, `extinguish_blocked(compartment_id, reason)`. Fields `channeling:bool`, `extinguished:bool`.

- [ ] **Step 1: Write the failing smoke** — `scripts/validation/fire_suppression_point_smoke.gd`:

```gdscript
extends SceneTree

## Pass marker: FIRE SUPPRESSION POINT PASS extinguished=true charge_spent=true gated=true

const FireSuppressionStateScript := preload("res://scripts/systems/fire_suppression_state.gd")
const ExtinguisherStateScript := preload("res://scripts/systems/extinguisher_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const FireSuppressionPointScript := preload("res://scripts/tools/fire_suppression_point.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var fire = FireSuppressionStateScript.new()
	fire.configure({"compartments": ["engineering"], "adjacency": {}})
	var ext = ExtinguisherStateScript.new()
	ext.configure({"charge": 100.0, "max_charge": 100.0, "charge_cost_per_use": 34.0})
	var inv = InventoryStateScript.new()
	inv.add_item("fire_extinguisher", 1)

	var player := Node3D.new()
	get_root().add_child(player)
	player.global_position = Vector3.ZERO

	var point = FireSuppressionPointScript.new()
	point.configure("engineering", fire, ext, inv, null, Vector3.ZERO, 4.0, "fire_extinguisher", 1.8)
	get_root().add_child(point)
	await process_frame

	# gated: not burning yet -> try_start fails.
	if point.try_start(player):
		_fail("try_start should fail when compartment is not burning"); return

	fire.ignite("engineering", 1.0)
	var charge_before: float = ext.charge
	if not point.try_start(player):
		_fail("try_start should succeed: burning, in range, tool + charge present"); return
	point.advance_channel(10.0)
	if fire.is_burning("engineering"):
		_fail("fire should be extinguished after the channel completes"); return
	if ext.charge >= charge_before:
		_fail("extinguisher charge should be spent on completion"); return

	print("FIRE SUPPRESSION POINT PASS extinguished=true charge_spent=true gated=true")
	_cleanup(0)

func _cleanup(code: int) -> void:
	quit(code)

func _fail(reason: String) -> void:
	push_error("FIRE SUPPRESSION POINT FAIL reason=%s" % reason)
	quit(1)
```
> Note: confirm `scripts/systems/inventory_state.gd` and `InventoryState.add_item(id, qty)` / `get_quantity(id)` exist (they are used by `BreachSealPoint` precedent). If the constructor needs no `configure`, the above is correct (matches M7-A's seal-point smoke fix).

- [ ] **Step 2: Run; verify it fails** (node script missing).

- [ ] **Step 3: Create `scripts/tools/fire_suppression_point.gd`** (modeled on `scripts/tools/breach_seal_point.gd`):

```gdscript
extends Area3D
class_name FireSuppressionPoint

## Spatial, tool-gated, timed extinguish node bound to one burning compartment of a
## FireSuppressionState. Modeled on BreachSealPoint: interacting starts a channel that
## ticks in this node's OWN _process; leaving range cancels with no cost; completing
## consumes one extinguisher use and extinguishes the compartment.

signal fire_extinguished(compartment_id: String)
signal extinguish_blocked(compartment_id: String, reason: String)

var compartment_id: String = ""
var fire_state                          # FireSuppressionState
var extinguisher_state                  # ExtinguisherState
var inventory_state                     # InventoryState
var player_progression                  # PlayerProgressionState | null
var interaction_radius: float = 1.8
var extinguish_seconds: float = 4.0
var required_tool: String = "fire_extinguisher"

var channeling: bool = false
var progress: float = 0.0
var extinguished: bool = false
var _channel_player: Node = null
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D
var marker_visible: bool = true

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

func configure(p_compartment_id: String, p_fire_state, p_extinguisher_state, p_inventory_state, p_player_progression, world_position: Vector3, p_extinguish_seconds: float, p_required_tool: String, radius := 1.8) -> void:
	compartment_id = p_compartment_id
	fire_state = p_fire_state
	extinguisher_state = p_extinguisher_state
	inventory_state = p_inventory_state
	player_progression = p_player_progression
	extinguish_seconds = maxf(0.01, p_extinguish_seconds)
	required_tool = p_required_tool
	interaction_radius = radius
	channeling = false
	progress = 0.0
	extinguished = false
	candidate_player = null
	position = world_position
	name = "FireSuppressionPoint_%s" % p_compartment_id
	set_meta("fire_suppression_point", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func try_start(player_body: Node) -> bool:
	if extinguished or channeling or not is_instance_valid(player_body) or fire_state == null:
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	if not fire_state.is_burning(compartment_id):
		emit_signal("extinguish_blocked", compartment_id, "not_burning")
		return false
	if not _has_required_tool():
		emit_signal("extinguish_blocked", compartment_id, "missing_extinguisher")
		return false
	if extinguisher_state == null or not extinguisher_state.has_charge_for_use():
		emit_signal("extinguish_blocked", compartment_id, "no_charge")
		return false
	_channel_player = player_body
	channeling = true
	progress = 0.0
	return true

func _has_required_tool() -> bool:
	if required_tool.is_empty():
		return true
	if inventory_state == null:
		return false
	return int(inventory_state.get_quantity(required_tool)) > 0

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
	progress = clampf(progress + delta / extinguish_seconds, 0.0, 1.0)
	if progress >= 1.0:
		_complete()

func _complete() -> void:
	channeling = false
	if extinguisher_state == null or not extinguisher_state.has_charge_for_use():
		progress = 0.0
		emit_signal("extinguish_blocked", compartment_id, "no_charge")
		return
	if not _has_required_tool():
		progress = 0.0
		emit_signal("extinguish_blocked", compartment_id, "missing_extinguisher")
		return
	extinguisher_state.consume_use()
	if fire_state.extinguish(compartment_id):
		extinguished = true
		_set_extinguished_visual()
		if player_progression != null and player_progression.has_method("grant_xp"):
			player_progression.grant_xp("repair", 10)
		emit_signal("fire_extinguished", compartment_id)
	else:
		progress = 0.0
		emit_signal("extinguish_blocked", compartment_id, "extinguish_failed")

func _cancel() -> void:
	channeling = false
	progress = 0.0
	_channel_player = null

func _set_extinguished_visual() -> void:
	if collision_shape != null:
		collision_shape.disabled = true
	if marker != null:
		marker.visible = false

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var player_node: Node3D = player_body as Node3D
	if not is_inside_tree() or not player_node.is_inside_tree():
		return false
	return global_position.distance_to(player_node.global_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "FireSuppressionCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = extinguished

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "FireSuppressionMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.45, 0.1, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible and not extinguished
	marker.set_meta("debug_fire_suppression_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Run; verify PASS** — `FIRE SUPPRESSION POINT PASS extinguished=true charge_spent=true gated=true`.
- [ ] **Step 5: Commit**
```bash
git add scripts/tools/fire_suppression_point.gd scripts/validation/fire_suppression_point_smoke.gd
git commit -m "feat(m7b): FireSuppressionPoint extinguish interaction + smoke"
```

---

### Task 6: `ExtinguisherRechargePort` node

**Files:**
- Create: `scripts/tools/extinguisher_recharge_port.gd`
- Create: `scripts/validation/extinguisher_recharge_port_smoke.gd`

**Interfaces:**
- Consumes: `ExtinguisherState` (`recharge`).
- Produces: `configure(extinguisher_state, world_position, radius)`, `set_powered(bool)`, self-ticking recharge while powered + player in range. Field `powered:bool`.

- [ ] **Step 1: Write the failing smoke** — `scripts/validation/extinguisher_recharge_port_smoke.gd`:

```gdscript
extends SceneTree

## Pass marker: EXTINGUISHER RECHARGE PORT PASS powered_refills=true unpowered_noop=true

const ExtinguisherStateScript := preload("res://scripts/systems/extinguisher_state.gd")
const PortScript := preload("res://scripts/tools/extinguisher_recharge_port.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var ext = ExtinguisherStateScript.new()
	ext.configure({"charge": 10.0, "max_charge": 100.0, "recharge_per_second": 20.0})
	var player := Node3D.new(); get_root().add_child(player); player.global_position = Vector3.ZERO
	var port = PortScript.new()
	port.configure(ext, Vector3.ZERO, 1.8)
	get_root().add_child(port)
	await process_frame
	port.set_validation_player_in_range(player)

	# unpowered: no refill.
	port.set_powered(false)
	var before: float = ext.charge
	port._process(1.0)
	if absf(ext.charge - before) > 0.001:
		_fail("unpowered port must not recharge"); return

	# powered: refills.
	port.set_powered(true)
	port._process(1.0)
	if ext.charge <= before:
		_fail("powered port should refill charge"); return

	print("EXTINGUISHER RECHARGE PORT PASS powered_refills=true unpowered_noop=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("EXTINGUISHER RECHARGE PORT FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run; verify it fails.**

- [ ] **Step 3: Create `scripts/tools/extinguisher_recharge_port.gd`:**

```gdscript
extends Area3D
class_name ExtinguisherRechargePort

## Stationary recharge station for the player's fire extinguisher (ADR-0041).
## Refills ExtinguisherState charge while powered AND a player is in range. The
## coordinator drives `powered` each frame from the "stations" power channel
## (same precedent as CraftingStation.set_powered).

var extinguisher_state                  # ExtinguisherState
var interaction_radius: float = 1.8
var powered: bool = false
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

func configure(p_extinguisher_state, world_position: Vector3, radius := 1.8) -> void:
	extinguisher_state = p_extinguisher_state
	interaction_radius = radius
	candidate_player = null
	powered = false
	position = world_position
	name = "ExtinguisherRechargePort"
	set_meta("extinguisher_recharge_port", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_powered(value: bool) -> void:
	powered = value

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func _process(delta: float) -> void:
	if not powered or extinguisher_state == null:
		return
	if not _player_in_range():
		return
	extinguisher_state.recharge(delta)

func _player_in_range() -> bool:
	if not is_instance_valid(candidate_player) or not (candidate_player is Node3D):
		return false
	var p: Node3D = candidate_player as Node3D
	if not is_inside_tree() or not p.is_inside_tree():
		return false
	return global_position.distance_to(p.global_position) <= interaction_radius

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "RechargePortCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "RechargePortMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.6, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_recharge_port_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Run; verify PASS** — `EXTINGUISHER RECHARGE PORT PASS powered_refills=true unpowered_noop=true`.
- [ ] **Step 5: Commit**
```bash
git add scripts/tools/extinguisher_recharge_port.gd scripts/validation/extinguisher_recharge_port_smoke.gd
git commit -m "feat(m7b): extinguisher recharge port node + smoke"
```

---

### Task 7: Coordinator — retire `fire_state`, stand up authoritative fire + passable per-compartment zones

This is the largest task. It removes the old timer fire from the coordinator, deletes `fire_state.gd`, fixes the hazard-contract smoke, extends the tuning JSON, and renders fire from the authoritative model. **Read `scripts/procgen/playable_generated_ship.gd` around every anchor below before editing** — line numbers drift.

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `data/ship_systems/subsystem_tuning.json`
- Delete: `scripts/systems/fire_state.gd`
- Modify: `scripts/validation/hazard_contract_smoke.gd`
- Rewrite: `scripts/validation/main_playable_slice_fire_smoke.gd`

**Interfaces:**
- Consumes: `FireSuppressionState` (Task 1), `ship_systems_manager` (Task 3), `electrical_arc_state`, `hull_integrity_state`, `life_support_expanded_state`.
- Produces (used by Tasks 8-9 + smokes): `get_burning_compartments_for_validation()->Array`, `get_fire_zone_nodes_for_validation()->Array`, `force_ignite_compartment_for_validation(cid, intensity)->bool`, the per-frame fire context, and the `_build_fire_zones()/_clear_fire_zones()/_refresh_fire_zones()` lifecycle.

- [ ] **Step 1: Extend the tuning JSON.** Replace the `"fire_suppression"` block in `data/ship_systems/subsystem_tuning.json` with:

```json
  "fire_suppression": {
    "compartments": ["bridge", "engineering", "hydroponics", "cargo"],
    "suppressant_units": 100.0,
    "suppression_rate_per_second": 25.0,
    "power_threshold": 0.5,
    "adjacency": {
      "bridge": ["engineering"],
      "engineering": ["bridge", "hydroponics", "cargo"],
      "hydroponics": ["engineering"],
      "cargo": ["engineering"]
    },
    "spread_rate_per_second": 0.15,
    "ignition_rate_per_second": 0.2,
    "cascade_rate_per_second": 0.5,
    "arc_compartment": "engineering"
  },
```

- [ ] **Step 2: Remove the old `fire_state` timer wiring** from `scripts/procgen/playable_generated_ship.gd`. Delete or replace:
  - the `FireStateScript` preload (~line 20);
  - the `var fire_state: FireState`, `fire_zone_node`, `fire_zone_label`, `fire_zone_resolved_room_id` declarations (~314-322);
  - `fire_state = FireStateScript.new()` (~1127) and the `_build_fire_zone()` call in the build sequence (~3615);
  - `fire_state.tick(delta); _refresh_fire_state(false)` in `_process` (~4259-4261);
  - the whole `_build_fire_zone` / `_resolve_fire_zone_world_position` / `_create_fire_zone_node` / `_make_fire_zone_material` / `_create_fire_zone_label` / `_refresh_fire_state` / `_apply_fire_zone_scene_state` / `_set_fire_zone_collision_enabled` / `_update_fire_zone_visual` / `get_fire_summary` / `get_fire_zone_node` / `get_fire_zone_resolved_room_id` / `get_fire_zone_collision_enabled_count` / `teleport_player_to_fire_zone_for_validation` block (~4642-4851);
  - `FIRE_ZONE_FALLBACK_ID` / `FIRE_ZONE_FALLBACK_ROOM_ID` / label-text / color constants used only by the above;
  - the `snapshot.fire_summary` save (~5471-5472) and restore (~5758-5760);
  - the `fire_state.is_passability_blocked()` audio check (~5100) — replace with `fire_suppression_state != null and not fire_suppression_state.get_burning_compartments().is_empty()`;
  - the `fire_state.configure(...)` reset block (~6504-6508) and `fire_zone_node = null` reset lines (~6531).

  Keep `FireSuppressionStateScript` and the existing `fire_suppression_state` declaration (~337).

- [ ] **Step 3: Add fire-zone scene rendering + context + seeding.** Add these members near the breach-seal-point declarations (~line 247):

```gdscript
var fire_zone_nodes: Dictionary = {}    # compartment_id -> Area3D (passable fire trigger)
const FIRE_COMPARTMENT_SYSTEM := {
	"bridge": "navigation",
	"engineering": "power",
	"hydroponics": "life_support",
	"cargo": "",
}
const OXYGEN_MIN_FOR_FIRE: float = 5.0
const FIRE_HEALTH_DRAIN_PER_SECOND: float = 2.0
const FIRE_SYSTEM_DAMAGE_PER_SECOND: float = 0.05
```

Add the fire-tick + rendering helpers (place them near the retired fire region, e.g. after `_clear_breach_seal_points`):

```gdscript
## Builds the per-frame context the authoritative fire model ticks against.
func _build_fire_context() -> Dictionary:
	var breached: Array = []
	if hull_integrity_state != null:
		for cid in hull_integrity_state.compartments:
			if bool((hull_integrity_state.compartments[cid] as Dictionary).get("breach_open", false)):
				breached.append(str(cid))
	var damaged: Array = []
	if ship_systems_manager != null:
		for cid in FIRE_COMPARTMENT_SYSTEM:
			var sid: String = str(FIRE_COMPARTMENT_SYSTEM[cid])
			if sid.is_empty():
				continue
			var sys = ship_systems_manager.get_system(sid)
			if sys != null and not sys.is_self_functional():
				damaged.append(cid)
	var oxygen_present: bool = true
	if life_support_expanded_state != null:
		oxygen_present = life_support_expanded_state.oxygen_percent > OXYGEN_MIN_FOR_FIRE
	var arc_arcing: bool = false
	if electrical_arc_state != null:
		arc_arcing = electrical_arc_state.phase == ElectricalArcState.Phase.ARCING
	return {
		"powered_ratio": power_grid_state.get_allocation_ratio("stations") if power_grid_state != null else 0.0,
		"ship_oxygen_present": oxygen_present,
		"breached_compartments": breached,
		"damaged_compartments": damaged,
		"arc_arcing": arc_arcing,
	}

## Seeds fires in compartments whose mapped system is already damaged at build time,
## so a damaged ship presents fire immediately rather than only after the ignition
## accumulator fills.
func _seed_fires_from_damage() -> void:
	if fire_suppression_state == null:
		return
	var ctx := _build_fire_context()
	var breached := {}
	for c in ctx.get("breached_compartments", []):
		breached[str(c)] = true
	if not bool(ctx.get("ship_oxygen_present", true)):
		return
	for cid in ctx.get("damaged_compartments", []):
		if not breached.has(str(cid)):
			fire_suppression_state.ignite(str(cid), 1.0)

func _build_fire_zones() -> void:
	_clear_fire_zones()
	if fire_suppression_state == null:
		return
	var burning: Array = fire_suppression_state.get_burning_compartments()
	if burning.is_empty():
		return
	var positions: Array = _distributed_room_positions()
	if away_from_start and current_ship != null and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root):
		pass  # current-ship positions resolved by _distributed_room_positions() already
	if positions.is_empty():
		return
	var idx: int = 0
	for cid in burning:
		var pos: Vector3 = positions[idx % positions.size()]
		idx += 1
		var zone := Area3D.new()
		zone.name = "FireZone_%s" % str(cid)
		zone.monitoring = false
		zone.monitorable = false
		zone.set_meta("fire_compartment_id", str(cid))
		zone.position = pos
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 2.0
		shape.shape = sphere
		zone.add_child(shape)
		var visual := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 1.2, 1.2)
		visual.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.3, 0.05, 0.65)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.1)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		visual.material_override = mat
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		zone.add_child(visual)
		_attach_zone_to_active_ship(zone)
		fire_zone_nodes[str(cid)] = zone

func _attach_zone_to_active_ship(node: Node) -> void:
	if away_from_start and current_ship != null and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root):
		current_ship.scene_root.add_child(node)
	elif lifeboat_ship != null and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root):
		lifeboat_ship.scene_root.add_child(node)
	else:
		repair_point_root.add_child(node)

func _clear_fire_zones() -> void:
	for cid in fire_zone_nodes:
		var z = fire_zone_nodes[cid]
		if is_instance_valid(z):
			var parent = z.get_parent()
			if parent != null and is_instance_valid(parent):
				parent.remove_child(z)
			z.queue_free()
	fire_zone_nodes.clear()

func _refresh_fire_zones() -> void:
	# Rebuild only when the burning set differs from the rendered set.
	var burning := {}
	if fire_suppression_state != null:
		for cid in fire_suppression_state.get_burning_compartments():
			burning[str(cid)] = true
	var rendered := {}
	for cid in fire_zone_nodes:
		rendered[str(cid)] = true
	if JSON.stringify(burning.keys()) != JSON.stringify(rendered.keys()):
		_build_fire_zones()

# --- validation seams ---
func get_burning_compartments_for_validation() -> Array:
	return fire_suppression_state.get_burning_compartments() if fire_suppression_state != null else []

func get_fire_zone_nodes_for_validation() -> Array:
	return fire_zone_nodes.values()

func force_ignite_compartment_for_validation(compartment_id: String, intensity: float = 1.0) -> bool:
	if fire_suppression_state == null:
		return false
	var ok: bool = fire_suppression_state.ignite(compartment_id, intensity)
	_refresh_fire_zones()
	return ok
```

- [ ] **Step 4: Drive the fire tick in `_process`.** Where the old `fire_state.tick` was (~4259), and alongside the existing `fire_suppression_state.tick(...)` at ~1342-1343, **replace** that single-line tick with the contextual tick + zone refresh. Find the existing block:
```gdscript
	if fire_suppression_state != null:
		fire_suppression_state.tick(delta, {"powered_ratio": power_grid_state.get_allocation_ratio("stations")})
```
and replace with:
```gdscript
	if fire_suppression_state != null:
		if fire_suppression_state.tick(delta, _build_fire_context()):
			_refresh_fire_zones()
```

- [ ] **Step 5: Pair the lifecycle calls.** At every site that calls `_build_breach_seal_points()` (build at ~1801, ~3058, ~3621, ~5823) add `_seed_fires_from_damage()` (build only, once per fresh build — put it right before the first `_build_fire_zones()`) and `_build_fire_zones()`. At every `_clear_breach_seal_points()` site (~3055, ~6388) add `_clear_fire_zones()`. (Seed only on a genuine fresh build, not on reload-from-save where fires come from the restored summary — guard `_seed_fires_from_damage()` so it is not called on the save-restore path.)

- [ ] **Step 6: Delete `scripts/systems/fire_state.gd`.**

- [ ] **Step 7: Fix `scripts/validation/hazard_contract_smoke.gd`.** Remove the entire `--- FireState ---` block (lines ~25-55). Update the final print to `models=2 phase_timer_owners=%d wrong_kind_rejected=%d configure_dict=%d` and the header marker comment to `HAZARD CONTRACT PASS models=2 phase_timer_owners=1 wrong_kind_rejected=2 configure_dict=2`. (Now only ElectricalArc owns a PhaseTimer; Oxygen does not; Fire is gone.)

- [ ] **Step 8: Rewrite `scripts/validation/main_playable_slice_fire_smoke.gd`** to the new model (passable zones + presence + vent). Drop the REQ-010 critical-path placement guard (fire no longer blocks passability). New body:

```gdscript
extends SceneTree

## M7-B fire slice: fires render as PASSABLE per-compartment zones from the authoritative
## model; a breached compartment vent-extinguishes.
## Pass marker: MAIN PLAYABLE FIRE PASS passable=true present=true vent=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	if playable.fire_suppression_state == null:
		_fail("fire_suppression_state missing"); return
	# Force a fire and confirm a passable zone renders.
	playable.away_from_start = false
	playable.force_ignite_compartment_for_validation("engineering", 1.0)
	var zones: Array = playable.get_fire_zone_nodes_for_validation()
	if zones.is_empty():
		_fail("no fire zone node rendered for a burning compartment"); return
	var z = zones[0]
	if not (z is Area3D):
		_fail("fire zone should be an Area3D"); return
	# Passable: the zone must NOT carry a StaticBody collision blocker.
	if z is StaticBody3D:
		_fail("fire zone must be passable, not a StaticBody"); return
	# Vent: breach the compartment, tick, fire should clear.
	playable.force_hull_breach_for_validation("engineering", 0.7)
	playable.fire_suppression_state.tick(0.5, playable._build_fire_context())
	if playable.fire_suppression_state.is_burning("engineering"):
		_fail("breached compartment should vent-extinguish the fire"); return
	finished = true
	print("MAIN PLAYABLE FIRE PASS passable=true present=true vent=true")
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE FIRE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```
> Confirm `force_hull_breach_for_validation(cid, amount)` exists (used by M7-A's vitals smoke); if its signature differs, adapt the call.

- [ ] **Step 9: Run the affected smokes; verify PASS**
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hazard_contract_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_fire_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/golden_fire_zone_source_marker_smoke.gd
```
Expected: `HAZARD CONTRACT PASS models=2 phase_timer_owners=1 wrong_kind_rejected=2 configure_dict=2`; `MAIN PLAYABLE FIRE PASS passable=true present=true vent=true`; the golden marker smoke still PASSES unchanged (marker schema untouched).

- [ ] **Step 10: Commit**
```bash
git add scripts/procgen/playable_generated_ship.gd data/ship_systems/subsystem_tuning.json scripts/validation/hazard_contract_smoke.gd scripts/validation/main_playable_slice_fire_smoke.gd
git rm scripts/systems/fire_state.gd
git commit -m "feat(m7b): retire fire_state; authoritative compartment fire + passable zones"
```

---

### Task 8: Coordinator — fire teeth (vitals drain + ship-system damage)

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify (extend): `scripts/validation/main_playable_slice_fire_smoke.gd`

**Interfaces:**
- Consumes: `get_burning_compartments_for_validation`, `FIRE_COMPARTMENT_SYSTEM`, `FIRE_HEALTH_DRAIN_PER_SECOND`, `FIRE_SYSTEM_DAMAGE_PER_SECOND`, `ship_systems_manager.damage_system` (Task 3), `vitals_state` `fire_health_drain` channel (Task 4).
- Produces: vitals drain + system damage applied per frame while a compartment burns; seam `get_player_in_fire() -> bool`.

- [ ] **Step 1: Extend the slice smoke** with vitals + system assertions. After the vent block in `_validate`, before `finished = true`, add a fresh-fire scenario:

```gdscript
	# Teeth: a burning compartment drains vitals and damages its system.
	playable.threat_manager.threats.clear() if playable.threat_manager != null else null
	playable.force_ignite_compartment_for_validation("engineering", 1.0)
	playable.vitals_state.health = 90.0
	var sys_before: float = playable.ship_systems_manager.get_system("power").health()
	# Place the player inside the engineering fire zone.
	var ez = null
	for zn in playable.get_fire_zone_nodes_for_validation():
		if str(zn.get_meta("fire_compartment_id", "")) == "engineering":
			ez = zn
	if ez == null:
		_fail("no engineering fire zone to stand in"); return
	if playable.player != null and ez is Node3D:
		playable.player.global_position = (ez as Node3D).global_position
	var step: float = 1.0 / 30.0
	var elapsed: float = 0.0
	while elapsed < 2.0:
		playable._process(step)
		elapsed += step
	if playable.vitals_state.health >= 90.0:
		_fail("standing in fire should drain vitals"); return
	if playable.ship_systems_manager.get_system("power").health() >= sys_before:
		_fail("burning compartment should damage its system"); return
```
And update the marker to:
```gdscript
	print("MAIN PLAYABLE FIRE PASS passable=true present=true vent=true vitals_drain=true system_damage=true")
```

- [ ] **Step 2: Run; verify it fails** (no teeth applied yet).

- [ ] **Step 3: Implement teeth in the coordinator.** In `_process`, where the M7-A vitals context is assembled for `vitals_state.tick`, add a `fire_health_drain` term when the player overlaps a burning fire zone, and apply system damage per burning compartment. Add a helper and fold its output into the existing vitals context dict:

```gdscript
## Returns the intensity of the fire the player is currently standing in (0.0 if none).
func _player_fire_intensity() -> float:
	if player == null or fire_suppression_state == null:
		return 0.0
	for cid in fire_zone_nodes:
		var z = fire_zone_nodes[cid]
		if not is_instance_valid(z) or not (z is Node3D):
			continue
		if (z as Node3D).global_position.distance_to(player.global_position) <= 2.0:
			return fire_suppression_state.get_intensity(str(cid))
	return 0.0

## Applies fire degradation to the ship system housed in each burning compartment.
func _apply_fire_system_damage(delta: float) -> void:
	if fire_suppression_state == null or ship_systems_manager == null:
		return
	for cid in fire_suppression_state.get_burning_compartments():
		var sid: String = str(FIRE_COMPARTMENT_SYSTEM.get(str(cid), ""))
		if sid.is_empty():
			continue
		var intensity: float = fire_suppression_state.get_intensity(str(cid))
		ship_systems_manager.damage_system(sid, FIRE_SYSTEM_DAMAGE_PER_SECOND * intensity * delta)
```

In the vitals context assembly (the dict passed to `vitals_state.tick`), add:
```gdscript
		"fire_health_drain": FIRE_HEALTH_DRAIN_PER_SECOND * _player_fire_intensity(),
```
And call `_apply_fire_system_damage(delta)` once per `_process` right after the `fire_suppression_state.tick(...)` block from Task 7.

- [ ] **Step 4: Run; verify PASS** — `MAIN PLAYABLE FIRE PASS passable=true present=true vent=true vitals_drain=true system_damage=true`.
- [ ] **Step 5: Commit**
```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_fire_smoke.gd
git commit -m "feat(m7b): fire teeth - vitals drain + ship-system damage"
```

---

### Task 9: Coordinator — manual extinguish loop, recharge port, save/load

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/main_playable_fire_loop_smoke.gd`

**Interfaces:**
- Consumes: `FireSuppressionPoint` (Task 5), `ExtinguisherRechargePort` (Task 6), `ExtinguisherState` (Task 2).
- Produces: `extinguisher_state` owned by the coordinator; `fire_suppression_points` built/cleared + wired into both interact branches; one recharge port; nested save of `extinguisher_summary`; seams `get_fire_suppression_points_for_validation()`, `teleport_player_to_fire_suppression_point_for_validation(point)`, `get_extinguisher_state()`.

- [ ] **Step 1: Write the failing full-loop smoke** — `scripts/validation/main_playable_fire_loop_smoke.gd`:

```gdscript
extends SceneTree

## M7-B full loop (live scene): damaged system + oxygen ignites; player takes vitals
## damage; manual extinguish via the REAL interact dispatcher clears it (charge spent);
## still-damaged compartment re-ignites; repairing the system stops re-ignition;
## a powered recharge port refills the extinguisher.
## Pass marker:
##   MAIN PLAYABLE FIRE LOOP PASS ignite=true teeth=true extinguish=true reignite=true repair_stops=true recharge=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	if playable.fire_suppression_state == null or playable.get_extinguisher_state() == null:
		_fail("fire model / extinguisher missing"); return
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.away_from_start = false

	# Damage power (engineering's system) so engineering becomes ignitable; ensure oxygen.
	playable.life_support_expanded_state.oxygen_percent = 100.0
	for sub in playable.ship_systems_manager.get_system("power").subcomponents:
		sub.health = 0.1
	# Drive ignition via the model tick.
	var ctx_steps := 0
	while not playable.fire_suppression_state.is_burning("engineering") and ctx_steps < 600:
		playable.fire_suppression_state.tick(0.1, playable._build_fire_context())
		ctx_steps += 1
	if not playable.fire_suppression_state.is_burning("engineering"):
		_fail("damaged+oxygen never ignited engineering"); return
	playable._refresh_fire_zones()

	# Teeth.
	playable.vitals_state.health = 90.0
	var ez = _engineering_zone()
	if ez == null:
		_fail("no engineering fire zone"); return
	if playable.player != null:
		playable.player.global_position = ez.global_position
	for i in range(60):
		playable._process(1.0 / 30.0)
	if playable.vitals_state.health >= 90.0:
		_fail("fire did not drain vitals"); return

	# Manual extinguish via the REAL dispatcher.
	playable.get_extinguisher_state().charge = playable.get_extinguisher_state().max_charge
	if int(playable.inventory_state.get_quantity("fire_extinguisher")) < 1:
		playable.inventory_state.add_item("fire_extinguisher", 1)
	var points: Array = playable.get_fire_suppression_points_for_validation()
	if points.is_empty():
		_fail("no fire suppression point for the burning compartment"); return
	var fp = null
	for p in points:
		if str(p.compartment_id) == "engineering":
			fp = p
	if fp == null:
		_fail("no engineering suppression point"); return
	playable.teleport_player_to_fire_suppression_point_for_validation(fp)
	var charge_before: float = playable.get_extinguisher_state().charge
	playable._on_player_interact_requested(playable.player)
	if not (fp.channeling or fp.extinguished):
		_fail("interact dispatch did not start the extinguish channel (loop unreachable)"); return
	fp.advance_channel(10.0)
	if playable.fire_suppression_state.is_burning("engineering"):
		_fail("manual extinguish did not clear the fire"); return
	if playable.get_extinguisher_state().charge >= charge_before:
		_fail("extinguish should spend charge"); return

	# Re-ignition while still damaged.
	var reignited := false
	for i in range(600):
		playable.fire_suppression_state.tick(0.1, playable._build_fire_context())
		if playable.fire_suppression_state.is_burning("engineering"):
			reignited = true; break
	if not reignited:
		_fail("still-damaged compartment did not re-ignite"); return

	# Repair stops re-ignition.
	playable.fire_suppression_state.extinguish("engineering")
	for sub in playable.ship_systems_manager.get_system("power").subcomponents:
		sub.health = 1.0
	for i in range(200):
		playable.fire_suppression_state.tick(0.1, playable._build_fire_context())
	if playable.fire_suppression_state.is_burning("engineering"):
		_fail("repaired compartment kept re-igniting"); return

	# Recharge port refills when powered.
	var ext = playable.get_extinguisher_state()
	ext.charge = 0.0
	var port = playable.get_extinguisher_recharge_port_for_validation()
	if port == null:
		_fail("no recharge port present"); return
	port.set_powered(true)
	port.set_validation_player_in_range(playable.player)
	if playable.player != null:
		playable.player.global_position = port.global_position
	for i in range(60):
		port._process(1.0 / 30.0)
	if ext.charge <= 0.0:
		_fail("powered recharge port did not refill the extinguisher"); return

	finished = true
	print("MAIN PLAYABLE FIRE LOOP PASS ignite=true teeth=true extinguish=true reignite=true repair_stops=true recharge=true reachable=true")
	_cleanup_and_quit(0)

func _engineering_zone() -> Node3D:
	for zn in playable.get_fire_zone_nodes_for_validation():
		if str(zn.get_meta("fire_compartment_id", "")) == "engineering" and zn is Node3D:
			return zn as Node3D
	return null

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE FIRE LOOP FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run; verify it fails** (no extinguisher_state / points / port / seams yet).

- [ ] **Step 3: Add coordinator members** near the fire declarations (Task 7 region):

```gdscript
const ExtinguisherStateScript := preload("res://scripts/systems/extinguisher_state.gd")
const FireSuppressionPointScript := preload("res://scripts/tools/fire_suppression_point.gd")
const ExtinguisherRechargePortScript := preload("res://scripts/tools/extinguisher_recharge_port.gd")

var extinguisher_state                  # ExtinguisherState
var fire_suppression_points: Array = []
var extinguisher_recharge_port          # ExtinguisherRechargePort
```

- [ ] **Step 4: Construct the extinguisher** where the other ship-systems models are built (near `fire_suppression_state = FireSuppressionStateScript.new()`, ~1304):
```gdscript
	extinguisher_state = ExtinguisherStateScript.new()
	extinguisher_state.configure(tuning.get("extinguisher", {}))
```
(Add an `"extinguisher"` block to `subsystem_tuning.json` is optional; defaults apply if absent.)

- [ ] **Step 5: Build/clear FireSuppressionPoints + recharge port** (helpers near `_build_fire_zones`):

```gdscript
func _build_fire_suppression_points() -> void:
	_clear_fire_suppression_points()
	if fire_suppression_state == null:
		return
	var burning: Array = fire_suppression_state.get_burning_compartments()
	if burning.is_empty():
		return
	var positions: Array = _distributed_room_positions()
	if positions.is_empty():
		return
	var idx: int = 0
	for cid in burning:
		var pos: Vector3 = positions[idx % positions.size()]
		idx += 1
		var fp = FireSuppressionPointScript.new()
		fp.configure(str(cid), fire_suppression_state, extinguisher_state, inventory_state, player_progression, pos, 4.0, "fire_extinguisher", 1.8)
		if not fp.fire_extinguished.is_connected(_on_fire_extinguished):
			fp.fire_extinguished.connect(_on_fire_extinguished)
		_attach_zone_to_active_ship(fp)
		fire_suppression_points.append(fp)

func _clear_fire_suppression_points() -> void:
	for fp in fire_suppression_points:
		if is_instance_valid(fp):
			var parent = fp.get_parent()
			if parent != null and is_instance_valid(parent):
				parent.remove_child(fp)
			fp.queue_free()
	fire_suppression_points.clear()

func _on_fire_extinguished(_compartment_id: String) -> void:
	_refresh_fire_zones()
	_build_fire_suppression_points()

func _build_extinguisher_recharge_port() -> void:
	_clear_extinguisher_recharge_port()
	if extinguisher_state == null or away_from_start:
		return
	var positions: Array = _distributed_room_positions()
	var pos: Vector3 = positions[0] if not positions.is_empty() else Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	var port = ExtinguisherRechargePortScript.new()
	port.configure(extinguisher_state, pos, 1.8)
	_attach_zone_to_active_ship(port)
	extinguisher_recharge_port = port

func _clear_extinguisher_recharge_port() -> void:
	if is_instance_valid(extinguisher_recharge_port):
		var parent = extinguisher_recharge_port.get_parent()
		if parent != null and is_instance_valid(parent):
			parent.remove_child(extinguisher_recharge_port)
		extinguisher_recharge_port.queue_free()
	extinguisher_recharge_port = null
```

Make `_refresh_fire_zones()` also call `_build_fire_suppression_points()` when the burning set changes (so points track fires). Pair `_build_extinguisher_recharge_port()` / `_clear_extinguisher_recharge_port()` at the same lifecycle sites as `_build_fire_zones()`.

- [ ] **Step 6: Power the recharge port + wire interact.** In `_process`, near the crafting-station `set_powered` loop (~1351), add:
```gdscript
	if is_instance_valid(extinguisher_recharge_port):
		extinguisher_recharge_port.set_powered(power_grid_state.get_allocation_ratio("stations") > 0.0)
```
In `_on_player_interact_requested`, add a FireSuppressionPoint loop immediately **after** the `breach_seal_points` loop in **both** branches (away ~3838 and home ~3863):
```gdscript
		# M7-B: fire suppression points share the survival-critical precedence.
		for fp in fire_suppression_points:
			if is_instance_valid(fp) and fp.try_start(player_body):
				return
```

- [ ] **Step 7: Save/load.** In the ship-systems summary assembly (~1371) add:
```gdscript
		"extinguisher_summary": extinguisher_state.get_summary() if extinguisher_state != null else {},
```
and in the restore path (~5714, next to `fire_suppression_state.apply_summary(...)`) add:
```gdscript
		if extinguisher_state != null:
			extinguisher_state.apply_summary(snapshot.ship_systems_summary.get("extinguisher_summary", {}))
```
After restoring `fire_suppression_state`, call `_refresh_fire_zones()` and `_build_fire_suppression_points()` so restored fires render. Confirm no top-level `SUMMARY_FIELDS` change.

- [ ] **Step 8: Add the remaining validation seams:**
```gdscript
func get_extinguisher_state():
	return extinguisher_state

func get_fire_suppression_points_for_validation() -> Array:
	return fire_suppression_points.duplicate()

func get_extinguisher_recharge_port_for_validation():
	return extinguisher_recharge_port

func teleport_player_to_fire_suppression_point_for_validation(point) -> bool:
	if player == null or point == null or not is_instance_valid(point):
		return false
	if player is Node3D and point is Node3D:
		(player as Node3D).global_position = (point as Node3D).global_position
		return true
	return false
```

- [ ] **Step 9: Run; verify PASS** — `MAIN PLAYABLE FIRE LOOP PASS ignite=true teeth=true extinguish=true reignite=true repair_stops=true recharge=true reachable=true`. Also re-run the slice + save/load smokes to confirm no regression:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_fire_loop_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_fire_smoke.gd
```

- [ ] **Step 10: Commit**
```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_fire_loop_smoke.gd
git commit -m "feat(m7b): manual extinguish loop, recharge port, nested save"
```

---

### Task 10: Docs, ADR, validation registration, full regression

**Files:**
- Create: `docs/game/adr/0041-fire-as-persistent-compartment-hazard.md`
- Modify: `docs/game/adr/0005-multi-hazard-architecture.md`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/game/system_completion_audit.md`

- [ ] **Step 1: Write ADR `0041-fire-as-persistent-compartment-hazard.md`** documenting: fire leaves the ADR-0005 phase-timer cyclic contract; becomes a persistent, compartment-keyed, resource/repair-coupled hazard owned by `FireSuppressionState` (joins oxygen as a non-timer hazard); the symptom-of-damage ignition rule + re-ignition; the three extinguish paths (manual extinguisher w/ charge + recharge port, powered auto-suppression, breach/vacuum vent); spread; arc cascade; the vitals + ship-system couplings; deterministic accumulators. Reference the spec.

- [ ] **Step 2: Amend `0005-multi-hazard-architecture.md`** with a short note that FireState has been retired and fire migrated to `FireSuppressionState` per ADR-0041; the timer-hazard set is now ElectricalArc only (oxygen and fire are non-timer hazards).

- [ ] **Step 3: Register smokes in `docs/game/06_validation_plan.md`.** Add the new smoke commands + expected markers:
  - `fire_suppression_state_smoke.gd` → `FIRE SUPPRESSION STATE PASS ...`
  - `extinguisher_state_smoke.gd` → `EXTINGUISHER STATE PASS ...`
  - `ship_systems_damage_smoke.gd` → `SHIP SYSTEMS DAMAGE PASS ...`
  - `fire_suppression_point_smoke.gd` → `FIRE SUPPRESSION POINT PASS ...`
  - `extinguisher_recharge_port_smoke.gd` → `EXTINGUISHER RECHARGE PORT PASS ...`
  - `main_playable_fire_loop_smoke.gd` → `MAIN PLAYABLE FIRE LOOP PASS ...`
  - Update the `main_playable_slice_fire_smoke.gd` expected marker to the new `MAIN PLAYABLE FIRE PASS passable=true present=true vent=true vitals_drain=true system_damage=true`.
  - Update the `hazard_contract_smoke.gd` expected marker to `models=2 phase_timer_owners=1 wrong_kind_rejected=2 configure_dict=2`.
  - **Remove** the retired `fire_state_smoke.gd` entry.
  - Bump the `commands=NN` count (current is 43; net change: −1 removed +6 added = `commands=48`; verify by counting the bundle).
  - Note: the bundle hardcodes macOS `ROOT`/`GODOT` (lines ~31-32). Run it by sed-substituting **quoted** Windows paths (the path contains spaces): `ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"`.

- [ ] **Step 4: Re-grade the audit `docs/game/system_completion_audit.md`.** Move `fire_suppression_state` from 🔴 to 🟢 (now the authoritative fire hazard with sources, sinks, and a full player loop). Update rollup item #5 (fire-suppression is no longer a HUD shadow). Note the deferred follow-ups (B2 vent control, fire-consumes-oxygen, extinguisher/sealant acquisition, derelict-side ports, door-gated spread).

- [ ] **Step 5: REQ-010 note.** In `docs/game/05_requirements.md` (and/or the hazard_variety feature doc), note that fire no longer blocks passability, so REQ-010's "non-critical side room" placement constraint is obsolete for fire (it applied to the impassable timed zone). Keep the requirement history; mark the constraint superseded by ADR-0041.

- [ ] **Step 6: Run the FULL regression bundle.** Use the bash block in `06_validation_plan.md` with quoted Windows `GODOT`/`ROOT`. Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=48 clean_output=true` (or the verified count). Fix any unexpected `ERROR:`/`WARNING:`.

- [ ] **Step 7: Commit**
```bash
git add docs/game/adr/0041-fire-as-persistent-compartment-hazard.md docs/game/adr/0005-multi-hazard-architecture.md docs/game/06_validation_plan.md docs/game/system_completion_audit.md docs/game/05_requirements.md
git commit -m "docs(m7b): ADR-0041, validation registration, audit re-grade"
```

---

## Self-Review

**Spec coverage:**
- Authoritative compartment fire model → Task 1. ✅
- Retire `fire_state` → Task 7. ✅
- Three extinguish paths: manual (Task 5 node + Task 9 wiring), powered auto-suppression (Task 1 tick), vent (Task 1 tick + Task 7 context). ✅
- Extinguisher charge + recharge port → Tasks 2, 6, 9. ✅
- Teeth: vitals (Task 4 channel + Task 8 wiring) + system damage (Task 3 method + Task 8 wiring). ✅
- Spread (Task 1), arc cascade (Task 1 + Task 7 context). ✅
- Ignition = symptom of damage + re-ignition (Task 1 tick + Task 7 `_build_fire_context`/`_seed_fires_from_damage`). ✅
- Save/load nested, no top-level field change → Task 9. ✅
- ADR 0041 + amend 0005 + contract smoke → Tasks 7, 10. ✅
- Validation registration + audit re-grade + full regression → Task 10. ✅
- Blast-radius callouts (dual-branch interact, golden marker untouched, fire_state sweep) → Tasks 7, 9. ✅

**Placeholder scan:** No TBD/TODO; all code steps carry full code or precise anchors. Coordinator edits reference patterns to find (line numbers are drift-warned) because the 6900-line file cannot be reproduced verbatim — this matches the M7-A plan's approach.

**Type consistency:** `FireSuppressionState` methods (`ignite/extinguish/is_burning/get_burning_compartments/get_intensity/tick/get_summary/apply_summary`) are used consistently across Tasks 1, 5, 7, 8, 9. `ExtinguisherState` (`has_charge_for_use/consume_use/recharge`) consistent across Tasks 2, 5, 6, 9. Context keys (`powered_ratio`, `ship_oxygen_present`, `breached_compartments`, `damaged_compartments`, `arc_arcing`) consistent between Task 1's tick and Task 7's `_build_fire_context`. Seam names consistent between coordinator (Tasks 7-9) and smokes.

**Open verification items for the implementer (flagged, not blocking):**
- Confirm `InventoryState` API (`add_item`, `get_quantity`, no `configure` needed) and `force_hull_breach_for_validation` signature before Tasks 5/7 (used by M7-A precedent).
- Confirm `_distributed_room_positions()`, `repair_point_root`, `PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR`, `current_ship`/`lifeboat_ship` are the right anchors in the current coordinator (they are referenced by `_build_breach_seal_points`).
- Verify the exact regression `commands=` count after registration.
