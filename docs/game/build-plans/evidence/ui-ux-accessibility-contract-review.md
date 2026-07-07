# Task 09: UI/UX, HUD, Menus, Tutorials, Controller & Accessibility — Contract Review

## Source-backed review

This package extends, not replaces, the existing UI/UX/HUD/accessibility
seams. The existing `AccessibilitySettings` (`scripts/ui/accessibility_settings.gd`)
already provides the single runtime seam for HUD text + world Label3D
scale (A11Y-P1-001). The existing input map (`playable_generated_ship.gd::ensure_default_input_actions`)
already covers keyboard, mouse, and the alternate-keyboard surface
(A11Y-P1-002). The existing HUD layer already hosts ObjectiveTracker,
PlayerVitalsPanel, ScannerPanel, and InventoryPanel.

This package **adds the missing UI shell** — a top-level menu stack
(main menu → pause menu → settings → in-play HUD → codex / minimap /
tooltip / tutorial) — plus the data-driven configuration that drives it
(settings, tutorial triggers, codex entries, input glyph tables,
accessibility presets, fog-of-war map state).

| Required new system | Existing seam reused | Extension surface |
|---|---|---|
| MenuState | none — top-level menu stack did not exist | New `scripts/systems/menu_state.gd` is a pure state machine that owns `current_menu`, the `menu_history` stack for back navigation, and the active focus index. Headless-queryable. |
| SettingsState | `scripts/ui/accessibility_settings.gd::AccessibilitySettings` (text-scale only) | New `scripts/systems/settings_state.gd` is a pure `RefCounted` that owns a settings dict (text_scale, colorblind_mode, motion_reduce, captions, hold_to_tap, gameplay_difficulty) plus a SettingsStateSchema (`scripts/schemas/settings_schema.gd`) for static validation. SettingsState.apply_to_accessibility(a11y)` writes back to the existing `AccessibilitySettings` so the rest of the HUD keeps its single source of truth. |
| TooltipPresenter | `scripts/ui/inventory_panel.gd` (its own row hover, not centralized) | New `scripts/systems/tooltip_presenter.gd` is a pure state object that resolves a `TooltipQuery` (subject_kind, subject_id, context) to a `TooltipPayload` (title, body, footer) using a registered tooltip catalog. Reusable by interactables, inventory rows, and codex. |
| TutorialState | none | New `scripts/systems/tutorial_state.gd` owns the trigger catalog and the per-run "fired / dismissed" ledger. `trigger(event, target)` is idempotent (fires once per `event|target` pair), `dismiss(tutorial_id)` lets the player skip, and `unlock_codex(tutorial_id)` emits a codex unlock so the help entry becomes available. |
| MapFogState | `scripts/procgen/room_graph.gd` (room list only) | New `scripts/systems/map_fog_state.gd` is a pure fog-of-war map state: per-room `revealed` flag, per-room `discovered` flag, current `tracked_room_id`. Loaded from the room graph at runtime via `configure_for_rooms(room_ids)`. |
| ControllerGlyphState | `scripts/procgen/playable_generated_ship.gd::ensure_default_input_actions` (input bindings only) | New `scripts/systems/controller_glyph_state.gd` is a pure data object that maps `action_name` → glyph text per active scheme (`keyboard` / `gamepad_xbox` / `gamepad_ps`). Reads the same binding list at boot so the glyph reflects the actually-bound keycode, not a hard-coded label. |
| AccessibilitySettings expansion | `scripts/ui/accessibility_settings.gd` (text-scale only) | Extend the existing class with `get/set colorblind_mode`, `motion_reduce`, `captions`, `hold_to_tap`, plus a `preset_id` accessor and `apply_preset(preset_id)`. Default values reproduce the prior hard-coded behaviour exactly so the existing A11Y-P1-001 smoke stays green. |

## Files to extend (not replace)

- `scripts/ui/accessibility_settings.gd` — additive: new fields
  (`colorblind_mode`, `motion_reduce`, `captions`, `hold_to_tap`,
  `preset_id`), new `apply_preset(id)` helper. Default constructor
  reproduces prior behaviour exactly.
- `scripts/procgen/playable_generated_ship.gd` — wire UI shell coordinator:
  - `_build_hud_layer()` adds `menu_state`, `tutorial_state`, `codex_panel`,
    `minimap_panel`, `pause_menu`, `settings_menu`, `main_menu`, and the
    `hotbar` as additional hud_layer children.
  - `ensure_default_input_actions()` adds the UI shell actions
    (`ui_cancel`, `ui_pause`, `ui_open_codex`, `ui_open_map`,
    `ui_navigate_up/down/left/right`, `ui_accept`, `ui_select_*`).
  - `_input()` routes the new actions to the menu coordinator. Existing
    keyboard / mouse / alternate-key handling is preserved unchanged.
  - `apply_accessibility_settings()` cascades the new fields into every
    UI node that subscribes to it.
- `scripts/systems/run_snapshot.gd` — additive: `settings_summary`
  field, schema-version bumped 1.0.0 → 1.1.0. The save/load smoke
  summaries count rises from 9 to 10 (audio + settings).

## Files to author (new)

### Pure-model state (RefCounted)
- `scripts/systems/menu_state.gd` — menu stack state machine
- `scripts/systems/settings_state.gd` — settings dict + apply_to_accessibility
- `scripts/systems/tooltip_presenter.gd` — query → payload resolver
- `scripts/systems/tutorial_state.gd` — trigger catalog + dismiss + codex unlock
- `scripts/systems/map_fog_state.gd` — per-room revealed/discovered flags
- `scripts/systems/controller_glyph_state.gd` — action → glyph per scheme

### Schemas / static validation
- `scripts/schemas/settings_schema.gd` — SettingsStateSchema
- `scripts/schemas/menu_state_schema.gd` — MenuStateSchema
- `scripts/schemas/tooltip_schema.gd` — TooltipPresenterSchema
- `scripts/schemas/tutorial_state_schema.gd` — TutorialStateSchema
- `scripts/schemas/map_fog_schema.gd` — MapFogStateSchema
- `scripts/schemas/controller_glyph_schema.gd` — ControllerGlyphStateSchema

### Configuration data (JSON / data-Resource)
- `scripts/schemas/settings_state_schema.gd` — live settings field definitions; supersedes deleted `data/ui/settings_schema.json`
- `data/ui/tutorial_triggers.json` — tutorial catalog
- `data/ui/codex_entries.json` — codex entries
- `data/ui/input_glyphs.json` — glyph table per scheme
- `data/ui/accessibility_presets.json` — preset definitions
- `data/ui/menu_definitions.json` — menu / item definitions
- `data/ui/tooltip_catalog.json` — tooltip query → payload catalog

### UI nodes (Control / CanvasLayer)
- `scripts/ui/menu_panel.gd` — generic menu base (stack of items)
- `scripts/ui/main_menu_panel.gd` — main menu (Start / Continue / Settings / Quit)
- `scripts/ui/pause_menu_panel.gd` — pause menu (Resume / Settings / Codex / Save / Quit)
- `scripts/ui/settings_menu_panel.gd` — settings menu (subscribes SettingsState)
- `scripts/ui/codex_panel.gd` — codex viewer (subscribes TutorialState)
- `scripts/ui/minimap_panel.gd` — minimap (subscribes MapFogState)
- `scripts/ui/hotbar_panel.gd` — bottom hotbar (passive; reads selected_tool from inventory)
- `scripts/ui/tooltip_panel.gd` — tooltip overlay (subscribes TooltipPresenter)
- `scripts/ui/tutorial_overlay_panel.gd` — tutorial banner
- `scripts/ui/menu_coordinator.gd` — coordinator that owns MenuState and dispatches to panels

### ADR / docs
- `docs/game/adr/0033-ui-ux-accessibility-architecture.md` — package ADR
- `docs/game/features/ui_ux_accessibility.md` — feature spec
- `docs/game/balance/ui_ux_accessibility_tuning.md` — tuning notes
- `docs/game/05_requirements.md` — append REQ-UI-001..016
- `docs/game/07_risk_register.md` — risk row
- `docs/game/06_validation_plan.md` — register 6 new smokes

### Smoke scripts (6 total + a save/load round-trip smoke)
- `scripts/validation/menu_state_smoke.gd` — pure-model + headless main menu
- `scripts/validation/settings_state_smoke.gd` — pure-model + apply_to_accessibility
- `scripts/validation/tooltip_presenter_smoke.gd` — query → payload + unknown-id guard
- `scripts/validation/tutorial_state_smoke.gd` — trigger once / skip / codex unlock
- `scripts/validation/map_fog_state_smoke.gd` — reveal / discover / track
- `scripts/validation/controller_glyph_state_smoke.gd` — scheme resolution + unknown-action guard
- `scripts/validation/main_playable_slice_ui_shell_smoke.gd` — end-to-end UI shell through PlayableGeneratedShip
- `scripts/validation/ui_shell_save_load_smoke.gd` — settings_summary round-trip through save/load

## Backward compatibility

- `AccessibilitySettings` defaults reproduce the prior text-scale-only
  behaviour exactly. The existing A11Y-P1-001 smoke (`main_playable_slice_text_scale_smoke.gd`)
  stays green because every new field defaults to its prior implicit value
  (`colorblind_mode = "none"`, `motion_reduce = false`, `captions = true`,
  `hold_to_tap = false`, `preset_id = "default"`).
- The HUD layer construction appends children; no existing children are
  removed or repositioned.
- The input map additions (`ui_cancel`, `ui_pause`, etc.) are
  additive — existing bindings (`move_*`, `interact`, `save_run`,
  `load_run`, `toggle_scanner`, `toggle_inventory`) are unchanged. The
  A11Y-P1-002 alternate-input smoke stays green.
- `RunSnapshot` schema bumps from 1.0.0 to 1.1.0; the save migration
  service already handles missing-fields-permissive loads, so older
  saves load without `settings_summary` and the in-memory state is
  re-bootstrapped from the default AccessibilitySettings.

## Stop / block conditions

None hit. No existing ADR contradicts this package.

## Out of scope

- Final art assets beyond the placeholder sprites referenced by the
  scene tree (placeholder rects are sufficient for locked-isometric
  readability; final art is a Gate 3 concern).
- Controller rumble / haptics (REQ-AU-008 audio only; controller
  haptics is a Gate 3 follow-up ADR).
- VR / accessibility for vision-impaired beyond high-contrast and
  reduced motion; full screen-reader integration is a post-launch
  follow-up.
- Localisation of UI strings beyond the existing `LocalizationCatalog`
  seam — UI strings flow through the catalog but this package does not
  ship localised strings.
