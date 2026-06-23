# System 6 Slice 2 — Equipment Slots, Carry Containers & Carts (PZ-faithful) — Design

Date: 2026-06-23
Status: Approved-pending-review (brainstorming output)
System: 6 — Inventory & Equipment
Predecessors: player inventory + loot (#3, PR #11), ship cargo holds (ADR-0020, PR #17)
North Star: open-world ship-survival, PZ-style (PR #10 vision)

## 1. Purpose & summary

Add the **worn-equipment and carry-container** layer of System 6, modeled on
Project Zomboid's inventory mechanics:

- A **worn-equipment** system: body-location slots (`suit`, `back`, `waist`,
  `primary_hand`, `secondary_hand`), one item per slot, items declare their slot.
- **Worn containers** (backpack on `back`, tool-belt/pack on `waist`, bag in a
  hand) that **raise the player's carry capacity** — PZ's "the bag lets you carry
  more" effect, collapsed onto our single-pool inventory.
- **PZ soft-cap encumbrance**: the player may carry *over* capacity; doing so
  triggers a **Heavy Load** movement-speed penalty that scales with how far over
  capacity they are. (PZ also drains endurance and damages health over capacity;
  those are deferred — see §9 — because no player stamina/health model exists.)
- **Carts** (pushable mobile containers): a wheeled container whose contents are
  **entirely off** the player's personal encumbrance (a cart removes weight; a
  worn backpack only raises the cap). Pushing a cart occupies **both hands**,
  blocks hand actions, and applies a push speed penalty.
- **Equipment effects beyond capacity**: a worn suit modifies the oxygen-drain
  multiplier (ties into the existing oxygen hazard); the model is generic so more
  effects can be added without new plumbing.

The rich equip/unequip and item-transfer **UI is Phase-7-deferred** (same call as
cargo-holds withdraw). This slice provides equipping via **auto-equip-best-
container on pickup** plus validation seams; the screen UI lands in Phase 7.

## 2. Goals / non-goals

**Goals**
- A pure `EquipmentState` model (worn slots + aggregated effects) with
  get/apply_summary round-trip.
- Carry capacity = base + worn-container bonus + (seam) strength bonus.
- Soft-cap `InventoryState`: `add_item` accepts over the weight cap (still bounded
  by `max_stack`); a separate query reports encumbrance/over-capacity.
- Heavy Load → `PlayerController.move_speed` multiplier, PZ-tiered.
- A pure `CartState` mobile container reusing `CargoTransfer`; a `CartControl`
  scene node (grab/haul/release + both-hands + push penalty + load/unload).
- Additive persistence of equipment + carts (no `world-4` version bump unless
  structurally required).
- Full PASS-marker validation: pure-model smokes + a main-scene smoke; registered
  in the regression bundle.

**Non-goals (this slice)**
- Screen-space equipment/inventory/transfer UI (Phase 7).
- Player endurance / health / over-encumbrance damage (no player-condition model
  yet; movement penalty only).
- Full clothing layering & protection (bite/insulation) — only the generic effect
  hook + the suit→oxygen effect are wired.
- Strength-skill scaling of capacity (System 3 work; a seam is provided, default 0).
- Nested per-container item assignment (PZ assigns each item to a specific bag).
  We collapse worn-bag reduction onto the single inventory pool as a capacity
  bonus; per-container nesting is a deferred enhancement (§9).

## 3. PZ reference model (what we are matching)

From research (pzwiki / community):
- Carry capacity is one encumbrance budget, raised by Strength.
- Over 100% capacity → Heavy Load, with escalating penalties: ~37% slower walk at
  125%, ~75% slower at 175%, plus endurance/health effects.
- Worn bags reduce the encumbrance of their contents (a back/waist slot gives full
  reduction; a hand-held bag less). Containers also have their own hard cap.
- Body locations: one item per location; some conflict.
- Carts (Build 42): two-handed, block other hand actions and climbing, reduced
  push speed; their contents do not count toward the character's weight.

Our collapse decisions (single-pool inventory, no nesting, no Strength yet):
- Worn container → **+capacity** to the single inventory pool (math-equivalent to
  contents reduction for one pool).
- Cart → **separate** container, contents excluded from personal encumbrance.
- Heavy Load → **movement penalty only** this slice.

## 4. Components & interfaces

### 4.1 `scripts/systems/equipment_state.gd` — `EquipmentState extends RefCounted` (new)

Pure model. Worn items by slot; aggregates effects.

```
const SLOTS := ["suit", "back", "waist", "primary_hand", "secondary_hand"]

var slots: Dictionary = {}          # slot_id -> item_id (String); absent = empty
var _definitions: Dictionary = {}   # merged item defs (ItemDefs.load_definitions)

static func create() -> EquipmentState              # load() self-ref factory
func can_equip(item_id) -> bool                      # item has equip_slot in SLOTS
func equip(item_id) -> Dictionary                     # { "ok": bool, "displaced": String }
func unequip(slot) -> String                         # returns removed item_id ("" if empty)
func get_equipped(slot) -> String
func is_slot_occupied(slot) -> bool
func get_carry_capacity_bonus() -> float             # sum of container_capacity of worn containers
func get_oxygen_drain_multiplier() -> float          # product of suit effects (default 1.0)
func get_summary() -> Dictionary                     # { "slots": {...} }
func apply_summary(summary) -> bool
```

- `equip(item_id)` validates `can_equip`; on failure returns `{ok=false,
  displaced=""}`. On success it displaces any item already in that slot (returned
  as `displaced` for the caller to put back in inventory) and records
  `slots[slot]=item_id`, returning `{ok=true, displaced=<id-or-"">}`.
- Hands: `primary_hand`/`secondary_hand` accept hand-eligible items. EquipmentState
  does **not** know about carts; the coordinator owns cart state (§4.5) and, while a
  cart is grabbed, blocks equips into either hand slot. The both-hands-busy
  condition lives in the coordinator, not in EquipmentState.

### 4.2 `scripts/systems/item_defs.gd` — extension

Add optional equipment metadata read from item defs (no signature changes to the
existing static helpers; add new readers):

```
static func equip_slot(defs, item_id) -> String          # "" if not equippable
static func container_capacity(defs, item_id) -> float    # 0.0 if not a container
static func effects(defs, item_id) -> Array               # generic [{type,value}]
```

New item defs in `data/items/item_definitions.json` (and/or a new
`data/items/equipment_definitions.json` merged like tools):
- `eva_backpack` — equip_slot `back`, container_capacity e.g. 40, weight ~3.
- `tool_belt` — equip_slot `waist`, container_capacity e.g. 12, weight ~1.
- `hardsuit` — equip_slot `suit`, effect `{type:"oxygen_drain", value:0.75}`.
- `salvage_cart` — a cart item (see §4.5), not a worn slot.

### 4.3 `scripts/systems/inventory_state.gd` — soft-cap rework

- `add_item` no longer refuses for weight; it accepts up to `max_stack` regardless
  of weight. (The `weight 0 ignore cap` branch is removed; weight never gates.)
- `get_max_weight()` stays the **base** capacity (50). New:
  - `var bonus_capacity: float = 0.0` — set by the coordinator from
    `EquipmentState.get_carry_capacity_bonus()` (+ future strength).
  - `func get_capacity() -> float: return MAX_WEIGHT + bonus_capacity`
  - `func get_load_ratio() -> float: return get_total_weight() / max(0.0001, get_capacity())`
  - `func is_over_capacity() -> bool: return get_total_weight() > get_capacity()`
- `get_status_lines()` weight readout reports `weight/capacity` (capacity, not the
  bare const) so the HUD shows the equipment-expanded budget.

**Blast-radius note (must re-validate):** `CargoTransfer` conservation = "remove
from source exactly what the destination's `add_item` accepted". With soft-cap,
`add_item` accepts up to stack room (weight no longer limits), so withdraw can pull
a hold empty and over-encumber the player — PZ-faithful, but it changes
`cargo_transfer_smoke` and `cargo_hold_smoke` expectations. Both smokes are updated
to assert the new accept-up-to-stack behavior; the conservation invariant
(removed == accepted) still holds structurally and is re-asserted.

### 4.4 Encumbrance → movement (coordinator + `PlayerController`)

- `scripts/systems/encumbrance.gd` — `Encumbrance` (new, all-static pure):
  ```
  static func move_speed_multiplier(load_ratio: float) -> float
  ```
  PZ-tiered: `<=1.0 -> 1.0`; ramps down above 1.0 — e.g. `1.0..1.25 -> 1.0..0.63`,
  `1.25..1.75 -> 0.63..0.25`, `>=1.75 -> 0.25` (clamped floor). Exact breakpoints
  in the plan; monotonic non-increasing, returns 1.0 at/below capacity.
- The coordinator (`playable_generated_ship.gd`) recomputes on inventory/equipment
  change and sets `player.move_speed = DEFAULT_MOVE_SPEED * Encumbrance.move_speed_multiplier(ratio) * cart_push_multiplier`.

### 4.5 Carts — `scripts/systems/cart_state.gd` + `scripts/tools/cart_control.gd`

- `CartState extends RefCounted` (new): a mobile container. Wraps a `ShipInventory`
  (or mirrors its API) for contents; identity `cart_id`; `parked_ship_id` and
  `parked_position` for persistence; `push_speed_multiplier` (e.g. 0.8).
  `get_summary()/apply_summary()`; `create()` factory. Contents are **never** added
  to player encumbrance.
- `CartControl extends Area3D` (new): walk-up node mirroring `CargoHoldControl`'s
  strict in-range gate. Signals: `cart_grab_requested(cart_id)`,
  `cart_release_requested(cart_id)`, `cart_load_requested(cart_id)`,
  `cart_unload_requested(cart_id, category)`. Grab → coordinator marks both hand
  slots busy + reparents/positions the cart to follow the player + applies
  `push_speed_multiplier`. Release → park at player position in current ship,
  free hands, clear push penalty. Load/unload reuse `CargoTransfer`.
- While a cart is grabbed, hand-requiring actions (equip into a hand, other
  interactions that need a free hand) are blocked by the coordinator; the cart
  "falls" (auto-releases, parked) only if forced — minimal this slice: grabbing is
  explicit, no auto-drop edge cases beyond release.

### 4.6 Equip interaction (no-UI, Phase-7 deferral)

- **Auto-equip-best-container on pickup**: when the player loots/acquires a
  container item whose target slot is empty, the coordinator auto-equips it
  (raising capacity immediately). "Best" = if the slot is already filled, a
  higher-`container_capacity` item is NOT auto-swapped (auto-equip only fills empty
  slots; upgrading a filled slot is a manual/Phase-7 action). A worn item displaced
  by a manual equip returns to inventory.
- Validation seams on the coordinator drive the real equip/unequip + capacity
  recompute paths (mirroring `cargo_interact_deposit_for_validation`):
  `equip_for_validation`, `unequip_for_validation`, `player_capacity_for_validation`,
  `player_move_speed_for_validation`, cart grab/load/unload seams.
- Real equip/unequip UX (slot picker) and the transfer screen are Phase 7.

## 5. Data flow

1. Player loots a container item → `InventoryState.add_item` (soft-cap, always
   accepts) → coordinator auto-equips into empty target slot →
   `EquipmentState.equip` → coordinator pushes new
   `bonus_capacity = EquipmentState.get_carry_capacity_bonus()` into
   `InventoryState` → recompute load ratio → set `player.move_speed`.
2. Player over-loads (loot/withdraw beyond capacity) → `is_over_capacity()` true →
   Heavy Load multiplier < 1.0 → slower movement until items shed.
3. Player grabs a cart → both hands busy, cart follows, push multiplier applied →
   loads salvage into the cart (off personal encumbrance) → hauls to another ship →
   unloads into that ship's hold via `CargoTransfer`.
4. Suit equipped → `EquipmentState.get_oxygen_drain_multiplier()` feeds the oxygen
   hazard's drain (composed with the existing `portable_oxygen_pump` tool shim).

## 6. Persistence (additive, ADR to follow)

- **Player equipment**: `WorldSnapshot.player_equipment: Dictionary = {}` (mirrors
  the cargo-holds `home_ship_inventory` pattern) ← `EquipmentState.get_summary()`.
  `RunSnapshot` is untouched (ADR-0007 field freeze).
- **Carts**: persisted with the ship they are parked in —
  `ShipInstance.get_summary()["carts"]` (array of `CartState.get_summary()`),
  conditional on non-empty, same as the `inventory` hold. A cart currently grabbed
  by the player persists as parked in the player's current ship at save time
  (release-on-save semantics) to avoid a player-owned cart limbo.
- **No `world-4` bump** unless a structural incompatibility is found; both
  additions are tolerant new keys. The save/load smoke is extended to round-trip
  equipment + a parked cart.

## 7. Validation (definition of done)

New smokes (pure-model first, then main-scene), each one PASS marker:
- `equipment_state_smoke.gd` — equip/unequip, slot validation, displaced-item
  return, capacity-bonus + oxygen-multiplier aggregation, summary round-trip.
- `encumbrance_smoke.gd` — `move_speed_multiplier` monotonic, 1.0 at/below cap,
  PZ-tier breakpoints, clamped floor.
- `cart_state_smoke.gd` — load/unload via CargoTransfer, contents excluded from
  player encumbrance, summary round-trip.
- `equipment_carts_smoke.gd` (main-scene) — boot playable ship; auto-equip on
  pickup raises capacity (assert via seam); over-load drops move_speed (assert via
  seam); grab cart → both hands busy + push penalty; load/unload; save→load
  persists equipment + a parked cart.
- Update `inventory_state_smoke.gd`, `item_inventory_smoke.gd`,
  `cargo_transfer_smoke.gd`, `cargo_hold_smoke.gd` for the soft-cap behavior; keep
  their existing PASS markers (assert new semantics, not new markers, where the
  marker contract is unchanged).
- Register all new smokes in `docs/game/06_validation_plan.md` (104 → ~108) and
  re-green the full bundle + Gate-1.

## 8. Decisions log

1. **Soft cap, PZ-exact** (user). `add_item` accepts over capacity; Heavy Load
   penalty applies. Blast radius to cargo conservation re-validated (§4.3).
2. **Heavy Load = movement only** this slice; endurance/health damage deferred (no
   player-condition model).
3. **Worn bag = +capacity** on the single pool (no per-container nesting).
4. **Cart = separate container, zero personal encumbrance**, two-handed, push
   penalty (user’s description of PZ B42 carts).
5. **Equip UX = auto-equip-best-container on pickup + seams**; rich UI Phase 7.
6. **Strength scaling = seam, default 0** (System 3, not picked).
7. **Additive persistence, no version bump**; equipment on `WorldSnapshot`, carts
   on `ShipInstance`.
8. **Slots = suit/back/waist/primary_hand/secondary_hand** (trimmed PZ body
   locations to what this game uses).

## 9. Deferred (future slices)

- Player endurance/health + over-encumbrance damage (needs a player-condition
  system); then full PZ Heavy Load.
- Nested per-container item assignment + per-bag weight-reduction %.
- Full clothing layering: protection (bite/scratch), insulation/temperature.
- Strength-skill capacity scaling (System 3 roster work).
- Screen-space equipment/inventory/transfer UI (Phase 7).
- Cart edge cases: auto-drop on climb/board, multi-cart trains.

## 10. Scope / decomposition note

This spec covers two loosely-coupled subsystems — **worn equipment + encumbrance**
and **carts**. They share the `CargoTransfer`/container patterns but are
independently testable. The implementation plan may split delivery into two task
groups (equipment+encumbrance first, carts second) and optionally two PRs; each is
a working, validated slice on its own. That split is decided at the writing-plans /
finishing stage, not here.
```
