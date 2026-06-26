# Feature: Loot Ecosystem, Rarity, Containers & Unique Finds

Source plan: `docs/game/build-plans/04-loot-ecosystem-e2e.md`
ADR: `docs/game/adr/0037-loot-ecosystem-rarity-container-architecture.md`
Requirement range: REQ-LE-001..009

## Concept

Finite, deterministic-by-seed scavenging translated into the Synaptic Sea: derelicts carry room-role loot, container subtypes, depth/condition/biome scaling, junk that doubles as future crafting material, and world-unique finds that unlock codex knowledge exactly once per world state.

## Player experience

A player boards a derelict, searches lockers/crates/caches, reads rarity from color and text immediately, hears a pickup confirmation, and sees a concise loot line in the HUD. Common salvage keeps repair and survival loops fed; rarer rolls surface better tools/parts; unique finds feel singular because once claimed they do not reappear for the same world state.

## Core behavior

- Loot tables are deterministic for identical `(table_key, seed_source, biome, depth, condition, container_kind)` inputs.
- Container subtype matters: `industrial_crate`, `survivor_locker`, `maintenance_cache`, and `hidden_cache` bias different pools.
- Biome, depth, and hull condition push the same table toward different outcomes.
- Rarity is surfaced through the shared `RarityTier` palette and inventory-row border styling.
- Junk items expose material yields through `JunkYieldResolver` and merged `ItemDefs` lookups.
- Unique items are tracked separately from rarity: they are world-unique drops backed by `UniqueItemState`, plus codex unlock persistence through meta progression / world snapshot state.
- Loot feedback has three redundant surfaces: HUD line (`Loot: ...`), rarity-color border, and audio-caption event.

## Runtime seams

- Pure models: `scripts/systems/rarity_tier.gd`, `loot_distribution.gd`, `unique_item_state.gd`, `junk_yield_resolver.gd`
- Data: `data/items/loot_tables.json`, `item_definitions.json`, `junk_items.json`, `unique_items.json`, `biome_definitions.json`, `data/ui/rarity_palette.json`
- Scene/runtime integration: `scripts/tools/loot_container.gd`, `scripts/procgen/playable_generated_ship.gd`, `scripts/ui/inventory_row.gd`
- Persistence: `scripts/systems/world_snapshot.gd` stores `unique_item_summary` and home-container loot state

## Non-goals

- No crafting stations / recipe execution in this package.
- No economy/vendor loop.
- No final art dependency; placeholder icons/colors are acceptable if the runtime seam is real.
- No broad item-stat refactor outside the loot-specific fields.

## Acceptance criteria

Mapped 1:1 to REQ-LE-001..009 in `docs/game/05_requirements.md`.

## Verification

- `scripts/validation/rarity_tier_smoke.gd` — `RARITY TIER PASS`
- `scripts/validation/loot_distribution_smoke.gd` — `LOOT DISTRIBUTION PASS`
- `scripts/validation/loot_table_biome_smoke.gd` — `LOOT TABLE BIOME PASS`
- `scripts/validation/unique_item_state_smoke.gd` — `UNIQUE ITEM STATE PASS`
- `scripts/validation/junk_items_smoke.gd` — `JUNK ITEMS PASS`
- `scripts/validation/container_variety_smoke.gd` — `CONTAINER VARIETY PASS`
- `scripts/validation/main_playable_slice_loot_ecosystem_smoke.gd` — `MAIN PLAYABLE LOOT ECOSYSTEM PASS`

All seven are registered in `docs/game/06_validation_plan.md` and the focused package command uses `ROOT=/Users/christopherwilloughby/the-synaptic-sea`.
