# Domain 10: UI/UX Polish (Tooltip + Web-Chart Map Pivot) — Design Spec

Date: 2026-07-02
Status: Draft for user review; extends ADR-0033 via new ADR-0045.
Roadmap source: `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` Domain 10 (loops `tooltip`, `map_reveal`).

## 1. Problem

- **`tooltip` (broken):** the render chain works end-to-end — `MenuCoordinator.set_tooltip_query` → `TooltipPresenter.resolve()` (pure RefCounted) → `payload_changed` → `TooltipPanel` — but has **zero gameplay callers** (only 2 smokes). No hover/focus concept exists anywhere: interactables are Area3D proximity spheres (r=1.8) consulted only on interact keypress; inventory has selection but surfaces no detail.
- **`map_reveal` (partial → redefined by user):** the roadmap prescribed proximity fog-reveal on a room minimap. **The user has overridden this**: no traditional minimap ("cuts down on the horror"); maps become **items** (like Project Zomboid paper maps) focused on **mapping ship positions in the web**, not interior awareness.

## 2. Definition of CLOSED (user-revised)

1. `set_tooltip_query` is called from real gameplay: **proximity focus** on interactables AND **inventory row selection**, live on BOTH `_process` branches.
2. The room-fog minimap (`MapFogState`/`MinimapPanel`) is **deleted**; `ui_open_map` opens a **web chart screen** gated on possessing a chart item, rendering recorded ship-marker knowledge.
3. Chart knowledge comes from **both** sources: scanner contacts auto-record while a chart is possessed; found chart items import markers.
4. All remaining UI-shell smokes are registered in the regression bundle; ADR-0033's false "all registered" claim is corrected.

## 3. User-locked decisions

| Decision | Choice |
|---|---|
| Tooltip triggers | Proximity focus + inventory selection |
| UI-shell smoke registration | Register all (9 remaining after map-fog deletion) + reconcile ADR-0033 |
| Map direction | Retire room minimap; ship web-chart v1 in this domain (one PR) |
| Chart persistence | **Session-only** — no RunSnapshot schema change, no summary seam |
| Chart sources | Both: scanner auto-record (while chart possessed) + found chart items |
| Chart item spawn | Derelict loot containers |
| Chart detail | Detail-at-recording (scan detail 1–6 reused); re-record upgrades to max detail |
| MapFogState disposition | **Delete outright** (model, schema, panel, smoke, all wiring) |

## 4. Verified current state (explored 2026-07-02)

- Tooltip catalog: `data/ui/tooltip_catalog.json` (`tooltip-catalog-1`, 14 entries: 8 `interactable`, 3 `hazard`, 3 `item`). Subject ids are objective-type-shaped (`circuit_board`, `fire_extinguisher`, `breach`, …). Configured via `MenuCoordinator.configure(...)` → `tooltip_presenter.configure(tooltip_catalog)` (menu_coordinator.gd:135/148).
- `TooltipPresenter.resolve(query)` emits `payload_changed` **unconditionally on every call** — per-frame callers must be change-gated. `get_summary()`/`SAVE_KEY` exist with no `apply_summary` and no callers (dead seam; tooltip is ephemeral — documented, not persisted).
- Interactables: `scripts/interaction/interactable.gd` (Area3D) maintains `candidate_player` via body_entered/exited (:152-159); `prompt_text` set from `objective_type` / `step_id` at configure time.
- Inventory selection: `InventoryPanel.select_row(pane, index, additive, range_sel)` (inventory_panel.gd:130) drives `InventorySelectionModel` (`select_single`/`toggle`/`select_range_to`/`get_selected_ids`).
- Map fog: `MapFogState` (room-id graph) → `MenuCoordinator._refresh_minimap` (:1046) → `MinimapPanel` (text Label). Gameplay callsites: objective-completed reveal (playable_generated_ship.gd:3861), critical-path track (:4567), `ui_open_map` reveal (:7834), panel toggle (menu_coordinator.gd:176). Never persisted in RunSnapshot (moot — deleted).
- Web substrate: `SynapticSeaWorld.markers_in_range(radius)` → markers `{marker_id, position, size_class, ship_type, condition, seed_value}`; `ScannerState.scan(world, systems_ops, skill)` returns `{detail_level: 1–6, markers: [view dicts]}` with detail-gated fields (≥2 ship_type, ≥3 condition, ≥4 predicted_status, ≥5 predicted_offline, ≥6 loot_hint); `ScannerPanel.refresh()` calls `_coordinator.scan()` (scanner_panel.gd:72); coordinator `scan()` at playable_generated_ship.gd:1968.
- Items/loot: `data/items/utility_item_definitions.json` uses a `utility_flag` pattern (flare, lockpick, hack_chip); `data/items/loot_tables.json` (`loot-tables-2`) has weighted per-table entries; `LootRoller` loads it. `InventoryState.get_quantity(item_id)` is the possession gate.
- **Docs integrity (pre-existing):** ADR-0033:190-204 claims the UI smokes are "added to the regression bundle" — zero of the 10 are (verified by grep of `06_validation_plan.md`). `ui_shell_parse_check.gd` instantiates MapFogState/schema and must be updated when they are deleted.

## 5. Design

### 5.1 Tooltip trigger 1 — proximity focus (interactables)

- `Interactable` gains `tooltip_subject_id: String`, set where `prompt_text` is set today: `configure_from_objective` → `objective_type` (amended 2026-07-02: does NOT match existing catalog subject ids — the 4 procgen objective types `recover_supplies`/`restore_systems`/`download_logs`/`stabilize_reactor` had no `subject_kind: "interactable"` entries and silently resolved to null; 4 new catalog entries were added in the Task 5 fix wave to close the gap), `configure_from_step` → `"junction_step"` (one new catalog entry covers repair steps generically).
- `PlayableGeneratedShip` gains `_refresh_tooltip_focus()` called from BOTH `_process` branches (mirroring `_refresh_audio_state`'s dual wiring): scan the live interactable collections for nodes whose `candidate_player == player` (already maintained by physics callbacks — the scan is read-only), pick the nearest to the player, and **only on change** call `menu_coordinator.set_tooltip_query({"subject_kind": "interactable", "subject_id": focused.tooltip_subject_id})`; on focus lost call it with `{"subject_kind": "interactable", "subject_id": ""}` (unknown id → null payload → panel hides — the presenter's existing graceful path).
- Validation seam: `get_focused_tooltip_subject() -> String` on the coordinator node (matches `get_last_caption_line()` convention).
- Unknown/uncataloged subject ids resolve to null harmlessly (presenter's existing behavior) — the honest fallback for interactables without catalog entries; no per-frame warning spam (resolve is change-gated).

### 5.2 Tooltip trigger 2 — inventory selection (items)

- `InventoryPanel` gains an injected `tooltip_query_push: Callable` (set by the coordinator at bind time — same injection pattern as `AudioSettingsPanel.set_settings_push`, ADR-0044). At the end of `select_row(...)`: when exactly **one** item is selected, push `{"subject_kind": "item", "subject_id": <selected item id>}`; on empty/multi selection or panel close, push the empty-id clear query.
- `data/ui/tooltip_catalog.json` gains `item` entries for the chart item (`web_chart`) and the items the two main-scene smokes exercise; other items resolve null (graceful, same as 5.1). No schema change (`tooltip-catalog-1` already supports `item`).
- Hazard tooltips (3 existing catalog entries) remain smoke-only — documented deferral in ADR-0045.

### 5.3 Minimap retirement (deletion)

Delete: `scripts/systems/map_fog_state.gd`, `scripts/schemas/map_fog_schema.gd`, `scripts/ui/minimap_panel.gd`, `scripts/validation/map_fog_state_smoke.gd`.
Strip: `MenuCoordinator` (instantiation, `configure_map`/`track_room`/`reveal_room`/`_refresh_minimap`/`get_minimap_text`, the :974 accessibility child list entry, the `ui_open_map` toggle at :176); `PlayableGeneratedShip` callsites (:3861, :4563-4567, :7834); `ui_shell_parse_check.gd` (drop the two deleted classes; its `classes=N` marker count changes).
Rewrite: `main_playable_ui_shell_smoke.gd` + `main_playable_slice_ui_shell_smoke.gd` — replace `minimap=true` / `"Tracked:"` assertions with chart assertions (§5.6); their PASS-marker byte contracts change and are registered in the same PR (rewrite → verify → register, in that order).

### 5.4 WebChartState (new pure model)

`scripts/systems/web_chart_state.gd` (`RefCounted`, `class_name WebChartState`, typed GDScript, no scene-tree access):
- `_entries: Dictionary` — `marker_id → {position: Array[3], size_class: int, detail: int, ...detail-gated fields}`.
- `record_views(views: Array, detail_level: int) -> int` — merge scan/chart views; per marker keep `max(existing.detail, detail_level)` and union fields; returns count of new/upgraded entries.
- `get_known_marker_ids() -> Array`, `get_entry(marker_id) -> Dictionary`, `get_known_count() -> int`, `get_status_lines() -> PackedStringArray`.
- **No `get_summary`/`apply_summary` and no `SAVE_KEY`** — session-only by user decision; adding an unused save seam would recreate the exact dead-seam pattern this domain flags on `TooltipPresenter`. ADR-0045 documents ephemerality as deliberate.

### 5.5 Chart item + sources + chart screen

- **Item:** `web_chart` in `data/items/utility_item_definitions.json` (`utility_flag: "web_chart"`, low weight, `max_stack` small); loot entries in `salvage_cargo` and `hidden_cache` tables (`loot-tables-2` weighted-entry shape).
- **Source A — found chart:** whenever a `web_chart` enters the player inventory (the existing item-pickup path), record ALL current world markers at **detail 2** (position + ship_type) — the "paper map" import. No first-pickup tracking needed: `record_views` is idempotent (equal-detail re-record is a no-op), so repeat pickups are harmless. Deterministic, no RNG.
- **Source B — scanner recording:** in the coordinator's `scan()` (playable_generated_ship.gd:1968), after a successful scan, if `player inventory get_quantity("web_chart") > 0`, call `web_chart_state.record_views(result.markers, result.detail_level)`. Scanning without a chart records nothing (nothing to write on).
- **Chart screen:** new `scripts/ui/chart_panel.gd` (text panel, `ScannerPanel` presentation style, headless-queryable rows). `ui_open_map` (repurposed from the minimap toggle) opens it **only if** `get_quantity("web_chart") > 0`; otherwise a HUD feedback line ("No web chart") via the existing system-status-lines path. Renders one row per known marker with detail-gated fields; read-only (travel stays on the scanner panel).

### 5.6 Validation

- **New pure smoke** `web_chart_state_smoke.gd`: record at detail 2 → assert fields; re-record same marker at detail 5 → assert upgrade (never downgrade); unknown/malformed views rejected. Marker: `WEB CHART STATE PASS known=N detail_upgrade=true`.
- **New main-scene smoke** `ui_polish_smoke.gd` (byte contract fixed in the implementation plan): boots the playable slice, drives `away_from_start = true`, manual `_process` ticks; asserts (a) walking a player body into an interactable's Area3D sets the focused subject and the tooltip panel text (change-gated: tick twice, assert single payload emission), (b) leaving clears it, (c) inventory single-selection pushes an item tooltip, (d) `ui_open_map` without chart → gate message, (e) with chart + scan → chart panel renders the recorded marker. Carries the mandatory `away_ticks=` assertion. Writes nothing to disk; frees the scene on both exit paths.
- **Rewrite** the two `main_playable*_ui_shell_smoke.gd` (drop minimap assertions, keep tooltip assertion, add chart-gate assertion); **update** `ui_shell_parse_check.gd` class list.
- **Register** in the bundle: the 9 surviving UI-shell smokes (tooltip_presenter, menu_state, settings_state, tutorial_state, controller_glyph_state, ui_shell_parse_check, ui_shell_save_load, main_playable_ui_shell, main_playable_slice_ui_shell) + 2 new = **11 new run_clean lines; bundle 121 → 132** (`SYNAPTIC_SEA REGRESSION PASS commands=132 clean_output=true`). Each verified passing before registration; any newly surfaced warnings classified per allowlist discipline first.

### 5.7 Docs/inventory delta

- **ADR-0045** "Tooltip gameplay triggers, minimap retirement, and item-based web charts": the two trigger seams (change-gating rationale), the deletion decision, WebChartState's deliberate ephemerality, chart source semantics, retained deferrals (hazard tooltips, chart visual pass, chart persistence). Indexed in `adr/README.md`.
- **ADR-0033 correction** (pre-existing false claim): "all eight entries are added to the regression bundle" → the verified post-Domain-10 registration state.
- **Roadmap spec update**: Domain 10 section annotated with the user's map_reveal redefinition; status table row updated.
- **Inventory**: delete `map_fog_state`/`minimap_panel` system entries; add `web_chart_state`/`chart_panel`; `tooltip.closes → closed` (both trigger paths as break_point closures); `map_reveal` loop redefined (steps: web_chart_state → chart_panel) → `closed`; `tooltip_presenter.input.live → true`. Regenerate via `tools/build_system_inventory.py`; `--check` passes.

## 6. Out of scope (explicit)

Hazard-tooltip gameplay triggers; chart visual/graphical map pass (text rows only); chart knowledge persistence (session-only by decision); interior/room mapping of any kind; crafting charts; scanner hardware upgrades; tooltip persistence (dead `get_summary` seam documented, not wired).

## 7. Risks

1. **Marker byte-contract churn**: 3 existing smokes' PASS markers change (2 ui_shell rewrites + parse_check class count) in the same PR that registers them — order is rewrite → verify → register.
2. **Away-branch regression** (3 shipped precedents): `_refresh_tooltip_focus` must be wired into BOTH `_process` branches; `ui_polish_smoke` drives the away branch.
3. **Per-frame emit spam**: `payload_changed` fires on every `resolve()` — both triggers are change-gated at the callsite; the smoke asserts single emission across repeated ticks.
4. **Coordinator churn**: playable_generated_ship.gd ~7,800 lines; cite `function:symbol` alongside line numbers in briefs.
5. **project.godot untouched** this domain; `git diff project.godot` after every Godot invocation (`--editor` mutation trap).
