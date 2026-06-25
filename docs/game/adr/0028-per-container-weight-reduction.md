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
