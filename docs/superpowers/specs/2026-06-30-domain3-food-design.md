# Domain 3: Close the Food Loop — Design

**Date:** 2026-06-30
**Loop:** `food` (roadmap Domain 3, current: 🟡 partial)
**Depends on:** Domain 1 (away-branch survival pattern). Independent of Domain 2 (combat).
**Branch:** `feat/domain3-food` (off `docs/completion-roadmap`)

## Problem

The food **consumption** half is live: spoilage ages food in the home loop, eating
restores vitals, crafted/looted food registers for spoilage, and save/load round-trips
all of it. The **production** half is dead, and the roadmap (`food` loop) requires it
closed:

- `hydroponics_state` and `water_recycler_state` are complete pure models — each splits a
  **start** method (consumes inputs) from a **collect** method (returns produce) and a
  `tick` that advances and flips state — but **nothing calls start or collect**. They have
  no world nodes and no runtime callers.
- The per-frame production tick (`playable_generated_ship.gd` lines 4904–4911) plus
  `spoilage_state.tick` live **only in the home `_process` branch**. The away early-return
  (line 4805) means **food does not spoil and production does not advance on a derelict**.
- `synthesizer_state` is flagged "dead," but this is a misdiagnosis: the synthesizer
  **function** is already live via the crafting `"synthesizer"` station kind
  (`CraftingState` recipe `synthesize_nutrient_paste → synthesized_paste`). The standalone
  `synthesizer_state` model (a thin `cooking_state` wrapper) is an **orphan duplicate** with
  no callers.
- `sustenance_state` is a read-only HUD/save roll-up of the three station summaries; one of
  the three (synthesizer) is about to be retired, so it must be re-sourced.

## Decisions (settled in brainstorming)

1. **Production model:** **player-initiated + manual harvest.** The player interacts with a
   station to start a cycle (consuming inputs) and interacts again, once it is ready, to
   harvest the produce into inventory. No auto-deposit. (Consistent with the project's
   Project-Zomboid/Barotrauma direction.)
2. **Away branch:** **spoilage AND production both continue while boarded.** Production that
   finishes away sits in its READY state until the player returns home to harvest it. This
   deliberately diverges from crafting (powered crafting stations pause away); the rationale
   — growth/recycling are time-based biological/chemical processes that do not require the
   player aboard — is documented at the call site.
3. **`sustenance_state`:** **kept as a live HUD status roll-up.** The HUD is its real
   consumer; it is already wired into HUD (`get_status_lines`) and save/load. Re-sourced to
   drop the retired synthesizer.
4. **`synthesizer_state`:** **retired as redundant.** The crafting `"synthesizer"` station is
   the canonical synthesizer. Remove the orphan model + its save field with a one-time
   migration; record in the inventory that the synthesizer loop closes via `CraftingState`.

## Scope

In scope: build **hydroponics** and **water_recycler** as player-operated production
stations; retire `synthesizer_state`; make spoilage + production tick on the away branch;
re-source `sustenance_state`; add the `contaminated_water` input item and wire the closed
water→food chain; full validation + inventory updates.

Out of scope: any new vitals axis, new cooking content beyond what already exists, a
sustenance-driven gameplay mechanic (e.g. larder morale), and persistence of in-progress
production beyond the existing per-model save summaries.

---

## Architecture

### Component 1: `ProductionStation` (new node)

**File:** `scripts/tools/production_station.gd` — `extends Area3D`, `class_name ProductionStation`.

Mirrors `crafting_station.gd`'s range-gate + marker + `try_interact()` contract, but for a
**stateful, persistent** model (unlike `CraftingStation`, which is single-active and
stateless per node). One node binds to one production model, identified by `station_kind`
(`"hydroponics"` or `"water_recycler"`).

**Configure (dependency injection):**

```
configure(
    station_kind: String,            # "hydroponics" | "water_recycler"
    model,                            # HydroponicsState | WaterRecyclerState
    inventory_state,                  # InventoryState (input source + produce sink)
    power_available: Callable,        # () -> float, available power on the "sustenance" band
    player_skill: Callable,           # () -> int, skill level (hydroponics gates on it)
    config: Dictionary,               # hydroponics: {"crops": [...]} from hydroponics_crops.json
    world_position: Vector3,
    radius := 1.8
) -> void
```

**`try_interact(player_body) -> bool`** — range-gated exactly like `CraftingStation`
(`global_position.distance_to(player) <= radius`, requires both in tree). Dispatches on the
bound model's state:

- **IDLE** → attempt **start**:
  - *Hydroponics:* auto-pick the first crop in `config["crops"]` (catalog order) the player
    can afford — `skill >= required_skill_level`, inventory has `purified_water >= water_cost`,
    `power_available() >= power_cost`. On success: remove `water_cost` `purified_water` from
    inventory, call `model.plant(crop_config, skill, water, power)`, emit
    `production_started(station_kind, crop_id)`. On failure: emit
    `production_blocked(station_kind, reason)` (`"insufficient_skill"` / `"insufficient_water"`
    / `"insufficient_power"` / `"no_affordable_crop"`).
  - *Water recycler:* require inventory `contaminated_water >= 1` and
    `power_available() >= power_cost`. On success: remove the available `contaminated_water`
    (up to a per-cycle cap), call `model.load_input("contaminated_water", qty, power)`, emit
    `production_started(station_kind, "contaminated_water")`. Else emit
    `production_blocked(...)` (`"insufficient_power"` / `"no_input"`).
- **RUNNING** (`PLANTED` / `RECYCLING`) → no-op; emit `production_blocked(station_kind, "in_progress")`
  (feedback only — the coordinator ticks the model, not this node).
- **READY** (`HARVESTABLE` / `output_ready > 0`) → **harvest/collect**:
  - Call `model.harvest()` (hydroponics) or `model.collect_output()` (recycler); deposit
    `item_id × quantity` into inventory via `add_item`; surface overflow as a
    `PRODUCTION OVERFLOW` log line (never a WARNING — the bundle fails on unexpected
    WARNING). Emit `production_harvested(station_kind, item_id, qty)`.

The node performs the model calls itself (it holds the model + inventory refs), mirroring
how `CraftingStation` calls `begin_craft`. It emits signals only; it never advances the
model and never touches spoilage/HUD. **Unit-testable** with a real `HydroponicsState` /
`WaterRecyclerState`, a fake `InventoryState`, and stub callables.

### Component 2: Coordinator wiring (`playable_generated_ship.gd`)

- **`_build_production_stations()`** — parallel to `_build_crafting_stations()`. Builds one
  `"hydroponics"` and one `"water_recycler"` `ProductionStation`, parented to
  `home_ship.scene_root`, positioned via the existing `_home_local_station_positions()` (or
  the same fallback spread). Stored in a new `production_stations: Array`. Called from the
  same three sites `_build_crafting_stations()` is (boot, rebuild, restore). Connects each
  station's signals to handlers.
- **Signal handlers:**
  - `_on_production_started(kind, input_id)` → `_refresh_inventory_hud()`,
    `_recompute_player_encumbrance()`, `print("PRODUCTION STARTED station=%s input=%s")`.
  - `_on_production_harvested(kind, item_id, qty)` → `add_item` already done by the node;
    `_register_food_for_spoilage(item_id)`, refresh HUD + encumbrance,
    `print("PRODUCTION HARVESTED station=%s item=%s qty=%d")`.
  - `_on_production_blocked(kind, reason)` → `print("PRODUCTION BLOCKED station=%s reason=%s")`.
- **Interaction sweep:** add `production_stations` to the unified `try_interact` sweep
  (alongside the `crafting_stations` loop at ~line 4428) so the existing interact input
  reaches them.
- **Validation seam:** `produce_at_station_for_validation(station_kind, harvest: bool)` —
  mirrors `craft_at_station_for_validation`: teleport the player onto the station, then call
  `try_interact`. (`harvest=false` to start, `harvest=true` to collect once ready.)

### Component 3: Away-branch tick (the regression-class fix)

Extract the food/spoilage/production tick block into a shared helper
**`_tick_food_runtime(delta)`**:

```
func _tick_food_runtime(delta: float) -> void:
    if spoilage_state != null:
        spoilage_state.tick(delta)
    if hydroponics_state != null and hydroponics_state.state == HydroponicsStateScript.State.PLANTED:
        hydroponics_state.tick(delta)
    if water_recycler_state != null and water_recycler_state.state == WaterRecyclerStateScript.State.RECYCLING:
        water_recycler_state.tick(delta)
```

Call it from **both** `_process` branches:
- Home branch: replaces the inline block at 4904–4911.
- Away branch: add a call (with a comment documenting the deliberate divergence from
  crafting, which pauses away). This closes the away early-return gap for food, matching the
  fire / sanity / audio fixes (Codex PRs #43–44).

`sustenance_state` continues to tick where it does today (inside
`_recompute_expanded_ship_systems`, home branch) — its roll-up is a HUD convenience and does
not need to update away; the underlying station models (which it reads) do advance away, so
the roll-up self-corrects on return. (No away-branch sustenance tick required.)

### Component 4: Retire `synthesizer_state`

- Remove the `synthesizer_state` field, `SynthesizerStateScript` preload, instantiation
  (line ~1173), the home-branch tick (line ~4908–4909), and the save read/write of
  `snapshot.synthesizer_summary` (lines ~5984–5985, ~6290–6291).
- Delete `scripts/systems/synthesizer_state.gd` and its smoke if present, OR keep the file
  unreferenced — **delete** it to avoid a dead orphan (the whole point of the decision).
- **Save handling (no version bump — revised after tracing the save code):** remove the
  `synthesizer_summary` field from `RunSnapshot` (the `var` declaration, the `SUMMARY_FIELDS`
  array, `to_dict`, and `from_dict`). `RunSnapshot.from_dict` reads every field with
  `.get(key, {})` and rejects neither unknown nor missing keys, so this is backward-compatible
  **without** a schema-version bump or migration step: old saves keep an ignored
  `synthesizer_summary` key; new saves omit it; both load clean. A version bump was rejected as
  unnecessary and more invasive (it would touch `CURRENT_SLICE_VERSION` plus 4 smokes, one with
  a hardcoded `"gate2-current-run-3"` string), and the migration table (ADR-0032) exists for
  load-breaking changes — the prior v1→v2/v2→v3 steps all *added required fields*, the opposite
  of removing an ignored optional key. Update `save_load_service_smoke.gd`, which asserts
  `get_summary_count() == 27` and prints `summaries=27` (lines 147, 258), to `26`.
- **`sustenance_state.tick`** re-sourced: it currently reads `synthesizer_summary`. Change it
  to roll up `hydroponics` (`harvest_ready` from HARVESTABLE) + `water_recycler`
  (`purified_water_ready` from `output_ready`) only. `meals_ready` is read from the live
  crafting kitchen/synthesizer activity via a single `crafting_state` query (whether an
  active cooking/synthesis craft exists) rather than the retired model; if that coupling is
  undesirable, `meals_ready` falls to 0 (HUD shows only harvest + water). The coordinator
  call site at ~line 1394 drops the `synthesizer_summary` context key.

### Component 5: Data — `contaminated_water` + the closed chain

- **New item `contaminated_water`** in `data/items/item_definitions.json` (category
  `"supply"`, modest weight, stackable, lootable rarity). It is a recycler **input only** —
  never eaten, drunk, or spoiled — so it gets **no** `food_definitions` entry (unlike
  `purified_water`, which is drinkable and therefore appears in both files). If any
  consumable/spoilage loader asserts every `"supply"` item has a food entry, prefer fixing
  that assumption over inventing a fake nutrition profile for waste water.
- **Acquisition:** seed `contaminated_water` into a derelict (and/or home) loot table so the
  player can actually obtain it. This makes `purified_water` **renewable** via the recycler
  instead of finite-loot-only.
- **The closed chain:**
  `contaminated_water` (loot) → recycler → `purified_water` → hydroponics (consumes
  `purified_water`) → `hydroponic_greens` → kitchen cook (greens + water) → `cooked_meal` →
  eat → vitals. `purified_water` is also directly drinkable (thirst restore).

---

## Data Flow

```
loot contaminated_water ─▶ [WaterRecyclerState]  (player loads, ticks, harvests)
                                   │ purified_water
                                   ▼
inventory purified_water ─▶ [HydroponicsState]   (player plants w/ water+power+skill,
                                   │ hydroponic_greens     ticks to HARVESTABLE, harvests)
                                   ▼
inventory greens + water ─▶ [CraftingState kitchen]  (existing live cook loop)
                                   │ cooked_meal
                                   ▼
                            eat ─▶ vitals (hunger/thirst/sanity restore, spoilage-scaled)

[SpoilageState] ages all food every frame on BOTH _process branches.
[SustenanceState] rolls up hydroponics + recycler readiness → HUD (home tick).
```

## Error Handling

- All start/harvest failures emit `production_blocked(kind, reason)` and `print` a
  `PRODUCTION BLOCKED` line — never a WARNING (bundle fails on unexpected WARNING).
- Harvest overflow (inventory stack full) deposits what fits and logs
  `PRODUCTION OVERFLOW item=… lost=…`, mirroring `CRAFT OVERFLOW`.
- Range gate rejects interacts when the player is out of radius or either node is outside the
  tree (mirrors `CraftingStation._is_player_in_direct_range`).
- Save migration tolerates snapshots both with and without `synthesizer_summary`.

## Testing (validation smokes)

All smokes `extends SceneTree`, print a single `… PASS …` marker, and trust the marker (not
exit code). Register every marker in `docs/game/06_validation_plan.md` and bump the bundle
count.

1. **`production_station_smoke.gd`** (model-level): construct a `ProductionStation` with a
   real `HydroponicsState` + fake `InventoryState` + stub power/skill callables.
   - Pre-seed inventory with `purified_water`. Interact (IDLE→start) → assert water consumed,
     model `PLANTED`, `production_started` fired.
   - Tick the model to `HARVESTABLE`. Interact (READY→harvest) → assert `hydroponic_greens`
     deposited, model back to `IDLE`, `production_harvested` fired.
   - Repeat for `WaterRecyclerState`: seed `contaminated_water`, start → `RECYCLING`, tick to
     ready, collect → `purified_water` deposited.
   - Marker: `PRODUCTION STATION PASS hydro_harvest=true recycler_collect=true blocked_in_progress=true`.

2. **`main_playable_food_production_smoke.gd`** (scene-level): boot `main.tscn`, repair power,
   use `produce_at_station_for_validation` to start hydroponics + recycler on the home ship;
   advance via `_process`; harvest both; assert inventory gains `hydroponic_greens` and
   `purified_water` and that the produce registered for spoilage.
   - **Away variant in the same smoke:** set `away_from_start = true`, record spoilage values,
     advance `_process` for N frames, assert spoilage advanced **and** an in-progress crop's
     growth advanced on the derelict branch.
   - Marker: `MAIN PLAYABLE FOOD PRODUCTION PASS harvested=true recycled=true away_ticks=<n> spoiled_away=true`.

3. **`food_synthesizer_retirement_smoke.gd`**: assert `playable.synthesizer_state` is gone
   (null/absent) and that the crafting `"synthesizer"` station still produces
   `synthesized_paste` via `craft_at_station_for_validation`; build a `RunSnapshot` dict that
   still carries a legacy `synthesizer_summary` key, run it through `RunSnapshot.from_dict`, and
   assert it loads clean (extra key ignored, no error, snapshot valid). Marker:
   `FOOD SYNTHESIZER RETIREMENT PASS orphan_removed=true crafting_synth_ok=true legacy_load_ok=true`.

Existing food smokes (`spoilage_eat_scaling_smoke`, `main_playable_food_consumption_smoke`,
`food_save_load_smoke`, `food_state_smoke`, `spoilage_state_smoke`, `sustenance_state_smoke`)
must continue to pass; update any that reference `synthesizer_state` or the moved tick block.

## Inventory deltas (`docs/game/inventory/system_inventory.json`)

- `food` loop: `closes → "closed"`; update break-points to reflect the live production.
- `hydroponics_state`: `output.live → true`; record `ProductionStation` as the caller.
- `water_recycler_state`: `output.live → true`; record `ProductionStation` caller +
  `contaminated_water` input.
- `synthesizer_state`: mark **retired/removed**; note the synthesizer loop closes via
  `CraftingState`. Adjust the system count accordingly.
- `sustenance_state`: record the HUD as its live consumer; note re-sourcing.
- New entry: `production_station` (node) if the inventory tracks nodes of this kind.
- Regenerate MD + HTML via `python tools/build_system_inventory.py`; keep `--check`,
  `--coverage`, and `tools/test_build_system_inventory.py` green. Verify no cross-entry
  semantic contradiction (gaps/desc claiming production dead while the loop is closed) —
  this class of drift was missed by `--check` in Domains 1 and 2 and caught only by review.

## Definition of CLOSED (roadmap)

1. ✅ Hydroponics + water_recycler have **live player callers** (`ProductionStation`) that
   consume inputs and **produce** food/water items into inventory.
2. ✅ `sustenance_state`'s counts feed a real consumer (HUD), re-sourced off the retired model.
3. ✅ Spoilage (and production) age on the **away branch**.
4. ✅ The synthesizer duplication is resolved (orphan retired; crafting synthesizer canonical).

## Risks

- **Away-branch divergence from crafting** could read as an inconsistency; mitigated by an
  explicit call-site comment + the design decision recorded here.
- **Save migration** must handle both old (with `synthesizer_summary`) and new snapshots; the
  retirement smoke covers the old-save path.
- **Power-band gating** (`sustenance`) at boot may allocate 0 to a damaged ship; the
  validation seam forces power like `craft_at_station_for_validation` does, and real play
  requires the player to restore power first (intended).
