# ADR-0033: UI/UX, HUD, Menus, Tutorials, Controller & Accessibility Architecture

- Status: Accepted
- Date: 2026-06-25
- Package: Task 09 (`docs/game/build-plans/09-ui-ux-accessibility-e2e.md`)
- Related ADRs: ADR-0025 (player vitals HUD), ADR-0027 (vitals HUD cleanup),
  ADR-0029 (audio music spatial), ADR-0031 (localization)

## Context

The Synaptic Sea shipped the foundational HUD layer (ObjectiveTracker,
PlayerVitalsPanel, ScannerPanel, InventoryPanel) plus the single
`AccessibilitySettings` seam (A11Y-P1-001) and the keyboard/alternate
input surface (A11Y-P1-002). What it does NOT have is:

1. A top-level menu stack (main menu, pause menu, settings menu).
2. A settings dict that lives beyond `text_scale`.
3. A codex / tutorial / minimap / tooltip / hotbar surface.
4. A controller glyph resolver.
5. A fog-of-war map state.
6. A save/load seam for settings.

Gate 1 explicitly defers the full UI shell ("core shell available,
HUD overlays for status, inventory, scanner, vitals") to a follow-up
package. Task 09 is that package.

## Decision

### 1. Pure-model-first state

Every new UI feature has a `RefCounted` (or `Resource`) pure state
model first; scene nodes subscribe to that model via signals. Models
never reach into the scene tree. Models expose:

- `configure(catalog: Dictionary)` — static validation against a
  Schema class.
- `tick(delta)` where relevant (none of the UI models need tick — they
  are event-driven).
- `get_summary()`, `apply_summary(summary)`, `get_status_lines()`.

The scene nodes are thin Control / CanvasLayer views over the model.

### 2. Single accessibility seam

`AccessibilitySettings` (`scripts/ui/accessibility_settings.gd`) is the
single seam. New fields are added to it:

- `colorblind_mode` — "none" | "protanopia" | "deuteranopia" | "tritanopia"
- `motion_reduce` — bool
- `captions` — bool
- `hold_to_tap` — bool
- `preset_id` — string (default = "default")
- `difficulty` — string ("standard" | "hardened" | "deep_dive")
- `glyph_scheme` — string ("auto" | "keyboard" | "gamepad_xbox" | "gamepad_ps")

Default values reproduce the pre-package behaviour exactly so the
existing A11Y-P1-001 smoke stays green. A new `apply_preset(preset_id)`
helper applies a full preset (loaded from `data/ui/accessibility_presets.json`)
to the same instance.

`SettingsState` (a new `RefCounted`) owns the dict representation of
these fields and writes back via `SettingsState.apply_to_accessibility(a11y)`
— never creating a duplicate seam.

### 3. Menu state machine

`MenuState` is a pure state object that owns:

- `current_menu` — the id of the active menu (or `""` for "in-play")
- `menu_history` — a stack of menu ids so `cancel` pops one
- `focus_index` — the focused item index within the current menu
- `pending_close_on_cancel` — bool so a confirm vs cancel can target
  different outcomes when an in-play action opened a menu

Transitions are headless: `open_menu(id)`, `close_top()`, `navigate(dx, dy)`,
`confirm()`, `cancel()`. The scene coordinator subscribes to signals
emitted on every transition.

### 4. Tutorial / codex surface

`TutorialState` is a pure state object that owns:

- `_catalog` — loaded from `data/ui/tutorial_triggers.json`
- `_fired` — set of `event|target` pairs already fired
- `_dismissed` — set of tutorial ids dismissed in this run
- `_codex_unlocks` — set of codex entry ids unlocked in this run

`trigger(event, target)` returns the tutorial id on first call,
empty string on re-fire, empty string on unknown `(event, target)`.
`dismiss(id)` removes the banner, marks the tutorial dismissed,
unlocks the matching codex entry, and emits the `codex_unlocked`
signal.

`TutorialOverlayPanel` subscribes to `triggered` and renders the
banner. `CodexPanel` subscribes to `codex_unlocked` and rebuilds the
entry list.

### 5. Minimap / fog-of-war

`MapFogState` is a pure state object that owns:

- `_rooms` — `{room_id: {revealed: bool, discovered: bool}}`
- `_neighbours` — `{room_id: [adjacent_room_id, ...]}`
- `_tracked_room_id` — current player location

`configure_for_rooms(room_ids)` initialises every room as
`discovered=false, revealed=false`. `reveal(room_id)` marks the room
revealed and propagates discovery to its neighbours. `track(room_id)`
sets the current location; tracking an unknown room is rejected with
`push_warning`.

### 6. Tooltip catalog

`TooltipPresenter` owns a catalog of `{subject_kind, subject_id}` →
`{title, body, footer}` mappings. `resolve(query)` returns a
`TooltipPayload` (a small `RefCounted`) or `null` for unknown ids.

The catalog lives in `data/ui/tooltip_catalog.json` and is statically
validated by `TooltipPresenterSchema` on `configure()`.

### 7. Controller glyph resolver

`ControllerGlyphState` owns per-scheme glyph maps loaded from
`data/ui/input_glyphs.json`. The glyph table is keyed by
`(action_name, scheme)` and yields a glyph text string.

`glyph_for(action_name, scheme)` returns the glyph for the requested
scheme and falls back to `keyboard` when the scheme key is missing.

### 8. UI input map

The existing `ensure_default_input_actions` is extended with the UI
shell actions:

- `ui_up`, `ui_down`, `ui_left`, `ui_right` — keyboard arrows + gamepad d-pad / left stick
- `ui_accept` — keyboard Enter + Space + gamepad A
- `ui_cancel` — keyboard Escape + gamepad B
- `ui_pause` — keyboard Escape + gamepad Start (mirrors `ui_cancel`
  semantics on the keyboard to keep "open the pause menu" discoverable)
- `ui_open_codex` — keyboard F1 + gamepad back
- `ui_open_map` — keyboard M + gamepad Y

The new actions are added additively; existing bindings stay unchanged.

### 9. Save / load seam

`RunSnapshot.settings_summary` is added (schema bump 1.0.0 → 1.1.0).
The save migration service already handles missing fields gracefully,
so older saves load with `settings_summary = null` and the in-memory
state re-bootstraps from defaults. The save/load service smoke
assertion rises from 9 to 10.

### 10. UI shell coordinator

A new `MenuCoordinator` (Node) wires the panels together:

- Owns `MenuState`, `SettingsState`, `TutorialState`, `TooltipPresenter`,
  `MapFogState`, `ControllerGlyphState`.
- Routes input actions to the active panel.
- Owns the HUD layer (added by `PlayableGeneratedShip._build_hud_layer`).

The coordinator is built once per playable run; rebuild happens on
reload (mirrors the existing scanner / inventory teardown contract).

## Consequences

### Positive

- Single accessibility seam preserved.
- Pure-model-first means every feature is headless-testable.
- The HUD layer is extensible: adding a new panel is additive.
- The save/load contract stays backward compatible (older saves load
  with `settings_summary = null` and re-bootstrap from defaults).

### Negative

- Adds 6 new pure-state classes + 6 schema classes + 10 UI nodes; the
  diff is large but bounded.
- Adds 6 new input actions; the A11Y-P1-002 idempotency smoke stays
  green but the input map gets longer.

### Risks

- A11Y seam drift: a duplicate seam could be introduced later. Mitigated
  by the `SettingsState.apply_to_accessibility` write-back contract.
- Save migration: a malformed `settings_summary` from an older
  experimental build could fail to load. Mitigated by the
  missing-fields-permissive `RunSnapshot.from_dict`.

## Verification

- 6 new pure-state smokes:
  `menu_state_smoke`, `settings_state_smoke`, `tooltip_presenter_smoke`,
  `tutorial_state_smoke`, `map_fog_state_smoke` (deleted in Domain 10 — see
  ADR-0045), `controller_glyph_state_smoke`.
- 1 new main-playable end-to-end smoke:
  `main_playable_slice_ui_shell_smoke` — drives the coordinator through
  the full menu stack via `Input.action_press` / `Input.parse_input_event`.
- 1 new save/load smoke:
  `ui_shell_save_load_smoke` — proves settings round-trip.
- The existing `a11y_p1_002_idempotency_smoke`, `save_load_service_smoke`,
  and `main_playable_slice_text_scale_smoke` are re-verified after the
  changes and stay green.

**Correction (Domain 10, 2026-07-02):** the claim below this line originally
read "All eight entries are added to the regression bundle." This was false
— none of them were registered in `docs/game/06_validation_plan.md` at the
time this ADR was written (verified by grep). Domain 10 (ADR-0045) registers
all 9 UI-shell smokes that survive its `map_fog_state_smoke` deletion, plus
2 new ones, for 11 total `run_clean` entries (`06_validation_plan.md`,
`commands=121 → 132`).