# Feature: Governed Meshy-to-Blender Candidate Asset Pipeline

## Status

Implemented and host-verified at toolchain snapshot commit
`4dc9e7d7f7aee2c5884bb72118949583737e8994`. This document records the current CLI and runtime
contracts. Real provider tasks, downloaded candidates, external Blender masters, and six-case
candidate runtime captures remain intentionally reserved for the post-PR live pilot; this
documentation refresh performs no provider call or promotion.

## Scope

This feature defines a fail-closed, candidate-only path for turning rights-cleared reference
images into reviewable game assets. It governs the five pilot assets listed below, the
contract and provenance records around them, the external editable Blender master, normalized
staged GLBs, and temporary Godot runtime evidence.

The authoritative chain is:

> **asset contract -> consistent separate reference images -> Meshy candidate -> Blender canonical master/cleanup -> staged validation -> temporary Godot overlay locked-isometric review -> separate reviewed promotion**

Meshy is a candidate generator only. It cannot author structural floors, walls, doors, ramps,
sockets, collision, or damage topology. A raw candidate never becomes a runtime asset by
being downloaded, selected, textured, or opened by a Godot bridge.

The implemented tools and tests preserve this scope and the protected-path rules below. A real
candidate lifecycle is a separate post-PR pilot and cannot be inferred from host-only evidence.

## Authority and ownership

| Surface | Authoritative owner | Required boundary |
|---|---|---|
| Asset contract | Repository contract/schema and its validator | Defines category, role, dimensions/tolerance, pivot, +Z forward, states, budgets, reference requirements, generation policy, and review matrix before any provider call. |
| Reference images | Asset/content owner and contract packet | Use consistent, separate view files; record rights and hashes. A collage is not a substitute for separate views. |
| Meshy output | Meshy staging adapter, as candidate evidence only | Produce candidate geometry under the contract. Meshy must not author structural geometry, sockets, collision, or damage topology, and must not write a runtime surface. |
| Staged provenance | Immutable generation record plus later review/validation records | Record the validated contract, request, reference hashes, provider/model/task data, output hashes/sizes, license path, consumed credits, and reviewer decisions without secrets or signed URLs. |
| Editable asset master | Blender external `.blend` master | Own editable source, topology, UVs, exact meter scale, pivot, `+Z` forward, derived alternate states, rig, cleanup, and export. Blender validation reports failures; it does not silently invent gameplay collision or damage topology. |
| Runtime behavior | Godot wrappers and repository runtime data | Own collision, navigation, sockets/connectors, integrity/damage state, VFX/animation integration, and gameplay bindings. Visual replacement must not change these contracts. |
| Staged validation | Contract, Blender, provenance, and runtime-review validators | Validate the re-imported normalized GLB and the real production review environment before a promotion packet can be reviewed. |
| Promotion | Separate reviewed task | Apply no live catalog, index, wrapper, or asset promotion as a side effect of generation, cleanup, or runtime review. |

Blender's rig ownership is distinct from runtime animation/VFX integration: Blender creates and
exports the authored rig/state representation; Godot wrappers and repository data decide how
animation and VFX integrate with gameplay.

## Pilot roster

The initial governed pilots are deliberately mixed so the workflow proves static props,
modular kits, and non-humanoid threat forms without expanding structural scope:

| Asset ID | Role in the pilot |
|---|---|
| `stalker_v1` | Threat candidate with a readable stalking silhouette; any rigging decision remains contract- and review-gated. |
| `hull_tendril_kit_v1` | Segmented non-humanoid kit: root, trunk modules, branches, attack tip, and severed tip; Blender owns the segmented-chain rig. |
| `biomatter_swarm_kit_v1` | Modular organism/cluster kit; Godot MultiMesh/particles own swarm behavior, not Meshy. |
| `loot_container_derelict_v1` | Gameplay prop whose closed master yields Blender-derived open/looted states and hinge behavior. |
| `crafting_station_derelict_v1` | Gameplay prop with a clear front-side interaction silhouette and bounded machinery detail. |

## State transitions

The state machine is forward-only except for an explicit rejection or recycle decision. A
candidate cannot skip a gate or become promoted from a generator side effect.

```text
contract_draft
  -> contract_validated
  -> references_validated
  -> credit_gate_ready
  -> candidates_staged
  -> candidate_selected
  -> blender_master_created
  -> cleaned_glb_staged
  -> staged_validation_pass
  -> runtime_review_pass
  -> promotion_review_ready
  -> promoted (separate reviewed task only)
```

Allowed rejection/recycle paths are:

```text
contract_draft       -> rejected
references_validated -> rejected
candidates_staged   -> rejected
candidate_selected   -> rejected
cleaned_glb_staged   -> rejected
staged_validation_*  -> rejected
runtime_review_*     -> rejected
```

`promoted` is not a state transition available to Meshy, the staging adapter, Blender cleanup,
or the runtime-review harness. It requires a separately reviewed promotion task with an
explicit diff and complete provenance.

## Contract-first and provider gates

The project has standing subscription authorization for post-PR testing. Spend, cap, and account
bookkeeping do not block that testing, but authorization never waives request integrity or any
evidence gate. Before any Meshy API call, all of the following must be present and valid:

1. The repository asset contract validates without unknown fields, invalid dimensions, or an
   unsupported category/state/generation policy.
2. Required reference images are separate files, consistent with one another, rights-cleared,
   hash-recorded, and free of collage substitution.
3. For candidate generation, a read-only plan is current, and its `maximum_credits` is passed as
   the required `--approved-credits` request-envelope/integrity field to `meshy_stage.py generate`
   and `resume`. This value is not renewed human spend approval; materially changed requests are
   replanned.
4. An immutable request record is created before submission. It records the exact validated
   request and hashes but never stores API keys, authorization headers, or signed download
   URLs.

Later contract/schema work must also preserve two shape constraints for the pilot kits:

- Threat and kit triangle budgets are represented as an explicit range plus scope (for example,
  per organism, per module, or final kit), not as one ambiguous integer.
- `hull_tendril_kit_v1` and `biomatter_swarm_kit_v1` contracts enumerate their required
  deliverables with explicit `deliverables`/`kit_parts` arrays, including module and state
  coverage needed by Blender and Godot review.

The candidate plan's `maximum_credits` applies to `meshy_stage.py generate` and `resume`. The
optional texture packet is proposal-only, uses a separate current 10-credit integrity estimate via
`TEXTURE_APPROVED_CREDITS`, and does not create a provider task. The texture packet's
`--approved-credits` value must be greater than or equal to the current fixed 10-credit estimate,
so `TEXTURE_APPROVED_CREDITS` must be `10` or greater. It still requires selected candidate,
Blender, and UV evidence and does not weaken task/artifact integrity.

No API call is permitted without a validated contract, validated reference rights, the required
`--approved-credits` integrity field, and an immutable request record. A dry-run plan is read-only
and makes no provider call; its current `references_resolved=false` result truthfully records that
rights-cleared reference files are absent until the live pilot.

Each `generate` operation creates one governed batch containing exactly the contract's
`candidate_count` planned candidate task records. `loot_container_derelict_v1` therefore uses one
batch with four candidate records. Each planned candidate record allows exactly one paid creation
POST attempt. A timeout, transport failure, `429`, `5xx`, or other ambiguous creation outcome is
reconciled from the immutable journal and is never automatically retried. One selected Blender
master derives all alternate states; single-attempt safety never reduces candidate cardinality.

Candidates are staged in isolation and must be selected before Blender cleanup. Geometry is
judged before optional texturing. Alternate states are derived from one Blender master; the
pipeline must reject independently generated closed/open, intact/damaged, or living/dead
variants.

## Canonical staging layout

```text
assets/_staging/meshy/<asset_id>/<task_id>/
  contract.json
  prompt-packet.json
  source_front.png
  source_side.png
  source_back.png
  source_three_quarter.png
  raw.glb
  thumbnail.png
  generation.json
  review.json
  cleaned.glb
  blender-validation.json
  sidecar-overlay.json
```

Absent reference views are omitted rather than represented by empty files. `generation.json`
is immutable after download; candidate decisions and later validation belong in `review.json`
and the corresponding validation records.

The editable master is external/heavy source and is not a runtime staging substitute:

```text
MESHY_MASTER_ROOT="${MESHY_MASTER_ROOT:?set external Meshy master root}"
$MESHY_MASTER_ROOT/<asset_id>/
  <asset_id>_master.blend
  textures/
  exports/
```

The external master backup gate must pass before any future promotion-ready decision.

## Protected runtime surfaces

Generation, selection, cleanup, validation, and runtime review must not write to any of these
live surfaces:

- `assets/imported`
- `data/combat/threat_visual_catalog.json`
- `data/props/visual_bindings.generated.json`
- `scenes/wrappers`

A temporary Godot review overlay may copy a staged GLB into a temporary review-only project
surface, but it must not mutate the live catalogs, generated index, wrapper scenes, or gameplay
data. Any proposed sidecar/index/catalog change is emitted as a reviewable promotion packet;
it is not applied by the generator.

## Promotion proposal packets

Promotion is a proposal-producing boundary, not a promotion command. Run
`tools/meshy_promotion_packet.py` only against a completed task directory below
`assets/_staging/meshy/<asset_id>/<task_id>/`. The tool writes proposal records back into that
staging directory and never writes `assets/imported`, `data/combat`, `data/props`, or
`scenes/wrappers`.

Every proposal carries this complete, ADR-0052-compatible envelope:

```json
{
  "provenance": {
    "license_state": "paid-private",
    "source_platform": "meshy"
  },
  "extensions": {
    "ai_generation": {
      "provider": "meshy",
      "task_id": "018...",
      "model": "meshy-t2",
      "input_sha256": ["<64-lowercase-hex>"],
      "raw_output_sha256": "<64-lowercase-hex>",
      "cleaned_output_sha256": "<64-lowercase-hex>",
      "contract_sha256": "<64-lowercase-hex>",
      "human_cleanup": true,
      "reviewer": "operator"
    }
  }
}
```

Missing rights or any hash, `human_cleanup: false`, `source_platform: self-authored`, signed
URLs, and API keys are hard failures. All proposal output paths must remain under
`assets/_staging/meshy`; a target path in a proposal is descriptive only and is never opened for
writing.

For props, the tool emits `sidecar-overlay.json`. It contains `proposal_only: true`, the live
sidecar target path, and only the authored `provenance`/`extensions` overlay needed to review a
future adjacent `<asset>.sidecar.json`. For threats, it emits
`threat_visual_catalog.patch.json` containing a reviewable JSON-patch-style operation targeting
`data/combat/threat_visual_catalog.json`, plus `asset-provenance.json` containing the generic
asset provenance record. A separate, human-approved task must inspect and apply either proposal;
no proposal file is itself a live catalog, index, wrapper, or imported asset.

## ADR-0052 reconciliation

This feature extends, rather than replaces, ADR-0052:

- The prop **GLB plus adjacent same-basename `.sidecar.json`** remains the portable visual
  record, and `data/props/visual_bindings.generated.json` remains the authoritative generated
  index for the existing prop metadata pipeline. The generated index is derived and never a
  second authored source of truth.
- Meshy provenance is authored in the existing provenance fields and `extensions`, including
  the AI-generation details required by the later promotion packet. A cleaned Meshy asset is
  not relabeled `self-authored` merely because Blender performed cleanup.
- Structural wrappers remain gameplay authority for connector/socket contracts, collision,
  passability, and integrity/damage variants. Candidate or Blender visual geometry must not
  replace those wrappers or create a duplicate gameplay authority.
- An explicit GLB-derived refresh continues to replace source evidence such as SHA-256,
  byte size, mesh count, glTF version, and bounds while preserving authored bindings,
  placement, provenance, and extensions. Refresh must never erase AI provenance or authored
  fields.

Direct prop records continue to use `collision_policy="none_visual_only"`. The candidate
pipeline therefore supplies visual candidates and provenance proposals; it does not turn a
visual GLB into collision, navigation, socket, or integrity data.

## Acceptance criteria

This feature is accepted when the repository documentation makes all of the following testable
and unambiguous:

- The authority chain is contract-first, candidate-only, Blender-canonical, staged-validation-
  gated, runtime-reviewed in a temporary overlay, and promotion-separated.
- Meshy is explicitly prohibited from structural floors, walls, doors, ramps, sockets,
  collision, and damage topology.
- Blender ownership explicitly covers the editable master, topology, UV, exact meter scale,
  pivot, `+Z` forward, state derivation, rig, and export.
- Godot wrappers/runtime data explicitly own collision, navigation, sockets, integrity,
  VFX/animation integration, and gameplay bindings.
- The five pilot IDs are present exactly as listed above.
- No provider call can proceed without the contract, reference rights, the plan's
  `--approved-credits` request-integrity field, and immutable request-record gates. Standing
  subscription authorization removes spend bookkeeping as a human blocker; it does not remove
  any integrity, review, or protected-path gate.
- No generator path can write to any protected runtime surface.
- Runtime review is pinned to seeds `42` and `777` in `breach_field` under `normal`,
  `emergency`, and `dark` lighting.
- Promotion is documented as a separate reviewed task, never automatic.
- Requirements `REQ-AIAP-001` through `REQ-AIAP-010` each have an executable gate in the current
  toolchain or a clearly identified post-PR live-pilot evidence limitation.
- The later skill pressure tests must demonstrate the same refusals and routing rules, not
  merely repeat prose.
- Unexpected `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` lines block runtime acceptance unless
  the existing validation plan explicitly classifies that exact output. A passing marker or
  zero exit code alone does not override an unclassified diagnostic.

## Current validation and command surfaces

The current host-Python lifecycle is plan → generate → resume/verify → candidate review →
Blender master and validator → optional texture packet after selection/UV → runtime review →
evidence binder → proposal only. Run commands from the repository root:

```bash
/usr/bin/python3 tools/meshy_stage.py plan --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json \
  --pricing-file data/asset_generation/meshy_pricing_v1.json
/usr/bin/python3 tools/meshy_stage.py generate --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json \
  --approved-credits <maximum_credits> --pricing-file data/asset_generation/meshy_pricing_v1.json \
  --reference-root <reference_root> --reference front=<front_file> \
  --reference side=<side_file> --reference back=<back_file> \
  --reference three_quarter=<three_quarter_file> --output-license paid-private
/usr/bin/python3 tools/meshy_stage.py resume --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json \
  --batch-journal <batch_journal> --approved-credits <maximum_credits> \
  --pricing-file data/asset_generation/meshy_pricing_v1.json \
  --reference-root <reference_root> --reference front=<front_file> \
  --reference side=<side_file> --reference back=<back_file> \
  --reference three_quarter=<three_quarter_file> --output-license paid-private
/usr/bin/python3 tools/meshy_stage.py verify --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json \
  --batch-journal <batch_journal> --pricing-file data/asset_generation/meshy_pricing_v1.json
```

After a candidate is selected and its Blender UV pass is complete, the remaining host launchers
are:

```bash
/usr/bin/python3 tools/meshy_candidate_review.py select --project-root . --task-dir "<task_dir>" \
  --reviewer "<reviewer>" --check silhouette_readable --check proportions_match_contract \
  --check functional_volume_present --check movable_parts_separable --check cleanup_bounded \
  --check camera_readability
/usr/bin/python3 tools/meshy_blender_master.py --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json --task-dir "<task_dir>" \
  --reviewer "<reviewer>"
/usr/bin/python3 tools/meshy_blender_validate.py --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json --task-dir "<task_dir>" \
  --glb <task_dir>/cleaned.glb --report <task_dir>/blender-validation.json
TEXTURE_APPROVED_CREDITS="${TEXTURE_APPROVED_CREDITS:-10}"
/usr/bin/python3 tools/meshy_texture_packet.py --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json --task-dir "<task_dir>" \
  --material-family <family> --resolution 1024 --reviewer "<reviewer>" \
  --approved-credits "$TEXTURE_APPROVED_CREDITS"
/usr/bin/python3 tools/meshy_runtime_review.py --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json --task-dir "<task_dir>" \
  --preview-dir "artifacts/validation-previews/meshy/<asset_id>"
/usr/bin/python3 tools/meshy_candidate_review.py bind --project-root . --task-dir "<task_dir>"
/usr/bin/python3 tools/meshy_promotion_packet.py prop --project-root . --task-dir "<task_dir>" \
  --target-path res://assets/imported/props/dressing/<asset_id>.sidecar.json
# threat_character / threat_kit contracts must use the threat packet instead:
# /usr/bin/python3 tools/meshy_promotion_packet.py threat --project-root . --task-dir "<task_dir>"
```

The host toolchain evidence is current at commit `4dc9e7d7f7aee2c5884bb72118949583737e8994`:
the focused Meshy suite completed 340 tests in 185.67 seconds, and the real Blender focused
tests passed 2 tests for valid re-import/publication and non-affine rejection. The real candidate
lifecycle is not claimed here: no Meshy task directory, raw/cleaned GLB, generation/review
record, external Blender master, or six runtime captures exists until the post-PR live pilot.

The runtime marker requires task identity:

```text
MESHY RUNTIME REVIEW PASS asset=stalker_v1 task_id=<task_id> seeds=42,777 lighting=normal,emergency,dark captures=6
```

Existing Godot regression smokes remain regression evidence and must use the current validation
plan. Unexpected `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` output blocks acceptance unless that
exact output is classified there. A pass marker or zero exit code does not override an
unclassified diagnostic.

## Non-goals

- Meshy generation, API calls, paid credit spend, or reference upload during this documentation
  refresh.
- Treating raw Meshy output as a runtime source or production Godot import route.
- Meshy cannot author structural floors, walls, doors, ramps, sockets, collision, or damage
  topology.
- Independent generation of alternate states.
- Blender-generated gameplay collision, navigation, sockets, integrity, or damage authority.
- Direct writes to live imported assets, catalogs, generated indexes, wrapper scenes, or
  gameplay data.
- Automatic promotion or a hidden catalog/index/wrapper mutation.
- A standalone neutral model viewer in place of the real locked-isometric runtime review.
- Aesthetic scoring that pretends subjective candidate selection is fully automated.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Attractive candidate bypasses the contract | Validate category, dimensions, states, axes, budgets, and provenance before selection or cleanup. |
| Inconsistent or unlicensed references | Require separate, consistent images, explicit rights, and input hashes before any provider call. |
| Duplicate or ambiguous paid submission | Bind the plan's `maximum_credits` to required `--approved-credits` request integrity, allow one creation POST per planned candidate record, and reconcile ambiguity without automatic retry. |
| Candidate or provider writes into runtime | Use isolated staging, path containment, protected-surface snapshots, and proposal-only promotion output. |
| Blender cleanup drifts from gameplay | Keep collision, navigation, sockets, integrity, VFX/animation integration, and bindings in Godot wrappers/runtime data. |
| Refresh erases provenance | Reconcile through ADR-0052's explicit refresh-preservation rule for authored fields and extensions. |
| Review passes in the wrong visual context | Run seeds `42` and `777` in `breach_field` under all three lighting modes with the production locked-isometric camera. |
| Diagnostics are mistaken for harmless noise | Treat every unexpected `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` as a blocker unless the validation plan classifies it. |
| Skill advice diverges from repository enforcement | Pressure-test the umbrella skill against the same contract, request-integrity, staging, ownership, and promotion gates. |

## Related records

- ADR: `docs/game/adr/0058-meshy-candidates-blender-authority.md`
- Existing prop metadata authority: `docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md`
- Existing prop feature contract: `docs/game/features/asset_metadata_pipeline.md`
- Requirements: `REQ-AIAP-001` through `REQ-AIAP-010` in `docs/game/05_requirements.md`
- Validation plan and pending command registry: `docs/game/06_validation_plan.md`
