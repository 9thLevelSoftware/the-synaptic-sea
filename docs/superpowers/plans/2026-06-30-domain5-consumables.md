# Domain 5: Consumables — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the `consumables` loop — every consumable branch gains a real, consumed effect, with all per-frame decay ticks running on both `_process` branches.

**Architecture:** Repurpose `ammo_state` from a dead reserve-dict into a per-weapon magazine with a timed reload; combat fires from the magazine while inventory holds reserve stock. Wire stim/addiction decay onto the away branch. Add a full sealed-hatch bypass sub-system (new `SealedHatch` node reusing the breach-zone passability pattern + coordinator-side deterministic seeding). Add a `temperature_delta` thermal consumable and give `utility_flare` a real sanity-steadying reader. Remove the two orphaned pre-combat ammo relics.

**Tech Stack:** Godot 4.6.2, typed GDScript. Pure models = `RefCounted` with `get_summary()`/`apply_summary()`. Validation = headless `SceneTree` smokes printing a single PASS marker.

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (use `_console` build, headless). **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- **Validation is the definition of done.** No task is complete without fresh PASS-marker output. **Trust the PASS marker, not the exit code** — Godot `--script` can exit 0 on parse errors.
- **Both `_process` branches.** Every per-frame tick added is wired into the `away_from_start` (derelict) branch (`playable_generated_ship.gd:5013-5079`) **and** the home branch (`:5085+`). Each new main-scene smoke drives `away_from_start = true` and carries an `away_ticks=` assertion.
- **Typed GDScript**; Resources are data, Nodes are behavior.
- **Baseline noise allowlist** (do NOT treat as failures): `ERROR: Capture not registered: 'gdaimcp'.`, `WARNING: ObjectDB instances leaked at exit ...`, and the one expected `WARNING: SaveLoadService: save file rejected by from_dict ...`. **Any other `ERROR:`/`WARNING:` line blocks completion.**
- **Save-schema changes are additive** — read via `.get(..., default)`; no `CURRENT_SLICE_VERSION` bump.
- **Conventional Commits.** `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx` trailers on every commit.
- **Do NOT `git add -A`.** Stage only the explicit paths per step. Never stage `project.godot`, `.godot/`, `*.uid`, or `addons/`.
- **Run a smoke:**
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke_name>.gd
  ```
- **Full regression bundle** (final task): extract from `docs/game/06_validation_plan.md`:
  ```bash
  awk '/^ROOT=/{f=1} f{print} /clean_output=true/{exit}' "$ROOT/docs/game/06_validation_plan.md" \
    | sed 's|^ROOT=.*|ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"|; s|^GODOT=.*|GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"|' > /tmp/reg.sh
  bash /tmp/reg.sh; echo "EXIT=$?"
  ```
  Gate: `EXIT=0` + zero unexpected `ERROR:`/`WARNING:`/`FAIL` + all markers + final line `SYNAPTIC_SEA REGRESSION PASS`.

## Verified current state (line-cited, 2026-06-30)

- `ammo_state.gd` — reserve tracker (`reserves` dict, `add_ammo`/`consume`/`get_reserve`). Constructed `playable_generated_ship.gd:1194`; in `_consumable_pipeline_context()` `:4175`; saved `:6221-6222`, restored `:6527-6528`.
- Combat fires via `threat_manager.attack_with_weapon(weapon_id, inventory_state, equipment_state, target_id="")` (`threat_manager.gd:105`); ammo gate at `:114-118` reads/decrements **inventory** directly; caller `playable_generated_ship.gd:4128` (`_attack_with_equipped_weapon`, `:4122`); wasted-action teeth `:4133-4141`.
- Weapons: `data/combat/weapon_definitions.json` (crowbar melee `ammo_item_id:""`, flare_pistol→flare_round, shock_probe→capacitor_cell, welding_lance→fuel_canister). Combat ammo defs: `data/combat/ammo_definitions.json`.
- **Orphan relic #1:** `data/items/ammo_definitions.json` (flare_round/shock_probe → `effects:["flare_burn"]`/`["shock_jolt"]`; those effect ids are absent from `effect_definitions.json`).
- **Orphan relic #2:** `effect_definitions.json` has `pistol_rounds_small`/`shells_small` (`kind:"ammo_reserve"`, ammo_kind pistol/shell) consumed by `effect_dispatcher.gd:84-91` (`add_ammo`). These pistol/shell kinds don't match any combat weapon.
- Stim/addiction tick **home-only** at `playable_generated_ship.gd:5102-5105`; away branch `:5013-5079` never ticks them. Signatures: `stimulant_state.tick(delta_seconds, addiction_state, context)`, `addiction_state.tick(delta_seconds, status_effects_state=null)`.
- `_consumable_pipeline_context()` (`:4168-4183`) carries `body_temperature_state`, `ammo_state`, `sanity_state`, `status_effects_state`, etc.
- `effect_dispatcher.gd:55-60` `temperature_delta` branch reads `definition.amount` → `body_temperature_state.adjust_temperature(amount)`. **No effect uses it.** `body_temperature_state`: DEFAULT 22.0, safe 18–32, `adjust_temperature(amount) -> float` adds and returns.
- `utility_item_resolver.gd` sets `active_flags[flag]` (lockpick/hack_chip/flare/repair_foam); **no reader.** Statuses `utility_lockpick_ready`/`utility_hack_chip_ready`/`utility_flare` (`effect_definitions.json`) are `add_status` with no reader. Only `repair_foam`→`heal_small` does real work.
- Passability pattern (breach zone): `playable_generated_ship.gd:5405-5416` — a zone node whose collision `disabled` toggles with `passability_blocked`.
- Loot-container seeding: `_build_loot_containers` `:2520-2553` reads `active_loader.get_loot_container_specs_copy()`; `LootContainer` (`scripts/tools/loot_container.gd`) is an `Area3D` with `configure(...)`, `try_interact(player_body)->bool`, `container_searched` signal, `set_searched`. Interact dispatch loop `:3567-3570`. Looted state tracked on `ShipInstance.looted_container_ids`.
- Input registration: `ensure_default_input_actions()` `:446-450` via `_ensure_key_action_set(name, keys)`; `DEFAULT_ATTACK_BINDINGS := [KEY_F]` `:443`. Attack input handled `_input` `:7374-7377`.

---

### Task 1: Thermal consumable (`temperature_delta`)

Smallest, self-contained. Makes the dead dispatcher branch live via a real item.

**Files:**
- Modify: `data/items/effect_definitions.json` (add `heatpack`)
- Modify: `data/items/utility_item_definitions.json` (add `heat_pack` item)
- Create: `scripts/validation/thermal_consumable_smoke.gd`

**Interfaces:**
- Consumes: `EffectDispatcher.dispatch_effect(effect_id, context)` (exists); `BodyTemperatureState.adjust_temperature(amount)->float`, `.get_summary()["temperature"]` (exist).
- Produces: effect id `heatpack` (`kind:temperature_delta`, `amount:8.0`); item `heat_pack`.

- [ ] **Step 1: Write the failing smoke** — `scripts/validation/thermal_consumable_smoke.gd`:

```gdscript
extends SceneTree

## Domain 5 Task 1: the temperature_delta dispatcher branch is now live via the
## heatpack effect. Configure a cold body temperature, dispatch heatpack, assert
## the temperature rose by the effect amount.
## Marker: THERMAL CONSUMABLE PASS temp_before=<f> temp_after=<f> temp_shifted=true

const EffectDispatcherScript := preload("res://scripts/systems/effect_dispatcher.gd")
const BodyTempScript := preload("res://scripts/systems/body_temperature_state.gd")

func _initialize() -> void:
	var dispatcher = EffectDispatcherScript.new()
	dispatcher.configure({})
	var temp = BodyTempScript.new()
	temp.configure({"temperature": 12.0})  # cold zone, below safe_min 18
	var before: float = temp.get_summary()["temperature"]
	var result: Dictionary = dispatcher.dispatch_effect("heatpack", {"body_temperature_state": temp})
	var after: float = temp.get_summary()["temperature"]
	if not bool(result.get("ok", false)):
		push_error("THERMAL CONSUMABLE FAIL reason=dispatch_%s" % str(result.get("reason", "?")))
		quit(1); return
	if after <= before + 0.001:
		push_error("THERMAL CONSUMABLE FAIL reason=no_shift before=%.3f after=%.3f" % [before, after])
		quit(1); return
	print("THERMAL CONSUMABLE PASS temp_before=%.3f temp_after=%.3f temp_shifted=true" % [before, after])
	quit(0)
```

- [ ] **Step 2: Run it — expect FAIL** (`unknown_effect`, heatpack not defined):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/thermal_consumable_smoke.gd`
Expected: `THERMAL CONSUMABLE FAIL reason=dispatch_unknown_effect`

- [ ] **Step 3: Add the `heatpack` effect** — in `data/items/effect_definitions.json`, add after `utility_hack_chip`:

```json
  "heatpack": { "kind": "temperature_delta", "amount": 8.0 },
```

- [ ] **Step 4: Add the `heat_pack` item** — in `data/items/utility_item_definitions.json`, add a new entry (mirror `repair_foam`'s shape; no `utility_flag`):

```json
  "heat_pack": {
    "display_name": "Heat Pack",
    "category": "utility",
    "weight": 0.3,
    "max_stack": 6,
    "effects": ["heatpack"],
    "use_note": "A chemical heat pack pushes back the cold of a dead ship.",
    "icon": "res://assets/placeholder/repair_foam.png"
  }
```

- [ ] **Step 5: Run the smoke — expect PASS:**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/thermal_consumable_smoke.gd`
Expected: `THERMAL CONSUMABLE PASS temp_before=12.000 temp_after=20.000 temp_shifted=true`

- [ ] **Step 6: Commit:**

```bash
git add scripts/validation/thermal_consumable_smoke.gd data/items/effect_definitions.json data/items/utility_item_definitions.json
git commit -m "feat: add heatpack thermal consumable (temperature_delta live)

Closes the effect_dispatcher temperature_delta branch (Domain 5) with a real
heat_pack item that shifts body_temperature_state toward safe.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 2: Repurpose `ammo_state` into a per-weapon magazine + timed reload (pure model)

Rewrite the model only. No coordinator/threat wiring yet (Task 3). This lets a reviewer gate the model in isolation.

**Files:**
- Modify (full rewrite): `scripts/systems/ammo_state.gd`
- Create: `scripts/validation/ammo_magazine_state_smoke.gd`

**Interfaces:**
- Produces: `AmmoState` with `const RELOAD_SECONDS := 1.5`; `loaded(weapon_id:String)->int`; `spend(weapon_id:String)->bool`; `is_reloading()->bool`; `begin_reload(weapon_id:String, magazine_size:int, reserve_available:int)->bool` (sets `reload_target`); `reload_target:int`; `tick(delta:float)->Dictionary` (returns `{"weapon_id","loaded"}` on completion else `{}`); `get_summary()`/`apply_summary()`; `get_status_lines()`. Removes `add_ammo`/`consume`/`get_reserve`/`reserves`.

- [ ] **Step 1: Write the failing smoke** — `scripts/validation/ammo_magazine_state_smoke.gd`:

```gdscript
extends SceneTree

## Domain 5 Task 2: ammo_state is now a per-weapon magazine with a timed reload.
## Asserts spend/empty/begin_reload/tick-completion and summary round-trip.
## Marker: AMMO MAGAZINE STATE PASS spent=true empty=true reloaded=true roundtrip=true

const AmmoStateScript := preload("res://scripts/systems/ammo_state.gd")

func _initialize() -> void:
	var a = AmmoStateScript.new()
	a.configure({"magazines": {"flare_pistol": 1}})
	var spent: bool = a.spend("flare_pistol") and a.loaded("flare_pistol") == 0
	var empty: bool = not a.spend("flare_pistol")  # magazine now empty -> false
	# Reload 2 rounds from a 2-round magazine with 5 in reserve.
	var began: bool = a.begin_reload("flare_pistol", 2, 5) and a.reload_target == 2 and a.is_reloading()
	# tick less than RELOAD_SECONDS: not done
	var mid: Dictionary = a.tick(0.5)
	var not_done: bool = mid.is_empty() and a.is_reloading()
	# tick past completion
	var done: Dictionary = a.tick(2.0)
	var reloaded: bool = began and not_done and done.get("weapon_id", "") == "flare_pistol" \
		and int(done.get("loaded", 0)) == 2 and a.loaded("flare_pistol") == 2 and not a.is_reloading()
	# summary round-trip mid-reload
	var b = AmmoStateScript.new()
	b.configure({"magazines": {"shock_probe": 3}})
	b.begin_reload("shock_probe", 5, 4)
	var c = AmmoStateScript.new()
	c.apply_summary(b.get_summary())
	var roundtrip: bool = c.loaded("shock_probe") == 3 and c.is_reloading() and c.reload_target == b.reload_target
	if spent and empty and reloaded and roundtrip:
		print("AMMO MAGAZINE STATE PASS spent=true empty=true reloaded=true roundtrip=true")
		quit(0)
	else:
		push_error("AMMO MAGAZINE STATE FAIL spent=%s empty=%s reloaded=%s roundtrip=%s" % [str(spent), str(empty), str(reloaded), str(roundtrip)])
		quit(1)
```

- [ ] **Step 2: Run it — expect FAIL** (old `AmmoState` has no `loaded`/`spend`/`begin_reload`):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ammo_magazine_state_smoke.gd`
Expected: FAIL / parse error referencing missing methods.

- [ ] **Step 3: Rewrite `scripts/systems/ammo_state.gd`** (full replacement):

```gdscript
extends RefCounted
class_name AmmoState

## Per-weapon magazine + timed reload. Combat (threat_manager) fires from the
## magazine; inventory holds the reserve stock. Reload moves reserve -> magazine
## over RELOAD_SECONDS. Domain 5: repurposed from the pre-combat reserve tracker
## (combat consumes ammo from inventory; ammo_state is the loaded-magazine layer).

const RELOAD_SECONDS: float = 1.5

var magazines: Dictionary = {}          # weapon_id (String) -> loaded rounds (int)
var reload_active: bool = false
var reload_remaining: float = 0.0
var reload_weapon_id: String = ""
var reload_target: int = 0              # rounds committed to load on completion
var total_fired: int = 0

func configure(config: Dictionary = {}) -> void:
	magazines.clear()
	reload_active = false
	reload_remaining = 0.0
	reload_weapon_id = ""
	reload_target = 0
	total_fired = 0
	var raw: Variant = config.get("magazines", {})
	if raw is Dictionary:
		for wid in (raw as Dictionary):
			magazines[str(wid)] = max(0, int((raw as Dictionary)[wid]))

func loaded(weapon_id: String) -> int:
	return int(magazines.get(weapon_id, 0))

func spend(weapon_id: String) -> bool:
	var cur: int = loaded(weapon_id)
	if cur <= 0:
		return false
	magazines[weapon_id] = cur - 1
	total_fired += 1
	return true

func is_reloading() -> bool:
	return reload_active

## Begins a reload if not already reloading and there is room + reserve.
## reserve_available is the inventory count the coordinator passes in; the
## coordinator removes reload_target from inventory once this returns true.
func begin_reload(weapon_id: String, magazine_size: int, reserve_available: int) -> bool:
	if reload_active:
		return false
	if weapon_id.is_empty() or magazine_size <= 0:
		return false
	var need: int = magazine_size - loaded(weapon_id)
	var can_load: int = min(need, max(0, reserve_available))
	if can_load <= 0:
		return false
	reload_active = true
	reload_remaining = RELOAD_SECONDS
	reload_weapon_id = weapon_id
	reload_target = can_load
	return true

## Advances the reload timer. On completion, credits the magazine and returns
## {"weapon_id","loaded"} so the coordinator can refresh the HUD (inventory was
## already debited at begin_reload time). Returns {} while idle or mid-reload.
func tick(delta: float) -> Dictionary:
	if not reload_active:
		return {}
	reload_remaining -= delta
	if reload_remaining > 0.0:
		return {}
	var wid: String = reload_weapon_id
	var loaded_count: int = reload_target
	magazines[wid] = loaded(wid) + loaded_count
	reload_active = false
	reload_remaining = 0.0
	reload_weapon_id = ""
	reload_target = 0
	return {"weapon_id": wid, "loaded": loaded_count}

func get_summary() -> Dictionary:
	return {
		"magazines": magazines.duplicate(true),
		"reload_active": reload_active,
		"reload_remaining": reload_remaining,
		"reload_weapon_id": reload_weapon_id,
		"reload_target": reload_target,
		"total_fired": total_fired,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	configure({"magazines": summary.get("magazines", {})})
	reload_active = bool(summary.get("reload_active", false))
	reload_remaining = float(summary.get("reload_remaining", 0.0))
	reload_weapon_id = str(summary.get("reload_weapon_id", ""))
	reload_target = int(summary.get("reload_target", 0))
	total_fired = int(summary.get("total_fired", 0))
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var wids: Array = magazines.keys()
	wids.sort()
	for wid in wids:
		lines.append("Mag %s=%d" % [String(wid), int(magazines[wid])])
	if reload_active:
		lines.append("Reloading %s (%.1fs)" % [reload_weapon_id, reload_remaining])
	return lines
```

- [ ] **Step 4: Run the smoke — expect PASS:**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ammo_magazine_state_smoke.gd`
Expected: `AMMO MAGAZINE STATE PASS spent=true empty=true reloaded=true roundtrip=true`

- [ ] **Step 5: Check for compile fallout** — the `effect_dispatcher.gd:84-91` `ammo_reserve` branch calls `ammo.add_ammo(...)`, now removed. This is fixed in Task 3; if any smoke exercises it before then it will fail. Confirm the model smoke passes; defer dispatcher/relic cleanup to Task 3.

- [ ] **Step 6: Commit:**

```bash
git add scripts/systems/ammo_state.gd scripts/validation/ammo_magazine_state_smoke.gd
git commit -m "refactor: repurpose ammo_state into per-weapon magazine + timed reload

Domain 5: ammo_state now holds loaded rounds per weapon with a 1.5s timed
reload; inventory remains the reserve stock. Combat wiring in follow-up.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 3: Fire from the magazine + reload input/tick + remove ammo relics (combat wiring)

Wires the magazine into combat, adds the reload action, ticks reload on both branches, and removes the two orphaned pre-combat ammo relics + the dead `ammo_reserve` dispatcher branch.

**Files:**
- Modify: `scripts/systems/threat_manager.gd:105-138` (fire from magazine)
- Modify: `data/combat/weapon_definitions.json` (add `magazine_size`)
- Modify: `scripts/procgen/playable_generated_ship.gd` (reload input + tick both branches; attack caller)
- Modify: `scripts/systems/effect_dispatcher.gd:84-91` (remove `ammo_reserve` branch)
- Modify: `data/items/effect_definitions.json` (remove `pistol_rounds_small`, `shells_small`)
- Delete: `data/items/ammo_definitions.json` (orphan flare_burn/shock_jolt)
- Modify: `scripts/validation/effect_dispatcher_smoke.gd` (drop any `ammo_reserve` assertion) — **only if it references `ammo_reserve`/`add_ammo`; verify first**
- Create: `scripts/validation/ammo_magazine_smoke.gd` (main-scene, away_ticks)

**Interfaces:**
- Consumes: `AmmoState.spend/loaded/is_reloading/begin_reload/reload_target/tick` (Task 2).
- Produces: `threat_manager.attack_with_weapon(weapon_id, inventory_state, equipment_state, ammo_state=null, target_id="")` returning `{ok:false, reason:"empty_magazine"|"reloading", ...}` on no-fire; `weapon_definitions` gains `magazine_size`; coordinator `reload_weapon` action (KEY_R) + `_begin_weapon_reload()`.

- [ ] **Step 1: Write the failing main-scene smoke** — `scripts/validation/ammo_magazine_smoke.gd`:

```gdscript
extends SceneTree

## Domain 5 Task 3: combat fires from the per-weapon magazine, empty magazine is a
## dry-fire click (no shot), reload refills from inventory reserve over 1.5s, and the
## reload timer advances on the AWAY (derelict) branch. Drives away_from_start = true.
## Marker: AMMO MAGAZINE PASS away_ticks=<n> spent=true dry_fire=true reloaded=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
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
	finished = true
	var wid := "flare_pistol"
	# Seed a loaded magazine of 1 and reserve stock in inventory.
	playable.ammo_state.configure({"magazines": {wid: 1}})
	playable.inventory_state.add_item("flare_round", 5)
	# Fire once from the magazine (spend), then dry-fire on empty.
	var spent: bool = playable.ammo_state.spend(wid) and playable.ammo_state.loaded(wid) == 0
	var dry_fire: bool = not playable.ammo_state.spend(wid)
	# Begin a reload and advance it on the AWAY branch.
	playable.away_from_start = true
	var mag_size := 2
	var reserve := playable.inventory_state.get_quantity("flare_round")
	var began: bool = playable.ammo_state.begin_reload(wid, mag_size, reserve)
	playable.inventory_state.remove_item("flare_round", playable.ammo_state.reload_target)
	var n: int = 0
	for i in range(30):
		playable._process(0.1)  # 3.0s total > 1.5s reload
		n += 1
	var reloaded: bool = began and playable.ammo_state.loaded(wid) == mag_size and not playable.ammo_state.is_reloading()
	if spent and dry_fire and reloaded:
		print("AMMO MAGAZINE PASS away_ticks=%d spent=true dry_fire=true reloaded=true" % n)
		_cleanup(0)
	else:
		_fail("spent=%s dry_fire=%s reloaded=%s loaded=%d" % [str(spent), str(dry_fire), str(reloaded), playable.ammo_state.loaded(wid)])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("AMMO MAGAZINE FAIL reason=%s" % reason)
	_cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run it — expect FAIL** (reload timer not ticked on away branch → `reloaded=false`):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ammo_magazine_smoke.gd`
Expected: `AMMO MAGAZINE FAIL reason=...reloaded=false...`

- [ ] **Step 3: Add `magazine_size` to ranged weapons** — in `data/combat/weapon_definitions.json`, add `"magazine_size"` to each entry with a non-empty `ammo_item_id` (crowbar keeps none): `flare_pistol` → `2`, `shock_probe` → `5`, `welding_lance` → `6`. Example for flare_pistol:

```json
  "flare_pistol": {
    "display_name": "Flare Pistol",
    "equip_slot": "primary_hand",
    "damage": 16.0,
    "damage_type": "fire",
    "noise": 1.00,
    "stun_seconds": 0.15,
    "ammo_item_id": "flare_round",
    "magazine_size": 2,
    "status_effect_id": "burn"
  },
```

- [ ] **Step 4: Fire from the magazine** — in `scripts/systems/threat_manager.gd`, change the signature (`:105`) and the ammo gate (`:114-118`):

```gdscript
func attack_with_weapon(weapon_id: String, inventory_state, equipment_state, ammo_state = null, target_id: String = "") -> Dictionary:
```

Replace the `:114-118` inventory gate with a magazine gate:

```gdscript
	var ammo_item_id: String = str(weapon.get("ammo_item_id", ""))
	if not ammo_item_id.is_empty():
		# Domain 5: fire from the per-weapon magazine, not raw inventory.
		if ammo_state == null:
			return {"ok": false, "reason": "no_ammo", "ammo_item_id": ammo_item_id}
		if ammo_state.is_reloading():
			return {"ok": false, "reason": "reloading", "ammo_item_id": ammo_item_id}
		if not ammo_state.spend(weapon_id):
			return {"ok": false, "reason": "empty_magazine", "ammo_item_id": ammo_item_id}
```

And update the `ammo_remaining` report (`:136`) to read the magazine:

```gdscript
	result["ammo_remaining"] = ammo_state.loaded(weapon_id) if ammo_state != null and not ammo_item_id.is_empty() else -1
```

- [ ] **Step 5: Pass `ammo_state` from the coordinator attack caller** — in `scripts/procgen/playable_generated_ship.gd:4128`:

```gdscript
	var result: Dictionary = threat_manager.attack_with_weapon(weapon_id, inventory_state, equipment_state, ammo_state)
```

Also update the stale comment at `:4133-4134` (ammo is no longer "already spent" on an empty magazine — the dry-fire click still triggers the phantom-dissipate teeth):

```gdscript
	# ADR-0042: a swing also dissipates a phantom within reach. On an empty magazine
	# the shot is a dry-fire click (no round spent) but the swing still counts as the
	# wasted-action teeth.
```

- [ ] **Step 6: Register the `reload_weapon` action** — in `scripts/procgen/playable_generated_ship.gd`, add a binding const near `:443` and register it in `ensure_default_input_actions()` near `:450`:

```gdscript
const DEFAULT_RELOAD_BINDINGS: Array[Key] = [KEY_R]
```
```gdscript
	_ensure_key_action_set("reload_weapon", DEFAULT_RELOAD_BINDINGS)
```

- [ ] **Step 7: Add the reload-begin helper + input handler** — add `_begin_weapon_reload()` near `_attack_with_equipped_weapon` (`:4122`):

```gdscript
func _begin_weapon_reload() -> void:
	if ammo_state == null or ammo_state.is_reloading() or threat_manager == null:
		return
	var weapon_id: String = _equipped_primary_weapon_id()
	if weapon_id.is_empty():
		return
	var weapon: Dictionary = threat_manager.weapon_definitions.get(weapon_id, {}) if threat_manager.weapon_definitions.get(weapon_id, {}) is Dictionary else {}
	var ammo_item_id: String = str(weapon.get("ammo_item_id", ""))
	if ammo_item_id.is_empty():
		return  # melee: no reload
	var mag_size: int = int(weapon.get("magazine_size", 0))
	var reserve: int = inventory_state.get_quantity(ammo_item_id) if inventory_state != null else 0
	if ammo_state.begin_reload(weapon_id, mag_size, reserve):
		if inventory_state != null:
			inventory_state.remove_item(ammo_item_id, ammo_state.reload_target)  # commit reserve
		_refresh_inventory_hud()
		_refresh_weapon_hotbar()
```

And handle the action in `_input` after the attack block (`:7377`):

```gdscript
		if event.is_action_pressed("reload_weapon"):
			_begin_weapon_reload()
			get_viewport().set_input_as_handled()
			return
```

- [ ] **Step 8: Tick reload on BOTH `_process` branches** — add to the away branch (inside `if away_from_start:`, before the `return` at `:5079`) and the home branch (near the stim/addiction block `:5102`):

```gdscript
		if ammo_state != null and not ammo_state.tick(delta).is_empty():
			_refresh_weapon_hotbar()
```

- [ ] **Step 9: Remove the `ammo_reserve` dispatcher branch** — delete `scripts/systems/effect_dispatcher.gd:84-91` (the entire `"ammo_reserve":` `match` case). The `ammo_state` context entry is now the magazine; no effect writes to it.

- [ ] **Step 10: Remove the orphan relics** — in `data/items/effect_definitions.json` delete the `pistol_rounds_small` and `shells_small` lines. Delete the file `data/items/ammo_definitions.json`. Grep to confirm nothing live references them:

```bash
grep -rn "pistol_rounds_small\|shells_small\|flare_burn\|shock_jolt\|ammo_reserve\|add_ammo\|\.consume(\|get_reserve" scripts/ data/ | grep -v "validation/"
```
Expected: no live (non-validation) references. If `consumable_state.gd` or `inventory_selection_model.gd` reference `data/items/ammo_definitions.json` for item metadata, repoint them to `data/combat/ammo_definitions.json` or remove the dead branch (read those files; fix in this step).

- [ ] **Step 11: Fix any smoke referencing the removed API** — if `scripts/validation/effect_dispatcher_smoke.gd` asserts `ammo_reserve`/`add_ammo`, remove that assertion (the branch is gone). Verify by reading the smoke first.

- [ ] **Step 12: Run the new smoke + the combat + dispatcher smokes — expect PASS/clean:**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ammo_magazine_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_closure_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/effect_dispatcher_smoke.gd
```
Expected: `AMMO MAGAZINE PASS away_ticks=30 spent=true dry_fire=true reloaded=true`; combat + dispatcher smokes still print their PASS markers with no new `ERROR:`/`WARNING:`.

- [ ] **Step 13: Commit:**

```bash
git add scripts/systems/threat_manager.gd scripts/systems/effect_dispatcher.gd scripts/procgen/playable_generated_ship.gd data/combat/weapon_definitions.json data/items/effect_definitions.json scripts/validation/ammo_magazine_smoke.gd
git rm data/items/ammo_definitions.json
# add any repointed consumers / edited effect_dispatcher_smoke.gd explicitly
git commit -m "feat: combat fires from the ammo magazine + timed reload (KEY_R)

Domain 5: threat_manager spends the loaded magazine (empty = dry-fire click),
reload refills from inventory over 1.5s ticked on both _process branches, and
the two orphaned pre-combat ammo relics (data/items/ammo_definitions.json +
ammo_reserve effects/branch) are removed.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 4: Stim/addiction away-tick

Wire the two per-frame decay ticks onto the away branch.

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (away branch `:5013-5079`)
- Create: `scripts/validation/consumables_away_tick_smoke.gd`

**Interfaces:**
- Consumes: `stimulant_state.tick(delta, addiction_state, _consumable_pipeline_context())`, `addiction_state.tick(delta, status_effects_state)` (exist, home branch `:5102-5105`).

- [ ] **Step 1: Write the failing smoke** — `scripts/validation/consumables_away_tick_smoke.gd`:

```gdscript
extends SceneTree

## Domain 5 Task 4: stimulant + addiction per-frame decay advance on the AWAY branch.
## Drives away_from_start = true, applies a stim, and asserts its buff timer decays
## and the addiction model ticks while boarded.
## Marker: CONSUMABLES AWAY TICK PASS away_ticks=<n> stim_decayed=true addiction_ticked=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
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
	finished = true
	# Seed an active stim buff (StimulantState.active_stims entries carry "remaining")
	# and an addiction profile (AddictionState.record_dose seeds tolerance/dependence).
	playable.stimulant_state.active_stims.append({
		"item_id": "stim_focus", "remaining": 20.0, "base_duration": 20.0,
		"effects": [], "withdrawal_effects": [],
	})
	playable.addiction_state.record_dose("stim_focus", {"tolerance_gain": 0.5, "dependence_gain": 0.5})
	var stim_before: float = _active_buff_seconds()
	var tol_before: float = playable.addiction_state.get_tolerance("stim_focus")
	playable.away_from_start = true
	var n: int = 0
	for i in range(20):
		playable._process(1.0)
		n += 1
	# Stim "remaining" decays each away tick; addiction tolerance decays by delta*0.01/s.
	var stim_decayed: bool = _active_buff_seconds() < stim_before - 0.5
	var addiction_ticked: bool = playable.addiction_state.get_tolerance("stim_focus") < tol_before - 0.001
	if stim_decayed and addiction_ticked:
		print("CONSUMABLES AWAY TICK PASS away_ticks=%d stim_decayed=true addiction_ticked=true" % n)
		_cleanup(0)
	else:
		_fail("stim_decayed=%s addiction_ticked=%s stim_before=%.2f stim_after=%.2f tol_before=%.3f tol_after=%.3f" % [
			str(stim_decayed), str(addiction_ticked), stim_before, _active_buff_seconds(),
			tol_before, playable.addiction_state.get_tolerance("stim_focus")])

## Highest active-stim remaining-seconds from StimulantState.get_summary()["active_stims"].
func _active_buff_seconds() -> float:
	var s: Dictionary = playable.stimulant_state.get_summary()
	var best: float = 0.0
	var actives: Variant = s.get("active_stims", [])
	if actives is Array:
		for e in actives:
			if e is Dictionary:
				best = maxf(best, float((e as Dictionary).get("remaining", 0.0)))
	return best

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("CONSUMABLES AWAY TICK FAIL reason=%s" % reason)
	_cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

> **API note (verified):** `StimulantState.active_stims` is an `Array` of dicts each carrying `"remaining"`; `AddictionState.record_dose(item_id, definition)` seeds a profile and `get_tolerance(item_id)->float` reads it; `AddictionState.tick(delta, status_effects_state)` decays `tolerance` by `delta*0.01/s`. The smoke seeds both directly (no dispatcher coupling). Tick signatures are `stimulant_state.tick(delta, addiction_state, context)` and `addiction_state.tick(delta, status_effects_state)`.

- [ ] **Step 2: Run it — expect FAIL** (`stim_decayed=false`: away branch does not tick stim):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/consumables_away_tick_smoke.gd`
Expected: FAIL with `stim_decayed=false`.

- [ ] **Step 3: Add the ticks to the away branch** — in `scripts/procgen/playable_generated_ship.gd`, inside `if away_from_start:` (before `return` at `:5079`), mirror the home block:

```gdscript
		# Domain 5: stimulant buff timers + addiction withdrawal/tolerance decay advance
		# on the derelict branch too (item USE already worked away; only per-frame decay
		# was home-only). Shared with the home block at the bottom of _process.
		if stimulant_state != null:
			stimulant_state.tick(delta, addiction_state, _consumable_pipeline_context())
		if addiction_state != null:
			addiction_state.tick(delta, status_effects_state)
```

- [ ] **Step 4: Run the smoke — expect PASS:**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/consumables_away_tick_smoke.gd`
Expected: `CONSUMABLES AWAY TICK PASS away_ticks=20 stim_decayed=true addiction_ticked=true`

- [ ] **Step 5: Commit:**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/consumables_away_tick_smoke.gd
git commit -m "fix: tick stimulant + addiction decay on the away (derelict) branch

Domain 5: buff timers, withdrawal, and tolerance decay no longer freeze while
boarded a derelict (were home-only). Wires both _process branches.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 5: `SealedHatch` node (model + unit smoke)

The locked-hatch node in isolation — proximity + flag check + collision toggle + signal. No coordinator seeding yet (Task 6).

**Files:**
- Create: `scripts/interaction/sealed_hatch.gd`
- Create: `scripts/validation/sealed_hatch_node_smoke.gd`

**Interfaces:**
- Produces: `SealedHatch extends Area3D` with `const MECHANICAL := "mechanical"`, `const ELECTRONIC := "electronic"`; `hatch_id:String`; `lock_kind:String`; `bypassed:bool`; `signal hatch_bypassed(hatch_id, lock_kind)`; `configure(hatch_id, lock_kind, world_position, radius=1.8)`; `required_flag()->String` (`"lockpick"`/`"hack_chip"`); `set_bypassed(bool)`; `set_validation_player_in_range(bool)`; `try_bypass(player_body, active_flags:Dictionary)->Dictionary`.

- [ ] **Step 1: Write the failing smoke** — `scripts/validation/sealed_hatch_node_smoke.gd`:

```gdscript
extends SceneTree

## Domain 5 Task 5: SealedHatch checks proximity + the matching utility flag, opens
## (disables its passage collision) and emits hatch_bypassed exactly once.
## Marker: SEALED HATCH NODE PASS locked=true opened=true collision_off=true signalled=true

const SealedHatchScript := preload("res://scripts/interaction/sealed_hatch.gd")

var _signalled: int = 0

func _initialize() -> void:
	var hatch = SealedHatchScript.new()
	get_root().add_child(hatch)
	hatch.configure("hatch_a", "mechanical", Vector3.ZERO, 1.8)
	hatch.hatch_bypassed.connect(func(_id, _k): _signalled += 1)
	hatch.set_validation_player_in_range(true)
	# Wrong flag -> locked.
	var locked_res: Dictionary = hatch.try_bypass(null, {"hack_chip": {"count": 1}})
	var locked: bool = not bool(locked_res.get("ok", false)) and str(locked_res.get("reason", "")) == "locked"
	# Right flag -> opens.
	var open_res: Dictionary = hatch.try_bypass(null, {"lockpick": {"count": 1}})
	var opened: bool = bool(open_res.get("ok", false)) and hatch.bypassed
	var collision_off: bool = _blocker_collision_disabled(hatch)
	# Second attempt -> already_open, no second signal.
	hatch.try_bypass(null, {"lockpick": {"count": 1}})
	var signalled: bool = _signalled == 1
	hatch.queue_free()
	if locked and opened and collision_off and signalled:
		print("SEALED HATCH NODE PASS locked=true opened=true collision_off=true signalled=true")
		quit(0)
	else:
		push_error("SEALED HATCH NODE FAIL locked=%s opened=%s collision_off=%s signalled=%s" % [str(locked), str(opened), str(collision_off), str(signalled)])
		quit(1)

func _blocker_collision_disabled(hatch: Node) -> bool:
	for child in hatch.get_children():
		if child is StaticBody3D:
			for gc in child.get_children():
				if gc is CollisionShape3D:
					return (gc as CollisionShape3D).disabled
	return false
```

- [ ] **Step 2: Run it — expect FAIL** (script does not exist):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sealed_hatch_node_smoke.gd`
Expected: FAIL (preload of missing `sealed_hatch.gd`).

- [ ] **Step 3: Create `scripts/interaction/sealed_hatch.gd`:**

```gdscript
extends Area3D
class_name SealedHatch

## A locked passage on a generated ship. Blocks traversal (a StaticBody3D collider)
## until the player bypasses it with the matching utility flag: a mechanical hatch
## needs "lockpick", an electronic one needs "hack_chip". Mirrors the LootContainer
## interaction shape (Area3D proximity + try_* + a signal). Domain 5.

signal hatch_bypassed(hatch_id: String, lock_kind: String)

const MECHANICAL: String = "mechanical"
const ELECTRONIC: String = "electronic"

var hatch_id: String = ""
var lock_kind: String = MECHANICAL
var bypassed: bool = false

var _radius: float = 1.8
var _player_in_range: bool = false
var _blocker: StaticBody3D = null

func configure(p_hatch_id: String, p_lock_kind: String, world_position: Vector3, radius: float = 1.8) -> void:
	hatch_id = p_hatch_id
	lock_kind = p_lock_kind if (p_lock_kind == MECHANICAL or p_lock_kind == ELECTRONIC) else MECHANICAL
	_radius = radius
	position = world_position
	_ensure_detection(radius)
	_ensure_blocker(radius)
	_apply_blocked_state()

func required_flag() -> String:
	return "lockpick" if lock_kind == MECHANICAL else "hack_chip"

func set_bypassed(value: bool) -> void:
	bypassed = value
	_apply_blocked_state()

func set_validation_player_in_range(value: bool) -> void:
	_player_in_range = value

## Attempts to bypass using the player's active utility flags. Returns a result dict;
## on success the collider is disabled and hatch_bypassed is emitted once.
func try_bypass(player_body: Node, active_flags: Dictionary) -> Dictionary:
	if bypassed:
		return {"ok": false, "reason": "already_open", "hatch_id": hatch_id}
	if not _is_player_in_range(player_body):
		return {"ok": false, "reason": "out_of_range", "hatch_id": hatch_id}
	var flag: String = required_flag()
	if active_flags == null or not active_flags.has(flag):
		return {"ok": false, "reason": "locked", "hatch_id": hatch_id, "needs": flag, "lock_kind": lock_kind}
	set_bypassed(true)
	hatch_bypassed.emit(hatch_id, lock_kind)
	return {"ok": true, "hatch_id": hatch_id, "lock_kind": lock_kind, "consumed_flag": flag}

func _is_player_in_range(player_body: Node) -> bool:
	if _player_in_range:
		return true
	if player_body is Node3D and self != null:
		return global_position.distance_to((player_body as Node3D).global_position) <= _radius
	return false

func _ensure_detection(radius: float) -> void:
	monitoring = true
	for child in get_children():
		if child is CollisionShape3D:
			return
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _ensure_blocker(radius: float) -> void:
	if _blocker != null and is_instance_valid(_blocker):
		return
	_blocker = StaticBody3D.new()
	_blocker.name = "HatchBlocker"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius, radius * 2.0, 0.4)
	col.shape = box
	_blocker.add_child(col)
	add_child(_blocker)

func _apply_blocked_state() -> void:
	if _blocker == null or not is_instance_valid(_blocker):
		return
	for c in _blocker.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = bypassed

func _on_body_entered(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_player_in_range = true

func _on_body_exited(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_player_in_range = false
```

> **Implementer note:** confirm the player node's group name — the codebase uses `"player"` group membership for proximity elsewhere; if `LootContainer._on_body_entered` uses a different check, match it.

- [ ] **Step 4: Run the smoke — expect PASS:**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sealed_hatch_node_smoke.gd`
Expected: `SEALED HATCH NODE PASS locked=true opened=true collision_off=true signalled=true`

- [ ] **Step 5: Commit:**

```bash
git add scripts/interaction/sealed_hatch.gd scripts/validation/sealed_hatch_node_smoke.gd
git commit -m "feat: add SealedHatch locked-passage node

Domain 5: an Area3D hatch that blocks a passage (StaticBody3D collider) until
bypassed with the matching utility flag (lockpick/hack_chip), then emits
hatch_bypassed. Coordinator seeding + flag consumption follow.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 6: Seed hatches + interact dispatch + flag consumption + persistence

Wire `SealedHatch` into the running ship: deterministic seeding, the interact action, utility-flag consumption on bypass, and per-ship persistence of bypassed hatches.

**Files:**
- Modify: `scripts/systems/utility_item_resolver.gd` (add `consume_flag`)
- Modify: `scripts/systems/ship_instance.gd` (add `bypassed_hatch_ids` + persist)
- Modify: `scripts/procgen/playable_generated_ship.gd` (seed/build/clear hatches, interact dispatch, `_on_hatch_bypassed`, persistence)
- Create: `scripts/validation/sealed_hatch_smoke.gd` (main-scene, away_ticks)

**Interfaces:**
- Consumes: `SealedHatch.configure/try_bypass/hatch_bypassed/required_flag` (Task 5); `utility_item_resolver.active_flags`; `status_effects_state.remove_effect(id, count)`; `_distributed_room_positions()` (exists — used for deterministic interior positions).
- Produces: `UtilityItemResolver.consume_flag(flag:String)->bool`; coordinator `sealed_hatches:Array`, `_build_sealed_hatches()`, `_clear_sealed_hatches()`, `_on_hatch_bypassed(hatch_id, lock_kind)`, `_try_bypass_nearest_hatch()->bool`; `ShipInstance.bypassed_hatch_ids:Array`.

- [ ] **Step 1: Write the failing main-scene smoke** — `scripts/validation/sealed_hatch_smoke.gd`:

```gdscript
extends SceneTree

## Domain 5 Task 6: sealed hatches are seeded on a boarded derelict; priming the
## lockpick flag then interacting opens a mechanical hatch, consuming the flag and
## disabling its passage collision. Drives away_from_start = true.
## Marker: SEALED HATCH PASS away_ticks=<n> seeded=true mechanical_open=true flag_consumed=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
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
	finished = true
	playable.away_from_start = true
	playable._build_sealed_hatches()
	var n: int = 0
	for i in range(3):
		playable._process(0.1); n += 1
	var seeded: bool = playable.sealed_hatches.size() > 0
	# Find a mechanical hatch; prime the lockpick flag; force in-range; bypass.
	var mech = null
	for h in playable.sealed_hatches:
		if h.lock_kind == "mechanical":
			mech = h; break
	if mech == null:
		_fail("no mechanical hatch seeded (count=%d)" % playable.sealed_hatches.size()); return
	playable.utility_item_resolver.active_flags["lockpick"] = {"item_id": "lockpick_set", "count": 1}
	mech.set_validation_player_in_range(true)
	var res: Dictionary = mech.try_bypass(playable.player, playable.utility_item_resolver.active_flags)
	# Coordinator consumes the flag via the hatch_bypassed signal handler.
	var mechanical_open: bool = bool(res.get("ok", false)) and mech.bypassed
	var flag_consumed: bool = not playable.utility_item_resolver.active_flags.has("lockpick")
	if seeded and mechanical_open and flag_consumed:
		print("SEALED HATCH PASS away_ticks=%d seeded=true mechanical_open=true flag_consumed=true" % n)
		_cleanup(0)
	else:
		_fail("seeded=%s open=%s consumed=%s" % [str(seeded), str(mechanical_open), str(flag_consumed)])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("SEALED HATCH FAIL reason=%s" % reason)
	_cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run it — expect FAIL** (`_build_sealed_hatches` / `sealed_hatches` do not exist):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sealed_hatch_smoke.gd`
Expected: FAIL (missing member `sealed_hatches`).

- [ ] **Step 3: Add `consume_flag` to `utility_item_resolver.gd`** — after `use_item`:

```gdscript
## Domain 5: a utility flag is consumed when its promised bypass fires (e.g. a
## sealed hatch opened by lockpick/hack_chip). Returns true if a flag was removed.
func consume_flag(flag: String) -> bool:
	if flag.is_empty() or not active_flags.has(flag):
		return false
	active_flags.erase(flag)
	return true
```

- [ ] **Step 4: Add `bypassed_hatch_ids` to `ship_instance.gd`** — mirror `looted_container_ids`. Add the field, include it in `get_summary()` (additive), and read it in `apply_summary()` via `.get("bypassed_hatch_ids", [])`. **Read `scripts/systems/ship_instance.gd` for the exact `looted_container_ids` pattern and mirror it.**

```gdscript
var bypassed_hatch_ids: Array = []
```
(in `get_summary`) `result["bypassed_hatch_ids"] = bypassed_hatch_ids.duplicate(true)`
(in `apply_summary`) `bypassed_hatch_ids = (summary.get("bypassed_hatch_ids", []) as Array).duplicate(true)`

- [ ] **Step 5: Add coordinator hatch state + build/clear + seeding** — near the loot-container root fields (`:249-250`) add:

```gdscript
var sealed_hatch_root: Node3D = null
var sealed_hatches: Array = []
```

Create the root where `loot_container_root` is created (`:1218-1220`):

```gdscript
	sealed_hatch_root = Node3D.new()
	sealed_hatch_root.name = "SealedHatchRoot"
	add_child(sealed_hatch_root)
```

Add the build/clear pair (place near `_build_loot_containers`). Seeding is coordinator-side and deterministic per ship marker (avoids a loader-schema change): two hatches at distinct interior room positions, alternating lock kind.

```gdscript
const SEALED_HATCH_COUNT: int = 2
const SealedHatchScript := preload("res://scripts/interaction/sealed_hatch.gd")

func _build_sealed_hatches() -> void:
	_clear_sealed_hatches()
	if current_ship == null:
		return
	var positions: Array = _distributed_room_positions()
	if positions.is_empty():
		return
	var bypassed: Array = current_ship.bypassed_hatch_ids
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(current_ship.marker_id))
	var count: int = min(SEALED_HATCH_COUNT, positions.size())
	for i in range(count):
		var idx: int = (int(rng.randi()) + i * 7) % positions.size()
		var pos_variant: Variant = positions[idx]
		if typeof(pos_variant) != TYPE_VECTOR3:
			continue
		var hid: String = "%s:hatch_%d" % [String(current_ship.marker_id), i]
		var lock_kind: String = SealedHatchScript.MECHANICAL if (i % 2 == 0) else SealedHatchScript.ELECTRONIC
		var hatch = SealedHatchScript.new()
		hatch.configure(hid, lock_kind, pos_variant, 1.8)
		if bypassed.has(hid):
			hatch.set_bypassed(true)
		if not hatch.hatch_bypassed.is_connected(_on_hatch_bypassed):
			hatch.hatch_bypassed.connect(_on_hatch_bypassed)
		if away_from_start and current_ship != null and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root):
			current_ship.scene_root.add_child(hatch)
		else:
			sealed_hatch_root.add_child(hatch)
		sealed_hatches.append(hatch)

func _clear_sealed_hatches() -> void:
	for h in sealed_hatches:
		if is_instance_valid(h):
			h.queue_free()
	sealed_hatches.clear()
```

> **Implementer note:** confirm `_distributed_room_positions()` returns an `Array` of `Vector3` interior positions (it is used by the hallucination anchors). If it returns something else, use the same interior-position source the loot containers use.

- [ ] **Step 6: Call `_build_sealed_hatches()` where loot containers are built** — `_build_loot_containers()` is called at `:1925`. Add `_build_sealed_hatches()` immediately after it in the same setup path (and in the same revisit/attach path where loot containers are rebuilt, so hatches appear on a boarded derelict). **Read around `:1925` and the derelict-attach path to place both calls consistently.**

- [ ] **Step 7: Add the bypass signal handler (consumes the flag + status)** — add:

```gdscript
func _on_hatch_bypassed(hatch_id: String, lock_kind: String) -> void:
	var flag: String = "lockpick" if lock_kind == SealedHatchScript.MECHANICAL else "hack_chip"
	if utility_item_resolver != null:
		utility_item_resolver.consume_flag(flag)
	if status_effects_state != null and status_effects_state.has_method("remove_effect"):
		status_effects_state.remove_effect("utility_%s_ready" % flag, 9999)
	# Track for persistence so a revisited derelict remembers the open hatch.
	if current_ship != null and not current_ship.bypassed_hatch_ids.has(hatch_id):
		current_ship.bypassed_hatch_ids.append(hatch_id)
	_refresh_inventory_hud()
```

> **Implementer note:** confirm the resolver member name — brainstorming used `utility_item_resolver`; the context builder (`:4176`) exposes it as `utility_state → utility_item_state`. **Read `:4176` and the construct site** to use the correct variable name for the resolver instance (likely `utility_item_state`). Use that name consistently in Steps 3/7 and the smoke.

- [ ] **Step 8: Route the interact action to hatch bypass** — the interact dispatch tries interactables in turn (loot containers at `:3567-3570`). Add a hatch attempt in the same interact handler (before/after loot containers). Add:

```gdscript
func _try_bypass_nearest_hatch() -> bool:
	if player == null:
		return false
	for h in sealed_hatches:
		if not is_instance_valid(h) or h.bypassed:
			continue
		var res: Dictionary = h.try_bypass(player, utility_item_resolver.active_flags if utility_item_resolver != null else {})
		if bool(res.get("ok", false)):
			return true
	return false
```

Call `_try_bypass_nearest_hatch()` in the interact dispatch chain (read the `interact` handler that calls `lc.try_interact(player)` near `:3567`; add the hatch attempt there so pressing interact near a primed hatch opens it).

- [ ] **Step 9: Persist bypassed hatches** — where the ship/world snapshot is built and restored (loot uses `looted_container_ids`), ensure `current_ship.bypassed_hatch_ids` is captured/restored. Since it lives on `ShipInstance` (Step 4) and ship instances are already persisted, verify the round-trip; add capture only if `ShipInstance.get_summary` is not already serialized wholesale. **Read the ship-instance persistence path to confirm.**

- [ ] **Step 10: Run the smoke — expect PASS:**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sealed_hatch_smoke.gd`
Expected: `SEALED HATCH PASS away_ticks=3 seeded=true mechanical_open=true flag_consumed=true`

- [ ] **Step 11: Commit:**

```bash
git add scripts/systems/utility_item_resolver.gd scripts/systems/ship_instance.gd scripts/procgen/playable_generated_ship.gd scripts/validation/sealed_hatch_smoke.gd
git commit -m "feat: seed + bypass sealed hatches; consume utility flags

Domain 5: derelicts seed locked hatches (deterministic per marker); interacting
with the lockpick/hack_chip flag primed opens the matching hatch, consuming the
flag + status and unblocking the passage. Bypassed hatches persist per ship.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 7: Flare sanity-steadying reader

Give `utility_flare` a real consumer: while active, reduce sanity drain in unsafe zones.

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (sanity tick / attrition path)
- Create: `scripts/validation/flare_steady_smoke.gd`

**Interfaces:**
- Consumes: `status_effects_state.has_effect("utility_flare")` (confirm method name); `sanity_state` drain path.

- [ ] **Step 1: Confirm the drain path (verified)** — `SanityState.tick` (`scripts/systems/sanity_state.gd:26-40`) drains `drain_rate * delta_seconds` when `not in_safe_zone`; there is no steady/multiplier knob yet (this task adds one). The coordinator sets `sanity_state.in_safe_zone` right before ticking on both branches (away `:5024`, home `:5111`) — the flare multiplier is set at those same points. `status_effects_state.has_effect("utility_flare")` exists (`status_effects_state.gd:57`).

- [ ] **Step 2: Write the failing smoke** — `scripts/validation/flare_steady_smoke.gd` (pure-model where possible): drive two identical unsafe-zone sanity ticks, one with `utility_flare` active, and assert the flare run loses **less** sanity.

```gdscript
extends SceneTree

## Domain 5 Task 7: an active utility_flare steadies the player -> less sanity drain
## in an unsafe zone than without it.
## Marker: FLARE STEADY PASS drain_no_flare=<f> drain_flare=<f> steadier=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES: _fail("not ready")
		return
	_validate()

func _validate() -> void:
	finished = true
	playable.away_from_start = true  # unsafe zone
	# Run A: no flare.
	playable.sanity_state.configure({})
	var a0: float = playable.sanity_state.sanity
	for i in range(10): playable._process(1.0)
	var drain_no_flare: float = a0 - playable.sanity_state.sanity
	# Run B: flare active for the whole window.
	playable.sanity_state.configure({})
	var b0: float = playable.sanity_state.sanity
	for i in range(10):
		playable.status_effects_state.add_effect("utility_flare", 5.0, 1)  # keep it topped up
		playable._process(1.0)
	var drain_flare: float = b0 - playable.sanity_state.sanity
	var steadier: bool = drain_flare < drain_no_flare - 0.01
	if steadier:
		print("FLARE STEADY PASS drain_no_flare=%.3f drain_flare=%.3f steadier=true" % [drain_no_flare, drain_flare])
		_cleanup(0)
	else:
		_fail("drain_no_flare=%.3f drain_flare=%.3f" % [drain_no_flare, drain_flare])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip: return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null: return f
	return null

func _fail(reason: String) -> void:
	push_error("FLARE STEADY FAIL reason=%s" % reason); _cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node): main_node.queue_free()
	quit(code)
```

> **API note (verified):** `status_effects_state.add_effect(id, duration, stacks)` and `has_effect(id)` both exist (`status_effects_state.gd:17,57`). The smoke tops up `utility_flare` each tick so it stays active across the window.

- [ ] **Step 3: Run it — expect FAIL** (`steadier=false`: flare has no reader):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/flare_steady_smoke.gd`
Expected: FAIL with `steadier=false`.

- [ ] **Step 4a: Add the `steady_multiplier` knob to `SanityState`** — in `scripts/systems/sanity_state.gd`, add the field, apply it to the unsafe-zone drain, and reset it in `configure`:

Add after `var in_safe_zone: bool = false` (`:17`):
```gdscript
var steady_multiplier: float = 1.0  # Domain 5: <1.0 when a flare steadies the player
```
In `configure` (after `:24`):
```gdscript
	steady_multiplier = 1.0
```
In `tick`, change the drain line (`:36`) to apply the multiplier:
```gdscript
		var drn: float = drain_rate * steady_multiplier * delta_seconds
```

- [ ] **Step 4b: Set the multiplier from the flare flag on BOTH branches** — in `scripts/procgen/playable_generated_ship.gd`, immediately before each `sanity_state.tick(delta)` (away `:5025`, home `:5112`), set:

```gdscript
		sanity_state.steady_multiplier = 0.5 if (status_effects_state != null and status_effects_state.has_effect("utility_flare")) else 1.0
```

- [ ] **Step 5: Run the smoke — expect PASS:**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/flare_steady_smoke.gd`
Expected: `FLARE STEADY PASS drain_no_flare=... drain_flare=... steadier=true`

- [ ] **Step 6: Commit:**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/systems/sanity_state.gd scripts/validation/flare_steady_smoke.gd
git commit -m "feat: utility_flare steadies the player (reduced sanity drain)

Domain 5: an active utility_flare halves unsafe-zone sanity drain on both
_process branches, giving the flag a real reader (was decorative).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 8: Close the loop — inventory + validation registration + full bundle

Flip the inventory, register the new smokes, regenerate + verify, and gate on the full regression bundle.

**Files:**
- Modify: `docs/game/inventory/system_inventory.json` (consumables loop + system entries)
- Regenerate: `docs/game/inventory/SYSTEM_INVENTORY.md` + `system_map.html` (via `tools/build_system_inventory.py`)
- Modify: `docs/game/06_validation_plan.md` (register 6 new smokes + expected markers; bump `commands=`)

- [ ] **Step 1: Register the new smokes in `06_validation_plan.md`** — add these to the regression bundle command list with their expected markers, and bump the `commands=` count in the final `SYNAPTIC_SEA REGRESSION PASS commands=<N>` line by the number of added commands:
  - `thermal_consumable_smoke.gd` → `THERMAL CONSUMABLE PASS`
  - `ammo_magazine_state_smoke.gd` → `AMMO MAGAZINE STATE PASS`
  - `ammo_magazine_smoke.gd` → `AMMO MAGAZINE PASS`
  - `consumables_away_tick_smoke.gd` → `CONSUMABLES AWAY TICK PASS`
  - `sealed_hatch_node_smoke.gd` → `SEALED HATCH NODE PASS`
  - `sealed_hatch_smoke.gd` → `SEALED HATCH PASS`
  - `flare_steady_smoke.gd` → `FLARE STEADY PASS`

  **Read the existing bundle structure first** and follow its exact command + grep-marker format.

- [ ] **Step 2: Update `system_inventory.json`** — set `consumables.closes → "closed"`; clear/reduce the five break-points to reflect: magazine consumption (ammo_state live), orphan effects removed, stim/addiction away-tick, utility flags consumed by hatch bypass + flare reader, `temperature_delta` live. Flip `ammo_state.output.live` true (cite `threat_manager.attack_with_weapon` magazine spend + coordinator reload), `utility_item_resolver.output.live` true (cite hatch bypass consume_flag + flare reader). Add inventory entries for the new `SealedHatch` model if the coverage check requires it. **Distinguish model tick (both branches) from player-facing output.** Cite exact `function:symbol` + line where practical.

- [ ] **Step 3: Regenerate the inventory MD + HTML:**

```bash
python tools/build_system_inventory.py
```

- [ ] **Step 4: Run the inventory `--check` + `--coverage`:**

```bash
python tools/build_system_inventory.py --check
python tools/build_system_inventory.py --coverage
```
Expected: `SYSTEM INVENTORY CHECK PASS systems=<N> verified=<N>` (all verified) and no "not in inventory" from `--coverage`.

- [ ] **Step 5: Run the FULL regression bundle** (see Global Constraints for extraction):

```bash
bash /tmp/reg.sh; echo "EXIT=$?"
```
Expected: `EXIT=0`, no unexpected `ERROR:`/`WARNING:`/`FAIL`, all markers present, final line `SYNAPTIC_SEA REGRESSION PASS commands=<N>`.

- [ ] **Step 6: Commit:**

```bash
git add docs/game/inventory/system_inventory.json docs/game/inventory/SYSTEM_INVENTORY.md docs/game/inventory/system_map.html docs/game/06_validation_plan.md
git commit -m "docs: close consumables loop in inventory + register Domain 5 smokes

Domain 5 complete: consumables.closes -> closed; ammo_state/utility_item_resolver
output.live flipped with citations; five break-points cleared; 7 new smokes
registered in the regression bundle.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

## Self-review checklist (controller, before dispatch)

- **Spec coverage:** ammo→magazine (T2/T3) · stim/addiction away-tick (T4) · sealed-hatch (T5/T6) · temperature_delta (T1) · flare reader (T7) · orphan cleanup (T3) · inventory/validation (T8). All five spec break-points mapped.
- **Away-branch:** reload tick (T3), stim/addiction (T4), hatch presence (T6), flare reader (T7) all wired on the away branch with `away_ticks=` smokes.
- **Type consistency:** `AmmoState.spend/loaded/begin_reload/tick/reload_target` used identically in T2/T3. `SealedHatch.try_bypass/hatch_bypassed/required_flag/MECHANICAL` used identically in T5/T6. Resolver variable name flagged in T6 note (confirm `utility_item_resolver` vs `utility_item_state` before wiring — must be consistent across T3/T6/T7).
- **Combat regression fence:** T3 re-runs `combat_closure_smoke.gd`; T8's bundle re-runs every combat/hull/fire smoke.
- **Verified APIs (hardened in-plan):** `StimulantState.active_stims[].remaining` + `AddictionState.record_dose`/`get_tolerance`/`tick` (T4); `SanityState.tick` drain + new `steady_multiplier` (T7); `StatusEffectsState.add_effect`/`remove_effect`/`has_effect` (T6/T7); `body_temperature_state.adjust_temperature`/`get_summary["temperature"]` (T1).
- **Open confirmations for implementers (flagged inline, low-risk):** resolver instance variable name (`utility_item_resolver` vs `utility_item_state` — T6 note; must be consistent across T3/T6/T7); `_distributed_room_positions()` return shape; player group name for hatch proximity; `ship_instance` persistence round-trip. Each is a "read the cited file, match the real symbol" note, not a `TBD` in the deliverable.
