# Feature: Player Progression, Skills, Classes, Hub & Meta-Progression

Source plan: `docs/game/build-plans/08-progression-skills-meta-e2e.md`
ADR: `docs/game/adr/0033-player-progression-meta-architecture.md`
Requirement range: REQ-PM-001..010

## Concept

Project Zomboid-influenced learn-by-doing progression translated to a
locked-isometric 3D space-horror survival aboard derelict ships trapped
in a biomatter Synaptic Sea field. The player picks a class (engineer, medic,
pilot, …) on a fresh run, gains XP from repair / combat / crafting /
discovery actions, levels skills, reads skill books/schematics to gain
bonus XP and unlock prerequisites in the skill tree, and unlocks
persistent meta-currency + hub upgrades across runs that affect the
hub ship and the next run's starting conditions.

## Mechanic surface

### Learn-by-doing XP

Every player action emits a typed `TrainingEvent` to the
`TrainingEventBus`. The bus resolves the event into a `(skill_id, xp)`
pair via the `data/player/training_actions.json` table and forwards
`grant_xp(skill_id, xp)` to `PlayerProgressionState`. The XP curve is
`(level + 1) * 100` to next level, capped at `MAX_SKILL_LEVEL = 10`,
class-multiplied per category (1.5x technical for engineer, 1.5x
medical for medic, etc.). The existing `PlayerProgressionState.grant_xp`
method is reused unchanged.

### Cross-training

A skill not in the player's primary category gains 50% of the XP it
would gain in its primary category ("cross-training penalty"). The
`PlayerProgressionState.cross_training` dictionary stores the per-skill
XP earned via cross-training so the player can see how much they've
diversified. This is the `cross_training_smoke` invariant.

### Skill books / schematics

A skill book is a one-shot consumable that adds a flat `book_xp` to the
target skill (default 200) and permanently marks the book's `book_id`
in the run's `books_read` set. Books that are also "schematics" unlock
a prerequisite skill (e.g. reading the "Advanced Welding" schematic
lets you put points into `welding_mastery`). Books are defined in
`data/player/skill_books.json`. They interact with `SkillTreeState`
which tracks per-skill prerequisites and per-book consumption.

### Skill tree

`SkillTreeState` builds a tree from `data/player/skills.json` plus
`data/player/skill_books.json`. Each skill has:

- `category` (technical / medical / navigation / survival / social)
- `display_name`
- `prerequisites`: array of `{skill_id, min_level}` pairs (pure
  player-progression prerequisites)
- `book_prerequisite`: optional `book_id` from the books table

The skill tree panel reads from `SkillTreeState`, the player's current
levels (`PlayerProgressionState`), and the books-read set. It exposes
`can_unlock(skill_id)` and `unlock(skill_id)`. For this package the
"unlock" is a UI signal that doesn't change skill levels — that
already happened via XP grant. The unlock records a marker in
`SkillTreeState.unlocked` so the panel can highlight branches.

### Classes

The class roster (Phase 3 / ADR-0010) is unchanged: 8 classes from
`data/player/classes.json`, each defining starting skills and per-
category XP multipliers. The new `class_panel.gd` displays the roster
and, on a fresh run, lets the player pick a class. Class selection
records the choice in the run snapshot (`player_progression_summary`
class_id field is reused) and seeds the new run's `PlayerProgressionState`.

### Meta progression

`MetaProgressionState` is a separate, persistent model that survives
across runs. It owns:

- `meta_currency` — earned at run-end from completed objectives,
  repair counts, discovery counts, and survival duration.
- `unlocked_class_ids` — class roster expansions (e.g. "salvage_captain"
  unlocks once the player has finished a run with `scavenging >= 5`).
- `unlocked_hub_upgrade_ids` — purchased hub upgrades that persist.
- `unlocked_codex_entry_ids` — codex entries that persist.

Persistence is via `user://meta_progression.json`, independent of the
run snapshot. The schema is `meta-progression-1` with explicit version
gating; older saves without the field default to a zeroed state.

### Hub upgrades

`HubUpgradeState` loads `data/player/hub_upgrades.json`. Each upgrade
has `cost`, `requires` (other upgrades or class unlocks), and
`effects` (a dict of multipliers or caps applied during gameplay).
`purchase(upgrade_id)` is gated on:

1. `MetaProgressionState.unlocked_hub_upgrade_ids` already has all
   `requires` upgrades
2. `meta_currency >= cost`
3. upgrade id is in the catalog (otherwise rejected as unknown)

On success the cost is deducted and the id is added to the meta
unlock set. The `hub_upgrade_panel.gd` UI is the player-facing surface.

### Run-end processing

When `PlayableGeneratedShip.run_complete` is set (or death rules
trigger; see below), `apply_meta_payout` walks the run summary and
emits meta currency: a fixed payout per completed objective plus a
bonus per high-level skill (`>= 5` adds +5 per skill, `>= 8` adds +15).
The run-end smoke (`player_progression_full_smoke`) asserts the
meta_payout is non-zero for a run that completes objectives.

### Death / run-end rules

Death does not wipe meta state (per ADR-0007 / 0033: meta is cross-
run). The run snapshot is wiped on death, the meta state persists,
and a fresh run starts from the meta state's class unlock set + hub
upgrades. Death triggers `end_run(reason="death")` on
`PlayableGeneratedShip`, which applies the meta payout then clears the
current-run state. The smoke verifies the meta state survives a
synthetic death event while the run snapshot is wiped.

## Out of scope

- Cosmetic customization tied to hub upgrades (handled by ADR-0033
  scope cuts).
- Faction reputation (separate deferred work, ADR-0003).
- Cross-class XP transfer on death (classes are locked per run).
- Per-run permadeath with full reset (death rules apply only to
  current-run state).

## Acceptance criteria

Mapped 1:1 to REQ-PM-001..010 in `docs/game/05_requirements.md`.

## Verification

Smokes registered in `docs/game/06_validation_plan.md` regression
bundle:

- `player_progression_full_smoke.gd` (PLAYER PROGRESSION FULL PASS)
- `cross_training_smoke.gd`
- `training_by_item_smoke.gd`
- `meta_progression_state_smoke.gd` (META PROGRESSION STATE PASS)
- `meta_snapshot_smoke.gd` (META SNAPSHOT PASS)
- `skill_tree_panel_smoke.gd` (SKILL TREE PANEL PASS)