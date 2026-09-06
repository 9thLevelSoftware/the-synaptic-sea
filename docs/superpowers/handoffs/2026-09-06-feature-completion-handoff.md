# Feature-completion pause and resume handoff — 2026-09-06

## Read this first

**Paused at the user's request. Do not automatically continue implementation.**
The user asked for a good stopping point, a resume handoff, and a commit of the
current changes because the work had taken longer than expected. This is a WIP
checkpoint, not a feature-complete release or an accepted R10-A implementation.

Resume in **`D:/the-synaptic-sea-feature-completion`**, branch
**`codex/feature-completion`**. Preserve the original user checkout at
`D:/the-synaptic-sea`. No merge, push, or publication was requested or performed.
The checkpoint intentionally commits the previously uncommitted integrated
runtime work; that commit does not retroactively give every change independent
review or fresh whole-game acceptance.

The user's priorities remain working game systems, honest completion accounting,
crafting, and derelict repair/rebuild. Execute the remaining program using
`superpowers:subagent-driven-development` and the repository's cost-aware agent
policy after the user explicitly resumes. Root coordinates and owns the index;
Luna handles retrieval/checks, Terra ordinary implementation, and Sol difficult
integration and independent review. Preserve other agents' work. Do not spawn
redundant reviews or reimplement already accepted slices.

## Authoritative documents and portable evidence

- [Remaining R01–R19 execution plan](../plans/2026-09-05-remaining-feature-completion.md).
- [Original P00–P24 plan](../plans/2026-09-04-crafting-derelict-feature-completion.md).
- [Feature specification](../../game/features/crafting_derelict_feature_completion.md).
- [Project status](../../../STATUS.md).
- ADRs 0059 (transactions/persistence), 0065 (structural safety/docking), and
  0066 (machinery condition), under `docs/game/adr/`.
- Registry: `docs/game/inventory/feature_acceptance.json`; generator:
  `tools/build_feature_acceptance.py`; local board cards:
  `data/validation/feature_completion_cards.json`.

The detailed execution record is in
`.superpowers/sdd/2026-09-05-remaining-feature-completion/`, especially
`progress.md`, `task-10a-brief.md`, and `task-10a-report.md`. A tracked compressed
copy of this entire plan workspace is retained at
`artifacts/handoffs/2026-09-06-feature-completion-sdd.tar.gz`, with its SHA-256
and checkpoint inventory beside it. It contains task briefs, reviews,
beforeimages, frozen source packages, and raw evidence; it excludes the separate
toolchain and Python environment. On a fresh clone, extract it to the repository
root to restore the same `.superpowers/sdd/...` relative paths. Do not overwrite
a newer local execution record; compare the recorded hashes first.

Other retained test evidence is under `artifacts/feature-completion/`.
Transient `.tmp*`, `.p0*`, `.cargo*`, `.obj*`, `.widget*`, and Godot cache folders
remain local, outside the checkpoint's project-file commit. Their inventory is
recorded with the handoff. They contain large scratch logs and synthetic test
profiles; do not delete them or confuse them with accepted evidence. The local
GDAI plugin remains excluded. The original checkout is untouched.

## Completion accounting

The frozen registry has **668 source rows, 657 active rows, 11 deferrals, and
622 distinct active criteria** after 35 reviewed aliases. Do not replace this
denominator with the count of passing smokes or completed R packages.

- Scope fingerprint:
  `8041e481680152f85fe2d3617491880a5268d89dcb63a59608590711edef48d0`.
- Supersession fingerprint:
  `ffe325ef281156711db10d85eb896a4781804ec976944aef4a948bdbe12ad0df`.
- Source-audit mapping reached 168 semantic mappings / 489 active complement;
  evidence mapping is incomplete. These are source-coverage counts, not runtime
  acceptance or product completion percentages.
- R01, R02, R03, and R06 have accepted bounded outcomes. R04's economy checker
  component and the R10-A runner component are reviewed. The rest of those
  parent packages remain open.
- Overall feature-completion percentages remain **unknown**, not zero and not
  inferred from the above counts. No full G1–G6 claim is justified.
- External synchronization of `synaptic-sea-stage-gate` remains pending; local
  generated cards are the available record. No callable board connector was
  found in the current session.

## Accepted work to preserve

**R01:** evidence/WIP reconciliation, stable scope, honest unknown coverage.
Reviewed at `a12d3eed`. P13 run8 logs are historical: their exact source snapshot
is unavailable, and an older unrelated manifest must never be paired with them.

**R02/R03:** strict paired run6/world6 persistence, nested threat-manager-2,
legacy hull-tendril `structure_damage = 0.4`, exact combat behavior after load,
atomic detached restore, full-precision round trips, real manual/quick/auto/title
load paths, rollback of live owners/settings/audio/camera/source bytes, and
three independent processes. R03 retained 16 focused cases, 47 Python tests,
and a clean three-process proof. Its report/review and source packages are in
the execution archive. Preserve the sole explicitly accepted comparison
exception: the derived Boolean home oxygen `player_in_breach_zone` projection.
Do not introduce tolerances or ignored fields to obtain save equality.

**R06:** physical work uses authenticated live target range and fresh occupancy,
with exact escrow/refunds, no invalid effects, and reentrancy/duplicate completion
coverage. Final independent review after fix round 2:
`2e6407eda76990daf265cdec5fb7017d83633aadc9e0b4ec879e01a4e171a453`.
Evidence includes four canonical P10–P13 runs, twelve focused cases, 36 Python
tests, and the retained direct-snapshot check from fix round 1. The plan's four
R06 bullets are now checked. Acceptance is pinned to its exact reviewed source
packages, not every later change to the coordinator.

**R04 economy component:** checker and negative tests independently approved;
final production proof pin remains deliberately fail-closed. R04 exits on real
natural routes plus provisional graph checks. R05 pins the final economy source
only after reviewed R11 rebuild integration; do not reintroduce that dependency
cycle. No resource/skill injection or forced repairs count as natural acquisition.

**Reviewed R10-A runner:** `tools/run_r10a_docking_smokes.py` and its tests were
committed at `73233569`; ten Python tests passed. The runner uses the hardened
isolation seam and 15 prerequisite cases. The R04 natural route is separate and
must run last, not as a tolerated failure inside the prerequisite aggregate.

## Current stopping point: R10-A docking prerequisite

**Final quiescent checkpoint:** the implementer stopped with no Godot/Python
processes running and no currently known focused RED. Home production-controller
traversal (`production-traversal-dev-04`) and away traversal
(`away-production-traversal-dev-01`) both pass. A prior
`baseline-aggregate-dev-01` passed all 15 cases, but predates the final occupancy
and marker refinements; a new full aggregate and independent review remain
pending. The stopping report SHA-256 is
`e5b3fa2df9f0519d0d6fb2f254c9d3352ef95e1a1ee4b58218ba9b53d86194cc`.
Its exact 22-source checkpoint manifest is
`task-10a-work-evidence/runtime-checkpoint-handoff-01/source_manifest.json`, SHA-256
`7f9be8d323474cd532884a538edbea61198f2f586ed076a7a2d80fbe1b029f43`.

Root's fresh stopping checks passed: registry consistency (668 criteria,
zero unassessed sources) and 19 Python tests across collision projection and
the R10-A runner. These checks do not replace the pending gameplay aggregate.

R10-A was introduced because the natural crafting route was physically blocked
by overlapping docked hulls and an obsolete ceiling collider. R10-B still owns
the later rebuild candidate egress/support work. Do not emit full FC P17
acceptance from this baseline repair.

Implemented WIP at this checkpoint includes:

1. A deterministic `dock_collision_projection_v1` in
   `data/kits/ship_structural_v0.json`, generated by
   `tools/build_dock_collision_projection.py` from contract-selected wrapper
   scenes. The current catalog has 15 wrappers / 21 boxes. It records stable
   paths, composed transforms, dimensions, and source/content hashes.
2. Binary32 bit normalization shared across Python and Godot. A real nested
   fractional `ResourceLoader` fixture exposed and corrected a row/column basis
   ordering error. Runtime verifies materialized paths/transforms/dimensions and
   content fingerprints; it does not depend on raw `.tscn` source bytes being
   available in an exported game. Source-byte hashes remain build provenance.
3. Authentic exterior endpoint authoring for fixed lifeboat, home/fallback, and
   native generation. Port position is derived from the actual doorway frame's
   outer collision face, with exact quarter-turn bases. The former west
   lifeboat airlock/engine seam is an internal seam and is not an exterior port.
4. A shared pure static pair predicate for author-time compatible-pair search
   and live docking preflight. Every non-join positive-volume overlap rejects.
   Only authenticated frame/incident-floor join portions can use the exact
   bounded seam envelope. No global margin, epsilon, or opaque-wall waiver.
5. Corrected ceiling physical bounds: floor-relative y=3.8..4.0, size
   4×0.2×4, center `(0, 3.9, 0)`. Visual bounds remain separate. No corner
   wrapper geometry was changed to hide docking failures.
6. A real barrier and controlled bidirectional grounded CharacterBody traversal
   across the 0.2m seam. Analytic support and physical traversal did not require
   an additional sill.
7. A strict authored initial lifeboat spawn and explicit boot failure propagation
   before `playable_ready`. The original `(4,.55,0)` point collided with a corner;
   the measured clear interior anchor `(4,.55,-1.1)` is used. Missing, malformed,
   foreign-owner and blocked spawn cases have focused passing evidence.

Important retained development evidence under `task-10a-work-evidence/`:

- `recovery-aggregate-01`: 8/15 passed; historical development baseline.
- `projection-character-aggregate-01`: 10/15 passed.
- `pair-selection-dev-01`: 14/15 passed; only the then-stale dock-port assertion
  failed. Includes clean physical travel, boot, occupancy and existing save cases.
- `pair-selection-contract-dev-02`: deterministic selection assertion passes.
- `dock-ports-retired-contract-dev-01`: corrected port-contract case passes.
- `spawn-clearance-contract-dev-01`: valid and invalid authored spawn checks pass.
- `character-traversal-dev-01`: controlled character fixture only, not the final
  production-controller/player-route claim.

The native first target (seed42, size0, condition2) had 32 candidate exterior
edges. Old first-supporting edge `0|h|7|8` collided twice with the lifeboat's
`wall_outer_corner` WingEast. Pair-aware selection chooses `0|v|3|3` and passes
live docking. Seed777 retains its valid original selection. Full measured
rejected/selected coordinates are in `pair-selection-diagnostic-03/04` and the
ledger. This proves canonical lifeboat pairing only; claimed-ship pairing remains
an R14 obligation.

### Immediate unfinished baseline issue

Production-controller traversal exposed merged room AABBs overlapping across the
dock. Piloted-first occupancy incorrectly kept the player on the lifeboat after
physically crossing to the home interior. The current WIP resolves that overlap
using the authenticated connection plane. **Read the final stopping report before
assuming this last change is fully tested.** Preserve these rulings:

- Exact shared threshold/tie belongs to the mobile endpoint, consistent with
  future saved threshold-pose ownership.
- Authenticate the current connection and endpoint IDs; a marker ID alone is
  not authority.
- Closing a door behind a player on the host side must not assign them back to
  the mobile ship. Closed-state shortcuts cannot replace geometric ownership.
- Prove ordinary production inputs, grounded crossing and occupancy both ways,
  plane tie, initial closed spawn, closing from each side, and away/return.
- The independently identified initial spawn may reuse a capsule-clear interior
  anchor but remains distinct from the threshold. Reconcile ADR/spec/card wording
  that still unnecessarily requires it to differ from both clearance anchors.
- Update the stale canonical-opening overlap comment and misleading
  `aboard_derelict=true` suffix consistently with the actual lifeboat assertion;
  preserve historical logs.

Before resuming schema work: finish this bounded baseline, synchronize governance
and report chronology, run the 15-case aggregate on one stable source set, freeze
an exact component package, and obtain independent review. No geometry-component
review was completed at the point the user requested a pause. The final R10-A
integration review is still required after persistence changes.

## R10-A paired persistence: allocated, not implemented

**Do not assume run7/world7 already exists in runtime.** ADR0059 allocates it;
current accepted runtime is run6/world6. The new pair must be changed together.
Full details and negative matrices are in the archived `task-10a-brief.md`.

- World7 owns strict `dock_connections_v1`, `boarding_port_states_v1`, and the
  sole `player_owner_pose_v1` with owner ID, local position, location kind,
  connection ID and endpoint ID. Run7 removes its global `player_position`.
- Reject obsolete current keys, missing/malformed owners/endpoints, impossible
  local poses and unsupported future versions before live mutation. No nearest
  room, clamp, spawn recovery or coordinate guessing.
- Resolve owner roots and connection graph first, then project the exact local
  pose and require capsule clearance. An ephemeral restore receipt may preserve
  the accepted local array only while owner/root revision/body projection remain
  bit-exact unchanged; movement recomputes full-precision local position.
- Legacy world6 uses version-pinned OLD geometry, not corrected current geometry.
  At home, finite embedded home-run position must exactly match the top global
  pose before one owner-aware migration. Away, validate then discard the obsolete
  embedded home departure position; it is not a home-ownership witness.
- Raw standalone run6 must continue explicitly rejecting `unclosed_owner_graph`
  even after the current version becomes 7. Keep literal v5→v6→v7 steps; do not
  use a mutable CURRENT constant as an old migration target. Future sentinels
  move to 8 while old evidence remains retained.
- Rebase world-space combat position/last-known-position through old/new owner
  roots. Ship-local carts, drops, corpses, stations and lot state remain exact.
- ADR0042 removes transient `hallucination_summary`: recognized legacy absent is
  valid; present data is strictly validated then removed from the detached copy.
  Current presence rejects. Explicitly clear director/render timers, FX and HUD
  state before first tick. Preserve durable sanity/vitals and pure director tests.
- Requalify the complete affected P10/R06 save/load/rollback/process matrix,
  then the R10-A prerequisites and separate R04 natural route. Earlier clean
  run6 evidence does not qualify run7.

## Remaining program after R10-A

1. **R04:** real New Game starter, donor and advanced crafting acquisition routes.
2. **R07:** durable machinery condition/effective health. Prepared
   `task-7-brief.md`; runtime not implemented. Effective mapped health is
   `min(intrinsic, max(provider conditions))`; no provider means disconnected.
   Remove install/dismount/restore healing side effects. Preserve quality rules,
   paid repair and exact lots. Durable mapped-target history and nested V3
   require a subsequent outer pair, provisionally run8/world8 after R10 review;
   do not absorb this into run7. Current P10 recapture already rejects ordinary
   projection mismatch; no accepted end-to-end bypass was demonstrated.
3. **R08:** selected paid module/system repair using R07 authority.
4. **R09/R10-B:** live actor/cart/drop/component blockers and candidate egress,
   docking, floor/ceiling support. Pure helper proofs are insufficient.
5. **R11/R12:** real timed rebuild admission and exactly-once atomic scene/state
   replacement. **R05** final crafting/economy proof pin follows reviewed R11.
6. **R13/R14:** rebuilt-ship persistence, claim/pilot/travel and actual consumers.
7. **R15/R16:** restoration UX and an ordinary cold-player journey.
8. **R17:** finish all-domain source audit and demonstrated fixes. Known items
   include authored audio-config bypass (prepared
   `r17-authored-audio-config-brief.md`), incorrect weighted FLEE traversal/tie
   objective, assertion gaps, and reviewed metadata supersessions. Do not delete
   criteria or restore obsolete gameplay to satisfy stale assertions. Audio
   defaults must be detached per manager so overrides cannot mutate cached
   ResourceLoader state or another manager.
9. **R18:** one integrated frozen candidate, complete canonical regression,
   independent whole-source review, accurate per-domain evidence accounting.
10. **R19:** supported Windows offline export, ordinary journey, historical saves,
    actual windowed performance and final evidence packet. Human acceptance must
    be recorded honestly; do not invent it. Publish/merge/push remain separate.

## Toolchain, isolation and resume commands

Accepted engine (ADR0060):
`C:/Users/dasbl/Downloads/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`.
Version: `4.7.2.stable.mono.official.ed1daf0bf`.
Python with pytest: `.superpowers/test-runtime/Scripts/python.exe`.
Git Bash: `C:/Program Files/Git/bin/bash.exe`.

Every Godot body must use the hardened isolated runner seam with a fresh owned
home and **APPDATA, LOCALAPPDATA, GODOT_USER_PATH and XDG_DATA_HOME all pointing
to that home**. A separate no-save P10 probe must prove Godot's resolved
`user://` equals `OS.get_user_data_dir()` and is contained. Unsupported
`--user-data-dir` flags and environment variables alone are not proof. Require
exit0, exact marker once, no unexpected diagnostics, no timeout, raw logs and
source hashes. A zero Godot exit can still contain parse errors.

The default profile is read-only: an earlier R02 test incident wrote it. The
observed afterimage at `artifacts/feature-completion/R02-default-profile-observed-20260905`
is not a beforeimage or recovery guarantee. Never overwrite it as test setup.
Serialize Godot runs and shared coordinator/schema edits against stable sources.

Useful checks after explicit resume (not a claim they ran at this pause):

```powershell
& .superpowers/test-runtime/Scripts/python.exe tools/build_feature_acceptance.py --check
& .superpowers/test-runtime/Scripts/python.exe -m pytest -q tests/test_dock_collision_projection.py tests/test_r10a_docking_runner.py
& 'C:/Program Files/Git/bin/bash.exe' tools/classify_orphan_smokes.sh --check
& .superpowers/test-runtime/Scripts/python.exe tools/run_r10a_docking_smokes.py --help
```

Use a fresh evidence destination for the actual R10-A runner invocation. Full
regression is exactly `docs/game/06_validation_plan.md`; the old shell bundle has
stale macOS engine paths. Preserve strict diagnostic policy. Only the six exact
authored missing AudioLog warnings have a narrowly documented ADR0044
classification; retain raw strict failure and never use a generic warning waiver.

## Export preparation already acquired

The official 4.7.2 Mono archive is cached locally at
`.superpowers/toolchains/godot-4.7.2-mono/Godot_v4.7.2-stable_mono_export_templates.tpz`:
1,202,598,411 bytes, SHA-256
`92f8681e349ef1f90891b792da95e3b2b0bd1ed610b78018c58feb2d87e15a9d`.
The extracted Windows release x86_64 executable is 109,513,728 bytes, SHA-256
`16e0ec3cfd398b938f514de95ff2474b532b5061ada78f92226dba3f7584d55d`.
Do not redownload or install into a real user profile unnecessarily. Official
custom-template preset/discovery options are recorded in the archived
`r19-packaging-implementation-brief.md` and acquisition report.

No export or template installation was performed. The old export script/checker
has macOS/4.6.2 and filename mismatches. The packaging brief requires both source
engine and packaged-executable no-save probes at the correct lifecycle points;
a shell containment check does not replace either. Missing P20–P22 cases,
plugin independence, packaged native DLL loading and actual offline/windowed
player evidence remain open.

## Resume instruction

After the user explicitly resumes: read this handoff, the final stopping report,
the archived ledger and current task10a brief; verify branch/commit, clean project
source status and tool paths; inspect the last actual result; then finish the
bounded R10-A occupancy/traversal/review work before paired migration. Do not
restart the completed R01–R03/R06 program, infer old agent handles still exist,
or interpret this checkpoint commit as whole-game approval.
