# Synaptic Sea LoRA training dataset

This directory contains the seed image/caption dataset for training an SDXL LoRA
for the Synaptic Sea's salvage-industrial derelict visual style.

## Dataset layout

- `raw/` — 1024×1024 source images and matching caption files.
- `output/` — generated LoRA checkpoints (created by the training script; not
  populated by dataset preparation).

Each image in `raw/` has a same-stem `.txt` file. Kohya `sd-scripts` reads these
captions with `--caption_extension=.txt`.

## Seed sources

`tools/prepare_lora_dataset.py` gathers:

- Blender beauty renders from `/tmp/tile_renders/*_beauty.png`.
- Explicit generated tile previews from `/tmp`, when present.
- Image files in `assets/tiles/synaptic_sea/`.

The preparation script de-duplicates byte-identical source images, preserves
source basenames where possible, and adds a source-directory prefix if two
non-identical inputs would otherwise collide. Images are resized to 1024×1024
with Pillow when it is installed; without Pillow, they are copied unchanged and
the script emits a warning.

## Caption

The shared style caption is:

```text
synaptic_sea salvage-industrial derelict, weathered dark metal panels, visible rivets, rust patina, dim amber and cool blue-green accent lighting, functional military aesthetic, utilitarian, worn, ventilation grates, exposed pipes, emergency lighting strips
```

The caption intentionally combines the project trigger token (`synaptic_sea`)
with material, lighting, and construction cues that should be learned by the
LoRA. It is a starting dataset, not a final quality gate; inspect generated
samples and expand the image variety before production training.

## Prepare the dataset

From the repository root:

```bash
python3 tools/prepare_lora_dataset.py
```

The command is safe to rerun. It recreates/updates generated image and caption
pairs in `raw/` and prints the number of images ready for training.

## Train

The documented training settings are in `tools/lora_train_config.toml`; the
runnable wrapper is `tools/train_lora.sh`. Training is intentionally not run by
dataset preparation because it requires the local SDXL checkpoint and a free
GPU.
