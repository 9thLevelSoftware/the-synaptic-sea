# ADR-0065: Propagate Gate 3 contracts through immutable adapter wrappers

- **Status:** Accepted
- **Date:** 2026-08-26
- **Related:** ADR-0057, ADR-0058, ADR-0060, ADR-0061, ADR-0063,
  ADR-0064; `docs/game/features/unified_procgen_platform.md`;
  REQ-PG-001..004, REQ-PG-007..009, REQ-PG-012; Gate 3 card
  `t_c01fdb84`

## Context

ADR-0064 correctly advances the mechanical Gate 3 contracts to request 2,
player model 2, GameplayIR 2, PresentationIR 2, bundle 4, and lifecycle 4.
The checked Gate 2 capability, generator-manifest, and build-manifest schemas,
however, embed exact constants for the lifecycle and export-schema maps. Those
files cannot describe the Gate 3 contract map without changing their accepted
bytes under an existing identifier. ADR-0064 also refers to generation trace 1
where the accepted Gate 2 contract is generation trace 2.

The project has already established an additive-wrapper rule: a contract that
embeds a changed nested schema map receives a new identifier, while unchanged
mechanical layers retain theirs. Gate 3 must apply that rule consistently on
native and Web.

## Decision

1. Gate 3 adds, and makes current, these immutable public contracts:
   `player-model-2`, `procgen-request-2`, `gameplay-ir-2`,
   `presentation-ir-2`, `procgen-bundle-4`, and
   `procgen-lifecycle-result-4`.
2. Because their exact nested schema maps change, Gate 3 also adds
   `procgen-capabilities-3`, `procgen-generator-manifest-3`, and
   `procgen-build-manifest-3`. Their operational limits and native/Web target
   behavior remain the proven Gate 2 behavior; only the embedded contract map
   advances.
3. `world-ir-2`, `site-ir-2`, `generation-trace-2`,
   `generation-metrics-1`, `procgen-failure-1`, and `adaptive-proposal-1`
   remain current and unchanged. Gate 3 may add bounded named RNG channels and
   typed decision records permitted by trace 2, but it does not relabel the
   trace document.
4. Platform generator version 3 and nested structural ship version 2 remain
   unchanged. The new content-manifest hash and export-schema envelope create
   the intentional pre-release world break.
5. Every earlier schema file remains byte-immutable. Earlier Rust constants and
   wrapper constructors remain available only where migration evidence or
   explicit prior/future-substitution tests require them; production APIs emit
   only the complete Gate 3 map.
6. Native and Web adapters advance together. A mixed request, lifecycle,
   capability, generator manifest, build manifest, or bundle map fails before
   generation or scene assembly.

## Consequences

- Build and runtime identity can represent Gate 3 honestly without weakening
  immutable Gate 2 contracts.
- The adapter implementation changes mechanically but retains the already
  accepted queue, cancellation, timeout, and overload semantics.
- Checked artifacts, parity corpora, Godot consumers, save compatibility, and
  manifest tooling must all move to the same wrapper map in one Gate 3 cut.
- This ADR corrects only wrapper propagation and the trace-version reference;
  ADR-0064 remains authoritative for gameplay, player-model, and presentation
  semantics.

## Rejected alternatives

- Mutate capability, generator-manifest, or build-manifest v2 in place: breaks
  checked-contract immutability and lets identical schema names mean different
  maps.
- Keep wrapper v2 and accept either old or new nested strings: makes startup
  mismatch detection ambiguous and fails closed only by convention.
- Increment the platform or structural generator merely to carry new domains:
  conflates stable algorithm identity with additive IR evolution.

## Verification

- Hash-pin every earlier schema before and after Gate 3 schema export.
- Closed DTO/schema round trips for every new contract and rejection of every
  mixed prior/future substitution.
- Native/Web capability, manifest, lifecycle, sync/async, and semantic-hash
  parity over the refreshed shared corpus.
- Build-manifest schema and startup-consumer tests for exact target, artifact,
  source, content, and export-map identity.
- Save compatibility returns the typed new-world requirement for every Gate 2
  to Gate 3 generated-world mismatch while preserving portable settings.
