# ADR-0060: Restore Locked-Isometric 3D Production Path

- Status: Accepted
- Decision owner: Christopher
- Confirmation date: 2026-09-02
- Supersedes in part: ADR-0048

## Context

The canonical superseded artifact is `docs/game/adr/ADR-0048-top-down-pivot.md` (`ADR-0048: Top-down Pivot`). It pivoted the sole production art path from locked-isometric 3D to orthogonal top-down 2D, established the `scenes/topdown` tree and top-down presentation stack, made the Winlu tileset the authoritative environment art for that path, and declared the existing locked-isometric 3D surfaces and 3D vertical-slice work non-production.

This ADR restores locked-isometric 3D as the production presentation and asset path without deleting or invalidating the existing 2D implementation or the presentation-agnostic simulation work. The lowercase-path artifact `docs/game/adr/0048-mermaid-architecture-diagram-source-and-svg-exports.md` reuses the number 0048 for an unrelated Accepted Mermaid diagram-source decision; it is unaffected by this ADR and remains fully in force.

## Decision

Restore locked-isometric 3D as the production presentation and asset path for the game. The existing orthographic/isometric gameplay camera is locked and remains the authoritative gameplay camera and runtime-review viewpoint. New 3D work must follow the authority and transition ordering below; this ADR does not make an ungoverned provider output or an existing unpromoted asset production-authoritative.

### Retained versus superseded ADR-0048 decisions

The following table is the complete boundary of this partial supersession:

| ADR-0048 area | Prior decision | ADR-0060 disposition |
| --- | --- | --- |
| Production art path | Orthogonal top-down 2D was the sole production path. | **Superseded/demoted.** Locked-isometric 3D is restored as the production path. The 2D implementation remains a supported legacy/alternate path. |
| Presentation-stack authority | The top-down-only presentation stack, including the `scenes/topdown` tree and top-down camera/controller/threat-manager surfaces, was authoritative. | **Superseded/demoted.** The locked-isometric presentation and camera are authoritative for production and runtime review; the top-down stack remains supported as legacy/alternate 2D implementation. |
| Environment art | Winlu tiles were globally authoritative environment art for production. | **Superseded/demoted.** Winlu is retained only for the legacy/alternate 2D path; it is not global authority for restored 3D production. |
| Locked-isometric and 3D surfaces | The locked-isometric harness and camera, 3D structural wrappers, and imported GLBs were frozen smoke-only, with no new 3D assets. | **Superseded/demoted.** The freeze is lifted for governed production work. The locked-isometric harness/camera, 3D wrappers, and imported GLBs may be used through ADR-0058; new 3D assets remain subject to that authority chain. |
| Existing 3D vertical slice | Existing 3D vertical-slice work was declared non-production. | **Superseded/demoted.** That blanket presentation-path declaration no longer governs the restored path, but existing work is not automatically promoted; it must satisfy ADR-0058 review and promotion requirements. |
| Simulation loops | The 18 simulation loops were retained. | **Retained unchanged.** |
| Persistence and services | Save/load, the audio manager/router, schema files, and the inventory/smoke pipeline were retained. | **Retained unchanged.** |
| Validation contract | The vertical-slice contract was retained. | **Retained unchanged.** |
| 2D implementation | The top-down implementation was created and supported by the pivot. | **Retained as a supported legacy/alternate path.** It is not deleted, and it is not the authority for restored 3D production. |

No other ADR-0048 decision is changed by this ADR unless the table says so explicitly.

### Authority and transition ordering

1. **ADR-0058 governs now.** Accepted ADR-0058 owns the pipeline boundary: Meshy is candidate-only; Blender is the visual master/export authority; and Godot wrappers plus repository runtime data own sockets/connectors, collision, navigation, integrity/damage, VFX/animation integration, and gameplay bindings. Exported visual GLBs must not carry runtime-authority socket or helper markers. ADR-0058's workflow and ownership remain authoritative for every 3D asset and promotion decision.
2. **Proposed ADR-0059 does not override ADR-0058.** ADR-0059 is still Proposed and its conflicting language that Blender/GLBs own socket markers is design intent only, not production authority. ADR-0058 takes precedence over that conflict until the transition below is complete.
3. **Task 1 must reconcile ADR-0059 before later architectural consumption.** Task 1 must reconcile ADR-0059 and the feature docs to repository/Godot socket authority, visual-only GLBs, and an explicit graph/per-manager assembler. Only after that reconciliation is complete may ADR-0059 be set to Accepted; later tasks must not consume it as architecture authority before then. This ADR does not imply that Task 1 has already happened.

Neither this ADR nor a provider output bypasses ADR-0058. The locked-isometric camera remains locked while 3D assets and assembled threats are reviewed in the real runtime environment.

### Pilot and lifecycle transition

ADR-0058's initial pilot scope remains authoritative for workflow and ownership and names these five IDs: `stalker_v1`, `hull_tendril_kit_v1`, `biomatter_swarm_kit_v1`, `loot_container_derelict_v1`, and `crafting_station_derelict_v1`.

The lifecycle transition is narrower than the pipeline decision:

- Existing artifacts for the three singular-threat IDs (`stalker_v1`, `hull_tendril_kit_v1`, and `biomatter_swarm_kit_v1`) remain readable as historical evidence, including their historical verification.
- After the Task 2 lifecycle record is merged, new planning and generation for those three singular-threat IDs is retired. This ADR does not claim that the Task 2 lifecycle record has already been merged.
- `loot_container_derelict_v1` and `crafting_station_derelict_v1` remain active pilot families for planning and generation under ADR-0058.

### Visual direction

The restored 3D production direction is **stylized low-poly**. Asset decisions prioritize clear silhouette, gameplay readability, and strong shape language over micro-detail. Geometry, materials, and lighting should support the locked-isometric view and preserve readable threat identity at gameplay distance.

## Consequences

- Locked-isometric 3D is again the production presentation and the camera basis for runtime review.
- Top-down 2D remains available as a supported legacy/alternate presentation and implementation; it is not deleted or treated as the 3D authority.
- Winlu remains useful for legacy/alternate 2D environment art but is no longer global environment-art authority.
- New production GLBs and 3D assets are permitted only when they satisfy ADR-0058's governed pipeline and the applicable reconciled architecture contracts.
- Existing singular-threat artifacts remain historical evidence; after the Task 2 lifecycle record is merged, new planning/generation for those three IDs is retired while loot and crafting stations remain active.
- Stylized low-poly assets reduce visual noise and keep silhouette/readability ahead of micro-detail.
- Existing gameplay systems and camera assumptions remain stable because the orthographic/isometric camera is locked rather than redesigned.

## References

- `docs/game/adr/ADR-0048-top-down-pivot.md` — `ADR-0048: Top-down Pivot` (partially superseded here)
- `docs/game/adr/0048-mermaid-architecture-diagram-source-and-svg-exports.md` — unrelated Accepted Mermaid architecture-diagram source ADR; unaffected by ADR-0060
- `docs/game/adr/0058-meshy-candidates-blender-authority.md` — `ADR-0058`: Meshy Candidates, Blender Canonical Masters, and Godot Runtime Authority
- `docs/game/adr/0059-procedural-biomass-assembly.md` — `ADR-0059`: Procedural Biomass Assembly — Modular Body-Part Threats (Proposed pending Task 1 reconciliation)
