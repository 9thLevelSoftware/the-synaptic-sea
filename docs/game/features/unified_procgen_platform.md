# Feature: Unified Procedural-Generation Platform

## Status

Approved; Gates 0 through 4 are complete. Gate 5 is next. No later gate is
considered complete until its scoped card,
acceptance evidence, and regression evidence are current.

This specification is canonical for procedural generation. It supersedes the
GDScript-authority assumptions in
`docs/game/features/procedural_generation_expansion.md` and
`docs/game/features/remaining_procgen_play_stack.md`; their validated loader,
enclosure, walkability, and presentation work remains reusable evidence.

## Design pillar alignment

- Pillar: explore a hostile, legible sea of derelicts whose history can be read
  in its spaces, systems, inhabitants, and salvage.
- Pillar: make failure fair. A generated challenge must be explainable,
  replayable, and bounded by authored rules.
- Why this feature supports them: one deterministic platform composes the world,
  sites, missions, encounters, rewards, creatures, and presentation without
  allowing discovery order, platform, or an unconstrained model to rewrite the
  run.

## Player fantasy

The player charts a persistent Synaptic Sea where every coordinate has a stable
identity, boards derelicts that tell a coherent mechanical story, and adapts to
pressure that responds to the run without cheating or invalidating prior
knowledge.

## Gameplay problem

The current game has two materially different authorities. Windows may use the
Rust worldgen v2 extension, while other environments can silently use a
GDScript pipeline. The Godot bridge then adds biome, encounter, loot, and
gameplay mutations after Rust generation. Layout and gameplay are exported by
separate calls, asynchronous requests are unbounded threads, Web has no shared
core, and saves cannot prove which source/content/binary produced them. That
breaks replayability, platform parity, diagnosis, and safe evolution.

## Core behavior

One versioned operation consumes a `ProcgenRequest` and produces a complete
`ProcgenBundle`. The Rust core runs each requested domain once, validates it,
applies bounded local repair when allowed, revalidates, and otherwise returns an
authored safe fallback or an explicit failure. Godot validates the returned
version envelope and semantic hash, instantiates approved authored resources,
applies runtime consequences, and persists mutation deltas. It does not invent
authoritative encounters, rewards, biome mechanics, or topology after export.

The platform is local and offline. Desktop uses the same Rust core through
GDExtension; Web uses the same core compiled to WebAssembly. Every public output
has a deterministic semantic representation that excludes adapter and
presentation-only noise.

## Public contracts

All public contracts carry an export-schema version and reject unknown major
versions.

### `ProcgenRequest`

- world seed;
- stable site identity and integer coordinates;
- difficulty band;
- bounded, versioned player-model snapshot;
- requested domain bitset;
- generator version;
- content-manifest hash.

### `ProcgenBundle`

- `WorldIR`: coordinate-addressed markers, route graph, biome/hazard fields,
  resources, landmarks, extraction guarantees, and site archetypes;
- `SiteIR`: topology, structural plan, mission graph, locks/keys/repair gates,
  navigation, occupancy, clearance, LOS/cover, objectives, and prop sockets;
- `GameplayIR`: encounters, items, creature blueprints, budgets, and decision
  records;
- `PresentationIR`: approved asset identifiers, material/VFX/audio tags, and
  deterministic assembly instructions;
- semantic hash, metrics, generation trace, and version envelope.

### `GenerationTrace`

The bounded trace records named RNG channels, considered and rejected
candidates, failed constraints, repairs, retries, fallback use, per-stage
timings, and stable failure/rationale codes. Gate 4 advances this contract to
`generation-trace-4`, adding bounded adaptive decisions for the world ranker,
site ranker, and encounter director without mutating earlier trace versions.
It contains no personal data. See ADR-0066 and ADR-0067.

### `AdaptiveProposal`

The proposal records candidate score, rationale codes, confidence, rule or
model version, and only a permitted ranking or encounter action. A proposal is
never authoritative and cannot bypass domain validators or budgets.

## Rules

1. Rust is the sole production generation authority on native and Web. A
   missing, incompatible, overloaded, or failed adapter produces an explicit
   error or authored fallback; the legacy GDScript generator is never selected
   silently.
2. Stable generation keys include `(world_seed, generator_version,
   content_manifest_hash, coordinate/site_id, domain, named_channel)`. Discovery
   order and parallel scheduling may not alter output.
3. Every domain follows `generate -> validate -> bounded local repair ->
   revalidate -> authored-safe fallback/fail closed`. Disconnected or partially
   valid content is never exported.
4. Asynchronous APIs use a bounded queue, request and entity caps, cancellation,
   deterministic overload behavior, and per-request time budgets. No
   thread-per-request path remains.
5. The build manifest binds source commit, generator version, content-manifest
   hash, target, artifact hash, and export-schema versions. Startup and CI reject
   mismatches.
6. Mechanics come from authored identifiers, typed sockets/affixes, budgets,
   compatibility, and constraints. Unconstrained generated prose never controls
   stats or runtime behavior.
7. Presentation-only seeds and locale may change presentation, never topology or
   gameplay stats.
8. A deterministic classical ranker/director ships before any embedded model.
   Optional inference uses the same proposal interface and deterministic
   fallback, and is evidence-gated.
9. Pre-release saves store world/site identity, generator/content versions, and
   mutation deltas. Incompatible worlds show a clear new-world requirement;
   profile and settings data remain portable.
10. Source assets proposed by Blender or generative tooling remain offline.
    Runtime assembly uses only approved manifest entries with provenance.

## Domain behavior

### World and sites

World generation owns routes, fields, markers, landmarks, resource pressure,
site archetypes, and reachable extraction. Site generation extends the existing
Rust topology/compiler rather than replacing it. Mission graphs, key/lock and
repair ordering, functional prop sockets, traversal clearance, cover/LOS, and
objective reachability are validated together.

### Encounters

Encounter composition uses authored factions, roles, abilities, threat/economy
budgets, room occupancy, navigation, visibility, pacing, and the bounded player
snapshot. Every spawn and composition has a replayable decision record.

### Items

Items combine authored families, typed sockets/affixes, stat budgets, rarity
envelopes, economy constraints, drop-frequency targets, and visual tags. Values
outside the authored envelope fail validation.

### Creatures and presentation

Creature blueprints combine compatible authored body plans, rigs, animations,
abilities, behaviors, materials, footprints, and counterplay roles. Incompatible
or untraversable combinations are rejected. Presentation assembles approved
meshes, materials, animations, VFX, audio, and captions deterministically.

### Adaptive direction

The ranker selects only fully validated site/world candidates. The encounter
director adjusts composition and pacing only inside authored threat, economy,
fairness, accessibility, performance, and counterplay envelopes. Its inputs,
candidates, scores, selection, rationale, and fallback are traced.

## Inputs

- authored content manifest and safe fallbacks;
- versioned `ProcgenRequest`;
- immutable world/site identity;
- run-local bounded player signals;
- generator/build manifest and target capabilities;
- approved asset and provenance catalogues.

## Outputs

- one validated `ProcgenBundle` and semantic hash;
- deterministic scene assembly instructions;
- mutation-delta persistence identity;
- bounded metrics and diagnostic trace;
- explicit unsupported, overload, timeout, mismatch, validation, cancellation,
  or fallback result codes.

## Runtime APIs

Native and Web expose equivalent behavior for:

- `generate_bundle`
- `generate_bundle_async`
- `poll`
- `cancel`
- `capabilities`
- `generator_manifest`

Web may implement polling on the main thread when workers are unavailable, but
the request/result semantics and semantic hash remain identical.

## Authoring and observability

The in-Godot seed laboratory presents world, mission, topology, navigation,
encounter, item, and creature graphs with metrics and validation failures. It
supports seed comparison, locked parameters, selective regeneration, rejected
candidate inspection, repair explanation, named-channel tracing, semantic
hashes, version manifests, and promotion to source-controlled fixtures or
authored fallbacks. Diagnostic bundles are bounded and local-only.

Every promoted asset records source/license, tool or model version, inputs,
parameters/seed, human changes, technical validation, art approval, and the
promoted content-manifest entry.

## Non-goals

- Hosted generation, live-service dependencies, telemetry accounts, or network
  player profiles.
- Multiplayer implementation; deterministic identities remain
  multiplayer-forward only.
- Terrestrial hydrology, settlement simulation, or other research domains not
  required by the GDD.
- Runtime Blender, runtime generative media, or unconstrained generated text.
- An embedded model before the deterministic implementation passes production
  gates and demonstrates measurable benefit.
- Deleting the legacy migration oracle before Gate 6 parity, save-reset,
  fallback, export, and gameplay regression evidence is accepted.

## Technical design

- Rust workspace: `native/worldgen/`.
- Native adapter: Rust GDExtension under `native/worldgen/crates/worldgen-godot/`
  with checked artifacts under `addons/derelict/bin/`.
- Web adapter: Rust WebAssembly package generated from the same core.
- Godot consumer/assembly: `scripts/procgen/` and authored resource catalogues.
- Schemas and manifests: `native/worldgen/schemas/`, `data/procgen/`, and a
  checked build manifest consumed by Rust, Godot, export tooling, and CI.
- Seed laboratory: in-Godot tooling; RoboGodot is the preferred live-editor MCP
  when available, while headless CLI evidence remains canonical.
- Persistence: existing profile/settings files remain separate from generated
  world identity and mutation deltas.
- Version axes: Gate 2 platform/bundle generation is version 3 while the proven
  structural ship compiler remains version 2; public JSON seeds stay within the
  shared Rust/Godot/JavaScript exact-integer range. See ADR-0061.
- Save compatibility: a closed generated-world envelope regenerates then applies
  fully validated deltas; typed incompatibility preserves the original file and
  portable profile/settings data. See ADR-0062.
- Site mission contract: Gate 2 advances the site overlay independently while
  retaining platform v3 and structural ship v2; checked earlier schema files
  remain immutable. See ADR-0063.
- Gameplay/presentation contract: Gate 3 advances the typed player snapshot,
  request, gameplay, presentation, complete-bundle, and lifecycle schemas while
  retaining the validated platform-v3, structural-v2, WorldIR-v2, and SiteIR-v2
  layers. Its expanded named RNG-channel set advances independently to
  `generation-trace-3`; trace 2 remains immutable. See ADR-0064 through
  ADR-0066.
- Adaptive contract: Gate 4 advances the public bundle to `procgen-bundle-5`,
  gameplay to `gameplay-ir-3`, lifecycle to `procgen-lifecycle-result-5`,
  capabilities to `procgen-capabilities-4`, generator/build manifests to
  versions 4, and proposals to `adaptive-proposal-2`. The shipped rule version
  is `adaptive-classical-1`; no embedded inference model ships in Gate 4. See
  ADR-0067.

## Gate acceptance criteria

### Gate 0 — governance and source unification

- Canonical spec, `REQ-PG-*`, risks, validation plan, systems inventory, and
  ADR-0057..0063 agree.
- `D:\world_gen` history is imported under `native/worldgen/` without importing
  external untracked tooling state.
- Separate scoped board cards exist for Gates 0 through 6 with dependencies,
  allowed files, non-goals, and verification commands.
- A checked build manifest is generated and mismatches are rejected by focused
  tests and CI/startup consumers.

### Gate 1 — unified contracts and integration

- One pipeline run returns the complete versioned bundle and trace.
- Native and Web expose equivalent lifecycle APIs and capabilities.
- Async work is bounded, cancellable, capped, timed, and deterministic under
  overload.
- Godot validates and consumes the bundle without authoritative post-generation
  gameplay mutation; legacy generation is explicit migration tooling only.

### Gate 2 — world and ship generation

- Coordinate-addressed world/site outputs are invariant under discovery order
  and parallel scheduling.
- Mission, topology, locks/keys/repairs, sockets, navigation, clearance,
  LOS/cover, objectives, and extraction validate together.
- Failed content is repaired within bounded rules or replaced by a validated
  authored fallback; no partial export is possible.
- Save compatibility produces a clear new-world prompt while preserving
  profile/settings data.

### Gate 3 — gameplay domains and presentation

- Encounters, items, and creature blueprints obey authored compatibility,
  economy, fairness, traversal, and performance envelopes.
- Each selection has a replayable record.
- Runtime presentation references only approved manifest assets, and promoted
  assets have complete provenance.

### Gate 4 — deterministic adaptation

- Classical ranking/directing is deterministic, bounded, traceable, and cannot
  bypass validation.
- Player input is bounded, versioned, run-local, and offline.
- The shipped implementation is classical utility scoring only. No embedded
  inference experiment is present; any future model must use the same proposal
  interface and deterministic fallback and pass a separate promotion gate.

### Gate 5 — authoring and observability

- The seed lab exposes all specified graphs, comparison and lock controls,
  selective regeneration, rejected candidates, repairs, traces, hashes, and
  promotion flows.
- Failure seeds and approved candidates are source-controlled regression data.
- Diagnostic bundles are bounded, local-only, and contain no personal data.

### Gate 6 — cutover and retirement

- Windows, macOS, Linux, and Web produce the same semantic hash for identical
  request/manifest/version inputs.
- At least 10,000 composite PR cases and the nightly million-domain campaign,
  metamorphic checks, failure corpus, adversarial search, simulation layers, and
  platform parity gates pass.
- Travel, starting scene, top-down mode, saves, captures, and debug tools consume
  `ProcgenBundle`; request-scoped paths or in-memory documents replace fixed
  temporary names.
- The legacy GDScript generation authority is deleted only after all fallback,
  save-reset, export, visual, performance, and gameplay regression gates pass.

## Validation

Fresh evidence is required for every completion claim:

```text
cargo test --workspace
cargo run --release -p derelict_cli -- --stress
python tools/build_system_inventory.py --check
python scripts/validation/doc_currency_validators.py requirement-trace
<godot> --headless --path . --script res://scripts/validation/worldgen_wired_travel_smoke.gd
```

Gate-specific suites add contract/schema tests, queue/cancellation/overload tests,
native/Web semantic-hash parity, deterministic composite sweeps, metamorphic
checks, automated mission/combat/economy agents, adversarial failure-corpus
replay, platform exports, windowed performance, and visual/gameplay review.

Release ceilings remain generation under 2 seconds, scene load under 3 seconds,
peak memory under 512 MB target / 1 GB stop, and 60 fps target / 30 fps stop.
Per-stage latency, queue depth, entities, instances, navigation, and Web build
size receive explicit budgets before their gate closes.

Current Windows Gate 4 artifacts are bound to Rust source commit
`29720efecfc8b9dd3f6959870639061f43203b8f`, content-manifest SHA-256
`0923a378b923021172606f0c678383a5ca14c261e20b498369d3768b852e7385`, native
SHA-256 `f8d3aab1c4643749e38c1a9a3f0c75ab7d8a968e937c92534d4e35db119ebd87`,
and Web SHA-256
`ef8ff3861225c99ca0a2cdb190b4d4a27631b1d4f824c2e9c8fd12065d41c1f2`.
Rust formatting, strict Clippy, all 318 workspace tests, schema and manifest
checks, the 1,800-ship release stress sweep, and the Web lifecycle/parity smoke
pass. The exact Godot 4.7.2 Mono console in Downloads passes adaptive trace,
live consumer, mapper, fallback, build-manifest, wired-travel, and native
lifecycle smokes with no unexpected warnings or errors. Canonical Godot 4.7.1,
macOS/Linux exports, final exported-Web parity, windowed performance, and
RoboGodot/manual editor review remain later-gate evidence and are not verified.

## Risks

See `RISK-002` and `RISK-034` through `RISK-040` in
`docs/game/07_risk_register.md`.

## ADRs

- `docs/game/adr/0057-rust-authoritative-procgen-native-web.md`
- `docs/game/adr/0058-procgen-ir-versioning-save-fallback.md`
- `docs/game/adr/0059-deterministic-adaptive-proposals.md`
- `docs/game/adr/0060-deterministic-bounded-procgen-lifecycle.md`
- `docs/game/adr/0061-procgen-platform-structural-version-separation.md`
- `docs/game/adr/0062-generated-world-save-envelope-and-clean-break.md`
- `docs/game/adr/0063-site-mission-overlay-and-contract-versioning.md`
- `docs/game/adr/0064-authoritative-gameplay-blueprints-and-presentation-bindings.md`
- `docs/game/adr/0065-gate3-contract-wrapper-version-propagation.md`
- `docs/game/adr/0066-gate3-generation-trace-channel-versioning.md`
- `docs/game/adr/0067-gate4-adaptive-trace-and-wrapper-versioning.md`
