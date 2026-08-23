# ADR-0055: ShipLayoutGenerator owns structural compile and wreck stamp order

- **Status:** Accepted
- **Date:** 2026-08-23
- **Supersedes / amends:** Amends ADR-0051 persistence grain (module keys) and ADR-0029 procgen expansion ownership. Does not reopen ADR-0054 (standing nav kinds).
- **Related:** feature `docs/game/features/live_wreck_overlay.md` (or overlay LOCKED/BREACH + module damage); REQ-MI-004; `structural_plan_validated`

## Context

Quality-gate and other layout-only callers never enter `ShipGenerator._load_layout_as_scene`. Compile, validation, and wreck `module_damage` therefore cannot live only in the scene loader. Wreck amounts must key `edge/<edge_key>`, `floor/<cell_key>`, and `ceiling/<cell_key>` — the same `module_key` metadata the loader stamps on wrappers. Stamping wreck before the last compile, or recompiling after stamp, desyncs those ids from scene consequences.

## Decision

1. `ShipLayoutGenerator` is the authoritative owner of `StructuralEdgeCompiler.compile` + `StructuralPlanValidator.validate` for generated layouts. On success it writes `layout.structural_plan` and `layout.structural_plan_validated = true`. Validation failure is fail-closed (empty layout / no load).
2. Portal/lock overlays (`apply_branch_overlays`, `apply_portal_overlays`) run **before** that compile so the plan sees `LOCKED` / `BREACH` kinds.
3. Wreck `module_damage` (`apply_wreck_to_compiled_plan`) runs **after** the last compile and never restamps keys. `ShipGenerator` must not recompile when `structural_plan_validated` is already true.
4. Loaders may trust a persisted `structural_plan_validated` flag plus a non-empty plan; they must not invent a second compile that would drift wreck keys.
5. Runtime fire/decompression consumers damage the compiled `module_key` namespace already registered on `ModuleIntegrityMap`, falling back to `room_id/placement_name` only when no compiled ids exist for the room (goldens without a plan).

## Consequences

- Quality-gate seeds get the same compiled plan as travel-generated ships.
- Wrapper `module_key` meta matches integrity map ids after wreck and live fire.
- A later unlock/door-hack card must overlay costs on the existing plan, not recompile.

## Rejected alternatives

- Keep compile only in `ShipGenerator._load_layout_as_scene` — layout-only paths never compile.
- Wreck stamp before compile — keys cannot name compiler edges that do not exist yet.

## Verification

- `live_decay_stamp_smoke.gd` (`structural_plan_validated`)
- `module_integrity_consequences_smoke.gd` (compiler `edge/` fire ids)
- `multi_source_module_damage_smoke.gd`
