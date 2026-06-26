# Vitals / HUD Cleanup (Design Spec)

Date: 2026-06-25
Status: Approved (brainstorm)

## Goal

Pay down the HUD debt that the player-vitals slice (ADR-0025) left behind, in
one focused batch:

1. **De-duplicate the HUD.** The bottom-left `PlayerVitalsPanel` is now the home
   for player oxygen, suit effect, and load. The top-left `ObjectiveTracker`
   still redundantly renders a terse `Oxygen:` line, a `Breach:` line, and an
   inventory `weight=` line. Remove those from the tracker so each fact lives in
   exactly one place; the tracker keeps objectives, ship-system status, carried
   tools, and repair skill.
2. **Close a validation gap.** `main_playable_slice_hud_smoke.gd` exists and
   passes but is not registered in the regression bundle, so a top-left-HUD
   regression is currently unguarded. Register it.
3. **Accessibility parity.** `ObjectiveTracker` scales its font/panel/label from
   the `AccessibilitySettings` seam (A11Y-P1-001) and the coordinator pushes
   settings into it. `PlayerVitalsPanel` hard-codes its sizes and is never
   wired, so text-scale accessibility does not reach it. Bring it to parity.

This is a cleanup slice: no new player-facing feature, no model/persistence
change. Default text scale (1.0) must leave every pixel identical to today.

## Context (what exists — verified)

- **`ObjectiveTracker`** (`scripts/ui/objective_tracker.gd`): top-left HUD. Owns
  an `accessibility_settings` (default `AccessibilitySettings.new()`), exposes
  `apply_accessibility_settings(settings)`, and derives font/panel/label sizes
  from `BASE_*` constants × the scale. Renders `system_status_lines` (set via
  `set_system_status_lines`) under a "Systems:" block.
- **`PlayerVitalsPanel`** (`scripts/ui/player_vitals_panel.gd`): bottom-left HUD,
  `PRESET_BOTTOM_LEFT`, `PANEL_POSITION = Vector2(18, -168)` (= −(150 height + 18
  bottom margin)). Hard-codes `PANEL_SIZE = (360,150)`, `LABEL_MIN_SIZE = (320,0)`,
  `HUD_FONT_SIZE = 18`. Presentation-only: `set_status_lines(lines)` renders
  pre-formatted lines from the coordinator. No `accessibility_settings`.
- **`playable_generated_ship.gd`** (coordinator):
  - `_combined_system_status_lines()` (≈L2907) builds the tracker block: ship
    systems (Power/Reactor/Supplies/Main Power/Logs/Reactor), then
    `route_control_state.get_status_lines()` (Routes/Extraction), then
    **`oxygen_state.get_status_lines()`** (`Oxygen:` + `Breach:` — the duplication),
    then **`inventory_state.get_status_lines()`** (`Tool:`/`tool=`/`item=` +
    a trailing **`weight=`** line — the duplication), then `Repair Skill:`.
    Exposed publicly via `get_combined_system_status_lines()` /
    `get_combined_system_status_lines_contains(token)`.
  - `_refresh_player_vitals(delta)` (≈L3189) drives `vitals_model` from
    `oxygen_state`, `inventory_state`, and channeling `repair_points`, then pushes
    `vitals_model.get_status_lines()` to `vitals_panel`. The vitals oxygen line is
    `Oxygen: N (BREACH)` / `(SEALED)` / trailing ` LOW`; load is `Load: P%` or
    `Load: P% HEAVY (-M% move)`.
  - `apply_accessibility_settings(settings)` (≈L306) stores the settings and
    pushes them into `tracker` only. The HUD-build path (≈L2349) calls
    `tracker.apply_accessibility_settings(accessibility_settings)` after the
    tracker is built. `vitals_panel` is never given the settings.
- **`oxygen_state.get_status_lines()`** / **`inventory_state.get_status_lines()`**:
  pure-model methods. Their full output is asserted by their own model smokes
  (`oxygen_state_smoke`, inventory smokes) and must stay unchanged.
- **Smoke consumers of the tracker block (verified):** only
  `main_playable_slice_hazard_smoke.gd` reads `Oxygen:`/`Breach:` from
  `get_combined_system_status_lines()`. `main_playable_slice_progression_smoke`
  reads `Repair Skill:`, `main_playable_slice_inventory_smoke` and
  `main_playable_slice_junction_calibrator_smoke` read `Tool:`/calibrator lines —
  all tokens this spec **keeps**. No smoke asserts `weight=` against the tracker
  (`ship_inventory_smoke`'s `weight=` is only its own PASS-marker string).
- **`main_playable_slice_hud_smoke.gd`**: asserts the tracker is parented through
  the `CanvasLayer`, sized correctly, and that `get_hud_text()` contains
  `Synapse Sea First Playable`, `Current: 01 Recover Supplies`, the Controls line,
  and `Progress: 0/4`. Marker `MAIN PLAYABLE SLICE HUD PASS …`. **Not** in the
  regression bundle.
- **`main_playable_slice_text_scale_smoke.gd`**: instantiates the main scene and
  runs three sequential passes (1.0 / 1.5 / 2.0×) against the SAME live instance,
  calling `playable.apply_accessibility_settings(settings)` between passes and
  asserting the tracker font + `custom_minimum_size` and world-label `pixel_size`.
  Marker `MAIN PLAYABLE TEXT SCALE PASS …`. Already in the bundle.
- **Regression bundle** (`docs/game/06_validation_plan.md`): tail marker
  `SYNAPSE_SEA REGRESSION PASS commands=119 clean_output=true`.

## Decisions

1. **Vitals panel is the sole home for player oxygen + load.** Remove the
   `Oxygen:`, `Breach:`, and `weight=` lines from the tracker entirely (user
   decision). The tracker keeps objectives, ship systems, Routes/Extraction,
   carried `Tool:`/`item=` lines (REQ-007), and `Repair Skill:`.
2. **De-dup by filtering in the coordinator, not by editing the models.** Leave
   `oxygen_state.get_status_lines()` and `inventory_state.get_status_lines()`
   untouched (their model smokes assert full output). In
   `_combined_system_status_lines()`: delete the `oxygen_state.get_status_lines()`
   append outright, and when copying `inventory_state.get_status_lines()`, skip
   the single line beginning with `weight=`. Rejected alternative: adding
   `inventory_state.get_hud_tool_lines()` — new API for one caller (YAGNI).
3. **Repoint the hazard smoke's HUD-reflection assertions to the vitals panel.**
   `main_playable_slice_hazard_smoke.gd` already reads numeric oxygen from
   `get_oxygen_summary()` (unchanged); only its "HUD shows oxygen" assertions
   read the tracker block. Repoint those to `get_player_vitals_lines()`. Mapping:
   the separate `Breach: OPEN`/`Breach: SEALED` line → the vitals oxygen line's
   embedded `(BREACH)`/`(SEALED)`; the `Oxygen:`-prefix check still holds (vitals
   line is `Oxygen: N (…)`). The test still proves the runtime tick drains oxygen
   AND that the HUD reflects it, now against the panel that owns oxygen. Marker
   `MAIN PLAYABLE HAZARD PASS` unchanged.
4. **Register the orphaned HUD smoke.** Add one `run_clean` line for
   `main_playable_slice_hud_smoke.gd` and bump the tail marker to
   `commands=120`. It asserts only objective/control tokens, so Decision 1 does
   not affect it.
5. **Vitals-panel accessibility parity mirrors the tracker.** `PlayerVitalsPanel`
   gains an owned `accessibility_settings` (default scale 1.0 ⇒ identical pixels),
   `BASE_*` constants, and an idempotent `apply_accessibility_settings(settings)`
   that rescales font + label min-size + panel size in place. The coordinator
   pushes the same settings into `vitals_panel` alongside the tracker (in
   `apply_accessibility_settings()` and the HUD-build path), guarded by
   `is_instance_valid` + `has_method`.
6. **Bottom-anchor scaling.** Because the panel is `PRESET_BOTTOM_LEFT`, scaling
   its height naively pushes it off the bottom edge. The Y offset is computed
   from the scaled height: `position.y = -(scaled_panel_height + BOTTOM_MARGIN)`
   (`BOTTOM_MARGIN = 18`). The panel grows upward from a fixed bottom margin. The
   X offset (18) is unscaled.
7. **No model, coordinator-logic, or persistence change beyond the above.** The
   vitals model, oxygen/inventory models, save format, and gameplay are untouched.

## Architecture & Data Flow

```
ObjectiveTracker (top-left)          PlayerVitalsPanel (bottom-left)
  objectives                           Oxygen: N (BREACH|SEALED) [LOW]
  Systems:                             Suit: -P% O2 drain
    Power / Reactor / Supplies         Load: P% [HEAVY (-M% move)]
    Routes / Extraction                Repairing P%  |  Repair blocked: …
    Tool: … / item= …                ^ sole home for oxygen + load
    Repair Skill: N
  ^ no Oxygen:/Breach:/weight=

_combined_system_status_lines():       apply_accessibility_settings(settings):
  - drop oxygen_state lines              tracker.apply_accessibility_settings(settings)
  - inventory lines minus `weight=`      if is_instance_valid(vitals_panel) and
  - keep systems/routes/skill              vitals_panel.has_method(...):
                                             vitals_panel.apply_accessibility_settings(settings)
```

## Components / Files

### Modify `scripts/procgen/playable_generated_ship.gd`
- `_combined_system_status_lines()`: remove the `oxygen_state.get_status_lines()`
  append; filter the `weight=` line out of the `inventory_state.get_status_lines()`
  copy. Comment that oxygen + load now live in `PlayerVitalsPanel`.
- `apply_accessibility_settings(settings)` (≈L306): after pushing to `tracker`,
  push the same settings to `vitals_panel` (guard `is_instance_valid` +
  `has_method`).
- HUD-build path (≈L2349): after building/wiring `vitals_panel`, call
  `vitals_panel.apply_accessibility_settings(accessibility_settings)`.

### Modify `scripts/ui/player_vitals_panel.gd`
- Add `const AccessibilitySettingsScript := preload(...)` and an owned
  `accessibility_settings: RefCounted = AccessibilitySettingsScript.new()`.
- Rename `PANEL_SIZE` → `BASE_PANEL_SIZE`, `LABEL_MIN_SIZE` → `BASE_LABEL_MIN_SIZE`,
  `HUD_FONT_SIZE` → `BASE_HUD_FONT_SIZE`; add `const BOTTOM_MARGIN: float = 18.0`
  and `const LEFT_MARGIN: float = 18.0`.
- `_ensure_nodes()` / layout: derive `scaled_panel = scaled_hud_panel_size(BASE_PANEL_SIZE)`,
  `scaled_label_min = scaled_hud_minimum_size(BASE_LABEL_MIN_SIZE)`,
  `scaled_font = scaled_hud_font_size(BASE_HUD_FONT_SIZE)`; set
  `custom_minimum_size`/panel size/label min-size/font from those; set
  `position = Vector2(LEFT_MARGIN, -(scaled_panel.y + BOTTOM_MARGIN))`.
- Add `apply_accessibility_settings(settings)`: store (ignore null), then
  re-apply font + label min-size + panel size + position in place; idempotent.
  Default scale 1.0 reproduces today's `(360,150)` / `(320,0)` / `18` / y=−168.

### Modify `scripts/validation/main_playable_slice_hazard_smoke.gd`
- Replace the tracker-block oxygen/breach HUD-reflection reads with
  `playable.get_player_vitals_lines()`: the line beginning `Oxygen:` is the
  vitals oxygen line; assert it `contains("(BREACH)")` where the test asserted
  `Breach: OPEN`, and `contains("(SEALED)")` where it asserted `Breach: SEALED`.
  The `_first_status_line_starting_with("Oxygen:")` helper reads vitals lines.
  Numeric assertions via `get_oxygen_summary()` are unchanged. Marker unchanged.
  **Cadence dependency:** `get_player_vitals_lines()` reflects the vitals model,
  which `_refresh_player_vitals` updates on a `_process` tick. The smoke already
  waits `DRAIN_WAIT_FRAMES` between mutation and read, so the model is current —
  but the implementer MUST confirm the repointed line actually changes across the
  drain frames (the prior tracker assertion `hud_line_after_drain != hud_line_before`
  has a vitals-line equivalent) when running the smoke, not just that it passes the
  prefix check.

### Modify `scripts/validation/main_playable_slice_text_scale_smoke.gd`
- In each of `_validate_default_scale` / `_validate_15x_scale` / `_validate_20x_scale`,
  also assert `playable.vitals_panel` is present and its label font_size ==
  `round(18 × scale)` and its `custom_minimum_size == (360,150) × scale`. The
  three `_apply_scale` calls already drive `apply_accessibility_settings` in
  place; Decision 5 makes those reach the panel. Marker unchanged.

### Modify `docs/game/06_validation_plan.md`
- Add a `run_clean` line for `main_playable_slice_hud_smoke.gd`
  (marker `MAIN PLAYABLE SLICE HUD PASS`) near the other main-slice HUD smokes.
- Bump the tail marker: `commands=119` → `commands=120`.

### Docs
- New `docs/game/adr/0027-vitals-hud-cleanup.md`: records the single-home HUD
  decision (vitals panel owns oxygen + load; tracker owns objectives + ship
  systems + tools + skill), the coordinator-side de-dup, the hazard-smoke
  repoint, the registered HUD smoke, and vitals-panel A11Y parity. Supersedes
  the duplicated-line note implicit in ADR-0025.
- `docs/game/09_system_roadmap.md`: under System 6, note the vitals/HUD cleanup
  (de-dup + A11Y parity + bundle 120) shipped; cite ADR-0027.

## Testing & Validation

- `main_playable_slice_hazard_smoke` prints `MAIN PLAYABLE HAZARD PASS` with the
  repointed vitals-panel oxygen/breach assertions.
- `main_playable_slice_hud_smoke` prints `MAIN PLAYABLE SLICE HUD PASS` and is now
  in the bundle.
- `main_playable_slice_text_scale_smoke` prints `MAIN PLAYABLE TEXT SCALE PASS`
  with the added vitals-panel scale assertions at 1.0/1.5/2.0×.
- `main_playable_slice_vitals_hud_smoke` (`MAIN PLAYABLE VITALS HUD PASS`) stays
  green — the vitals panel's rendered text is unchanged at default scale.
- Full regression bundle green at **`commands=120 clean_output=true`** (stash
  `project.godot` drift before the run, pop after; never commit `project.godot` /
  `.godot/` / `*.uid` / `addons/`).
- Gate-1 automated playtest still `GO`.

## Out of Scope (explicit)

- A settings menu or persisted text-scale choice (the A11Y seam stays env/project-
  setting driven per A11Y-P1-001).
- Any change to the vitals model's line formats or content.
- Re-homing REQ-007 tool surfacing (tools stay in the tracker).
- The other System 6 remaining items (item icons, drag-out-to-unequip,
  gamepad/keyboard grid nav, drop-target highlight, split UX polish,
  encumbrance depth).
