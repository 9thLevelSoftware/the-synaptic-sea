# M7-A · Life-support ambient atmosphere → vitals (with hull breaches as source)

Date: 2026-06-27
Status: **Design approved (verbal). Awaiting written-spec review before plan.**
Lane: M7 — Ship systems & sustenance infrastructure (`system_completion_audit.md`)
Sub-project: **A** of the M7 "give it teeth" decomposition (A spine / B fire-suppression / C sustenance)

## Background & why this exists

The system-completion audit grades M7 the **most hollow lane**: `power → propulsion →
crafting` is a real coupled core, but `shield`, `hull_integrity`, `life_support` (the
"expanded" model), `fire_suppression`, and `sustenance` are **HUD-only shadows** — ticked
every frame, output to `get_status_lines()` only, no live gameplay sink.

Two design decisions set the direction for the whole lane:

1. **On-foot survival only.** There is no "ship takes directed damage" combat layer. The ship
   is a base/vehicle, not a combatant. → `shield_state` has no role and is **cut**.
2. **"Give it teeth" (deep sim).** The remaining shadows are promoted into real on-foot
   survival mechanics rather than deleted. The lane is decomposed into three independent
   sub-projects, each with its own spec → plan → build cycle:
   - **A (this spec):** life-support ambient atmosphere fails (hull breaches + power loss) and
     drains the player's vitals while aboard the hub.
   - **B (deferred):** fire-suppression becomes the player's tool against the real `fire_state`
     hazard (requires reconciling `fire_state`'s timed auto-cycle with an ignite/extinguish
     model).
   - **C (deferred):** sustenance passive production (`hydroponics`/`synthesizer`/
     `water_recycler`) feeds player hunger/thirst, including `water_liters → thirst`.

A is built first: highest on-foot payoff and it establishes the "expanded model produces a
vitals-context channel" pattern that B and C reuse.

## Goal (sub-project A)

Close this loop:

```
hull breaches (pre-damaged at run start)
   → life-support ambient atmosphere degrades (gated by power-allocation ratio)
   → drains the player's vitals while aboard the hub
   → player must keep power routed to life support AND seal breaches to survive
```

"Suffocate in your own base if you neglect the ship." This is the headline deep-sim mechanic
the lane was missing.

## Non-goals (explicitly deferred)

- Fire-suppression ↔ `fire_state` reconciliation (sub-project B).
- Sustenance passive production and `water_liters → thirst` (sub-project C).
- Live hull-damage **sources** #1–3: biomatter-web stress (a tick), hazard cascades
  (fire/arc weakening a compartment), derelict/event-driven damage. A ships source **#4 only**
  (pre-damaged compartments at run start); the mutation interface is designed so #1–3 plug in
  later with no rework.
- Any ship-to-ship / piloting combat.

## Current-state facts (verified in code this pass)

- **Coordinator:** `scripts/procgen/playable_generated_ship.gd`.
  - `_recompute_expanded_ship_systems(delta)` (~1321) ticks the expanded models.
    `life_support_expanded_state.tick` (~1340) already receives
    `{powered_ratio, breach_count, recycled_water}` — `breach_count` already comes from
    `hull_integrity_state.get_breach_count()`. The input side of the spine is *already wired*;
    only the **output side (→ vitals)** is missing.
  - `shield_state.tick` (~1334) — to be removed.
  - Vitals context is assembled at ~4211–4226 and consumed by `vitals_state.tick`. This block
    already feeds `radiation_health_drain`, `temperature_thirst_mult`,
    `status_stamina_recovery_mult`, `moving`. **This is the wiring point for the new channel.**
  - `away_from_start` (bool) is the existing "aboard hub vs. away on a derelict" signal;
    `radiation_state`, `body_temperature_state`, and `sanity_state` all gate on it (~4228–4239).
- **`vitals_state.gd`** `tick(delta, context)` reads context channels and applies drains. Adding
  a new `atmosphere_health_drain` channel mirrors the existing `radiation_health_drain` exactly
  (added to `h_drain`).
- **`life_support_state.gd`** (`class_name LifeSupportState`) already models `oxygen_percent`,
  `co2_percent`, `temperature_c`, `water_liters`, gated by `powered_ratio` and `breach_count`.
  It currently exposes only `is_nominal()` + `get_status_lines()`. It needs read-only accessors.
- **`hull_integrity_state.gd`** (`class_name HullIntegrityState`) has `damage_compartment()`,
  `seal_compartment()`, `get_breach_count()`, `average_integrity()`. Its only live caller today
  is `force_hull_breach_for_validation()` (test seam). It is configured from a JSON config path
  at run start.
- **Save/load:** the expanded-systems summaries live in `_expanded_ship_systems_summary()`
  (~1369) for the HUD; they are **NOT** in `RunSnapshot.SUMMARY_FIELDS` (currently 26 fields).
  So hull-breach and ambient-atmosphere state does **not** survive save/load today. Because A
  makes them gameplay-affecting, A adds `hull_integrity_summary` and `life_support_summary` to
  the snapshot so a loaded save preserves the threat (count 26 → 28). `shield` is cut, so it is
  never added.

## Architecture / data flow (sub-project A)

No new model classes. Wire existing ones via read-only accessors + a ~3-line coordinator change.

```
HullIntegrityState
  • run-start config: some compartments start damaged/breached (source #4)
  • damage_compartment() remains the single mutation entry point (future sources #1–3)
        │ get_breach_count()
        ▼
LifeSupportState.tick(delta, {powered_ratio, breach_count, recycled_water})   [already wired]
  • NEW get_health_drain_per_second() -> float   (suffocation: low O2 / high CO2)
  • NEW get_thirst_multiplier() -> float          (ambient temperature extreme)
        │
        ▼  (coordinator vitals-context block ~4221, gated by `not away_from_start`)
VitalsState.tick(delta, {
    radiation_health_drain, temperature_thirst_mult, status_stamina_recovery_mult, moving,
    atmosphere_health_drain  ← NEW (added to health drain, same pattern as radiation),
})
```

### Component contracts

**`LifeSupportState` (additions — pure, no scene access):**
- `get_health_drain_per_second() -> float`
  Returns a per-second health drain > 0 when the ambient atmosphere is unsafe, scaled by how
  far O2/CO2 are past their danger thresholds; 0.0 when nominal. Tunables (thresholds, max
  drain) are config fields with defaults, exposed via `get_summary()` so smokes can assert
  them. Suggested shape: drain ramps from 0 at the safe threshold to a max as O2 → 0 / CO2 →
  100; O2 and CO2 contributions take the max (the worse of the two governs), not the sum, to
  keep tuning legible.
- `get_thirst_multiplier() -> float`
  Returns ≥ 1.0 when `temperature_c` is outside a comfort band, 1.0 inside it. Composes
  multiplicatively with `body_temperature_state.get_thirst_multiplier()` in the coordinator.

**`HullIntegrityState`:**
- No new methods required. Confirm the run-start config can carry pre-damaged compartments
  (`health` < 1.0 and/or `breach_open: true`). If the existing config file is all-nominal, add
  the pre-damaged entries to the config data (not the code). `damage_compartment()` stays the
  single mutation seam; document the three future sources that will call it.

**Coordinator (`playable_generated_ship.gd`):**
- In the vitals-context block (~4221), compute:
  ```
  var atmo_drain := 0.0
  var atmo_temp_mult := 1.0
  if life_support_expanded_state != null and not away_from_start:
      atmo_drain = life_support_expanded_state.get_health_drain_per_second()
      atmo_temp_mult = life_support_expanded_state.get_thirst_multiplier()
  ```
  Add `"atmosphere_health_drain": atmo_drain` to the context dict, and fold `atmo_temp_mult`
  into the existing `temp_mult` (`temp_mult *= atmo_temp_mult`).
- The gate `not away_from_start` ensures the hub atmosphere only bites while aboard the hub. On
  derelicts the existing oxygen/radiation/body-temp hazards own the danger.

### Layering: ambient vs. personal oxygen (no double-count by design)

`oxygen_state` (personal, breach-zone-local, fast, position-driven) and `life_support_state`
(ambient, ship-wide, slow, power/breach-driven) are **distinct layers that compose**, not
duplicates. A hub breach can engage both; that is intended (a breach is locally and
ship-wide bad), but A keeps the ambient drain tuned gently so a single breach aboard the hub
is survivable while you reach the power console / seal kit. Final numbers are set during the
balance step of implementation, asserted by the smokes below.

## Cutting `shield_state`

Remove every reference (no on-foot role):
- `scripts/systems/shield_state.gd` (+ `.uid`).
- Coordinator: `ShieldStateScript` preload (~94), `shield_state` field (~337), instantiation +
  `configure` (~1307–1308), `tick` (~1334–1335), and the `shield_state_summary` line in
  `_expanded_ship_systems_summary()` (~1376).
- Its config block (`tuning.get("shields", …)`) in the ship-systems tuning data.
- Its validation smoke (and its entry in `06_validation_plan.md` + the regression bundle).
- Any HUD/status consumer that renders the shield line.
- `shield_state` is **not** in `RunSnapshot`, so the snapshot count is unaffected by the cut.

Grep `shield` across the repo as the completeness check; remove all live references, leaving no
dangling reads.

## Save/load

Add to `RunSnapshot.SUMMARY_FIELDS` (and `to_dict` / `from_dict`):
- `hull_integrity_summary` (from `hull_integrity_state.get_summary()`)
- `life_support_summary` (from `life_support_expanded_state.get_summary()`)

So a loaded save preserves breach state and ambient atmosphere — without this, loading silently
heals the ship and erases the threat. Count 26 → 28. The coordinator must apply these on load
via the models' existing `apply_summary()`. The save-load service smoke and run-snapshot model
smoke that assert the summary count must be updated to 28.

## Testing (the definition of done)

1. **Pure-model smoke — `life_support_state` teeth.** New or extended smoke asserting:
   - `get_health_drain_per_second()` is 0.0 when atmosphere is nominal.
   - It becomes > 0.0 once O2 drops below / CO2 rises above the danger threshold, and increases
     monotonically as they worsen.
   - Driving `tick` unpowered with `breach_count > 0` degrades the atmosphere faster (breach
     multiplier), raising the drain, vs. `breach_count == 0`.
   - `get_thirst_multiplier()` is 1.0 in the comfort band and > 1.0 outside it.
2. **Main-scene smoke — `main_playable_life_support_vitals_smoke.gd`.** With a pre-damaged hull
   and life support unpowered:
   - player health measurably drops over N ticks **while aboard** (`away_from_start == false`);
   - restoring power to life support (+ sealing breaches) halts the health drain;
   - **no atmosphere health drain while `away_from_start == true`** (away on a derelict).
3. **Regression bundle (`docs/game/06_validation_plan.md`):** add both new smokes with their
   PASS markers; **remove** the shield smoke entry and its expected marker; update the command
   count. Update the save-load / run-snapshot summary-count assertions to 28. Run the full
   bundle to `SARGASSO REGRESSION PASS` with clean output (only the allowlisted baseline noise).

## Files touched (anticipated)

- `scripts/systems/life_support_state.gd` — add two read-only accessors + tunable fields.
- `scripts/systems/hull_integrity_state.gd` — no code change expected; verify config-driven
  pre-damage. Config data file gains pre-damaged compartment entries.
- `scripts/systems/shield_state.gd` — **deleted.**
- `scripts/systems/run_snapshot.gd` — add two summary fields (26 → 28).
- `scripts/procgen/playable_generated_ship.gd` — vitals-context wiring (~4221); remove shield
  wiring; persist/restore hull + life-support summaries.
- `scripts/validation/` — new life-support model smoke + `main_playable_life_support_vitals_smoke.gd`;
  delete the shield smoke.
- `docs/game/06_validation_plan.md` — markers/bundle/count updates.
- `docs/game/system_completion_audit.md` — re-grade M7 life-support/hull/shield rows after A lands.

## Open questions for written-spec review

- **Config home for pre-damaged compartments:** reuse the existing hull-compartments config file
  (`HULL_COMPARTMENTS_CONFIG_PATH`) with some entries pre-breached, vs. a run-setup parameter?
  Recommendation: the config file (simplest, deterministic, matches source #4 framing).
- **Should low ambient O2 also gate passability** (like `oxygen_state` blocks corridors) or
  **only drain vitals**? Recommendation: drain only for A; passability stays the personal
  `oxygen_state`'s job. Revisit if playtest wants ship-wide lockout.
