# ADR-0030: Achievement Catalog and Triggers

Date: 2026-06-25
Status: Accepted
System: 13 — Distribution, Store, Achievements, Demo, Localization & Post-Launch Ops
Relates to: ADR-0029 (release distribution architecture),
ADR-0007 (save/load boundary),
`docs/game/features/release_distribution.md`.

## Context

Steam achievements (and itch / GOG equivalents) require:

1. A catalog the storefront can ingest at submission time.
2. Per-run unlock events triggered by real gameplay, not by a debug flag.
3. A persistence seam so a player's unlocks survive crashes and game exits.
4. A separation between per-run state (current run's unlock set) and
   cross-run state (the "you have X points" total Steam shows).

The Synaptic Sea had none of this. Adding achievements without a clean
catalog/unlock/persistence triad would have meant hand-coding `if (event)
{ Steam.unlock(...) }` at every gameplay milestone — a recipe for missed
unlocks and double-unlocks.

## Decision

Introduce a data-driven catalog + service pair.

### Catalog: `data/release/achievement_catalog.json`

A JSON list of `{id, display_name, description, icon_placeholder, trigger_event, trigger_target}` entries. Example:

```json
{
  "id": "first_breath",
  "display_name": "First Breath",
  "description": "Pick up your first portable oxygen pump.",
  "icon_placeholder": "res://assets/icons/achievements/first_breath.svg.placeholder",
  "trigger_event": "tool_acquired",
  "trigger_target": "portable_oxygen_pump"
}
```

The catalog is the single source of truth: `AchievementState` loads it at
boot and refuses to unlock any id that is not in the catalog. This stops
typos from silently creating un-lockable achievements.

### Service: `AchievementState` (pure `RefCounted`)

- Owns the per-run unlock set.
- `unlock(id) -> bool` — returns `true` on a successful unlock,
  `false` if the id is unknown or already unlocked. Idempotent on
  duplicates (Steam-style: "I don't care that you called me twice").
- `is_unlocked(id) -> bool`.
- `get_unlocked() -> Array[String]` — sorted unlock ids.
- `get_summary()` / `apply_summary()` — for the per-run save seam.
- `get_status_lines()` — for HUD / debug overlays.

### Persistence

- `user://achievements.json`, schema `release-achievements-1`.
- Saved at the same checkpoints the run snapshot saves (objective
  completion, manual save). Loaded at run boot.
- Per-run only: a new run wipes the unlock set. ADR-0007 boundary
  preserved. The "lifetime achievements" tally that Steam shows is a
  cross-run concern deferred to the future Steamworks integration.

### Triggers

The scene coordinator (`PlayableGeneratedShip`) emits
`achievement_unlocked(id)` at real gameplay milestones:

- `tool_acquired` → `portable_oxygen_pump`, `junction_calibrator`
- `objective_completed` → for each objective kind
- `reactor_stabilized` → `reactor_stabilized`
- `run_complete` → `extracted`
- `repair_consumed` → `first_repair`
- `loot_searched` → `first_loot`

The achievement service listens and looks up the matching catalog entry
by `trigger_event` / `trigger_target`, then calls `unlock(id)`. Adding a
new achievement is a JSON edit + one coordinator emit at the right
milestone; no code change.

## Consequences

- Achievements are deterministic and reproducible — the smoke unlocks a
  fixed set and asserts the summary line.
- Unknown catalog ids are rejected by the service; unknown trigger events
  are rejected by the coordinator (no silent drop).
- Per-run-only boundary is preserved; ADR-0007 is unaffected.
- Cross-run "lifetime achievement points" is a deferred Steamworks
  concern; the smoke proves the per-run state, not the cross-run tally.

## Deferred

- Steamworks SDK activation that pushes unlocks to Steam.
- Cross-run "you have N points" HUD.
- Cloud sync of unlock state.
- Icon art — the catalog references placeholder paths; final art is a
  production asset swap, not a code change.