# UI/UX, HUD, Menus, Tutorials, Controller & Accessibility — Tuning

Tuning numbers for the UI / UX package. Every number is stored in a
data resource / JSON file, never as a magic constant in code.

## Text scale

| Preset | Multiplier | Notes |
|---|---|---|
| 1.0x (default) | 1.0 | Reproduces the pre-A11Y-P1-001 hard-coded sizes pixel-for-pixel. |
| 1.5x | 1.5 | Mid-size for partial-vision players. |
| 2.0x (max) | 2.0 | Upper bound; beyond this the panels overflow the viewport at 1280×720. |

## Reduced motion

| Setting | Behaviour |
|---|---|
| off (default) | Tutorial banner slides in over 0.4s, fades out over 0.6s. |
| on | Tutorial banner appears instantly, fades out over 0.6s. No slide-in. |

## Colorblind modes

| Mode | Palette swap |
|---|---|
| none (default) | Default palette; objective = gold, hazard = red, safe = green. |
| protanopia | Objective = blue, hazard = magenta, safe = cyan. |
| deuteranopia | Objective = yellow, hazard = magenta, safe = cyan. |
| tritanopia | Objective = magenta, hazard = red, safe = green. |

The palette is applied via a single `theme` swap on the HUD layer;
panels read `AccessibilitySettings.colorblind_mode` and pick the
matching palette from a static `data/ui/colorblind_palettes.json`
catalog.

## Hold-to-tap

| Setting | Behaviour |
|---|---|
| off (default) | Tap-to-interact (one interact press). |
| on | Hold-to-interact (interact press is consumed on release within a 0.5s window; longer presses revert to tap behaviour). |

## Difficulty

| Preset | Multiplier | Effect |
|---|---|---|
| standard (default) | 1.0 | Baseline hazard drain / spawn rate / loot quality. |
| hardened | 1.5 | Hazard drain ×1.5, spawn rate ×1.25, loot quality ÷1.25. |
| deep_dive | 2.0 | Hazard drain ×2.0, spawn rate ×1.5, loot quality ÷1.5. |

Multipliers surface in the pause menu, codex, and tooltip text.
They do not retroactively change live hazard state (an explicit reload
is required).

## Captions

| Setting | Behaviour |
|---|---|
| off | Captions suppressed. |
| on (default) | Captions shown for SFX events with a caption mapping (REQ-AU-009). |

## Glyph scheme

| Scheme | Behaviour |
|---|---|
| auto (default) | Pick `gamepad_xbox` when a gamepad is connected, `keyboard` otherwise. |
| keyboard | Force keyboard glyphs in prompts. |
| gamepad_xbox | Force Xbox glyphs (A / B / X / Y) in prompts. |
| gamepad_ps | Force PlayStation glyphs (Cross / Circle / Square / Triangle) in prompts. |

## Tooltip footer format

Default: `[glyph] [action_label]` — e.g. `[E] Interact`, `[Tab] Toggle Scanner`.
The footer format is overridable per-catalog entry (the catalog entry
may set `footer_override`).

## Tutorial banner timing

| Setting | Value |
|---|---|
| Default banner duration | 5.0s |
| Dismiss action | KEY_BACKSPACE + gamepad X (default) |
| Reduced-motion slide-in duration | 0.0s (disabled) |
| Normal slide-in duration | 0.4s |

## Minimap

| Setting | Value |
|---|---|
| Cell size | 24 px |
| Revealed cell alpha | 1.0 |
| Discovered cell alpha | 0.5 |
| Undiscovered cell alpha | 0.15 |
| Player position marker | 6 px diameter, gold |
| Objective room marker | 4 px diameter, gold outline |

## Codex

| Setting | Value |
|---|---|
| Default topic list | "Survival", "Ship Systems", "Combat", "Exploration", "Items" |
| Topic sorting | Alphabetical by topic name |
| Entry sorting | Alphabetical by entry title within topic |