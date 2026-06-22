# Loot & Player Inventory (sub-project #3) — design

Date: 2026-06-21
Status: Accepted
Related: ADR-0011 (ShipInstance & travel), ADR-0012 (world persistence),
ADR-0013 (derelict gameplay parity), docs/game/00_vision.md (open-world survival North Star)

## Purpose

Make boarding a derelict *pay off*. Per the North Star, a derelict is a Project-Zomboid
style building: a place to **search containers and scavenge parts, tools, and supplies**
into a carried inventory. #3 delivers the acquire → carry (weight-gated) → persist loop.
It is the prerequisite for repair (#4), which spends the parts #3 lets you accumulate.

This closes the reward gap ADR-0013 deliberately left open: completing a salvage objective
currently yields only a `cleared` flag and no tangible loot.

## Existing foundation (build on / around)

- **`InventoryState`** (`scripts/systems/inventory_state.gd`) exists but is a **tool-set**
  model: `tool_ids: Array[String]`, unique IDs, no quantities, no categories. It is
  player-global, owned by the coordinator (`playable_generated_ship.gd`), never freed across
  travel, and round-trips via `get_summary()`/`apply_summary()`.
- **Three consumers** read its tool surface and MUST keep working unchanged:
  `ToolPickup` (`add_tool`), `OxygenState` (drain multiplier from `portable_oxygen_pump`),
  and the junction-calibrator gate (`has_tool("junction_calibrator")`).
- **`ToolPickup`** (`scripts/tools/tool_pickup.gd`) is the existing acquire-on-interact node
  pattern (`try_interact(player_body)` → `inventory_state.add_tool(id)`). `LootContainer`
  reuses this shape.
- **Salvage objectives** are generated in `gameplay_slice_builder.gd` (`type: "salvage"`,
  non-connective rooms) and spawn `Interactable` nodes in #2 that currently grant nothing.
- **Persistence already wired**: the player bag round-trips through
  `RunSnapshot.inventory_summary`; `ShipInstance.get_summary()` takes per-ship keys the same
  way `"objective"` does.

## Design

### 1. Item model — evolve `InventoryState` in place

Internal storage changes from `tool_ids: Array[String]` to `items: Dictionary`
(`item_id -> quantity: int`). The existing tool surface is preserved as thin shims over the
new store so the three consumers are untouched:

- `add_tool(id)` → `add_item(id, 1)`; `has_tool(id)` → `get_quantity(id) > 0`;
  `remove_tool(id)` → `remove_item(id, 1)`; `tool_ids` → **derived** getter returning the
  ids whose definition category is `tool`; `get_drain_multiplier()` unchanged in behavior
  (0.5 iff a `portable_oxygen_pump` is carried).

New surface:

- `add_item(id: String, qty: int) -> int` — adds up to `qty`, **weight-checked**; returns
  the quantity actually added (0 if it won't fit). Respects `max_stack` from the definition.
- `get_quantity(id) -> int`, `remove_item(id, qty) -> int`.
- `get_total_weight() -> float`, `get_max_weight() -> float`.
- `get_items_by_category(category: String) -> Array` — `[{id, quantity, weight_each}]`.

Categories: `part`, `supply`, `tool`. The two existing tools are `tool`-category items.
Tools have weight but are light, and `max_weight` is generous, so a critical tool (oxygen
pump) always fits — weight pressure comes from bulk `part`/`supply` loot, never from gating
tools. `max_weight` is a constant on the model for this slice (capacity upgrades are future
scope).

### 2. One `LootContainer` mechanism, two spawn contexts

`LootContainer` (`scripts/tools/loot_container.gd`) is an interactable Area3D (same pattern as
`ToolPickup`) holding a loot-table key. Searching it rolls items into the player inventory and
marks it looted; a looted container rejects further searches and reads as empty.

- **Salvage points**: salvage-objective specs gain a `loot_table` field; the salvage
  interactable's completion path also rolls and grants loot. Reuses the existing `completed`
  flag for persistence — no new per-ship state for salvage points.
- **Scattered crates/lockers**: a new spawn pass in `gameplay_slice_builder.gd` emits
  loot-container specs (`{id, kind, room_id, cell, loot_table}`) into the gameplay slice,
  analogous to the salvage-objective pass. The coordinator builds `LootContainer` nodes from
  them under a new `LootContainerRoot: Node3D`, mirroring how `DerelictObjectiveRoot` /
  `derelict_interactables` are built and cleared.

**Derelicts only this slice.** The home ship keeps its existing tool pickups and singleton
loop untouched (the #2 hard constraint: the home loop must not change behavior). "Loot is an
any-ship system" remains the North Star; unifying the home ship onto the same container
mechanism is a later pass, tracked with the home/derelict convergence (ADR-0011 Approach B).

### 3. Data & determinism

- `data/items/item_definitions.json`: `{ id: {display_name, category, weight, max_stack} }`.
  `InventoryState` merges this with the existing `tool_definitions.json` (each tool def is
  treated as category `tool` with a default weight if none is set). Existing tool **effect**
  fields are read by the existing code path and are not disturbed by the merge.
- `data/items/loot_tables.json`: `{ table_key: [ {item_id, qty_min, qty_max, weight} ] }`,
  where `weight` is the relative roll probability. A small starter set keyed by container kind
  / room role (e.g. `salvage_engineering`, `salvage_cargo`, `generic_crate`,
  `generic_locker`).
- **Deterministic roll**: container contents are rolled by a seeded RNG keyed by
  `hash(ship marker_id + container id)`, so the same ship always yields the same loot from the
  same container ("ships persist once accessed"). Because the roll is reproducible,
  persistence records only *that* a container was emptied, never *what* it held.

### 4. Persistence

- **Player bag** → the extended `inventory_summary` (already in `RunSnapshot`, already on the
  save path). The summary gains an `items` map and `total_weight`/`max_weight`; it keeps a
  derived `tool_ids` and `drain_multiplier` for backward compatibility and for `OxygenState`.
  `apply_summary` accepts **both** the new (`items`) and the legacy (`tool_ids`-only) shapes.
  The bag is global: it MUST persist on save-anywhere from aboard a derelict (the #1
  capability), independent of the active ship.
- **Scattered-container looted state** → a new `looted_container_ids: Array[String]` on the
  `ShipInstance` summary, written/read exactly like the `"objective"` key. Salvage points need
  no new state (they reuse `completed`).

### 5. Scope boundary — what #3 does NOT do

- Parts and supplies are **inert accumulation**. The deliverable is acquire → carry → persist.
  **Consumption is out of scope**: repair spending parts is #4; survival consumables
  (e.g. oxygen refills) are #2b. Tools keep their current effects only.
- **No drop / transfer-to-ship-storage UI.** Ship storage does not exist until #4; over-weight
  simply rejects the pickup. There is no partial-pickup or "leave some" UI this slice.
- **No home-ship containers** (see §2).
- **No capacity upgrades** — `max_weight` is a fixed constant this slice.

## Components

| Unit | Type | Responsibility | Depends on |
| --- | --- | --- | --- |
| `InventoryState` (evolved) | `RefCounted` model | quantitied, categorized, weight-capped bag; tool shims; round-trip | item + tool definition JSON |
| `LootTable` roller | pure helper (in `InventoryState` or a small `loot_roller.gd`) | deterministic seeded roll of a table key → item grants | `loot_tables.json` |
| `LootContainer` | `Node3D` scene node | search-on-interact; grant via inventory; mark looted | `InventoryState`, loot roller |
| `gameplay_slice_builder` (pass) | pure builder | emit scattered loot-container specs; add `loot_table` to salvage specs | archetype/room roles |
| `playable_generated_ship` (coordinator) | `Node3D` | build/clear `LootContainerRoot`; wire salvage loot; HUD weight line; per-ship looted persistence | all above |
| `ShipInstance` (extended) | `RefCounted` | carry `looted_container_ids` in its summary | — |

## HUD

Extend `InventoryState.get_status_lines()` (already feeding the HUD) to add per-item lines and
a `weight=<total>/<max>` readout. Existing `tool=...` / `drain_multiplier=...` lines are
preserved so the REQ-007 main-scene smoke is unaffected.

## Portability constraints (from prior sub-projects)

- New `class_name` scripts (e.g. `LootContainer`) are NOT in the committed
  `global_script_class_cache.cfg` and `--headless --script` does not rebuild it. Construct via
  a `load("res://...").new()` static factory and reference cross-script via `preload(...)`
  const — never bare `ClassName.new()` or `: ClassName` annotations in another script.
  `InventoryState` is already in the cache and may keep bare refs.
- The home loop must stay behaviorally identical (singletons, tool pickups, OxygenState drain,
  junction gate, HUD) after travelling out and back.

## Validation (3 new smokes → bundle 67 → 70)

1. **Pure-model** (`item_inventory_smoke.gd`): `add_item` stacking, weight-cap rejection
   (returns partial/0 when full), `get_items_by_category`, full `get_summary`/`apply_summary`
   round-trip, **and** backward-compat applying a legacy `tool_ids`-only summary. Plus: the
   three tool consumers still resolve (`has_tool`, `get_drain_multiplier`, derived `tool_ids`).
   Marker: `ITEM INVENTORY PASS add=true weight_cap=true round_trip=true legacy_compat=true`.
2. **Loot determinism** (`loot_table_smoke.gd`): same `marker_id + container id` → identical
   roll across two rollers; a different key → a different roll; rolled items resolve to known
   definitions. Marker: `LOOT TABLE PASS deterministic=true varies_by_seed=true`.
3. **Main-scene** (`derelict_loot_smoke.gd`): board a derelict → search a `LootContainer` →
   items enter the bag and `get_total_weight()` rises and the container reads looted; leave to
   home → revisit → that container is still looted (no respawn) and the bag is unchanged; disk
   save/load while aboard → bag survives; return home → home loop intact and the oxygen-pump
   tool effect still applies. Marker:
   `DERELICT LOOT PASS searched=true carried=true persists=true home_intact=true`.

Each smoke prints exactly its PASS marker; all three are registered in
`docs/game/06_validation_plan.md` and the regression bundle count is bumped.

## ADR

This decision (general quantitied/weighted inventory; unified `LootContainer`; deterministic
seeded loot; derelicts-only this slice) is recorded as **ADR-0014** during implementation.
