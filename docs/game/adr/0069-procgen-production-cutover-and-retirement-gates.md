# ADR-0069: Cut production entry points over to in-memory procgen bundles

- **Status:** Accepted
- **Date:** 2026-08-26
- **Related:** ADR-0057, ADR-0058, ADR-0060, ADR-0062, ADR-0068;
  `docs/game/features/unified_procgen_platform.md`; REQ-PG-001,
  REQ-PG-003, REQ-PG-012; Gate 6 card `t_46fd8510`

## Context

The Rust generator and its native/Web lifecycle contracts are authoritative,
but several Godot entry points still bypass them. Top-down generation and the
start-scene builder invoke the legacy layout and gameplay builders directly.
Production startup and save reload consume fixed layout/gameplay paths, and the
legacy migration loader writes shared temporary filenames. Those paths make a
validated bundle cease to be the unit that actually enters gameplay.

Gate 6 must cut over production without invalidating the large authored-fixture
regression suite or deleting migration evidence before all supported platform,
export, visual, save-reset, performance, and gameplay gates have passed.

## Decision

1. `ShipGenerator` is the sole Godot production gateway. It exposes an
   in-memory generation result containing the exact validated `ProcgenBundle`,
   request, mapped layout/gameplay documents, approved kit document, semantic
   hash, and fallback outcome. One call to the native lifecycle produces each
   result; consumers may not rebuild gameplay or mutate biome/encounter/loot
   authority afterward.
2. Seed-based callers and save reload both use that gateway. Seed callers build
   a versioned request through `ProcgenBundleConsumer`; reload callers replay
   the persisted exact request and require the regenerated semantic hash to
   match before any scene consequences or mutation state are applied.
3. `GeneratedShipLoader.load_from_documents` is the production assembly seam.
   Travel, project-title New Game/Continue startup, top-down generation, the
   start-scene builder, and bundle-backed debug/export tooling pass documents in
   memory. Shared `user://procgen_temp` and `user://start_scenario` files are not
   used by those paths.
4. The project title explicitly configures `main.tscn` for bundle startup before
   adding it to the tree. Direct `main.tscn` and golden-scene smokes remain
   explicitly classified authored-fixture/migration harnesses until their
   gameplay assertions are ported; fixture loading is never selected because a
   native request failed.
5. Run snapshots advance through the existing save-version policy and carry a
   closed procgen replay identity: exact request plus expected semantic hash.
   Bundle-backed saves regenerate and verify that identity. Production Continue
   rejects older/path-only snapshots with the clean-break new-world outcome;
   those snapshots remain readable only inside explicitly named fixture/oracle
   harnesses and are never migrated into a live production run. New production
   saves do not depend on generated temporary paths.
6. The separate `generated-world-save-1` envelope remains the authoritative
   clean-break and mutation-delta contract from ADR-0062. Gate 6 must wire it to
   production before final exit; broad runtime summaries in the historical
   `WorldSnapshot` are transitional and do not become procedural authority.
7. First-run selection may inspect only canonical bundle candidates. It may not
   call the GDScript layout or gameplay builders. The ultimately selected site
   is regenerated from the same stable request identity by the normal travel
   path.
8. Fixed authored inputs are permitted for immutable regression fixtures and
   offline migration comparison only. They must be named/classified as such and
   cannot be reached from project production boot, travel, top-down play, or a
   bundle-backed save.
9. Legacy GDScript generators, path loaders, and migration fixtures are deleted
   only after Windows, macOS, Linux, and exported Web semantic parity; fallback
   and clean-break save evidence; full regression; visual review; performance;
   and representative gameplay evidence are accepted. Missing platform evidence
   keeps retirement open rather than weakening or silently skipping a gate.
10. Gate 6 automation has distinct PR and nightly profiles. PR runs at least
    10,000 deterministic composite cases plus corpus, metamorphic, native/Web
    adapter, and Godot entry-point checks. Nightly runs at least one million
    domain cases plus adversarial/simulation campaigns. Every runner records its
    actual case count and fails if the requested floor was not reached.

## Implementation status (2026-08-26)

The Windows-local entry-point cutover is implemented and verified. Travel,
title/main startup, top-down play, start-scene generation, capture/export, and
debug paths consume in-memory documents from one native bundle lifecycle call.
Current-run summaries persist a normalized exact request and semantic hash and
reject incompatible identity before applying saved state. Current-world
summaries preflight each site's request/version/hash shape, but do not yet
provide atomic multi-site regeneration and delta application. The 14-smoke
production runner and 32-smoke expanded runner pass with a strict clean output
scan. The 10,000-case PR campaign passes with 9,992 bundles and eight
replay-identical typed fail-closed outcomes while structural-v2 golden output
remains byte-stable.

This does not close Gate 6. Decision 6 still requires a production adapter for
`generated-world-save-1`: a live Rust-backed provider must regenerate every
persisted site and an atomic typed applier must validate every target before one
commit. The current `WorldSnapshot` path remains transitional. The nightly
million-case run, macOS/Linux/exported-Web parity, windowed performance,
RoboGodot/manual review, and representative gameplay evidence also remain open.
The migration oracle is therefore retained intentionally.

## Consequences

- A production scene can be traced back to one exact request, bundle, semantic
  hash, manifest, and mapping operation without request-shared temporary files.
- Save reload fails closed on semantic drift before applying saved gameplay
  state.
- Existing authored-fixture tests can remain stable while production is cut
  over, but their classification is visible and they provide no platform-retire
  evidence by themselves.
- The migration oracle remains source-visible until the external Gate 6 matrix
  is complete; this ADR does not authorize premature deletion.

## Rejected alternatives

- Change only top-down generation: startup and reload would still make path
  documents the production authority.
- Persist the full bundle or instantiated scene: duplicates generator authority
  and binds saves to stale content.
- Fall back to GDScript when the extension is absent or overloaded: recreates
  cross-platform semantic divergence.
- Rewrite every historical fixture smoke during cutover: conflates regression
  evidence with production routing and makes the change needlessly unsafe.
- Delete the migration generator after Windows-local success: cannot establish
  macOS, Linux, Web, export, visual, or performance parity.

## Verification

- A dedicated Godot entry-point smoke asserts one native lifecycle invocation,
  in-memory assembly, exact request/hash replay, top-down/start-builder bundle
  consumption, and zero migration-oracle invocations or shared temp files.
- Source assertions reject production imports/calls to `ShipLayoutGenerator`,
  `GameplaySliceBuilder`, `generate_layout_migration_oracle`, and fixed procgen
  temp paths while allowlisting explicit migration/fixture files.
- Save smokes cover bundle identity round trip, semantic mismatch rejection,
  production rejection of path-only snapshots, fixture-only oracle isolation,
  and zero state application on failure.
- PR/nightly harness tests verify their floors, deterministic hashes,
  metamorphic properties, promoted corpus, native/Web adapter parity, and
  bounded performance output.
- Full Godot output must contain expected pass markers and no unexpected
  `ERROR:`, `WARNING:`, `FAIL`, or `BLOCKED` lines. Cross-platform exports,
  windowed performance, RoboGodot/manual review, and representative gameplay
  remain mandatory final-exit evidence.
