# Task 12: Procedural Generation Expansion — Contract Review

## Source-backed review

This package extends, not replaces, the existing procgen pipeline. The
following table maps each required new system to the existing seams it
reuses so the pipeline remains backward-compatible.

| Required new system | Existing seam reused | Extension surface |
|---|---|---|
| RoomVariantSelector | `scripts/procgen/room_assigner.gd::_pick_role` and `scripts/procgen/room_graph_generator.gd` weighted role selection | New `scripts/procgen/room_variant_selector.gd` consumed by `room_assigner.gd` after a thin adapter shim. Selector picks a variant string from a variant list per role using a seed-deterministic RNG. |
| KitCatalog | `data/kits/ship_structural_v0.json` + `scripts/procgen/structural_placer.gd::ROOM_MODULES` | New `scripts/procgen/kit_catalog.gd` that loads every `data/kits/*.json` file at `configure()` time, exposes `kits_for_role(role, biome)`, and the existing `StructuralPlacer` reads from `KitCatalog` via a `kit_id` lookup. |
| TemplateCTraversal | `data/procgen/templates/stacked.json` + `scripts/procgen/layout_serializer.gd::_build_vertical_connections` | New `scripts/procgen/template_c_traversal.gd` that takes a layout dict, picks every vertical transition (ramp + elevator) and validates each transition has both endpoints in the layout, the decks differ, and the cells are within their deck bounds. |
| BiomeProfile | `data/procgen/archetypes/derelict.json` archetype JSON | New `scripts/procgen/biome_profile.gd` + `data/procgen/biomes/*.json` files. `BiomeProfile` is a pure data class with a `modifier(hazard_id) -> float`, `loot_table(role) -> String`, `encounter_table(role) -> String` surface. |
| DifficultyProfile | `scripts/procgen/ship_blueprint.gd::Condition` | New `scripts/procgen/difficulty_profile.gd` + `data/procgen/difficulty/*.json` files. `DifficultyProfile` is a pure data class scaling hazard density, loot quality, and encounter frequency. Composes with `BiomeProfile` as `biome.modifier() * difficulty.modifier()`. |
| EncounterInjector | `scripts/procgen/layout_serializer.gd::fire_zones/arc_zones/breach_zones` arrays | New `scripts/procgen/encounter_injector.gd` that takes a layout + biome + difficulty, rolls a deterministic encounter table per room role, and emits a `encounter_spawn_markers` list inside the layout dict for the loader to spawn combat threat nodes from. |
| SeedDeterminismContract | `ShipBlueprint.seed_value` + every RNG consumer (`RoomAssigner`, `StructuralPlacer`, `TemplateSelector`) | New `scripts/procgen/seed_determinism_contract.gd` that hashes (FNV-1a 64-bit) the full layout dict twice via the same `serialize()` call and asserts equality; also runs the layout pipeline twice from the same blueprint+archetype+biome+difficulty and asserts byte-equal layout output. |

## Files to extend (not replace)

- `scripts/procgen/ship_layout_generator.gd` — accept an optional
  `biome` and `difficulty` parameter (default empty dict) and forward
  to `EncounterInjector` after layout serialisation.
- `scripts/procgen/room_assigner.gd` — accept an optional
  `room_variant_selector` and consult it after picking a role to
  attach a variant string.
- `scripts/procgen/structural_placer.gd` — read its per-role module
  list from `KitCatalog` if a `kit_id` was passed in.
- `scripts/procgen/layout_serializer.gd` — embed the
  `encounter_spawn_markers` array under a new `encounters` key
  alongside `fire_zones` / `arc_zones` / `breach_zones`.

## Files to author (new)

- `scripts/procgen/room_variant_selector.gd`
- `scripts/procgen/kit_catalog.gd`
- `scripts/procgen/template_c_traversal.gd`
- `scripts/procgen/biome_profile.gd`
- `scripts/procgen/difficulty_profile.gd`
- `scripts/procgen/encounter_injector.gd`
- `scripts/procgen/seed_determinism_contract.gd`
- `data/procgen/templates/stacked_v2.json`
- `data/procgen/templates/compact.json`
- `data/procgen/templates/dispersed.json`
- `data/procgen/templates/derelict_a.json`
- `data/procgen/templates/derelict_b.json`
- `data/procgen/biomes/abyssal_sargasso.json`
- `data/procgen/biomes/breach_field.json`
- `data/procgen/biomes/dead_fleet.json`
- `data/procgen/difficulty/standard.json`
- `data/procgen/difficulty/hardened.json`
- `data/procgen/difficulty/deep_dive.json`
- `data/procgen/encounter_tables/threat_drone_swarm.json`
- `data/procgen/encounter_tables/biomatter_lurker.json`
- `data/procgen/encounter_tables/derelict_pirate.json`
- `data/kits/ship_structural_hazard.json`
- `data/kits/ship_structural_industrial.json`
- `docs/game/features/procedural_generation_expansion.md`
- `docs/game/adr/0029-procedural-generation-expansion-architecture.md`
- `docs/game/balance/procgen_expansion_tuning.md`
- 7 smoke scripts under `scripts/validation/`

## Backward compatibility

- Every existing smoke in `docs/game/06_validation_plan.md` must still
  pass. The adapters pass empty defaults for `biome` / `difficulty` /
  `kit_id`, so legacy callers see no behavioural change.
- The `schema_version` for `layout.json` is bumped from `1.1.0` to
  `1.2.0`. The bump is additive: the only new key is `encounters`,
  an Array of spawn-marker dicts that older loaders can ignore.
- `RoomVariantSelector` writes a `variant` key into each room dict;
  older consumers that ignore unknown keys continue to work.
- `KitCatalog` falls back to `ship_structural_v0` if no `kit_id` is
  requested, preserving the exact module list the StructuralPlacer
  uses today.

## Stop / block conditions

None hit. No existing ADR contradicts this package.

## Out of scope

- New art assets beyond what the existing structural kit already
  provides.
- HUD/scanner UI rebuilds; only the existing scanner data fields get
  additive `biome` / `difficulty` strings.
- Combat encounter runtime — the injector emits spawn markers;
  combat consumes them in a separate ADR/scope.
