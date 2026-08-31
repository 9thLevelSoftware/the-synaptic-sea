# ADR-0057: Meshy Candidates, Blender Canonical Masters, and Godot Runtime Authority

## Status

Accepted for Task 1 governance; implementation of the later tools and runtime-review harness is
pending. No Meshy API call, paid action, asset generation, or promotion is part of this ADR's
implementation task.

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

### Cost, provenance, and path gates

No Meshy API call may occur without all five of these gates:

1. a validated repository asset contract;
2. validated reference rights and consistent separate input images;
3. a live provider balance check;
4. an explicit maximum credit ceiling that bounds the requested batch; and
5. an immutable request record containing the exact request and relevant hashes before
   submission.

The request and generation records must not contain API keys, authorization headers, signed
URLs, or other secrets. Generation output is staged atomically and records provider/model/task
identifiers, contract and reference hashes, output hashes/sizes, license state, and consumed
credits. Later review decisions are separate records and do not rewrite immutable generation
facts.

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

Thus ADR-0057 governs how a candidate reaches the existing visual-record boundary; it does not
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
- The first implementation tasks must land before the commands in the validation plan can be
  claimed as passing.

## Validation

The feature contract and requirement rows are the executable documentation targets for this
ADR:

- Feature: `docs/game/features/ai_candidate_asset_pipeline.md`.
- Requirements: `REQ-AIAP-001` through `REQ-AIAP-010` in `docs/game/05_requirements.md`.
- Pending command registry: `docs/game/06_validation_plan.md`.

The eventual gates include the contract validator, focused Python tests, the Blender
normalized-GLB validator, the locked-isometric runtime-review harness, and the existing Godot
smokes. They are explicitly pending until the corresponding implementation tasks land; Task 1
reports no runtime or provider pass.

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
6. **Call a paid endpoint whenever an API key is available.** Rejected: contract, rights,
   live balance, explicit maximum credit ceiling, and immutable request evidence are mandatory.
