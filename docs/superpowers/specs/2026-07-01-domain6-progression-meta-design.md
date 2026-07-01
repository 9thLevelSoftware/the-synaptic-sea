# Domain 6 — Progression & Meta — design spec

**Date:** 2026-07-01
**Status:** approved in brainstorming; pending written-spec review.
**Loop:** `progression` (currently 🟡 partial → target 🟢 closed).
**Roadmap:** `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` (Domain 6).

## Context

The `progression` loop's **inner half is live and closed** — earn XP → level skills → gate
scan/craft/repair. The **outer meta half is broken**: currency accrues with no sink, the skill
tree gates nothing, cross-run unlocks have no reader, and there is a live XP double-grant. Every
model needed already exists, is typed, and is unit-smoked; this domain is **wiring + two consumers +
one bridge + one bug fix**, not new systems.

### Verified current state (line-cited, `main` @ `b374c99`, 2026-07-01)

**Meta persistence already works and is independent of Domain 8 (Save).** `MetaProgressionState`
and `UnlockRegistry` each persist to their own `user://*.json` file, explicitly "independent of
RunSnapshot (ADR-0007 boundary)":
- `meta_progression_state.load_from_disk()` at boot (`playable_generated_ship.gd:1117`);
  `_apply_meta_payout_and_persist()` (`:6424`) accrues currency via `apply_meta_payout` (`:6439`) and
  `save_to_disk()` (`:6441`), called on slice completion (`:4868`).
- `unlock_registry.load_from_disk()` (`:1135`); at run-end `unlock_for_trigger(...)` + `save_to_disk()`
  (`:6448–6449`) from the training log.
- **Consequence:** the roadmap's D6↔D8 circular worry does not bind. Meta persistence needs no
  multi-slot save work.

**The currency source is live** but has **no sink**:
- `hub_upgrade_state.purchase()` (`hub_upgrade_state.gd:122`) is fully implemented (catalog + prereq +
  currency gates, with rollback) and has **zero callers**.
- `compose_starting_skill_bonuses` / `compose_xp_multipliers` are already applied at run-start
  (`playable_generated_ship.gd:1294` / `:1302`) — they just read an empty owned-set today.
- The `hub_upgrades` meta panel *renders* the catalog (owned/affordable/cost) but
  `MenuCoordinator.handle_ui_input` only **swallows** the accept/navigate keys while a meta screen is
  active (`menu_coordinator.gd:163–171`) — no input path calls `purchase()`.

**The skill tree gates nothing:**
- `skill_tree_state.unlock()` / `can_unlock()` (`skill_tree_state.gd:146` / `:114`) have **zero
  callers**, and **no gameplay reads `is_unlocked()`** (grep: only meta/achievement smokes).
- The tree's 11 nodes are the **advanced skills** (`welding_mastery`, `biomatter_diagnostics`,
  `surgery`, `pharmacology`, `astrogation`, `fabrication`, `construction`, `resource_management`,
  `leadership`, `intimidation`, `comms`) gated behind base-skill levels + optional books
  (`data/player/skill_tree.json`). Several already drive real gameplay once leveled — e.g.
  `fabrication` sets crafting quality (`crafting_station.gd:79`, `playable_generated_ship.gd:3183/3415`).
- `skill_tree_state` unlocks are **per-run** (`reset_unlocks()` each fresh run; the model comment:
  "the `unlocked` set is per-run; the catalogs persist"). The tree is therefore a **within-run
  specialization gate**, not cross-run meta — confirmed correct in brainstorming.

**The unlock registry has no reader:**
- `unlock_registry` is written at run-end and persisted, but nothing reads it back. The codex panel
  reads a *different* source, `tutorial_state.get_unlocked_codex_ids()` (`menu_coordinator.gd:640`).
- Catalog `data/player/unlock_tables.json`: **16 codex + 4 hub_scene + 3 class** entries.

**Class selection is a fixed default, not a player choice:**
- `@export var starting_class_id: String = "engineer"` (`playable_generated_ship.gd:173`);
  `_configure_player_progression` reads it at `:1277–1285`. `main.gd` boots straight into the playable
  ship — there is **no run-start menu or class picker**. `class_panel.gd` is read-only by design
  ("class selection happens at run-start in the run setup scene" — a scene that does not exist).
- `meta_progression_state.unlocked_class_ids` + `is_class_unlocked` + `unlock_class` exist but are
  never populated from gameplay, and class configuration never consults them.

**The XP ingest path has a live double-grant:**
- Objective completion grants `player_progression.grant_xp("repair", REPAIR_OBJECTIVE_XP)` (`:4831`,
  `REPAIR_OBJECTIVE_XP = 50` @ `:297`) **and** `training_event_bus.emit("repair_full_system", …)`
  (`:4835`). `repair_full_system` **is** in `data/player/training_actions.json` (+120), and
  `bus.emit()` itself calls `grant_xp` (`training_event_bus.gd:98–99`) → repair is granted **170 XP**
  (50 + 120) per objective.
- The kill path is already single-path via the bus: `emit_training_event("threat_killed", …)` (`:3612`)
  → `threat_killed` (+10 scavenging).

## Goal

Close the `progression` loop: give meta-currency a spendable sink, make skill-tree unlocks gate real
gameplay, surface cross-run unlocks in-game (records display **and** class-selection gate), and unify
the XP ingest path (removing the double-grant) — measured by the code-verified inventory flipping
`progression.closes → "closed"`.

## Global constraints

- **Validation is the definition of done** — no closure without fresh PASS-marker output.
- **Both `_process` branches** where a per-frame tick is added. Domain 6 is mostly *event-driven*
  (grants at kill/objective, payout at run-end), so its `_process` footprint is light; the smoke still
  carries an `away_ticks=` assertion (derelict kill → XP via bus; advanced-skill gate holds away).
- **Typed GDScript**; Resources are data, Nodes are behavior. The pure models stay pure — the gate
  and class hooks are injected (Callable / accessor), never a scene-tree reach from a model.
- Baseline noise allowlist unchanged; any other `ERROR:`/`WARNING:` blocks completion.
- Update `docs/game/06_validation_plan.md` with the new smoke(s) + markers.

## Decisions locked (from brainstorming)

1. **Skill-tree unlock = training gate.** Advanced skills cannot gain XP until their node is unlocked;
   unlocking requires the base-skill level (+ any book) already encoded in `skill_tree.json`. Reuses
   the existing skill effects; the tree is a **within-run** specialization gate (per-run, resets each
   run).
2. **Unlock-registry reader = Both.** A records/codex **display** of unlocked entries **and** a
   **class-selection gate** that reads the cross-run unlock set at run-start.
3. **Interaction model = keyboard-in-panel**, consistent with the existing menu shell. Meta screens
   gain a per-panel cursor; `ui_accept` calls the model action. No mouse controls, no new boot scene.

## Architecture

All work lands in two nodes plus one data bridge:

- **`MenuCoordinator`** (`scripts/ui/menu_coordinator.gd`) — turns the three render-only meta screens
  (`hub_upgrades`, `skill_tree`, `class`) interactive. Each panel gains a lightweight
  selected-index + `get_selected_id()` + `move_selection(dir)`; `handle_ui_input`'s meta-screen block
  (currently swallowing nav/accept at `:163–171`) routes `ui_up/down` to the cursor and `ui_accept` to
  the model action, then re-renders. The records/codex screen also renders `unlock_registry` entries.
- **`playable_generated_ship.gd`** — the two consumers + the bridge + the ingest fix: the training
  gate at the XP-grant boundary; `_configure_player_progression` reads the persisted
  `selected_class_id`; the run-end bridge that turns an `unlock_registry` class unlock into
  `meta_progression_state.unlock_class(id)`; removal of the direct repair `grant_xp`.
- **Pure models** — unchanged except additive: `MetaProgressionState` gains a persisted
  `selected_class_id` field; `TrainingEventBus` gains an optional injected **skill gate** callback
  (mirroring its existing `event_filter`) so XP for a locked advanced skill is dropped at grant time.

### Work items (mapped to the roadmap's 4 CLOSED criteria)

**WI-1 — Hub-upgrade purchase (criterion 1).**
`hub_upgrades` panel cursor; `ui_accept` → `hub_upgrade_state.purchase(sel, meta_progression_state)`;
on success `meta_progression_state.save_to_disk()` + re-render (currency/owned/affordable). `compose_*`
already applies at run-start and persistence already works ⇒ bonuses apply next run with no extra
wiring. Feedback line/caption on purchase result (ok / already-owned / insufficient / missing-prereq).

**WI-2 — Skill-tree unlock + training gate (criterion 2).**
`skill_tree` panel cursor; `ui_accept` → `skill_tree_state.can_unlock(sel, player_progression,
meta_progression_state)` then `unlock(sel)` + re-render. **Training gate:** the XP-grant boundary
consults `skill_tree_state` — an injected gate callback on `TrainingEventBus` (and the equivalent
guard on any direct advanced-skill grant) drops XP for an advanced skill whose node is not unlocked;
the ~11 base skills are ungated. Because base-skill prereqs are ungated, the loop is reachable: level a
base skill → unlock the advanced node → the advanced skill can now train and its effect (e.g.
`fabrication` → crafting quality) applies. Per-run (resets on fresh run).

**WI-3 — Unlock-registry records reader (criterion 3a).**
The records/codex screen renders `unlock_registry.get_entries_for_category()` for the unlocked
codex/scene/class entries (a pure reader), distinct from the tutorial-driven codex list.

**WI-4 — Class-selection gate (criterion 3b — the "Both" choice).**
`class` panel becomes interactive: classes not in `meta_progression_state.unlocked_class_ids` (except
the `engineer` starter) render as locked and are not selectable; `ui_accept` on an unlocked class
persists `meta_progression_state.selected_class_id` (new additive field) + `save_to_disk()`.
`_configure_player_progression` reads `selected_class_id` (falling back to the `engineer` export).
**Bridge:** when `unlock_registry` resolves a `class`-category unlock at run-end (`:6448`), also call
`meta_progression_state.unlock_class(class_id)` so the selectable set actually grows. Selection applies
at the **next run's** boot (there is no mid-run class swap).

**WI-5 — Single ingest path + double-grant fix (criterion 4).**
Remove the direct `grant_xp("repair", REPAIR_OBJECTIVE_XP)` at `:4831`; keep `bus.emit(
"repair_full_system", …)` as the single grant (repair objective → 120 once, not 170). Audit remaining
direct `grant_xp` sites (tool nodes) and route through the bus so the training log is the complete
ingest record that feeds `unlock_registry` at run-end.

## Away-branch checklist

Domain 6 is event-driven, not per-frame. The relevant guarantees, asserted with `away_ticks=`:
- The kill→XP path (`:3612`) and the training gate live at the grant boundary — inherently
  branch-agnostic; assert a derelict kill grants XP via the bus while `away_from_start = true`.
- The advanced-skill training gate holds while away (locked skill gains no XP on a derelict).
- Meta payout + persistence are at run-end (branch-agnostic) — assert unaffected.

## Validation

`progression_meta_smoke.gd` (pure-model + coordinator seams; register marker in `06_validation_plan.md`):
1. Purchase a hub upgrade → currency debited, owned set + persisted file updated, `compose_*` applies
   the bonus on a fresh `_configure_player_progression`.
2. Skill-tree: a locked advanced skill gains **no** XP through the bus; after `unlock()`, the same
   event grants XP and the effect (fabrication → crafting) engages.
3. Records reader surfaces an `unlock_registry` unlocked entry.
4. Class gate: a locked class is not selectable; selecting an unlocked class persists
   `selected_class_id`; a fresh run configures progression with it; the run-end bridge turns a
   class-category registry unlock into `meta_progression_state.unlock_class`.
5. Ingest path: a `restore_systems`/`stabilize_reactor` objective grants repair **120 once** (not 170).
6. Away assertion (`away_ticks=`): derelict kill grants XP via the bus; the advanced-skill gate holds.

## Inventory delta

`progression.closes → "closed"`; clear/redocument its break-points; flip `output.live` (with new
line-cited evidence) for `hub_upgrade_state` (purchase caller), `skill_tree_state` (unlock caller +
gate reader), `unlock_registry` (records reader + class bridge), and `training_event_bus` (single
ingest path). Regenerate `SYSTEM_INVENTORY.md` + `system_map.html`; `--check` + `--coverage` clean.

## Critical files

- `scripts/ui/menu_coordinator.gd` — interactive meta panels (cursor + accept routing), records reader.
- `scripts/ui/hub_upgrade_panel.gd`, `skill_tree_panel.gd`, `class_panel.gd`, `codex_panel.gd` —
  add selection index + `get_selected_id()`/`move_selection()`; class-locked rendering; registry list.
- `scripts/procgen/playable_generated_ship.gd` — training gate, `selected_class_id` config read,
  run-end class-unlock bridge, remove direct repair `grant_xp`.
- `scripts/systems/meta_progression_state.gd` — additive `selected_class_id` (persisted in
  `to_dict`/`apply_summary`).
- `scripts/systems/training_event_bus.gd` — optional injected skill-gate callback.
- `data/player/unlock_tables.json` — confirm the 3 class-category triggers fire a real class unlock.
- New: `scripts/validation/progression_meta_smoke.gd`; `docs/game/06_validation_plan.md`;
  `docs/game/inventory/system_inventory.json` (+ regenerated MD/HTML).

## Risks

- **`MenuCoordinator` input churn.** Routing accept/nav into per-panel cursors touches the shared
  meta-screen input block. Mitigate by keeping the cursor state per-panel and asserting each panel's
  selection + action through a headless seam; keep every existing menu/meta smoke green as a fence.
- **Training-gate hook location.** Enforcing at the bus boundary keeps models pure but must cover any
  direct advanced-skill `grant_xp` too — the WI-5 audit and the gate share the same call-site survey.
- **Class-gate scope.** Net-new interaction (no class picker exists today). Bounded by reusing the
  keyboard menu paradigm + the existing `class_panel` render, and by applying selection only at
  next-run boot (no mid-run swap).
- **Per-run vs cross-run tree.** Locked decision: tree is per-run. If a persistent cross-run tree is
  later desired, that is a separate, larger effort — not in this domain.
