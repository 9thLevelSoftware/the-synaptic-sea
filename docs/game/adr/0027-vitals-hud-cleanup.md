# ADR-0027: Vitals/HUD cleanup — single-home oxygen/load, bundle + A11Y parity

Date: 2026-06-25
Status: Accepted
Supersedes (in part): the duplicated player-vitals lines implicit in ADR-0025.

## Context

The player-vitals slice (ADR-0025) added a bottom-left PlayerVitalsPanel that
renders oxygen, suit effect, load, and repair progress. The top-left
ObjectiveTracker still redundantly mirrored a terse `Oxygen:` line, a `Breach:`
line, and an inventory `weight=` line via `_combined_system_status_lines()`. The
orphaned `main_playable_slice_hud_smoke` was never registered in the regression
bundle, and the vitals panel — unlike the tracker — ignored the A11Y-P1-001
`AccessibilitySettings` text-scale seam.

## Decision

1. **The vitals panel is the sole home for player oxygen + load.** The tracker's
   combined status block drops `Oxygen:`, `Breach:`, and `weight=`. It keeps
   objectives, ship-system status, Routes/Extraction, carried `Tool:`/`item=`
   lines (REQ-007), and `Repair Skill:`. The de-dup is a coordinator-side filter;
   the pure models (`oxygen_state`, `inventory_state`) are unchanged so their
   model smokes still assert full output.
2. **The hazard smoke reads oxygen/breach from the vitals panel.** Its
   HUD-reflection assertions repoint to `get_player_vitals_lines()` (mapping the
   old separate `Breach: OPEN/SEALED` line to the vitals oxygen line's embedded
   `(BREACH)`/`(SEALED)`, and the zero-drive `BLOCKED` check to a "reflects zero"
   check since the vitals line has no BLOCKED token). Numeric drain/seal/recovery
   assertions still read `get_oxygen_summary()`.
3. **`main_playable_slice_hud_smoke` is registered** in the regression bundle
   (commands 119 → 120).
4. **PlayerVitalsPanel reaches A11Y parity** with ObjectiveTracker: it scales
   font/panel/label from the `AccessibilitySettings` seam, the coordinator pushes
   settings into it alongside the tracker, and the text-scale smoke asserts its
   scaling at 1.0/1.5/2.0×. Because the panel is bottom-anchored, its Y offset is
   computed from the scaled height so it grows upward instead of overflowing.

## Consequences

- Each player-vitals fact appears in exactly one HUD location.
- A top-left HUD regression is now guarded by a bundled smoke.
- Text-scale accessibility now covers both HUD panels.
- No model, gameplay, or world-4 persistence change; default scale (1.0) is
  pixel-identical to before.
