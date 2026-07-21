# Feature: Crafting Recipe Picker

## Status

Validated

## Design pillar alignment

- Pillar: player agency over the home-ship production economy
- Why: stations, materials, skill gates, and kitchens are live; auto-picking the first craftable recipe removes choice when multiple recipes are affordable

## Player fantasy

At a fabricator, kitchen, medbay, workbench, or synthesizer the player browses what the station can make, sees what they can afford, and chooses the craft that matches the run — not whatever sorts first in the catalog.

## Gameplay problem

`CraftingStation.try_interact` previously auto-selected the first craftable recipe (skill- and output-gated). With many recipes per station kind, that made intentional production impossible.

## Core behavior

1. Interacting a non-salvage crafting station (while not already crafting) opens a recipe picker panel for that `station_kind`.
2. The panel lists **all** non-deconstruction recipes for the station, sorted by `recipe_id`, each tagged with status: `ready`, `missing_ingredients`, `insufficient_skill`, or `output_full`.
3. Default cursor is the first **ready** recipe (else index 0).
4. Confirm on a `ready` row starts `CraftingState.begin_craft` for that recipe (ingredients consumed, quality resolved, single-active craft).
5. Confirm on a blocked row leaves the panel open with a reason; no ingredients consumed.
6. Cancel / close restores player control. Salvage stations remain auto-select.
7. KEY_C opens the same picker for `field_crafting` portable recipes (skill-ungated start; skill still affects quality).

## Inputs

- Player interact on a crafting station (home ship)
- `ui_up` / `ui_down` / `ui_accept` / `ui_cancel` while the picker is open
- Data: `data/recipes/recipe_definitions.json` via `CraftingState`
- Skill: fabrication level from `PlayerProgressionState`
- Inventory + material state for affordability / quality (quality only at begin)

## Outputs

- Visible recipe list with status markers
- On confirm success: craft starts; existing `craft_started` / completion deposit path
- On busy / blocked interact: existing `craft_blocked` reasons where applicable

## Rules

- One active craft globally (`CraftingState` single `_active_craft`); busy stations do not open a second picker that clobbers.
- Medbay field surgery (Stream F) still runs before the picker when the patient is critical.
- Deconstruction recipes never appear on normal stations (salvage bench owns that path).
- Pure model listing is headless-testable without UI.
- Validation seams may start a craft by explicit `recipe_id` without opening the panel.

## Non-goals

- Salvage / deconstruction item picker
- Recipe codex / discovery unlocks
- Multi-queue parallel crafts
- Final art / themed chrome (text list is sufficient)
- Recipe JSON schema changes

## Technical design

| Layer | File |
| --- | --- |
| Pure listing | `scripts/systems/crafting_state.gd` → `list_recipe_entries` |
| Station seam | `scripts/tools/crafting_station.gd` → `recipe_picker_requested`, `try_craft_recipe` |
| UI | `scripts/ui/recipe_picker_panel.gd` |
| Coordinator | `scripts/procgen/playable_generated_ship.gd` (HUD, input, freeze, validation) |
| Requirement | `REQ-CS-016` in `docs/game/05_requirements.md` |
| Architecture | ADR-0038 (no new ADR; presentation over existing begin_craft) |

## Acceptance criteria

- Given a powered fabricator and ≥2 craftable recipes, when the player interacts, then a recipe list opens and no craft starts until confirm.
- Given the list is open with cursor on a non-first ready recipe, when the player confirms, then that recipe becomes the active craft and its ingredients are consumed.
- Given a recipe lacking ingredients or skill, when confirmed, then craft does not start and the panel stays open with a clear reason.
- Given salvage station interact, then behavior is unchanged (no picker).
- Given an active craft, when interacting any craft station, then blocked as busy.
- Headless smokes: pure listing, panel unit, main-scene picker path all PASS; station craft reachability still PASSes.

## Validation

```text
scripts/validation/crafting_recipe_list_smoke.gd
  → CRAFTING RECIPE LIST PASS ready=<n> blocked=<n> station=fabricator

scripts/validation/recipe_picker_panel_smoke.gd
  → RECIPE PICKER PANEL PASS rows=<n> move=true confirm=true closed=true

scripts/validation/main_playable_slice_recipe_picker_smoke.gd
  → MAIN PLAYABLE RECIPE PICKER PASS station=fabricator recipe=<id> crafted=true chosen_not_first=true

scripts/validation/main_playable_slice_station_craft_smoke.gd
  → MAIN PLAYABLE STATION CRAFT PASS crafted=true salvaged=true field=true reachable=true
```

## Risks

| Risk | Mitigation |
| --- | --- |
| Existing station craft smoke breaks when interact stops auto-crafting | Validation seam uses first-ready `try_craft_recipe` |
| Player freezes if close paths miss signal | Always emit `panel_closed` (scanner precedent) |
| Confirm races with mid-craft | Re-check `is_crafting` + craftability at confirm |

## ADRs

- ADR-0038: Crafting, Materials & Station Architecture
