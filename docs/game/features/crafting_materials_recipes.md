# Feature: Crafting, Materials, Recipes & Stations

Source plan: `docs/game/build-plans/03-crafting-materials-recipes-e2e.md`
ADR: `docs/game/adr/0038-crafting-materials-stations-architecture.md`
Requirement range: REQ-CS-001..015

## Concept

A full production economy for the Synaptic Sea: salvage yields materials, recipes consume them through station-gated queues, output quality depends on inputs + skill + station level + power, emergency field crafting covers a small survival subset, and deconstruction turns found gear back into usable stock.

## Player experience

The player scavenges derelicts for scrap, circuits, fluids, and biomatter; returns to the home-ship workshop/fabricator/medbay/kitchen/synthesizer to turn those parts into tools, repairs, medicine, and survival supplies; and reads outcome quality immediately through the resulting item quality tier. When power drops or the station is underleveled, throughput and quality suffer. In the field, a reduced emergency recipe set keeps the run alive without replacing the shipboard economy.

## Core behavior

- `MaterialState` loads the material catalog, tracks per-material quality, and persists quality summaries.
- `CraftingState` loads 50+ recipes from `data/recipes/recipe_definitions.json`, validates ingredients, consumes inventory, resolves quality tiers, and snapshots active mid-craft state.
- `StationState` owns station kind, level, power state, queue state, pause/resume, and completion progression.
- `FieldCraftingState` exposes only `station_kind == field_crafting` recipes and resolves quality without powered-station bonuses.
- `DeconstructionResolver` maps deconstruction recipes back into material yields.
- Quality is a deterministic function of ingredient quality, skill level, station level, and power availability.
- Save/load carries `crafting_summary` + `material_summary` through `RunSnapshot`, allowing mid-craft resume without ingredient duplication.

## Runtime seams

- Pure models: `scripts/systems/material_state.gd`, `crafting_state.gd`, `station_state.gd`, `field_crafting_state.gd`, `deconstruction_resolver.gd`, `quality_tier_resolver.gd`
- Data: `data/materials/material_definitions.json`, `data/recipes/recipe_definitions.json`
- Validation: `scripts/validation/material_state_smoke.gd`, `crafting_state_smoke.gd`, `station_state_smoke.gd`, `recipe_resource_smoke.gd`, `quality_tier_smoke.gd`, `field_crafting_state_smoke.gd`, `main_playable_slice_crafting_smoke.gd`
- Persistence: `scripts/systems/run_snapshot.gd`, `scripts/validation/save_load_service_smoke.gd`

## Non-goals

- No vendor/trade loop.
- No discovered-vs-known recipe codex progression in this package.
- No final art dependency; placeholder icon/audio seams are acceptable if the runtime seam is real.
- No broad inventory schema rewrite beyond additive crafting/material snapshot fields.

## Acceptance criteria

Mapped 1:1 to REQ-CS-001..015 in `docs/game/05_requirements.md`.

## Verification

- `scripts/validation/material_state_smoke.gd` — `MATERIAL STATE PASS`
- `scripts/validation/crafting_state_smoke.gd` — `CRAFTING STATE PASS`
- `scripts/validation/station_state_smoke.gd` — `STATION STATE PASS`
- `scripts/validation/recipe_resource_smoke.gd` — `RECIPE RESOURCE PASS`
- `scripts/validation/quality_tier_smoke.gd` — `QUALITY TIER PASS`
- `scripts/validation/field_crafting_state_smoke.gd` — `FIELD CRAFTING STATE PASS`
- `scripts/validation/main_playable_slice_crafting_smoke.gd` — `MAIN PLAYABLE CRAFTING PASS`
- `scripts/validation/save_load_service_smoke.gd` — `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27`
