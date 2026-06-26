# ADR-0008: Ship Systems Architecture — Data-Driven Systems, Derived Cascade, Parameterized Repair

## Status

Accepted

## Context

Build Phase 2 of the core-systems rebuild
(`docs/superpowers/specs/2026-06-20-synaptic-sea-core-systems-design.md`, System 2) introduces
the six core ship systems — Power, Life Support, Gravity, Propulsion, Navigation, Scanners —
each with subcomponents, inter-system dependencies, dependency-cascade failure, and a repair
flow. The design is detailed in
`docs/superpowers/specs/2026-06-20-phase2-ship-systems-design.md`.

Two facts constrain the architecture:

1. An existing `ShipSystemState` (`scripts/systems/ship_system_state.gd`) already models
   "ship systems" for the live playable slice, but as an objective-flag model
   (`recover_supplies`, `restore_systems`, `stabilize_reactor` → booleans + power %). It is
   covered by a green regression smoke (`main_playable_slice_ship_systems_smoke.gd`,
   `completed_systems=4`). The parent spec says it "becomes ShipSystemsManager," which would
   be an in-place rewrite with a large blast radius.
2. The repair flow described in the parent spec depends on a skill system (Phase 3) and an
   inventory/parts/tools system (Phase 6) that do not exist yet.

Without an ADR, the likely outcomes are: an in-place rewrite that risks the regression
bundle; a cached per-system "online/offline" cascade flag that desynchronizes from health on
save/load; or a repair method hard-wired to not-yet-built skill/inventory systems.

## Decision

Adopt an independent, data-driven `ShipSystemsManager` model layer with a **derived**
(non-cached) dependency cascade and a **parameterized** repair contract.

### 1. Build alongside, integrate later

Phase 2 ships `ShipSystemsManager` + `ShipSystem` + `ShipSubcomponent` (+ a
`LifeSupportSystem` subclass) as new `RefCounted` models alongside `ShipSystemState`. The
live slice and its smoke are untouched this phase. Wiring the manager into the runtime
(`PlayableGeneratedShip`, HUD, `SaveLoadService`) is a separate later step. This honors the
parent spec's "each system built in isolation with clean interfaces" principle and keeps the
regression bundle green.

### 2. Data-driven systems, not a class per system

Systems are configured from `data/ship_systems/systems.json` (subcomponents, repair
requirements, dependency ids). The base `ShipSystem` class is sufficient for five of the six
systems; only `LifeSupportSystem` is a subclass, because it is the one system with a
model-level time effect (draining the existing `OxygenState` when offline). Per-system
non-oxygen effects (gravity, propulsion, navigation, scanners) are exposed as status for
future consumers rather than encoded as subclasses now (YAGNI).

### 3. Derived cascade, no cached operational flag

`is_operational(system_id)` is computed on demand: a system is operational iff it is
self-functional (all subcomponents at/above threshold) AND every dependency is operational,
resolved by a cycle-safe recursive walk. There is no stored "offline because of a
dependency" flag. This makes the Power → everything cascade emergent and eliminates a class
of save/load desync bugs (only health and oxygen state are serialized; status is always
recomputed).

### 4. Parameterized repair contract

`repair(system_id, subcomponent_id, available_parts, available_tools, skill_level)` takes
the skill level and available parts/tools as inputs and resolves deterministically against
each subcomponent's declared requirements (`required_parts`, `required_tools`, `min_skill`,
`repair_seconds`). Success is fully determined by requirements being met — no seed-based
chance in Phase 2. Phase 3 (skills) and Phase 6 (inventory) later supply the skill value and
parts/tools sets through this same signature, with no interface change.

### Why not the alternatives

- **In-place rewrite of `ShipSystemState`** — large blast radius on a freshly-green bundle;
  the objective-flag model and the rich 6-system model serve different current consumers.
  Deferring the merge de-risks both.
- **Cached cascade flags** — cheaper repeated reads, but introduce derived state that must
  be kept in sync and serialized carefully; the system count is tiny, so recomputation is
  negligible.
- **Repair hard-wired to skills/inventory** — impossible cleanly before those systems exist;
  a parameterized signature is the seam that lets them plug in later.

## Consequences

- Two "ship system" models coexist until the integration step; this is intentional and
  time-boxed. The integration step must reconcile `ShipSystemState`'s objective flags with
  the new manager and update the live slice + its smoke together.
- The new model layer carries its own `get_summary()`/`apply_summary()` round-trip
  (REQ-012 convention) but is **not** in the live save snapshot yet, so the `summaries=7`
  save contract is unchanged this phase.
- Phase 2 is validated by a pure-model smoke only; a main-scene smoke is added at
  integration time when scene consequences first exist.
- The repair contract anchors the Phase 3 / Phase 6 interfaces in advance, reducing rework
  when skills and inventory land.
