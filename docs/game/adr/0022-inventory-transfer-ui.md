# ADR-0022: Inventory & Transfer UI (Phase 7 slice 1)

Date: 2026-06-23
Status: Accepted

## Context
System 6 built the inventory/equipment/cargo/cart models but deferred the player-facing
UI to Phase 7. This slice delivers the interactive screen.

## Decisions
1. **Hand-built theme, no external asset kit.** The Godot Asset Library has no usable
   game-UI skins; itch kits were surveyed and declined. The panel uses `StyleBoxFlat`
   matching `ObjectiveTracker`/`ScannerPanel`.
2. **Physical open model.** Interact (`E`) at a hold/cart opens TRANSFER mode;
   `toggle_inventory` (`I`, registered at runtime) opens SELF mode. Supersedes the bulk
   deposit/withdraw prompts; bulk deposit-all survives as the panel's convenience action.
3. **Mouse-driven** drag-and-drop, shift/ctrl multi-select, right-click context menus —
   list-with-icons layout (not a slot grid), matching our weight/quantity model.
4. **Item icons deferred** behind an `ItemDefs.icon` reader with a category-swatch
   fallback; no icon art in this slice.
5. **Tools transferable** via manual move; bulk `deposit_all` still excludes them.
   Depositing the O2 pump reverts the oxygen drain multiplier live (×1.0), withdrawing
   restores ×0.5, via `_on_inventory_transfer_completed` → `_refresh_oxygen_state`.
6. **Model/Node split.** Pure `InventorySelectionModel` (selection math + action
   resolver, fully smoke-tested) + thin `InventoryPanel` Control whose mouse/DnD
   overrides delegate to a headless-queryable logical API. Only literal pixel-drag
   plumbing is lightly covered.
7. **No new persisted state**; `world-4` unchanged. The panel is a pure view.

## Consequences
The player can now view inventory + worn gear and move salvage per-item to/from holds
and carts. Deferred: item-icon generation, partial-stack split UX polish, slot/volume
model, floor-drop, gamepad nav, the B/C/D Phase-7 sub-slices.
