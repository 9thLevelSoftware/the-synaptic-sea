# Feature: Inventory / Tool Loop

## Status

Approved for Gate 2 implementation

## Requirement cross-reference

- REQ-007 Inventory/tool loop
- Supersedes the Gate 1 non-goal in `features/hazards.md`: "No oxygen tanks, pickups, or inventory items" is lifted for the single tool defined here.
- Preserves REQ-001 (route gates remain real runtime blockers), REQ-002 (restoring systems still opens powered gates), and REQ-006 (oxygen hazard semantics are unchanged).

## Design pillar alignment

- Runtime systems over proof artifacts: the tool is a real pickup, a real inventory entry, and a real modifier to the hazard model.
- Every action has visible consequence: acquiring the tool updates the HUD; carrying it changes the oxygen drain rate in the breach zone.
- Small vertical slices before broad systems: exactly one tool and one effect for Gate 2; no general crafting, shops, or equipment slots.

## Player fantasy

The player finds a portable oxygen pump in the derelict. Carrying it makes the breach corridor survivable for longer, turning a desperate sprint into a calculated risk.

## Gameplay problem

REQ-007 identified that inventory/tools are not yet a real runtime loop. Gate 1 solved route control and hazard pressure as environmental systems the player reacts to; Gate 2 adds the first player-owned resource that changes how those systems behave.

## Core behavior

- One tool exists in the Gate 2 slice: `portable_oxygen_pump`.
- The tool is acquired by interacting with a pickup in a fixed side room (room id `tool_storage_01` in the default layout, with a fallback spawn near the entry room if the layout does not define it).
- Once acquired, the tool stays in the player's inventory for the current ship slice.
- While the tool is carried and the player is inside an unsealed oxygen breach zone, the oxygen drain rate is reduced by 50%.
- The tool does not prevent the zero-oxygen passability block; it only delays it.
- The tool does not affect route gates, extraction unlock, objective sequence, or breach sealing.
- The tool is consumed implicitly by the hazard model while carried; there is no manual "use" input in Gate 2.

## Inputs

- Player interaction event from the tool-pickup interactable.
- Player-in-breach-zone signal from `PlayableGeneratedShip` (same source `oxygen_state` already uses).
- Current inventory state queried by `OxygenState` each tick.

## Outputs

- Inventory summary (`tool_ids`, `active_effects`).
- HUD status line `Tool: Oxygen Pump` when carried.
- Modified oxygen drain rate while the tool is carried and the player is inside an unsealed breach zone.
- Pickup node is hidden/removed after acquisition.

## Rules

- A tool can be acquired at most once per slice run.
- Tool effects apply only while the tool is in the inventory; dropping/reset is out of scope for Gate 2.
- The oxygen pump effect multiplies the current drain rate by `0.5` while inside an unsealed breach zone; it does not change regeneration rate, thresholds, or breach seal logic.
- If multiple tools ever exist, effects stack multiplicatively; Gate 2 only ships one tool.
- The tool pickup is not a route gate key and cannot open powered blockers.

## Non-goals

- No equipment UI, inventory grid, or drag-and-drop.
- No tool durability, charges, or crafting.
- No dropping, trading, or hub-stored tools across runs.
- No tools that alter route gates, extraction, objective sequence, or fire hazards in Gate 2.
- No audio, particle, or animation polish for the pickup.

## Technical design

- New pure model: `scripts/systems/inventory_state.gd` (`InventoryState` extending `RefCounted`).
  - Inputs: `add_tool(tool_id: String)`, `has_tool(tool_id: String) -> bool`, `remove_tool(tool_id: String) -> bool`, `reset()`.
  - Outputs: `get_summary() -> Dictionary`, `get_status_lines() -> PackedStringArray`.
- Tool definition data: `data/tools/tool_definitions.json` (or a `ToolDefinition` Resource under `res://data/tools/`).
  - Gate 2 entry: `{ "portable_oxygen_pump": { "display_name": "Portable Oxygen Pump", "effect": { "type": "oxygen_drain_multiplier", "value": 0.5 } } }`.
- `OxygenState` gains a dependency: `apply_inventory_summary(summary: Dictionary) -> void` is called before each tick so the model can compute the effective drain multiplier.
  - Effective drain = `drain_rate * _compute_drain_multiplier()`.
  - `_compute_drain_multiplier()` returns `0.5` if the inventory summary contains `portable_oxygen_pump` and the breach is unsealed, otherwise `1.0`.
- Scene integration:
  - `scripts/procgen/playable_generated_ship.gd` owns one `InventoryState` instance.
  - A new `ToolPickup` scene/node (`scenes/tools/portable_oxygen_pump_pickup.tscn` or script `scripts/tools/tool_pickup.gd`) is placed in the side room by the loader or by the coordinator using a fixed fallback position.
  - Interacting with the pickup calls `inventory_state.add_tool("portable_oxygen_pump")`, hides the pickup node, and refreshes the HUD.
  - `_refresh_oxygen_state()` passes the inventory summary into `OxygenState` before ticking, matching the existing ship-system summary pattern.
- HUD: `scripts/ui/objective_tracker.gd` appends the active tool status line when `inventory_state.get_status_lines()` is non-empty.
- Direct model smoke: `scripts/validation/inventory_state_smoke.gd`.
- Main-scene smoke: `scripts/validation/main_playable_slice_inventory_smoke.gd` loads the slice, teleports the player to the pickup, acquires it, teleports into the breach zone, and asserts the effective drain rate is halved.

## Data model additions

- `InventoryState.tool_ids: Array[String]` (owned by `PlayableGeneratedShip`).
- `OxygenState.effective_drain_rate: float` (computed per tick; exposed in `get_summary()`).
- `data/tools/tool_definitions.json` Resource or JSON.
- Save/load (REQ-012) serializes `InventoryState.tool_ids` as part of the current-run snapshot.

## Trigger / preconditions / postconditions

- **Trigger:** Player interacts with the portable oxygen pump pickup.
- **Preconditions:**
  - Slice is loaded and `playable_ready` has fired.
  - Player is within interaction range of the pickup.
  - The tool is not already in inventory.
- **Postconditions:**
  - `InventoryState.has_tool("portable_oxygen_pump")` is true.
  - Pickup node is hidden/queued for deletion.
  - HUD shows the active tool.
  - Subsequent oxygen ticks inside an unsealed breach zone use the reduced drain rate.

## Edge cases and failure modes

- **Double pickup:** Interacting again after acquisition is a no-op; the pickup node is already hidden.
- **Load with saved tool:** If REQ-012 load restores a tool id that is no longer defined, `InventoryState` keeps the id but `OxygenState` treats an unknown effect as multiplier `1.0`.
- **No breach zone:** If the loaded slice has no breach zone, the tool has no runtime effect but still appears in inventory and HUD.
- **Breach sealed while carrying tool:** The multiplier reverts to `1.0` because the effect only applies to an unsealed breach.
- **Tool effect stacking:** If a future tool also modifies oxygen drain, multipliers compose; Gate 2 only ships one tool so the composition is trivial.
- **Model tick order:** `apply_inventory_summary` must run before `tick()` in the same frame; otherwise the player can enter the breach for one tick before the pump helps. The coordinator already groups model refresh calls before ticks.

## Acceptance criteria

- Given a fresh slice load, when `inventory_state.get_summary()` is queried, then `tool_ids` is empty.
- Given the player is within range of the portable oxygen pump pickup, when the player interacts, then `has_tool("portable_oxygen_pump")` returns true and the pickup node is no longer visible.
- Given the player carries the pump and stands in an unsealed breach zone, when `oxygen_state.tick(delta, true)` runs, then `effective_drain_rate` equals `drain_rate * 0.5`.
- Given the player carries the pump and stands outside any breach zone, when `oxygen_state.tick(delta, false)` runs, then regeneration rate is unchanged.
- Given the breach is sealed, when the player stands in the (now safe) zone with the pump, then `effective_drain_rate` equals `drain_rate` (the multiplier no longer applies).
- Given the main playable slice loads, when the inventory main-scene smoke runs, then it prints `MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5`.
- Given the model smoke runs in isolation, when it adds the pump and ticks inside a breach, then it prints `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5`.

## Validation

- Direct model smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/inventory_state_smoke.gd
  ```
  Expected marker: `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5`

- Main-scene smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_inventory_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5`

- Regression inclusion: add both smokes to the bundle in `docs/game/06_validation_plan.md` before the feature is marked done.

## Risks

- Risk: the pickup placement is not readable and players miss it. Mitigation: place it on the critical path side room and add a Label3D marker `TOOL PICKUP`; assert visibility in the main-scene smoke.
- Risk: oxygen pump makes the breach trivial. Mitigation: keep the multiplier at 0.5 (still drains, still blocks at zero) and record the effective drain in smoke output so tuning is visible.
- Risk: inventory model and oxygen model form a tight coupling. Mitigation: `OxygenState` only reads a summary Dictionary; it does not own `InventoryState`.
- Risk: tool data model decisions become ad-hoc. Mitigation: author ADR-0004 (Inventory/Tool Data Model) before implementation if the implementation worker wants to generalize beyond one hard-coded tool.

## ADRs

- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md`
- ADR-0004 recommended if the implementation generalizes the tool/effect system beyond one hard-coded multiplier. The spec itself can ship with a single JSON definition and one conditional branch, deferring the formal ADR until a second tool is added.
