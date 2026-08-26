#!/usr/bin/env python3
"""Generate/check the deterministic Gate 0 procgen build manifest (stdlib only)."""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT_MANIFEST = ROOT / "data/procgen/manifests/content_manifest.json"
BUILD_MANIFESTS = {
    "windows": (ROOT / "data/procgen/manifests/build/win64.json", "x86_64-pc-windows-msvc", "gdextension", ROOT / "addons/derelict/bin/win64/derelict_godot.dll", "addons/derelict/bin/win64/derelict_godot.dll"),
    "web": (ROOT / "data/procgen/manifests/build/web.json", "wasm32-unknown-unknown", "wasm", ROOT / "addons/derelict/bin/web/derelict_wasm_bg.wasm", "addons/derelict/bin/web/derelict_wasm_bg.wasm"),
}
# Backwards-compatible aliases used by focused tests and downstream tooling.
BUILD_MANIFEST = BUILD_MANIFESTS["windows"][0]
ARTIFACT = ROOT / "addons/derelict/bin/win64/derelict_godot.dll"
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

def build_document(content_digest: str, source_commit: str, target: str, kind: str, artifact_path: str, artifact: Path) -> dict:
    return {
        "manifest_schema": "procgen-build-manifest-2", "rust_source_commit": source_commit,
        "generator_version": 3, "content_manifest_path": "data/procgen/manifests/content_manifest.json",
        "content_manifest_hash": content_digest, "target": target,
        "artifact": {"kind": kind, "path": artifact_path, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()},
        "export_schemas": {"procgen_request":"procgen-request-1", "procgen_bundle":"procgen-bundle-3", "world_ir":"world-ir-2", "site_ir":"site-ir-2", "gameplay_ir":"gameplay-ir-1", "presentation_ir":"presentation-ir-1", "generation_trace":"generation-trace-2", "adaptive_proposal":"adaptive-proposal-1"},
    }

def canonical(value: dict) -> str:
    return json.dumps(value, indent=2, sort_keys=False) + "\n"

def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--check", action="store_true"); parser.add_argument("--source-commit"); parser.add_argument("--target", choices=sorted(BUILD_MANIFESTS), default="windows"); args = parser.parse_args()
    selected = BUILD_MANIFESTS[args.target]
    build_manifest, target, kind, artifact, artifact_path = selected
    if args.target == "windows" and BUILD_MANIFEST != BUILD_MANIFESTS["windows"][0]:
        build_manifest = BUILD_MANIFEST
    if args.target == "windows" and ARTIFACT != BUILD_MANIFESTS["windows"][3]:
        artifact = ARTIFACT
    source_commit = args.source_commit
    if source_commit is None and build_manifest.exists():
        try: source_commit = json.loads(build_manifest.read_text(encoding="utf-8"))["rust_source_commit"]
        except (OSError, KeyError, TypeError, json.JSONDecodeError): source_commit = ""
    if not isinstance(source_commit, str) or len(source_commit) != 40 or any(c not in "0123456789abcdef" for c in source_commit):
        print("source commit must be 40 lowercase hexadecimal characters", file=sys.stderr); return 1
    commit_check = subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", f"{source_commit}^{{commit}}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if commit_check.returncode != 0:
        print(f"source commit is not present in Git: {source_commit}", file=sys.stderr); return 1
    paths = files()
    if not artifact.exists():
        print(f"missing artifact: {rel(artifact)}", file=sys.stderr); return 1
    content = content_document(paths); build = build_document(content["content_manifest_hash"], source_commit, target, kind, artifact_path, artifact)
    expected = {CONTENT_MANIFEST: canonical(content), build_manifest: canonical(build)}
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
