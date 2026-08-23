# ADR-0054: Compiler-edge standing nav and fail-closed walkability

- **Status:** Accepted
- **Date:** 2026-08-23
- **Supersedes / amends:** Amends ADR-0049 “graph quality depends on floor placement completeness” → “graph quality depends on compiler edge kinds plus `vertical_connections` plus `blocked_links` overlay.” Does not reopen ADR-0053 (enclosure geometry) or ADR-0051 (module grain).
- **Related:** feature `docs/game/features/compiler_walkability.md`; REQ-WALK-001; remaining play stack `docs/game/features/remaining_procgen_play_stack.md`

## Context

ADR-0049 made `ShipNavGraph` the production threat-path authority and left baked `NavigationRegion3D` as tooling. The live graph was still 4-connected from floor-module world positions. Compiler `SOLID` / `LOCKED` / `BREACH` edges were ignored, so threats and quality-gate start→goal paths tunneled walls and locked doors.

Walkability smoke used occupancy BFS over every non-`SOLID` edge, then a `NavigationAgent3D` on floor polygons. That treats `LOCKED` as walkable, never tests player height or doorway aperture, and cannot fail closed on walk-through walls or walk-off void.

Enclosure (ADR-0053) must still treat `LOCKED` and `BREACH` as watertight. Play must not.

## Decision

### 1. Two occupancy floods

- **Enclosure flood:** every compiler kind except `SOLID` (`OPEN`, `DOOR`, `HATCH`, `LOCKED`, `BREACH`) plus `layout.vertical_connections`. All occupied cells from any occupied start. Portal-endpoint and `critical_path` reachability in `StructuralPlanValidator` stay on this flood. A `LOCKED` portal remains enclosure-reachable.
- **Standing-play flood:** `OPEN` / `DOOR` / `HATCH` only, plus `layout.vertical_connections`. Start room → goal room only. Rooms behind `LOCKED` may be standing-unreachable. Validator must not fail portal / critical_path checks because standing-play cannot cross a lock.

Named helpers: `WalkabilityContract.enclosure_passable` / `standing_passable`.

### 2. Production `ShipNavGraph` is the standing graph

`build_from_layout` prefers `structural_plan.occupancy` + `edges`. Floor-module 4-connect remains fallback only when that plan is absent.

`build_from_structural_plan`:

1. One node per occupancy cell.
2. Compiler edges into `_base_edges` with standing costs. `LOCKED` and `BREACH` at `BLOCKED_COST`, present in `_base_edges`. `SOLID` omitted.
3. Overlay `layout.blocked_links` as `BLOCKED_COST` even if the stored plan still says `DOOR`. Do not regenerate goldens.
4. Vertical edges only from `layout.vertical_connections` (1.25 same-XZ / elevator, 1.5 ramp-like XZ step). Never infer by `dy == deck_height`.
5. Do not add `unlock_edge`. `reset_dynamic_costs` copies `_base_edges` onto `edges`.

`crouch_cost_for_kind` is a test helper (`BREACH` 1.75). Live crouch does not shrink the capsule.

### 3. Walkability Stage A is extruded-slab capsule sweep

Named numbers live in `scripts/procgen/walkability_contract.gd`. For every `SOLID` edge, a standing capsule (radius 0.35 m, height 1.6 m, bottom at floor Y + 0.12 m) swept cell-center → neighbor-center **must hit** the contract bounds yawed onto the edge pose and extruded to 0.20 m thickness. `DOOR` / `HATCH` sweeps **must pass** a 0.80 × 1.70 opening (hole width 1.20 m). `LOCKED` must not pass. Standing-path cells must have floors; a standing hop into missing occupancy is void.

`NavigationAgent3D` remains debug/tooling only (ADR-0049). It is not the PASS contract.

## Consequences

- Threats and quality-gate paths stop 4-connecting around compiler walls and locks.
- Isolated rooms behind `LOCKED` stay enclosure-valid and may be standing-unreachable.
- Wrapper collision retune is a later card; Stage A tests contract slabs, not live 1×1×1 boxes.
- No unlock API in this stack; a later door-hack card may add an `_unlocked` overlay reapplied after `reset_dynamic_costs`.

## Rejected alternatives

- Keep NavigationAgent as the walkability contract — walls are not obstacles; contradicts ADR-0049.
- One flood for enclosure and standing-play — wrecks with `LOCKED` portals fail 100% occupancy and validator portal reachability.
- Infer vertical edges by stacked proximity — drops authored ramp/elevator identity and invents shafts.

## Verification

- `procgen_walkability_smoke.gd`
- `ship_nav_graph_smoke.gd`
- `procgen_quality_gate_smoke.gd`
