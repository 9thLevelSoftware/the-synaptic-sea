# Task9 Canonical Structural Compiler Parity Evidence

## Scope and policy

`StructuralEdgePlan` is the sole boundary authority. The legacy resolver and
`structural_placer` remain debug-only compatibility paths; neither may derive or
place production boundaries. Runtime capture uses the live wrapper catalog.
Staged capture uses a disposable overlay that mounts staged GLB/material inputs
at canonical paths without runtime promotion.

The parity contract is structural only. For each sorted `placement_id`/`edge_key`
pair, the live wrapper path and staged overlay evidence must agree on:

- `kind` and `state`;
- `module_id`;
- canonical `position` and `yaw_degrees` pose; and
- `room IDs`.

GLB/material and scene-path differences are explicitly visual-only. Any other
structural plan drift is a gate failure.

## Evidence inputs

- Live path: `ShipGenerator` → `GeneratedShipLoader` using seed `17`, the
  compact derelict archetype, and the live wrapper catalog.
- Staged overlay path: the committed staged-only capture bundle
  `artifacts/validation-previews/focused-nine/edge_map.json`, produced by the
  disposable overlay runner with capture ID `StagedFocusedNine`.
- Compared inventories: sorted canonical placements plus one metadata-bearing
  wrapper per placement.

## Parity smoke

Command:

```bash
godot --headless --path . --script res://scripts/validation/procgen_golden_parity_smoke.gd
```

Expected pass marker:

```text
PROCGEN GOLDEN PARITY PASS seed=17 placements=<n> wrappers=<n> structural=true visual_only=GLB,material
```

The smoke rejects count changes, missing/duplicate placement IDs or edge keys,
kind/state/module changes, pose drift, room-ID drift, and wrapper metadata that
is not one-for-one with the canonical plan.

## Final integration gate record

The final gate is run in this order and its complete output is recorded here:

1. `PYTHONPATH=. python3.11 -m pytest -q tests/test_procgen_structural_compiler.py tests/test_focused_nine_staged_derelict_preview.py`
2. `godot --headless --path . --script res://scripts/validation/procgen_structural_compiler_smoke.gd -- 17 23 41 73 101`
3. `godot --headless --path . --script res://scripts/validation/procgen_golden_parity_smoke.gd`
4. `git diff --check`

Gate output was captured after fresh execution:

### 1. Focused Python gate

```text
........................................................................ [ 93%]
.....                                                                    [100%]
77 passed in 10.89s
```

Exit code: `0`.

### 2. Multi-seed compiler smoke

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

PROCGEN_STRUCTURAL_COMPILER_PASS seeds=5 placements=248 portals=46
```

Exit code: `0`; no `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` diagnostics.

### 3. Live/staged parity smoke

```text
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

PROCGEN GOLDEN PARITY PASS seed=17 placements=51 wrappers=51 structural=true visual_only=GLB,material
```

Exit code: `0`; no `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` diagnostics.

### 4. Diff hygiene

```text
```

Exit code: `0`.
