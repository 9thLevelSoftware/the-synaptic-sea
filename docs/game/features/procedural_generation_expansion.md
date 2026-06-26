# Feature: Procedural Generation Expansion — Templates, Biomes, Difficulty & Encounter Injection

## Status

In progress for Gate 2 content-complete target. Implements the
Task 12 package plan:
`docs/game/build-plans/12-procedural-generation-expansion-e2e.md`.

## Requirement cross-reference

- REQ-PG-001..012 (proposed in `docs/game/05_requirements.md`).
- Source templates: `data/procgen/templates/{spine,bifurcated,stacked}.json`.
- Source blueprint: `scripts/procgen/ship_blueprint.gd`.
- Source pipeline: `scripts/procgen/ship_layout_generator.gd`.
- ADR: `docs/game/adr/0029-procedural-generation-expansion-architecture.md`.

## Design intent

Phase 1 procgen shipped three hand-authored topology templates
(`spine`, `bifurcated`, `stacked`/`Template C`) and one kit
(`ship_structural_v0`). Phase 1 gameplay slice works through those
seeds but offers no per-room role variation, no biome flavour, no
difficulty curve, and no encounter markers for combat.

This feature extends the procgen pipeline so every generated ship
is a **seed-deterministic** composition of:

1. **At least six template variants** (the three existing + three
   new — `stacked_v2`, `compact`, `dispersed`, `derelict_a`,
   `derelict_b`). Six total because the package acceptance criterion
   is "at least six templates/variants deterministic by seed" — the
   three existing plus three new makes five; `derelict_a` /
   `derelict_b` add two more to give six and prove the system
   generalises to derelict mode.
2. **Room variant selection** per role: every room gets a
   `variant` string (e.g. `airlock:standard`, `airlock:bio_seal`,
   `corridor:narrow`, `corridor:wide`, `cargo:hold`,
   `cargo:refrigerated`) drawn deterministically from a per-role
   variant list seeded by the blueprint.
3. **Biome profile**: each ship carries a biome id
   (`abyssal_sargasso`, `breach_field`, `dead_fleet`). Biome
   modifiers scale hazard density, loot quality, encounter density,
   and lighting ambience. Modifiers are stored as numeric floats in
   `[0.0, 2.0]`; composition with difficulty is multiplicative.
4. **Difficulty profile**: each ship carries a difficulty id
   (`standard`, `hardened`, `deep_dive`). Difficulty scales the same
   four dials the biome touches, with safe ranges documented in
   `docs/game/balance/procgen_expansion_tuning.md`.
5. **Encounter injection**: after layout is serialised, the
   `EncounterInjector` walks every non-critical room, rolls a
   deterministic encounter table from the biome + difficulty, and
   emits `encounter_spawn_markers` entries under the new
   `encounters` key. Combat subscribes to this list.
6. **Seed determinism contract**: a single helper hashes the full
   layout dict via FNV-1a 64-bit and proves two runs from the same
   `(seed, archetype, biome, difficulty)` produce byte-identical
   layout output.

## Topology variant set

The package ships these template JSON files:

- `spine` (existing) — linear submarine layout.
- `bifurcated` (existing) — branch-and-merge.
- `stacked` (existing / Template C) — two-deck vertical.
- `stacked_v2` (new) — three-deck vertical with an auxiliary deck
  between the two main decks.
- `compact` (new) — single-deck minimal freighter with very tight
  corridors; used as the LIFE_BOAT-adjacent small variant.
- `dispersed` (new) — single-deck "wide" layout where rooms spread
  out laterally rather than along a spine.
- `derelict_a` (new) — derelict dock + compartments with one
  biomatter blockage.
- `derelict_b` (new) — derelict dock + compartments + a sealed
  forward chamber with a high-value cache.

The `RoomGraphGenerator` and `TemplateSelector` are extended so the
selector picks from this 8-element list by seed. The legacy
`AVAILABLE_TEMPLATES` constant expands to keep the existing
`AVAILABLE_TEMPLATES = ["spine","bifurcated","stacked"]` smoke
contract; new variants are added behind an opt-in
`include_derelict` / `extended_templates` flag.

## Room variants

Each room role gets a per-biome variant list:

| Role | Standard variants | Derelict-only variants |
|---|---|---|
| airlock | standard, bio_seal, maintenance_hatch | broken_seal |
| corridor | narrow, wide, junction | collapsed, flooded |
| bridge | command, observation | dark_bridge |
| cargo | hold, refrigerated, secure | empty_hold |
| medical | triage, surgery | contaminated |
| crew_quarters | bunks, officer | derelict_bunks |
| engineering | reactor, life_support, propulsion | burned_out |
| maintenance | tool_storage, junction | sealed |
| reactor | primary, secondary | unstable |

The `RoomVariantSelector` rolls a variant from the role's list
using `RandomNumberGenerator` seeded by `blueprint.seed_value XOR
role_hash XOR room_index`. Same seed = same variant.

## Biome profile

Each biome JSON declares:

- `id`, `description`
- `hazard_modifier` (float, default 1.0)
- `loot_quality_modifier` (float, default 1.0)
- `encounter_density_modifier` (float, default 1.0)
- `ambient_color`, `ambient_intensity` (Godot Color values for the
  HUD/scanner detail layer)
- `hazard_overrides`: per-hazard-id multiplier applied after the
  base modifier
- `encounter_table`: id of the encounter placement table
- `loot_table_overrides`: per-role loot table id

Initial biome set:

- `abyssal_sargasso` — standard; deep-sea baseline.
- `breach_field` — many oxygen breaches; high hazard density; cold
  blue ambient.
- `dead_fleet` — many derelicts; high loot quality; warm orange
  ambient.

## Difficulty profile

- `standard` — all modifiers 1.0.
- `hardened` — hazard 1.4, loot 0.85, encounter 1.3.
- `deep_dive` — hazard 1.7, loot 1.1, encounter 1.6.

Difficulty and biome compose multiplicatively: final_modifier =
biome.modifier * difficulty.modifier, then clamped to `[0.0, 3.0]`
to prevent impossible seeds.

## Encounter injection

The injector walks every room in `layout["rooms"]`, skips rooms on
the critical path (the same critical-path BFS the layout serializer
already produces), and for each non-critical room rolls against the
biome's encounter table. Each spawn marker is:

```json
{
  "id": "enc_<room_id>_<index>",
  "room_id": "<room_id>",
  "deck": 0,
  "cell": [x, y],
  "encounter_kind": "biomatter_lurker",
  "count": 1,
  "difficulty_tier": "deep_dive",
  "seed_offset": 17
}
```

Combat subscribes to `layout["encounters"]` on scene load. Empty
encounter list is valid (Phase 1 ships with at least one encounter
per non-critical room on `deep_dive` difficulty, and zero on
`standard` difficulty unless the biome is `breach_field`).

## Seed determinism contract

The contract asserts:

- Running the full pipeline twice from the same
  `(seed, archetype, biome, difficulty)` produces layout dicts
  that are byte-equal under `JSON.stringify(layout, "  ")`.
- A FNV-1a 64-bit hash of the same stringified layout is stable
  across runs and equals the recorded golden hash for any seed
  with a recorded golden.

The smoke captures the hash from a fixed seed and re-derives it
on every run.

## Persistence

- The new `biome`, `difficulty`, `kit_id`, and `variants` per-room
  fields are written into `layout.json` and `gameplay_slice.json`.
- `RunSnapshot` does NOT need to track biome / difficulty (they
  are layout-time, not gameplay-time state).
- Encounter markers are loaded once at scene load and not
  persisted (the layout JSON they came from is what persists).

## Verification

Focused package smokes:

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
$GODOT --headless --path "$ROOT" --script res://scripts/validation/template_c_traversal_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/room_variant_selector_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/kit_catalog_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/biome_profile_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/difficulty_profile_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/encounter_injector_smoke.gd
$GODOT --headless --path "$ROOT" --script res://scripts/validation/seed_determinism_smoke.gd
```

Expected markers:

- `TEMPLATE C TRAVERSAL PASS`
- `ROOM VARIANT SELECTOR PASS`
- `KIT CATALOG PASS`
- `BIOME PROFILE PASS`
- `DIFFICULTY PROFILE PASS`
- `ENCOUNTER INJECTOR PASS`
- `SEED DETERMINISM PASS`

All seven are registered in `docs/game/06_validation_plan.md`
regression bundle.

## Non-goals

- New art assets beyond what `ship_structural_v0` already provides.
- Combat encounter runtime — the injector emits spawn markers; combat
  consumes them in a separate package.
- Hub/meta progression — deferred per ADR-0003.
- HUD/scanner UI rebuilds — only existing scanner data fields get
  additive `biome` / `difficulty` strings.
- Layout JSON schema migration tooling for the `1.1.0 -> 1.2.0` bump;
  older loaders ignore the new `encounters` key.
