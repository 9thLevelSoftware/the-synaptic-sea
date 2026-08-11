"""Build and run ComfyUI API workflows for Synaptic Sea tile textures.

The module deliberately uses only Python's standard library so it can be run by
Blender/Godot pipeline scripts without an additional Python dependency.  The
workflow and prompt data live beside the project in ``data/comfyui``.
"""

from __future__ import annotations

import argparse
import copy
import json
import shutil
import time
from pathlib import Path
from typing import Any, Mapping, Sequence
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROMPTS_PATH = PROJECT_ROOT / "data" / "comfyui" / "tile_prompts.json"
WORKFLOW_PATH = PROJECT_ROOT / "data" / "comfyui" / "base_workflow.json"
DEPTH_RENDER_DIR = Path("/tmp/tile_renders")
COMFY_INPUT_DIR = Path.home() / "Documents" / "comfy" / "ComfyUI" / "input"
COMFY_LORA_DIR = Path.home() / "Documents" / "comfy" / "ComfyUI" / "models" / "loras"
POLL_INTERVAL_SECONDS = 1.0


def _load_json(path: Path) -> dict[str, Any]:
    """Load a JSON object and fail with a useful path in configuration errors."""

    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except OSError as exc:
        raise RuntimeError(f"Unable to read ComfyUI configuration {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON in ComfyUI configuration {path}: {exc}") from exc

    if not isinstance(value, dict):
        raise RuntimeError(f"ComfyUI configuration {path} must contain a JSON object")
    return value


PROMPTS: dict[str, Any] = _load_json(PROMPTS_PATH)
BASE_WORKFLOW: dict[str, Any] = _load_json(WORKFLOW_PATH)


def available_modules() -> list[str]:
    """Return module IDs in the prompt library, in file order."""

    per_module = PROMPTS.get("per_module", {})
    if not isinstance(per_module, Mapping):
        raise RuntimeError(f"Invalid prompt library: per_module must be an object in {PROMPTS_PATH}")
    return list(per_module.keys())


def available_loras() -> list[str]:
    """Return supported LoRA filenames currently visible to ComfyUI.

    ComfyUI receives the filename relative to its ``models/loras`` directory,
    not an absolute path.  Missing directories simply mean that no trained
    LoRA is available yet.
    """

    if not COMFY_LORA_DIR.is_dir():
        return []
    supported_suffixes = {".ckpt", ".pt", ".pth", ".safetensors"}
    return sorted(
        path.name
        for path in COMFY_LORA_DIR.iterdir()
        if path.is_file() and path.suffix.lower() in supported_suffixes
    )


def _replace_placeholders(value: Any, replacements: Mapping[str, str]) -> Any:
    """Replace template markers recursively without mutating the source data."""

    if isinstance(value, str):
        for marker, replacement in replacements.items():
            value = value.replace(marker, replacement)
        return value
    if isinstance(value, list):
        return [_replace_placeholders(item, replacements) for item in value]
    if isinstance(value, dict):
        return {
            key: _replace_placeholders(item, replacements)
            for key, item in value.items()
        }
    return value


def _require_module(module_id: str) -> str:
    per_module = PROMPTS.get("per_module", {})
    if not isinstance(per_module, Mapping) or module_id not in per_module:
        choices = ", ".join(available_modules())
        raise ValueError(f"Unknown tile module {module_id!r}. Available modules: {choices}")
    prompt = per_module[module_id]
    if not isinstance(prompt, str):
        raise RuntimeError(f"Prompt for module {module_id!r} must be a string")
    return prompt


def build_workflow(
    module_id: str,
    depth_map_filename: str,
    lora_name: str | None = None,
    seed: int = 42,
) -> dict[str, Any]:
    """Build a fresh ComfyUI API workflow for one tile module.

    ``depth_map_filename`` must be the filename visible in ComfyUI's input
    directory.  ``lora_name`` is likewise a ComfyUI LoRA filename; when it is
    omitted the LoRA node is removed and the checkpoint model is connected
    directly to KSampler.
    """

    module_prompt = _require_module(module_id)
    style_prefix = PROMPTS.get("style_prefix", "")
    negative_prompt = PROMPTS.get("negative", "")
    if not isinstance(style_prefix, str) or not isinstance(negative_prompt, str):
        raise RuntimeError(f"Invalid prompt library strings in {PROMPTS_PATH}")

    workflow = copy.deepcopy(BASE_WORKFLOW)
    replacements = {
        "__POSITIVE_PROMPT__": f"{style_prefix}, {module_prompt}",
        "__NEGATIVE_PROMPT__": negative_prompt,
        "__DEPTH_MAP_FILENAME__": str(depth_map_filename),
        "__OUTPUT_PREFIX__": f"synaptic_tile_{module_id}",
    }
    if lora_name is not None:
        replacements["__LORA_NAME__"] = str(lora_name)
    workflow = _replace_placeholders(workflow, replacements)

    # Keep the node IDs from the checked-in template, but configure every
    # generation setting from tile_prompts.json rather than duplicating values.
    latent_inputs = workflow.get("5", {}).get("inputs", {})
    resolution = int(PROMPTS.get("resolution", latent_inputs.get("width", 1024)))
    latent_inputs["width"] = resolution
    latent_inputs["height"] = resolution
    latent_inputs["batch_size"] = 1

    controlnet_inputs = workflow.get("12", {}).get("inputs", {})
    controlnet_inputs["strength"] = float(
        PROMPTS.get("controlnet_strength", controlnet_inputs.get("strength", 0.8))
    )

    sampler_inputs = workflow.get("3", {}).get("inputs", {})
    sampler_inputs["seed"] = int(seed)
    sampler_inputs["steps"] = int(PROMPTS.get("steps", sampler_inputs.get("steps", 20)))
    sampler_inputs["cfg"] = float(PROMPTS.get("cfg_scale", sampler_inputs.get("cfg", 7.0)))
    sampler_inputs["sampler_name"] = str(
        PROMPTS.get("sampler", sampler_inputs.get("sampler_name", "euler_ancestral"))
    )
    sampler_inputs["scheduler"] = str(
        PROMPTS.get("scheduler", sampler_inputs.get("scheduler", "normal"))
    )

    if lora_name is None:
        workflow.pop("20", None)
        sampler_inputs["model"] = ["4", 0]
    else:
        lora_node = workflow.get("20")
        if not isinstance(lora_node, dict):
            raise RuntimeError("Workflow template is missing the LoraLoader node (20)")
        lora_inputs = lora_node.setdefault("inputs", {})
        lora_inputs["lora_name"] = str(lora_name)
        lora_weight = float(PROMPTS.get("lora_weight", 0.7))
        lora_inputs["strength_model"] = lora_weight
        lora_inputs["strength_clip"] = lora_weight
        sampler_inputs["model"] = ["20", 0]

    return workflow


def _api_url(api_url: str, path: str) -> str:
    return f"{api_url.rstrip('/')}/{path.lstrip('/')}"


def _read_response(response: Any) -> bytes:
    body = response.read()
    return body if isinstance(body, bytes) else str(body).encode("utf-8")


def _request_json(
    method: str,
    url: str,
    payload: Mapping[str, Any] | None = None,
    timeout: float = 30.0,
) -> Any:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(request, timeout=timeout) as response:
            body = _read_response(response)
    except HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"ComfyUI HTTP {exc.code} for {url}: {details}") from exc
    except URLError as exc:
        raise RuntimeError(f"Unable to reach ComfyUI at {url}: {exc.reason}") from exc
    except OSError as exc:
        raise RuntimeError(f"Unable to reach ComfyUI at {url}: {exc}") from exc

    try:
        return json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"ComfyUI returned invalid JSON from {url}") from exc


def submit_workflow(workflow: dict[str, Any], api_url: str) -> str:
    """Submit a workflow to ComfyUI and return its prompt ID."""

    response = _request_json("POST", _api_url(api_url, "/prompt"), {"prompt": workflow})
    if not isinstance(response, Mapping):
        raise RuntimeError("ComfyUI /prompt response was not a JSON object")
    prompt_id = response.get("prompt_id")
    if not isinstance(prompt_id, str) or not prompt_id:
        error = response.get("error") or response.get("node_errors")
        detail = f": {error}" if error else ""
        raise RuntimeError(f"ComfyUI did not return a prompt_id{detail}")
    return prompt_id


def _history_entry(payload: Any, prompt_id: str) -> Mapping[str, Any] | None:
    if not isinstance(payload, Mapping):
        raise RuntimeError("ComfyUI history response was not a JSON object")
    direct_entry = payload.get(prompt_id)
    if isinstance(direct_entry, Mapping):
        return direct_entry
    if "outputs" in payload or "status" in payload:
        return payload
    if len(payload) == 1:
        only_entry = next(iter(payload.values()))
        if isinstance(only_entry, Mapping):
            return only_entry
    return None


def _completion_error(entry: Mapping[str, Any]) -> str | None:
    status = entry.get("status")
    if not isinstance(status, Mapping):
        return None
    status_name = str(status.get("status_str", "")).lower()
    if status_name in {"error", "failed", "failure", "cancelled", "canceled"}:
        messages = status.get("messages")
        return f"{status_name}: {messages}" if messages else status_name
    return None


def _is_complete(entry: Mapping[str, Any]) -> bool:
    status = entry.get("status")
    if isinstance(status, Mapping):
        if status.get("completed") is True:
            return True
        if str(status.get("status_str", "")).lower() in {"success", "completed"}:
            return status.get("completed") is not False
    # Some ComfyUI-compatible servers omit status but publish outputs when done.
    return bool(entry.get("outputs")) and not isinstance(status, Mapping)


def poll_completion(prompt_id: str, api_url: str, timeout: int = 300) -> dict[str, Any]:
    """Poll ComfyUI history until a prompt succeeds and return its history entry."""

    if timeout < 0:
        raise ValueError("timeout must be non-negative")
    history_url = _api_url(api_url, f"/history/{quote(prompt_id, safe='')}")
    deadline = time.monotonic() + timeout

    while True:
        payload = _request_json("GET", history_url)
        entry = _history_entry(payload, prompt_id)
        if entry is not None:
            error = _completion_error(entry)
            if error:
                raise RuntimeError(f"ComfyUI generation failed for {prompt_id}: {error}")
            if _is_complete(entry):
                return dict(entry)

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"Timed out waiting for ComfyUI prompt {prompt_id}")
        time.sleep(min(POLL_INTERVAL_SECONDS, remaining))


def _first_output_image(history: Mapping[str, Any]) -> Mapping[str, Any]:
    outputs = history.get("outputs")
    if not isinstance(outputs, Mapping):
        raise RuntimeError("ComfyUI history contains no outputs")
    for node_output in outputs.values():
        if not isinstance(node_output, Mapping):
            continue
        images = node_output.get("images")
        if not isinstance(images, Sequence) or isinstance(images, (str, bytes)):
            continue
        for image in images:
            if isinstance(image, Mapping) and image.get("filename"):
                return image
    raise RuntimeError("ComfyUI completed without an output image")


def download_image(prompt_id: str, output_dir: str | Path, api_url: str) -> str:
    """Download the first image recorded for ``prompt_id`` and return its path."""

    history_url = _api_url(api_url, f"/history/{quote(prompt_id, safe='')}")
    history_payload = _request_json("GET", history_url)
    history = _history_entry(history_payload, prompt_id)
    if history is None:
        raise RuntimeError(f"ComfyUI history does not contain prompt {prompt_id}")
    image = _first_output_image(history)

    filename = str(image["filename"])
    query = urlencode(
        {
            "filename": filename,
            "subfolder": str(image.get("subfolder", "")),
            "type": str(image.get("type", "output")),
        }
    )
    view_url = f"{_api_url(api_url, '/view')}?{query}"
    request = Request(view_url, headers={"Accept": "image/*"}, method="GET")
    try:
        with urlopen(request, timeout=30.0) as response:
            image_bytes = _read_response(response)
    except HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"ComfyUI image download failed with HTTP {exc.code}: {details}") from exc
    except (URLError, OSError) as exc:
        raise RuntimeError(f"Unable to download ComfyUI image from {view_url}: {exc}") from exc

    destination_dir = Path(output_dir)
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / Path(filename).name
    destination.write_bytes(image_bytes)
    return str(destination)


def generate_tile(
    module_id: str,
    output_dir: str | Path,
    seed: int = 42,
    api_url: str = "http://127.0.0.1:8199",
) -> str:
    """Run the complete depth-upload, generation, and image-download pipeline."""

    source_depth = DEPTH_RENDER_DIR / f"{module_id}_depth.png"
    if not source_depth.is_file():
        raise FileNotFoundError(f"Depth map not found for {module_id!r}: {source_depth}")
    COMFY_INPUT_DIR.mkdir(parents=True, exist_ok=True)
    uploaded_depth = COMFY_INPUT_DIR / source_depth.name
    shutil.copy2(source_depth, uploaded_depth)

    # A future trained LoRA can be picked up automatically; with today's empty
    # models/loras directory this remains None and node 20 is removed.
    loras = available_loras()
    lora_name = loras[0] if loras else None
    workflow = build_workflow(module_id, uploaded_depth.name, lora_name=lora_name, seed=seed)
    prompt_id = submit_workflow(workflow, api_url)
    poll_completion(prompt_id, api_url)
    return download_image(prompt_id, output_dir, api_url)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module", help="tile module ID to generate")
    parser.add_argument("--seed", type=int, default=42, help="generation seed (default: 42)")
    parser.add_argument("--output", type=Path, help="directory for the downloaded tile image")
    parser.add_argument("--api-url", default="http://127.0.0.1:8199", help="ComfyUI API base URL")
    parser.add_argument("--list", action="store_true", help="list available tile modules")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.list:
        for module_id in available_modules():
            print(module_id)
        return 0

    if not args.module:
        parser.error("--module is required unless --list is used")
    if args.output is None:
        parser.error("--output is required unless --list is used")

    try:
        output_path = generate_tile(args.module, args.output, seed=args.seed, api_url=args.api_url)
    except (FileNotFoundError, OSError, RuntimeError, TimeoutError, ValueError) as exc:
        parser.error(str(exc))
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
