# Derelict-Side Fire — Design

**Date:** 2026-06-28
**Status:** Approved (brainstorm)
**Milestone:** M7-B follow-up (fire-suppression parity for boarded derelicts)
**Supersedes:** the M7-B "derelict-side fire deferred" note in `system_completion_audit.md` item 5

## Problem

The authoritative fire hazard (`FireSuppressionState`, ADR-0041) runs only on the
home/lifeboat ship. On a boarded derelict — the *primary* gameplay context — fire is
absent: four `away_from_start` early-return guards skip seeding, zone rendering,
suppression-point building, and the recharge port, and the fire model is **never ticked
on the away branch** (`_recompute_expanded_ship_systems` is called only in the home
branch of `_process`). The item economy (PR #45) made `fire_extinguisher`/`hull_sealant`
obtainable, which unblocks a real derelict fire loop.

This was held back as "remove two guards." It is not: there are **four** guards, the fire
tick is missing from the away branch entirely, and fire context reads home-ship models.
This design closes those gaps and adds a fairness pass.

## Scope

**In:** pre-seeded environmental fire on boarded derelicts; per-ship fire ownership with
sequential persistence (a revisited derelict remembers its fire); a power-gated recharge
port on the derelict; the away-branch fire tick; save/load; validation.

**Out (explicitly):** simultaneous *live* burning on unattended ships (fire spreading on a
derelict you are not aboard). That requires the coordinator to tick inactive ships —
oxygen, breaches, systems, and threats are all single-active too — and is a coordinator-wide
change that fire must not lead solo. Inactive-ship fire *freezes* (the existing home-fire
behavior while away) and resumes on revisit.

Also out: deliberate-vent control (B2), fire-consumes-oxygen, door-gated spread. Those
remain separately deferred M7-B follow-ups.

## Decisions (from brainstorm)

1. **Ignition source:** pre-seeded at build from derelict condition — self-contained,
   deterministic per seed. No live coupling to the derelict's systems for *new* ignitions.
2. **Recharge:** a port exists on the derelict but works only once the derelict's power
   system is restored (repair gate) — rewards engineering play, keeps charges scarce.
3. **Fairness scale:** scaled & capped (max 2–3 burning compartments at boarding); slow
   spread. Fire is **not** a default — most derelicts board fire-free.
4. **Ownership:** Approach B — fire state owned **per-ship** on `ShipInstance`, accessed via
   an `_active_fire_state()` helper mirroring the existing `_active_systems_manager()`. Gives
   sequential per-ship persistence; serves a future multi-derelict (sequential-boarding) world
   without over-building.

## Architecture & ownership

**Per-ship fire on `ShipInstance`** (`scripts/systems/ship_instance.gd`):
- `var fire = null  # FireSuppressionState`
- `func get_fire()` — lazy creator (mirrors `get_inventory()`/`get_hangar()`).
- `get_summary()` emits `"fire"` only when the model has burning compartments (same
  conditional pattern as `inventory`/`hangar`); `apply_summary()` restores it.

**Home fire stays on the coordinator** (`fire_suppression_state`, round-tripping via
`ship_systems_summary`) — untouched, so the proven home save/load path takes zero risk.
Precedent: `objective_controller` is documented as "null for the home ship, which uses the
coordinator's singleton loop."

**New helper** in `playable_generated_ship.gd`, mirroring `_active_systems_manager()`:

```gdscript
func _active_fire_state():
    if away_from_start and current_ship != null:
        return current_ship.get_fire()
    return fire_suppression_state
```

The fire functions switch from reading `fire_suppression_state` directly to
`_active_fire_state()`, and the four `away_from_start` early-return guards are **deleted**:
- `_build_fire_zones` (was guarded ~2678)
- `_build_fire_suppression_points` (was guarded ~2804)
- `_build_extinguisher_recharge_port` (was guarded ~2845)
- `_seed_fires_from_damage` (home seeding; stays home-only — derelict uses its own seeder)
- plus `_build_fire_context`, `_apply_fire_system_damage`, `_player_fire_intensity`,
  `_refresh_fire_zones`, and the tick read the active state.

`extinguisher_state` (the player's charges) stays coordinator-owned — it travels with the
player, correctly shared across ships.

## Seeding, presence gate & balance

New `_seed_derelict_fire()`, called once on the **fresh derelict build path only**
(alongside existing loot/repair/breach seeding when a new derelict is built) — never on the
save-restore path (restored fires come from the applied `"fire"` summary).

**Presence gate (deterministic, no RNG):**

```gdscript
const FIRE_PRESENCE_PERCENT: int = 15
var h := hash("%s:fire_presence" % _ship_seed(current_ship))
if (h % 100) >= FIRE_PRESENCE_PERCENT:
    return   # this derelict has no fire
```

Roughly 1 in 7 derelicts board with any fire.

**When present — scaled & capped:** candidate compartments = those whose mapped system
(`FIRE_COMPARTMENT_SYSTEM`) is damaged on the *derelict's* `systems_manager`, excluding
breached ones. Sort deterministically; ignite up to a cap:

```gdscript
var cap := 2 + (1 if derelict_condition_is_wrecked else 0)   # 2, or 3 at worst condition
```

A derelict boards with **0 fires (~85% of the time), or 1–3** when fire is present and
systems are damaged. If the gate says "present" but no mapped system is damaged, zero fires
seed — fire stays coherent with actual derelict damage, never appearing in pristine rooms.

**Derelict fire context** (`_build_fire_context` when away):
- `damaged_compartments = []` — pre-seeded only; no live re-ignition chain on the derelict.
- `ship_oxygen_present = true` — boarded derelict has breathable pockets; seeded fire
  sustains and spreads slowly per the model's existing spread logic.
- `powered_ratio = 0.0` — no auto-suppression on the derelict.
- breached compartments from the derelict hull if available, else `[]`.

## Power-gated recharge port & away-branch tick

The recharge port **builds on derelicts** (guard dropped), positioned via the already
away-aware `_distributed_room_positions()`, but is **dead until derelict power is restored**:

```gdscript
var derelict_powered := current_ship.systems_manager != null \
    and current_ship.systems_manager.is_operational("power")
extinguisher_recharge_port.set_powered(derelict_powered)
```

Board → port present but dead → ration brought/crafted charges → repair the derelict's power
system → port comes alive → recharge and finish clearing.

**The critical wiring — away-branch fire tick** (the "wire BOTH branches" guardrail). The
away branch of `_process` currently returns without the fire tick. Add, before its early
return, a block mirroring the home path but on the active state:

```gdscript
var afs = _active_fire_state()
if afs != null:
    if afs.tick(delta, _build_fire_context()):
        _refresh_fire_zones()
    _apply_fire_system_damage(delta)   # uses _active_systems_manager() -> derelict systems
if is_instance_valid(extinguisher_recharge_port):
    extinguisher_recharge_port.set_powered(derelict_powered)
```

`_apply_fire_system_damage` and `_build_fire_context` switch systems reads to
`_active_systems_manager()` so derelict fire degrades the derelict's systems and feeds the
player-vitals teeth that already run on the away branch (`_refresh_player_vitals`).
Interaction precedence for suppression points is already wired on the away branch, so manual
extinguish works the moment the points build.

## Save/load

Persistence rides on the existing `ShipInstance` round-trip. Because `visited_ships` is
serialized in the world snapshot keyed by `marker_id`, a half-cleared derelict left and
revisited returns exactly as left. Travel-home reverts `_active_fire_state()` to the
coordinator's home model; the derelict's fire stays parked on its retained `ShipInstance`.
No new snapshot plumbing.

## Validation

All registered in `docs/game/06_validation_plan.md`. Bundle currently `commands=58`; this
adds ~3–4 smokes (~61–62) and must end `SYNAPTIC_SEA REGRESSION PASS ... clean_output=true`.

1. **Pure-model seeding smoke** — `_seed_derelict_fire` determinism: same seed → same
   presence verdict and same ignited set; presence ~15% across a seed sweep; cap never
   exceeded; pristine-systems derelict seeds zero even when the gate says "present."
2. **`ShipInstance` fire round-trip smoke** — fire `get_summary()`/`apply_summary()`
   preserves the burning set (extends existing ship_instance persistence coverage).
3. **Main-scene away smoke** (with an `away_ticks=`-style assertion driving
   `away_from_start = true`) — on a seeded-fire derelict: fire zones + suppression points
   build; the model **ticks** while away (intensity/spread advance, system damage accrues on
   the derelict's manager); recharge port reads **unpowered** until the derelict power system
   is operational, then **powered**; manual extinguish via the real interaction path clears a
   compartment.
4. **Sequential-persistence smoke** — board derelict A (fire seeded), partially extinguish,
   travel home, revisit A, assert the remaining burning set is intact.

## Risks

- **Symmetric state on travel:** `_active_fire_state()` must select correctly on every fire
  read; a missed site renders/ticks the wrong ship's fire. Mitigated by routing all reads
  through the one helper and by the away smoke asserting derelict-side ticking.
- **Away-branch tick omission** is the historical regression class; the away smoke's
  `away_ticks` assertion is the guard.
- **`_ship_seed(current_ship)` availability** on the build path must be confirmed during
  planning (used by loot seeding already, so expected present).
