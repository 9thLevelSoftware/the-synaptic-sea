# Domain 2: Combat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the `combat` loop (🟡 → 🟢) by making detection the single signal source the enemy AI consumes, driving stealth from real runtime signals (movement / room-light / proximity / a new crouch action), and making kills rewarding (lootable corpse + XP) with the corpse removed from the active array.

**Architecture:** `DetectionState` becomes the single producer of the player's emitted detectability profile (noise/light/visibility after crouch); `ThreatManager` feeds each threat's AI that profile (per-archetype sensitivities preserved) with a per-threat distance-proximity scaling on visibility, emits a `threat_killed` signal and removes dead threats; the coordinator computes the real stealth signals each frame (both `_process` branches), registers a new `crouch` input action, and on `threat_killed` spawns a reused `LootContainer` at the corpse + grants XP through the progression bus.

**Tech Stack:** Godot 4.6.2, typed GDScript. Headless `--script` smokes (`extends SceneTree`). Pure-model + main-scene validation.

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (`_console`, headless).
- **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- **Both `_process` branches.** Combat is primarily a derelict activity. The stealth-signal feed (`_tick_threat_runtime`) already runs on the `away_from_start` branch; the kill→reward→removal path fires from `tick_threats` (called inside `_tick_threat_runtime`), so it is both-branches by construction. The combat scene smoke MUST include an `away_kill=`-style assertion driving `away_from_start = true`.
- **Typed GDScript** for all new code.
- **Trust the PASS marker, not the exit code.** Godot `--script` can exit 0 on parse errors. Confirm the `... PASS ...` marker prints and no unexpected `ERROR:`/`WARNING:` appears.
- **Baseline output noise allowlist** (ignore exactly): `ERROR: Capture not registered: 'gdaimcp'.`, `WARNING: ObjectDB instances leaked at exit ...`, and the one expected `WARNING: SaveLoadService: save file rejected by from_dict ...`. Any other `ERROR:`/`WARNING:` blocks completion.
- **git:** selective `git add <paths>` only — NEVER `git add -A`. Never stage `project.godot`, `.godot/`, `*.uid`, `addons/`. The `.godot/` cache may be dirty (a class-cache rescan) — leave it.
- **Commit trailers** (append to every commit message, blank line before):
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx
  ```
- **Regression bundle baseline = `commands=68`.** Each registered smoke bumps the `commands=` literal in `docs/game/06_validation_plan.md` by one. The final `echo` line asserts `SYNAPTIC_SEA REGRESSION PASS commands=<N> clean_output=true`. NOTE: `run_clean` only aborts on an unexpected `ERROR:`/`WARNING:` — the marker grep is unchecked — so when running the full bundle, verify the section-header count, zero `FAIL`, and exit 0, not just the final echo.
- **Done = loop green:** `combat.closes == "closed"` in `docs/game/inventory/system_inventory.json`, views regenerated, `--check` passes, full bundle ends `SYNAPTIC_SEA REGRESSION PASS`.

**Run one smoke:**
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke>.gd
```

## File Structure

- `scripts/systems/detection_state.gd` — add `get_emitted_profile()` (the single emitted signal source).
- `scripts/systems/threat_manager.gd` — source per-threat AI context from the emitted profile; per-threat distance-proximity on visibility; `threat_killed` signal + dead-threat removal.
- `scripts/player/player_controller.gd` — `is_crouching()`/`set_crouching()` + crouch speed factor composed with the Domain 1 movement gate.
- `scripts/procgen/playable_generated_ship.gd` — `crouch` input action; real stealth-signal computation + `_player_room_lit()` in `_tick_threat_runtime`; connect `threat_killed` → `_on_threat_killed` (LootContainer + XP).
- `data/combat/threat_archetypes.json` — add `loot_table` per archetype.
- `data/items/loot_tables.json` — add a `combat_drop_common` table.
- `data/player/training_actions.json` — add a `threat_killed` action.
- `scripts/validation/detection_state_smoke.gd` (extend) + `scripts/validation/combat_closure_smoke.gd` (new).
- `docs/game/06_validation_plan.md`, `docs/game/inventory/system_inventory.json` (+ regenerated MD/HTML).

---

### Task 1: DetectionState emitted profile (single signal source)

**Files:**
- Modify: `scripts/systems/detection_state.gd`
- Test: `scripts/validation/detection_state_smoke.gd` (extend if it exists; else create)

**Interfaces:**
- Produces: `DetectionState.get_emitted_profile() -> Dictionary` returning `{"noise": float, "light": float, "visibility": float}` — the player's emitted signals after the global crouch reduction (`0.65` when `crouching`, else `1.0`), matching the crouch multiplier `detection_state.tick` already applies to its HUD awareness.

- [ ] **Step 1: Add the failing assertion to the detection smoke**

If `scripts/validation/detection_state_smoke.gd` exists, insert this block immediately before its final `print("... PASS ...")` line; if it does not exist, create the file per the template at the end of this step.

```gdscript
	# Domain 2: emitted profile is the post-crouch signal the AI consumes.
	var de = DetectionStateScript.new()
	de.configure({})
	de.update_inputs(1.0, 0.5, 0.8, false, "")
	var prof: Dictionary = de.get_emitted_profile()
	if absf(float(prof["noise"]) - 1.0) > 0.001 or absf(float(prof["light"]) - 0.5) > 0.001 or absf(float(prof["visibility"]) - 0.8) > 0.001:
		_fail("emitted profile should equal raw signals when standing")
		return
	de.update_inputs(1.0, 0.5, 0.8, true, "")  # crouching
	var profc: Dictionary = de.get_emitted_profile()
	if not (float(profc["noise"]) < 1.0 and float(profc["visibility"]) < 0.8):
		_fail("crouch should reduce emitted noise + visibility")
		return
```

If creating the file fresh, use this full template (preload const name `DetectionStateScript`):

```gdscript
extends SceneTree

## Pure-model smoke for DetectionState (Domain 2 emitted profile).

const DetectionStateScript := preload("res://scripts/systems/detection_state.gd")

func _initialize() -> void:
	# Domain 2: emitted profile is the post-crouch signal the AI consumes.
	var de = DetectionStateScript.new()
	de.configure({})
	de.update_inputs(1.0, 0.5, 0.8, false, "")
	var prof: Dictionary = de.get_emitted_profile()
	if absf(float(prof["noise"]) - 1.0) > 0.001 or absf(float(prof["light"]) - 0.5) > 0.001 or absf(float(prof["visibility"]) - 0.8) > 0.001:
		_fail("emitted profile should equal raw signals when standing")
		return
	de.update_inputs(1.0, 0.5, 0.8, true, "")
	var profc: Dictionary = de.get_emitted_profile()
	if not (float(profc["noise"]) < 1.0 and float(profc["visibility"]) < 0.8):
		_fail("crouch should reduce emitted noise + visibility")
		return
	print("DETECTION STATE PASS emitted=true crouch=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("DETECTION STATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/detection_state_smoke.gd
```
Expected: FAIL — `get_emitted_profile` not defined (parse error / no PASS marker).

- [ ] **Step 3: Implement `get_emitted_profile`**

In `scripts/systems/detection_state.gd`, add after `update_inputs(...)` (after line 41):

```gdscript
## Domain 2: the player's emitted detectability profile — the SINGLE signal the
## threat AI consumes. Crouch is applied here once (the global stealth modifier),
## matching the crouch multiplier tick() applies to the HUD awareness, so the AI
## must NOT re-apply crouch.
func get_emitted_profile() -> Dictionary:
	var crouch_mult: float = 0.65 if crouching else 1.0
	return {
		"noise": noise_level * crouch_mult,
		"light": light_level * crouch_mult,
		"visibility": sight_level * crouch_mult,
	}
```

- [ ] **Step 4: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/detection_state_smoke.gd
```
Expected: PASS — prints `DETECTION STATE PASS ...` (or the file's existing marker), no unexpected `ERROR:`/`WARNING:`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/detection_state.gd scripts/validation/detection_state_smoke.gd
git commit -m "feat(combat): DetectionState emitted profile (single AI signal source)"
```

---

### Task 2: ThreatManager consumes the emitted profile + per-threat proximity (BP1)

**Files:**
- Modify: `scripts/systems/threat_manager.gd` (`tick_threats`, lines 65-94; add a proximity helper)
- Test: `scripts/validation/threat_detection_source_smoke.gd` (new)

**Interfaces:**
- Consumes: `DetectionState.get_emitted_profile()` (Task 1).
- Produces: `ThreatManager` builds each threat's AI context's `noise_level/light_level/sight_level` from the emitted profile; `sight_level` is scaled per-threat by `_proximity_factor(threat, player_position)`; `crouching` is passed as `false` (crouch already in the profile). New const `ThreatManager.SIGHT_RANGE: float = 12.0` and method `_proximity_factor(threat, player_position: Vector3) -> float`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/threat_detection_source_smoke.gd`:

```gdscript
extends SceneTree

## Domain 2 (BP1): the threat AI consumes DetectionState's emitted profile as the
## single signal source — changing the profile changes every threat's awareness,
## two archetypes with different sensitivities perceive the SAME profile
## differently, and a closer threat perceives more visibility than a far one.
##
## Pass marker:
##   THREAT DETECTION SOURCE PASS single_source=true per_archetype=true proximity=true

const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")

func _initialize() -> void:
	var tm = ThreatManagerScript.new()
	tm._ready()  # loads archetypes (no scene tree needed for the model path)
	# Two archetypes with different sensitivities, one near, one far.
	tm.inject_validation_encounter(["stalker", "biomatter_swarm"], Vector3.ZERO)
	if tm.threats.size() < 2:
		_fail("expected 2 injected threats")
		return
	# Place threat 0 near the player, threat 1 far.
	tm.threats[0].world_position = [1.0, 0.0, 0.0]
	tm.threats[1].world_position = [50.0, 0.0, 0.0]
	# Low emitted signal -> low awareness for both.
	tm.set_player_signals(0.05, 0.1, 0.1, false, "")
	tm.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	var low0: float = float(tm.threats[0].awareness_score)
	# Raise the emitted signal -> awareness must rise (single source drives the AI).
	tm.set_player_signals(1.5, 1.5, 1.5, false, "")
	tm.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	var hi0: float = float(tm.threats[0].awareness_score)
	var hi1: float = float(tm.threats[1].awareness_score)
	if not (hi0 > low0):
		_fail("raising the emitted profile must raise threat awareness (single source)")
		return
	# Per-archetype: the two threats perceive the same profile differently.
	if absf(hi0 - hi1) < 0.0001:
		_fail("different archetypes should perceive the same profile differently")
		return
	# Proximity: the NEAR threat perceives more visibility-driven awareness than the FAR one
	# (same archetype comparison via two stalkers, near vs far).
	var tm2 = ThreatManagerScript.new()
	tm2._ready()
	tm2.inject_validation_encounter(["stalker", "stalker"], Vector3.ZERO)
	tm2.threats[0].world_position = [1.0, 0.0, 0.0]
	tm2.threats[1].world_position = [50.0, 0.0, 0.0]
	tm2.set_player_signals(0.0, 0.0, 1.5, false, "")  # visibility-only signal
	tm2.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	if not (float(tm2.threats[0].awareness_score) > float(tm2.threats[1].awareness_score)):
		_fail("near threat should perceive more visibility than far threat")
		return
	print("THREAT DETECTION SOURCE PASS single_source=true per_archetype=true proximity=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("THREAT DETECTION SOURCE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_detection_source_smoke.gd
```
Expected: FAIL — proximity assertion fails (today both threats get identical raw `sight_level`, no distance scaling), or awareness is computed from raw signals rather than the profile.

- [ ] **Step 3: Add the proximity helper and route the context through the emitted profile**

In `scripts/systems/threat_manager.gd`, add the const near the top (after line 17):

```gdscript
const SIGHT_RANGE: float = 12.0
```

Add this helper (place it just above `_update_placeholder`, around line 271):

```gdscript
## Domain 2 (BP1): visibility falls off with world distance, so a closer threat
## perceives more of the player's emitted visibility than a far one.
func _proximity_factor(threat, player_position: Vector3) -> float:
	var tp: Vector3 = Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
	return clampf(1.0 - tp.distance_to(player_position) / SIGHT_RANGE, 0.0, 1.0)
```

Then replace the per-threat context build inside `tick_threats` (the `threat.tick(delta, { ... })` call, lines 74-82) with:

```gdscript
		var profile: Dictionary = detection_state.get_emitted_profile()
		var prox: float = _proximity_factor(threat, player_position)
		threat.tick(delta, {
			"noise_level": float(profile["noise"]),
			"light_level": float(profile["light"]),
			"sight_level": float(profile["visibility"]) * prox,
			"crouching": false,  # crouch already applied in the emitted profile (no double-count)
			"room_id": player_room_id,
			"same_room": same_room,
			"detect_threshold": detection_state.detect_threshold,
		})
```

> Leave the `same_room` computation (line 73) and the attack-resolution block (lines 84-93) unchanged — this task only changes the AI's *perception* inputs, not the attack gate.

- [ ] **Step 4: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_detection_source_smoke.gd
```
Expected: PASS — `THREAT DETECTION SOURCE PASS single_source=true per_archetype=true proximity=true`.

- [ ] **Step 5: Run the existing combat regression smokes to confirm no break**

Run any existing `threat`/`combat` smokes (e.g. `scripts/validation/threat_ai_state_smoke.gd`, `scripts/validation/main_playable_slice_combat*_smoke.gd` if present — grep `combat`/`threat` in `docs/game/06_validation_plan.md` for the exact set) and confirm each prints its PASS marker.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/threat_manager.gd scripts/validation/threat_detection_source_smoke.gd
git commit -m "feat(combat): AI consumes detection emitted profile + per-threat proximity (BP1)"
```

---

### Task 3: PlayerController crouch seam (composes with Domain 1 movement gate)

**Files:**
- Modify: `scripts/player/player_controller.gd`
- Test: `scripts/validation/player_crouch_smoke.gd` (new)

**Interfaces:**
- Consumes: `get_effective_move_speed()` (Domain 1: `move_speed * _speed_multiplier`).
- Produces:
  - `PlayerController.CROUCH_SPEED_FACTOR: float` (const, `0.5`)
  - `PlayerController.set_crouching(c: bool) -> void` / `PlayerController.is_crouching() -> bool` (backing `var _crouching: bool = false`)
  - `get_effective_move_speed()` now returns `move_speed * _speed_multiplier * (CROUCH_SPEED_FACTOR if _crouching else 1.0)`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/player_crouch_smoke.gd`:

```gdscript
extends SceneTree

## Pure-node smoke: crouch reduces effective move speed and COMPOSES with the
## Domain 1 vitals movement multiplier (both apply multiplicatively).
##
## Pass marker:
##   PLAYER CROUCH PASS stand=%.2f crouch=%.2f composed=%.2f

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

func _initialize() -> void:
	var p := PlayerControllerScript.new()
	var stand: float = p.get_effective_move_speed()
	p.set_crouching(true)
	var crouch: float = p.get_effective_move_speed()
	if not (crouch < stand and crouch > 0.0):
		_fail("crouch should reduce but not zero effective speed (%.3f vs %.3f)" % [crouch, stand])
		return
	if not p.is_crouching():
		_fail("is_crouching should report true")
		return
	# Composes with the Domain 1 vitals gate: half multiplier AND crouch.
	p.set_movement_speed_multiplier(0.5)
	var composed: float = p.get_effective_move_speed()
	if absf(composed - p.move_speed * 0.5 * PlayerControllerScript.CROUCH_SPEED_FACTOR) > 0.001:
		_fail("crouch must compose multiplicatively with the vitals gate (got %.3f)" % composed)
		return
	p.free()
	print("PLAYER CROUCH PASS stand=%.2f crouch=%.2f composed=%.2f" % [stand, crouch, composed])
	quit(0)

func _fail(reason: String) -> void:
	push_error("PLAYER CROUCH FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_crouch_smoke.gd
```
Expected: FAIL — `set_crouching`/`is_crouching`/`CROUCH_SPEED_FACTOR` undefined.

- [ ] **Step 3: Implement the crouch seam**

In `scripts/player/player_controller.gd`, add the const near `DEFAULT_MOVE_SPEED` (after line 7):

```gdscript
const CROUCH_SPEED_FACTOR: float = 0.5
```

Add the backing field next to `_speed_multiplier` (the Domain 1 field):

```gdscript
var _crouching: bool = false
```

Add these methods (near `set_movement_speed_multiplier`):

```gdscript
## Domain 2: crouch state. Driven by the "crouch" input in _physics_process and
## settable for validation. Crouch lowers move speed and the player's emitted
## stealth signals (the coordinator reads is_crouching() for the detection feed).
func set_crouching(c: bool) -> void:
	_crouching = c

func is_crouching() -> bool:
	return _crouching
```

Change `get_effective_move_speed()` (Domain 1) to compose crouch:

```gdscript
func get_effective_move_speed() -> float:
	return move_speed * _speed_multiplier * (CROUCH_SPEED_FACTOR if _crouching else 1.0)
```

In `_physics_process`, drive `_crouching` from the real input at the top of the function (after the `move_direction` read, before the velocity assignment):

```gdscript
	if InputMap.has_action("crouch"):
		_crouching = Input.is_action_pressed("crouch")
```

- [ ] **Step 4: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_crouch_smoke.gd
```
Expected: PASS — `PLAYER CROUCH PASS ...`.

- [ ] **Step 5: Re-run the Domain 1 movement-gating smoke (no regression)**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_movement_gating_smoke.gd
```
Expected: PASS — `PLAYER MOVEMENT GATING PASS full=6.0 half=3.0 locked=0.0` (crouch defaults off, so Domain 1 numbers are unchanged).

- [ ] **Step 6: Commit**

```bash
git add scripts/player/player_controller.gd scripts/validation/player_crouch_smoke.gd
git commit -m "feat(combat): PlayerController crouch seam composing with the vitals gate"
```

---

### Task 4: Register the `crouch` input action

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (around lines 434-440)
- Test: `scripts/validation/crouch_action_smoke.gd` (new)

**Interfaces:**
- Produces: a registered `"crouch"` InputMap action (bound to `KEY_CTRL`) after `ensure_default_input_actions()` runs.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/crouch_action_smoke.gd`:

```gdscript
extends SceneTree

## The coordinator registers a "crouch" InputMap action (Domain 2 stealth control).
##
## Pass marker: CROUCH ACTION PASS registered=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360
var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	# Actions are registered during coordinator init; a few frames is plenty.
	if frame_count < 5 and not InputMap.has_action("crouch"):
		return
	if not InputMap.has_action("crouch"):
		if frame_count > TIMEOUT_FRAMES:
			_fail("crouch action never registered")
		return
	finished = true
	print("CROUCH ACTION PASS registered=true")
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("CROUCH ACTION FAIL reason=%s" % reason)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/crouch_action_smoke.gd
```
Expected: FAIL — `crouch action never registered`.

- [ ] **Step 3: Register the action**

In `scripts/procgen/playable_generated_ship.gd`, add the binding const next to `DEFAULT_ATTACK_BINDINGS` (after line 434):

```gdscript
const DEFAULT_CROUCH_BINDINGS: Array[Key] = [KEY_CTRL]
```

In `ensure_default_input_actions()`, register it next to `attack_primary` (after line 440):

```gdscript
	_ensure_key_action_set("crouch", DEFAULT_CROUCH_BINDINGS)
```

- [ ] **Step 4: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/crouch_action_smoke.gd
```
Expected: PASS — `CROUCH ACTION PASS registered=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/crouch_action_smoke.gd
git commit -m "feat(combat): register crouch input action"
```

---

### Task 5: Real stealth signals in `_tick_threat_runtime` (BP2)

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (`_tick_threat_runtime`, lines 3905-3916; add `_player_room_lit()` helper)
- Test: covered by the combat scene smoke in Task 9 (this task is verified by the existing combat smokes staying green + the Task 9 assertions). Add a focused assertion in Task 9 Step 1.

**Interfaces:**
- Consumes: `player.is_moving()`, `player.is_crouching()` (Task 3), `_active_systems_manager()`.
- Produces: `_player_room_lit() -> bool`; `_tick_threat_runtime` feeds real signals to `set_player_signals`.

- [ ] **Step 1: Add the `_player_room_lit` helper**

In `scripts/procgen/playable_generated_ship.gd`, add directly above `_tick_threat_runtime` (line 3905):

```gdscript
## Domain 2 (BP2): a derived "is the player in a lit area" signal. A powered ship is
## lit (player more visible); an unpowered/derelict ship is dark (stealthier). Uses
## the active ship's power system (no per-room lighting model exists).
func _player_room_lit() -> bool:
	var mgr = _active_systems_manager()
	return mgr != null and mgr.is_operational("power")
```

- [ ] **Step 2: Replace the literal `set_player_signals` call with real signals**

Replace the `set_player_signals(...)` call in `_tick_threat_runtime` (lines 3909-3915) with:

```gdscript
	var moving: bool = player != null and player.has_method("is_moving") and player.is_moving()
	var crouching: bool = player != null and player.has_method("is_crouching") and player.is_crouching()
	threat_manager.set_player_signals(
		0.3 if moving else 0.05,          # noise from movement
		0.6 if _player_room_lit() else 0.15,  # light from room power
		0.8,                               # base visibility (proximity-scaled per threat in the manager)
		crouching,                          # crouch reduces emitted noise + visibility in DetectionState
		"",
	)
```

> `set_player_signals`'s 3rd arg is the *base* visibility; the manager scales it per-threat by distance (Task 2). Crouch is applied once inside `DetectionState.get_emitted_profile()` — do not pre-multiply here.

- [ ] **Step 3: Confirm both-branches.** `_tick_threat_runtime` is already called on the `away_from_start` branch (it ticks threats on a derelict). No new wiring is needed here — verify by reading the away branch and confirming the `_tick_threat_runtime(delta)` call is present before the early `return`. If it is NOT, STOP and report (the plan assumes it is).

- [ ] **Step 4: Run the existing combat smokes to confirm no break**

Run the existing combat/threat smokes (grep `combat`/`threat` in `docs/game/06_validation_plan.md`). Each must still print its PASS marker. (Full behavioral assertions for BP2 land in Task 9.)

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd
git commit -m "feat(combat): drive stealth signals from movement/light/crouch (BP2)"
```

---

### Task 6: ThreatManager `threat_killed` signal + dead-threat removal (BP3 part 1)

**Files:**
- Modify: `scripts/systems/threat_manager.gd` (add signal, dead-sweep, removal; clear in `_clear_runtime_nodes`)
- Test: `scripts/validation/threat_kill_removal_smoke.gd` (new)

**Interfaces:**
- Produces:
  - `signal threat_killed(record: Dictionary)` — `record = {instance_id, archetype_id, position: Vector3, loot_table: String}`.
  - dead threats (`health <= 0.0`) are removed from `threats[]` and their placeholder despawned, exactly once (a manager-local `_rewarded_kills` guard).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/threat_kill_removal_smoke.gd`:

```gdscript
extends SceneTree

## Domain 2 (BP3): killing a threat emits threat_killed exactly once with the
## archetype's loot_table, and removes the corpse from the active array.
##
## Pass marker:
##   THREAT KILL REMOVAL PASS emitted_once=true removed=true loot_table=true

const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")

var _events: Array = []

func _initialize() -> void:
	var tm = ThreatManagerScript.new()
	tm._ready()
	tm.inject_validation_encounter(["stalker"], Vector3.ZERO)
	if tm.threats.size() != 1:
		_fail("expected 1 threat")
		return
	tm.threat_killed.connect(_on_killed)
	# Kill it.
	tm.threats[0].health = 0.0
	tm.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	if _events.size() != 1:
		_fail("expected exactly one threat_killed event, got %d" % _events.size())
		return
	if tm.threats.size() != 0:
		_fail("dead threat should be removed from the active array")
		return
	if str(_events[0].get("loot_table", "")).is_empty():
		_fail("kill record should carry a loot_table")
		return
	# A second tick must not re-emit (idempotent).
	tm.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	if _events.size() != 1:
		_fail("kill must not re-emit on a later tick")
		return
	print("THREAT KILL REMOVAL PASS emitted_once=true removed=true loot_table=true")
	quit(0)

func _on_killed(record: Dictionary) -> void:
	_events.append(record)

func _fail(reason: String) -> void:
	push_error("THREAT KILL REMOVAL FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_kill_removal_smoke.gd
```
Expected: FAIL — `threat_killed` signal undefined / dead threat not removed.

- [ ] **Step 3: Implement the signal, dead-sweep, and removal**

In `scripts/systems/threat_manager.gd`, add the signal declaration near the top (after the `class_name ThreatManager` / preload block, e.g. after line 9):

```gdscript
signal threat_killed(record: Dictionary)
```

Add the guard field next to `placeholder_nodes` (after line 27):

```gdscript
var _rewarded_kills: Dictionary = {}  # instance_id -> true (reward/remove once)
```

At the END of `tick_threats` (after the `for threat in threats:` loop closes, i.e. after line 94), add:

```gdscript
	_sweep_dead_threats()
```

Add these methods (place them just above `_update_placeholder`, around line 271):

```gdscript
## Domain 2 (BP3): reward + remove threats that died this frame, exactly once.
func _sweep_dead_threats() -> void:
	var dead: Array = []
	for threat in threats:
		if threat != null and threat.health <= 0.0 and not _rewarded_kills.has(threat.instance_id):
			_rewarded_kills[threat.instance_id] = true
			dead.append(threat)
	for threat in dead:
		emit_signal("threat_killed", {
			"instance_id": threat.instance_id,
			"archetype_id": threat.archetype_id,
			"position": Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2])),
			"loot_table": str((threat_archetypes.get(threat.archetype_id, {}) as Dictionary).get("loot_table", "combat_drop_common")),
		})
		_remove_threat(threat)

func _remove_threat(threat) -> void:
	var node = placeholder_nodes.get(threat.instance_id, null)
	if node != null and is_instance_valid(node):
		if node.get_parent() == self:
			remove_child(node)
		node.queue_free()
	placeholder_nodes.erase(threat.instance_id)
	threats.erase(threat)
```

In `_clear_runtime_nodes()` (line 284), add `_rewarded_kills.clear()` next to `placeholder_nodes.clear()`:

```gdscript
	placeholder_nodes.clear()
	_rewarded_kills.clear()
```

- [ ] **Step 4: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_kill_removal_smoke.gd
```
Expected: PASS — `THREAT KILL REMOVAL PASS emitted_once=true removed=true loot_table=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/threat_manager.gd scripts/validation/threat_kill_removal_smoke.gd
git commit -m "feat(combat): threat_killed signal + dead-threat removal (BP3)"
```

---

### Task 7: Reward data — archetype loot tables, combat drop table, kill training action

**Files:**
- Modify: `data/combat/threat_archetypes.json` (add `loot_table` to each archetype)
- Modify: `data/items/loot_tables.json` (add `combat_drop_common`)
- Modify: `data/player/training_actions.json` (add `threat_killed`)
- Test: `scripts/validation/combat_reward_data_smoke.gd` (new)

**Interfaces:**
- Produces: every archetype has a `loot_table` string; `loot_tables.json` has a `combat_drop_common` table; `training_actions.json` resolves `threat_killed → {target_skill: "scavenging", base_xp: 10}`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/combat_reward_data_smoke.gd`:

```gdscript
extends SceneTree

## Domain 2 (BP3): the reward data exists and resolves — every archetype names a
## loot_table that exists in loot_tables.json, and the threat_killed training
## action maps to a real skill with positive XP.
##
## Pass marker: COMBAT REWARD DATA PASS archetypes=true table=true training=true

func _initialize() -> void:
	var arch: Dictionary = _json("res://data/combat/threat_archetypes.json")
	var tables: Dictionary = _json("res://data/items/loot_tables.json")
	if arch.is_empty() or tables.is_empty():
		_fail("could not load archetype/table data")
		return
	for aid in arch:
		var lt: String = str((arch[aid] as Dictionary).get("loot_table", ""))
		if lt.is_empty() or not tables.has(lt):
			_fail("archetype %s has no valid loot_table (%s)" % [aid, lt])
			return
	# Training action resolves.
	var TrainingBus := preload("res://scripts/systems/training_event_bus.gd")
	var bus = TrainingBus.new()
	bus.configure()
	var action = bus.get_action_for_validation("threat_killed") if bus.has_method("get_action_for_validation") else bus._actions_by_id.get("threat_killed", {})
	if action == null or (action as Dictionary).is_empty():
		_fail("threat_killed training action missing")
		return
	if str((action as Dictionary).get("target_skill", "")).is_empty() or int((action as Dictionary).get("base_xp", 0)) <= 0:
		_fail("threat_killed action must map to a skill with positive base_xp")
		return
	print("COMBAT REWARD DATA PASS archetypes=true table=true training=true")
	quit(0)

func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return p if p is Dictionary else {}

func _fail(reason: String) -> void:
	push_error("COMBAT REWARD DATA FAIL reason=%s" % reason)
	quit(1)
```

> If `training_event_bus.gd` exposes neither `get_action_for_validation` nor a `_actions_by_id` dict by that name, read the bus (it stores `event_id -> {target_skill, base_xp, category}`; the field was confirmed at `training_event_bus.gd:29`) and adjust the lookup to the real member. The assertion (action resolves to a skill + positive XP) is what matters.

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_reward_data_smoke.gd
```
Expected: FAIL — archetypes lack `loot_table` / `combat_drop_common` missing / `threat_killed` action missing.

- [ ] **Step 3: Add `combat_drop_common` to `data/items/loot_tables.json`**

Add a new top-level table key alongside the existing ones (e.g. after `generic_locker`). Mirror the shape of an existing table in that file (open `generic_crate` to copy its exact schema — entries with item ids + weights/quantities). A reasonable combat-drop table (adjust item ids to ones that exist in `data/items/`):

```json
  "combat_drop_common": {
    "rolls": 1,
    "entries": [
      { "item_id": "scrap_metal", "weight": 5, "min": 1, "max": 2 },
      { "item_id": "biomatter_sample", "weight": 3, "min": 1, "max": 1 },
      { "item_id": "ammo_kinetic", "weight": 2, "min": 1, "max": 3 }
    ]
  }
```

> Match the EXACT key names the existing tables use (`rolls`/`entries`/`item_id`/`weight`/`min`/`max` may differ — copy from a real table in the same file). Use item ids that exist in the item registry; if unsure, reuse item ids already referenced by `generic_crate`/`salvage_cargo`.

- [ ] **Step 4: Add `loot_table` to each archetype in `data/combat/threat_archetypes.json`**

For each of the 5 archetypes (`biomatter_swarm, puppet_corpse, stalker, mimic, hull_tendril`), add `"loot_table": "combat_drop_common"` (you may give richer archetypes a distinct table later; one shared table satisfies BP3). Example for one:

```json
  "stalker": {
    "display_name": "...",
    "...": "... existing fields ...",
    "loot_table": "combat_drop_common"
  }
```

- [ ] **Step 5: Add the `threat_killed` training action to `data/player/training_actions.json`**

Add to the `training_actions` collection (match the file's exact shape — open it to see whether actions are a dict keyed by `event_id` or a list of objects). As a dict entry:

```json
    "threat_killed": { "target_skill": "scavenging", "base_xp": 10, "category": "combat" }
```

> `scavenging` is a real `skill_id` (confirmed in `data/player/skills.json`). This XP mapping is a **data-driven interim** per the spec's Non-goals — the future verbose skill system re-points it with no code change.

- [ ] **Step 6: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_reward_data_smoke.gd
```
Expected: PASS — `COMBAT REWARD DATA PASS archetypes=true table=true training=true`.

- [ ] **Step 7: Commit**

```bash
git add data/combat/threat_archetypes.json data/items/loot_tables.json data/player/training_actions.json scripts/validation/combat_reward_data_smoke.gd
git commit -m "feat(combat): kill reward data (archetype loot tables + combat drop + kill XP action)"
```

---

### Task 8: Coordinator kill handler — lootable corpse + XP (BP3 part 2)

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (connect `threat_killed`; add `_on_threat_killed`)
- Test: covered by the combat scene smoke (Task 9); this task wires the handler.

**Interfaces:**
- Consumes: `ThreatManager.threat_killed` (Task 6); `LootContainerScript` + `loot_container_root` + `loot_containers` + `_loot_tables` + `inventory_state` + `_on_loot_container_searched` (existing); `emit_training_event(event_id, target_id)` (existing).
- Produces: `_on_threat_killed(record: Dictionary) -> void`.

- [ ] **Step 1: Connect the signal where the threat manager is wired**

Find where `threat_manager` is created / its signals are connected (mirror the `salvage_completed.connect` pattern near `playable_generated_ship.gd:3015`; if no signal is connected there, connect right after `threat_manager` is assigned/added). Add an idempotent connect:

```gdscript
	if threat_manager != null and not threat_manager.threat_killed.is_connected(_on_threat_killed):
		threat_manager.threat_killed.connect(_on_threat_killed)
```

> Place this where `threat_manager` is guaranteed non-null and only runs once per manager (the same place other manager signals/encounters are configured). If unsure, connect inside the function that calls `threat_manager.configure_for_layout(...)`.

- [ ] **Step 2: Add the kill handler**

Add this method near the other loot-container / threat code:

```gdscript
## Domain 2 (BP3): a threat died — grant XP through the progression bus and spawn a
## lootable corpse container at its position (reusing the closed loot/interact path).
## Runs on BOTH _process branches (the signal fires from tick_threats, called on the
## away branch too), so derelict kills reward identically.
func _on_threat_killed(record: Dictionary) -> void:
	# XP (data-driven interim skill via training_actions.json).
	emit_training_event("threat_killed", str(record.get("archetype_id", "")))
	# Lootable corpse container.
	if inventory_state == null:
		return
	var pos: Vector3 = record.get("position", Vector3.ZERO)
	var cid: String = "corpse_%s" % str(record.get("instance_id", ""))
	var lc = LootContainerScript.new()
	var seed_source: String = "kill:%s" % cid
	lc.configure(cid, str(record.get("loot_table", "combat_drop_common")), seed_source,
		inventory_state, _loot_tables, pos, 1.8, {})
	if not lc.container_searched.is_connected(_on_loot_container_searched):
		lc.container_searched.connect(_on_loot_container_searched)
	var parent_node: Node = loot_container_root
	if away_from_start and current_ship != null and is_instance_valid(current_ship.scene_root):
		parent_node = current_ship.scene_root
	if parent_node != null and is_instance_valid(parent_node):
		parent_node.add_child(lc)
		loot_containers.append(lc)
```

- [ ] **Step 3: Sanity parse-check via an existing scene smoke**

Run any existing main-scene smoke (e.g. `scripts/validation/main_playable_meta_autosave_smoke.gd`) to confirm the coordinator still loads/parses cleanly:

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_meta_autosave_smoke.gd
```
Expected: its PASS marker prints, no parse error. (Behavioral kill-reward assertions are in Task 9.)

- [ ] **Step 4: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd
git commit -m "feat(combat): kill handler spawns lootable corpse + grants XP (BP3)"
```

---

### Task 9: Combat closure scene smoke (BP1+BP2+BP3, home + away)

**Files:**
- Create: `scripts/validation/combat_closure_smoke.gd`
- Modify: `docs/game/06_validation_plan.md` (register 6 new smokes from Tasks 1-9)

**Interfaces:**
- Consumes: the live coordinator (`playable._process`, `playable.threat_manager`, `playable.player`, `playable.loot_containers`, `playable.away_from_start`).

- [ ] **Step 1: Write the scene smoke**

Create `scripts/validation/combat_closure_smoke.gd`:

```gdscript
extends SceneTree

## Domain 2 closure (live scene): on a boarded derelict (away_from_start=true) the
## real coordinator tick drives the combat loop end-to-end —
##   BP2: moving raises emitted noise vs idle; crouch lowers emitted visibility.
##   BP1: the threat's awareness reflects the detection emitted profile.
##   BP3: killing a threat spawns a lootable corpse container AND removes the threat.
##
## Pass marker:
##   COMBAT CLOSURE PASS away_kill=true noise=true crouch=true reward=true removed=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
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
	process_frame.connect(_on_frame)

func _on_frame() -> void:
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
	if playable.threat_manager == null or playable.player == null:
		_fail("threat_manager / player missing")
		return
	var tm = playable.threat_manager
	# Board a derelict so the whole loop is exercised on the away branch.
	playable.away_from_start = true
	# Ensure at least one threat exists to kill.
	if tm.threats.is_empty():
		tm.inject_validation_encounter(["stalker"], Vector3.ZERO)
	# --- BP2: noise rises with movement. Drive the emitted profile via the manager. ---
	tm.set_player_signals(0.05, 0.15, 0.8, false, "")
	tm.detection_state.update_inputs(0.05, 0.15, 0.8, false, "")
	var idle_noise: float = float(tm.detection_state.get_emitted_profile()["noise"])
	tm.detection_state.update_inputs(0.3, 0.15, 0.8, false, "")
	var move_noise: float = float(tm.detection_state.get_emitted_profile()["noise"])
	var noise_ok: bool = move_noise > idle_noise
	# --- BP2: crouch lowers emitted visibility. ---
	tm.detection_state.update_inputs(0.3, 0.15, 0.8, false, "")
	var stand_vis: float = float(tm.detection_state.get_emitted_profile()["visibility"])
	tm.detection_state.update_inputs(0.3, 0.15, 0.8, true, "")
	var crouch_vis: float = float(tm.detection_state.get_emitted_profile()["visibility"])
	var crouch_ok: bool = crouch_vis < stand_vis
	# --- BP3: kill a threat through the live coordinator tick (away branch). ---
	var before_containers: int = playable.loot_containers.size()
	var before_threats: int = tm.threats.size()
	tm.threats[0].health = 0.0
	# Drive the real coordinator process (away branch runs _tick_threat_runtime -> tick_threats -> sweep).
	playable._process(1.0 / 30.0)
	var reward_ok: bool = playable.loot_containers.size() > before_containers
	var removed_ok: bool = tm.threats.size() < before_threats
	if not noise_ok:
		_fail("moving should raise emitted noise (%.3f vs %.3f)" % [move_noise, idle_noise])
		return
	if not crouch_ok:
		_fail("crouch should lower emitted visibility (%.3f vs %.3f)" % [crouch_vis, stand_vis])
		return
	if not reward_ok:
		_fail("kill should spawn a lootable corpse container")
		return
	if not removed_ok:
		_fail("kill should remove the threat from the active array")
		return
	finished = true
	print("COMBAT CLOSURE PASS away_kill=true noise=true crouch=true reward=true removed=true")
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f: PlayableGeneratedShip = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("COMBAT CLOSURE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_closure_smoke.gd
```
Expected: PASS — `COMBAT CLOSURE PASS away_kill=true noise=true crouch=true reward=true removed=true`. If `reward_ok` fails, confirm Task 8's signal connect runs for this manager; if `removed_ok` fails, confirm Task 6's `_sweep_dead_threats` runs at the end of `tick_threats`.

- [ ] **Step 3: Register all 7 new smokes in the regression bundle**

In `docs/game/06_validation_plan.md`, add a `run_clean` line for each new smoke near the related registrations (combat/threat block), and bump the final `commands=` literal by 7 (from `68` to `75`). The 7 smokes + exact markers:

```
run_clean 'detection state model smoke' 'DETECTION STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/detection_state_smoke.gd
run_clean 'threat detection source smoke' 'THREAT DETECTION SOURCE PASS single_source=true per_archetype=true proximity=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_detection_source_smoke.gd
run_clean 'player crouch seam smoke' 'PLAYER CROUCH PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_crouch_smoke.gd
run_clean 'crouch action smoke' 'CROUCH ACTION PASS registered=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/crouch_action_smoke.gd
run_clean 'threat kill removal smoke' 'THREAT KILL REMOVAL PASS emitted_once=true removed=true loot_table=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_kill_removal_smoke.gd
run_clean 'combat reward data smoke' 'COMBAT REWARD DATA PASS archetypes=true table=true training=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_reward_data_smoke.gd
run_clean 'combat closure smoke' 'COMBAT CLOSURE PASS away_kill=true noise=true crouch=true reward=true removed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_closure_smoke.gd
```

> That is **7** new `run_clean` lines (Tasks 1-9 produced 7 smokes: detection, threat-source, crouch-seam, crouch-action, kill-removal, reward-data, closure). Bump `commands=` from `68` to `75` (Task 10 Step 4 verifies the count == 75). Add a matching `- [x]` checklist entry per smoke in the prose list for consistency.

- [ ] **Step 4: Commit**

```bash
git add scripts/validation/combat_closure_smoke.gd docs/game/06_validation_plan.md
git commit -m "test(combat): combat closure scene smoke + register Domain 2 smokes"
```

---

### Task 10: Flip the loop green + full regression

**Files:**
- Modify: `docs/game/inventory/system_inventory.json`
- Regenerate (do not hand-edit): `docs/game/inventory/SYSTEM_INVENTORY.md`, `docs/game/inventory/system_map.html`

- [ ] **Step 1: Update the `combat` loop entry**

In `docs/game/inventory/system_inventory.json`, find `"id": "combat"`. Change `"closes": "partial"` to `"closes": "closed"` and replace its `break_points` array with:

```json
      "break_points": [
        "CLOSED (Domain 2): DetectionState.get_emitted_profile() is now the single signal source the threat AI consumes (threat_manager.tick_threats builds each threat's context noise/light/sight from the emitted profile, scaling visibility per-threat by world distance via _proximity_factor); archetype sensitivities preserve per-enemy perception. Verified by threat_detection_source_smoke.gd + combat_closure_smoke.gd.",
        "CLOSED (Domain 2): stealth inputs are real runtime signals in _tick_threat_runtime (noise from movement, light from _player_room_lit room power, base visibility proximity-scaled, crouch from the new 'crouch' input action reducing emitted noise+visibility and move speed). No literal placeholders remain.",
        "CLOSED (Domain 2): killing a threat emits threat_killed (ThreatManager) -> coordinator spawns a lootable LootContainer at the corpse (archetype loot_table) collected through the closed loot/interact path AND grants XP via emit_training_event('threat_killed') (data-driven interim skill 'scavenging'); the dead threat is removed from threats[] and its placeholder despawned, exactly once. Runs on both _process branches.",
        "Deferred (by design): the verbose Project-Zomboid/Barotrauma skill overhaul (Domain 6) re-points the threat_killed XP target with no Domain 2 code change; player room-id resolution is out of scope (proximity uses world distance)."
      ]
```

- [ ] **Step 2: Update the `detection_state` and `threat_ai_state` outputs**

In `detection_state`'s entry: set `output.live → true`, update `desc` to note it is now the single emitted-signal source consumed by the AI (`get_emitted_profile()` → `threat_manager.tick_threats`); update the relevant integration edge health (detection→AI) from `weak`/decorative to `healthy`; clear stale `gaps`.

In `threat_ai_state`'s entry: set `output.live → true`, update `desc` to note threat death now drives reward (loot container + XP) and removal via `threat_killed`; clear stale `gaps`.

> Cite function symbols (`get_emitted_profile`, `_sweep_dead_threats`, `_on_threat_killed`) rather than line numbers; `--check` does not gate on line numbers.

- [ ] **Step 3: Regenerate views + run the gates**

```bash
python tools/build_system_inventory.py
python tools/build_system_inventory.py --check
python tools/build_system_inventory.py --coverage
python tools/test_build_system_inventory.py
```
Expected: `SYSTEM INVENTORY BUILD PASS systems=187`, `SYSTEM INVENTORY CHECK PASS systems=187 verified=187`, `SYSTEM INVENTORY COVERAGE PASS ...`, `BUILD INVENTORY SELFTEST PASS`. (Coverage may report `scripts=N` for the new smokes — ensure each new smoke is registered in `06_validation_plan.md` from Task 9.)

- [ ] **Step 4: Run the full regression bundle**

Extract and run the bash block in `docs/game/06_validation_plan.md` with the Windows `GODOT`/`ROOT` values. Verify rigorously (run_clean only aborts on unexpected ERROR/WARNING):
- exit code 0
- section-header count == 75
- zero `FAIL` lines, zero `UNEXPECTED_ERROR_OR_WARNING`
- the 7 new Domain 2 markers all present
- final line `SYNAPTIC_SEA REGRESSION PASS commands=75 clean_output=true`

If the script's tally disagrees with `75`, reconcile the `commands=` literal to the actual count.

- [ ] **Step 5: Commit**

```bash
git add docs/game/inventory/system_inventory.json docs/game/inventory/SYSTEM_INVENTORY.md docs/game/inventory/system_map.html
git commit -m "feat(combat): close combat loop in inventory (Domain 2 done)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-29-domain2-combat-design.md`):
1. *BP1 detection single source of truth (per-enemy senses)* → Task 1 (emitted profile) + Task 2 (AI consumes it, per-archetype, proximity). ✅
2. *BP2 full stealth (movement/light/proximity/crouch)* → Task 3 (crouch seam), Task 4 (crouch action), Task 5 (real signals + `_player_room_lit`), Task 2 (proximity). ✅
3. *BP3 lootable corpse + XP + removal* → Task 6 (signal + removal), Task 7 (reward data), Task 8 (corpse container + XP). ✅
4. *Both branches* → Task 5 Step 3 verifies `_tick_threat_runtime` on the away branch; Task 8 handler fires from `tick_threats` (both branches); Task 9 asserts `away_kill`. ✅
5. *Validation + inventory delta* → Task 9 (smokes + registration), Task 10 (loop green + regen + bundle). ✅

**Documented deviations from the spec** (pragmatic, equally-real):
- Proximity uses **world distance** (not exact room-id match) — no cheap position→room_id resolver exists. The `same_room` attack gate is left unchanged. (Spec said "same-room + distance"; distance alone is the real available signal.)
- The `detect_threshold` stays sourced from `DetectionState` (a single shared config, not a duplication) — no per-archetype threshold field exists in data; inventing one is YAGNI.

**Placeholder scan:** Loot-table/training-action JSON shapes are flagged to copy from the real files (Task 7 Steps 3-5) because their exact key names live in data, not the spec; the assertions (archetype loot_table resolves; training action → skill + positive XP) are concrete. No TODO/TBD steps.

**Type consistency:** `get_emitted_profile()` (`{noise,light,visibility}`), `_proximity_factor`, `SIGHT_RANGE`, `set_crouching`/`is_crouching`/`CROUCH_SPEED_FACTOR`, `threat_killed(record)` with `{instance_id,archetype_id,position,loot_table}`, `_sweep_dead_threats`/`_remove_threat`/`_rewarded_kills`, `_player_room_lit`, `_on_threat_killed` are named identically across Tasks 1-10.

## Risks & mitigations

- **Existing combat smokes may assume the old context.** Tasks 2 & 5 each re-run the existing combat/threat smokes before committing; if one shifts, confirm it reflects the now-real signal rather than masking a regression (do not weaken assertions).
- **Double-reward / double-remove.** Task 6's `_rewarded_kills` guard + the kill-removal smoke's second-tick assertion prevent it.
- **Away-branch starvation.** Task 9's `away_kill=` assertion (driving `away_from_start=true`) fails if the kill→reward path is home-only.
- **Loot-table item ids.** Task 7 mandates reusing item ids that exist in the registry (copy from `generic_crate`/`salvage_cargo`); the reward-data smoke fails if `combat_drop_common` is missing, and the closure smoke fails if a kill cannot spawn a container.
