# Loot Ecosystem — Balance & Tuning Note

Source: `docs/game/build-plans/04-loot-ecosystem-e2e.md`
ADR: `docs/game/adr/0037-loot-ecosystem-rarity-container-architecture.md`

## Safe ranges

### Rarity weighting

| Tier | Weight multiplier | Role |
|---|---:|---|
| common | 1.00 | baseline repair/survival throughput |
| uncommon | 0.72 | regular reward moments |
| rare | 0.45 | meaningful upgrade / high-value salvage |
| epic | 0.22 | standout run-defining pull |
| legendary | 0.10 | top-end presentation tier; may still be non-unique |

These live in `scripts/systems/rarity_tier.gd`. Keep multipliers positive and monotonic (`common >= uncommon >= rare >= epic >= legendary`) so tier ordering remains legible.

### Context bonuses

| Surface | Current rule | Safe range |
|---|---|---|
| depth bonus | `base_roll += 0.04 * depth` | `0.00 .. 0.08` per depth |
| dead_fleet biome bonus | `+0.06` | `0.00 .. 0.15` |
| wrecked condition bonus | `+0.04` | `0.00 .. 0.10` |
| per-entry depth weight scale | data-driven (`depth_weight_scale`) | `0.00 .. 0.20` |

The package intentionally stacks small bonuses instead of one huge spike so deterministic seeds still feel readable rather than chaotic.

### Container identity

| Container kind | Intended feel |
|---|---|
| industrial_crate | bulky cargo, repair parts, junk |
| survivor_locker | compact supplies/tools |
| maintenance_cache | engineering-focused repairs/upgrades |
| hidden_cache | premium/rare surprise pull |

### Junk-yield floor

Every junk item must return at least one material entry and a total material value >= 1. Junk that yields nothing is flavor-only clutter and violates REQ-LE-006.

## Validation evidence

- `RARITY TIER PASS`
- `LOOT DISTRIBUTION PASS`
- `LOOT TABLE BIOME PASS`
- `UNIQUE ITEM STATE PASS`
- `JUNK ITEMS PASS`
- `CONTAINER VARIETY PASS`
- `MAIN PLAYABLE LOOT ECOSYSTEM PASS`
