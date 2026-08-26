# ADR-0062: Generated-world save envelope and clean-break load result

- **Status:** Accepted
- **Date:** 2026-08-26
- **Amends:** ADR-0007 and ADR-0032 for generated-world data; implements the
  persistence decision in ADR-0058 and the version split in ADR-0061
- **Related:** `docs/game/features/unified_procgen_platform.md`; REQ-PG-004,
  REQ-PG-005, REQ-PG-012; Gate 2 card `t_0901bbf`

## Context

The current native `ShipPersistence` file stores a seed, one generator version,
generation parameters, and a permissive mutation diff. The current Godot
`WorldSnapshot` stores broad runtime summaries but no procgen content/schema or
semantic identity. Loaders return `null` for several incompatible cases, skip
unknown mutation targets, and cannot tell the UI whether a file is corrupt,
newer, or a valid world that requires the intentional pre-release clean break.

Settings are also embedded in run data or held in memory. Starting a compatible
new world must not require discarding accessibility/settings state, and an
incompatible generated world must never be silently deleted or overwritten.

## Decision

1. Add a closed `generated-world-save-1` envelope. Its world identity records
   world seed, platform generator version, content-manifest hash, and the exact
   export-schema map. Each discovered site records site id/coordinates, derived
   site seed, structural generator version, bundle semantic hash, and one
   bounded typed mutation delta.
2. Mutation deltas identify their base site and base semantic hash and contain
   only approved operation variants with stable target kind/id and bounded
   typed payloads. Generated topology, encounter composition, item definitions,
   creature blueprints, and presentation bindings are not copied into the save
   as a second authority.
3. Compatible loading is two-phase. The loader first validates the entire save,
   compares the current platform/content/schema envelope, regenerates each
   referenced bundle through an injected bundle provider, verifies site,
   structural, and semantic identity, and validates every delta target. Only
   after every site and operation passes may an injected applier mutate runtime
   state. Invalid targets or identities produce no partial application.
4. Load returns a closed typed result with `compatible`,
   `new_world_required`, `corrupt`, or `io_failure` status plus a stable reason
   code. Platform, content, export-schema, structural, or semantic mismatches are
   `new_world_required`, not corruption and not best-effort migration.
5. A `new_world_required` result includes the preserved original path and its
   identity summary. Evaluation performs no write, rename, delete, or migration.
   Archiving/replacing an incompatible world requires a later explicit
   user-confirmed action; there is no automatic candidate selection.
6. Corrupt input is distinguished from incompatibility. Any recovery copy is
   additive and leaves the original bytes recoverable; corruption handling must
   not masquerade as a clean-break decision.
7. Until Gate 6 cuts over all call sites, the new generated-world service uses a
   separate versioned file and does not reinterpret existing `world.json`,
   `current_run.json`, or native per-site files. Gate 6 owns their coordinated
   migration/retirement.
8. Add a generator-independent portable profile/settings file containing the
   closed settings schema and accessibility values only. It remains loadable
   when generated-world compatibility fails and never carries world or gameplay
   authority.
9. New save/profile writes use same-directory request-scoped temporary paths,
   validate the staged document, then replace atomically where the platform
   permits. No fixed shared temporary filename is introduced.
10. The title/load UI consumes a pure prompt-state seam derived from the typed
    result. It can show the reason and preserved path and offer explicit new
    world/back actions; it cannot delete a world as a side effect of probing
    whether Continue is available.

## Consequences

- A generated world can be regenerated and replayed without duplicating its
  procedural authority in save files.
- Incompatible pre-release data produces a clear, recoverable state rather than
  a null result or silent reset.
- Existing save systems remain operational until the Gate 6 cutover, so the
  transition temporarily has two explicitly named persistence surfaces.
- Profile/settings portability becomes independent of generated-world format.

## Rejected alternatives

- Add only `generator_version` to `WorldSnapshot`: cannot detect content,
  schema, site-seed, structural, or semantic drift.
- Apply deltas as targets are encountered and skip missing IDs: permits partial
  state and hides an incompatible regenerated site.
- Treat incompatibility as corruption and move/delete the file: destroys useful
  pre-release evidence and violates the clean-break policy.
- Persist the complete generated bundle/scene as save authority: duplicates
  mechanics and binds persistence to old nodes/content.
- Keep settings only inside the incompatible world: forces accessibility and
  player preferences to reset with generated content.

## Verification

- Exact compatible round trip regenerates bundles, validates all targets, then
  applies deltas once.
- Every platform/content/export-schema/site/structural/semantic mismatch returns
  `new_world_required` with unchanged original bytes/path.
- Unknown target, duplicate operation, oversized delta, malformed payload, and
  provider mismatch return a typed failure with zero applied operations.
- Prompt-state probes are read-only and deletion APIs are not called.
- Portable profile/settings survive each generated-world mismatch and reject
  unknown fields/versions without importing gameplay state.
- Focused Godot 4.7.2 smokes emit one pass marker and no unexpected diagnostics.
