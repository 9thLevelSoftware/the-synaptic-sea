# Feature: WorkAction Framework (Strip / Weld / Patch)

## Status

In progress — pure WorkActionState/catalog/resolver landed (PKG-B2.2a/b);
repair/seal/suppress wrappers ride WorkActionChannel (PKG-B2.5). Scene driver
+ salvage picker full wiring still open for B2.2b scene package.

## Design pillar alignment

- Pillar: Salvage / Craft / Repair (pre-polish plan Part 2.2, 2.5)
- Why: One data-defined verb surface for every physical interaction with modules and components

## Player fantasy

Cut a hole into a sealed room, unbolt machinery silently, weld plates under threat pressure, overload the salvage cart.

## Gameplay problem

Repair, breach seal, and fire suppression are parallel one-off mechanics; free-form dismantling does not exist.

## Core behavior

Data-defined WorkAction:

```
{verb: cut|unbolt|weld|patch|pry|splice, target: module|component|repair_point|breach,
 tool_class, min_skill, duration, materials_consumed, materials_yielded, noise, xp_event}
```

- Pure `WorkActionState`: progress, interruption, tool/skill/material gates (model on `repair_with_inventory`).
- Interact chain: target resolution → hold-to-work → yield / noise / XP.
- Noise feeds threat detection; XP feeds `TrainingEventBus`; yields feed inventory/encumbrance/cart.
- Repair unification re-expresses repair_point / breach_seal / suppression as WorkActions (authored repair_point remains objective wrapper).

## Inputs

- ModuleIntegrityMap / component entities
- Player tool + skill + inventory
- Damage events (interrupt)

## Outputs

- Module/component state changes; inventory yields; noise; XP; audio event IDs

## Rules

1. Every physical verb is catalog data, not a hard-coded coordinator path.
2. Cutting is noisy and partial yield; unbolting is slower/silent/full yield.
3. Interrupt on damage; stamina drains via existing vitals context.
4. Quality of yields inherits skill/tool/source when MaterialState quality API is ready.

## Non-goals

- Ship-modification install UI (ship_modification feature)
- Final tool art/SFX (placeholder audio event IDs required)
- Station batch crafting (crafting depth feature)

## Technical design

- `WorkActionCatalog` data + `WorkActionState` pure model
- Scene driver + salvage-target-picker (PR #76) as universal "what can I do" surface
- ADR-0051 for targets; requirements REQ-WA-001..REQ-WA-004

## Acceptance criteria

- Given a sealed room and a welding_lance-class tool, when the player completes cut on a wall module, then the module is destroyed/breached, partial scrap is yielded, and noise is emitted.
- Given damage mid-work, when health is hit, then progress interrupts without double-consuming materials.
- Given three legacy repair paths, when unification lands, then one progress/interrupt/UI path covers patch/weld/seal/suppress.

## Validation

- Pure WorkActionState smoke (gates, progress, interrupt)
- Scene: cut + strip + cart overload + noise wakes threat
- Persistence: in-progress work survives save when D8 lands

## Risks

- Interactable ownership conflicts with repair unification — single owner package for B2.5.
- Threat noise coupling requires perception package for full fantasy teeth.
