# UI/UX, HUD, Menus, Tutorials, Controller & Accessibility

Production UI shell for The Synaptic Sea. This feature covers the
top-level player-facing surface: main menu → pause menu → in-play HUD →
settings menu → codex / minimap / tooltip / tutorial systems. Every
menu is navigable by keyboard, mouse, and gamepad. Settings persist
through save/load. Tutorials trigger once, can be skipped, and unlock
codex entries.

## Source

- Build plan: `docs/game/build-plans/09-ui-ux-accessibility-e2e.md`
- ADR: `docs/game/adr/0033-ui-ux-accessibility-architecture.md`
- Requirements: REQ-UI-001..016 in `docs/game/05_requirements.md`
- Validation plan: `docs/game/06_validation_plan.md`

## Concept lock

Project Zomboid-style moodle / status readability, health panel,
inventory, map/FOW, and contextual survival feedback — adapted to
locked-isometric 3D space-horror survival aboard derelict ships trapped
in a biomatter Sargasso field.

Every mechanic must read as locked-isometric, in-character, and
production-grade. Placeholder art is acceptable so long as readability
is maintained.

## Player-facing surface

### Main menu
- New Run
- Continue (greyed when no save exists)
- Settings
- Quit

### Pause menu (in-play)
- Resume
- Settings
- Codex
- Save (only when an autosave or manual save exists)
- Quit to Main Menu

### Settings menu
- Accessibility
  - Text Scale: 1.0x / 1.5x / 2.0x (radio)
  - Colorblind Mode: None / Protanopia / Deuteranopia / Tritanopia
  - Reduced Motion: Off / On
  - Captions: Off / On
- Gameplay
  - Hold-to-Tap: Off / On (interact press becomes release)
  - Difficulty: Standard / Hardened / Deep Dive
- Input
  - Controller Glyph Scheme: Auto / Keyboard / Xbox / PlayStation

### HUD (in-play)
- Top-left: Objective tracker
- Bottom-left: Player vitals panel
- Top-right: Minimap (with fog-of-war)
- Bottom-center: Hotbar (5 slots)
- Center: Context prompt (ToolTipPresenter-driven)
- Top-center: Tutorial banner (transient; 5s default)
- Bottom-right: Codex hint glyph (when a new codex entry is unlocked)

### Codex
- Topic list (categorised)
- Entry list per topic
- Selected entry shows transcript

### Minimap
- Per-room footprint (5×5 grid sample)
- Fog-of-war overlay (unrevealed rooms render as dark cells)
- Player position marker
- Optional objective room markers (gold)

## Functional contract

- Every menu is reachable from the main menu and (where relevant) from
  the pause menu.
- Back navigation pops one menu off the stack; closing the topmost menu
  returns the player to the previous menu or to in-play (when the pause
  menu is closed).
- Settings changes apply immediately (text scale cascades through
  `AccessibilitySettings` to every HUD node).
- Tutorial triggers fire once per `(event, target)` pair per run; the
  same trigger on a second event does not re-fire.
- Tutorials can be dismissed via the "Skip" button or by holding the
  dismiss action for 2 seconds; dismissed tutorials still unlock the
  matching codex entry.
- Codex entries unlocked via `tutorial_state.unlock_codex(id)` are
  available in the codex panel immediately and persist through save/load.
- Map fog of war advances one room per interact (every room the player
  walks into is `discovered` and `revealed`; rooms adjacent to revealed
  rooms are `discovered` but not `revealed`).
- Controller glyph resolution reads the **actually bound** keycode at
  boot, so swapping input bindings updates the glyph on the next menu
  open.

## Acceptance criteria

1. Main menu lists Start / Continue / Settings / Quit. Continue is
   disabled when no save exists.
2. Pause menu lists Resume / Settings / Codex / Save / Quit to Main.
3. Settings menu lists Accessibility / Gameplay / Input submenus.
4. Every menu is reachable from keyboard + mouse + gamepad and back
   navigation always returns to the prior menu.
5. Text scale change applies immediately to every HUD panel and
   persists across save/load.
6. Reduced Motion toggle disables transient banner animations.
7. Colorblind mode swaps the objective / hazard color palette.
8. Hold-to-Tap toggle swaps interact between press and release.
9. Difficulty toggle updates the gameplay difficulty multiplier; this
   surfaces in pause-menu / codex / tooltip text but does not retroactively
   change live hazard state (an explicit reload is required).
10. Controller glyph reflects the bound action + selected scheme.
11. Tutorial banner appears on first trigger and disappears after 5s,
    on dismiss, or on a new trigger.
12. Codex is reachable from the pause menu and lists every unlocked
    entry.
13. Minimap shows the player position and the fog-of-war overlay.
14. Save/load round-trips the settings state; the loaded settings
    match the saved settings field-for-field.

## Out of scope

- Final art assets beyond placeholder rects (Gate 3 follow-up).
- Controller rumble / haptics.
- VR / screen-reader integration.
- Localised UI strings (the strings flow through `LocalizationCatalog`,
  but this package does not ship translated strings).
- Steamworks / cross-run achievement surface (covered by REQ-RL-003).