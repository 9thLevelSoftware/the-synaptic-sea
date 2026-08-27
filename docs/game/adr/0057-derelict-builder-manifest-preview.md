# ADR-0057: Local derelict builder manifest preview

- **Status:** Accepted
- **Date:** 2026-08-26
- **Supersedes / amends:** none
- **Related:** feature `docs/game/features/derelict_builder_runtime_preview.md`; REQ-PCG-BUILDER-001

## Context

The standalone derelict builder must prove that an authored room or area survives export into the real Synaptic Sea runtime. Previewing metadata or routing through fixed temporary files does not prove that structural wrappers, collision, navigation, vertical links, objectives, loot, or hazards work in game. The builder and runtime also need one explicit contract for resolving exported files and kits.

## Decision

1. The builder writes a temporary `derelict_builder_bundle` manifest after successful validation. The manifest identifies the source hash and layout, gameplay-slice, and kit paths.
2. A dedicated local/offline preview scene reads the manifest. Relative paths resolve from the manifest directory; absolute kit paths are preserved as absolute.
3. Preview loading enters through `GeneratedShipLoader` and uses actual structural wrappers and runtime systems. Readiness requires instantiated collision, navigation, vertical links, objectives, authored props, loot, and observable fire, arc, breach, radiation, and atmosphere consumers.
4. Preview emits machine-readable result JSON and a meaningful exit code. The canonical success marker is:

   `DERELICT BUILDER PREVIEW PASS collision=true navigation=true verticals=true objectives=true props=true loot=true fire=true arc=true breach=true radiation=true atmosphere=true`

5. Unsupported semantics fail readiness. The builder must not present an unsupported authored control as working merely because export succeeded.

## Consequences

- Builder Run in Game tests the production loading path locally and offline.
- Manifest-relative resolution prevents preview/export path drift and avoids legacy fixed-file routing.
- Runtime behavior remains authoritative: a successful structural export alone is not a gameplay acceptance result.
- Radiation and authored atmosphere become explicit runtime acceptance gates.

## Rejected alternatives

- Metadata-only markers — they cannot prove collision, navigation, or behavior.
- A second preview-only loader — it would create a divergent runtime authority.
- Cloud or hosted preview execution — local/offline Godot is the supported workflow.
- Full campaign composition in the builder — reusable room/area authoring is the current scope.

## Verification

- Focused preview smoke in `docs/game/06_validation_plan.md`.
- Acceptance marker and result JSON fields listed in `docs/game/features/derelict_builder_runtime_preview.md`.

## Operational note

`legion status --json` currently reports `migration_required` for `.legion/tmp`; therefore no live board card was created in this change.
