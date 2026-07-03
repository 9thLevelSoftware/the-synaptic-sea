# ADR-0045: Tooltip gameplay triggers, minimap retirement, and item-based web charts

**Status:** Accepted
**Date:** 2026-07-02
**Supersedes:** the minimap half of ADR-0033 (`docs/game/adr/0033-ui-ux-accessibility-architecture.md`) — its `map_fog_state`/`minimap_panel` architecture is deleted outright, not extended.
**Roadmap source:** `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` Domain 10 (`tooltip`, `map_reveal` loops), redefined per user decision (see design spec `docs/superpowers/specs/2026-07-02-domain10-ui-polish-design.md`).

## Context

ADR-0033 built a complete tooltip render chain (`MenuCoordinator.set_tooltip_query`
→ `TooltipPresenter.resolve()` → `payload_changed` → `TooltipPanel`) and a
complete room-fog minimap (`MapFogState` → `MinimapPanel`), but both had
architectural gaps the system inventory's break-point audit surfaced:

- `set_tooltip_query` had **zero gameplay callers** — only two validation
  smokes drove it. No hover/focus concept existed anywhere in the codebase;
  interactables were Area3D proximity spheres consulted only on interact
  keypress, and inventory selection surfaced no tooltip detail.
- The roadmap originally prescribed proximity fog-reveal for `map_reveal`
  (reveal a room as the player nears it). **The user overrode this during
  Domain 10 planning**: a traditional minimap "cuts down on the horror" this
  game is built around. Maps become **items** (in the spirit of Project
  Zomboid's paper maps), focused on mapping ship positions in the
  surrounding web — not interior room awareness.

This ADR documents the three decisions that closed both loops.

## Decision 1: Two tooltip triggers, both change-gated at the callsite

`TooltipPresenter.resolve()` emits `payload_changed` **unconditionally on
every call** (by design — it is a pure resolver, not a debounced signal).
Any per-frame or per-interaction caller must gate the call itself, or the
signal (and the eventual UI/audio work hung off it) would spam.

- **Trigger 1 — proximity focus:** `Interactable` gained a
  `tooltip_subject_id: String`, set wherever `prompt_text` is already set
  (`configure_from_objective` → `objective_type`; `configure_from_step` →
  the new catalog entry `junction_step`, covering all repair steps
  generically rather than per-step). `PlayableGeneratedShip` gained
  `_refresh_tooltip_focus()`, called from **both** `_process` branches
  (mirroring `_refresh_audio_state`'s dual wiring): it scans the existing
  `interactables`/`derelict_interactables` collections (read-only —
  `candidate_player` is already maintained by `Interactable`'s own
  `body_entered`/`body_exited` physics callbacks), finds the nearest node
  whose `candidate_player == player`, and calls `set_tooltip_query` only
  when the resolved subject id **changes** from the previous frame
  (`_last_tooltip_focus_subject_id`).
- **Trigger 2 — inventory selection:** `InventoryPanel` gained an injected
  `tooltip_query_push: Callable`, set by the coordinator at bind time — the
  same injection pattern `AudioSettingsPanel.set_settings_push` established
  in ADR-0044. All seven selection-mutation call sites route through the
  shared `_after_mutation()` re-sync (which pushes the current single
  selection's tooltip, or the empty-id clear query for empty/multi
  selection), plus `select_row(...)` itself pushes on direct selection.

Unknown/uncataloged subject ids resolve to `null` harmlessly — the
presenter's pre-existing graceful fallback — so hazard tooltips (3 existing
catalog entries with no trigger wired yet) and any interactable without a
catalog entry fail silently rather than spam warnings. Hazard-tooltip
gameplay triggers remain an explicit, documented deferral.

**Reset discipline:** `_last_tooltip_focus_subject_id` is keyed only by
subject id, and objective/step types repeat across derelicts, so a stale
value surviving a ship transition would suppress a legitimate re-query for a
same-typed interactable on the next ship. It is force-reset (and the panel
force-cleared via an empty-id query) at all three `away_from_start`
transitions: boarding (`_attach_derelict_active`), unboarding
(`travel_home`), and reload-while-away (`_reset_runtime_for_reload`). Each
of the three was a separate fix landed during this branch's review passes
after the previous transition's reset was found insufficient — see the
`Domain 10 Task 5 fix` comments at each site in
`scripts/procgen/playable_generated_ship.gd`.

**Catalog correction against the original design premise.** The design
spec's original premise — that objective types already matched existing
catalog subject ids — was false: none of `recover_supplies`,
`restore_systems`, `download_logs`, `stabilize_reactor` existed in
`data/ui/tooltip_catalog.json` before this branch. Four new interactable
entries were added for them, plus `interactable_junction_step` and
`item_web_chart` (Decision 3). The catalog grew from ADR-0033's original 14
entries to **20** (`data/ui/tooltip_catalog.json`).

**Correction (PR #60 review, Codex P2):** the claim above that the four
GOLDEN objective types (`recover_supplies`, `restore_systems`,
`download_logs`, `stabilize_reactor`) closed the catalog gap was incomplete —
it only covered the hand-authored GOLDEN derelicts. `GameplaySliceBuilder`
(`scripts/procgen/gameplay_slice_builder.gd`), which emits objectives for
every **generated** derelict (the primary gameplay context — most runs are
on generated ships, not the three GOLDEN layouts), emits its own objective
`type` strings: `"salvage"` (:66, one per non-connective room) and
`"interact"` (:83, the final "reach goal" objective). Neither existed in the
catalog, so every generated derelict's salvage/reach-goal interactables
resolved a null tooltip payload — silently, per the graceful-fallback design
in Decision 1, so it produced no warnings and was easy to miss. Two more
interactable entries (`salvage`, `interact`) were added to close this;
the catalog is now **22** entries.

## Decision 2: Minimap deleted outright, not extended

`MapFogState`, `MapFogStateSchema`, `MinimapPanel`, and
`map_fog_state_smoke.gd` are deleted, along with every wiring callsite in
`MenuCoordinator` and `PlayableGeneratedShip` (`configure_map`/`track_room`/
`reveal_room`/`_refresh_minimap`/`get_minimap_text`, the `ui_open_map`
toggle, the objective-completed reveal, the critical-path track) —
commit `34c6e3b`. This is a deliberate architectural reversal, not an
oversight: the room-fog concept is retired for good per the user's
horror-pacing decision above, so extending it with proximity-reveal (the
original roadmap plan) would have built on a foundation about to be torn
out. `ui_shell_parse_check.gd`'s `classes=N` marker changes accordingly
(13 → 11 after deletion, → 12 after `WebChartState` is added with
Decision 3).

The system inventory's `map_fog_state`/`minimap_panel` rows (and the
`map_reveal` loop entry that had only those two systems as its steps) were
left stale in `docs/game/inventory/system_inventory.json` by `34c6e3b` and
were dropped in a follow-up fix (`263dc0f`) once `build_system_inventory.py
--check` started failing on the missing files — see the Verification
section below and the roadmap annotation's Inventory delta for the current,
truthful state of that file.

## Decision 3: WebChartState — session-only, item-gated, two recording sources

A new pure model, `WebChartState` (`scripts/systems/web_chart_state.gd`),
replaces the minimap's role for `map_reveal`, redefined as: recorded
knowledge of **ship positions in the web**, not interior rooms.

- **No `get_summary`/`apply_summary`/`SAVE_KEY`.** This is deliberate, not an
  oversight this ADR later has to explain away: the user explicitly scoped
  chart knowledge as session-only. Adding an unused save seam here would
  recreate the exact dead-seam pattern this same domain flags on
  `TooltipPresenter` (a `get_summary()` with a `SAVE_KEY` but no
  `apply_summary` and no callers — see `scripts/systems/tooltip_presenter.gd`)
  — so this domain does not repeat that mistake with a new class.
- **Two recording sources**, both deterministic (no RNG):
  - **Source A — found chart:** whenever a `web_chart` item (new entry in
    `data/items/utility_item_definitions.json`, loot-tabled into
    `salvage_cargo` and `hidden_cache`) enters the player inventory via the
    existing loot-grant hub (`_postprocess_loot_grants`, which every loot
    path — salvage, containers, corpses — already funnels through), all
    currently in-range world markers are recorded at detail 2
    (position + ship_type), the "paper map" import. `record_views` is
    idempotent (an equal-or-lower-detail re-record is a no-op), so repeat
    pickups of additional charts are harmless without any first-pickup
    tracking.
  - **Source B — scanner recording:** the coordinator's `scan()` already
    computes `ScannerState.scan()`'s detail-gated marker views (detail 1–6,
    gated by ship navigation/scanner systems + the player's
    `scanner_operation` skill). If the player possesses a `web_chart`
    (`InventoryState.get_quantity("web_chart") > 0`), the scan's markers are
    merged into the chart at the scan's own detail level. Scanning without a
    chart records nothing — there is nothing to write the recording onto.
- **Chart screen:** `ChartPanel` (`scripts/ui/chart_panel.gd`) reuses
  `ScannerPanel`'s presentation style (a bare vertical text-row panel,
  headless-queryable). `ui_open_map` (repurposed from the minimap toggle) now
  opens it **only if** the player possesses a `web_chart`; otherwise a HUD
  feedback line (`"No web chart"`, via `_last_loot_feedback_line`) surfaces
  through the pre-existing status-line seam. The panel is read-only — travel
  remains exclusively on the scanner panel.

## A validation pitfall worth naming: same-frame input dispatch

`Input.parse_input_event()` only *queues* a synthetic event; it is not
dispatched to `_input()`/`_unhandled_input()` until the **next**
`process_frame`. Two of this domain's end-to-end smokes
(`main_playable_ui_shell_smoke.gd`, `main_playable_slice_ui_shell_smoke.gd`)
originally sent the `KEY_M` chart-gate keypress and asserted the gate result
in the same phase/call — which always observed pre-dispatch state and
passed **vacuously** regardless of whether the gate logic worked at all.
This happened twice (both smokes share the same driver shape) before being
caught and fixed in commit `b169e39`, which split the send and the
assertion across a `process_frame` boundary (`_validate_runtime_pre_chart`
returns after sending `KEY_M`; `_validate_chart_gate` asserts one phase
later). Any future smoke that synthesizes a key/action press and expects to
observe its `_input()`-side effect must budget at least one intervening
`process_frame` — asserting in the same call/frame the event was queued is
a silent false-positive, not a stricter test.

## Retained deferrals (explicit, not gaps)

- Hazard-tooltip gameplay triggers (the 3 existing `hazard` catalog entries
  stay smoke-only).
- Chart visual/graphical map pass — text rows only, matching the scanner
  panel's current presentation maturity.
- Chart knowledge persistence — session-only by user decision (see
  Decision 3).
- Interior/room mapping of any kind — permanently retired (Decision 2), not
  a "later" item.
- Tooltip persistence — `TooltipPresenter.get_summary()`/`SAVE_KEY` remain a
  documented, intentionally-unwired dead seam (unchanged from ADR-0033).
- Tooltip-after-equip granularity — `_after_mutation()`'s re-sync covers all
  seven selection-mutating call sites uniformly; no equip-specific tooltip
  copy (e.g. distinguishing "equipped" vs "in bag" body text) was added.
- `force_repair_all_for_validation`'s docstring overpromises: it does not
  cover piloted-ship systems, only the currently active derelict/home ship.
  Pre-existing, unrelated to this domain, but surfaced during this branch's
  review and left uncorrected in code — flagged here so it is not
  rediscovered as a surprise.
- `docs/game/inventory/system_inventory.json` does not yet carry
  `web_chart_state`/`chart_panel` entries (`build_system_inventory.py
  --coverage`, not gated in the regression bundle, flags this). Left for a
  follow-up pass; see commit `263dc0f`'s note and the roadmap annotation's
  Inventory delta.

## Verification

- 1 new pure-state smoke: `web_chart_state_smoke` —
  `WEB CHART STATE PASS known=2 detail_upgrade=true` (record/upgrade/
  no-downgrade/malformed-rejection).
- 1 new main-scene end-to-end smoke: `ui_polish_smoke` —
  `UI POLISH PASS away_ticks=6 focus=true clear=true inventory_tooltip=true
  chart_gated=true chart_recorded=true`. Drives `away_from_start = true`,
  asserts proximity focus set + change-gated (single emission across
  repeated no-op ticks) + cleared on range-exit, inventory single-selection
  tooltip push, and the `ui_open_map` chart gate both denied (no chart) and
  rendered (chart + recorded scan).
- 2 rewritten main-scene smokes (`main_playable_ui_shell_smoke`,
  `main_playable_slice_ui_shell_smoke`) — minimap assertions replaced with
  chart-gate assertions; their previously byte-identical PASS markers are
  now distinct (`MAIN PLAYABLE UI SHELL PASS` vs.
  `MAIN PLAYABLE SLICE UI SHELL PASS`). This rewrite also changed
  `_validate_runtime`'s signature from `-> void` (fire-and-forget) to
  `-> bool`, a structural fix that makes the phase driver actually gate on
  the assertion's result rather than advance regardless.
- 1 updated parse-check (`ui_shell_parse_check`) —
  `UI SHELL PARSE PASS classes=12` (class count 13 → 12: −2 for the deleted
  `MapFogState`/`MapFogStateSchema` entries in the check's own class list —
  `MinimapPanel` was never in that list — +1 for the new `WebChartState`).
- The system inventory's anti-drift check
  (`tools/build_system_inventory.py --check`) initially broke after the
  minimap deletion, because the stale `map_fog_state`/`minimap_panel` rows
  (and the `map_reveal` loop entry built only from those two steps) were
  left behind in `docs/game/inventory/system_inventory.json`; under the
  regression bundle's `set -e`, this silently killed the run before any
  Domain 10 smoke was reached. Fixed in commit `263dc0f`, which drops the
  two stale system rows and the now-empty `map_reveal` loop entry and
  regenerates `SYSTEM_INVENTORY.md`/`system_map.html`
  (`SYSTEM INVENTORY CHECK PASS systems=189 verified=189`).
- All 9 surviving UI-shell smokes (previously never registered — see the
  ADR-0033 correction in `docs/game/adr/0033-ui-ux-accessibility-architecture.md`)
  plus the 2 new ones above are registered in the regression bundle
  (`docs/game/06_validation_plan.md`): `commands=121 → 132`, ending in
  `SYNAPTIC_SEA REGRESSION PASS commands=132 clean_output=true`.

## Consequences

- Tooltips are no longer dead code: both real-play triggers (proximity
  focus, inventory selection) now drive `TooltipPresenter` on every frame
  that matters, on both `_process` branches.
- The horror-pacing goal is preserved — no persistent, always-on room map
  exists anywhere in the shipped game.
- `map_reveal` closes under a redefinition, not the roadmap's original
  per-step-proximity plan; anyone reading the original Domain 10 roadmap
  text without the annotation in
  `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` would
  expect the wrong feature. That file is annotated, not rewritten, to keep
  both the original plan and the actual outcome visible.
- `WebChartState`'s lack of a save seam is a structural risk in the sense
  that any future request to persist chart knowledge across saves requires
  adding `get_summary`/`apply_summary`/`SAVE_KEY` and a `RunSnapshot` field
  from scratch — this ADR is the record that the omission was a decision,
  not an oversight, should that request arise.
