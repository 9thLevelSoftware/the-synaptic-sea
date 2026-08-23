# Vertical Slice Asset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace prototype readability stand-ins with a coherent Salvage Industrial environment for the fixed lifeboat and eight-room derelict golden fixture, including structural integrity visuals, objective props, materials, VFX, and thin-slice audio.

**Architecture:** Blender remains the source of truth for all structural geometry. Eight P0 modules are recovered from existing imported GLBs into canonical `.blend` sources, then sixteen integrity variants are authored. A runtime visual resolver maps integrity states to alternate GLB children. Non-structural props are authored in Blender (some using Meshy donor meshes as starting points). Materials are procedural/PBR. Audio is synthesized or sourced from free libraries.

**Tech Stack:** Godot 4.7.1, Blender (CLI), GDScript, glTF/GLB, sidecar JSON, ComfyUI (concept art only), Meshy AI (non-structural donors only)

## Global Constraints

- Structural geometry (floors, walls, corridors, portals, bulkheads, ramps) is ALWAYS hand-authored in Blender with explicit sockets and collision. AI-generated structural topology is prohibited.
- All heavy assets live under `/Volumes/Untitled/SynapticSeaAssets/`, not the internal drive.
- Existing module IDs, 4m footprint, origin/pivot policy, socket interface, collision proxy behavior, and Godot wrapper identity are preserved — never changed.
- The repository at `/Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea` is the integration and declarative-contract home.
- No changes to procgen layout, objectives, player movement, combat, inventory rules, save format, or ship-system simulation semantics.
- Godot 4.7.1 installed at `/opt/homebrew/bin/godot`.

## Asset Root Layout

```
/Volumes/Untitled/SynapticSeaAssets/
  meshes/source/ship_structural_v0/<module_id>/<module_id>.blend
  meshes/processed/ship_structural_v0/<module_id>/<module_id>_intact.glb
  meshes/processed/ship_structural_v0/<module_id>/<module_id>_damaged.glb
  meshes/processed/ship_structural_v0/<module_id>/<module_id>_breached.glb
  meshes/incoming/<donor-glb>
  concepts/
  textures/
  audio/
```

---

## Phase 1: Structural Source Recovery and Validation

### Task 1.1: Create asset directory structure and provenance scaffold

**Files:**
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/` (8 subdirectories)
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/` (8 subdirectories)
- Create: `/Volumes/Untitled/SynapticSeaAssets/concepts/`
- Create: `/Volumes/Untitled/SynapticSeaAssets/textures/`
- Create: `/Volumes/Untitled/SynapticSeaAssets/audio/`

**Steps:**

- [ ] **Step 1: Create directory tree**

```bash
MODULES="floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2"
BASE="/Volumes/Untitled/SynapticSeaAssets"
for m in $MODULES; do
  mkdir -p "$BASE/meshes/source/ship_structural_v0/$m"
  mkdir -p "$BASE/meshes/processed/ship_structural_v0/$m"
done
mkdir -p "$BASE/concepts" "$BASE/textures" "$BASE/audio"
```

- [ ] **Step 2: Verify directories exist**

```bash
ls -la /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/
ls -la /Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/
```

- [ ] **Step 3: Commit scaffold** (no repo changes — this is external asset drive only)

**Stop condition:** All 8 source and 8 processed subdirectories exist on the external drive.

---

### Task 1.2: Extract existing GLB metadata for the 8 P0 modules

**Files:**
- Read: `assets/imported/structural/ship_structural_v0/<module_id>/<module_id>.glb` (8 files)
- Read: `data/placement/contracts/structural/ship_structural_v0/<module_id>_contract.json` (8 files)
- Read: `scenes/wrappers/structural/ship_structural_v0/<module_id>.tscn` (8 files)
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.meta.json` (8 files)

**Consumes:** Existing repository GLBs, contracts, and wrapper scenes.
**Produces:** Per-module metadata JSON capturing socket positions, collision bounds, pivot policy, and wrapper structure — ground truth for Blender recovery.

**Steps:**

- [ ] **Step 1: Write extraction script**

```python
#!/usr/bin/env python3
"""Extract metadata from existing GLB + contract + wrapper for each P0 module."""
import json, os, re, sys

REPO = "/Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea"
OUT = "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0"

MODULES = [
    "floor_1x1", "floor_2x1", "corridor_floor_1x1", "corridor_floor_1x2",
    "wall_straight_1x1", "doorway_frame_open_1x1", "pillar_support_1x1", "ramp_up_1x2"
]

for mod in MODULES:
    contract_path = f"{REPO}/data/placement/contracts/structural/ship_structural_v0/{mod}_contract.json"
    wrapper_path = f"{REPO}/scenes/wrappers/structural/ship_structural_v0/{mod}.tscn"
    glb_path = f"{REPO}/assets/imported/structural/ship_structural_v0/{mod}/{mod}.glb"

    meta = {"module_id": mod, "source_files": {}}

    # Read contract
    if os.path.exists(contract_path):
        with open(contract_path) as f:
            contract = json.load(f)
        meta["contract"] = {
            "module_family": contract.get("module_family", ""),
            "grid_step_m": contract.get("grid_step_m", 4.0),
            "bounds": contract.get("bounds", {}),
            "footprint_cells": contract.get("footprint_cells", []),
            "sockets": contract.get("sockets", []),
            "collision": contract.get("collision", {}),
            "provenance": contract.get("provenance", {}),
        }
        meta["source_files"]["contract"] = contract_path

    # Read wrapper scene (parse socket Marker3D positions)
    if os.path.exists(wrapper_path):
        with open(wrapper_path) as f:
            tscn = f.read()
        sockets_in_scene = re.findall(r'name="Anchor_SOCK_(\w+)"', tscn)
        meta["wrapper"] = {
            "sockets_in_scene": sockets_in_scene,
            "has_collision": "CollisionRoot" in tscn,
            "has_visual": "Visual" in tscn,
            "visual_resource_path": re.search(r'path="(res://[^"]+\.glb)"', tscn).group(1) if re.search(r'path="(res://[^"]+\.glb)"', tscn) else None,
        }
        meta["source_files"]["wrapper"] = wrapper_path

    # GLB file size
    if os.path.exists(glb_path):
        meta["source_files"]["glb"] = glb_path
        meta["glb_size_bytes"] = os.path.getsize(glb_path)

    out_path = f"{OUT}/{mod}/{mod}.meta.json"
    with open(out_path, 'w') as f:
        json.dump(meta, f, indent=2)
    print(f"Wrote: {out_path}")
```

- [ ] **Step 2: Run extraction**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
python3 /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/extract_meta.py
```

- [ ] **Step 3: Verify all 8 meta.json files exist and contain expected fields**

```bash
for m in floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2; do
  echo "=== $m ==="
  python3 -c "import json; d=json.load(open('/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/$m/$m.meta.json')); print('sockets:', len(d.get('contract',{}).get('sockets',[])), 'family:', d.get('contract',{}).get('module_family',''))"
done
```

- [ ] **Step 4: Commit extraction script to repo**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
git add scripts/tools/extract_module_meta.py
git commit -m "tools: add P0 module metadata extraction script"
```

**Stop condition:** 8 meta.json files exist with correct socket counts, bounds, and collision definitions matching the contracts.

---

### Task 1.3: Recover 8 Blender source files from existing GLB geometry

**Files:**
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.blend` (8 files)
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.sidecar.json` (8 files)

**Consumes:** Existing GLBs at `assets/imported/structural/ship_structural_v0/`, meta.json from Task 1.2.
**Produces:** Canonical Blender source files with proper transforms, socket empties, collision proxies, and UV maps. Sidecar JSON with full provenance.

**Steps:**

- [ ] **Step 1: Write Blender recovery script template**

```python
#!/usr/bin/env python3
"""Recover a Blender source file from an existing GLB import.
Run with: blender --background --python recover_module.py -- <module_id>
"""
import bpy
import json
import os
import sys
import math

# Parse -- separator args
argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    print("Usage: blender --background --python recover_module.py -- <module_id>")
    sys.exit(1)

MODULE_ID = argv[0]
REPO = "/Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea"
ASSET_ROOT = "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0"

GLB_PATH = f"{REPO}/assets/imported/structural/ship_structural_v0/{MODULE_ID}/{MODULE_ID}.glb"
META_PATH = f"{ASSET_ROOT}/{MODULE_ID}/{MODULE_ID}.meta.json"
OUT_BLEND = f"{ASSET_ROOT}/{MODULE_ID}/{MODULE_ID}.blend"
OUT_SIDECAR = f"{ASSET_ROOT}/{MODULE_ID}/{MODULE_ID}.sidecar.json"

# Load metadata
with open(META_PATH) as f:
    meta = json.load(f)

contract = meta.get("contract", {})
sockets = contract.get("sockets", [])
bounds = contract.get("bounds", {})
collision = contract.get("collision", {})

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Import GLB
bpy.ops.import_scene.gltf(filepath=GLB_PATH)
imported = list(bpy.context.selected_objects)

# Apply transforms to all mesh objects
for obj in imported:
    if obj.type == 'MESH':
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Create socket empties from contract data
socket_names = []
for sock in sockets:
    sock_id = sock["id"]
    pos = sock.get("position_m", [0, 0, 0])
    empty = bpy.data.objects.new(f"Anchor_SOCK_{sock_id}", None)
    empty.empty_display_type = 'ARROWS'
    empty.empty_display_size = 0.3
    empty.location = (pos[0], pos[2], pos[1])  # GLB Y-up to Blender Z-up
    bpy.context.collection.objects.link(empty)
    socket_names.append(sock_id)

# Create collision proxy
coll_kind = collision.get("proxy_shape", "box")
bounds_min = bounds.get("local_min_m", [-2, 0, -2])
bounds_max = bounds.get("local_max_m", [2, 0.25, 2])

size_x = bounds_max[0] - bounds_min[0]
size_y = bounds_max[1] - bounds_min[1]
size_z = bounds_max[2] - bounds_min[2]
center_x = (bounds_max[0] + bounds_min[0]) / 2
center_y = (bounds_max[1] + bounds_min[1]) / 2
center_z = (bounds_max[2] + bounds_min[2]) / 2

bpy.ops.mesh.primitive_cube_add(size=1)
col_obj = bpy.context.active_object
col_obj.name = "CollisionProxy"
col_obj.display_type = 'WIRE'
col_obj.location = (center_x, center_z, center_y)  # Y-up to Z-up
col_obj.scale = (size_x, size_z, size_y)
bpy.ops.object.transform_apply(scale=True)

# Create origin marker
origin = bpy.data.objects.new("Origin", None)
origin.empty_display_type = 'PLAIN_AXES'
origin.empty_display_size = 0.5
bpy.context.collection.objects.link(origin)

# Save
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)

# Write sidecar
sidecar = {
    "asset_id": MODULE_ID,
    "module_id": MODULE_ID,
    "source_type": "recovered_from_imported_glb",
    "source_glb": GLB_PATH,
    "recovery_date": "2026-07-31",
    "grid_unit_m": contract.get("grid_step_m", 4.0),
    "footprint_cells": contract.get("footprint_cells", [1, 1]),
    "pivot_policy": bounds.get("placement_origin", "cell-center-floor"),
    "socket_names": socket_names,
    "collision_policy": collision,
    "material_list": [],  # populated after material pass
    "license": "self-authored",
    "validation_status": "recovered",
}
with open(OUT_SIDECAR, 'w') as f:
    json.dump(sidecar, f, indent=2)

print(f"Recovered: {OUT_BLEND}")
print(f"Sidecar: {OUT_SIDECAR}")
```

- [ ] **Step 2: Run recovery for all 8 modules**

```bash
MODULES="floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2"
for m in $MODULES; do
  echo "=== Recovering $m ==="
  blender --background --python /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/recover_module.py -- "$m" 2>&1 | tail -5
done
```

- [ ] **Step 3: Verify each .blend opens and contains expected objects**

```bash
MODULES="floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2"
for m in $MODULES; do
  echo "=== $m ==="
  blender --background "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/$m/$m.blend" \
    --python-expr "
import bpy
objs = [o.name for o in bpy.data.objects]
meshes = [o.name for o in bpy.data.objects if o.type == 'MESH']
sockets = [o.name for o in bpy.data.objects if 'SOCK' in o.name]
print(f'  Objects: {len(objs)}, Meshes: {len(meshes)}, Sockets: {len(sockets)}')
print(f'  Socket names: {sockets}')
" 2>&1 | grep -E "(Objects:|Socket)"
done
```

- [ ] **Step 4: Verify sidecar JSON files have correct socket counts**

```bash
for m in floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2; do
  echo -n "$m: "
  python3 -c "import json; d=json.load(open('/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/$m/$m.sidecar.json')); print(len(d['socket_names']), 'sockets')"
done
```

**Stop condition:** All 8 `.blend` files open without errors, contain mesh geometry + socket empties + collision proxy, and sidecars match contract socket counts.

---

### Task 1.4: Re-export intact GLBs from recovered Blender sources

**Files:**
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/<module_id>/<module_id>_intact.glb` (8 files)
- Modify: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.sidecar.json` (8 files — update validation_status)

**Consumes:** Blender sources from Task 1.3.
**Produces:** Fresh intact GLBs with guaranteed provenance, ready for Godot import.

**Steps:**

- [ ] **Step 1: Write GLB export script**

```python
#!/usr/bin/env python3
"""Export intact GLB from recovered Blender source.
Run: blender --background --python export_intact.py -- <module_id>
"""
import bpy, json, os, sys

argv = sys.argv[argv.index("--") + 1:] if "--" in sys.argv else sys.exit(1)
MODULE_ID = argv[0]
SRC = f"/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/{MODULE_ID}/{MODULE_ID}.blend"
OUT = f"/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/{MODULE_ID}/{MODULE_ID}_intact.glb"
SIDECAR = f"/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/{MODULE_ID}/{MODULE_ID}.sidecar.json"

bpy.ops.wm.open_mainfile(filepath=SRC)

# Export only mesh objects (exclude collision proxy and empties)
mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH' and o.name != 'CollisionProxy']
bpy.ops.object.select_all(action='DESELECT')
for obj in mesh_objects:
    obj.select_set(True)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    use_selection=False,  # export all visible
    export_apply=True,
    export_materials='EXPORT',
)

# Update sidecar
with open(SIDECAR) as f:
    sidecar = json.load(f)
sidecar["validation_status"] = "intact_exported"
sidecar["intact_glb"] = OUT
with open(SIDECAR, 'w') as f:
    json.dump(sidecar, f, indent=2)

print(f"Exported: {OUT} ({os.path.getsize(OUT)} bytes)")
```

- [ ] **Step 2: Run export for all 8 modules**

```bash
MODULES="floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2"
for m in $MODULES; do
  echo "=== Exporting $m ==="
  blender --background --python /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/export_intact.py -- "$m" 2>&1 | tail -3
done
```

- [ ] **Step 3: Verify GLBs are valid and non-empty**

```bash
for m in floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2; do
  f="/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/$m/${m}_intact.glb"
  sz=$(stat -f%z "$f" 2>/dev/null || echo 0)
  echo "$m: ${sz} bytes"
done
```

- [ ] **Step 4: Replace existing repo GLBs with re-exported intact versions**

```bash
MODULES="floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2"
REPO="/Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea"
for m in $MODULES; do
  SRC="/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/$m/${m}_intact.glb"
  DST="$REPO/assets/imported/structural/ship_structural_v0/$m/$m.glb"
  cp "$SRC" "$DST"
  echo "Replaced: $DST"
done
```

- [ ] **Step 5: Run Godot headless import to verify no breakage**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
godot --headless --import --quit 2>&1 | grep -iE "(error|warning|fail)" | head -20
```

- [ ] **Step 6: Commit re-exported GLBs**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
git add assets/imported/structural/ship_structural_v0/
git commit -m "assets: replace P0 structural GLBs with provenance-verified re-exports"
```

**Stop condition:** All 8 intact GLBs import into Godot without errors. File sizes are reasonable (>1KB, <5MB each).

---

## Phase 2: Integrity Variants and Visual Resolver

### Task 2.1: Author 8 damaged structural variants

**Files:**
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/<module_id>/<module_id>_damaged.glb` (8 files)

**Consumes:** Blender sources from Task 1.3.
**Produces:** 8 damaged GLB variants — same footprint and socket interface, with readable dents, scoring, heat damage, and partial panel loss.

**Steps:**

- [ ] **Step 1: Write Blender damage-variant script**

```python
#!/usr/bin/env python3
"""Author a damaged variant of a structural module.
Run: blender --background --python author_damaged.py -- <module_id>
"""
import bpy, bmesh, json, os, sys, random, math

argv = sys.argv[argv.index("--") + 1:] if "--" in sys.argv else sys.exit(1)
MODULE_ID = argv[0]
SRC = f"/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/{MODULE_ID}/{MODULE_ID}.blend"
OUT = f"/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/{MODULE_ID}/{MODULE_ID}_damaged.glb"

random.seed(hash(MODULE_ID + "_damaged"))

bpy.ops.wm.open_mainfile(filepath=SRC)

# Process each mesh object (not collision proxy or empties)
for obj in bpy.data.objects:
    if obj.type != 'MESH' or obj.name == 'CollisionProxy':
        continue
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')

    bm = bmesh.from_edit_mesh(obj.data)

    # Displace ~15% of vertices randomly for dent/scoring effect
    for v in bm.verts:
        if random.random() < 0.15:
            # Displace inward along normal
            disp = random.uniform(0.02, 0.08)
            v.co += v.normal * -disp
            # Add slight random offset
            v.co.x += random.uniform(-0.02, 0.02)
            v.co.z += random.uniform(-0.02, 0.02)

    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Add a dark material for scorch marks if not present
    if len(obj.data.materials) < 2:
        scorch_mat = bpy.data.materials.new(name=f"{MODULE_ID}_scorch")
        scorch_mat.use_nodes = True
        bsdf = scorch_mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (0.08, 0.06, 0.04, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.95
        obj.data.materials.append(scorch_mat)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=True)
print(f"Exported damaged: {OUT} ({os.path.getsize(OUT)} bytes)")
```

- [ ] **Step 2: Run for all 8 modules**

```bash
MODULES="floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2"
for m in $MODULES; do
  blender --background --python /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/author_damaged.py -- "$m" 2>&1 | tail -2
done
```

- [ ] **Step 3: Verify damaged GLBs exist and differ from intact**

```bash
for m in floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2; do
  intact=$(stat -f%z "/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/$m/${m}_intact.glb" 2>/dev/null)
  damaged=$(stat -f%z "/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/$m/${m}_damaged.glb" 2>/dev/null)
  echo "$m: intact=${intact} damaged=${damaged} (diff=$((damaged - intact)) bytes)"
done
```

**Stop condition:** 8 damaged GLBs exist, each structurally distinct from its intact counterpart (different vertex positions), but same footprint.

---

### Task 2.2: Author 8 breached structural variants

**Files:**
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/<module_id>/<module_id>_breached.glb` (8 files)

**Consumes:** Blender sources from Task 1.3.
**Produces:** 8 breached GLB variants — clear perforation/opening, exposed edge, readable as structurally compromised.

**Steps:**

- [ ] **Step 1: Write Blender breach-variant script**

```python
#!/usr/bin/env python3
"""Author a breached variant of a structural module.
Run: blender --background --python author_breached.py -- <module_id>
"""
import bpy, bmesh, json, os, sys, random, math
from mathutils import Vector

argv = sys.argv[argv.index("--") + 1:] if "--" in sys.argv else sys.exit(1)
MODULE_ID = argv[0]
SRC = f"/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/{MODULE_ID}/{MODULE_ID}.blend"
OUT = f"/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/{MODULE_ID}/{MODULE_ID}_breached.glb"

random.seed(hash(MODULE_ID + "_breached"))

bpy.ops.wm.open_mainfile(filepath=SRC)

for obj in bpy.data.objects:
    if obj.type != 'MESH' or obj.name == 'CollisionProxy':
        continue
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')

    bm = bmesh.from_edit_mesh(obj.data)

    # Create breach: remove ~20% of faces to create visible holes
    faces_to_delete = []
    for face in bm.faces:
        center = face.calc_center_median()
        # Breach concentrated in one area (offset from center)
        breach_center = Vector((
            random.uniform(-0.5, 0.5),
            random.uniform(-0.5, 0.5),
            0.0
        ))
        dist = (center - breach_center).length
        if dist < 0.8 and random.random() < 0.6:
            faces_to_delete.append(face)

    # Delete breach faces
    bmesh.ops.delete(bm, geom=faces_to_delete, context='FACES')

    # Displace remaining edges near breach for torn-edge effect
    for v in bm.verts:
        if random.random() < 0.25:
            disp = random.uniform(0.01, 0.05)
            v.co += v.normal * -disp
            v.co.x += random.uniform(-0.03, 0.03)

    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Add exposed-edge dark material
    if len(obj.data.materials) < 2:
        exposed_mat = bpy.data.materials.new(name=f"{MODULE_ID}_exposed")
        exposed_mat.use_nodes = True
        bsdf = exposed_mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (0.15, 0.12, 0.10, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.9
            bsdf.inputs["Metallic"].default_value = 0.8
        obj.data.materials.append(exposed_mat)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=True)
print(f"Exported breached: {OUT} ({os.path.getsize(OUT)} bytes)")
```

- [ ] **Step 2: Run for all 8 modules**

```bash
MODULES="floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2"
for m in $MODULES; do
  blender --background --python /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/author_breached.py -- "$m" 2>&1 | tail -2
done
```

- [ ] **Step 3: Verify breached GLBs exist and have fewer faces than intact (holes removed)**

```bash
for m in floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2; do
  for state in intact damaged breached; do
    f="/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/$m/${m}_${state}.glb"
    sz=$(stat -f%z "$f" 2>/dev/null || echo "MISSING")
    echo -n "$m/$state: ${sz}  "
  done
  echo
done
```

**Stop condition:** 8 breached GLBs exist with visible topology differences from intact (face deletion creates holes). All 24 variant GLBs (8×3 states) are present.

---

### Task 2.3: Import integrity variants into Godot and add to wrapper scenes

**Files:**
- Modify: `assets/imported/structural/ship_structural_v0/<module_id>/` (add `_damaged.glb` and `_breached.glb` per module)
- Modify: `scenes/wrappers/structural/ship_structural_v0/<module_id>.tscn` (8 files — add variant visual children)

**Consumes:** 24 GLBs from Tasks 1.4, 2.1, 2.2. Existing wrapper scenes.
**Produces:** Updated wrapper scenes with three visual children (intact, damaged, breached) selectable by the resolver.

**Steps:**

- [ ] **Step 1: Copy variant GLBs into repo**

```bash
MODULES="floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2"
REPO="/Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea"
for m in $MODULES; do
  for state in damaged breached; do
    SRC="/Volumes/Untitled/SynapticSeaAssets/meshes/processed/ship_structural_v0/$m/${m}_${state}.glb"
    DST="$REPO/assets/imported/structural/ship_structural_v0/$m/${m}_${state}.glb"
    cp "$SRC" "$DST"
    echo "Copied: $DST"
  done
done
```

- [ ] **Step 2: Update wrapper scenes to include variant visual children**

For each module's `.tscn`, add two additional `VisualInstance` nodes under `Visual`:

```tscn
[node name="Visual" type="Node3D" parent="."]

[node name="VisualInstance_Intact" parent="Visual" instance=ExtResource("1_visual")]
visible = true

[node name="VisualInstance_Damaged" parent="Visual" instance=ExtResource("2_visual_damaged")]
visible = false

[node name="VisualInstance_Breached" parent="Visual" instance=ExtResource("3_visual_breached")]
visible = false
```

Add the new ext_resources at the top of each `.tscn`.

- [ ] **Step 3: Run Godot headless import**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
godot --headless --import --quit 2>&1 | grep -iE "(error|warning|fail)" | head -20
```

- [ ] **Step 4: Commit**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
git add assets/imported/structural/ship_structural_v0/ scenes/wrappers/structural/ship_structural_v0/
git commit -m "assets: add damaged/breached integrity variants to P0 structural wrappers"
```

**Stop condition:** All 8 wrapper scenes import in Godot without errors. Each has 3 visual children (intact/damaged/breached) with correct visibility defaults.

---

### Task 2.4: Build runtime integrity visual resolver

**Files:**
- Create: `scripts/systems/integrity_visual_resolver.gd`
- Modify: `scripts/systems/module_integrity_consequences.gd` (expand `is_wall_kind` to cover all P0 families)
- Test: `scripts/validation/integrity_visual_resolver_smoke.gd`

**Consumes:** `ModuleIntegrityState` (states), `ModuleIntegrityConsequences` (mesh_suffix), wrapper scene visual children.
**Produces:** A resolver that maps integrity state → visible visual child in the wrapper scene, without creating new module IDs.

**Steps:**

- [ ] **Step 1: Write the resolver script**

```gdscript
extends RefCounted
class_name IntegrityVisualResolver

## Maps integrity state to the correct visual child in a structural wrapper scene.
## Does not change module identity, collision, or navigation — only visibility.

const STATE_INTACT: String = "intact"
const STATE_DAMAGED: String = "damaged"
const STATE_BREACHED: String = "breached"
const STATE_DESTROYED: String = "destroyed"

const SUFFIX_INTACT: String = "Intact"
const SUFFIX_DAMAGED: String = "Damaged"
const SUFFIX_BREACHED: String = "Breached"

## Apply visual state to a wrapper node's Visual child group.
## Returns true if a matching visual was found and toggled.
static func apply_visual_state(wrapper_node: Node3D, state: String) -> bool:
	var visual_group: Node3D = wrapper_node.get_node_or_null("Visual")
	if visual_group == null:
		return false

	# Hide all variant children
	var intact_node := visual_group.get_node_or_null("VisualInstance_Intact")
	var damaged_node := visual_group.get_node_or_null("VisualInstance_Damaged")
	var breached_node := visual_group.get_node_or_null("VisualInstance_Breached")

	# Legacy single-child fallback
	var legacy_node := visual_group.get_node_or_null("VisualInstance")

	if intact_node == null and damaged_node == null and breached_node == null:
		# Legacy wrapper with single VisualInstance — apply modulate tint
		if legacy_node != null and legacy_node is Node3D:
			var tint: Array = ModuleIntegrityConsequences.consequence_for_state(state).get("modulate", [1,1,1,1])
			legacy_node.modulate = Color(tint[0], tint[1], tint[2], tint[3])
			legacy_node.visible = (state != STATE_DESTROYED)
		return legacy_node != null

	# Variant-aware wrapper: hide all, show correct one
	if intact_node: intact_node.visible = false
	if damaged_node: damaged_node.visible = false
	if breached_node: breached_node.visible = false

	match state:
		STATE_INTACT:
			if intact_node: intact_node.visible = true
		STATE_DAMAGED:
			if damaged_node: damaged_node.visible = true
		STATE_BREACHED:
			if breached_node: breached_node.visible = true
		STATE_DESTROYED:
			pass  # all hidden = no visual

	return true


## Batch-apply integrity visuals to all modules in a ship scene tree.
## Expects each structural module wrapper to be a direct child of a modules container.
static func apply_to_ship(ship_root: Node3D, module_map: RefCounted) -> int:
	var applied: int = 0
	var modules_container := ship_root.get_node_or_null("StructuralModules")
	if modules_container == null:
		modules_container = ship_root  # fallback: modules are direct children

	for child in modules_container.get_children():
		if not child is Node3D:
			continue
		var module_id: String = child.name
		if module_map == null or not module_map.has_method("get_state"):
			continue
		var state: String = module_map.call("get_state", module_id)
		if apply_visual_state(child, state):
			applied += 1

	return applied
```

- [ ] **Step 2: Expand `is_wall_kind` to cover all P0 structural families**

In `module_integrity_consequences.gd`, update `WALL_PREFIXES`:

```gdscript
const STRUCTURAL_PREFIXES: Array[String] = [
	"wall_", "bulkhead_", "panel_", "door_",
	"floor_", "corridor_", "pillar_", "ramp_",
]

static func is_structural_kind(kind: String) -> bool:
	if kind.is_empty():
		return false
	var k: String = kind.to_lower()
	for prefix in STRUCTURAL_PREFIXES:
		if k.begins_with(prefix) or k.find(prefix) >= 0:
			return true
	return false
```

Keep `is_wall_kind` for backward compat but add `is_structural_kind` for the resolver's use.

- [ ] **Step 3: Write smoke test**

```gdscript
extends "res://scripts/validation/_base_smoke.gd"

func test_name() -> String:
	return "integrity_visual_resolver"

func run(p_result: RefCounted) -> void:
	# Verify resolver exists and can be instantiated
	var resolver_script = preload("res://scripts/systems/integrity_visual_resolver.gd")
	assert(resolver_script != null, "Resolver script loaded")

	# Verify consequence suffixes match wrapper naming
	for state in ["intact", "damaged", "breached", "destroyed"]:
		var c = ModuleIntegrityConsequences.consequence_for_state(state)
		assert(c.has("mesh_suffix"), "State " + state + " has mesh_suffix")
		assert(c.has("modulate"), "State " + state + " has modulate")

	# Verify structural kind coverage
	assert(ModuleIntegrityConsequences.is_structural_kind("floor_1x1"), "floor_1x1 is structural")
	assert(ModuleIntegrityConsequences.is_structural_kind("corridor_floor_1x1"), "corridor is structural")
	assert(ModuleIntegrityConsequences.is_structural_kind("pillar_support_1x1"), "pillar is structural")
	assert(ModuleIntegrityConsequences.is_structural_kind("ramp_up_1x2"), "ramp is structural")
	assert(ModuleIntegrityConsequences.is_structural_kind("wall_straight_1x1"), "wall is structural")

	p_result.add_pass("resolver and structural kind coverage OK")
```

- [ ] **Step 4: Run smoke test**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
godot --headless --script scripts/validation/integrity_visual_resolver_smoke.gd --quit 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/integrity_visual_resolver.gd scripts/systems/module_integrity_consequences.gd scripts/validation/integrity_visual_resolver_smoke.gd
git commit -m "feat: add integrity visual resolver and expand structural kind coverage"
```

**Stop condition:** Resolver script loads, consequence states cover all P0 families, smoke test passes.

---

## Phase 3: Objective/Component/Room Asset Production

### Task 3.1: Author 4 hero objective props

**Files:**
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/props/` (4 `.blend` files)
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/processed/props/` (4 `.glb` files)
- Create: `assets/imported/props/objectives/` (4 `.glb` files in repo)
- Create: `scenes/wrappers/props/objectives/` (4 `.tscn` wrapper scenes)

**Props:** supply_cache, repair_junction, medbay_terminal, reactor_control_panel

**Steps:**

- [ ] **Step 1: Author supply cache in Blender**

```python
#!/usr/bin/env python3
"""Author supply cache objective prop."""
import bpy, os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Base: sturdy container
bpy.ops.mesh.primitive_cube_add(size=1)
base = bpy.context.active_object
base.name = "SupplyCache_Body"
base.scale = (0.8, 0.5, 0.6)
base.location = (0, 0, 0.25)
bpy.ops.object.transform_apply(scale=True, location=True)

# Add a slightly inset lid
bpy.ops.mesh.primitive_cube_add(size=1)
lid = bpy.context.active_object
lid.name = "SupplyCache_Lid"
lid.scale = (0.78, 0.48, 0.05)
lid.location = (0, 0, 0.52)
bpy.ops.object.transform_apply(scale=True, location=True)

# Latch detail
bpy.ops.mesh.primitive_cylinder_add(radius=0.03, depth=0.1)
latch = bpy.context.active_object
latch.name = "SupplyCache_Latch"
latch.location = (0.35, 0, 0.52)
bpy.ops.object.transform_apply(scale=True, location=True)

# Material: worn military green
mat = bpy.data.materials.new("supply_cache_green")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.15, 0.22, 0.12, 1.0)
bsdf.inputs["Roughness"].default_value = 0.75
bsdf.inputs["Metallic"].default_value = 0.1
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        obj.data.materials.append(mat)

OUT = "/Volumes/Untitled/SynapticSeaAssets/meshes/source/props/supply_cache.blend"
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT)

GLB = "/Volumes/Untitled/SynapticSeaAssets/meshes/processed/props/supply_cache.glb"
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_apply=True)
print(f"Exported: {GLB}")
```

- [ ] **Step 2: Author repair junction, medbay terminal, reactor control panel** (similar scripts with distinct shapes — breaker panel form, console with screen, reactor control desk)

- [ ] **Step 3: Copy to repo and create wrapper scenes**

```bash
REPO="/Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea"
for prop in supply_cache repair_junction medbay_terminal reactor_control_panel; do
  cp "/Volumes/Untitled/SynapticSeaAssets/meshes/processed/props/$prop.glb" \
     "$REPO/assets/imported/props/objectives/$prop.glb"
done
```

- [ ] **Step 4: Verify Godot import**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
godot --headless --import --quit 2>&1 | grep -iE "(error|fail)" | head -10
```

- [ ] **Step 5: Commit**

```bash
git add assets/imported/props/objectives/ scenes/wrappers/props/objectives/
git commit -m "assets: add 4 hero objective props (supply cache, repair junction, med terminal, reactor panel)"
```

**Stop condition:** 4 objective props import in Godot, have wrapper scenes, and are visually distinguishable at isometric camera distance.

---

### Task 3.2: Author 11 physical component forms

**Files:**
- Create: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/components/` (11 `.blend` files)
- Create: `assets/imported/props/components/` (11 `.glb` files)
- Create: `scenes/wrappers/props/components/` (11 `.tscn` files)

**Components (from catalog):** reactor_console, air_recycler_unit, nav_console, thruster_control, sensor_rack, console_generic, conduit_run, pump_assembly, locker_wall, machinery_block, hull_plating

**Steps:**

- [ ] **Step 1: Author each component in Blender using shared chassis approach**

Use parameterized base meshes: console_unit (wall-mounted), machinery_block (floor-standing), conduit_segment (wall-run). Derive 11 forms from 3 base shapes with different faceplates, gauges, and proportions.

- [ ] **Step 2: Export and import into repo**

- [ ] **Step 3: Verify Godot import and commit**

**Stop condition:** 11 component GLBs import without errors. System-linked forms (5) are visually distinct from generic forms (6).

---

### Task 3.3: Author loot/haul and readability props

**Files:**
- Create: 3 loot/haul `.blend` + `.glb` (generic_crate, generic_locker, salvage_cart)
- Create: 5 readability `.blend` + `.glb` (cargo_pallet, cable_tray, service_rack, maintenance_bench, medical_cabinet)
- Create: 3 lighting fixture `.blend` + `.glb` (practical_overhead, emergency_wall, focused_work_lamp)

**Steps:**

- [ ] **Step 1: Author and export all 11 props** (3 loot + 5 readability + 3 lighting)

- [ ] **Step 2: Import into repo with wrapper scenes**

- [ ] **Step 3: Verify and commit**

**Stop condition:** All 11 props import in Godot and are non-colliding (outside approach cells).

---

## Phase 4: Materials, VFX, and Audio

### Task 4.1: Author 6-8 master materials

**Files:**
- Create: `assets/materials/` (Godot `.tres` material files)

**Materials:** painted_alloy, bare_steel, dark_polymer, hazard_marking, emissive_panel, grime_soot, biomatter (optional)

**Steps:**

- [ ] **Step 1: Create Godot StandardMaterial3D resources for each material**

- [ ] **Step 2: Assign materials to structural and prop wrapper scenes**

- [ ] **Step 3: Verify materials render in Godot viewport**

**Stop condition:** Materials are assigned and render correctly at isometric distance.

---

### Task 4.2: Build 3 VFX families

**Files:**
- Create: `scenes/vfx/` (timed_fire.tscn, biomatter_blockage.tscn, beacon_reactor_glow.tscn)

**Steps:**

- [ ] **Step 1: Build timed fire with smoke/embers** (GPUParticles3D + OmniLight3D flicker)

- [ ] **Step 2: Build biomatter blockage/pulse** (animated shader + point light)

- [ ] **Step 3: Build parameterized beacon/reactor glow** (emissive mesh + pulsing light)

- [ ] **Step 4: Wire VFX into golden fixture positions and commit**

**Stop condition:** Fire, biomatter, and beacon/glow are visible in the golden fixture at correct positions.

---

### Task 4.3: Author 21 thin-slice audio clips

**Files:**
- Create: `/Volumes/Untitled/SynapticSeaAssets/audio/` (21 `.wav` or `.ogg` files)
- Create: `assets/audio/` (imported audio files)

**Steps:**

- [ ] **Step 1: Source or synthesize 21 audio clips**

Use free SFX libraries (Freesound.org CC0, Kenney.nl) or synthesize with basic audio tools. Map to the 6 families from the spec:
- movement: footstep_metal, suit_breath
- doors_docking: door_open, door_close, dock_land
- work: tool_use, cut, weld, patch, unbolt_pry
- pickup_haul: pickup, drop
- hazards_meta: fire_crackle, biomatter_pulse, hull_groan, reactor_hum
- ambient: docking, corridor, engineering, medical, reactor

- [ ] **Step 2: Import into Godot and wire to existing audio event IDs**

- [ ] **Step 3: Add graceful fallback for missing clips**

**Stop condition:** 21 audio clips route through existing event IDs with fallback.

---

## Phase 5: Godot Validation and Visual Proof

### Task 5.1: Run full Godot headless import and regression

**Files:**
- Modify: Various (fix any import errors found)

**Steps:**

- [ ] **Step 1: Full Godot import**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
godot --headless --import --quit 2>&1 | tee /tmp/godot_import_log.txt
grep -ciE "error" /tmp/godot_import_log.txt
```

- [ ] **Step 2: Run existing regression suite**

```bash
cd /Volumes/Untitled/SynapticSeaAssets/projects/the-synaptic-sea
# Find and run the project's regression command
find scripts/validation -name "*.gd" | head -20
```

- [ ] **Step 3: Fix any import errors and re-run**

**Stop condition:** Zero import errors. Existing regression suite passes.

---

### Task 5.2: Visual proof — golden fixture viewport capture

**Steps:**

- [ ] **Step 1: Open Godot editor and load the golden fixture scene**

- [ ] **Step 2: Navigate the locked-isometric camera through the 8-room derelict path**

- [ ] **Step 3: Capture viewport screenshots at key positions:**
  - Airlock entry
  - Corridor + ramp transition
  - Main spine with blue beacon
  - Cargo room with supply cache
  - Maintenance room with repair junction
  - Medbay with terminal
  - Reactor room with control panel and green core

- [ ] **Step 4: Inspect screenshots for readability and report limitations honestly**

**Stop condition:** Real viewport captures show coherent Salvage Industrial environment. All 4 objectives visible and distinguishable. Fire, biomatter, beacon, and reactor glow readable. Any visual limitations documented honestly.

---

## Dependency Graph

```
Task 1.1 (directories)
  └→ Task 1.2 (metadata extraction)
       └→ Task 1.3 (Blender recovery)
            └→ Task 1.4 (intact re-export)
                 ├→ Task 2.1 (damaged variants)
                 │    └→ Task 2.3 (import variants + wrapper update)
                 └→ Task 2.2 (breached variants)
                      └→ Task 2.3 (import variants + wrapper update)
                           └→ Task 2.4 (visual resolver)
                                └→ Task 5.1 (full import)
                                     └→ Task 5.2 (visual proof)

Task 3.1 (objective props) ──→ Task 5.1
Task 3.2 (component forms) ──→ Task 5.1
Task 3.3 (loot/readability) ──→ Task 5.1
Task 4.1 (materials) ──→ Task 5.1
Task 4.2 (VFX) ──→ Task 5.1
Task 4.3 (audio) ──→ Task 5.1
```

Tasks 3.x, 4.x can proceed in parallel after Task 1.4 completes. Phase 2 (integrity) and Phase 3/4 (props/materials/audio) are independent workstreams that converge at Phase 5.
