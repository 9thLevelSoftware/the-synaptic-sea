# Asset-pipeline closure baseline proof

Task A only: freeze a non-destructive baseline and reconcile ownership. Observed at
`2026-09-04 23:53:49 EDT` (`2026-09-05T03:53:49Z`). No provider call, asset generation,
Blender authoring, runtime capture, promotion, or source edit was performed by this task.
Evidence was read from the repository, the existing Meshy worktree, the board database, and
external source receipts; historical PASS prose is not treated as fresh acceptance evidence.

## Tested commit

- Main checkout: `/Users/christopherwilloughby/Code/the-synaptic-sea`.
- Main branch at inspection: `main`.
- Main `HEAD`: `f4a656692606e23813df68d24daba4c5e4a0151b`.
- Isolated worktree: `/Users/christopherwilloughby/Code/the-synaptic-sea-asset-pipeline-closure`.
- Isolated branch: `fix/asset-pipeline-closure`.
- Isolated worktree `HEAD`: `f4a656692606e23813df68d24daba4c5e4a0151b`.
- The isolated worktree was created from the exact main `HEAD`, was clean before the scoped
  gate, and remained clean until this proof was created.

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

The isolated worktree at `/Users/christopherwilloughby/Code/the-synaptic-sea-asset-pipeline-closure` was created by Task A3 during execution from the recorded baseline; it was not a pre-existing worktree observed before this task.

Recent main history at the baseline: `f4a65669 Merge pull request #547 from
9thLevelSoftware/fix/meshy-runtime-dual-hash-binding`, `f84ff366 test: align promotion
fixture with runtime evidence`, `9c9899bf fix: bind runtime visibility evidence`, `69b1e1d0
Merge pull request #546 from 9thLevelSoftware/cursor/hinge-sample-semantics-c965`, and
`8e226670 fix: use local transforms for runtime cutaway`.

During final verification, the separate main checkout advanced independently from the recorded
baseline to `5240a42fdd4309c5c6ded45fba3ca05144b391ce` through commits `e1407d63` and
`5240a42f`. Its remaining status was 4 tracked modifications and 2,202 untracked paths.
The isolated Task A worktree stayed at the recorded `f4a656692606e23813df68d24daba4c5e4a0151b`
commit; no attempt was made to reconcile or modify main.

## Toolchain

The plan-required environment was used in the isolated worktree:

| Tool | Path | Observed version | exit |
|---|---|---|---:|
| Python | `/opt/homebrew/bin/python3.11` | `Python 3.11.15` | 0 |
| Godot | `/opt/homebrew/bin/godot` | `4.7.1.stable.official.a13da4feb` | 0 |
| Blender | `/opt/homebrew/bin/blender` | `Blender 5.2.0 LTS`, build date `2026-07-14` | 0 |

The scoped gate used `PYTHONPATH=.`, `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1`, and
`PYTHONDONTWRITEBYTECODE=1`.

## Dirty-source exclusions

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
| BASE-002 | The scoped Python pipeline gate must be run without hiding failures | Exact Task A4 pytest command; `528 passed, 5 failed, 44 subtests passed` | Meshy/Blender evidence | BLOCKED | Five named loot tests fail on missing task-local `raw.glb`; rerun after exact evidence rehydration |
| BASE-003 | Selected loot evidence must bind raw, cleaned, Blender, runtime, and promotion records | Meshy worktree task `01a05dcb-fc3b-7418-b105-2170af354088`; `review.json.state=selected`; no `runtime-review.json`; no live-pilot directory | Loot evidence lane | BLOCKED | Reconcile exact task evidence, run fresh six-case runtime review, then verify candidate state |
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

- Main and isolated baseline both resolve to `f4a656692606e23813df68d24daba4c5e4a0151b`.
- Main and the existing Meshy worktree contain the same five read-only plan envelopes under
  `assets/_staging/meshy/_plans/`: `biomatter_swarm_kit_v1.json` (`112f9998...`),
  `crafting_station_derelict_v1.json` (`87a5a058...`), `hull_tendril_kit_v1.json`
  (`feb2b227...`), `loot_container_derelict_v1.json` (`8cd0b5db...`), and `stalker_v1.json`
  (`e44cd28c...`). These are planning records, not provider execution or promotion evidence.
- Main contains historical `stalker_v1` task records with contract/generation/review JSON and
  a mixture of raw outputs; no selected loot evidence is present in main.

### Existing Meshy loot evidence

The existing Meshy worktree is
`/Volumes/Untitled/HermesOffload/christopherwilloughby/.hermes/worktrees/the-synaptic-sea/meshy-blender-asset-system`.
Its loot batch journal is `_batches/9e04213bc806421d8e64c9c9c23f26d3.json`, size `3,180`,
SHA-256 `c4b5be55db4f433ff9e2be57b9f5161701beb974d71c4455ab44c4d104376a15`.

Four candidate records were present. Contract SHA-256 was `a6227476...` for each candidate;
the following file hashes were observed:

| candidate | generation.json | review.json state | raw.glb | cleaned.glb / Blender report |
|---|---|---|---|---|
| `01a05d53-a25e-73e9-9b2a-376899969470` | `3d981f04...` | `pending` | 58,192 bytes, `46358dce...` | absent / absent |
| `01a05dcb-fc3b-7418-b105-2170af354088` | `19af8fde...` | `selected` | 58,720 bytes, `ff07ca3f0e87e29fb1a77c007cf261920ac370f870ead9c21446b4ad1f15e377` | 67,188 bytes, `eebcead4...` / report `4a205a23...` |
| `01a05dcc-80b8-74ef-8c40-6f4e6d414cc3` | `d97a6cbe...` | `pending` | 55,440 bytes, `6e286803...` | absent / absent |
| `01a05dcd-5f42-7694-a318-fb104d459344` | `5939b931...` | `pending` | 57,380 bytes, `436c3c34...` | absent / absent |

For selected task `01a05dcb-fc3b-7418-b105-2170af354088`:

- `contract.json`: 1,286 bytes, SHA-256 `a6227476a16d51288eb2dc588b032b55c3b0dcd758210a4d427c6643642cf1e0`.
- `generation.json`: 2,888 bytes, SHA-256 `19af8fde5bf8f42bbb3aefbe4584b6029283dc2ccc1537102c1e3cca7356b1a5`; its
  `outputs.raw.glb` hash matches the observed raw file `ff07ca3f...`.
- `review.json`: 451 bytes, SHA-256 `fd2df22a099e687e20719d6cf3b891c24c5127db18e947bcf308c69d293aa3ff`; state remains
  `selected`, decision `accept_for_cleanup`, with all six candidate checks true.
- `raw.glb`: 58,720 bytes, SHA-256 `ff07ca3f0e87e29fb1a77c007cf261920ac370f870ead9c21446b4ad1f15e377`.
- `cleaned.glb`: 67,188 bytes, SHA-256 `eebcead4f6620845dcc53819fff0e600ebc409435598dfedc259254640bfca92`.
- `blender-validation.json`: 1,441 bytes, SHA-256 `4a205a236fc063ebc73648aa8081bd9067ee1b6848bce0c00a37f6c4d4589ace`; report status
  is `PASS`, with 792 triangles, six meshes, UV evidence, and `master_provenance: null`.
- `runtime-review.json` is absent. The expected external live-pilot directory
  `/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088`
  is absent.
- External master receipt `build_recipe_manifest.json`: 1,232 bytes, SHA-256
  `0bb2dc885e98d4e6cce9bd82bdca0269f37fb457f8ffec2807d45e84bd77aa93`. External master
  `loot_container_derelict_v1_master.blend`: 177,620 bytes, SHA-256
  `85a31b4bd06a24566ca88894fc181f95461a2a00aef67bc3494510291bdf651b`. The receipt binds the
  selected task and raw hash, records `source_raw_preserved: true`, and records
  `runtime_promoted: false`.

No evidence was copied from the existing Meshy worktree into this isolated worktree because the
selected task's full promotion prerequisite set is not verified and the scoped gate must remain
non-destructive.

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
| `git worktree add -b fix/asset-pipeline-closure /Users/christopherwilloughby/Code/the-synaptic-sea-asset-pipeline-closure f4a656692606e23813df68d24daba4c5e4a0151b` | 0 | New clean isolated branch at the requested baseline |
| `/opt/homebrew/bin/python3.11 --version` | 0 | Python 3.11.15 |
| `/opt/homebrew/bin/godot --version` | 0 | Godot 4.7.1 stable |
| `/opt/homebrew/bin/blender --version` | 0 | Blender 5.2.0 LTS |
| `PYTHONPATH=. PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 /opt/homebrew/bin/python3.11 -m pytest -q -p no:cacheprovider tests/test_meshy_asset_contract.py tests/test_meshy_stage.py tests/test_meshy_governance.py tests/test_meshy_candidate_review.py tests/test_meshy_blender_tools.py tests/test_meshy_loot_container_recipe.py tests/test_meshy_texture_packet.py tests/test_meshy_promotion_packet.py tests/test_meshy_runtime_review.py tests/test_prop_visual_metadata.py tests/test_validate_prop_visual_bindings.py` | 1 | `528 passed, 5 failed, 44 subtests passed` — five failures caused by missing task-local `raw.glb`; see below. |
| Read-only board SQLite query for `synaptic-sea-stage-gate` | 0 | Asset/refinement/runtime-review statuses and dependencies recorded above |
| Read-only evidence inventory/hash comparison | 0 | Main, Meshy worktree, selected task, master receipt, and historical proofs inventoried |
| `git status --short --branch` in isolated worktree before proof creation | 0 | `fix/asset-pipeline-closure`; clean |

The five failing tests were exactly:

- `tests/test_meshy_loot_container_recipe.py::test_real_blender_recipe_is_deterministic_and_preserves_disposable_master`
- `tests/test_meshy_loot_container_recipe.py::test_real_blender_front_hardware_geometry_and_hinge_follow`
- `tests/test_meshy_loot_container_recipe.py::test_real_blender_recipe_rejects_unowned_generated_name_collision`
- `tests/test_meshy_loot_container_recipe.py::test_real_blender_recipe_is_idempotent_on_same_disposable_generated_master`
- `tests/test_meshy_loot_container_recipe.py::test_real_private_glb_uses_contract_dimension_order_for_pure_validator`

The first, second, and fifth fail at their assertion that the canonical external master and
main-relative task-local raw path exist. The third and fourth fail while copying that same
missing task-local `raw.glb`. The five real-Blender loot paths therefore did not reach their
recipe operation; the missing bound raw artifact is recorded as a blocker, not bypassed.

## Visual verdicts

- **Loot container:** no fresh runtime visual verdict. The selected candidate has a machine
  Blender validation report with status `PASS`, but the candidate remains `selected`, not
  `promotion_ready`; runtime evidence is absent and no promotion is claimed.
- **Focused Nine:** historical comparison proof is staging/validation PASS and explicitly
  non-promoted. Current ownership and airlock cards remain blocked; no fresh visual acceptance
  was asserted.
- **ithappy:** historical full-conversion proof is explicitly pending Godot import verification;
  it is not used as current runtime evidence.
- Image existence, a machine validation report, a board status, or an old PASS paragraph was not
  treated as human/art or gameplay-scale acceptance.

## Promotion diffs

- Task A made no promotion diff and did not write `assets/imported`, `data/combat`, `data/props`,
  `scenes/wrappers`, generated indexes, runtime catalogs, or gameplay data.
- The isolated worktree had no diff before the proof was created. The main checkout's pre-existing
  tracked and untracked changes remain excluded and were not reclassified as Task A output.
- The only intended commit content is this proof document.

## Known blockers

1. The isolated baseline lacks the exact task-local loot raw artifact at
   `assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088/raw.glb`,
   causing the five exact scoped-test failures. Do not fabricate or regenerate it through Meshy;
   rehydrate only from a verified immutable source with matching identity and hash.
2. The selected loot record has Blender evidence but no task-local runtime report, no live-pilot
   evidence directory, and `review.json.state=selected`; it is not promotion-ready.
3. Focused Nine ownership remediation is blocked by the board's fail-closed salvage findings:
   no coherent migration/backups/report, six unowned masters, and three potentially tainted masters.
4. The main checkout remains dirty with user changes and generated/untracked assets. Any later task
   must start from a newly reconciled baseline and must not reset, stash, clean, or mass-stage it.
5. Existing historical proofs are retained as audit context only. They do not close current runtime,
   ownership, evidence, or promotion gates.
