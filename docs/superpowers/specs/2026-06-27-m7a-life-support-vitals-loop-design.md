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
- **Save/load (CORRECTED after tracing the code):** the expanded-systems summaries are NOT
  top-level `RunSnapshot.SUMMARY_FIELDS` (which stays 26), **but they already round-trip** —
  the snapshot builder merges every key of `_expanded_ship_systems_summary()` *into*
  `snapshot.ship_systems_summary` (~5381–5382), and the loader restores them via
  `life_support_expanded_state.apply_summary(...)` (~5641) and
  `hull_integrity_state.apply_summary(...)` (~5643). So hull-breach + ambient-atmosphere state
  **survive save/load today, nested under `ship_systems_summary`**. → A needs **no** new
  `SUMMARY_FIELDS` and the count stays 26. Cutting `shield_state` removes `shield_state_summary`
  from `_expanded_ship_systems_summary()`, which automatically drops it from the nested persist;
  there is no shield restore call to remove.

## Planning-stage refinements (decided during plan authoring, approved)

Two decisions made the loop actually playable; both extend (do not contradict) the approved design:

1. **Breaches leak atmosphere even while powered.** The existing `LifeSupportState.tick` only
   lets `breach_count` amplify drain in the *unpowered* branch — so a pre-damaged hull (source #4)
   would be inert while power is on, and there would be no "race to seal." A adds a per-breach
   atmosphere leak that applies in the **powered** branch too (reduces/overcomes online recovery),
   so unsealed breaches degrade O2/CO2 until sealed. Existing `life_support_state_smoke` assertions
   use `breach_count == 0` (recover-online case), so they stay green; the new behavior is additive
   and gated on `breach_count > 0`.

2. **A player-facing breach-seal interaction (`BreachSealPoint`).** Verified there is **no** live
   caller of `HullIntegrityState.seal_compartment()` except a test seam, and no per-compartment
   repair interaction exists. A adds a `BreachSealPoint` interactable **modeled on the existing
   `RepairPoint`** (`scripts/interaction/repair_point.gd`): the player approaches a breached
   compartment, interacts (consuming a sealant/repair material via `inventory_state`, optionally
   skill-gated like RepairPoint), and on completion the coordinator calls
   `hull_integrity_state.seal_compartment(compartment_id, amount)` → breach closes (`health ≥ 0.75`)
   → `breach_count` drops → atmosphere recovers. This realizes source #4's "racing to seal."

## Architecture / data flow (sub-project A)

No new *model* classes (one new *interaction* node — `BreachSealPoint`). Wire the existing models
via read-only accessors + the breach-leak refinement + a small coordinator change.

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

Remove the **model and its direct wiring** (no on-foot role):
- `scripts/systems/shield_state.gd` (+ `.uid`).
- Coordinator: `ShieldStateScript` preload (~94), `shield_state` field (~337), instantiation +
  `configure` (~1307–1308), `tick` (~1334–1335), and the `shield_state_summary` line in
  `_expanded_ship_systems_summary()` (~1376). Removing that line auto-drops shields from the
  nested save persist; there is no shield restore call to remove.
- The `"shields"` block in `data/ship_systems/subsystem_tuning.json` (dead config once the model
  is gone).
- No HUD consumer reads `shield_state_summary` (verified — grep found none outside the model and
  coordinator), so no HUD change is needed.
- **There is no dedicated shield validation smoke.** `shield` appears only inside
  `power_grid_state_smoke.gd` as a power-allocation channel (see below).

**Deliberately LEFT in place (flagged follow-up, not silently ignored):** `"shields"` is also a
**power-grid allocation channel** — hardcoded in `power_grid_state.gd` (`DEFAULT_SUBSYSTEM_ORDER`),
present in `data/ship_systems/power_budget_tables.json`, and asserted by `power_grid_state_smoke.gd`.
Removing it would re-balance the power-allocation ratios across **all** subsystems and ripple into
the working 🟢 power grid + its smoke + propulsion/life-support thresholds — out of scope for a
life-support→vitals loop and a real regression risk. A leaves the orphaned `"shields"` power
channel intact (it allocates power to nothing now) and records it as an explicit follow-up: a
later card can either repurpose the channel or remove it together with a deliberate power
re-balance. Grep `shield` after the cut to confirm the only remaining references are the power
channel (`power_grid_state.gd`, `power_budget_tables.json`, `power_grid_state_smoke.gd`) plus the
incidental `material_definitions.json` / `recipe_definitions.json` item data (a craftable shield
item, unrelated to the cut model).

## Save/load

**No change required — hull + life-support already persist.** Tracing the coordinator confirmed
the snapshot builder merges `_expanded_ship_systems_summary()` into `snapshot.ship_systems_summary`
(~5381–5382) and the loader restores `hull_integrity_state` / `life_support_expanded_state` via
their `apply_summary()` (~5641, ~5643). Because A only adds **read-only accessors** to those
models (no new persisted fields), the existing nested round-trip already preserves breach state
and ambient atmosphere across save/load. `RunSnapshot.SUMMARY_FIELDS` stays at **26**; the
save-load-service smoke's `summary_count == 26` assertion is unchanged.

Cutting `shield_state` removes `shield_state_summary` from `_expanded_ship_systems_summary()`,
which automatically removes it from the nested persist. No shield restore call exists, so nothing
on the load path needs changing.

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
3. **Regression bundle (`docs/game/06_validation_plan.md`):** add the new main-scene smoke with
   its PASS marker (the life-support model teeth are folded into the existing
   `life_support_state_smoke.gd`, already in the bundle); update the command count for the added
   main-scene smoke. There is no dedicated shield smoke to remove (shields is only exercised
   inside `power_grid_state_smoke.gd`, which is left intact — see the shield-cut section). The
   save-load summary count stays **26** (unchanged). Run the full bundle to
   `SARGASSO REGRESSION PASS` with clean output (only the allowlisted baseline noise).

## Files touched (anticipated)

- `scripts/systems/life_support_state.gd` — add two read-only accessors + tunable fields.
- `scripts/systems/hull_integrity_state.gd` — no code change expected; verify config-driven
  pre-damage works.
- `data/ship_systems/hull_compartments.json` — pre-damage some compartments (source #4).
- `data/ship_systems/subsystem_tuning.json` — add `life_support` threshold tunables for the new
  accessors if not derivable from existing fields; remove the dead `"shields"` block.
- `scripts/systems/shield_state.gd` — **deleted** (+ `.uid`).
- `scripts/procgen/playable_generated_ship.gd` — vitals-context wiring (~4221); remove shield
  model wiring. **No save/load change** (hull + life-support already round-trip nested in
  `ship_systems_summary`).
- `scripts/validation/life_support_state_smoke.gd` — extend with the new-accessor assertions.
- `scripts/validation/main_playable_life_support_vitals_smoke.gd` — **new** main-scene smoke.
- `docs/game/06_validation_plan.md` — add the new main-scene smoke marker + command count (no
  shield smoke exists to remove; save-load count stays 26).
- `docs/game/system_completion_audit.md` — re-grade M7 life-support/hull/shield rows after A lands.

## Open questions for written-spec review

- **Config home for pre-damaged compartments:** reuse the existing hull-compartments config file
  (`HULL_COMPARTMENTS_CONFIG_PATH`) with some entries pre-breached, vs. a run-setup parameter?
  Recommendation: the config file (simplest, deterministic, matches source #4 framing).
- **Should low ambient O2 also gate passability** (like `oxygen_state` blocks corridors) or
  **only drain vitals**? Recommendation: drain only for A; passability stays the personal
  `oxygen_state`'s job. Revisit if playtest wants ship-wide lockout.
