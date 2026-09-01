# Loot Container Derelict v1 — Candidate 1 Blender Master

Status: Approved design

Requirements: REQ-AIAP-005, REQ-AIAP-006, REQ-AIAP-007, REQ-AIAP-009

Selected Meshy task: `01a05dcb-fc3b-7418-b105-2170af354088`

## Purpose

Turn the selected closed Meshy candidate into one editable, functional Blender master that preserves the candidate's readable chest silhouette while deriving the required `closed`, `open`, and `looted` visual states. This phase produces staged visual evidence only. It does not promote an asset or change Godot runtime data.

## Inputs and authority

- The selected candidate's governed `raw.glb` is the only visual donor.
- The immutable raw mesh remains hidden in the master under `SOURCE_RAW`.
- Blender owns deliberate cleanup/reconstruction, UVs, materials, dimensions, pivot, the lid hinge, state derivation, and normalized GLB export.
- Godot wrappers remain authoritative for collision, interaction, inventory state, navigation, sockets, integrity, and gameplay behavior.
- AI provenance remains `meshy` / `paid-private`; Blender cleanup does not relabel the asset as self-authored.

## Chosen approach: functional low-poly rebuild

Use Candidate 1 as the shape-language reference, but deliberately reconstruct the production visual from clean low-poly components rather than decimating or cutting the generated mesh. Preserve these selected characteristics:

- compact rectangular case;
- strong lid/body separation;
- U-shaped front handle;
- two readable front latches;
- reinforced corner/edge treatment;
- restrained derelict sci-fi detailing suitable for the locked-isometric camera.

The reconstruction must remain visibly faithful to Candidate 1 while replacing generated topology with purposeful, editable geometry.

## Scene structure

The canonical master is:

`/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/loot_container_derelict_v1_master.blend`

Required collections and objects:

- `SOURCE_RAW`: hidden immutable imported candidate.
- `WORKING`: clean production hierarchy.
- `EXPORT`: exportable visual hierarchy only.
- `SOCKETS_MARKERS`: non-exported origin/forward authoring markers.
- `ContainerRoot`: identity-transform export root with state metadata.
- `ContainerBody`: lower shell and interior cavity.
- `HingePivot`: rear hinge parent for the lid.
- `ContainerLid`: separable lid parented to `HingePivot`.
- `FrontHandle`: U-shaped readable handle.
- `LatchLeft` and `LatchRight`: paired front latches.
- `LootVisual`: small non-gameplay visual insert that the Godot wrapper may show for the open/unlooted presentation and hide for looted.

No collision, navigation, interaction area, gameplay socket, or structural helper may be exported.

## Geometry and coordinate contract

- Closed visual bounds: `(X, Y, Z) = (0.90, 0.55, 0.65)` metres within `0.01 m` per axis.
- Bottom-center pivot: X/Y bounds centered on zero and minimum Z at zero.
- Exported node transforms: applied, finite, positive-orientation, canonical local `+Z`.
- Maximum triangles: `3,000`; design target: at most `1,500` triangles to leave room for later visual refinement.
- Maximum materials: `2`.
- Every exported primitive has finite UV0 coordinates within `[0, 1]`.
- Construction uses deliberate primitive topology and bevels; generic auto-decimation is not an acceptance method.
- The default exported pose is `closed`.

## Materials

Use two simple Blender materials without generated textures:

1. `painted_ship_alloy`: cool desaturated grey-blue body and lid.
2. `warning_accent`: muted orange/red latch, handle, and loot accents.

Materials are preview-quality geometry gates, not final texture approval. A later texture packet remains separately governed.

## State derivation

All states derive from the same objects in the same master:

- `closed` — frame 1: lid at 0 degrees; latches and handle readable; `LootVisual` hidden by the authored state presentation.
- `open` — frame 30: lid rotates approximately 105 degrees around `HingePivot`; interior and `LootVisual` are visible.
- `looted` — frame 60: lid remains open; `LootVisual` is hidden.

The master stores one `lid_open` action and root custom properties describing the three required states, hinge axis, and state frames. Runtime visibility and inventory truth remain wrapper-owned. The GLB must not duplicate complete closed/open/looted meshes; one hierarchy supplies the states.

## Outputs

External editable/source evidence:

- canonical `.blend` master;
- deterministic authoring script/recipe;
- closed/open/looted preview renders;
- geometry/state manifest with source hash, dimensions, triangle count, material inventory, object hierarchy, state frames, and decoded-pixel hashes.

Governed task-local outputs after visual approval:

- `cleaned.glb` in the selected task directory, exported in the closed default pose with the lid hierarchy/action and metadata;
- `blender-validation.json`, published only by the independent validator after Blender re-import of the same GLB.

No output is written to `assets/imported`, `data/combat`, `data/props`, `scenes/wrappers`, or any live catalog/index.

## Error handling and stop conditions

Stop without promotion if any of the following occurs:

- source task/review identity mismatch;
- missing or changed governed raw candidate;
- external master path is outside the trusted source root;
- candidate silhouette is no longer recognizable;
- incorrect dimensions, pivot, forward axis, or non-applied transform;
- more than 3,000 triangles or two materials;
- missing/invalid UV0;
- lid cannot open cleanly around one hinge;
- state implementation duplicates complete meshes;
- exported helper/collision/gameplay geometry;
- Blender/host validator disagreement;
- non-deterministic decoded preview pixels;
- any attempted runtime promotion during this phase.

## Verification and acceptance

1. Build the master twice from the same selected raw candidate and recipe in disposable output roots.
2. Compare geometry/state manifests and decoded RGBA preview hashes.
3. Visually inspect closed, open, and looted renders before accepting the export.
4. Export task-local `cleaned.glb` only after visual approval.
5. Run:

   `/usr/bin/python3 tools/meshy_blender_validate.py --project-root . --contract data/asset_generation/contracts/loot_container_derelict_v1.json --task-dir assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088 --glb assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088/cleaned.glb --report assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088/blender-validation.json`

6. Verify the selected candidate record after validation.
7. Confirm tracked repository files and protected runtime paths are unchanged except for this approved feature spec.
8. Require an independent artifact review before runtime review or any promotion proposal.

## Non-goals

- Final PBR texturing.
- Runtime collision or interaction implementation.
- Godot wrapper/catalog/index changes.
- Runtime promotion.
- New Meshy generation or duplicate provider calls.
- Independently generated alternate states.
