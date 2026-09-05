# ADR-0061: Persist the resolved context of a generated ship

- Status: Accepted contract; implementation and regression evidence pending.
- Date: 2026-09-04
- Requirement: FC-02; supports FC-18 and FC-22 deterministic restoration.

## Context

The native generation route omitted builder-authored electrical arc descriptors.
Repairing that projection exposed two regeneration inconsistencies in the
canonical derelict arc smoke. Reload used the fallback generation entry point,
and revisit recalculated biome/difficulty from the seed without retaining the
first-run contract's overrides. A persisted arc summary can consequently refer
to zone IDs absent from regenerated geometry even though the summary survived.

## Decision

ShipBlueprint is the authority for generation inputs. Add an optional versioned
`generation_context_v1` payload containing the resolved biome and difficulty
identifiers. Capture the context actually used for initial generation, including
first-run overrides, before the blueprint becomes the ShipInstance identity.
Serialize it through the existing blueprint dictionary; restored instances retain
their own context rather than inheriting the generator's last configured state.

Reload and revisit use the same public native-capable generation entry point as
initial travel, with the saved seed, size, condition and resolved context. This
change does not alter seeds or retrofit a new room graph. Existing backend/version
compatibility remains subject to the P00 baseline and later structural fingerprint
checks; the context payload does not authorize substituting a different generator.

This is an optional additive blueprint payload, not a new top-level RunSnapshot
field. Existing blueprint dictionaries without it remain readable and use the
documented legacy deterministic context resolver. A present malformed or unsupported
context must not silently masquerade as an absent legacy field. The feature program
will carry this payload forward into the reserved run/world v5 formats in P10.

## Limits and verification

Old saves never recorded first-run context overrides, so the missing historical
input cannot be claimed recovered from the seed alone. Preserve their supplied
data and document the legacy fallback; do not invent context from damage state.

Acceptance requires explicit native-route generation evidence, same-context and
same-seed deterministic descriptors, blueprint summary round-trip, and the full
derelict arc smoke passing initial boarding, away simulation, reload and revisit.
Saved arc zone IDs must address the newly built descriptors at every reconstruction.
Current run context from a different ship must not affect this result.
