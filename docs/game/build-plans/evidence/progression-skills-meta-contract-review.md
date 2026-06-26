# Task 08: Player Progression, Skills, Classes, Hub & Meta — Contract Review

## Source-backed review

This package extends, not replaces, the existing progression seam. The
table below maps each required new system to the existing files it
extends so the package stays backward-compatible with Phase 3 progression
(ADR-0010), the achievement unlock service (ADR-0030), and the
save/load contract (ADR-0007 / ADR-0031).

| Required new system | Existing seam reused | Extension surface |
|---|---|---|
| PlayerProgressionState expansion (skill books, cross-training) | `scripts/systems/player_progression_state.gd` (Phase 3 model, `grant_xp`, `apply_summary`) | Same class file, additive API: `grant_xp_from_book(book_id, books_state)`, `get_training_xp_preview(action_id)`. New `cross_training` dictionary carries the per-skill cross-training XP counters (kept inside the same `apply_summary` round-trip). |
| MetaProgressionState | None — meta state has been deferred (ADR-0002 / 0003) | New `scripts/systems/meta_progression_state.gd` as a separate RefCounted. Owns meta_currency, unlocked_hub_upgrade_ids, unlocked_class_ids, persistence to `user://meta_progression.json` (independent of RunSnapshot, per ADR-0007 boundary). |
| TrainingEventBus | `scripts/systems/sfx_event_router.gd` pattern + the existing `grant_xp` call sites in `playable_generated_ship.gd` | New `scripts/systems/training_event_bus.gd` as a deterministic event log. Every loop emits a typed event (`repair`, `combat`, `crafting`, `discovery`, `cross_training`, `book_read`). TrainingEventBus.resolve_xp(...) folds an event into a skill id via the catalog and forwards to PlayerProgressionState.grant_xp. |
| SkillTreeState | `PlayerProgressionState.skills` + `data/player/skills.json` | New `scripts/systems/skill_tree_state.gd`. Pure data model that loads `data/player/skill_books.json` and exposes per-skill `requirements` (prerequisite skills + required books), `unlock_status`, and `can_unlock(skill_id)`. Composes with `PlayerProgressionState` for level checks. |
| HubUpgradeState | None (deferred) | New `scripts/systems/hub_upgrade_state.gd` loads `data/player/hub_upgrades.json`. Each upgrade has a `cost`, `requires` list (other upgrades / meta_currency), and `effects` dict (XP multiplier, inventory cap, repair speed, etc.). `purchase(upgrade_id)` is gated on MetaProgressionState + prerequisites. |
| UnlockRegistry | `scripts/systems/achievement_state.gd::unlock` + `scripts/procgen/playable_generated_ship.gd::get_player_achievements` | New `scripts/systems/unlock_registry.gd`. Wraps AchievementState for cross-cutting unlocks (codex, codex entries, hub scenes). Same `unlock(id)` contract: idempotent, catalog-driven, returns false on unknown id. |

## Files to extend (not replace)

- `scripts/systems/player_progression_state.gd` — add cross-training
  counters + book-aware `grant_xp_from_book`.
- `scripts/procgen/playable_generated_ship.gd` — emit training events
  on repair / loot / cooking / scanner interactions; expose meta snapshot
  via the world save; run-end processing honors `meta_payout` per ADR.
- `scripts/systems/save_load_service.gd` — add `save_meta_snapshot`
  / `load_meta_snapshot` independent of RunSnapshot (per ADR-0007).
- `scripts/systems/world_snapshot.gd` — add `meta_progression_summary`
  field (carried alongside the home ship, but not inside RunSnapshot).
- `scripts/ui/` — add `skill_tree_panel.gd`, `class_panel.gd`,
  `hub_upgrade_panel.gd` reading from the new pure models.

## Files to author (new)

- `scripts/systems/meta_progression_state.gd`
- `scripts/systems/training_event_bus.gd`
- `scripts/systems/skill_tree_state.gd`
- `scripts/systems/hub_upgrade_state.gd`
- `scripts/systems/unlock_registry.gd`
- `data/player/skill_books.json`
- `data/player/hub_upgrades.json`
- `data/player/unlock_tables.json`
- `docs/game/features/player_progression.md`
- `docs/game/adr/0033-player-progression-meta-architecture.md`
- `docs/game/balance/progression_meta_tuning.md`
- `scripts/ui/skill_tree_panel.gd`
- `scripts/ui/class_panel.gd`
- `scripts/ui/hub_upgrade_panel.gd`
- 6 smokes listed in the package plan

## Existing ADR conflicts

- ADR-0002 / ADR-0003 defer hub/meta past Gate 2. This package
  resolves the deferral by introducing the hub/meta data model + UI in a
  way that satisfies ADR-0033 (this ADR). Cross-run persistence stays
  scoped to `meta_progression.json`; RunSnapshot remains current-run
  only (ADR-0007 preserved).
- ADR-0010 keeps player progression inside RunSnapshot. This package
  adds the `cross_training` sub-dictionary to `player_progression_summary`
  and the `meta_payout` to `world_summary` (NOT RunSnapshot).

## Stop conditions confirmed

- No existing file is replaced; every change is additive.
- Save/load contract (ADR-0007) boundary preserved: meta state lives in
  its own file.
- Existing `player_progression_state_smoke` still passes (no signature
  changes to the public `grant_xp` / `apply_summary` / `get_summary`).