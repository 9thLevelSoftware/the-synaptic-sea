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

