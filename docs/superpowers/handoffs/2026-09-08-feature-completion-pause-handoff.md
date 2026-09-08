# Feature-completion pause handoff — 2026-09-08

## Pause and objective

Work is paused at the user's explicit request. Do not resume implementation,
testing, or background work until the user asks. The full feature-completion goal
remains unfinished; this is a recovery checkpoint, not an acceptance declaration.

The objective remains completion of the documented game systems, especially
crafting and derelict repair/rebuilding, with functioning player journeys and
whole-program acceptance. Do not reduce it to the save-migration prerequisites
that occupied this session.

## Authoritative checkout and remote

- Execution worktree: `D:/the-synaptic-sea-feature-completion`.
- Branch: `codex/feature-completion-resume`.
- Last accepted implementation commit: `1e165e50bdd26d801f814ae94c782b71ad20688d`.
- Unaccepted projection WIP checkpoint: `fa2c5fc3` (committed at the user's request after the pause).
- Original user checkout: `D:/the-synaptic-sea`; leave it untouched.
- Remote: `https://github.com/9thLevelSoftware/the-synaptic-sea.git`.
- Earlier PR #548 was merged as `2f9c6913`.
- Pause-time `gh pr list --head codex/feature-completion-resume --state all`
  returned no PR. The user subsequently requested committing and pushing all work. The checkpoint
  branch is the push target; no new PR or merge is part of this handoff.
- Local `origin/main...HEAD` reported 0 behind / 26 ahead before the handoff.
  This uses the local remote-tracking ref; no fresh fetch was performed for pause.

Always set command working directory explicitly to the execution worktree.
Inspect its actual HEAD and status on resume; a later documentation commit can
advance HEAD beyond the implementation commit above.

## Read first on resume

1. `STATUS.md` and this handoff.
2. `docs/superpowers/plans/2026-09-05-remaining-feature-completion.md`.
3. `docs/superpowers/plans/2026-09-04-crafting-derelict-feature-completion.md`.
4. `docs/game/features/crafting_derelict_feature_completion.md`.
5. `.superpowers/sdd/2026-09-05-remaining-feature-completion/progress.md`.
6. `docs/superpowers/handoffs/2026-09-08-parallel-ai-ownership.md`.

The plan-local `.superpowers/sdd/2026-09-05-remaining-feature-completion/`
directory contains authoritative briefs, rulings, review reports, and immutable
review packages. It and many `artifacts/` outputs are local evidence, not a promise
that a fresh clone contains them. Preserve this worktree. Never use `git clean`,
reset it, delete unmerged files, or regenerate evidence over existing results.

## Accepted work — do not repeat

| Slice | Commit | Acceptance boundary |
|---|---|---|
| Corrected physical geometry/docking baseline | `925f3f5c` | Independently reviewed; 15 final cases, 22 qualified public-loader rejection cases, and 60 layout stress cases. Does not close save integration. |
| Public compiled integrity-ID seam | `c3bdf40b` | Actual compiler/seeder ID comparisons passed; independent review approved. |
| Run-7 model and literal historical run-6 closure | `581aec07` | Pose/hallucination keys removed from current run model, 31 summaries, historical closure preserved. Paired migration remains unfinished. |
| World-7 pure snapshot and root-authority model | `14eb8071` | Fixed home root, retained current-owner/anchor closure, cardinal transforms, overflow, duplicate/cycle checks; independent review approved. Live capture/restore remains unfinished. |
| Strict current-integrity admission/application | `1e165e50` | Raw run/home/visited validation, descriptor-authenticated atomic application, exact health preservation, explicit repaired-state semantics, and precision fix; independently approved. |

The latest integrity change includes these five runtime/test files:

- `scripts/systems/module_integrity_map.gd`
- `scripts/systems/module_integrity_state.gd`
- `scripts/systems/run_snapshot.gd`
- `scripts/systems/world_snapshot.gd`
- `scripts/validation/r10a_integrity_admission_smoke.gd`

Its original six-smoke bundle is
`artifacts/feature-completion/R10-A-integrity-admission-final-01`.
Review found integer-to-float precision loss; the meaningful failure and fix are
`R10-A-integrity-admission-fix1-red-01` and
`R10-A-integrity-admission-fix1-green-01`. The latter exited 0 with exactly one
PASS marker, empty stderr/diagnostics, stable source hashes, and a clean P10 probe.
The original reviewer approved the scoped fix with no remaining findings.

Review packages under the plan-local `task-10a-review-packages/` directory:

- `current-integrity-admission-unit5-01`: manifest SHA-256
  `1204f11943a581d7569e024191d34bc511cd7403124def822d9518cb814f70cb`.
- `current-integrity-admission-unit5-fix1-01`: manifest SHA-256
  `f81cb56d3b4395afb9ab022249a1e0ab1eafe3bd2dc60401e7b073d8b4aa5c11`.
- Reports: `r10-current-integrity-admission-review.md` and
  `r10-current-integrity-admission-fix1-review.md` in the plan-local directory.

## Committed WIP: historical attachment projection

These three files were untracked when the pause began and are now preserved in
WIP commit `fa2c5fc3`. They are the reviewed pre-fix implementation, not accepted
work. Preserve them exactly.

| File | SHA-256 at pause |
|---|---|
| `scripts/systems/world_v6_layout_projection.gd` | `e1f8130927b597828b4f7184bf79f83658d542d313577a7e67b96ffabd43663c` |
| `data/migrations/world_v6_geometry_authority_v1.json` | `e9a45432e4b3a28d3d3dd915c892519aaf24470dd6c5b6f372fcf9dbfe9149e1` |
| `scripts/validation/r10a_world6_layout_projection_smoke.gd` | `cb7a6c379b622b4b87c9f63ad698c275d649397961930ab780b8fbf7a61094eb` |

The focused test passed in `R10-A-world6-layout-projection-green-03`, comparing
three independent historical fallback and three authenticated native outputs.
That GREEN did not establish acceptance. Independent review requires all four fixes:

1. **HIGH:** Authenticate the fallback RNG runtime. Admit the historical contract
   and the explicitly approved Windows build `4.7.2.stable.mono.official.ed1daf0bf`;
   never assume arbitrary future engine builds reproduce historical geometry.
2. **HIGH:** Reject incomplete/malformed native documents. Do not skip invalid
   cells, placement rows, room identities, or required positions and authenticate
   the surviving partial document as complete.
3. **HIGH:** Record exact source paths, full blobs, byte hashes, extracted symbols,
   and historical persisted-witness mappings. Keep legitimate threat room/cell
   evidence; remove unsupported objective provenance rather than inventing it.
4. **MEDIUM:** Prove input immutability on negative paths and acceptance when a
   legitimate persisted witness leaves exactly one real candidate.

Review report: plan-local `r10-world6-layout-projection-review.md`, SHA-256
`34444a7862ef83c44654acd7efbcd901b9ead56fe25a4165d3e6712955ea69c1`.
Frozen full diff: `task-10a-review-packages/world6-layout-projection-unit5a-01.diff`.
Implementer report: `artifacts/feature-completion/R10-A-world6-layout-projection-review-package.md`.

Fix round 1 was authorized to the original owner but has no qualified RED/GREEN
run at pause. The three source hashes above still match the pre-fix GREEN-03.
The owner confirmed no production/test fix edits had started. Its detailed note
is plan-local `r10-world6-layout-projection-fix1-pause-handoff.md`, SHA-256
`2a57469ecd5adf904d37106c0e853a0bf8e6ee9770ce5c1a9546178864c7ba92`.
Resume from the worker's pause note and existing preparation; do not redispatch
the complete original implementation or treat its earlier GREEN as final.

The real historical witness chain is
`WorldSnapshot.visited_ships[marker_id].combat.threats[*].{room_id,cell}`.
The owner located the c51 `ThreatAIState`, `ThreatManager`, playable save,
`ShipInstance`, and `WorldSnapshot` producers. Record those exact historical
blobs in the repair. Distinguish them from the later `ThreatSaveContract`
validation gate; do not claim that later validator existed in c51. The later
adapter must validate the complete legacy combat envelope before extracting
nonempty room IDs and finite integer topology-local cells.

## Reference evidence and next migration slice

Historical authority is commit `c51bcacbcb5557fd54ccf5a3e2775f0e35c61bad`.
The exact archived project is under
`artifacts/feature-completion/R10-A-world6-layout-reference-capture/historical-project`.
Keep historical sources immutable; only additive artifact harnesses are permitted.

- `historical-green-01` under that reference-capture directory contains the three
  fallback captures. Its raw result remains RED because of one archived
  RoomAssigner warning for seed -73. A separate root classification accepts that
  exact warning for reference purposes only. It is not a production waiver.
- `native-green-01` contains three clean direct native-v2 reference captures,
  authenticated against DLL SHA-256
  `3279db6338e7af6b54cb4e8c8886d39bdffec73549a25149a05a87d9ebdb8798`.
- `native-document-green-01` contains a clean full native JSON document for strict
  parser development. It is formatted multiline JSON, not a single line. Root
  parsed schema `1.2.0`, `document_kind=ship_layout`, and 16 rooms. Manifest SHA-256:
  `6115adb5927eacb7bf5380261bc7c4890934b7959eb09a66dfb692d801582c17`.

The next bounded production slice is **Unit 5B1, historical integrity
reconstruction**, governed by commit `e46673d4`. Its detailed proposal is
plan-local `r10-world6-integrity-unit5b1-proposal.md`.
It must wait for accepted attachment projection before modifying the shared
projector/authority files. It reconstructs actual old plans and old damage only;
current half-span/vertex mapping is a later Unit 5B2.

Critical contract: missing or `{}` integrity means reconstruct generated historical
damage; present null/non-Dictionary rejects; a valid nonempty envelope with
`deltas: []` means explicitly fully repaired and suppresses generated damage.
Use actual c51 generation/compiler/mutator order. Only the later corrected current
target uses the final current post-authoring plan. Copy exact uniform health to
physical claimants; conflicting vertex contributors or ambiguous payloads reject
atomically. Never divide, average, silently discard damage, or infer a save's route
from unavailable native support.

The 25 historical sources and 16 sorted contract files are extracted at
`task-10a-review-packages/world6-integrity-authority-01` in the plan-local directory.
Use **manifest02.json**, SHA-256
`2f8c4d34b128ce627bb641529b107d1e3dd222f472c1be3de924534b552cebac`.
Root verified all 25 source bytes. The original manifest/report contains a worker
transcription error and a false mismatch claim, explicitly retracted in
`correction-addendum.md`; the source bytes and proposal were correct.

An artifact-only historical damage-reference worker was preparing original c51
fixed/fallback full-plan, generated damage, registered-ID, and sparse-summary
captures. No test request from that worker had entered the lane at pause. Its
outputs must not be confused with completed native attachment captures. Native
structural/damage parity and B1 implementation are still unproved.
The reference worker confirmed preparation only: no harness was created and no
Godot run was requested. Its note is
`artifacts/feature-completion/R10-A-world6-integrity-reference-capture/PAUSE_HANDOFF.md`,
SHA-256 `c2645c24ae169a64d33a93d94ea82d3ab16622f843088d74be59b18d2626eff8`.
Resolve the actual historical fixed-home source/loader path before writing that
harness; do not substitute a convenient procedural seed for the production home.

## Resume sequence

1. Confirm explicit user authorization to resume, worktree/HEAD/status, and the
   pause notes. Reconcile live agent handles; completed/missing handles can be
   replaced with bounded briefs, but never restart solely after an observation timeout.
2. Complete attachment fix round 1 on only its three files. Obtain meaningful
   RED and clean focused GREEN through the isolated lane; preserve six reference
   comparisons. Freeze an exact fix package and request the same reviewer's
   scoped re-review. Resolve all findings before accepting/committing the slice.
3. Finish independent historical damage-reference captures using the original c51
   pipeline. Do not use the new migration implementation as its own oracle.
4. Implement and independently review Unit 5B1 after its prerequisites clear,
   then Unit 5B2 mapping through the accepted public compiled-ID seam and strict
   integrity application API.
5. Complete detached world-6 to world-7 docking/combat/integrity migration,
   explicit service wiring, live capture/staged restoration, and transient
   hallucination reset. Preserve exact owner-local poses, durable endpoint states,
   root authority, atomic publication, and historical fixture bytes.
6. Resume the natural crafting/repair/rebuild journey and remaining program below.

## Remaining full program and external ownership

Do not infer completion percentages from counts of passing focused tests.
Remaining work includes natural starter/donor/advanced crafting proof; machinery
condition; paid repair; live cart/drop/component blockers; candidate egress and
support; timed rebuilding; atomic scene replacement; final economy qualification;
persistence; claim/pilot/travel; player UX; and an ordinary cold-start journey.
R17 domain closure, fresh full regression/G5, and Windows export/performance/
compatibility/G6 obligations remain. Do not fabricate human acceptance.

External AI ownership remains reserved for **R17 UI/accessibility, authored audio
bus configuration, and threat flee-path correctness**. See the parallel ownership
handoff for exact boundaries and briefs. Do not take over those files on resume
without reconciling the other AI's work. Use a separate worktree for that AI and
integrate reviewed commits; it must not overwrite this execution worktree.

## Validation and operational constraints

- Follow the requested `superpowers:subagent-driven-development` workflow:
  bounded implementation, independent review, fixes/re-review, then acceptance.
- Follow repository Stage-Gate scope before edits; maintain board
  `synaptic-sea-stage-gate`. Root owns shared governance/Git/integration.
- Frozen scope: 668 recorded rows, 657 active, 11 deferred, 622 distinct active
  criteria. Canonical regression remains 652 commands. Latest registry checks:
  `FEATURE ACCEPTANCE REGISTRY PASS criteria=668 unassessed_sources=0`,
  27 registry tests passed, orphan classification passed with 218 orphans.
- Follow `docs/game/06_validation_plan.md` for the full bundle and exact marker
  `SYNAPTIC_SEA REGRESSION PASS commands=652 clean_output=true`.
  No fresh full regression has qualified the latest work.
- Accepted Windows runtime is ADR-0060's Godot 4.7.2 Mono executable:
  `C:/Users/dasbl/Downloads/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`.
- Python: `.superpowers/test-runtime/Scripts/python.exe`.
  Bash: `C:/Program Files/Git/bin/bash.exe`.
- Godot tests use fresh isolated APPDATA, LOCALAPPDATA, GODOT_USER_PATH, and
  XDG_DATA_HOME roots plus P10 containment proof. Never use the user's default
  save profile. Retain raw stdout/stderr, exact marker count, source hashes, and
  result manifests; a directory named GREEN or exit 0 alone is not proof.
- At pause the sole test lane confirmed **no active execution/session/process**.
  Pending attachment fix tests and damage-reference tests were not started.
  Both implementation/preparation workers also confirmed they had stopped and
  had no active process or tool session.
- `.godot` modifications, UID/import sidecars, local profiles, ignored evidence,
  and unrelated untracked files remain. Preserve them; do not blanket-stage or
  clean them. The projection sources above are committed, intentionally unaccepted WIP.

## Pause notes

The user-requested pause supersedes automatic goal continuation. Keep the goal
unfinished and paused by user intent; do not label this a technical blocker or
mark the full objective complete. This handoff records known state without
authorizing further work.

## Portable evidence checkpoint

`2026-09-08-resume-evidence.zip` alongside this document preserves 332 selected
plan-local briefs/reports, review packages, historical authority sources, capture
harnesses, and raw evidence files at their original repository-relative paths.
It includes `RESUME_EVIDENCE_MANIFEST.json` with per-file SHA-256 hashes. Archive
SHA-256: `e9df8e8b18b0fd9a8a4c276efbed0cb13ed6db7f2beecc63c47b85dfa65e588c`.
The archive integrity check passed. Extract into a temporary location first and
reconcile with existing local evidence; do not overwrite newer work blindly.
The full archived Godot project is recoverable from pinned c51 Git sources and
is not duplicated in this archive. Generated caches and test profiles are not
part of the source checkpoint and remain preserved locally.
