# Phase 2: Ship Systems — Design

Date: 2026-06-20
Status: Approved for implementation
Parent spec: `docs/superpowers/specs/2026-06-20-synapse-sea-core-systems-design.md` (System 2 / Build Phase 2)
ADR: `docs/game/adr/0008-ship-systems-architecture.md`

---

## Goal

Model the six core ship systems (Power, Life Support, Gravity, Propulsion, Navigation,
Scanners) as pure data models with subcomponents, dependency cascades, and a repair flow.

Phase 2 exit criteria (from the parent spec): "systems come online/offline, cascades work,
repair flow functions."

## Scope decisions (brainstorming 2026-06-20)

1. **Build alongside, not in place.** The existing `ShipSystemState`
   (`scripts/systems/ship_system_state.gd`) is the objective-flag model driving the live
   playable slice and a green regression smoke. Phase 2 ships an independent
   `ShipSystemsManager` + 6-system model layer. The live slice and `ShipSystemState` are
   **untouched** this phase; wiring the manager into the runtime is a later integration step.
2. **All 6 systems, full depth, one plan** — base class + manager + subcomponents +
   dependency cascade + parameterized repair flow.
3. **Parameterized repair.** Repair takes the skill level and available parts/tools as
   inputs; Phase 3 (skills) and Phase 6 (inventory) plug in later through the same signature.
4. **Derived status + `advance(delta)` for effects.** Operational status is computed on
   demand by walking health + dependencies (no cached cascade state). A single
   `advance(delta)` applies time-based effects; only Life Support has a model-level time
   effect (draining oxygen when offline).
5. **Deterministic repair.** Repair success is fully determined by requirements being met
   (parts + tools present, skill ≥ minimum). No seed-based success chance in Phase 2; a skill
   margin / chance factor can be layered in later without changing the interface.

## Global constraints

- Godot 4.6.2, typed GDScript, `RefCounted` only (no scene tree) — model/node separation.
- New scripts in `scripts/systems/`; new data in `data/ship_systems/`.
- Deterministic: same seed + condition = identical initial damage and identical round-trip.
- Every model implements `get_summary()` / `apply_summary()` (REQ-012 round-trip convention).
- Existing validation smokes must continue to pass; the regression bundle stays green.

---

## Architecture

```
ShipSystemsManager (owns the 6 systems, resolves cascades, advance(delta))
    ├── PowerSystem          (ShipSystem)          deps: []
    ├── LifeSupportSystem    (LifeSupportSystem)   deps: [power]   owns OxygenState
    ├── GravitySystem        (ShipSystem)          deps: [power]
    ├── NavigationSystem     (ShipSystem)          deps: [power]
    ├── PropulsionSystem     (ShipSystem)          deps: [power, navigation]
    └── ScannerSystem        (ShipSystem)          deps: [power, navigation]

ShipSystem  -> Array[ShipSubcomponent]
ShipSubcomponent -> health + repair requirements
```

### New files

| File | Class | Responsibility |
|------|-------|----------------|
| `scripts/systems/ship_subcomponent.gd` | `ShipSubcomponent` | One repairable part: `health` (0–1), `operational_threshold`, repair requirements, `repair()`, summary round-trip. |
| `scripts/systems/ship_system.gd` | `ShipSystem` | One system: `system_id`, `Array[ShipSubcomponent]`, `dependency_ids`. Derives own health; base `advance()` is a no-op. |
| `scripts/systems/life_support_system.gd` | `LifeSupportSystem` (extends `ShipSystem`) | Owns an `OxygenState`; drains it in `advance()` when not operational. |
| `scripts/systems/ship_systems_manager.gd` | `ShipSystemsManager` | Owns 6 systems, resolves cascades, `advance(delta)`, `is_operational(id)`, `repair(...)`, summary round-trip. |
| `data/ship_systems/systems.json` | — | Data definitions: per-system subcomponents (+ requirements) and dependencies. |
| `scripts/validation/ship_systems_manager_smoke.gd` | — | Pure-model smoke; Phase 2 gate test. |

> The 5 non-life-support systems are plain data-configured `ShipSystem` instances, not 5
> subclasses. Only `LifeSupportSystem` needs a subclass (the oxygen coupling). The table's
> "PowerSystem"/"GravitySystem"/etc. names denote configured instances, not classes.

---

## Components

### ShipSubcomponent

```
var subcomponent_id: String
var health: float = 1.0                 # 0.0 (destroyed) .. 1.0 (perfect)
var operational_threshold: float = 0.5  # >= threshold counts as functional
var required_parts: Array[String]       # part ids needed to repair
var required_tools: Array[String]       # tool ids needed to repair
var min_skill: int = 0                  # minimum repair skill
var repair_seconds: float = 5.0         # base repair time at skill == min_skill

func is_functional() -> bool                       # health >= operational_threshold
func repair(parts: Array, tools: Array, skill: int) -> Dictionary   # RepairResult
func get_summary() -> Dictionary
func apply_summary(s: Dictionary) -> bool
```

`RepairResult` dictionary: `{ "success": bool, "reason": String, "seconds": float }`.
Reasons: `"ok"`, `"missing_parts"`, `"missing_tools"`, `"insufficient_skill"`,
`"already_functional"`.

### ShipSystem

```
var system_id: String
var subcomponents: Array[ShipSubcomponent]
var dependency_ids: Array[String]

func health() -> float                  # min() of subcomponent healths (weakest link)
func is_self_functional() -> bool       # all subcomponents functional
func advance(delta: float, operational: bool) -> void   # base: no-op
func get_summary() -> Dictionary
func apply_summary(s: Dictionary) -> bool
```

Operational status is NOT stored on the system; the manager computes it (it needs the
dependency graph). `is_self_functional()` is the health half of that decision.

### LifeSupportSystem (extends ShipSystem)

Owns an `OxygenState` (`scripts/systems/oxygen_state.gd`). `advance(delta, operational)`:
when `operational == false`, ticks the oxygen model toward depletion; when operational, the
oxygen model holds/regenerates per its own rules. Exposes `get_oxygen_state()` for the HUD
later. Its summary nests the oxygen summary.

### ShipSystemsManager

```
var systems: Dictionary                 # system_id -> ShipSystem

static func configure(definitions: Dictionary, condition: int, seed: int) -> ShipSystemsManager
func is_operational(system_id: String) -> bool      # derived, dependency-aware, cycle-safe
func advance(delta: float) -> void                  # ticks every system with its operational status
func repair(system_id, subcomponent_id, parts, tools, skill) -> Dictionary
func get_status_summary() -> Dictionary             # per-system {operational, health}
func get_summary() -> Dictionary
func apply_summary(s: Dictionary) -> bool
```

---

## Data flow

1. **Build:** `ShipSystemsManager.configure(definitions, condition, seed)` instantiates the 6
   systems from `systems.json`, then deterministically damages subcomponents based on
   `condition` (pristine = none, damaged = some, wrecked = most) using a seeded RNG. The
   `condition` enum mirrors `ShipBlueprint.Condition`.
2. **Query:** `is_operational(id)` walks `dependency_ids` recursively with a visited set
   (cycle-safe) — a system is operational iff it is self-functional AND every dependency is
   operational. Power has no dependencies, so it gates the whole tree.
3. **Tick:** `advance(delta)` calls `system.advance(delta, is_operational(id))` for each
   system. Life Support drains oxygen when its computed status is offline.
4. **Repair:** `repair(...)` locates the subcomponent and delegates to its `repair()`,
   returning the `RepairResult`. A successful repair raises `health` to 1.0, which can flip
   the system (and its dependents) back to operational on the next query.

## Dependency cascade

```
Power offline  ->  Life Support, Gravity, Navigation offline
                   ->  Propulsion, Scanners offline (also need Navigation)
```

The cascade is emergent from `is_operational()` recursion; there is no separate cascade
pass and no stored "offline because of dependency" flag to desync. Repairing Power's
subcomponents back above threshold restores every downstream system that is itself healthy.

## Repair flow (parameterized)

```
repair(system_id, subcomponent_id, available_parts, available_tools, skill_level)
  -> locate subcomponent
  -> if already functional: { success=false, reason="already_functional" }
  -> if any required_part not in available_parts: { reason="missing_parts" }
  -> if any required_tool not in available_tools: { reason="missing_tools" }
  -> if skill_level < min_skill: { reason="insufficient_skill" }
  -> else: health = 1.0; seconds = repair_seconds * skill_factor(skill_level); { success=true }
```

`skill_factor` reduces time as skill exceeds the minimum (e.g.
`repair_seconds / (1 + 0.1 * (skill_level - min_skill))`, floored). Deterministic; no RNG.
Phase 3 supplies `skill_level`; Phase 6 supplies the parts/tools arrays.

## Time effects (`advance`)

Only Life Support accumulates a model-level time effect (oxygen drain). Other systems'
consequences are read as status by future consumers:

| System offline | Consequence (consumed later, not in Phase 2 model time loop) |
|----------------|---------------------------------------------------------------|
| Power | cascades all others offline (already modeled) |
| Life Support | oxygen drains (modeled now via OxygenState) |
| Gravity | movement penalty / floating (status only) |
| Propulsion | cannot travel (status only) |
| Navigation | scanner blind (status only) |
| Scanners | no ship detail (status only) |

## Save / load

- `ShipSystemsManager.get_summary()` returns the full nested state (each system's
  subcomponent healths + the oxygen summary). `apply_summary()` restores it and rejects a
  malformed/mismatched summary (returns `false`).
- **Not** wired into the live `SaveLoadService` snapshot this phase. Doing so would change
  the `summaries=7` contract in `save_load_service_smoke.gd` / `run_snapshot.gd`; that is
  deferred to the runtime-integration step so the bundle stays green. The round-trip is
  fully validated by the Phase 2 model smoke in isolation.

## Validation

New `scripts/validation/ship_systems_manager_smoke.gd` (pure model, `extends SceneTree`,
PASS/`quit` convention) asserting:

1. **Deterministic build** — same (condition, seed) produces identical subcomponent health
   sets across two `configure()` calls; different conditions produce more/less damage.
2. **Cascade** — with Power damaged below threshold, every dependent reports
   `is_operational() == false`; repairing Power restores dependents that are themselves
   healthy; a dependent still-broken stays offline.
3. **Repair flow** — missing part, missing tool, and under-skill each fail with the correct
   reason; full requirements succeed and set health to 1.0; repairing an already-functional
   subcomponent reports `already_functional`.
4. **Time effect** — `advance(delta)` drains the Life Support oxygen model when Life Support
   is offline and does not when it is operational.
5. **Round-trip** — `get_summary()` → `apply_summary()` on a fresh manager reproduces state;
   a wrong-shaped summary is rejected.

Marker: `SHIP SYSTEMS MANAGER PASS ...`. Registered in the regression bundle
(`docs/game/06_validation_plan.md`, `commands 42 -> 43`) and documented there.

**No main-scene smoke** this phase — the models have no scene consequences yet (build
alongside). A main-scene smoke is added when the manager is wired into the runtime.

## Out of scope (Phase 2)

- Wiring the manager into `PlayableGeneratedShip` / the live HUD / SaveLoadService.
- Skill system (Phase 3) and inventory/parts/tools sourcing (Phase 6) — only the repair
  interface that consumes them.
- Per-system non-oxygen runtime effects (movement penalty, travel gating) — exposed as
  status only.
- Retiring or refactoring `ShipSystemState`.
