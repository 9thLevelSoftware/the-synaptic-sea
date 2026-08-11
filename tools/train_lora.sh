#!/usr/bin/env bash
# Train SDXL LoRA for Synaptic Sea style (Mac MPS-optimized)
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SD_SCRIPTS="${HOME}/Documents/comfy/sd-scripts"
OUTPUT_DIR="${PROJECT_ROOT}/data/training/lora_synaptic_sea/output"
DATASET_DIR="${PROJECT_ROOT}/data/training/lora_synaptic_sea/kohya"
CHECKPOINT="/Users/christopherwilloughby/Documents/comfy/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA_DIR="${HOME}/Documents/comfy/ComfyUI/models/loras"

mkdir -p "$OUTPUT_DIR" "$LORA_DIR"
export PYTORCH_ENABLE_MPS_FALLBACK=1

cd "$SD_SCRIPTS"

# MPS-friendly: 512 res, fewer steps, AdamW, no mixed_precision quirks
# 19 imgs * 5 repeats * 4 epochs = 380 steps
.venv/bin/accelerate launch --num_cpu_threads_per_process 2 sdxl_train_network.py \
  --pretrained_model_name_or_path="$CHECKPOINT" \
  --train_data_dir="$DATASET_DIR" \
  --output_dir="$OUTPUT_DIR" \
  --output_name="synaptic_sea_style" \
  --resolution=512 \
  --train_batch_size=1 \
  --max_train_epochs=4 \
  --learning_rate=1e-4 \
  --network_module=networks.lora \
  --network_dim=16 \
  --network_alpha=8 \
  --save_every_n_epochs=1 \
  --mixed_precision=no \
  --save_model_as=safetensors \
  --caption_extension=.txt \
  --cache_latents \
  --optimizer_type=AdamW \
  --lr_scheduler=cosine \
  --seed=42 \
  --max_data_loader_n_workers=0 \
  --gradient_checkpointing \
  --sdpa

OUT_FILE="${OUTPUT_DIR}/synaptic_sea_style.safetensors"
# Kohya may write epoch files; pick latest
if [ ! -f "$OUT_FILE" ]; then
  LATEST=$(ls -t "$OUTPUT_DIR"/*.safetensors 2>/dev/null | head -1 || true)
  if [ -n "${LATEST:-}" ]; then
    cp "$LATEST" "$OUT_FILE"
  fi
fi
if [ -f "$OUT_FILE" ]; then
  cp "$OUT_FILE" "$LORA_DIR/"
  echo "LoRA copied to $LORA_DIR/synaptic_sea_style.safetensors"
  ls -lh "$LORA_DIR/synaptic_sea_style.safetensors"
else
  echo "WARNING: no safetensors found in $OUTPUT_DIR"
  ls -la "$OUTPUT_DIR"
  exit 1
fi
