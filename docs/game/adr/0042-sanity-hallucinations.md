# ADR-0042: Sanity Hallucinations — Deterministic Director, Four Channels, Tiered Teeth

## Status

Accepted

## Context

Through the E2E wave and the subsequent system-completion audit, `SanityState` was graded
**🟡 half-coupled**: it had a live source (the safe-zone flag toggled by
`away_from_start` / breach state in the coordinator) and published a `perception_pressure_active`
flag in its summary, but its output was **HUD warning text only** — low sanity caused no
traced damage, no hallucination, and no control effect. The audit listed it as rollup item 6
("Sanity is cosmetic") and called it the highest-priority remaining loop closure in M1.

Two design constraints shaped the solution:

1. **Determinism.** The rest of the sim uses no `randi()`/`randf()`. Hallucinations must be
   reproducible from the same seed and sanity history to keep the game fair and smoke-testable.

2. **No save persistence for hallucinations.** Hallucination events are ephemeral; they re-derive
   from the already-persisted `sanity` value on load. Adding a `RunSnapshot` field for transient
   visual events would bloat save files and couple the save format to a cosmetic sub-system. The
   `summaries` count stays at **26** — the HallucinationDirector's `get_summary()` / `apply_summary()`
   exist for round-trip testing only, not for the autosave path.

3. **Real combat must be untouched.** Phantom threats must live in a separate manager, never
   registered with `ThreatManager`, so real combat math (damage pipeline, armor, detection) is
   never confused by phantom branches.

4. **Hallucinations are deliberately NOT a phase-timer hazard.** ADR-0005's `PhaseTimer`/cyclic
   contract applies to `ElectricalArcState` only. Sanity hallucinations are continuous and
   tier-driven, not periodic cycles.

## Decision

### HallucinationDirector (pure model)

A new `HallucinationDirector` (`scripts/systems/hallucination_director.gd`, `RefCounted`) is the
single source of truth for hallucination state. It is seeded from the coordinator's run seed and
uses **only integer hashing** (`seed * 1103515245 + step * 12345 + hash(kind)`) — no RNG calls.

Sanity maps to **three tiers** (0 = none):

| Tier | Sanity threshold | Active channels |
|------|-----------------|-----------------|
| 0    | ≥ 40            | none |
| 1    | < 40            | ambient cues only |
| 2    | < 25            | ambient + false HUD + phantom threats |
| 3    | < 15            | all channels + direct vitals teeth |

The director schedules discrete events (`{ id, kind, position, ttl }`) per enabled kind using a
per-kind interval and cap. Events expire by TTL; the entire event set is cleared when the player is
in a safe zone or sanity returns to tier 0. `get_direct_teeth()` returns `health_drain_per_second`
and `stamina_recovery_mult` only at tier 3 (zero / 1.0 otherwise).

### Four manifestation channels

| Channel | Kind | Min tier | Mechanic |
|---------|------|----------|----------|
| Ambient cues | `"ambient"` | 1 | SFX whispers / environmental sounds via `AudioManager.play_sfx` |
| False HUD | `"hud"` | 2 | `HallucinationManager.get_hallucinated_status_lines()` injects phantom contact blips into the HUD tracker |
| Phantom threats | `"phantom"` | 2 | Placeholder `Node3D` children of `HallucinationManager`; same visual as real threats (shared `ThreatPlaceholderRenderer`) but never in `ThreatManager` |
| Screen FX | continuous | 1 | `get_fx_intensity()` drives a `CanvasLayer` overlay intensity; rises 0 → 1 across tiers 1–3 |

### HallucinationManager (Node3D scene driver)

A new `HallucinationManager` (`scripts/systems/hallucination_manager.gd`, `Node3D`) renders the
director's active events each frame. Phantom threat nodes are its **own children**, reusing the
shared `ThreatPlaceholderRenderer` (`scripts/tools/threat_placeholder_renderer.gd`, Task 2)
extracted from `ThreatManager._spawn_placeholder`. This keeps the visual identical between real
and phantom threats while ensuring phantoms are never confused with real ones in any code path.

### Indirect teeth — wasted action

When the player swings at a phantom (`_attack_with_equipped_weapon`), `attack_with_weapon` runs
the normal path: the weapon fires, ammo is spent, the attack animation plays. The call returns
`no_target` (no real threat in range), but the coordinator then calls
`hallucination_manager.dissipate_phantom_in_range(player_position)`. If a phantom was in swing
range the result dict gains `phantom_dissipated: true`; the ammo is still gone. This is the
**commit-to-reveal** loop: the player must decide whether to swing at a suspicious shape and risk
wasting consumable ammo.

### Direct teeth — tier-3 vitals

At tier 3, `get_direct_teeth()` returns `{ health_drain_per_second: 0.5, stamina_recovery_mult: 0.5 }`.
The coordinator feeds these into the vitals tick context as `sanity_health_drain` and
`sanity_stamina_recovery_mult` (Task 3 keys), mirroring the existing `fire_health_drain` and
`status_stamina_recovery_mult` channels. This closes the simulation loop: sanity → hallucination
director → vitals tick → health + stamina penalty.

### Coordinator wiring

Three seams in `scripts/procgen/playable_generated_ship.gd` close the loop:

1. **Director tick** — in the sanity block, after `sanity_state.tick(delta)`, the director is
   ticked with `{ sanity, in_safe_zone, anchor_positions }`.
2. **Teeth keys** — in the vitals tick context dict, `sanity_health_drain` and
   `sanity_stamina_recovery_mult` are read from `hallucination_director.get_direct_teeth()`.
3. **Phantom dissipation** — in `_attack_with_equipped_weapon`, after `attack_with_weapon`, the
   manager's `dissipate_phantom_in_range` is called and the result dict is annotated.

## Consequences

Positive:

- Sanity gains real mechanical teeth at all three tiers: misdirection (tier 2), wasted ammo
  (tier 2+), and health/stamina drain (tier 3). The audit's 🔴 hollow is closed.
- Real combat math is completely untouched — phantoms live in their own manager and are never
  registered as `ThreatState` instances.
- The hallucination stream is fully deterministic from `(seed, step, sanity_input)`, keeping the
  system smoke-testable headless.
- `ThreatPlaceholderRenderer` is now shared: both real and phantom threats use the same visual
  builder, so the player cannot distinguish them by appearance — only by proximity dissipation.

Negative / tradeoffs:

- Phantoms spawn in `anchor_positions` from `_distributed_room_positions()`, so their placement
  is constrained by the room grid rather than being free-positioned. This is a deliberate
  trade-off for determinism.
- Hallucination events are ephemeral (not persisted); a save/load mid-hallucination cycle starts
  clean. This is intentional (see constraints above) but means the player cannot reload to escape
  a bad tier-3 stretch if sanity was already low before the save.
- The screen-FX overlay is minimal in v1 (a red-tinted `ColorRect` driven by
  `hallucination_intensity` meta); richer shader work is deferred.
- Ambient SFX relies on `audio_manager.play_sfx()` — if no real audio assets exist yet, it is a
  no-op at runtime (the seam exists but the asset path is a placeholder).

Deferred follow-ups (not in v1):

- **Directional hallucination audio** — spatial positioning of the ambient SFX to match phantom
  positions (deferred pending real audio assets).
- **HUD false readouts beyond bearing blips** — e.g. fake oxygen warnings at tier 2.
- **Proximity-triggered dialogue** — player character reacts verbally to phantoms (writing/VO
  dependency).
- **Per-run hallucination history** — tracking which phantoms were seen/missed for end-of-run
  stats.

## Affected documents

- `docs/game/05_requirements.md` — REQ-SV-002 updated from "communicated to HUD" to the
  implemented tiered mechanic.
- `docs/game/features/survival_vitals.md` — cascade rule 3 updated from cosmetic to mechanical.
- `docs/game/system_completion_audit.md` — M1 sanity row re-graded 🟡 → 🟢; rollup item 6
  ("Sanity is cosmetic") marked RESOLVED.
- `docs/game/adr/README.md` — 0042 added to the index.
- `docs/game/06_validation_plan.md` — new smokes registered (Tasks 1–5).

## Verification

- `docs/game/adr/0042-sanity-hallucinations.md` exists and is Accepted.
- `scripts/systems/hallucination_director.gd` exists; `hallucination_director_smoke.gd` passes
  `HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true`.
- `scripts/tools/threat_placeholder_renderer.gd` exists; `threat_placeholder_renderer_smoke.gd`
  passes `THREAT PLACEHOLDER RENDERER PASS swarm=true anchored=true default=true color=true`.
- `scripts/systems/vitals_state.gd` honors `sanity_health_drain` and `sanity_stamina_recovery_mult`;
  `vitals_state_smoke.gd` passes `VITALS STATE PASS sanity_drain=true sanity_stamina=true`.
- `scripts/systems/hallucination_manager.gd` exists; `main_playable_hallucination_smoke.gd`
  passes `MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true hud=true fx=true reachable=true`.
- `SanityState` row in `system_completion_audit.md` is 🟢.
- REQ-SV-002 in `05_requirements.md` references the tiered hallucination mechanic, not cosmetic HUD text.
