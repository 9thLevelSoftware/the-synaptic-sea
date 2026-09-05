# Asset-pipeline closure evidence reconciliation

This document retains the non-destructive Task A baseline context and reconciles it with the now-
integrated loot-container evidence. This documentation task made no provider call, asset-generation
request, Blender authoring, runtime capture, promotion, or source-asset edit; it read
the tracked state and updated only the four requested documentation files. Historical baseline
notes remain audit context; the current integrated state is recorded in the evidence and command
sections below.

## Tested commit

- Main checkout: `/Users/christopherwilloughby/Code/the-synaptic-sea`.
- Main branch at inspection: `main`.
- Main `HEAD` for the integrated evidence: `655ae0380f5950c6723aec9fa9b150a463ad4ff4`.
- Isolated worktree: `/Users/christopherwilloughby/Code/the-synaptic-sea-docs`.
- Isolated branch: `docs/evidence-rebind-reconciliation`.
- Isolated worktree `HEAD`: `655ae0380f5950c6723aec9fa9b150a463ad4ff4`.
- The isolated worktree was clean before the documentation edits; the dirty main checkout was
  not reset, stashed, cleaned, staged, or overwritten.

Pre-existing worktrees observed before Task A3:

| Path | HEAD | branch |
|---|---|---|
| `/Users/christopherwilloughby/Code/the-synaptic-sea` | `f4a65669` | `main` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/baseline-focused-nine` | `1bf474c3` | `kanban/t_1577d922` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/baseline-focused-nine-airlock-bounds` | `b4457269` | `kanban/focused-nine-airlock-bounds` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/baseline-focused-nine-pressure-door` | `924d9e08` | `kanban/focused-nine-pressure-door` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/baseline-regressions-integrated` | `5841392c` | `fix/baseline-regression-bundle` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/baseline-structural-contract` | `4ab11293` | `kanban/t_29802bb6` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/baseline-topdown-spawn` | `11b45e62` | `kanban/t_b99c5016` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/baseline-world-save` | `2decec45` | `kanban/t_1df350c5` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/biomass-pipeline-readiness-corrections` | `e6711675` | `docs/biomass-pipeline-readiness-corrections` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/biomass-readiness-corrections` | `e8225987` | `docs/biomass-readiness-corrections` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/biomass-readiness-integrated` | `e1bf2b0f` | `docs/biomass-readiness-integrated` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/biomass-task9-final-readiness` | `97768af0` | `docs/biomass-task9-final-readiness` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/biomass-validator-python39` | `b7878bb4` | `fix/biomass-validator-python39` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/ceiling-fade-lifecycle` | `5b9ef1e7` | `fix/ceiling-fade-freed-node-guards` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/loot-integration-recovery` | `f589f62c` | `fix/loot-integration-recovery` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/meshy-blender-asset-system` | `f84ff366` | `fix/meshy-runtime-dual-hash-binding` |
| `/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/procedural-biomass-assembly` | `4f1dc22a` | `feature/procedural-biomass-threat-assembly` |

The worktree table above is retained as historical Task A context. The current docs worktree used for
this reconciliation is `/Users/christopherwilloughby/Code/the-synaptic-sea-docs` on
`docs/evidence-rebind-reconciliation` at `655ae038`; the main checkout was not reset, stashed,
cleaned, staged, or overwritten.

Recent integrated history includes `655ae038 test: pin reapprove fixtures to pre-reapprove journal
snapshot`, `48202a8b art: rebind loot container approval evidence offline`, `c70f9b17 art: stage
loot container promotion proposal (D8)`, `ceb8fe5a art: record loot container runtime review (D6)`,
and `cc8c8c95 art: publish cleaned loot container evidence (D5)`.

## Historical Task A toolchain

The plan-required environment was used in the isolated worktree:

| Tool | Path | Observed version | exit |
|---|---|---|---:|
| Python | `/opt/homebrew/bin/python3.11` | `Python 3.11.15` | 0 |
| Godot | `/opt/homebrew/bin/godot` | `4.7.1.stable.official.a13da4feb` | 0 |
| Blender | `/opt/homebrew/bin/blender` | `Blender 5.2.0 LTS`, build date `2026-07-14` | 0 |

The scoped gate used `PYTHONPATH=.`, `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1`, and
`PYTHONDONTWRITEBYTECODE=1`.

## Historical Task A dirty-source exclusions

The main checkout was not reset, stashed, cleaned, staged, or overwritten. Its status at
inspection contained `2,208` entries: `5` tracked modifications and `2,203` untracked paths.
The five tracked modifications were deliberately excluded from the isolated baseline commit:

- `.DS_Store`
- `addons/derelict/bin/macos/libderelict_godot.dylib`
- `docs/game/05_requirements.md`
- `docs/game/adr/README.md`
- `tools/meshy_stage.py`

The main-only `tools/meshy_stage.py` diff was preserved exactly and not copied into this
worktree: `_GLB_MAX_BYTES` changes `64 * 1024 * 1024` to `128 * 1024 * 1024`, and
`_DOWNLOAD_TOTAL_MAX_BYTES` changes `80 * 1024 * 1024` to `256 * 1024 * 1024`. The untracked
source/evidence families were also excluded, including `assets/_staging/meshy/stalker_v1/`,
`data/catalogs/`, `docs/superpowers/plans/2026-09-02-procedural-biomass-threat-assembly.md`,
`scripts/validation/worldgen_ship_render.gd`, `tests/test_meshy_download_limits.py`, and
`tools/generate_ship_structural_wall_meshes.py`. No untracked asset or generated import file
was mass-staged.

## Issue ledger

Every row records `ID | requirement | source evidence | owner lane | state | closing test/evidence`.

| ID | requirement | source evidence | owner lane | state | closing test/evidence |
|---|---|---|---|---|---|
| BASE-001 | Preserve the user's dirty main checkout | Main status: 5 tracked modifications and 2,203 untracked paths; isolated worktree at the exact main `HEAD` | Integrator | CLOSED for Task A | Isolated status was clean before proof; main was not edited by this task |
| BASE-002 | The scoped Python pipeline gate must be run without hiding failures | Exact integrated nine-suite command; `442 passed in 34.38s` | Meshy/Blender evidence | CLOSED for integrated evidence | Fresh focused bundle passed with `/usr/bin/python3` |
| BASE-003 | Selected loot evidence must bind raw, cleaned, Blender, runtime, and promotion records | Tracked batch `9e04213bc806421d8e64c9c9c23f26d3`; selected task `01a05dcb-fc3b-7418-b105-2170af354088`; `review.json.state=promotion_ready`; D5/D6/D8 records present | Loot evidence lane | CLOSED except live application | Candidate, Blender, runtime, and proposal evidence verify; apply the staged proposal only through a separate reviewed operation |
| BASE-004 | Do not submit a replacement historical `stalker_v1` batch | Main `_staging/meshy/stalker_v1/` and plan context record historical failed batch IDs `1a2553d5068b4f069fcbbdb88db851c5`, `8b09cef0333541db8ae3781c8ea2b9a6`, and completed batch `a7089e88e2cf4cea90a0c4c2efc0df7b` | Provider-integrity lane | HOLD | Preserve existing journals and records; no provider call or replacement submission |
| BASE-005 | Keep Focused Nine ownership fail-closed | Board `t_f2796a0f` is blocked; its read-only salvage comment reports no coherent migration/backups, six unowned masters, and three potentially tainted masters | Structural/ownership lane | BLOCKED | Governed migration with exact signatures, backups, hashes, and rerun of the focused ownership suite |
| BASE-006 | Keep review-only biomass promotion packets behind their dependencies | Board `t_ee221c02` is running; child spec/quality cards `t_139d5dfc` and `t_8569ee64` are todo | Biomass continuation lane | IN PROGRESS / DEPENDENCY | Complete Task 11 implementation and independent spec/quality gates |
| BASE-007 | Keep runtime-review batching separate from promotion | Board `t_dc74bad8` and QA child `t_eb9f6440` are todo; downstream `t_3d3afc0f` is todo | Runtime-review lane | TODO / DEPENDENCY | Prove one-window capture and exact six-case evidence before Task 14 |
| BASE-008 | Integrate loot recovery only after independent QA | `t_cd275951` and `t_812d51b6` are done; `t_e274ae71` remains todo and is parented by loot QA plus final composite QA | Integrator | PENDING | Cherry-pick only the QA-approved repair after both parent gates; no integration in Task A |

Read-only board reconciliation was limited to asset/refinement/runtime-review cards on
`synaptic-sea-stage-gate`. Relevant observed statuses and dependencies were: `t_1577d922`
blocked with bounded replacements `t_f2796a0f` and `t_b85932c9`; `t_70ba76f3` done with
`t_908e35ed` done and `t_f2d8687a` blocked; `t_a10e866e` done; `t_6839abb1` and `t_0a24fdee`
done; `t_ee221c02` running with review children; `t_b8ebb99a` and `t_3c67ff53` todo;
`t_dc74bad8`, `t_eb9f6440`, `t_3d3afc0f`, and `t_dc163ef7` todo; and the loot recovery pair
`t_cd275951`/`t_812d51b6` done with integration `t_e274ae71` todo. No historical PASS prose
was used to close a card.

## Evidence inventory

### Repository and planning records

- The docs worktree and main both resolve to `655ae0380f5950c6723aec9fa9b150a463ad4ff4`,
  with the integrated evidence commits `d3df50da`, `d444f8a6`, `cc8c8c95`, `ceb8fe5a`,
  `c70f9b17`, `48202a8b`, and the fixture-pinning `655ae038`.
- The tracked loot plan envelope is
  `assets/_staging/meshy/_plans/loot_container_derelict_v1.json` with
  `references_resolved=true`, four `resolved_references`, and provider payload SHA-256
  `e1cadfd6f2292bbd6cff38956fe6d2d0287d4f94d4523a5ff0bce4d63a2d90b7`.
- The plan's four resolved references are `source_front.png`, `source_side.png`,
  `source_back.png`, and `source_three_quarter.png`, with the tracked task-local byte sizes and
  hashes recorded in the envelope.

### Integrated Meshy loot evidence

- The tracked batch journal is
  `assets/_staging/meshy/loot_container_derelict_v1/_batches/9e04213bc806421d8e64c9c9c23f26d3.json`.
  It is `COMPLETED` with four `SUCCEEDED` tasks at five consumed credits each; the current
  approval has protected snapshot `assets/imported` SHA-256 `4842dcc36a48f47c63850433d56763b7a4957bcc4031788d702315e9d93c42e7`,
  size `2528217250`, `reapproved_at` `2026-09-05T19:03:05.491301Z`, operator `christopher`, and reason
  `assets/imported grew from legitimate post-approval imports; protected snapshot recomputed offline against current repository state`.
- The journal has one append-only `approval_history` entry containing the original approval
  verbatim. Its original `assets/imported` snapshot was SHA-256 `0ad2fc66f53680b0f772f9344c215ddaaed35a69cb61a60b0bfc7d13610ee39c`,
  size `1922700132`; the other three protected-surface records were unchanged. The current approval snapshot is
  `4842dcc36a48f47c63850433d56763b7a4957bcc4031788d702315e9d93c42e7` / `2528217250`; the rebind was offline and did not create a provider task.
- D5 selected-candidate evidence is task
  `assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088/`:
  `raw.glb` is 58,720 bytes with SHA-256
  `ff07ca3f0e87e29fb1a77c007cf261920ac370f870ead9c21446b4ad1f15e377`; `cleaned.glb` is
  67,188 bytes with SHA-256 `eebcead4f6620845dcc53819fff0e600ebc409435598dfedc259254640bfca92`;
  and `blender-validation.json` is `PASS` with 792 triangles, 6 meshes, 2 materials
  (`painted_ship_alloy`, `warning_accent`), and valid UV evidence.
- The selected `review.json` has `state=promotion_ready`, `decision=promotion_ready`, and all
  six candidate checks true. The other three candidates are `rejected`, each with reason
  `superseded by already-selected candidate 01a05dcb-fc3b-7418-b105-2170af354088`.
- D6 runtime evidence is
  `artifacts/validation-previews/meshy/loot_container_derelict_v1/runtime-review.json` with
  `pass=true`, six captures for seeds `42` and `777` across `normal`, `emergency`, and `dark`,
  and 18 runtime PNG outputs.
- D8 evidence is the task-local `sidecar-overlay.json` with `proposal_only=true`, targeting
  `res://assets/imported/props/dressing/loot_container_derelict_v1.sidecar.json`; that target
  file is not present under `assets/imported`.
- Git-tracked evidence leaves are mode `0644` by design. Private execution and external staging
  contexts rehydrate evidence leaves to `0600` and directories to `0700` before private gates;
  this is the documented mode policy, not a blocker.

### Historical proofs and limits

- `docs/superpowers/proofs/meshy-blender-asset-system.md` says `LIVE PILOT PENDING`, reports
  historical evidence head `35816acfef34b8eee14d11c0d0eca07592b9fa01`, and explicitly distinguishes
  its historical 375-pass focused result from a live provider pilot.
- `docs/superpowers/proofs/focused-nine-comparison.md` records staging/validation PASS but
  explicitly says no runtime promotion and no original source replacement occurred.
- `docs/superpowers/proofs/ithappy-full-conversion.md` records `PASS (pending Godot import
  verification)`, so it is not current Godot import acceptance evidence.

## Commands and exit codes

| Command or action | exit | observed result |
|---|---:|---|
| `git worktree add -b docs/evidence-rebind-reconciliation /Users/christopherwilloughby/Code/the-synaptic-sea-docs 655ae038` | 0 | Isolated docs worktree at the required base |
| `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. /usr/bin/python3 tools/meshy_stage.py reapprove --project-root . --contract data/asset_generation/contracts/loot_container_derelict_v1.json --batch-journal assets/_staging/meshy/loot_container_derelict_v1/_batches/9e04213bc806421d8e64c9c9c23f26d3.json --reason "assets/imported grew from legitimate post-approval imports; protected snapshot recomputed offline against current repository state" --operator christopher` | 0 | `MESHY REAPPROVE PASS`; the live protected snapshot was rebound offline and the original approval was retained in history |
| `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. /usr/bin/python3 tools/meshy_stage.py resolve-plan --project-root . --contract data/asset_generation/contracts/loot_container_derelict_v1.json --pricing-file data/asset_generation/meshy_pricing_v1.json --reference-root assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088 --reference front=source_front.png --reference side=source_side.png --reference back=source_back.png --reference three_quarter=source_three_quarter.png` | 0 | `MESHY RESOLVE-PLAN PASS`; four references and the provider payload hash were persisted |
| `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. /usr/bin/python3 tools/meshy_stage.py verify --project-root . --contract data/asset_generation/contracts/loot_container_derelict_v1.json --batch-journal assets/_staging/meshy/loot_container_derelict_v1/_batches/9e04213bc806421d8e64c9c9c23f26d3.json --pricing-file data/asset_generation/meshy_pricing_v1.json` on main | 0 | `MESHY VERIFY PASS`; terminal state `COMPLETED`, four verified task IDs, no unresolved entries |
| `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. /usr/bin/python3 tools/meshy_candidate_review.py verify --project-root . --task-dir assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088` | 0 | `MESHY CANDIDATE REVIEW PASS`; `state=promotion_ready` |
| Candidate verify for each of the three sibling task directories | 1 each | `MESHY CANDIDATE REVIEW REJECTED`; each was rejected as superseded by the selected candidate |
| Integrated nine-suite Meshy command from `docs/game/06_validation_plan.md` | 0 | `442 passed in 34.38s` |

The three sibling exit-1 results are expected terminal rejection results, not failed validation of
the selected candidate. The private candidate and preview directories were rehydrated to mode
`0700` with evidence leaves at `0600` for the candidate verification gate, then restored to their
Git-tracked `0755`/`0644` representation.

## Visual verdicts

- **Loot container:** D5 Blender evidence is `PASS` with 792 triangles, 2 materials, and UVs;
  D6 runtime evidence passes six locked-isometric cases across seeds `42` and `777` and
  `normal`, `emergency`, and `dark` lighting; the selected candidate is `promotion_ready`.
  D8 remains proposal-only: no live imported asset or sidecar target was written.
- **Focused Nine:** historical comparison proof is staging/validation PASS and explicitly
  non-promoted. Current ownership and airlock cards remain blocked; no fresh visual acceptance
  was asserted.
- **ithappy:** historical full-conversion proof is explicitly pending Godot import verification;
  it is not used as current runtime evidence.
- Image existence, a machine validation report, a board status, or an old PASS paragraph was not
  treated as human/art or gameplay-scale acceptance. The current D6 report is included because it
  records the exact six-case runtime review and passes its evidence contract.

## Promotion diffs

- D8 added only the staged `sidecar-overlay.json` proposal under the selected task directory; it
  did not write `assets/imported`, `data/combat`, `data/props`, `scenes/wrappers`, generated
  indexes, runtime catalogs, or gameplay data.
- The proposal target
  `res://assets/imported/props/dressing/loot_container_derelict_v1.sidecar.json` is descriptive
  and absent. Applying it is a separate future operation per plan Task I.
- The main checkout's pre-existing tracked and untracked changes remain excluded from this docs
  branch and were not reclassified as task output.

## Reconciled former blockers

- Protected-surface drift was resolved by offline reapproval: the current approval snapshot is
  `assets/imported` SHA-256 `4842dcc36a48f47c63850433d56763b7a4957bcc4031788d702315e9d93c42e7`, size
  `2528217250`; the original approval remains in append-only `approval_history` with SHA-256
  `0ad2fc66f53680b0f772f9344c215ddaaed35a69cb61a60b0bfc7d13610ee39c`, size `1922700132`.
- The three pending candidate-review blockers were resolved: the siblings are explicitly rejected
  as superseded, while candidate `01a05dcb-fc3b-7418-b105-2170af354088` is `promotion_ready`.
- The `references_resolved=false` blocker was resolved: the tracked loot plan persists
  `references_resolved=true`, four resolved references, and provider payload SHA-256
  `e1cadfd6f2292bbd6cff38956fe6d2d0287d4f94d4523a5ff0bce4d63a2d90b7`.

## Known blockers

1. The promotion proposal is staged but not applied: applying `sidecar-overlay.json` to live
   `assets/imported` is a separate future operation per plan Task I; no promotion is claimed here.
