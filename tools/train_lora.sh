#!/usr/bin/env bash
# Train SDXL LoRA for Synaptic Sea style using Kohya sd-scripts (Mac MPS)
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SD_SCRIPTS="${HOME}/Documents/comfy/sd-scripts"
OUTPUT_DIR="${PROJECT_ROOT}/data/training/lora_synaptic_sea/output"
DATASET_DIR="${PROJECT_ROOT}/data/training/lora_synaptic_sea/kohya"
CHECKPOINT="/Users/christopherwilloughby/Documents/comfy/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA_DIR="${HOME}/Documents/comfy/ComfyUI/models/loras"

mkdir -p "$OUTPUT_DIR" "$LORA_DIR"

if [ ! -d "$SD_SCRIPTS/.git" ]; then
  echo "Installing Kohya sd-scripts..."
  rm -rf "$SD_SCRIPTS"
  git clone --depth 1 https://github.com/kohya-ss/sd-scripts.git "$SD_SCRIPTS"
  cd "$SD_SCRIPTS"
  python3.11 -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install torch torchvision torchaudio
  .venv/bin/pip install -r requirements.txt
  .venv/bin/pip install accelerate transformers diffusers safetensors
fi

cd "$SD_SCRIPTS"

# MPS: no bitsandbytes/AdamW8bit — use AdamW + fp16
# Dataset dir must contain N_concept/ subfolders (e.g. 10_synaptic_sea/)
export PYTORCH_ENABLE_MPS_FALLBACK=1

.venv/bin/accelerate launch --num_cpu_threads_per_process 2 sdxl_train_network.py \
  --pretrained_model_name_or_path="$CHECKPOINT" \
  --train_data_dir="$DATASET_DIR" \
  --output_dir="$OUTPUT_DIR" \
  --output_name="synaptic_sea_style" \
  --resolution=1024 \
  --train_batch_size=1 \
  --max_train_epochs=8 \
  --learning_rate=1e-4 \
  --network_module=networks.lora \
  --network_dim=16 \
  --network_alpha=8 \
  --save_every_n_epochs=2 \
  --mixed_precision=no \
  --save_model_as=safetensors \
  --caption_extension=.txt \
  --cache_latents \
  --optimizer_type=AdamW \
  --lr_scheduler=cosine \
  --seed=42 \
  --max_data_loader_n_workers=0 \
  --gradient_checkpointing

OUT_FILE="${OUTPUT_DIR}/synaptic_sea_style.safetensors"
if [ -f "$OUT_FILE" ]; then
  cp "$OUT_FILE" "$LORA_DIR/"
  echo "LoRA copied to $LORA_DIR/synaptic_sea_style.safetensors"
  ls -lh "$LORA_DIR/synaptic_sea_style.safetensors"
else
  echo "WARNING: expected output not found; checking output dir:"
  ls -la "$OUTPUT_DIR"
  exit 1
fi
