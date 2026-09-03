# ADR-0060: Restore Locked-Isometric 3D Production Path

- Status: Accepted
- Decision owner: Christopher
- Confirmation date: 2026-09-02
- Supersedes in part: ADR-0048

## Context

ADR-0048 pivoted the production art path from locked-isometric 3D to orthogonal top-down 2D. The project now has a governed 3D asset pipeline and a procedural biomass assembly direction that require the original locked-isometric presentation to be restored as the production path.

This ADR reverses only the relevant presentation and production-path portions of ADR-0048. It does not discard the existing 2D work or change the simulation systems that are presentation-agnostic.

## Decision

Restore locked-isometric 3D as the production presentation and asset path for the game. The existing orthographic/isometric gameplay camera is locked and remains the authoritative gameplay camera and runtime-review viewpoint.

### ADR-0048 clauses superseded in part

This ADR supersedes these exact ADR-0048 clauses:

1. **Top-down 2D as the sole production path:** the statement that the production art path is orthogonal top-down 2D is superseded. Top-down 2D remains supported as a legacy and alternate presentation, but it is no longer the sole production path.
2. **Locked-isometric freeze:** the ADR-0048 designation of `scenes/validation/locked_iso_readability_harness.tscn` and `scripts/camera/iso_camera_rig.gd` as frozen, smoke-only 3D surfaces is superseded. The locked-isometric camera and 3D runtime path are production-authoritative again.
3. **Prohibition on new production GLBs:** the ADR-0048 prohibition on ordering or adding new production GLB assets is superseded. New 3D assets may proceed only through the governed authority chain in ADR-0058 and the modular assembly contract in ADR-0059.

All other ADR-0048 decisions remain in force unless explicitly changed by a later ADR.

### 3D authority

ADR-0058 and ADR-0059 govern 3D asset and runtime authority:

- **ADR-0058** governs the candidate-only Meshy boundary, canonical Blender masters, staged validation, provenance, runtime review, promotion, and Godot/repository-data ownership of collision, navigation, sockets, integrity, animation/VFX integration, and gameplay bindings.
- **ADR-0059** governs procedural biomass assembly, modular body-part categories and sockets, recipes, locomotion hints, and the replacement of singular creature models with assembled threats.

Neither this ADR nor a provider output bypasses those contracts. The existing orthographic/isometric gameplay camera remains locked while 3D assets and assembled threats are reviewed in the real runtime environment.

### Visual direction

The 3D production direction is **stylized low-poly**. Asset decisions prioritize clear silhouette, gameplay readability, and strong shape language over micro-detail. Geometry, materials, and lighting should support the locked-isometric view and preserve readable threat identity at gameplay distance.

## Consequences

- Locked-isometric 3D is again the production presentation and the camera basis for runtime review.
- Top-down 2D remains available as a legacy/alternate presentation and is not deleted or treated as the 3D authority.
- New production GLBs are permitted only when they satisfy ADR-0058's governed pipeline and the relevant ADR-0059 biomass assembly contracts.
- Stylized low-poly assets reduce visual noise and keep silhouette/readability ahead of micro-detail.
- Existing gameplay systems and camera assumptions remain stable because the orthographic/isometric camera is locked rather than redesigned.

## References

- ADR-0048: Top-down Pivot — Supersedes ADR-0010/0017
- ADR-0058: Meshy Candidates, Blender Canonical Masters, and Godot Runtime Authority
- ADR-0059: Procedural Biomass Assembly — Modular Body-Part Threats
