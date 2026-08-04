# Focused 9 Gameplay-Grade Comparison Batch

**Status:** approved design

## Purpose

Create a deliberately small, reviewable “improved batch” for visual comparison against Synaptic Sea’s current structural-runtime baseline. The batch proves a consistent Salvage Industrial visual language across a locked-isometric room while preserving the existing runtime assets until a separate explicit promotion decision.

The baseline remains available for comparison: all 15 current intact structural GLBs are simple 24-triangle, two-mesh assets. `floor_1x1` is the visual control: its runtime GLB stays unchanged while its external Blender source contains the first gameplay-grade improvement.

## Scope

### Structural visual representatives

These existing structural modules receive new source-only visual geometry while retaining their current contracts, IDs, sockets, origins, collision proxies, and wrapper topology:

1. `floor_1x1` — existing improved control; panel seams, cable channels, drain, access panel, bolts.
2. `wall_straight_1x1` — layered plates, framed recess, vertical service conduit route, localized hazard detail.
3. `doorway_frame_open_1x1` — segmented jambs, lintel mechanism, status-light/indicator bays.
4. `pillar_support_1x1` — reinforced foot and cap, service collar, restrained service markings.
5. `ramp_up_1x2` — tread plates, raised curbs, cable raceway.
6. `ceiling_cap_1x1` — recessed light trough, vent grille, cable tray.

### New gameplay-facing assets

1. `pressure_door_1x1` — new structural module with an explicit contract, source pair, Godot wrapper, and three visual roles: `intact`, `damaged`, `breached`.
2. `hull_breach_seal_point` — objective prop with a repair-facing clamp rig and orange service face.
3. `fire_suppression_station` — objective prop with a red emergency-cabinet silhouette and readable response equipment.

The pressure door expands the structural module allowlist from 15 to 16. New props are visual-only during this batch; they do not receive automatic runtime gameplay bindings or collision claims.

## Explicit non-goals

- Do not overwrite any current runtime GLB during generation.
- Do not automatically bind the new door or props into live Godot gameplay scenes.
- Do not add the five deferred candidates: fabricator workbench, hydroponics grow tray, water recycler, airlock control panel, or heavy cargo container.
- Do not alter the seven legacy structural metadata families or rewrite the historical source/provenance paths during this batch.
- Do not use AI-generated topology as structural source-of-truth geometry.
- Do not turn source-only collision helpers or socket empties into runtime visual meshes.

## Art direction

### Visual pillars

- Readable gameplay silhouettes at the locked-isometric camera distance.
- Salvage-industrial construction: modular blue-gray painted steel, engineered seams, restrained damage, service access, and mechanical purpose.
- One or two clear service/conduit details per module rather than dense nonfunctional greebling.
- Cyan-white functional lighting and orange maintenance/hazard accents; yellow-black hazard stripes only at thresholds, curbs, and service panels.
- Grid-aligned construction that keeps structural connector edges visibly and mechanically clear.

### Shared material usage

Use the existing external material library:

`/Volumes/Untitled/SynapticSeaAssets/meshes/source/materials/salvage_industrial.blend`

- `MAT_PaintedAlloyGray`: dominant plated-metal material.
- `MAT_WarningStripe`: localized threshold and service-hazard marking.
- `MAT_ReactorGlow`: only for controlled functional cyan accents where appropriate.
- `MAT_Conduit`: cable and conduit surfaces.
- `MAT_Biomatter`: excluded from this clean industrial batch.

## Source and staging architecture

### Structural sources

Existing structural sources remain at:

```text
/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module>/<module>.blend
```

Each structural recipe must update only visual meshes under `Geometry`. It must preserve or regenerate deterministically:

- `ModuleRoot_<module_id>` at identity transform;
- `Geometry` and `AuthoringHelpers` collections;
- `Origin` and required `Anchor_SOCK_<socket_id>` empties;
- custom socket data derived from the placement contract;
- a wireframe `CollisionProxy` derived from contract bounds.

Contract coordinates remain Y-up; Blender helper placement uses the one mapping `[x, y, z] → [x, z, y]`.

### New pressure door

`pressure_door_1x1` is a new structural module, not a visual replacement for `doorway_frame_open_1x1`. It needs:

- a new contract in the existing structural-contract location;
- allowlist expansion to 16 module IDs;
- an external source `.blend` plus `.source.json` record;
- an intact/damaged/breached export collection per source convention;
- a structural wrapper with collision, socket markers, and the three visual roles.

The wrapper and runtime paths are generated and validated in the staged batch but do not become live gameplay dependencies before the promotion decision.

### Props

New prop sources live at:

```text
/Volumes/Untitled/SynapticSeaAssets/meshes/source/props/<asset_id>.blend
```

Each prop is authored by deterministic Blender Python and receives:

- a GLB containing visual meshes only;
- a same-basename JSON sidecar following the existing `prop_visual_binding` shape;
- self-authored provenance and a SHA-256, byte size, mesh count, and bounds derived from the staged GLB;
- `collision_policy: "none_visual_only"` until a gameplay integration task explicitly owns collision and bindings.

### Staging and review

Structural GLBs use the existing module staging root consumed by `promote_structural_sources.py`. Props use a dedicated comparison-batch staging root outside `assets/imported/`. The batch records source paths, output hashes, mesh metrics, materials, and preview-render paths in one checked-in comparison report.

## Generation rules

### Deterministic Blender recipes

All nine assets are generated from reusable, parameterized Blender recipe modules. The generator is responsible for additive gameplay-grade geometry: plates, seams, access hatches, conduits, trim, light housings, clamps, curbs, and other explicit hard-surface elements.

Recipes must be idempotent for their generated visual-object names. Reruns replace only generated visual geometry for the target module/prop and must not delete unrelated source helpers or source metadata.

### Triangle budgets

Budgets apply to freshly exported/re-imported runtime GLBs, not only source polygon counts.

| Category | Target runtime triangles | Rationale |
|---|---:|---|
| Structural representative | 350–1,500 | Must read from an isometric camera while leaving headroom for variants and room composition. |
| Gameplay prop | 300–1,200 | Clear interaction silhouette without exceeding the existing objective-prop range. |

A justified silhouette requirement may exceed these values only if the comparison report records the reason and no validation is relaxed.

## Validation and failure handling

### Structural validation

For every structural source and staged export:

1. Run `validate_structural_sources.py` against its contract and source root.
2. Export via the atomic Blender staging path.
3. Verify valid GLB magic, nonempty file, and Blender re-import with nonzero mesh data.
4. Run the standalone staged Godot import validation.
5. Run structural wrapper/variant validation for the new pressure door and the existing representative wrappers.

### Prop validation

For every prop:

1. Verify the Blender source opens and has nonzero renderable mesh data.
2. Export to the dedicated comparison staging root.
3. Re-import the GLB in a clean Blender process.
4. Generate a sidecar from the actual staged file, then validate hash, size, mesh count, bounds, provenance, and visual-only collision policy using `validate_prop_visual_bindings.py`.

### Error behavior

- Missing contracts, source files, helper objects, or source records fail the affected asset.
- Invalid/empty GLBs, invalid GLB magic, duplicate export variants, failed Blender/Godot subprocesses, or invalid sidecars fail the affected asset.
- All writers use temporary files/directories and atomic publish. A failure preserves current runtime assets and prior valid staging artifacts.
- The report must list individual failed assets and their first causal error; it may not report a batch pass with failures omitted.

## Comparison artifact

The batch produces a deterministic locked-isometric comparison render and report:

- Baseline side: current runtime structural assets and existing gameplay-prop stand-ins.
- Improved side: the focused-nine staged assets.
- Evidence: output path, SHA-256, triangle count, mesh count, material names/count, byte size, validator results, and a pass/fail marker for each asset.

The render is design-review evidence only. It does not imply runtime promotion or gameplay integration.

## Promotion gate

Promotion is a separate post-review action. It requires an explicit user approval after inspecting the comparison render and report.

For approved structural assets only, promotion must:

1. back up external sources using the existing backup integration;
2. run staged GLB and Godot validation;
3. atomically copy staged GLBs to `assets/imported/structural/`;
4. run fresh Godot import/wrapper smoke validation;
5. report final hashes and runtime paths.

New props and the pressure-door wrapper/binding remain staged unless their discrete runtime integration is included in the explicit promotion approval.

## Success criteria

The focused-nine batch is ready for review when:

- all six structural representatives and all three new assets have sources and staged exports;
- structural contracts/helpers remain valid;
- all staged assets re-import and validate;
- the pressure door has a valid contract and all three visual roles;
- prop sidecars match their staged GLBs;
- the locked-isometric comparison render/report exists and has no omitted failures;
- no current runtime asset, live gameplay binding, or manifest was modified.
