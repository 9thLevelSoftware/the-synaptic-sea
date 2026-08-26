# ADR-0058: Layered procgen IR, version envelopes, save reset, and authored fallbacks

- **Status:** Accepted
- **Date:** 2026-08-26
- **Supersedes / amends:** Amends ADR-0007 and ADR-0032 for generated-world
  compatibility; preserves profile/settings portability. Amends layout-schema
  ownership from ADR-0029 and compiler persistence from ADR-0055.
- **Related:** `docs/game/features/unified_procgen_platform.md`;
  REQ-PG-002, REQ-PG-004..009, REQ-PG-012; Gates 0 through 3 and Gate 6

## Context

Current layout/gameplay JSON can be produced by different pipelines and then
mutated in Godot. It does not bind the producing source commit, content
manifest, target artifact, schema family, or semantic identity. Additive layout
schema compatibility is insufficient for a pre-release platform clean break:
loading a world under materially different generator/content rules can create
softlocks or silently change discovered sites.

Generation also needs different consumers. World mapping does not need mesh
instructions; encounter simulation does not need localized names; scene
assembly should not infer mechanics from asset paths. A single untyped layout
blob couples all of them.

## Decision

1. `ProcgenBundle` has four typed semantic layers: `WorldIR`, `SiteIR`,
   `GameplayIR`, and `PresentationIR`. Each layer has an independently declared
   export schema inside one version envelope.
2. `ProcgenRequest` binds world seed, site identity/coordinates, difficulty,
   bounded player snapshot, requested domains, generator version, and content
   manifest hash. Required fields are never inferred from process-global state.
3. A canonical semantic hash covers versioned mechanical content and stable
   identifiers. It excludes serialization map order, locale text, target paths,
   timings, and presentation-only entropy. Presentation-only seeds cannot change
   topology or gameplay.
4. Stable RNG derivation includes world seed, generator version, content hash,
   coordinate/site identity, domain, and named channel. Discovery order,
   concurrency, optional domains, and adapter scheduling do not consume a shared
   mutable stream.
5. Every stage validates, attempts only named bounded local repairs, revalidates,
   and otherwise chooses a versioned authored-safe fallback or fails closed. A
   fallback is a complete validated bundle/layer with its use recorded in the
   trace; partial content is never exported.
6. The checked build manifest records Rust source commit, generator version,
   content-manifest hash, build target, binary/WASM hash, and export-schema
   versions. Startup, adapter loading, saves, diagnostic bundles, and CI compare
   the relevant fields and reject mismatches.
7. Pre-release saves store world/site identity, generator version,
   content-manifest hash, semantic identity, and mutation deltas rather than a
   second mutable generated authority. An incompatible major/schema/content
   envelope cannot load the world and produces a clear new-world prompt.
8. Profile, settings, accessibility, achievements, and other explicitly
   generator-independent data stay portable across that reset. The game never
   silently deletes or rewrites an incompatible world.
9. Runtime asset bindings reference approved manifest IDs. Promoted source
   assets require provenance for source/license, tool/model version, inputs,
   parameters/seed, human changes, technical validation, art approval, and
   promoted manifest entry.

## Consequences

- Domain consumers can evolve without treating presentation paths or localized
  text as mechanics.
- A clean pre-release incompatibility policy is explicit and recoverable; it may
  require starting a new generated world but not a new profile.
- Content changes that affect generation deliberately change identity rather
  than silently contaminating an old run.
- Authored fallbacks become versioned production content with regression
  fixtures, not an informal escape hatch.

## Rejected alternatives

- Best-effort load across incompatible generator/content versions: risks
  discovering different sites and invalid mutation targets.
- Persist the whole instantiated scene as authority: binds saves to Godot nodes
  and cannot prove deterministic regeneration.
- Treat filenames or localized strings as mechanics: breaks manifest and locale
  metamorphic guarantees.
- Export partial layers after a failed validator: transfers invalidity to scene
  code and makes failure nondeterministic.

## Verification

- Schema round-trip, unknown-major rejection, canonical-hash ordering, and
  presentation/locale metamorphic tests.
- Build-manifest generation plus tampered source/content/artifact/schema
  mismatch tests in Rust, Godot startup, and CI.
- Save compatibility tests for compatible mutation replay, incompatible
  new-world prompt, no implicit deletion, and preserved profile/settings.
- Failure-corpus tests prove repair bounds and every authored fallback validates.
