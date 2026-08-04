# Synaptic Sea Complete Asset Pipeline Design

> **Date:** 2026-08-03
> **Status:** Draft — awaiting user review
> **Scope:** Close all 5 remaining pipeline gaps in phased order
> **Prerequisite:** Blender structural source recovery (8 modules, complete)

## Overview

The Synaptic Sea structural asset pipeline currently has a working source
recovery layer (8 modules with contract-derived helpers, inspector, validator)
but lacks the ability to promote sources to runtime, covers only 8 of 15
catalog modules, has no automated authoring tool, no artistic iteration
workflow, and no backup for external source files.

This design closes all 5 gaps in linear phases, each independently shippable.

## Phase 1: Staged Export/Promotion Gate

**Goal:** Enable `.blend` sources to produce validated runtime GLBs.

### Architecture

```
Source (.blend)              Staging                    Runtime
─────────────              ───────                    ───────
Blender export  →  /Volumes/.../staging/<module_id>/  →  assets/imported/structural/
  intact.glb       intact.glb  (new, reviewed)          <module_id>.glb
  damaged.glb      damaged.glb (new, reviewed)          <module_id>_damaged.glb
  breached.glb     breached.glb (new, reviewed)         <module_id>_breached.glb
```

### CLI

```
promote_structural_sources.py \
  --project-root <path> \
  --source-root <path> \
  --staging-root <path> \
  --module <id> | --all \
  [--dry-run] [--force] [--backup]
```

### Pipeline steps per module

1. **Export** — Blender subprocess opens `.blend`, exports GLB collections to
   staging. Each collection tagged with variant role (`intact`, `damaged`,
   `breached`) exports to the corresponding staged file.
2. **Hash** — Compute SHA-256 of each staged GLB.
3. **Skip-if-identical** — Compare staged hash to current runtime GLB hash.
   If identical and `--force` not set, skip with `STRUCTURAL_PROMOTED_SKIP
   module=<id> reason=hash_match`.
4. **Validate** — Run Godot import smoke test against staged assets (copy
   staged GLBs to a temp `assets/imported/` overlay, run `godot --headless
   --import`, check zero errors).
5. **Smoke** — Run structural variant wrapper smoke test against staged
   overlay.
6. **Promote** — Copy staged GLBs to `assets/imported/structural/`, preserving
   existing `.import` files. Only the GLB bytes change; Godot re-imports on
   next editor open.
7. **Verify** — Re-run Godot import against promoted assets to confirm the
   promotion itself didn't break anything.
8. **Report** — Print `STRUCTURAL_PROMOTED module=<id> glbs=<n>` per module,
   summary at end.

### Variant handling

Each module's `.blend` may contain 1–3 exportable collections:

- `Export_Intact` — always present, produces `<module_id>.glb`
- `Export_Damaged` — optional, produces `<module_id>_damaged.glb`
- `Export_Breached` — optional, produces `<module_id>_breached.glb`

Collections are identified by name prefix `Export_` and a custom property
`variant_role` (values: `intact`, `damaged`, `breached`). If only intact
exists, damaged/breached GLBs in staging are skipped and existing runtime
variants are preserved.

### Safety

- `--dry-run` shows what would change without touching anything.
- `--force` overrides the hash-match skip.
- If any validation step fails, the module is skipped with `ERROR:` message
  and nonzero exit. Other modules continue.
- Staging directory is cleaned before each run.
- The promote tool reads `.source.json` to verify contract/hash integrity
  before export.

### Files

| Path | Responsibility |
|------|---------------|
| `tools/promote_structural_sources.py` | CLI orchestrator: export → hash → validate → promote |
| `tools/export_structural_glb.py` | Blender-only: open .blend, export tagged collections |
| `tools/validate_promoted_sources.py` | Standard-Python: Godot import + smoke test against staging |
| `tests/test_promote_structural_sources.py` | Unit tests for hash comparison, skip logic, report format |
| `tests/test_export_structural_glb.py` | Blender-backed tests for collection detection and export |

---

## Phase 2: Remaining 7 Catalog Modules

**Goal:** Extend source recovery to all 15 structural modules.

### Modules

All 7 have existing GLBs (~3KB primitives) and contracts. Same recovery
pipeline as the original 8:

| Module | Family | Footprint |
|--------|--------|-----------|
| bulkhead_portal_2x1 | portal | [2, 1] |
| ceiling_cap_1x1 | ceiling | [1, 1] |
| doorway_frame_blocked_1x1 | portal | [1, 0] |
| wall_end_cap | wall | [1, 0] |
| wall_inner_corner | wall | [1, 1] |
| wall_outer_corner | wall | [1, 1] |
| wall_t_junction | wall | [1, 1] |

### Changes

1. Expand `STRUCTURAL_SOURCE_MODULE_IDS` in
   `tools/structural_source_contract.py` from 8 to 15.
2. Run `recover_modules.py --all` with the expanded list.
3. Run `validate_structural_sources.py --all` to verify all 15.
4. Update documentation and validation plan.

### Geometry improvement

Artists can later improve geometry via the Blender add-on (Phase 3). The
initial recovery preserves existing primitives as-is, matching the pattern
established for the first 8 modules.

### Files

| Path | Change |
|------|--------|
| `tools/structural_source_contract.py` | Expand `STRUCTURAL_SOURCE_MODULE_IDS` to 15 |
| `tests/test_structural_source_contract.py` | Update parameterized tests for 15 modules |
| `docs/game/features/blender_structural_source_pipeline.md` | Update module list |

---

## Phase 3: Blender Add-on for One-Button Module Generation

**Goal:** Provide a Blender UI panel for creating and editing structural
modules with contract-derived helpers.

### UI Panel (N-panel sidebar, "Structural" tab)

```
┌─────────────────────────┐
│  Structural Module Tool  │
├─────────────────────────┤
│ Module ID: [floor_3x3  ]│
│ Family:    [floor    ▼] │
│ Grid Size: [3] x [3]    │
│                          │
│ [Load Contract]          │
│ [Import GLB]             │
│ [Generate Helpers]       │
│ [Export GLB]             │
│ [Validate]               │
├─────────────────────────┤
│ Status: Ready            │
│ Sockets: 8 detected      │
│ Contract: valid          │
└─────────────────────────┘
```

### Operator workflows

**New module:**
1. Enter module ID + family + grid size
2. "Load Contract" reads existing or creates draft contract JSON
3. "Generate Helpers" adds socket empties + collision proxy
4. Artist authors geometry in Blender
5. "Export GLB" stages for promotion

**Edit existing:**
1. "Import GLB" loads current runtime asset
2. Artist modifies geometry
3. "Export GLB" stages for promotion

**Validate:**
1. "Validate" runs inspector against current scene
2. Shows pass/fail in panel status

### Contract creation

When a module ID doesn't have a contract yet, the add-on generates a draft
from:
- Family template (floor, wall, portal, support, corridor_floor,
  vertical_transition, ceiling)
- Grid size → footprint_cells
- Family + grid → default socket positions (edges at grid boundaries)

Draft is saved to
`data/placement/contracts/structural/ship_structural_v0/<module_id>_contract.json`.
Must be reviewed and committed before promotion.

### Architecture

```
tools/blender_addons/structural_module_toolkit/
├── __init__.py          # Add-on registration, bl_info
├── panels.py            # UI panel (N-panel sidebar)
├── operators.py         # Button operators (Load, Import, Generate, Export, Validate)
├── export.py            # Staged GLB export with variant tagging
├── contract_creator.py  # Draft contract generation from family templates
└── preferences.py       # Add-on preferences (source root, staging root)
```

Reuses `tools/structural_source_contract.py` for contract loading (imported
as Blender-external module via `sys.path` manipulation).

### Files

| Path | Responsibility |
|------|---------------|
| `tools/blender_addons/structural_module_toolkit/` | Blender add-on package |
| `tests/test_contract_creator.py` | Unit tests for draft contract generation |
| `tests/test_export_structural_glb.py` | Already created in Phase 1 |

---

## Phase 4: Artistic Iteration Workflow

**Goal:** Provide artists with materials, documentation, and validation
tooling for working with structural sources.

### Material library

A Blender material file at `meshes/source/materials/salvage_industrial.blend`
containing:
- `MAT_PaintedAlloyGray` — base structural material (roughness 0.7, metallic
  0.35, gray)
- `MAT_WarningStripe` — hazard marking (yellow/black)
- `MAT_ReactorGlow` — emissive blue-green for reactor areas
- `MAT_Biomatter` — organic contamination (dark red, subsurface)
- `MAT_Conduit` — cable/pipe material (dark rubber)

Artists append materials from this file via Blender's File → Append.

### Export operator

The Blender add-on's "Export GLB" button (from Phase 3) handles staging
export with correct settings:
- Format: GLB (binary glTF)
- Up axis: Y-up (Godot convention)
- Apply transforms: yes
- Draco compression: optional (off by default)
- Preserve hierarchy: yes (ModuleRoot → Geometry)
- Selection: only `Export_*` collections

### Validation shortcut

The add-on's "Validate" button runs the inspector in-process (no subprocess)
and shows results in the panel status area. Errors are listed with specific
object names and expected vs actual values.

### Documentation

`docs/game/features/blender_artist_workflow.md` covering:
- How to open source .blend files
- Material library usage and append workflow
- Export process (staging → validation → promotion)
- What validation checks and how to fix common failures
- Coordinate system reference (contract Y-up ↔ Blender Z-up)

### Files

| Path | Responsibility |
|------|---------------|
| `meshes/source/materials/salvage_industrial.blend` | Material library |
| `docs/game/features/blender_artist_workflow.md` | Artist workflow guide |
| `tools/blender_addons/structural_module_toolkit/panels.py` | Updated with material append operator |

---

## Phase 5: Cloud Backup Integration

**Goal:** Sync external source files to a cloud bucket as part of the promote
pipeline.

### CLI

```
backup_structural_sources.py \
  --source-root <path> \
  --backup-target <url> \
  [--dry-run]
```

### Behavior

- Runs `rsync` (or `aws s3 sync` / `gsutil rsync`) from source root to
  backup target
- Preserves directory structure:
  `<bucket>/meshes/source/ship_structural_v0/<module_id>/`
- Includes `.blend`, `.source.json`, and any variant sources
- Dry-run shows what would be synced without uploading
- Exits nonzero on rsync failure

### Integration with promote pipeline

`promote_structural_sources.py` gets a `--backup` flag. When set, runs backup
before promotion (source is backed up before any runtime changes). Can also
run standalone.

### Configuration

- Backup target URL in `config.yaml` under `synaptic_sea.backup_target`
- Or passed as `--backup-target` CLI arg
- Supports S3 (`s3://bucket/path`), GCS (`gs://bucket/path`), or local path

### Files

| Path | Responsibility |
|------|---------------|
| `tools/backup_structural_sources.py` | Backup CLI |
| `tools/promote_structural_sources.py` | Updated with `--backup` flag |
| `tests/test_backup_structural_sources.py` | Unit tests for dry-run, target validation |

---

## Risks and Tradeoffs

- **Godot smoke tests require a working Godot install.** The promote gate
  runs Godot headless for validation. If Godot is not installed or broken,
  promotion is blocked. Mitigation: `--skip-godot` flag for CI environments
  that don't have Godot.
- **Blender add-on maintenance.** Blender's Python API changes between major
  versions. The add-on targets Blender 4.x; Blender 5.x may need updates.
  Mitigation: version check in `__init__.py` with clear error message.
- **Cloud backup requires credentials.** The backup script needs cloud
  provider credentials configured. Mitigation: fall back to local rsync if
  cloud target is not configured.
- **Draft contracts need human review.** The add-on's auto-generated contracts
  are drafts — socket positions are template-derived and may need adjustment
  for non-standard modules. Mitigation: validation catches position errors at
  promote time.
- **External files not in Git.** `.blend` files live on external storage.
  Cloud backup (Phase 5) addresses this, but artists should understand the
  risk of working without version control for binary files.

## Phase Dependencies

```
Phase 1 (Export Gate) ←── Phase 2 (Remaining Modules) ←── Phase 3 (Add-on)
                                                    ↖────── Phase 4 (Art Workflow)
Phase 5 (Backup) ←── Phase 1 (uses promote pipeline)
```

- Phase 1 is the critical blocker; everything else depends on it.
- Phase 2 can start as soon as Phase 1 is done (trivial expansion).
- Phase 3 depends on Phase 1 (add-on uses export gate).
- Phase 4 depends on Phase 3 (add-on provides material append + export).
- Phase 5 depends on Phase 1 (backup integrates with promote).

## Success Criteria

1. `promote_structural_sources.py --all` promotes all 15 modules from source
   to runtime with zero Godot errors.
2. The Blender add-on can create a new module from scratch (contract +
   helpers + export) in under 5 minutes.
3. All 15 `.blend` source files are backed up to cloud storage.
4. Full test suite passes: 150+ tests covering contract, recovery,
   inspection, validation, promotion, export, and backup.
5. Documentation covers the complete workflow from authoring to runtime.
