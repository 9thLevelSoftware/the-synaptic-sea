# Task 05 contract review — consumables, medicine, stimulants, ammo & utility

Date: 2026-06-25
Task: `t_67389b76`

## Existing seams extended
- `scripts/systems/item_defs.gd` remains the single merged item-catalog loader; Task 05 extends it with medicine, stimulant, ammo, utility, and trade definition files instead of inventing a parallel registry.
- `scripts/systems/inventory_state.gd` remains the authoritative quantity / weight model; `ConsumableState` consumes stacks through its existing add/remove API instead of duplicating inventory ownership.
- `scripts/procgen/playable_generated_ship.gd` stays the scene coordinator. Consumable gameplay is additive: inventory-panel use, hotbar assignment/use, stimulant/addiction ticking, HUD refresh, and RunSnapshot save/load restore all hang off existing coordinator seams.
- `scripts/systems/run_snapshot.gd` keeps additive persistence summaries (`consumable`, `medicine`, `stimulant`, `addiction`, `ammo`, `utility`) instead of replacing older snapshot fields.

## Implemented artifacts
- Pure models:
  - `scripts/systems/effect_dispatcher.gd`
  - `scripts/systems/consumable_state.gd`
  - `scripts/systems/medicine_state.gd`
  - `scripts/systems/stimulant_state.gd`
  - `scripts/systems/addiction_state.gd`
  - `scripts/systems/ammo_state.gd`
  - `scripts/systems/utility_item_resolver.gd`
- Data:
  - `data/items/effect_definitions.json`
  - `data/items/medicine_definitions.json`
  - `data/items/stimulant_definitions.json`
  - `data/items/ammo_definitions.json`
  - `data/items/utility_item_definitions.json`
  - `data/items/trade_item_definitions.json`
  - `data/items/addiction_tuning.json`
- Integration:
  - `scripts/procgen/playable_generated_ship.gd`
  - `scripts/ui/hotbar_panel.gd`
- Validation:
  - `scripts/validation/effect_dispatcher_smoke.gd`
  - `scripts/validation/consumable_state_smoke.gd`
  - `scripts/validation/medicine_state_smoke.gd`
  - `scripts/validation/stimulant_state_smoke.gd`
  - `scripts/validation/addiction_state_smoke.gd`
  - `scripts/validation/consumable_save_load_smoke.gd`
  - `scripts/validation/main_playable_consumables_smoke.gd`

## Missing / deferred surfaces
- Trade goods are catalog-only in this package. Vendor / barter runtime remains future economy work.
- Repair consumables are currently represented by utility-side field repair foam; direct RepairPoint/system-repair consumable spend remains future work.
- Final art/audio juice is still placeholder-only by package design.

## Chosen extension seams
- Shared effect execution is centralized in `EffectDispatcher`; medicine, stimulants, ammo packs, utility items, and food/drink-style supply use all route through that one executor.
- Timed stimulant expiry delegates durable dependence/tolerance to `AddictionState`, while visible debuffs remain in `StatusEffectsState`; this preserves save/load parity without forcing scene nodes to own timers.
- Hotbar persistence lives in `ConsumableState` so slot summaries survive save/load even when inventory/UI are rebuilt.

## ADR conflict review
- No direct contradiction found with existing ADRs. The package follows ADR-0036 and preserves the ADR-0007 additive save/load boundary.
