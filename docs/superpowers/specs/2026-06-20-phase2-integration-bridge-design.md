# Phase 2 Integration Bridge — ShipSystemsManager into the live coordinator

Date: 2026-06-20
Status: Approved for implementation
Parent spec: `docs/superpowers/specs/2026-06-20-synaptic-sea-core-systems-design.md` (System 2)
Phase 2 model spec: `docs/superpowers/specs/2026-06-20-phase2-ship-systems-design.md`
Handoff: `docs/superpowers/plans/2026-06-20-phase2-integration-handoff.md`
ADR (to be authored): retires `ShipSystemState`; `ship_systems_summary` carries the manager snapshot.

---

## Context

Two overlapping tracks exist in the repo:

- **Track 1 — vertical slice (shipped, green):** the live game loads a golden ship, runs four
  scripted objectives (`recover_supplies`, `restore_systems`, `download_logs`,
  `stabilize_reactor`), drives oxygen/fire/arc hazards, and supports current-run save/load. Its
  ship-systems model is `ShipSystemState` — a coarse **objective-flag** model.
- **Track 2 — master core-systems rebuild:** governed by `synaptic-sea-core-systems-design.md`. Phase 1
  (procgen layout pipeline) and Phase 2 (`ShipSystemsManager` model layer, PR #1) are built. The
  master spec is explicit (System 2, "relationship to existing code"): **`ship_system_state.gd`
  becomes `ShipSystemsManager`** and `oxygen_state.gd` eventually becomes a child of
  `LifeSupportSystem`.

This spec covers the **bridge**: wiring the Phase 2 `ShipSystemsManager` into the live coordinator
(`scripts/procgen/playable_generated_ship.gd`) and **retiring `ShipSystemState`** (full replacement
of its systems role — "Path B"), scoped tightly to the bridge.

### Out of scope (later phases — do not pull in)

- Moving the breach `oxygen_state` under `LifeSupportSystem` (a later LifeSupport refactor).
- Refactoring `generated_ship_loader.gd` into `RoomGraphGenerator` (Phase 1 continuation).
- Routing the live boot through the runtime generator instead of the golden fixture.
- A real parts/tools/skill repair loop feeding `manager.repair()` (Phase 6 inventory/equipment).

## Goal / definition of done

`ShipSystemsManager` is the single source of truth for ship-systems state in the live game.
`ShipSystemState` is deleted. Every consequence it used to drive (route gates, breach seal, blocked
affordance clearing, extraction unlock, HUD power/reactor readouts) is re-derived from the manager.
The full regression bundle ends `SYNAPTIC_SEA REGRESSION PASS` with clean output, and a new main-scene
smoke proves the live runtime consequences.

---

## Design

### 1. Build the manager from a blueprint sidecar

The live game boots from the golden fixture by path; there is no `ShipBlueprint` in memory. We give
the golden ship a blueprint sidecar so the manager is built from real blueprint inputs without
changing the geometry load.

- New fixture: `data/procgen/golden/coherent_ship_001/blueprint.json` = `ShipBlueprint.to_dict()`
  with **`condition = DAMAGED`** (fits the trapped, broken hub-ship fiction) and a **fixed seed**
  (e.g. `17`, matching the existing golden lineage) so the condition-damage set is deterministic.
- Coordinator: add `@export var blueprint_path: String` defaulting to the sidecar path. In
  `_build_runtime_nodes()`, load and parse it via `ShipBlueprint.from_dict(...)`, then:
  ```gdscript
  ship_systems_manager = ShipSystemsManagerScript.new()
  ship_systems_manager.configure(ship_systems_manager.load_definitions(), bp.condition, bp.seed_value)
  ```
- If the sidecar is missing or malformed, fall back to a coordinator default
  (`condition = DAMAGED`, `seed = 17`) and `push_warning` — never crash the slice.
- Geometry continues to load from the golden `layout.json` (unchanged). This is the seam for when
  geometry generation later also moves onto the blueprint.

### 2. Objective completion drives manager repairs (replaces `apply_objective`)

`_on_interactable_completed()` stops calling `ship_systems.apply_objective(...)`. Instead it maps the
completed `objective_type` to manager subcomponents and brings them operational:

| `objective_type`   | Manager effect                                                  |
|--------------------|----------------------------------------------------------------|
| `recover_supplies` | none (supply objective; no system)                             |
| `restore_systems`  | bring `power` operational (`power_distribution`, `battery_cells`) |
| `download_logs`    | bring `navigation` operational (`nav_computer`)                |
| `stabilize_reactor`| bring `power/reactor_core` to full health                      |

The mapping is a data constant in the coordinator (`OBJECTIVE_REPAIR_MAP`) so it stays declarative.

**Additive manager method (in scope):** `force_repair(system_id, subcomponent_id) -> bool` that
deterministically sets the named subcomponent's health to operational (≥ `operational_threshold`,
default to `1.0`). Required because the slice has no parts/tools/skill inventory feeding the real
`repair()` path yet (Phase 6). `force_repair` is the only addition to the manager's public surface.

### 3. Consequences derive from manager state, via a flag-compat adapter

The downstream Track-1 models — `route_control_state` and the breach `oxygen_state` — **stay
unchanged**. Both consume a flag-shaped summary today (`summary["main_power_restored"]`). The
coordinator synthesizes that summary from manager state and feeds it to them exactly as before:

```gdscript
func _manager_compat_summary() -> Dictionary:
    var power_on: bool = ship_systems_manager.is_operational("power")
    return {
        "main_power_restored": power_on,
        "blocked_routes_cleared": power_on,
        "extraction_unlocked": _is_extraction_unlocked(),
        "power_percent": int(round(ship_systems_manager.get_system("power").health() * 100.0)),
        "reactor_stability_percent": int(round(_reactor_core_health() * 100.0)),
        # ...remaining keys the downstream models read, derived from manager state
    }
```

- **Route gates open / breach seals / blocked affordances clear** → keyed on
  `ship_systems_manager.is_operational("power")` (was `main_power_restored`).
- **Extraction unlock** → coordinator predicate `_is_extraction_unlocked()`:
  `is_operational("power")` AND `reactor_core.health` is full.
- **HUD `Power %` / `Reactor %`** → derived from manager health.
- **HUD systems lines** → driven from `ship_systems_manager.get_status_summary()`.

This adapter is the blast-radius control: only the coordinator changes; the breach-seal and
route-control models are untouched.

### 4. Save / load

- `snapshot.ship_systems_summary` now carries `ship_systems_manager.get_summary()` — a **content
  swap**, not an added field. Summary **count stays 7** (the handoff's "7→8" assumed
  add-alongside; replacement keeps it at 7).
- On load: `ship_systems_manager.apply_summary(snapshot.ship_systems_summary)` restores exact
  subcomponent health, so every consequence re-derives. `objective_completion_count` derives from
  `current_objective_sequence` (the slice completes sequences linearly); the
  `completed_sequences`-array reconstruction is removed with `ShipSystemState`.
- The manager's internal **life-support oxygen stays internal** — advanced each frame but not
  surfaced on the HUD, to avoid a confusing second oxygen meter until the breach/life-support
  unification is designed separately.

### 5. Retire `ShipSystemState`

- Delete `scripts/systems/ship_system_state.gd`.
- Remove `ShipSystemStateScript` preload and `ship_systems` field from the coordinator; replace all
  usages with `ship_systems_manager` + the adapter.
- Update `scripts/ui/objective_tracker.gd` to drop any direct `ShipSystemState` coupling (it consumes
  status lines via `set_system_status_lines`, so this is expected to be a no-op or a small change).
- Drive `ship_systems_manager.advance(delta)` from `_process()` alongside the existing hazard ticks.

### 6. Process / docs / validation

- **ADR (new):** records that `ship_systems_summary` now holds the manager snapshot and
  `ShipSystemState` is retired (RunSnapshot content is ADR-gated by ADR-0007; ship-systems
  architecture is ADR-0008). New `docs/game/adr/0009-*.md` (or an ADR-0008 addendum).
- **Validation:**
  - Update `scripts/validation/save_load_service_smoke.gd` — change the **shape** assertions on
    `ship_systems_summary` (no longer `main_power_restored`/`power_percent` flags; now
    `systems`/`system_order`). Count assertion stays `summaries=7`.
  - Replace `scripts/validation/main_playable_slice_ship_systems_smoke.gd` with a manager-driven
    version: build from the blueprint sidecar → complete `restore_systems` → assert
    `is_operational("power")`, route gates open, breach sealed → complete `stabilize_reactor` →
    assert extraction unlocked → save/load round-trips the manager summary.
  - Check `req012_autosave_sequence_smoke.gd` for any summary-count assertion.
  - Net regression-bundle command count ≈ neutral (one model smoke repurposed, no new model layer).
  - Done = `SYNAPTIC_SEA REGRESSION PASS commands=<n> clean_output=true`, plus the Gate-1 automated
    playtest still passes.

---

## Risk

The breach-seal and route-gate behavior currently depends on the `main_power_restored` flag arriving
at the exact `restore_systems` completion. Deriving it from `is_operational("power")` must reproduce
that timing precisely. The flag-compat adapter (keeping downstream models untouched) plus the new
main-scene integration smoke are the mitigations: the smoke asserts the gate-open/breach-seal
transition fires on the same objective boundary as before.

## Headless gotchas (carried from the handoff)

- In a `SceneTree`, `quit()` does not halt `_initialize()` — every failure path must `return` after
  `quit(1)`.
- `class_name` globals are unreliable under `--headless --script`; reference cross-file scripts via
  `preload(...)` const Script vars; avoid `class_name` return-type annotations on cross-file calls.
- Allowlisted teardown noise: `ERROR: Capture not registered: 'gdaimcp'.` and
  `WARNING: ObjectDB instances leaked at exit ...`. Any other ERROR/WARNING fails the bundle.
