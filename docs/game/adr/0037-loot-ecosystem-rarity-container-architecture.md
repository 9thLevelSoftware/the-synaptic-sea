# ADR-0037: Loot Ecosystem, Rarity & Unique Container Architecture

Status: Accepted
Date: 2026-06-26

## Context

The repository already had deterministic loot containers, quantitative inventory, and world persistence seams, but the loot layer was still incomplete: rarity had no shared presentation contract, biome/depth/container modifiers were partial, junk items had no material-yield catalog, and unique finds lacked a durable once-per-world registry. Task 04 requires a complete loot package without turning `PlayableGeneratedShip` into a god-object.

## Decision

1. Keep loot selection in pure models: `LootDistribution`, `RarityTier`, `UniqueItemState`, and `JunkYieldResolver` remain `RefCounted`/static data seams with no scene-tree access.
2. Treat unique items as a separate world-uniqueness concern, not just a top rarity tier. Rarity remains the presentation/balance axis; `UniqueItemState` is the persistence/duplication-prevention axis.
3. Store loot tuning in additive JSON catalogs (`loot_tables.json`, `junk_items.json`, `unique_items.json`, `biome_definitions.json`, `rarity_palette.json`) so balance can move without rewriting scene code.
4. Let `LootContainer` own interaction/range behavior while `PlayableGeneratedShip` only supplies context, records searched container ids, surfaces HUD/audio feedback, and snapshots persistence.
5. Persist unique-item and searched-container state through `WorldSnapshot` (`unique_item_summary`, `home_looted_containers`, per-ship `looted_container_ids`) so a save/load round-trip cannot respawn finite loot or re-award a claimed unique.

## Consequences

- Loot remains deterministic and testable in headless smokes because the roll inputs are explicit and pure.
- Designers can add or rebalance junk yields, unique items, and biome/container modifiers in data files.
- Inventory/UI color treatment stays centralized in `RarityTier` + `rarity_palette.json`, avoiding ad-hoc hardcoded swatches across widgets.
- `PlayableGeneratedShip` grows only by orchestration seams (`_build_loot_context`, `_postprocess_loot_grants`, save/load hooks), not by embedding the actual roll logic.

## Rejected alternatives

- Persist the exact contents of every unopened container. Rejected: the deterministic seed contract already defines unopened loot, while opened-state persistence is the real player-facing commitment.
- Encode unique items as just a `legendary`/`unique` rarity with no registry. Rejected: rarity alone cannot stop duplicate cross-save claims.
- Put junk-yield data directly inside every consumer (crafting/inventory/UI). Rejected: one resolver and one data catalog keep future crafting integration consistent.
