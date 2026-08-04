# Blender Artist Workflow for Structural Sources

This workflow covers editable structural `.blend` sources for the Synaptic Sea
salvage-industrial kit. JSON placement contracts remain authoritative for module
IDs, bounds, sockets, footprint, collision intent, and placement origin. The
`.blend` file is the editable visual source; runtime GLBs are produced only by
the staged export and validation pipeline.

## Opening Source Files

Structural source files live outside the Git checkout so that large editable
Blender files can be backed up independently:

```text
/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.blend
```

1. Open Blender 4.x.
2. Choose **File → Open** and browse to the external source root above.
3. Select a module directory and open its `<module_id>.blend` file.
4. Keep the source file open while iterating. Do not edit the runtime files under
   `assets/imported/structural/` directly.
5. Save the `.blend` in its existing module directory. Keep the matching
   `<module_id>.source.json` record beside it; update source metadata only through
the approved source-authoring tools.

The external root can also be opened from a terminal with:

```bash
/opt/homebrew/bin/blender \
  /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.blend
```

## Material Library

The shared library is:

```text
/Volumes/Untitled/SynapticSeaAssets/meshes/source/materials/salvage_industrial.blend
```

Its materials are:

- `MAT_PaintedAlloyGray` — gray painted alloy, medium metallic response.
- `MAT_WarningStripe` — procedural yellow/black hazard bands.
- `MAT_ReactorGlow` — blue-green emission for reactor and energized details.
- `MAT_Biomatter` — dark red organic surface with subsurface response.
- `MAT_Conduit` — dark, high-roughness rubber for cables and conduits.

To append a material into the open source file:

1. Choose **File → Append**.
2. Browse to `meshes/source/materials/salvage_industrial.blend`.
3. Open the `Material` directory.
4. Select the material by its exact `MAT_*` name and click **Append**.
5. Assign it from the Material Properties panel or the material dropdown.

Append only the material datablock needed by the module. Do not link the
library file into runtime scenes, rename the canonical material names, or bake
source-only helpers into exported geometry.

## Export Process

1. **Open source:** open the module `.blend` from the external source root.
2. **Edit geometry:** modify visual meshes under `Geometry` while preserving the
   module ID, origin, contract bounds, socket empties, and collision helper.
3. **Tag export collections:** put runtime visual geometry in collections named
   `Export_*`. Set each collection's `variant_role` custom property to one of
   `intact`, `damaged`, or `breached`. If no tagged collection is present, the
   exporter uses `Geometry` as the intact fallback.
4. **Run the add-on export:** use the structural module add-on's **Export GLB**
   button. The operator writes staged GLBs and exports only the selected tagged
   visual collections; authoring helpers are not runtime geometry.
5. **Validate:** run the source/GLB validation gates and the Godot import smoke.
   Fix every unexpected `ERROR:`, `WARNING:`, or structural contract mismatch.
6. **Promote:** after validation and review, run the promotion command to copy
   the staged GLB into `assets/imported/structural/`. Use `--backup
   --backup-target <url>` when the external source should be backed up before
   promotion.

Example command-line promotion for one module:

```bash
/opt/homebrew/bin/python3.11 tools/promote_structural_sources.py \
  --project-root /Volumes/Untitled/SynapticSeaAssets/worktrees/the-synaptic-sea-asset-metadata-retrofit \
  --source-root /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0 \
  --staging-root /private/tmp/synaptic-promote \
  --module floor_1x1 \
  --backup --backup-target s3://bucket/synaptic-sea/structural-sources
```

## Validation

Validation checks the machine-readable source contract and the authored source,
not just whether Blender can save a file. The focused source validator checks
that:

- the `.blend` exists and can be opened by Blender;
- the module ID and source record match the contract;
- `ModuleRoot_<module_id>`, `Geometry`, `AuthoringHelpers`, `Origin`, and the
  required `Anchor_SOCK_<socket_id>` empties are present;
- socket positions use the contract-to-Blender coordinate conversion;
- `CollisionProxy` preserves the contract bounds and remains a source-only
  wireframe helper;
- export collections have valid, non-duplicated variant roles;
- staged GLBs are non-empty, have valid GLB data, and re-import in Blender;
- Godot imports the staged GLBs without unexpected errors or warnings before
  promotion.

Common failures and fixes:

| Failure | Fix |
|---|---|
| Missing `Anchor_SOCK_*` | Restore the socket empty from the contract; do not hand-tune its contract position. |
| Socket appears in the wrong place | Reapply `[x, y, z] → [x, z, y]`; Blender is Z-up while the placement contract is Y-up. |
| Missing or changed `CollisionProxy` | Recreate the wireframe box from contract bounds; do not derive it from decorative geometry. |
| No GLB exported | Add a tagged `Export_*` collection with a valid `variant_role`, or keep a `Geometry` intact fallback. |
| Duplicate/invalid variant | Use one collection per role and set the role to `intact`, `damaged`, or `breached`. |
| Empty/invalid GLB | Check that runtime mesh objects are selected and rerun the add-on export into a clean staging directory. |
| Godot import warning/error | Inspect the first reported asset path, repair missing materials/textures or invalid mesh data, then rerun the import smoke. |
| Runtime file changed without review | Restore the staged/runtime boundary and repeat export → validation → promotion; never edit `assets/imported` directly. |

A clean Blender save or a non-empty file is not sufficient evidence for
promotion. Record the command and fresh validator output with the asset review.

## Coordinate Reference

The placement contract uses **Y-up** coordinates. Blender uses **Z-up**. Convert
contract positions and bounds with this exact component mapping:

```text
contract [x, y, z] → Blender [x, z, y]
```

For example:

```text
contract [1.0, 2.0, 0.5] → Blender [1.0, 0.5, 2.0]
```

Apply the mapping consistently to socket locations, bounds, origins, and any
other contract-derived helper. Do not rotate or reinterpret coordinates a
second time during export.
