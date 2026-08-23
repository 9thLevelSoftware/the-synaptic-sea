# ADR-0056: ModularSocketCatalog missing-kit fallback

- **Status:** Accepted
- **Date:** 2026-08-23
- **Supersedes / amends:** none. Does not reopen ADR-0053 (enclosure geometry) or ADR-0052 (asset metadata / visual binding).
- **Related:** feature `docs/game/features/hive_biomatter_kit.md`; REQ-HIVE-001; remaining play stack `docs/game/features/remaining_procgen_play_stack.md`

## Context

Hive stamps `kit_id=ship_structural_biomatter` but this milestone does not ship a unique biomatter contract directory or unique meshes. Hazard and industrial kits likewise have no wrapper-map / contract dir. Placement still needs authored sockets (kinds, `compatible_kinds`, local positions) so occupancy stays on v0 geometry.

A kit-id stamp without a socket catalog would either fail closed (no sockets, no wrappers) or invent biomatter-only meshes, both of which are out of scope.

## Decision

1. `ModularSocketCatalog` is the runtime consumer of structural socket contracts. `load_kit(kit_id)` loads `data/placement/contracts/structural/<kit_id>/`.
2. If that directory is missing or yields no modules, the catalog loads `ship_structural_v0` and binds `kit_id` to `DEFAULT_KIT_ID`. Callers must not synthesize unique meshes for the missing kit.
3. `sockets_compatible` is mutual `compatible_kinds` membership for both equal and differing kinds. Authored lists are authoritative; same-kind is not an automatic join (inner/outer corner vertex sockets list only `wall_edge` / `portal_edge`).
4. Wrapper-map absence in `ShipGenerator` remains a separate fallback to `ship_structural_v0.json` scene paths. Catalog fallback does not replace that path.

## Consequences

- Biomatter hive layouts reuse v0 sockets and v0 wrapper scenes.
- Adding a real biomatter contract dir later is additive: `load_kit` succeeds without hitting the v0 fallback.
- Placement code that used same-kind as a free join must go through `compatible_kinds`.

## Rejected alternatives

- Ship a unique biomatter contract/mesh set this milestone — out of scope (no unique meshes).
- Fail `load_kit` when the kit dir is missing — hive occupancy would have no sockets.
- Expand `LayoutSerializer` keys for kit sockets — contracts stay on disk, not in layout.json.

## Verification

- `hive_biomatter_kit_smoke.gd` (`sockets_fallback=true`, catalog `load_kit("ship_structural_biomatter")` binds v0, `sockets_compatible` rejects same-kind inner-corner joins)
