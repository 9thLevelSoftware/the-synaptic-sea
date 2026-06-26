# Food, Cooking, Spoilage & Sustenance Tuning

## Source
- ADR-0034: `docs/game/adr/0034-food-cooking-spoilage-architecture.md`
- Feature spec: `docs/game/features/food_cooking_spoilage.md`
- Build plan: `docs/game/build-plans/02-food-cooking-spoilage-e2e.md`

## Spoilage thresholds

| Stage | Threshold | Visual | Stat multiplier range |
|-------|-----------|--------|----------------------|
| FRESH | < 50% of spoilage_seconds | Green badge | 1.0 (full restore) |
| STALE | 50% – 99% of spoilage_seconds | Yellow badge | 0.5 – 0.9 (per-item config) |
| ROTTEN | ≥ 100% of spoilage_seconds | Red badge + skull | 0.1 – 0.5 (per-item config) |

## Food item stats (current)

| Item | Category | Weight | Stack | Spoilage (s) | Hunger | Thirst | Sanity | Stale mult | Rotten mult | Sickness risk |
|------|----------|--------|-------|--------------|--------|--------|--------|-----------|-------------|---------------|
| ration_pack | supply | 0.5 | 20 | 3600 | 15 | 5 | 2 | 0.6 | 0.2 | 0.25 |
| cooked_meal | food | 0.8 | 10 | 1800 | 25 | 8 | 5 | 0.7 | 0.3 | 0.15 |
| nutrient_paste | food | 0.3 | 20 | 7200 | 20 | 10 | 0 | 0.8 | 0.4 | 0.10 |
| hydroponic_greens | food | 0.4 | 15 | 2400 | 12 | 3 | 1 | 0.6 | 0.2 | 0.20 |
| purified_water | supply | 0.2 | 20 | 86400 | 0 | 15 | 1 | 0.9 | 0.5 | 0.05 |
| scavenged_protein | food | 0.6 | 10 | 1200 | 18 | 0 | 0 | 0.5 | 0.1 | 0.35 |
| alien_flora | food | 0.5 | 10 | 600 | 10 | 2 | -2 | 0.5 | 0.1 | 0.40 |

## Cooking recipes (current)

| Recipe | Ingredients | Produces | Power | Time | Skill | Station |
|--------|-------------|----------|-------|------|-------|---------|
| cooked_meal_basic | 1× ration_pack + 1× purified_water | 1× cooked_meal | 5.0 | 10.0 s | 0 | galley |
| nutrient_paste | 2× hydroponic_greens + 1× purified_water | 2× nutrient_paste | 8.0 | 15.0 s | 1 | synthesizer |

## Hydroponics crop stats (current)

| Crop | Produce | Quantity | Growth (s) | Water | Power | Skill |
|------|---------|----------|------------|-------|-------|-------|
| hydroponic_greens | hydroponic_greens | 3 | 120.0 s | 2.0 | 3.0 | 0 |

## Water recycler stats (current)

| Input | Output | Conversion rate | Power per unit |
|-------|--------|----------------|----------------|
| contaminated_water | purified_water | 1:1 | 2.0 |

## Balance targets

- A full run through the golden slice (~8–12 minutes of active play) should see ration packs transition from FRESH to STALE but not ROTTEN if consumed promptly.
- The synthesizer is intentionally slower and skill-gated so that cooking raw ingredients remains attractive early-game.
- Hydroponics produces 3 units per 120s cycle; this is tuned to supplement, not replace, scavenged food.
- Alien flora has negative sanity and high sickness risk to reinforce the horror tone — it is a desperation food, not a staple.

## Tuning knobs

All numbers above live in:
- `data/items/item_definitions.json` — per-item spoilage and stat fields
- `scripts/systems/cooking_state.gd` — recipe config via `configure()`
- `scripts/systems/hydroponics_state.gd` — crop config via `plant()`
- `scripts/systems/water_recycler_state.gd` — conversion rate via `configure()`

No hard-coded constants outside these configuration paths.
