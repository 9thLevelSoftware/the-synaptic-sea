# Per-Container Weight Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Worn containers reduce the *effective* weight of the load they carry (capacity-share, best-first), so a better bag measurably lowers the Heavy-Load penalty and the displayed Load%.

**Architecture:** A pure-data def field (`weight_reduction`) + a pure static fill algorithm (`Encumbrance.weight_reduction_saved`) + a data provider on `EquipmentState` + an effective-weight path on `InventoryState`, wired at the coordinator's existing `_recompute_player_encumbrance` (mirrors the `bonus_capacity` push). The vitals Load line gains a `(bags -Nkg)` marker. No save-schema change; reduction is derived from persisted equipment and recomputed on load.

**Tech Stack:** Godot 4.6.2, GDScript (typed). Headless validation smokes (`--headless --script`); trust the PASS marker, never the exit code.

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`. Run every smoke headless: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke>.gd`.
- **Trust the PASS marker, not the exit code.** Godot `--script` can exit 0 on parse/load errors. RED = the PASS marker is absent (a failed `assert` aborts; a `_fail` prints `... FAIL reason=...`). GREEN = the exact PASS marker line is present.
- **Allowlisted baseline noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`. Any other `ERROR:`/`WARNING:` blocks completion.
- **Keep every PASS marker literally unchanged.** No new bundle registrations, no `06_validation_plan.md` grep edits; the bundle stays at `commands=120`.
- **Reduction values:** EVA Backpack `0.30`, Field Pack `0.15`, Tool Belt `0.10`; default for any container without the field = `0.0`. `weight_reduction` is clamped to `[0.0, 1.0]` at the accessor.
- **No persistence change.** `InventoryState.get_summary()` keeps emitting `total_weight` as the RAW weight. Reduction is recomputed on load by `_recompute_player_encumbrance`.
- **Effective weight feeds `get_load_ratio()` AND `is_over_capacity()`** together (consistency). `get_total_weight()` stays raw.
- **Commit hygiene:** Conventional Commits; selective `git add <explicit paths>` ONLY — never `git add -A`; NEVER stage `project.godot`, `.godot/`, `*.uid`, `addons/`. End every commit message with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Branch:** `per-container-weight-reduction` (off main @ `667b0ee`; spec committed `8026fd9`).

For brevity, each task's run commands assume these are exported once per shell:

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
```

---

## File Structure

| File | Responsibility | Task |
|------|----------------|------|
| `data/items/equipment_definitions.json` | declare `weight_reduction` on the 3 containers | 1 |
| `scripts/systems/item_defs.gd` | `weight_reduction()` accessor (clamped) | 1 |
| `scripts/validation/equipment_defs_smoke.gd` | assert the def values | 1 |
| `scripts/systems/encumbrance.gd` | `weight_reduction_saved()` fill algorithm | 2 |
| `scripts/validation/encumbrance_smoke.gd` | assert the fill math | 2 |
| `scripts/systems/equipment_state.gd` | `get_container_reductions()` provider | 3 |
| `scripts/validation/equipment_state_smoke.gd` | assert the provider shape | 3 |
| `scripts/systems/inventory_state.gd` | `weight_reduction` field + effective-weight path | 4 |
| `scripts/validation/inventory_state_smoke.gd` | assert effective ratio/over-capacity | 4 |
| `scripts/systems/player_vitals_model.gd` | `(bags -Nkg)` Load marker | 5 |
| `scripts/validation/player_vitals_model_smoke.gd` | assert the marker | 5 |
| `scripts/procgen/playable_generated_ship.gd` | wire the push + pass to vitals | 6 |
| `scripts/validation/main_playable_slice_vitals_hud_smoke.gd` | main-scene bag phase | 6 |
| `docs/game/adr/0028-per-container-weight-reduction.md` | ADR | 7 |
| `docs/game/09_system_roadmap.md` | System 6 row update | 7 |

---

### Task 1: Def field + `weight_reduction` accessor

**Files:**
- Modify: `data/items/equipment_definitions.json`
- Modify: `scripts/systems/item_defs.gd:76-77`
- Test: `scripts/validation/equipment_defs_smoke.gd`

**Interfaces:**
- Produces: `ItemDefs.weight_reduction(defs: Dictionary, item_id: String) -> float` — declared reduction clamped to `[0.0, 1.0]`, default `0.0`.

- [ ] **Step 1: Write the failing test.** In `scripts/validation/equipment_defs_smoke.gd`, add an `_approx` helper and the new assertions. Insert the assertions immediately after line 18 (`assert(ItemDefsScript.container_capacity(defs, "hardsuit") == 0.0, ...)`):

```gdscript
	assert(_approx(ItemDefsScript.weight_reduction(defs, "eva_backpack"), 0.30), "backpack reduces 30%")
	assert(_approx(ItemDefsScript.weight_reduction(defs, "field_pack"), 0.15), "field_pack reduces 15%")
	assert(_approx(ItemDefsScript.weight_reduction(defs, "tool_belt"), 0.10), "tool_belt reduces 10%")
	assert(ItemDefsScript.weight_reduction(defs, "hardsuit") == 0.0, "suit has no weight reduction")
	assert(ItemDefsScript.weight_reduction(defs, "scrap_metal") == 0.0, "plain item has no weight reduction")
```

And add this helper just above `func _init()` (line 9):

```gdscript
func _approx(a: float, b: float) -> bool:
	return absf(a - b) <= 0.0001
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_defs_smoke.gd`
Expected: NO `EQUIPMENT DEFS SMOKE PASS` line (the call to the missing `weight_reduction` aborts/errors).

- [ ] **Step 3: Add the accessor.** In `scripts/systems/item_defs.gd`, insert immediately after `container_capacity` (after line 77):

```gdscript
static func weight_reduction(defs: Dictionary, item_id: String) -> float:
	return clampf(float(get_definition(defs, item_id).get("weight_reduction", 0.0)), 0.0, 1.0)
```

- [ ] **Step 4: Add the data.** In `data/items/equipment_definitions.json`, add a `weight_reduction` field to the three containers (the suit is unchanged). The file becomes:

```json
{
  "eva_backpack": {
    "display_name": "EVA Backpack",
    "category": "equipment",
    "weight": 3.0,
    "max_stack": 1,
    "equip_slot": "back",
    "container_capacity": 40.0,
    "weight_reduction": 0.30
  },
  "field_pack": {
    "display_name": "Field Pack",
    "category": "equipment",
    "weight": 1.5,
    "max_stack": 1,
    "equip_slot": "back",
    "container_capacity": 15.0,
    "weight_reduction": 0.15
  },
  "tool_belt": {
    "display_name": "Tool Belt",
    "category": "equipment",
    "weight": 1.0,
    "max_stack": 1,
    "equip_slot": "waist",
    "container_capacity": 12.0,
    "weight_reduction": 0.10
  },
  "hardsuit": {
    "display_name": "Salvage Hardsuit",
    "category": "equipment",
    "weight": 6.0,
    "max_stack": 1,
    "equip_slot": "suit",
    "effects": [{ "type": "oxygen_drain", "value": 0.75 }]
  }
}
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_defs_smoke.gd`
Expected: `EQUIPMENT DEFS SMOKE PASS slots=3 effects=1` and no non-allowlisted ERROR/WARNING.

- [ ] **Step 6: Commit.**

```bash
git add data/items/equipment_definitions.json scripts/systems/item_defs.gd scripts/validation/equipment_defs_smoke.gd
git commit -m "feat(inventory): add weight_reduction item-def field + accessor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `Encumbrance.weight_reduction_saved` fill algorithm

**Files:**
- Modify: `scripts/systems/encumbrance.gd`
- Test: `scripts/validation/encumbrance_smoke.gd`

**Interfaces:**
- Produces: `Encumbrance.weight_reduction_saved(total_weight: float, container_reductions: Array) -> float`. `container_reductions` is an `Array` of `{ "capacity": float, "reduction": float }`. Returns saved kg (>= 0); fills best-first (highest reduction first), each container covering up to its capacity of the remaining weight.

- [ ] **Step 1: Write the failing test.** In `scripts/validation/encumbrance_smoke.gd`, insert these assertions immediately before `print("EQUIPMENT ENCUMBRANCE SMOKE PASS floor=0.25")` (line 28). The file already has `_approx(a, b)` (tolerance 0.01).

```gdscript
	# --- per-container weight reduction (slice D): capacity-share, best-first ---
	assert(_approx(EncumbranceScript.weight_reduction_saved(100.0, []), 0.0), "no containers -> 0 saved")
	# Single container, weight under its capacity -> covers all weight.
	assert(_approx(EncumbranceScript.weight_reduction_saved(30.0, [{"capacity": 40.0, "reduction": 0.30}]), 9.0), "30kg x0.30 = 9 saved")
	# Single container, weight over its capacity -> covers only its capacity.
	assert(_approx(EncumbranceScript.weight_reduction_saved(100.0, [{"capacity": 40.0, "reduction": 0.30}]), 12.0), "40kg cap x0.30 = 12 saved")
	# Best-first ordering matters when weight runs out mid-fill: 40kg across
	# caps 30(0.10) + 30(0.50). Best-first fills the 0.50 bag first:
	# 30x0.50 + 10x0.10 = 16.0  (list order would give 30x0.10 + 10x0.50 = 8.0).
	assert(_approx(EncumbranceScript.weight_reduction_saved(40.0, [{"capacity": 30.0, "reduction": 0.10}, {"capacity": 30.0, "reduction": 0.50}]), 16.0), "best-first fill saves 16, not 8")
	# Worked spec example: 70kg, EVA(40,0.30) + belt(12,0.10) = 13.2 saved.
	assert(_approx(EncumbranceScript.weight_reduction_saved(70.0, [{"capacity": 40.0, "reduction": 0.30}, {"capacity": 12.0, "reduction": 0.10}]), 13.2), "spec example saves 13.2")
	# Non-positive weight -> 0 saved.
	assert(_approx(EncumbranceScript.weight_reduction_saved(-5.0, [{"capacity": 40.0, "reduction": 0.30}]), 0.0), "negative weight saves 0")
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/encumbrance_smoke.gd`
Expected: NO `EQUIPMENT ENCUMBRANCE SMOKE PASS` line.

- [ ] **Step 3: Add the algorithm.** In `scripts/systems/encumbrance.gd`, append after `move_speed_multiplier` (after line 20):

```gdscript

## Capacity-share, best-first weight reduction. container_reductions is an Array
## of { "capacity": float, "reduction": float }. Sorts best-first (highest
## reduction), lets each container cover up to its capacity of the remaining
## weight at its reduction rate, and returns the total kg saved (>= 0). Weight
## beyond all containers is uncovered. Never exceeds total_weight.
static func weight_reduction_saved(total_weight: float, container_reductions: Array) -> float:
	var sorted: Array = container_reductions.duplicate()
	sorted.sort_custom(func(a, b): return float(a["reduction"]) > float(b["reduction"]))
	var remaining: float = maxf(0.0, total_weight)
	var saved: float = 0.0
	for c in sorted:
		if remaining <= 0.0:
			break
		var covered: float = minf(remaining, maxf(0.0, float(c["capacity"])))
		saved += covered * clampf(float(c["reduction"]), 0.0, 1.0)
		remaining -= covered
	return saved
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/encumbrance_smoke.gd`
Expected: `EQUIPMENT ENCUMBRANCE SMOKE PASS floor=0.25` and no non-allowlisted ERROR/WARNING.

- [ ] **Step 5: Commit.**

```bash
git add scripts/systems/encumbrance.gd scripts/validation/encumbrance_smoke.gd
git commit -m "feat(inventory): Encumbrance.weight_reduction_saved (capacity-share, best-first)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `EquipmentState.get_container_reductions` provider

**Files:**
- Modify: `scripts/systems/equipment_state.gd:54-58`
- Test: `scripts/validation/equipment_state_smoke.gd`

**Interfaces:**
- Consumes: `ItemDefs.weight_reduction(defs, item_id)` (Task 1), `ItemDefs.container_capacity(defs, item_id)`.
- Produces: `EquipmentState.get_container_reductions() -> Array` — `[{ "capacity": float, "reduction": float }, ...]`, one entry per worn item whose `container_capacity > 0` (the suit, capacity 0, is excluded). Iteration order is the `slots` dict order (callers must not depend on it).

- [ ] **Step 1: Write the failing test.** In `scripts/validation/equipment_state_smoke.gd`, insert this block immediately after line 30 (`assert(eq.get_oxygen_drain_multiplier() == 0.75, "hardsuit drain multiplier 0.75")`), while `eva_backpack` + `tool_belt` + `hardsuit` are all worn and BEFORE the `field_pack` displacement on line 33:

```gdscript
	# get_container_reductions: worn containers only (suit excluded, capacity 0).
	var reds: Array = eq.get_container_reductions()
	assert(reds.size() == 2, "two worn containers (suit excluded), got %d" % reds.size())
	var by_cap: Dictionary = {}
	for r in reds:
		by_cap[float(r["capacity"])] = float(r["reduction"])
	assert(by_cap.has(40.0) and absf(by_cap[40.0] - 0.30) < 0.0001, "backpack 40 -> 0.30")
	assert(by_cap.has(12.0) and absf(by_cap[12.0] - 0.10) < 0.0001, "tool_belt 12 -> 0.10")
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_state_smoke.gd`
Expected: NO `EQUIPMENT STATE SMOKE PASS` line.

- [ ] **Step 3: Add the provider.** In `scripts/systems/equipment_state.gd`, insert after `get_carry_capacity_bonus` (after line 58):

```gdscript

## [{capacity, reduction}] for each worn item that is a container (capacity > 0).
## The suit (no container_capacity) is excluded. Pure data; feeds
## Encumbrance.weight_reduction_saved at the coordinator.
func get_container_reductions() -> Array:
	var out: Array = []
	for slot in slots:
		var cap: float = ItemDefsScript.container_capacity(_defs, str(slots[slot]))
		if cap > 0.0:
			out.append({
				"capacity": cap,
				"reduction": ItemDefsScript.weight_reduction(_defs, str(slots[slot])),
			})
	return out
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_state_smoke.gd`
Expected: `EQUIPMENT STATE SMOKE PASS bonus=27 oxy=0.75` (the existing marker; values unchanged) and no non-allowlisted ERROR/WARNING.

- [ ] **Step 5: Commit.**

```bash
git add scripts/systems/equipment_state.gd scripts/validation/equipment_state_smoke.gd
git commit -m "feat(inventory): EquipmentState.get_container_reductions provider

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `InventoryState` effective-weight path

**Files:**
- Modify: `scripts/systems/inventory_state.gd:19-20,52-60`
- Test: `scripts/validation/inventory_state_smoke.gd:113`

**Interfaces:**
- Produces: `InventoryState.weight_reduction: float` (saved kg, default `0.0`, pushed by the coordinator); `InventoryState.get_effective_weight() -> float` = `max(0, total - weight_reduction)`. `get_load_ratio()` and `is_over_capacity()` now use effective weight; `get_total_weight()` stays raw.

- [ ] **Step 1: Write the failing test.** In `scripts/validation/inventory_state_smoke.gd`, insert this block immediately after line 113 (`assert(not sc.is_over_capacity(), "container bonus lifts player back under capacity")`), before the final `print(...)`:

```gdscript
	# --- per-container weight reduction (slice D): effective weight feeds ratio ---
	var wr := InventoryState.new()
	wr.add_item("scrap_metal", 20)              # 20 * 5.0 = 100.0 raw weight, base cap 50
	assert(wr.get_total_weight() == 100.0, "raw weight is 100 before reduction")
	assert(wr.is_over_capacity(), "over capacity before reduction")
	wr.weight_reduction = 60.0                   # coordinator pushes saved kg
	assert(absf(wr.get_effective_weight() - 40.0) < 0.0001, "effective = raw - reduction = 40")
	assert(wr.get_total_weight() == 100.0, "raw weight unchanged by reduction")
	assert(not wr.is_over_capacity(), "reduction lifts effective under capacity")
	assert(absf(wr.get_load_ratio() - 0.8) < 0.0001, "load ratio uses effective: 40/50 = 0.8")
	wr.weight_reduction = 1000.0                 # over-large reduction never goes negative
	assert(wr.get_effective_weight() == 0.0, "effective weight clamps at 0")
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_state_smoke.gd`
Expected: NO `INVENTORY STATE PASS` line (the missing `weight_reduction` field / `get_effective_weight` aborts).

- [ ] **Step 3: Add the field.** In `scripts/systems/inventory_state.gd`, add the field after line 20 (`var bonus_capacity: float = 0.0 ...`):

```gdscript
	var weight_reduction: float = 0.0   # saved kg from worn containers (set by the coordinator)
```

(Match the existing indentation: these are module-level `var`s declared at column 0 — insert it as `var weight_reduction: float = 0.0` with no leading tab, immediately below the `bonus_capacity` line.)

- [ ] **Step 4: Add `get_effective_weight` and switch the ratio/over-capacity to effective.** Replace the existing `get_capacity` / `get_load_ratio` / `is_over_capacity` block (lines 51-60):

```gdscript
## Effective carry budget = base cap + worn-container bonus (+ future strength).
func get_capacity() -> float:
	return MAX_WEIGHT + bonus_capacity

## total_weight / capacity. >1.0 means over-encumbered (Heavy Load).
func get_load_ratio() -> float:
	return get_total_weight() / max(0.0001, get_capacity())

func is_over_capacity() -> bool:
	return get_total_weight() > get_capacity()
```

with:

```gdscript
## Effective carry budget = base cap + worn-container bonus (+ future strength).
func get_capacity() -> float:
	return MAX_WEIGHT + bonus_capacity

## Raw weight minus the worn-container weight reduction (saved kg), floored at 0.
## get_total_weight() stays the true mass; this is what encumbrance keys off.
func get_effective_weight() -> float:
	return maxf(0.0, get_total_weight() - weight_reduction)

## effective_weight / capacity. >1.0 means over-encumbered (Heavy Load).
func get_load_ratio() -> float:
	return get_effective_weight() / max(0.0001, get_capacity())

func is_over_capacity() -> bool:
	return get_effective_weight() > get_capacity()
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_state_smoke.gd`
Expected: `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5` (the existing marker; values unchanged) and no non-allowlisted ERROR/WARNING.

- [ ] **Step 6: Commit.**

```bash
git add scripts/systems/inventory_state.gd scripts/validation/inventory_state_smoke.gd
git commit -m "feat(inventory): InventoryState effective-weight path (weight_reduction)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Vitals Load marker

**Files:**
- Modify: `scripts/systems/player_vitals_model.gd:14-15,24-26,98-103`
- Test: `scripts/validation/player_vitals_model_smoke.gd:112`

**Interfaces:**
- Produces: `PlayerVitalsModel.apply_inventory_load(load_ratio: float, move_multiplier: float, weight_saved: float = 0.0)` — the defaulted third param keeps existing callers valid. `_load_line()` appends `" (bags -Nkg)"` (N = `int(round(weight_saved))`) when `N >= 1`.

- [ ] **Step 1: Write the failing test.** In `scripts/validation/player_vitals_model_smoke.gd`, insert this block immediately after line 112 (`return` of the "blocked line clears" check), before `print("PLAYER VITALS MODEL SMOKE PASS ...")`:

```gdscript
	# --- per-container weight reduction marker (slice D) ---
	m.apply_inventory_load(0.56, 1.0, 13.2)
	if not _has(m.get_status_lines(), "Load: 56% (bags -13kg)"):
		_fail("expected bag-reduction marker, got %s" % str(m.get_status_lines()))
		return
	m.apply_inventory_load(1.40, 0.70, 13.2)
	if not _has(m.get_status_lines(), "Load: 140% HEAVY (-30% move) (bags -13kg)"):
		_fail("expected heavy + bag marker, got %s" % str(m.get_status_lines()))
		return
	m.apply_inventory_load(0.56, 1.0, 0.0)
	if not _has(m.get_status_lines(), "Load: 56%"):
		_fail("expected no marker at zero reduction, got %s" % str(m.get_status_lines()))
		return
	m.apply_inventory_load(0.56, 1.0, 0.4)   # rounds to 0 -> no marker
	if not _has(m.get_status_lines(), "Load: 56%"):
		_fail("sub-1kg reduction should not show a marker, got %s" % str(m.get_status_lines()))
		return
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_vitals_model_smoke.gd`
Expected: NO `PLAYER VITALS MODEL SMOKE PASS` line (the `(bags -13kg)` suffix is absent until `_load_line` is updated). Note the 3-arg `apply_inventory_load` call itself does not error even before Step 3 only if the default param exists — so this RED is driven by the missing suffix; it will print `... FAIL reason=expected bag-reduction marker ...`.

- [ ] **Step 3: Store the saved weight.** In `scripts/systems/player_vitals_model.gd`, add the field after line 15 (`var _move_multiplier: float = 1.0`):

```gdscript
var _weight_saved: float = 0.0
```

- [ ] **Step 4: Accept the new param.** Replace `apply_inventory_load` (lines 24-26):

```gdscript
func apply_inventory_load(load_ratio: float, move_multiplier: float) -> void:
	_load_ratio = maxf(0.0, load_ratio)
	_move_multiplier = move_multiplier
```

with:

```gdscript
func apply_inventory_load(load_ratio: float, move_multiplier: float, weight_saved: float = 0.0) -> void:
	_load_ratio = maxf(0.0, load_ratio)
	_move_multiplier = move_multiplier
	_weight_saved = maxf(0.0, weight_saved)
```

- [ ] **Step 5: Append the marker.** Replace `_load_line` (lines 98-103):

```gdscript
func _load_line() -> String:
	var pct: int = int(round(_load_ratio * 100.0))
	if _load_ratio > 1.0:
		var penalty: int = int(round((1.0 - _move_multiplier) * 100.0))
		return "Load: %d%% HEAVY (-%d%% move)" % [pct, penalty]
	return "Load: %d%%" % pct
```

with:

```gdscript
func _load_line() -> String:
	var pct: int = int(round(_load_ratio * 100.0))
	var saved_kg: int = int(round(_weight_saved))
	var suffix: String = " (bags -%dkg)" % saved_kg if saved_kg >= 1 else ""
	if _load_ratio > 1.0:
		var penalty: int = int(round((1.0 - _move_multiplier) * 100.0))
		return "Load: %d%% HEAVY (-%d%% move)%s" % [pct, penalty, suffix]
	return "Load: %d%%%s" % [pct, suffix]
```

- [ ] **Step 6: Run the test to verify it passes.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_vitals_model_smoke.gd`
Expected: `PLAYER VITALS MODEL SMOKE PASS suit=-25 heavy=-30 repair=47` (marker unchanged) and no non-allowlisted ERROR/WARNING.

- [ ] **Step 7: Commit.**

```bash
git add scripts/systems/player_vitals_model.gd scripts/validation/player_vitals_model_smoke.gd
git commit -m "feat(hud): vitals Load line shows the bag weight-reduction marker

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Coordinator wiring + main-scene smoke

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd:1620-1623,3206-3208`
- Test: `scripts/validation/main_playable_slice_vitals_hud_smoke.gd:39-51,116-129`

**Interfaces:**
- Consumes: `Encumbrance.weight_reduction_saved` (Task 2), `EquipmentState.get_container_reductions` (Task 3), `InventoryState.weight_reduction` + `get_load_ratio` (Task 4), `PlayerVitalsModel.apply_inventory_load(.., weight_saved)` (Task 5). `EncumbranceScript` is already a const in this file (used at line 1625).

- [ ] **Step 1: Write the failing test.** Edit `scripts/validation/main_playable_slice_vitals_hud_smoke.gd`.

  (a) Add the `settle_bags` branch to the `match phase` block. Replace lines 46-49:

```gdscript
			"settle_heavy":
				_check_heavy()
			"settle_repair":
				_check_repair()
```

with:

```gdscript
			"settle_heavy":
				_check_heavy()
			"settle_bags":
				_check_bags()
			"settle_repair":
				_check_repair()
```

  (b) Replace the tail of `_check_heavy` (lines 123-129, from the `# Drive an active repair channel` comment through `phase_frames = 0`):

```gdscript
	# Drive an active repair channel directly on a repair point.
	repair_point = playable.repair_points[0]
	repair_point.set_process(false)   # stop RepairPoint self-cancelling the directly-set channel
	repair_point.channeling = true
	repair_point.progress = 0.47
	phase = "settle_repair"
	phase_frames = 0
```

with:

```gdscript
	# Equip a backpack and recompute: it raises the cap AND reduces effective
	# weight, so the Load line gains the bag-reduction marker.
	var bag: Dictionary = playable.equipment_state.equip("eva_backpack")
	if not bool(bag.get("ok", false)):
		_fail("equipping eva_backpack failed")
		return
	playable._recompute_player_encumbrance()
	phase = "settle_bags"
	phase_frames = 0

func _check_bags() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	# 100 kg of scrap, EVA backpack cap 40 / 30% -> saves 12 kg.
	if not _line_with(playable.get_player_vitals_lines(), "Load:", "(bags -12kg)"):
		_fail("expected a Load line with the bag-reduction marker, got %s" % str(playable.get_player_vitals_lines()))
		return
	# Drive an active repair channel directly on a repair point.
	repair_point = playable.repair_points[0]
	repair_point.set_process(false)   # stop RepairPoint self-cancelling the directly-set channel
	repair_point.channeling = true
	repair_point.progress = 0.47
	phase = "settle_repair"
	phase_frames = 0
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_hud_smoke.gd`
Expected: NO `MAIN PLAYABLE VITALS HUD PASS` line — it prints `... FAIL reason=expected a Load line with the bag-reduction marker ...` because the coordinator does not yet push `weight_reduction`.

- [ ] **Step 3: Push the reduction in `_recompute_player_encumbrance`.** In `scripts/procgen/playable_generated_ship.gd`, replace lines 1620-1623:

```gdscript
	var bonus: float = 0.0
	if equipment_state != null:
		bonus = equipment_state.get_carry_capacity_bonus()   # + future strength bonus
	inventory_state.bonus_capacity = bonus
```

with:

```gdscript
	var bonus: float = 0.0
	var saved: float = 0.0
	if equipment_state != null:
		bonus = equipment_state.get_carry_capacity_bonus()   # + future strength bonus
		saved = EncumbranceScript.weight_reduction_saved(
			inventory_state.get_total_weight(), equipment_state.get_container_reductions())
	inventory_state.bonus_capacity = bonus
	inventory_state.weight_reduction = saved
```

- [ ] **Step 4: Pass the saved weight to the vitals model.** Replace lines 3206-3208:

```gdscript
	if inventory_state != null:
		var ratio: float = inventory_state.get_load_ratio()
		vitals_model.apply_inventory_load(ratio, EncumbranceScript.move_speed_multiplier(ratio))
```

with:

```gdscript
	if inventory_state != null:
		var ratio: float = inventory_state.get_load_ratio()
		vitals_model.apply_inventory_load(ratio, EncumbranceScript.move_speed_multiplier(ratio), inventory_state.weight_reduction)
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_hud_smoke.gd`
Expected: `MAIN PLAYABLE VITALS HUD PASS panel=true breach=true suit=true heavy=true repair=true` (marker unchanged) and no non-allowlisted ERROR/WARNING.

- [ ] **Step 6: Commit.**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_vitals_hud_smoke.gd
git commit -m "feat(inventory): wire per-container weight reduction into encumbrance + vitals

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: ADR-0028 + roadmap + full regression bundle

**Files:**
- Create: `docs/game/adr/0028-per-container-weight-reduction.md`
- Modify: `docs/game/09_system_roadmap.md` (System 6 row, line 39)

**Interfaces:** none (docs + verification).

- [ ] **Step 1: Write ADR-0028.** Create `docs/game/adr/0028-per-container-weight-reduction.md` (mirrors the ADR-0027 structure):

```markdown
# ADR-0028: Per-Container Weight Reduction

Date: 2026-06-25
Status: Accepted
System: 6 — Inventory & Equipment (Phase 7 deferred sub-slice D)
Relates to: ADR-0021 (equipment & carts), ADR-0023 (widget layer),
ADR-0025/0027 (player-vitals HUD).

## Context

A worn container only raised carry capacity (`bonus_capacity`); it never reduced
the weight of what it carried. Choosing between the EVA Backpack, Field Pack, and
Tool Belt was therefore a flat capacity decision with no Project-Zomboid-style
"pack the heavy things in a good bag" trade-off. The player inventory is a flat
`{item_id -> quantity}` model with no per-item container assignment, so a true
nested-container model was out of scope.

## Decision

Worn containers reduce the **effective** weight of the load they carry, computed
by a pure **capacity-share, best-first** function:

- Each container declares `weight_reduction` ∈ [0, 1] (new item-def field,
  default 0; clamped at the accessor).
- Sort worn containers best-first; each covers up to its `container_capacity` of
  the remaining weight at its reduction rate; weight beyond all containers rides
  on the body unreduced. `saved_kg = Σ covered_i × reduction_i`;
  `effective_weight = max(0, total − saved_kg)`.
- The fill lives in `Encumbrance.weight_reduction_saved`; `EquipmentState`
  exposes the worn `(capacity, reduction)` list; `InventoryState` gains a
  coordinator-pushed `weight_reduction` field and an effective-weight
  `get_load_ratio()` / `is_over_capacity()`. `get_total_weight()` stays raw.
- The coordinator pushes the reduction in `_recompute_player_encumbrance`
  (mirroring the `bonus_capacity` push) and passes it to the vitals model.
- The vitals Load line shows a `(bags -Nkg)` marker when reduction is active.
- Reduction values: EVA Backpack 0.30, Field Pack 0.15, Tool Belt 0.10.

## Consequences

- A better bag now lowers both the displayed Load% and the actual Heavy-Load
  movement penalty — capacity and reduction stack (intended; a good bag is doubly
  good, as in PZ).
- No save-schema change: reduction is derived from the persisted `EquipmentState`
  and recomputed on load.
- `get_load_ratio()` and `is_over_capacity()` move to effective weight together,
  so the inventory panel's readout and the vitals "heavy" indicator stay
  consistent. `is_over_capacity()` had no runtime consumers (smokes only).
- Carts are unchanged — they already remove weight from the player entirely.
- Deferred: strength-skill capacity scaling (slice B) and endurance/health
  Heavy-Load effects (slice C) still require a physical attribute/condition model.

## Validation

Six existing smokes extended, all PASS markers unchanged: `equipment_defs_smoke`,
`encumbrance_smoke`, `equipment_state_smoke`, `inventory_state_smoke`,
`player_vitals_model_smoke`, `main_playable_slice_vitals_hud_smoke`. Full
regression bundle green at `commands=120`.
```

- [ ] **Step 2: Update the roadmap.** In `docs/game/09_system_roadmap.md`, find the System 6 row (line 39). Make two edits:

  (a) Immediately after `vitals/HUD cleanup (...) — ADR-0027 ✅;` and before ` *Remaining:*`, insert:

```
 per-container weight reduction (worn containers reduce effective load — capacity-share, best-first; the Load line shows the bag savings) — ADR-0028 ✅;
```

  (b) In that row's `*Remaining:*` list, delete `nested per-container weight-reduction, ` and change the trailing `(Phase 7 sub-slices B/C/D)` to `(Phase 7 sub-slices B/C)`.

- [ ] **Step 3: Run the full regression bundle.** Stash the local `project.godot` autoload drift first (the headless run breaks otherwise), run the bundle, then restore the stash:

```bash
cd "$ROOT"
git stash push -- project.godot
bash <(awk '/^## Regression bundle/{f=1} f && /^```bash$/ {c=1; next} f && c && /^```$/ {exit} f && c {print}' docs/game/06_validation_plan.md)
git stash pop
```

Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=120 clean_output=true`.
If the bundle fails, fix the offending smoke before committing; do NOT commit `project.godot` or any `.godot/` file. If `git stash pop` reports the working tree already has `project.godot` changes, that is the pre-existing local drift — resolve by keeping the stashed (pre-run) version.

- [ ] **Step 4: Commit the docs.**

```bash
git add docs/game/adr/0028-per-container-weight-reduction.md docs/game/09_system_roadmap.md
git commit -m "docs(inventory): ADR-0028 per-container weight reduction + roadmap

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Model (capacity-share, best-first) → Task 2 algorithm + Task 6 wiring. ✅
- `weight_reduction` def field + values (30/15/10, default 0, clamped) → Task 1. ✅
- `ItemDefs.weight_reduction` → Task 1. ✅
- `Encumbrance.weight_reduction_saved` → Task 2. ✅
- `EquipmentState.get_container_reductions` → Task 3. ✅
- `InventoryState.weight_reduction` + `get_effective_weight` + effective `get_load_ratio`/`is_over_capacity` → Task 4. ✅
- Coordinator push + vitals pass-through → Task 6. ✅
- `(bags -Nkg)` HUD marker → Task 5. ✅
- No persistence change → confirmed (no `get_summary`/`apply_summary` edits in any task). ✅
- Six smokes extended, markers unchanged, bundle stays 120 → Tasks 1-6 + Task 7 Step 3. ✅
- ADR-0028 + roadmap → Task 7. ✅

**Type consistency:** `weight_reduction_saved(total_weight: float, container_reductions: Array) -> float` is produced in Task 2 and consumed identically in Task 6. `get_container_reductions() -> Array` of `{capacity, reduction}` is produced in Task 3 and consumed in Task 6. `InventoryState.weight_reduction: float` is set in Task 6 and read in Task 4's path + Task 6's vitals pass. `apply_inventory_load(.., weight_saved := 0.0)` is defined in Task 5 and called with the third arg in Task 6. Consistent. ✅

**Placeholder scan:** every code/test step contains complete code and exact run commands with expected markers. No TBD/TODO. ✅
