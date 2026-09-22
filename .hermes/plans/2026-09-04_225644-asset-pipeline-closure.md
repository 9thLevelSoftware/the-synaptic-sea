# Synaptic Sea Asset Creation and Refinement Closure Plan

> **For Hermes:** Use `subagent-driven-development` to execute this plan one reviewed work packet at a time. Load `synaptic-sea-asset-pipeline`, `test-driven-development`, and `verification-before-completion`. This document is a plan, not authorization to generate, publish, merge, or change assets during the planning turn.

**Goal:** Resolve the known outstanding creation, refinement, evidence, integration, and promotion gaps without losing source assets, duplicating paid tasks, or weakening gameplay and visual-quality gates.

**Architecture:** Keep the existing contract → candidate staging → Blender master → independently validated GLB → real Godot review → separate promotion architecture. Converge the existing implementation branches and evidence before adding functionality, and use the accepted biomass contract rather than building a second singular-threat production system. Preserve structural JSON/Godot ownership and keep optional texture-generation experiments outside the production write path.

**Tech stack:** Python 3.11 for host tools/tests; Blender for editable masters and visual-only GLB export; Godot 4.7.1 for runtime behavior and captures; JSON contracts/sidecars; pytest; git; existing Meshy staging adapter.

## 1. Current context and evidence limits

Inspected on 2026-09-04. All observations below came from read-only source, git, and evidence inspection. No tests, Blender jobs, Godot imports, provider tasks, or promotions were executed for this plan. Historical PASS records are not fresh acceptance evidence.

### Working locations

- Main repository: `/Users/christopherwilloughby/Code/the-synaptic-sea`.
- Inspected main commit: `f4a656692606e23813df68d24daba4c5e4a0151b`.
- Existing Meshy worktree: `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/meshy-blender-asset-system`.
- Existing biomass worktree: `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/procedural-biomass-assembly`.
- Inspected biomass branch: `feature/procedural-biomass-threat-assembly`, commit `3823b9a7c8f50ccc43a15e3689d40a2e94b8cdc6`.
- Biomass readiness-document branch: `docs/biomass-task9-final-readiness`, commit `97768af0100e2b56a925609493f99f52fe16c908`.
- Heavy sources: `/Volumes/Untitled/SynapticSeaAssets/`.
- Board: `synaptic-sea-stage-gate`.
- GitHub repository: `9thLevelSoftware/the-synaptic-sea`. The read-only open-issue query returned an empty list; it is not the complete backlog.

### Facts that change the implementation order

1. Main already contains the Meshy contract, journal/recovery, candidate review, Blender master, Blender validator, runtime review, texture-proposal, and promotion-proposal tools. PR #547 is merged and includes runtime visibility/hash binding. Do not recreate the old August implementation plan.
2. Main is dirty. It contains user changes to `tools/meshy_stage.py`, requirements/ADR files, the native extension, untracked biomass design files, and many generated/imported assets. Do not reset, stash, clean, mass-stage, or overwrite that checkout.
3. The uncommitted Meshy change raises `_GLB_MAX_BYTES` from 64 MiB to 128 MiB and `_DOWNLOAD_TOTAL_MAX_BYTES` from 80 MiB to 256 MiB. Preserve those exact chosen limits and formalize them with tests; do not silently revert them.
4. The selected loot task is `01a05dcb-fc3b-7418-b105-2170af354088`. Its evidence exists in the Meshy worktree, not main. It has `raw.glb`, `cleaned.glb`, and a Blender PASS report, but `review.json.state` is still `selected`; no task-local runtime report was found in that inventory. This is not promotion readiness.
5. Main contains historical `stalker_v1` batches: `1a2553d5068b4f069fcbbdb88db851c5` and `8b09cef0333541db8ae3781c8ea2b9a6` are FAILED; `a7089e88e2cf4cea90a0c4c2efc0df7b` is COMPLETED with four SUCCEEDED records. Do not submit a replacement batch. Preserve failed and completed evidence in place.
6. The accepted biomass branch replaces the draft's Blender-authored sockets, IK, and assembler autoload with repository/Godot socket authority, rigid socket-space gaits, and a per-manager assembler. Main's untracked draft is not the implementation specification.
7. The biomass plan has Tasks 0–15; Tasks 10–15 define unfinished asset-production work. Main does not yet contain the biomass runtime/tools. Integration and Task 9 review are dependencies, not permission to implement duplicate versions.
8. `docs/game/06_validation_plan.md` on main advertises a 633-command bundle but read-only parsing counted **651 actual `run_clean` registrations**. This is a confirmed count/marker defect, not an inferred failed runtime test. The biomass branch targets 658 after its seven additional registrations. Derive the number at the tested commit; never copy a stale total.
9. `docs/superpowers/proofs/meshy-blender-asset-system.md` and the AI feature/validation status paragraphs describe a pre-live-pilot snapshot. Preserve that historical evidence but add a current-state section; do not rewrite old test results as current results.
10. Focused-nine comparison proof explicitly says no promotion occurred. ithappy full-conversion proof still says Godot import is pending. Neither is proof that current imported art is usable in production.
11. Legacy `tools/batch_import_textured_tiles.py` defaults to writing beside live structural GLBs. `tools/synaptic_sea_gate4_regression.sh` points at an obsolete project/Godot and globally filters teardown warnings. Neither is an acceptable production shortcut.

### Source map for a zero-context implementer

| Concern | Exact authority / implementation |
|---|---|
| Repository operating rules | `AGENTS.md` |
| Meshy policy and ownership | `docs/game/features/ai_candidate_asset_pipeline.md`, `docs/game/adr/0058-meshy-candidates-blender-authority.md` |
| Generation schema and contract parsing | `tools/meshy_asset_contract.py`, `data/asset_generation/contracts/`, `data/asset_generation/meshy_pricing_v1.json` |
| Provider calls, journals, download limits | `tools/meshy_stage.py`, `tests/test_meshy_stage.py` |
| Safe publication and evidence | `tools/meshy_governance.py`, `tools/meshy_candidate_review.py` |
| Generic Blender master/validator | `tools/meshy_blender_master.py`, `tools/meshy_blender_validate.py` |
| Loot-specific authoring | `tools/meshy_loot_container_recipe.py`, `tests/test_meshy_loot_container_recipe.py` |
| Candidate runtime review | `tools/meshy_runtime_review.py`, `scripts/validation/meshy_asset_review_capture.gd` |
| Proposal-only promotion | `tools/meshy_promotion_packet.py` |
| Structural source authority | `tools/structural_source_contract.py`, `tools/validate_structural_sources.py` |
| Structural export/promotion | `tools/export_structural_glb.py`, `tools/promote_structural_sources.py`, `tools/validate_promoted_sources.py` |
| Focused-nine art and proofs | `tools/focused_nine_blender_recipes.py`, `tools/focused_nine_batch.py`, `tools/focused_nine_staged_derelict_preview.py`, `tools/focused_nine_airlock_control_room_preview.py` |
| Prop provenance and index | `tools/prop_visual_metadata.py`, `tools/generate_prop_sidecars.py`, `tools/validate_prop_visual_bindings.py` |
| External source backup | `tools/backup_structural_sources.py` |
| Current canonical regression | fenced bash under `## Regression bundle` in `docs/game/06_validation_plan.md` |
| Accepted biomass continuation | `docs/superpowers/plans/2026-09-02-procedural-biomass-threat-assembly.md` at `3823b9a7c8f50ccc43a15e3689d40a2e94b8cdc6` |

## 2. Locked decisions and non-goals

- Production is locked-isometric 3D, stylized low-poly, with silhouette readability at gameplay scale. Do not pivot to top-down, sprites, photorealistic gore, or a standalone model viewer.
- Structural grid spacing is 4.0 m. Contract dimensions for props are literal meters, not tile counts. Godot is +Y-up/+Z-forward; keep each existing exporter’s explicit Blender-coordinate conversion.
- Meshy generates candidates only. It does not own structural geometry, sockets, collision, navigation, damage topology, or behavior.
- Blender owns the editable visual master, deliberate cleanup, UVs, scale, pivot, visual state derivation and export. Godot/repository data own runtime sockets and gameplay.
- Closed/open/looted states derive from one loot master. No independently generated state variants.
- Generic `blender-validation.json.master_provenance` remains `null` by design. Master provenance belongs in the separately verified recipe record; do not extend a closed report with invented fields.
- Keep the standing Meshy subscription authorization. Credit values remain request-integrity fields, not a new human approval negotiation. Never repeat an ambiguous paid POST.
- Loot is the end-to-end calibration asset. Crafting is the subsequent static-prop check. Biomass replaces singular-threat production; historical stalker/tendril/swarm evidence remains auditable, not deleted or silently promoted.
- No generic orchestration framework, new asset database, alternate catalog, blanket auto-decimation, universal MCP dependency, or mandatory LoRA training.
- Generated indexes are derived. Never hand-edit `data/props/visual_bindings.generated.json` to make a check pass.
- Generation/refinement/review never mutate `assets/imported`, `data/combat`, `data/props`, or `scenes/wrappers`. Promotion is a separate explicit diff and validation gate.
- An image's existence or a tool's exit code is not visual approval. Capture generation, machine validation, and human/art review are distinct records.

## 3. Execution model

Each numbered checkbox is 2–5 minutes of focused operator work. Test runs, renders, imports, and provider polling may take longer elapsed time; launching and inspecting them are separate checkboxes. Never pretend a large Blender cleanup or a complete new subsystem takes five minutes: iterate a bounded edit, preview, compare, and decide.

For code changes: write the supplied regression first → run and observe the intended failure → implement the minimal change → run targeted and neighboring suites → review → commit only the named paths. If a regression is already green, inspect the existing implementation and close the task as already implemented rather than manufacture a failing assertion.

Independent lanes after baseline: provider integrity, structural/metadata evidence, and biomass continuation. Serialize edits to `tools/meshy_stage.py`, `tools/meshy_blender_validate.py`, `tools/meshy_promotion_packet.py`, `docs/game/05_requirements.md`, and `docs/game/06_validation_plan.md`. One integrator owns those hotspots. Discover live worker profiles before creating execution cards; do not reuse stale assignee names from `AGENTS.md` without checking.

## 4. Task A — Freeze a non-destructive baseline and reconcile ownership

**Files:** create `docs/superpowers/proofs/asset-pipeline-closure.md` during execution; no source edits in this task.

- [ ] A1. Read `AGENTS.md`, this plan, and the existing card threads. Query only asset/refinement/runtime-review cards; record current status, dependencies, source commit and evidence path. Close no cards from historical PASS prose.
- [ ] A2. Inspect the dirty checkout without changing it:

```bash
cd /Users/christopherwilloughby/Code/the-synaptic-sea
git diff --name-only
git diff -- tools/meshy_stage.py
git worktree list
git log -5 --oneline
```

Expected: the observed dirty files remain untouched; exact branch heads are recorded. If heads moved, compare the new diff before using any code block below.

- [ ] A3. Create the implementation worktree only during execution:

```bash
git worktree add -b fix/asset-pipeline-closure \
  /Users/christopherwilloughby/Code/the-synaptic-sea-asset-pipeline-closure \
  f4a656692606e23813df68d24daba4c5e4a0151b
cd /Users/christopherwilloughby/Code/the-synaptic-sea-asset-pipeline-closure
export PYTHON=/opt/homebrew/bin/python3.11
export GODOT=/opt/homebrew/bin/godot
export BLENDER=/opt/homebrew/bin/blender
export PYTHONPATH=.
export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
export PYTHONDONTWRITEBYTECODE=1
"$PYTHON" --version
"$GODOT" --version
"$BLENDER" --version
```

Expected: new clean branch; Python 3.11; Godot 4.7.1; working Blender. Do not replace the user's installed tools when a version differs—record the toolchain mismatch and resolve that dependency first.

- [ ] A4. Run the existing Python pipeline gate in the isolated worktree:

```bash
"$PYTHON" -m pytest -q -p no:cacheprovider \
  tests/test_meshy_asset_contract.py tests/test_meshy_stage.py \
  tests/test_meshy_governance.py tests/test_meshy_candidate_review.py \
  tests/test_meshy_blender_tools.py tests/test_meshy_loot_container_recipe.py \
  tests/test_meshy_texture_packet.py tests/test_meshy_promotion_packet.py \
  tests/test_meshy_runtime_review.py tests/test_prop_visual_metadata.py \
  tests/test_validate_prop_visual_bindings.py
```

Expected acceptance: zero failures/errors, and Blender-backed tests actually execute on this host. Initial baseline may be red; record exact node IDs and tracebacks, not the old 340/375-pass totals. A preexisting failure remains a required-path blocker until reproduced, assigned, fixed, and rerun.

- [ ] A5. Inventory asset evidence in main and the Meshy worktree. Hash and compare candidate `contract.json`, `generation.json`, `review.json`, raw/cleaned outputs and master receipts. Copy an existing task to the isolated worktree only as a complete verified evidence set; never combine one task's GLB with another task's records, and never regenerate missing raw evidence through Meshy.
- [ ] A6. Create the proof document with these literal sections, filling only observed values: `Tested commit`, `Toolchain`, `Dirty-source exclusions`, `Issue ledger`, `Evidence inventory`, `Commands and exit codes`, `Visual verdicts`, `Promotion diffs`, `Known blockers`. Every ledger row has `ID | requirement | source evidence | owner lane | state | closing test/evidence`.
- [ ] A7. Review the proof inventory and commit only it:

```bash
git add docs/superpowers/proofs/asset-pipeline-closure.md
git commit -m "docs: record asset pipeline closure baseline"
```

## 5. Task B — Formalize the existing Meshy size-limit fix

**Modify:** `tools/meshy_stage.py`.
**Create:** `tests/test_meshy_download_limits.py`.
**Requirement:** REQ-AIAP-004; preserve bounded download and paid-task identity.

- [ ] B1. Write this complete test file:

```python
from types import SimpleNamespace

import pytest

from tools import meshy_stage as stage


def test_download_limits_preserve_live_operator_fix():
    assert stage._GLB_MAX_BYTES == 128 * 1024 * 1024
    assert stage._THUMBNAIL_MAX_BYTES == 16 * 1024 * 1024
    assert stage._DOWNLOAD_TOTAL_MAX_BYTES == 256 * 1024 * 1024


@pytest.mark.parametrize("size", [0, 7, 8])
def test_download_accepts_bytes_up_to_bound_without_extra_request(size):
    calls = []
    payload = b"x" * size

    def download(url, maximum, remaining, clock):
        calls.append((url, maximum, remaining))
        return payload

    client = SimpleNamespace(download_bytes=download)
    preflight = SimpleNamespace(clock=lambda: 0.0, operation_deadline=10.0)
    assert stage._download_with_limit(client, "https://example.invalid/a", 8, preflight) == payload
    assert calls == [("https://example.invalid/a", 8, 10.0)]


def test_download_rejects_one_byte_over_bound_without_retry():
    calls = []

    def download(*args):
        calls.append(args)
        return b"x" * 9

    client = SimpleNamespace(download_bytes=download)
    preflight = SimpleNamespace(clock=lambda: 0.0, operation_deadline=10.0)
    with pytest.raises(RuntimeError, match="exceeds maximum size"):
        stage._download_with_limit(client, "https://example.invalid/a", 8, preflight)
    assert len(calls) == 1


def test_expired_download_does_not_call_client():
    def unexpected(*args):
        pytest.fail("expired operation reached download client")

    client = SimpleNamespace(download_bytes=unexpected)
    preflight = SimpleNamespace(clock=lambda: 10.0, operation_deadline=10.0)
    with pytest.raises(RuntimeError, match="deadline exceeded"):
        stage._download_with_limit(client, "https://example.invalid/a", 8, preflight)
```

These small payload tests prove boundary logic without allocating a 128 MiB fixture. Existing `tests/test_meshy_stage.py` remains responsible for HTTP streaming, journal recovery, and complete GLB validation; an empty download passing the byte-cap helper is not a valid GLB.

- [ ] B2. Run RED:

```bash
"$PYTHON" -m pytest -q tests/test_meshy_download_limits.py
```

Expected at the pinned committed baseline: `test_download_limits_preserve_live_operator_fix` fails because the old cap is 64 MiB; the other checks pass. A different failure is not the intended RED.

- [ ] B3. Replace only the existing three constants with:

```python
_GLB_MAX_BYTES = 128 * 1024 * 1024
_THUMBNAIL_MAX_BYTES = 16 * 1024 * 1024
_DOWNLOAD_TOTAL_MAX_BYTES = 256 * 1024 * 1024
```

Do not increase request/reference limits or alter retry behavior. Do not add cap overrides to the CLI.

- [ ] B4. Run GREEN:

```bash
"$PYTHON" -m pytest -q tests/test_meshy_download_limits.py tests/test_meshy_stage.py
```

Expected: zero failures/errors. No API client credentials or real provider calls are needed.

- [ ] B5. Review the two-file diff and commit:

```bash
git add tools/meshy_stage.py tests/test_meshy_download_limits.py
git commit -m "fix: retain bounded larger Meshy artifact downloads"
```

## 6. Task C — Make the obsolete regression entry point use the canonical bundle

**Modify:** `tools/synaptic_sea_gate4_regression.sh`, `docs/game/06_validation_plan.md` (final count marker only, before biomass integration).
**Create:** `tools/run_canonical_regression.py`, `tests/test_run_canonical_regression.py`.
**Why:** the old script's absolute paths and global warning suppression can provide misleading or unusable validation. Do not maintain a second list of smoke commands.

- [ ] C1. Write the complete test file:

```python
import pytest

from tools.run_canonical_regression import extract_bundle


def document(command_count=1, claimed_count=1):
    calls = "\n".join("run_clean 'case' 'PASS' true" for _ in range(command_count))
    return (
        "# Validation\n## Regression bundle\n\n```bash\nset -euo pipefail\n"
        + calls
        + "\necho 'SYNAPTIC_SEA REGRESSION PASS commands="
        + str(claimed_count)
        + " clean_output=true'\n```\n"
    )


def test_extract_preserves_exact_canonical_bytes():
    text = document()
    expected = text.split("```bash\n", 1)[1].split("\n```", 1)[0] + "\n"
    assert extract_bundle(text) == expected


def test_count_mismatch_is_not_a_pass():
    with pytest.raises(ValueError, match="count mismatch"):
        extract_bundle(document(command_count=2, claimed_count=1))


@pytest.mark.parametrize("text", ["", "## Regression bundle\n```bash\ntrue\n```\n"])
def test_missing_block_or_marker_fails_closed(text):
    with pytest.raises(ValueError):
        extract_bundle(text)


def test_duplicate_sections_fail_closed():
    with pytest.raises(ValueError, match="exactly one"):
        extract_bundle(document() + document())


def test_real_canonical_document_has_consistent_count():
    from pathlib import Path
    root = Path(__file__).resolve().parents[1]
    assert extract_bundle((root / "docs/game/06_validation_plan.md").read_text())
```

- [ ] C2. Run `"$PYTHON" -m pytest -q tests/test_run_canonical_regression.py`.
Expected RED: missing `tools.run_canonical_regression`.

- [ ] C3. Create `tools/run_canonical_regression.py` with:

```python
#!/usr/bin/env python3
"""Run the sole regression bundle owned by docs/game/06_validation_plan.md."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess


def extract_bundle(document: str) -> str:
    sections = re.findall(
        r"^## Regression bundle\s*\n(.*?)(?=^## |\Z)",
        document,
        flags=re.MULTILINE | re.DOTALL,
    )
    if len(sections) != 1:
        raise ValueError("expected exactly one Regression bundle section")
    blocks = re.findall(r"^```bash\n(.*?)^```\s*$", sections[0], re.MULTILINE | re.DOTALL)
    if len(blocks) != 1:
        raise ValueError("expected exactly one bash regression block")
    script = blocks[0]
    claimed = re.findall(r"SYNAPTIC_SEA REGRESSION PASS commands=(\d+) clean_output=true", script)
    if len(claimed) != 1:
        raise ValueError("expected exactly one regression count marker")
    actual = sum(line.lstrip().startswith("run_clean ") for line in script.splitlines())
    if actual < 1 or actual != int(claimed[0]):
        raise ValueError(f"regression count mismatch: registered={actual}, claimed={claimed[0]}")
    return script if script.endswith("\n") else script + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    root = args.project_root.resolve(strict=True)
    try:
        script = extract_bundle((root / "docs/game/06_validation_plan.md").read_text())
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    if args.check:
        print("CANONICAL REGRESSION MANIFEST PASS")
        return 0
    env = dict(os.environ)
    env["ROOT"] = str(root)
    if not env.get("GODOT"):
        parser.error("GODOT must name the verified Godot 4.7.1 executable")
    return subprocess.run(["/bin/bash", "-s"], input=script, text=True, cwd=root, env=env).returncode


if __name__ == "__main__":
    raise SystemExit(main())
```

This is a trusted repository-document runner, not a sandbox for untrusted Markdown. Run the full bundle as a supervised bounded job with a process-group watchdog; individual smokes and the existing canonical diagnostic policy remain unchanged. Do not add blanket suppression to make the runner green.

- [ ] C4. Replace `tools/synaptic_sea_gate4_regression.sh` completely with:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
PYTHON="${PYTHON:-python3}"
if [ "$#" -ne 0 ]; then
  printf '%s\n' 'Use shell redirection for logs; this entry point accepts no positional log directory.' >&2
  exit 2
fi
exec "$PYTHON" "$ROOT/tools/run_canonical_regression.py" --project-root "$ROOT"
```

At this pre-biomass baseline, also replace the exact final echo in `docs/game/06_validation_plan.md`:

```bash
echo 'SYNAPTIC_SEA REGRESSION PASS commands=651 clean_output=true'
```

It replaces `commands=633`; leave all 651 registrations intact. After biomass integration the same test must require the newly computed total, not force it back to 651.

The obsolete optional positional log-directory argument is deliberately rejected instead of silently ignored. Existing callers must use normal stdout/stderr capture. This task does not execute the full suite yet.

- [ ] C5. Run GREEN:

```bash
"$PYTHON" -m pytest -q tests/test_run_canonical_regression.py
"$PYTHON" tools/run_canonical_regression.py --project-root . --check
bash -n tools/synaptic_sea_gate4_regression.sh
```

Expected: tests pass, `CANONICAL REGRESSION MANIFEST PASS`, shell syntax exit 0. If the real document's count is inconsistent, fix its exact registration/count discrepancy, not the parser's equality check.

- [ ] C6. Commit the four named paths:

```bash
git add tools/synaptic_sea_gate4_regression.sh tools/run_canonical_regression.py tests/test_run_canonical_regression.py docs/game/06_validation_plan.md
git commit -m "fix: route legacy regression launcher to canonical gates"
```

## 7. Required closure ledger

The subsequent packets must close each of these outcomes; a rejected or superseded asset needs a recorded disposition, not a fabricated PASS.

| ID | Outstanding outcome | Closing evidence |
|---|---|---|
| AP-01 | Dirty/worktree/code/evidence convergence | frozen source diff, explicit integration lineage, clean isolated acceptance checkout |
| AP-02 | Uncommitted larger-download fix | Task B tests and neighboring staging suite |
| AP-03 | Legacy validation entry point drift | Task C tests plus real canonical bundle |
| AP-04 | Loot end-to-end review and refinement | exact selected task, reproducible master recipe, fresh Blender report, six runtime cases, explicit artistic verdict |
| AP-05 | Loot gameplay promotion is separate | reviewed live diff, collision/interaction/state behavior, save/load and rollback evidence |
| AP-06 | Historical singular-threat batches | immutable lifecycle disposition; no new generation or automatic promotion |
| AP-07 | Structural/ithappy/focused-nine status not current | complete current inventory, validated masters/variants, fresh real-room review, separate promotion decision |
| AP-08 | Prop sidecar/index and derived import integrity | provenance-preserving refresh, index validator and runtime loader smokes |
| AP-09 | Unsafe legacy texture outputs | staging-only writes or explicitly retired entry point; no production overwrite |
| AP-10 | Biomass Tasks 10–15 and branch integration | recipe/archive tools, proposals, eight references/plans, governed candidates, per-part review, final composite and playable pilot |
| AP-11 | External master durability | hash-verified backup and tested restore to a different temporary directory |
| AP-12 | Stale completion documentation | current evidence/limitations separated from historical snapshots; exact command counts |

## 8. Task D — Finish the existing loot-container pilot before generating anything else

**Inputs:** the selected task in the Meshy worktree; the canonical master at `/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/loot_container_derelict_v1_master.blend`.
**Outputs:** regenerated downstream evidence in the isolated worktree; current artistic verdict and proposal. No production writes.
**Requirements:** REQ-AIAP-004 through REQ-AIAP-009.

- [ ] D1. Recover only immutable candidate inputs and the selected review into the isolated workspace. Use this exact execution-only script. It fails rather than overwriting existing work:

```bash
"$PYTHON" - <<'PY'
from pathlib import Path
import hashlib
import shutil

source = Path('/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/meshy-blender-asset-system/assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088')
target = Path('assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088')
leaves = ('contract.json', 'generation.json', 'pricing.json', 'prompt-packet.json',
          'review.json', 'raw.glb', 'thumbnail.png', 'source_front.png',
          'source_side.png', 'source_back.png', 'source_three_quarter.png')
assert not target.exists(), 'existing task must be verified, never overwritten'
for name in leaves:
    p = source / name
    assert p.is_file() and not p.is_symlink(), name
    assert all(not parent.is_symlink() for parent in p.parents), name
target.mkdir(parents=True, mode=0o700)
for name in leaves:
    shutil.copy2(source / name, target / name)
    (target / name).chmod(0o600)
    assert hashlib.sha256((source / name).read_bytes()).digest() == hashlib.sha256((target / name).read_bytes()).digest()
print('LOOT INPUT RECOVERY PASS files=11 downstream_evidence_not_copied=true')
PY
```

If interrupted, do not rerun over partial output. Compare every existing leaf to its source; complete only missing byte-identical inputs after review. Original source evidence is untouched. Do not copy the stale validation report or edit any `generation.json` field.

- [ ] D2. Pin the actual selected task and existing matching recipe baseline:

```bash
export ASSET_ID=loot_container_derelict_v1
export TASK_ID=01a05dcb-fc3b-7418-b105-2170af354088
export TASK_DIR="assets/_staging/meshy/$ASSET_ID/$TASK_ID"
export CONTRACT="data/asset_generation/contracts/$ASSET_ID.json"
export EVIDENCE_DIR=/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/loot_container_derelict_v1/selected_01a05dcb_master_0244e568/task3_86012634_3ce35e2f/run-1
"$PYTHON" tools/meshy_candidate_review.py verify --project-root . --task-dir "$TASK_DIR"
```

The current source `build_recipe_manifest.json` had SHA-256 `0bb2dc885e98d4e6cce9bd82bdca0269f37fb457f8ffec2807d45e84bd77aa93`; the named evidence directory had byte-identical manifest content. Recheck before use. A directory name containing a commit is not proof of approval. Inspect the four images and the latest user/art-review decision before publishing cleaned bytes.

- [ ] D3. Review the existing `closed.png`, `open.png`, `looted.png`, and `states_contact_sheet.png` from that exact directory. Required design: hollow container body; genuinely separate lid; back-edge X-axis hinge opening 105 degrees; handle that reads as usable, not a floating bar; two readable latch assemblies; loot visible only before the looted state; no self-intersection through the body during opening. Dimensions are exactly the contract's `[0.9, 0.55, 0.65]` within tolerance, with at most two materials and 3,000 contract triangles. The existing recipe's tighter 1,500-triangle design gate must remain intact.
- [ ] D4. If the preview needs refinement, alter only the corresponding builder in `tools/meshy_loot_container_recipe.py`: `_build_body`, `_build_lid`, `_build_handle`, `_build_accents`, or `_build_animation`. One edit per iteration; no generic remesh/decimate pass. Start by adding the failing behavioral assertion to `tests/test_meshy_loot_container_recipe.py`, then run that file RED, make the specific geometry/animation edit, run GREEN, and obtain a new preview decision. Do not modify the source/master merely to satisfy a screenshot hash. Existing manifest and reproduction tests specify the exact object/state/material interface.
- [ ] D5. If the existing approved recipe is acceptable, regenerate cleaned output using it, not the generic master creator:

```bash
"$PYTHON" tools/meshy_loot_container_recipe.py --project-root . \
  --contract "$CONTRACT" --task-dir "$TASK_DIR" \
  --evidence-dir "$EVIDENCE_DIR" --mode publish-cleaned
"$PYTHON" tools/meshy_blender_validate.py --project-root . \
  --contract "$CONTRACT" --task-dir "$TASK_DIR" \
  --glb "$TASK_DIR/cleaned.glb" --report "$TASK_DIR/blender-validation.json"
```

Expected: recipe reproduction passes; a complete cleaned GLB is published; `MESHY BLENDER VALIDATION PASS`; selected task/hash/contract, transforms, UVs, triangle/material limits and hinge samples validate. If reproduction differs, stop and inspect the actual difference. Do not bless new output by manually changing recorded hashes.

- [ ] D6. Run the existing real-runtime review:

```bash
"$PYTHON" tools/meshy_runtime_review.py --project-root . \
  --contract "$CONTRACT" --task-dir "$TASK_DIR" \
  --preview-dir artifacts/validation-previews/meshy/loot_container_derelict_v1
"$PYTHON" tools/meshy_candidate_review.py verify --project-root . --task-dir "$TASK_DIR"
```

Expected exact summary:

```text
MESHY RUNTIME REVIEW PASS asset=loot_container_derelict_v1 task_id=01a05dcb-fc3b-7418-b105-2170af354088 seeds=42,777 lighting=normal,emergency,dark captures=6
```

Each case has contextual, staged-only and reference PNGs: 18 PNGs for six cases, plus the runtime report. Require 1600×900, current hash-bound camera/visibility evidence, and no unexpected `ERROR:`, `WARNING:` or `SCRIPT ERROR:`. The runner must bind `promotion_ready`; the subsequent candidate command is verify-only. Never use `bind` to manufacture missing runtime evidence.

- [ ] D7. Inspect all six contextual captures at native size. Pass only if the closed silhouette and interaction-facing details remain understandable in normal/emergency lighting, dark mode remains intentionally readable under the production lighting policy, the prop is not hidden by the cutaway or floating, and it belongs visually with the room. A diagnostic mask or isolated staged image cannot substitute for this decision. Record reviewer, exact report hash, verdict and specific failed criterion when rejected.
- [ ] D8. Produce the proposal only:

```bash
"$PYTHON" tools/meshy_promotion_packet.py prop --project-root . \
  --task-dir "$TASK_DIR" \
  --target-path res://assets/imported/props/dressing/loot_container_derelict_v1.sidecar.json
```

Expected: task-local `sidecar-overlay.json`, `proposal_only: true`, valid AI provenance, zero writes to live runtime paths. A new sidecar overlay is not a complete gameplay binding and must not be applied blindly.
- [ ] D9. Commit the exact reviewed source/test changes (if any), selected JSON evidence, and `docs/superpowers/proofs/asset-pipeline-closure.md`. Inspect `git diff --cached --name-only` first; reject secrets, raw binaries, temporary `.import` churn, unselected candidates, or unrelated files. Use commit message `art: verify selected loot container through runtime review` only after D6 and D7 actually pass.

## 9. Task E — Reconcile source durability, structural variants, and metadata

**Existing tools, not a new framework:** `tools/backup_structural_sources.py`, `tools/validate_structural_sources.py`, `tools/validate_structural_variant_bindings.py`, `tools/focused_nine_batch.py`, `tools/generate_prop_sidecars.py`, `tools/validate_prop_visual_bindings.py`.

- [ ] E1. Enumerate the authoritative 15 structural IDs from `tools/structural_source_contract.py`; enumerate the focused-nine inventory from `tools/focused_nine_contract.py`; enumerate imported ithappy files with Python. Record missing, duplicate, orphan and untracked evidence separately. Never repeat the old proof's `1,084` or `15/15` without counting the actual target inventory.
- [ ] E2. Validate all external structural masters:

```bash
"$PYTHON" tools/validate_structural_sources.py --project-root . \
  --source-root /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0 --all
"$PYTHON" -m pytest -q \
  tests/test_structural_source_contract.py tests/test_validate_structural_sources.py \
  tests/test_export_structural_glb.py tests/test_promote_structural_sources.py \
  tests/test_backup_structural_sources.py tests/test_validate_structural_variant_bindings.py
```

Expected: every required source validates and no suite failures/errors. Missing external masters are recovery work; they are not a reason to overwrite known good masters with imported primitives. Existing structural wrappers remain collision/socket authority.
- [ ] E3. Before editing any master, create a hash-verified backup outside its source directory. `BACKUP_TARGET` must name a real available independent destination; do not invent an S3 bucket or treat a sibling directory on the same disk as disaster recovery.

```bash
: "${BACKUP_TARGET:?set the verified backup destination}"
"$PYTHON" tools/backup_structural_sources.py \
  --source-root /Volumes/Untitled/SynapticSeaAssets/meshes/source \
  --backup-target "$BACKUP_TARGET" --dry-run
"$PYTHON" tools/backup_structural_sources.py \
  --source-root /Volumes/Untitled/SynapticSeaAssets/meshes/source \
  --backup-target "$BACKUP_TARGET"
```

Repeat for `/Volumes/Untitled/SynapticSeaAssets/meshy/source` with a distinct target subtree. Verify file hashes and restore one structural master and the loot master to a new temporary directory; open each restored copy in Blender and validate its expected object/collection inventory. A successful upload is insufficient. If no independent destination is available, record that explicit durability blocker; local checkpoints still precede editing.
- [ ] E4. Run prop metadata checks before attempting any repair:

```bash
"$PYTHON" tools/generate_prop_sidecars.py --project-root . --check
"$PYTHON" tools/validate_prop_visual_bindings.py --project-root . --check-index
"$PYTHON" -m pytest -q tests/test_prop_visual_metadata.py tests/test_validate_prop_visual_bindings.py
```

Expected acceptance: exit 0 and no `ERROR:` lines. For each failing sidecar, distinguish missing source bytes from stale derived SHA/size/bounds and from invalid authored bindings/rights. Recover bytes first. Use the existing scoped `--asset-id` refresh only for that asset; preserve authored provenance/extensions/bindings, and rebuild the index with `--write-index` after reviewing all authored changes. Never mark a paid/AI asset self-authored.
- [ ] E5. For a derived-only stale sidecar, the exact execution pattern is:

```bash
: "${ASSET_ID:?set the failing sidecar's exact existing asset_id}"
"$PYTHON" tools/generate_prop_sidecars.py --project-root . --refresh-derived --asset-id "$ASSET_ID"
"$PYTHON" tools/generate_prop_sidecars.py --project-root . --write-index
"$PYTHON" tools/validate_prop_visual_bindings.py --project-root . --check-index
```

Before committing, compare the authored `bindings`, `placement`, `provenance`, and `extensions` subtrees before/after; they must remain byte-equivalent after canonical JSON serialization. If any changed, stop and investigate; do not accept a regenerated-but-different authored record.
- [ ] E6. Run the focused-nine test suite before regenerating previews:

```bash
"$PYTHON" -m pytest -q \
  tests/test_focused_nine_contract.py tests/test_focused_nine_blender_recipes.py \
  tests/test_focused_nine_staged_structural.py tests/test_focused_nine_staged_props.py \
  tests/test_focused_nine_batch.py tests/test_focused_nine_evidence.py \
  tests/test_focused_nine_comparison_capture.py \
  tests/test_focused_nine_staged_derelict_preview.py \
  tests/test_focused_nine_airlock_control_room_preview.py \
  tests/test_focused_nine_airlock_control_room_capture.py
```

Expected: zero failures/errors. Do not convert a rejected diagnostic into an allowlist entry just because an older proof had a PASS.
- [ ] E7. Pin structural and prop source roots from the existing focused-nine report/source manifests; fail if the named files are absent. Run the existing batch with its verified external roots:

```bash
: "${FOCUSED_STRUCTURAL_ROOT:?set verified focused-nine external structural source root}"
: "${FOCUSED_PROPS_ROOT:?set verified focused-nine external prop source root}"
"$PYTHON" tools/focused_nine_batch.py --project-root . \
  --structural-source-root "$FOCUSED_STRUCTURAL_ROOT" \
  --validation-structural-source-root /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0 \
  --props-source-root "$FOCUSED_PROPS_ROOT" \
  --report assets/_staging/focused_nine/focused-nine-comparison.json \
  --preview-dir artifacts/validation-previews/focused-nine
```

Expected: `FOCUSED_NINE_BATCH PASS assets=9` and unchanged protected runtime surfaces. Existing immutable reports are verified/recovered rather than silently overwritten. Use a clean isolated checkout for a fresh run.
- [ ] E8. Review one complete production-style room before any batch restyling: readable traversal, aligned seams, no coplanar floor/wall overlap, correct doorway clearance, no hovering props, no wall/cutaway occlusion of interaction targets, and functional pressure-door intact/damaged/breached states. Compare ithappy and focused-nine as separate candidates; do not create a patchwork style by picking individual materials without the room comparison.
- [ ] E9. For each module that fails the room rubric, make one bounded Blender/source-recipe change, export to staging, run its source/variant gate, re-render the same camera/seed, and compare before/after. Accept or reject that change before touching another module. Structural coordinates, footprint, sockets and collision do not change in an art-refinement packet.
- [ ] E10. Update `docs/superpowers/proofs/ithappy-full-conversion.md`, `docs/superpowers/proofs/focused-nine-comparison.md`, and the closure proof with current inventory and review status. Preserve historical snapshots. Commit only intentional source/sidecar/index/proof changes, one issue per commit.

## 10. Task F — Keep optional material tooling from bypassing staging

Legacy tools are not authorized production publishers. Preserve their useful generation functionality, but require explicit isolated output destinations in all operator commands. Until the staging-boundary regression below is implemented, do not run their default write mode.

**Modify:** `tools/batch_import_textured_tiles.py`.
**Create:** `tests/test_textured_tile_output_boundary.py`.

- [ ] F1. Write these complete tests:

```python
from pathlib import Path

import pytest

from tools import batch_import_textured_tiles as batch


def test_default_output_is_staged_not_next_to_live_source(tmp_path, monkeypatch):
    monkeypatch.setattr(batch, "PROJECT_ROOT", tmp_path)
    live = tmp_path / "assets/imported/structural/ship_structural_v0"
    expected = tmp_path / "assets/_staging/textured_structural/floor_1x1/floor_1x1_textured.glb"
    assert batch.output_glb(live, None, "floor_1x1") == expected


def test_explicit_production_output_is_rejected(tmp_path, monkeypatch):
    monkeypatch.setattr(batch, "PROJECT_ROOT", tmp_path)
    with pytest.raises(ValueError, match="staging"):
        batch.output_glb(tmp_path / "source", tmp_path / "assets/imported", "floor_1x1")


def test_symlinked_staging_root_is_rejected(tmp_path, monkeypatch):
    monkeypatch.setattr(batch, "PROJECT_ROOT", tmp_path)
    (tmp_path / "assets").mkdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    (tmp_path / "assets/_staging").symlink_to(outside, target_is_directory=True)
    with pytest.raises(ValueError, match="symlink"):
        batch.output_glb(tmp_path / "source", None, "floor_1x1")


def test_invalid_module_does_not_escape_staging(tmp_path, monkeypatch):
    monkeypatch.setattr(batch, "PROJECT_ROOT", tmp_path)
    with pytest.raises(ValueError, match="module"):
        batch.output_glb(tmp_path / "source", None, "../../escape")
```

- [ ] F2. Run `"$PYTHON" -m pytest -q tests/test_textured_tile_output_boundary.py`. Expected RED: current output goes beside the live source and invalid destinations are accepted.
- [ ] F3. Replace `output_glb` in `tools/batch_import_textured_tiles.py` with this complete function:

```python
def output_glb(module_dir: Path, output_dir: Path | None, module_id: str) -> Path:
    """Choose a preview-only output; promotion is owned by separate tools."""
    if module_id not in MODULE_IDS:
        raise ValueError("unknown structural module")
    root = PROJECT_ROOT.absolute()
    staging = root / "assets/_staging/textured_structural"
    destination_root = staging if output_dir is None else Path(output_dir).expanduser()
    if not destination_root.is_absolute():
        destination_root = root / destination_root
    destination = Path(os.path.abspath(destination_root / module_id / f"{module_id}_textured.glb"))
    try:
        destination.relative_to(staging)
    except ValueError as exc:
        raise ValueError("textured output must stay inside textured_structural staging") from exc
    for path in (staging, destination):
        for component in (path, *path.parents):
            if component.is_symlink():
                raise ValueError("textured staging output contains a symlink")
    if destination.exists():
        raise ValueError("textured staging output already exists; use a fresh revision directory")
    return destination
```

This guard assumes a trusted local workspace and does not claim protection against a malicious same-UID race. Reuse the existing governed/transactional promotion tools for production writes. Do not elevate this preview helper into a new publisher.
- [ ] F4. Replace the module docstring's production-output instructions with literal text:

```text
By default exports are written under assets/_staging/textured_structural.
--output-dir must remain inside that staging tree. Existing output leaves are
not overwritten. Use a fresh revision subdirectory for another iteration.
This tool creates preview candidates only; it never promotes runtime assets.
```

- [ ] F5. Run GREEN: `"$PYTHON" -m pytest -q tests/test_textured_tile_output_boundary.py`, then `"$PYTHON" tools/batch_import_textured_tiles.py --dry-run`. Expected: tests pass; every planned output is staged or explicitly skipped for missing input, never under `assets/imported`. A missing Blender/texture is an input blocker, not a reason to default back to production.
- [ ] F6. Commit:

```bash
git add tools/batch_import_textured_tiles.py tests/test_textured_tile_output_boundary.py
git commit -m "fix: confine legacy textured previews to staging"
```

### Task F7 — Close the direct Blender-export bypass

**Modify:** `tools/apply_tile_texture.py`, `tests/test_textured_tile_output_boundary.py`.

- [ ] Add this failing test to `tests/test_textured_tile_output_boundary.py`:

```python
def test_direct_export_rejects_live_path_before_blender(tmp_path, monkeypatch):
    from tools import apply_tile_texture as texture
    monkeypatch.setattr(batch, "PROJECT_ROOT", tmp_path)
    monkeypatch.setattr(texture, "PROJECT_ROOT", tmp_path)
    monkeypatch.setattr(texture, "require_blender", lambda: pytest.fail("reached Blender before path rejection"))
    live = tmp_path / "assets/imported/floor_1x1/floor_1x1_textured.glb"
    with pytest.raises(ValueError, match="staging"):
        texture.export_glb(live)
    assert not live.exists()
```

- [ ] Run `"$PYTHON" -m pytest -q tests/test_textured_tile_output_boundary.py`. Expected RED: the direct exporter reaches `require_blender` before any boundary check.
- [ ] Add this complete helper before `export_glb` in `tools/apply_tile_texture.py`:

```python
def staged_output_path(output_path: Path) -> Path:
    if str(PROJECT_ROOT) not in sys.path:
        sys.path.insert(0, str(PROJECT_ROOT))
    from tools.batch_import_textured_tiles import output_glb
    candidate = resolve_project_path(output_path).absolute()
    expected = output_glb(PROJECT_ROOT, candidate.parent.parent, candidate.parent.name)
    if candidate != expected:
        raise ValueError("staging output must use the canonical module filename")
    return expected
```

- [ ] In `export_glb`, insert `output_path = staged_output_path(output_path)` immediately before `require_blender()`. In `main`, replace `output_path = resolve_project_path(args.output)` with `output_path = staged_output_path(resolve_project_path(args.output))`. Add `ValueError` to the final `except (FileNotFoundError, RuntimeError)` tuple. These are the only behavior edits; do not change material creation or exporter flags.
- [ ] Replace the usage example's output path with `assets/_staging/textured_structural/floor_1x1/floor_1x1_textured.glb`.
- [ ] Run GREEN: `"$PYTHON" -m pytest -q tests/test_textured_tile_output_boundary.py`.
- [ ] Commit:

```bash
git add tools/apply_tile_texture.py tests/test_textured_tile_output_boundary.py
git commit -m "fix: reject direct texture export into runtime assets"
```

### Optional texture/LoRA route disposition

- `tools/comfyui_tile_workflow.py`, `tools/batch_generate_tiles.py`, `tools/inpaint_tile_edges.py`, `tools/apply_tile_texture.py`, `tools/prepare_lora_dataset.py`, and `tools/train_lora.sh` remain optional experiments. No primary closure gate depends on ComfyUI or training availability.
- Do not invoke `tools/apply_tile_texture.py` directly against a runtime path. The batch tool above is the allowed operator entry point. Existing direct-write examples must be changed to staging paths before that workflow is documented as supported.
- Do not train the current raw image directory indiscriminately. It contains depth/canny/edge/test intermediates and historical aesthetic experiments. Use a curated image manifest with rights and exclusions if this optional route is chosen; mask/depth renders are conditioning inputs, not beauty-training examples.
- Choose manual Blender materials for the first accepted loot/room/biomass pilot. This is an explicit YAGNI decision, not a claim that optional LoRA quality is solved.

## 11. Task G — Integrate the reviewed biomass foundation, not the stale draft

**Exact upstream implementation:** `feature/procedural-biomass-threat-assembly` at `3823b9a7c8f50ccc43a15e3689d40a2e94b8cdc6`.
**Exact continuation specification:** `docs/superpowers/plans/2026-09-02-procedural-biomass-threat-assembly.md` at that revision; SHA-256 `b7d89b3724bcb97468507d2f480aaaea97dcb046246968e4908d63e57b075bfc`.

This existing specification is incorporated by immutable revision, not by whichever untracked draft happens to be on main. Its Tasks 0–9 are an integration/review lane; Tasks 10–15 are the remaining biomass asset-production lane. Do not reopen settled schema/architecture choices or execute the old singular-threat roadmap in parallel.

- [ ] G1. Read the exact source plan and its proof from the biomass worktree. Verify its SHA before delegating continuation:

```bash
"$PYTHON" - <<'PY'
import hashlib
import subprocess
ref = '3823b9a7c8f50ccc43a15e3689d40a2e94b8cdc6'
path = 'docs/superpowers/plans/2026-09-02-procedural-biomass-threat-assembly.md'
body = subprocess.check_output(['git', 'show', ref + ':' + path])
assert hashlib.sha256(body).hexdigest() == 'b7d89b3724bcb97468507d2f480aaaea97dcb046246968e4908d63e57b075bfc'
print('BIOMASS CONTINUATION SPEC IDENTITY PASS')
PY
```

- [ ] G2. Reconcile Tasks 5–9's implementation and review cards. A paused review is not permission to merge. A stale blocked execution card is not evidence that already-committed code must be reimplemented. Obtain the existing review decision or run a fresh independent review of the exact diff, then use the board's existing dependencies instead of duplicate cards.
- [ ] G3. Once that foundation is approved, merge it into the isolated integration branch with a reviewable merge commit, not by copying its entire worktree:

```bash
git merge --no-ff --no-commit 3823b9a7c8f50ccc43a15e3689d40a2e94b8cdc6
git diff --cached --stat
git diff --check
```

Expected: all conflicts are explicitly reconciled, and the new Meshy/runtime fixes plus the 128/256 MiB limit policy remain. Do not blindly take `--ours`/`--theirs` on validators, requirements, native binaries, or the regression document. Do not commit until G4 passes.
- [ ] G4. Use the branch's exact native-extension build provenance. Do not copy the dirty main `.dylib` into the integration tree to turn a smoke green. Run:

```bash
"$PYTHON" -m pytest -q tests/test_biomass_catalog_validate.py tests/test_biomass_composite_review.py
"$PYTHON" tools/biomass_catalog_validate.py --project-root . \
  --parts data/combat/biomass_part_catalog.json \
  --recipes data/combat/biomass_recipe_catalog.json
"$GODOT" --headless --path . --script res://scripts/validation/biomass_catalog_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/biomass_recipe_generator_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/biomass_wrapper_authority_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/biomass_assembly_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/biomass_threat_manager_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/biomass_revisit_persistence_smoke.gd
"$PYTHON" tools/run_canonical_regression.py --project-root . --check
```

Expected: `BIOMASS CATALOG VALIDATION PASS parts=8 recipes=5 archetypes=6`; generator marker `BIOMASS GENERATOR PASS seeds=100 distinct=100 hints=5`; assembly emits its assembly marker and `BIOMASS GAIT PASS recipes=5 profiles=5 deterministic=true bounded=true rest=true drift=false`; all other smokes emit the exact markers registered in the branch validation document, no unexpected diagnostics. The mechanically counted bundle must match its final marker (658 at the adopted Task 9 snapshot).
- [ ] G5. Verify the existing placeholder composite with `"$PYTHON" tools/biomass_composite_review.py verify --project-root . --report artifacts/validation-previews/biomass-assembly-placeholder/review.json`. Require all 30 cases and their current source/fixture identities; recover missing ignored images from verified archives, never fabricate a manifest or suppress permission/hash errors.
- [ ] G6. Review and commit the merge with `git commit -m "merge: integrate reviewed biomass foundation with asset closure fixes"`. Record the actual resulting commit in the closure ledger.
- [ ] G7. Apply the branch's existing lifecycle manifest to the historical `stalker_v1`, `hull_tendril_kit_v1`, and `biomatter_swarm_kit_v1` contracts. Preserve those files and provider evidence byte-for-byte. They are superseded production routes, not failed assets to regenerate. Tests must reject new paid generation through retired production contracts while allowing offline historical verification/reconciliation as specified by the existing lifecycle policy.

## 12. Task H — Complete the biomass asset-production continuation

Do not dispatch this packet until G is green. Execute the six adopted work packages in their existing order, but split the work into the bite-sized units below. Every code unit uses RED → minimal implementation → GREEN → spec review → quality review → its own scoped commit. The pinned source plan supplies the exact closed manifests and cross-record ownership matrix; this plan does not replace them with a looser generic record.

### H0. Fixed inventory and interfaces

The exact active part IDs are:

```text
biomass_human_arm_v1
biomass_insect_leg_v1
biomass_cephalopod_tentacle_v1
biomass_animal_skull_v1
biomass_humanoid_torso_v1
biomass_gunk_connector_v1
biomass_claw_v1
biomass_maw_v1
```

All eight part contracts are at `data/asset_generation/contracts/<asset_id>.json`; the catalog is `data/combat/biomass_part_catalog.json`. The five recipes are `biped_puppet_v1`, `four_legged_scrambler_v1`, `tripod_hound_v1`, `intestinal_dragger_v1`, and `tendril_knot_v1`. Preserve the six archetype pools. Keep the schema's 30,000-triangle hard limit distinct from the final visual-review 24,000-triangle cap; do not silently change either.

### H1. Archive and restore selected raw inputs (adopted Task 10, first slice)

**Create:** `tools/meshy_biomass_part_recipe.py`, `tests/test_meshy_biomass_part_recipe.py`.

- [ ] Add host-import tests proving no `bpy` import, exact public root enforcement and rejection of symlinks, traversal, wrong asset/task/catalog IDs and differing existing leaves.
- [ ] Implement only `RecipePaths` and the exact `resolve_recipe_paths(project_root, contract_path, catalog_path, expected_part_catalog_sha256, task_dir, evidence_dir, mode)` interface from the pinned plan. Production roots are fixed; only the private test seam may inject roots.
- [ ] Add RED tests for `archive-raw` and `rehydrate-raw`: generation owns task/raw hash/size; source archive preserves bytes; existing identical files are idempotent; mismatches fail without overwrite; neither mode calls Blender or Meshy.
- [ ] Implement those two modes using the existing governed atomic-writer primitives, restrictive permissions and compensating cleanup of only newly created hash-matching leaves. A manifest-write failure must not leave a falsely complete raw archive.
- [ ] Run `"$PYTHON" -m pytest -q tests/test_meshy_biomass_part_recipe.py`; expected zero failures/errors and zero paid/client invocations. Commit only these two files with `feat: archive and restore governed biomass raw inputs`.

### H2. Preview, approval and cleaned publication (remaining adopted Task 10)

**Modify:** the same two files; no runtime paths.

- [ ] Implement and test each closed loader separately: `load_source_raw_manifest`, `load_preview_manifest`, `load_preview_approval`, and `load_recipe_manifest`. Each has duplicate-key, malformed UTF-8, size/depth, non-finite scalar, unknown/missing nested field, wrong type and defensive-return tests. Use the exact field tables in the pinned Task 10, not invented optional fields.
- [ ] Add the normalization regression and implementation below as a complete small TDD unit; create `tests/test_biomass_triangle_limits.py`:

```python
from types import SimpleNamespace
import pytest
from tools.meshy_biomass_part_recipe import BiomassRecipeError, triangle_limits


@pytest.mark.parametrize("budget", [2500, {"min": 100, "max": 2500}])
def test_triangle_limits_keep_target_and_hard_cap_distinct(budget):
    contract = SimpleNamespace(document={"generation": {"target_polycount": 1500}, "budget": {"triangles": budget}})
    assert triangle_limits(contract) == (1500, 2500)


@pytest.mark.parametrize("target,hard", [(True, 2500), (1500, True), (0, 2500), (2501, 2500)])
def test_triangle_limits_reject_invalid_values(target, hard):
    contract = SimpleNamespace(document={"generation": {"target_polycount": target}, "budget": {"triangles": {"max": hard}}})
    with pytest.raises(BiomassRecipeError):
        triangle_limits(contract)
```

Run RED with `"$PYTHON" -m pytest -q tests/test_biomass_triangle_limits.py`, then add to `tools/meshy_biomass_part_recipe.py`:

```python
class BiomassRecipeError(ValueError):
    """An authored biomass recipe or its evidence violates the contract."""


def triangle_limits(contract):
    document = contract.document
    target = document["generation"]["target_polycount"]
    budget = document["budget"]["triangles"]
    hard_max = budget if isinstance(budget, int) and not isinstance(budget, bool) else budget["max"]
    if not isinstance(target, int) or isinstance(target, bool) or not isinstance(hard_max, int) or isinstance(hard_max, bool):
        raise BiomassRecipeError("triangle target/hard maximum must be integers")
    if target < 1 or hard_max < target:
        raise BiomassRecipeError("triangle target must be within hard maximum")
    return target, hard_max
```

If `BiomassRecipeError` already exists from H1, reuse it rather than redeclare it. Preserve the pinned Task 10 public annotation `triangle_limits(contract: AssetContract) -> tuple[int, int]` when inserting this body into the module; the `AssetContract` import is already required by H1.

- [ ] Run GREEN for both recipe files and commit this normalization unit.
- [ ] Add the Blender preview test using the exact private `RecipeRoots` seam and a synthetic mesh/master. Require raw preservation, exact meter dimensions/pivot, at most two materials, UV0, and no exported helpers/sockets/collision/skins. Run RED before implementing preview.
- [ ] Implement preview-only guide construction from the catalog, never from guessed Blender socket locations. Export only the selected cleaned visual geometry; keep `SOURCE_RAW` and `SOCKET_GUIDES` excluded. Generate the five exact images: `front.png`, `side.png`, `three_quarter.png`, `socket_overlay.png`, `contact_sheet.png`.
- [ ] Add RED approval tests for changed master, catalog, raw, preview GLB and any render. Implement `approve-preview` as a no-Blender/no-provider immutable approval record binding the exact preview baseline and reviewer.
- [ ] Add RED publish tests for a changed approved baseline and injected failure after each coupled leaf. Implement `publish-cleaned` as private reproduction plus exact approved-baseline comparison, then all-or-none task-local cleaned GLB and recipe publication.
- [ ] Run `"$PYTHON" -m pytest -q tests/test_meshy_biomass_part_recipe.py tests/test_biomass_triangle_limits.py tests/test_meshy_blender_tools.py tests/test_meshy_candidate_review.py`. Blender absence may skip the real-host probe only on a host without Blender; the acceptance host must run it. Commit the reviewed recipe/test changes with `feat: review and publish canonical biomass visual masters`.

### H3. Biomass proposal envelopes (adopted Task 11)

**Modify:** `tools/meshy_promotion_packet.py`, `tests/test_meshy_promotion_packet.py`.

- [ ] Add one RED case per cross-record owner: generation→raw/task; source archive→generation/raw; recipe→master/catalog/approval/cleaned; Blender→cleaned; runtime→Blender/cleaned/captures. Never demand master/catalog fields from the closed generic Blender report.
- [ ] Add the `biomass-part` subcommand beside existing `prop` and `threat` with exactly these options: `--project-root`, `--contract`, `--task-dir`, `--evidence-dir`, `--part-catalog`, `--expected-part-catalog-sha256`.
- [ ] Implement the pinned `build_biomass_part_promotion_proposal(...)` and `write_biomass_part_promotion_proposal(...)` using existing `_verified_task` and governance. Output only `biomass_part_catalog.patch.json`, `biomass_wrapper.proposal.json`, and `asset-provenance.json` under the selected task.
- [ ] Keep targets exact: `res://assets/imported/threats/biomass/<asset_id>.glb`, `res://scenes/wrappers/biomass/<asset_id>.tscn`, and `res://data/combat/biomass_part_catalog.json`. Catalog patch changes only that part's `wrapper_scene_path`; do not change sockets/roles/collision/budgets.
- [ ] Test all-or-none publication and byte-identical idempotence, unknown options, existing `prop`/`threat` compatibility, protected-path snapshots and secret rejection. Run `"$PYTHON" -m pytest -q tests/test_meshy_promotion_packet.py tests/test_meshy_governance.py tests/test_meshy_candidate_review.py tests/test_meshy_runtime_review.py tests/test_meshy_blender_tools.py`; expected zero failures/errors. Commit only the two named paths with `feat: propose governed biomass part promotion`.

### H4. References and read-only plans (adopted Task 12)

**Create:** `tools/biomass_reference_audit.py`, `tests/test_biomass_reference_audit.py`, the eight exact `assets/_staging/meshy/<asset_id>/_references/three_quarter.png` files, eight `_plans/<asset_id>.json` files and `_plans/biomass_reference_audit.json`.
**Modify:** `.gitignore`, `docs/superpowers/proofs/procedural-biomass-pilot.md`.

- [ ] Use these fixed art instructions for each part: isolated single connected stylized low-poly part; broad readable masses; neutral opaque gray background; orthographic three-quarter view; no collage, text, floor shadow, photorealistic gore or disconnected ornament. Preserve generous catalog attachment-clearance regions. The part contract supplies dimensions, species and category; do not substitute a full creature image.
- [ ] Write audit tests before implementing the audit: PNG decode, at least 1024×1024, opaque pixels, less than 16 MiB, unique bytes, regular non-symlink files, project-owned rights, one central foreground component containing at least 90% of foreground, no second component at least 5%, and non-border-touching foreground. Also reject unknown/duplicate part IDs and inconsistent contract/catalog hashes. Human image review still decides whether semantic content is the intended part.
- [ ] Implement the exact audit record and canonical 0600 plan publication from pinned Task 12. Run the audit tests RED then GREEN. The auditor never creates provider tasks or writes a live catalog.
- [ ] Add only `!assets/_staging/meshy/*/_references/*.png` after the existing broad Meshy PNG ignore. Do not unignore raw candidates, thumbnails or arbitrary staging files.
- [ ] Run plans twice for each exact active asset and compare canonical results. Use this loop only after all eight references pass the audit:

```bash
set -euo pipefail
for ASSET_ID in biomass_human_arm_v1 biomass_insect_leg_v1 biomass_cephalopod_tentacle_v1 biomass_animal_skull_v1 biomass_humanoid_torso_v1 biomass_gunk_connector_v1 biomass_claw_v1 biomass_maw_v1; do
  "$PYTHON" tools/meshy_stage.py plan --project-root . \
    --contract "data/asset_generation/contracts/$ASSET_ID.json" \
    --pricing-file data/asset_generation/meshy_pricing_v1.json \
    --reference-root "assets/_staging/meshy/$ASSET_ID/_references" \
    --reference three_quarter=three_quarter.png
done
```

Expected each: resolved references; untextured image-to-3D smart-topology request; four candidates. At the adopted pricing snapshot the per-candidate cost is 5, max is 20 per part. Revalidate the pricing record at execution; an expired/mismatched record is replanned, not bypassed. The plan/audit writer binds both request-plan-file SHA and provider-payload SHA.
- [ ] Verify exactly eight tracked references with `git add --dry-run` and the staged-name inventory; run all H1–H4 host tests; commit the exact reference/plan/audit/tool/test/proof files with `art: stage audited biomass pilot references`.

### H5. Serial candidates and explicit selection (adopted Task 13)

**Create:** `tools/biomass_candidate_batch.py`, `tests/test_biomass_candidate_batch.py`, `assets/_staging/meshy/_plans/biomass_candidate_batch.json`; eight per-asset `_review/contact_sheet.json` records.

- [ ] Write fake-client tests for no-POST preflight, plan/audit/pricing/reference identity, existing journal rejection, one POST attempt per slot, unknown-ID ambiguity, GET-only resume, valid FAILED→continue suffix recovery, exact cardinality and deterministic contact sheets.
- [ ] Implement only the pinned `preflight`, `generate`, `reconcile` and `contact-sheet` operations over `meshy_stage.py`; do not build a second provider client. Existing any-state inventory routes to verification/recovery, never new generation. Record all IDs before allowing another state transition.
- [ ] Run `"$PYTHON" -m pytest -q tests/test_biomass_candidate_batch.py tests/test_meshy_stage.py` RED/GREEN and independently review paid-call reachability. Commit the tool/test slice before any real provider invocation.
- [ ] Execute `preflight --project-root . --asset-id "$ASSET_ID"`, then one `generate --project-root . --asset-id "$ASSET_ID" --pricing-file data/asset_generation/meshy_pricing_v1.json` per asset, serially. Iterate the exact H0 roster; stop on ambiguity. Never run an automatic retry loop around `generate`.
- [ ] Run `reconcile --project-root . --pricing-file data/asset_generation/meshy_pricing_v1.json`. Expected: eight journals, four unique task IDs each, 32 unique candidates globally, all hashes bound. Current authorization/pricing integrity remains required; the historical aggregate 160 is not permission to use stale pricing.
- [ ] Build all eight contact sheets using `contact-sheet --project-root . --asset-id "$ASSET_ID"`. Then inspect every sheet, choose at most one candidate per asset, and explicitly reject all unselected candidates. If none meets the six candidate checks, leave that asset rejected and revise its reference before any separately planned generation.
- [ ] Immediately `archive-raw` each selected task using H1. Verify the external archive and manifest before committing selection records. Commit no raw GLBs, generated thumbnails, unselected task directories or contact-sheet PNGs.

### H6. Per-part masters, guide approval and runtime review (adopted Task 14)

For each selected task in the verified H5 batch manifest, derive `TASK_ID` from that record, never from the newest directory name. Pin `CONTRACT`, `TASK_DIR`, `CATALOG=data/combat/biomass_part_catalog.json`, catalog SHA and `EVIDENCE_DIR=/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/$ASSET_ID/$TASK_ID`.

- [ ] Run `rehydrate-raw`; verify immutable raw/generation/archive identity.
- [ ] Create the canonical master with `tools/meshy_blender_master.py` only if absent. An existing master must match its receipt and is never recreated as a retry.
- [ ] Run the H2 `preview` mode. Review the front/side/three-quarter/socket-overlay/contact-sheet set. Guides must have clearance; no disconnected fragments, unwanted protrusions, excessive material noise, or texture camouflage hiding a weak silhouette.
- [ ] Record actual reviewer approval with `approve-preview`; run `publish-cleaned`. Do not have the generation worker sign a human decision on the user's behalf.
- [ ] Run `tools/meshy_blender_validate.py` and `tools/meshy_runtime_review.py` with the same exact contract/task path as D5/D6, changing only the manifest-derived asset/task ID. Each part requires six cases and 18 PNGs, genuine visibility, zero unexpected diagnostics, and fresh `promotion_ready` verification.
- [ ] Run `tools/meshy_promotion_packet.py biomass-part` with the six H3 arguments, bound to the current catalog SHA and exact external evidence path. Expected: `MESHY BIOMASS PART PROMOTION PROPOSAL PASS asset=$ASSET_ID`, no live writes.
- [ ] Repeat only for the eight selected records. On a fresh checkout restore fixed evidence permissions (directories 0700, JSON/PNG leaves 0600) before verification; never change file bytes to repair permission-only failures.
- [ ] Commit only the exact selected JSON/proposal evidence, approved per-part runtime evidence and proof inventory after a programmatic count. Do not stage master/GLB binaries or unselected candidates in this evidence commit.

### H7. Transactional biomass promotion and playable acceptance (adopted Task 15)

**Create:** `tools/biomass_pilot_promote.py`, `tests/test_biomass_pilot_promote.py`, `scripts/validation/biomass_playable_pilot_smoke.gd`.
**Create at promotion only:** the eight exact `assets/imported/threats/biomass/<asset_id>.glb` files and descriptors; eight `scenes/wrappers/biomass/<asset_id>.tscn` wrappers.
**Modify:** only the matching catalog wrapper paths, current proof, feature status and final evidence after approval.

- [ ] Add RED transaction tests for every publication/import/validation failure point, unknown or mismatched preexisting targets, symlink/hardlink destinations, modified catalog prestate, interrupted journal recovery and identical repeat application.
- [ ] Implement the pinned `plan`, `apply`, `verify`, `rollback`, and `finalize` operations. `plan` is read-only; it preflights all eight packets against one pre-mutation catalog and protected prestate digest. `apply` owns the whole bundle and journal; no other worker writes these targets.
- [ ] Stage thin wrappers from the catalog, not from GLB markers: Node3D root + imported visual child + direct plain Node3D socket nodes. No physics/animation/collision nodes in wrappers; the existing assembler materializes gameplay authority from catalog descriptors.
- [ ] On failure, restore catalog prestate and remove only newly created hash-matching targets. Never delete or overwrite a file another process changed. Incomplete transactions block unrelated promotion until exact recovery/rollback.
- [ ] Import twice with Godot 4.7.1 and require eight stable `.glb.import` descriptors. Never commit `.godot/imported` or accept a second import that changes descriptors unexpectedly.
- [ ] Write the actual playable smoke before changing feature status. It must load production main, prove eight wrappers, six archetypes and five gaits, kill/removal, travel/revisit, and exact saved/loaded recipe, seed, attachment graph, transforms and collision fingerprints. Do not settle for a catalog-load-only smoke.
- [ ] Run host transaction tests and the smoke RED/GREEN. The exact required playable marker is:

```text
BIOMASS PLAYABLE PILOT PASS wrappers=8 archetypes=6 gaits=5 kill=true travel=true save_load=true
```

- [ ] Run `tools/biomass_composite_review.py` in its existing `--visual-stage final` capture mode and verify `artifacts/validation-previews/biomass-assembly-final/review.json`. Require exactly five recipes × two seeds × three lighting states = 30 cases, no PrimitiveMesh fallback, ≤160 nodes and ≤24,000 triangles, finite 0.05–20 m extents, collision/LOS/readability evidence and actual artistic approval.
- [ ] `finalize` only after the approved final manifest SHA, transaction targets and playable evidence match. Only finalize changes the feature to Implemented. Keep ADR-0059 Accepted; an ADR is not an implementation-status switch.
- [ ] Commit the exact transaction tool/tests/smoke, eight GLBs/descriptors/wrappers, catalog/proof/feature/final-evidence inventory. Re-verify on a clean checkout before release review.

## 13. Task I — Static-prop pilot and separately reviewed production promotion

### I1. Complete the remaining static crafting-station pilot

**Contract:** `data/asset_generation/contracts/crafting_station_derelict_v1.json`.
**Required visual:** one serviceable front-facing work surface with bounded machinery detail, recognizable from the locked-isometric camera; dimensions `[1.6, 1.2, 1.8]` meters within 0.02 m, 3,000–6,000 triangles for the whole asset, at most three materials, default state only, no rigging or gameplay collision in GLB.

- [ ] First inventory all existing task journals across the known worktrees for this exact asset. Recover existing tasks if any; only absence of any prior submission permits a new batch.
- [ ] Create rights-cleared separate `source_front.png`, `source_side.png`, `source_back.png`, and `source_three_quarter.png` under `assets/_staging/meshy/crafting_station_derelict_v1/_references/`. Keep the design consistent across views; no collage. Use the approved loot/room material palette, not a new visual style.
- [ ] Run the existing read-only plan:

```bash
export ASSET_ID=crafting_station_derelict_v1
export CONTRACT="data/asset_generation/contracts/$ASSET_ID.json"
export REFERENCE_ROOT="assets/_staging/meshy/$ASSET_ID/_references"
"$PYTHON" tools/meshy_stage.py plan --project-root . --contract "$CONTRACT" \
  --pricing-file data/asset_generation/meshy_pricing_v1.json \
  --reference-root "$REFERENCE_ROOT" \
  --reference front=source_front.png --reference side=source_side.png \
  --reference back=source_back.png --reference three_quarter=source_three_quarter.png
```

Expected: valid resolved-reference plan, four untextured candidates, current pricing identity and maximum. Store exact plan bytes/hash in the proof using the existing canonical writer, not shell-redirection partial files.
- [ ] For a genuinely new approved batch only, pass that current `maximum_credits` as `--approved-credits` to `tools/meshy_stage.py generate` with the identical arguments plus `--output-license paid-private`. Record the batch ID. On ambiguity use the existing `resume`/reconciliation path; do not retry generation.
- [ ] Select one candidate using all six explicit candidate-review checks; reject the others. Create/clean the canonical Blender master and stage the normalized `cleaned.glb`; validate with `tools/meshy_blender_validate.py`, then run six runtime cases using `tools/meshy_runtime_review.py`. No default prop or placeholder is allowed to substitute for the selected geometry in the capture.
- [ ] After the six-case machine and artistic verdicts pass, emit the prop proposal with target `res://assets/imported/props/dressing/crafting_station_derelict_v1.sidecar.json`. Keep this output staged. Commit the reviewed reference/selected-record/proof inventory separately from production promotion.

### I2. Promote only accepted visual replacements in an explicit reviewed diff

This is a separate execution/review packet, not a flag on generation. Do not treat the new loot visual as permission to redesign `scripts/tools/loot_container.gd` or crafting gameplay; inventory, collision, range, saved search state and grant-once semantics remain unchanged.

**Allowed production paths for the two props:**

- `assets/imported/props/dressing/loot_container_derelict_v1.glb`
- `assets/imported/props/dressing/loot_container_derelict_v1.sidecar.json`
- `assets/imported/props/dressing/crafting_station_derelict_v1.glb`
- `assets/imported/props/dressing/crafting_station_derelict_v1.sidecar.json`
- `data/props/visual_bindings.generated.json` (generated only).

A new sidecar must be complete under `tools/prop_visual_metadata.py`, not just the provenance overlay. Use the existing authored visual-binding schema for the intended role; verify the consuming `scripts/placement/gameplay_prop_factory.gd` resolves the exact new ID. Do not guess a binding role from the English asset name. If the current approved gameplay contract has no slot for the new ID, keep it promotion-ready and obtain a separately specified gameplay integration decision; do not broaden this asset-pipeline task into a new interaction system.

- [ ] Prepare the live diff in an isolated promotion worktree. Snapshot the prestate; require current selected/raw/master/validation/runtime/proposal hashes and the explicit artistic approval.
- [ ] Publish only the hash-bound cleaned GLBs and reviewed complete sidecars, refusing differing preexisting targets. Use the existing metadata generator for the derived index. Keep a compensating rollback list of newly created leaves and original index bytes.
- [ ] Import with the verified Godot version, rerun metadata checks and the existing structural/prop loader smokes, then rerun the existing loot ecosystem, grant-once/save-load and crafting smokes from the canonical bundle. Expected: exact registered pass markers and no new diagnostic or gameplay behavior change.
- [ ] For structural promotion, use `tools/promote_structural_sources.py` with its verified source/staging roots and a single reviewed module first. Run source/variant/import/wrapper gates before and after publication. Never run `--all` until the complete-room style decision and one-module rollback rehearsal pass. Do not alter connector/collision data to hide a mesh mismatch.
- [ ] Review before merging each promotion diff. A failure restores only this packet's newly created/hash-matching outputs and original derived index; no cleanup of unrelated assets.
- [ ] Commit accepted prop and structural promotions separately. Record the source master, cleaned GLB, sidecar/index and tested commit identities in the closure proof.

## 14. Task J — Fresh final verification and truthful documentation

**Modify:** `docs/game/features/ai_candidate_asset_pipeline.md`, `docs/game/features/blender_structural_source_pipeline.md`, `docs/game/features/asset_metadata_pipeline.md`, `docs/game/06_validation_plan.md`, `docs/game/05_requirements.md`, `docs/superpowers/proofs/asset-pipeline-closure.md` and the existing biomass/loot/ithappy proof files only as their outcomes require.

- [ ] Separate `toolchain implemented`, `candidate generated`, `master accepted`, `runtime reviewed`, `promotion proposed`, and `promoted` in the current status table. Historical snapshots retain their original commit and numbers. Correct the structural feature's obsolete blanket no-export/future-promotion prose to describe recovery-only versus the separately governed promotion phase; do not erase the original ownership rules.
- [ ] Every AP ledger row must end in `verified fixed`, `verified completed`, `superseded with preserved evidence`, or an explicit unresolved blocker. An optional disabled workflow is recorded as disabled, never falsely counted as implemented.
- [ ] Create a new clean acceptance worktree at the final candidate commit, restore verified external/ignored evidence and native-extension provenance, and run all required pipeline tests. Capture output with a bounded job; do not execute tests in the user's dirty main checkout.

```bash
"$PYTHON" -m pytest -q -p no:cacheprovider \
  tests/test_meshy_download_limits.py tests/test_run_canonical_regression.py \
  tests/test_textured_tile_output_boundary.py \
  tests/test_meshy_asset_contract.py tests/test_meshy_stage.py tests/test_meshy_governance.py \
  tests/test_meshy_candidate_review.py tests/test_meshy_blender_tools.py \
  tests/test_meshy_loot_container_recipe.py tests/test_meshy_texture_packet.py \
  tests/test_meshy_promotion_packet.py tests/test_meshy_runtime_review.py \
  tests/test_structural_source_contract.py tests/test_validate_structural_sources.py \
  tests/test_export_structural_glb.py tests/test_promote_structural_sources.py \
  tests/test_backup_structural_sources.py tests/test_validate_structural_variant_bindings.py \
  tests/test_prop_visual_metadata.py tests/test_validate_prop_visual_bindings.py \
  tests/test_biomass_catalog_validate.py tests/test_biomass_composite_review.py \
  tests/test_meshy_biomass_part_recipe.py tests/test_biomass_triangle_limits.py \
  tests/test_biomass_reference_audit.py tests/test_biomass_candidate_batch.py \
  tests/test_biomass_pilot_promote.py
"$PYTHON" tools/generate_prop_sidecars.py --project-root . --check
"$PYTHON" tools/validate_prop_visual_bindings.py --project-root . --check-index
"$PYTHON" tools/run_canonical_regression.py --project-root . --check
"$PYTHON" tools/run_canonical_regression.py --project-root .
git diff --check
```

Expected: no failures/errors, real Blender probes run, no unexplained skip of required gates, metadata exit 0, exact mechanically counted canonical marker, no unexpected diagnostics, whitespace check clean. Run E6's full focused-nine suite as well; it is not replaced by the abbreviated final command above.

- [ ] Reverify both biomass composite reports and the real playable pilot, not just the placeholder proof:

```bash
"$PYTHON" tools/biomass_composite_review.py verify --project-root . \
  --report artifacts/validation-previews/biomass-assembly-placeholder/review.json
"$PYTHON" tools/biomass_composite_review.py verify --project-root . \
  --report artifacts/validation-previews/biomass-assembly-final/review.json
"$GODOT" --headless --path . --script res://scripts/validation/biomass_playable_pilot_smoke.gd
```

Expected: both 30-case reports verify and the exact H7 playable marker appears with clean diagnostics. Check each accepted prop's six-case report and artistic verdict against its actually promoted GLB hash.
- [ ] Verify git status against an explicit allowed generated/import descriptor inventory. No unrelated changes, `.DS_Store`, native binary of unknown provenance, credentials, raw provider responses containing signed URLs, staging cache, or `.godot` directory may enter the release commit.
- [ ] Independently review code/spec compliance, then visual output and the promotion/rollback evidence. Submit to the fork repository only after review; no automatic upstream PR, merge or release is part of a code-generation job.
- [ ] Commit documentation with `docs: close verified asset pipeline gaps with current evidence`. The final report names exactly what was promoted and what remains blocked; no global `all outstanding issues resolved` claim is allowed while any required AP row remains open.

## 15. Risks, tradeoffs and open questions

1. **Concurrent source changes:** main is dirty and several branches touch the same validators/documents. Use an isolated worktree, preserve user changes and serialize hotspot integration. Do not overwrite the untracked wall generator or draft biomass files as a cleanup task.
2. **Stale evidence vs real regressions:** a hash/permission/version mismatch is not automatically a code bug. Recover/rehydrate evidence or rebuild the exact native extension before proposing behavior changes. Do not backfill historic evidence with current outputs.
3. **Art cannot be approved from source inspection:** no new visual defect was asserted during planning. The plan specifies objective gates and a constrained aesthetic rubric; actual render review determines whether a geometry change is needed. Rejected art remains staged.
4. **Paid ambiguity:** known failed/uncertain batches are never silently retried. A subscription removes spending negotiation, not request identity or exactly-once submission discipline.
5. **External source availability:** the independent backup destination is not established by the inspected source. Verify an existing destination or obtain that one concrete choice before declaring disaster recovery complete. Do not create cloud resources on a guessed account.
6. **Scope boundary for new gameplay slots:** two prop proposals can be fully validated without changing game design. If there is no approved consuming binding for one, its status remains promotion-ready pending the specific gameplay decision, not promoted. This is not permission to invent new inventory/crafting behavior.
7. **Optional historical texture/training tools:** staging safety is fixed here; a newly curated LoRA dataset or new texture-provider implementation is explicitly not required for the first accepted production pipeline. If chosen later, it needs separate quality/provenance verification before use.
8. **Baseline failures are not waived:** earlier proof recorded full-suite baseline failures. This plan does not assert they still exist or are fixed. Fresh required-path failures get an exact test/trace and scoped remediation; unknown fixes must not be invented before reproduction.
9. **Execution duration:** the checklist units are small, but Blender/provider jobs and the full regression bundle are not. Use supervised jobs and heartbeats; do not detach unsupervised work or claim completion from a launch message.

## 16. Late audit reconciliation — additional mandatory gates

The completed read-only fan-out exposed additional gaps after the initial plan draft. The Meshy findings below were independently checked against the current source. They are not evidence of failing runtime tests. Add AP-13 through AP-16 to the execution ledger; the final closure checklist includes them.

### AP-13 — Generic master initialization is not a cleaned export

`tools/meshy_blender_master.py:run_blender_master()` saves the master but does not invoke a GLB exporter. The loot-specific recipe is not a generic export implementation. Consequently, Task I1 must not assume that running the generic master command produces `cleaned.glb`.

Decision: keep initialization separate from deliberate artist cleanup. For this closure, use the existing Blender-native export operation from the reviewed master's `EXPORT` collection, then the existing host validator; do not add automatic export of `WORKING` or invent a generic auto-cleanup algorithm. Record this operator step in `docs/game/features/ai_candidate_asset_pipeline.md` during execution. In Blender's Python console, with the exact reviewed master already open, execute this complete block after setting `TASK_DIR` to the task-local staging directory (not a live runtime path):

```python
exec('''import bpy, os
from pathlib import Path
root = Path(os.environ["TASK_DIR"]).absolute()
if "assets/_staging/meshy/" not in root.as_posix() + "/":
    raise RuntimeError("Expected Meshy task staging directory")
if not root.is_dir() or root.is_symlink():
    raise RuntimeError("Missing or symlink task directory")
output = root / "cleaned.glb"
if output.exists() or output.is_symlink():
    raise RuntimeError("Refusing to overwrite existing evidence; reconcile it first")
collection = bpy.data.collections.get("EXPORT")
if collection is None or not list(collection.all_objects):
    raise RuntimeError("Reviewed EXPORT collection is empty")
bpy.ops.object.select_all(action="DESELECT")
for obj in collection.all_objects:
    obj.hide_set(False)
    obj.select_set(True)
result = bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", use_selection=True, export_apply=True, export_extras=True, export_materials="EXPORT", export_texcoords=True, export_animations=True)
if "FINISHED" not in result or "CANCELLED" in result:
    raise RuntimeError("GLB export failed; quarantine partial output")
os.chmod(output, 0o600)
print("STAGED EXPORT CREATED; INDEPENDENT VALIDATION REQUIRED")
''')
```

This is an interactive staging-only operation, not an unattended secure publisher. First inspect all staging ancestors for symlinks using the existing governance preflight. Keep the original raw candidate immutable. Export failure quarantines the partial file; it does not permit review binding. Run the Task D validator/runtime command sequence with this asset's contract and task ID. Expected: independent Blender validation and all six real runtime cases pass before any proposal. A successful export alone does not close AP-13. The loot recipe's deterministic replacement geometry must be described as such, not as proof of generic raw-mesh refinement.

### AP-14 — Master-root documentation must match the trust boundary

`tools/meshy_blender_master.py:29–32,71–78` uses a fixed trusted external root; the documented `MESHY_MASTER_ROOT` override is not implemented. Decision: retain the fixed root and its existing path-security tests for this project, rather than expand the filesystem trust boundary merely to match stale prose.

- [ ] Remove the claim that `MESHY_MASTER_ROOT` configures the generic writer from `docs/game/features/ai_candidate_asset_pipeline.md`; document the exact fixed root `/Volumes/Untitled/SynapticSeaAssets/meshy/source` and stop if unavailable.
- [ ] Run `"$PYTHON" -m pytest -q tests/test_meshy_blender_tools.py`; expected zero failures. This is a documentation correction, not a TDD code change.
- [ ] Commit only that document with `docs: clarify fixed trusted Meshy master root`.

### AP-15 — Optional texture proposals must not trust forged semantic reports

`tools/meshy_texture_packet.py:237–259` checks report structure/flags, and later checks the cleaned file hash, but does not call the independent `verify_validation_report()` authority. The stronger verifier exists in `tools/meshy_blender_validate.py:1112`. Do not describe this proposal-only gap as a proven production-promotion bypass.

Decision for the mandatory closure path: keep texture proposals disabled until this gap receives its own TDD repair; manual Blender material work remains the supported path. In `docs/game/features/ai_candidate_asset_pipeline.md`, mark the texture-proposal example unavailable pending semantic verification. Do not execute texture requests in D, H or I. AP-15 may close as explicitly disabled, not as implemented or security-fixed.

If enabling this optional feature is chosen, the exact repair boundary is `tools/meshy_texture_packet.py` and `tests/test_meshy_texture_packet.py`: after the existing cleaned-file identity check, call `verify_validation_report(cleaned, task_contract_path, report, task_id=resolved_task.name, expected_contract_sha256=generation["contract_sha256"])`, translating its failure to `TexturePacketError`. First extend the existing valid-report fixture test to change only `triangle_count`, preserve the cleaned hash, and require rejection without creating `texture_request.json`. Observe failure before editing production code, then run `"$PYTHON" -m pytest -q tests/test_meshy_texture_packet.py tests/test_meshy_blender_tools.py` and require zero failures plus the real Blender probe. Never mock semantic recomputation to always succeed. Commit the optional repair separately from the mandatory documentation disablement.

### AP-16 — Structural validation coverage must be measured, not assumed

The structural audit reports eight allowlisted source modules versus fifteen catalog modules, and possible empty-source bootstrap in `tools/focused_nine_batch.py:_ensure_source()`. Treat the numbers and bootstrap behavior as source-review findings to recheck, not as runtime-proven failures or permission to automatically expand a v0 authority list.

Before E2/E7, compare `data/kits/ship_structural_v0.json`, `tools/structural_source_contract.py`, `tools/validate_structural_variant_bindings.py`, `tools/validate_promoted_sources.py`, and `_ensure_source()`. Add an explicit per-module coverage table to `docs/superpowers/proofs/asset-pipeline-closure.md`: catalog ID, governed source path, derived variants, validating command, and intentional exclusion reason if any. An excluded module is not counted as source-validated. A missing authored source is recovery/manual authoring work, never a blank-master substitution.

Do not run a focused-nine batch with missing named source files. Existing manual source preflight E7 is mandatory even if `_ensure_source()` offers bootstrap behavior. Run `"$PYTHON" -m pytest -q tests/test_focused_nine_batch.py tests/test_structural_source_contract.py tests/test_validate_structural_variant_bindings.py tests/test_validate_promoted_sources.py` and require no failures; separately verify every required module has real source evidence. If broader automated catalog governance is required after that comparison, specify and review that schema change before implementing it rather than pretending the original eight-module tests cover the entire catalog.

## 17. Review and completion discipline

- Never claim all tests green from the historical suite totals in the proof files.
- Every later packet's verification output is an expected acceptance condition, not a result observed during planning.
- No unknown task IDs, hashes, reviewers, provider URLs, image judgments, or catalog entries may be invented.
- Missing selected evidence, raw archive, source volume, credentials, or visual approval is a named blocker. Stop the affected lane while independent lanes continue.
- Keep one golden-room comparison before scaling a style change across all modules.
- Finish with a reviewed promotion diff and a new clean-checkout verification, not with a generated contact sheet or proposal JSON alone.
