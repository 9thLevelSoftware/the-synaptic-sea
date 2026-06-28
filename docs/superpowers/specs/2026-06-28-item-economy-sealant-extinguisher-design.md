# Item Economy: hull_sealant + fire_extinguisher — Design

Date: 2026-06-28
Status: Approved (brainstorm complete; ready for implementation plan)
Related: M7-A (`BreachSealPoint`), M7-B / ADR-0041 (`FireSuppressionPoint`, `ExtinguisherState`),
`docs/game/system_completion_audit.md` (M7 hull row: `hull_sealant` "not obtainable" gap;
M7-B deferred follow-up: `fire_extinguisher` acquisition).

## Problem

Two player loops are wired but **unreachable in real play** because the items their
interaction nodes require do not exist anywhere in the data:

- `scripts/tools/breach_seal_point.gd` requires `hull_sealant` (`required_item`, consumed 1
  per seal). Only a generic `sealant` part exists; `hull_sealant` is undefined — no item def,
  no loot entry, no recipe.
- `scripts/tools/fire_suppression_point.gd` requires `fire_extinguisher` (`required_tool`).
  Undefined everywhere.

Today both loops only pass their smokes because the smokes inject the items via
`inventory_state.add_item(...)`. A real player can never seal a breach or manually
extinguish a fire. This spec closes that gap with an **uncommon-loot + mid-tier-recipe**
economy (no starting handout), so crafting is the reliable path and loot is a bonus find.

## Product decisions (locked during brainstorm)

- **Scope: economy only.** Derelict-side fire (removing the M7-B `away_from_start` guards) is
  a **separate follow-up spec** — it carries an independent fairness/balance design and
  depends on this economy existing first. Not in this spec.
- **Acquisition: uncommon loot AND a mid-tier craftable recipe** for both items. Crafting is
  the dependable route; loot is opportunistic.
- **No starting handout** — neither item is seeded into starting inventory.

## Items (`data/items/item_definitions.json`)

| id | category | weight | max_stack | rarity | role |
| --- | --- | --- | --- | --- | --- |
| `hull_sealant` | `part` | 1.0 | 10 | `uncommon` | **Consumable** — 1 spent per breach seal. The breach-grade refinement of the common `sealant`. |
| `fire_extinguisher` | `tool` | 3.0 | 1 | `uncommon` | **Reusable tool** — acquired once; charge tracked by `ExtinguisherState`, refilled at the existing recharge port. |

The two behave differently and that difference is intentional: `hull_sealant` is spent each
use (needs a steady supply), `fire_extinguisher` is a one-time acquisition (then recharge).

## Loot placement (`data/items/loot_tables.json`, schema `loot-tables-2`)

Add weighted entries at `rarity: "uncommon"`, `weight: 2`:

- `hull_sealant` → `salvage_cargo` (already holds `sealant`/`plating` — hull-repair theme),
  `qty_min: 1, qty_max: 2`; and `repair_parts_common`, `qty 1`.
- `fire_extinguisher` → `generic_locker` (holds tools/safety gear: welder, plasma_cutter),
  `qty 1`; and `salvage_engineering`, `qty 1`.

No biome/condition weighting required (kept simple; can tune later).

## Recipes (`data/recipes/recipe_definitions.json`, mid-tier)

```jsonc
{
  "recipe_id": "craft_hull_sealant",
  "display_name": "Mix Hull Sealant",
  "category": "repair",
  "ingredients": { "sealant": 2, "adhesive_paste": 1 },
  "produces": { "item_id": "hull_sealant", "quantity": 1 },
  "craft_time_seconds": 12.0,
  "required_skill_level": 2,
  "station_kind": "workbench",
  "power_cost": 2.0,
  "batch_size": 1
}
```
```jsonc
{
  "recipe_id": "craft_fire_extinguisher",
  "display_name": "Assemble Fire Extinguisher",
  "category": "fabrication",
  "ingredients": { "scrap_metal": 2, "power_cell": 1, "reactive_gel": 1 },
  "produces": { "item_id": "fire_extinguisher", "quantity": 1 },
  "craft_time_seconds": 20.0,
  "required_skill_level": 3,
  "station_kind": "fabricator",
  "power_cost": 3.0,
  "batch_size": 1
}
```

All ingredient ids are already in the data: `sealant` (item + loot), `adhesive_paste`
(`data/materials/material_definitions.json`, already an ingredient of `weld_plating`),
`scrap_metal`/`power_cell`/`reactive_gel` (items used by existing recipes). The implementer
confirms each ingredient is obtainable; if `adhesive_paste` proves unobtainable as an
inventory item, substitute `scrap_metal: 1` in `craft_hull_sealant` (it is identically
craftable from loot then).

## Consumer reconciliation

No code change to the interaction nodes — `breach_seal_point` and `fire_suppression_point`
already default to `hull_sealant` / `fire_extinguisher`; defining the items simply makes those
defaults satisfiable. Confirm the starting-inventory seed (grep the coordinator's run-setup
inventory population) contains neither item.

## Testing

1. **`scripts/validation/item_economy_smoke.gd`** (data validation, pure):
   - `hull_sealant` and `fire_extinguisher` are defined in `item_definitions.json` with the
     stated category/rarity;
   - each appears in ≥1 loot table entry;
   - each has exactly one recipe producing it, at the stated `required_skill_level`
     (2 and 3) and `station_kind` (workbench, fabricator);
   - neither id is in the starting-inventory seed.
   - Marker e.g. `ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true no_starting_seed=true`.
2. **`scripts/validation/main_playable_item_economy_smoke.gd`** (live reachability — the point):
   - Craft `hull_sealant` through the **real** craft path (begin craft at a workbench with
     ingredients in inventory + skill ≥ 2 → `_on_craft_completed`), then seal a pre-damaged
     breach through the **real** interact dispatcher — **no `add_item("hull_sealant")`**.
   - Craft `fire_extinguisher` through the real craft path, then extinguish a fire through the
     real dispatcher — **no `add_item("fire_extinguisher")`**.
   - Marker e.g. `MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true`.
3. Register both in `docs/game/06_validation_plan.md`; bump the commands count. Existing
   breach/fire smokes (which pre-seed via `add_item`) keep passing — no regression.

## Docs to update on completion

- `docs/game/system_completion_audit.md` — M7 hull row: drop the "`hull_sealant` not
  obtainable" caveat; note the fire/breach player loops are now reachable. Move the
  `fire_extinguisher` acquisition follow-up to RESOLVED.
- Note in the audit that **derelict-side fire** remains the open M7 follow-up (this economy
  unblocks it).

## Implementation phasing (for the plan)

1. **Item definitions** — add both items + data smoke assertion for the defs.
2. **Loot entries** — add to the four tables + extend the data smoke.
3. **Recipes** — add both recipes + extend the data smoke (skill/station assertions).
4. **Live reachability smoke** — craft→seal and craft→extinguish through real paths.
5. **Docs** — audit re-grade.

## Non-goals (v1)

- Derelict-side fire enablement (separate spec).
- Biome/condition loot weighting for these items.
- New station kinds or a broader crafting-economy rebalance.
- Any change to `ExtinguisherState` charge/recharge tuning.
