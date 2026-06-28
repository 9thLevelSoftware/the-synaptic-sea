# Sanity Hallucination System — Design

Date: 2026-06-28
Status: Approved (brainstorm complete; ready for implementation plan)
Related: REQ-SV-002 (sanity), ADR-0042 (to be authored — hallucinations as sanity teeth),
ADR-0005 (multi-hazard architecture — hallucinations are NOT a phase-timer hazard, noted for contrast),
`docs/game/system_completion_audit.md` (M1 sanity row: 🟡 cosmetic → 🟢 closed-loop on completion).

## Problem

`SanityState` (`scripts/systems/sanity_state.gd`) is fully functional as a meter — it drains
at 1.5/s outside safe zones, recovers at 3.0/s inside, and publishes
`perception_pressure_active = sanity < 40` in its summary. But **nothing consumes that flag**.
`PlayerVitalsModel._sanity_lines()` renders two HUD strings ("Sanity: N% CRITICAL" and
"PERCEPTION PRESSURE -> hallucination risk"); no mechanical system reacts. The HUD literally
promises "hallucination risk" that does not exist. Sanity is cosmetic.

This design gives sanity **mechanical teeth**: low sanity makes the player's perception
unreliable through four manifestation channels, with escalating consequences, driven by one
deterministic model and isolated from real combat.

## Product decisions (locked during brainstorm)

- **Forms:** all four channels — phantom threats, false sensor/HUD, environmental cues, screen FX.
- **Teeth:** indirect (wasted resources on reaction, misdirection) **plus** a direct penalty
  below a deeper threshold.
- **Counterplay:** commit-to-reveal (attacking or closing to melee dissipates a phantom, wasting
  the action) + an audio tell (phantoms make no real positional combat sound). No dedicated
  "focus" action; no trusted-instrument oracle. Recovery via raising sanity (safe zones /
  consumables) clears all manifestations.
- **Architecture:** a separate `HallucinationManager` Node owns all four channels; phantom
  threats are its own nodes that **reuse** `ThreatManager`'s placeholder visual via an extracted
  shared renderer. Real combat math is never touched by phantom-exclusion branches.

## Tiers

Sanity thresholds drive a single integer tier. `PERCEPTION_PRESSURE_THRESHOLD = 40` already
exists; 25 and 15 are new and tunable.

| Tier | Name | Sanity | Manifestations (cumulative) | Direct teeth |
|------|------|--------|------------------------------|--------------|
| 0 | Stable | ≥ 40 | none | none |
| 1 | Unease | < 40 | environmental cues + mild screen FX (vignette pulse) | none |
| 2 | Distortion | < 25 | + false sensor/HUD (phantom blips, brief wrong readouts) + stronger FX (desaturation/warp) + occasional phantom threat | none |
| 3 | Breakdown | < 15 | + frequent phantom threats + heavy FX | stamina-recovery penalty + slow health drain |

Manifestations never fire while `in_safe_zone` is true, regardless of tier (the hub/lifeboat is
a refuge; recovery happens there). Tiers are derived purely from sanity each tick — no hysteresis
in v1 (tunable later if flicker at the boundary is a problem).

## Components

### 1. `HallucinationDirector` — pure model (`scripts/systems/hallucination_director.gd`)

`extends RefCounted`. The brain. No scene-tree access.

State:
- `seed: int`, `step: int` (deterministic clock)
- `active_events: Array[Dictionary]` — each `{ id:int, kind:String, payload:Dictionary, ttl:float }`
  where `kind ∈ {"phantom", "hud", "ambient", "fx"}`
- tunables: per-tier spawn interval per kind, max concurrent per kind, ttl ranges, tier thresholds,
  teeth values.

Methods:
- `configure(config: Dictionary) -> void` — load tunables + seed; clear state.
- `tick(delta: float, context: Dictionary) -> bool` — context keys: `sanity:float`,
  `in_safe_zone:bool`, `anchor_positions:Array[Vector3]` (candidate world spots, supplied by the
  coordinator), `real_threat_positions:Array[Vector3]` (to bias/avoid placement). Logic:
  1. compute tier from sanity; if tier 0 or in_safe_zone → expire all events, return.
  2. decrement `ttl` on active events; drop expired.
  3. for each kind enabled at the current tier, accumulate a per-kind spawn timer; when it
     fires and the kind is below its max-concurrent cap, append a new event whose position is
     chosen **deterministically** via `_pick_index(seed, step, kind) % anchor_positions.size()`.
  4. `step += 1`; return whether anything changed.
- `get_active_events(kind := "") -> Array` — all, or filtered by kind.
- `get_tier() -> int`
- `get_direct_teeth() -> Dictionary` — `{ health_drain_per_second:float, stamina_recovery_mult:float }`
  (zeros above tier 3).
- `get_summary()/apply_summary()` — round-trip tunables + seed + step (for the pure-model smoke
  and the model-contract convention). **Not** wired into `RunSnapshot` (see Save/Load).

Determinism: `_pick_index` is a pure integer hash (e.g. a small LCG seeded by
`seed * 1103515245 + step` mixed with a per-kind salt), **never** `randi()`/`Math.random`.
Same `(seed, step, inputs)` ⇒ identical event stream. This mirrors the RNG-free accumulator
approach used by the fire and encounter systems.

### 2. `HallucinationManager` — scene driver (`scripts/systems/hallucination_manager.gd`)

`extends Node3D`. The hands. Holds a `HallucinationDirector`; ticked each frame by the coordinator
with the built context. Reconciles the director's active events against rendered state per channel:

- **Phantom threats:** for each `kind == "phantom"` event, ensure a phantom node exists at its
  position (built via the shared renderer, see #3), tagged `is_phantom = true`; free phantom nodes
  whose event expired. Phantoms are tracked in **this manager's own list**, never in
  `ThreatManager`. They never drain vitals. On player attack at a phantom, or player within melee
  proximity, the phantom dissipates (see Teeth).
- **False sensor/HUD:** publishes phantom blips / transient wrong readouts into a dedicated
  `get_hallucinated_status_lines()` / blip feed that the tracker/HUD merges (additive — does not
  overwrite real readouts beyond the transient window).
- **Ambient cues:** fires `audio_manager.play_sfx(...)` for whisper/creak events (reuses the audio
  seam; may add 1–2 new SFX ids).
- **Screen FX:** drives a `CanvasLayer` + `ColorRect` shader overlay whose intensity tracks the
  tier (vignette pulse → desaturation/warp → heavy).

`clear_all()` — frees all phantom nodes, clears HUD lies, fades FX. Called when the director
reports tier 0 / safe zone.

### 3. Shared placeholder renderer (refactor of `ThreatManager`)

Extract the visual-construction body of `ThreatManager._spawn_placeholder` into a reusable helper
(`scripts/tools/threat_placeholder_renderer.gd`, e.g. `static func build_placeholder(archetype_id, color) -> Node3D`).
`ThreatManager._spawn_placeholder` calls it (behavior-identical refactor — **the only change to
real combat code**). `HallucinationManager` calls it for phantoms so they are visually
indistinguishable from real threats.

## Teeth

- **Indirect (all hallucination tiers):**
  - *Wasted action:* attacking a phantom routes through the **real** attack dispatcher, but the
    coordinator detects the target is a phantom (`HallucinationManager.is_phantom_at(target)`),
    spends the weapon's ammo/charge via the existing cost path, dissipates the phantom, and deals
    **no** damage. The player paid for a swing at nothing.
  - *Misdirection:* phantoms are placed at real anchor positions (optionally biased near real
    threats), so reacting to a fake can pull the player toward genuine danger. Emergent; no extra
    code beyond placement.
- **Direct (tier 3, sanity < 15):** the coordinator reads `director.get_direct_teeth()` and feeds
  two **new** context keys into `vitals_state.tick()` — `sanity_health_drain` (slow) and
  `sanity_stamina_recovery_mult` (< 1.0 penalty) — following the exact pattern of the existing
  `radiation_health_drain` / `fire_health_drain` / status-multiplier channels. Even a perfectly
  disciplined player who ignores every phantom still pays at the extreme.

Phantoms **never** apply `tick_threats`-style vitals drain; the only health cost from hallucination
is the tier-3 direct drain.

## Counterplay & tells

- **Commit-to-reveal:** a phantom dissipates when attacked (the hit passes through) or when the
  player closes to melee proximity. The cost (wasted attack) is the price of checking.
- **Audio tell:** phantoms emit no real positional combat sound. The ambient and false-HUD
  channels are independent, so the scanner is **not** a reliable oracle — consistent with the
  "no trusted instrument" decision.
- **Recovery:** raising sanity ≥ 40 (safe zone dwell or a sanity consumable) triggers
  `clear_all()`; entering a safe zone clears immediately.

## Data flow

```
SanityState.perception_pressure_active / sanity
        |
   coordinator builds context:
     { sanity, in_safe_zone, anchor_positions (reuse _distributed_room_positions /
       lifeboat-local, as fire does), real_threat_positions }
        |
   HallucinationDirector.tick(delta, context)  -> active events + tier + teeth
        |
   HallucinationManager renders 4 channels       coordinator applies get_direct_teeth()
   (phantom/hud/ambient/fx)                       into vitals_state.tick() context keys
```

The manager attaches to the active ship the same way `ThreatManager` / fire zones do
(home/lifeboat or current derelict), so phantom world positions are valid in the active frame.
Hallucinations manifest wherever the player is when sanity is low (predominantly away on
derelicts, since safe zones recover sanity).

## Save / load

**No new `RunSnapshot` field.** Hallucinations are ephemeral and re-derive from the
already-persisted `sanity` (+ a run-seed-derived director seed) on load. A brief, unobservable
discontinuity in the deterministic sequence after a load is acceptable. `summaries` count stays
unchanged. The director keeps `get_summary`/`apply_summary` for config round-trip and the
pure-model smoke; the persistence seam exists if exact continuity is ever wanted.

## Testing

- **`scripts/validation/hallucination_director_smoke.gd`** (pure model):
  - tier mapping (≥40→0, <40→1, <25→2, <15→3);
  - no events when tier 0 or `in_safe_zone`;
  - determinism: two directors with the same seed + identical tick inputs produce identical
    event streams;
  - ttl expiry removes events;
  - per-tier channel gating: at tier 1, only "ambient"/"fx" events occur (no "hud", no
    "phantom"); "hud" and "phantom" appear only at tier ≥ 2;
  - `get_direct_teeth()` zeros above tier 3, non-zero at tier 3;
  - `get_summary`/`apply_summary` round-trip.
  - Marker e.g. `HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true round_trip=true`.
- **`scripts/validation/main_playable_hallucination_smoke.gd`** (live scene, via real dispatchers):
  - drop sanity < 40 → ambient/FX manifest; < 25 → false-HUD + a phantom node appears;
  - a phantom deals **zero** vitals damage over N frames, contrasted with a real threat draining
    vitals in the same harness;
  - attacking a phantom through the **real** attack dispatcher spends extinguisher/ammo charge
    and dissipates the phantom (loop reachable in real play);
  - sanity < 15 → `sanity_health_drain` / `sanity_stamina_recovery_mult` measurably bite vitals;
  - raising sanity ≥ 40 (or entering safe zone) → `clear_all()` removes every manifestation.
  - Marker e.g. `MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true reachable=true`.
- Register both in `docs/game/06_validation_plan.md` (bump the commands count); confirm the full
  bundle stays clean.

## Docs to update on completion

- New **ADR-0042** — hallucinations as sanity teeth; phantom-vs-real isolation rationale.
- `docs/game/system_completion_audit.md` — M1 sanity row 🟡 → 🟢 with coordinator line cites.
- `docs/game/05_requirements.md` / `docs/game/features/survival_vitals.md` — REQ-SV-002 now has a
  mechanical consumer; replace "communicated to HUD" with the implemented effect.

## Implementation phasing (for the plan)

1. **Director model + pure smoke** — tiers, determinism, ttl, teeth values, round-trip.
2. **Shared placeholder renderer extraction** — `ThreatManager` refactor; existing combat smokes
   stay green (behavior-identical).
3. **Manager + phantom channel + coordinator wiring** — context build, phantom render/dissipate,
   attack-dissipate teeth, direct teeth into vitals; live smoke for the phantom + teeth loop.
4. **False-HUD + ambient + screen-FX channels** — layered on the manager; extend the live smoke.

This lands the highest-value, highest-risk parts (phantoms + teeth) under test before the polish
channels.

## Non-goals (v1)

- Tier hysteresis / smoothing (add only if boundary flicker is observed).
- A dedicated "focus/steady" counterplay action (commit-to-reveal covers it).
- Persisting active hallucinations across save/load (they re-derive).
- Bespoke phantom AI behaviors (phantoms reuse the placeholder visual; they don't path or attack).
- Sanity-driven *control inversion* (rejected in favor of perception unreliability + tier-3 drain).
