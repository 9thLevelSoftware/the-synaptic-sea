# ADR-0036: Consumable Effect Pipeline Architecture

Status: Accepted
Date: 2026-06-25

## Context
Task 05 needs medicine, stimulants, ammo packs, and utility consumables to work through a single runtime pipeline instead of bespoke one-off item handlers. The project already has inventory, vitals, status, and save/load systems, but lacked a shared coordinator for effect definitions, timed stimulant withdrawal, consumable hotbar slots, and additive persistence.

## Decision
1. Introduce `EffectDispatcher` as the authoritative pure-model executor for effect ids defined in `data/items/effect_definitions.json`.
2. Keep `ConsumableState` as the inventory-facing entry point that decides category behavior (`medicine`, `stimulant`, `ammo`, `utility`, food-like supply use) and hotbar slot state.
3. Retain category-specific state in small pure models (`MedicineState`, `StimulantState`, `AddictionState`, `AmmoState`, `UtilityItemResolver`) instead of inflating `InventoryState`.
4. Let `PlayableGeneratedShip` remain the scene coordinator that wires inventory-panel actions, numeric hotbar keys, HUD labels, per-frame stimulant/addiction ticking, and RunSnapshot save/load restoration.
5. Persist the package additively via new `RunSnapshot` summaries (`consumable`, `medicine`, `stimulant`, `addiction`, `ammo`, `utility`) so reloads restore runtime context without rewriting older ship/inventory summaries.

## Consequences
- Consumable behavior is data-driven and expandable without new scene-specific code for each item.
- Timed stimulant withdrawal survives save/load and headless validation because the durable state is in pure models.
- The RunSnapshot summary count increases and must be locked by validation whenever new additive summary fields land.
- Hotbar contents follow inventory availability; consumed or missing items can be re-assigned safely after reload.

## Rejected alternatives
- Put all consumable state directly inside `InventoryState`. Rejected because it would mix cargo accounting with transient gameplay effects/timers.
- Add one giant `consumables_summary` blob for every category. Rejected because separate summaries keep migrations and targeted smokes clearer.
