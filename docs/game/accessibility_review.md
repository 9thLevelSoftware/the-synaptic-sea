# Accessibility Review

Date: 2026-06-19; final Gate 4 pass accepted 2026-06-20
Reviewer: `synapse_sea_review`
Scope: basic accessibility pass for the current Synapse Sea playable slice, Gate 4 readiness planning, and final Gate 4 accessibility acceptance.

## Summary

This review found no P0 accessibility issue and no P0 issue without a workaround. The current build has a readable high-contrast HUD, scalable HUD/world text, keyboard-only movement/interaction with alternate keyboard bindings, visible state for the currently implemented hazards, and a low-risk orthographic locked-isometric camera with no shake or rotation.

P1 accessibility items tracked as Kanban cards:

| ID | Severity | Finding | Kanban card | Disposition |
|---|---|---|---|---|
| A11Y-P1-001 | P1 | HUD/world text was hard-coded and not scalable. | `t_18c36407` — P1 accessibility: add scalable HUD and world text | Closed: `AccessibilitySettings` scales HUD font/panel and world `Label3D.pixel_size`; default, 1.5x, and 2.0x are covered by `main_playable_slice_text_scale_smoke.gd`. |
| A11Y-P1-002 | P1 | Controls are keyboard-only but hard-coded to a narrow WASD/E/F5/F9 layout with no alternate bindings or remap seam. | `t_ec529103` — P1 accessibility: add alternate keyboard bindings or remap seam | Closed: alternate bindings added in `scripts/procgen/playable_generated_ship.gd` (`ensure_default_input_actions()`). |

P0 stop condition: not triggered. A11Y-P1-001 and A11Y-P1-002 are closed, and the final Gate 4 accessibility pass (`t_d9d85bad`) is accepted.

## Evidence reviewed

Source/code review:

- `scripts/ui/objective_tracker.gd`
  - HUD panel is a dark `PanelContainer` with white label text and black shadow.
  - HUD dimensions and label font size are now derived from `AccessibilitySettings`; the baseline constants (`BASE_HUD_SIZE = Vector2(520, 250)`, `BASE_HUD_FONT_SIZE = 18`) reproduce the prior 1.0x layout, and `apply_accessibility_settings()` can scale them in place.
  - The player-facing controls line now says `Controls: WASD or Arrows move / E or Enter or Space interact / F5 save / F9 load`.
- `scripts/procgen/playable_generated_ship.gd`
  - Runtime input actions are injected for `move_forward=W/Up`, `move_back=S/Down`, `move_left=A/Left`, `move_right=D/Right`, `interact=E/Enter/Space/KP_Enter`, `save_run=F5`, and `load_run=F9`.
  - Oxygen, fire, and electrical-arc hazards have visible world labels plus collision/passability state.
  - World `Label3D.pixel_size` values now flow through the shared `AccessibilitySettings` seam; default 1.0x reproduces the prior `0.003` / `0.0035` values, while larger text scales reduce pixel size consistently.
  - Camera is an orthographic locked-isometric rig following the player with a fixed offset and fixed camera size.
- `scripts/camera/iso_camera_rig.gd`
  - Camera projection is orthographic, `DEFAULT_OFFSET = Vector3(16, 18, 16)`, and `DEFAULT_SIZE = 22`.
  - No camera rotation, shake, FOV changes, or zoom transitions were found.
- `project.godot`
  - No persistent input map entries were found; actions are registered at runtime.
- Audio search:
  - No runtime `AudioStreamPlayer`, `AudioStreamPlayer2D`, `AudioStreamPlayer3D`, or equivalent critical gameplay audio cue path was found in the gameplay scripts/scenes reviewed.

Baseline focused validation run during initial review:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_input_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_readability_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/objective_progress_hud_label_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_hazard_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_fire_smoke.gd
```

Observed pass markers:

- `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2`
- `MAIN PLAYABLE SLICE READABILITY PASS objective_props=5 blocked=1 ramp=1 entry=1 destination=1 route_cues=4 labels=0`
- `OBJECTIVE PROGRESS HUD LABEL PASS repair_junction=Repair_junction restore_systems_suppressed=true sequence_3=Download_Logs`
- `MAIN PLAYABLE HAZARD PASS oxygen=0.04861111111111 breach_open=false breach_sealed=true passability_blocked=false drain_consumed=8.29999999999988 regen_recovered=6.7302753333333`
- `MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false`

Only the already-classified baseline Godot teardown lines appeared after each smoke:

- `ERROR: Capture not registered: 'gdaimcp'.`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

Contrast spot-checks for coded colors:

| Pair | Approximate contrast |
|---|---:|
| HUD white text on panel base | 19.54:1 |
| HUD complete green on panel base | 14.99:1 |
| HUD cyan border on panel base | 8.78:1 |
| Oxygen/fire red label with black outline/shadow | 6.50:1 |
| Fire-cleared cyan label with black outline/shadow | 10.03:1 |

## Area findings

### 1. Color contrast — are HUD elements readable?

Disposition: acceptable for the current slice; no P0/P1 issue.

Findings:

- The HUD uses a dark translucent panel, white text, black text shadow, and a cyan border. The coded foreground/background color ratios are comfortably above common 4.5:1 body-text targets when measured against the panel base color.
- The completed-run green text still has high contrast against the panel base.
- Critical hazard labels use high-saturation colors and black outlines. The red and cyan label spot checks remain above 4.5:1 against black outlines.
- World affordances rely on shape and placement as well as color: objectives use distinct mesh compositions, blocked routes use biomatter props, ramps use directional cue props, and route cues use arrow/strip geometry.

Gaps / follow-up:

- No P1 color-contrast card is required from this pass.
- Future visual polish should avoid relying on hue alone for new hazard/tool states; use text, iconography, geometry, or HUD lines for every critical state.

### 2. Text size — is UI text scalable?

Disposition: closed for Gate 4. The baseline finding below was a P1 gap; card `t_18c36407` resolved it.

Baseline finding A11Y-P1-001:

- HUD text size is fixed at `18` in `ObjectiveTracker`, and the HUD panel/minimum sizes are fixed.
- World-space `Label3D` affordance/hazard labels use fixed pixel sizes.
- No runtime setting, project setting, exported scale, or validation smoke proves enlarged text.

Baseline impact:

- Before the fix, low-vision users might not have been able to read objective status, prompts, hazard labels, or state updates without OS/window magnification.
- This did not break the core loop because the smokes proved HUD state and objective labels were present, but it was a significant accessibility gap for Gate 4 until `t_18c36407` closed it.

Tracking:

- Kanban: `t_18c36407` — P1 accessibility: add scalable HUD and world text.

Resolution (2026-06-20): A11Y-P1-001 closed. The runtime `AccessibilitySettings` seam now drives HUD `font_size`, HUD/panel minimum size, and world `Label3D.pixel_size` for the breach marker and fire label. Fresh focused evidence from `scripts/validation/main_playable_slice_text_scale_smoke.gd` reports `A11Y TEXT SCALE DEFAULT PASS font=18 panel=(520.0, 250.0) marker_pixel=0.0035 fire_pixel=0.0035`, `A11Y TEXT SCALE 1.5X PASS font=27 panel=(780.0, 375.0) marker_pixel=0.002333 fire_pixel=0.002333`, `A11Y TEXT SCALE 2.0X PASS font=36 panel=(1040.0, 500.0) marker_pixel=0.001750 fire_pixel=0.001750`, and `MAIN PLAYABLE TEXT SCALE PASS scales=3 default=1.0x1.5x2.0 runtime_text=present`.

### 3. Input alternatives — are there keyboard-only controls?

Disposition: closed for Gate 4. Keyboard-only controls exist, and alternate keyboard bindings are now validated.

Findings:

- Keyboard-only movement and interaction exist through `W/A/S/D` and `E`.
- Manual save/load also has keyboard paths (`F5` / `F9`).
- The focused input smoke proves movement, camera follow, and interaction advance the run.

Baseline finding A11Y-P1-002:

- The accepted controls are hard-coded at runtime and not persisted in `project.godot`.
- No alternate keyboard layout (arrow keys, Enter/Space, etc.), controller path, or remap UI/seam is currently documented or validated.
- HUD prompt only advertises `WASD move / E interact`, so even if additional bindings are added later, discoverability must be updated.

Baseline impact:

- Before the alternate-binding seam, players who could not comfortably use WASD/E, used non-QWERTY layouts, or needed one-handed/adaptive keyboard layouts needed OS/external key remapping.
- The original keyboard-only path meant this was not P0, but it was a P1 accessibility gap for Gate 4 until `t_ec529103` closed it.

Tracking:

- Kanban: `t_ec529103` — P1 accessibility: add alternate keyboard bindings or remap seam.

Resolution (2026-06-19; re-verified 2026-06-20): A11Y-P1-002 closed. The runtime input seam in `scripts/procgen/playable_generated_ship.gd` (`ensure_default_input_actions()`) now registers both original and alternate keycodes on the same InputMap actions: movement uses `W/A/S/D` plus arrow keys (`Up/Down/Left/Right`), interaction uses `E` plus `Enter`, `Space`, and keypad `Enter`, and manual save/load remain `F5`/`F9`. Evidence: the focused smoke `scripts/validation/main_playable_slice_alternate_input_smoke.gd` reports `MAIN PLAYABLE ALTERNATE INPUT PASS moves_alt=1 interact_alt=1` and confirms the HUD prompt advertises `WASD or Arrows` plus `E or Enter or Space`; the event-path smoke `scripts/validation/playable_slice_alternate_input_smoke.gd` reports `PLAYABLE SLICE ALTERNATE INPUT EVENTS PASS static_bindings=ok moves_alt=1 interact_alt=3 enter=1 space=1 kp_enter=1`. The current 29-command regression bundle defined in `docs/game/06_validation_plan.md` passes clean with only accepted baseline `ERROR:`/`WARNING:` lines and the expected REQ-012 contract warning.

### 4. Audio cues — are critical events also visible?

Disposition: acceptable for current slice; no P0/P1 issue.

Findings:

- No critical gameplay audio-only cue path was found. The current runtime does not appear to depend on audio for objective completion, hazard state, route gating, extraction, save/load, or input feedback.
- Critical events have visible evidence paths:
  - Objective/progress state: HUD text from `ObjectiveTracker`.
  - Oxygen hazard: HUD oxygen/breach lines, `OXYGEN LOW` world label, breach-zone visual, and collision/passability state.
  - Fire hazard: `FIRE CLEARED` / `FIRE BURNING — WAIT` world label, fire-zone visual color, and collision/passability state.
  - Route gates/extraction: HUD route/extraction lines plus world route/blocked affordances.

Gaps / follow-up:

- No P1 card is required unless future work adds audio cues that become gameplay-critical.
- Future audio work should include captions/subtitles or matching HUD/world visual cues at the same time the cue is introduced.

### 5. Camera — can the locked-isometric view cause motion sickness?

Disposition: low current risk; P2/future comfort gap, not P0/P1.

Findings:

- The camera is orthographic, fixed-angle, fixed-size, and locked-isometric.
- It follows the player by maintaining a fixed offset and looking at the player every frame.
- No camera shake, FOV kick, rotation, bob, or animated zoom was found.
- The input smoke proves the camera follows the player during movement.

Risk assessment:

- Current motion-sickness risk is lower than a rotating, bobbing, or perspective chase camera because the view is orthographic and stable.
- There is still no player-facing comfort option for camera scale/zoom, follow mode, or reduced motion. This is a good Beta polish target, but not a P1 in the current slice because no strong motion trigger was found and the current implementation is stable.

## Final Gate 4 accessibility pass (2026-06-20)

Fresh focused validation for card `t_d9d85bad` passed all required accessibility smokes:

- `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2`
- `MAIN PLAYABLE SLICE READABILITY PASS objective_props=5 blocked=1 ramp=1 entry=1 destination=1 route_cues=4 labels=0`
- `OBJECTIVE PROGRESS HUD LABEL PASS repair_junction=Repair_junction restore_systems_suppressed=true sequence_3=Download_Logs`
- `MAIN PLAYABLE TEXT SCALE PASS scales=3 default=1.0x1.5x2.0 runtime_text=present`
- `MAIN PLAYABLE ALTERNATE INPUT PASS moves_alt=1 interact_alt=1`

The current full regression bundle in `docs/game/06_validation_plan.md` also passed with `SYNAPSE_SEA REGRESSION PASS commands=29 clean_output=true`. The only `ERROR:`/`WARNING:` lines observed were the accepted Godot teardown baseline lines (`Capture not registered: 'gdaimcp'`, `ObjectDB instances leaked at exit`) plus the expected REQ-012 incompatible-save contract warning.

## Gate and backlog implications

- Gate 4 accessibility pass is accepted: A11Y-P1-001 (`t_18c36407`) and A11Y-P1-002 (`t_ec529103`) are closed with fresh focused and full-regression evidence.
- No unresolved P0/P1 accessibility blocker remains in the current reviewed slice.
- No P0 accessibility blocker was found in this pass.
- No P0 issue without a workaround was found, so the task stop condition is not triggered.
- This document is cited from `docs/game/08_milestone_gates.md` Gate 4 section.
