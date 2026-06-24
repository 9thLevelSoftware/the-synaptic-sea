# ADR-0023: Inventory Interactive Widget Layer (Phase 7 slice 2)

Date: 2026-06-23
Status: Accepted

## Context
Slice 1 (ADR-0022) delivered the inventory/transfer logic + Godot DnD entry points but rendered
a single text label with no per-row widgets, so the panel was not actually mouse-operable
(Codex PR review confirmed empty drag payloads in real play).

## Decisions
1. **Custom row Controls** back the rows (`inventory_row.gd`) — not ItemList/Tree — for full
   control over the hand-built theme, drag-drop, and right-click; rows stay thin and forward
   every mouse event to coordinator callbacks on InventoryPanel.
2. **Drop targets** are `inventory_drop_zone.gd` (panes + the 5 equipment slots); rows are also
   drop targets for their own pane (drop-on-row == drop-on-pane).
3. **Right-click `PopupMenu`** built from `context_actions`: Transfer / Transfer all
   (`transfer_all_from`, includes tools) / Split… (SpinBox amount picker -> transfer_quantity) /
   Equip; right-click an occupied slot -> Unequip.
4. **On-screen Deposit All + Close buttons**, keeping A/Esc/I as keyboard equivalents.
5. **Purely additive** — the slice-1 model/logic layer and its smokes are unchanged; the
   text-mirror render is replaced by the widget tree. No persistence change (world-4).
6. Menus are **built, not popped** in tests (popups aren't headless-safe); the widget smoke
   drives row/zone methods with synthetic input and asserts the logical effect.

## Consequences
The panel is now genuinely mouse-driven (click/shift/ctrl select, drag across panes + onto
equipment slots, right-click menus). Deferred: drag-out-to-unequip, gamepad/keyboard grid
navigation, item-icon generation (swatch fallback stays), drop-target highlight animation.
