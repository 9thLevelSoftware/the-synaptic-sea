# ADR-0041: Fire as a Persistent, Compartment-Keyed Hazard

## Status

Accepted

## Context

Through Gate 2, fire was `FireState` (`scripts/systems/fire_state.gd`): a single
layout-room zone on a fixed `CLEARED ↔ BURNING` phase timer (ADR-0005's timer-hazard
contract), toggling collision/passability on a side corridor. The player could only
*wait it out* — there was no interaction, no consequence, and no cause. In parallel,
`FireSuppressionState` (`scripts/systems/fire_suppression_state.gd`) modeled an
abstract per-compartment `active_fires` dictionary that ignited only from a validation
seam and emitted HUD text. The system-completion audit graded suppression 🔴 "a HUD
shadow of the real fire hazard": two parallel, unconnected fire models, neither of
which closed a gameplay loop.

The M7-B brainstorm (design spec
`docs/superpowers/specs/2026-06-27-m7b-fire-suppression-loop-design.md`) chose to
collapse both into **one authoritative, compartment-keyed, persist-until-extinguished
fire model** that the player actually fights, FTL-style, with fire as a *symptom of
unrepaired system damage* rather than a timer cycle. This is a deliberate departure
from the ADR-0005 phase-timer cyclic contract for fire, so it needs its own ADR.

## Decision

Retire `FireState`. Promote `FireSuppressionState` to the **single authoritative fire
model**: a pure `RefCounted` (no scene tree, per the model/node rule) that holds
per-compartment fires which **persist until extinguished**. Fire **joins oxygen as a
non-timer hazard** — it owns no `PhaseTimer` and is no longer cyclic. The ADR-0005
timer-hazard set is now `ElectricalArcState` only.

### Compartment-keyed, not room-keyed

All fire couplings (fire ↔ hull breach, fire ↔ ship system, fire spread, arc → fire
cascade) collapse onto the **4 logical compartments** (`bridge`, `engineering`,
`hydroponics`, `cargo`) already shared by `HullIntegrityState` and
`FireSuppressionState`. The coordinator renders **one passable fire-zone `Area3D` per
burning compartment** (visual + overlap trigger, *no* collision block — the player
must walk in to fight the fire), positioned with the same `_distributed_room_positions()`
the breach seal points use, refreshed whenever the burning set changes. Fire no longer
blocks passability — this supersedes REQ-010's impassable-side-corridor placement
constraint (see `05_requirements.md`).

### Ignition is a symptom of damage, with re-ignition

Fire is never random. A compartment ignites only when its mapped ship system has a
non-functional (damaged) subcomponent **and** the compartment has oxygen (not vented),
plus the electrical-arc cascade path. Crucially, fire **re-ignites until the system is
repaired** (or the compartment is vented): extinguishing is temporary relief; you must
treat the cause. Compartments that are not damaged, or are vented, decay their ignition
accumulator toward zero.

Compartment → system map (constant in the coordinator):

```
bridge       -> navigation
engineering  -> power          (power is every other system's dependency: cascades)
hydroponics  -> life_support
cargo        -> (none; storage, pre-breached/vacuum, never ignites)
```

### Three extinguish paths

1. **Manual extinguisher (full player loop).** A `FireSuppressionPoint` (`Area3D`,
   modeled on `BreachSealPoint`) per burning compartment. `try_start(player)` succeeds
   only when the player is in range, the compartment `is_burning`, inventory holds the
   `fire_extinguisher` tool, and `ExtinguisherState.has_charge_for_use()`. Completing
   the channel consumes one charge, extinguishes that compartment, and grants repair
   XP. The reusable `fire_extinguisher` has a depletable **charge**
   (`ExtinguisherState`); an `ExtinguisherRechargePort` refills it slowly **only while
   ship power is active and a player is in range**.
2. **Powered auto-suppression.** When `powered_ratio ≥ power_threshold` and
   `suppressant_units > 0`, each active fire's intensity is reduced by
   `suppression_rate_per_second * delta`; suppressant drains; fires that hit 0 clear.
3. **Breach / vacuum vent.** Any fire in a breached (vacuum) compartment is removed
   immediately at no cost, and a breach blocks ignition there. Cheap coupling reusing
   M7-A `breach_open`; deliberate-vent control is deferred to B2.

### Deterministic tick (no RNG)

The coordinator assembles a context dict and calls `fire_suppression_state.tick(delta,
context)` with `powered_ratio`, `ship_oxygen_present`, `breached_compartments`,
`damaged_compartments`, `arc_arcing`, and `arc_compartment`. The model runs a fixed
5-step order: (1) vent-extinguish, (2) powered auto-suppression, (3) spread, (4)
ignition-from-damage / re-ignition, (5) arc cascade. Spread, ignition, and cascade are
**accumulator-based** (`spread_progress`, `ignition_progress`, `cascade_progress`):
each adds `rate * delta * intensity` per frame and ignites at ≥ 1.0, resetting the
accumulator. `has-oxygen` for a compartment = `ship_oxygen_present ∧ cid ∉
breached_compartments`; active fires whose compartment loses oxygen die. This
determinism lets smokes assert exact behavior. `tick` returns `bool` (burning set
changed) so the coordinator can refresh scene zones.

### Teeth: vitals + ship system

An active fire damages **both** the player and the ship:

- **Vitals:** standing in a burning fire zone adds `FIRE_HEALTH_DRAIN_PER_SECOND *
  intensity` to the vitals tick context (`fire_health_drain` channel, mirroring M7-A's
  `atmosphere_health_drain`).
- **Ship system:** each tick, every burning compartment with a mapped system loses
  `FIRE_SYSTEM_DAMAGE_PER_SECOND * intensity * delta` subcomponent health via
  `ship_systems_manager.damage_system()`.

### Save / load

No top-level `SUMMARY_FIELDS` change. `fire_suppression_summary` already round-trips
nested inside `ship_systems_summary`; its payload is extended (`active_fires`,
`suppressant_units`, accumulators, tunables) and `extinguisher_summary` joins the same
nested summary. The retired top-level `fire_summary` is dropped from new snapshots and
ignored if present in a legacy save (no error).

## Consequences

Positive:

- Fire becomes a real, fightable loop with cause (system damage), teeth (vitals + ship
  system), and three counters — closing the audit's 🔴 hollow.
- One authoritative fire model instead of two parallel ones; all fire couplings live on
  the 4-compartment key shared with hull and suppression.
- Determinism (accumulators, static intensity) keeps the new behavior fully smoke-testable.

Negative / tradeoffs:

- Fire diverges from the ADR-0005 timer-hazard contract; `hazard_contract_smoke.gd` now
  asserts only `ElectricalArc` under the timer contract (`models=2 phase_timer_owners=1`).
- Intensity is a static multiplier in B (no fire growth); spread is ungated by doors.
- The `fire_extinguisher` and `hull_sealant` items exist but have no acquisition path
  yet (same staging as M7-A).

Deferred follow-ups (not in B):

- **B2** deliberate-vent control + decompression danger.
- Fire **consumes** ship oxygen (gradual per-room O₂ depletion).
- `fire_extinguisher` / `hull_sealant` acquisition paths (economy decision).
- Fire-suppression points and recharge ports on derelicts (B is home/lifeboat-side only).
- Door-gated spread (closing doors as containment — FTL's full spread model).

## Affected documents

- `docs/game/adr/0005-multi-hazard-architecture.md` — amended: fire retired from the
  timer-hazard set; timer hazards are now `ElectricalArc` only.
- `docs/game/05_requirements.md` — REQ-010's "non-critical side room" impassable-zone
  placement constraint marked superseded by this ADR (fire no longer blocks passability).
- `docs/game/features/hazard_variety.md` — Gate 2 `FireState` implementation superseded
  by M7-B.
- `docs/game/06_validation_plan.md` — `fire_state_smoke` retired; six new/updated fire
  smokes registered; `commands` bumped to 48.
- `docs/game/system_completion_audit.md` — `fire_suppression_state` re-graded 🔴 → 🟢.

## Verification

- `docs/game/adr/0041-fire-as-persistent-compartment-hazard.md` exists and is Accepted.
- `scripts/systems/fire_state.gd` is deleted; `FireSuppressionState` is the only fire model.
- `scripts/validation/fire_suppression_state_smoke.gd` asserts ignite / persist /
  manual extinguish / powered auto-suppression / vent-extinguish / spread / re-ignition
  (and that repair/vent stops it) / arc cascade / round-trip.
- `scripts/validation/main_playable_fire_loop_smoke.gd` drives the full live loop
  (ignite → teeth → manual extinguish → re-ignite → repair stops → recharge).
- `hazard_contract_smoke.gd` no longer asserts fire under the timer-hazard contract
  (`HAZARD CONTRACT PASS models=2 phase_timer_owners=1 wrong_kind_rejected=2 configure_dict=2`).
- Full regression bundle passes with `SYNAPTIC_SEA REGRESSION PASS commands=48 clean_output=true`.
