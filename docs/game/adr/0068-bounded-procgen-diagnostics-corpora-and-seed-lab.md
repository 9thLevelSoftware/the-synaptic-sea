# ADR-0068: Bound procgen diagnostics, promotion corpora, and the in-engine seed lab

- **Status:** Accepted
- **Date:** 2026-08-26
- **Related:** ADR-0057, ADR-0058, ADR-0059, ADR-0062, ADR-0067;
  `docs/game/features/unified_procgen_platform.md`; REQ-PG-011; Gate 5 card
  `t_bdced4e5`

## Context

Gate 4 produces a complete validated bundle and a bounded replay trace, but a
designer still has to read raw JSON to compare seeds, inspect rejected
candidates and repairs, or understand why an authored fallback was selected.
The project has a structural debug viewer and a crash-report sink, but neither
is a complete bundle consumer: the former predates the layered IR and the latter
accepts arbitrary context without a byte cap or privacy allowlist.

Gate 5 must add an actual in-Godot authoring surface, bounded local diagnostic
documents, and source-controlled regression corpora. It must not mutate the
closed Gate 4 generator contracts, restore GDScript generation authority, write
directly into source-controlled content from an exported game, or turn local
diagnostics into telemetry.

## Decision

1. Gate 5 adds standalone tooling contracts
   `procgen-diagnostic-1`, `procgen-promotion-candidate-1`, and
   `procgen-regression-corpus-1`. They are consumers of a validated
   `procgen-bundle-5` or a typed lifecycle failure. They do not change the
   request, bundle, trace, lifecycle, capability, generator-manifest, or build-
   manifest versions and are not added to the adapter export-schema map.
2. A diagnostic document is an allowlisted summary, never a raw log or full
   bundle. It contains request identity, version and build identities, semantic
   and content hashes, bounded graph/trace counts, selected adaptive decisions,
   metrics, stage timings, fallback and failure codes. It excludes locale,
   filesystem paths, host/device identifiers, account identifiers, arbitrary
   context, free-form player text, stack traces, and network data.
3. Diagnostic JSON is canonicalized before hashing. A stable identity hash
   covers request/version/semantic/failure identity without timings; a capture
   hash covers the complete summary including timings. Documents are capped at
   64 KiB, collections at 64 entries, identifiers at 128 UTF-8 bytes, and
   rationale/failure code strings at 128 ASCII code characters. Any overflow,
   unknown key, invalid code, or disallowed privacy field fails closed.
4. Diagnostics are local-only and content-addressed under
   `user://procgen/diagnostics/<identity-hash>/<capture-hash>.json`. The store
   validates both hashes and the byte cap before writing, refuses a conflicting
   existing file, and never uses a shared temporary filename. No upload,
   telemetry, account, or network API is added.
5. The seed laboratory is a dedicated Godot scene backed by typed pure
   `RefCounted` models/controllers and deterministic graph views. The controller
   invokes the existing GDExtension generation operation once per request and
   passes the lifecycle document through the canonical manifest validator and
   `ProcgenBundleConsumer` before the model can display or promote it. Scene
   nodes render and save consequences; they do not generate or mutate mechanics.
6. The lab exposes two comparison slots; lockable seed, coordinate, archetype,
   difficulty, intactness, loot, player-snapshot, and presentation parameters;
   and an explicit requested-domain selection for selective regeneration. A
   regeneration always returns one internally consistent complete bundle.
   Selective regeneration controls request intent and refreshed views; it never
   splices independently generated IR layers together.
7. Each validated slot exposes capped world, mission, topology, navigation,
   encounter, item, and creature graph projections, plus metrics, validation
   failures, rejected candidates, repairs, retries, named RNG channels,
   adaptive rule traces, semantic hashes, and generator/build manifests. Graph
   layout is deterministic and presentation-only.
8. The lab may write a bounded pending promotion candidate under `user://`, but
   it never writes directly to `res://` or activates runtime content. The
   repository promotion command validates the candidate, approval reference,
   current generator/content identity, classification, expected outcome,
   provenance, ordering, duplicates, privacy allowlist, and corpus freshness
   before atomically updating the source-controlled corpus.
9. Regression-corpus classifications are `approved_candidate`, `failure_seed`,
   and `authored_fallback`. Every entry contains the exact request and expected
   semantic/failure/fallback evidence needed for deterministic replay. Promoting
   an authored fallback means recording an already-validator-selected authored
   fallback outcome as a regression fixture; it does not synthesize, edit, or
   enable new runtime fallback content.
10. Promotion provenance is closed and non-personal: tool/schema version,
    generator/content/build identities, source diagnostic hashes, deterministic
    reason codes, technical-validation codes, and a bounded stage-gate or card
    approval reference. Free-form notes, usernames, machine paths, model output,
    and unapproved asset references are rejected.
11. Source-controlled corpora replay through the current native generator and
    consumer. They fail on stale content/build identities, semantic hashes,
    expected fallback/failure evidence, invalid diagnostics, or unapproved
    ordering. The adapter parity corpus remains a separate cross-platform
    corpus and is not silently rewritten by the seed lab.

## Consequences

- Designers can inspect and compare the complete authoritative generation
  pipeline in-engine without restoring a second generator.
- Diagnostic captures are useful for reproduction while remaining bounded,
  local, privacy-allowlisted, and safe under concurrent requests.
- Promotion is reviewable and source-controlled; exported builds cannot mutate
  authored content or bypass provenance review.
- Timings may differ between captures, but the stable identity hash and expected
  semantic result remain deterministic.
- Gate 5 adds tooling contracts and corpus formats without forcing another
  production bundle or wrapper-version transition.

## Rejected alternatives

- Reuse `CrashReportBundle`: its arbitrary context, timestamps, stack text, and
  missing total byte cap violate the Gate 5 privacy and determinism boundary.
- Embed diagnostics into `procgen-bundle-5`: would mutate a checked production
  contract for a tooling-only concern.
- Let the UI splice selectively regenerated IR layers: can export a combination
  the Rust pipeline never validated.
- Write promoted fixtures directly from the running scene: exported builds
  cannot safely or reviewably mutate source-controlled authored content.
- Store full bundles in every diagnostic: unnecessary, large, and more likely
  to retain data outside the allowlist.
- Treat screenshots, HTML reports, or raw JSON dumps as the seed laboratory:
  none provides the required in-engine interactions or model/controller tests.

## Verification

- RED/GREEN pure-model tests cover all seven graph projections, comparison,
  parameter locks, selective regeneration, trace/repair/rejection inspection,
  hashes/manifests, and promotion-candidate construction.
- Diagnostic tests cover exact keys, canonical hashes, deterministic summaries,
  collection/string/64-KiB caps, path isolation, conflict handling, timing
  capture, lifecycle failure summaries, and a denylist of personal/host/network
  fields.
- Promotion tests cover each classification, provenance, approval reference,
  duplicate/order rejection, stale generator/content/build identities, atomic
  updates, and source-controlled corpus replay/freshness.
- A dedicated `SceneTree` smoke loads and drives the actual seed-lab scene and
  proves compare, locks, selective regeneration, inspection, diagnostics, and
  promotion controls without invoking a RefCounted script directly.
- Godot output must contain the exact Gate 5 PASS markers and no unexpected
  `ERROR:`, `WARNING:`, `FAIL`, or `BLOCKED` line. RoboGodot/manual interaction
  remains required when its callable connector is available.
