# Feature: Derelict builder runtime preview

## Status

Approved — REQ-PCG-BUILDER-001.

## Requirement cross-reference

- `REQ-PCG-BUILDER-001` in `docs/game/05_requirements.md`
- ADR-0057: `docs/game/adr/0057-derelict-builder-manifest-preview.md`

## Design pillar alignment

- Pillar: make generated derelicts playable and testable locally.
- Why this feature supports it: builder validation is only meaningful when the exported area can enter the real loader and exercise runtime behavior.

## Player fantasy

Author a reusable room or area, press Run in Game, and walk the same authored space with its doors, hazards, loot, objectives, collision, and navigation intact.

## Gameplay problem

Builder previews and generated runtime loading can diverge when they use different files, kits, or structural policies. A metadata-only preview can report success while collision, navigation, vertical links, or hazard consumers are absent in game.

## Core behavior

1. The builder validates and writes a temporary `derelict_builder_bundle` manifest.
2. The dedicated local preview scene reads that manifest and resolves layout, gameplay-slice, and kit paths relative to the manifest. An explicitly absolute kit path remains absolute.
3. Loading enters through `GeneratedShipLoader`, using the same structural wrappers and runtime systems as a generated ship.
4. The preview checks instantiated collision and navigation, vertical links, objectives, authored props, loot, and fire, arc, breach, radiation, and atmosphere consumers.
5. The process emits machine-readable result JSON and a meaningful non-zero exit code when loading, validation, or runtime readiness fails.

## Inputs

- A validated builder `derelict_builder_bundle` manifest.
- Referenced layout, gameplay slice, and kit files.
- The local Godot executable and the Synaptic Sea project.

## Outputs

- An actual loaded preview area with structural wrappers, collision, navigation, vertical links, objectives, authored props, loot, and authored hazards.
- Machine-readable result JSON containing per-capability readiness and source/kit identity.
- Acceptance marker: `DERELICT BUILDER PREVIEW PASS collision=true navigation=true verticals=true objectives=true props=true loot=true fire=true arc=true breach=true radiation=true atmosphere=true`.

## Rules

- Resolve relative manifest paths from the manifest directory; do not route through temporary legacy filenames.
- Enter through `GeneratedShipLoader`; metadata-only markers do not satisfy readiness.
- Unsupported semantics fail readiness and remain unavailable to the builder until a runtime consumer exists.
- Radiation zones and authored room atmosphere must have observable runtime consumers.
- Keep authoring source JSON separate from generated runtime outputs.

## Non-goals

- Full campaign or complete derelict composition.
- Cloud generation or hosted runtime execution.
- A general main-scene refactor.
- Replacing the normal generated-ship loader with a second runtime authority.

## Technical design

- Dedicated preview scene and validation script in the Synaptic Sea project.
- `GeneratedShipLoader` is the runtime entry point.
- The builder owns temporary bundle creation and launch reporting; the game owns runtime instantiation and behavior checks.

## Acceptance criteria

- Given a validated builder bundle, when the preview runs locally, then its manifest paths resolve correctly for both relative and absolute kit paths.
- Given structural layout and gameplay data, when `GeneratedShipLoader` loads them, then actual wrappers expose collision and navigation and authored vertical links are traversable.
- Given authored objectives, props, inventories, and hazards, when the preview ticks runtime systems, then objectives, prop placement, loot, fire, arc, breach, radiation, and atmosphere produce observable readiness evidence.
- Given any missing or unsupported required consumer, when readiness is evaluated, then the preview emits machine-readable failure JSON and a non-zero exit code.

## Validation

Run the focused smoke from `docs/game/06_validation_plan.md`. A green run must contain the exact acceptance marker above and a result JSON object with matching `true` fields.

## Risks

- Preview paths can drift from builder export paths. Mitigation: manifest-relative resolution and source/kit identity in result JSON.
- A marker can be emitted without behavior. Mitigation: instantiate actual wrappers and tick each runtime consumer before reporting PASS.
- Runtime consumers can regress independently of export. Mitigation: keep localized radiation, authored atmosphere, portals, and placed props as focused runtime smokes and fail readiness when any consumer is absent.

## ADRs

- ADR-0057: Derelict builder manifest preview.
