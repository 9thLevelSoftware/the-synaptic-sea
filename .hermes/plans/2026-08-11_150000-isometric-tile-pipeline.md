# Synaptic Sea Isometric Tile Pipeline Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build a fully automated Blender → ComfyUI pipeline that generates consistent salvage-industrial isometric tiles for all 15 structural kit modules, with LoRA-trained style, ControlNet depth conditioning, and edge inpainting for seamless modularity.

**Architecture:** Blender headless renders depth maps and normal maps from each GLB module at a fixed isometric camera angle. ComfyUI (SDXL + ControlNet depth + custom LoRA) generates textured tiles conditioned on those maps. A post-processing pass inpaints tile edges for seamless snapping. All runs on the Mac (M4 MPS).

**Tech Stack:** Blender 5.2 CLI, ComfyUI 0.29.0, PyTorch 2.13 (MPS), SDXL 1.0, ControlNet depth/canny (SDXL), Kohya-ss (LoRA training), Python 3.11

---

## Current State

- ComfyUI running on `http://127.0.0.1:8199` (MPS, 24GB unified)
- SDXL base checkpoint: symlinked from external drive
- ControlNet models: depth + canny (SDXL), on external drive
- 15 GLB modules at `assets/imported/structural/ship_structural_v0/`
- Blender render script exists at `/tmp/render_module_iso.py` (proof of concept)
- Focused-nine Blender recipes at worktree (7 structural + 2 props)
- No LoRA trained yet
- No depth/normal pass rendering yet
- No edge inpainting yet

---

## Task 1: Upgrade Blender Render Script to Multi-Pass

**Objective:** Render depth map, normal map, and beauty pass from each module at the exact isometric camera angle.

**Files:**
- Create: `tools/render_module_passes.py`
- Output: `/tmp/tile_renders/{module_id}_depth.png`, `_normal.png`, `_beauty.png`

**Step 1: Write the Blender script**

```python
# tools/render_module_passes.py
# Usage: blender --background --python tools/render_module_passes.py -- --module floor_1x1
#
# Renders three passes per module:
#   1. Depth map (near=white, far=black) for ControlNet depth conditioning
#   2. Normal map for additional geometric guidance
#   3. Beauty pass (dark metal lit scene) for Canny edge fallback
#
# Camera: fixed isometric angle (45° azimuth, arctan(1/sqrt(2)) elevation)
# Output: /tmp/tile_renders/{module_id}_{pass}.png at 1024x1024
```

Key implementation details:
- Parse `--module` arg from `sys.argv` after `--`
- GLB path: `assets/imported/structural/ship_structural_v0/{module}/{module}.glb`
- Isometric camera: orthographic, `ortho_scale` derived from module bounds × 2.5
- Camera position: `dist * cos(elev) * sin(azimuth)`, etc. (same as proof-of-concept)
- Dark metallic materials on all meshes (Principled BSDF: metallic=0.8, roughness=0.5)
- Two area lights (warm + cool) for readable surface detail
- Depth pass: enable `use_pass_z` on view layer, normalize + invert in compositor
- Normal pass: enable `use_pass_normal`, remap to 0-1 range for PNG
- Beauty pass: standard render with dark background
- Save all three as 1024×1024 PNG

**Step 2: Test with floor_1x1**

Run: `blender --background --python tools/render_module_passes.py -- --module floor_1x1`
Expected: Three PNGs in `/tmp/tile_renders/`

**Step 3: Test with wall_straight_1x1**

Run: `blender --background --python tools/render_module_passes.py -- --module wall_straight_1x1`
Expected: Three PNGs, wall geometry clearly visible in depth/normal maps

**Step 4: Commit**

```bash
git add tools/render_module_passes.py
git commit -m "feat(procgen): multi-pass isometric module renderer for tile pipeline"
```

---

## Task 2: Batch Render All 15 Modules

**Objective:** Run the multi-pass renderer on every kit module.

**Files:**
- Create: `tools/batch_render_modules.py` (shell wrapper)
- Output: `/tmp/tile_renders/{module_id}_{depth,normal,beauty}.png` × 15

**Step 1: Write the batch script**

```python
# tools/batch_render_modules.py
# Iterates all 15 module IDs from the kit catalog,
# calls blender --background --python tools/render_module_passes.py -- --module {id}
# for each, and reports success/failure.
```

Module IDs (from `data/kits/ship_structural_v0.json`):
```
floor_1x1, floor_2x1, corridor_floor_1x1, corridor_floor_1x2,
wall_straight_1x1, wall_end_cap, wall_inner_corner, wall_outer_corner,
wall_t_junction, doorway_frame_open_1x1, doorway_frame_blocked_1x1,
bulkhead_portal_2x1, ceiling_cap_1x1, pillar_support_1x1, ramp_up_1x2
```

**Step 2: Run the batch**

Run: `python3 tools/batch_render_modules.py`
Expected: 45 PNGs (3 passes × 15 modules) in `/tmp/tile_renders/`
Time: ~2 minutes (Blender renders fast in headless)

**Step 3: Verify renders**

Spot-check 5 random depth maps: no black screens, geometry visible, correct isometric angle.

**Step 4: Commit**

```bash
git add tools/batch_render_modules.py
git commit -m "feat(procgen): batch renderer for all 15 structural modules"
```

---

## Task 3: Curate LoRA Training Images

**Objective:** Collect 15-20 reference images that define the salvage-industrial aesthetic for style consistency.

**Files:**
- Create: `data/training/lora_synaptic_sea/` (training image directory)
- Create: `data/training/lora_synaptic_sea/prompts.txt` (captions per image)

**Step 1: Source reference images**

Generate 10 images via ComfyUI (text-to-image, SDXL, no ControlNet) with salvage-industrial prompts:
- Corridor interiors, control rooms, engineering bays, airlock chambers
- Vary the seed (100-109) for diversity
- Use the refined prompt from Task 5 below
- Save to `data/training/lora_synaptic_sea/raw/`

Source 5-10 additional images from:
- The existing Blender beauty renders (Task 2)
- Curated screenshots from sci-fi derelict concept art (fair use / reference only)
- The procgen tile renders from today's session

**Step 2: Write captions**

Each image needs a `.txt` file with the same filename containing the training caption:
```
synaptic_sea salvage-industrial derelict, weathered dark metal panels, visible rivets,
rust patina, dim amber and cool blue-green accent lighting, functional military aesthetic,
utilitarian, worn, ventilation grates, exposed pipes, emergency lighting strips
```

**Step 3: Resize to training resolution**

All images must be 1024×1024. Resize any non-square sources.

**Step 4: Commit**

```bash
git add data/training/lora_synaptic_sea/
git commit -m "feat(procgen): LoRA training dataset for salvage-industrial style"
```

---

## Task 4: Train LoRA on Mac (MPS)

**Objective:** Train a SDXL LoRA on the curated reference images using Kohya-ss.

**Files:**
- Create: `tools/train_lora.sh` (training script)
- Output: `data/training/lora_synaptic_sea/output/synaptic_sea_style.safetensors`

**Step 1: Install Kohya-ss**

```bash
cd ~/Documents/comfy
git clone https://github.com/kohya-ss/sd-scripts.git
cd sd-scripts
python3.11 -m venv .venv
.venv/bin/pip install torch torchvision torchaudio
.venv/bin/pip install -r requirements.txt
```

**Step 2: Write training config**

```toml
# tools/lora_train_config.toml
[model]
pretrained_model = "/Users/christopherwilloughby/Documents/comfy/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors"

[training]
resolution = 1024
batch_size = 1
max_train_epochs = 10
learning_rate = 1e-4
network_dim = 32
network_alpha = 16
save_every_n_epochs = 2

[dataset]
image_dir = "data/training/lora_synaptic_sea"
caption_extension = ".txt"
```

**Step 3: Run training**

Run: `bash tools/train_lora.sh`
Expected: ~30-60 minutes on M4 MPS. Checkpoints every 2 epochs.
Output: `.safetensors` LoRA file.

**Step 4: Copy LoRA to ComfyUI**

```bash
cp data/training/lora_synaptic_sea/output/synaptic_sea_style.safetensors \
   ~/Documents/comfy/ComfyUI/models/loras/
```

**Step 5: Commit**

```bash
git add tools/train_lora.sh tools/lora_train_config.toml
git commit -m "feat(procgen): LoRA training script for salvage-industrial style"
```

---

## Task 5: Refine ComfyUI Prompts

**Objective:** Develop optimized prompts that produce the best salvage-industrial tiles through SDXL + LoRA.

**Files:**
- Create: `data/comfyui/tile_prompts.json` (prompt library)
- Create: `data/comfyui/base_workflow.json` (ComfyUI API workflow template)

**Step 1: Define the prompt structure**

```json
{
  "style_prefix": "synaptic_sea_style, salvage-industrial derelict spaceship interior, weathered dark metal panels, visible rivets and seam lines, subtle rust and grime patina, dim amber and cool blue-green accent lighting from recessed strips, functional military aesthetic, utilitarian and slightly worn",
  "negative": "blurry, low quality, cartoon, anime, bright colors, clean, new, pristine, text, watermark, 3d render, plastic, oversaturated",
  "per_module": {
    "floor_1x1": "top-down isometric view of metal floor plate, panel seam lines, drainage grate, diamond tread pattern",
    "wall_straight_1x1": "front-facing isometric view of metal wall panel, bolt lines, recessed panels, indicator light",
    "doorway_frame_open_1x1": "isometric view of doorway frame, mechanical rails, seal groove, threshold plate",
    "ceiling_cap_1x1": "underside isometric view of ceiling panel, recessed light fixture, cable conduit"
  },
  "lora_weight": 0.7,
  "controlnet_strength": 0.8,
  "cfg_scale": 7.0,
  "steps": 20,
  "sampler": "euler_ancestral"
}
```

**Step 2: Test prompt variations**

Generate 3 variants each for floor_1x1 and wall_straight_1x1 with different prompt suffixes. Compare and select the best.

**Step 3: Commit**

```bash
git add data/comfyui/
git commit -m "feat(procgen): optimized prompt library for tile generation"
```

---

## Task 6: Build ComfyUI Workflow Template

**Objective:** Create a reusable ComfyUI API workflow that combines SDXL + LoRA + ControlNet depth.

**Files:**
- Create: `tools/comfyui_tile_workflow.py` (workflow builder + API caller)
- Create: `data/comfyui/workflow_depth_lora.json` (serializable workflow)

**Step 1: Build the workflow Python module**

```python
# tools/comfyui_tile_workflow.py
# Functions:
#   build_workflow(module_id, depth_map_path, prompt, negative, lora_name, lora_weight, seed) -> dict
#   submit_workflow(workflow, api_url="http://127.0.0.1:8199") -> prompt_id
#   poll_completion(prompt_id, api_url, timeout=300) -> dict
#   download_result(prompt_id, output_dir, api_url) -> str
#   generate_tile(module_id, output_dir, seed=42) -> str  # full pipeline
```

Workflow structure:
1. `CheckpointLoaderSimple` → SDXL base
2. `LoraLoader` → synaptic_sea_style at weight 0.7
3. `ControlNetLoader` → depth_sdxl_model
4. `LoadImage` → depth map from `/tmp/tile_renders/{module_id}_depth.png`
5. `CLIPTextEncode` × 2 → positive (style_prefix + module prompt) + negative
6. `ControlNetApplyAdvanced` → strength 0.8, 0%-90% range
7. `EmptyLatentImage` → 1024×1024
8. `KSampler` → 20 steps, euler_ancestral, cfg 7.0
9. `VAEDecode` → pixel output
10. `SaveImage` → to output directory

**Step 2: Test with floor_1x1**

Run: `python3 tools/comfyui_tile_workflow.py --module floor_1x1 --output /tmp/tile_output/`
Expected: PNG saved, ~3 min generation time

**Step 3: Commit**

```bash
git add tools/comfyui_tile_workflow.py data/comfyui/
git commit -m "feat(procgen): ComfyUI API workflow builder for tile generation"
```

---

## Task 7: Batch Generate All 15 Tiles

**Objective:** Generate textured tiles for every module using the full pipeline.

**Files:**
- Create: `tools/batch_generate_tiles.py`
- Output: `assets/tiles/synaptic_sea/{module_id}.png` × 15

**Step 1: Write the batch script**

```python
# tools/batch_generate_tiles.py
# For each of the 15 modules:
#   1. Check that depth map exists at /tmp/tile_renders/{id}_depth.png
#   2. Submit ComfyUI workflow via comfyui_tile_workflow.generate_tile()
#   3. Download result to assets/tiles/synaptic_sea/
#   4. Log progress
```

**Step 2: Run the batch**

Run: `python3 tools/batch_generate_tiles.py`
Expected: 15 tiles, ~45 minutes total (3 min each)
Progress: printed per-module

**Step 3: Visual review**

Open all 15 tiles side by side. Check for:
- Consistent style across all tiles (LoRA effect)
- Correct geometry following the depth map
- No visual artifacts or corruption
- Each tile reads as its intended module type

**Step 4: Commit**

```bash
git add tools/batch_generate_tiles.py assets/tiles/synaptic_sea/
git commit -m "feat(procgen): batch generated all 15 structural tiles"
```

---

## Task 8: Edge Inpainting for Seamless Tiling

**Objective:** Clean up tile edges so adjacent modules blend seamlessly when placed in the procgen grid.

**Files:**
- Create: `tools/inpaint_tile_edges.py`
- Create: `tools/comfyui_inpaint_workflow.py`
- Output: `assets/tiles/synaptic_sea/{module_id}_seamless.png` × 15

**Step 1: Define edge zones**

For each tile, identify the 8-pixel border zones where seams will be visible:
- Top/bottom edges: where floor tiles meet
- Left/right edges: where wall tiles connect
- These zones must be consistent across all tiles of the same family

**Step 2: Build inpainting workflow**

Use ComfyUI's inpainting capability:
1. Load the generated tile
2. Create a mask covering the 8px edge zones
3. Inpaint with the same LoRA + prompt
4. Blend the result back

**Step 3: Process all tiles**

Run: `python3 tools/inpaint_tile_edges.py --input-dir assets/tiles/synaptic_sea/ --output-dir assets/tiles/synaptic_sea/`
Expected: 15 seamless tiles

**Step 4: Tiling test**

Create a 3×3 grid of floor tiles to verify seams are invisible. Save as `/tmp/tiling_test_floor.png`.

**Step 5: Commit**

```bash
git add tools/inpaint_tile_edges.py tools/comfyui_inpaint_workflow.py
git commit -m "feat(procgen): edge inpainting for seamless tile modularity"
```

---

## Task 9: Import Textured Tiles into Godot

**Objective:** Replace the placeholder GLB meshes with the AI-textured tiles in the Godot wrapper scenes.

**Files:**
- Modify: `scenes/wrappers/structural/ship_structural_v0/*.tscn` (15 files)
- Create: `assets/tiles/synaptic_sea/materials/` (PBR material imports)

**Step 1: Convert PNG tiles to GLB with textures**

Use Blender to apply the generated tile textures back onto the module geometry:
```bash
blender --background --python tools/apply_tile_texture.py -- --module floor_1x1 --texture assets/tiles/synaptic_sea/floor_1x1_seamless.png
```

This produces textured GLBs that replace the existing placeholder meshes.

**Step 2: Update Godot wrapper scenes**

Each `.tscn` file references a GLB via `ExtResource`. Update the path to point to the new textured GLB.

**Step 3: Visual verification in Godot**

Run the procgen loader smoke with the new assets:
```bash
godot --headless --script scripts/validation/procgen_loader_playable_contract_smoke.gd
```
Expected: `PROCGEN_STRUCTURAL_LOADER_PASS`

**Step 4: Render comparison**

Run the visual preview script to show the textured procgen layout:
```bash
godot scenes/validation/procgen_visual_preview.tscn
```

**Step 5: Commit**

```bash
git add assets/tiles/ scenes/wrappers/structural/
git commit -m "feat(procgen): import AI-textured tiles into Godot wrapper scenes"
```

---

## Task 10: Automation Skill for Future Tile Generation

**Objective:** Create a Hermes skill that automates the full pipeline for new modules or style variants.

**Files:**
- Create: `~/.hermes/skills/game-development/synaptic-sea-tile-pipeline/SKILL.md`

**Step 1: Write the skill**

Document the complete pipeline:
- How to render new module passes (Blender)
- How to generate tiles (ComfyUI API)
- How to train new LoRAs (Kohya)
- How to inpaint edges
- How to import into Godot

**Step 2: Verify the skill loads**

```bash
hermes skill list | grep synaptic-sea-tile
```

---

## Risks and Tradeoffs

| Risk | Mitigation |
|------|-----------|
| LoRA training overfits on small dataset | Use low rank (32), few epochs (10), validate with held-out seeds |
| MPS training is slow (~60 min) | Could offload to RTX 5070 PC if needed |
| ControlNet depth doesn't match module geometry well | Fall back to Canny if depth maps are low-quality |
| Edge inpainting changes tile identity | Keep original + seamless versions; use originals for non-adjacent tiles |
| SDXL generates inconsistent style across modules | LoRA + fixed seed + style prefix should mitigate; iterate on prompt |
| Blender 5.2 compositor API changed | Use beauty pass + Canny as fallback if depth compositor fails |

## Open Questions

1. **LoRA vs. fine-tune:** A LoRA (rank 32) should suffice for style transfer. Full fine-tuning would be overkill and slower.
2. **Resolution:** 1024×1024 matches SDXL's native resolution. Could go 512×512 for faster iteration.
3. **Seed strategy:** Fixed seed per module for reproducibility, or random for variety? Recommend fixed for initial batch, then variant seeds for room_variant_selector.
4. **Training data source:** Self-generated SDXL images as training data risks circular quality issues. Supplement with curated external references if results are bland.
