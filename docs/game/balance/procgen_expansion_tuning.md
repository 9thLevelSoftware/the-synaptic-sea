# Procedural Generation Expansion — Balance and Tuning Notes

Tuning ranges, safe values, and difficulty composition rules for the
seven pure-model classes added in Task 12 (REQ-PG-001..012). All
multipliers are multiplicative when biome and difficulty compose;
the `combined_modifier()` clamp at `[0.0, 3.0]` is the single safety
valve (see RISK-012).

## Biome modifiers

The three shipped biomes (defined under `data/procgen/biomes/`):

| id | hazard | loot quality | encounter density | ambient intensity |
|---|---|---|---|---|
| abyssal_sargasso | 1.0 | 1.0 | 1.0 | 1.0 |
| breach_field | 1.4 | 1.1 | 1.3 | 0.85 |
| dead_fleet | 1.1 | 1.4 | 0.8 | 1.1 |

`breach_field` has hazard overrides for individual hazard ids:
`oxygen_breach: 1.6`, `electrical_arc: 1.2`, `fire: 1.0`. The
multiplier is applied AFTER the base hazard_modifier, so the
effective oxygen-breach density for breach_field is
`1.4 × 1.6 = 2.24`.

`dead_fleet` overrides loot tables for `compartment` and `quarters`
roles (the derelict-cache feel). Encounter density is dropped to
0.8 to make exploration less combat-heavy.

## Difficulty modifiers

| id | hazard | loot quality | encounter density |
|---|---|---|---|
| standard | 1.0 | 1.0 | 1.0 |
| hardened | 1.4 | 0.85 | 1.3 |
| deep_dive | 1.7 | 1.1 | 1.6 |

`hardened` trades loot quality for hazard pressure (0.85 ×) — a
player who survives harder content earns less. `deep_dive` keeps
loot quality baseline and pushes both hazard and encounter density
to the upper end of the safe range.

## Composition safety ranges

Final hazard multiplier = `biome.hazard_modifier × difficulty.hazard_modifier`.

- abyssal_sargasso × standard = **1.0**
- abyssal_sargasso × hardened = **1.4**
- abyssal_sargasso × deep_dive = **1.7**
- breach_field × standard = **1.4**
- breach_field × hardened = **1.96** (safe, under 3.0)
- breach_field × deep_dive = **2.38** (safe, under 3.0; upper edge)
- dead_fleet × standard = **1.1**
- dead_fleet × hardened = **1.54**
- dead_fleet × deep_dive = **1.87**

Final encounter density = `biome.encounter_density_modifier × difficulty.encounter_density_modifier`, clamped to `[0.0, 1.0]` inside the EncounterInjector. The most extreme combinations (`breach_field × deep_dive = 2.08`) clamp to 1.0, so the injector still rolls but never above 100% per room.

## Encounter density model

`EncounterInjector.inject()` walks every non-critical room, computes:

```
p_final = clamp(base_probability[role] × combined_density, 0.0, 1.0)
```

`base_probability[role]` per room role (defined in
`scripts/procgen/encounter_injector.gd::ENCOUNTER_BASE_PROBABILITY`):

| role | base | | role | base |
|---|---|---|---|---|
| airlock | 0.10 | | corridor | 0.20 |
| bridge | 0.15 | | cargo | 0.25 |
| medical | 0.20 | | crew_quarters | 0.20 |
| engineering | 0.30 | | maintenance | 0.35 |
| reactor | 0.40 | | ramp / elevator | 0.05 |
| hub / dock | 0.10 | | compartment | 0.30 |
| bay / hangar | 0.20-0.25 | | storage | 0.20 |

For a `breach_field × deep_dive` ship (combined_density clamped to 1.0),
cargo rooms fire 25%, engineering 30%, maintenance 35%, reactor 40%.
For a `standard × abyssal_sargasso` ship (combined_density 1.0), the
same numbers apply — but in practice the encounter_injector_smoke
verifies that a 10-room layout with all-cargo roles fires >= 1
marker in the deep_dive+breach_field combination.

## Room variant count targets

Each common role has at least 4 variants in
`scripts/procgen/room_variant_selector.gd::VARIANTS_BY_ROLE`. The
selector rolls a variant per room using `seed_value XOR role_hash XOR
room_index` as the RNG seed. The same (role, room_index, seed) always
returns the same variant.

`corridor` carries 7 variants (`standard`, `narrow`, `wide`, `junction`,
`flooded`, `collapsed`, `biomatter_crusted`) — the highest variant
count. The higher count gives corridor rooms a meaningful dressing
delta even when the layout and biome are identical.

## Kit affinity

`KitCatalog.kits_for_role(role, biome)` consults the biome_preference
map in each kit JSON. The shipped kits declare:

| kit | abyssal_sargasso | breach_field | dead_fleet |
|---|---|---|---|
| ship_structural_v0 | default | default | default |
| ship_structural_hazard | 0.4 | 0.9 | 0.3 |
| ship_structural_industrial | 0.4 | 0.3 | 0.9 |

`breach_field` selects the hazard kit by 0.9 affinity; `dead_fleet`
selects the industrial kit by 0.9 affinity. `abyssal_sargasso`
defaults to the legacy kit (no kit exceeds 0.4).

## Determinism contract

`SeedDeterminismContract.assert_layout_match()` runs the full
procgen pipeline twice for the same inputs and asserts byte-equal
JSON output and equal FNV-1a 64-bit hashes. The FNV-1a constants
are written as signed-decimal int64 (because GDScript's hex literal
parser rejects values > INT64_MAX). The implementation performs
the unsigned 64-bit multiply via a 32-bit-split trick that produces
the canonical FNV-1a 64-bit value of "hello" exactly
(`-6615550055289275125` as signed int64; canonical unsigned
`0xa430d84680aab8ca`).

## Persistence rules

Biome, difficulty, kit_id, and per-room variant are layout-time
state. They are NOT saved in `RunSnapshot`; on save/load the
generator re-runs from the saved seed and the same biome / difficulty
/ variant selection re-emits (covered by REQ-PG-008 + REQ-PG-012).

## Adding a new biome or difficulty

To add a new biome:

1. Author `data/procgen/biomes/<id>.json` matching the schema
   documented in `docs/game/features/procedural_generation_expansion.md`.
2. The biome loads automatically on the next pipeline run (no code
   change required for the loader).
3. Update this balance note with the new id's multipliers and any
   role overrides.
4. Update the smoke `biome_profile_smoke.gd` to add the new id to
   the round-trip / determinism cases.

To add a new difficulty:

1. Author `data/procgen/difficulty/<id>.json`.
2. Update the built-in fallback in `_resolve_difficulty()` and in
   `SeedDeterminismContract._default_difficulty()` if the smoke
   needs the new preset.
3. Update this balance note.

## Tuning experiments

When re-tuning multipliers, prefer changing a single dial at a time
and re-running the focused smokes (`biome_profile_smoke`,
`difficulty_profile_smoke`, `encounter_injector_smoke`,
`seed_determinism_smoke`) before re-running the regression bundle.
A change that breaks any of the four will surface in those focused
runs first.

Critical-path safety: `EncounterInjector` never spawns on rooms
listed in `layout.critical_path`. `TemplateCTraversal.validate()`
confirms the critical path itself stays intact (every room on the
critical path is reachable from the entry room via `room_links`).
Tuning multiplier changes that increase encounter density past 1.0
are auto-clamped; tuning changes that add new roles to
`ENCOUNTER_BASE_PROBABILITY` must include smoke evidence that the
new role's base probability + worst-case combined density still
leaves the critical path encounter-free.
