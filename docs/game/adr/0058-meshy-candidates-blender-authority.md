# ADR-0058: Meshy Candidates, Blender Canonical Masters, and Godot Runtime Authority

## Status

Accepted. The toolchain implementation is present and host-verified at merge commit
`4dc9e7d7f7aee2c5884bb72118949583737e8994`. Real provider tasks, candidate artifacts, and the
six-case runtime evidence remain intentionally reserved for the post-PR live pilot; no provider
call or promotion is part of this documentation refresh.

## Date

2026-08-30

## Context

The Synaptic Sea needs a repeatable way to explore AI-assisted visual assets without allowing
provider output to bypass the repository's asset contracts or existing gameplay owners. Meshy
can produce useful visual candidates, but its output is not a substitute for the project's
editable source, structural kit, wrapper scenes, gameplay data, or runtime validation.

The project already has a portable prop visual record and generated visual-binding index under
ADR-0052. That authority must remain intact while AI provenance is added to authored records.
The same boundary must also cover threat kits, props with derived states, and future texturing
or rigging steps.

## Decision

> Meshy output is a candidate source, not a runtime source. A selected candidate becomes eligible for runtime review only after a canonical Blender master exists, the normalized GLB passes the project asset contract, provenance is complete, and a temporary Godot overlay passes locked-isometric review. Runtime collision, navigation, sockets, integrity, animation/VFX integration, and gameplay bindings remain owned by Godot wrappers and repository data. Promotion is a separate reviewed action.

The governing authority chain is:

```text
asset contract
  -> consistent separate reference images
  -> Meshy candidate
  -> Blender canonical master/cleanup
  -> staged validation
  -> temporary Godot overlay locked-isometric review
  -> separate reviewed promotion
```

### Candidate-only Meshy boundary

Meshy may generate candidate visual geometry only for a validated, non-structural contract.
Meshy cannot author or replace structural floors, walls, doors, ramps, sockets, collision, or
damage topology. Raw output remains isolated under the staging root and is never a production
Godot import route. Texturing and rigging are also subordinate to candidate selection and the
Blender master policy; they cannot promote or replace the master implicitly.

### Blender canonical-master authority

Blender owns the editable master and the visual asset transformations required to make a
candidate usable:

- topology and cleanup;
- UVs;
- exact meter scale;
- pivot;
- canonical `+Z` forward orientation;
- derivation of alternate states from one master;
- rig; and
- normalized GLB export.

Blender does not become a gameplay authority by performing those duties. It does not generate
runtime collision, navigation, sockets, integrity, or damage topology for the visual-only
candidate path. Blender validation is an independent re-imported-GLB gate and reports failures
for the artist to correct rather than silently auto-fixing them.

### Godot and repository-data authority

Godot wrappers and repository runtime data own collision, navigation, sockets/connectors,
integrity and damage consequences, VFX/animation integration, and gameplay bindings. A visual
child may change only after the wrapper contract remains intact. Runtime state is not duplicated
in a candidate sidecar, staged GLB, or generated visual index.

### Standing subscription, request integrity, and path gates

The project has standing subscription authorization for post-PR testing. Spend, cap, and account
bookkeeping do not block that testing, but authorization never waives the integrity gates. No
Meshy API call may occur without all of these conditions:

1. a validated repository asset contract;
2. validated rights and consistent separate input images;
3. a read-only plan whose `maximum_credits` is copied into the required
   `--approved-credits` request-envelope/integrity field; and
4. an immutable request record containing the exact request and relevant hashes before submission.

The `--approved-credits` value must equal the plan's `maximum_credits`; it is not renewed human
spend approval. A materially changed request must be replanned. Within one governed batch, every
planned candidate record allows exactly one paid creation POST attempt. A timeout, transport
failure, `429`, `5xx`, or other ambiguous outcome is reconciled from the immutable journal and is
never automatically retried. Task and artifact identity, selected/SUCCEEDED evidence, Blender
re-import, runtime review, provenance, and protected-path gates remain mandatory.

The request and generation records must not contain API keys, authorization headers, signed URLs,
or other secrets. Generation output is staged atomically and records provider/model/task
identifiers, contract and reference hashes, output hashes/sizes, license state, and consumed
credits. Later review decisions are separate records and do not rewrite immutable generation
facts.

Each generation creates one governed batch with exactly the contract's `candidate_count` planned
candidate records. `loot_container_derelict_v1` therefore uses one batch of four candidate records;
each record has one creation POST attempt. One selected Blender master derives its closed, open,
and looted states. Single-attempt safety never reduces candidate cardinality.

The generator, downloader, Blender staging flow, and runtime-review harness must never write to:

- `assets/imported`;
- `data/combat/threat_visual_catalog.json`;
- `data/props/visual_bindings.generated.json`; or
- `scenes/wrappers`.

They may create temporary review overlays and proposal packets outside those live surfaces, but
promotion is always a separate reviewed task.

### Runtime review boundary

A selected and validated candidate is reviewed only in a temporary overlay that loads the real
production derelict environment and locked-isometric camera. The review matrix is fixed at
seeds `42` and `777` in `breach_field`, under `normal`, `emergency`, and `dark` lighting. A
standalone neutral model viewer is not final runtime evidence. Unexpected `ERROR:`, `WARNING:`,
or `SCRIPT ERROR:` lines block runtime acceptance unless the existing validation plan
explicitly classifies the exact output.

### Current command surfaces and order

Commands are host-Python launchers and run from the repository root. The supported lifecycle is:

1. Read-only plan, then provider submission only after the plan, rights, and request record are
   valid:

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
   ```

2. Recovery and offline verification use the existing journal; neither creates a second task:

   ```bash
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

3. Select or reject a candidate, then run the host-Python Blender master and independent
   re-import validator. Optional texture packet generation is after selection and the Blender UV
   pass, never before geometry approval:

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
   /usr/bin/python3 tools/meshy_texture_packet.py --project-root . \
     --contract data/asset_generation/contracts/<asset_id>.json --task-dir "<task_dir>" \
     --material-family <family> --resolution 1024 --reviewer "<reviewer>" --approved-credits 10
   ```

4. Run the real runtime review, bind its evidence, and emit a proposal only. The binder and
   proposal never promote or write protected runtime surfaces:

   ```bash
   /usr/bin/python3 tools/meshy_runtime_review.py --project-root . \
     --contract data/asset_generation/contracts/<asset_id>.json --task-dir "<task_dir>" \
     --preview-dir "artifacts/validation-previews/meshy/<asset_id>"
   /usr/bin/python3 tools/meshy_candidate_review.py bind --project-root . --task-dir "<task_dir>"
   /usr/bin/python3 tools/meshy_promotion_packet.py prop --project-root . --task-dir "<task_dir>" \
     --target-path res://assets/imported/props/dressing/<asset_id>.sidecar.json
   ```

The promotion packet is a review proposal only; applying it is a separate reviewed task.

### Pilot scope

This decision initially covers:

- `stalker_v1`;
- `hull_tendril_kit_v1`;
- `biomatter_swarm_kit_v1`;
- `loot_container_derelict_v1`; and
- `crafting_station_derelict_v1`.

## ADR-0052 reconciliation

ADR-0052 remains authoritative for the existing prop metadata and visual-binding system:

- A prop **GLB plus adjacent same-basename `.sidecar.json`** remains the portable visual
  record, and `data/props/visual_bindings.generated.json` remains the authoritative generated
  index. The index is derived from valid sidecars and GLBs; it is not a hand-authored second
  authority.
- AI provenance is stored in ADR-0052's authored provenance/extensions model, including the
  later `extensions.ai_generation` record. Blender cleanup does not turn Meshy provenance into
  `self-authored` provenance.
- Structural wrappers remain gameplay authority for sockets/connectors, collision, passability,
  and integrity variants. Candidate visuals may not weaken or duplicate those wrapper
  contracts.
- An explicit GLB-derived refresh replaces source evidence (hash, byte size, mesh count, glTF
  version, and bounds) while preserving authored bindings, placement, provenance, and
  extensions. Refresh must preserve AI provenance and authored fields.

Thus ADR-0058 governs how a candidate reaches the existing visual-record boundary; it does not
redefine the prop sidecar/index contract or move gameplay state into it.

## Consequences

### Positive

- AI-assisted exploration is repeatable, bounded, and reviewable without treating a provider as
  an asset authority.
- One Blender master prevents independent alternate-state drift and gives the project an
  editable source of topology, UV, scale, pivot, orientation, rig, and export.
- Existing Godot wrapper/runtime ownership remains stable while visuals are iterated.
- Provenance, cost, rights, and output evidence are available for review without exposing
  secrets or signed URLs.
- Runtime evidence is obtained in the real locked-isometric environment rather than a neutral
  viewer.

### Costs and limitations

- Candidate generation, selection, Blender cleanup, validation, and promotion are separate
  stages and require more records than a direct import.
- External `.blend` masters require a backup/checkpoint gate before promotion.
- The six-case runtime review and clean diagnostic requirement make visual promotion slower but
  prevent context and log regressions.
- Real provider tasks, raw/cleaned GLBs, external Blender masters, generation records, and six
  runtime captures are not present until the post-PR live pilot.

## Validation

The feature contract and requirement rows are the executable documentation targets for this
ADR:

- Feature: `docs/game/features/ai_candidate_asset_pipeline.md`.
- Requirements: `REQ-AIAP-001` through `REQ-AIAP-010` in `docs/game/05_requirements.md`.
- Current command registry and evidence boundary: `docs/game/06_validation_plan.md`.

The implemented gates include the contract validator, focused Python tests, the host-Python
Blender master and normalized-GLB validator, the locked-isometric runtime-review harness, and
the existing Godot smokes. At commit `4dc9e7d7f7aee2c5884bb72118949583737e8994`, the focused
Meshy suite passed 340 tests in 185.67 seconds and the Blender focused tests passed 2 tests.
There is no real Meshy task directory, raw/cleaned GLB, generation/review record, external master,
or six-capture runtime report yet; those are truthful post-PR live-pilot evidence limitations.

## Alternatives considered

1. **Import raw Meshy output directly into Godot.** Rejected: it bypasses canonical cleanup,
   contract validation, provenance review, and the wrapper/runtime ownership boundary.
2. **Let Meshy generate structural modules or collision.** Rejected: structural wrappers and
   repository gameplay data already own sockets, collision, navigation, and integrity/damage
   consequences.
3. **Use Blender-exported visual geometry as gameplay collision.** Rejected: Blender owns the
   visual master and export, while Godot wrappers own runtime collision/navigation/integrity.
4. **Generate alternate states independently.** Rejected: independent states drift in scale,
   topology, pivots, and gameplay attachment; all states derive from one Blender master.
5. **Let generation write the live catalog, generated index, or wrappers.** Rejected: it makes
   review and rollback ambiguous; proposal output and separate promotion keep the boundary
   explicit.
6. **Call a paid endpoint whenever an API key is available.** Rejected: standing subscription
   authorization does not waive contract, rights, `--approved-credits` request integrity,
   immutable evidence, single-POST-attempt, reconciliation, or review gates.
