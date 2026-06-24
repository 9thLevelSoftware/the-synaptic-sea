# Phase 7 Sub-Project C — Player Vitals HUD Panel (Design Spec)

Date: 2026-06-24
Status: Approved (brainstorm)

## Goal

Surface live runtime player-state on-screen that the models already compute but never show.
Three readouts, in priority order:

1. **Active repair** — `RepairPoint.progress` (the live channel %) and the `repair_blocked`
   rejection reason. Fully absent from the HUD today (only the static `Repair Skill: N` is shown).
2. **Suit oxygen contribution** — ADR-0024 wired `EquipmentState.get_oxygen_drain_multiplier()`
   into `OxygenState`, but the suit's effect is invisible to the player; ADR-0024 explicitly
   deferred HUD surfacing to this slice.
3. **Encumbrance / Heavy Load** — the player's load ratio is known and `Encumbrance.move_speed_multiplier`
   computes the movement penalty, but the penalty state is never called out (the existing
   `weight=X/Y` line shows the raw number only).

These ride a **new dedicated player-vitals panel**, distinct from the existing objective tracker.

## Context (what already exists — verified)

- **HUD layer + objective tracker.** `scripts/ui/objective_tracker.gd` (`ObjectiveTracker`,
  a `Control`) is the only always-on HUD element, anchored top-left, parented under
  `playable_generated_ship.gd`'s `hud_layer` (`CanvasLayer`). The coordinator pushes a flat
  status list to it via `set_system_status_lines(PackedStringArray)`, built in
  `_combined_system_status_lines()` (ship systems, route, oxygen, carried tools, repair skill).
- **`OxygenState`** (`scripts/systems/oxygen_state.gd`): 0–100 scale (`max_oxygen=100`,
  `safe_threshold=35`, `recovery_threshold=30`). `get_summary()` exposes `oxygen`,
  `breach_open`, `breach_sealed`, combined `drain_multiplier` (gated to 1.0 when sealed/closed),
  and `equipment_drain_multiplier` (the suit's own factor, e.g. 0.75; **not** breach-gated).
  `get_status_lines()` already returns `Oxygen: N` + `Breach: OPEN/SEALED/CLOSED`.
- **`InventoryState`** (`scripts/systems/inventory_state.gd`): `get_load_ratio()` =
  `total_weight / capacity`, `is_over_capacity()`, `get_total_weight()`, `get_capacity()`.
  `get_status_lines()` already returns carried tools + `weight=X/Y`.
- **`Encumbrance`** (`scripts/systems/encumbrance.gd`): pure-static
  `move_speed_multiplier(load_ratio) -> float` (1.0 at/under capacity; 0.63 at 125%; 0.25 floor).
- **`RepairPoint`** (`scripts/tools/repair_point.gd`, an `Area3D`): `channeling: bool`,
  `progress: float` (0..1), signals `repair_completed` and `repair_blocked(system_id,
  subcomponent_id, reason)`. Reasons: `already_functional`, `missing_parts`, `missing_tools`,
  `insufficient_skill`.
- **Coordinator** (`scripts/procgen/playable_generated_ship.gd`): holds `repair_points: Array`;
  `_build_repair_points()` connects each point's `repair_completed` to `_on_repair_completed`
  but **not** `repair_blocked`. `_process(delta)` runs per-frame while the slice is live
  (`not away_from_start and playable_started and not slice_complete`) and calls
  `_refresh_oxygen_state(false, delta)` with the real delta. `_refresh_oxygen_state` is also
  invoked with `delta = 0.0` on initial load and on state changes.

## Decisions

1. **Dedicated vitals panel, not an extension of the objective tracker.** Player vitals are
   conceptually distinct from objectives and ship-system repair state, and the tracker's flat
   "Systems:" block is already ~13 unsectioned lines. A focused `Control` keeps each unit's
   responsibility clear and leaves room to grow.

2. **Anchor bottom-left.** Classic survival-sim vitals location; stacks on the same left edge as
   the top-left tracker (reads as one HUD column), clear of the right-side on-demand
   inventory/transfer UI, near the player's natural eye path for breach/Heavy-Load warnings.

3. **Purely additive — the objective tracker and `get_combined_system_status_lines()` are left
   unchanged.** The four main-scene smokes assert tokens (`Oxygen:`, `Breach:`,
   `drain_multiplier=`, `Repair Skill:`) against the coordinator getter
   `get_combined_system_status_lines()`, and `main_playable_slice_hazard_smoke.gd` is deeply
   coupled to the oxygen/breach lines living there. Moving those off the tracker would force a
   hazard-smoke rewrite — out of proportion for a polish slice. The vitals panel earns its place
   by showing the **new** information the tracker never had (suit contribution, Heavy-Load
   penalty, live repair progress/blocked). The resulting duplication is a bare `Oxygen: N`
   value appearing in both places; removing the redundant terse `Oxygen:`/`weight=` lines from
   the tracker (and repointing the hazard smoke) is recorded as an out-of-scope follow-up.

4. **Formatting/warning logic lives in a pure model.** A `PlayerVitalsModel` (`RefCounted`,
   no scene-tree access) owns the rule of turning raw numbers into player-facing strings, so it
   is unit-testable without a scene — consistent with the project's strict model/node split and
   the way `OxygenState` already owns its drain math. The panel is presentation only.

5. **Repair readout: live % while channeling + a transient blocked message.** While a
   `RepairPoint` channel is active, show `Repairing N%`. On a `repair_blocked` rejection, show
   `Repair blocked: <reason>` for a fixed display window, then clear. When idle with nothing
   recent, the repair line is omitted entirely. The display window counts down via the same
   per-frame `delta` so it is headless-testable (drive `tick(delta)` directly).

6. **No persistence.** Vitals are live-derived each frame from `oxygen_state`, `inventory_state`,
   `equipment_state`, and `repair_points` (all of which persist their own state where relevant).
   `PlayerVitalsModel` has no `get_summary`/`apply_summary` and is not a hazard — it does not
   participate in the ADR-0005 hazard contract.

7. **ASCII-only output.** No `₂`/`−`/`…`/`·`. The Windows headless console and the smoke grep
   contracts require exact ASCII.

8. **Accessibility scaling parity is deferred.** The objective tracker honors
   `AccessibilitySettings` (A11Y-P1-001); the vitals panel ships at fixed 1.0x sizing this slice.
   Wiring `apply_accessibility_settings` into the vitals panel is an out-of-scope follow-up.

## Line formats (vitals panel, top → bottom)

| Readout | When shown | Format |
|---|---|---|
| Oxygen | always | `Oxygen: 87`, plus state suffix ` (BREACH)` when `breach_open and not breach_sealed`, ` (SEALED)` when sealed (nothing when closed); append ` LOW` when `oxygen <= recovery_threshold` (read from the summary's `recovery_threshold` key, default `30.0` when absent) |
| Suit | only when `equipment_drain_multiplier < 1.0` | `Suit: -25% O2 drain` — percent = `round((1.0 - equipment_drain_multiplier) * 100)` |
| Load | always | `Load: 78%` (`round(load_ratio * 100)`); when `load_ratio > 1.0` → `Load: 112% HEAVY (-30% move)` where penalty = `round((1.0 - move_multiplier) * 100)` |
| Repair | transient (omitted when idle) | channeling → `Repairing 47%` (`round(progress * 100)`); blocked (within display window) → `Repair blocked: <reason>` |

Reason map (blocked): `missing_parts` → `missing parts`; `missing_tools` → `missing tools`;
`insufficient_skill` → `need higher repair skill`; `already_functional` → `already repaired`;
any other → the raw reason string.

## Architecture & Data Flow

Per-frame, inside the coordinator's existing oxygen refresh path, a new
`_refresh_player_vitals(delta)` runs at the end of `_refresh_oxygen_state(...)` (so it shares the
per-frame cadence AND the just-applied oxygen/equipment summaries, and also updates on the
`delta = 0.0` initial/state-change refreshes):

```
oxygen_state.get_summary()                  -> vitals_model.apply_oxygen_summary(...)
inventory_state.get_load_ratio()            -\
Encumbrance.move_speed_multiplier(ratio)     -> vitals_model.apply_inventory_load(ratio, mult)
scan repair_points for channeling==true     -> vitals_model.set_repair_progress(channeling, progress)
vitals_model.tick(delta)                       (decrements the transient blocked timer)
vitals_panel.set_status_lines(vitals_model.get_status_lines())
```

`repair_blocked` is event-driven: `_build_repair_points()` connects each point's `repair_blocked`
signal to a coordinator handler that calls `vitals_model.notify_repair_blocked(reason)` (which
resets the display timer). No scene-tree access is added to either the model or the panel; the
coordinator remains the only place that bridges the four model/node sources into the vitals model.

## Components / Files

### New `scripts/systems/player_vitals_model.gd` (pure `RefCounted`)

- Const `BLOCKED_DISPLAY_SECONDS: float = 3.0`.
- State: `_oxygen_summary: Dictionary`, `_load_ratio: float`, `_move_multiplier: float`,
  `_repair_channeling: bool`, `_repair_progress: float`, `_blocked_reason: String`,
  `_blocked_remaining: float`.
- `apply_oxygen_summary(summary: Dictionary) -> void` — stores a deep copy.
- `apply_inventory_load(load_ratio: float, move_multiplier: float) -> void`.
- `set_repair_progress(channeling: bool, progress: float) -> void`.
- `notify_repair_blocked(reason: String) -> void` — sets `_blocked_reason`, resets
  `_blocked_remaining = BLOCKED_DISPLAY_SECONDS`.
- `tick(delta: float) -> void` — `_blocked_remaining = max(0.0, _blocked_remaining - delta)`;
  clears `_blocked_reason` when it reaches 0.
- `get_status_lines() -> PackedStringArray` — composes the lines per the table above.
- `get_vitals_summary() -> Dictionary` — structured snapshot for the smoke
  (`oxygen`, `breach_state`, `suit_drain_percent`, `load_percent`, `heavy`, `move_penalty_percent`,
  `repair_line`, `blocked_active`).

### New `scripts/ui/player_vitals_panel.gd` (`Control`)

- Mirrors `ObjectiveTracker`'s node construction: styled `PanelContainer` → `MarginContainer`
  → autowrap `Label`. Anchored `PRESET_BOTTOM_LEFT`, `mouse_filter = MOUSE_FILTER_IGNORE`,
  positioned with a small bottom-left margin offset; fixed 1.0x sizing.
- `set_status_lines(lines: PackedStringArray) -> void` — joins with `\n` into the label.
- `get_hud_text() -> String` — returns the rendered label text (for the smoke).

### Modify `scripts/procgen/playable_generated_ship.gd`

- New fields `vitals_model` and `vitals_panel`; preload consts for the two new scripts.
- Build `vitals_panel` and parent it under `hud_layer` where the tracker is built (~line 2338),
  and construct `vitals_model`.
- In `_build_repair_points()`, after the existing `repair_completed` connection, connect
  `rp.repair_blocked` to a new `_on_repair_blocked(system_id, subcomponent_id, reason)` handler
  that forwards `reason` to `vitals_model.notify_repair_blocked(reason)` (guard `vitals_model != null`).
- Add `_refresh_player_vitals(delta_seconds)` and call it at the end of
  `_refresh_oxygen_state(...)`, guarded by `vitals_model != null and vitals_panel != null`. It
  feeds the model from the four sources (oxygen summary, inventory load, channeling repair point),
  calls `tick(delta_seconds)`, and pushes `get_status_lines()` to the panel.
- Expose `get_player_vitals_lines() -> PackedStringArray` (returns `vitals_model.get_status_lines()`)
  as a coordinator seam for the main-scene smoke, mirroring `get_combined_system_status_lines()`.

### New `scripts/validation/player_vitals_model_smoke.gd` (pure model)

Drives `PlayerVitalsModel` directly (no scene tree), constructed via a preload const:
- Oxygen open + suit: `apply_oxygen_summary({oxygen:87, breach_open:true, breach_sealed:false,
  drain_multiplier:0.375, equipment_drain_multiplier:0.75})` → lines contain `Oxygen: 87`,
  ` (BREACH)`, `Suit: -25% O2 drain`.
- Oxygen sealed: `breach_sealed:true` → ` (SEALED)`, no `(BREACH)`.
- Oxygen low: `oxygen:20` → ` LOW`.
- Load normal: `apply_inventory_load(0.78, 1.0)` → `Load: 78%`, no `HEAVY`.
- Load heavy: `apply_inventory_load(1.12, 0.70)` → `Load: 112% HEAVY (-30% move)`.
- Repair channeling: `set_repair_progress(true, 0.47)` → `Repairing 47%`.
- Repair blocked + clear: `notify_repair_blocked("missing_parts")` → `Repair blocked: missing parts`;
  `tick(BLOCKED_DISPLAY_SECONDS + 0.1)` → no `Repair blocked:` line.
- Idle: `set_repair_progress(false, 0.0)` with no recent block → no repair line.
- Marker: `PLAYER VITALS MODEL SMOKE PASS suit=-25 heavy=-30 repair=47`.

### New `scripts/validation/main_playable_slice_vitals_hud_smoke.gd` (main scene)

Instantiates `res://scenes/main.tscn` headless (mirroring `main_playable_slice_hud_smoke.gd`),
finds the `PlayableGeneratedShip`, waits for `loader.has_loaded_ship()`:
- Assert `vitals_panel` exists, is a `Control`, parented under `hud_layer`, anchored bottom-left.
- Teleport the player into a breach zone via `teleport_player_to_breach_zone_for_validation()`,
  refresh → `get_player_vitals_lines()` / panel text contains `Oxygen:` and `(BREACH)`.
- Equip the hardsuit through the equipment path, refresh → `Suit: -25% O2 drain`.
- Over-encumber via `inventory_state.add_item(...)` with heavy items, refresh → a `Load:` line
  containing `HEAVY`.
- Drive a repair point: `advance_channel` partway → `Repairing` with a percent; trigger a
  blocked `try_start` (no parts) → `Repair blocked:`.
- Marker: `MAIN PLAYABLE VITALS HUD PASS panel=true breach=true suit=true heavy=true repair=true`.

### Docs

- `docs/game/adr/0025-player-vitals-hud.md` — record the dedicated panel, the pure
  `PlayerVitalsModel` formatting seam, the additive (no-tracker-churn) stance and its rationale,
  and the deferred follow-ups.
- `docs/game/06_validation_plan.md` — register both smokes with their markers; bundle 117 → 119.
- `docs/game/09_system_roadmap.md` — note the player-vitals HUD under System 6 / Phase 7.

## Testing & Validation

- Both new smokes print their PASS marker (the contract) and run clean (no unexpected
  `ERROR:`/`WARNING:` beyond the allowlisted baseline noise).
- Full regression bundle green at **commands=119 clean_output=true** (stash `project.godot`
  drift before the run, pop after; never commit it / `.godot/` / `*.uid` / `addons/`).
- Gate-1 automated playtest still `GO`.

## Out of Scope (explicit)

- Removing the redundant terse `Oxygen:`/`weight=` lines from the objective tracker and repointing
  `main_playable_slice_hazard_smoke.gd` — deferred follow-up (decision 3).
- Accessibility-scaling parity for the vitals panel (`apply_accessibility_settings`) — deferred
  follow-up (decision 8).
- Re-tuning any underlying values (suit 0.75, encumbrance curve, oxygen thresholds) — that is the
  balance slice (sub-project D).
- Icons, color-coded severity bands, animation/tweening of the bars, or numeric oxygen-bar widgets
  — text readouts only this slice.
- Suit air-supply depletion and any new gameplay state — surfacing existing model state only.
