# Blender room kit v2

Status: implementation in progress; no production promotion approved.

Source: `.hermes/plans/2026-09-08_113552-blender-room-kit-v2.md`, approved for implementation by Christopher.

Execution worktree: `/Volumes/Untitled/SynapticSeaAssets/worktrees/room-kit-v2` on `feat/blender-room-kit-v2` from `d07a4011`. Internal-disk worktree creation failed with ENOSPC; no existing checkout was deleted. External editable candidates remain under `/Volumes/Untitled/SynapticSeaAssets/meshes/source/room_kit_v2`; original structural masters remain unchanged.

## 2. Locked design decisions

### Chosen approach and rejected alternatives

- **Chosen: hand-authored Blender masters with repeatable export and automated contract checks.** Use editable subassemblies, measured dimensions, and a tightly specified art language. This permits actual taste-driven refinement without building a new asset-generation framework.
- **Rejected: automatically add bevels and random greebles to every old mesh.** Cheap, but repeats the current silhouette problem and can obscure traversal.
- **Rejected: regenerate the ship kit through Meshy or switch to a different engine/asset pack.** Structural dimensions and ownership would drift; it does not serve this Blender-first request. Existing purchased assets may be viewed as proportion/material references, not silently copied into self-authored provenance.

### What “prettier” means here

Build readable mid-detail, stylized hard-surface assets—not photorealistic noise, toy blocks, chrome machinery, or neon rooms.

- Primary silhouette: recognizable as a working object even in flat gray. Each prop must have a distinctive negative space or profile, not merely a different colored rectangular box.
- Secondary form: one believable mechanical story per asset—service access, fluid path, mounting, restraint, heat exchange, or operator controls.
- Tertiary detail: restrained fastening/wear; subordinate to silhouette. Detail that only appears in a close-up does not justify repeated runtime geometry.
- Shared construction: planar alloy panels with selective 0.01–0.03 m bevels; large structural edge bevels at most 0.04 m, only inside the frozen contract envelope. Two bevel segments, not subdivision everywhere.
- Small fasteners: at most eight visible bolts per small prop; represent additional screws through texture/normal detail only if later needed. No screws smaller than 0.015 m as separate meshes.
- Cylinders: 16 sides for small hoses/caps, 24 for visible tanks/rollers; no 64-sided hidden cylinders.
- Hose routing: both ends terminate in visible fittings; no unattached rings or hoses passing through unrelated housings.
- Materials: predominantly cool dark alloy; rubber/black service cavities provide value contrast. Safety amber appears in bounded maintenance labels. Cyan/red indicate actual powered/fault state only. Static derelict dressing uses unlit screens, not permanent emission pretending to be a live ship system.
- Wear: at most two local wear zones per base prop. Choose contact-edge scraping and one service/heat stain. Never uniform dirt noise. Structural damage is derived from one master and never rewrites nav/collision.
- Biomatter: optional visual contamination on the existing structural damaged/breached surfaces, subordinate to metal structure. No new animated threats, autonomous tendrils, infestation gameplay, or Meshy jobs in this release.

### Materials and export policy

Canonical existing library: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/materials/salvage_industrial.blend`.

Reuse exact existing datablocks `MAT_PaintedAlloyGray`, `MAT_WarningStripe`, `MAT_ReactorGlow`, `MAT_Biomatter`, `MAT_Conduit`. Do not silently accept `.001` duplicates. A library material with procedural nodes is authoring data, not proof those nodes survive glTF: approved export uses Principled values and real baked textures when needed. In this first batch, model hazard bands as a few contrasting faces; do not depend on an unbaked shader stripe.

For static props, use a named local, non-emissive display material `MAT_RoomKitDisplayOff` with base color `(0.035,0.075,0.085,1)`, metallic `0.0`, roughness `0.28`, emission `0`. Add it through the new feature's material specification and record it as an intentional new material, not as a renamed library material. Do not modify the shared external library just to add it. The only other permitted addition is `MAT_ExposedSteelV2` as explicitly specified in Appendix M; both additions are candidate-local and remain inside the four-material-per-export limit.

Opaque or lightly tinted opaque canopy panels are the default. Transparent refraction is deferred; it complicates sorting and locked-camera readability. Preserve unflattened subassemblies in the `.blend`; flatten transforms on an export copy only. Runtime GLBs are Y-up, meter scale, origin at floor center, front +Z, positive identity object transforms for this static prop set.

### Scope boundary and honest capability

This release produces environment structure and static room dressing. A new oxygen manifold visually explains a life-support space; it does not automatically repair oxygen, create inventory, emit a hazard, or become lootable. Those behaviors remain in existing gameplay owners. Direct prop sidecars remain `collision_policy=none_visual_only`; no gameplay collision, sockets, nav, or system health is smuggled into them.

Static dressing is deliberately non-solid in this batch. Its envelope is understood by placement and visually kept out of reserved traversal/interaction areas, but it does not become a physical obstacle. If a prop must stop the player or support an interaction, that prop's promotion is held for a separately specified wrapper/interaction change; do not describe visual-only art as solid furniture. No new locomotion, multi-cell placement engine, LOD framework, material randomizer, or automatic bake farm.

## 3. Finite deliverable roster and path contract

### Counts

- Improve 15 existing structural base IDs.
- Improve the four existing recent dressing IDs.
- Add twelve distinct dressing IDs.
- Total: **31 editable base-asset masters**, including **12 genuinely new IDs**.
- Structural outputs: 15 intact GLBs plus damaged/breached outputs for the eight already governed triplets = **31 structural GLBs**.
- Props: 16 static GLBs = **47 scoped GLB outputs in total**. State variants are not counted as new asset IDs.
- Preserve the other existing prop GLBs and their bindings. After full promotion the prop inventory becomes 11 components, 28 dressing, 4 objectives = 43 prop GLBs. Inventory tests must compare sets, not just totals.

### Execution roots

After approval, create a new worktree from the inspected feature branch; do not execute in dirty main.

```bash
BASE=/Users/christopherwilloughby/Code/the-synaptic-sea-room-assets
ROOT=/Users/christopherwilloughby/Code/the-synaptic-sea-room-kit-v2
SOURCE=/Volumes/Untitled/SynapticSeaAssets/meshes/source/room_kit_v2
STAGE="$ROOT/assets/_staging/room_kit_v2"
EVIDENCE="$ROOT/artifacts/room_kit_v2"
BACKUP=/Users/christopherwilloughby/SynapticSeaAssetBackups/room_kit_v2
PY=/opt/homebrew/bin/python3.11
BLENDER=/opt/homebrew/bin/blender
GODOT=/opt/homebrew/bin/godot
export BASE ROOT SOURCE STAGE EVIDENCE BACKUP PY BLENDER GODOT
export SRC="$SOURCE" OUT="$STAGE"
RUN_ID="$ROOT/artifacts/room_kit_v2/export-probe"
export RUN_ID
```

No command in this plan runs until execution is authorized. All expected output below is an acceptance target, not output obtained during planning. Unattended Blender/Godot operations may take longer than a task's hands-on 2–5 minutes; do not falsify duration estimates or bypass a gate to meet them.

| Artifact | Exact path rule |
|---|---|
| Structural editable master | `$SOURCE/structural/<id>/<id>.blend` and matching `<id>.source.json` copied from the baseline source tree |
| Prop editable master | `$SOURCE/props/<id>/<id>.blend` |
| Per-master operator record | `$SOURCE/props/<id>/authoring.json` or `$SOURCE/structural/<id>/authoring.json` |
| Structural staging | `$STAGE/structural/<id>/<id>.glb`, and `_damaged.glb`, `_breached.glb` only for the eight triplets |
| Prop staging | `$STAGE/props/<id>.glb` |
| Runtime structural path | `assets/imported/structural/ship_structural_v0/<id>/<id>.glb`; existing variant siblings `<id>_damaged.glb`, `<id>_breached.glb` |
| Runtime structural wrapper | `scenes/wrappers/structural/ship_structural_v0/<id>.tscn` |
| Structural JSON contract | `data/placement/contracts/structural/ship_structural_v0/<id>_contract.json`; `.tres` remains the runtime companion |
| Runtime prop pair | `assets/imported/props/dressing/<id>.glb` and `<id>.sidecar.json` |
| New authored selection/content contract | `data/procgen/dressing/room_kit_v2.json` (Appendix A) |
| Runtime derived index | `data/props/visual_bindings.generated.json` (generated, never hand-edited) |
| Feature / ADR | `docs/game/features/blender_room_kit_v2.md`, `docs/game/adr/0061-blender-room-kit-v2.md` (check number conflict before creating) |
| Review evidence | `$EVIDENCE/<gate>/<case>.png`, raw logs, bounds/inventory JSON, `visual-review.md` |

`authoring.json` records asset ID, artist/reviewer, source-input hashes, intended dimensions, named subassemblies, export settings, tools, materials, and change history. It is an authoring log, not a new runtime schema. Store a backup manifest mapping each master to SHA-256 before promotion. `.blend` binaries remain external; recipe/export/test code and metadata remain versioned.

## 4. Art specifications — no unspecified taste decisions

### A. Structural improvements

Do not change IDs, footprint, floor height, sockets, doorway aperture, wrapper collision, connector compatibility, or compiler placement IDs. Load numbers from the per-ID contract; never infer wall thickness from old visual AABBs. The standing contract in `scripts/procgen/walkability_contract.gd` includes 4 m grid, 0.20 m wall slabs, 1.20 m door opening, 0.35 m player radius, 1.60 m height, and 0.10 m clearance margin.

The detailed surface stays inside the current allowed envelope. A zero-depth wall contract is not permission to inflate collision to match decorative art; preserve its explicit wrapper slabs. If visual envelope and contract disagree, hold that module for review rather than silently widening the contract.

| ID | Required primary/secondary modeling changes | Intact triangulated ceiling | States |
|---|---|---:|---|
| `floor_1x1` | Four large panel fields, 0.02 m recessed central service seam, one edge service strip, flush fasteners; preserve top walking plane | 1,200 | intact/damaged/breached |
| `floor_2x1` | Continue the same panel pitch over the long axis; two removable service panels, no seam discontinuity at 4 m joins | 2,000 | trio |
| `corridor_floor_1x1` | Central readable walking strip, two edge cable trough lids, restrained transverse anti-slip faces | 1,200 | trio |
| `corridor_floor_1x2` | Longitudinal continuation of corridor pattern; one inset maintenance cover off the center line | 2,000 | trio |
| `wall_straight_1x1` | Large upper/lower plate hierarchy, inset service panel, one vertical conduit route with two brackets; no bulge into door lane | 2,400 | trio |
| `doorway_frame_open_1x1` | Layered jambs, recessed gasket, overhead actuator cover, flush threshold cue; keep 1.20 × 2.20 m clear opening | 3,000 | trio |
| `pillar_support_1x1` | Four load ribs, base/ceiling bearing plates, service recess, two clamped cable segments | 2,000 | trio |
| `ramp_up_1x2` | Continuous tread plane, recessed side tracks, directional threshold panels; no raised ribs that snag the capsule | 2,400 | trio |
| `bulkhead_portal_2x1` | Substantial frame, joined service trim, hinge/track covers attached to frame; preserve existing HATCH proxy exactly | 3,500 | intact only |
| `ceiling_cap_1x1` | Recessed tray underside, two vent grille strips, service hatches; no permanent hanging prop below allowed clearance | 2,000 | intact only |
| `doorway_frame_blocked_1x1` | Solid retained closure plate, gasket framing, mechanically believable lock bar; do not pretend it is traversable | 2,800 | intact only |
| `wall_end_cap` | Close wall layers cleanly, one exposed capped conduit, seam alignment with straight wall | 1,500 | intact only |
| `wall_inner_corner` | Continuous inside trim and turned service path; avoid doubled coplanar panels at junction | 2,800 | intact only |
| `wall_outer_corner` | Reinforced outside corner spine, separate meeting panels; match straight-wall pitch | 2,800 | intact only |
| `wall_t_junction` | Three-way structural spine with capped/continued service branches; no stacked duplicate wall planes | 3,500 | intact only |

Budgets above are proposed caps, not measurements. Damage states may use at most the same cap plus 15%, measured on the reimported triangulated GLB. No generic decimation to hit the cap. Each state retains the same anchoring and gameplay collision; cosmetic breaches do not create new traversable holes.

### B. Improved existing props

Dimensions are maximum finished **Godot X width × Y height × Z depth**, meters. Fit the target silhouette naturally; do not squash an export after modeling. All have floor-center origins, front +Z, unit scale and zero placement offset. New identity-normalized exports replace the previous coordinate ambiguity.

| ID | W × H × D envelope | Distinctive form and exact refinement brief | Max triangles |
|---|---|---|---:|
| `fabrication_station_derelict_v1` | 1.80 × 1.85 × 1.10 | Open C-frame work bay; broad worktop over empty knee space; rear tool rail, 3 hanging tool silhouettes, one off-center vise, recessed display, cable terminating at rear service box. Not a closed cabinet. | 5,000 |
| `medical_stasis_pod_derelict_v1` | 2.20 × 1.25 × 1.10 | Horizontal capsule body with chamfered ends; separate opaque canopy rim and inset panel; two curved-looking support cradles made from beveled profiles; latch pairs, side control arm, one hose pair. Not a luminous coffin-sized block. | 5,000 |
| `power_cell_cradle_derelict_v1` | 1.40 × 1.80 × 1.00 | Three separate vertically mounted cells with visible gaps; top/bottom collars, rear busbar, protected disconnected terminals, lower drip tray and warning panel. No glowing cells on a dead ship. | 4,500 |
| `salvage_sorter_derelict_v1` | 1.90 × 1.50 × 1.10 | Asymmetric input hopper → short 5-roller bed → twin output trays; rear motor box, belt guard, sorting gate, one off-center operator panel. It must no longer share the fabrication-station silhouette. | 5,000 |

### C. Twelve genuinely new props

All are floor-standing, static, one-slot visuals; “wall slot” describes a floor cell near a wall, not a new wall-mount transform. Front faces the room interior where possible. Every object uses max four visible material slots after export; minor parts may share a material.

| ID | W × H × D envelope | Assembly recipe and distinguishing features | Eligible existing room roles | Max tris |
|---|---|---|---|---:|
| `oxygen_manifold_derelict_v1` | 1.50 × 1.90 × 0.90 | Twin upright pressure bottles in an open cage; cross-manifold, 2 shutoff wheels, gauge plate, strapped hose loop connected at both ends | life_support, engineering, compartment | 4,000 |
| `coolant_pump_skid_derelict_v1` | 1.80 × 1.20 × 1.10 | Low open skid; horizontal pump body, finned motor, elbow pipe returning into small reservoir; removable perforated guard | engineering, maintenance, reactor | 4,500 |
| `navigation_chart_table_derelict_v1` | 1.80 × 1.15 × 1.10 | Sloped polygonal chart surface, split pedestal supports, raised rim, non-emissive recessed chart panel; one hinged-looking access panel closed | bridge, cockpit, navigation | 4,000 |
| `scanner_signal_cabinet_derelict_v1` | 1.30 × 2.00 × 0.90 | Staggered receiver drawers, ventilated top, thick rear cable trunks and small fold-out-looking but static operator shelf; no dish inside room | bridge, engineering, scanner | 4,000 |
| `hydroponic_grow_tray_derelict_v1` | 2.00 × 1.40 × 1.10 | Raised tray, 6 recessed plant cups, dry root/substrate clumps, two end supports carrying an unlit lamp bar; no dense foliage curtain | life_support, hydroponics, compartment | 4,000 |
| `water_reclaimer_derelict_v1` | 1.60 × 1.70 × 1.00 | Vertical filtration tower beside lower sump; three removable filter canisters, one U-pipe, service hatch; distinct from twin-bottle oxygen manifold | life_support, hydroponics, maintenance | 4,500 |
| `galley_heater_derelict_v1` | 1.50 × 1.35 × 1.00 | Two deep circular heating wells, rear splash panel, small vent hood attached to body, sealed oven hatch and chunky knobs | mess_hall, crew_quarters, quarters | 3,500 |
| `crew_bunk_derelict_v1` | 2.20 × 1.50 × 1.10 | Single suspended bunk in angular end frames; thin segmented cushion, foot storage drawer, restrained folded fabric, attached reading lamp off; no second deck | crew_quarters, quarters, compartment | 4,000 |
| `suit_service_stand_derelict_v1` | 1.30 × 1.90 × 1.00 | Empty human-proportioned hanger yoke, boot rests, service hose loop, vertical back rail and offset equipment tray; no human or suit mesh | maintenance, armory, storage | 3,500 |
| `sample_quarantine_cabinet_derelict_v1` | 1.40 × 1.75 × 0.90 | Tall sealed chamber with 2 glove-port rings, opaque observation insert, 3 visible sealed sample holders on lower shelf, two caution latches | medical, medbay, life_support | 4,000 |
| `gravity_coil_housing_derelict_v1` | 1.80 × 1.50 × 1.10 | Horizontal annular coil framed by two heavy side supports; split service casing, visible insulated windings in one bounded window, power terminal blank | engineering, reactor, compartment | 4,500 |
| `cargo_restraint_frame_derelict_v1` | 2.20 × 1.70 × 1.10 | Empty asymmetric cargo frame on a floor pallet; two over-center clamps, restrained diagonal straps anchored to frame, no generic crate filling its silhouette | cargo, storage, bay, hangar, tool_storage | 3,500 |

These are room-scale assemblies, not duplicates of detachable components such as `pump_assembly`, `air_recycler_unit`, or `sensor_rack`. The existing component remains its own repairable gameplay item. The new assembly is a surrounding visual apparatus and receives no component ID alias.

### D. Repeatable Blender construction instructions

Each action below is a separate 2–5 minute work item. Execute the entire sequence for each row, using that row's exact ID and dimensions. It is an explicit reusable work order, not “make it look good.”

1. **Create/save master:** File → New → General; remove default cube/camera/light in this new scratch scene only. Units: Metric, scale 1. Create `Geometry`, `AuthoringHelpers`, and `Export_Static` collections. Save to the exact prop master path. Add source-only floor plane outline and envelope wire box to `AuthoringHelpers`; never export helpers.
2. **Primary mass:** Model the named primary silhouette to 85–95% of its target envelope. Use the specified open spaces; for a C-frame use separate uprights + beam, for cages use posts/rails, for tanks use 24-sided cylinders. Put local front at Blender -Y, height +Z. Add object names `<id>__<part>` with no arbitrary numeric names.
3. **Secondary assembly:** Add the named apparatus in the table in order. Keep fittings physically attached; give vents depth through inset/recess rather than many floating slats. Model the sorter hopper as a tapered open mesh using inset + extrusion, not a filled cube. Model pod ends as an eight-vertex chamfered profile, not a rounded rectangle with a glow material.
4. **Tertiary pass:** Add at most eight 0.015–0.035 m fastener heads at actual joint locations, one service panel, and the specified localized wear faces. Bevel only light-catching external edges 0.01–0.03 m, 2 segments. Apply scale before bevel. Avoid destructive booleans as the default construction method.
5. **Material/value pass:** Append approved materials; verify exact names. Assign major housing alloy, cavities/hoses conduit, warning faces selectively, displays off. At least one large dark/light value break supports the primary silhouette. Do not add unrestricted emission.
6. **Cleanup/UV:** Remove hidden internal faces only where not needed by silhouette; merge accidental duplicates, recalculate outward normals, apply modifiers deliberately. Unwrap non-overlapping UV0 with 4-pixel-equivalent padding at 1024; no bake is required for flat Principled materials. Leave useful subassemblies separate in the source; do not flatten the master.
7. **Preview/review:** Save a front, side, and locked-isometric viewport capture using the same framing per asset; compare flat-gray silhouette before beauty lighting. Reviewer checks every table feature and rejects rectangular-box substitutions. Record revisions in `authoring.json`.
8. **Export/prove/commit:** Execute the static-export recipe and artifact/runtime gates below. Back up the master. Commit only this asset's approved runtime pair plus its metadata updates after the staging gate; do not batch-stage unrelated assets.

Structural modeling uses the same primary/secondary/tertiary discipline, but starts by copying the per-module recovered master (never File → New), locks all helpers, and edits only visual collections. For each structural row, split the work into: open/copy; major panels; service layer; materials; source validation; state derivation (if specified); export; seams/walkability review. Do not change helpers to make a failed visual fit.


| Gate | Required evidence | Reject when |
|---|---|---|
| Source | 31 editable masters, input provenance, source backup hashes | Only GLBs exist; source overwritten; rights relabeled |
| Structural | Per-ID contracts/helpers, all-angle seams, eight real state trios, unchanged structural inventory and collision behavior | Missing anchors, intact reused for all states, duplicate physics, changed topology |
| Static prop geometry | 16 normalized GLBs, real assembled bounds, correct floor pivot/up/front, triangle/material counts | Accessor-only apparent pass on translated parts, lying sideways, whole prop floating, export helper leakage |
| Metadata | Exact adjacent pairs, hashes fresh, derived index deterministic, baseline inventory preserved | Arbitrary allowlist relaxation, stale hash, duplicated gameplay authority |
| Selection | Actual role-aware deterministic choices; safe skips; coverage for all IDs | Unused metadata fields, phantom roles, forced coverage by editing goal rooms |
| Occupancy | Real nodes and components/loot/objectives/ambient dressing share safe slot accounting | Same cell used twice, dressing steals essentials, door/interact lane obscured |
| Visual | Pilot plus six production-case images, native game-size readability, signed per-family review | A box with a different color, floating hardware, noisy surfaces, faux powered machines, empty/synthetic captures |
| Performance | Same-scene before/after measurements and per-asset budgets | Budget changed after failure, improvement asserted without measurement |
| Release | Fresh full gates on integration commit and per-ID target manifest | Staging called shipped, main checkout implicitly overwritten, unreviewed promotion |

Visual rubric, 0–2 per item: silhouette recognizability; convincing assembly; material/value hierarchy; purposeful wear; route/interaction readability. Pass requires at least 8/10, no zero, and no hard blocker (collision/clearance/provenance/state/geometry error). Reviewer identifies the entry, threshold and intended apparatus in the unlabelled pilot capture before reading the asset list. This is an approval method, not an automated promise of human recognition speed.

## 8. Risks, tradeoffs and open decisions

- **Known structural baseline defects:** stop affected structural promotion and integrate reviewed contract fixes; do not pretend this plan repaired them. Art-only prop work can still progress.
- **Visual-only furniture:** optional dressing is not solid or interactive. Making it solid requires explicit runtime collision/nav authority and new tests, outside this batch. This limitation must appear in handoff, not be hidden behind “procgen-ready.”
- **Static normalization vs general GLB support:** deliberately smaller than rewriting the scene-bounds parser. Reject animations/armatures/morphs and nonidentity export transforms; route such assets to their existing specialized pipeline.
- **Room semantics:** use actual normalized roles from current generation. A derelict “medical” role means historical purpose, not functioning treatment machinery. Do not alter ship-system health or role assignment for an art demo.
- **Shared source volume:** unavailable volume blocks source work; do not silently create a similarly named local substitute. Disk failure is mitigated by the separate backup.
- **Subjective art quality:** numerical budgets cannot prove beauty. Pilot review is mandatory before broad production; the chosen direction is salvage-industrial, not a new style vote.
- **Scope choice:** this is an environmental kit, not a complete character/enemy/UI/audio asset list. Existing threat/loot Meshy contracts, animation pipelines, and top-down experiments stay untouched.
- **Open at execution, not invented now:** exact accepted baseline failure classifications; benchmark results; reviewer identity; ADR number if another lane has occupied 0061. Any missing source or unresolved ownership conflict yields HOLD for the affected gate, not fabricated results.

## Execution boundaries

Pilot: four structural masters (floor_1x1, wall_straight_1x1, doorway_frame_open_1x1, pillar_support_1x1) and three props (fabrication_station_derelict_v1, coolant_pump_skid_derelict_v1, suit_service_stand_derelict_v1). Only pilot geometry is authorized before a recorded scored visual review. Tooling may proceed independently. Original structural baseline failures hold affected promotion; no wrapper/contract repairs are implicit.

Execution path corrections: STAGE is `assets/_staging/room_kit_v2`; prop staging is `STAGE/props/<id>.glb`; evidence is `artifacts/room_kit_v2`. Static export API is `--source <blend> --output <glb>`. Blender commands use `--python-exit-code 1`. These replace inconsistent example aliases in the plan without changing asset scope.
