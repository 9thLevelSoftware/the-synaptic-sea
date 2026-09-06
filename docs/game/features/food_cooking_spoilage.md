# Food, Cooking, Spoilage & Sustenance Inputs

## Overview
Complete food economy for The Synaptic Sea. Players must manage hunger, thirst, and sanity through rations, scavenged food, alien flora, cooked meals, and hydroponics. Food spoils over time, affecting restoration values and sickness risk.

## Source requirements
- REQ-FC-001..010
- ADR-0034

## Systems
- FoodState / SpoilageState — freshness and spoilage
- CookingState / SynthesizerState — station-based food production
- HydroponicsState — timed crop growth
- WaterRecyclerState — water purification

## Data
- `data/items/food_definitions.json`
- `data/recipes/cooking_recipes.json`
- `data/crops/hydroponics_crops.json`

## Runtime integration
- PlayableGeneratedShip owns all models
- Per-frame tick advances spoilage, cooking, hydroponics
- Food consumption affects VitalsState (hunger/thirst/sanity)
- Save/load persists all food state

## Non-goals
- Final art assets (placeholders only)
- Multiplayer sync
- Hub/meta persistence (current-run only per ADR-0007)

## Acceptance criteria

Mapped to existing requirement rows: `REQ-FC-001`, `REQ-FC-004`, `REQ-FC-008`.

- **Gameplay:** Food and spoilage state advance freshness over time and spoiled food changes restoration values and sickness risk.
- **Gameplay:** Cooking and synthesizer stations produce authored meals from the cooking recipe catalog.
- **Gameplay:** Hydroponics advances timed crop growth and the water recycler performs authored purification.
- **Gameplay:** Consuming food applies its hunger, thirst, and sanity effects to `VitalsState`.
- **Gameplay:** The playable ship owns and ticks spoilage, cooking, and hydroponics models through the live runtime path.
- **Gameplay:** Save/load round-trips all current-run food, spoilage, cooking, hydroponics, and water state.
- **Constraint:** Placeholder art is sufficient; multiplayer and cross-run hub/meta persistence remain outside this package.

## Verification
- FOOD STATE PASS
- SPOILAGE STATE PASS
- COOKING STATE PASS
- HYDROPONICS STATE PASS
- MAIN PLAYABLE COOKING PASS
- FOOD SAVE LOAD PASS
