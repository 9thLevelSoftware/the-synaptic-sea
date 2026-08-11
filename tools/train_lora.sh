#!/usr/bin/env bash
# Train SDXL LoRA for Synaptic Sea style using Kohya sd-scripts
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SD_SCRIPTS="${HOME}/Documents/comfy/sd-scripts"
OUTPUT_DIR="${PROJECT_ROOT}/data/training/lora_synaptic_sea/output"
DATASET_DIR="${PROJECT_ROOT}/data/training/lora_synaptic_sea/raw"
CHECKPOINT="/Users/christopherwilloughby/Documents/comfy/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors"

mkdir -p "$OUTPUT_DIR"

if [ ! -d "$SD_SCRIPTS" ]; then
  echo "Installing Kohya sd-scripts..."
  git clone https://github.com/kohya-ss/sd-scripts.git "$SD_SCRIPTS"
  cd "$SD_SCRIPTS"
  python3.11 -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install torch torchvision torchaudio
  .venv/bin/pip install -r requirements.txt
fi

cd "$SD_SCRIPTS"
# Kohya accelerate launch for SDXL LoRA
.venv/bin/accelerate launch --num_cpu_threads_per_process 1 sdxl_train_network.py \
  --pretrained_model_name_or_path="$CHECKPOINT" \
  --train_data_dir="$DATASET_DIR" \
  --output_dir="$OUTPUT_DIR" \
  --output_name="synaptic_sea_style" \
  --resolution=1024 \
  --train_batch_size=1 \
  --max_train_epochs=10 \
  --learning_rate=1e-4 \
  --network_module=networks.lora \
  --network_dim=32 \
  --network_alpha=16 \
  --save_every_n_epochs=2 \
  --mixed_precision=fp16 \
  --save_model_as=safetensors \
  --caption_extension=.txt \
  --cache_latents \
  --optimizer_type=AdamW8bit \
  --lr_scheduler=cosine \
  --seed=42

echo "Done. Copy LoRA to ComfyUI:"
echo "  cp ${OUTPUT_DIR}/synaptic_sea_style.safetensors ~/Documents/comfy/ComfyUI/models/loras/"
