# ADR-0012: World persistence model & save-anywhere

Date: 2026-06-21
Status: Accepted
Supersedes: the Phase 4.5 away-save rejection (ADR-0011 consequence) — saving is
now allowed aboard a traveled derelict.
Extends: ADR-0007 (single-ship RunSnapshot scope).
Related: docs/superpowers/specs/2026-06-21-world-persistence-foundation-design.md

## Context

Travel materialized derelicts statelessly (regenerated from seed, freed on leave;
ADR-0011) and the save model held exactly one ship (RunSnapshot; ADR-0007). The
target session loop needs every visited ship to persist (multi-visit, parts-gated
repair) and saving to work anywhere (Project-Zomboid style).

## Decision

Introduce `WorldSnapshot` (RefCounted, pure data): wraps the `Synaptic SeaWorld`
summary, the home ship's unchanged `RunSnapshot`, a `visited_ships` registry of
per-derelict slices keyed by `marker_id`, the `current_location`, and the in-ship
player position. The coordinator keeps a live `visited_ships: Dictionary` of
`ShipInstance`s; only the active ship has a live `scene_root`. Derelict geometry is
regenerated deterministically from seed on revisit; mutable state rides the
`ShipInstance` summaries (regenerate-geometry / persist-state).

`request_save`/`request_load` operate on the whole `WorldSnapshot` through
`SaveLoadService.save_world`/`load_world` (single slot, `current_run.json`).
`RunSnapshot` gains no fields (ADR-0007 honored); it is embedded whole.

## Consequences

- Saving is allowed anywhere, including aboard a derelict; the Phase 4.5 away-save
  rejection is removed.
- Old single-ship saves are version-incompatible under the new `WorldSnapshot`
  slice version and are rejected on load → fresh run (pre-release; no migration).
- The home ship keeps detach-not-free travel behavior; only derelicts take the
  free-and-rebuild path. Full unification (home as just another registry entry) is
  deferred.
- The per-ship slice is an extensible summary-bag: sub-project #2 (objectives/
  hazards), #3 (inventory/loot), and #4 (repair loop) add fields without reshaping
  the world model.
- Out of scope: autosave, multiple/named save slots, save-file migration.
- The single save slot (`user://saves/current_run.json`) now holds a
  `WorldSnapshot` for ALL writes, including the objective-completion auto-save
  (`_auto_save_current_run` routes through `save_world`); the single-ship
  `RunSnapshot` on-disk format is superseded, and `req012_autosave_sequence_smoke`
  now reads the slot as a `WorldSnapshot` (its PASS marker is unchanged).
