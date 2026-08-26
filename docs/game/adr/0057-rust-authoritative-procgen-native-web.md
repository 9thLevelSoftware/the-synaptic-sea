# ADR-0057: Rust is the sole authoritative procgen core on native and Web

- **Status:** Accepted
- **Date:** 2026-08-26
- **Supersedes / amends:** Supersedes ADR-0029's GDScript ownership of topology,
  biome, encounter, and gameplay-slice generation. Preserves ADR-0053 through
  ADR-0056 contracts as inputs to the Rust migration and Godot assembly layer.
- **Related:** `docs/game/features/unified_procgen_platform.md`;
  REQ-PG-001..004; Gate 0 and Gate 1 cards

## Context

The repository currently chooses Rust worldgen on builds that can load
`DerelictGenerator`, then silently executes a different GDScript generator when
the extension is unavailable. Even on the Rust path, layout and gameplay are
exported independently and Godot injects biome, encounter, loot, and gameplay
mutations afterward. Web has no equivalent Rust adapter. The same seed therefore
does not identify one production algorithm across targets, and a successful
fallback can conceal a broken or mismatched native artifact.

The external `D:\world_gen` repository already contains the stronger structural
core: generator versioning, named RNG streams, authoritative topology, bounded
retries, fail-closed validation, repair, damage, deterministic exports, and
tests. Rebuilding that core would discard working evidence.

## Decision

1. Import `D:\world_gen` with history at `native/worldgen/`. Rust source,
   schemas, manifests, adapters, and checked runtime artifacts version together
   in this repository.
2. Rust is the only production generator. Native targets use GDExtension and Web
   uses WebAssembly compiled from the same core and schemas.
3. Public native and Web surfaces are behaviorally equivalent:
   `generate_bundle`, `generate_bundle_async`, `poll`, `cancel`, `capabilities`,
   and `generator_manifest`.
4. One generation call runs the requested pipeline once and returns one complete
   `ProcgenBundle`. Separate layout/gameplay calls may exist only as explicitly
   named migration-oracle tooling until retirement.
5. The Godot layer validates the envelope and hash, resolves authored resources,
   instantiates presentation, applies runtime consequences, and persists
   mutation deltas. It does not authoritatively change topology, encounters,
   loot, items, creatures, biome mechanics, or budgets after export.
6. Missing classes, unsupported capabilities, manifest mismatches, queue
   overload, cancellation, timeout, validation failure, or adapter failure
   return explicit stable result codes or a declared authored fallback. They
   never select the GDScript generator silently.
7. Asynchronous native execution uses a bounded worker queue with request/entity
   caps, cancellation, time budgets, bounded retained results, and deterministic
   overload resolution. Thread-per-request is removed.
8. The legacy GDScript generator remains a non-production migration oracle until
   Gate 6 evidence permits deletion. Reusable loaders and presentation code may
   remain.

## Consequences

- A platform without a compatible Rust/WASM adapter fails clearly instead of
  appearing to generate a different world successfully.
- Native artifacts and Web modules must be reproducible from the imported source
  and checked against the build manifest.
- Godot tests must distinguish adapter errors, authored fallbacks, and migration
  oracle runs.
- Incremental cutover is possible without weakening the final authority rule:
  incomplete domains return explicit unsupported/fallback results rather than
  delegating production authority to GDScript.

## Rejected alternatives

- Keep GDScript as a platform fallback: this preserves platform-dependent
  mechanics and conceals broken integration.
- Rewrite the existing Rust core around Godot data structures: this loses the
  tested pure core and couples validation to scene runtime.
- Hosted generation: incompatible with the local-installable, offline product
  and introduces account, latency, privacy, and availability dependencies.
- Run Web through a JavaScript reimplementation: a second algorithm cannot meet
  semantic parity requirements.

## Verification

- Rust contract and adapter tests for all six lifecycle methods.
- Godot missing-adapter and mismatch tests assert explicit failure/fallback codes
  and prove the migration oracle is never selected.
- Native Windows/macOS/Linux and Web requests with identical inputs produce the
  same semantic hash.
- Queue saturation, cancellation, timeout, and retained-result bounds are tested
  deterministically.
