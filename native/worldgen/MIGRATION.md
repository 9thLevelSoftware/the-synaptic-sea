# Migrating v1 → v2 (GENERATOR_VERSION 2)

v2 replaces the raster-first pipeline with authored topology and a canonical
structural plan. Same seed now produces a **different** ship than v1 — this
is a full cutover, not a compatible upgrade. The v1 state is tagged
`v1-final` in git.

## What breaks

- **Ships regenerate differently.** Any world that stored v1 site seeds will
  regenerate v2 ships at those sites. Golden hashes were re-baselined
  (`crates/derelict_core/tests/golden/hashes.txt`); the v1 hashes are archived
  at `tests/golden/v1_hashes.txt` for reference.
- **Mutation diffs degrade gracefully.** v1 `ShipMutationDiff` files address
  entity ids that no longer exist in v2 layouts. `apply_diff` skips unknown
  ids by design, so old saves load as pristine-ish ships instead of crashing.
- **`RoomType` is gone.** The role vocabulary is now `derelict_core::Role`
  (~21 roles matching The Synaptic Sea's vocabulary, with an alias table).
  Exported names changed: `medbay`→`medical`, `galley`→`mess_hall`,
  `hydroponics`→`life_support`.
- **Archetype RON schema changed.** Sizes are in 4 m module-grid cells;
  `required_rooms`/`optional_rooms`/`min_room_dim`/`corridor_loop_bp`/`shafts`
  were replaced by `template`, `role_weights`, `guaranteed_roles`,
  `max_duplicates`, `filler_roles`.

## What carried over unchanged

- The determinism contract: `rng::stream(seed, tag, sub)`, ordered
  collections, no floats in decisions, golden hashes, replay tests.
- `DeckLayer` (the 2D raster) — now produced by
  `structural::project::project_to_raster` instead of the generation stages,
  so the Godot 2D addon needed zero changes.
- The gdext bridge API (`generate`, `generate_async`, `poll_async`,
  `derive_site_seed`) plus new `export_layout_json` /
  `export_gameplay_slice_json`.
- JSON mutation-diff persistence and its co-op replication model.
