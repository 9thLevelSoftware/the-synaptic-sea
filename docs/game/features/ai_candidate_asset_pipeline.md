# Feature: Governed Meshy-to-Blender Candidate Asset Pipeline

## Status

Approved as Task 1 governance. Implementation of the contract, staging adapter, Blender
validator, runtime-review harness, and skill pressure tests is pending the later tasks in the
Meshy-to-Blender implementation plan. Task 1 changes documentation only; it does not create,
import, generate, promote, or modify any asset or runtime file.

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

Task 1 establishes the documentation and ownership boundary. Later implementation tasks may
add tools and tests, but they must preserve this scope and the protected-path rules below.

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

Before any Meshy API call, all of the following must be present and valid:

1. The repository asset contract validates without unknown fields, invalid dimensions, or an
   unsupported category/state/generation policy.
2. Required reference images are separate files, consistent with one another, rights-cleared,
   hash-recorded, and free of collage substitution.
3. A live Meshy balance has been checked.
4. An explicit maximum credit ceiling has been approved for the requested batch, and the
   provider estimate is within both the balance and that ceiling.
5. An immutable request record is created before submission. It records the exact validated
   request and hashes but never stores API keys, authorization headers, or signed download
   URLs.

Later contract/schema work must also preserve two shape constraints for the pilot kits:

- Threat and kit triangle budgets are represented as an explicit range plus scope (for example,
  per organism, per module, or final kit), not as one ambiguous integer.
- `hull_tendril_kit_v1` and `biomatter_swarm_kit_v1` contracts enumerate their required
  deliverables with explicit `deliverables`/`kit_parts` arrays, including module and state
  coverage needed by Blender and Godot review.

No API call is permitted without a validated contract, validated reference rights, a live
balance, an explicit maximum credit ceiling, and an immutable request record. A dry-run plan
is read-only and makes no API call.

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
/Volumes/Untitled/SynapticSeaAssets/meshy/source/<asset_id>/
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

## Promotion proposal packets (Task 10)

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

Task 1 is accepted when the repository documentation makes all of the following testable and
unambiguous:

- The authority chain is contract-first, candidate-only, Blender-canonical, staged-validation-
  gated, runtime-reviewed in a temporary overlay, and promotion-separated.
- Meshy is explicitly prohibited from structural floors, walls, doors, ramps, sockets,
  collision, and damage topology.
- Blender ownership explicitly covers the editable master, topology, UV, exact meter scale,
  pivot, `+Z` forward, state derivation, rig, and export.
- Godot wrappers/runtime data explicitly own collision, navigation, sockets, integrity,
  VFX/animation integration, and gameplay bindings.
- The five pilot IDs are present exactly as listed above.
- No provider call can proceed without the contract, reference rights, live balance, explicit
  maximum credit ceiling, and immutable request record gates.
- No generator path can write to any protected runtime surface.
- Runtime review is pinned to seeds `42` and `777` in `breach_field` under `normal`,
  `emergency`, and `dark` lighting.
- Promotion is documented as a separate reviewed task, never automatic.
- Requirements `REQ-AIAP-001` through `REQ-AIAP-010` each have a later executable gate or
  explicitly labeled pending validation command.
- The later skill pressure tests must demonstrate the same refusals and routing rules, not
  merely repeat prose.
- Unexpected `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` lines block runtime acceptance unless
  the existing validation plan explicitly classifies that exact output. A passing marker or
  zero exit code alone does not override an unclassified diagnostic.

## Validation placeholders (pending later implementation tasks)

The commands below are the eventual gates. They are intentionally **PENDING** in Task 1;
they must not be reported as currently passing until their implementation tasks land and
fresh output is captured.

### Contract and focused Python tests — PENDING Tasks 2–7, 9–11

```bash
python3 tools/meshy_asset_contract.py validate data/asset_generation/contracts/*.json
python3 -m pytest -q \
  tests/test_meshy_asset_contract.py \
  tests/test_meshy_stage.py \
  tests/test_meshy_candidate_review.py \
  tests/test_meshy_blender_tools.py \
  tests/test_meshy_texture_packet.py \
  tests/test_meshy_promotion_packet.py \
  tests/test_meshy_runtime_review.py \
  tests/test_validate_prop_visual_bindings.py \
  tests/test_prop_visual_metadata.py
```

### Blender normalized-GLB validator — PENDING Task 8

```bash
BLENDER="${BLENDER:-/opt/homebrew/bin/blender}"
"$BLENDER" --background --factory-startup --python tools/meshy_blender_validate.py -- \
  --project-root . \
  --contract data/asset_generation/contracts/loot_container_derelict_v1.json \
  --task-dir assets/_staging/meshy/loot_container_derelict_v1/<task-id> \
  --glb assets/_staging/meshy/loot_container_derelict_v1/<task-id>/cleaned.glb
```

Expected eventual marker (not a Task 1 result):

```text
MESHY BLENDER VALIDATION PASS asset=loot_container_derelict_v1 triangles=<n> materials=<n>
```

### Locked-isometric runtime review — PENDING Task 11

```bash
python3 tools/meshy_runtime_review.py \
  --project-root . \
  --contract data/asset_generation/contracts/stalker_v1.json \
  --task-dir assets/_staging/meshy/stalker_v1/<task-id> \
  --preview-dir artifacts/validation-previews/meshy/stalker_v1
```

The eventual harness must run exactly six real-environment cases: seeds `42` and `777`, each
under `normal`, `emergency`, and `dark` lighting, in `breach_field` with the production
locked-isometric camera. It must publish captures only after all six cases pass and after
checking for unexpected diagnostics. Expected eventual marker (not a Task 1 result):

```text
MESHY RUNTIME REVIEW PASS asset=stalker_v1 seeds=42,777 lighting=normal,emergency,dark captures=6
```

### Existing Godot regression smokes — PENDING integration of Task 11

These are existing production-environment smokes and remain regression evidence; Task 1 does
not claim them as newly passing:

```bash
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --headless --path . --script res://scripts/validation/threat_visual_catalog_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/structural_live_loader_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/generated_seed_boarded_slice_smoke.gd
```

The full existing regression bundle remains governed by `docs/game/06_validation_plan.md`.
Unexpected `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` output from these or the future review
harness blocks acceptance unless that exact output is already classified there.

## Non-goals

- Meshy generation, API calls, paid credit spend, or reference upload during Task 1.
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
| Unbounded paid spend | Check live balance and enforce an explicit maximum credit ceiling before immutable submission. |
| Candidate or provider writes into runtime | Use isolated staging, path containment, protected-surface snapshots, and proposal-only promotion output. |
| Blender cleanup drifts from gameplay | Keep collision, navigation, sockets, integrity, VFX/animation integration, and bindings in Godot wrappers/runtime data. |
| Refresh erases provenance | Reconcile through ADR-0052's explicit refresh-preservation rule for authored fields and extensions. |
| Review passes in the wrong visual context | Run seeds `42` and `777` in `breach_field` under all three lighting modes with the production locked-isometric camera. |
| Diagnostics are mistaken for harmless noise | Treat every unexpected `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` as a blocker unless the validation plan classifies it. |
| Skill advice diverges from repository enforcement | Task 12 pressure-tests the umbrella skill against the same contract, cost, staging, ownership, and promotion gates. |

## Related records

- ADR: `docs/game/adr/0057-meshy-candidates-blender-authority.md`
- Existing prop metadata authority: `docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md`
- Existing prop feature contract: `docs/game/features/asset_metadata_pipeline.md`
- Requirements: `REQ-AIAP-001` through `REQ-AIAP-010` in `docs/game/05_requirements.md`
- Validation plan and pending command registry: `docs/game/06_validation_plan.md`
