# Crafting / Materials / Recipes Tuning Note

Source: `docs/game/build-plans/03-crafting-materials-recipes-e2e.md`
ADR: `docs/game/adr/0038-crafting-materials-stations-architecture.md`
Requirement range: REQ-CS-001..015

## Safe ranges

### Quality resolution

`QualityTierResolver.compute_score(material_quality, skill_level, station_level, powered)` currently uses:

- material quality weight: `0.40`
- skill bonus cap: `0.35` via `skill_level * 0.08`
- station bonus cap: `0.25` via `station_level * 0.06`
- powered bonus: `+0.05`

Keep the final score clamped to `[0.0, 1.0]`. Preserve monotonicity: improving any one input must never reduce the final score.

### Tier thresholds

| Tier | Threshold | Multiplier |
|---|---:|---:|
| poor | 0.00 | 0.70 |
| standard | 0.35 | 1.00 |
| good | 0.55 | 1.25 |
| excellent | 0.75 | 1.60 |
| masterwork | 0.90 | 2.00 |

### Recipe catalog targets

- Material entries: 30-40 is the safe readable range for Gate 2.
- Recipes: 50-70 keeps each station meaningfully populated without drowning the player.
- Field-craft recipes: keep to 4-8 emergency actions so shipboard stations remain the primary economy.
- Batch outputs should be rare and legible; use them for low-value staples (`nutrient_paste`, adhesive, sealant), not high-tier tools.

### Station role targets

| Station | Intended role |
|---|---|
| fabricator | parts, tools, ship modules |
| workbench | repair stock, sealants, improvised gear |
| medbay | medicine, stimulant, nanite patching |
| kitchen | edible transformations |
| synthesizer | bulk substrate conversion |
| field_crafting | emergency-only survival subset |

## Validation evidence

- `MATERIAL STATE PASS`
- `CRAFTING STATE PASS`
- `STATION STATE PASS`
- `RECIPE RESOURCE PASS`
- `QUALITY TIER PASS`
- `FIELD CRAFTING STATE PASS`
- `MAIN PLAYABLE CRAFTING PASS`
- `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27`
