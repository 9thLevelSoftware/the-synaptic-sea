# Domain 8: Save / Persistence — Design Spec

**Date:** 2026-07-01
**Domain:** Completion roadmap Domain 8 (`save` loop, `closes: "partial"` → `"closed"`)
**Branch:** `feat/domain8-save-persistence` (off `main` @ e7e77c0, post-Domain-7)
**ADR:** ADR-0043 (written as part of this work)

## 1. Problem

The save subsystem's write half is live (autosave rotation, world.json via F5) but the read half
and the death-gate are dead code. All six inventory break-points verified TRUE against current
code:

1. **Multi-slot LOAD path unwired.** `load_from_slot` (`scripts/systems/save_load_service.gd:241`)
   has no live caller; slots are write-only. `SaveLoadMenu.select_slot_for_load`
   (`scripts/ui/save_load_menu.gd:21`) — the sole route to it — is never dispatched; the
   save/load meta screen renders rows into a read-only `RichTextLabel`
   (`menu_coordinator.gd:517-543`).
2. **Permadeath hollow.** `PermadeathResolver.record_death` (`permadeath_resolver.gd:37`) has no
   live caller; its consume gate (`load_from_slot:249`) is itself unreached.
3. **No boot-time resume.** `scripts/main.gd:9-19` boots straight into gameplay; no title screen
   exists anywhere. F9 (`request_load` → `load_world`) is the only load path, manual, in-session.
4. **Cloud manifest stub** — remains out of scope (documented deferral, unchanged).
5. **Quicksave guards unwired.** `AutosavePolicy.try_quicksave` (`autosave_policy.gd:86`) and
   `SaveLoadMenu.confirm_quicksave` have no callers.
6. **SaveLoadMenu dispatch dead.** `select_slot_for_load` / `confirm_save_to_slot` /
   `confirm_delete` have no live callers; only `refresh()` is used (display).

**Newly discovered pre-existing bug (fixed in this domain):** `_input` hard-returns when
`slice_complete` is true (`playable_generated_ship.gd:7548-7550`). After death the player cannot
open ANY menu. Domain 8 is the first feature that needs post-death menu access (epitaph
browsing), so the fix lands and is regression-guarded here.

## 2. User-locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Load surface | **Interactive slot screen** | Fully closes break-points 1 and 6; reuses the proven interactive meta-screen pattern |
| Boot resume | **Minimal title screen** (Continue / New Game / Quit) | Real seam; the roadmap's "continue entry" done properly |
| Permadeath | **Freeze, don't delete — including manual slots written this run** | True permadeath, no save-scumming; epitaphs stay browsable (ADR-0032 intent) |
| Quicksave | **Repurposed as Save & Exit** | Game is heading multiplayer (Project Zomboid-like); quicksave/quickload doesn't fit. Roadmap definition-of-closed #4 amended |
| Direction | Multiplayer / PZ-like future | Informs no-quicksave, permadeath severity, persistent-world framing |

## 3. Design

### 3.1 Title screen — new bootstrap wrapper; `main.tscn` UNCHANGED

`PlayableGeneratedShip` is a `_ready()`-driven coordinator that assumes it owns the session from
construction; retrofitting a pre-gameplay gate inside it would risk every one of the ~40 existing
main-scene smokes. Instead:

- **New** `scenes/title_main.tscn` + `scripts/title_main.gd` (root `Node`). `project.godot`
  `run/main_scene` flips to it — a **surgical one-line diff**; nothing else in `project.godot`
  moves, and no `.godot/` or `*.uid` churn is staged.
- `scripts/main.gd` / `scenes/main.tscn` stay byte-identical — every existing smoke preloads
  `res://scenes/main.tscn` explicitly and is unaffected.
- Title UI reuses the **existing `main_menu` catalog** in `data/ui/menu_definitions.json`
  (start / continue / settings / quit) with its own `MenuState` + `MenuPanel`
  (`scripts/ui/menu_panel.gd`) instances — never shared with `menu_coordinator`'s (enabled-state
  maps are per-instance; sharing would collide).
- **New pure model** `scripts/systems/title_save_query.gd` (`TitleSaveQuery`, RefCounted):
  `is_continue_available(service, resolver) -> bool` =
  `service.has_slot("world") and not resolver.has_died_in("world")`. No scene-tree access;
  headlessly smokeable.
- **New Game:** instantiate `scenes/main.tscn`, `add_child` — identical to today's boot. Free the
  title UI.
- **Continue:** same instantiation; poll `process_frame` until
  `playable_instance.playable_started` (the pattern every main-scene smoke uses), then call
  `request_load()` **verbatim** — the exact path the live F9 key already exercises
  (`_apply_world_snapshot` → `_apply_run_snapshot` → `_reset_runtime_for_reload`). No new apply
  path.
- **Quit:** `get_tree().quit()` — the game's first real process-exit path.
- **Gameplay → title:** new `signal return_to_title_requested` on `PlayableGeneratedShip`.
  Producers: Save & Exit (3.4) and the pause menu's `quit_main` item — currently a dead stub that
  reopens `main_menu` (`:4505-4507`) — rewired to emit it. `title_main.gd` handles it:
  `queue_free()` the gameplay instance, rebuild the title UI, re-run `TitleSaveQuery`.
  InputMap entries from `_ensure_key_action_set` are idempotent and safe to leave registered.

### 3.2 Interactive slot screen

Extend the proven `hub_upgrades`/`skill_tree`/`class` interactive meta-screen pattern
(`menu_coordinator.gd:174-183`, `:578-627`) to `"save_load"`:

- `ui_up`/`ui_down` → `meta_screen_move_selection`; `ui_accept` → `meta_screen_confirm()`.
- `ui_left`/`ui_right` cycles the selected row's **pending verb** among the verbs valid for its
  state:
  - Empty manual slot (`slot_01..06`): `[Save]`.
  - Filled manual slot: `[Load, Save (overwrite), Delete]`.
  - World row (exactly one, "World — <location>"): `[Load]` only — Save & Exit and autosave own
    writing it; deleting the only continue-path from in-game would be a footgun.
  - Autosave rows: display-only (autosaves feed the world-coherence model, never individually
    player-loadable).
  - Frozen rows: `DEAD — <epitaph>`, no verb.
- **Delete** is two-step: first `ui_accept` arms `_pending_delete_slot_id`; second `ui_accept` on
  the same row calls `confirm_delete(slot_id)`; any cursor/verb move clears the arm.
- **Save** dispatches `save_load_menu.confirm_save_to_slot(slot_id, snapshot_builder.call(),
  "manual", display_name)`. `bind_meta_screens` gains one parameter — `snapshot_builder:
  Callable` — and the coordinator passes `_build_run_snapshot`, so the menu never owns gameplay
  state.
- **Load** dispatches `save_load_menu.select_slot_for_load(slot_id)`; `meta_screen_confirm()`
  returns `{screen:"save_load", action:"load", ok:true, detail:slot_id, snapshot:<RunSnapshot>}`
  and the coordinator's `_input` dispatch site calls `apply_manual_slot(snapshot)` (3.3).
- Row rendering (`_refresh_save_load_panel`) gains the `> ` cursor prefix (mirrors
  `_refresh_menu_panel`) plus inline verb / armed-delete state.

### 3.3 Manual-slot load semantics (ADR-0031, implemented at last)

Manual slots are **ship-only side-saves**, per ADR-0031's original text: loading one restores the
active ship's `RunSnapshot` (27 summaries) and does **not** touch `visited_ships`, dock edges,
`world_time`, or `current_location`. New seam on `PlayableGeneratedShip`:

```gdscript
func apply_manual_slot(snapshot: RunSnapshot) -> bool:
    if snapshot == null:
        return false
    return _apply_run_snapshot(snapshot)
```

`parent_world_slot` on `RunSnapshot` stays reserved/unused (comment updated; ADR-0043 records why
full world-coherent slot pairing — compatibility schema, refusal UX, location-drift edge cases —
is out of scope). The slot-screen smoke asserts this directly: advance the world after saving,
load the slot back, objective progress reverts while `visited_ships`/dock state is untouched.

### 3.4 Permadeath — freeze, don't delete

`end_run` (`playable_generated_ship.gd:1604-1621`) branches on reason:

- `reason == "death"` → `_freeze_run_on_death()` — **nothing is deleted**:
  - `PermadeathResolver.record_death(slot_id, cause, epitaph, run_time, final_seq)` for: the
    active-autosave alias, `"world"`, every `AUTOSAVE_SLOT_IDS`, the quickslot if present, **and
    every manual slot written this run** (new run-local set
    `_manual_slots_written_this_run`, populated by the slot screen's Save action). Manual slots
    freeze too — user decision; a mid-run manual save must not be a permadeath escape hatch.
  - `world.json` stays on disk, frozen via its death record — the slot screen renders DEAD rows
    with epitaphs (ADR-0032's browse-the-epitaph intent, wired for the first time).
- Extraction/completion path **unchanged** (still deletes — a finished run has nothing to
  continue; that is not permadeath).
- `load_world()` gains the same gate `load_from_slot:249` already has:
  `has_died_in("world") → null`. Old saves have no `world.death.json`, so legacy loads are
  unaffected by construction.
- `_apply_meta_payout_and_persist(reason)` still runs on death — meta progression is cross-run
  and intentionally survives (recorded in ADR-0043 so nobody "fixes" it away).
- New Game after death does not touch frozen files; a "forget this death" action remains out of
  scope (ADR-0032 seam note).
- **Reclaim-on-write:** `save_world()`/`save_to_slot()` call `PermadeathResolver.clear_death(slot_id)`
  *after* the write to disk is confirmed successful (not before opening the file), so a failed write
  never unfreezes a still-DEAD payload (PR #57 Codex round 3 P2), while the next live run's
  successful system write still reclaims a previously-frozen slot instead of permanently bricking
  Continue/that autosave slot (final-review finding; see ADR-0043).
- **Freeze-set ownership (PR #57 Codex round 3 P1):** `_freeze_run_on_death()` only freezes the
  shared lineage (active-autosave alias, `"world"`, `AUTOSAVE_SLOT_IDS`, quickslot) when the
  run-local `_persisted_lineage_active` flag is true — set on a successful Continue/F9 load or this
  run's first successful world/autosave/manual-slot write — so a fresh New Game that dies before
  ever loading or saving cannot brick a different, still-live run's Continue. Manual slots
  (`_manual_slots_written_this_run`) are always frozen regardless, since that set is already
  write-tracked per run.
- **`_input` fix:** the `menu_coordinator` input dispatch moves ahead of the
  `slice_complete` early-return; only the gameplay-input tail stays gated. Death detection
  already ticks on both `_process` branches (`_tick_survival_attrition` at `:5254`/`:5330` →
  `_check_vitals_death` → `end_run("death")`), so no new away-branch wiring — but the freeze
  smoke drives death on **both** branches anyway (the historically-regressive pattern) and
  asserts the pause menu opens post-death in both.

### 3.5 Save & Exit

- New `save_and_exit` item in `pause_menu` (`data/ui/menu_definitions.json`) + new
  `signal save_and_exit_requested` on `menu_coordinator` + handler on the coordinator:
  `request_save()`; on success emit `return_to_title_requested`; on failure surface a toast and
  **do not exit** (never silently lose progress on a leave action).
- Deliberately does **not** reuse `AutosavePolicy.try_quicksave`'s cooldown — that guard exists
  to stop autosave thrashing during play; gating a terminal "I am leaving" save behind a cooldown
  that could skip the write is a correctness footgun. `try_quicksave`/`confirm_quicksave` stay
  dead-but-harmless (small, model-smoked, available if a real quicksave key ever ships).
- F5/F9 keep their current world save/load behavior, documented as dev/debug keys (comment-only
  touch at `DEFAULT_SAVE_RUN_BINDINGS`/`DEFAULT_LOAD_RUN_BINDINGS`, `:459-460`).

### 3.6 Migration / back-compat

- Title-Continue on a pre-Domain-8 `world.json`: `WorldSnapshot.from_dict` +
  `SaveMigrationService.migrate_world` already handle it; the only new read-time check is the
  permadeath gate, which defaults open for legacy saves.
- **Domain-7 follow-up, documented not engineered:** old `ShipInstance` summaries lack
  `breach_seeded`/`fire_seeded` (default `false` → benign re-seed on revisit), and variant-list
  additions shift `pick()` results, so pre-Domain-7 saves may re-roll room variants. Expected,
  cosmetic-only; recorded under "Known migration behavior" in ADR-0043
  (cross-ref `ship_instance.gd:213-214`).

### 3.7 Title settings sub-flow (user-added scope, 2026-07-02)

The title's Settings item is fully functional, not a dead `pass` arm (user decision during
execution — supersedes the earlier "optional" note). `title_main.gd` gains its own
`SettingsState` instance and mirrors `menu_coordinator`'s settings handling against the same
`settings_menu` catalog entry: confirm on `settings` → `menu_state.open_menu("settings_menu")`;
`ui_left`/`ui_right` (and `ui_accept` on non-back rows) → a title-local `_cycle_setting(direction)`
mirroring `menu_coordinator._cycle_setting` (`:339-360`), including preset cycling from
`accessibility_presets.json`; `back` → `close_top()`. Row rendering mirrors `_settings_line`
(`menu_coordinator.gd:707-717`) minus the difficulty-multiplier suffix (no `AccessibilitySettings`
exists at title).

**Persistence semantics:** settings persist only inside `RunSnapshot.settings_summary` (verified —
no standalone settings file exists). The title flow therefore hands its summary into the session:
`PlayableGeneratedShip` gains a production seam `apply_ui_settings_summary(summary)` (the existing
`apply_ui_settings_summary_for_validation` delegates to it), and `title_main.gd` calls it after
`playable_started` on BOTH New Game and Continue — but **only if the player changed a setting at
the title** (dirty flag), so an untouched title never clobbers a loaded run's saved settings.
A standalone `user://settings.json` layer is explicitly out of scope (future multiplayer card).

Validation: `title_settings_smoke.gd`, marker
`TITLE SETTINGS PASS open=true cycle=true back=true applied=true`.

## 4. Files

**New:** `scenes/title_main.tscn`, `scripts/title_main.gd`, `scripts/systems/title_save_query.gd`,
`docs/game/adr/0043-title-screen-permadeath-freeze-save-and-exit.md`, five smokes (§5).
(`scripts/ui/title_screen.gd` only if a separate Control proves cleaner than building the panel in
`title_main.gd`, matching `_build_meta_screens` style.)

**Modified:** `scripts/procgen/playable_generated_ship.gd` (end_run/freeze, `_input` fix,
`apply_manual_slot`, Save & Exit handler, `return_to_title_requested`, `bind_meta_screens` call,
written-slot tracking), `scripts/ui/menu_coordinator.gd` (save_load interactive arm, cursor
renderer, `save_and_exit_requested`, `quit_main` rewire), `scripts/systems/save_load_service.gd`
(`load_world` death-gate, freeze helper), `data/ui/menu_definitions.json`, `project.godot`
(run/main_scene line only), `scripts/systems/run_snapshot.gd` (comment only),
`docs/game/06_validation_plan.md`, `docs/game/inventory/system_inventory.json` (+ regenerated
outputs), `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` (definition-of-closed
#4 amendment), `CLAUDE.md` (run-the-game note: main scene is now `title_main.tscn`),
`scripts/validation/save_load_service_smoke.gd` (extended in place).

**Deleted:** `scripts/validation/main_playable_death_clears_autosave_smoke.gd` — its
`cleared=true` contract inverts under freeze-not-delete; replaced by `permadeath_freeze_smoke.gd`
(keeping a factually-wrong smoke would be dishonest).

## 5. Validation

| Smoke | Kind | Marker |
|---|---|---|
| `title_save_query_smoke.gd` | pure-model | `TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true` |
| `title_screen_flow_smoke.gd` | main-scene (boots `title_main.tscn`) | `TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true` — includes the teardown/reinstantiate double-boot check |
| `title_settings_smoke.gd` | main-scene (boots `title_main.tscn`) | `TITLE SETTINGS PASS open=true cycle=true back=true applied=true` — title settings sub-flow (§3.7) |
| `save_load_slot_screen_smoke.gd` | main-scene | `SAVE LOAD SLOT SCREEN PASS save=true load=true delete_armed=true delete_confirmed=true` — includes the ship-only-not-world assertion |
| `permadeath_freeze_smoke.gd` | main-scene | `PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true` — drives death on both away/home branches; asserts manual-slot freeze and post-death pause-menu access |
| `save_and_exit_smoke.gd` | main-scene | `SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true` |

Bundle math: 107 − 1 (deleted) + 6 (new) = **`commands=112`**. Final echo and per-smoke marker
entries updated in `06_validation_plan.md`.

**Save-dir hygiene (hard requirement):** every new smoke deletes ALL files it wrote —
`world.json`, every `*.death.json`, manifests, slot files — in **both** success and failure exit
paths (the existing `_cleanup_and_quit(code)` convention). A leaked `world.death.json` would
permanently disable Continue for a human running the game after tests.

**Inventory delta:** `save.closes → "closed"`; `permadeath_resolver` driven=true (driven_at
`end_run`); `save_load_menu`/`save_load_service` rows updated (dispatch methods live);
new `title_save_query` row; quicksave break-point reworded to "intentionally unwired — Save & Exit
uses request_save directly (ADR-0043)"; cloud manifest stays a documented deferral.
`python tools/build_system_inventory.py --check` must pass. Full regression bundle must end
`SYNAPTIC_SEA REGRESSION PASS commands=112 clean_output=true`.

## 6. Risks

1. **`_input` guard change** — highest blast radius (every input-path smoke). Full-bundle check
   immediately after that task, not just at branch end.
2. **Live scene teardown** — nothing frees `PlayableGeneratedShip` mid-process today. The title
   flow smoke frees and re-instantiates in one process, asserting a clean second boot and no new
   ERROR/WARNING lines beyond the allowlist.
3. **Save-dir pollution** — per-smoke unconditional cleanup (§5).
4. **project.godot** — one-line diff; never stage `.godot/` or `*.uid` churn.
