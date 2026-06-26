# Consumables, Medicine, Stimulants, Ammo & Utility Items

## Source
- Package plan: `docs/game/build-plans/05-consumables-medicine-stimulants-e2e.md`
- Requirement range: REQ-CN-001..010
- ADR-0036

## Concept
A unified consumable pipeline for medicine, stimulants, ammo packs, repair-foam utility items, and trade-good catalogs that runs through the player inventory, shared effect dispatch, hotbar/UI presentation, and save/load persistence.

## Scope
- `EffectDispatcher` resolves item effect ids into vitals/sanity/radiation/status/ammo mutations.
- `ConsumableState` owns use actions, hotbar slots, and total-use tracking.
- `MedicineState`, `StimulantState`, `AddictionState`, `AmmoState`, and `UtilityItemResolver` retain category-specific runtime state.
- `PlayableGeneratedShip` wires inventory-panel use, 1-3 hotbar keys, per-frame stimulant/addiction ticking, HUD hotbar labels, and RunSnapshot persistence.
- Data-driven item definitions under `data/items/*.json` define medicine, stimulant, ammo, utility, trade, and shared effect catalogs.
- Trade goods ship as real item definitions now, while vendor / barter runtime remains explicitly deferred.

## Out of scope
- Final VFX/audio juice for item use.
- Weapon firing / combat ammo spend beyond reserve tracking.
- Meta-progression or hub persistence for consumables.
- Trade/vendor economy behavior beyond item definitions existing in the catalog.

## Acceptance criteria
- Using medicine changes vitals/status state through `EffectDispatcher` and consumes inventory.
- Using stimulants applies timed buffs, records tolerance/dependence, and can trigger withdrawal on expiry.
- Ammo packs add reserve ammo through the same dispatcher pipeline.
- Utility items set persistent utility flags/notes and can be triggered from inventory.
- The playable scene exposes at least three consumable hotbar slots and saves/restores their summaries.

## Verification
- `scripts/validation/effect_dispatcher_smoke.gd` -> `EFFECT DISPATCHER PASS`
- `scripts/validation/consumable_state_smoke.gd` -> `CONSUMABLE STATE PASS`
- `scripts/validation/medicine_state_smoke.gd` -> `MEDICINE STATE PASS`
- `scripts/validation/stimulant_state_smoke.gd` -> `STIMULANT STATE PASS`
- `scripts/validation/addiction_state_smoke.gd` -> `ADDICTION STATE PASS`
- `scripts/validation/consumable_save_load_smoke.gd` -> `CONSUMABLE SAVE LOAD PASS`
- `scripts/validation/main_playable_consumables_smoke.gd` -> `MAIN PLAYABLE CONSUMABLES PASS`
- `scripts/validation/save_load_service_smoke.gd` -> `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27`
