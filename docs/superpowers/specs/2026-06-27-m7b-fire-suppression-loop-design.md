# M7-B — Fire Suppression ↔ Real Fire (design spec)

**Date:** 2026-06-27
**Lane:** M7 "Ship systems & sustenance infrastructure" — sub-project **B** (after A: life-support→vitals).
**Status:** approved in brainstorming; pending written-spec review.

## Goal

Close the fire loop. Today the real fire hazard (`fire_state`, a single layout-room
zone on a fixed `CLEARED↔BURNING` timer the player can only wait out) and the
fire-suppression system (`fire_suppression_state`, an abstract per-compartment
`active_fires` dictionary that ignites only from a validation seam and emits HUD
text) are two parallel, unconnected models. The audit grades suppression 🔴
"a HUD shadow of the real fire hazard."

This sub-project makes **one authoritative, compartment-keyed, persist-until-extinguished
fire model** that the player actually fights, with fire as a *symptom of unrepaired
system damage* and three distinct extinguish paths, FTL-style.

This is intentionally a single large spec (user chose "one big B spec, all at once"
over a B1/B2/B3 sequence). The implementation plan keeps tasks cleanly separated so
it stays reviewable.

## Product decisions locked in brainstorming

1. **Authority:** suppression becomes authoritative; `fire_state` (the cyclic
   phase-timer hazard) is **retired**. Fire is no longer a timer cycle.
2. **Player role:** manual extinguish interaction (full loop) **plus** powered
   auto-suppression **plus** decompression (venting) extinguishes.
3. **Decompression scope:** cheap coupling now — a breached/vacuum compartment
   auto-extinguishes fire (binary, reuses M7-A `breach_open`). The deliberate-vent
   *control* + decompression danger is a deferred follow-up (B2).
4. **Fire teeth:** active fire damages **player vitals AND the ship system** housed
   in the burning compartment.
5. **Spread:** simple spread in B — a burning compartment can ignite an adjacent
   one over time (deterministic accumulator, no door-gating yet).
6. **Ignition:** fire is a **symptom of damage**, never random. A compartment
   ignites only when its mapped ship system has a non-functional (damaged)
   subcomponent **and** the compartment has oxygen (not vented). Plus
   electrical-arc cascade. Fire **re-ignites until the system is repaired** (or the
   compartment is vented) — extinguishing is temporary relief; you must treat the
   cause.
7. **Extinguisher economy:** the `fire_extinguisher` is a reusable tool with a
   depletable **charge**; manual extinguish consumes charge; a **recharge port**
   refills it slowly but only while ship power is active.

## Architecture

### The core move: fire is compartment-keyed

All couplings (fire↔hull breach, fire↔ship system, fire spread, arc→fire cascade)
collapse onto the **4 logical compartments** (`bridge`, `engineering`,
`hydroponics`, `cargo`) already used by `HullIntegrityState` and
`FireSuppressionState`. `fire_state.gd` (layout-room space, phase-timer) is deleted.

`FireSuppressionState` is promoted to the **single authoritative fire model**:
per-compartment fires that persist until extinguished. Pure `RefCounted`, no scene
tree (ADR model/node rule). The coordinator renders **one passable fire-zone
`Area3D` per burning compartment** (visual + overlap trigger, *no* collision
block — the player must be able to walk in to fight the fire), positioned with the
same `_distributed_room_positions()` the breach seal points use, refreshed whenever
`active_fires` changes.

### Data flow per tick (coordinator → fire model)

The coordinator assembles a context dict and calls `fire_suppression_state.tick(delta, context)`:

```
context = {
  "powered_ratio":          power_grid_state.get_allocation_ratio("stations"),
  "ship_oxygen_present":     life_support_expanded_state.oxygen_percent > OXYGEN_MIN_FOR_FIRE,
  "breached_compartments":   [cid for cid in hull where breach_open],   # vacuum
  "damaged_compartments":    [cid for cid,sys in COMP_SYS if not manager.get_system(sys).is_self_functional()],
  "arc_arcing":              electrical_arc_state.phase == ARCING,
  "arc_compartment":         ARC_COMPARTMENT,   # config
}
```

Tick order inside the model (all deterministic — no RNG):

1. **Vent-extinguish:** any active fire in a `breached_compartments` entry is removed
   immediately (no charge/suppressant cost). Breach also blocks ignition there.
2. **Powered auto-suppression:** if `powered_ratio ≥ power_threshold` and
   `suppressant_units > 0`, reduce each active fire's intensity by
   `suppression_rate_per_second * delta`; drain `suppressant_units`; clear fires
   that hit 0.
3. **Spread:** for each burning compartment, add `spread_rate_per_second * delta *
   intensity` to `spread_progress[adjacent]` for each oxygenated, non-burning,
   adjacent compartment; ignite when ≥ 1.0 and reset that accumulator.
4. **Ignition from damage (re-ignition):** for each compartment that is
   `damaged ∧ has-oxygen ∧ not-burning`, add `ignition_rate_per_second * delta` to
   `ignition_progress[cid]`; ignite at ≥ 1.0 and reset. Compartments that are not
   damaged, or vented, decay their `ignition_progress` toward 0.
5. **Arc cascade:** while `arc_arcing ∧ arc_compartment has-oxygen ∧ not-burning`,
   add `cascade_rate_per_second * delta` to `cascade_progress`; ignite at ≥ 1.0 and
   reset. Resets to 0 when the arc is not arcing.

`has-oxygen` for a compartment = `ship_oxygen_present ∧ cid ∉ breached_compartments`.
Active fires whose compartment loses oxygen (global O₂ gone) also die.

**Tuning constants** (coordinator-level, where not in the JSON tuning):
- `OXYGEN_MIN_FOR_FIRE = 5.0` — `ship_oxygen_present` is `oxygen_percent > 5.0`.
- `FIRE_HEALTH_DRAIN_PER_SECOND = 2.0` — vitals drain while standing in a fire
  (×intensity); echoes FTL's ~2.13 hp/s.
- `FIRE_SYSTEM_DAMAGE_PER_SECOND = 0.05` — subcomponent health lost per second a
  compartment burns (×intensity); echoes FTL's 0.08/s system damage.

> **Deferred (B2):** an active fire does *not* yet consume/reduce ship oxygen
> (gradual per-room O₂). Fire only *reads* oxygen presence. Per the "cheap coupling
> now" decision.

## Components (file-by-file)

### Rework: `scripts/systems/fire_suppression_state.gd` (authoritative fire model)

New/changed fields (config-driven via `configure`):

- `compartments: Array[String]` — existing.
- `active_fires: Dictionary` — `{compartment_id: intensity}`, existing.
- `suppressant_units: float`, `suppression_rate_per_second: float`,
  `power_threshold: float` — existing (powered auto-suppression).
- `adjacency: Dictionary` — `{compartment_id: Array[String]}` for spread.
- `spread_rate_per_second: float` (default `0.15`).
- `ignition_rate_per_second: float` (default `0.2`) — damaged+oxygen re-ignition.
- `cascade_rate_per_second: float` (default `0.5`) — arc cascade.
- `arc_compartment: String` (default `"engineering"`).
- `spread_progress: Dictionary`, `ignition_progress: Dictionary`,
  `cascade_progress: float` — accumulators (dynamic state; saved).

New methods:

- `tick(delta, context)` — rewritten to the 5-step order above. Returns `bool`
  (any fire set changed) so the coordinator can refresh scene zones.
- `extinguish(compartment_id) -> bool` — manual/external full removal of one fire.
- `is_burning(compartment_id) -> bool`, `get_burning_compartments() -> Array[String]`.
- `ignite(compartment_id, intensity)` — existing, retained (used by tests + cascade).
- `get_intensity(compartment_id) -> float`.

`get_summary()` / `apply_summary()` extended to round-trip `active_fires`,
`suppressant_units`, `spread_progress`, `ignition_progress`, `cascade_progress`,
and the tunables (mirrors the M7-A pattern of saving tunables for a clean
round-trip). `apply_summary` validates types and returns `true` on any change.

### New: `scripts/systems/extinguisher_state.gd` (player tool charge)

Pure `RefCounted`. Player-equipment resource, owned by the coordinator.

- `charge: float` (0..`max_charge`), `max_charge: float` (default `100`).
- `charge_cost_per_use: float` (default `34` → ~3 uses per full charge).
- `recharge_per_second: float` (default `5`).
- `configure(config)`, `has_charge_for_use() -> bool`,
  `consume_use() -> bool` (subtract cost, clamp ≥0),
  `recharge(delta)` (add `recharge_per_second*delta`, clamp ≤max),
  `get_summary()` / `apply_summary()`.

### New: `scripts/tools/fire_suppression_point.gd` (manual extinguish interaction)

`class_name FireSuppressionPoint extends Area3D`, modeled exactly on
`BreachSealPoint`:

- `configure(compartment_id, fire_state_ref, extinguisher_state, inventory_state,
  player_progression, world_position, extinguish_seconds, required_tool, radius)`
  where `fire_state_ref` is the `FireSuppressionState`, `required_tool` =
  `"fire_extinguisher"`.
- `try_start(player)` succeeds only when: player in range, compartment
  `is_burning`, inventory holds the `fire_extinguisher` tool,
  `extinguisher_state.has_charge_for_use()`. Emits `extinguish_blocked(cid, reason)`
  otherwise (`not_burning` / `missing_extinguisher` / `no_charge`).
- self-ticking channel (`_process` → `advance_channel`); leaving range cancels with
  no cost.
- `_complete()`: `extinguisher_state.consume_use()` + `fire_state_ref.extinguish(cid)`;
  grants repair XP; emits `fire_extinguished(cid)`.
- validation seam `advance_channel(delta)` (exposed, as on BreachSealPoint).

### New: `scripts/tools/extinguisher_recharge_port.gd` (recharge station)

`class_name ExtinguisherRechargePort extends Area3D`. Stationary node on the ship.

- `configure(extinguisher_state, world_position, radius)`.
- `set_powered(bool)` — driven by the coordinator each frame from the `stations`
  power channel (same precedent as `CraftingStation.set_powered`).
- `_process(delta)`: when `powered` **and** a player is in range, call
  `extinguisher_state.recharge(delta)`.
- one port on the home/lifeboat ship; deferred: ports on derelicts.

### Change: `scripts/systems/vitals_state.gd`

Add a `fire_health_drain` context channel to `tick`, exactly mirroring the existing
`atmosphere_health_drain` (added in M7-A):

```gdscript
if context.has("fire_health_drain"):
    h_drain += float(context.get("fire_health_drain", 0.0)) * delta_seconds
```

Update the `tick` docstring channel list. No save change.

### Change: `scripts/systems/ship_systems_manager.gd`

Add `damage_system(system_id: String, amount: float) -> bool`: reduce every
subcomponent's `health` by `amount` (clamp ≥ 0). Returns `false` for unknown
system. Used by the coordinator to apply fire→system degradation.

### Change: `scripts/procgen/playable_generated_ship.gd` (coordinator)

- **Delete** all `fire_state` wiring: the `fire_state` var, `FireStateScript`
  preload, `_build_fire_zone`/`_refresh_fire_state`/`_apply_fire_zone_scene_state`,
  the single `fire_zone_node`/`fire_zone_label`, room-space resolution, the
  `fire_state.tick` call (line ~4259), and the top-level `snapshot.fire_summary`
  save/restore.
- **Add** per-compartment fire-zone rendering: `_build_fire_zones()` /
  `_clear_fire_zones()` / `_refresh_fire_zones()` building one passable Area3D
  (overlap monitor + emissive visual + `Label3D`) per `get_burning_compartments()`,
  positioned via `_distributed_room_positions()` (home) /
  `_lifeboat_local_repair_positions()` / current-ship positions, paired at the same
  6 lifecycle sites as the breach seal points.
- **Add** `_build_extinguisher_recharge_ports()` / `_clear_*` (one port, home/lifeboat),
  paired at the same lifecycle sites; `set_powered(stations_powered)` each frame.
- **Add** `_build_fire_suppression_points()` / `_clear_*` — one FireSuppressionPoint
  per burning compartment, rebuilt whenever the burning set changes.
- **Wire FireSuppressionPoints into `_on_player_interact_requested` in BOTH the home
  and away branches** (pre-empting the exact P1 Codex caught in M7-A), iterating the
  points and calling `try_start(player)`.
- **Build the fire tick context** (data-flow section above) and call
  `fire_suppression_state.tick(delta, context)`; on change, refresh fire zones +
  suppression points.
- **Vitals teeth:** when the player overlaps any burning fire zone, add
  `fire_health_drain = FIRE_HEALTH_DRAIN_PER_SECOND * intensity` to the vitals
  context (the same vitals tick already assembled for M7-A).
- **System damage:** each tick, for each burning compartment with a mapped system,
  `ship_systems_manager.damage_system(sys, FIRE_SYSTEM_DAMAGE_PER_SECOND * intensity * delta)`.
- **Extinguisher recharge ports** ticked via `set_powered`.
- Validation seams: `get_fire_suppression_points_for_validation()`,
  `teleport_player_to_fire_suppression_point_for_validation(point)`,
  `get_burning_compartments_for_validation()`, `get_extinguisher_state()`,
  `set_extinguisher_charge_for_validation(value)`.

## Data files

### `data/ship_systems/subsystem_tuning.json` → `fire_suppression` block

Extend with:

```json
"fire_suppression": {
  "compartments": ["bridge", "engineering", "hydroponics", "cargo"],
  "suppressant_units": 100.0,
  "suppression_rate_per_second": 25.0,
  "power_threshold": 0.5,
  "adjacency": {
    "bridge": ["engineering"],
    "engineering": ["bridge", "hydroponics", "cargo"],
    "hydroponics": ["engineering"],
    "cargo": ["engineering"]
  },
  "spread_rate_per_second": 0.15,
  "ignition_rate_per_second": 0.2,
  "cascade_rate_per_second": 0.5,
  "arc_compartment": "engineering"
}
```

### Compartment → system map (constant in the coordinator)

```
bridge       -> navigation
engineering  -> power
hydroponics  -> life_support
cargo        -> (none; storage, never ignites)
```

Rationale: maps fire onto systems that have real downstream stakes — `power` is the
dependency of every other system, so an engineering fire that knocks out power
cascades. `cargo` has no system and is pre-breached (vacuum), so it never burns —
consistent with the symptom-of-damage rule.

### `fire_extinguisher` tool definition

Add a `fire_extinguisher` **tool** item (reusable, category `tool`) to the item
catalog so inventory can hold it and the manual loop is real. Acquisition path is a
deferred follow-up (see below) — same staging as M7-A's `hull_sealant`, but lower
stakes since it is reusable, not consumable.

## Save / load

Like M7-A, **no top-level `SUMMARY_FIELDS` change.** `fire_suppression_summary`
already round-trips nested inside `ship_systems_summary`; we extend its payload.
Add `extinguisher_summary` to the same nested ship-systems summary. The retired
top-level `fire_summary` is removed from new snapshots and ignored if present in a
legacy save (no error).

## ADR

New ADR `docs/game/adr/0041-fire-as-persistent-compartment-hazard.md` (next free
number; the directory convention is `NNNN-title.md`, highest existing is `0040`):
fire leaves the ADR-0005 phase-timer cyclic contract and becomes a **persistent,
compartment-keyed, resource/repair-coupled hazard** owned by `FireSuppressionState`,
joining oxygen as a non-timer hazard. Document the symptom-of-damage ignition rule,
re-ignition, the three extinguish paths, spread, and the vitals/system couplings.
Amend ADR-0005 to note fire's migration out of the timer-hazard set. Update
`hazard_contract_smoke.gd` so it no longer asserts fire under the timer-hazard
contract.

## Validation

Markers are the contract (exit code is not trusted). New/changed smokes:

- **Rework** `scripts/validation/fire_state_smoke.gd` → delete; replace with
  `scripts/validation/fire_suppression_state_smoke.gd` (pure model): asserts ignite,
  persist, manual `extinguish`, powered auto-suppression, vent-extinguish (breached
  compartment), deterministic spread to an adjacent oxygenated compartment,
  damaged+oxygen re-ignition (and that repair/vent stops it), arc cascade, and
  `get_summary`/`apply_summary` round-trip.
  Marker: `FIRE SUPPRESSION STATE PASS ignite=true persist=true extinguish=true auto_suppress=true vent=true spread=true reignite=true cascade=true round_trip=true`
- **New** `scripts/validation/extinguisher_state_smoke.gd`: charge consume + recharge
  clamps + round-trip.
  Marker: `EXTINGUISHER STATE PASS consume=true recharge=true round_trip=true`
- **New** `scripts/validation/fire_suppression_point_smoke.gd`: try_start gating
  (not_burning / missing_extinguisher / no_charge), channel completes, fire cleared,
  charge consumed.
  Marker: `FIRE SUPPRESSION POINT PASS extinguished=true charge_spent=true gated=true`
- **Rewrite** `scripts/validation/main_playable_slice_fire_smoke.gd`: fire zones are
  passable (player can enter), overlapping a burning zone drains vitals, system in
  the burning compartment loses health, extinguish via the **real**
  `_on_player_interact_requested` dispatcher clears the fire, breached compartment
  vent-extinguishes.
  Marker (extended): `MAIN PLAYABLE FIRE PASS passable=true vitals_drain=true system_damage=true extinguish_loop=true vent=true reachable=true`
- **New** `scripts/validation/main_playable_fire_loop_smoke.gd`: full end-to-end loop
  in the live scene — damaged system + oxygen ignites; player takes vitals damage;
  manual extinguish (charge consumed) clears it; still-damaged compartment
  re-ignites; repair the system stops re-ignition; recharge port (powered) refills
  the extinguisher.
  Marker: `MAIN PLAYABLE FIRE LOOP PASS ignite=true teeth=true extinguish=true reignite=true repair_stops=true recharge=true`
- **Update** `scripts/validation/hazard_contract_smoke.gd` (fire out of timer set) and
  `scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd` if it
  references fire.
- **`golden_fire_zone_source_marker_smoke.gd`:** kept passing by **not** changing the
  layout `fire_zones` marker schema. Markers remain valid spatial hints; fire
  behavior is decoupled from them (ignition is symptom-driven, not marker-driven).
- **Register** all new/changed smokes in `docs/game/06_validation_plan.md` and bump
  `commands=43` to the new count. Re-grade fire-suppression in
  `docs/game/system_completion_audit.md` (🔴 → 🟢) and update audit rollup item #5.

## Known blast-radius callouts (honest)

1. **`_on_player_interact_requested` dual-branch wiring** — must add FireSuppressionPoints
   to *both* home and away branches. This is the precise gap Codex flagged P1 in
   M7-A; the plan calls it out explicitly and the loop smoke drives the real
   dispatcher (not a direct `try_start`).
2. **Layout `fire_zones` / `gameplay_slice_builder` / golden files / marker smoke** are
   entangled with the deleted timer model. Mitigation: leave the marker schema
   untouched and decouple behavior from it. This is the riskiest seam — verify the
   golden marker smoke still passes unchanged.
3. **`fire_state` deletion** touches the hazard-contract smoke, ADR-0005, the save
   snapshot, and any HUD/audio status lines that read `fire_state`. Sweep all
   references (grep `fire_state`) in one pass.
4. **Determinism:** ignition/spread/cascade are accumulator-based (no RNG) so smokes
   assert exact behavior; intensity is a static multiplier in B (no fire growth).

## Deferred follow-ups (not in B; surface before starting)

- **B2 — deliberate vent control + decompression danger** (intentional venting of an
  *intact* compartment; player pull, atmosphere loss, re-pressurization).
- **Fire consumes ship oxygen** (gradual per-room O₂ depletion; folds into B2).
- **`fire_extinguisher` + `hull_sealant` acquisition paths** (economy decision).
- **Recharge ports / fire-suppression points on derelicts** (B currently builds them
  home/lifeboat-side; away-ship parity is a follow-up).
- **Door-gated spread** (closing doors as containment — FTL's full spread model).
- **Live hull-damage sources #1–3** (shared with M7-A's deferred list).
