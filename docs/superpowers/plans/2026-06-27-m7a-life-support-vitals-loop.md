# M7-A · Life-support ambient atmosphere → vitals — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the loop "hull breaches → hub ambient atmosphere fails → drains player vitals while aboard → player keeps power on life-support AND seals breaches to survive," and cut the dead `shield_state` model.

**Architecture:** No new *model* classes — promote the existing HUD-only `LifeSupportState`/`HullIntegrityState` by adding read-only accessors that feed the vitals context the coordinator already assembles (same pattern `radiation_state` uses). Add one new *interaction* node (`BreachSealPoint`) modeled on the existing `RepairPoint`. Hull damage source for A is config-only (pre-damaged compartments at run start); the `damage_compartment()` seam stays open for future sources.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes (the project's test harness).

## Global Constraints

- Godot binary: `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (use the `_console` build).
- Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`.
- Run smokes headless: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke>.gd`.
- **`--script` can exit 0 even on parse/load errors** — never trust the exit code alone; confirm the `... PASS ...` marker is printed and no parse error/unexpected `ERROR:`/`WARNING:` appears.
- Allowlisted baseline noise (ignore): `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`.
- Typed GDScript for new code. Resources/RefCounted are data; Nodes are behavior (Model/Node separation).
- Conventional Commits. Branch: `feat/m7a-life-support-vitals` (already created).
- Validation is the definition of done: no completion claim without fresh PASS-marker output.

## File Structure

- `scripts/systems/life_support_state.gd` — MODIFY: add atmosphere tunables + `get_health_drain_per_second()` + `get_thirst_multiplier()` + breach-leak-while-powered in `tick()`; expose tunables in `get_summary()`.
- `scripts/validation/life_support_state_smoke.gd` — MODIFY: assert the new accessors + breach leak.
- `scripts/systems/shield_state.gd` — DELETE (+ `.uid`).
- `data/ship_systems/subsystem_tuning.json` — MODIFY: remove the dead `"shields"` block; add atmosphere tunables under `life_support` (optional — defaults exist in code).
- `data/ship_systems/hull_compartments.json` — MODIFY: pre-damage one compartment (source #4).
- `scripts/procgen/playable_generated_ship.gd` — MODIFY: remove all `shield_state` model wiring; add the atmosphere→vitals context wiring; build/clear/handle `BreachSealPoint`s.
- `scripts/tools/breach_seal_point.gd` — CREATE (+ used via preload): new interaction node modeled on `repair_point.gd`.
- `scripts/validation/breach_seal_point_smoke.gd` — CREATE: pure/seam test of the seal node.
- `scripts/validation/main_playable_life_support_vitals_smoke.gd` — CREATE: live-scene proof of the full loop.
- `docs/game/06_validation_plan.md` — MODIFY: add the two new smoke markers + command count.
- `docs/game/system_completion_audit.md` — MODIFY: re-grade M7 life-support / hull / shield rows.

---

### Task 1: LifeSupportState teeth — atmosphere drain + thirst accessors + breach leak

**Files:**
- Modify: `scripts/systems/life_support_state.gd`
- Test: `scripts/validation/life_support_state_smoke.gd`

**Interfaces:**
- Produces: `LifeSupportState.get_health_drain_per_second() -> float` (0.0 when atmosphere nominal; rises as O2 falls below `atmosphere_safe_oxygen` or CO2 rises above `atmosphere_safe_co2`; max = `max_atmosphere_health_drain`). `LifeSupportState.get_thirst_multiplier() -> float` (1.0 inside the temperature comfort band, up to `max_atmosphere_thirst_mult` outside). `tick(delta, {powered_ratio, breach_count, recycled_water})` now also leaks atmosphere per unsealed breach **while powered**.

- [ ] **Step 1: Write the failing test** — append to `scripts/validation/life_support_state_smoke.gd` (inside `_initialize()`, before the final pass print). Add these assertions:

```gdscript
	# --- M7-A: atmosphere teeth ---
	var teeth := LifeSupportStateScript.new()
	teeth.configure({})
	# Nominal atmosphere -> no health drain, neutral thirst.
	if teeth.get_health_drain_per_second() != 0.0:
		_fail("nominal atmosphere should not drain health")
		return
	if absf(teeth.get_thirst_multiplier() - 1.0) > 0.0001:
		_fail("nominal temperature should give thirst mult 1.0")
		return
	# Severe atmosphere -> positive, increasing health drain.
	teeth.oxygen_percent = 30.0
	teeth.co2_percent = 20.0
	var mild_drain: float = teeth.get_health_drain_per_second()
	if mild_drain <= 0.0:
		_fail("unsafe atmosphere should drain health (got %.3f)" % mild_drain)
		return
	teeth.oxygen_percent = 5.0
	teeth.co2_percent = 60.0
	if teeth.get_health_drain_per_second() <= mild_drain:
		_fail("worse atmosphere should drain more health")
		return
	# Temperature outside the comfort band raises the thirst multiplier.
	teeth.temperature_c = teeth.nominal_temperature_c + 40.0
	if teeth.get_thirst_multiplier() <= 1.0:
		_fail("extreme temperature should raise thirst mult")
		return
	# Unsealed breaches leak atmosphere EVEN while powered (the "race to seal").
	var leaky := LifeSupportStateScript.new()
	leaky.configure({})
	leaky.oxygen_percent = 100.0
	leaky.co2_percent = 2.0
	leaky.tick(2.0, {"powered_ratio": 1.0, "breach_count": 3, "recycled_water": 0.0})
	if leaky.oxygen_percent >= 100.0:
		_fail("breaches should leak oxygen even while powered")
		return
	if leaky.co2_percent <= 2.0:
		_fail("breaches should raise co2 even while powered")
		return
```

- [ ] **Step 2: Run test to verify it fails**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_support_state_smoke.gd
```
Expected: FAIL — parse error "Invalid call. Nonexistent function 'get_health_drain_per_second'" (method not defined yet).

- [ ] **Step 3: Add tunable fields** — in `scripts/systems/life_support_state.gd`, after the existing `var life_support_power_threshold` declaration (line ~15), add:

```gdscript
# M7-A atmosphere-teeth tunables. Defaults are the values used by the slice;
# get_summary() exposes them so smokes can assert the tuning in use.
var atmosphere_safe_oxygen: float = 50.0          # O2 % at/above which there is no drain
var atmosphere_safe_co2: float = 15.0             # CO2 % at/below which there is no drain
var max_atmosphere_health_drain: float = 5.0      # hp/sec when atmosphere is fully fouled
var atmosphere_temp_comfort_band: float = 8.0     # +/- degrees C around nominal with no thirst penalty
var max_atmosphere_thirst_mult: float = 1.5       # thirst multiplier at temperature extreme
var breach_oxygen_leak_per_second: float = 1.5    # per-breach atmosphere loss while powered
```

- [ ] **Step 4: Read the tunables in `configure()`** — in the `configure()` body, after the existing `life_support_power_threshold = ...` line, add:

```gdscript
	atmosphere_safe_oxygen = clampf(float(config.get("atmosphere_safe_oxygen", 50.0)), 1.0, 100.0)
	atmosphere_safe_co2 = clampf(float(config.get("atmosphere_safe_co2", 15.0)), 0.0, 99.0)
	max_atmosphere_health_drain = maxf(0.0, float(config.get("max_atmosphere_health_drain", 5.0)))
	atmosphere_temp_comfort_band = maxf(0.1, float(config.get("atmosphere_temp_comfort_band", 8.0)))
	max_atmosphere_thirst_mult = maxf(1.0, float(config.get("max_atmosphere_thirst_mult", 1.5)))
	breach_oxygen_leak_per_second = maxf(0.0, float(config.get("breach_oxygen_leak_per_second", 1.5)))
```

- [ ] **Step 5: Add the breach leak to the powered branch of `tick()`** — in `tick()`, inside the `if powered:` branch, after the existing `temperature_c = lerpf(...)` line, add:

```gdscript
		# M7-A: unsealed breaches leak atmosphere even while powered, so the player
		# must SEAL them (not just keep power on). Additive + gated on breach_count,
		# so the breach_count==0 recovery assertions are unaffected.
		if breach_count > 0:
			var leak: float = breach_oxygen_leak_per_second * float(breach_count) * delta
			oxygen_percent = maxf(0.0, oxygen_percent - leak)
			co2_percent = minf(100.0, co2_percent + leak)
```

- [ ] **Step 6: Add the two accessors** — add these methods to `scripts/systems/life_support_state.gd` (e.g. after `is_nominal()`):

```gdscript
# M7-A: per-second health drain the failing atmosphere inflicts on the player.
# The worse of the O2-deficit and CO2-excess severities governs (max, not sum),
# scaled to max_atmosphere_health_drain. 0.0 when the atmosphere is nominal.
func get_health_drain_per_second() -> float:
	var o2_deficit: float = clampf((atmosphere_safe_oxygen - oxygen_percent) / atmosphere_safe_oxygen, 0.0, 1.0)
	var co2_excess: float = clampf((co2_percent - atmosphere_safe_co2) / (100.0 - atmosphere_safe_co2), 0.0, 1.0)
	return maxf(o2_deficit, co2_excess) * max_atmosphere_health_drain

# M7-A: thirst multiplier from ambient temperature. 1.0 inside the comfort band,
# ramping to max_atmosphere_thirst_mult one band-width outside it.
func get_thirst_multiplier() -> float:
	var deviation: float = absf(temperature_c - nominal_temperature_c)
	if deviation <= atmosphere_temp_comfort_band:
		return 1.0
	var over: float = clampf((deviation - atmosphere_temp_comfort_band) / atmosphere_temp_comfort_band, 0.0, 1.0)
	return 1.0 + over * (max_atmosphere_thirst_mult - 1.0)
```

- [ ] **Step 7: Expose tunables in `get_summary()`** — add these keys to the dictionary returned by `get_summary()`:

```gdscript
		"atmosphere_safe_oxygen": atmosphere_safe_oxygen,
		"atmosphere_safe_co2": atmosphere_safe_co2,
		"max_atmosphere_health_drain": max_atmosphere_health_drain,
		"atmosphere_temp_comfort_band": atmosphere_temp_comfort_band,
		"max_atmosphere_thirst_mult": max_atmosphere_thirst_mult,
		"breach_oxygen_leak_per_second": breach_oxygen_leak_per_second,
```

- [ ] **Step 8: Run test to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_support_state_smoke.gd
```
Expected: PASS marker printed (the smoke's existing `LIFE SUPPORT STATE ... PASS` line), no parse errors, only allowlisted noise.

- [ ] **Step 9: Commit**

```bash
git add scripts/systems/life_support_state.gd scripts/validation/life_support_state_smoke.gd
git commit -m "feat(survival): give life-support atmosphere teeth (vitals drain + breach leak)"
```

---

### Task 2: Cut the dead `shield_state` model

**Files:**
- Delete: `scripts/systems/shield_state.gd`, `scripts/systems/shield_state.gd.uid`
- Modify: `scripts/procgen/playable_generated_ship.gd`, `data/ship_systems/subsystem_tuning.json`

**Interfaces:**
- Consumes: nothing. Produces: nothing. Pure removal. The `"shields"` **power-allocation channel** in `power_grid_state.gd` / `power_budget_tables.json` / `power_grid_state_smoke.gd` is **intentionally left intact** (removing it would re-balance the working power grid — out of scope). No HUD consumer reads `shield_state_summary` (verified).

- [ ] **Step 1: Delete the model files**

```bash
git rm scripts/systems/shield_state.gd scripts/systems/shield_state.gd.uid
```

- [ ] **Step 2: Remove the preload** — in `scripts/procgen/playable_generated_ship.gd`, delete the line:

```gdscript
const ShieldStateScript := preload("res://scripts/systems/shield_state.gd")
```

- [ ] **Step 3: Remove the field** — delete the declaration:

```gdscript
var shield_state  # ShieldState
```

- [ ] **Step 4: Remove instantiation + configure** — delete these two lines (~1307–1308):

```gdscript
	shield_state = ShieldStateScript.new()
	shield_state.configure(tuning.get("shields", {}))
```

- [ ] **Step 5: Remove the tick** — delete the block (~1334–1335):

```gdscript
	if shield_state != null:
		shield_state.tick(delta, {"powered_ratio": power_grid_state.get_allocation_ratio("shields")})
```

- [ ] **Step 6: Remove the summary line** — in `_expanded_ship_systems_summary()`, delete the line:

```gdscript
		"shield_state_summary": shield_state.get_summary() if shield_state != null else {},
```

- [ ] **Step 7: Remove the dead tuning block** — in `data/ship_systems/subsystem_tuning.json`, delete the entire `"shields": { ... }` object (and the trailing comma on the preceding `"propulsion"` block so the JSON stays valid).

- [ ] **Step 8: Verify no dangling references** — run:

```bash
grep -rn "shield_state\|ShieldState" scripts/ data/
```
Expected: **no matches** (the remaining `shield` hits in `power_grid_state.gd`, `power_budget_tables.json`, `power_grid_state_smoke.gd`, `material_definitions.json`, `recipe_definitions.json` are the power channel + item data, which are intentionally retained — confirm none say `shield_state`/`ShieldState`).

- [ ] **Step 9: Parse-check the coordinator + power grid still pass** — run an existing smoke that exercises the coordinator and the power grid:

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/power_grid_state_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_support_state_smoke.gd
```
Expected: both print their PASS markers, no parse error referencing `shield_state`, only allowlisted noise.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor(ship-systems): cut dead shield_state model (no on-foot role)"
```

---

### Task 3: Wire atmosphere → vitals + pre-damage the hull (live drain loop)

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (vitals-context block ~4211–4226), `data/ship_systems/hull_compartments.json`
- Modify: `scripts/systems/vitals_state.gd` (consume the new context channel)
- Test: `scripts/validation/main_playable_life_support_vitals_smoke.gd` (new)

**Interfaces:**
- Consumes: `LifeSupportState.get_health_drain_per_second()` / `get_thirst_multiplier()` (Task 1); existing `away_from_start` flag; existing `set_manual_power_route_for_validation()` / `force_hull_breach_for_validation()` seams.
- Produces: `VitalsState.tick` now reads `context["atmosphere_health_drain"]` (added to health drain, same handling as `radiation_health_drain`). New live-scene PASS marker: `MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true reachable=true`.

- [ ] **Step 1: Write the failing test** — create `scripts/validation/main_playable_life_support_vitals_smoke.gd`:

```gdscript
extends SceneTree

## M7-A loop proof (live scene): a pre-damaged hull + unpowered life support fouls the
## hub's ambient atmosphere, which drains the player's health WHILE ABOARD; the drain does
## NOT apply while away on a derelict; restoring power halts it.
##
## Pass marker:
##   MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
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
	if playable.vitals_state == null or playable.life_support_expanded_state == null or playable.hull_integrity_state == null:
		_fail("vitals / life_support / hull missing")
		return

	# Aboard the hub, cut power to life support and foul the atmosphere via a real breach.
	playable.away_from_start = false
	playable.set_manual_power_route_for_validation("life_support", 0.0)
	playable.force_hull_breach_for_validation("cargo", 0.7)
	playable.life_support_expanded_state.oxygen_percent = 10.0
	playable.life_support_expanded_state.co2_percent = 60.0
	if playable.life_support_expanded_state.get_health_drain_per_second() <= 0.0:
		_fail("fouled atmosphere should report a health drain")
		return

	# Drive the LIVE coordinator vitals tick for a span; health must drop while aboard.
	playable.vitals_state.health = 90.0
	var aboard_before: float = playable.vitals_state.health
	_pump_vitals(2.0)
	var aboard_after: float = playable.vitals_state.health
	if aboard_after >= aboard_before:
		_fail("health should drop from fouled atmosphere while aboard (%.2f -> %.2f)" % [aboard_before, aboard_after])
		return

	# Away on a derelict: the hub atmosphere must NOT bite.
	playable.away_from_start = true
	playable.vitals_state.health = 90.0
	var away_before: float = playable.vitals_state.health
	_pump_vitals(2.0)
	var away_after: float = playable.vitals_state.health
	if away_after < away_before - 0.001:
		_fail("hub atmosphere should not drain health while away (%.2f -> %.2f)" % [away_before, away_after])
		return

	# Restore power + a clean atmosphere aboard: drain halts.
	playable.away_from_start = false
	playable.set_manual_power_route_for_validation("life_support", 100.0)
	playable.life_support_expanded_state.oxygen_percent = 100.0
	playable.life_support_expanded_state.co2_percent = 2.0
	playable.vitals_state.health = 90.0
	var recover_before: float = playable.vitals_state.health
	_pump_vitals(1.0)
	var recover_after: float = playable.vitals_state.health
	if recover_after < recover_before - 0.001:
		_fail("health should not drop with restored power + clean atmosphere (%.2f -> %.2f)" % [recover_before, recover_after])
		return

	finished = true
	print("MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true reachable=true aboard=%.2f->%.2f" % [aboard_before, aboard_after])
	_cleanup_and_quit(0)

# Pumps the coordinator's own _process for `seconds` of simulated time at a fixed step,
# so the live vitals/atmosphere tick path (not the model in isolation) does the work.
func _pump_vitals(seconds: float) -> void:
	var step: float = 1.0 / 30.0
	var elapsed: float = 0.0
	while elapsed < seconds:
		playable._process(step)
		elapsed += step

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
	push_error("MAIN PLAYABLE LIFE SUPPORT VITALS FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_life_support_vitals_smoke.gd
```
Expected: FAIL — `aboard_after >= aboard_before` (atmosphere drain is not wired into vitals yet, so health does not drop).

- [ ] **Step 3: Consume the new channel in `VitalsState`** — in `scripts/systems/vitals_state.gd`, in `tick()`, the health-drain block currently reads:

```gdscript
		var h_drain: float = health_drain_rate * delta_seconds
		if context.has("radiation_health_drain"):
			h_drain += float(context.get("radiation_health_drain", 0.0)) * delta_seconds
```
Add a second contribution immediately after the radiation line:

```gdscript
		if context.has("atmosphere_health_drain"):
			h_drain += float(context.get("atmosphere_health_drain", 0.0)) * delta_seconds
```
Also update the `## context keys used by downstream systems:` doc comment to list `"atmosphere_health_drain" -> float (added to health drain when the hub atmosphere is fouled)`.

- [ ] **Step 4: Assemble + gate the channel in the coordinator** — in `scripts/procgen/playable_generated_ship.gd`, the vitals-context block (~4211–4226). Replace it with:

```gdscript
	if vitals_state != null:
		var temp_mult: float = 1.0
		if body_temperature_state != null:
			temp_mult = body_temperature_state.get_thirst_multiplier()
		var rad_drain: float = 0.0
		if radiation_state != null:
			rad_drain = radiation_state.get_health_drain_per_second()
		var status_mult: float = 1.0
		if status_effects_state != null:
			status_mult = status_effects_state.get_modifier("stamina_recovery")
		# M7-A: the hub's failing ambient atmosphere bites only while ABOARD the hub
		# (away on a derelict, the personal oxygen / radiation / body-temp hazards own it).
		var atmo_drain: float = 0.0
		if life_support_expanded_state != null and not away_from_start:
			atmo_drain = life_support_expanded_state.get_health_drain_per_second()
			temp_mult *= life_support_expanded_state.get_thirst_multiplier()
		vitals_state.tick(delta, {
			"temperature_thirst_mult": temp_mult,
			"radiation_health_drain": rad_drain,
			"atmosphere_health_drain": atmo_drain,
			"status_stamina_recovery_mult": status_mult,
			"moving": player != null and player.has_method("is_moving") and player.is_moving(),
		})
```

- [ ] **Step 5: Pre-damage a compartment at run start** — in `data/ship_systems/hull_compartments.json`, change the `cargo` entry so the hub starts with a breach the player must seal (source #4):

```json
    {"compartment_id": "cargo", "health": 0.3, "breach_open": true, "isolation_rating": 0.6}
```
(Leave `bridge`, `engineering`, `hydroponics` nominal so the start is pressured but survivable.)

- [ ] **Step 6: Run test to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_life_support_vitals_smoke.gd
```
Expected: `MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true reachable=true ...`, only allowlisted noise.

- [ ] **Step 7: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/systems/vitals_state.gd data/ship_systems/hull_compartments.json scripts/validation/main_playable_life_support_vitals_smoke.gd
git commit -m "feat(survival): hub atmosphere drains vitals while aboard (M7-A loop live)"
```

---

### Task 4: `BreachSealPoint` interaction node

**Files:**
- Create: `scripts/tools/breach_seal_point.gd`
- Test: `scripts/validation/breach_seal_point_smoke.gd`

**Interfaces:**
- Consumes: `HullIntegrityState` (calls `seal_compartment(compartment_id, repair_amount)`), `InventoryState` (sealant precheck), optional `PlayerProgressionState`.
- Produces: `class_name BreachSealPoint extends Area3D`. `configure(p_compartment_id, p_hull_state, p_inventory_state, p_player_progression, world_position, p_seal_seconds, p_required_item, p_seal_amount, radius)`. Signals `breach_sealed(compartment_id)` and `seal_blocked(compartment_id, reason)`. Methods `try_start(player_body) -> bool` and `advance_channel(delta)` (deterministic for smokes), mirroring `RepairPoint`.

- [ ] **Step 1: Write the failing test** — create `scripts/validation/breach_seal_point_smoke.gd`:

```gdscript
extends SceneTree

## M7-A: the BreachSealPoint channel consumes a sealant and seals a hull compartment.
## Pass marker: BREACH SEAL POINT PASS sealed=true breach_cleared=true

const BreachSealPointScript := preload("res://scripts/tools/breach_seal_point.gd")
const HullIntegrityStateScript := preload("res://scripts/systems/hull_integrity_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

var finished: bool = false

func _initialize() -> void:
	var hull := HullIntegrityStateScript.new()
	hull.configure({"compartments": [{"compartment_id": "cargo", "health": 0.3, "breach_open": true, "isolation_rating": 0.6}]})
	if hull.get_breach_count() != 1:
		_fail("setup: cargo should start breached")
		return
	var inv := InventoryStateScript.new()
	inv.configure({})
	inv.add_item("hull_sealant", 1)

	var sealed_signals: Array = []
	var point := BreachSealPointScript.new()
	point.configure("cargo", hull, inv, null, Vector3.ZERO, 4.0, "hull_sealant", 1.0, 1.8)
	point.breach_sealed.connect(func(cid): sealed_signals.append(cid))
	get_root().add_child(point)

	var player := PlayerControllerScript.new()
	get_root().add_child(player)
	player.global_position = Vector3.ZERO
	point.set_validation_player_in_range(player)

	if not point.try_start(player):
		_fail("try_start should succeed with sealant in range")
		return
	# Drive the channel deterministically to completion.
	point.advance_channel(5.0)

	if sealed_signals.size() != 1:
		_fail("breach_sealed should have fired once (got %d)" % sealed_signals.size())
		return
	if hull.get_breach_count() != 0:
		_fail("compartment should be sealed (breach_count=%d)" % hull.get_breach_count())
		return
	if int(inv.get_quantity("hull_sealant")) != 0:
		_fail("sealant should have been consumed")
		return

	finished = true
	print("BREACH SEAL POINT PASS sealed=true breach_cleared=true")
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("BREACH SEAL POINT FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/breach_seal_point_smoke.gd
```
Expected: FAIL — cannot load `res://scripts/tools/breach_seal_point.gd` (file does not exist).

- [ ] **Step 3: Create the node** — create `scripts/tools/breach_seal_point.gd`:

```gdscript
extends Area3D
class_name BreachSealPoint

## A spatial, item-gated, timed seal node bound to one hull compartment of a
## HullIntegrityState. Modeled on RepairPoint: interacting starts a channel that ticks in
## this node's OWN _process; leaving range cancels with no item loss; completing consumes
## the sealant and seals the compartment.

signal breach_sealed(compartment_id: String)
signal seal_blocked(compartment_id: String, reason: String)

var compartment_id: String = ""
var hull_state                          # HullIntegrityState
var inventory_state                     # InventoryState
var player_progression                  # PlayerProgressionState | null
var interaction_radius: float = 1.8
var seal_seconds: float = 4.0
var required_item: String = "hull_sealant"
var seal_amount: float = 1.0

var channeling: bool = false
var progress: float = 0.0
var sealed: bool = false
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

func configure(p_compartment_id: String, p_hull_state, p_inventory_state, p_player_progression, world_position: Vector3, p_seal_seconds: float, p_required_item: String, p_seal_amount: float, radius := 1.8) -> void:
	compartment_id = p_compartment_id
	hull_state = p_hull_state
	inventory_state = p_inventory_state
	player_progression = p_player_progression
	seal_seconds = maxf(0.01, p_seal_seconds)
	required_item = p_required_item
	seal_amount = maxf(0.0, p_seal_amount)
	interaction_radius = radius
	channeling = false
	progress = 0.0
	sealed = false
	candidate_player = null
	position = world_position
	name = "BreachSealPoint_%s" % p_compartment_id
	set_meta("breach_seal_point", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_sealed(value: bool) -> void:
	sealed = value
	channeling = false
	progress = 1.0 if value else 0.0
	if collision_shape != null:
		collision_shape.disabled = sealed
	if marker != null:
		marker.visible = marker_visible and not sealed

## Begins the channel if the player is in range and a dry-run would succeed.
func try_start(player_body: Node) -> bool:
	if sealed or channeling or not is_instance_valid(player_body) or hull_state == null:
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	if not hull_state.compartments.has(compartment_id):
		return false
	if not bool((hull_state.compartments[compartment_id] as Dictionary).get("breach_open", false)):
		emit_signal("seal_blocked", compartment_id, "not_breached")
		return false
	if not _has_required_item():
		emit_signal("seal_blocked", compartment_id, "missing_sealant")
		return false
	_channel_player = player_body
	channeling = true
	progress = 0.0
	return true

func _has_required_item() -> bool:
	if inventory_state == null:
		return false
	if required_item.is_empty():
		return true
	return int(inventory_state.get_quantity(required_item)) > 0

func _process(delta: float) -> void:
	if not channeling:
		return
	if not is_instance_valid(_channel_player) or not _is_player_in_direct_range(_channel_player):
		_cancel()
		return
	advance_channel(delta)

## Pumps the channel by delta; seals when progress reaches 1.0. Exposed for smokes.
func advance_channel(delta: float) -> void:
	if not channeling:
		return
	progress = clampf(progress + delta / seal_seconds, 0.0, 1.0)
	if progress >= 1.0:
		_complete()

func _complete() -> void:
	channeling = false
	if not _has_required_item():
		progress = 0.0
		emit_signal("seal_blocked", compartment_id, "missing_sealant")
		return
	if not required_item.is_empty():
		inventory_state.remove_item(required_item, 1)
	if hull_state.seal_compartment(compartment_id, seal_amount):
		set_sealed(true)
		if player_progression != null and player_progression.has_method("grant_xp"):
			player_progression.grant_xp("repair", 15)
		emit_signal("breach_sealed", compartment_id)
	else:
		progress = 0.0
		emit_signal("seal_blocked", compartment_id, "seal_failed")

func _cancel() -> void:
	channeling = false
	progress = 0.0
	_channel_player = null

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
		collision_shape.name = "BreachSealCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = sealed

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "BreachSealMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.95, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible and not sealed
	marker.set_meta("debug_breach_seal_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Verify the InventoryState API used exists** — confirm `InventoryState` has `add_item`, `get_quantity`, and `remove_item` (the food smoke uses `add_item`/`get_quantity`; `remove_item` is used here):

```bash
grep -n "func add_item\|func get_quantity\|func remove_item" scripts/systems/inventory_state.gd
```
Expected: all three present. If `remove_item` has a different name/signature, adjust the `_complete()` call in `breach_seal_point.gd` to match (do not invent a method).

- [ ] **Step 5: Run test to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/breach_seal_point_smoke.gd
```
Expected: `BREACH SEAL POINT PASS sealed=true breach_cleared=true`, only allowlisted noise.

- [ ] **Step 6: Commit**

```bash
git add scripts/tools/breach_seal_point.gd scripts/validation/breach_seal_point_smoke.gd
git commit -m "feat(ship-systems): add BreachSealPoint interaction for hull breaches"
```

---

### Task 5: Spawn + wire `BreachSealPoint`s in the coordinator (close the loop live)

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/main_playable_life_support_vitals_smoke.gd` (extend)

**Interfaces:**
- Consumes: `BreachSealPoint` (Task 4), `hull_integrity_state`, `inventory_state`, `player_progression`, the existing repair-point parenting/lifecycle pattern.
- Produces: live breach-seal points on the hub for each breached compartment; a `_on_breach_sealed(compartment_id)` handler. Extended PASS marker adds `seal_loop=true`.

- [ ] **Step 1: Write the failing test** — in `main_playable_life_support_vitals_smoke.gd`, after the "recover" block and before the final `print(...)`, insert a seal-loop assertion:

```gdscript
	# Seal the pre-damaged cargo breach through a live BreachSealPoint -> breach clears.
	playable.away_from_start = false
	if int(playable.inventory_state.get_quantity("hull_sealant")) < 1:
		playable.inventory_state.add_item("hull_sealant", 1)
	var seal_points: Array = playable.get_breach_seal_points_for_validation()
	if seal_points.is_empty():
		_fail("expected at least one breach seal point for the pre-damaged hull")
		return
	var sp = seal_points[0]
	playable.teleport_player_to_breach_seal_point_for_validation(sp)
	sp.set_validation_player_in_range(playable.player)
	if not sp.try_start(playable.player):
		_fail("breach seal channel should start")
		return
	sp.advance_channel(10.0)
	if playable.hull_integrity_state.get_breach_count() != 0:
		_fail("hull breach should be sealed (count=%d)" % playable.hull_integrity_state.get_breach_count())
		return
```
Then update the final pass `print(...)` to add `seal_loop=true`:

```gdscript
	print("MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true seal_loop=true reachable=true aboard=%.2f->%.2f" % [aboard_before, aboard_after])
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_life_support_vitals_smoke.gd
```
Expected: FAIL — `Nonexistent function 'get_breach_seal_points_for_validation'` (seam + wiring not added yet).

- [ ] **Step 3: Add the preload + container field** — in `scripts/procgen/playable_generated_ship.gd`, near the other tool preloads (~50), add:

```gdscript
const BreachSealPointScript := preload("res://scripts/tools/breach_seal_point.gd")
```
Near the `repair_points` field declaration, add:

```gdscript
var breach_seal_points: Array = []
```

- [ ] **Step 4: Build the seal points** — add a builder method. Reuse the same room-position source the repair points use (`_distributed_room_positions()` away / `_lifeboat_local_repair_positions()` home). Add after `_clear_repair_points()`:

```gdscript
func _build_breach_seal_points() -> void:
	_clear_breach_seal_points()
	if hull_integrity_state == null:
		return
	# Only seal breached compartments; healthy hull needs no seal node.
	var breached: Array = []
	for cid in hull_integrity_state.compartments:
		if bool((hull_integrity_state.compartments[cid] as Dictionary).get("breach_open", false)):
			breached.append(str(cid))
	if breached.is_empty():
		return
	var use_lifeboat: bool = (not away_from_start) and lifeboat_ship != null \
		and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root)
	var positions: Array = _lifeboat_local_repair_positions() if use_lifeboat else _distributed_room_positions()
	if positions.is_empty():
		return
	var idx: int = 0
	for cid in breached:
		var pos: Vector3 = positions[idx % positions.size()]
		idx += 1
		var sp = BreachSealPointScript.new()
		sp.configure(cid, hull_integrity_state, inventory_state, player_progression, pos, 4.0, "hull_sealant", 1.0, 1.8)
		if not sp.breach_sealed.is_connected(_on_breach_sealed):
			sp.breach_sealed.connect(_on_breach_sealed)
		if away_from_start and current_ship != null and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root):
			current_ship.scene_root.add_child(sp)
		elif lifeboat_ship != null and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root):
			lifeboat_ship.scene_root.add_child(sp)
		else:
			repair_point_root.add_child(sp)
		breach_seal_points.append(sp)

func _clear_breach_seal_points() -> void:
	for sp in breach_seal_points:
		if is_instance_valid(sp):
			var parent = sp.get_parent()
			if parent != null and is_instance_valid(parent):
				parent.remove_child(sp)
			sp.queue_free()
	breach_seal_points.clear()

func _on_breach_sealed(compartment_id: String) -> void:
	# The HullIntegrityState was already mutated by the seal node; nothing else to do here
	# beyond letting the next _recompute_expanded_ship_systems pick up the lower breach_count.
	# Hook for HUD/audio later.
	pass
```

- [ ] **Step 5: Call the builder where repair points are built** — find the call site of `_build_repair_points()` (search it) and add `_build_breach_seal_points()` immediately after it, so seal points spawn on the same load/reload path. Also call `_clear_breach_seal_points()` wherever `_clear_repair_points()` is called.

```bash
grep -n "_build_repair_points()\|_clear_repair_points()" scripts/procgen/playable_generated_ship.gd
```
Add the paired calls at each site found.

- [ ] **Step 6: Add the validation seams** — add near the other `*_for_validation` methods:

```gdscript
func get_breach_seal_points_for_validation() -> Array:
	return breach_seal_points.duplicate()

func teleport_player_to_breach_seal_point_for_validation(seal_point) -> bool:
	if player == null or seal_point == null or not is_instance_valid(seal_point):
		return false
	if player is Node3D and seal_point is Node3D:
		(player as Node3D).global_position = (seal_point as Node3D).global_position
		return true
	return false
```

- [ ] **Step 7: Run test to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_life_support_vitals_smoke.gd
```
Expected: `MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true seal_loop=true reachable=true ...`, only allowlisted noise.

- [ ] **Step 8: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_life_support_vitals_smoke.gd
git commit -m "feat(ship-systems): spawn + wire hull breach seal points (M7-A loop closed)"
```

---

### Task 6: Docs — validation bundle markers + audit re-grade + full regression

**Files:**
- Modify: `docs/game/06_validation_plan.md`, `docs/game/system_completion_audit.md`

**Interfaces:** none (documentation + the full regression run).

- [ ] **Step 1: Register the new smokes in the bundle** — in `docs/game/06_validation_plan.md`, add the two new smokes with their expected PASS markers next to the existing main-playable smokes:
  - `breach_seal_point_smoke.gd` → `BREACH SEAL POINT PASS sealed=true breach_cleared=true`
  - `main_playable_life_support_vitals_smoke.gd` → `MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true seal_loop=true reachable=true`
  Increment the command/smoke count in the final marker (`SARGASSO REGRESSION PASS commands=N ...`) by 2. Confirm there is **no** shield smoke entry to remove (there was none) and the save-load summary count stays **26**.

- [ ] **Step 2: Re-grade the audit** — in `docs/game/system_completion_audit.md` M7 table, update the rows:
  - `shield_state` → removed (note: cut; orphan power channel flagged as follow-up).
  - `life_support_expanded_state` → 🟢 closed-loop (← power + hull breach_count → `get_health_drain_per_second()` → `vitals_state` health while aboard).
  - `hull_integrity_state` → 🟡→🟢 on the sink side (breach_count now drives life-support; live source still config-only #4, sources #1–3 deferred); player can seal via `BreachSealPoint`.
  Update the rollup items (#2 hull source partly addressed via #4; #3 shields resolved by cut) and add a short "Resolved by M7-A" note.

- [ ] **Step 3: Run the FULL regression bundle** — run the bash block from `docs/game/06_validation_plan.md` with the Windows `GODOT`/`ROOT` values.
Expected: ends with `SARGASSO REGRESSION PASS commands=<N+2> clean_output=true`. If any smoke fails or an unexpected `ERROR:`/`WARNING:` appears, fix it before proceeding (do not edit the doc to hide it).

- [ ] **Step 4: Commit**

```bash
git add docs/game/06_validation_plan.md docs/game/system_completion_audit.md
git commit -m "docs: register M7-A smokes + re-grade the ship-systems lane"
```

---

## Self-Review

**Spec coverage:**
- A1 goal (hull breach → atmosphere → vitals → response) → Tasks 1, 3, 4, 5. ✅
- A2 architecture (accessors + ~coordinator wiring, no new model class) → Tasks 1, 3. ✅
- A3 teeth (O2/CO2 health drain, temp→thirst, aboard gate, deferred water) → Tasks 1, 3; water explicitly deferred to C. ✅
- A4 hull source #4 + future-proof `damage_compartment()` → Task 3 (config) + seam left intact. ✅
- A5 cut shield (model + tuning; power channel flagged) → Task 2. ✅
- A6 testing (model smoke, main-scene smoke, bundle) → Tasks 1, 3, 5, 6. ✅
- Save/load: no change needed (already round-trips nested) → confirmed in spec; no task required. ✅
- Planning-stage refinements (breach leak while powered; BreachSealPoint) → Tasks 1, 4, 5. ✅

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to" — every code step shows full code. Two steps (Task 4 Step 4, Task 5 Step 5) are *verification greps* that say exactly what to confirm and what to do if the API name differs (adjust to the real method; do not invent) — acceptable, not placeholders.

**Type consistency:** `get_health_drain_per_second()` / `get_thirst_multiplier()` defined in Task 1, consumed in Task 3. `BreachSealPoint.configure(...)`, `try_start`, `advance_channel`, `breach_sealed` defined in Task 4, consumed in Tasks 5. `get_breach_seal_points_for_validation()` / `teleport_player_to_breach_seal_point_for_validation()` defined in Task 5 Step 6, used in Task 5 Step 1 (same task — defined before the test runs in Step 7). `hull_integrity_state.seal_compartment(id, amount)` / `compartments` / `get_breach_count()` match the real `HullIntegrityState` API. `inventory_state.add_item/get_quantity/remove_item` verified in Task 4 Step 4 before first use.

**Known risk flagged:** the `away_from_start` and `life_support_expanded_state` fields are written directly by the smokes (white-box) — acceptable for validation smokes, consistent with the existing food smoke writing `vitals_state.hunger`.
