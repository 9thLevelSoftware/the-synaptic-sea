# ADR-0029: Procedural Generation Expansion — Templates, Biomes, Difficulty & Encounter Injection

Date: 2026-06-25
Status: Accepted
Supersedes: none
Related: Task 12 package plan
`docs/game/build-plans/12-procedural-generation-expansion-e2e.md`;
features `docs/game/features/procedural_generation_expansion.md`;
contract review
`docs/game/build-plans/evidence/procedural-generation-expansion-contract-review.md`.

## Context

Phase 1 procgen ships three hand-authored topology templates
(`spine`, `bifurcated`, `stacked`) and one shared kit
(`ship_structural_v0`). Phase 1 gameplay works through those seeds
but offers:

- no per-room role variation (every `corridor` is identical
  regardless of seed),
- no biome flavour (no concept of `abyssal_sargasso` vs
  `breach_field` vs `dead_fleet`),
- no difficulty curve (every run is the same `Condition` scalar),
- no encounter markers for combat (combat has nowhere to spawn
  threats from in a seed-deterministic way).

The Task 12 package plan (`build-plans/12-procedural-generation-expansion-e2e.md`)
requires at least six templates, deterministic seed behaviour, biome
+ difficulty composition, and encounter injection that does not
break connectivity. This ADR decides how those pieces fit into the
existing pipeline without breaking any Phase 1 contract.

## Decision

Extend, do not replace. The pipeline gains seven pure-model classes
that sit *alongside* the existing five-stage
(`TemplateSelector → RoomAssigner → CellLayoutEngine → WallDoorResolver
→ LayoutSerializer`) chain and one adapter change at the top of the
chain (`ShipLayoutGenerator.generate(...)`).

### 1. RoomVariantSelector (pure RefCounted)

`scripts/procgen/room_variant_selector.gd` exposes:

```gdscript
func pick(role: String, room_index: int, seed_value: int, biome: String = "") -> String
```

Internally a per-role variant list plus a `RandomNumberGenerator`
seeded by `seed_value XOR role_hash XOR room_index`. Unknown role
returns `"standard"` deterministically. The selector is *advisory*;
it does not mutate room_plan state — `RoomAssigner` calls it after
role selection and writes the variant string into the room dict.

### 2. KitCatalog (pure RefCounted)

`scripts/procgen/kit_catalog.gd` exposes:

```gdscript
func configure(kits_dir: String = "res://data/kits/") -> int   # count loaded
func kits_for_role(role: String, biome: String = "") -> Array[String]
func module_id_for_role(kit_id: String, role: String) -> String
```

Loads every `*.json` under `data/kits/` at `configure()` time and
builds a `kit_id -> role -> module_list` map. Default kit is
`ship_structural_v0`. The structural placer accepts an optional
`kit_id` parameter; absent `kit_id` keeps the existing built-in
module list (zero risk to Phase 1 smokes).

### 3. TemplateCTraversal (pure RefCounted)

`scripts/procgen/template_c_traversal.gd` exposes:

```gdscript
func validate(layout: Dictionary) -> Dictionary
# returns {valid: bool, error_code: String, error_room: String}
```

Validates every `layout.vertical_connections` entry has both rooms
in `layout.rooms`, both decks match their room's deck, and both
endpoint cells are in their deck's cell set. Returns a stable
`error_code` (`missing_room` / `deck_mismatch` / `cell_missing`) so
smokes can pin the failure path.

### 4. BiomeProfile + DifficultyProfile (pure data + composition)

`scripts/procgen/biome_profile.gd` and
`scripts/procgen/difficulty_profile.gd` are pure data classes with
`from_dict(json) -> RefCounted` and `modifier(dial) -> float`
accessors. A free function:

```gdscript
static func combined_modifier(biome: RefCounted, difficulty: RefCounted, dial: String) -> float
```

returns `biome.modifier(dial) * difficulty.modifier(dial)`, clamped
to `[0.0, 3.0]`. The clamp is the single safety valve preventing
impossible seeds when biome × difficulty multiplies > 3.

### 5. EncounterInjector (pure RefCounted)

`scripts/procgen/encounter_injector.gd` exposes:

```gdscript
func inject(layout: Dictionary, biome: RefCounted, difficulty: RefCounted, seed_value: int) -> Dictionary
```

Walks every room, skips critical-path rooms (read from
`layout.critical_path` which `LayoutSerializer._build_critical_path`
already populates), rolls a deterministic encounter table per room
role, and appends `encounter_spawn_markers` to `layout.encounters`
in place. Each marker has the schema documented in
`docs/game/features/procedural_generation_expansion.md`.

### 6. SeedDeterminismContract (pure RefCounted + free functions)

`scripts/procgen/seed_determinism_contract.gd` exposes:

```gdscript
static func fnv1a_64(text: String) -> int
static func assert_layout_match(blueprint: RefCounted, archetype: Dictionary, biome: RefCounted, difficulty: RefCounted) -> Dictionary
# returns {match: bool, hash_a: int, hash_b: int}
```

FNV-1a 64-bit is a small deterministic hash with no engine
dependency; the smoke asserts that two runs from the same inputs
produce identical stringified layout JSON and the same hash.

### 7. Layout JSON schema bump

`scripts/procgen/layout_serializer.gd` writes
`schema_version: "1.2.0"` (was `1.1.0`) and a new top-level key
`encounters: Array`. The bump is additive — older loaders ignore
the unknown key. No data is migrated or removed.

### 8. `ShipLayoutGenerator` adapter

`scripts/procgen/ship_layout_generator.gd::generate(...)` accepts
two new optional kwargs:

```gdscript
func generate(blueprint: RefCounted, archetype: Dictionary = {}, biome_id: String = "", difficulty_id: String = "") -> Dictionary
```

After Stage 5, it instantiates a BiomeProfile + DifficultyProfile
from the supplied ids, calls `EncounterInjector.inject(...)` on the
serialised layout, and returns the augmented dict. Default empty
ids fall back to `abyssal_sargasso` + `standard` so existing
callers see no behavioural change in their JSON output (the
`encounters` array is empty for `standard` biome+difficulty
combinations in `abyssal_sargasso`).

### 9. Template JSON files

Six+ topology templates live under `data/procgen/templates/`. The
existing three are unchanged. Five new files are added:

- `data/procgen/templates/stacked_v2.json` — three-deck vertical.
- `data/procgen/templates/compact.json` — tight single-deck.
- `data/procgen/templates/dispersed.json` — wide lateral layout.
- `data/procgen/templates/derelict_a.json` — derelict dock + compartments.
- `data/procgen/templates/derelict_b.json` — derelict dock + sealed cache.

The `TemplateSelector.AVAILABLE_TEMPLATES` constant is bumped from
3 → 8 ids; the existing `template_selector_smoke` continues to
test the existing 3 and the new ones are covered by the
`room_variant_selector_smoke` (which enumerates the registered set).

## Consequences

- Every existing Phase 1 smoke in
  `docs/game/06_validation_plan.md` continues to pass because
  `ShipLayoutGenerator.generate(blueprint, archetype)` (the
  signature Phase 1 callers use) ignores `biome_id` and
  `difficulty_id`. New kwargs default to `""` so legacy callers see
  the same output.
- `LayoutSerializer` schema bumps from `1.1.0` to `1.2.0`. Any
  external tool pinned to `1.1.0` will need a one-line bump; the
  bump is additive and the only new key is `encounters`.
- `RoomAssigner` accepts a new optional `variant_selector`
  parameter; missing selector keeps the existing behaviour
  (zero risk to existing smokes).
- `StructuralPlacer` accepts a new optional `kit_id` parameter;
  missing `kit_id` keeps the existing hardcoded `ROOM_MODULES`
  fallback.
- RunSnapshot is unchanged. Biome / difficulty / variants are
  layout-time state, recovered by re-running the seed through the
  pipeline — covered by REQ-PG-012.
- The smoke bundle grows by seven commands (one per new smoke).
  Total `commands=N` in the regression bundle is updated to reflect
  the new total.

## Risks

- A too-aggressive encounter multiplier could starve the
  critical path. Mitigation: EncounterInjector skips critical-path
  rooms by reading `layout.critical_path` (already populated by
  the serializer).
- FNV-1a 64-bit is non-cryptographic but stable across runs /
  platforms — adequate for a determinism fingerprint, not for
  security. No security use is intended.
- A schema bump from `1.1.0` to `1.2.0` could surprise external
  fixtures. Mitigation: the bump is additive; a smoke asserts
  older 1.1.0 layouts still load (the loader ignores the unknown
  `encounters` key).

## Stop / block conditions

- If a required Godot 4.6.2 feature (e.g. seeded RNG stability
  across versions) is unavailable, escalate with evidence; do not
  paper over with a non-deterministic stub.
