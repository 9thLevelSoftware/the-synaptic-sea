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

## Verification
- FOOD STATE PASS
- SPOILAGE STATE PASS
- COOKING STATE PASS
- HYDROPONICS STATE PASS
- MAIN PLAYABLE COOKING PASS
- FOOD SAVE LOAD PASS
