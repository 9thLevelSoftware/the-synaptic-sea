MODULAR-FIT PIPELINE UPDATE — VERIFIED

Commit: bfbb12c6884659e4c5cd34a2a5aa852925f0ddaa
Branch: feat/blender-room-kit-v2
Workspace: /Volumes/Untitled/SynapticSeaAssets/worktrees/room-kit-v2

Implemented
- Versioned canonical art measurements: data/art/structural_visual_dimensions.v1.json.
- Separate snapping footprint, traversable opening, visual envelope, protected joining interfaces, and existing gameplay collision/navigation ownership.
- Native-runtime triangle validation after real Blender GLB import. Checks geometry, not just GLB accessor bounds or helper attestations.
- Mandatory validation in structural CLI and Blender add-on export; separate Blender validation process preserves unsaved authoring scenes.
- Rollback-safe multi-variant publication shared by CLI, add-on and promoter; recoverable backups retained if rollback cannot finish.
- Cancelled source loads and compensated mesh-origin transforms rejected.
- Updated artist workflow, source pipeline, room-kit specification, ADR, and reusable default-profile Blender/Synaptic Sea skills.

Primary guideline
/Volumes/Untitled/SynapticSeaAssets/worktrees/room-kit-v2/docs/game/features/modular_structural_fit.md

Verification
- 58 focused tests passed (0 failures/errors/skips): final-focused-tests.xml and final-focused-tests.log.
- 15/15 actual Blender fixture outcomes matched: 7 valid core profiles, plus raised floor, recessed wall join, excess wall thickness, leaked collision helper, translated mesh, compensated mesh origin, sealed doorway, and unsupported ramp. Source BLEND/GLB bytes stayed unchanged during each validation.
- Genuine add-on path: valid export accepted, invalid unsaved mesh rejected, unsaved scene and mesh preserved, previous staging preserved: final-addon-state.log.
- Real filesystem fault injected at the second new variant: all three previous staged files restored and recovery directory cleaned: final-publication-rollback.log.
- --force --skip-godot --backup cannot bypass source-authority HOLD; neither staging nor backup target created: final-promotion-hold.log.
- Independent bounded integration and final doorway reviews PASS; their exact hashes were reconciled against the committed files.
- 3283 protected worktree files unchanged: protected-final.json.
- Existing regression cohort: 106 passed, 19 failed. The SAME 19 failure IDs reproduce against pinned pre-update code 51f7cf2e9263abd8f9ddfeb9337d34d108c72d37; no newly failing IDs: baseline-comparison.json. This is not a claim that the full repository suite is green.

Limits / next production phase
- Seven per-module profiles are implemented; eight remaining profiles fail closed with HOLD. See module-profile-coverage.json for all 15 IDs.
- Per-module PASS is NOT full-kit assembly, visual approval, provenance approval or runtime promotion. Loopbacks, gap/stack/rotation/cross-kit assemblies, ramp endpoints, and actual Godot Compatibility camera-distance review remain explicit acceptance gates.
- Source authority remains unresolved under the frozen policy. A reviewed authority-contract revision and source reconciliation are required; do not merely flip status strings or force promotion.
- This update does not claim completion of asset authoring, repair of the pre-existing source/fixture failures, or any new runtime asset promotion.
- Legacy recipe behavior was retained; published outputs must use the guarded exporters. A blanket authoring-HOLD experiment was removed rather than disabling unrelated established diagnostics.

Reproduction
Use /opt/homebrew/bin/python3.11 with PYTHONPATH set to this worktree and TMPDIR set to artifacts/room_kit_v2/pipeline-update/tmp. Blender: /opt/homebrew/bin/blender.
The fixture generation, actual CLI, GUI and filesystem probes are retained beside this report. They create TEST FIXTURES only, not production assets.
characterize_baseline.py loads pinned pre-update code in a disposable process; it does not revert the checkout.
