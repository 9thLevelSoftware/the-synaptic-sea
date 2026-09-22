# Functional Room and Derelict Asset Set — Production Implementation Plan

> **For Hermes:** Use subagent-driven-development to execute the approved plan task by task. Use separate spec-compliance and code-quality reviews. This document is a plan, not permission to submit provider jobs or promote assets during the planning turn.

**Goal:** Deliver a coherent, editable, validated modular asset library that builds readable, traversable Synaptic Sea rooms and playable derelicts using the existing Blender, Meshy, and Godot pipelines.

**Architecture:** Reuse `ship_structural_v0` and the existing prop library; qualify and improve assets rather than build another generator. Blender owns structural geometry and editable prop masters, Meshy supplies non-structural visual candidates, and existing Godot wrappers and gameplay owners retain collision, navigation, sockets, interaction, and persistence. Prove one room first, expand to a connected five-room derelict, then promote reviewed assets and repeat the proofs through the production consumers.

**Tech stack:** Godot 4.7.1, Blender, repository Python tooling, pytest, JSON asset contracts, GLB, external `.blend` masters, Git worktrees.

---

## 1. Context, authority, and limits

### Verified during planning

Repository: `/Users/christopherwilloughby/Code/the-synaptic-sea`.
Inspected main HEAD: `2205a33d` (`docs: fix reconciliation review findings`).

The checkout is dirty. Tracked changes include `.DS_Store`, `addons/derelict/bin/macos/libderelict_godot.dylib`, `docs/game/05_requirements.md`, and `docs/game/adr/README.md`; there are many untracked imports and other files. These are not permission to clean, overwrite, stash, or commit another person's work. Existing sibling worktrees are also not disposable scratch space.

Live source findings:

- `data/kits/ship_structural_v0.json` declares 15 modules on a 4.0 m grid. `tools/structural_source_contract.py` has the same 15-module recovery/promotion allowlist.
- External structural source directory exists at `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0`. Its directory roster also contains the separate `pressure_door_1x1` candidate. Directory presence is not source validity.
- `tools/focused_nine_contract.py` covers seven structural candidates plus two props. Six structural candidates overlap the 15-module production kit; `pressure_door_1x1` does not. Do not pretend the focused-nine batch is a complete room kit.
- `data/props/visual_bindings.generated.json` contains 11 component assets, 11 dressing assets, and four distinct objective assets. Multiple binding aliases do not count as additional models.
- The loot pilot at `assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088/` has `review.json` state `promotion_ready`, `blender-validation.json` status `PASS`, and a proposal-only `sidecar-overlay.json`. Its recorded GLB has 792 triangles and two materials. These are historical records, not fresh approval for the current checkout.
- `tools/meshy_blender_master.py` imports and organizes a selected candidate into `SOURCE_RAW`, `WORKING`, `SOCKETS_MARKERS`, and `EXPORT` and saves a master. It does NOT perform the artist's cleanup, UV work, state derivation, or final GLB export for them.
- `scripts/placement/gameplay_prop_factory.gd` creates a primitive `Mesh` even when a GLB loads as a PackedScene, then attaches `CatalogMesh` as its sibling. Existing owners such as `scripts/tools/loot_container.gd` hide only `Mesh`; naïve GLB binding therefore produces duplicate geometry and incorrect hide behavior. Task C fixes this before production binding.
- `tools/generate_prop_sidecars.py` and `tools/validate_prop_visual_bindings.py` have explicit governed inventory counts. Adding GLBs without registering them breaks validation; `--write-missing` is not a safe Meshy promotion route because its default provenance is self-authored.
- `scripts/validation/coherent_proof_ship_capture.gd` requires a real viewport capture. `procgen_playable_ship_capture.gd` can produce a diagnostic map fallback: do not call that fallback an art screenshot.

No Blender run, Godot import, test suite, provider call, or runtime promotion was performed during planning. Commands and expected results below are future acceptance criteria, not claimed results.

### Source reading order for a zero-context implementer

1. `AGENTS.md` — repository workflow and warning policy.
2. `docs/game/features/ai_candidate_asset_pipeline.md` and `docs/game/06_validation_plan.md` — current Meshy lifecycle and canonical regression command.
3. `docs/game/features/blender_artist_workflow.md` — source collections and coordinate conversion. Its example worktree and Blender version are historical; use this plan's isolated workspace and verified executable instead.
4. `tools/structural_source_contract.py`, `tools/export_structural_glb.py`, `tools/promote_structural_sources.py` — supported modules and source/export boundary.
5. `tools/focused_nine_contract.py`, `tools/focused_nine_batch.py` — comparison-only recipe batch.
6. `data/placement/contracts/structural/ship_structural_v0/` — actual bounds, sockets, footprint, and pivot authority. Old catalog `source_blend` strings point to an earlier project; do not use them instead of the verified external source root.
7. `scripts/placement/gameplay_prop_factory.gd`, `scripts/tools/loot_container.gd`, `data/kits/gameplay_prop_v0.json` — live gameplay visual consumer.
8. `data/procgen/golden/coherent_ship_001/layout.json`, `data/procgen/golden/coherent_ship_001/gameplay_slice.json`, `scenes/procgen/playable_coherent_ship.tscn` — existing connected room proof. Do not invent another layout format.

### Scope decision

The required release roster is **43 distinct asset IDs: 15 structural + 26 existing props + two Meshy props**. Reuse is production work: each reused asset must pass the same acceptance gates, but it need not be regenerated or resubmitted to a provider.

The focused-nine pressure-door, breach-seal, and fire-station candidates remain staging-only comparison assets in this release. They are useful for the one-room art benchmark but are not counted among the 43. Existing open/blocked doorway and bulkhead modules provide the required passage vocabulary. Promoting a new pressure-door gameplay system, threats, tendrils, swarm behavior, procedural biomass, extra biomes, exterior hull building, multiple decks, and new crafting mechanics are out of scope.

`crafting_station_derelict_v1` supplies a visual for the existing `workbench` role; it does not authorize inventing a crafting interaction. Loot keeps the current searched/hidden behavior. The Blender master must retain its closed/open/looted authoring states, but persistent in-game open-lid animation is not a requirement of this asset-library release and must not be claimed.

---

## 2. Fixed visual direction — do not improvise

### Recommended approach and alternatives

Choose hybrid reuse + Blender refinement + selective Meshy candidates. A Meshy-everything approach violates structural ownership and cannot guarantee joints; a complete Blender rebuild throws away an existing kit and expands risk. Purchased ithappy content remains a rights-cleared reference/reuse source, not permission to mix another visual language into the first release.

### Art acceptance rubric

- Locked-isometric 3D, stylized low-poly industrial salvage, readable silhouettes; not photorealism, medieval rust, toy-room candy colors, or micro-greeble noise.
- Base language: broad gray alloy panels, dark rubber conduits, restrained yellow hazard markings, blue-green energized elements, and localized dark-red organic contamination.
- Use existing canonical materials where appropriate: `MAT_PaintedAlloyGray`, `MAT_WarningStripe`, `MAT_ReactorGlow`, `MAT_Conduit`, `MAT_Biomatter`. Meshy loot already uses its own governed two-slot `painted_ship_alloy` / `warning_accent` palette; preserve the contract rather than renaming evidence-bound data for cosmetic consistency.
- At most one main panel break and one service-detail band per 4 m structural face. No decorative protrusions across sockets, door apertures, walkable floor planes, or adjacent-cell seams.
- Hazard paint identifies actual thresholds, dangerous machinery, or service access; never stripe every edge. Emission identifies powered/service affordances; never brighten the entire room to hide unreadability.
- Wear belongs around handles, thresholds, vents, and service access. Do not apply the same random damage/noise to every surface.
- Intact = complete silhouette. Damaged = localized scoring/dents/scorch with existing occupancy retained. Breached = authored missing visual material only where the existing runtime integrity contract supports it. Never assume a visual hole changes collision or navigation.
- Props face their intended interaction side into the room, not into a wall. Keep a clear route from entry to every required exit/objective. Door clearance is measured against the existing wrapper aperture and player capsule, not an invented corridor-width rule.
- Materials and silhouette must remain identifiable in normal, emergency, and dark lighting at the production camera, 1600×900. Review an overview and a player-distance crop; a turntable alone cannot pass.
- An asset may be mechanically valid and still fail art review. Do not mark checklist booleans true before viewing the output.

### Contract and budget rules

The structural grid step is 4.0 m; a Blender unit is one meter, not one tile. Structural placement contracts are Godot Y-up; source helper conversion is the repository's `[x,y,z] -> [x,z,y]`. Do not apply a second compensating rotation on export. Read actual GLB and engine-space bounds: Meshy contract dimension ordering and Blender reports must not be silently treated as interchangeable coordinate frames.

Preserve structural contract bounds and existing budgets. For decorative refinements, use flat panels and limited bevels instead of increasing density; do not arbitrarily raise a contract budget. Measure triangles after GLB re-import, not source quads.

Meshy contracts stay unchanged for this release:

| Asset | Contract dimensions_m | Tolerance | States | Triangles | Materials | Texture | Candidates |
|---|---|---|---|---|---|---|---|
| `loot_container_derelict_v1` | `[0.9,0.55,0.65]` | 0.01 m | closed, open, looted; one master | max 3000 | 2 | 1024 | 4 existing records; reuse |
| `crafting_station_derelict_v1` | `[1.6,1.2,1.8]` | 0.02 m | default | 3000–6000 whole asset | 3 | 1024 | 4, only if no usable existing batch |

Both use bottom-center pivot, canonical +Z forward policy, yaw 0/90/180/270, Godot-wrapper collision ownership, untextured `image_to_3d`, `smart-topology`, `meshy-t2`. Four separate reference views are required even though this generation mode's provider input behavior must be taken from the resolved plan, not inferred from the view count.

---

## 3. Exact asset roster and room recipes

### Structural assets

For EVERY ID below, the paths are mechanically fixed:

- Contract: `data/placement/contracts/structural/ship_structural_v0/{ID}_contract.json` and its existing `.tres` peer.
- Source: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/{ID}/{ID}.blend` plus `{ID}.source.json`.
- Production visual: `assets/imported/structural/ship_structural_v0/{ID}/{ID}.glb`.
- Existing state files, when the wrapper references them: `{ID}_damaged.glb`, `{ID}_breached.glb` in the same directory.
- Wrapper: `scenes/wrappers/structural/ship_structural_v0/{ID}.tscn`.

This is exact path expansion, not a request to choose a filename.

| ID | Mandatory production use / authoring action |
|---|---|
| `floor_1x1` | Basic room deck; qualify focused recipe, keep floor plane and collision intact. |
| `floor_2x1` | Large room deck span; repeat the accepted floor panel language, not scaled-up bevels. |
| `corridor_floor_1x1` | Corridor turns/short links; make threshold direction readable. |
| `corridor_floor_1x2` | Long links; match the short corridor's end profile exactly. |
| `wall_straight_1x1` | Shared bulkhead; refine panels without moving the edge-center pivot. |
| `wall_end_cap` | Close exposed wall ends; match straight-wall cross-section. |
| `wall_inner_corner` | Concave closure; no overlapping duplicate wall skins at the joint. |
| `wall_outer_corner` | Convex closure; same thickness/panel height as straight wall. |
| `wall_t_junction` | Branch boundary; no decorative geometry across the three socket faces. |
| `doorway_frame_open_1x1` | Traversable room/corridor threshold; opening remains fully clear. |
| `doorway_frame_blocked_1x1` | Visually blocked route; preserve the existing blocked collision policy. |
| `bulkhead_portal_2x1` | Large transition/landmark; do not replace it with the unqualified pressure-door candidate. |
| `ramp_up_1x2` | Qualify existing ramp geometry and traversal; do not add multi-deck procgen. |
| `pillar_support_1x1` | Sparse support/dressing anchor; never place in the route center. |
| `ceiling_cap_1x1` | Overhead closure with existing cutaway/fade behavior; never hide the player permanently. |

### Existing props — keep IDs and bindings

Each ID resolves to `assets/imported/props/{GROUP}/{ID}.glb` and `{ID}.sidecar.json`.

- `components` (11): `air_recycler_unit`, `conduit_run`, `console_generic`, `hull_plating`, `locker_wall`, `machinery_block`, `nav_console`, `pump_assembly`, `reactor_console`, `sensor_rack`, `thruster_control`.
- `dressing` (11): `cable_tray`, `cargo_pallet`, `emergency_wall`, `focused_work_lamp`, `generic_crate`, `generic_locker`, `maintenance_bench`, `medical_cabinet`, `practical_overhead`, `salvage_cart`, `service_rack`.
- `objectives` (4): `medbay_terminal`, `reactor_control_panel`, `repair_junction`, `supply_cache`.

Use existing imported assets unchanged if they pass. Their sidecars supply scale, bounds, placement surface, and provenance; do not eyeball substitute transforms or relabel purchased/AI provenance.

New dressing leaves after reviewed promotion:

- `assets/imported/props/dressing/loot_container_derelict_v1.glb` and `.sidecar.json`.
- `assets/imported/props/dressing/crafting_station_derelict_v1.glb` and `.sidecar.json`.

### Room recipes (placement constraints, not a second runtime schema)

Record these in `docs/game/features/functional_room_derelict_assets.md`. Use existing room IDs/footprints in the coherent fixtures; do not overwrite their graphs with these human-readable recipes.

| Recipe | Required visual anchors | Dressing rule | Functional proof |
|---|---|---|---|
| Airlock/control benchmark | open frame, blocked frame or existing bulkhead, console, emergency wall | one clear threshold, one service wall; no clutter in aperture | entry/exit, threshold collision, interaction visibility |
| Cargo | cargo pallet, generic crate/locker, supply cache, selected loot container | group cargo against one wall; a single readable aisle | supply objective accessible, loot searchable once |
| Engineering | machinery block, pump, reactor console/control panel, conduit | one machine cluster, service face toward aisle | reactor objective accessible; damage visuals do not erase the route |
| Medical | medical cabinet, medbay terminal, practical overhead | cleanest silhouette of the set, restrained damage | medbay objective accessible under all lighting |
| Maintenance | maintenance bench or new crafting visual, service rack, repair junction, work lamp | face bench into room; keep approach open | existing repair/workbench interaction remains unchanged |
| Bridge/control | nav console, sensor rack, thruster control | orient consoles consistently; no random furniture rotation | controls visible from the locked camera |
| Corridor | corridor floors, matching wall corners, emergency wall/cable tray | no floor clutter at turns or doors | physically traverse every intended connector |

The required final demonstration is the existing coherent five-room playable ship plus the generated-ship traversal smoke. Do not claim a new six-room graph merely because six room recipes are documented. A room recipe is reusable composition guidance; the production proof must load actual runtime fixtures.

---

## 4. Execution setup and common verification commands

All commands below are for execution AFTER plan approval. Each numbered action is a 2–5 minute work unit. Blender authoring is decomposed per mesh operation; rendering, provider polling, and full regressions may wait longer than five minutes but are single bounded actions. Do not describe an entire new mesh as a five-minute task.

### A1. Record the baseline; create one clean integration worktree

Read-only first:

```bash
git -C /Users/christopherwilloughby/Code/the-synaptic-sea rev-parse HEAD
git -C /Users/christopherwilloughby/Code/the-synaptic-sea status --short --untracked-files=no
git -C /Users/christopherwilloughby/Code/the-synaptic-sea worktree list
```

Expected: identify the actual approved base SHA and preserve the dirty checkout. If main moved since `2205a33d`, review intervening pipeline changes before proceeding; do not silently reset it to this historical SHA.

After that review, the explicit initial branch command is:

```bash
git -C /Users/christopherwilloughby/Code/the-synaptic-sea worktree add \
  -b feat/functional-room-asset-set \
  /Users/christopherwilloughby/Code/the-synaptic-sea-room-assets 2205a33d
cd /Users/christopherwilloughby/Code/the-synaptic-sea-room-assets
export ROOT="$PWD"
export GODOT=/opt/homebrew/bin/godot
export BLENDER=/opt/homebrew/bin/blender
export PYTHONPATH="$ROOT"
export PYTHONDONTWRITEBYTECODE=1
export STRUCTURAL_SOURCE=/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0
export PRODUCTION_SOURCE=/Volumes/Untitled/SynapticSeaAssets/meshes/source/room_assets_v1/ship_structural_v0
export PROP_SOURCE=/Volumes/Untitled/SynapticSeaAssets/meshes/source/room_assets_v1/props
export PREVIEW="$ROOT/artifacts/validation-previews/room-assets-v1"
```

If the worktree or branch already exists, inspect ownership and resume only an explicitly matching run; do not delete/recreate it. If a newer base was approved, replace only the final SHA in the worktree command with that reviewed SHA and record it.

### A2. Check tool prerequisites

```bash
"$GODOT" --version
"$BLENDER" --version
/usr/bin/python3 --version
/usr/bin/python3 -m pytest --version
/opt/homebrew/bin/python3.11 --version
test -d "$STRUCTURAL_SOURCE"
test -f addons/derelict/derelict.gdextension
```

Expected: Godot 4.7.1, working Blender executable, working Python/pytest, source mount present. Some modern structural/metadata tools use Python 3.11 features; use `/opt/homebrew/bin/python3.11` for those. Meshy commands documented for `/usr/bin/python3` retain that interpreter. A missing native extension binary/import dependency is a baseline blocker, not a reason to borrow the dirty main binary without provenance.

### A3. Define one strict Godot runner in the execution shell

This is a shell helper, not a new project script:

```bash
run_godot() {
  /opt/homebrew/bin/python3.11 - "$1" "$2" "$ROOT" "$GODOT" <<'PY'
import pathlib, subprocess, sys
script, marker, root, godot = sys.argv[1:]
result = subprocess.run([godot, '--headless', '--path', root, '--script', script],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        text=True, timeout=240)
print(result.stdout)
assert result.returncode == 0, result.returncode
assert marker in result.stdout, 'required pass marker absent'
assert not any(s in result.stdout for s in ('SCRIPT ERROR:', 'ERROR:', 'WARNING:')), 'unexpected diagnostic'
PY
}
```

Expected on success: actual smoke output with its pass marker and shell exit 0. A parse error that exits 0 is still a failure. If an existing warning needs classification, stop and have the coordinator decide; do not add a broad warning suppression.

### A4. Run baseline gates before changing art

```bash
/opt/homebrew/bin/python3.11 tools/run_canonical_regression.py --project-root "$ROOT" --check
/opt/homebrew/bin/python3.11 tools/validate_prop_visual_bindings.py --project-root "$ROOT" --check-index
/opt/homebrew/bin/python3.11 tools/validate_structural_variant_bindings.py --project-root "$ROOT"
run_godot res://scripts/validation/coherent_playable_traversal_smoke.gd \
  'COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true'
```

Expected: `CANONICAL REGRESSION MANIFEST PASS`, no metadata/variant errors, and the exact traversal marker. Record actual baseline failures in `artifacts/validation-previews/room-assets-v1/baseline.md`; do not fix unrelated gameplay in this asset branch or claim baseline failures are new art defects.

### A5. Freeze a production spec and requirement ownership

Create `docs/game/features/functional_room_derelict_assets.md` from sections 1–3 and the final checklist in this plan. Add `REQ-ROOMASSET-001` (43-ID library), `REQ-ROOMASSET-002` (one-room art gate), `REQ-ROOMASSET-003` (production bindings), `REQ-ROOMASSET-004` (playable derelict proof) to `docs/game/05_requirements.md` on this worktree only. Reconcile that hotspot with the owner of the dirty main requirements file before merging. No new ADR is necessary while preserving ADR-0058's ownership boundaries; if changing them becomes necessary, stop for a new architecture decision rather than silently broadening the work.

Commit only the feature and requirement change:

```bash
git add docs/game/features/functional_room_derelict_assets.md docs/game/05_requirements.md
git commit -m "docs: define functional room asset production acceptance"
```

### A6. Preserve the older masters before recovering current sources

The original source records are NOT directly portable: they contain absolute paths to an older metadata-retrofit worktree, and planning-time hash comparison found contract/source-GLB mismatches for multiple modules. Do not copy them into the new root and rewrite hashes as if the old source had been authored against today's contract. Preserve that art as a backup, then explicitly recover editable baselines from the current production GLBs; this is source reconstruction, not a claim to possess the original authoring history.

```bash
/opt/homebrew/bin/python3.11 tools/backup_structural_sources.py \
  --source-root "$STRUCTURAL_SOURCE" \
  --backup-target /Volumes/Untitled/SynapticSeaAssets/backups/room_assets_v1/original-sources --dry-run
/opt/homebrew/bin/python3.11 tools/backup_structural_sources.py \
  --source-root "$STRUCTURAL_SOURCE" \
  --backup-target /Volumes/Untitled/SynapticSeaAssets/backups/room_assets_v1/original-sources
```

Expected: preserved relative paths and byte-identical backups. This is a same-volume checkpoint, not disaster recovery. Original sources remain untouched.

### A7. Recover and validate an immutable baseline source root

```bash
export BASELINE_SOURCE=/Volumes/Untitled/SynapticSeaAssets/meshes/source/room_assets_v1/baseline
/opt/homebrew/bin/python3.11 tools/recover_modules.py \
  --project-root "$ROOT" --source-root "$BASELINE_SOURCE" --all --dry-run
"$BLENDER" --background --factory-startup --python tools/recover_modules.py -- \
  --project-root "$ROOT" --source-root "$BASELINE_SOURCE" --all
/opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root "$ROOT" --source-root "$BASELINE_SOURCE" --all --blender "$BLENDER"
```

Expected: 15 recovered `.blend`/`.source.json` pairs bound to this checkout's contracts and imported GLBs; all source validation passes. This writes external source files only, not production GLBs. Do not use `--overwrite` on a pre-existing source root; inspect an existing matching run first. Keep this baseline root unchanged for the focused comparison validator.

### A8. Recover a separate editable production root

Repeat A7's dry-run/recover/validate commands with `--source-root "$PRODUCTION_SOURCE"`. Run each as a separate bounded action. Do not simply copy the baseline records: absolute `blend_path` would be wrong. Expected: another 15 correctly bound source pairs, now at the editable production root. Current intact GLBs are the starting geometry; existing state GLBs remain authoritative reference material when B4–B8 builds state collections from the recovered master. Preserve provenance linking the original GLB, recovered baseline, and deliberate new edits.

Before production promotion, checkpoint this edited root under `/Volumes/Untitled/SynapticSeaAssets/backups/room_assets_v1/structural`; report the same-volume limitation unless an independent approved backup target is available.

---

## 5. B — One-room art gate, then structural library

### B1. Qualify the focused-nine recipe without touching live assets

```bash
/opt/homebrew/bin/python3.11 tools/focused_nine_batch.py \
  --project-root "$ROOT" --structural-source-root "$PRODUCTION_SOURCE" \
  --validation-structural-source-root "$BASELINE_SOURCE" \
  --props-source-root "$PROP_SOURCE" \
  --report assets/_staging/focused_nine/focused-nine-comparison.json \
  --preview-dir "$ROOT/artifacts/validation-previews/focused-nine/room-assets-v1" --dry-run
```

Expected: nine planned candidate IDs, no writes, no provider requests. Read the plan to confirm sources resolve to the isolated production roots. Then run the identical command without `--dry-run` as a separate action. Expected: a complete comparison JSON and staged assets; no mutation of imported assets, live structural wrappers, `data/kits/ship_structural_v0.json`, or the prop index. The six overlapping structural candidates are potential replacements, not automatic promotions.

### B2. Capture the airlock/control-room benchmark

```bash
/opt/homebrew/bin/python3.11 tools/focused_nine_airlock_control_room_preview.py \
  --project-root "$ROOT" --staging-root assets/_staging/focused_nine \
  --preview-dir "$PREVIEW/airlock" --proof "$PREVIEW/airlock-proof.json"
```

Expected: preview/proof artifacts from the real temporary Godot project with all required checks true and no protected changes. Inspect the command's actual output paths; do not rename/forge the proof to satisfy an imagined schema.

### B3. Review that room before bulk authoring

Open the resulting real image in an image-capable reviewer and inspect doorway aperture, straight-wall/floor alignment, player readability, material language, prop placement, ceiling visibility, and contact with the floor. Record the exact image paths and verdict in `$PREVIEW/airlock/review.md`. All seven checks must pass. If the look is rejected, adjust only the failed component in the isolated `.blend`, rerun its export/preview, and review again. No bulk generation until this gate passes. Do not accept a collage as in-engine traversal proof.

### B4–B8. Per-module authoring microcycle

Execute this five-action cycle separately for each of the 15 structural rows in section 3, in table order. This expansion creates an explicit finite work queue; one artist owns each `.blend` and no two workers edit the same external source.

1. **Inspect, 2–5 min:** open `$PRODUCTION_SOURCE/{ID}/{ID}.blend`; inspect `Geometry`, `AuthoringHelpers`, `Origin`, socket empties, current `Export_*` roles and the exact contract. Record existing roles, bounds, triangles, and whether any improvement is needed. Reuse an acceptable asset without changing it.
2. **Author one improvement, 2–5 min:** perform only the row's prescribed panel/profile improvement from section 3. Preserve socket positions, floor plane, pivot, and collision helpers. For a wall/corner, compare its terminal cross-section to the accepted straight wall. Save the production copy, not the original master.
3. **Derive states, 2–5 min per existing role:** if a live wrapper references damaged/breached geometry, preserve those roles from the same master. Modify only visual meshes in the corresponding export collection. No duplicate roles; no blanket decimation; no source helper exported as a visual. If a new breach would require changed gameplay collision, do not introduce it in this release.
4. **Export, single bounded action:** run the exact exporter below with `ID` set to this row. A reused source still needs a verified output.
5. **Inspect round-trip, 2–5 min:** import the exported GLB in a fresh Blender scene and compare bounds, normals, triangle budget, material assignments, and socket-edge surfaces against the accepted baseline. Record pass/fail and fix the first failure before moving to the next ID.

Per-row command, with the roster token assigned literally, e.g. `ID=floor_1x1`:

```bash
ID=floor_1x1
"$BLENDER" --background --factory-startup --python tools/export_structural_glb.py -- \
  --blend-path "$PRODUCTION_SOURCE/$ID/$ID.blend" \
  --staging-dir "$ROOT/assets/_staging/room_assets_v1/structural/$ID" --module "$ID"
```

Expected: nonempty `{ID}.glb` and exactly the authored supported state leaves. Inspect actual Blender logs; cancelled export is failure even if process exit is 0. Validate GLB magic `glTF` and re-import geometry, not just file sizes. Missing `Geometry` or stale source metadata is an authoring error; repair through the existing source workflow, not by editing evidence hashes.

### B9. Validate the entire source roster

```bash
/opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root "$ROOT" --source-root "$PRODUCTION_SOURCE" --all --blender "$BLENDER"
```

Expected: all 15 production modules pass. `pressure_door_1x1` is not a sixteenth `--all` production module. Retain its focused-nine staging evidence without changing the catalog count.

### B10. Qualify existing props in small batches

Review the exact 26-ID roster by room recipe: cargo, engineering, medical, maintenance, bridge/control, then remaining shared dressing. One asset per 2–5 minute inspection: correct ground contact/scale, surface placement, silhouette, material fit, and front-facing affordance. Default action is reuse unchanged. For a failed visual, return to its rights-cleared editable source, make one focused change, re-export, and use the existing derived-metadata refresh command only after that asset's reviewed promotion. Do not overwrite an acceptable original merely to make every file appear newly generated.

Verify current metadata:

```bash
/opt/homebrew/bin/python3.11 tools/generate_prop_sidecars.py --project-root "$ROOT" --check
/opt/homebrew/bin/python3.11 tools/validate_prop_visual_bindings.py --project-root "$ROOT" --check-index
```

Expected: all current 26 asset leaves and their binding aliases validate. Keep a per-ID verdict in `$PREVIEW/prop-review.md`; an absent editable source is explicitly recorded as a reuse-only restriction, not represented as a reconstructed original.

### B11. Inspect a staged derelict, not only the airlock

```bash
/opt/homebrew/bin/python3.11 tools/focused_nine_staged_derelict_preview.py \
  --project-root "$ROOT" --staging-root assets/_staging/focused_nine \
  --preview-dir "$PREVIEW/staged-derelict" --proof "$PREVIEW/staged-derelict-proof.json"
```

Expected: staged overlay proof, clean diagnostics, no live mutation. Record silhouette consistency across repeated cells, exposed seams, corners, thresholds, and ceiling fade. This validates focused candidates in context; it does not certify all 15 replacements or any production promotion.

---

## 6. C — TDD: correct the gameplay GLB visual boundary

This is a narrow required code change, not a new interaction framework. Preserve the direct `Mesh` child contract so all existing callers keep their visibility behavior. Put imported geometry beneath that child and apply catalog scale exactly once. Missing/primitive assets retain their current fallback behavior.

### C1. Write the failing integration smoke

Create `scripts/validation/gameplay_prop_imported_visual_smoke.gd` with the full content below:

```gdscript
extends SceneTree

const Factory = preload("res://scripts/placement/gameplay_prop_factory.gd")
const SOURCE = "res://assets/imported/props/dressing/generic_crate.glb"

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error("GAMEPLAY PROP IMPORTED VISUAL FAIL " + message)
		quit(1)
	return ok

func _run() -> void:
	if not _require(ResourceLoader.exists(SOURCE), "fixture GLB missing"):
		return
	Factory._catalog_path = Factory.DEFAULT_KIT_PATH
	Factory._catalog = {"props": {"import_probe": {
		"mesh_path": SOURCE, "scale": 2.0, "y_offset": 0.0
	}}}
	var prop: Node3D = Factory.build("import_probe")
	root.add_child(prop)
	var anchor := prop.get_node_or_null("Mesh") as MeshInstance3D
	if not _require(anchor != null, "legacy Mesh anchor missing"):
		return
	if not _require(anchor.mesh == null, "placeholder drawn beside imported model"):
		return
	var imported := anchor.get_node_or_null("CatalogMesh") as Node3D
	if not _require(imported != null, "imported model must inherit marker visibility"):
		return
	if not _require(anchor.scale == Vector3.ONE * 2.0, "catalog scale missing"):
		return
	if not _require(imported.scale == Vector3.ONE, "catalog scale applied twice"):
		return
	anchor.hide()
	if not _require(not imported.is_visible_in_tree(), "hidden owner leaves imported model visible"):
		return
	anchor.show()
	if not _require(imported.is_visible_in_tree(), "show does not restore imported model"):
		return
	prop.free()
	Factory._catalog_path = ""
	Factory._catalog = {}
	var fallback: Node3D = Factory.build("corpse_bag")
	root.add_child(fallback)
	var fallback_mesh := fallback.get_node_or_null("Mesh") as MeshInstance3D
	if not _require(fallback_mesh != null and fallback_mesh.mesh != null, "primitive fallback broken"):
		return
	fallback.free()
	print("GAMEPLAY PROP IMPORTED VISUAL PASS placeholder=false visibility_inherited=true scale_once=true fallback=true")
	quit(0)
```

### C2. Verify RED

```bash
run_godot res://scripts/validation/gameplay_prop_imported_visual_smoke.gd \
  'GAMEPLAY PROP IMPORTED VISUAL PASS placeholder=false visibility_inherited=true scale_once=true fallback=true'
```

Expected failure: `GAMEPLAY PROP IMPORTED VISUAL FAIL placeholder drawn beside imported model`; no PASS marker. Missing fixture/import errors are not the intended RED; fix the test environment first.

### C3. Replace only `build` in `scripts/placement/gameplay_prop_factory.gd`

```gdscript
static func build(prop_id: String, world_position: Vector3 = Vector3.ZERO) -> Node3D:
	var catalog: Dictionary = load_catalog()
	var props: Dictionary = catalog.get("props", {}) as Dictionary
	var prop: Dictionary = props.get(prop_id, {}) as Dictionary
	var node := Node3D.new()
	node.name = "GameplayProp_%s" % prop_id
	node.position = world_position + Vector3.UP * float(prop.get("y_offset", 0.0))
	node.set_meta("gameplay_prop_id", prop_id)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var scale_value: float = float(prop.get("scale", 1.0))
	mesh_instance.scale = Vector3.ONE * scale_value
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mesh_instance)
	var mesh_resource: Resource = _load_mesh_resource(prop)
	if mesh_resource is PackedScene:
		var packed_instance := (mesh_resource as PackedScene).instantiate()
		packed_instance.name = "CatalogMesh"
		mesh_instance.add_child(packed_instance)
	else:
		if mesh_resource is Mesh:
			mesh_instance.mesh = mesh_resource as Mesh
		else:
			mesh_instance.mesh = _primitive_mesh(str(prop.get("primitive", "box")), float(prop.get("height_hint", 1.0)))
		var material := StandardMaterial3D.new()
		material.albedo_color = _catalog_color(prop)
		mesh_instance.material_override = material
	return node
```

Do not change `LootContainer` inventory, range, or persistence code. Imported GLBs keep their authored materials. The imported node retains its intrinsic source transform; no extra catalog multiplier is added to it.

### C4. GREEN, existing behavior, commit

Rerun C2; require its exact PASS and clean output. Then run the canonical bundle before committing this code independently:

```bash
/opt/homebrew/bin/python3.11 tools/run_canonical_regression.py --project-root "$ROOT"
git add scripts/placement/gameplay_prop_factory.gd scripts/validation/gameplay_prop_imported_visual_smoke.gd
git commit -m "fix: make imported gameplay visuals inherit marker visibility"
```

Expected: all canonical commands actually run; the final regression marker from `docs/game/06_validation_plan.md` is present. Do not copy a historical command count into an asserted fresh result. Add this new smoke to that document's canonical bundle in its own small reviewed documentation change, incrementing the declared count to match parsed commands, then run `--check` again.

---

## 7. D — Meshy production: reuse loot, qualify one crafting station

### D0. Rehydrate private checkout permissions before evidence verification

Git does not preserve the pipeline's private evidence modes. `docs/superpowers/proofs/asset-pipeline-closure.md` documents this as an execution prerequisite, not an integrity failure. In the private integration worktree only, run:

```bash
/opt/homebrew/bin/python3.11 - <<'PY'
from pathlib import Path
roots = [
    Path('assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088'),
    Path('artifacts/validation-previews/meshy/loot_container_derelict_v1'),
]
for root in roots:
    assert root.is_dir() and not root.is_symlink(), root
    entries = [root, *root.rglob('*')]
    assert not any(p.is_symlink() for p in entries), 'unexpected evidence symlink'
    assert all(p.is_dir() or p.is_file() for p in entries), 'non-regular evidence entry'
    for path in entries:
        path.chmod(0o700 if path.is_dir() else 0o600)
print('ROOM ASSET PRIVATE EVIDENCE MODES PASS')
PY
```

Expected: only mode changes beneath these two exact evidence roots; file bytes/hashes unchanged. Newly generated task directories are created privately by the pipeline. Do not weaken mode checks in code or chmod the original dirty checkout.

### D1. Audit the existing loot batch; do not generate another

```bash
export LOOT_TASK=assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088
/usr/bin/python3 tools/meshy_stage.py verify --project-root "$ROOT" \
  --contract data/asset_generation/contracts/loot_container_derelict_v1.json \
  --batch-journal assets/_staging/meshy/loot_container_derelict_v1/_batches/9e04213bc806421d8e64c9c9c23f26d3.json \
  --pricing-file data/asset_generation/meshy_pricing_v1.json
/usr/bin/python3 tools/meshy_candidate_review.py verify --project-root "$ROOT" --task-dir "$LOOT_TASK"
```

Expected: offline evidence verifies. If a fresh worktree has a different protected snapshot, distinguish legitimate checkout/import differences from changed runtime bytes. Do not delete imports or edit hashes to obtain a pass. `reapprove` is an explicit audited recovery operation, not a generic retry: document the actual delta, verify every task first, and follow the current runbook only after coordinator review. Never claim the historical `promotion_ready` field is sufficient.

### D2. Inspect and preserve the loot master/states

Master: `/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/loot_container_derelict_v1_master.blend`.

Open it and its sibling `build_recipe_manifest.json`; inspect the selected candidate provenance, `ContainerRoot`, `ContainerBody`, `HingePivot`, `ContainerLid`, `FrontHandle`, `LatchLeft`, `LatchRight`, and `LootVisual`. The current recipe records closed at frame 1, open at frame 30, looted at frame 60, with an X-axis hinge opening 105 degrees. Inspect those exact frames and compare the currently staged cleaned GLB. The generic validator's historical `master_provenance=null` is not proof that this separate recipe/master/backup gate passed. Do not rerun the selected-only master constructor on a promotion-ready task. If remediation is needed, use the existing `tools/meshy_loot_container_recipe.py` governed workflow after reading its current mode/evidence requirements; do not reset review.json by hand. A missing or untraceable master is a blocking production-source gap even if the GLB looks good.

### D3. Establish crafting reference files

First inspect `assets/_staging/meshy/crafting_station_derelict_v1/` and its batch journals; reuse an existing resolvable batch before requesting work. If no reusable batch exists, create four project-owned reference images under `/Volumes/Untitled/SynapticSeaAssets/meshy/references/crafting_station_derelict_v1/`:

`source_front.png`, `source_side.png`, `source_back.png`, `source_three_quarter.png`.

Use one Blender blockout for all views: broad work surface, two sturdy supports, one service cabinet, one clearly forward-facing control/readout, no stool, no room walls, no detached tools, no opaque clutter on the work surface. Match the contract dimensions and the accepted airlock material blocks. Render each camera separately with neutral lighting and plain background; no collage, baked captions, or different objects between views. Verify rights and SHA-256 for each source before planning. Do not use unrelated found images to satisfy cardinality.

### D4. Plan and resolve; no paid call yet

```bash
export CRAFT_REF=/Volumes/Untitled/SynapticSeaAssets/meshy/references/crafting_station_derelict_v1
/usr/bin/python3 tools/meshy_asset_contract.py validate data/asset_generation/contracts/crafting_station_derelict_v1.json
/usr/bin/python3 tools/meshy_stage.py plan --project-root "$ROOT" \
  --contract data/asset_generation/contracts/crafting_station_derelict_v1.json \
  --pricing-file data/asset_generation/meshy_pricing_v1.json \
  --reference-root "$CRAFT_REF" --reference front=source_front.png \
  --reference side=source_side.png --reference back=source_back.png \
  --reference three_quarter=source_three_quarter.png
/usr/bin/python3 tools/meshy_stage.py resolve-plan --project-root "$ROOT" \
  --contract data/asset_generation/contracts/crafting_station_derelict_v1.json \
  --pricing-file data/asset_generation/meshy_pricing_v1.json \
  --reference-root "$CRAFT_REF" --reference front=source_front.png \
  --reference side=source_side.png --reference back=source_back.png \
  --reference three_quarter=source_three_quarter.png
```

Expected: valid contract, four resolved references, plan identity and provider-payload hash, positive maximum credits. `plan` is read-only; `resolve-plan` records the envelope offline. Pricing must still be valid at execution time. The standing subscription authorization removes an extra spend-ceiling negotiation, not request-integrity fields or duplicate-job safety.

### D5. Submit exactly the governed batch once

Set `APPROVED_CREDITS` to the actual `maximum_credits` printed by D4; set `REVIEWER` to the actual reviewer identity, never another person's identity copied from a historical record.

```bash
: "${APPROVED_CREDITS:?copy maximum_credits from the current plan}"
: "${REVIEWER:?set actual reviewer identity}"
/usr/bin/python3 tools/meshy_stage.py generate --project-root "$ROOT" \
  --contract data/asset_generation/contracts/crafting_station_derelict_v1.json \
  --pricing-file data/asset_generation/meshy_pricing_v1.json \
  --approved-credits "$APPROVED_CREDITS" --output-license paid-private \
  --reference-root "$CRAFT_REF" --reference front=source_front.png \
  --reference side=source_side.png --reference back=source_back.png \
  --reference three_quarter=source_three_quarter.png
```

Expected: one journal containing exactly four planned candidate records, not one candidate and not repeated batches. Record the returned journal and task IDs in `$PREVIEW/crafting-batch.md`. Provider IDs are outputs, not filenames the implementer is allowed to invent. On ambiguous POST outcome stop and reconcile; only `resume` on the recorded journal is GET-only recovery. Never rerun `generate` because polling failed.

### D6. Select one candidate or reject the batch

Inspect all four candidates separately; choose only if silhouette, proportions, work-surface volume, separable/serviceable forms, bounded cleanup, and locked-camera readability all pass. Reject any candidate missing the functional work surface even if it has attractive texture. Record each rejection with its actual reason.

For the chosen directory returned by D5, set `CRAFT_TASK` to `assets/_staging/meshy/crafting_station_derelict_v1/` followed by its actual task ID, then:

```bash
: "${CRAFT_TASK:?set the chosen recorded task directory}"
/usr/bin/python3 tools/meshy_candidate_review.py select --project-root "$ROOT" \
  --task-dir "$CRAFT_TASK" --reviewer "$REVIEWER" \
  --check silhouette_readable --check proportions_match_contract \
  --check functional_volume_present --check movable_parts_separable \
  --check cleanup_bounded --check camera_readability
/usr/bin/python3 tools/meshy_blender_master.py --project-root "$ROOT" \
  --contract data/asset_generation/contracts/crafting_station_derelict_v1.json \
  --task-dir "$CRAFT_TASK" --reviewer "$REVIEWER"
```

Expected: selected review and `MESHY BLENDER MASTER COMMAND PASS asset=crafting_station_derelict_v1`. This is organized source creation, NOT cleanup completion.

### D7–D11. Clean the crafting master as five separate artist actions

Exact source: `/Volumes/Untitled/SynapticSeaAssets/meshy/source/crafting_station_derelict_v1/crafting_station_derelict_v1_master.blend`.

1. Keep `SOURCE_RAW` untouched and hidden. In `WORKING`, remove floating artifacts/internal scraps; preserve the readable worktop/support/service-cabinet silhouette.
2. Deliberately simplify high-frequency non-silhouette topology and repair normals. Keep whole-asset triangles within 3000–6000 after triangulation. Do not pad triangle count with meaningless geometry or lower the contract minimum to pass.
3. Normalize scale, bottom-center origin and forward policy against the contract. Inspect the real engine-space result; do not rely on a marker name as proof of orientation.
4. Unwrap the production meshes and assign at most three readable materials: alloy, dark service surfaces, restrained energized/hazard accent. No automatic texture purchase is required; the texture-packet tool is proposal-only, not an executed texture pipeline.
5. Put only approved visual objects in `EXPORT`, save the master, and export selected visual objects as binary GLB to `$CRAFT_TASK/cleaned.glb`. Export via Blender's glTF exporter with transforms applied and without raw/working/helpers/collision proxies. Verify the export reports FINISHED and a nonempty `glTF` file.

These are artist operations in an existing `.blend`, not a request to write an unreviewed generic cleanup script. If one operation takes longer, split by object; never fake completion to fit a timebox.

### D12. Fresh Blender validation for both Meshy assets

For loot first, then crafting, set `ASSET_ID` and `TASK_DIR` to their exact contract ID / recorded task directory:

```bash
ASSET_ID=loot_container_derelict_v1
TASK_DIR="$LOOT_TASK"
/usr/bin/python3 tools/meshy_blender_validate.py --project-root "$ROOT" \
  --contract "data/asset_generation/contracts/$ASSET_ID.json" --task-dir "$TASK_DIR" \
  --glb "$TASK_DIR/cleaned.glb" --report "$TASK_DIR/blender-validation.json"
```

Repeat with `ASSET_ID=crafting_station_derelict_v1` and `TASK_DIR="$CRAFT_TASK"`. Expected: fresh `status=PASS`, genuine Blender re-import, all contract bounds/UV/triangle/material gates pass. A historical output file left in place after a command fails is not a new pass.

### D13. Fresh six-case runtime review, separately per asset

```bash
/usr/bin/python3 tools/meshy_runtime_review.py --project-root "$ROOT" \
  --contract "data/asset_generation/contracts/$ASSET_ID.json" --task-dir "$TASK_DIR" \
  --preview-dir "$ROOT/artifacts/validation-previews/meshy/$ASSET_ID"
/usr/bin/python3 tools/meshy_candidate_review.py verify --project-root "$ROOT" --task-dir "$TASK_DIR"
/usr/bin/python3 tools/meshy_promotion_packet.py prop --project-root "$ROOT" \
  --task-dir "$TASK_DIR" \
  --target-path "res://assets/imported/props/dressing/$ASSET_ID.sidecar.json"
```

Expected: seeds 42 and 777 × normal/emergency/dark, six cases, complete real images at 1600×900, clean runtime diagnostics, bound candidate readiness, proposal-only sidecar overlay. Loot can have multiple state captures per case: six cases does NOT imply exactly six files. Count from the runtime manifest. Review the actual images, including whether the worktop/latch faces the player. No live target is written by the proposal command.

### D14. Back up Meshy masters; review production eligibility

Back up `/Volumes/Untitled/SynapticSeaAssets/meshy/source/` using `tools/backup_structural_sources.py --source-root /Volumes/Untitled/SynapticSeaAssets/meshy/source --backup-target /Volumes/Untitled/SynapticSeaAssets/backups/room_assets_v1/meshy` (dry-run, then real copy as in A6). Compare master hashes to the backup. Keep a checkpoint before any subsequent edits. Require separate spec and asset-quality review of contract, raw/cleaned lineage, editable source, states, rights, six-case evidence, and proposed target. Neither an automated boolean nor a proposal file alone approves promotion.

---

## 8. E — Reviewed production integration (single writer)

Do not run this phase while another batch is binding snapshots against the same checkout. Complete and archive all required pre-promotion evidence first. Execute E3–E6 BEFORE E0–E2: both Meshy proposals must be verified against the unchanged protected baseline before any structural promotion changes it. E4 preflights both candidates before writing either one. Promotion changes protected surfaces, so subsequent validation requires fresh evidence rather than pretending the old protected snapshot still matches.

### E0. TDD: repair existing state-to-GLB bindings

Execute AFTER E3–E6 and BEFORE E1. Planning inspection verified that `floor_2x1.tscn` binds both damaged and breached resource IDs to its intact GLB. A state node existing or changing visibility does not prove damage art is shown. This specific baseline defect is in scope; do not classify it as unrelated and abandon the required asset-state gate.

The exact eight wrapper paths are `scenes/wrappers/structural/ship_structural_v0/{ID}.tscn`, for `floor_1x1`, `floor_2x1`, `corridor_floor_1x1`, `corridor_floor_1x2`, `wall_straight_1x1`, `doorway_frame_open_1x1`, `pillar_support_1x1`, and `ramp_up_1x2`.

1. Run `/opt/homebrew/bin/python3.11 tools/validate_structural_variant_bindings.py --project-root "$ROOT"`; expected RED for the intact-resource aliases. Preserve the exact diagnostics. This existing validator is the failing contract test; no duplicate parser is needed.
2. In each of those eight files, change only the `path` of `id="2_visual_damaged"` to `res://assets/imported/structural/ship_structural_v0/{ID}/{ID}_damaged.glb`, and `id="3_visual_breached"` to the corresponding `{ID}_breached.glb`. Keep `id="1_visual"`, nodes, anchors, physics, and manifests unchanged. Expand the exact ID from the finite list, one wrapper per work unit. Verify both target files exist; do not invent empty variants.
3. Rerun the same validator for GREEN; also run the existing structural variant smoke through `run_godot` with its full PASS marker. If the validator reports additional manifest/source-hash defects, repair only correctly derived metadata for the exact affected assets and retain original provenance; never silence those checks.
4. Compare each role in Blender and the actual Godot state switch. Require deliberate visible damage/breach distinction, not merely different filenames or file hashes. If two role files are visually identical, return that asset to B4–B8 for same-master state authoring before accepting it.
5. Commit only the changed wrapper `.tscn` leaves after GREEN. This is visual binding repair, not permission to alter integrity behavior or collision.

Focused staged derelict proofs use the `compact` template; the canonical compiler smoke uses `derelict_a`. Do not equate their placement/room counts. The production five-room proof remains a separate required lane.

### E1. Structural promotion dry-run, one module

After B9 and the art review, for each accepted module use:

```bash
ID=floor_1x1
/opt/homebrew/bin/python3.11 tools/promote_structural_sources.py \
  --project-root "$ROOT" --source-root "$PRODUCTION_SOURCE" \
  --staging-root "$ROOT/assets/_staging/room_assets_v1/promotion" --module "$ID" \
  --backup --backup-target /Volumes/Untitled/SynapticSeaAssets/backups/room_assets_v1/structural \
  --dry-run
```

Expected: only the selected module's planned source/variant/runtime leaves. Never use `--skip-godot` or `--force` as a workaround.

### E2. Promote and physically verify one structural module

Run E1 without `--dry-run`. Then:

```bash
run_godot res://scripts/validation/floor_wrapper_collision_footprint_smoke.gd 'FLOOR WRAPPER COLLISION FOOTPRINT PASS'
run_godot res://scripts/validation/structural_wrapper_collision_footprint_smoke.gd 'STRUCTURAL WRAPPER COLLISION FOOTPRINT PASS'
run_godot res://scripts/validation/playable_generated_ship_floor_collision_smoke.gd 'PLAYABLE GENERATED SHIP FLOOR COLLISION SMOKE PASS'
run_godot res://scripts/validation/structural_variant_wrapper_smoke.gd 'STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true'
```

Require the full emitted floor-footprint PASS line, including its actual checked count. Check that wrapper-owned floor/wall collision still exists, and that a visual-only replacement has not removed physics formerly supplied through imported nodes. Do not add collision to every GLB based on an old skill note; inspect the actual current wrapper owner. A physics failure blocks this module's promotion acceptance.

Repeat E1–E2 for each of the other 14 IDs. Commit only the reviewed GLB leaves and any approved source-record metadata after each module or inseparable seam pair. Do not stage whole directories containing unrelated imports. Do not modify wrapper geometry solely to conceal an incorrectly sized visual.

### E3. TDD: register the two additional dressing IDs

Create `tests/test_room_asset_dressing_inventory.py`:

```python
from tools.generate_prop_sidecars import DRESSING_SURFACES, EXPECTED_ASSET_COUNTS
from tools.validate_prop_visual_bindings import EXPECTED_COUNTS


def test_room_asset_dressing_inventory():
    assert DRESSING_SURFACES["loot_container_derelict_v1"] == "floor"
    assert DRESSING_SURFACES["crafting_station_derelict_v1"] == "floor"
    assert len(DRESSING_SURFACES) == 13
    assert EXPECTED_ASSET_COUNTS == {"component": 11, "dressing": 13, "objective": 4}
    assert EXPECTED_COUNTS == {"components": 11, "dressing": 13, "objectives": 4}
```

Run `/opt/homebrew/bin/python3.11 -m pytest -q tests/test_room_asset_dressing_inventory.py`; expected RED: missing loot key. Then make these exact small changes:

- In `tools/generate_prop_sidecars.py`, change only dressing count in `EXPECTED_ASSET_COUNTS` from 11 to 13; append `"loot_container_derelict_v1": "floor"` and `"crafting_station_derelict_v1": "floor"` to `DRESSING_SURFACES`.
- In `tools/validate_prop_visual_bindings.py`, change only dressing count in `EXPECTED_COUNTS` from 11 to 13.

Rerun the focused test; expect one pass. The full inventory is intentionally incomplete until E4 supplies BOTH approved GLBs/sidecars. Do not commit a knowingly broken intermediate production inventory; E3–E5 form one atomic integration commit. This is not permission to weaken inventory checks or replace them with directory-derived counts.

### E4. Materialize each approved Meshy proposal, retaining provenance

This is an explicit reviewed file operation on the isolated integration worktree, not a new automatic promotion service. Before running, confirm D14 passed and `CRAFT_TASK` identifies the approved task. Run the following complete snippet once; it preflights both assets, refuses pre-existing targets, computes real metadata, retains proposal provenance, and writes only the declared four new leaves.

```bash
export CRAFT_TASK
/opt/homebrew/bin/python3.11 - <<'PY'
import json, os
from pathlib import Path
from tools.generate_prop_sidecars import _canonical_sidecar
from tools.prop_visual_metadata import validate_sidecar, write_canonical_json
from tools.meshy_candidate_review import verify_review

root = Path.cwd().resolve()
inputs = {
    'loot_container_derelict_v1': Path('assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088'),
    'crafting_station_derelict_v1': Path(os.environ['CRAFT_TASK']),
}
prepared = []
for asset_id, relative in inputs.items():
    task = (root / relative).resolve()
    assert task.is_relative_to(root / 'assets/_staging/meshy' / asset_id)
    review = verify_review(root, task)
    assert review['state'] == 'promotion_ready', review['state']
    proposal = json.loads((task / 'sidecar-overlay.json').read_text())
    glb = root / 'assets/imported/props/dressing' / (asset_id + '.glb')
    sidecar_path = glb.with_suffix('.sidecar.json')
    assert not glb.exists() and not glb.is_symlink(), glb
    assert not sidecar_path.exists() and not sidecar_path.is_symlink(), sidecar_path
    assert proposal['proposal_only'] is True
    assert proposal['asset_id'] == asset_id
    assert proposal['target_path'] == 'res://' + sidecar_path.relative_to(root).as_posix()
    payload = (task / 'cleaned.glb').read_bytes()
    assert payload[:4] == b'glTF'
    import hashlib
    assert hashlib.sha256(payload).hexdigest() == proposal['extensions']['ai_generation']['cleaned_output_sha256']
    prepared.append((asset_id, glb, sidecar_path, payload, proposal))
# No provider jobs or snapshot rebinds occur here.
created = []
try:
    for asset_id, glb, sidecar_path, payload, proposal in prepared:
        with glb.open('xb') as out:
            created.append(glb)
            out.write(payload)
        sidecar = _canonical_sidecar(root, glb, 'dressing')
        sidecar['provenance'] = proposal['provenance']
        sidecar['extensions'] = proposal['extensions']
        errors = validate_sidecar(sidecar, glb, root)
        assert not errors, errors
        created.append(sidecar_path)
        write_canonical_json(sidecar_path, sidecar)
    print('ROOM ASSET MESHY MATERIALIZATION PASS assets=2 leaves=4')
except BaseException:
    for path in reversed(created):
        path.unlink(missing_ok=True)
    raise
PY
```

This snippet depends on the inspected internal helper signatures. If those APIs change on the approved base, stop and revise this narrowly scoped promotion recipe; do not bypass validation. The workspace is assumed trusted and single-writer; it is not a hardened multi-user publication service. On rerun after a previous successful write, verify exact targets and resume E5 rather than deleting/replacing them.

### E5. Build and validate the extended index

```bash
/opt/homebrew/bin/python3.11 tools/generate_prop_sidecars.py --project-root "$ROOT" --write-index
/opt/homebrew/bin/python3.11 tools/generate_prop_sidecars.py --project-root "$ROOT" --check
/opt/homebrew/bin/python3.11 tools/validate_prop_visual_bindings.py --project-root "$ROOT" --check-index
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_room_asset_dressing_inventory.py tests/test_prop_visual_metadata.py
```

Expected: 11 component, 13 dressing, four objective asset leaves; aliases preserved; AI provenance retained; all tests pass. Do not run `--write-missing` to regenerate approved Meshy provenance. If a regression explicitly asserts the old inventory, inspect whether it is a fixture-local invariant or a production invariant; update only the latter and add the two real assets, never replace a failed assertion with `>=`.

Commit E3–E5 together with explicit paths: the two tools, the new test, the four new Meshy leaves, and `data/props/visual_bindings.generated.json`. No unrelated GLBs, `.import` files, or source backups.

### E6. TDD: bind the gameplay catalog to the two promoted props

Create `tests/test_room_asset_gameplay_bindings.py`:

```python
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_room_asset_gameplay_bindings():
    props = json.loads((ROOT / 'data/kits/gameplay_prop_v0.json').read_text())['props']
    expected = {
        'loot_crate': 'loot_container_derelict_v1',
        'workbench': 'crafting_station_derelict_v1',
    }
    for role, asset in expected.items():
        path = f'res://assets/imported/props/dressing/{asset}.glb'
        assert props[role]['mesh_path'] == path
        assert props[role]['y_offset'] == 0.0
        assert props[role]['scale'] == 1.0
        assert (ROOT / path.removeprefix('res://')).is_file()
```

Run `/opt/homebrew/bin/python3.11 -m pytest -q tests/test_room_asset_gameplay_bindings.py`; expected RED: empty `mesh_path` does not match promoted leaf.

Edit only these existing objects in `data/kits/gameplay_prop_v0.json`:

- `props.loot_crate.mesh_path` = `res://assets/imported/props/dressing/loot_container_derelict_v1.glb`; `y_offset` = `0.0`; `scale` = `1.0`.
- `props.workbench.mesh_path` = `res://assets/imported/props/dressing/crafting_station_derelict_v1.glb`; `y_offset` = `0.0`; `scale` = `1.0`.

Preserve all other roles and fields. Bottom-centered authored visuals do not inherit the old primitive half-height offset. Rerun the Python test and C2 smoke; both must pass. Then physically inspect the two imported visuals in the production scene; a JSON path match alone does not prove placement or interaction.

Commit the test and `data/kits/gameplay_prop_v0.json` after GREEN. Do not claim the factory/catalog route automatically populates room dressing tables or changes gameplay objective selection.

---

## 9. F — Room/derelict validation and release gates

### F1. Verify sockets and runtime ownership after integration

Run:

```bash
/opt/homebrew/bin/python3.11 tools/validate_structural_variant_bindings.py --project-root "$ROOT"
/opt/homebrew/bin/python3.11 tools/validate_prop_visual_bindings.py --project-root "$ROOT" --check-index
run_godot res://scripts/validation/structural_wrapper_collision_footprint_smoke.gd 'STRUCTURAL WRAPPER COLLISION FOOTPRINT PASS'
run_godot res://scripts/validation/playable_generated_ship_floor_collision_smoke.gd 'PLAYABLE GENERATED SHIP FLOOR COLLISION SMOKE PASS'
run_godot res://scripts/validation/structural_variant_wrapper_smoke.gd 'STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true'
```

Expected: no missing variants/resources, floor remains solid, wall slabs/corners retain 0.20 m runtime thickness policy, openings remain traversable, blocked routes remain blocked. Visual mesh surface details do not redefine physics.

### F2. Verify production boot and existing five-room traversal

```bash
run_godot res://scripts/validation/main_coherent_boot_smoke.gd 'MAIN COHERENT BOOT PASS scene=playable_coherent_ship'
run_godot res://scripts/validation/coherent_playable_scene_smoke.gd 'COHERENT PLAYABLE SCENE PASS'
run_godot res://scripts/validation/coherent_playable_traversal_smoke.gd \
  'COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true'
run_godot res://scripts/validation/procgen_playable_ship_smoke.gd 'PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true'
run_godot res://scripts/validation/procgen_ship_walkthrough_smoke.gd 'WALKTHROUGH PASS'
```

Expected: actual production boot, five-room objective/blocked-route proof, generated-ship collision/interaction proof, and completed walkthrough. Record that the coherent traversal helper may use validation seams; accompany it with a real manual walk through doors/corners rather than describing every smoke as a human-input traversal test.

### F3. Capture the real promoted five-room ship

```bash
"$GODOT" --path "$ROOT" --resolution 1600x900 \
  --script res://scripts/validation/coherent_proof_ship_capture.gd -- \
  --output "$PREVIEW/promoted-coherent-ship.png" --capture-frame 180
```

Expected: `COHERENT PROOF SHIP CAPTURE PASS ... mode=viewport`, complete PNG, no unexpected diagnostics. Do not add `--headless` to this art proof. Inspect the image at actual player distance; no map fallback, cropped-out bad junctions, or alternate camera masquerading as production.

### F4. Perform six small manual acceptance checks in the live scene

Launch `"$GODOT" --path "$ROOT" res://scenes/procgen/playable_coherent_ship.tscn`. Use existing input bindings from `project.godot`; do not invent undocumented key commands.

1. Walk entry → corridor → each accessible room and back; verify no floor drop, snagging, fake doorway, or gap at a corner.
2. Approach every objective from its intended side; verify prop/collision do not prevent interaction.
3. Search a generated loot container; verify one grant, searched state, imported visual hidden with the marker, no leftover primitive. Repeat interaction: no second grant.
4. Leave/re-enter or use the existing save/restore test path; verify the current searched-state policy remains intact. Do not add a new save schema.
5. Exercise existing damage/repair state changes and inspect intact/damaged/breached visual switching; verify no duplicate visible variants and no missing floor collision.
6. Inspect overhead cutaway/fade and camera occlusion. In dark/emergency configurations supported by the runtime, identify the player, doors, loot, and work surface without moving the camera to a flattering angle.

Record actual actions/results and screenshots in `$PREVIEW/playthrough.md`. If a particular fixture lacks a container or workbench, use the generated playable ship that instantiates that existing owner; do not mark an absent interaction tested. Missing coverage blocks the corresponding acceptance criterion.

### F5. Execute the full automated gate

```bash
/usr/bin/python3 tools/meshy_asset_contract.py validate data/asset_generation/contracts/*.json
/usr/bin/python3 -m pytest -q \
  tests/test_meshy_asset_contract.py tests/test_meshy_stage.py \
  tests/test_meshy_candidate_review.py tests/test_meshy_blender_tools.py \
  tests/test_meshy_texture_packet.py tests/test_meshy_promotion_packet.py \
  tests/test_meshy_runtime_review.py tests/test_meshy_reapprove.py
/opt/homebrew/bin/python3.11 -m pytest -q \
  tests/test_prop_visual_metadata.py tests/test_room_asset_dressing_inventory.py \
  tests/test_room_asset_gameplay_bindings.py
/opt/homebrew/bin/python3.11 tools/run_canonical_regression.py --project-root "$ROOT" --check
/opt/homebrew/bin/python3.11 tools/run_canonical_regression.py --project-root "$ROOT"
```

Expected: all tests pass, canonical manifest validates, the actual bundle runs and emits its final clean-output marker. Capture stdout/stderr and durations; do not reuse the historical 442-test result as evidence. Source/art-specific tests discovered in baseline must also run for any source tools changed; this plan otherwise does not modify the source tooling.

### F6. Produce a usable handoff, not a screenshot dump

First run this exact inventory check; it counts distinct asset IDs rather than binding aliases:

```bash
/opt/homebrew/bin/python3.11 - <<'PY'
import json
from pathlib import Path
root = Path.cwd()
kit = json.loads((root / 'data/kits/ship_structural_v0.json').read_text())
index = json.loads((root / 'data/props/visual_bindings.generated.json').read_text())
structural = {m['module_id'] for m in kit['modules']}
assert len(structural) == kit['module_count'] == 15
counts = {'components': 11, 'dressing': 13, 'objectives': 4}
all_ids = set(structural)
for group, expected_count in counts.items():
    records = index[group]
    unique = {record['asset_id'] for record in records.values()}
    assert len(unique) == expected_count, (group, unique)
    assert not all_ids.intersection(unique), 'asset ID collision across groups'
    all_ids.update(unique)
    for record in records.values():
        path = root / record['visual_scene_path'].removeprefix('res://')
        assert path.is_file(), path
        assert path.read_bytes()[:4] == b'glTF', path
assert len(all_ids) == 43
assert {'loot_container_derelict_v1', 'crafting_station_derelict_v1'} <= all_ids
print('ROOM ASSET INVENTORY PASS structural=15 components=11 dressing=13 objectives=4 distinct=43')
PY
```

Expected: the exact inventory PASS line. Metadata validators still own hashes, bounds, provenance, and binding validity; this roster check does not replace them.

Create `docs/game/assets/room_assets_v1_handoff.md` containing:

- Exact 43-ID roster and production GLB/sidecar/wrapper paths; source path and backup path for each authored asset; explicit reuse-only source restrictions.
- State vocabulary, grid step, coordinate/pivot rules, allowed rotations, collision owner, placement surface, intended room roles.
- The accepted one-room reference, promoted five-room viewport image, and six-case Meshy manifests with actual counts.
- Per-asset rights/provenance and raw → master → cleaned → promoted hashes; never include credentials, signed URLs, or API keys.
- Reproduction commands from this plan and fresh test logs, reviewed commit SHA, known limitations, and instructions for building a new room by reusing the existing wrapper/catalog contracts.
- A clear statement that pressure-door/fire-station/breach-seal focused candidates are NOT part of the production roster, and that loot open-state animation/new crafting mechanics were not implemented.

Add the relevant gate rows to `docs/game/06_validation_plan.md` without duplicating the canonical bundle. Commit handoff and validation docs separately from binaries. Run canonical `--check` after documentation edits.

### F7. Independent final review and release decision

A reviewer other than the author checks roster completeness, real source backups, contract compliance, visual quality, production consumer reachability, physics/interaction proof, provenance, and exact diff scope. Resolve spec issues first, then code/art-quality issues. Re-run affected gates after each correction; screenshots made before an asset change cannot approve its new bytes.

Do not merge, push, or publish merely because the plan mentions frequent commits. A separately authorized integration/release action selects the reviewed commit and verifies the live target after applying it. Preserve the original dirty main work and reconcile `docs/game/05_requirements.md` / `docs/game/06_validation_plan.md` hotspots explicitly.

---

## 10. Dependencies and worker ownership

Execution graph:

`A baseline/spec/source isolation -> B one-room acceptance -> B full kit qualification -> E structural promotion -> F`

`A -> C factory fix -> E gameplay bindings -> F`

`A -> D existing-loot audit + crafting reference/generation -> D fresh gates/backups -> E Meshy promotion -> E bindings -> F`

Parallelize only independent source review, Python/Godot code fix, and provider candidate inspection. Serialize shared external master writes, batch evidence publication, catalog/index edits, structural promotions, and canonical validation-document edits. Three workers is enough; do not run multiple provider submitters for one contract.

Suggested roles, not assumed installed profile names: technical artist (Blender/Meshy source), game programmer (factory and bindings), QA/reviewer (visual/physics/gate). If execution is converted into Kanban, discover actual profiles first and create scoped dependency cards only after plan approval; no board actions were performed in this planning turn.

---

## 11. Risks, tradeoffs, and explicit stop conditions

| Risk | Handling |
|---|---|
| Dirty checkout and stale source paths | Isolated reviewed worktree; explicit source-root verification; preserve unrelated changes. |
| External drive absent or shared master collision | Stop the affected lane; do not recreate a fake source tree or have two artists save the same master. |
| Same-volume backup | Useful checkpoint, not disaster recovery; report limitation and use an existing approved off-volume target if available. |
| Historical `promotion_ready` vs changed protected bytes | Fresh verification and audited recovery only; no hash editing or automatic reapproval. |
| Recipe visual export removes old collision | Inspect current wrapper ownership and run physical floor/door probes before accepting promotion. |
| Asset pack looks coherent only in a turntable | One-room art gate plus production five-room viewport and real playthrough. |
| Generic Meshy master command mistaken for cleanup | Explicit artist cleanup/UV/export tasks; no claim that SOURCE_RAW duplication is production quality. |
| Provider timeout / ambiguous task creation | Preserve journal, reconcile, GET-only resume. Never resubmit the same planned record. |
| New prop roster breaks fixed inventory validators | E3–E5 atomic reviewed integration, exact counts, real sidecars; no relaxed inventory assertions. |
| GLB binding bypasses runtime state visibility | C RED/GREEN smoke and actual loot search/revisit test. |
| Contract dimension/axis mismatch | Verify Blender and Godot bounds/orientation independently; no silent reinterpretation to force a pass. |
| Crafting candidate cleanup exceeds bounded effort | Reject; do not replace it with a generic block while claiming Meshy provenance or weaken the contract. |
| Procedural worldgen defect unrelated to assets | Record baseline and route a separate repair; asset release cannot claim playable proof until required checks pass. |
| Meshy/Blender quality takes longer than estimated | Microtasks are operator effort, not guarantees of total art-production duration. Repeat only the failed operation with fresh evidence. |

No upfront art-direction question is needed: this plan chooses the established locked-isometric salvage-industrial direction and a finite room-building kit. Execution-time unknowns that cannot be fabricated are actual provider task IDs, actual reviewer identity, current pricing maximum, fresh base SHA, absent source credentials/mounts, and visual verdicts. These have explicit discovery/gate steps above.

### Definition of done

- [ ] All 43 distinct IDs are accounted for; aliases and staged candidates are not counted as additional production models.
- [ ] All 15 structural modules retain exact contract placement and usable wrapper physics.
- [ ] All 28 prop asset leaves have valid metadata/provenance; 26 are qualified reuse and two are governed Meshy production assets.
- [ ] Source masters and backups are real, with explicit limitations for reuse-only assets.
- [ ] One-room art gate passed before bulk authoring.
- [ ] Both Meshy assets have fresh Blender and six-case runtime evidence before reviewed promotion.
- [ ] Gameplay imported-visual test proved RED then GREEN; no duplicate primitive or visible residue after owner hide.
- [ ] Existing loot/workbench owners load the new visuals without changing gameplay/persistence semantics.
- [ ] The production five-room ship boots, traverses, preserves blocked routes, and completes objectives; generated-ship proof passes too.
- [ ] Real viewport image and manual interaction/occlusion/physics checks pass for promoted bytes.
- [ ] Full canonical regression and focused suites passed with fresh logs.
- [ ] Handoff names exact assets, source/provenance, room recipes, commands, limitations, and reviewed commit.
- [ ] Independent spec and quality reviews approve; no unrelated dirty work was overwritten or committed.
