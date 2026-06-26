# Loot Ecosystem / Rarity / Containers / Unique Finds — Contract Review

Source plan: `docs/game/build-plans/04-loot-ecosystem-e2e.md`
Package range: REQ-LE-001..009
Author: synapse_seaworker (Task 04)

## Existing seams extended, not replaced

| Area | Existing seam | Disposition |
|---|---|---|
| Deterministic loot rolling | `scripts/systems/loot_roller.gd`, `data/items/loot_tables.json` | Extend with contextual weighting rather than replacing the original seed contract. |
| Container interaction | `scripts/tools/loot_container.gd` | Keep the Area3D interaction contract; add richer context and feedback instead of a new pickup type. |
| Inventory & UI | `scripts/systems/item_defs.gd`, `scripts/ui/inventory_row.gd`, `scripts/ui/inventory_panel.gd` | Reuse merged item-definition lookups and row styling so rarity reads in the existing inventory surface. |
| World persistence | `scripts/systems/world_snapshot.gd`, `scripts/procgen/playable_generated_ship.gd`, `scripts/systems/ship_instance.gd` | Persist searched-container ids and unique-item summary additively; do not create a second save path. |
| Audio/caption feedback | `scripts/audio/audio_manager.gd`, `scripts/audio/audio_event_seam.gd` | Reuse the existing SFX + caption routing so loot feedback is audible and accessible without bespoke audio code. |

## Greenfield files created by the package

Runtime / model files:
- `scripts/systems/rarity_tier.gd`
- `scripts/systems/loot_distribution.gd`
- `scripts/systems/unique_item_state.gd`
- `scripts/systems/junk_yield_resolver.gd`

Data files:
- `data/items/junk_items.json`
- `data/items/unique_items.json`
- `data/items/biome_definitions.json`
- `data/ui/rarity_palette.json`

Validation files:
- `scripts/validation/rarity_tier_smoke.gd`
- `scripts/validation/loot_distribution_smoke.gd`
- `scripts/validation/loot_table_biome_smoke.gd`
- `scripts/validation/unique_item_state_smoke.gd`
- `scripts/validation/junk_items_smoke.gd`
- `scripts/validation/container_variety_smoke.gd`
- `scripts/validation/main_playable_slice_loot_ecosystem_smoke.gd`

Docs:
- `docs/game/features/loot_ecosystem.md`
- `docs/game/adr/0037-loot-ecosystem-rarity-container-architecture.md`
- `docs/game/balance/loot_ecosystem_tuning.md`

## Conflicts checked

- `docs/game/adr/0014-loot-player-inventory.md`: compatible; this package deepens the same deterministic-container model instead of changing the fundamental approach.
- `docs/game/adr/0007-save-load-service-scope.md`: respected; loot persistence stays in current-run/world snapshot state only.
- No contradictory ADR found that forbids additive rarity/junk/unique catalogs.
