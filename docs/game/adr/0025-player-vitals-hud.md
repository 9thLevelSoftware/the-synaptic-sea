# ADR-0025: Player Vitals HUD Panel

Date: 2026-06-24
Status: Accepted
Phase: 7 (Integration & Polish), sub-project C

## Context

Three runtime states the models already computed were invisible in real play:
active repair progress (`RepairPoint.progress`) and its `repair_blocked` reason,
the worn-suit oxygen-drain contribution (ADR-0024's `equipment_drain_multiplier`),
and the Heavy-Load movement penalty (`Encumbrance.move_speed_multiplier`). The
objective tracker's flat "Systems:" block was already ~13 unsectioned lines.

## Decision

A dedicated, always-on **`PlayerVitalsPanel`** (`Control`, bottom-left, under the
existing `hud_layer`) renders player vitals, distinct from the objective tracker.
A pure **`PlayerVitalsModel`** (`RefCounted`, no scene tree, no persistence) owns
the formatting/warning rules and a transient blocked-message timer driven by the
per-frame `delta`. The coordinator bridges the four sources (oxygen summary,
inventory load, channeling `RepairPoint`, `repair_blocked` signal) into the model
inside its existing `_refresh_oxygen_state` cadence and pushes
`get_status_lines()` to the panel.

Output is ASCII-only (Windows headless console + smoke grep contracts).

## Additive stance

The objective tracker and `get_combined_system_status_lines()` are unchanged. The
four main-scene smokes assert oxygen/breach/weight tokens against that coordinator
getter, and `main_playable_slice_hazard_smoke.gd` is tightly coupled to the
oxygen/breach lines living there; moving them would force a hazard-smoke rewrite,
out of proportion for a polish slice. The bare `Oxygen: N` value therefore appears
both on the tracker (terse) and the vitals panel (player-facing); the panel earns
its place with the new info the tracker never had.

## Consequences

- Suit, Heavy-Load, and live repair status are now visible in play.
- Two new smokes (`player_vitals_model_smoke`, `main_playable_slice_vitals_hud_smoke`);
  regression bundle 117 -> 119.

## Deferred follow-ups

- Remove the redundant terse `Oxygen:`/`weight=` lines from the objective tracker
  and repoint `main_playable_slice_hazard_smoke.gd` (eliminates the duplication).
- Accessibility-scaling parity for the vitals panel (`apply_accessibility_settings`),
  matching the objective tracker's A11Y-P1-001 seam.
