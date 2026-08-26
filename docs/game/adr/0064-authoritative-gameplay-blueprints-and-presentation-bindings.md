# ADR-0064: Version authoritative gameplay blueprints and presentation bindings

- **Status:** Accepted
- **Date:** 2026-08-26
- **Related:** ADR-0047, ADR-0052, ADR-0057, ADR-0058, ADR-0059,
  ADR-0061, ADR-0063; `docs/game/features/unified_procgen_platform.md`;
  REQ-PG-002, REQ-PG-007..009, REQ-PG-012; Gate 3 card `t_c01fdb84`

## Context

The Gate 2 bundle owns the world, structural ship, mission, navigation, and
functional sockets, but its `GameplayIR` still contains only the migration
gameplay slice and its `PresentationIR` contains an empty binding map. Current
Godot systems can inject encounter markers, roll rewards, synthesize threat
fallbacks, and choose placeholder visuals after generation. Those decisions
cannot participate in whole-bundle budgets, native/Web parity, trace replay, or
the site progression and occupancy validators.

The existing player snapshot is also an unbounded vector of unnamed integers.
It cannot safely drive encounter composition, and tightening its meaning under
`player-model-1` would mutate an already checked contract. The existing ship
compiler, WorldIR, and SiteIR remain valid and must not be relabelled merely
because later gameplay layers now consume them.

## Decision

1. Gate 3 advances the request to `procgen-request-2`, the player snapshot to
   `player-model-2`, `GameplayIR` to `gameplay-ir-2`, `PresentationIR` to
   `presentation-ir-2`, the complete bundle to `procgen-bundle-4`, and the
   lifecycle result to `procgen-lifecycle-result-4`. Task 7 owns
   `procgen-bundle-3`/lifecycle 3. Every earlier schema file remains immutable.
   `world-ir-2`, `site-ir-2`, `generation-trace-1`, and unchanged adapter
   schemas retain their identifiers.
2. The platform generator remains version 3 and the nested structural ship
   remains version 2. New authored gameplay and presentation catalogues change
   the content-manifest hash; the schema map and content identity provide the
   pre-release clean break without changing either stable algorithm axis.
3. `player-model-2` is a closed, bounded, run-local snapshot. It contains at
   most one value for each approved signal kind (combat mastery, damage
   pressure, resource pressure, and objective pace), canonically ordered, with
   every value in `0..=10_000` basis points. It contains no text, account ID,
   network history, or process-global state. An empty snapshot selects authored
   baseline values.
4. `gameplay-ir-2` retains the validated migration gameplay slice and adds
   closed encounter instructions, generated item blueprints and drop bindings,
   compatible creature blueprints, and typed decision records. A decision
   record contains a stable decision/channel ID, bounded candidate scores,
   rejection/rationale codes, and the selected candidate. Free-form text,
   filenames, locale, and presentation tags never define mechanics.
5. Creature blueprints are compiled before encounters. They combine only
   authored-compatible body plan, footprint, rig, animation set, ability,
   behavior, material, threat cost, and counterplay-role IDs. Footprints must
   fit the SiteIR clearance/occupancy envelope. An encounter may reference only
   a blueprint exported in the same GameplayIR.
6. Encounter instructions bind stable spawn IDs to existing SiteIR rooms and
   cells. Composition is constrained by authored faction/role/ability
   compatibility, difficulty-monotonic threat budgets, entity/performance caps,
   player-snapshot bounds, navigation, occupancy, functional-prop conflicts,
   clearance, cover/LOS, pacing, and economy. Entry, required objective, and
   extraction approach cells are never spawn cells; critical-path rooms are not
   spawn camps. A structurally valid site with no fair spawn may export zero
   encounters rather than violate fairness.
7. Items combine authored families, typed sockets and affixes, fixed-point stat
   budgets, rarity envelopes, drop-frequency targets, economy value, and a
   nonmechanical visual-binding tag. Drops bind to stable existing container or
   encounter reward IDs. Loot richness changes an authored budget/count
   envelope monotonically; it never lowers expected value for an identical
   request family. Existing structural-v2 `ItemStack` data remains migration
   evidence and is not reinterpreted as a generated affix blueprint.
8. `presentation-ir-2` emits deterministic assembly instructions containing
   only approved asset/material/rig/animation/VFX/audio/caption IDs. The
   authoritative presentation catalogue validates each ID against a promoted
   manifest entry and a complete provenance record: source/license, tool or
   model version, inputs, parameters/seed, human changes, technical validation,
   art approval, and promoted content entry. Scene paths are adapter bindings,
   not mechanics.
9. Gameplay and presentation choices derive directly from the full
   length-delimited request key and named channels. Generation consumes the
   already validated SiteIR once and cannot mutate its ship, mission,
   navigation, props, or spatial annotations. Locale and presentation seed may
   select approved cosmetic alternatives only and are excluded from mechanical
   selection and the semantic hash.
10. Each domain follows `generate -> validate -> bounded named repair -> full
    revalidate -> complete authored fallback/fail closed`. Domain fallbacks are
    complete typed records and remain inside the same validators and budgets.
    Godot instantiates the exported instructions and applies later runtime
    combat/inventory consequences; it does not reroll composition, rewards,
    blueprints, or fallback markers.

## Consequences

- Native and Web can replay the same encounter, reward, creature, and approved
  assembly decisions from one request and content identity.
- Existing Godot combat, inventory, AI, and visual binders remain reusable as
  runtime consequence/assembly systems, while their post-generation selection
  paths become migration-only and are retired at Gate 6.
- The typed player snapshot creates the bounded input required by the Gate 4
  director without granting it authority to bypass Gate 3 validators.
- Gate 3 intentionally refreshes request/bundle/lifecycle schemas, parity
  corpus, checked artifacts, content/build manifests, and save compatibility.

## Rejected alternatives

- Keep Godot encounter injection or empty-marker fallback in production:
  duplicates authority and prevents whole-bundle validation and parity.
- Add fields in place to GameplayIR v1, PresentationIR v1, or player-model v1:
  changes checked contract bytes under stable identifiers.
- Let asset paths, generated prose, or localized labels define stats or
  behavior: breaks manifest authority, locale invariance, and reviewability.
- Generate arbitrary creatures and test them only after scene instantiation:
  permits rig, footprint, navigation, and counterplay incompatibilities into
  the bundle.
- Force an encounter into every site: turns the presence target into a fairness
  bypass on small or fully critical-path layouts.

## Verification

- Closed DTO/schema round trips and prior/future substitution rejection for
  request 2, player model 2, GameplayIR 2, PresentationIR 2, bundle 4, and
  lifecycle 4.
- Encounter budget/fairness/navigation/visibility properties, deterministic
  combat simulation, and adversarial unfair-spawn search.
- Item compatibility/stat/economy/rarity/drop-frequency properties,
  loot-richness metamorphics, economy simulation, and dominant-item search.
- Creature compatibility matrices, footprint/traversal simulation, invalid
  blueprint search, and exact encounter-reference validation.
- Presentation manifest/provenance audits, deterministic assembly parity, and
  Godot consumer/runtime-binding smokes with no authoritative reroll path.
- Existing structural goldens/stress, Task 7 mission agents, native/Web corpus,
  semantic-hash metamorphics, and exact Godot warning/error gates remain green.
