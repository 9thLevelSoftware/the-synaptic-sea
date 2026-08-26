# Unified Procedural-Generation Platform Roadmap

## Status

Approved for staged implementation. This tracked plan records the user-supplied
implementation program and is subordinate to the canonical feature spec,
requirements, ADRs, and gate evidence created by Gate 0.

## Summary

- Keep and generalize Rust worldgen v2; do not rebuild its structural core. It
  already provides authoritative topology, named RNG streams, generator
  versioning, bounded retries, fail-closed validation, damage repair, async
  support, and strong tests.
- Replace the current integration architecture: Synaptic Sea presently uses
  Rust on Windows but silently falls back to a materially different GDScript
  generator elsewhere. The Rust cutover is also absent from the canonical
  feature, ADR, requirements, and regression documentation.
- Build a complete game-specific PCG platform covering the Synaptic Sea world,
  derelicts, missions, encounters, items, creatures, and runtime assembly of
  authored assets.
- Use the same Rust core through GDExtension on desktop and WebAssembly on Web.
  Adopt a versioned clean break for incompatible pre-release saves.
- Ship deterministic classical adaptation first. Add an embedded offline model
  only in a later evidence-gated milestone, behind the same constrained
  proposal interface.

## Global constraints

- Rust worldgen is the sole authoritative generator on every production
  platform. A materially different generator may never be selected silently.
- Godot consumes validated bundles, instantiates approved authored assets,
  applies scene consequences, and persists mutation deltas; it does not make
  authoritative post-generation biome, encounter, loot, item, or creature
  decisions.
- Generation is deterministic for a stable request, generator version, content
  manifest, platform adapter, and domain set.
- Every exported bundle is versioned, validated, semantically hashed, traced,
  and fail-closed. Bounded repair precedes an authored-safe fallback.
- Incompatible pre-release world saves require an explicit new-world flow while
  profile and settings data remain portable.
- Runtime content is deterministic assembly of approved authored assets.
  Generative tools may propose source assets offline only.
- No embedded model may bypass validators, budgets, authored envelopes, or
  deterministic fallbacks.
- Unexpected Godot `ERROR:` or `WARNING:` output blocks acceptance unless it is
  explicitly classified and approved.

## Gate 0 — Governance and source unification

- Import `D:\world_gen` with history into `native/worldgen/` so Rust source,
  Godot integration, schemas, content manifests, and binaries version
  atomically.
- Create the canonical platform feature spec, update `REQ-PG-*`, risk register,
  validation plan, systems map, and mark the older expansion documents as
  superseded where their GDScript assumptions are obsolete.
- Add ADRs for:
  - Rust as the sole authoritative generator across native and Web.
  - Layered semantic IR, versioning, save-reset policy, and authored fallbacks.
  - Deterministic adaptive director/ranker with optional later embedded
    inference.
- Create separate scoped cards on `synaptic-sea-stage-gate` for every gate,
  each citing requirements, allowed files, non-goals, dependencies, and
  verification commands.
- Add a build manifest containing Rust source commit, generator version,
  content-manifest hash, target, binary/WASM hash, and export-schema versions.
  Reject mismatches at startup and in CI.

## Gate 1 — Unified contracts and integration

- Replace separate layout/gameplay export calls with one generation operation
  that runs the pipeline once and returns a complete bundle.
- Introduce versioned public contracts:
  - `ProcgenRequest`: world seed, site identity and coordinates, difficulty,
    player-model snapshot, requested domains, generator version, and
    content-manifest hash.
  - `ProcgenBundle`: `WorldIR`, `SiteIR`, `GameplayIR`, `PresentationIR`,
    semantic hash, metrics, trace, and version envelope.
  - `GenerationTrace`: named RNG channels, selected/rejected candidates, failed
    constraints, repairs, retries, fallback use, and per-stage timings.
  - `AdaptiveProposal`: candidate score, rationale codes, confidence,
    model/rule version, and permitted encounter or ranking action.
- Expose matching native and Web APIs: `generate_bundle`,
  `generate_bundle_async`, `poll`, `cancel`, `capabilities`, and
  `generator_manifest`.
- Replace unbounded thread-per-request behavior with a bounded worker queue,
  request caps, cancellation, time budgets, and deterministic overload
  handling.
- Make Godot a consumer: validate the envelope, instantiate authored resources,
  apply scene consequences, and persist mutation deltas. Remove authoritative
  post-generation encounter, loot, or biome mutation from the Godot bridge.
- Keep the old GDScript generator only as a migration oracle. Never select it
  silently at runtime.

## Gate 2 — World and ship generation

- Move coordinate-addressed marker generation, route graphs, biome/hazard
  fields, site archetypes, resource pressure, landmarks, and extraction
  guarantees into `WorldIR`.
- Derive every site through stable `(world_seed, generator_version,
  content_manifest, coordinate, channel)` keys so discovery order and parallel
  scheduling cannot change results.
- Extend the existing ship topology/compiler with mission graphs, key/lock and
  repair-gate ordering, functional prop sockets, traversal clearance,
  LOS/cover annotations, and objective reachability.
- Apply `validate -> bounded local repair -> revalidate -> authored-safe
  fallback`. Never export disconnected or partially valid content.
- Persist world/site identity, generator/content versions, and mutation deltas.
  Incompatible pre-release worlds fail with a clear new-world prompt;
  profile/settings data remains portable.

## Gate 3 — Encounters, items, creatures, and presentation

- Generate encounters from authored factions, roles, abilities,
  threat/economy budgets, room occupancy, navigation, visibility, pacing, and
  current player capability. Every spawn and composition has a replayable
  decision record.
- Generate items from authored families, typed sockets/affixes, stat budgets,
  rarity envelopes, drop-frequency targets, economy constraints, and
  visual-binding tags. Unconstrained generated text never controls stats.
- Generate creature blueprints from compatible authored body plans, rigs,
  animations, abilities, behaviors, materials, footprints, and counterplay
  roles. Reject incompatible or untraversable combinations.
- Keep runtime visuals as deterministic assembly of approved meshes, materials,
  animations, VFX, and audio. Blender or generative tools may propose source
  assets offline only.
- Require asset provenance records covering source/license, tool or model
  version, inputs, parameters/seed, human changes, technical validation, art
  approval, and promoted content-manifest entry.

## Gate 4 — Adaptive director and candidate ranker

- Implement deterministic utility scoring/search first:
  - The candidate ranker selects only among fully validated world/site
    candidates.
  - The encounter director adjusts composition and pacing only within authored
    threat, economy, fairness, and performance envelopes.
  - Player modeling uses a bounded, versioned snapshot of run-local gameplay
    signals; no network or account dependency is introduced.
- Log inputs, candidates, scores, selected actions, rationale codes, and
  fallback decisions so runs remain diagnosable and replayable.
- Add an optional embedded-model experiment only after the classical
  implementation passes production gates. It implements the same proposal
  interface, cannot bypass validators, and falls back deterministically on
  timeout, unsupported hardware, invalid output, or disabled configuration.
- Promote embedded inference only after a measurable quality benefit without
  violating build-size, memory, latency, determinism, accessibility, or legal
  gates.

## Gate 5 — Authoring and observability

- Add an in-Godot seed laboratory showing world, mission, topology, navigation,
  encounter, item, and creature graphs alongside metrics and validation
  failures.
- Support seed comparison, locked parameters, selective regeneration,
  rejected-candidate inspection, repair explanation, rule/RNG-channel tracing,
  semantic hashes, version manifests, and promotion to authored fixtures or
  fallbacks.
- Store promoted failure seeds and approved candidates as source-controlled
  regression corpora.
- Emit bounded local diagnostic bundles containing request identity, versions,
  hashes, trace summaries, metrics, timings, and failure codes without
  collecting personal data.

## Gate 6 — Cutover and retirement

- Prove native Windows, macOS, Linux, and Web builds produce the same semantic
  hash for identical requests and manifests.
- Register the existing worldgen travel smoke and new bundle/parity tests in the
  canonical regression script; unexpected Godot warnings or errors remain
  blocking.
- Switch every production entry point—travel, starting scene, top-down mode,
  saves, captures, and debug tools—to `ProcgenBundle`.
- Remove fixed temporary filenames and use in-memory documents or
  request-scoped paths where files are necessary.
- Delete the legacy GDScript generation pipeline only after parity, fallback,
  save-reset, export, and full gameplay regression gates pass. Retain only
  reusable loader/presentation code and archived migration evidence.

## Execution tasks

The gates above are acceptance boundaries. The numbered tasks below are the
reviewable implementation units used by Subagent-Driven Development. They run
sequentially; each task may consume earlier interfaces but must stay inside its
owned files and gate card.

### Task 1: Gate 0 manifest integrity and systems-map currency

Prerequisites already completed by the primary agent: governing feature/ADRs/
requirements/risks/validation plan, linked Gate 0..6 cards, and unsquashed
history import at `native/worldgen/`.

- Define `procgen-build-manifest-1` with `rust_source_commit`,
  `generator_version`, `content_manifest_hash`, `target`, artifact path/hash,
  and explicit request/bundle/trace/proposal plus layer schema versions.
- Add a deterministic generator/checker. Hash canonical content by sorted
  repository-relative path plus file bytes; never hash filesystem timestamps.
- Add Rust parsing/validation and expose the manifest data required by adapters.
- Add a typed Godot validator and startup seam. The production Rust path rejects
  missing/malformed/mismatched manifests; it must not choose GDScript.
- Update system inventory source JSON and regenerate derived map artifacts.
- Tests first: valid manifest, each tampered field, missing artifact, artifact
  hash mismatch, content mismatch, unknown manifest major, and Godot rejection.
- Owned files: manifest/schema/check tooling; Rust manifest module/tests; typed
  Godot manifest validator/smoke and minimal production startup hook; inventory
  source/generated outputs. Do not redesign bundle APIs in this task.

### Task 2: Gate 1 versioned contracts and single-pass core bundle

- Add versioned Rust types for `ProcgenRequest`, `ProcgenBundle`, `WorldIR`,
  `SiteIR`, `GameplayIR`, `PresentationIR`, `GenerationTrace`, metrics, version
  envelope, result/failure codes, and `AdaptiveProposal`.
- Canonicalize semantic hashing over mechanical IR while excluding timings,
  locale, target paths, and presentation-only entropy.
- Implement `generate_bundle` as one pipeline execution; migration exports may
  derive both legacy documents from that one result.
- Tests first: serde round trips, unknown-major rejection, one-execution proof,
  stable semantic hash, map-order invariance, and presentation/locale isolation.
- Owned files: Rust core contract/bundle/schema modules and focused tests. Do not
  change async or Godot call sites.

Task 2 contract decisions:

- Schema constants are exactly `procgen-request-1`, `procgen-bundle-1`,
  `world-ir-1`, `site-ir-1`, `gameplay-ir-1`, `presentation-ir-1`,
  `generation-trace-1`, `adaptive-proposal-1`, `player-model-1`, and
  `procgen-failure-1`. Serde structs deny unknown fields.
- `ProcgenRequest` fields are: `schema_version`, `world_seed: u64`, `site`
  (`site_id`, integer `x`/`y`, `archetype_id`, `kit_id`, optional
  `intactness_override_bp`, optional existing `CauseOfLoss`, and
  `loot_richness_bp`), `difficulty_id`, `player_model` (`schema_version` plus
  ordered integer signals), ordered `requested_domains` (`world`, `site`,
  `gameplay`, `presentation`), `generator_version`, 64-lowercase-hex
  `content_manifest_hash`, and `presentation` (`seed: u64`, `locale`).
- Request validation requires exact schema/generator, nonempty site/archetype/
  kit/difficulty, `intactness_override_bp <= 10000`,
  `loot_richness_bp <= 30000`, exact player schema, nonempty domains, and a
  lowercase SHA-256 content hash. Task 12 adds tighter player-signal caps.
- `ProcgenBundle` fields are: `schema_version`, `version`, the normalized
  `request`, non-optional `world_ir`, `site_ir`, `gameplay_ir`,
  `presentation_ir`, `semantic_hash`, `metrics`, and `trace`. `WorldIR` carries
  the requested world/site identity in v1. `SiteIR` carries the authoritative
  `Ship`. `GameplayIR` carries the legacy gameplay-slice JSON derived from that
  same ship. `PresentationIR` carries kit, locale, presentation seed, and an
  ordered approved-binding map ready for later domains.
- `VersionEnvelope` contains generator version, content-manifest hash, and all
  eight exact `ExportSchemas` from Task 1. Add a `v1()` constructor rather than
  duplicating schema strings.
- `GenerationTrace` contains ordered named RNG channels, candidate decisions,
  failed constraints, repairs, retries, optional fallback, and stage timings.
  Instrument successful/rejected topology-template attempts and damage retries
  in the existing timed pipeline so trace data is truthful; do not perturb RNG
  consumption or generated `Ship` bytes. No fallback/repair is recorded unless
  one actually occurred.
- `GenerationMetrics` records pipeline executions (exactly one), room/entity/
  structural placement counts, and diagnostic stage timings. Timings are never
  semantic input.
- `AdaptiveProposal` is constrained data with schema, signed integer score,
  ordered rationale codes, confidence basis points, rule/model version, and an
  action enum limited to no-op, select an already-identified candidate, or
  adjust an identified encounter by a signed pacing delta. Task 12 implements
  selection policy.
- Failures use serializable `ProcgenFailure {schema_version, code, stage,
  message, retryable, fallback_id}` and a stable snake-case code enum covering
  invalid request, unsupported schema/domain, generator/content mismatch,
  generation/validation/fallback failure, adapter/manifest failure, capacity,
  overload, cancellation, timeout, and internal failure.
- `generate_bundle(request, data)` validates then invokes the existing timed
  ship pipeline exactly once. Migration layout/gameplay helpers accept the
  completed bundle and never regenerate. New bundle generation may keep the
  existing v2 seed behavior (`world_seed` feeds the ship pipeline); Task 6 owns
  the coordinate-key algorithm and its intentional generator-version decision.
- The semantic SHA-256 projection includes the mechanical request with
  presentation seed/locale removed, the version envelope, `WorldIR`, `SiteIR`,
  and `GameplayIR`. It excludes all `PresentationIR`, metrics, trace, timings,
  target paths, and locale. Canonicalization recursively sorts JSON object keys
  before hashing.
- Ship one JSON Schema file per manifest-listed public contract under
  `native/worldgen/schemas/`; shared `$defs` are allowed, but all required fields
  and `additionalProperties: false` must agree with Rust validation.

### Task 3: Gate 1 bounded native lifecycle and GDExtension surface

- Replace thread-per-request with a fixed bounded worker pool, bounded queue,
  bounded retained results, deterministic monotonic request ids, request/entity
  caps, cancellation, and time budgets.
- Expose native `generate_bundle`, `generate_bundle_async`, `poll`, `cancel`,
  `capabilities`, and `generator_manifest` with stable result codes.
- Tests first: saturation order, overload, cancel-before/start/done, timeout,
  unknown/consumed id, retained-result eviction, shutdown, and cap rejection.
- Owned files: native lifecycle/core queue and GDExtension adapter/tests. Preserve
  migration API names but route them through the single-pass bundle.

Task 3 lifecycle decisions (ADR-0060):

- Keep the core generator free of Godot values. Add target-neutral lifecycle,
  capabilities, and generator-manifest DTOs, then expose a UTF-8 JSON `GString`
  ABI: `generate_bundle(request_json)`, `generate_bundle_async(request_json)`,
  `poll(request_id)`, `cancel(request_id)`, `capabilities()`, and
  `generator_manifest()`.
- Lifecycle statuses are exactly `accepted`, `queued`, `running`,
  `cancel_requested`, `completed`, and `failed`. Completion contains exactly one
  bundle; failure contains exactly one `ProcgenFailure`. Extend stable failures
  with unknown request, consumed result, expired result, shutdown, and too-late
  cancellation codes; callers never parse messages for state. Each result also
  carries at most 32 ordered stable lifecycle-event codes covering rejection,
  admission, queue/start, cancel, timeout, completion, and failure without
  wall-clock values.
- One process-wide native service backs all `DerelictGenerator` instances;
  isolated test services inject limits, a monotonic clock, and a generator.
  Defaults are two workers, eight queued requests, sixteen retained terminal
  results, 64 KiB request JSON, 4,096 entities, 4,096 entries per bundle trace
  list, 32 lifecycle events, and 2,000 ms from admission through completion.
- Parse, validate, and cap before assigning a positive monotonic signed-64-bit
  request ID. Admission is serialized; when the queue is full, the later call
  returns overload without consuming an ID. Synchronous generation observes the
  same document/entity/deadline caps but does not enter the async queue.
- Queued cancellation immediately retains a cancellation failure. Running
  cancellation sets `cancel_requested`; generation may finish, but the output is
  discarded. Repeated cancellation is idempotent. Terminal cancellation returns
  too-late without consuming the terminal result.
- The deadline starts at admission. Pre-start and post-generation expiry both
  return timeout, and workers are never force-killed. Completion/failure is
  consumed exactly once by `poll`. Retention evicts the lowest accepted terminal
  ID; bounded tombstones classify recent consumed/expired IDs, and older admitted
  IDs deterministically decay to expired.
- Shutdown rejects admission, resolves queued work, wakes and joins all workers,
  and leaves no detached thread. Capabilities report schemas, domains, target,
  sync/async/cancel support, worker availability, and every effective limit.
- Generator manifest metadata is compiled from the checked source/content/schema
  identity plus target and dirty-development state. Artifact path/hash stay in
  the external build manifest to avoid a self-hash cycle.
- Legacy native generation/export methods remain migration APIs, but each routes
  through `generate_bundle` and bundle-only converters. Unit/GDExtension tests
  cover saturation order/recovery, queued/running/done cancellation, timeout,
  unknown/consumed/expired IDs, deterministic eviction, shutdown/join, caps,
  malformed JSON, bounded event sequences, six-method registration, shared
  service, and legacy routing.

### Task 4: Gate 1 WebAssembly adapter and adapter parity

- Add a WebAssembly package built from the same Rust core, with lifecycle
  semantics matching native. Where workers are unavailable, async polling may
  cooperatively complete without changing result semantics.
- Add adapter-neutral contract vectors and compare canonical semantic hashes.
- Add target capabilities and manifest reporting.
- Tests first: request/result vectors, unsupported capability, cancel/poll,
  manifest fields, and native/WASM semantic parity on representative cases.
- Owned files: new WASM crate/package/build scripts and adapter parity fixtures.
  Do not change domain algorithms.

### Task 5: Gate 1 Godot bundle consumer and explicit migration oracle

- Add typed Godot request/envelope/bundle consumer models. Validate manifest,
  schemas, result code, and semantic hash before scene assembly.
- Make the production `ShipGenerator` path call the unified bundle API once.
  Remove authoritative Godot-side biome, encounter, loot, and gameplay-slice
  decisions from that production branch.
- A legacy generator invocation must be explicitly migration-oracle mode and
  never selected due to a missing class or runtime error.
- Tests first: valid consumption, malformed/mismatched/unsupported bundle,
  missing adapter, explicit authored fallback, explicit oracle mode, and source
  assertions against silent fallback/post-generation mutation.
- Owned files: Godot procgen bridge/consumer and focused validation scripts.
  Reusable loader/presentation code remains.

### Task 6: Gate 2 coordinate-stable WorldIR

- Generate coordinate markers, routes, biome/hazard fields, archetypes,
  resource pressure, landmarks, and required extraction reachability.
- Derive named streams from the full stable key; optional domains, iteration,
  discovery order, and concurrency may not perturb existing results.
- Validate graph/site identities and provide bounded repair then complete
  authored fallback or fail closed.
- Tests first: golden coordinates, order/concurrency invariance, extraction,
  content/version isolation, optional-domain independence, and adversarial seeds.
- Owned files: Rust WorldIR domain/content/fallbacks/tests and schemas.

### Task 7: Gate 2 SiteIR mission compiler, validation, repair, and fallback

- Extend existing topology/structural compilation with mission graph,
  objective/extraction nodes, key-lock/repair ordering, functional prop sockets,
  traversal clearance, LOS/cover, and reachability annotations.
- Validate all layers together. Repairs are named, bounded, traced, and followed
  by full revalidation. Never export partial site data.
- Tests first: mission/lock-key/repair agents, socket/clearance/LOS properties,
  objective/extraction reachability, repair bounds, and validated fallbacks.
- Owned files: Rust SiteIR/compiler/domain validators/fallbacks/tests. Preserve
  the existing structural core and golden baselines unless versioned intentionally.

### Task 8: Gate 2 generated-world save identity and clean-break UX

- Persist world/site identity, generator/content/schema/semantic identity, and
  mutation deltas without duplicating generated authority.
- Compatible saves regenerate then apply validated deltas. Incompatible worlds
  are preserved and return a typed new-world requirement; profile/settings/
  accessibility remain portable and no file is silently deleted or rewritten.
- Tests first: compatible round trip, invalid delta target, every mismatch,
  preserved incompatible file, prompt state, and portable profile/settings.
- Owned files: Godot save/version compatibility models/UI seam and focused
  tests; Rust compatibility helper only if the envelope contract requires it.

### Task 9: Gate 3 encounter generation and replay

- Generate compositions/spawns from authored factions, roles, abilities,
  threat/economy budgets, occupancy, navigation, visibility, pacing, and bounded
  player snapshot.
- Trace candidates, constraints, scores, selection, and every spawn decision.
- Tests first: budgets, critical-path and visibility fairness, navigation,
  difficulty/threat monotonicity, cap/performance bounds, deterministic replay,
  combat simulation, and adversarial unfair-spawn search.
- Owned files: encounter content/domain/validators/simulation/tests and matching
  bundle fields; Godot only assembles exported instructions.

### Task 10: Gate 3 typed item generation and economy

- Generate items from authored families, typed sockets/affixes, stat budgets,
  rarity envelopes, drop-frequency/economy constraints, and visual tags.
- Reject invalid combinations and ensure text/presentation cannot control stats.
- Tests first: compatibility, budget/range, deterministic replay, loot-richness
  monotonicity, economy simulations, drop targets, and dominant-item search.
- Owned files: item content/domain/validators/economy simulation/tests and
  matching bundle fields.

### Task 11: Gate 3 creature, presentation, and provenance contracts

- Generate compatible creature blueprints from authored body/rig/animation/
  ability/behavior/material/footprint/counterplay definitions.
- Bind runtime presentation only to approved manifest IDs; add complete asset
  provenance schema/audit and deterministic Godot assembly.
- Tests first: compatibility matrix, traversal/footprint and performance bounds,
  invalid-combination search, deterministic replay, manifest binding, missing
  asset failure, and provenance completeness.
- Owned files: creature/presentation content/domain/tests, provenance tooling/
  records, and deterministic Godot assembly. No runtime asset generation.

### Task 12: Gate 4 deterministic adaptive proposal engine

- Implement classical utility scoring/search, bounded run-local player snapshot,
  validated-candidate ranker, and constrained encounter director.
- Record normalized inputs, candidates, scores, tie-break, action, rationale,
  version, confidence, and fallback so selection replays exactly.
- Tests first: golden scores/ties, candidate validity, authored envelopes,
  monotonicity/fairness/accessibility/performance, replay, and snapshot bounds.
- Optional embedded inference remains disabled and out of scope unless an
  evidence-backed follow-up is explicitly promoted; proposal/fallback seams may
  be tested with a fake invalid/timeout implementation.
- Owned files: adaptive Rust modules/content/tests and trace fields.

### Task 13: Gate 5 bounded diagnostics and promoted corpora

- Serialize local-only bounded diagnostic bundles with request identity,
  versions, hashes, summary traces/metrics/timings, and failure codes.
- Add source-controlled failure/approval corpus formats, deterministic replay,
  and promotion to authored fixture/fallback with provenance.
- Tests first: size/item caps, deterministic redaction/summary, personal-data
  field rejection, corpus freshness/replay, and promotion validation.
- Owned files: Rust/Godot diagnostic serializers, corpus data/tooling/tests.

### Task 14: Gate 5 in-Godot seed laboratory

- Build an actual in-engine tool showing world, mission, topology, navigation,
  encounter, item, and creature graphs plus metrics/validation failures.
- Support compare, parameter locks, selective regeneration, rejected candidates,
  repair explanation, named channels/rules, hashes/manifests, and promotion.
- Tests first for pure models/controllers, then clean headless scene smoke and
  RoboGodot/manual interaction evidence when the connector is available.
- Owned files: typed seed-lab models/controllers/resources/scenes and tests. No
  HTML, screenshots, or proof docs as a substitute for behavior.

### Task 15: Gate 6 all-entry-point cutover and request-scoped transport

- Switch travel, starting scene, top-down mode, saves, captures, and debug tools
  to `ProcgenBundle` and remove fixed temporary filenames in favor of in-memory
  documents or request-scoped paths.
- Register clean travel, bundle, and parity smokes in the canonical `run_clean`
  regression only after they emit no unexpected warning/error.
- Tests first: source/call-site inventory, concurrent path collision, each entry
  point, fallback/save reset, travel gameplay, and canonical warning policy.
- Owned files: production entry points/load transport and focused/canonical
  validation. Do not delete the migration oracle yet.

### Task 16: Gate 6 parity, scale, retirement decision, and acceptance synthesis

- Execute native Windows/macOS/Linux and Web semantic-hash parity; 10,000-case
  PR campaign; million-domain nightly campaign; metamorphic/adversarial/corpus/
  simulation suites; exports; full Godot; windowed performance; visual and
  representative gameplay review.
- Verify all release and per-stage/queue/entity/instance/navigation/build-size
  budgets with fresh evidence.
- Delete legacy generation only if every parity, fallback, save-reset, export,
  gameplay, warning/error, and evidence prerequisite is available and accepted.
  Otherwise preserve it as an explicit oracle and report Gate 6 blocked without
  weakening the production no-silent-fallback contract.
- Owned files: scale/parity/export/CI evidence and conditional legacy retirement;
  final docs/status updates. This task is an acceptance decision owned by the
  primary agent; a worker may only run bounded evidence collection.

## Test and acceptance plan

- Preserve the Rust baseline: all workspace tests and the 1,800-ship stress
  sweep remain green.
- PR gate: at least 10,000 deterministic composite cases spanning domains,
  versions, archetypes, difficulty bands, damage states, and platform adapters.
- Nightly gate: at least one million domain cases, metamorphic checks,
  adversarial seed search, promoted failure-corpus replay, and native/Web
  semantic-hash parity.
- Metamorphic requirements:
  - Difficulty cannot systematically reduce expected threat.
  - Loot richness cannot systematically reduce loot value.
  - Presentation-only seeds cannot alter topology or gameplay stats.
  - Locale cannot change mechanics.
  - Identical request/version/manifest produces an identical semantic hash.
- Automated simulation progresses from flood-fill/A* through objective and
  lock/key agents, encounter/combat simulation, economy runs, and adversarial
  searches for softlocks, excessive path stretch, unfair spawns, dominant
  items, invalid creatures, or performance spikes.
- Enforce existing release ceilings: procgen under 2 seconds, scene load under
  3 seconds, peak memory under 512 MB target/1 GB stop, and 60 fps target/30 fps
  stop. Add per-stage latency, queue, entity, instance, navigation, and
  build-size budgets.
- Require fresh Rust, Godot headless, platform export, Web, windowed
  performance, visual review, and representative gameplay evidence before each
  gate closes.

## Assumptions and verified starting baseline

- The platform remains a local installable Godot game with no hosted generation
  or live-service dependency.
- Current multiplayer work remains out of scope; deterministic identifiers and
  replayability remain multiplayer-forward.
- Terrestrial research topics such as hydrology and settlements are excluded
  unless later GDD requirements establish a game need.
- At plan approval, `D:\world_gen` had a healthy Rust test and 1,800-ship stress
  baseline, and its freshly built Windows DLL matched the checked-in addon.
- Godot validation in the prior planning session was unverified; this execution
  must produce fresh evidence on available toolchains and report unavailable
  platform gates explicitly.
