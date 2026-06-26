# ADR-0033: Player Progression Meta-Architecture

Date: 2026-06-25
Status: Accepted
Amends: ADR-0002 / ADR-0003 (hub/meta deferral — resolved), ADR-0007
(save/load service scope), ADR-0010 (player progression persistence)

## Context

ADR-0002 / ADR-0003 deferred hub/meta progression past Gate 1 and Gate
2 respectively, with the next anchor at Gate 3 entry planning. The
phase-3 progression (ADR-0010) added `PlayerProgressionState` to
`RunSnapshot` as current-run state. Task 08 now resolves the deferral
by introducing the meta layer the core loop (`02_core_loop.md`)
expects: meta-currency earned at run-end, hub upgrades that persist,
and class unlock expansion.

This ADR scopes the data model, persistence boundary, and the
additive-only change rule for existing save contracts.

## Decision

### Meta state lives outside RunSnapshot

`MetaProgressionState` is persisted to `user://meta_progression.json`
with schema `meta-progression-1`. ADR-0007's "no hub/meta in
RunSnapshot" rule is preserved: `RunSnapshot.player_progression_summary`
remains current-run state, and the meta state is a sibling file
read on boot, written on run-end.

### Add `meta_progression_summary` to `WorldSnapshot`

`WorldSnapshot` gains a `meta_progression_summary` field that carries
the meta snapshot alongside the world. This is world-scope (per
ADR-0012), not run-scope (ADR-0007), so the field is allowed.

### PlayerProgressionState extension is additive

`PlayerProgressionState` gains two new fields inside the existing
`get_summary` / `apply_summary` round-trip:

- `cross_training: Dictionary` — per-skill XP earned outside the
  primary category. Stored at the same level as `skill_xp`.
- `books_read: Dictionary` — `{ book_id: bool }` set. Schema-gated so
  older saves default to `{}` and the field is silently applied.

The public `grant_xp` API is unchanged; the new
`grant_xp_from_book(book_id)` consumes a book and grants a flat XP
bonus. `apply_summary` is forward-compatible: it tolerates the new
sub-keys.

### Training events are deterministic and pure

`TrainingEventBus` is a deterministic event log: every event has
`{event_id, target_id, timestamp}` and is resolved through
`data/player/training_actions.json` to a `(skill_id, base_xp)` pair.
The bus has no RNG; it processes events in emission order.

### Death rules

Death is end-of-run for the current run only. Meta state survives
death. `PlayableGeneratedShip.end_run(reason)` triggers
`apply_meta_payout` then clears the run snapshot.

## Consequences

- New persistent file `user://meta_progression.json`; a corrupted or
  missing file defaults to zeroed state and is rewritten on the next
  save.
- Save/load service smoke stays at `summaries=10` (no new RunSnapshot
  field added). World save smoke adds the meta field.
- `player_progression_summary` schema version bumps to
  `progression-2`; `apply_summary` on a `progression-1` summary
  accepts it and ignores the new sub-keys.

## Verification

- `scripts/validation/player_progression_full_smoke.gd` exercises the
  full data + cross-training + book + meta-payout surface.
- `scripts/validation/meta_snapshot_smoke.gd` round-trips
  `user://meta_progression.json` with version gating.
- `scripts/validation/skill_tree_panel_smoke.gd` proves the
  prerequisite + book unlock chain works end-to-end.

## Affected documents

- `docs/game/05_requirements.md` — REQ-PM-001..010 added.
- `docs/game/06_validation_plan.md` — six new smokes registered.
- `docs/game/07_risk_register.md` — Risk 0033 added (see ADR).
- `docs/game/features/player_progression.md` — feature spec.
- `docs/game/balance/progression_meta_tuning.md` — tuning notes.