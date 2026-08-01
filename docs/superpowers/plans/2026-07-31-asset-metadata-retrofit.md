# Asset Metadata Retrofit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic asset-metadata pipeline, retrofit all 26 imported prop GLBs with portable sidecars, repair validation for existing structural variants, and bind imported component/objective GLBs into the playable ship without changing gameplay ownership.

**Architecture:** Each imported prop GLB owns one canonical adjacent `.sidecar.json`; the repository generates one committed runtime lookup index from those sidecars. The runtime catalog resolves that derived index, and the visual binder instances GLBs as visual-only children below existing component markers and objective-affordance roots. Structural wrappers remain the authority for sockets, collision, and integrity-state switching; their validator is repaired to recognize the variant nodes already used by the runtime.

**Tech Stack:** Godot 4.7.1 headless import/test workflow; typed GDScript; Python 3 standard library (`json`, `hashlib`, `struct`, `pathlib`, `unittest`); glTF 2.0 GLB JSON/BIN parsing; JSON Schema document validation.

## Global Constraints

- Do not re-export, rewrite, embed metadata into, or otherwise mutate any `.glb` file.
- Prop sidecars are the only hand-authored visual metadata authority. `data/props/visual_bindings.generated.json` is generated from sidecars and must never be edited directly.
- Sidecars reserve an `extensions` object for forward-compatible studio data. The generator/refresh path must preserve it semantically and must never delete or rewrite an extension key.
- Every GLB under `assets/imported/props/` has exactly one same-basename `.sidecar.json`: 11 components, 11 dressing props, and 4 objectives.
- Component gameplay behavior remains in `data/components/component_catalog.json`; objective gameplay placement remains in `data/procgen/**/gameplay_slice.json`; live placement remains in `ComponentPlacementState` and `GeneratedShipLoader`.
- Prop sidecars contain no mass, condition, power, system link, role weighting, room, cell, approach cell, objective sequence, objective type, objective steps, or loot-table fields.
- Directly instanced prop GLBs are visual-only. Existing component markers and objective interactables continue to own collision, interaction, lifecycle, and gameplay state.
- Structural sockets, collision, navigation policy, and integrity state remain owned by the current structural wrapper/input/manifest/contract pipeline. Damaged and breached structural GLBs remain visual variants with no duplicated socket empties.
- Every Godot validation command begins with `/opt/homebrew/bin/godot --headless --editor --path . --quit`; Godot-generated `.godot` and `*.import` state is restored/cleaned before committing.
- Godot output containing unexpected `ERROR:` or `WARNING:` blocks task completion. A recognized pre-existing warning must be documented in the feature spec with an owner and a removal condition before it is tolerated.
- Use stable key ordering, compact JSON with a trailing newline, six decimal places for measured bounds, and SHA-256 for GLB hashes. Never emit timestamps.
- Work only on the task branch/worktree. Keep commits focused; do not include generated Godot cache files.

---

## File Structure

```text
assets/imported/props/
  components/<asset_id>.glb
  components/<asset_id>.sidecar.json
  dressing/<asset_id>.glb
  dressing/<asset_id>.sidecar.json
  objectives/<asset_id>.glb
  objectives/<asset_id>.sidecar.json

data/placement/schemas/prop_visual_binding_v1.schema.json
data/props/visual_bindings.generated.json

tools/prop_visual_metadata.py
tools/generate_prop_sidecars.py
tools/validate_prop_visual_bindings.py
tools/validate_structural_variant_bindings.py

tests/test_prop_visual_metadata.py
tests/test_validate_prop_visual_bindings.py

scripts/systems/prop_visual_binding_catalog.gd
scripts/procgen/runtime_prop_visual_binder.gd
scripts/validation/prop_visual_binding_smoke.gd
scripts/validation/objective_visual_binding_smoke.gd
scripts/validation/structural_variant_wrapper_smoke.gd

scripts/placement/validate_wrapper_scenes.gd
scripts/procgen/generated_ship_loader.gd
scripts/procgen/playable_generated_ship.gd
scripts/interaction/interactable.gd

docs/game/features/asset_metadata_pipeline.md
docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md
docs/game/05_requirements.md
docs/game/06_validation_plan.md
AGENTS.md
```

The Python metadata module owns format parsing, hash/bounds measurement, canonical serialization, and pure validation. The generator owns only missing-sidecar creation and derived-index regeneration. The runtime catalog owns lookup; the runtime binder owns visual scene instantiation; `PlayableGeneratedShip` retains component/objective lifecycle ownership.

### Task 1: Establish the governed feature contract and reproducible Godot baseline

**Files:**
- Create: `docs/game/features/asset_metadata_pipeline.md`
- Create: `docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md`
- Modify: `docs/game/adr/README.md`
- Modify: `docs/game/05_requirements.md`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Produces requirement IDs `REQ-AVB-001` through `REQ-AVB-009` for all implementation cards.
- Produces ADR-0052, which sets sidecar authority, derived-index policy, direct-GLB visual-only binding, structural ownership, and fallback rules.
- Defines `GODOT_BIN=/opt/homebrew/bin/godot` as the validation command for this repository revision.

- [ ] **Step 1: Write the failing baseline record and classify the known smoke warning**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/placement/validate_wrapper_scenes.gd -- scenes/wrappers/structural/ship_structural_v0
```

Expected before Task 2: exit `1` and eight errors containing `missing VisualInstance node for generated.visual_scene_path` for the variant-aware wrapper scenes.

Also run:

```bash
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_markers_smoke.gd
```

Current verified baseline: the smoke prints `COMPONENT MARKERS PASS wired=true count=true rebuild=true` and then ``WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).``. Record that exact warning in the feature spec as an external baseline, name `ship-core` as owner, require its count to remain exactly two while this feature is implemented, and link its removal to blocked Kanban card `t_b9b4e4f9` (title: Investigate ObjectDB leak in component marker smoke). Any other warning or a count other than two fails this feature's validation.

- [ ] **Step 2: Write the feature spec**

Write `docs/game/features/asset_metadata_pipeline.md` with these acceptance criteria:

```markdown
- Every one of the 26 imported prop GLBs has exactly one valid same-basename `.sidecar.json`.
- Sidecar data resolves an imported visual for every component ID in `component_catalog.json` and every supported objective placement ID with a supplied objective GLB.
- Missing or invalid bindings keep the existing primitive/readability visual path alive and set `visual_source = "fallback"`.
- Component marker placement, mount, dismount, save/load, and system linkage retain their current owners and behavior.
- Objective interaction volumes and objective progression retain their current owners and behavior.
- Structural variant wrappers validate and switch intact/damaged/breached visuals without socket or collision drift.
```

List non-goals explicitly: GLB re-export, procedural structural assembly, collision generation for props, new objective gameplay, and runtime dressing placement.

- [ ] **Step 3: Write ADR-0052**

Record these decisions:

```markdown
1. A prop GLB and its same-basename sidecar form one portable visual asset record.
2. The generated runtime index is derived and is overwritten only by the generator.
3. Runtime prop visuals are direct GLB children with `collision_policy = "none_visual_only"`.
4. Structural wrapper contracts remain connector/collision/integrity authorities.
5. Objective resolution uses gameplay `placement_id`, never objective `type`.
6. Missing binding behavior is an intentional visual fallback, never a substituted unrelated GLB.
7. GLB-derived refreshes replace the full GLB-derived source evidence (`sha256`, `byte_size`, `mesh_count`, `gltf_version`, and bounds) and preserve only sidecar `extensions` and hand-authored binding/placement/provenance fields.
```

- [ ] **Step 4: Add requirement rows and validation commands**

Add `REQ-AVB-001` through `REQ-AVB-009` covering sidecar completeness, sidecar schema/path/hash/bounds validity, no gameplay-field duplication, component binding, objective placement-ID binding, fallback behavior, structural variant validation, deterministic generated-index freshness, and extension survival during explicit derived-field refresh.

Add these commands to `docs/game/06_validation_plan.md`:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
ROOT="${ROOT:-.}"
"$GODOT_BIN" --headless --editor --path "$ROOT" --quit
python3 tools/validate_prop_visual_bindings.py --project-root "$ROOT" --check-index
python3 tools/validate_structural_variant_bindings.py --project-root "$ROOT"
"$GODOT_BIN" --headless --path "$ROOT" --script res://scripts/placement/validate_wrapper_scenes.gd -- scenes/wrappers/structural/ship_structural_v0
"$GODOT_BIN" --headless --path "$ROOT" --script res://scripts/validation/prop_visual_binding_smoke.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://scripts/validation/objective_visual_binding_smoke.gd
```

Update `AGENTS.md` from the unavailable Godot 4.6.2 path to the verified local Godot 4.7.1 path and retain the existing rule that unexpected diagnostics block completion.

- [ ] **Step 5: Verify documentation and commit**

Run:

```bash
git diff --check
python3 - <<'PY'
from pathlib import Path
paths = [
    Path('docs/game/features/asset_metadata_pipeline.md'),
    Path('docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md'),
]
for path in paths:
    text = path.read_text()
    assert ('TO' + 'DO') not in text and ('TB' + 'D') not in text
print('ASSET METADATA GOVERNANCE DOCS PASS')
PY
git add AGENTS.md \
  docs/game/features/asset_metadata_pipeline.md \
  docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md \
  docs/game/adr/README.md \
  docs/game/05_requirements.md \
  docs/game/06_validation_plan.md
git commit -m "docs: define asset metadata retrofit architecture"
```

Expected: `ASSET METADATA GOVERNANCE DOCS PASS` and one focused documentation commit.

### Task 2: Repair variant-aware structural wrapper validation before adding new gates

**Files:**
- Modify: `scripts/placement/validate_wrapper_scenes.gd`
- Create: `scripts/validation/structural_variant_wrapper_smoke.gd`
- Create: `tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.tscn`
- Create: `tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.manifest.json`
- Create: `tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.input.json`
- Create: `tests/fixtures/structural_variant_wrappers/partial_variant.tscn`
- Create: `tests/fixtures/structural_variant_wrappers/partial_variant.manifest.json`
- Create: `tests/fixtures/structural_variant_wrappers/partial_variant.input.json`
- Create: `tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.tscn`
- Create: `tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.manifest.json`
- Create: `tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.input.json`
- Create: `tests/fixtures/structural_variant_wrappers/missing_damaged_resource.tscn`
- Create: `tests/fixtures/structural_variant_wrappers/missing_damaged_resource.manifest.json`
- Create: `tests/fixtures/structural_variant_wrappers/missing_damaged_resource.input.json`

**Interfaces:**
- Produces validator support for exactly two legal visual forms:
  - legacy: `Visual/VisualInstance`
  - variant-aware: `Visual/VisualInstance_Intact`, `Visual/VisualInstance_Damaged`, `Visual/VisualInstance_Breached`
- The intact child must instance `manifest.generated.visual_scene_path`; damaged/breached children must be `PackedScene` resources under `Visual`.
- Every shell fence below starts from the repository root. A fence that invokes Godot defines `GODOT_BIN`, re-derives `STATE_RUNNER`, checks it is executable, and invokes Godot only through `$STATE_RUNNER -- "$GODOT_BIN" ...`; no fence relies on variables exported by an earlier fence.

- [ ] **Step 0: Establish the pre-mutation worktree guard and one isolated Godot state runner**

Run this once, before any Task 2 fixture/code mutation and before the first Task 2 Godot command. It is the only setup helper: it writes one executable Python standard-library runner outside the repository at a deterministic path derived from the SHA-256 of `$PWD`. The runner creates and removes one temporary per-invocation snapshot directory below that external directory; it never writes a helper or snapshot into the repository. The clean precondition covers all 14 owned paths, including staged, unstaged, untracked, and ignored changes, plus the broad structural source paths and their ignored artifacts. The precondition and every later runner fence reject a symlink/nonregular/stale `STATE_RUNNER` without unlinking it. Do not replace these checks with `git restore`, `git clean`, or a generated-state `git status` check.

```bash
set -euo pipefail

TASK2_PATHS=(
  scripts/placement/validate_wrapper_scenes.gd
  scripts/validation/structural_variant_wrapper_smoke.gd
  tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.tscn
  tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.manifest.json
  tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.input.json
  tests/fixtures/structural_variant_wrappers/partial_variant.tscn
  tests/fixtures/structural_variant_wrappers/partial_variant.manifest.json
  tests/fixtures/structural_variant_wrappers/partial_variant.input.json
  tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.tscn
  tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.manifest.json
  tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.input.json
  tests/fixtures/structural_variant_wrappers/missing_damaged_resource.tscn
  tests/fixtures/structural_variant_wrappers/missing_damaged_resource.manifest.json
  tests/fixtures/structural_variant_wrappers/missing_damaged_resource.input.json
)
STRUCTURAL_SOURCE_PATHS=(
  scenes/wrappers/structural
  assets/_processed
  assets/imported/structural
)
if (( ${#TASK2_PATHS[@]} != 14 )); then
  printf 'expected exactly 14 Task 2 paths, got %d\n' "${#TASK2_PATHS[@]}" >&2
  exit 1
fi
owned_status=$(git status --porcelain=v1 --untracked-files=all -- "${TASK2_PATHS[@]}")
owned_ignored=$(git ls-files --others --ignored --exclude-standard -- "${TASK2_PATHS[@]}")
if [[ -n "$owned_status" || -n "$owned_ignored" ]]; then
  printf 'Task 2 owned paths are not clean before work begins. Porcelain:\n%s\nIgnored owned paths:\n%s\n' \
    "$owned_status" "$owned_ignored" >&2
  exit 1
fi
source_status=$(git status --porcelain=v1 --untracked-files=all -- "${STRUCTURAL_SOURCE_PATHS[@]}")
source_ignored=$(git ls-files --others --ignored --exclude-standard -- "${STRUCTURAL_SOURCE_PATHS[@]}")
if [[ -n "$source_status" || -n "$source_ignored" ]]; then
  printf 'structural source paths are not clean before work begins. Porcelain:\n%s\nIgnored source paths:\n%s\n' \
    "$source_status" "$source_ignored" >&2
  exit 1
fi

WORKTREE_DIGEST=$(python3 - "$PWD" <<'PY'
import hashlib
import sys
print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())
PY
)
REPOSITORY_ROOT=$(python3 - "$PWD" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)
TEMP_BASE=$(python3 - "${TMPDIR:-/tmp}" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("TMPDIR must resolve to an external non-root directory")
print(candidate)
PY
)
STATE_HOME="$TEMP_BASE/synaptic-sea-task2-${WORKTREE_DIGEST}"
if [[ -L "$STATE_HOME" || ( -e "$STATE_HOME" && ! -d "$STATE_HOME" ) ]]; then
  printf 'STATE_HOME must not be a symlink or non-directory: %s\n' "$STATE_HOME" >&2
  exit 1
fi
STATE_HOME=$(python3 - "$STATE_HOME" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME must resolve to an external non-root directory")
print(candidate)
PY
)
mkdir -p "$STATE_HOME"
STATE_HOME=$(python3 - "$STATE_HOME" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME resolved inside the repository after mkdir")
print(candidate)
PY
)
STATE_RUNNER="$STATE_HOME/state_runner.py"
PRECONDITION_RECORD="$STATE_HOME/step0-precondition.txt"
# Never follow or replace a stale state path. The real-directory and absent-path
# checks are intentionally fail-closed; no unlink/rm is allowed here.
if [[ ! -d "$STATE_HOME" || -L "$STATE_HOME" ]]; then
  printf 'STATE_HOME must already be a real directory: %s\n' "$STATE_HOME" >&2
  exit 1
fi
if [[ -e "$STATE_RUNNER" || -L "$STATE_RUNNER" ]]; then
  printf 'refusing to overwrite pre-existing STATE_RUNNER: %s\n' "$STATE_RUNNER" >&2
  exit 1
fi
# Keep the explicit predicate above and make the write itself no-clobber so a
# stale path created between the check and redirection also fails closed.
set -o noclobber
cat >"$STATE_RUNNER" <<'PY'
#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

MARKER = "GENERATED STATE RESTORE VERIFIED"
SOURCE_ROOTS = (
    Path("scenes/wrappers/structural"),
    Path("assets/_processed"),
    Path("assets/imported/structural"),
)

def exists(path: Path) -> bool:
    return path.exists() or path.is_symlink()

def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()

def regular_record(root: Path, path: Path) -> dict[str, object]:
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"non-regular generated-state path: {path}")
    return {
        "mode": stat.S_IMODE(path.stat().st_mode),
        "path": path.relative_to(root).as_posix(),
        "sha256": digest(path),
    }

def external_import_paths(root: Path) -> list[Path]:
    found: list[Path] = []
    for current, directories, filenames in os.walk(root, topdown=True, followlinks=False):
        directories[:] = sorted(name for name in directories if name not in {".godot", ".git"})
        for name in sorted(filenames):
            path = Path(current) / name
            if not name.endswith(".import"):
                continue
            if path.is_symlink():
                raise RuntimeError(f"external import symlink is unsupported: {path}")
            if path.is_file():
                found.append(path)
    return sorted(found, key=lambda item: item.relative_to(root).as_posix())

def collect_generated(root: Path) -> dict[str, object]:
    godot = root / ".godot"
    godot_exists = exists(godot)
    if godot_exists and (godot.is_symlink() or not godot.is_dir()):
        raise RuntimeError(".godot exists but is not a real directory")
    records: list[dict[str, object]] = []
    if godot_exists:
        files = (item for item in godot.rglob("*") if item.is_file() and not item.is_symlink())
        records.extend(regular_record(root, item) for item in files)
    records.extend(regular_record(root, item) for item in external_import_paths(root))
    records.sort(key=lambda item: str(item["path"]))
    return {"files": records, "godot_exists": godot_exists}

def entry_record(root: Path, path: Path) -> dict[str, object]:
    relative = path.relative_to(root).as_posix()
    mode = stat.S_IMODE(path.lstat().st_mode)
    if path.is_symlink():
        return {"kind": "symlink", "path": relative, "target": os.readlink(path)}
    if path.is_dir():
        return {"kind": "directory", "mode": mode, "path": relative}
    if path.is_file():
        return {"kind": "file", "mode": mode, "path": relative, "sha256": digest(path)}
    return {"kind": "other", "mode": mode, "path": relative}

def collect_sources(root: Path) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for relative_root in SOURCE_ROOTS:
        source_root = root / relative_root
        if not exists(source_root):
            records.append({"kind": "missing", "path": relative_root.as_posix()})
            continue
        if source_root.is_symlink() or not source_root.is_dir():
            records.append(entry_record(root, source_root))
            continue
        records.append(entry_record(root, source_root))
        for current, directories, filenames in os.walk(source_root, topdown=True, followlinks=False):
            current_path = Path(current)
            kept_directories: list[str] = []
            for name in sorted(directories):
                child = current_path / name
                records.append(entry_record(root, child))
                if not child.is_symlink():
                    kept_directories.append(name)
            directories[:] = kept_directories
            for name in sorted(filenames):
                records.append(entry_record(root, current_path / name))
    return sorted(records, key=lambda item: str(item["path"]))

def remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)

def maybe_test_signal(root: Path, environment_name: str, phase: str) -> None:
    # These hooks are inert unless the synthetic verifier opts in explicitly.
    if os.environ.get("STATE_RUNNER_SYNTHETIC_HOOK") != "1":
        return
    raw_signum = os.environ.get(environment_name)
    if raw_signum is None:
        return
    if os.environ.get("STATE_RUNNER_SYNTHETIC_MUTATE_SOURCE") == phase:
        target = root / SOURCE_ROOTS[0] / f"synthetic-{phase}.txt"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("changed", encoding="utf-8")
    if phase == "launch":
        ready_name = os.environ.get("STATE_RUNNER_SYNTHETIC_READY_FILE")
        if ready_name:
            ready = Path(ready_name)
            for _ in range(500):
                if ready.exists():
                    break
                time.sleep(0.01)
            else:
                raise RuntimeError("synthetic child did not reach its launch hook")
    os.kill(os.getpid(), int(raw_signum))


def snapshot(root: Path, snapshot_root: Path) -> dict[str, object]:
    maybe_test_signal(root, "STATE_RUNNER_SYNTHETIC_SNAPSHOT_SIGNAL", "snapshot")
    generated = collect_generated(root)
    imports_backup = snapshot_root / "external-imports"
    for record in generated["files"]:
        relative = Path(*str(record["path"]).split("/"))
        if relative.parts and relative.parts[0] == ".godot":
            continue
        source = root / relative
        destination = imports_backup / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    if bool(generated["godot_exists"]):
        shutil.copytree(root / ".godot", snapshot_root / "godot", symlinks=True)
    maybe_test_signal(root, "STATE_RUNNER_SYNTHETIC_GENERATED_SIGNAL", "generated")
    return generated


def launch_child(
    command: list[str],
    root: Path,
    child_slot: list[subprocess.Popen | None],
) -> subprocess.Popen:
    launched = subprocess.Popen(command, cwd=root, start_new_session=True)
    # Publish the handle before the synthetic launch-boundary hook can raise.
    child_slot[0] = launched
    maybe_test_signal(root, "STATE_RUNNER_SYNTHETIC_LAUNCH_SIGNAL", "launch")
    return launched


def restore_and_verify(root: Path, snapshot_root: Path, generated: dict[str, object]) -> None:
    godot = root / ".godot"
    remove_path(godot)
    if bool(generated["godot_exists"]):
        shutil.copytree(snapshot_root / "godot", godot, symlinks=True)
    for path in external_import_paths(root):
        path.unlink()
    for record in generated["files"]:
        value = str(record["path"])
        if value == ".godot" or value.startswith(".godot/"):
            continue
        relative = Path(*value.split("/"))
        source = snapshot_root / "external-imports" / relative
        destination = root / relative
        if not source.is_file():
            raise RuntimeError(f"missing external import snapshot: {value}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    actual = collect_generated(root)
    if actual != generated:
        raise RuntimeError("restored generated state differs from the initial path/hash/mode manifest")


def interruption_status(signum: int) -> int:
    if signum == signal.SIGTERM:
        return 143
    return 130


def terminate_and_reap(process: subprocess.Popen) -> None:
    """Terminate the published process group, then reap the leader."""
    process_group = process.pid
    try:
        try:
            os.killpg(process_group, signal.SIGTERM)
        except ProcessLookupError:
            pass
        deadline = time.monotonic() + 2.0
        while process.poll() is None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                process.wait(timeout=min(0.1, remaining))
            except subprocess.TimeoutExpired:
                pass
        # The leader may have exited while a descendant remains. Always issue
        # the group fallback before restoration, not only while the leader runs.
        try:
            os.killpg(process_group, signal.SIGKILL)
        except ProcessLookupError:
            pass
    finally:
        # wait() is required even after poll() so the published leader is
        # reaped rather than merely observed.
        process.wait()


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] != "--":
        print("STATE RUNNER: usage: state_runner.py -- COMMAND [ARGS...]", file=sys.stderr)
        return 2
    root = Path.cwd().resolve()
    state_root = Path(__file__).resolve().parent
    if state_root == root or root in state_root.parents:
        print("STATE RUNNER: temporary state directory is inside the repository", file=sys.stderr)
        return 2

    watched_signals = (signal.SIGINT, signal.SIGTERM)
    previous_handlers = {signum: signal.getsignal(signum) for signum in watched_signals}
    pending_signal: list[int | None] = [None]
    for signum in watched_signals:
        # The handler must never raise: a signal can arrive during Popen before
        # its return value is assigned. Record it and let the lifecycle map it.
        def request_interrupt(received: int, _frame: object) -> None:
            if pending_signal[0] is None:
                pending_signal[0] = received
        signal.signal(signum, request_interrupt)

    primary_status = 0
    snapshot_state: dict[str, object] | None = None
    snapshot_root: Path | None = None
    initial_sources: list[dict[str, object]] | None = None
    child: subprocess.Popen | None = None
    child_slot: list[subprocess.Popen | None] = [None]
    child_reaped = False
    snapshot_status = 0
    restore_status = 0
    source_status = 0
    cleanup_status = 0
    restore_completed = False

    def remember_keyboard_interrupt() -> None:
        nonlocal primary_status
        if primary_status == 0:
            primary_status = 130
        print("STATE RUNNER: KeyboardInterrupt", file=sys.stderr)

    def check_pending_signal(phase: str) -> bool:
        nonlocal primary_status
        signum = pending_signal[0]
        if signum is None:
            return False
        pending_signal[0] = None
        if primary_status == 0:
            primary_status = interruption_status(signum)
        print(f"STATE RUNNER: pending signal {signum} during {phase}", file=sys.stderr)
        return True

    try:
        try:
            initial_sources = collect_sources(root)
            maybe_test_signal(root, "STATE_RUNNER_SYNTHETIC_SOURCE_SIGNAL", "source")
            check_pending_signal("after source baseline")
        except KeyboardInterrupt:
            remember_keyboard_interrupt()
        except Exception as exc:
            print(f"STATE RUNNER: source baseline failed: {exc}", file=sys.stderr)
            source_status = 1
            primary_status = 1

        if primary_status == 0:
            try:
                state_root.mkdir(parents=True, exist_ok=True)
                snapshot_root = Path(tempfile.mkdtemp(prefix="invocation-", dir=state_root))
                snapshot_state = snapshot(root, snapshot_root)
                check_pending_signal("after generated snapshot")
            except KeyboardInterrupt:
                remember_keyboard_interrupt()
            except Exception as exc:
                print(f"STATE RUNNER: snapshot failed: {exc}", file=sys.stderr)
                snapshot_status = 1
                primary_status = 1

        if primary_status == 0 and snapshot_state is not None:
            try:
                child = launch_child(argv[2:], root, child_slot)
                # Popen has returned and the handle is published before this
                # check, so an intervening signal cannot orphan the group.
                check_pending_signal("after Popen handle publication")
                while child.poll() is None and primary_status == 0:
                    check_pending_signal("child wait loop")
                    if primary_status != 0:
                        break
                    try:
                        child.wait(timeout=0.1)
                    except subprocess.TimeoutExpired:
                        continue
                if primary_status == 0:
                    child_status = child.wait()
                    # Check before publishing child_reaped: a signal that lands
                    # as the leader exits must still trigger group teardown.
                    check_pending_signal("after child wait")
                    if primary_status == 0:
                        primary_status = child_status
                        child_reaped = True
                else:
                    check_pending_signal("after child wait")
            except KeyboardInterrupt:
                remember_keyboard_interrupt()
            except OSError as exc:
                print(f"STATE RUNNER: command launch failed: {exc}", file=sys.stderr)
                primary_status = 127
            except Exception as exc:
                print(f"STATE RUNNER: command execution failed: {exc}", file=sys.stderr)
                primary_status = 1
    except KeyboardInterrupt:
        remember_keyboard_interrupt()
    except Exception as exc:
        print(f"STATE RUNNER: lifecycle failed: {exc}", file=sys.stderr)
        if primary_status == 0:
            primary_status = 1
    finally:
        # Keep the recording handler installed through teardown. Each phase is
        # checked below, so a signal during restore/verification suppresses the
        # marker and maps to 130/143 instead of jumping into a nested finally.
        if child is None:
            child = child_slot[0]
        if child is not None and (
            not child_reaped or primary_status != 0 or pending_signal[0] is not None
        ):
            try:
                terminate_and_reap(child)
                child_reaped = True
            except KeyboardInterrupt:
                remember_keyboard_interrupt()
                cleanup_status = 1
            except Exception as exc:
                print(f"STATE RUNNER: child teardown failed: {exc}", file=sys.stderr)
                cleanup_status = 1
        check_pending_signal("after child group teardown")

        if snapshot_state is not None and snapshot_root is not None:
            try:
                restore_and_verify(root, snapshot_root, snapshot_state)
                restore_completed = True
            except KeyboardInterrupt:
                remember_keyboard_interrupt()
                restore_status = 1
            except Exception as exc:
                print(f"STATE RUNNER: generated-state restore failed: {exc}", file=sys.stderr)
                restore_status = 1
        check_pending_signal("after generated-state restore")

        # Source verification is deliberately unconditional: source integrity
        # is independent of whether snapshot_state was completed.
        try:
            current_sources = collect_sources(root)
            if initial_sources is None:
                raise RuntimeError("structural source baseline was not completed")
            if current_sources != initial_sources:
                print("STATE RUNNER: structural source paths changed during invocation", file=sys.stderr)
                source_status = 1
        except KeyboardInterrupt:
            remember_keyboard_interrupt()
            source_status = 1
        except Exception as exc:
            print(f"STATE RUNNER: structural source inspection failed: {exc}", file=sys.stderr)
            source_status = 1
        check_pending_signal("after unconditional source verification")

        if snapshot_root is not None:
            try:
                shutil.rmtree(snapshot_root)
            except KeyboardInterrupt:
                remember_keyboard_interrupt()
                cleanup_status = 1
            except Exception as exc:
                print(f"STATE RUNNER: temporary snapshot cleanup failed: {exc}", file=sys.stderr)
                cleanup_status = 1
        check_pending_signal("after temporary snapshot cleanup")

        # The synthetic teardown hook runs after restore/verification and proves
        # that a late signal is still observed before marker eligibility.
        if os.environ.get("STATE_RUNNER_SYNTHETIC_TEARDOWN_SIGNAL"):
            maybe_test_signal(root, "STATE_RUNNER_SYNTHETIC_TEARDOWN_SIGNAL", "teardown")
        check_pending_signal("before marker")
        # Close the tiny post-check race: a signal delivered before this ignore
        # remains pending and is checked below; signals after the lifecycle is
        # complete cannot make a success marker retroactively invalid.
        for signum in watched_signals:
            signal.signal(signum, signal.SIG_IGN)
        check_pending_signal("marker gate")
        if (
            primary_status == 0
            and pending_signal[0] is None
            and snapshot_state is not None
            and restore_completed
            and snapshot_status == 0
            and restore_status == 0
            and source_status == 0
            and cleanup_status == 0
        ):
            print(MARKER, file=sys.stderr)
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)

    if primary_status != 0:
        return primary_status
    if snapshot_status or restore_status or source_status or cleanup_status:
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
PY
set +o noclobber
chmod 700 "$STATE_RUNNER"
if [[ ! -f "$STATE_RUNNER" || -L "$STATE_RUNNER" || ! -x "$STATE_RUNNER" ]]; then
  printf 'state runner was not created as a non-symlink executable regular file\n' >&2
  exit 1
fi
python3 - "$STATE_RUNNER" <<'PY'
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

RUNNER = Path(sys.argv[1])
MARKER = "GENERATED STATE RESTORE VERIFIED"
DESCENDANT_MUTATOR = """
from pathlib import Path
import signal
import time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
time.sleep(0.25)
(Path.cwd() / ".godot" / "descendant-mutated-after-restore.txt").write_text("mutated")
while True:
    time.sleep(30)
"""
MUTATE = f"""
from pathlib import Path
import os
import signal
import subprocess
import sys
import time
root = Path.cwd()
(root / ".godot").mkdir(exist_ok=True)
(root / ".godot" / "cache.txt").write_text("mutated")
(root / "asset.import").write_text("mutated")
pid_file = os.environ.get("SYN_CHILD_PID_FILE")
if pid_file:
    Path(pid_file).write_text(str(os.getpid()))
descendant = subprocess.Popen([sys.executable, "-c", {DESCENDANT_MUTATOR!r}])
descendant_pid_file = os.environ.get("SYN_DESCENDANT_PID_FILE")
if descendant_pid_file:
    Path(descendant_pid_file).write_text(str(descendant.pid))
if os.environ.get("SYN_CHILD_SOURCE_FAIL") == "1":
    (root / "scenes" / "wrappers" / "structural" / "child-changed.txt").write_text("changed")
(root / ".godot" / "started").write_text("ready")
ready_file = os.environ.get("SYN_CHILD_READY_FILE")
if ready_file:
    Path(ready_file).write_text("ready")
time.sleep(30)
"""
RESTORE_FAIL = """
from pathlib import Path
import os
import shutil
import time
state_home = Path(os.environ["SYN_STATE_HOME"])
for _ in range(500):
    snapshots = sorted(state_home.glob("invocation-*"))
    if snapshots:
        break
    time.sleep(0.01)
else:
    raise SystemExit("runner snapshot did not appear")
shutil.rmtree(snapshots[0] / "godot")
"""
SOURCE_FAIL = """
from pathlib import Path
(Path.cwd() / "scenes" / "wrappers" / "structural" / "changed.txt").write_text("changed")
"""


def make_fixture(present):
    temporary = tempfile.TemporaryDirectory()
    base = Path(temporary.name)
    repository = base / "repo"
    state_home = base / "state-home"
    repository.mkdir()
    state_home.mkdir()
    runner = state_home / "state_runner.py"
    shutil.copy2(RUNNER, runner)
    runner.chmod(0o700)
    source_root = repository / "scenes" / "wrappers" / "structural"
    source_root.mkdir(parents=True)
    (source_root / "original.txt").write_text("original")
    if present:
        (repository / ".godot").mkdir()
        (repository / ".godot" / "cache.txt").write_text("initial")
        (repository / "asset.import").write_text("initial")
    return temporary, repository, state_home, runner


def invoke(
    repository,
    state_home,
    runner,
    code,
    signum=None,
    wait_for_started=False,
    environment_overrides=None,
):
    environment = os.environ.copy()
    environment["SYN_STATE_HOME"] = str(state_home)
    environment["SYN_CHILD_PID_FILE"] = str(state_home / "child.pid")
    environment["SYN_DESCENDANT_PID_FILE"] = str(state_home / "descendant.pid")
    environment["SYN_CHILD_READY_FILE"] = str(state_home / "child.ready")
    environment["STATE_RUNNER_SYNTHETIC_READY_FILE"] = str(state_home / "child.ready")
    if environment_overrides:
        environment.update(environment_overrides)
    process = subprocess.Popen(
        [str(runner), "--", sys.executable, "-c", code],
        cwd=repository,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if wait_for_started:
        started = repository / ".godot" / "started"
        for _ in range(500):
            if started.exists():
                break
            time.sleep(0.01)
        else:
            process.kill()
            process.communicate(timeout=5)
            raise AssertionError("synthetic child did not reach its mutation")
    if signum is not None:
        process.send_signal(signum)
    stdout, stderr = process.communicate(timeout=10)
    return process.returncode, stdout, stderr


def assert_state(repository, present):
    if present:
        assert (repository / ".godot" / "cache.txt").read_text() == "initial"
        assert (repository / "asset.import").read_text() == "initial"
    else:
        assert not (repository / ".godot").exists()
        assert not (repository / "asset.import").exists()
    assert not (repository / ".godot" / "started").exists()


def assert_success(stderr):
    assert stderr.splitlines().count(MARKER) == 1, stderr
    assert "STATE RUNNER:" not in stderr, stderr


def assert_clean_primary_failure(stderr):
    assert MARKER not in stderr, stderr
    assert "STATE RUNNER:" not in stderr, stderr


def assert_runner_failure(stderr):
    assert MARKER not in stderr, stderr
    assert "STATE RUNNER:" in stderr, stderr


def assert_interrupted(stderr, expected_status, source_check=True):
    assert expected_status in (130, 143), expected_status
    assert MARKER not in stderr, stderr
    assert "STATE RUNNER:" in stderr, stderr
    if source_check:
        assert "structural source paths changed during invocation" in stderr, stderr


def assert_reaped(state_home):
    pid = int((state_home / "child.pid").read_text())
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return
    except PermissionError as exc:
        raise AssertionError(f"could not prove child {pid} was reaped") from exc
    raise AssertionError(f"child {pid} remains after runner exit")


def assert_group_gone(state_home, repository):
    descendant_pid = int((state_home / "descendant.pid").read_text())
    time.sleep(0.5)
    try:
        os.kill(descendant_pid, 0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError(f"descendant {descendant_pid} remains after group teardown")
    assert not (repository / ".godot" / "descendant-mutated-after-restore.txt").exists()


def accepts_step0_runner_path(state_home, runner):
    return state_home.is_dir() and not state_home.is_symlink() and not runner.exists() and not runner.is_symlink()


def accepts_fence_runner_path(runner):
    return runner.is_file() and not runner.is_symlink() and os.access(runner, os.X_OK)


def assert_path_guards():
    with tempfile.TemporaryDirectory() as temporary_name:
        root = Path(temporary_name)
        real_home = root / "real-home"
        real_home.mkdir()
        absent_runner = real_home / "state_runner.py"
        assert accepts_step0_runner_path(real_home, absent_runner)

        symlink_target = root / "symlink-target"
        symlink_target.write_text("must survive")
        stale_link = real_home / "state_runner-link.py"
        stale_link.symlink_to(symlink_target)
        assert not accepts_step0_runner_path(real_home, stale_link)
        assert stale_link.is_symlink() and symlink_target.read_text() == "must survive"

        stale_directory = real_home / "state_runner-dir.py"
        stale_directory.mkdir()
        assert not accepts_step0_runner_path(real_home, stale_directory)
        assert stale_directory.is_dir()

        real_runner = real_home / "state_runner-real.py"
        real_runner.write_text("#!/usr/bin/env python3\n")
        real_runner.chmod(0o700)
        assert accepts_fence_runner_path(real_runner)
        assert not accepts_fence_runner_path(stale_link)
        assert not accepts_fence_runner_path(stale_directory)

        home_link = root / "home-link"
        home_link.symlink_to(real_home, target_is_directory=True)
        assert not accepts_step0_runner_path(home_link, home_link / "new.py")


assert_path_guards()


def assert_ignored_owned_precondition():
    with tempfile.TemporaryDirectory() as temporary_name:
        repository = Path(temporary_name) / "repo"
        repository.mkdir()
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        owned = Path("tests/fixtures/structural_variant_wrappers/ignored-owner.tscn")
        (repository / ".gitignore").write_text(owned.as_posix() + "\n")
        ignored_path = repository / owned
        ignored_path.parent.mkdir(parents=True)
        ignored_path.write_text("must be rejected before adoption")
        porcelain = subprocess.run(
            ["git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all", "--", owned.as_posix()],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        ignored = subprocess.run(
            ["git", "-C", str(repository), "ls-files", "--others", "--ignored", "--exclude-standard", "--", owned.as_posix()],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        assert porcelain == ""
        assert ignored.splitlines() == [owned.as_posix()]
        assert porcelain or ignored, "combined owned precondition failed to detect ignored artifact"


assert_ignored_owned_precondition()

runner_source = RUNNER.read_text()
assert ("class Runner" + "Interrupted") not in runner_source
assert ("raise Runner" + "Interrupted") not in runner_source
assert "start_new_session=True" in runner_source
assert "os.killpg(process.pid" in runner_source or "os.killpg(process_group" in runner_source

# A relative TMPDIR and a symlink resolving into a repository are both rejected
# by the same canonical root/containment rule used by Step 0.
with tempfile.TemporaryDirectory() as temporary_name:
    temporary_root = Path(temporary_name)
    temporary_repository = temporary_root / "repo"
    temporary_repository.mkdir()
    symlinked_tmp = temporary_root / "tmp-link"
    symlinked_tmp.symlink_to(temporary_repository, target_is_directory=True)

    def rejected(raw, repository, base=None):
        raw_path = Path(raw)
        candidate = (
            (Path(base) / raw_path if base is not None and not raw_path.is_absolute() else raw_path)
            .expanduser()
            .resolve()
        )
        repository = repository.expanduser().resolve()
        return (
            candidate == Path(candidate.anchor)
            or candidate == repository
            or repository in candidate.parents
        )

    assert rejected(".", Path.cwd()), "relative TMPDIR inside repository was accepted"
    assert rejected(symlinked_tmp, temporary_repository), "symlinked TMPDIR inside repository was accepted"
    (temporary_root / "outside").mkdir()
    assert not rejected("../outside", temporary_repository, temporary_repository), "relative external TMPDIR was rejected"

for present in (False, True):
    temporary, repository, state_home, runner = make_fixture(present)
    try:
        status, _stdout, stderr = invoke(repository, state_home, runner, "pass")
        assert status == 0, (status, stderr)
        assert_success(stderr)
        assert_state(repository, present)
    finally:
        temporary.cleanup()

temporary, repository, state_home, runner = make_fixture(True)
try:
    status, _stdout, stderr = invoke(
        repository,
        state_home,
        runner,
        MUTATE.replace("time.sleep(30)", "") + "\nraise SystemExit(1)",
    )
    assert status == 1, (status, stderr)
    assert_clean_primary_failure(stderr)
    assert_state(repository, True)
finally:
    temporary.cleanup()

temporary, repository, state_home, runner = make_fixture(True)
try:
    status, _stdout, stderr = invoke(repository, state_home, runner, SOURCE_FAIL)
    assert status == 1, (status, stderr)
    assert_runner_failure(stderr)
finally:
    temporary.cleanup()

for primary_status in (0, 7):
    temporary, repository, state_home, runner = make_fixture(True)
    try:
        suffix = "" if primary_status == 0 else f"\nraise SystemExit({primary_status})"
        status, _stdout, stderr = invoke(repository, state_home, runner, RESTORE_FAIL + suffix)
        expected = 1 if primary_status == 0 else primary_status
        assert status == expected, (primary_status, status, stderr)
        assert_runner_failure(stderr)
    finally:
        temporary.cleanup()

# SIGINT after the source baseline: no generated snapshot exists, but the
# unconditional source check still runs and the interrupted path cannot emit a marker.
temporary, repository, state_home, runner = make_fixture(True)
try:
    status, _stdout, stderr = invoke(
        repository,
        state_home,
        runner,
        "pass",
        environment_overrides={
            "STATE_RUNNER_SYNTHETIC_HOOK": "1",
            "STATE_RUNNER_SYNTHETIC_SOURCE_SIGNAL": str(signal.SIGINT.value),
        },
    )
    assert status == 130, (status, stderr)
    assert_interrupted(stderr, status, source_check=False)
    assert_state(repository, True)
finally:
    temporary.cleanup()

# SIGTERM after the generated snapshot: restoration still runs, source changes
# are detected, and the pending signal wins over the would-be marker.
temporary, repository, state_home, runner = make_fixture(True)
try:
    status, _stdout, stderr = invoke(
        repository,
        state_home,
        runner,
        "pass",
        environment_overrides={
            "STATE_RUNNER_SYNTHETIC_HOOK": "1",
            "STATE_RUNNER_SYNTHETIC_GENERATED_SIGNAL": str(signal.SIGTERM.value),
            "STATE_RUNNER_SYNTHETIC_MUTATE_SOURCE": "generated",
        },
    )
    assert status == 143, (status, stderr)
    assert_interrupted(stderr, status)
    assert_state(repository, True)
finally:
    temporary.cleanup()

# SIGTERM immediately after Popen: the handle is published before the hook,
# so finally must terminate and reap the complete process group before restore.
temporary, repository, state_home, runner = make_fixture(True)
try:
    status, _stdout, stderr = invoke(
        repository,
        state_home,
        runner,
        MUTATE,
        environment_overrides={
            "STATE_RUNNER_SYNTHETIC_HOOK": "1",
            "STATE_RUNNER_SYNTHETIC_LAUNCH_SIGNAL": str(signal.SIGTERM.value),
            "STATE_RUNNER_SYNTHETIC_MUTATE_SOURCE": "launch",
        },
    )
    assert status == 143, (status, stderr)
    assert_interrupted(stderr, status)
    assert_reaped(state_home)
    assert_group_gone(state_home, repository)
    assert_state(repository, True)
finally:
    temporary.cleanup()

# Signals during the child wait loop cover both conventional interruption
# statuses. The child changes a protected source path before the parent signal,
# proving source verification is independent of snapshot restoration.
for signum, expected_status in ((signal.SIGINT, 130), (signal.SIGTERM, 143)):
    temporary, repository, state_home, runner = make_fixture(True)
    try:
        status, _stdout, stderr = invoke(
            repository,
            state_home,
            runner,
            MUTATE,
            signum=signum,
            wait_for_started=True,
            environment_overrides={"SYN_CHILD_SOURCE_FAIL": "1"},
        )
        assert status == expected_status, (signum, status, stderr)
        assert_interrupted(stderr, status)
        assert_reaped(state_home)
        assert_group_gone(state_home, repository)
        assert_state(repository, True)
    finally:
        temporary.cleanup()

# A signal injected during teardown/restore is recorded by the non-raising
# handler and checked before marker eligibility.
temporary, repository, state_home, runner = make_fixture(True)
try:
    status, _stdout, stderr = invoke(
        repository,
        state_home,
        runner,
        "pass",
        environment_overrides={
            "STATE_RUNNER_SYNTHETIC_HOOK": "1",
            "STATE_RUNNER_SYNTHETIC_TEARDOWN_SIGNAL": str(signal.SIGINT.value),
        },
    )
    assert status == 130, (status, stderr)
    assert_interrupted(stderr, status, source_check=False)
    assert_state(repository, True)
finally:
    temporary.cleanup()

print("STATE RUNNER SYNTHETIC PASS")
PY
printf '%s\n%s\n' "$PWD" "$(git rev-parse HEAD)" >"$PRECONDITION_RECORD"
printf 'TASK2 STEP0 READY state_runner=%s paths=14 source_guard=3\n' "$STATE_RUNNER"
```

The runner snapshots, for each invocation independently, every regular file below `.godot` (including tracked and ignored content) and every regular external `*.import` file outside `.godot` and `.git`, with deterministic relative POSIX paths, SHA-256 digests, modes, and full temporary copies. It fingerprints every entry below `scenes/wrappers/structural`, `assets/_processed`, and `assets/imported/structural` before the generated-state snapshot and verifies those source fingerprints unconditionally in `finally`, even when snapshot creation did not complete. It installs non-raising SIGINT/SIGTERM handlers before source setup, covers source baseline, generated snapshot, `Popen(..., start_new_session=True)` publication, polling/wait, and teardown, and maps pending SIGINT, pending SIGTERM, and `KeyboardInterrupt` to conventional primary statuses `130` and `143`. `check_pending_signal()` runs after the source baseline, after the generated snapshot, immediately after the published Popen handle, in the child wait loop, and after every teardown/verification phase; the non-raising handler prevents an orphan if a signal lands before Popen returns. A snapshot-complete invocation always attempts generated-state restoration and manifest comparison after command failure or interruption; a primary command/signal/snapshot/launch error wins over restore, source, or cleanup errors, while those cleanup errors control the status only when primary execution was otherwise successful. Teardown uses `os.killpg(process.pid, SIGTERM)`, waits boundedly, sends `SIGKILL` to the same group even if the leader already exited, and then reaps the leader, so descendants cannot mutate state after restoration. The success marker is gated only after the final pending-signal check and is exactly one plain `GENERATED STATE RESTORE VERIFIED` line on stderr when `primary_status == 0`, snapshot state exists, restoration completed and compared, broad source verification passed, and temporary-snapshot removal succeeded; no command failure, interruption, launch/snapshot error, restore/source error, or cleanup error can emit it. All runner diagnostics are prefixed `STATE RUNNER:` and none begins with `ERROR:` or `WARNING:`. The synthetic test above covers present and absent state, ordinary command failure without a marker, restore/source failures with primary-status preservation, canonical root/containment checks, source and generated-snapshot signals, launch-boundary and wait-loop SIGINT/SIGTERM, teardown-time signal, a child-launched delayed descendant that ignores SIGTERM, full process-group cleanup, no post-restore descendant mutation, and exactly one marker only for a clean invocation. It also statically rejects `RunnerInterrupted`/raising handlers and verifies `start_new_session=True` plus `os.killpg`.

- [ ] **Step 1: Execute the validator red gate and construct fixture-based negative coverage**

First run the real-directory red gate before any Task 2 code changes. The runner is already installed by Step 0, and this fence independently derives and checks it before the first Godot call. Each helper captures the complete combined output, requires exactly one plain `GENERATED STATE RESTORE VERIFIED` line for an exit-0 command, requires zero marker lines plus zero `STATE RUNNER:` diagnostics for an expected validator exit `1`, and then checks the complete validator signature: exact exit status, exact count of lines beginning `ERROR:`, every such error containing the required marker, and zero lines beginning `WARNING:`.

```bash
set -euo pipefail
GODOT_BIN=/opt/homebrew/bin/godot
RUNNER_MARKER='GENERATED STATE RESTORE VERIFIED'
derive_checked_state_runner() {
  REPOSITORY_ROOT=$(python3 - "$PWD" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)
  WORKTREE_DIGEST=$(python3 - "$REPOSITORY_ROOT" <<'PY'
import hashlib
import sys
print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())
PY
)
  TEMP_BASE=$(python3 - "${TMPDIR:-/tmp}" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("TMPDIR must resolve to an external non-root directory")
print(candidate)
PY
)
  local state_home="$TEMP_BASE/synaptic-sea-task2-${WORKTREE_DIGEST}"
  if [[ -L "$state_home" || ( -e "$state_home" && ! -d "$state_home" ) ]]; then
    printf 'STATE_HOME must not be a symlink or non-directory: %s\n' "$state_home" >&2
    exit 1
  fi
  STATE_HOME=$(python3 - "$state_home" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME must resolve to an external non-root directory")
print(candidate)
PY
)
  mkdir -p "$STATE_HOME"
  [[ -d "$STATE_HOME" && ! -L "$STATE_HOME" ]] || {
    printf 'STATE_HOME must be a real non-symlink directory: %s\n' "$STATE_HOME" >&2
    exit 1
  }
  STATE_HOME=$(python3 - "$STATE_HOME" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME resolved inside the repository after mkdir")
print(candidate)
PY
)
  runner_path="$STATE_HOME/state_runner.py"
  [[ -f "$runner_path" && ! -L "$runner_path" && -x "$runner_path" ]] || {
    printf 'STATE_RUNNER must be a non-symlink executable regular file: %s\n' "$runner_path" >&2
    exit 1
  }
  STATE_RUNNER=$(python3 - "$runner_path" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_RUNNER resolves inside the repository")
print(candidate)
PY
)
}
derive_checked_state_runner
[[ -f "$STATE_RUNNER" && ! -L "$STATE_RUNNER" && -x "$STATE_RUNNER" ]] || {
  printf 'missing executable STATE_RUNNER: %s\n' "$STATE_RUNNER" >&2
  exit 1
}

strip_runner_marker() {
  awk -v marker="$RUNNER_MARKER" '$0 != marker'
}

require_runner_success() {
  local label="$1"
  local raw="$2"
  local marker_count runner_diagnostics
  marker_count=$(awk -v marker="$RUNNER_MARKER" '$0 == marker { count += 1 } END { print count + 0 }' <<<"$raw")
  runner_diagnostics=$(awk '/^STATE RUNNER:/ { print }' <<<"$raw")
  if (( marker_count != 1 )); then
    printf '%s: expected exactly one %s, got %d\n' "$label" "$RUNNER_MARKER" "$marker_count" >&2
    return 1
  fi
  if [[ -n "$runner_diagnostics" ]]; then
    printf '%s: unexpected STATE RUNNER: diagnostic:\n%s\n' "$label" "$runner_diagnostics" >&2
    return 1
  fi
}

require_runner_clean_without_marker() {
  local label="$1"
  local raw="$2"
  local marker_count runner_diagnostics
  marker_count=$(awk -v marker="$RUNNER_MARKER" '$0 == marker { count += 1 } END { print count + 0 }' <<<"$raw")
  runner_diagnostics=$(awk '/^STATE RUNNER:/ { print }' <<<"$raw")
  if (( marker_count != 0 )); then
    printf '%s: expected no %s for a nonzero primary command, got %d\n' "$label" "$RUNNER_MARKER" "$marker_count" >&2
    return 1
  fi
  if [[ -n "$runner_diagnostics" ]]; then
    printf '%s: unexpected STATE RUNNER: diagnostic:\n%s\n' "$label" "$runner_diagnostics" >&2
    return 1
  fi
}

run_clean() {
  local label="$1"
  shift
  local raw filtered status
  if raw=$("$@" 2>&1); then
    status=0
  else
    status=$?
  fi
  if ! require_runner_success "$label" "$raw"; then
    return 1
  fi
  filtered=$(printf '%s\n' "$raw" | strip_runner_marker)
  printf '%s\n' "$filtered"
  if (( status != 0 )); then
    printf '%s: expected exit 0, got %d\n' "$label" "$status" >&2
    return 1
  fi
  if grep -Eq '^(ERROR|WARNING):' <<<"$filtered"; then
    printf '%s: unexpected ERROR:/WARNING: diagnostic\n' "$label" >&2
    return 1
  fi
}

expect_exact_error_signature() {
  local label="$1"
  local expected_status="$2"
  local expected_error_count="$3"
  local marker="$4"
  shift 4
  local raw filtered status error_count warning_count unexpected_errors
  if raw=$("$@" 2>&1); then
    status=0
  else
    status=$?
  fi
  if (( expected_status == 0 )); then
    if ! require_runner_success "$label" "$raw"; then
      return 1
    fi
  else
    if ! require_runner_clean_without_marker "$label" "$raw"; then
      return 1
    fi
  fi
  filtered=$(printf '%s\n' "$raw" | strip_runner_marker)
  printf '%s\n' "$filtered"
  if (( status != expected_status )); then
    printf '%s: expected exit %d, got %d\n' "$label" "$expected_status" "$status" >&2
    return 1
  fi
  error_count=$(awk 'BEGIN { count = 0 } /^ERROR:/ { count += 1 } END { print count }' <<<"$filtered")
  warning_count=$(awk 'BEGIN { count = 0 } /^WARNING:/ { count += 1 } END { print count }' <<<"$filtered")
  if (( error_count != expected_error_count )); then
    printf '%s: expected exactly %d ERROR: line(s), got %d\n' "$label" "$expected_error_count" "$error_count" >&2
    return 1
  fi
  if (( warning_count != 0 )); then
    printf '%s: expected zero WARNING: lines, got %d\n' "$label" "$warning_count" >&2
    return 1
  fi
  unexpected_errors=$(awk -v marker="$marker" 'index($0, "ERROR:") == 1 && index($0, marker) == 0 { print }' <<<"$filtered")
  if [[ -n "$unexpected_errors" ]]; then
    printf '%s: ERROR: line without required marker %s:\n%s\n' "$label" "$marker" "$unexpected_errors" >&2
    return 1
  fi
}

run_clean "editor import preflight" \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --editor --path . --quit
expect_exact_error_signature \
  "real structural directory baseline" 1 8 \
  "missing VisualInstance node for generated.visual_scene_path" \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
  --script res://scripts/placement/validate_wrapper_scenes.gd -- \
  scenes/wrappers/structural/ship_structural_v0
printf 'STRUCTURAL VALIDATOR RED CONFIRMED errors=8\n'
```

This direct-directory gate is intentionally distinct from the fixture harness below. It proves the current validator exits `1` with exactly eight matching errors and no warnings for the existing variant-aware wrappers, while the runner restores generated state even if this early red gate or the import preflight fails. Step 3 must make this same directory command exit `0` without changing structural scenes or GLBs.

Create all four same-basename fixture triples by copying the three existing `corridor_floor_1x1` source files, then mutate only the copied `.tscn` in each triple. Do not write either copied companion JSON file:

```bash
set -euo pipefail
FIXTURE_ROOT=tests/fixtures/structural_variant_wrappers
SOURCE_BASE=scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x1
mkdir -p "$FIXTURE_ROOT"
for fixture in mixed_legacy_variant partial_variant traversal_damaged_variant missing_damaged_resource; do
  for suffix in tscn manifest.json input.json; do
    cp "$SOURCE_BASE.$suffix" "$FIXTURE_ROOT/$fixture.$suffix"
  done
done

python3 - "$FIXTURE_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    assert text.count(old) == 1, (path, old, text.count(old))
    path.write_text(text.replace(old, new, 1))

# Mixed form: add the legacy child under Visual, reusing the copied intact resource.
mixed = root / "mixed_legacy_variant.tscn"
replace_once(
    mixed,
    '[node name="Visual" type="Node3D" parent="."]\n',
    '[node name="Visual" type="Node3D" parent="."]\n\n'
    '[node name="VisualInstance" parent="Visual" instance=ExtResource("1_visual")]\n',
)

# Partial form: remove only the breached variant node and its visibility property.
partial = root / "partial_variant.tscn"
replace_once(
    partial,
    '[node name="VisualInstance_Breached" parent="Visual" instance=ExtResource("3_visual_breached")]\nvisible = false\n',
    '',
)

# Traversal form: keep the text prefix but introduce a .. path component.
traversal = root / "traversal_damaged_variant.tscn"
replace_once(
    traversal,
    'path="res://assets/imported/structural/ship_structural_v0/corridor_floor_1x1/corridor_floor_1x1_damaged.glb"',
    'path="res://assets/imported/structural/../ship_structural_v0/corridor_floor_1x1/corridor_floor_1x1_damaged.glb"',
)

# Missing form: use a canonical structural PackedScene path that does not exist.
missing = root / "missing_damaged_resource.tscn"
replace_once(
    missing,
    'path="res://assets/imported/structural/ship_structural_v0/corridor_floor_1x1/corridor_floor_1x1_damaged.glb"',
    'path="res://assets/imported/structural/ship_structural_v0/missing_damaged_resource.tscn"',
)
PY
```

Run the exact baseline functions below against individual `.tscn` arguments. `expect_clean_accept` takes an exact expected success marker and proves the mixed fixture is still accepted before the fix; each `expect_exact_error_signature` call proves one and only one old missing-VisualInstance error with no warnings. This fence independently defines all variables and checks the same `STATE_RUNNER`; every validator call is isolated separately, so a failed fixture command still restores state and runs the structural source guard.

```bash
set -euo pipefail
GODOT_BIN=/opt/homebrew/bin/godot
FIXTURE_ROOT=tests/fixtures/structural_variant_wrappers
RUNNER_MARKER='GENERATED STATE RESTORE VERIFIED'
derive_checked_state_runner() {
  REPOSITORY_ROOT=$(python3 - "$PWD" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)
  WORKTREE_DIGEST=$(python3 - "$REPOSITORY_ROOT" <<'PY'
import hashlib
import sys
print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())
PY
)
  TEMP_BASE=$(python3 - "${TMPDIR:-/tmp}" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("TMPDIR must resolve to an external non-root directory")
print(candidate)
PY
)
  local state_home="$TEMP_BASE/synaptic-sea-task2-${WORKTREE_DIGEST}"
  if [[ -L "$state_home" || ( -e "$state_home" && ! -d "$state_home" ) ]]; then
    printf 'STATE_HOME must not be a symlink or non-directory: %s\n' "$state_home" >&2
    exit 1
  fi
  STATE_HOME=$(python3 - "$state_home" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME must resolve to an external non-root directory")
print(candidate)
PY
)
  mkdir -p "$STATE_HOME"
  [[ -d "$STATE_HOME" && ! -L "$STATE_HOME" ]] || {
    printf 'STATE_HOME must be a real non-symlink directory: %s\n' "$STATE_HOME" >&2
    exit 1
  }
  STATE_HOME=$(python3 - "$STATE_HOME" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME resolved inside the repository after mkdir")
print(candidate)
PY
)
  runner_path="$STATE_HOME/state_runner.py"
  [[ -f "$runner_path" && ! -L "$runner_path" && -x "$runner_path" ]] || {
    printf 'STATE_RUNNER must be a non-symlink executable regular file: %s\n' "$runner_path" >&2
    exit 1
  }
  STATE_RUNNER=$(python3 - "$runner_path" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_RUNNER resolves inside the repository")
print(candidate)
PY
)
}
derive_checked_state_runner
[[ -f "$STATE_RUNNER" && ! -L "$STATE_RUNNER" && -x "$STATE_RUNNER" ]] || {
  printf 'missing executable STATE_RUNNER: %s\n' "$STATE_RUNNER" >&2
  exit 1
}

strip_runner_marker() {
  awk -v marker="$RUNNER_MARKER" '$0 != marker'
}

require_runner_success() {
  local label="$1"
  local raw="$2"
  local marker_count runner_diagnostics
  marker_count=$(awk -v marker="$RUNNER_MARKER" '$0 == marker { count += 1 } END { print count + 0 }' <<<"$raw")
  runner_diagnostics=$(awk '/^STATE RUNNER:/ { print }' <<<"$raw")
  if (( marker_count != 1 )); then
    printf '%s: expected exactly one %s, got %d\n' "$label" "$RUNNER_MARKER" "$marker_count" >&2
    return 1
  fi
  if [[ -n "$runner_diagnostics" ]]; then
    printf '%s: unexpected STATE RUNNER: diagnostic:\n%s\n' "$label" "$runner_diagnostics" >&2
    return 1
  fi
}

require_runner_clean_without_marker() {
  local label="$1"
  local raw="$2"
  local marker_count runner_diagnostics
  marker_count=$(awk -v marker="$RUNNER_MARKER" '$0 == marker { count += 1 } END { print count + 0 }' <<<"$raw")
  runner_diagnostics=$(awk '/^STATE RUNNER:/ { print }' <<<"$raw")
  if (( marker_count != 0 )); then
    printf '%s: expected no %s for a nonzero primary command, got %d\n' "$label" "$RUNNER_MARKER" "$marker_count" >&2
    return 1
  fi
  if [[ -n "$runner_diagnostics" ]]; then
    printf '%s: unexpected STATE RUNNER: diagnostic:\n%s\n' "$label" "$runner_diagnostics" >&2
    return 1
  fi
}

expect_clean_accept() {
  local label="$1"
  local expected_marker="$2"
  shift 2
  local raw filtered status error_count warning_count marker_count
  if raw=$("$@" 2>&1); then
    status=0
  else
    status=$?
  fi
  if ! require_runner_success "$label" "$raw"; then
    return 1
  fi
  filtered=$(printf '%s\n' "$raw" | strip_runner_marker)
  printf '%s\n' "$filtered"
  if (( status != 0 )); then
    printf '%s: expected exit 0, got %d\n' "$label" "$status" >&2
    return 1
  fi
  error_count=$(awk 'BEGIN { count = 0 } /^ERROR:/ { count += 1 } END { print count }' <<<"$filtered")
  warning_count=$(awk 'BEGIN { count = 0 } /^WARNING:/ { count += 1 } END { print count }' <<<"$filtered")
  marker_count=$(awk -v expected="$expected_marker" '$0 == expected { count += 1 } END { print count + 0 }' <<<"$filtered")
  if (( error_count != 0 || warning_count != 0 || marker_count != 1 )); then
    printf '%s: expected exit 0, zero ERROR:/WARNING:, and exactly one %s; got errors=%d warnings=%d marker_count=%d\n' \
      "$label" "$expected_marker" "$error_count" "$warning_count" "$marker_count" >&2
    return 1
  fi
}

expect_exact_error_signature() {
  local label="$1"
  local expected_status="$2"
  local expected_error_count="$3"
  local marker="$4"
  shift 4
  local raw filtered status error_count warning_count unexpected_errors
  if raw=$("$@" 2>&1); then
    status=0
  else
    status=$?
  fi
  if (( expected_status == 0 )); then
    if ! require_runner_success "$label" "$raw"; then
      return 1
    fi
  else
    if ! require_runner_clean_without_marker "$label" "$raw"; then
      return 1
    fi
  fi
  filtered=$(printf '%s\n' "$raw" | strip_runner_marker)
  printf '%s\n' "$filtered"
  if (( status != expected_status )); then
    printf '%s: expected exit %d, got %d\n' "$label" "$expected_status" "$status" >&2
    return 1
  fi
  error_count=$(awk 'BEGIN { count = 0 } /^ERROR:/ { count += 1 } END { print count }' <<<"$filtered")
  warning_count=$(awk 'BEGIN { count = 0 } /^WARNING:/ { count += 1 } END { print count }' <<<"$filtered")
  if (( error_count != expected_error_count || warning_count != 0 )); then
    printf '%s: expected errors=%d warnings=0, got errors=%d warnings=%d\n' "$label" "$expected_error_count" "$error_count" "$warning_count" >&2
    return 1
  fi
  unexpected_errors=$(awk -v marker="$marker" 'index($0, "ERROR:") == 1 && index($0, marker) == 0 { print }' <<<"$filtered")
  if [[ -n "$unexpected_errors" ]]; then
    printf '%s: ERROR: line without required marker %s:\n%s\n' "$label" "$marker" "$unexpected_errors" >&2
    return 1
  fi
}

OLD_MISSING_VISUAL_MARKER='missing VisualInstance node for generated.visual_scene_path'
expect_clean_accept \
  "mixed_legacy_variant pre-fix baseline" \
  'Validated 1 wrapper scene bundle(s).' \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
  --script res://scripts/placement/validate_wrapper_scenes.gd -- \
  "$FIXTURE_ROOT/mixed_legacy_variant.tscn"
expect_exact_error_signature \
  "partial_variant pre-fix baseline" 1 1 "$OLD_MISSING_VISUAL_MARKER" \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
  --script res://scripts/placement/validate_wrapper_scenes.gd -- \
  "$FIXTURE_ROOT/partial_variant.tscn"
expect_exact_error_signature \
  "traversal_damaged_variant pre-fix baseline" 1 1 "$OLD_MISSING_VISUAL_MARKER" \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
  --script res://scripts/placement/validate_wrapper_scenes.gd -- \
  "$FIXTURE_ROOT/traversal_damaged_variant.tscn"
expect_exact_error_signature \
  "missing_damaged_resource pre-fix baseline" 1 1 "$OLD_MISSING_VISUAL_MARKER" \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
  --script res://scripts/placement/validate_wrapper_scenes.gd -- \
  "$FIXTURE_ROOT/missing_damaged_resource.tscn"
printf 'NEGATIVE FIXTURE RED CONFIRMED mixed=accepted legacy_missing=3\n'
```

The red harness returns zero only by proving `mixed_legacy_variant` is accepted with the exact `Validated 1 wrapper scene bundle(s).` line and one runner success marker, while the other three fixtures each produce exactly one old missing-VisualInstance error, no warnings, no runner diagnostics, and no runner success marker; any different result fails the block. Exit-0 captures require exactly one runner success marker before stripping it; expected validator exit-1 captures require zero runner markers and zero `STATE RUNNER:` diagnostics before their Godot diagnostics are counted. The marker is the only non-Godot runner line intentionally tolerated on a successful primary command. The post-fix helper used in Step 4 applies the same split: every fixture must exit `1`, emit exactly one `ERROR:` line, emit zero `WARNING:` lines, emit no runner marker or diagnostic, and contain its listed validator marker. This negative-fixture evidence remains separate from the eight-error real-directory red gate.

- [ ] **Step 2: Add a baseline-green eight-scene wrapper characterization smoke**

Create `scripts/validation/structural_variant_wrapper_smoke.gd` with this implementation-ready smoke skeleton. It loads and instantiates the eight existing variant wrappers, but it does **not** invoke `validate_wrapper_scenes.gd` and is not a validator test:

```gdscript
extends SceneTree

const IntegrityVisualResolverScript: GDScript = preload("res://scripts/systems/integrity_visual_resolver.gd")
const VARIANT_WRAPPER_PATHS: PackedStringArray = [
	"res://scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x2.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/doorway_frame_open_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/floor_2x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/pillar_support_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/ramp_up_1x2.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/wall_straight_1x1.tscn",
]

func _initialize() -> void:
	var failures: int = 0
	if not _expect(IntegrityVisualResolverScript != null, "resolver preload failed"):
		failures += 1
	var unique_paths: Dictionary = {}
	for scene_path in VARIANT_WRAPPER_PATHS:
		unique_paths[scene_path] = true
	if not _expect(
		VARIANT_WRAPPER_PATHS.size() == 8 and unique_paths.size() == 8,
		"expected exactly 8 unique variant wrapper paths",
	):
		failures += 1
	for scene_path in VARIANT_WRAPPER_PATHS:
		failures += _check_wrapper(scene_path)
	if failures != 0:
		push_error("STRUCTURAL VARIANT WRAPPER FAILURES: %d" % failures)
		quit(1)
		return
	print("STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true")
	quit(0)


func _check_wrapper(scene_path: String) -> int:
	var failures: int = 0
	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if not _expect(packed_scene != null, "%s did not load as PackedScene" % scene_path):
		return 1
	var instance: Node = packed_scene.instantiate()
	if not _expect(instance != null and instance is Node3D, "%s did not instantiate Node3D" % scene_path):
		if instance != null:
			instance.free()
		return 1
	var wrapper: Node3D = instance as Node3D
	get_root().add_child(wrapper)

	var visual_group: Node3D = wrapper.get_node_or_null("Visual") as Node3D
	if not _expect(visual_group != null, "%s missing Visual Node3D" % scene_path):
		_detach(wrapper)
		return 1
	var intact: Node3D = visual_group.get_node_or_null("VisualInstance_Intact") as Node3D
	var damaged: Node3D = visual_group.get_node_or_null("VisualInstance_Damaged") as Node3D
	var breached: Node3D = visual_group.get_node_or_null("VisualInstance_Breached") as Node3D
	if not _expect(intact != null, "%s missing intact Node3D" % scene_path):
		failures += 1
	if not _expect(damaged != null, "%s missing damaged Node3D" % scene_path):
		failures += 1
	if not _expect(breached != null, "%s missing breached Node3D" % scene_path):
		failures += 1
	if failures != 0:
		_detach(wrapper)
		return failures

	for state in ["intact", "damaged", "breached", "destroyed"]:
		var applied: bool = IntegrityVisualResolverScript.apply_visual_state(wrapper, state)
		if not _expect(applied, "%s resolver returned false for state=%s" % [scene_path, state]):
			failures += 1
		failures += _expect_state(scene_path, state, intact, damaged, breached)
	_detach(wrapper)
	return failures


func _expect_state(
	scene_path: String,
	state: String,
	intact: Node3D,
	damaged: Node3D,
	breached: Node3D,
) -> int:
	var expected_name: String = ""
	match state:
		"intact":
			expected_name = "VisualInstance_Intact"
		"damaged":
			expected_name = "VisualInstance_Damaged"
		"breached":
			expected_name = "VisualInstance_Breached"
		"destroyed":
			expected_name = ""
	var failures: int = 0
	for child in [intact, damaged, breached]:
		var should_be_visible: bool = state != "destroyed" and child.name == expected_name
		if not _expect(
			child.visible == should_be_visible,
			"%s state=%s visibility mismatch for %s" % [scene_path, state, child.name],
		):
			failures += 1
	return failures


func _detach(wrapper: Node3D) -> void:
	get_root().remove_child(wrapper)
	wrapper.free()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("STRUCTURAL VARIANT WRAPPER FAILURE: %s" % message)
	return false
```

Run this smoke once before Step 3 and once after Step 3. It must be baseline-green both times and print:

```text
STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true
```

The smoke is deliberately separate from validator coverage: it only proves that all eight existing `PackedScene` wrappers load, instantiate, expose `Visual` plus all three `Node3D` variant children, and return `true` from `IntegrityVisualResolver.apply_visual_state(...)` for `intact`, `damaged`, `breached`, and `destroyed`, with exact visibility (one matching child visible for the first three states and all three hidden for `destroyed`).



Run the baseline-green smoke once before Step 3. This fence is independent of the creation and red-gate fences and routes the smoke through the same runner:

```bash
set -euo pipefail
GODOT_BIN=/opt/homebrew/bin/godot
RUNNER_MARKER='GENERATED STATE RESTORE VERIFIED'
derive_checked_state_runner() {
  REPOSITORY_ROOT=$(python3 - "$PWD" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)
  WORKTREE_DIGEST=$(python3 - "$REPOSITORY_ROOT" <<'PY'
import hashlib
import sys
print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())
PY
)
  TEMP_BASE=$(python3 - "${TMPDIR:-/tmp}" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("TMPDIR must resolve to an external non-root directory")
print(candidate)
PY
)
  local state_home="$TEMP_BASE/synaptic-sea-task2-${WORKTREE_DIGEST}"
  if [[ -L "$state_home" || ( -e "$state_home" && ! -d "$state_home" ) ]]; then
    printf 'STATE_HOME must not be a symlink or non-directory: %s\n' "$state_home" >&2
    exit 1
  fi
  STATE_HOME=$(python3 - "$state_home" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME must resolve to an external non-root directory")
print(candidate)
PY
)
  mkdir -p "$STATE_HOME"
  [[ -d "$STATE_HOME" && ! -L "$STATE_HOME" ]] || {
    printf 'STATE_HOME must be a real non-symlink directory: %s\n' "$STATE_HOME" >&2
    exit 1
  }
  STATE_HOME=$(python3 - "$STATE_HOME" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME resolved inside the repository after mkdir")
print(candidate)
PY
)
  runner_path="$STATE_HOME/state_runner.py"
  [[ -f "$runner_path" && ! -L "$runner_path" && -x "$runner_path" ]] || {
    printf 'STATE_RUNNER must be a non-symlink executable regular file: %s\n' "$runner_path" >&2
    exit 1
  }
  STATE_RUNNER=$(python3 - "$runner_path" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_RUNNER resolves inside the repository")
print(candidate)
PY
)
}
derive_checked_state_runner
[[ -f "$STATE_RUNNER" && ! -L "$STATE_RUNNER" && -x "$STATE_RUNNER" ]] || {
  printf 'missing executable STATE_RUNNER: %s\n' "$STATE_RUNNER" >&2
  exit 1
}
strip_runner_marker() {
  awk -v marker="$RUNNER_MARKER" '$0 != marker'
}

require_runner_success() {
  local label="$1"
  local raw="$2"
  local marker_count runner_diagnostics
  marker_count=$(awk -v marker="$RUNNER_MARKER" '$0 == marker { count += 1 } END { print count + 0 }' <<<"$raw")
  runner_diagnostics=$(awk '/^STATE RUNNER:/ { print }' <<<"$raw")
  if (( marker_count != 1 )); then
    printf '%s: expected exactly one %s, got %d\n' "$label" "$RUNNER_MARKER" "$marker_count" >&2
    return 1
  fi
  if [[ -n "$runner_diagnostics" ]]; then
    printf '%s: unexpected STATE RUNNER: diagnostic:\n%s\n' "$label" "$runner_diagnostics" >&2
    return 1
  fi
}

require_runner_clean_without_marker() {
  local label="$1"
  local raw="$2"
  local marker_count runner_diagnostics
  marker_count=$(awk -v marker="$RUNNER_MARKER" '$0 == marker { count += 1 } END { print count + 0 }' <<<"$raw")
  runner_diagnostics=$(awk '/^STATE RUNNER:/ { print }' <<<"$raw")
  if (( marker_count != 0 )); then
    printf '%s: expected no %s for a nonzero primary command, got %d\n' "$label" "$RUNNER_MARKER" "$marker_count" >&2
    return 1
  fi
  if [[ -n "$runner_diagnostics" ]]; then
    printf '%s: unexpected STATE RUNNER: diagnostic:\n%s\n' "$label" "$runner_diagnostics" >&2
    return 1
  fi
}
expect_clean_accept() {
  local label="$1" expected_marker="$2"
  shift 2
  local raw filtered status error_count warning_count marker_count
  if raw=$("$@" 2>&1); then status=0; else status=$?; fi
  if ! require_runner_success "$label" "$raw"; then
    return 1
  fi
  filtered=$(printf '%s\n' "$raw" | strip_runner_marker)
  printf '%s\n' "$filtered"
  error_count=$(awk 'BEGIN { count = 0 } /^ERROR:/ { count += 1 } END { print count }' <<<"$filtered")
  warning_count=$(awk 'BEGIN { count = 0 } /^WARNING:/ { count += 1 } END { print count }' <<<"$filtered")
  marker_count=$(awk -v expected="$expected_marker" '$0 == expected { count += 1 } END { print count + 0 }' <<<"$filtered")
  if (( status != 0 || error_count != 0 || warning_count != 0 || marker_count != 1 )); then
    printf '%s: expected exit 0, zero ERROR:/WARNING:, and exactly one %s\n' "$label" "$expected_marker" >&2
    return 1
  fi
}
expect_clean_accept \
  "eight-scene structural variant wrapper smoke" \
  'STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true' \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
  --script res://scripts/validation/structural_variant_wrapper_smoke.gd
```

The smoke must be baseline-green and print exactly `STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true`. It is not validator coverage; it only proves that all eight existing `PackedScene` wrappers load, instantiate, expose `Visual` plus all three `Node3D` variant children, and return `true` from `IntegrityVisualResolver.apply_visual_state(...)` for `intact`, `damaged`, `breached`, and `destroyed`, with exact visibility (one matching child visible for the first three states and all three hidden for `destroyed`).

- [ ] **Step 3: Implement the smallest validator change with deterministic form and resource gates**

Replace the single hard-coded `VisualInstance` lookup with an explicit exactly-two-forms policy. Replace **only the body inside** the retained `if not generated_visual_scene_path.is_empty():` guard; the surrounding guard is shown below so the nesting is unambiguous. Every nonblank line inside that guard must have one additional tab of indentation exactly as shown; do not paste this block at function scope. Add `const STRUCTURAL_SCENE_PREFIX: String = "res://assets/imported/structural/"` with the other validator constants. The first validator invocation in Step 4 is the required Godot parser/compile check for this replacement; stop on any parse or type error. Use this logic:

```gdscript
if not generated_visual_scene_path.is_empty():
	var variant_names: Array[String] = [
		"VisualInstance_Intact",
		"VisualInstance_Damaged",
		"VisualInstance_Breached",
	]
	var visual_names: Array[String] = []
	var has_legacy: bool = nodes_by_name.has("VisualInstance")
	var present_variants: Array[String] = []
	for variant_name in variant_names:
		if nodes_by_name.has(variant_name):
			present_variants.append(variant_name)
	var has_any_variant: bool = not present_variants.is_empty()
	var has_all_variants: bool = present_variants.size() == variant_names.size()

	if has_legacy and has_any_variant:
		errors.append(
			"%s: mixed visual forms are forbidden: VisualInstance plus %s" %
			[scene_path, ", ".join(PackedStringArray(present_variants))]
		)
	elif has_legacy:
		visual_names = ["VisualInstance"]
	elif has_all_variants:
		visual_names = variant_names.duplicate()
	elif has_any_variant:
		var missing_variants: Array[String] = []
		for variant_name in variant_names:
			if not nodes_by_name.has(variant_name):
				missing_variants.append(variant_name)
		errors.append(
			"%s: incomplete variant visual form; missing variants: %s" %
			[scene_path, ", ".join(PackedStringArray(missing_variants))]
		)
	else:
		errors.append(
			"%s: missing VisualInstance or variant visual nodes for generated.visual_scene_path" %
			scene_path
		)

	for visual_name in visual_names:
		var visual_instance: Dictionary = nodes_by_name[visual_name]
		if str(visual_instance.get("parent", "")) != "Visual":
			errors.append("%s: %s must be parented to Visual" % [scene_path, visual_name])

		var visual_instance_ref: String = str(visual_instance.get("instance", ""))
		if visual_instance_ref.is_empty():
			errors.append("%s: %s must instance the generated visual scene" % [scene_path, visual_name])
			continue

		var instance_start: int = visual_instance_ref.find("\"")
		var instance_finish: int = visual_instance_ref.find("\"", instance_start + 1)
		if instance_start == -1 or instance_finish == -1:
			errors.append("%s: %s has malformed ext_resource reference" % [scene_path, visual_name])
			continue

		var resource_id: String = visual_instance_ref.substr(
			instance_start + 1,
			instance_finish - instance_start - 1
		)
		var visual_resource: Dictionary = extresources.get(resource_id, {})
		if visual_resource.is_empty():
			errors.append("%s: %s references missing ext_resource %s" % [scene_path, visual_name, resource_id])
			continue
		if str(visual_resource.get("type", "")) != "PackedScene":
			errors.append("%s: %s ext_resource must be a PackedScene" % [scene_path, visual_name])
			continue

		var resource_path: String = str(visual_resource.get("path", ""))
		if visual_name == "VisualInstance" or visual_name == "VisualInstance_Intact":
			# Preserve the existing intact contract: parent, PackedScene type, and exact manifest path.
			if resource_path != generated_visual_scene_path:
				errors.append("%s: %s ext_resource path does not match manifest.generated.visual_scene_path" % [scene_path, visual_name])
		else:
			# Damaged and breached references are text-checked before touching the loader.
			var canonical_contained_path: bool = (
				resource_path.begins_with(STRUCTURAL_SCENE_PREFIX)
				and not resource_path.split("/").has("..")
				and resource_path.simplify_path() == resource_path
			)
			if not canonical_contained_path:
				errors.append("%s: %s must use a canonical contained structural PackedScene path" % [scene_path, visual_name])
				continue
			if not ResourceLoader.exists(resource_path, "PackedScene"):
				errors.append("%s: %s references missing PackedScene resource" % [scene_path, visual_name])
```

The fixed `variant_names` order makes both the mixed-form and missing-variant diagnostics deterministic. Legacy is accepted only when no variant node is present; variant-aware form is accepted only when all three named nodes are present; any partial variant set is rejected. The four negative fixtures must therefore produce the exact substrings `mixed visual forms are forbidden`, `incomplete variant visual form; missing variants: VisualInstance_Breached`, `must use a canonical contained structural PackedScene path`, and `references missing PackedScene resource`. Do not edit structural scenes, source wrapper scenes, or GLBs; this step changes only validator logic.



- [ ] **Step 4: Run the complete green validator, negative-fixture, smoke, and source-integrity bundle**

Run this as an independent shell block after Step 3. It does not define or use an outer snapshot/trap: every Godot invocation is a separate `$STATE_RUNNER -- "$GODOT_BIN" ...` call, and the runner performs snapshot, command execution, generated-state restoration, broad source verification, and temporary-snapshot cleanup for that one invocation before returning. Thus an early import, validator, fixture, or smoke failure cannot skip its own source/state guard, and the runner preserves that command's primary nonzero status if cleanup also fails.

```bash
set -euo pipefail
GODOT_BIN=/opt/homebrew/bin/godot
FIXTURE_ROOT=tests/fixtures/structural_variant_wrappers
RUNNER_MARKER='GENERATED STATE RESTORE VERIFIED'
derive_checked_state_runner() {
  REPOSITORY_ROOT=$(python3 - "$PWD" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)
  WORKTREE_DIGEST=$(python3 - "$REPOSITORY_ROOT" <<'PY'
import hashlib
import sys
print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())
PY
)
  TEMP_BASE=$(python3 - "${TMPDIR:-/tmp}" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("TMPDIR must resolve to an external non-root directory")
print(candidate)
PY
)
  local state_home="$TEMP_BASE/synaptic-sea-task2-${WORKTREE_DIGEST}"
  if [[ -L "$state_home" || ( -e "$state_home" && ! -d "$state_home" ) ]]; then
    printf 'STATE_HOME must not be a symlink or non-directory: %s\n' "$state_home" >&2
    exit 1
  fi
  STATE_HOME=$(python3 - "$state_home" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME must resolve to an external non-root directory")
print(candidate)
PY
)
  mkdir -p "$STATE_HOME"
  [[ -d "$STATE_HOME" && ! -L "$STATE_HOME" ]] || {
    printf 'STATE_HOME must be a real non-symlink directory: %s\n' "$STATE_HOME" >&2
    exit 1
  }
  STATE_HOME=$(python3 - "$STATE_HOME" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME resolved inside the repository after mkdir")
print(candidate)
PY
)
  runner_path="$STATE_HOME/state_runner.py"
  [[ -f "$runner_path" && ! -L "$runner_path" && -x "$runner_path" ]] || {
    printf 'STATE_RUNNER must be a non-symlink executable regular file: %s\n' "$runner_path" >&2
    exit 1
  }
  STATE_RUNNER=$(python3 - "$runner_path" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_RUNNER resolves inside the repository")
print(candidate)
PY
)
}
derive_checked_state_runner
[[ -f "$STATE_RUNNER" && ! -L "$STATE_RUNNER" && -x "$STATE_RUNNER" ]] || {
  printf 'missing executable STATE_RUNNER: %s\n' "$STATE_RUNNER" >&2
  exit 1
}

strip_runner_marker() {
  awk -v marker="$RUNNER_MARKER" '$0 != marker'
}

require_runner_success() {
  local label="$1"
  local raw="$2"
  local marker_count runner_diagnostics
  marker_count=$(awk -v marker="$RUNNER_MARKER" '$0 == marker { count += 1 } END { print count + 0 }' <<<"$raw")
  runner_diagnostics=$(awk '/^STATE RUNNER:/ { print }' <<<"$raw")
  if (( marker_count != 1 )); then
    printf '%s: expected exactly one %s, got %d\n' "$label" "$RUNNER_MARKER" "$marker_count" >&2
    return 1
  fi
  if [[ -n "$runner_diagnostics" ]]; then
    printf '%s: unexpected STATE RUNNER: diagnostic:\n%s\n' "$label" "$runner_diagnostics" >&2
    return 1
  fi
}

require_runner_clean_without_marker() {
  local label="$1"
  local raw="$2"
  local marker_count runner_diagnostics
  marker_count=$(awk -v marker="$RUNNER_MARKER" '$0 == marker { count += 1 } END { print count + 0 }' <<<"$raw")
  runner_diagnostics=$(awk '/^STATE RUNNER:/ { print }' <<<"$raw")
  if (( marker_count != 0 )); then
    printf '%s: expected no %s for a nonzero primary command, got %d\n' "$label" "$RUNNER_MARKER" "$marker_count" >&2
    return 1
  fi
  if [[ -n "$runner_diagnostics" ]]; then
    printf '%s: unexpected STATE RUNNER: diagnostic:\n%s\n' "$label" "$runner_diagnostics" >&2
    return 1
  fi
}

run_clean() {
  local label="$1"
  shift
  local raw filtered status error_count warning_count
  if raw=$("$@" 2>&1); then status=0; else status=$?; fi
  if ! require_runner_success "$label" "$raw"; then
    return 1
  fi
  filtered=$(printf '%s\n' "$raw" | strip_runner_marker)
  printf '%s\n' "$filtered"
  error_count=$(awk 'BEGIN { count = 0 } /^ERROR:/ { count += 1 } END { print count }' <<<"$filtered")
  warning_count=$(awk 'BEGIN { count = 0 } /^WARNING:/ { count += 1 } END { print count }' <<<"$filtered")
  if (( status != 0 || error_count != 0 || warning_count != 0 )); then
    printf '%s: expected exit 0 with zero ERROR:/WARNING: lines\n' "$label" >&2
    return 1
  fi
}

expect_clean_accept() {
  local label="$1"
  local expected_marker="$2"
  shift 2
  local raw filtered status error_count warning_count marker_count
  if raw=$("$@" 2>&1); then status=0; else status=$?; fi
  if ! require_runner_success "$label" "$raw"; then
    return 1
  fi
  filtered=$(printf '%s\n' "$raw" | strip_runner_marker)
  printf '%s\n' "$filtered"
  error_count=$(awk 'BEGIN { count = 0 } /^ERROR:/ { count += 1 } END { print count }' <<<"$filtered")
  warning_count=$(awk 'BEGIN { count = 0 } /^WARNING:/ { count += 1 } END { print count }' <<<"$filtered")
  marker_count=$(awk -v expected="$expected_marker" '$0 == expected { count += 1 } END { print count + 0 }' <<<"$filtered")
  if (( status != 0 || error_count != 0 || warning_count != 0 || marker_count != 1 )); then
    printf '%s: expected exit 0, zero ERROR:/WARNING:, and exactly one %s; got errors=%d warnings=%d marker_count=%d\n' \
      "$label" "$expected_marker" "$error_count" "$warning_count" "$marker_count" >&2
    return 1
  fi
}

expect_exact_error_signature() {
  local label="$1"
  local expected_status="$2"
  local expected_error_count="$3"
  local marker="$4"
  shift 4
  local raw filtered status error_count warning_count unexpected_errors
  if raw=$("$@" 2>&1); then status=0; else status=$?; fi
  if (( expected_status == 0 )); then
    if ! require_runner_success "$label" "$raw"; then
      return 1
    fi
  else
    if ! require_runner_clean_without_marker "$label" "$raw"; then
      return 1
    fi
  fi
  filtered=$(printf '%s\n' "$raw" | strip_runner_marker)
  printf '%s\n' "$filtered"
  if (( status != expected_status )); then
    printf '%s: expected exit %d, got %d\n' "$label" "$expected_status" "$status" >&2
    return 1
  fi
  error_count=$(awk 'BEGIN { count = 0 } /^ERROR:/ { count += 1 } END { print count }' <<<"$filtered")
  warning_count=$(awk 'BEGIN { count = 0 } /^WARNING:/ { count += 1 } END { print count }' <<<"$filtered")
  if (( error_count != expected_error_count || warning_count != 0 )); then
    printf '%s: expected errors=%d warnings=0, got errors=%d warnings=%d\n' "$label" "$expected_error_count" "$error_count" "$warning_count" >&2
    return 1
  fi
  unexpected_errors=$(awk -v marker="$marker" 'index($0, "ERROR:") == 1 && index($0, marker) == 0 { print }' <<<"$filtered")
  if [[ -n "$unexpected_errors" ]]; then
    printf '%s: ERROR: line without required marker %s:\n%s\n' "$label" "$marker" "$unexpected_errors" >&2
    return 1
  fi
}

run_negative_fixture_green_suite() {
  expect_exact_error_signature \
    "mixed_legacy_variant post-fix rejection" 1 1 \
    "mixed visual forms are forbidden" \
    "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/mixed_legacy_variant.tscn"
  expect_exact_error_signature \
    "partial_variant post-fix rejection" 1 1 \
    "incomplete variant visual form; missing variants: VisualInstance_Breached" \
    "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/partial_variant.tscn"
  expect_exact_error_signature \
    "traversal_damaged_variant post-fix rejection" 1 1 \
    "must use a canonical contained structural PackedScene path" \
    "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/traversal_damaged_variant.tscn"
  expect_exact_error_signature \
    "missing_damaged_resource post-fix rejection" 1 1 \
    "references missing PackedScene resource" \
    "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/missing_damaged_resource.tscn"
}

# Every command below is isolated independently. The exact real-directory gate
# is 15 bundles, not merely a zero exit status.
run_clean "editor import preflight" \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --editor --path . --quit
expect_clean_accept \
  "real structural directory post-fix" \
  'Validated 15 wrapper scene bundle(s).' \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
  --script res://scripts/placement/validate_wrapper_scenes.gd -- \
  scenes/wrappers/structural/ship_structural_v0
run_negative_fixture_green_suite
printf 'NEGATIVE FIXTURE GREEN CONFIRMED\n'
expect_clean_accept \
  "eight-scene structural variant wrapper smoke" \
  'STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true' \
  "$STATE_RUNNER" -- "$GODOT_BIN" --headless --path . \
  --script res://scripts/validation/structural_variant_wrapper_smoke.gd
printf 'STRUCTURAL SOURCE GUARD PASS paths=3 per_invocation=true\n'
```

`expect_clean_accept` mechanically requires exit `0`, exactly one runner success marker, no `STATE RUNNER:` line, zero lines beginning `ERROR:` or `WARNING:`, and exactly one expected validator success marker. It is used for the mixed fixture's `Validated 1 wrapper scene bundle(s).` acceptance in the red gate and the post-fix real directory's exact `Validated 15 wrapper scene bundle(s).` acceptance above. `run_clean` applies the same runner-marker and runner-diagnostic checks to the editor preflight and every clean smoke/green run. The negative suite is the sole intentional `ERROR:` exception and requires status `1`, exactly one error, zero warnings, zero runner markers, no `STATE RUNNER:` diagnostics, and its exact validator diagnostic marker for each fixture. Successful-primary captures validate exactly one runner line before removing only that stderr restore marker; expected-primary-failure captures validate that no runner marker or diagnostic exists before counting Godot output. The runner's per-invocation signal-aware `finally` path always performs child teardown, generated-state restoration when the snapshot completed, the broad source fingerprint check, and temporary cleanup, including on early snapshot/launch/wait interruption; a source/state failure cannot replace a failed Godot status. No outer Step 4 snapshot, `STATE_ROOT`, or `EXIT` trap remains to duplicate the runner.

- [ ] **Step 5: Stage only Task 2 implementation artifacts and commit**

Step 0's pre-mutation clean-worktree check is the required protection against pre-existing staged, unstaged, untracked, and ignored changes in owned paths and structural source roots. This fence independently re-derives the external state directory and verifies Step 0's record still names this worktree and the same starting `HEAD`; it intentionally does not repeat the obsolete whole-index stage-only precondition. Retain the exact 14-path staging and commit-scope proofs below. Never use `git reset`.

```bash
set -euo pipefail
TASK2_PATHS=(
  scripts/placement/validate_wrapper_scenes.gd
  scripts/validation/structural_variant_wrapper_smoke.gd
  tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.tscn
  tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.manifest.json
  tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.input.json
  tests/fixtures/structural_variant_wrappers/partial_variant.tscn
  tests/fixtures/structural_variant_wrappers/partial_variant.manifest.json
  tests/fixtures/structural_variant_wrappers/partial_variant.input.json
  tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.tscn
  tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.manifest.json
  tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.input.json
  tests/fixtures/structural_variant_wrappers/missing_damaged_resource.tscn
  tests/fixtures/structural_variant_wrappers/missing_damaged_resource.manifest.json
  tests/fixtures/structural_variant_wrappers/missing_damaged_resource.input.json
)
if (( ${#TASK2_PATHS[@]} != 14 )); then
  printf 'expected exactly 14 Task 2 paths, got %d\n' "${#TASK2_PATHS[@]}" >&2
  exit 1
fi
derive_checked_state_runner() {
  REPOSITORY_ROOT=$(python3 - "$PWD" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)
  WORKTREE_DIGEST=$(python3 - "$REPOSITORY_ROOT" <<'PY'
import hashlib
import sys
print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())
PY
)
  TEMP_BASE=$(python3 - "${TMPDIR:-/tmp}" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("TMPDIR must resolve to an external non-root directory")
print(candidate)
PY
)
  local state_home="$TEMP_BASE/synaptic-sea-task2-${WORKTREE_DIGEST}"
  if [[ -L "$state_home" || ( -e "$state_home" && ! -d "$state_home" ) ]]; then
    printf 'STATE_HOME must not be a symlink or non-directory: %s\n' "$state_home" >&2
    exit 1
  fi
  STATE_HOME=$(python3 - "$state_home" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME must resolve to an external non-root directory")
print(candidate)
PY
)
  mkdir -p "$STATE_HOME"
  [[ -d "$STATE_HOME" && ! -L "$STATE_HOME" ]] || {
    printf 'STATE_HOME must be a real non-symlink directory: %s\n' "$STATE_HOME" >&2
    exit 1
  }
  STATE_HOME=$(python3 - "$STATE_HOME" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_HOME resolved inside the repository after mkdir")
print(candidate)
PY
)
  runner_path="$STATE_HOME/state_runner.py"
  [[ -f "$runner_path" && ! -L "$runner_path" && -x "$runner_path" ]] || {
    printf 'STATE_RUNNER must be a non-symlink executable regular file: %s\n' "$runner_path" >&2
    exit 1
  }
  STATE_RUNNER=$(python3 - "$runner_path" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
repository = Path(sys.argv[2]).expanduser().resolve()
candidate = Path(sys.argv[1]).expanduser().resolve()
if candidate == Path(candidate.anchor) or candidate == repository or repository in candidate.parents:
    raise SystemExit("STATE_RUNNER resolves inside the repository")
print(candidate)
PY
)
}
derive_checked_state_runner
[[ -f "$STATE_RUNNER" && ! -L "$STATE_RUNNER" && -x "$STATE_RUNNER" ]] || {
  printf 'missing executable STATE_RUNNER: %s\n' "$STATE_RUNNER" >&2
  exit 1
}
PRECONDITION_RECORD="$STATE_HOME/step0-precondition.txt"
[[ -f "$PRECONDITION_RECORD" ]] || { printf 'missing Step 0 precondition record\n' >&2; exit 1; }
python3 - "$PRECONDITION_RECORD" "$PWD" "$(git rev-parse HEAD)" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
if lines != [sys.argv[2], sys.argv[3]]:
    raise SystemExit("Step 0 precondition record does not match this worktree and starting HEAD")
PY

# Step 0's clean precondition was satisfied before any Task 2 mutation. The
# exact allowlist below is the only set that may enter the index or commit.
git add "${TASK2_PATHS[@]}"
expected_paths=$(printf '%s\n' "${TASK2_PATHS[@]}" | LC_ALL=C sort)
actual_paths=$(git diff --cached --name-only | LC_ALL=C sort)
if [[ "$actual_paths" != "$expected_paths" ]]; then
  printf 'cached Task 2 path set mismatch\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_paths" "$actual_paths" >&2
  exit 1
fi

git diff --cached --check
staged_placeholders=$(git diff --cached --unified=0 | awk '/^\+[^+]/ && /(TODO|TBD)/ { print }')
if [[ -n "$staged_placeholders" ]]; then
  printf 'staged Task 2 additions contain forbidden placeholders:\n%s\n' \
    "$staged_placeholders" >&2
  exit 1
fi

git commit -m "fix: validate structural visual variants"
committed_paths=$(git diff-tree --no-commit-id --name-only -r HEAD | LC_ALL=C sort)
if [[ "$committed_paths" != "$expected_paths" ]]; then
  printf 'committed Task 2 path set mismatch\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_paths" "$committed_paths" >&2
  exit 1
fi
git diff HEAD^ HEAD --check
```

The exact 14-element `TASK2_PATHS` array is the sole staging allowlist; the cached expected-vs-actual comparison fails with both sets on mismatch, so no Task 3+ files, source wrappers, GLBs, or generated Godot state can be staged. The staged whitespace check and added-line placeholder scan run before commit. After commit, `git diff-tree --no-commit-id --name-only -r HEAD | LC_ALL=C sort` must equal the same expected set, and `git diff HEAD^ HEAD --check` must pass. Step 0's clean check is deliberately not replaced by a stage-only check, so pre-existing changes in an owned path are blocked before work begins rather than silently included by `git add`.

### Task 3: Implement the pure prop-sidecar schema, GLB inspection, and canonical serialization layer

**Files:**
- Create: `data/placement/schemas/prop_visual_binding_v1.schema.json`
- Create: `tools/prop_visual_metadata.py`
- Create: `tests/test_prop_visual_metadata.py`
- Create: `tests/fixtures/prop_visual_metadata/invalid_parent_path.sidecar.json`
- Create: `tests/fixtures/prop_visual_metadata/invalid_gameplay_field.sidecar.json`

**Interfaces:**
- `read_glb_metadata(path: Path) -> dict` returns `sha256`, `byte_size`, `gltf_version`, `mesh_count`, `local_min_m`, and `local_max_m`.
- `validate_sidecar(sidecar: dict, glb_path: Path, project_root: Path) -> list[str]` returns deterministic diagnostic strings; an empty list means valid.
- `write_canonical_json(path: Path, document: dict) -> None` writes sorted JSON and a final newline.

- [ ] **Step 1: Write pure Python red tests**

Add tests that fail before implementation:

```python
def test_reactor_console_glb_has_stable_hash_and_ordered_bounds() -> None:
    record = read_glb_metadata(PROJECT_ROOT / "assets/imported/props/components/reactor_console.glb")
    assert len(record["sha256"]) == 64
    assert record["mesh_count"] > 0
    assert record["local_min_m"][0] <= record["local_max_m"][0]


def test_sidecar_rejects_parent_path() -> None:
    errors = validate_sidecar(load_fixture("invalid_parent_path.sidecar.json"), REACTOR_GLB, PROJECT_ROOT)
    assert any("path must be a contained res:// path" in error for error in errors)


def test_sidecar_rejects_component_gameplay_fields() -> None:
    errors = validate_sidecar(load_fixture("invalid_gameplay_field.sidecar.json"), REACTOR_GLB, PROJECT_ROOT)
    assert any("forbidden gameplay field: mass" in error for error in errors)
```

Run:

```bash
python3 -m unittest -v tests.test_prop_visual_metadata
```

Expected before implementation: import failure for `prop_visual_metadata`.

- [ ] **Step 2: Define the schema**

Require these fields:

```json
{
  "schema_version": "1.0.0",
  "document_kind": "prop_visual_binding",
  "asset_id": "reactor_console",
  "prop_kind": "component",
  "visual_scene_path": "res://assets/imported/props/components/reactor_console.glb",
  "binding": {"namespace": "component_id", "ids": ["reactor_console"]},
  "placement": {"origin": "scene_origin", "offset_m": [0, 0, 0], "rotation_degrees": [0, 0, 0], "allowed_yaw_deg": [0, 90, 180, 270], "scale": 1.0},
  "source": {"sha256": "64 lowercase hex characters", "byte_size": 0, "mesh_count": 0, "gltf_version": "2.0"},
  "bounds": {"local_min_m": [0, 0, 0], "local_max_m": [0, 0, 0]},
  "collision_policy": "none_visual_only",
  "provenance": {"license_state": "self-authored", "source_platform": "self-authored"},
  "extensions": {}
}
```

Allow `placement.surface` only for `dressing` and `objective`; component mount surface remains owned by `component_catalog.json`.

- [ ] **Step 3: Implement the module**

Parse a GLB by checking the `glTF` header, reading the JSON chunk, reading accessor min/max values when available, and scanning POSITION accessors when min/max is absent. Reject malformed header lengths, absent meshes, non-finite bounds, mismatched sidecar basename, absolute paths, `..` path components, unsupported major schema versions, wrong `document_kind`, wrong `collision_policy`, duplicate IDs, and forbidden gameplay keys. Permit arbitrary JSON below `extensions`, but reject unknown root-level fields so all future root additions remain deliberate schema decisions.

Use this forbidden-key set exactly:

```python
FORBIDDEN_GAMEPLAY_FIELDS = {
    "mass", "power_draw", "condition_default", "linked_system", "linked_subcomponent",
    "role_weights", "room_id", "cell", "approach_cell", "sequence", "type", "kind",
    "steps", "loot_table", "item_form",
}
```

- [ ] **Step 4: Run the unit suite**

Run:

```bash
python3 -m unittest -v tests.test_prop_visual_metadata
```

Expected: all tests pass with no temporary files beneath `assets/imported/props`.

- [ ] **Step 5: Commit**

```bash
git add data/placement/schemas/prop_visual_binding_v1.schema.json tools/prop_visual_metadata.py tests/test_prop_visual_metadata.py tests/fixtures/prop_visual_metadata
git commit -m "feat: add prop visual sidecar schema"
```

### Task 4: Retroactively create and validate sidecars for all 26 imported prop GLBs

**Files:**
- Create: `tools/generate_prop_sidecars.py`
- Create: `tools/validate_prop_visual_bindings.py`
- Create: `tests/test_validate_prop_visual_bindings.py`
- Create: `assets/imported/props/components/*.sidecar.json` (11 files)
- Create: `assets/imported/props/dressing/*.sidecar.json` (11 files)
- Create: `assets/imported/props/objectives/*.sidecar.json` (4 files)
- Create: `data/props/visual_bindings.generated.json`

**Interfaces:**
- `generate_prop_sidecars.py --project-root . --write-missing --write-index` creates only missing sidecars and rebuilds the derived index.
- `generate_prop_sidecars.py --project-root . --refresh-derived --asset-id <asset_id> --write-index` replaces the full GLB-derived source evidence (`sha256`, `byte_size`, `mesh_count`, `gltf_version`, and `bounds`) for one existing sidecar, preserves only authored `binding`, `placement`, `provenance`, and `extensions`, and rebuilds the derived index.
- `generate_prop_sidecars.py --project-root . --check` returns nonzero when a canonical sidecar or derived index differs from disk.
- `validate_prop_visual_bindings.py --project-root . --check-index` returns nonzero for any schema, GLB, hash, bounds, binding, count, path, or index mismatch.

- [ ] **Step 1: Write validator red tests**

Create fixture-copy helpers named `copied_project_without`, `copied_project_with_sidecar_value`, `copied_project_with_objective_alias`, and `copied_project_with_stale_index`, plus a `run_validator` helper that returns the newline-joined deterministic validator diagnostics. Prove the validator rejects each condition with these concrete tests:

```python
def test_validator_rejects_missing_sidecar() -> None:
    with copied_project_without("assets/imported/props/components/reactor_console.sidecar.json") as project_root:
        assert "missing sidecar" in run_validator(project_root)

def test_validator_rejects_stale_hash() -> None:
    with copied_project_with_sidecar_value("reactor_console", ["source", "sha256"], "0" * 64) as project_root:
        assert "sha256 mismatch" in run_validator(project_root)

def test_validator_rejects_unknown_component_id() -> None:
    with copied_project_with_sidecar_value("reactor_console", ["binding", "ids"], ["unknown_component"]) as project_root:
        assert "unknown component_id: unknown_component" in run_validator(project_root)

def test_validator_rejects_duplicate_objective_placement_binding() -> None:
    with copied_project_with_objective_alias("medbay_terminal", "reactor_control_panel") as project_root:
        assert "duplicate gameplay_placement_id: reactor_control_panel" in run_validator(project_root)

def test_validator_rejects_stale_generated_index() -> None:
    with copied_project_with_stale_index("components", "reactor_console") as project_root:
        assert "generated index differs from sidecars" in run_validator(project_root)

def test_refresh_preserves_extensions_and_hand_authored_fields() -> None:
    with copied_project_with_extension("reactor_console", {"studio": {"review_state": "approved"}}) as project_root:
        refresh_derived(project_root, "reactor_console")
        sidecar = load_sidecar(project_root, "components", "reactor_console")
        assert sidecar["extensions"] == {"studio": {"review_state": "approved"}}
        assert sidecar["binding"]["ids"] == ["reactor_console"]
        assert sidecar["placement"]["origin"] == "scene_origin"
```

Run:

```bash
python3 -m unittest -v tests.test_validate_prop_visual_bindings
```

Expected before implementation: import failure for `validate_prop_visual_bindings`.

- [ ] **Step 2: Implement explicit seed mappings**

Seed all 11 component sidecars with `binding.namespace = "component_id"` and exactly one ID equal to its GLB basename:

```text
air_recycler_unit, conduit_run, console_generic, hull_plating, locker_wall,
machinery_block, nav_console, pump_assembly, reactor_console, sensor_rack,
thruster_control
```

Seed all 11 dressing sidecars with `binding.namespace = "visual_prop_id"` and exactly one matching ID. Use these placement surfaces:

```text
wall: cable_tray, emergency_wall
ceiling: practical_overhead
floor: cargo_pallet, focused_work_lamp, generic_crate, generic_locker,
       maintenance_bench, medical_cabinet, salvage_cart, service_rack
```

Seed objective sidecars with `binding.namespace = "gameplay_placement_id"`:

```text
supply_cache: cargo_supply_cache, supply_cache
repair_junction: maintenance_breaker_panel
medbay_terminal: medbay_terminal
reactor_control_panel: reactor_control_panel
```

Set every existing prop sidecar to `collision_policy = "none_visual_only"` and `provenance = {"license_state": "self-authored", "source_platform": "self-authored"}`. Derive each hash, byte size, mesh count, and bounds from the actual GLB.

- [ ] **Step 3: Generate the derived index**

Emit `data/props/visual_bindings.generated.json` sorted by `asset_id` with this top-level shape:

```json
{
  "schema_version": "1.0.0",
  "document_kind": "prop_visual_binding_index",
  "components": {},
  "objectives": {},
  "dressing": {}
}
```

Each component key maps to one sidecar-derived record. Each objective placement ID maps to one sidecar-derived record, including both supply-cache aliases. Each dressing key maps to its sidecar-derived record.

- [ ] **Step 4: Run red-to-green generator checks**

Run:

```bash
python3 tools/generate_prop_sidecars.py --project-root . --check
python3 tools/generate_prop_sidecars.py --project-root . --write-missing --write-index
python3 tools/generate_prop_sidecars.py --project-root . --check
python3 tools/validate_prop_visual_bindings.py --project-root . --check-index
python3 -m unittest -v tests.test_validate_prop_visual_bindings
```

Expected sequence: initial check exits nonzero before sidecars exist; generation creates 26 sidecars and one index; final check/validator/test suite exit zero.

- [ ] **Step 5: Verify the exact retrofit inventory and commit**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
root = Path('assets/imported/props')
for group, expected in [('components', 11), ('dressing', 11), ('objectives', 4)]:
    glbs = sorted((root / group).glob('*.glb'))
    sidecars = sorted((root / group).glob('*.sidecar.json'))
    assert len(glbs) == expected, (group, len(glbs))
    assert len(sidecars) == expected, (group, len(sidecars))
    assert {p.stem.removesuffix('.sidecar') for p in sidecars} == {p.stem for p in glbs}
print('PROP SIDECAR RETROFIT PASS components=11 dressing=11 objectives=4')
PY
git add assets/imported/props data/props tools/generate_prop_sidecars.py tools/validate_prop_visual_bindings.py tests/test_validate_prop_visual_bindings.py
git commit -m "feat: retrofit prop visual sidecars"
```

### Task 5: Add pure runtime catalog and visual-only GLB binder

**Files:**
- Create: `scripts/systems/prop_visual_binding_catalog.gd`
- Create: `scripts/procgen/runtime_prop_visual_binder.gd`
- Create: `scripts/validation/prop_visual_binding_smoke.gd`

**Interfaces:**

```gdscript
class_name PropVisualBindingCatalog
func load_from_path(path: String = "res://data/props/visual_bindings.generated.json") -> bool
func get_component_binding(component_id: String) -> Dictionary
func get_objective_binding(placement_id: String) -> Dictionary
func get_dressing_binding(visual_prop_id: String) -> Dictionary
func get_errors() -> Array[String]

class_name RuntimePropVisualBinder
static func mount_component_visual(marker: Node3D, binding: Dictionary) -> bool
static func create_objective_visual(binding: Dictionary) -> Node3D
static func clear_imported_visuals(root: Node) -> void
```

- [ ] **Step 1: Write the catalog/binder red smoke**

Create `prop_visual_binding_smoke.gd` with these assertions:

```gdscript
var catalog := PropVisualBindingCatalog.new()
_assert(catalog.load_from_path(), "catalog loads generated index")
_assert(not catalog.get_component_binding("reactor_console").is_empty(), "reactor console resolves")
_assert(not catalog.get_objective_binding("reactor_control_panel").is_empty(), "reactor panel resolves")
_assert(catalog.get_component_binding("missing_component").is_empty(), "unknown component is empty")
_assert(catalog.get_objective_binding("bridge_power_distribution").is_empty(), "unmapped objective is empty")
```

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/prop_visual_binding_smoke.gd
```

Expected before implementation: script-load failure because the catalog class does not exist.

- [ ] **Step 2: Implement strict catalog loading**

The catalog must parse the generated index, require `document_kind = "prop_visual_binding_index"`, accept only major schema version `1`, validate that all scene paths begin `res://assets/imported/props/`, and return `{}` for unknown keys. It must never fabricate a fallback binding.

- [ ] **Step 3: Implement the visual-only binder**

`mount_component_visual` must:

```gdscript
if marker == null or binding.is_empty():
    return false
var packed := load(str(binding.get("visual_scene_path", ""))) as PackedScene
if packed == null:
    return false
var visual := packed.instantiate() as Node3D
if visual == null:
    return false
visual.name = "ImportedVisual"
visual.set_meta("visual_source", "imported")
marker.add_child(visual)
return true
```

Apply `offset_m`, `rotation_degrees`, and `scale` only after verifying their array lengths and finite values. `create_objective_visual` follows the same loading/transform rules but returns the detached `Node3D`. The binder must not add collision nodes, `Area3D`, or interaction scripts.

- [ ] **Step 4: Run green smoke and commit**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/prop_visual_binding_smoke.gd
git add scripts/systems/prop_visual_binding_catalog.gd scripts/procgen/runtime_prop_visual_binder.gd scripts/validation/prop_visual_binding_smoke.gd
git commit -m "feat: add prop visual binding runtime"
```

Expected: `PROP VISUAL BINDING PASS components=true objectives=true fallback=true` with no diagnostics.

### Task 6: Replace component-marker primitive visuals with imported GLBs while preserving fallback behavior

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd:3494-3554`
- Modify: `scripts/validation/component_markers_smoke.gd`
- Create: `scripts/validation/component_imported_visual_smoke.gd`

**Interfaces:**
- Consumes `PropVisualBindingCatalog.get_component_binding(component_id)` and `RuntimePropVisualBinder.mount_component_visual(marker, binding)`.
- Produces component marker metadata `visual_source = "imported"` or `visual_source = "fallback"`.

- [ ] **Step 1: Add a failing visual-source assertion**

Extend the component marker smoke to require that a placed `reactor_console` marker has:

```gdscript
_assert(str(marker.get_meta("visual_source", "")) == "imported", "reactor console uses imported GLB")
_assert(marker.get_node_or_null("ImportedVisual") != null, "imported visual child exists")
```

Add a second test fixture/path that temporarily requests `missing_component`; it must create a marker with `visual_source = "fallback"` and retain the existing primitive mesh child.

- [ ] **Step 2: Run the red smoke**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_imported_visual_smoke.gd
```

Expected before integration: missing `ImportedVisual` assertion.

- [ ] **Step 3: Integrate at the existing marker seam**

In `_rebuild_component_markers()`:

1. Preserve existing marker naming, position calculation, parent selection, component metadata, and `_clear_component_markers()` ownership.
2. Load the catalog once per rebuild.
3. Resolve the existing `component_id`.
4. Call `RuntimePropVisualBinder.mount_component_visual(marker, binding)`.
5. On success, call `marker.set_meta("visual_source", "imported")`.
6. On failure, call `marker.set_meta("visual_source", "fallback")` and run the current `BoxMesh` creation block unchanged.

Do not add visual path, visual transform, or binding data to `ComponentPlacementState`.

- [ ] **Step 4: Verify lifecycle regression coverage**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_markers_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_imported_visual_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_mount_dismount_smoke.gd
```

Expected: imported `reactor_console` visual appears after rebuild; a malformed/missing binding uses the primitive fallback; dismount removes the marker and visual; remount rebuilds one visual without duplicates.

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/component_markers_smoke.gd scripts/validation/component_imported_visual_smoke.gd
git commit -m "feat: render components from prop bindings"
```

### Task 7: Preserve objective placement IDs and bind imported objective visuals without changing interaction volumes

**Files:**
- Modify: `scripts/procgen/generated_ship_loader.gd:368-380`
- Modify: `scripts/interaction/interactable.gd:35-86`
- Modify: `scripts/procgen/playable_generated_ship.gd:973-981`
- Create: `scripts/validation/objective_visual_binding_smoke.gd`
- Modify: `scripts/validation/readability_prop_factory_smoke.gd`

**Interfaces:**
- `GeneratedShipLoader._build_objective_specs()` adds `placement_id: String` to each emitted spec.
- `Interactable.configure_from_objective()` and `configure_from_step()` store the `placement_id` in node metadata.
- Objective visual lookup consumes `placement_id`; it never uses objective `type` as its lookup key.

- [ ] **Step 1: Write red objective-flow tests**

Create a smoke that loads `coherent_ship_001` and asserts:

```gdscript
_assert(placement_ids.has("cargo_supply_cache"), "supply cache placement ID retained")
_assert(placement_ids.has("maintenance_breaker_panel"), "repair junction placement ID retained")
_assert(placement_ids.has("medbay_terminal"), "medbay placement ID retained")
_assert(placement_ids.has("reactor_control_panel"), "reactor placement ID retained")
_assert(imported_visual_count == 4, "four physical imported objective visuals")
_assert(interactable_count == 5, "repair junction retains two gameplay interaction steps")
```

Add a coherent-ship-003 assertion that `bridge_power_distribution` and `life_support_console` use the existing procedural visual fallback rather than an unrelated imported GLB.

- [ ] **Step 2: Run the red test**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/objective_visual_binding_smoke.gd
```

Expected before integration: missing `placement_id` assertion.

- [ ] **Step 3: Preserve and propagate `placement_id`**

Add this exact field to the objective spec dictionary in `generated_ship_loader.gd`:

```gdscript
"placement_id": str(objective.get("placement_id", "")),
```

In both `Interactable` configuration methods, set:

```gdscript
set_meta("placement_id", str(objective.get("placement_id", "")))
```

Keep all existing objective IDs, sequence, type, room, position, radius, step, and loot behavior unchanged.

- [ ] **Step 4: Bind objective visuals at the readability seam**

In `_build_objective_affordance_props()`:

1. Create `var rendered_placement_ids: Dictionary = {}` before iterating interactables.
2. Read `placement_id` from each interactable metadata.
3. If that ID is already rendered, skip imported rendering for the duplicate repair step.
4. Resolve the catalog objective binding by placement ID.
5. Call `RuntimePropVisualBinder.create_objective_visual(binding)`.
6. On success, set `visual_source = "imported"`, register it at the first matching interactable position, and mark the placement ID rendered.
7. On missing/invalid binding, call `ReadabilityPropFactoryScript.create_objective_prop(sequence, objective_type)` exactly as the current fallback does, set `visual_source = "fallback"`, and register it at the interactable position.

Do not parent visual meshes under `GeneratedShipLoader`'s `ObjectiveRoot`; that root remains gameplay-volume ownership. Do not delete, alter, or replace an `Interactable`/objective volume.

- [ ] **Step 5: Run objective and regression gates**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/objective_visual_binding_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/readability_prop_factory_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/main_playable_slice_completion_smoke.gd
```

Expected: four supplied objective GLBs appear once per physical placement in coherent ship 001; all five interactions remain; unsupported placement IDs use fallback visuals; objective progress/completion markers remain unchanged.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/generated_ship_loader.gd scripts/interaction/interactable.gd scripts/procgen/playable_generated_ship.gd scripts/validation/objective_visual_binding_smoke.gd scripts/validation/readability_prop_factory_smoke.gd
git commit -m "feat: bind objective visuals by placement id"
```

### Task 8: Add structural variant audit, generated-data freshness checks, and the release regression bundle

**Files:**
- Create: `tools/validate_structural_variant_bindings.py`
- Create: `tests/test_validate_structural_variant_bindings.py`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/game/features/asset_metadata_pipeline.md`

**Interfaces:**
- `validate_structural_variant_bindings.py --project-root .` validates the eight intact/damaged/breached trios without modifying GLBs, scenes, manifests, or contracts.
- It returns zero only when each trio exists, every GLB has a stable SHA-256, the wrapper references all three paths, wrapper anchors remain present, and `IntegrityVisualResolver` names match the scene nodes.

- [ ] **Step 1: Add red structural-audit tests**

Write temporary-fixture helpers named `copied_structural_fixture_without`, `copied_structural_fixture_with_wrapper_ref`, `copied_structural_fixture_without_node`, `copied_non_variant_structural_fixture`, and `run_structural_audit`. Add these exact failure checks:

```python
def test_missing_breached_variant_is_rejected() -> None:
    with copied_structural_fixture_without("floor_1x1_breached.glb") as project_root:
        assert "missing breached GLB: floor_1x1" in run_structural_audit(project_root)

def test_wrapper_path_that_differs_from_variant_path_is_rejected() -> None:
    with copied_structural_fixture_with_wrapper_ref("floor_1x1", "VisualInstance_Damaged", "floor_1x1.glb") as project_root:
        assert "damaged wrapper path does not match damaged variant: floor_1x1" in run_structural_audit(project_root)

def test_missing_wrapper_socket_anchor_is_rejected() -> None:
    with copied_structural_fixture_without_node("floor_1x1", "Anchor_SOCK_N") as project_root:
        assert "missing required socket anchor Anchor_SOCK_N: floor_1x1" in run_structural_audit(project_root)

def test_non_variant_wrapper_is_ignored_when_it_has_no_integrity_triplet() -> None:
    with copied_non_variant_structural_fixture("wall_end_cap") as project_root:
        assert run_structural_audit(project_root) == []
```

- [ ] **Step 2: Implement the read-only audit**

Audit exactly these variant families:

```text
floor_1x1, floor_2x1, corridor_floor_1x1, corridor_floor_1x2,
wall_straight_1x1, doorway_frame_open_1x1, pillar_support_1x1, ramp_up_1x2
```

For each, verify the exact `intact`, `_damaged`, and `_breached` GLB paths referenced by its wrapper. Verify that the wrapper has `Anchor_FloorCenter`; confirm its existing `Anchor_SOCK_*` set remains stable; verify `VisualInstance_Intact`, `VisualInstance_Damaged`, and `VisualInstance_Breached` are direct children of `Visual`.

- [ ] **Step 3: Run the complete deterministic gate**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
python3 tools/generate_prop_sidecars.py --project-root . --check
python3 tools/validate_prop_visual_bindings.py --project-root . --check-index
python3 tools/validate_structural_variant_bindings.py --project-root .
python3 -m unittest -v \
  tests.test_prop_visual_metadata \
  tests.test_validate_prop_visual_bindings \
  tests.test_validate_structural_variant_bindings
"$GODOT_BIN" --headless --path . --script res://scripts/placement/validate_wrapper_scenes.gd -- scenes/wrappers/structural/ship_structural_v0
"$GODOT_BIN" --headless --path . --script res://scripts/validation/structural_variant_wrapper_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/prop_visual_binding_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_imported_visual_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/objective_visual_binding_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_mount_dismount_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/main_playable_slice_completion_smoke.gd
```

Expected: every command exits zero, all pass markers appear, and 26 sidecars/index are fresh. Eight structural trios validate; components use imported visual bindings; supplied objectives use imported visual bindings; unsupported objective placement IDs retain fallbacks. The exact documented ``WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).`` baseline is the sole allowed warning from the component smoke; any other diagnostic or a warning count other than two fails the gate.

- [ ] **Step 4: Restore generated engine state and verify repository scope**

Run:

```bash
git restore .godot
git clean -fd -- '*.import'
git diff --check
git status --short
git diff --name-only HEAD~1..HEAD
```

Expected: no `.godot` or `*.import` files remain; the diff contains only Task 8 audit/tests/docs files.

- [ ] **Step 5: Commit**

```bash
git add tools/validate_structural_variant_bindings.py tests/test_validate_structural_variant_bindings.py docs/game/06_validation_plan.md docs/game/features/asset_metadata_pipeline.md
git commit -m "test: audit structural variants and asset bindings"
```

## Final Acceptance Checklist

- [ ] The documentation establishes ADR-0052 and `REQ-AVB-001` through `REQ-AVB-009`.
- [ ] Godot validation imports before tests and uses the installed Godot 4.7.1 command.
- [ ] Structural wrapper validation accepts both legacy and integrity-variant visual forms.
- [ ] The eight structural variant trios validate without rewriting GLBs or duplicating sockets.
- [ ] Every imported prop GLB has one canonical adjacent sidecar: components=11, dressing=11, objectives=4.
- [ ] Sidecar hashes and bounds match actual GLB contents; generated index freshness is enforced.
- [ ] The runtime index is generated-only and has no hand-authored duplicate authority.
- [ ] Components render real imported GLBs beneath existing markers and retain the primitive fallback for invalid bindings.
- [ ] Objectives resolve by `placement_id`, render one visual per physical placement, and retain existing fallback behavior for unmapped IDs.
- [ ] Component mounting, objective interaction, objective progression, structural integrity visuals, and game completion all retain their current behavior under headless regression tests.
- [ ] The exact two-instance ObjectDB leak remains classified as the pre-existing `ship-core` baseline or is removed by its dedicated remediation card; no new or increased warning is accepted.
- [ ] No GLB byte changes, Godot cache files, `.import` artifacts, or unrelated refactors are committed.
