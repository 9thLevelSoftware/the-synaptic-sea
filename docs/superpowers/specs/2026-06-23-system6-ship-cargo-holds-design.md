# System 6 — Ship Cargo Holds (Player↔Ship Transfer) Design

Date: 2026-06-23
Status: Approved design. First slice of System 6 (Inventory & Equipment) remainder.
Supersedes nothing. Builds on shipped player `InventoryState` + loot.

## Context

System 6 (Inventory & Equipment) has its player half shipped: `InventoryState`
(weight-capped, categorized: part/supply/tool) and the loot loop (`loot_roller`,
`loot_container`, `item_definitions.json`, `loot_tables.json`). The roadmap
(`docs/game/09_system_roadmap.md`) lists the remainder as ShipInventory,
EquipmentSlots, and item transfer.

This spec covers **only the first slice**: per-ship cargo storage plus a physical
player↔ship transfer mechanism. EquipmentSlots and carry containers
(bags/trolleys/carts) are explicitly **deferred to follow-on slices**.

### Design decision — no ship↔ship transfer

There is deliberately **no magic ship↔ship transfer**. Moving cargo from ship A to
ship B is emergent and physical: withdraw from A's hold into your personal carry
capacity, physically walk it through the airlock to the docked/bayed ship B, and
deposit. This matches System 5's whole ethos (physical docking, physical pilot
switch, no menu teleports) and removes an entire subsystem. Carry containers that
raise per-trip hauling capacity (bags/trolleys/carts) are a future slice; this
slice hauls via the player's existing 50 kg `InventoryState` cap.

## Goal

A ship can hold cargo. The player physically loads/unloads it by walking up to the
ship's cargo hold and depositing or withdrawing. No screen-space UI — the rich
item-picker is Phase 7 work regardless; this slice uses a deposit-all /
withdraw-by-category interaction consistent with the project's Phase-7 UI deferral.

## Architecture

Five components, mirroring patterns already proven in the codebase
(`HangarBay`/`HangarBayControl`, `LootContainer`, the `ShipInstance` lazy-create +
conditional-persist convention):

1. **`ShipInventory`** — pure model (`RefCounted`), the per-ship hold.
2. **`ItemDefs`** — small shared static for item weight/stack/category lookups,
   extracted from `InventoryState` so both player and ship inventories share it (DRY).
3. **`CargoTransfer`** — pure static transfer logic (deposit-all / withdraw-category),
   unit-testable off-tree.
4. **`CargoHoldControl`** — physical walk-up `Area3D` sensor in the cargo room.
5. **Coordinator wiring** in `playable_generated_ship.gd` — spawn, signal handlers,
   teardown, persistence routing.

### Component 1 — `ShipInventory` (`scripts/systems/ship_inventory.gd`, new)

`extends RefCounted`, `class_name ShipInventory`. A focused container; never touches
the scene tree.

```
const MAX_WEIGHT_DEFAULT: float = 500.0   # tunable balance knob

var items: Dictionary = {}                # item_id: String -> quantity: int
var max_weight: float = MAX_WEIGHT_DEFAULT # configurable per ship

# Static factory via load() self-reference (class_name globals unreliable under
# --headless --script). Mirrors ShipInstance.create / WorldSnapshot.from_dict.
static func create(p_max_weight: float = MAX_WEIGHT_DEFAULT) -> ShipInventory

func get_max_weight() -> float
func get_total_weight() -> float          # sum(ItemDefs.weight_each(id) * qty)
func get_quantity(item_id: String) -> int
func add_item(item_id: String, qty: int) -> int    # honors max_stack + weight room; returns qty actually added
func remove_item(item_id: String, qty: int) -> int # returns qty actually removed
func get_items_by_category(category: String) -> Array  # [{id, quantity, weight_each}], sorted by id
func reset() -> void
func get_summary() -> Dictionary          # { "items": {...}, "max_weight": float }
func apply_summary(summary) -> bool       # tolerant: missing/empty -> false; reads items + max_weight
```

`add_item` semantics match `InventoryState.add_item` exactly (stack room AND weight
room gating; weight-0 items ignore the cap; returns the quantity that actually fit).
No player-tool shims — this is a plain container.

`max_weight` default is 500.0. It is persisted (so a hand-tuned or
future-room-scaled cap round-trips). Scaling the cap with cargo-room footprint is a
future enhancement, out of scope here.

### Component 2 — `ItemDefs` (`scripts/systems/item_defs.gd`, new — DRY extract)

`InventoryState` currently owns the item-definition load + per-item lookups
(`get_weight_each`, `_max_stack`, `get_category`, `get_display_name`,
`get_definition`). `ShipInventory` needs the same weight/stack/category lookups.

Extract these into a small shared static so both call one source of truth:

```
class_name ItemDefs   # extends RefCounted, all-static

const ITEM_DEFINITIONS_PATH := "res://data/items/item_definitions.json"
const TOOL_DEFINITIONS_PATH := "res://data/tools/tool_definitions.json"
const DEFAULT_TOOL_WEIGHT := 2.0
const DEFAULT_MAX_STACK := 99

static func load_definitions() -> Dictionary   # merged tool+item defs (tools get synthetic category 'tool' + default weight), same merge order as InventoryState today
static func weight_each(defs: Dictionary, item_id: String) -> float
static func max_stack(defs: Dictionary, item_id: String) -> int
static func category(defs: Dictionary, item_id: String) -> String
static func display_name(defs: Dictionary, item_id: String) -> String
```

`InventoryState` is refactored to call `ItemDefs` internally. **Its public API,
constants, legacy tool shims, save/load shape, and `get_status_lines()` markers are
unchanged** — this is a pure internal extraction. The `InventoryState` model smoke
and the inventory HUD smoke must still pass byte-for-byte on their markers; that is
the regression guard for the extract.

`ShipInventory` holds its own `var _defs := ItemDefs.load_definitions()` and calls
`ItemDefs.weight_each(_defs, id)` etc.

### Component 3 — `CargoTransfer` (`scripts/systems/cargo_transfer.gd`, new)

Pure static transfer logic, so the load/unload rules are unit-testable without a
scene tree.

```
class_name CargoTransfer   # extends RefCounted, all-static

# Haulable salvage categories moved by deposit-all. Tools are intentionally excluded
# (survival gear stays on the player and is never auto-dumped).
const HAULABLE_CATEGORIES := ["part", "supply"]

# Moves all part+supply stacks from player -> hold, capped by the hold's weight room.
# For each stack: ask hold.add_item(id, have); remove from player EXACTLY what landed.
# Returns { "moved": {id:qty}, "total_moved": int }.
static func deposit_all(player: InventoryState, hold: ShipInventory) -> Dictionary

# Moves as much of `category` as the player's carry room accepts, hold -> player.
# For each stack of that category in the hold: ask player.add_item(id, have); remove
# from hold EXACTLY what the player accepted. Returns { "moved": {id:qty}, "total_moved": int }.
static func withdraw_category(hold: ShipInventory, player: InventoryState, category: String) -> Dictionary
```

**Correctness hinge — conservation:** every move removes from the source *exactly*
what the destination's `add_item` reported accepting. Partial fills (hold full mid-
deposit, player weight-capped mid-withdraw) must never duplicate or vanish items.
The transfer smoke asserts the **conservation invariant**: the summed quantity of
every item id across `player.items` + `hold.items` is identical before and after any
transfer.

Iterate over a snapshot of the source's item ids (not the live dict) so removals
during iteration are safe.

### Component 4 — `CargoHoldControl` (`scripts/tools/cargo_hold_control.gd`, new)

`extends Area3D`, `class_name CargoHoldControl`. Physical walk-up sensor placed at
the cargo room floor center. Same strict in-range gate + debug marker pattern as
`HangarBayControl` / `LootContainer` (orange-class marker, `_is_player_in_direct_range`
character-identical to the proven controls).

```
signal cargo_deposit_requested(ship_id: String)
signal cargo_withdraw_requested(ship_id: String, category: String)

var carrier_id: String = ""
var interaction_radius: float = 1.8

func configure(p_carrier_id: String, world_position: Vector3, radius := 1.8) -> void
func try_deposit(player_body: Node) -> bool                       # strict range gate -> emit cargo_deposit_requested
func try_withdraw(player_body: Node, category: String) -> bool    # strict range gate -> emit cargo_withdraw_requested
func set_validation_player_in_range(player_body: Node) -> void    # validation seam, mirrors LootContainer
```

The control only emits intent; it never mutates inventories itself (the coordinator
owns the models, single-ownership). `try_*` return `false` when out of range or no
player, and do not emit.

### Component 5 — Coordinator wiring (`scripts/procgen/playable_generated_ship.gd`)

Mirror the hangar-control wiring already in this file:

- `const CargoHoldControlScript := preload("res://scripts/tools/cargo_hold_control.gd")`
- `var cargo_hold_controls: Array = []`
- `_spawn_cargo_hold_control(inst)`:
  - `pos = DockPorts._room_floor_center(inst.built_layout, "cargo", "cargo")`; if
    `Vector3.INF`, skip (ship has no cargo room → no hold, no lazy `ShipInventory`).
  - Idempotent per-carrier prune (same guard as `_spawn_hangar_control`) so
    reload/re-peg never double-spawns.
  - Connect `cargo_deposit_requested` → `_on_cargo_deposit_requested`,
    `cargo_withdraw_requested` → `_on_cargo_withdraw_requested`.
- `_clear_cargo_hold_controls()` — paired into the existing reset / reload-to-home
  teardown at the exact site `_clear_hangar_controls()` is called. (PR #15/#16
  established that a missing teardown of per-ship interactables is a real bug class;
  it goes in from the start.)
- `_on_cargo_deposit_requested(ship_id)`:
  `CargoTransfer.deposit_all(player_inventory, _ship_for_id(ship_id).get_inventory())`.
- `_on_cargo_withdraw_requested(ship_id, category)`:
  `CargoTransfer.withdraw_category(_ship_for_id(ship_id).get_inventory(), player_inventory, category)`.
- Validation seams (mirroring the hangar seams): e.g.
  `cargo_deposit_for_validation(ship_id) -> int` (returns total_moved),
  `cargo_withdraw_for_validation(ship_id, category) -> int`,
  `ship_hold_quantity_for_validation(ship_id, item_id) -> int`,
  `ship_has_cargo_hold_for_validation(ship_id) -> bool`.

The player `InventoryState` instance is the coordinator's existing player inventory
(the one loot grants to). Confirm its accessor name during implementation; do not
assume.

### `ShipInstance` changes (`scripts/systems/ship_instance.gd`)

Mirror `get_hangar()` / `get_access()` exactly:

```
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")

var inventory = null   # ShipInventory | null; lazily created; persisted under "inventory" only when non-empty

func get_inventory():           # creates an empty ShipInventory on first access
    if inventory == null:
        inventory = ShipInventoryScript.create()
    return inventory

func has_cargo() -> bool:        # true iff inventory exists and holds at least one item
    return inventory != null and not inventory.items.is_empty()
```

- `get_summary()`: add `if inventory != null and not inventory.items.is_empty():
  result["inventory"] = inventory.get_summary()`.
- `apply_summary()`: read the `"inventory"` key when present (tolerant; absent → no hold).

## Persistence

**No `world-4` → `world-5` version bump.** The hold is an *additive, tolerant*
field: old saves simply lack it and load with empty holds; this changes no existing
structure (unlike `world-4`, which restructured `dock_edges`). This is a deliberate
distinction — additive-tolerant ≠ structural — recorded in ADR-0020.

Routing mirrors the existing home-vs-visited split:

- **Derelict / visited ships:** the hold rides `ShipInstance.get_summary()` under
  the `"inventory"` key (conditional on non-empty). Already covered by the
  `ShipInstance` changes above; `visited_ships` round-trips it for free.
- **Home ship:** persisted via a **new `WorldSnapshot.home_ship_inventory: Dictionary`
  field**, mirroring `home_looted_containers` exactly (written from the home ship's
  `ShipInventory.get_summary()`, read back into the home ship's hold on load).
  `RunSnapshot` is **not** touched — it carries an explicit ADR-0007 freeze on new
  fields, and its existing `inventory_summary` is the *player's* bag, a different
  concept from a ship hold.

`WorldSnapshot.to_dict()` / `from_dict()` gain symmetric handling of
`home_ship_inventory` (deep-copied dict; default `{}`).

## Transfer rules (summary)

- **Deposit-all:** moves all **part + supply** from player → hold, capped by hold
  weight room. **Tools stay on the player.** Partial if the hold fills.
- **Withdraw-by-category:** pulls a chosen category (part or supply) from hold →
  player, capped by the player's 50 kg carry room. Partial if the player fills up.

## Which ships get a hold

Any ship whose layout has a `cargo` room. Home always does (the hangar cargo-fallback
already relies on it). Derelicts get one when the cargo role is present in their
generated layout. A ship with no cargo room spawns no `CargoHoldControl` and never
lazily creates a `ShipInventory` — a clean no-op, identical to how bay-less ships
skip `HangarBayControl`.

## Validation (definition of done)

Per the project's smoke contract (pure-model smoke + main-scene smoke + register both
in `06_validation_plan.md`). Markers are the contract; they route to stderr under
headless Godot.

1. **`scripts/validation/ship_inventory_smoke.gd`** (pure model) — add/remove,
   weight-cap and max-stack gating, `get_summary`/`apply_summary` round-trip.
   Marker: `SHIP INVENTORY SMOKE PASS ...`
2. **`scripts/validation/cargo_transfer_smoke.gd`** (pure logic, off-tree) —
   deposit-all moves part+supply and **leaves tools**; withdraw-by-category respects
   the player 50 kg cap; partial fills both directions; the **conservation invariant**
   (summed per-id quantity across both containers invariant under transfer).
   Marker: `CARGO TRANSFER SMOKE PASS conserved=true ...`
3. **`scripts/validation/cargo_hold_smoke.gd`** (main-scene) — boots the playable
   ship, asserts a `CargoHoldControl` spawned at the home cargo room, drives a
   deposit then a withdraw through the signal handlers, and asserts the home hold
   **persists across a save/load round-trip** (the `WorldSnapshot.home_ship_inventory`
   path). Marker: `CARGO HOLD SMOKE PASS deposited=N withdrew=M persisted=true`

Plus regression guards: the existing `InventoryState` model smoke and inventory HUD
smoke must pass unchanged (the `ItemDefs` extract regression guard).

Bundle count: **101 → 104**. Register all three markers in
`docs/game/06_validation_plan.md`; the run must end
`SYNAPTIC_SEA REGRESSION PASS commands=104 clean_output=true`, and Gate-1 must still
return GO 2.00.

## Documentation

- **ADR-0020 (`docs/game/adr/0020-ship-cargo-holds.md`)** — records: per-ship
  `ShipInventory` as a pure model on `ShipInstance`; the no-ship↔ship-transfer
  design (physical haul only); deposit-all-excludes-tools rule; the additive,
  no-version-bump persistence decision and its routing (visited via `ShipInstance`,
  home via `WorldSnapshot.home_ship_inventory`, `RunSnapshot` untouched).
- Update `docs/game/09_system_roadmap.md` System 6 row: player-inventory + cargo
  holds done; EquipmentSlots and carry containers remain.

## Explicitly out of scope (follow-on slices)

- **Carry containers** (bags / trolleys / carts) that raise per-trip hauling
  capacity. Their own spec — a cart is plausibly a pushable in-world object or an
  equipped capacity multiplier.
- **EquipmentSlots** — worn items (suit / tool-belt) that modify actions.
- **Rich screen-space transfer UI** (item picker, quantity selection) — Phase 7.
- **Tool storage in ship holds** — this slice keeps tools on the player.
- **Cargo-room-footprint-scaled hold capacity** — fixed 500 kg default this slice.

## File summary

New:
- `scripts/systems/ship_inventory.gd`
- `scripts/systems/item_defs.gd`
- `scripts/systems/cargo_transfer.gd`
- `scripts/tools/cargo_hold_control.gd`
- `scripts/validation/ship_inventory_smoke.gd`
- `scripts/validation/cargo_transfer_smoke.gd`
- `scripts/validation/cargo_hold_smoke.gd`
- `docs/game/adr/0020-ship-cargo-holds.md`

Modified:
- `scripts/systems/inventory_state.gd` (internal `ItemDefs` extract; public API unchanged)
- `scripts/systems/ship_instance.gd` (lazy `inventory` + persistence)
- `scripts/systems/world_snapshot.gd` (`home_ship_inventory` field)
- `scripts/procgen/playable_generated_ship.gd` (spawn / handlers / teardown / seams)
- `docs/game/06_validation_plan.md` (register 3 smokes, 101 → 104)
- `docs/game/09_system_roadmap.md` (System 6 status)
