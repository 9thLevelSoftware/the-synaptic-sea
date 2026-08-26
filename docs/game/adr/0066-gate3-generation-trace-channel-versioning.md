# ADR-0066: Version the Gate 3 generation trace channel set

- **Status:** Accepted
- **Date:** 2026-08-26
- **Related:** ADR-0058, ADR-0063, ADR-0064, ADR-0065;
  `docs/game/features/unified_procgen_platform.md`; REQ-PG-002,
  REQ-PG-003, REQ-PG-008, REQ-PG-009, REQ-PG-012; Gate 3 card
  `t_c01fdb84`

## Context

Gate 2's immutable `generation-trace-2` schema fixes the complete ordered list
of 28 structural, world, and site RNG channels. Gate 3 adds ten authoritative
gameplay and presentation channels for creature compilation, encounter
selection and rewards, item construction, and asset assembly. Emitting those
channels under `generation-trace-2` makes a valid Gate 3 bundle fail the checked
standalone trace schema and changes the meaning of an existing identifier.

ADR-0065 allowed additional named channels without relabelling the trace. That
is incompatible with the checked exact-channel constraint and the project's
immutable-contract rule.

## Decision

1. Gate 3 adds `generation-trace-3` and makes it current for platform-v4
   requests, bundles, lifecycle results, capability maps, generator manifests,
   build manifests, native/Web adapters, Godot consumers, and validation tools.
2. `generation-trace-3` fixes the ordered 37-channel list emitted by the Rust
   generator. The exporter reads that list from the same Rust constant used by
   generation so schema and runtime cannot drift independently.
3. `generation-trace-1` and `generation-trace-2` remain byte-immutable
   migration evidence. Platform-v3 constructors and checked artifacts continue
   to identify `generation-trace-2`.
4. Gate 3's not-yet-promoted wrapper identifiers remain capability 3,
   generator-manifest 3, build-manifest 3, bundle 4, and lifecycle 4. Their
   checked maps advance to trace 3 before artifact promotion; no released
   contract is rewritten.
5. A mixed trace identifier or an altered channel order fails schema, Rust,
   adapter, startup-manifest, and Godot-consumer validation before assembly.

## Consequences

- Identical trace identifiers once again have identical channel semantics.
- Replay diagnostics can name every RNG stream used by authoritative Gate 3
  generation without weakening the older contract.
- Native, Web, checked manifests, fixtures, parity corpora, and the Godot
  consumer must move to the trace-3 map in the same Gate 3 cut.

## Supersession

This ADR supersedes only ADR-0065 Decision 3 and the trace-retention statements
in ADR-0064. Their gameplay, presentation, wrapper, and structural-version
decisions remain accepted.

## Verification

- Hash-pin every pre-Gate-3 schema, including `generation-trace-2`.
- Validate a generated trace independently against `generation-trace-3` and as
  the nested trace in bundle 4 and lifecycle 4.
- Reject trace-2 substitution and any missing, added, or reordered current RNG
  channel at Rust, JSON Schema, adapter, and Godot-consumer boundaries.
- Prove native/Web semantic-hash parity with the exact same trace-3 export map.
