# ADR-0052: Asset Metadata and Visual Binding Architecture

## Status

Accepted for the asset-metadata retrofit; implementation begins in Task 2.

## Date

2026-07-31

## Context

The repository has imported component, dressing, and objective GLBs, existing component and
objective gameplay owners, and structural wrappers that already define connector,
collision, and integrity behavior. The visual assets need portable metadata without
turning sidecars into a second gameplay database or allowing visual refresh work to erase
designer-authored bindings and provenance.

The retrofit must also be reproducible. A derived runtime index can make lookup cheap, but
it must be regenerated from source records rather than manually maintained. Structural
variants are a separate contract from direct prop visuals, and objective identity must
remain stable when multiple objectives share a type.

## Decision

1. **A same-basename prop GLB plus adjacent `.sidecar.json` is the portable visual asset
   record.** The GLB supplies visual source data; the `.sidecar.json` supplies stable
   identity, schema, bindings, placement information, provenance, and explicitly declared
   visual policy. The canonical pair is `<name>.glb` plus `<name>.sidecar.json` in the same
   directory, one sidecar per GLB. The pair is portable as a unit and is invalid when the
   sidecar is missing or does not name its matching GLB.
2. **The runtime index is derived and generator-only.** Runtime lookup consumes a
   deterministic index generated from valid sidecars and their GLBs. The index is never a
   hand-authored source of truth, and freshness/hash validation rejects stale or manually
   edited output.
3. **Direct prop GLBs are visual-only and use `collision_policy=none_visual_only`.** Prop
   metadata does not generate gameplay collision, navigation, connector geometry, or
   integrity consequences. Those behaviors remain owned by the runtime systems and
   structural wrappers that already implement them.
4. **Structural wrapper contracts own connector, collision, and integrity.** Structural
   wrappers own sockets/connectors, collision proxies, and intact/damaged/breached state
   switching. Replacing a visual child must not change those contracts or introduce
   socket/collision drift.
5. **Objectives resolve via gameplay `placement_id`, not type.** The gameplay-authored
   placement ID is the stable binding key. Objective type is descriptive data and cannot
   select a visual when two placements share that type.
6. **Missing binding retains the domain's existing fallback, never an unrelated
   substitute.** A missing, malformed, stale, or unsupported component binding retains the
   existing primitive fallback; the same failure in an objective binding retains the
   existing readability fallback. Both report `visual_source="fallback"`; neither silently
   borrows another component, objective, or prop visual.
7. **An explicit GLB-derived refresh preserves extensions and hand-authored binding/placement/provenance.** The refresh may update only fields derived from the GLB,
   such as source hash and visual bounds. Unknown extensions and authored binding,
   placement, and provenance fields survive byte-for-byte or semantically equivalent
   refresh output.

## Canonical document contract

- The canonical derived index path is `data/props/visual_bindings.generated.json`.
- Each sidecar document is a same-basename `<name>.sidecar.json` adjacent to its source
  `<name>.glb`, with `schema_version: "1.0.0"` and
  `document_kind: "prop_visual_binding"`.
- The index document at the canonical path has `schema_version: "1.0.0"` and
  `document_kind: "prop_visual_binding_index"`.
- Every GLB source hash is SHA-256 represented by exactly 64 lowercase hexadecimal
  characters.
- Visual bounds are meter-space `[x, y, z]` local min/max arrays, and every coordinate is
  rounded to six decimal places.
- Canonical JSON is lexicographically key-sorted, compact, newline-terminated, and
  timestamp-free. The index is generated only from validated sidecars and their source
  GLBs; it is never hand-authored or edited as a second authority.

## Ownership boundaries

- Asset/content authors own sidecars, bindings, placement declarations, provenance, and
  extensions.
- The GLB refresh/generator owns derived hashes and bounds and emits the runtime index.
- Component placement/catalog/runtime owners retain component-marker placement, component
  save/load ownership, lifecycle, and ship-system linkage.
- Gameplay objective volumes/controllers retain objective volume and progression state.
- Structural placement/integrity owners retain wrapper sockets, collision, and variants.
- The visual resolver owns fallback reporting but does not own the gameplay state behind a
  binding.

## Consequences

- Prop records can move between projects or generated runs without losing their authored
  identity and provenance.
- Runtime lookup stays deterministic and reproducible while sidecars remain reviewable
  source documents.
- Visual-only props cannot accidentally become gameplay collision or duplicate objective
  and component state.
- Structural variants can change appearance without changing passability, connectors, or
  integrity semantics.
- Refresh tooling needs a preservation-aware merge rather than a blind JSON rewrite.
- Unsupported or missing bindings remain visible as explicit fallback evidence instead of
  being hidden by a plausible but incorrect substitute.

## Alternatives considered

1. **Use GLB filenames or objective types as runtime identity.** Rejected because paths and
   types do not provide stable authored placement identity.
2. **Hand-author one global runtime index.** Rejected because it duplicates sidecars and
   becomes stale or non-portable.
3. **Generate collision directly from prop GLBs.** Rejected because structural wrappers
   and gameplay systems already own collision and integrity behavior, and visual assets
   are intentionally collision-free.
4. **Treat missing bindings as best-effort nearest-asset lookup.** Rejected because an
   unrelated substitute hides broken authored data and can mislead gameplay validation.
5. **Overwrite sidecars on every GLB import.** Rejected because it destroys extensions,
   authored bindings, placement, and provenance.

## Validation

- Feature contract: `docs/game/features/asset_metadata_pipeline.md`.
- Requirements: `REQ-AVB-001` through `REQ-AVB-009` in `docs/game/05_requirements.md`.
- Reproducible commands and Task 1 baseline evidence:
  `docs/game/06_validation_plan.md`.
- Structural wrapper baseline remains intentionally failing with eight missing
  `VisualInstance` errors until Task 2 supplies the required visual bindings.
- The exact two-instance ObjectDB teardown warning is classified as pre-existing external
  baseline noise owned by `ship-core` only for the component-marker smoke; any other
  diagnostic or count fails the feature gate. Removal is tracked by blocked Kanban card
  `t_b9b4e4f9` (title: Investigate ObjectDB leak in component marker smoke).
