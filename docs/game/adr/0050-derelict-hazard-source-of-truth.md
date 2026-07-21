# ADR-0050: Derelict Hazard Source of Truth

## Status

Accepted

## Context

Procgen `LayoutSerializer` emits empty `fire_zones` / `breach_zones` / often empty `arc_zones`. Golden fixtures may hand-author hazard markers. The live coordinator seeds derelict fire/breach at attach time (`_seed_derelict_fire`, `_seed_derelict_breaches`) and builds arc zones from home/derelict paths separately. Validation and tooling were confused about which source is authoritative.

## Decision

1. **Runtime seeding is authoritative** for derelict **fire** and **breach** hazards during play.
2. Layout arrays are **optional overlays** for hand-authored goldens / future content tools.
3. Procgen stamps `hazard_source: "runtime"` on generated layouts so tooling can distinguish pipeline output from curated fixtures.
4. Arc zones may still be dual-sourced (layout markers when present; otherwise runtime/home wiring) as already implemented post-Tranche-1.

## Consequences

- Smokes must not require non-empty layout fire/breach for procgen-generated ships.
- Goldens may keep authored markers for narrative hazard placement.
- Quality gate checks `hazard_source == "runtime"` on pipeline output.
