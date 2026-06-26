# Per-Container Weight Reduction — Design (System 6, slice D)

Date: 2026-06-25
Status: Approved (brainstorm complete; ready for implementation plan)
System: 6 — Inventory & Equipment (Phase 7 deferred sub-slice D)
Related ADRs: ADR-0021 (equipment & carts), ADR-0023 (inventory widget layer),
ADR-0025/0027 (player-vitals HUD). This slice will get ADR-0028.

## Problem

A worn container today only raises the player's carry **capacity**
(`EquipmentState.get_carry_capacity_bonus()` → `InventoryState.bonus_capacity`).
It does not reduce the **weight** of what it carries. The cart model's own
comment names the gap directly:

> "a cart 'removes' weight from the player whereas a worn bag only raises the cap."

The result: choosing between the EVA Backpack, Field Pack, and Tool Belt is a
flat decision — more capacity is the only axis. There is no Project-Zomboid-style
"pack the heavy things in a good bag to feel lighter" trade-off, so the
equipment/cart/encumbrance system built across the last several slices lacks the
strategic depth it was meant to enable.

## Goal

Worn containers reduce the **effective** weight of the load they carry, so a
better bag measurably lowers the Heavy-Load movement penalty and the displayed
Load%. One isolated, pure-model behavior behind the existing weight interface; no
new UI surface beyond a small marker on the existing vitals Load line.

## The model — capacity-share, best-first

The player inventory is a **flat** `{item_id -> quantity}` dictionary
(`InventoryState`). Items are **not** nested inside containers, and this slice
does not change that. Instead, effective weight is derived by a pure function:

1. Each worn container declares `weight_reduction` ∈ [0, 1] (a new item-def
   field; default `0.0`).
2. Sort the worn containers **best-first** (highest `weight_reduction` first).
3. Walk the containers, letting each "cover" up to its `container_capacity` of
   the remaining total weight. The covered weight is reduced by that container's
   `weight_reduction`. Any weight beyond all worn containers rides on the body at
   full weight.
4. `saved_kg = Σ (covered_weight_i × reduction_i)`;
   `effective_weight = max(0.0, total_weight − saved_kg)`.

This rewards both capacity (a bigger bag covers more weight) and reduction
quality (a better bag reduces more of it), and approximates PZ nesting without
introducing per-item container assignment.

### Worked example

Load 70 kg; worn EVA Backpack (cap 40, 30% off) + Tool Belt (cap 12, 10% off);
base body capacity 50 ⇒ total capacity 102.

```
fill EVA first (best):  40 kg covered × 0.30 = 12.0 saved   (40 × 0.70 = 28.0 effective)
fill belt next:         12 kg covered × 0.10 =  1.2 saved   (12 × 0.90 = 10.8 effective)
on body (unreduced):    18 kg          × 0.00 =  0.0 saved   (18.0 effective)
---------------------------------------------------------------
saved_kg   = 13.2
effective  = 70 − 13.2 = 56.8 kg
load ratio = 56.8 / 102 = 0.56   →  "Load: 56%"  (vs. 69% raw)
```

### Reduction values (balance)

Added to `data/items/equipment_definitions.json`:

| Item          | slot  | container_capacity | weight_reduction |
|---------------|-------|--------------------|------------------|
| EVA Backpack  | back  | 40.0               | **0.30**         |
| Field Pack    | back  | 15.0               | **0.15**         |
| Tool Belt     | waist | 12.0               | **0.10**         |
| Salvage Hardsuit | suit | (none)           | (none → 0.0)     |

Default for any container lacking the field = `0.0`. Values are deliberately
moderate so weight is still felt; easy to retune later.

## Architecture

Each unit is independently testable and keeps the strict model/node separation.

### 1. `scripts/systems/item_defs.gd`
New static accessor, mirroring `container_capacity`:

```gdscript
static func weight_reduction(defs: Dictionary, item_id: String) -> float:
    return clampf(float(get_definition(defs, item_id).get("weight_reduction", 0.0)), 0.0, 1.0)
```

Clamping at the accessor means bad data can never invert the math.

### 2. `scripts/systems/encumbrance.gd`
New pure static — the entire fill algorithm, no state:

```gdscript
## Capacity-share, best-first. container_reductions: Array of
## { "capacity": float, "reduction": float }. Returns saved kg.
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

### 3. `scripts/systems/equipment_state.gd`
New pure data provider (does not import Encumbrance):

```gdscript
## [{capacity, reduction}] for each worn item that is a container (capacity > 0).
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

### 4. `scripts/systems/inventory_state.gd`
Mirror the existing `bonus_capacity` push pattern:

- New field `var weight_reduction: float = 0.0` (saved kg, pushed by the
  coordinator — kept current by `_recompute_player_encumbrance` on every change,
  exactly like `bonus_capacity`).
- `get_total_weight()` stays **raw** (used by the save summary and status lines).
- New `get_effective_weight() -> float`:
  ```gdscript
  func get_effective_weight() -> float:
      return maxf(0.0, get_total_weight() - weight_reduction)
  ```
- `get_load_ratio()` switches to effective weight:
  ```gdscript
  func get_load_ratio() -> float:
      return get_effective_weight() / max(0.0001, get_capacity())
  ```
- `is_over_capacity()` switches to effective weight for consistency:
  ```gdscript
  func is_over_capacity() -> bool:
      return get_effective_weight() > get_capacity()
  ```

With `weight_reduction` defaulting to 0, effective == raw, so every existing
behavior and smoke assertion is preserved until a reduction is actually pushed.

### 5. Coordinator `scripts/procgen/playable_generated_ship.gd`
In `_recompute_player_encumbrance()` (~L1617), alongside the existing
`bonus_capacity` push:

```gdscript
inventory_state.bonus_capacity = bonus
inventory_state.weight_reduction = 0.0
if equipment_state != null:
    inventory_state.weight_reduction = EncumbranceScript.weight_reduction_saved(
        inventory_state.get_total_weight(), equipment_state.get_container_reductions())
```

The two existing `get_load_ratio()` call sites — move-speed (L1625) and the
vitals push (L3207) — then reflect the reduction with no further change.

## HUD marker

Decision: surface the reduction (not silent).

- `scripts/systems/player_vitals_model.gd`:
  `apply_inventory_load(load_ratio: float, move_multiplier: float, weight_saved: float = 0.0)`
  — the defaulted third param keeps existing callers/smokes valid. Store
  `_weight_saved = maxf(0.0, weight_saved)`.
- `_load_line()` appends `" (bags -Nkg)"` when `round(_weight_saved) >= 1`,
  where `N = int(round(_weight_saved))`. Examples:
  - `Load: 56% (bags -13kg)`
  - `Load: 132% HEAVY (-30% move) (bags -13kg)`
  - reduction 0 → no suffix (unchanged from today).
- Coordinator passes `inventory_state.weight_reduction` at the L3207 push site.

`inventory_panel.gd` reads `get_load_ratio()` for its own encumbrance readout
(L222/L232); it automatically reflects the effective ratio — consistent with the
vitals panel, no edit needed.

## Persistence

None. No save-schema or version change. The reduction is derived entirely from
the already-persisted `EquipmentState` and is recomputed by
`_recompute_player_encumbrance` on load. `InventoryState.get_summary()` keeps
emitting `total_weight` as the **raw** weight (the true mass). Mirrors the
vitals-hud-cleanup "no persistence change" principle.

## Testing

Extend existing smokes; **keep every PASS marker literally unchanged** so the
regression bundle stays at `commands=120` with zero grep edits. These smokes use
the abort style (`_fail` → `push_error(...FAIL...)` → `quit(1)`): a failed
assertion prints no PASS marker.

| Smoke | New coverage | Marker (unchanged) |
|-------|--------------|--------------------|
| `equipment_defs_smoke.gd` | the three `weight_reduction` values + default-0 for a non-container item | `EQUIPMENT DEFS SMOKE PASS slots=3 effects=1` |
| `encumbrance_smoke.gd` | `weight_reduction_saved`: best-first ordering, capacity cap, under/over-weight, empty list → 0 | `EQUIPMENT ENCUMBRANCE SMOKE PASS floor=0.25` |
| `equipment_state_smoke.gd` | `get_container_reductions()` shape/values; suit (no capacity) excluded | `EQUIPMENT STATE SMOKE PASS bonus=... oxy=...` |
| `inventory_state_smoke.gd` | `get_effective_weight`; `get_load_ratio`/`is_over_capacity` use effective weight; existing reduction-0 assertions still hold | `INVENTORY STATE PASS tools=... pump=... drain_multiplier=...` |
| `player_vitals_model_smoke.gd` | `(bags -Nkg)` marker present when `weight_saved>0`, absent at 0 | `PLAYER VITALS MODEL SMOKE PASS suit=-25 heavy=-30 repair=47` |
| `main_playable_slice_vitals_hud_smoke.gd` | equip EVA backpack + load weight ⇒ panel Load% drops and shows the marker | `MAIN PLAYABLE VITALS HUD PASS panel=true breach=true suit=true heavy=true repair=true` |

Each smoke runs headless via the Godot console binary; trust the PASS marker, not
the exit code. After implementation, run the full regression bundle (stash
`project.godot` first, pop after) and confirm
`SYNAPSE_SEA REGRESSION PASS commands=120 clean_output=true`.

## Edge cases & risks

- **Negative weight:** `get_effective_weight()` clamps at 0.0; `saved` can never
  exceed `total_weight` because the fill caps `remaining` at 0.
- **Bad data:** `weight_reduction` is clamped to [0, 1] at the accessor and again
  in the fill, so a malformed value cannot invert or amplify weight.
- **Stale value:** `weight_reduction` (absolute saved kg) depends on
  `total_weight`, so it is recomputed on every inventory/equipment/cart change in
  `_recompute_player_encumbrance` — the same currency guarantee as
  `bonus_capacity`. No call path mutates inventory weight without recompute.
- **Consistency:** both `get_load_ratio()` and `is_over_capacity()` move to
  effective weight together, so the "heavy" indicator and the over-capacity
  signal never disagree. `is_over_capacity()` has no runtime consumers (only
  smokes), so this is low-risk.

## Out of scope

- Strength-skill capacity scaling (slice B) and endurance/health Heavy-Load
  effects (slice C) — both require a physical attribute/condition model that does
  not exist yet.
- Nested per-item container assignment (true PZ container UI).
- Carts — they already remove weight from the player entirely; their model is
  unchanged.
- Item-icon generation, drag-out-to-unequip, gamepad navigation (other System 6
  remainders).

## Definition of done

- `weight_reduction` field on the three containers; accessor clamped [0,1].
- `Encumbrance.weight_reduction_saved` + `EquipmentState.get_container_reductions`
  + `InventoryState.get_effective_weight` and effective-weight `get_load_ratio` /
  `is_over_capacity`.
- Coordinator pushes `weight_reduction` in `_recompute_player_encumbrance`.
- Vitals Load line shows `(bags -Nkg)` when reduction is active.
- All six smokes extended and green; full bundle
  `SYNAPSE_SEA REGRESSION PASS commands=120 clean_output=true`.
- ADR-0028 + roadmap System 6 row updated.
