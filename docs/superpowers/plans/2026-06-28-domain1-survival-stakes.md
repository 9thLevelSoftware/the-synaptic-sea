# Domain 1: Survival & Stakes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the `survival_vitals` loop (currently 🔴 broken) by giving the game a real terminal failure state — death on `health<=0` wired into both `_process` branches, low-vitals movement penalty, and the full survival attrition tick (radiation / body-temperature / status) running on the boarded-derelict branch.

**Architecture:** Add two pure predicates to `VitalsState` (data). Add a movement-speed multiplier to `PlayerController` (behavior). Extract the home branch's survival-vitals tick into one coordinator helper `_tick_survival_attrition(delta)` that also enforces the stakes (movement gating + death), and call that single helper from **both** `_process` branches so attrition and death are live on a derelict. Generalize the body-temperature/radiation zone signal from the always-false `away_from_start` literal to a real `in_hazard_env` predicate. Prove it with a pure-model smoke, a player smoke, a home-stakes scene smoke, and an away-stakes scene smoke, then flip the loop green in the inventory.

**Tech Stack:** Godot 4.6.2, typed GDScript. Headless validation via `--script` smokes (`extends SceneTree`). Python inventory generator (`tools/build_system_inventory.py`).

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (use the `_console` build headless).
- **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- **Both `_process` branches.** Any per-frame system MUST run on the `away_from_start` (derelict) branch *and* the home branch of `playable_generated_ship.gd::_process`. The away early-return is at **line 4808**. Every scene smoke includes an `away_ticks=`-style assertion that drives `away_from_start = true`. (CLAUDE.md: this early-return has caused 3 shipped regressions.)
- **Model/Node separation (strict):** Resources/RefCounted are data (no scene tree); Nodes apply scene consequences. The death *threshold* is a pure predicate on `VitalsState`; the death *consequence* (`end_run`) is the coordinator's.
- **Typed GDScript** for all new code.
- **Validation is the definition of done.** No completion claim without fresh PASS-marker output. New systems get a pure-model smoke and a main-scene smoke, both registered in `docs/game/06_validation_plan.md`.
- **Baseline output noise allowlist** (ignore exactly these): `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...` on teardown, plus the one expected `WARNING: SaveLoadService: save file rejected by from_dict ...`. **Any other `ERROR:`/`WARNING:` line blocks completion.**
- **Done = loop green:** the domain closes only when `survival_vitals.closes == "closed"` in `docs/game/inventory/system_inventory.json`, the inventory regenerates, `--check` passes, and the full regression bundle ends `SYNAPTIC_SEA REGRESSION PASS`.

**Helper for running a single smoke (used throughout):**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke>.gd
```

> **Exit-code caveat:** Godot `--script` can exit 0 even on parse/load errors. **Trust the PASS marker line, not the exit code.** Confirm the marker prints and no unexpected `ERROR:`/`WARNING:` appears.

---

### Task 1: VitalsState death + movement-gating predicates

Add the pure data predicates the coordinator will consume. No scene tree.

**Files:**
- Modify: `scripts/systems/vitals_state.gd`
- Test: `scripts/validation/vitals_state_smoke.gd` (extend the existing pure-model smoke)

**Interfaces:**
- Produces:
  - `VitalsState.EXHAUSTION_STAMINA_THRESHOLD: float` (const, `15.0`)
  - `VitalsState.is_incapacitated() -> bool` — true when `health <= 0.0`
  - `VitalsState.get_movement_speed_multiplier() -> float` — `0.0` if incapacitated, `0.5` if `stamina <= EXHAUSTION_STAMINA_THRESHOLD`, else `1.0`

- [ ] **Step 1: Add the failing assertions to the pure-model smoke**

In `scripts/validation/vitals_state_smoke.gd`, insert this block immediately **before** the final `print("VITALS STATE PASS ...")` line (around line 131):

```gdscript
	# Domain 1: incapacitation predicate (health<=0)
	var vi := VitalsStateScript.new()
	vi.configure({})
	if vi.is_incapacitated():
		_fail("full-health vitals should not be incapacitated")
		return
	vi.health = 0.0
	if not vi.is_incapacitated():
		_fail("health=0 should be incapacitated")
		return

	# Domain 1: movement-speed multiplier gating
	var vm := VitalsStateScript.new()
	vm.configure({})
	if absf(vm.get_movement_speed_multiplier() - 1.0) > 0.001:
		_fail("healthy vitals should give full movement multiplier")
		return
	vm.stamina = VitalsStateScript.EXHAUSTION_STAMINA_THRESHOLD - 1.0
	if absf(vm.get_movement_speed_multiplier() - 0.5) > 0.001:
		_fail("exhausted vitals should halve movement multiplier")
		return
	vm.stamina = 100.0
	vm.health = 0.0
	if absf(vm.get_movement_speed_multiplier() - 0.0) > 0.001:
		_fail("incapacitated vitals should zero movement multiplier")
		return
```

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_state_smoke.gd
```
Expected: FAIL — `push_error` for an invalid call to `is_incapacitated` (method not found / parse error), no `VITALS STATE PASS` marker.

- [ ] **Step 3: Implement the predicates in the model**

In `scripts/systems/vitals_state.gd`, add the const next to the other thresholds (after line 18, `THIRST_VISION_WARNING_THRESHOLD`):

```gdscript
const EXHAUSTION_STAMINA_THRESHOLD: float = 15.0
```

Then add these methods after `apply_delta(...)` (after line 120):

```gdscript
## Domain 1 (survival_vitals stakes): true when the player has bled out.
## Pure predicate; the coordinator turns this into end_run("death").
func is_incapacitated() -> bool:
	return health <= 0.0

## Domain 1: low-vitals action-gating expressed as a movement-speed multiplier.
## 0.0 when incapacitated (movement locked at death), 0.5 when stamina is
## exhausted (attrition slows the player BEFORE death), else 1.0.
func get_movement_speed_multiplier() -> float:
	if is_incapacitated():
		return 0.0
	if stamina <= EXHAUSTION_STAMINA_THRESHOLD:
		return 0.5
	return 1.0
```

- [ ] **Step 4: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_state_smoke.gd
```
Expected: PASS — prints `VITALS STATE PASS health=... sanity_drain=true sanity_stamina=true`, no unexpected `ERROR:`/`WARNING:`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/vitals_state.gd scripts/validation/vitals_state_smoke.gd
git commit -m "feat(survival): add VitalsState incapacitation + movement-gating predicates"
```

---

### Task 2: PlayerController movement-speed multiplier

Give the coordinator a thin, testable seam to slow/lock the player from vitals.

**Files:**
- Modify: `scripts/player/player_controller.gd`
- Test: `scripts/validation/player_movement_gating_smoke.gd` (new)

**Interfaces:**
- Consumes: nothing from Task 1 directly (the coordinator bridges them in Task 4).
- Produces:
  - `PlayerController.set_movement_speed_multiplier(m: float) -> void` — stores `clampf(m, 0.0, 1.0)`
  - `PlayerController.get_effective_move_speed() -> float` — `move_speed * _speed_multiplier`

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/player_movement_gating_smoke.gd`:

```gdscript
extends SceneTree

## Pure-node smoke: PlayerController exposes a vitals-driven movement-speed
## multiplier seam (Domain 1 action-gating). No physics/input needed.
##
## Pass marker:
##   PLAYER MOVEMENT GATING PASS full=%.1f half=%.1f locked=%.1f

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

func _initialize() -> void:
	var p = PlayerControllerScript.new()
	var base: float = p.get_effective_move_speed()
	if base <= 0.0:
		_fail("base effective move speed should be > 0 (got %.3f)" % base)
		return
	p.set_movement_speed_multiplier(0.5)
	var half: float = p.get_effective_move_speed()
	if absf(half - base * 0.5) > 0.001:
		_fail("0.5 multiplier should halve effective speed (%.3f vs %.3f)" % [half, base * 0.5])
		return
	p.set_movement_speed_multiplier(0.0)
	var locked: float = p.get_effective_move_speed()
	if absf(locked) > 0.001:
		_fail("0.0 multiplier should lock movement (got %.3f)" % locked)
		return
	# clamp guard: out-of-range inputs are clamped, never amplify speed
	p.set_movement_speed_multiplier(5.0)
	if p.get_effective_move_speed() > base + 0.001:
		_fail("multiplier should clamp to <= 1.0")
		return
	p.free()
	print("PLAYER MOVEMENT GATING PASS full=%.1f half=%.1f locked=%.1f" % [base, half, locked])
	quit(0)

func _fail(reason: String) -> void:
	push_error("PLAYER MOVEMENT GATING FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_movement_gating_smoke.gd
```
Expected: FAIL — `get_effective_move_speed` / `set_movement_speed_multiplier` do not exist; no `PLAYER MOVEMENT GATING PASS`.

- [ ] **Step 3: Implement the multiplier in PlayerController**

In `scripts/player/player_controller.gd`, add the backing field next to `move_speed` (after line 13):

```gdscript
var _speed_multiplier: float = 1.0
```

Add these methods (place them near the top of the script's function section, e.g. directly above `_physics_process`):

```gdscript
## Domain 1: vitals-driven action-gating seam. The coordinator pushes a
## multiplier each frame from VitalsState.get_movement_speed_multiplier().
func set_movement_speed_multiplier(m: float) -> void:
	_speed_multiplier = clampf(m, 0.0, 1.0)

## Effective per-frame move speed after the vitals gate is applied.
func get_effective_move_speed() -> float:
	return move_speed * _speed_multiplier
```

Then change the velocity assignment (current lines 32-33) from:

```gdscript
	velocity.x = move_direction.x * move_speed
	velocity.z = move_direction.z * move_speed
```

to:

```gdscript
	velocity.x = move_direction.x * get_effective_move_speed()
	velocity.z = move_direction.z * get_effective_move_speed()
```

- [ ] **Step 4: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_movement_gating_smoke.gd
```
Expected: PASS — prints `PLAYER MOVEMENT GATING PASS full=... half=... locked=0.0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/player/player_controller.gd scripts/validation/player_movement_gating_smoke.gd
git commit -m "feat(player): add vitals-driven movement-speed multiplier seam"
```

---

### Task 3: Extract the survival attrition tick into one coordinator helper (home branch, behavior-preserving)

Pull the home branch's survival-vitals tick + radiation/body-temp/status ticks into a single helper that both branches will share, and append the stakes (movement gating + death) inside it. This task wires the helper into the **home** branch only and must not change home behavior except for adding the death/gating consequences.

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (around lines 4833-4889; add helper + two private methods)

**Interfaces:**
- Consumes: `VitalsState.is_incapacitated()`, `VitalsState.get_movement_speed_multiplier()` (Task 1); `PlayerController.set_movement_speed_multiplier(...)` (Task 2); existing `end_run(reason)` (line 1488).
- Produces:
  - `_tick_survival_attrition(delta: float) -> void`
  - `_apply_vitals_action_gating() -> void`
  - `_check_vitals_death() -> void`

- [ ] **Step 1: Add the helper and the two private methods**

In `scripts/procgen/playable_generated_ship.gd`, add this block immediately **above** `func _build_breach_zone()` (currently line 4907):

```gdscript
## Domain 1 (survival_vitals): the single survival-attrition tick, called from
## BOTH _process branches so radiation / body-temperature / status / the vitals
## cascade — and the terminal stakes (movement gating + death) — are live on a
## boarded derelict (the PRIMARY context), not home-only. The away early-return
## at line 4808 previously starved this entire loop in the field.
##
## Order preserves the prior home semantics: the vitals context reads the
## CURRENT (pre-tick) source values, vitals ticks, then the environmental
## sources advance. The hallucination teeth are read with the same one-frame
## lag the home path already tolerated (the sanity block ticks the director
## separately on each branch).
func _tick_survival_attrition(delta: float) -> void:
	if vitals_state == null:
		return
	# Real environmental hazard signal (replaces the always-false away_from_start
	# literal at the old line 4886): you are in a thermal/radiation hazard zone on
	# a derelict OR when the hub hull is breached. Mirrors radiation's prior in_rad.
	var breach_open: bool = oxygen_state != null and oxygen_state.get_summary().get("breach_open", false)
	var in_hazard_env: bool = away_from_start or breach_open
	# Assemble the vitals context from current source state (pre-tick).
	var temp_mult: float = 1.0
	if body_temperature_state != null:
		temp_mult = body_temperature_state.get_thirst_multiplier()
	var rad_drain: float = 0.0
	if radiation_state != null:
		rad_drain = radiation_state.get_health_drain_per_second()
	var status_mult: float = 1.0
	if status_effects_state != null:
		status_mult = status_effects_state.get_modifier("stamina_recovery")
	# Hub ambient atmosphere bites only while ABOARD (away, the personal hazards own it).
	var atmo_drain: float = 0.0
	if life_support_expanded_state != null and not away_from_start:
		atmo_drain = life_support_expanded_state.get_health_drain_per_second()
		temp_mult *= life_support_expanded_state.get_thirst_multiplier()
	var hteeth: Dictionary = hallucination_director.get_direct_teeth() if hallucination_director != null else {"health_drain_per_second": 0.0, "stamina_recovery_mult": 1.0}
	vitals_state.tick(delta, {
		"temperature_thirst_mult": temp_mult,
		"radiation_health_drain": rad_drain,
		"atmosphere_health_drain": atmo_drain,
		"fire_health_drain": FIRE_HEALTH_DRAIN_PER_SECOND * _player_fire_intensity(),
		"status_stamina_recovery_mult": status_mult,
		"sanity_health_drain": float(hteeth["health_drain_per_second"]),
		"sanity_stamina_recovery_mult": float(hteeth["stamina_recovery_mult"]),
		"moving": player != null and player.has_method("is_moving") and player.is_moving(),
	})
	# Stakes: penalize movement from low vitals, then end the run on incapacitation.
	_apply_vitals_action_gating()
	_check_vitals_death()
	# Advance the environmental sources AFTER the vitals read (preserves prior order).
	if radiation_state != null:
		radiation_state.in_radiation_zone = in_hazard_env
		radiation_state.tick(delta)
	if body_temperature_state != null:
		body_temperature_state.in_extreme_zone = in_hazard_env
		body_temperature_state.tick(delta)
	if status_effects_state != null:
		status_effects_state.tick(delta)

## Domain 1: push the vitals movement gate onto the player every frame.
func _apply_vitals_action_gating() -> void:
	if player == null or vitals_state == null:
		return
	if not player.has_method("set_movement_speed_multiplier"):
		return
	player.set_movement_speed_multiplier(vitals_state.get_movement_speed_multiplier())

## Domain 1: terminal stake. When the player is incapacitated (health<=0) end the
## run as a death. end_run is idempotent (guards slice_complete), so this is safe
## to call every frame and from both branches.
func _check_vitals_death() -> void:
	if vitals_state == null or slice_complete:
		return
	if vitals_state.is_incapacitated():
		end_run("death")
```

- [ ] **Step 2: Replace the home branch's inline vitals block with the helper call**

In `_process`, the home branch currently ticks vitals at lines 4834-4863, the sanity block at 4864-4879, radiation at 4880-4884, body-temp at 4885-4887, and status at 4888-4889. Replace the **vitals block** (the `if vitals_state != null:` block spanning 4834-4863) with a single call, and **delete** the radiation/body-temp/status blocks (4880-4889) since they now live in the helper. Leave the sanity block (4864-4879) and the food block (4891+) untouched.

After the edit, the home branch reads (from line 4829 context):

```gdscript
	if stimulant_state != null:
		stimulant_state.tick(delta, addiction_state, _consumable_pipeline_context())
	if addiction_state != null:
		addiction_state.tick(delta, status_effects_state)
	# REQ-SV / Domain 1: survival attrition + stakes (shared by both branches).
	_tick_survival_attrition(delta)
	if sanity_state != null:
		# Synaptic Sea field = not in a safe zone (away_from_start or breach open)
		var in_safe: bool = not away_from_start and (oxygen_state == null or not oxygen_state.get_summary().get("breach_open", false))
		sanity_state.in_safe_zone = in_safe
		sanity_state.tick(delta)
		# ADR-0042: drive sanity hallucinations from the post-tick sanity value.
		if hallucination_director != null:
			var hctx := {
				"sanity": sanity_state.sanity,
				"in_safe_zone": in_safe,
				"anchor_positions": _distributed_room_positions(),
			}
			hallucination_director.tick(delta, hctx)
			if hallucination_manager != null and is_instance_valid(hallucination_manager):
				var ppos: Vector3 = (player as Node3D).global_position if player != null and player is Node3D else Vector3.ZERO
				hallucination_manager.render(delta, ppos)
	# ADR-0034: tick food / cooking / spoilage / sustenance models.
	if spoilage_state != null:
		spoilage_state.tick(delta)
```

> The `radiation_state` / `body_temperature_state` / `status_effects_state` `if` blocks that were at 4880-4889 are now GONE from `_process` (moved into the helper). Do not leave duplicates — a double tick would drain twice as fast.

- [ ] **Step 3: Run the full regression bundle to verify home behavior is preserved**

Run the regression bundle from `docs/game/06_validation_plan.md` (the bash block with `GODOT`/`ROOT` set to the Windows values). It exercises every existing survival/vitals/hallucination/fire smoke against the home path.
Expected: ends `SYNAPTIC_SEA REGRESSION PASS commands=63 clean_output=true`. If any vitals/temperature smoke now asserts a slightly different exact value due to tick reordering, STOP and inspect — the helper must preserve home order (context read pre-tick, sources advance post-tick). Do not adjust smoke tolerances to mask a real ordering change.

- [ ] **Step 4: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd
git commit -m "refactor(survival): extract _tick_survival_attrition helper + wire stakes on home branch"
```

---

### Task 4: Home-stakes scene smoke (death + gating fire on the home path)

Prove the stakes are reachable through the live coordinator on the home branch before touching the away branch.

**Files:**
- Create: `scripts/validation/main_playable_survival_stakes_smoke.gd`
- Modify: `docs/game/06_validation_plan.md` (register the smoke + marker)

**Interfaces:**
- Consumes: `playable._process(delta)`, `playable.vitals_state`, `playable.player`, `playable.end_run(...)`, `playable.slice_complete`, `playable.away_from_start`.

- [ ] **Step 1: Write the failing scene smoke**

Create `scripts/validation/main_playable_survival_stakes_smoke.gd`:

```gdscript
extends SceneTree

## Domain 1 home-path proof (live scene): low stamina slows the player via the
## vitals movement gate, and draining health to 0 ends the run as a death through
## the REAL coordinator _process tick (home branch, away_from_start=false).
##
## Pass marker:
##   MAIN PLAYABLE SURVIVAL STAKES PASS gate_half=true gate_locked=true death=true reachable=true

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
	if playable.vitals_state == null or playable.player == null:
		_fail("vitals / player missing")
		return
	# Isolate the measurement from combat damage.
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.away_from_start = false

	# Exhausted stamina -> movement gate halves effective speed (before death).
	playable.vitals_state.health = 100.0
	playable.vitals_state.stamina = 5.0
	_pump(0.2)
	var gate_half: bool = absf(playable.player.get_effective_move_speed() - playable.player.move_speed * 0.5) < 0.001
	if not gate_half:
		_fail("exhausted stamina should halve effective move speed (got %.3f of %.3f)" % [playable.player.get_effective_move_speed(), playable.player.move_speed])
		return

	# Drain health to 0 -> incapacitation locks movement AND ends the run as death.
	playable.vitals_state.stamina = 100.0
	playable.vitals_state.health = 0.0
	_pump(0.1)
	var gate_locked: bool = absf(playable.player.get_effective_move_speed()) < 0.001
	if not gate_locked:
		_fail("incapacitation should lock movement (got %.3f)" % playable.player.get_effective_move_speed())
		return
	if not playable.slice_complete:
		_fail("health=0 should have ended the run (slice_complete still false)")
		return

	finished = true
	print("MAIN PLAYABLE SURVIVAL STAKES PASS gate_half=true gate_locked=true death=true reachable=true")
	_cleanup_and_quit(0)

func _pump(seconds: float) -> void:
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
	push_error("MAIN PLAYABLE SURVIVAL STAKES FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_survival_stakes_smoke.gd
```
Expected: PASS — prints `MAIN PLAYABLE SURVIVAL STAKES PASS gate_half=true gate_locked=true death=true reachable=true`. (This already passes because Task 3 wired the stakes into the home branch; it is the regression guard for the home path.)

- [ ] **Step 3: Register the smoke in the validation plan**

In `docs/game/06_validation_plan.md`, add the smoke to the regression bundle following the existing per-smoke pattern (invocation + grep for the PASS marker `MAIN PLAYABLE SURVIVAL STAKES PASS`). Bump the bundle's `commands=` count to match the new total (it increases by one per registered smoke; the final marker is `SYNAPTIC_SEA REGRESSION PASS commands=<N> clean_output=true`). Verify the count against the script's own tally by running the bundle in Task 7.

- [ ] **Step 4: Commit**

```bash
git add scripts/validation/main_playable_survival_stakes_smoke.gd docs/game/06_validation_plan.md
git commit -m "test(survival): home-path scene smoke for death + movement gating"
```

---

### Task 5: Away-stakes scene smoke (failing — drives the derelict branch)

Write the smoke that proves attrition and death are live on a boarded derelict. It will FAIL until Task 6 wires the away branch.

**Files:**
- Create: `scripts/validation/main_playable_survival_away_smoke.gd`
- Modify: `docs/game/06_validation_plan.md` (register the smoke + marker)

**Interfaces:**
- Consumes: `playable._process(delta)` with `away_from_start = true`; `playable.vitals_state`, `playable.radiation_state`, `playable.body_temperature_state`, `playable.slice_complete`.

- [ ] **Step 1: Write the failing away smoke**

Create `scripts/validation/main_playable_survival_away_smoke.gd`:

```gdscript
extends SceneTree

## Domain 1 away-path proof (live scene): on a boarded derelict
## (away_from_start=true, past the line 4808 early-return) the survival attrition
## tick must ADVANCE — radiation drains health, the extreme-zone signal heats body
## temperature — and draining health to 0 must end the run as a death.
##
## Pass marker:
##   MAIN PLAYABLE SURVIVAL AWAY PASS away_ticks=true rad_drain=true temp_rise=true away_death=true

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
	if playable.vitals_state == null or playable.radiation_state == null or playable.body_temperature_state == null:
		_fail("vitals / radiation / body_temperature missing")
		return
	# Isolate from combat damage; board a derelict.
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.away_from_start = true

	# Radiation must drain health on the AWAY branch (it ran home-only before).
	playable.radiation_state.radiation_level = 100.0
	playable.vitals_state.health = 90.0
	var rad_before: float = playable.vitals_state.health
	_pump(2.0)
	var rad_drain: bool = playable.vitals_state.health < rad_before - 0.001
	if not rad_drain:
		_fail("radiation should drain health on a derelict (%.3f -> %.3f)" % [rad_before, playable.vitals_state.health])
		return

	# Extreme-zone signal must engage body temperature away (was always-false before).
	var temp_before: float = playable.body_temperature_state.temperature
	_pump(2.0)
	var temp_rise: bool = playable.body_temperature_state.temperature > temp_before + 0.001
	if not temp_rise:
		_fail("body temperature should rise in the derelict extreme zone (%.3f -> %.3f)" % [temp_before, playable.body_temperature_state.temperature])
		return

	# Death must fire on the AWAY branch.
	playable.vitals_state.health = 0.0
	_pump(0.1)
	if not playable.slice_complete:
		_fail("health=0 on a derelict should end the run (slice_complete still false)")
		return

	finished = true
	print("MAIN PLAYABLE SURVIVAL AWAY PASS away_ticks=true rad_drain=true temp_rise=true away_death=true")
	_cleanup_and_quit(0)

func _pump(seconds: float) -> void:
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
	push_error("MAIN PLAYABLE SURVIVAL AWAY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

> **Note on `radiation_level`:** the smoke sets `playable.radiation_state.radiation_level = 100.0` to force a non-zero `get_health_drain_per_second()`. If `radiation_state.gd` names that field differently, read the model and use the actual field — the assertion (health drains on the away branch) is what matters, not the exact setter.

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_survival_away_smoke.gd
```
Expected: FAIL — `MAIN PLAYABLE SURVIVAL AWAY FAIL reason=radiation should drain health on a derelict ...` because the away branch returns at 4808 before any survival attrition runs.

- [ ] **Step 3: Register the smoke in the validation plan**

In `docs/game/06_validation_plan.md`, add `main_playable_survival_away_smoke.gd` to the bundle (invocation + grep for `MAIN PLAYABLE SURVIVAL AWAY PASS`), and bump `commands=` again. (Final count reconciled when the bundle runs in Task 7.)

- [ ] **Step 4: Commit**

```bash
git add scripts/validation/main_playable_survival_away_smoke.gd docs/game/06_validation_plan.md
git commit -m "test(survival): failing away-path scene smoke for derelict attrition + death"
```

---

### Task 6: Wire the away branch to the survival attrition helper

Make the away branch call the shared helper and remove its now-duplicate sanity/fire health teeth (those drains now flow through `vitals_state.tick` inside the helper, so leaving the `apply_delta` calls would double-count).

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (away branch, lines 4749-4808)

**Interfaces:**
- Consumes: `_tick_survival_attrition(delta)` (Task 3).

- [ ] **Step 1: Remove the duplicate away-branch sanity health teeth**

In the away branch, delete the sanity `apply_delta` teeth block (currently lines 4771-4774):

```gdscript
				if vitals_state != null:
					var away_drain: float = float(hallucination_director.get_direct_teeth()["health_drain_per_second"]) * delta
					if away_drain > 0.0:
						vitals_state.apply_delta({"health": -away_drain})
```

Keep the surrounding sanity scheduling/render (the `sanity_state.tick`, `hallucination_director.tick`, and `hallucination_manager.render` calls) — only the `vitals_state.apply_delta` teeth are removed.

- [ ] **Step 2: Remove the duplicate away-branch fire health teeth**

In the away branch fire block, delete the fire `apply_delta` teeth (currently lines 4785-4788):

```gdscript
			if vitals_state != null:
				var fire_drain: float = FIRE_HEALTH_DRAIN_PER_SECOND * _player_fire_intensity() * delta
				if fire_drain > 0.0:
					vitals_state.apply_delta({"health": -fire_drain})
```

Keep the fire MODEL tick above it (`_afs_away.tick`, `_apply_fire_system_damage`, `_refresh_fire_zones`) — only the player-vitals fire teeth are removed (they now flow through the helper's `fire_health_drain` context).

- [ ] **Step 3: Call the helper before the away vitals-panel refresh**

In the away branch, immediately **before** the existing `_refresh_player_vitals(delta)` call (currently line 4794), insert:

```gdscript
			# Domain 1: survival attrition + stakes on the derelict branch (shared
			# helper). Runs radiation/body-temp/status + the vitals cascade + death,
			# so the away path is no longer starved past the 4808 early-return.
			_tick_survival_attrition(delta)
```

After the edits the away branch around that point reads:

```gdscript
			if is_instance_valid(extinguisher_recharge_port):
				var _dmgr = _active_systems_manager()
				extinguisher_recharge_port.set_powered(_dmgr != null and _dmgr.is_operational("power"))
			# Domain 1: survival attrition + stakes on the derelict branch (shared
			# helper). Runs radiation/body-temp/status + the vitals cascade + death,
			# so the away path is no longer starved past the 4808 early-return.
			_tick_survival_attrition(delta)
			_refresh_player_vitals(delta)
```

- [ ] **Step 4: Run the away smoke to verify it now passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_survival_away_smoke.gd
```
Expected: PASS — prints `MAIN PLAYABLE SURVIVAL AWAY PASS away_ticks=true rad_drain=true temp_rise=true away_death=true`.

- [ ] **Step 5: Re-run the home smoke to confirm no regression**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_survival_stakes_smoke.gd
```
Expected: PASS — `MAIN PLAYABLE SURVIVAL STAKES PASS ...` still green (the helper is shared; home behavior unchanged).

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd
git commit -m "feat(survival): tick survival attrition + death on the derelict branch"
```

---

### Task 7: Flip the loop green in the inventory + full regression

Mark `survival_vitals` closed in the single source of truth, regenerate the views, and prove the whole bundle is clean.

**Files:**
- Modify: `docs/game/inventory/system_inventory.json`
- Regenerate (do not hand-edit): `docs/game/inventory/SYSTEM_INVENTORY.md`, `docs/game/inventory/system_map.html`

**Interfaces:**
- Consumes: the Python generator `tools/build_system_inventory.py` (`--check`, `--coverage`).

- [ ] **Step 1: Update the `survival_vitals` loop entry**

In `docs/game/inventory/system_inventory.json`, find the loop with `"id": "survival_vitals"` (around line 8179). Change `"closes": "broken"` to `"closes": "closed"` and replace its `break_points` array with a closure note + the documented deferral:

```json
      "break_points": [
        "CLOSED (Domain 1): end_run('death') now fires from _check_vitals_death() on health<=0, wired into BOTH _process branches via _tick_survival_attrition(); low-vitals movement gating applies through VitalsState.get_movement_speed_multiplier() -> PlayerController.set_movement_speed_multiplier(); radiation/body-temperature/status now tick on the away (derelict) branch; body_temperature in_extreme_zone is driven by the real in_hazard_env signal (away_from_start OR breach_open), not the always-false literal. Verified by main_playable_survival_stakes_smoke.gd + main_playable_survival_away_smoke.gd.",
        "Deferred (by design): no death animation / respawn UX yet; incapacitation == instant run-end."
      ]
```

- [ ] **Step 2: Update the `vitals_state` system output + clear its gaps**

In the `vitals_state` system entry (around line 19-43), update the `output` description and the `integrations` health, and clear the two stale `gaps`. Set:

```json
      "output": {
        "live": true,
        "desc": "Death/incapacitation is now a LIVE terminal consumer: _check_vitals_death() calls end_run('death') on health<=0 from BOTH _process branches; _apply_vitals_action_gating() pushes get_movement_speed_multiplier() onto PlayerController each frame (exhaustion at stamina<=15 halves speed, incapacitation locks it). Plus the prior audio consequence (vitals_critical -> CRITICAL music + SFX_SUIT_BREATH + UI_VITALS_LOW).",
        "at": "playable_generated_ship.gd:_tick_survival_attrition (_check_vitals_death / _apply_vitals_action_gating)"
      },
```

In `integrations`, change the existing `audio_manager` edge `"health": "weak"` to `"health": "healthy"` (the vitals output is now a real gameplay stake, not audio-only). Set `"gaps": []`.

> Line numbers in `desc`/`at` may drift as the coordinator changes; cite the function symbol (`_tick_survival_attrition`) which the `--check` smoke does not depend on for pass/fail.

- [ ] **Step 3: Run the build + check + coverage and verify markers**

```bash
python tools/build_system_inventory.py            # regenerate MD + HTML
python tools/build_system_inventory.py --check     # staleness + confidence gate
python tools/build_system_inventory.py --coverage  # script-coverage gate
```
Expected markers (no unexpected output): `SYSTEM INVENTORY BUILD ... systems=187`, `SYSTEM INVENTORY CHECK PASS systems=187 verified=187`, `SYSTEM INVENTORY COVERAGE PASS ...`. If `--check` reports the committed MD/HTML are stale, ensure Step-3's regenerate ran and re-stage them.

- [ ] **Step 4: Run the generator self-test**

```bash
python tools/test_build_system_inventory.py
```
Expected: `BUILD INVENTORY SELFTEST PASS`.

- [ ] **Step 5: Run the full regression bundle**

Run the bash block in `docs/game/06_validation_plan.md` with `GODOT`/`ROOT` set to the Windows values. It must now include the two new survival smokes registered in Tasks 4-5.
Expected: ends `SYNAPTIC_SEA REGRESSION PASS commands=<N> clean_output=true` with the updated count and zero unexpected `ERROR:`/`WARNING:` lines. Reconcile the `commands=<N>` literal in `06_validation_plan.md` with the value the script actually tallies (it grew by the number of newly registered smokes).

- [ ] **Step 6: Commit**

```bash
git add docs/game/inventory/system_inventory.json docs/game/inventory/SYSTEM_INVENTORY.md docs/game/inventory/system_map.html docs/game/06_validation_plan.md
git commit -m "feat(survival): close survival_vitals loop in inventory (Domain 1 done)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-28-completion-roadmap-design.md` Domain 1 Definition of CLOSED):
1. *`health<=0` consumer calls `end_run('death')` on both branches* → Task 3 (`_check_vitals_death` in the shared helper), Tasks 4 & 6 prove home + away. ✅
2. *Low-vitals action-gating* → Task 1 (`get_movement_speed_multiplier`), Task 2 (player seam), Task 3 (`_apply_vitals_action_gating`), Task 4 asserts halving + locking. ✅
3. *radiation/body-temp/status tick on the away branch* → Task 6 wires the helper into the away branch; Task 5 asserts radiation drain + temp rise on a derelict. ✅
4. *extreme-zone driven by a real signal, not always-false `away_from_start` at 4886* → Task 3 helper uses `in_hazard_env = away_from_start or breach_open`; Task 5 asserts temp rises away. ✅
- *Away-branch checklist (radiation/temp/status/death/gating live away)* → Tasks 5-6. ✅
- *Validation (pure-model + main-scene with `away_ticks=`)* → Tasks 1, 2, 4, 5. ✅
- *Inventory delta (loop → closed, flip output, regenerate, `--check`)* → Task 7. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every run step gives an exact command + expected marker. The one soft spot — `radiation_state.radiation_level` field name — is flagged inline with a fallback instruction (assert behavior, not the exact setter). ✅

**Type consistency:** `is_incapacitated()`, `get_movement_speed_multiplier()`, `EXHAUSTION_STAMINA_THRESHOLD`, `set_movement_speed_multiplier()`, `get_effective_move_speed()`, `_tick_survival_attrition()`, `_apply_vitals_action_gating()`, `_check_vitals_death()` are named identically everywhere they appear across Tasks 1-7. ✅

## Risks & mitigations

- **Tick-reorder drift at home.** Moving radiation/temp/status into the helper changes their position relative to the vitals read. The helper preserves the prior order (context read pre-tick, sources advance post-tick); Task 3 Step 3 runs the **full** regression as the guard and forbids masking a real change with tolerance edits.
- **Double-drain on the away branch.** Folding sanity/fire teeth into the shared `vitals_state.tick` while leaving the old `apply_delta` calls would drain twice. Task 6 Steps 1-2 explicitly remove both duplicate teeth blocks.
- **`radiation_level` field name.** Flagged inline (Task 5 Step 1 note): read `radiation_state.gd` and use the real field; the assertion is health-drains-away, not the setter.
- **Regression `commands=` count.** Adding two smokes changes the bundle tally; Tasks 4, 5, 7 update `commands=<N>` and Task 7 reconciles it against the script's own count.
```
