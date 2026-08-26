#!/usr/bin/env python3
"""Generate/check the deterministic Gate 0 procgen build manifest (stdlib only)."""
from __future__ import annotations
import argparse, hashlib, json, os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT_MANIFEST = ROOT / "data/procgen/manifests/content_manifest.json"
BUILD_MANIFEST = ROOT / "data/procgen/manifests/build/win64.json"
ARTIFACT = ROOT / "addons/derelict/bin/win64/derelict_godot.dll"
COMMIT = "b78fedf2624c2d54f0f42b6c0ad3c488fbd9e6a9"
CONTENT_ROOTS = [
    ROOT / "native/worldgen/crates/derelict_core/assets",
    *(ROOT / "data/procgen" / name for name in ("archetypes", "biomes", "difficulty", "encounter_tables", "templates")),
]

def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()

def files() -> list[Path]:
    result = []
    for base in CONTENT_ROOTS:
        if base.exists():
            result.extend(p for p in base.rglob("*") if p.is_file())
    return sorted(result, key=rel)

def content_hash(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        digest.update(rel(path).encode("utf-8")); digest.update(b"\0")
        digest.update(path.read_bytes()); digest.update(b"\0")
    return digest.hexdigest()

def content_document(paths: list[Path]) -> dict:
    entries = [{"path": rel(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]
    return {"manifest_schema": "procgen-content-manifest-1", "files": entries, "content_manifest_hash": content_hash(paths)}

def build_document(content_digest: str) -> dict:
    return {
        "manifest_schema": "procgen-build-manifest-1", "rust_source_commit": COMMIT,
        "generator_version": 2, "content_manifest_path": "data/procgen/manifests/content_manifest.json",
        "content_manifest_hash": content_digest, "target": "x86_64-pc-windows-msvc",
        "artifact": {"kind": "gdextension", "path": "addons/derelict/bin/win64/derelict_godot.dll", "sha256": hashlib.sha256(ARTIFACT.read_bytes()).hexdigest()},
        "export_schemas": {"procgen_request":"procgen-request-1", "procgen_bundle":"procgen-bundle-1", "world_ir":"world-ir-1", "site_ir":"site-ir-1", "gameplay_ir":"gameplay-ir-1", "presentation_ir":"presentation-ir-1", "generation_trace":"generation-trace-1", "adaptive_proposal":"adaptive-proposal-1"},
    }

def canonical(value: dict) -> str:
    return json.dumps(value, indent=2, sort_keys=False) + "\n"

def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--check", action="store_true"); args = parser.parse_args()
    paths = files()
    if not ARTIFACT.exists():
        print(f"missing artifact: {rel(ARTIFACT)}", file=sys.stderr); return 1
    content = content_document(paths); build = build_document(content["content_manifest_hash"])
    expected = {CONTENT_MANIFEST: canonical(content), BUILD_MANIFEST: canonical(build)}
    failures = []
    for path, text in expected.items():
        actual = path.read_text(encoding="utf-8") if path.exists() else None
        if args.check:
            if actual != text: failures.append(f"{rel(path)} is stale or missing")
        else:
            path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text, encoding="utf-8")
    if failures:
        print("\n".join(failures), file=sys.stderr); return 1
    print(f"procgen manifest {'check' if args.check else 'generated'}: {len(paths)} content files, hash {content['content_manifest_hash']}")
    return 0

if __name__ == "__main__": sys.exit(main())
