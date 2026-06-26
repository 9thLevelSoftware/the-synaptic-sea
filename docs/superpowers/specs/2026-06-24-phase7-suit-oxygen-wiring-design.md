# Phase 7 Sub-Project B — Live Suit→Oxygen Wiring (Design Spec)

Date: 2026-06-24
Status: Approved (brainstorm)

## Goal

Make worn equipment actually modify live oxygen drain. Today the `hardsuit` declares an
`oxygen_drain` effect (0.75) and `EquipmentState.get_oxygen_drain_multiplier()` computes the
product of worn `oxygen_drain` effects, but that value never reaches `OxygenState`. Wearing the
suit has **zero** effect on breach drain in real play. This slice wires the suit multiplier
end-to-end so equipping/removing the suit changes O2 consumption, multiplicatively stacking with
the portable oxygen pump.

## Context (what already exists — verified)

- **`OxygenState`** (`scripts/systems/oxygen_state.gd`): breach drain runs only when
  `breach_open and not breach_sealed and player_in_breach_zone`. The per-tick drain rate is
  `drain_rate * _compute_drain_multiplier()`. `_compute_drain_multiplier()` returns 1.0 when the
  breach is sealed/closed; otherwise it reads `_inventory_summary["drain_multiplier"]`.
  `apply_inventory_summary(summary)` is the seam the coordinator calls each frame before `tick`.
- **`EquipmentState`** (`scripts/systems/equipment_state.gd`):
  `get_oxygen_drain_multiplier() -> float` already returns the product of all worn items'
  `oxygen_drain` effect values (default 1.0). Pure model; round-trips via `get_summary`/
  `apply_summary`; persists through `WorldSnapshot.player_equipment`.
- **Data**: `data/items/equipment_definitions.json` → `hardsuit` has
  `effects: [{ "type": "oxygen_drain", "value": 0.75 }]`. `data/tools/tool_definitions.json` →
  `portable_oxygen_pump` drives the inventory side (0.5).
- **Coordinator** (`scripts/procgen/playable_generated_ship.gd`): `_refresh_oxygen_state(force_initial,
  delta_seconds)` (~line 3146) calls `oxygen_state.apply_inventory_summary(inventory_state.get_summary())`
  before `tick`. **The equipment multiplier is never applied here — this is the entire gap.**

## Decisions

1. **Combination point: a separate model seam on `OxygenState`** (chosen over coordinator-side
   multiplication or folding equipment into `InventoryState`). Keeps the project's strict
   model/node split: the combination rule lives in a pure, unit-testable model rather than in the
   ~5,000-line coordinator, and the oxygen summary self-documents both contributions. The
   `_inventory_summary["drain_multiplier"]` keeps meaning exactly what `InventoryState` reported.
2. **Multiplicative stacking**: effective breach multiplier = `inventory_mult * equipment_mult`
   (e.g. pump 0.5 × suit 0.75 = 0.375). Consistent with how `EquipmentState` already multiplies
   across worn items. Still hard-gated to 1.0 when the breach is sealed/closed (drain is
   suppressed there anyway; forcing 1.0 avoids masking model state from summary consumers — same
   rule the inventory multiplier already follows).
3. **No new persistence**: the equipment multiplier is recomputed live each frame from
   `equipment_state` (which already persists via `player_equipment`). `apply_summary` does **not**
   restore it — symmetric with the existing inventory-summary handling.
4. **Authored suit value (0.75) is treated as given.** Re-tuning the number is sub-project D
   (balance); this slice only wires the existing value.
5. **HUD presentation deferred to sub-project C** (the dedicated HUD slice). The suit's effect
   stays observable via `OxygenState.get_summary()` (`equipment_drain_multiplier` + the combined
   `drain_multiplier`). No HUD/status-line changes here.

## Architecture & Data Flow

Per frame, inside `_refresh_oxygen_state`, **before** `oxygen_state.tick(...)`:

```
inventory_state.get_summary()            ──► oxygen_state.apply_inventory_summary(...)   (unchanged)
equipment_state.get_oxygen_drain_multiplier() ──► oxygen_state.apply_equipment_summary(
                                                      {"drain_multiplier": <equip_mult>})  (NEW)
oxygen_state.tick(delta, player_in_zone)
  └─ _compute_drain_multiplier() = (sealed/closed ? 1.0 : inv_mult * equip_mult)
       └─ effective_drain_rate = drain_rate * that
```

No scene-tree access added to either model. The coordinator remains the only place that holds
both `inventory_state` and `equipment_state` and bridges them into `oxygen_state`.

## Components / Files

### Modify `scripts/systems/oxygen_state.gd`
- Add `var _equipment_summary: Dictionary = {}`.
- Add `func apply_equipment_summary(summary: Dictionary) -> void` (mirrors
  `apply_inventory_summary`: stores a deep copy).
- Rewrite `_compute_drain_multiplier()` to return `1.0` when sealed/closed, else
  `_summary_drain_mult(_inventory_summary) * _summary_drain_mult(_equipment_summary)`, where a
  small private helper `_summary_drain_mult(d: Dictionary) -> float` reads `d["drain_multiplier"]`
  (validates it is int/float, else 1.0). This removes the inline type-guard duplication.
- `configure(...)` resets `_equipment_summary = {}` alongside the existing `_inventory_summary = {}`.
- `get_summary()` adds `"equipment_drain_multiplier": _summary_drain_mult(_equipment_summary)`.
  The existing `"drain_multiplier"` key continues to expose the **combined effective** value
  (`_compute_drain_multiplier()`), which is what consumers already treat it as.
- `apply_summary(...)`: unchanged behavior; add a one-line comment that the equipment multiplier,
  like the inventory one, is recomputed live and intentionally not restored from the snapshot.

### Modify `scripts/procgen/playable_generated_ship.gd`
- In `_refresh_oxygen_state`, immediately after the existing
  `oxygen_state.apply_inventory_summary(inventory_state.get_summary())`, add:
  ```gdscript
  if equipment_state != null:
      oxygen_state.apply_equipment_summary(
          {"drain_multiplier": equipment_state.get_oxygen_drain_multiplier()})
  ```
  Guarded by `equipment_state != null` (same defensive style as the surrounding code). Applies on
  both the `force_initial` and per-tick paths since it precedes the branch.

### New `scripts/validation/oxygen_equipment_drain_smoke.gd` (pure model)
Drives `EquipmentState` + `OxygenState` directly (no scene tree):
- `EquipmentState.create()`, equip `hardsuit` → `get_oxygen_drain_multiplier() == 0.75`; empty → 1.0.
- `OxygenState` configured with a breach zone (`breach_open=true`, not sealed):
  - suit only (`apply_equipment_summary({"drain_multiplier":0.75})`, inventory neutral) → after a
    `tick` with `player_in_breach_zone=true`, `effective_drain_rate == drain_rate * 0.75`.
  - suit + pump (`apply_inventory_summary` 0.5) → `effective_drain_rate == drain_rate * 0.375`;
    `get_summary()["drain_multiplier"] == 0.375`, `["equipment_drain_multiplier"] == 0.75`.
  - breach sealed → `_compute_drain_multiplier()` via summary `drain_multiplier == 1.0`.
- Marker: `OXYGEN EQUIPMENT DRAIN SMOKE PASS suit=0.75 combined=0.375`.

### New `scripts/validation/main_playable_slice_suit_oxygen_smoke.gd` (main scene)
Instantiates the playable ship headless (mirroring `main_playable_slice_hazard_smoke.gd`):
- Ensure breach open; `teleport_player_to_breach_zone_for_validation()` so the player is in-zone.
- Baseline: no suit → run `_refresh_oxygen_state(false, delta)` →
  `oxygen_state.get_summary()["drain_multiplier"] == 1.0`.
- Equip the hardsuit through the coordinator's equipment path (`equipment_state.equip("hardsuit")`),
  then `_refresh_oxygen_state(false, delta)` → summary `drain_multiplier == 0.75` and measured
  oxygen drop over the tick equals the reduced rate.
- Add the pump to inventory → refresh → summary `drain_multiplier == 0.375`.
- Marker: `SUIT OXYGEN SLICE SMOKE PASS suit_mult=0.75 combined_mult=0.375`.

### Docs
- `docs/game/adr/0024-suit-oxygen-wiring.md` — record the seam + multiplicative rule.
- `docs/game/06_validation_plan.md` — register both smokes with their markers; bundle 115 → 117.
- `docs/game/09_system_roadmap.md` — note suit→oxygen wiring done under System 6/Phase 7.

## Testing & Validation

- Both new smokes print their PASS marker (the contract) and run clean (no unexpected
  `ERROR:`/`WARNING:` beyond the allowlisted baseline noise).
- Full regression bundle green at **commands=117 clean_output=true** (stash `project.godot`
  drift before the run, pop after; never commit it).
- Gate-1 automated playtest still `GO`.

## Out of Scope (explicit)

- Re-tuning the 0.75 suit value or any balance numbers (sub-project D).
- HUD/status-line surfacing of the suit contribution (sub-project C).
- Suit *air-supply depletion* (a suit having its own finite O2 that drains) — a larger future
  system, not modeled here; the suit is a drain **multiplier** only.
- Unifying the two effect type names (`oxygen_drain` on equipment vs `oxygen_drain_multiplier` on
  tools) — they are read by different models; no consumer needs them unified. Noted, not changed.
```
