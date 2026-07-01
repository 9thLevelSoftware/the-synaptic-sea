# Domain 4 — Ship Systems closure + Web Infestation foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the `ship_systems` loop green by giving `hull_integrity_state` a live damage source (a per-ship `WebInfestationState` — the hub is canonically trapped in the biomatter web) and making the hub ship sim run live on BOTH `_process` branches (no away-pause).

**Architecture:** A new pure `RefCounted` `WebInfestationState` model (coverage grows while web-attached → returns hull-damage magnitude per tick) owned by the coordinator for the hub hull. A mechanical refactor extracts the fire + field-crafting ticks out of `_recompute_expanded_ship_systems` so the recompute is safe to run on both branches without double-ticking. The away branch then runs `ship_systems_manager.advance` + web hull damage + recompute, mirroring the home branch.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes.

**Design spec:** `docs/superpowers/specs/2026-06-30-domain4-ship-systems-design.md`.

## Global Constraints

- **Godot binary (Windows):** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`. Use forward slashes.
- **Validation is the definition of done.** TRUST THE PASS MARKER, never the exit code (`--script` can exit 0 on parse errors). A smoke passes only when its exact marker line prints AND no non-allowlisted `ERROR:`/`WARNING:` appears.
- **Baseline noise allowlist (ignore these, they are expected):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...` on every headless `--script` run. Any OTHER `ERROR:`/`WARNING:` blocks completion.
- **Both `_process` branches.** Every per-frame tick added MUST run in the `away_from_start` (derelict) branch AND the home branch of `playable_generated_ship.gd::_process`. The closure smoke asserts this with an `away_ticks=` value driving `away_from_start = true`.
- **Typed GDScript** for all new code; Resources/RefCounted are data and never touch the scene tree, Nodes are behavior.
- **Save is additive.** Do NOT bump `RunSnapshot.CURRENT_SLICE_VERSION`. New summary fields read via `.get(key, {})` so older saves load with defaults (Domain 3 precedent).
- **Conventional Commits** (`feat:`/`fix:`/`refactor:`/`test:`/`docs:`). Every commit ends with these two trailers verbatim:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx
  ```
- **Git hygiene:** stage only the exact files named in each task with `git add <paths>`. NEVER `git add -A`. Never stage `project.godot`, `.godot/`, `*.uid`, or anything under `addons/`.
- **Plan-level refinement of the spec (documented):** the spec mentions a per-derelict `WebInfestationState`; the foundation only needs a per-derelict *attachment flag* (derelicts have no hull to damage yet), so `ShipInstance` gets a lightweight `web_attached: bool` instead of a full model. This is strictly smaller and is the hook the follow-on cut-free action will flip.

---

### Task 1: `WebInfestationState` pure model + config + model smoke

**Files:**
- Create: `scripts/systems/web_infestation_state.gd`
- Create: `data/ship_systems/web_infestation.json`
- Create: `scripts/validation/web_infestation_state_smoke.gd`

**Interfaces:**
- Produces: `WebInfestationState` with `configure(config: Dictionary) -> void`, `tick(delta: float, contact: bool) -> float` (advances `coverage`, returns hull-damage magnitude this tick), `cut_free() -> void`, `get_summary() -> Dictionary`, `apply_summary(summary: Dictionary) -> bool`, `get_status_lines() -> PackedStringArray`. Public fields: `attached_to_web: bool`, `coverage: float`, `growth_rate`/`recession_rate`/`damage_rate`/`contact_boost: float`. Discriminator constant `HAZARD_KIND := "web_infestation"`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/web_infestation_state_smoke.gd`:

```gdscript
extends SceneTree

## Domain 4 Task 1: WebInfestationState pure model.
## - Attached: coverage grows over time and tick() returns hull damage > 0.
## - Cut free: coverage recedes.
## - get_summary/apply_summary round-trip; apply_summary rejects a wrong hazard_kind.
## Marker: WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true

const WebInfestationStateScript := preload("res://scripts/systems/web_infestation_state.gd")

func _initialize() -> void:
	var grows := _test_grows_and_damages()
	var recedes := _test_recedes_when_cut()
	var roundtrip := _test_save_roundtrip()
	var reject := _test_reject_bad_kind()
	if grows and recedes and roundtrip and reject:
		print("WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true")
		quit(0)
	else:
		push_error("WEB INFESTATION FAIL grows=%s recedes=%s roundtrip=%s reject=%s" % [str(grows), str(recedes), str(roundtrip), str(reject)])
		quit(1)

func _test_grows_and_damages() -> bool:
	var w = WebInfestationStateScript.new()
	w.configure({})  # defaults: attached_to_web = true, seed_coverage = 0.0
	var dmg: float = 0.0
	for i in range(50):
		dmg += w.tick(1.0, false)
	return w.coverage > 0.5 and dmg > 0.0

func _test_recedes_when_cut() -> bool:
	var w = WebInfestationStateScript.new()
	w.configure({"seed_coverage": 0.8})
	w.cut_free()
	var before: float = w.coverage
	for i in range(5):
		w.tick(1.0, false)
	return (not w.attached_to_web) and w.coverage < before

func _test_save_roundtrip() -> bool:
	var w = WebInfestationStateScript.new()
	w.configure({"seed_coverage": 0.42})
	w.cut_free()
	var summary: Dictionary = w.get_summary()
	var w2 = WebInfestationStateScript.new()
	w2.configure({})
	var ok: bool = w2.apply_summary(summary)
	return ok and absf(w2.coverage - 0.42) < 0.001 and w2.attached_to_web == false

func _test_reject_bad_kind() -> bool:
	var w = WebInfestationStateScript.new()
	w.configure({})
	return w.apply_summary({"hazard_kind": "not_web", "coverage": 0.9}) == false
```

- [ ] **Step 2: Run the smoke to verify it fails**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/web_infestation_state_smoke.gd
```
Expected: FAIL — the preload of a non-existent `web_infestation_state.gd` errors / no PASS marker.

- [ ] **Step 3: Create the config file**

Create `data/ship_systems/web_infestation.json`:

```json
{
  "growth_rate": 0.02,
  "recession_rate": 0.05,
  "damage_rate": 0.03,
  "contact_boost": 0.03,
  "seed_coverage": 0.0,
  "attached_to_web": true
}
```

- [ ] **Step 4: Implement the model**

Create `scripts/systems/web_infestation_state.gd`:

```gdscript
extends RefCounted
class_name WebInfestationState

## Domain 4: the biomatter-web infestation that slowly devours a ship's hull.
## The hub is trapped in the Sargasso web (attached_to_web = true by default);
## coverage grows over time and translates into hull damage applied by the
## coordinator. A ship cut free from the web sees its coverage recede.
##
## Pure data — never touches the scene tree. A CONTINUOUS growth/drain hazard,
## not phase-based: the same exemption class as OxygenState, so it is NOT part of
## the PhaseTimer hazard_contract_smoke. It carries a hazard_kind discriminator
## purely for save-load robustness (apply_summary rejects a mismatched kind).

const HAZARD_KIND: String = "web_infestation"

var attached_to_web: bool = true
var coverage: float = 0.0          # 0..1 infestation level
var growth_rate: float = 0.02      # coverage/sec while attached
var recession_rate: float = 0.05   # coverage/sec while cut free
var damage_rate: float = 0.03      # hull damage/sec at full coverage
var contact_boost: float = 0.03    # extra growth/sec while docked to an attached derelict

func configure(config: Dictionary) -> void:
	growth_rate = maxf(0.0, float(config.get("growth_rate", 0.02)))
	recession_rate = maxf(0.0, float(config.get("recession_rate", 0.05)))
	damage_rate = maxf(0.0, float(config.get("damage_rate", 0.03)))
	contact_boost = maxf(0.0, float(config.get("contact_boost", 0.03)))
	coverage = clampf(float(config.get("seed_coverage", 0.0)), 0.0, 1.0)
	attached_to_web = bool(config.get("attached_to_web", true))

## Advance coverage by one tick and return the hull-damage magnitude for this tick.
## `contact` true = currently docked to a still-web-attached derelict (faster growth).
func tick(delta: float, contact: bool) -> float:
	if delta <= 0.0:
		return 0.0
	if attached_to_web:
		var rate: float = growth_rate + (contact_boost if contact else 0.0)
		coverage = clampf(coverage + rate * delta, 0.0, 1.0)
	else:
		coverage = clampf(coverage - recession_rate * delta, 0.0, 1.0)
	return coverage * damage_rate * delta

func cut_free() -> void:
	attached_to_web = false

func get_summary() -> Dictionary:
	return {
		"hazard_kind": HAZARD_KIND,
		"attached_to_web": attached_to_web,
		"coverage": coverage,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("hazard_kind", "")) != HAZARD_KIND:
		return false
	attached_to_web = bool(summary.get("attached_to_web", attached_to_web))
	coverage = clampf(float(summary.get("coverage", coverage)), 0.0, 1.0)
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if coverage > 0.0:
		var tag: String = "SPREADING" if attached_to_web else "RECEDING"
		lines.append("Web Infestation %d%% [%s]" % [int(round(coverage * 100.0)), tag])
	return lines
```

- [ ] **Step 5: Run the smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/web_infestation_state_smoke.gd
```
Expected: prints `WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true`, only baseline-allowlist noise otherwise.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/web_infestation_state.gd data/ship_systems/web_infestation.json scripts/validation/web_infestation_state_smoke.gd
git commit -F - <<'EOF'
feat: add WebInfestationState model (Domain 4 live hull damage source)

Pure RefCounted growth/drain hazard: coverage grows while web-attached and
returns a per-tick hull-damage magnitude; recedes when cut free. hazard_kind
discriminator for save robustness; not part of the PhaseTimer contract (oxygen
exemption class). Adds web_infestation.json tuning + pure-model smoke.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx
EOF
```

---

### Task 2: Extract fire + field-crafting ticks out of `_recompute_expanded_ship_systems` (pure refactor, no behavior change)

This makes the recompute safe to call on BOTH `_process` branches in Task 3 without double-ticking the fire/field-crafting the away branch already owns.

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` — `_recompute_expanded_ship_systems` (currently ~`:1347`), the `_process` away branch fire block (~`:4933-4937`), the `_process` home branch (~`:4965-4974`); add a new helper `_tick_active_fire`.

**Interfaces:**
- Consumes: existing `_active_fire_state()`, `_build_fire_context()`, `_refresh_fire_zones()`, `_apply_fire_system_damage(delta)`, `field_crafting_state`, `_on_field_craft_completed()`.
- Produces: `func _tick_active_fire(delta: float) -> void` — ticks the active ship's fire once and applies its system damage. After this task, `_recompute_expanded_ship_systems` no longer ticks fire or field crafting.

- [ ] **Step 1: Add the `_tick_active_fire` helper**

Add immediately ABOVE `func _recompute_expanded_ship_systems(delta: float) -> void:`:

```gdscript
## Tick the active ship's fire model (home: hub; away: derelict) once and apply
## its per-compartment system damage. Extracted from _recompute_expanded_ship_systems
## so the recompute can run on BOTH _process branches (Domain 4) without double-
## ticking the fire the away branch already owns. Call exactly once per branch.
func _tick_active_fire(delta: float) -> void:
	var afs = _active_fire_state()
	if afs == null:
		return
	if afs.tick(delta, _build_fire_context()):
		_refresh_fire_zones()
	# A burning compartment degrades the ship system housed there (M7-B Task 8).
	_apply_fire_system_damage(delta)
```

- [ ] **Step 2: Remove the fire block from `_recompute_expanded_ship_systems`**

Delete these lines (currently ~`:1369-1374`) from inside `_recompute_expanded_ship_systems`:

```gdscript
	var _afs_home = _active_fire_state()
	if _afs_home != null:
		if _afs_home.tick(delta, _build_fire_context()):
			_refresh_fire_zones()
		# M7-B Task 8: a burning compartment degrades the ship system housed there.
		_apply_fire_system_damage(delta)
```

- [ ] **Step 3: Remove the field-crafting tick from `_recompute_expanded_ship_systems`**

Delete this line + its body (currently ~`:1391-1392`) from inside `_recompute_expanded_ship_systems`:

```gdscript
	if field_crafting_state != null and field_crafting_state.tick(delta):
		_on_field_craft_completed()
```

(The recompute now ends after the `sustenance_state.tick(...)` block. The standalone-station power loop and extinguisher-recharge-port lines stay.)

- [ ] **Step 4: Replace the away-branch inline fire block with the helper call**

In `_process`, the `away_from_start` branch, replace this block (currently ~`:4933-4937`):

```gdscript
		var _afs_away = _active_fire_state()
		if _afs_away != null:
			if _afs_away.tick(delta, _build_fire_context()):
				_refresh_fire_zones()
			_apply_fire_system_damage(delta)
```

with:

```gdscript
		_tick_active_fire(delta)
```

(Leave the away-branch `field_crafting_state.tick(delta)` block — currently ~`:4950` — exactly as it is; the away branch keeps owning its own field-crafting tick.)

- [ ] **Step 5: Add the extracted ticks to the home branch**

In `_process`, the home branch, find:

```gdscript
	if ship_systems_manager != null:
		ship_systems_manager.advance(delta)
	_recompute_expanded_ship_systems(delta)
```

Change it to (adds the two extracted calls AFTER recompute):

```gdscript
	if ship_systems_manager != null:
		ship_systems_manager.advance(delta)
	_recompute_expanded_ship_systems(delta)
	_tick_active_fire(delta)
	if field_crafting_state != null and field_crafting_state.tick(delta):
		_on_field_craft_completed()
```

- [ ] **Step 6: Run the affected smokes to verify NO behavior change**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_suppression_state_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_life_support_vitals_smoke.gd
```
Expected markers, all unchanged:
- `MAIN PLAYABLE SHIP SYSTEMS EXPANDED PASS propulsion=true hull=true fire=true sustenance=true persistence=true`
- the fire suppression smoke's PASS marker
- `MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true seal_loop=true reachable=true`

If any marker differs or a non-allowlisted ERROR/WARNING appears, the extraction dropped or duplicated a call — fix before committing.

- [ ] **Step 7: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd
git commit -F - <<'EOF'
refactor: extract fire + field-crafting ticks out of recompute (Domain 4 prep)

_recompute_expanded_ship_systems no longer ticks the active fire model or field
crafting; both are now called explicitly once per _process branch via the new
_tick_active_fire helper. No behavior change at home — this lets the recompute
run on the away branch in the next task without double-ticking.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx
EOF
```

---

### Task 3: Wire `hull_web_state` live on both branches + `ShipInstance.web_attached` + closure smoke

**Files:**
- Modify: `scripts/systems/ship_instance.gd` — add `web_attached` field, `is_web_attached()`, persistence.
- Modify: `scripts/procgen/playable_generated_ship.gd` — preload const (~`:94`), config-path const (~`:150`), var decl (~`:348`), `_configure_expanded_ship_system_models` (~`:1325`), `_expanded_ship_systems_summary` (~`:1401`), load-path restore (~`:6313`), new helpers, both `_process` branches, validation seam.
- Create: `scripts/validation/ship_systems_closure_smoke.gd`

**Interfaces:**
- Consumes: `WebInfestationState` (Task 1); `_tick_active_fire` (Task 2); `hull_integrity_state` (`.compartments: Dictionary`, `.damage_compartment(id, amount)`, `.get_breach_count()`, `.average_integrity()`); `ship_systems_manager.advance(delta)`; `_recompute_expanded_ship_systems(delta)`; `life_support_expanded_state.get_health_drain_per_second()`; `current_ship`; `away_from_start`.
- Produces: `hull_web_state` (coordinator field); `_active_derelict_web_attached() -> bool`; `_apply_web_hull_damage(delta) -> void`; `advance_ship_systems_for_validation(delta) -> void`; `ShipInstance.is_web_attached() -> bool` + `web_attached: bool`.

- [ ] **Step 1: Add the closure smoke (failing)**

Create `scripts/validation/ship_systems_closure_smoke.gd`:

```gdscript
extends SceneTree

## Domain 4 Task 3: the ship_systems loop is live on the AWAY (derelict) branch.
## Drives away_from_start = true and asserts that, on the away branch:
##  - the hub web infestation ticks (coverage grows from 0),
##  - it damages the hub hull (average_integrity drops / a breach opens),
##  - the resulting breach engages the life-support atmosphere->vitals drain.
## ship_systems_manager.advance runs in the same away block as the web tick.
## Marker: SHIP SYSTEMS CLOSURE PASS away_ticks=<n> web_grew=true hull_damaged=true breach_to_vitals=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

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
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _validate() -> void:
	finished = true  # prevent re-entry across frames

	var coverage_before: float = playable.hull_web_state.coverage
	var integrity_before: float = playable.hull_integrity_state.average_integrity()

	# Force the AWAY branch and drive enough simulated seconds for the web to
	# breach a compartment (growth 0.05/s with contact, damage_rate 0.03/s).
	# Re-boost vitals each iteration so Domain 1 attrition / Domain 2 combat on the
	# away branch cannot kill the player mid-loop (which would reset the slice and
	# void the ship-systems assertion). This test isolates ship systems, not survival.
	playable.away_from_start = true
	var n: int = 0
	for i: int in range(60):
		if playable.vitals_state != null:
			playable.vitals_state.hunger = playable.vitals_state.max_hunger
			playable.vitals_state.thirst = playable.vitals_state.max_thirst
			playable.vitals_state.health = playable.vitals_state.max_health
		playable._process(1.0)
		n += 1

	var web_grew: bool = playable.hull_web_state.coverage > coverage_before + 0.05
	var hull_damaged: bool = playable.hull_integrity_state.average_integrity() < integrity_before - 0.05
	var breach_to_vitals: bool = playable.hull_integrity_state.get_breach_count() > 0 \
		and playable.life_support_expanded_state.get_health_drain_per_second() > 0.0

	if web_grew and hull_damaged and breach_to_vitals:
		print("SHIP SYSTEMS CLOSURE PASS away_ticks=%d web_grew=true hull_damaged=true breach_to_vitals=true" % n)
		_cleanup_and_quit(0)
	else:
		_fail("web_grew=%s hull_damaged=%s breach_to_vitals=%s cov_before=%.3f cov_after=%.3f integ_before=%.3f integ_after=%.3f breaches=%d drain=%.4f" % [
			str(web_grew), str(hull_damaged), str(breach_to_vitals),
			coverage_before, playable.hull_web_state.coverage,
			integrity_before, playable.hull_integrity_state.average_integrity(),
			playable.hull_integrity_state.get_breach_count(),
			playable.life_support_expanded_state.get_health_drain_per_second()
		])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child: Node in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("SHIP SYSTEMS CLOSURE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run the closure smoke to verify it fails**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_closure_smoke.gd
```
Expected: FAIL — `playable.hull_web_state` does not exist yet (nil access / no PASS marker).

- [ ] **Step 3: Add `web_attached` to `ShipInstance`**

In `scripts/systems/ship_instance.gd`, after the `fire_seeded` field block (~`:80`), add:

```gdscript
# Domain 4: is this ship still in contact with the biomatter web? Derelicts
# generate attached (floating in the Sargasso). The foundation reads this to
# decide whether docking to this ship accelerates the hub's web growth; the
# follow-on cut-free action will flip it. Persisted only when false (additive).
var web_attached: bool = true
```

In `get_summary()`, before `return result`, add:

```gdscript
	if not web_attached:
		result["web_attached"] = false
```

In `apply_summary()`, before `return true`, add:

```gdscript
	web_attached = bool(summary.get("web_attached", web_attached))
```

Add the accessor near `has_fire()` (~`:220`):

```gdscript
## True iff this ship is still in contact with the biomatter web.
func is_web_attached() -> bool:
	return web_attached
```

- [ ] **Step 4: Declare the hub web state on the coordinator**

In `scripts/procgen/playable_generated_ship.gd`:

Near the other model preloads (~`:94`, beside `HullIntegrityStateScript`), add:

```gdscript
const WebInfestationStateScript := preload("res://scripts/systems/web_infestation_state.gd")
```

Near the config-path consts (~`:150`, beside `HULL_COMPARTMENTS_CONFIG_PATH`), add:

```gdscript
const WEB_INFESTATION_CONFIG_PATH: String = "res://data/ship_systems/web_infestation.json"
```

Near the `hull_integrity_state` var decl (~`:348`), add:

```gdscript
var hull_web_state  # WebInfestationState (hub hull's live web damage source)
```

- [ ] **Step 5: Configure + persist + restore the hub web state**

In `_configure_expanded_ship_system_models()`, immediately after the `hull_integrity_state.configure(...)` line (~`:1325`), add:

```gdscript
	hull_web_state = WebInfestationStateScript.new()
	hull_web_state.configure(_load_json_dict(WEB_INFESTATION_CONFIG_PATH))
```

In `_expanded_ship_systems_summary()` (~`:1401`), add this entry to the returned dictionary (after `hull_integrity_summary`):

```gdscript
		"web_infestation_summary": hull_web_state.get_summary() if hull_web_state != null else {},
```

In the load-path restore block, immediately after the `hull_integrity_state.apply_summary(...)` lines (~`:6312-6313`), add:

```gdscript
			if hull_web_state != null:
				hull_web_state.apply_summary(snapshot.ship_systems_summary.get("web_infestation_summary", {}))
```

- [ ] **Step 6: Add the web-damage + contact helpers**

Add these two functions near `_recompute_expanded_ship_systems` (e.g., directly below `_tick_active_fire`):

```gdscript
## Foundation contagion seed: while away and docked to a still-web-attached
## derelict, the web creeps onto the hub faster (contact boost). Full dock-graph
## spread is the follow-on web spec.
func _active_derelict_web_attached() -> bool:
	return away_from_start and current_ship != null and current_ship.is_web_attached()

## Advance the hub web infestation by one tick and apply its hull damage across
## every hub compartment. The live damage source closing the ship_systems loop.
func _apply_web_hull_damage(delta: float) -> void:
	if hull_web_state == null or hull_integrity_state == null:
		return
	var dmg: float = hull_web_state.tick(delta, _active_derelict_web_attached())
	if dmg <= 0.0:
		return
	for cid in hull_integrity_state.compartments.keys():
		hull_integrity_state.damage_compartment(str(cid), dmg)
```

- [ ] **Step 7: Apply web damage on the HOME branch**

In `_process` home branch, change (from Task 2's state):

```gdscript
	if ship_systems_manager != null:
		ship_systems_manager.advance(delta)
	_recompute_expanded_ship_systems(delta)
```

to:

```gdscript
	if ship_systems_manager != null:
		ship_systems_manager.advance(delta)
	_apply_web_hull_damage(delta)
	_recompute_expanded_ship_systems(delta)
```

- [ ] **Step 8: Run the hub systems sim on the AWAY branch**

In `_process`, the `away_from_start` branch, find the existing food tick + return (~`:4963-4964`):

```gdscript
		# Domain 3: food spoilage + production advance on the derelict branch too (see
		# _tick_food_runtime — deliberate divergence from crafting, which pauses away).
		_tick_food_runtime(delta)
		return
```

Insert the ship-systems block immediately BEFORE `_tick_food_runtime(delta)`:

```gdscript
		# Domain 4: the hub ship sim is LIVE on the derelict branch (no pausing).
		# advance + web hull damage + recompute run here so the trapped hub keeps
		# degrading (web devours the hull) and powered stations stay live while the
		# player is aboard a derelict. _tick_active_fire already ran above; recompute
		# no longer ticks fire/field-crafting (see Task 2), so no double-tick.
		if ship_systems_manager != null:
			ship_systems_manager.advance(delta)
		_apply_web_hull_damage(delta)
		_recompute_expanded_ship_systems(delta)
		# Domain 3: food spoilage + production advance on the derelict branch too (see
		# _tick_food_runtime — deliberate divergence from crafting, which pauses away).
		_tick_food_runtime(delta)
		return
```

- [ ] **Step 9: Run the closure smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_closure_smoke.gd
```
Expected: prints `SHIP SYSTEMS CLOSURE PASS away_ticks=60 web_grew=true hull_damaged=true breach_to_vitals=true`, only baseline-allowlist noise otherwise.

If `hull_damaged`/`breach_to_vitals` is false, the web rates are too low for 60 ticks — re-confirm `data/ship_systems/web_infestation.json` matches Task 1 (growth 0.02, contact_boost 0.03, damage_rate 0.03). Do NOT raise rates beyond the spec's "slow" intent just to pass; 60 contact ticks reach ~full coverage and ~0.7 cumulative damage per compartment (default health 1.0, breach at ≤0.45), which breaches.

- [ ] **Step 10: Re-run the away-safety + ship-systems regression smokes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_life_support_vitals_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd
```
Expected: both markers unchanged (especially `away_safe=true` — away hull damage accrues to the hub but the vitals-application gate at `_process` keeps player drain zero while away).

- [ ] **Step 11: Commit**

```bash
git add scripts/systems/ship_instance.gd scripts/procgen/playable_generated_ship.gd scripts/validation/ship_systems_closure_smoke.gd
git commit -F - <<'EOF'
feat: wire web infestation as live hull damage on both _process branches

The hub (trapped in the Sargasso web) takes continuous web hull damage from
hull_web_state on the home AND away branches; ship_systems_manager.advance +
recompute now run on the away branch too (live sim, no pausing). ShipInstance
gains a web_attached flag (foundation contagion seed). Closure smoke drives the
away branch and asserts web->hull->breach->atmosphere drain engages on a derelict.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx
EOF
```

---

### Task 4: Register smokes in the bundle, flip the inventory loop green, update ADR/comment, full regression

**Files:**
- Modify: `docs/game/06_validation_plan.md` — two new `run_clean` lines + `commands=` label + two ledger entries.
- Modify: `docs/game/inventory/system_inventory.json` — `ship_systems.closes`, its `break_points`, `hull_integrity_state.input`.
- Regenerate: `docs/game/inventory/SYSTEM_INVENTORY.md` + `docs/game/inventory/system_map.html` via `tools/build_system_inventory.py`.
- Modify: `scripts/procgen/playable_generated_ship.gd` — the `:4948` "powered-station crafts pause while away" comment.
- Modify: `docs/game/adr/0038-crafting-materials-stations-architecture.md` — supersede note.

**Interfaces:** none (integration + docs).

- [ ] **Step 1: Register the two new smokes in the regression bundle**

In `docs/game/06_validation_plan.md`, in the executable bundle block (the `run_clean ...` lines), add after the existing `M7-A ship systems expanded smoke` line:

```bash
run_clean 'Domain 4 web infestation model smoke' 'WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/web_infestation_state_smoke.gd
run_clean 'Domain 4 ship systems closure smoke' 'SHIP SYSTEMS CLOSURE PASS away_ticks=60 web_grew=true hull_damaged=true breach_to_vitals=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_closure_smoke.gd
```

- [ ] **Step 2: Bump the `commands=` label**

In `docs/game/06_validation_plan.md`, update the final echo from `commands=82` to `commands=84` (two new smokes). NOTE: the hard gate is EXIT 0 + zero unexpected ERROR/WARNING + every PASS marker present — the `commands=` number is a human-facing label, not an assertion.

- [ ] **Step 3: Add the two ledger entries**

In the `- [x] ...` checklist section of `docs/game/06_validation_plan.md`, add:

```markdown
- [x] Domain 4 web infestation model smoke: `scripts/validation/web_infestation_state_smoke.gd` (expected marker `WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true`) — pure-model: coverage grows while web-attached and tick() returns hull damage; recedes when cut free; save round-trip; apply_summary rejects a mismatched hazard_kind. Added to regression bundle.
- [x] Domain 4 ship systems closure smoke: `scripts/validation/ship_systems_closure_smoke.gd` (expected marker `SHIP SYSTEMS CLOSURE PASS away_ticks=60 web_grew=true hull_damaged=true breach_to_vitals=true`) — main-scene: drives `away_from_start = true` and proves the hub web infestation ticks on the away branch, damages the hull, and the resulting breach engages the life-support atmosphere→vitals drain. Closes the `ship_systems` loop's live-input + both-branch requirements. Added to regression bundle.
```

- [ ] **Step 4: Flip the inventory loop + hull input live**

In `docs/game/inventory/system_inventory.json`:

In the `"id": "ship_systems"` loop object, change `"closes": "partial"` to `"closes": "closed"` and replace its `break_points` array with:

```json
      "break_points": [
        "hull_integrity_state now takes live damage from hull_web_state (WebInfestationState): the hub is trapped in the biomatter web, coverage grows and _apply_web_hull_damage degrades every compartment each tick on BOTH _process branches (playable_generated_ship.gd home + away).",
        "ship_systems_manager.advance + _recompute_expanded_ship_systems now run on the away (derelict) branch too (live sim, no pausing); fire + field-crafting were extracted to _tick_active_fire to avoid double-ticking. Powered stations are live on both branches (supersedes the former away-pause convention).",
        "DEFERRED to the follow-on web spec (gated on Phase-5 docking graph): dock-graph contagion spread across multiple persistent derelicts, the cut-a-ship-free action + reaching/re-contact, and per-derelict hull integrity."
      ]
```

In the `"id": "hull_integrity_state"` system object, change its `"input"` block to:

```json
      "input": {
        "live": true,
        "desc": "live web-infestation damage: hull_web_state (WebInfestationState) coverage -> _apply_web_hull_damage degrades every compartment each tick on both _process branches; config seed + force_hull_breach_for_validation remain as the static/test paths",
        "at": "playable_generated_ship.gd:_apply_web_hull_damage"
      },
```

Also update that system's `gaps` array — replace the single deferred-damage gap with:

```json
      "gaps": [
        "Live in-game damage source landed (Domain 4): hull_web_state web infestation. Per-derelict hull (so the web damages each ship's own hull, not just the hub's) is deferred to the follow-on web spec."
      ]
```

- [ ] **Step 4b: Add the `web_infestation_state` system entry to the inventory**

A new `scripts/systems/web_infestation_state.gd` exists (Task 1). The inventory `--coverage` gate flags any `scripts/systems/*.gd` not catalogued, so add an entry (mirroring the Domain 3 `production_station` addition). Insert this object immediately AFTER the `hull_integrity_state` system object's closing `},` in `docs/game/inventory/system_inventory.json`:

```json
    {
      "id": "web_infestation_state",
      "file": "scripts/systems/web_infestation_state.gd",
      "name": "Web Infestation",
      "domain": "ship_systems",
      "kind": "simulation",
      "model_exists": true,
      "smoke": "scripts/validation/web_infestation_state_smoke.gd",
      "reachable": true,
      "driven": true,
      "driven_at": "playable_generated_ship.gd:_apply_web_hull_damage",
      "input": {
        "live": true,
        "desc": "configured from data/ship_systems/web_infestation.json (growth/recession/damage/contact rates); hub attached_to_web=true by default; contact boost from a docked still-attached derelict via _active_derelict_web_attached",
        "at": "playable_generated_ship.gd:_configure_expanded_ship_system_models"
      },
      "output": {
        "live": true,
        "desc": "tick() returns per-tick hull damage applied across hull_integrity_state.compartments by _apply_web_hull_damage on BOTH _process branches (home + away) — the live source closing the ship_systems loop",
        "at": "playable_generated_ship.gd:_apply_web_hull_damage"
      },
      "confidence": "V",
      "loops": [
        "ship_systems"
      ],
      "integrations": [
        {
          "to": "hull_integrity_state",
          "via": "coverage -> damage_compartment on every compartment each tick",
          "at": "playable_generated_ship.gd:_apply_web_hull_damage",
          "health": "healthy"
        }
      ],
      "content": "partial",
      "content_note": "Domain 4 foundation: hub trapped in the Sargasso web (attached by default), coverage grows -> hull damage on both branches; ShipInstance.web_attached is the per-derelict contagion-seed flag. Full dock-graph spread / cut-free action / per-derelict hull deferred to the follow-on web spec.",
      "functional": null,
      "gaps": [
        "Foundation only: dock-graph contagion spread, the cut-a-ship-free action + reaching/re-contact, and per-derelict hull are deferred to the follow-on web spec (gated on the Phase-5 docking graph)."
      ],
      "subsystems": []
    },
```

If `system_inventory.json` has a top-level systems-count or metadata field, update it for +1 entry (the `--check` staleness gate will catch any mismatch).

- [ ] **Step 5: Regenerate the inventory views + verify check AND coverage**

```bash
cd "C:/Users/dasbl/Documents/The Synaptic Sea"
python tools/build_system_inventory.py            # regenerate MD + HTML from JSON
python tools/build_system_inventory.py --check     # expect: SYSTEM INVENTORY CHECK PASS systems=189 verified=189
python tools/build_system_inventory.py --coverage  # expect: SYSTEM INVENTORY COVERAGE PASS scripts=... (no "ERROR: not in inventory")
```
Expected: regenerates `SYSTEM_INVENTORY.md` + `system_map.html` with no error; `--check` and `--coverage` both PASS with the new `web_infestation_state` entry present. If `--coverage` prints `ERROR: not in inventory: scripts/systems/web_infestation_state.gd`, the entry was malformed or misplaced — fix it.

- [ ] **Step 6: Update the `:4948` comment + ADR-0038**

In `scripts/procgen/playable_generated_ship.gd`, the away-branch `field_crafting` comment (~`:4948-4949`) currently reads:

```gdscript
		# ADR-0038: emergency field crafting completes even away from home (powered-station
		# crafts pause while away, by design — only field_crafting_state advances here).
```

Change to:

```gdscript
		# ADR-0038 (superseded by Domain 4): field crafting completes away from home.
		# Powered-station crafting is NO LONGER paused away — the hub recompute runs on
		# both branches now (live sim), so powered stations stay live on a derelict too.
```

In `docs/game/adr/0038-crafting-materials-stations-architecture.md`, append a short note at the end:

```markdown

## Superseded in part (Domain 4, 2026-06-30)

The "powered-station crafts pause while the player is away on a derelict" behavior
was an emergent side-effect of `_recompute_expanded_ship_systems` running only on the
home `_process` branch — not a deliberate architectural rule. Domain 4 makes the ship
sim live on both branches (`docs/superpowers/specs/2026-06-30-domain4-ship-systems-design.md`),
so powered stations now advance while away as well. Field crafting remains the
unpowered/portable path and is unchanged.
```

- [ ] **Step 7: Run the FULL regression bundle**

Extract and run the bundle from `docs/game/06_validation_plan.md` with `GODOT`/`ROOT` set to the Windows values, capturing exit code, section count, and any unexpected lines. Verify ALL of:
- exit code `0`
- the run ends with `SYNAPTIC_SEA REGRESSION PASS commands=84 clean_output=true`
- zero `UNEXPECTED` / `FAIL` lines
- the two new markers (`WEB INFESTATION PASS ...`, `SHIP SYSTEMS CLOSURE PASS ...`) and the `SYSTEM INVENTORY CHECK PASS ...` marker all appear

If the inventory `--check` smoke fails, the regenerated MD/HTML drifted from the JSON or a referenced system/loop is inconsistent — re-run Step 5 and reconcile before proceeding.

- [ ] **Step 8: Commit**

```bash
git add docs/game/06_validation_plan.md docs/game/inventory/system_inventory.json docs/game/inventory/SYSTEM_INVENTORY.md docs/game/inventory/system_map.html scripts/procgen/playable_generated_ship.gd docs/game/adr/0038-crafting-materials-stations-architecture.md
git commit -F - <<'EOF'
docs: close the ship_systems loop in the inventory (Domain 4)

Registers the two Domain 4 smokes in the regression bundle (commands=84), flips
ship_systems.closes -> closed and hull_integrity_state.input.live -> true (web
infestation citation), and records the ADR-0038 powered-stations-away supersession.
Regenerated SYSTEM_INVENTORY.md + system_map.html.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx
EOF
```

---

## Self-Review

**Spec coverage:**
- Live hull damage source (BP1) → Tasks 1 + 3 (`WebInfestationState` + `_apply_web_hull_damage` on both branches). ✓
- Both-branch sim (BP2) → Task 3 Step 8 (away advance + recompute) + Task 2 (refactor enabling it). ✓
- Revive powered stations away (supersede `:4948`) → Task 3 (recompute on away) + Task 4 Step 6 (comment + ADR). ✓
- `hazard_kind` discriminator, non-PhaseTimer exemption → Task 1 model. ✓
- Additive save, no version bump → Task 3 Steps 5 (web summary via `.get(key, {})`) + ShipInstance `web_attached` persisted only when false. ✓
- Foundation contagion seed → Task 3 (`ShipInstance.web_attached` + `_active_derelict_web_attached`). ✓
- Validation: model smoke + away `away_ticks=` closure smoke + bundle registration → Tasks 1, 3, 4. ✓
- Inventory delta (loop closed, hull input live, break-points) + `--check` → Task 4. ✓
- Non-goals (dock-graph spread, cut-free action, per-derelict hull) → left out; recorded as deferred in the Task 4 break-points. ✓

**Placeholder scan:** no TBD/TODO; every code step shows complete code; rate values are concrete (`web_infestation.json`); no dead/unused functions (the closure smoke drives the real `_process` away branch directly). ✓

**Type consistency:** `hull_web_state` / `WebInfestationStateScript` / `WEB_INFESTATION_CONFIG_PATH` / `_apply_web_hull_damage` / `_active_derelict_web_attached` / `_tick_active_fire` / `ShipInstance.web_attached` / `is_web_attached()` used identically across tasks. `tick(delta, contact) -> float`, `get_summary`/`apply_summary`, `damage_compartment`, `average_integrity`, `get_breach_count`, `get_health_drain_per_second` match their source files. ✓

**Risk note for the executor:** Task 2 is the delicate one — verify the three smokes in Step 6 print byte-identical markers before committing; a dropped or duplicated fire/field-crafting call is the most likely defect and is invisible except through those markers + the bundle's unexpected-WARNING gate.
