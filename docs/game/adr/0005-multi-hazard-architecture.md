# ADR-0005: Multi-Hazard Architecture — Contract + Helper, Independent Models

## Status

Accepted

> **Amended by ADR-0041 (2026-06-27):** `FireState` has been **retired** and fire
> migrated to `FireSuppressionState` as a persistent, compartment-keyed,
> resource/repair-coupled hazard — it no longer cycles on a `PhaseTimer` and is no
> longer part of the timer-hazard set. The timer-hazard set is now `ElectricalArcState`
> **only**; oxygen and fire are both non-timer hazards. The `HazardStateContract`,
> `PhaseTimer` helper, loader zone arrays, and save/load shape below remain in force for
> oxygen and electrical arc. `hazard_contract_smoke.gd` accordingly asserts
> `models=2 phase_timer_owners=1`. See ADR-0041 for fire's new model.

## Context

REQ-013 (`docs/game/features/hazard_type_3.md`) adds `ElectricalArcState` as the third Alpha hazard type. The electrical-arc spec notes that `ElectricalArcState` shares the same timer/passability code shape as `FireState`: both cycle between two phases on fixed durations and toggle a collision segment. REQ-013 requires an ADR before implementation if the third hazard shares code with `FireState` or `OxygenState`.

Without a decision, the likely outcome is copy-paste between `FireState` and `ElectricalArcState`, or a premature inheritance hierarchy that drags `OxygenState` into a generalized hazard base it does not fit. The project also needs a stable loader contract for zone arrays and a save/load shape for hazard state before the electrical-arc feature is implemented.

The Alpha hazard set is intentionally small and fixed: one resource-drain hazard (oxygen/breach), one long-safe/short-danger timer hazard (fire), and one short-safe/short-danger timer hazard (electrical arc). No additional hazard types are planned for Alpha.

## Decision

Adopt a **shared `HazardStateContract` plus a reusable `PhaseTimer` helper**, while keeping `OxygenState`, `FireState`, and `ElectricalArcState` as independent `RefCounted` models.

### Why not a common base class

`OxygenState` is semantically different from the timer hazards: it models a depleting/regenerating resource, reacts to player position and tool multipliers, and blocks passability on a resource threshold. `FireState` and `ElectricalArcState` are pure phase timers with no resource, no player-position input, and no tool interaction. A common base class would either be too thin to be useful or would force `OxygenState` to carry timer-phase concepts it does not need.

### HazardStateContract

Every Alpha hazard model implements the same duck-typed integration contract so `PlayableGeneratedShip`, the HUD, and `SaveLoadService` can treat them uniformly at their boundaries without knowing per-hazard internals.

Required methods:

- `configure(config: Dictionary) -> void`
  - Receives the loader's zone array and tuning values as a dictionary so each model can unpack the fields it needs.
- `tick(delta_seconds: float, context: Dictionary) -> void`
  - Advances the model by one frame. `context` is optional and may be empty for timer hazards; `OxygenState` uses it for `player_in_breach_zone` and tool multipliers.
- `get_summary() -> Dictionary`
  - Returns a serializable snapshot of the model. Keys are model-specific but each summary must include `hazard_kind` (`"oxygen"`, `"fire"`, or `"electrical_arc"`) and `passability_blocked` (`bool`).
- `apply_summary(summary: Dictionary) -> bool`
  - Restores the model from a snapshot produced by `get_summary()`. Returns `true` if the summary was accepted, `false` if the kind or version does not match.
- `is_passability_blocked() -> bool`
  - Returns `true` if any of the hazard's zones currently block traversal.
- `get_status_lines() -> PackedStringArray`
  - Returns player-facing status lines. Only oxygen uses the global HUD; fire and arc are localized to their zone Label3D nodes.

Optional, model-specific accessors (not part of the contract) remain allowed, e.g. `FireState.is_burning()` or `OxygenState.current_oxygen()`.

### PhaseTimer helper

Timer-based hazards (`FireState`, `ElectricalArcState`) use a shared `scripts/systems/phase_timer.gd` (`PhaseTimer` extending `RefCounted`) for the phase-cycle logic:

- Tracks `phase` enum, `time_in_phase`, and phase durations.
- `tick(delta)` flips phase once when duration is reached and carries the remainder into the next phase (no multi-flip in one tick).
- `configure(phase_durations: Dictionary)` clamps each duration to a minimum of `0.1s`.
- Exposes `current_phase()`, `time_in_phase()`, and `normalized_progress()`.

`FireState` and `ElectricalArcState` own a `PhaseTimer` instance and translate its phase output into their own enum names, passability, and labels. The helper removes copy-paste timer math while keeping each hazard model responsible for its own semantics.

### Loader contract for zones

`scripts/procgen/generated_ship_loader.gd` exposes three optional zone arrays on its output:

- `breach_zones: Array[Dictionary]` — room id, cell, zone id. Missing/null treated as empty; the coordinator may inject a fallback for the main corridor.
- `fire_zones: Array[Dictionary]` — room id, cell, zone id. Missing/null treated as empty; Gate 2/Alpha coordinator may inject a fallback side-corridor zone.
- `arc_zones: Array[Dictionary]` — room id, cell, zone id. Missing/null treated as empty; no fallback is injected because arc placement is template-specific.

Each dictionary uses the same keys:

- `zone_id: String`
- `room_id: String`
- `cell: Vector2i` (or `Array[int]` serialized as `[x, y]` for JSON compatibility)

`PlayableGeneratedShip` passes the relevant array into each hazard model's `configure()` call.

### Save/load serialization shape

`RunSnapshot` (per ADR-0007) stores hazard state under a single `hazards: Dictionary` key:

```json
{
  "hazards": {
    "oxygen": { "hazard_kind": "oxygen", "oxygen": 78.5, ... },
    "fire": { "hazard_kind": "fire", "phase": "CLEARED", "time_in_phase": 1.2, ... },
    "electrical_arc": { "hazard_kind": "electrical_arc", "phase": "DISCHARGED", "time_in_phase": 0.4, ... }
  }
}
```

Each hazard summary is keyed by its `hazard_kind` string. `PlayableGeneratedShip` calls each model's `apply_summary()` during load. A model whose kind does not match must reject the summary and return `false`.

### Scene coordination

`PlayableGeneratedShip` owns one instance of each hazard model and one scene-node group per hazard zone type. On `_ready`:

1. Load generated ship data.
2. Build breach, fire, and arc zone nodes from their zone arrays.
3. Call `configure()` on each hazard model with its zones and tuning.
4. If a saved run exists, call `apply_summary()` on each model before the first `_process` tick.

On `_process`:

1. Tick `oxygen_state` with player-position context.
2. Tick `fire_state` and `electrical_arc_state` with empty context.
3. Refresh collision and labels for all three hazard node groups.

Hazard models do not reach into the scene tree; the coordinator maps model state to scene consequences.

## Consequences

Positive:

- Timer hazards share one well-tested helper instead of duplicated phase logic.
- `PlayableGeneratedShip` and `SaveLoadService` integrate each hazard through a single contract without per-hazard branches.
- `OxygenState` keeps its resource-drain semantics without inheriting timer concepts it does not need.
- The decision is scoped to the Alpha three-hazard set; future hazards require a new ADR before the contract is expanded.

Negative / tradeoffs:

- `FireState` and `ElectricalArcState` still have similar boilerplate (phase enum, passability mapping, label text). The helper removes the timer math but not all duplication.
- Adding a fourth hazard type in Beta will require revisiting this ADR; the contract is intentionally not generic beyond Alpha.
- `context: Dictionary` in `tick()` is loose-typed. This is acceptable for Alpha because only oxygen uses it; a future ADR should replace it with a typed context object if more hazards need per-frame inputs.

Mitigations:

- Keep `PhaseTimer` strictly a helper; do not let it own scene nodes or hazard-specific labels.
- Document the Alpha-only scope in this ADR and in the hazard feature specs.
- Code-review checklist: any new hazard model must implement `HazardStateContract` and add both model and main-scene smokes before the feature is marked done.

## Affected documents

- `docs/game/features/hazard_type_3.md` — updated to reference ADR-0005 and remove the dependency blocker.
- `docs/game/features/hazard_variety.md` — Gate 2 `FireState` implementation is unchanged; ADR-0005 becomes the reference if the spec is revised for Alpha.
- `docs/game/05_requirements.md` — REQ-013 acceptance criteria now cite ADR-0005.
- `docs/game/04_tdd.md` — future-ADR line for multi-hazard architecture is resolved by ADR-0005.
- `docs/game/adr/0007-save-load-service-scope.md` — hazard state serialization is bounded by the contract defined here.

## Verification

- `docs/game/adr/0005-multi-hazard-architecture.md` exists and is Accepted.
- `docs/game/features/hazard_type_3.md` cites ADR-0005 in its Risks and ADRs sections.
- `docs/game/05_requirements.md` REQ-013 acceptance criteria cite ADR-0005.
- `FireState` and `ElectricalArcState` share `PhaseTimer` but are separate `RefCounted` classes.
- Each hazard model implements `configure`, `tick`, `get_summary`, `apply_summary`, `is_passability_blocked`, and `get_status_lines`.
- Save/load smoke round-trips hazard state for all three hazard kinds.
