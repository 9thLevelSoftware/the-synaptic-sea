# 06 Validation Plan

## Core rule

No completion claim without fresh validation evidence.

## Godot binary

`/Users/christopherwilloughby/.local/bin/godot-4.6.2`

## Project root

`/Users/christopherwilloughby/the-sargasso-of-stars`

## Focused route-control validation

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/route_control_state_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
```

Expected markers:

- `ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true`
- `MAIN PLAYABLE ROUTE CONTROL PASS gates=1 opened=1 blockers=0 extraction=true`

## Regression bundle

```bash
set -euo pipefail
# Honor GODOT/ROOT environment overrides (quoted to tolerate spaces in the
# path, e.g. the Windows checkout "The Synaptic Sea"); fall back to the
# original author's macOS paths when unset.
ROOT="${ROOT:-/Users/christopherwilloughby/the-sargasso-of-stars}"
GODOT="${GODOT:-/Users/christopherwilloughby/.local/bin/godot-4.6.2}"
# Known baseline Godot shutdown lines that appear identically in every
# unchanged smoke (route-control, completion, input, readability, oxygen,
# hazard, ship-systems) and are NOT introduced by the Sargasso hazard code
# or any other Gate 1 runtime system. They are filtered out of the strict
# ERROR/WARNING check below; any other ERROR:/WARNING: line (parse errors,
# GDScript runtime errors, validation markers pushed via push_error) still
# fails the bundle. See "Baseline Godot teardown noise" below for the
# audit trail and the exact evidence-gathering command.
BASELINE_ERROR="^ERROR: Capture not registered: 'gdaimcp'\\.$"
BASELINE_WARNING="^WARNING: ObjectDB instances leaked at exit \\(run with --verbose for details\\)\\.$"
REQ012_WARNING="^WARNING: SaveLoadService: save file rejected by from_dict \\(missing fields or version mismatch\\)\$"
# load_from_blueprint_smoke deliberately calls load_from_blueprint(null) to
# verify the null-blueprint guard; that guard emits this push_error on the
# rejection path. It is the expected signal, not a failure (mirrors the
# REQ-012 save/load rejection WARNING above).
BLUEPRINT_NULL_ERROR="^ERROR: PlayableGeneratedShip\\.load_from_blueprint: blueprint must not be null\$"
# REQ-012 fix: travel_integration_smoke calls request_save() while aboard a
# traveled derelict to verify the away-save block. The block emits this
# push_warning as its expected signal; it is not a failure.
REQ012_AWAY_SAVE_WARNING="^WARNING: PlayableGeneratedShip: save blocked — cannot save while aboard a traveled derelict \\(away_from_start=true\\); return to the starting ship first\$"
run_clean() {
  label="$1"
  marker="$2"
  shift 2
  echo "=== $label ==="
  OUT=$("$@" 2>&1)
  printf '%s\n' "$OUT"
  printf '%s\n' "$OUT" | grep -q "$marker"
  FILTERED=$(printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' | grep -Ev "$BASELINE_ERROR|$BASELINE_WARNING|$REQ012_WARNING|$BLUEPRINT_NULL_ERROR|$REQ012_AWAY_SAVE_WARNING" || true)
  if [ -n "$FILTERED" ]; then
    printf '%s\n' "$FILTERED"
    echo "UNEXPECTED_ERROR_OR_WARNING in $label"
    exit 1
  fi
}
run_clean 'route control model smoke' 'ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/route_control_state_smoke.gd
run_clean 'main route control smoke' 'MAIN PLAYABLE ROUTE CONTROL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
run_clean 'oxygen model smoke' 'OXYGEN STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_state_smoke.gd
run_clean 'inventory model smoke' 'INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_state_smoke.gd
run_clean 'main inventory smoke' 'MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_inventory_smoke.gd
run_clean 'main hazard smoke' 'MAIN PLAYABLE HAZARD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hazard_smoke.gd
run_clean 'fire model smoke' 'FIRE STATE PASS cycles=2 phases=4 passability_switches=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_state_smoke.gd
run_clean 'main fire smoke' 'MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_fire_smoke.gd
run_clean 'golden fire zone source marker smoke' 'GOLDEN FIRE ZONE SOURCE MARKER PASS marker_room=cargo_01' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/golden_fire_zone_source_marker_smoke.gd
run_clean 'ship systems smoke' 'MAIN PLAYABLE SHIP SYSTEMS PASS power=true breach_sealed=true gates_open=true logs=true reactor=true extraction=true power_pct=100' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
run_clean 'completion smoke' 'MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
run_clean 'template b completion smoke' 'MAIN PLAYABLE TEMPLATE B COMPLETE PASS completed=5 current_sequence=6 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_template_b_completion_smoke.gd
run_clean 'input smoke' 'MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
run_clean 'readability smoke' 'MAIN PLAYABLE SLICE READABILITY PASS objective_props=5 blocked=1 ramp=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
run_clean 'main objective variation smoke' 'MAIN PLAYABLE OBJECTIVE VARIATION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
run_clean 'objective progress state smoke' 'OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_state_smoke.gd
run_clean 'objective progress hud label smoke' 'OBJECTIVE PROGRESS HUD LABEL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_hud_label_smoke.gd
run_clean 'save/load service smoke' 'SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=8' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
run_clean 'main save/load smoke' 'MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_save_load_smoke.gd
run_clean 'main reload affordance smoke' 'MAIN PLAYABLE RELOAD AFFORDANCE PASS cleared_live=true cleared_after_reload=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_reload_affordance_smoke.gd
run_clean 'REQ-012 auto-save sequence smoke' 'REQ012 AUTOSAVE SEQUENCE CHECK PASS live=2 snapshot=2 file=2 has_save=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/req012_autosave_sequence_smoke.gd
run_clean 'template C stacked layout main scenario smoke' 'TEMPLATE C MAIN SCENARIO PASS objectives=5 current_sequence=6 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/template_c_main_scenario_smoke.gd
run_clean 'junction calibrator model smoke' 'JUNCTION CALIBRATOR STATE PASS required_steps=2 consumed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/junction_calibrator_state_smoke.gd
run_clean 'main junction calibrator smoke' 'MAIN PLAYABLE JUNCTION CALIBRATOR PASS acquired=true required_steps=2 consumed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_junction_calibrator_smoke.gd
run_clean 'main junction calibrator save/load smoke' 'MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS carried_load=true consumed_load=true next_frame_interaction=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_junction_calibrator_save_load_smoke.gd
run_clean 'alternate input smoke' 'MAIN PLAYABLE ALTERNATE INPUT PASS moves_alt=1 interact_alt=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_alternate_input_smoke.gd
run_clean 'alternate input events smoke' 'PLAYABLE SLICE ALTERNATE INPUT EVENTS PASS static_bindings=ok moves_alt=1 interact_alt=3' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/playable_slice_alternate_input_smoke.gd
run_clean 'A11Y-P1-001 text scale smoke' 'MAIN PLAYABLE TEXT SCALE PASS scales=3 default=1.0x1.5x2.0 runtime_text=present' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_text_scale_smoke.gd
run_clean 'performance baseline smoke' 'PERFORMANCE BASELINE PASS templates=3' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/performance_profiler.gd
run_clean 'arc hazard model smoke' 'ARC STATE PASS cycles=2 phases=4 passability_switches=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/electrical_arc_state_smoke.gd
run_clean 'main arc smoke' 'MAIN PLAYABLE ARC PASS state=DISCHARGED cycles=2 blocked_arcing=true blocked_discharged=false' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_arc_smoke.gd
run_clean 'ADR-0005 hazard contract static smoke' 'HAZARD CONTRACT PASS models=3 phase_timer_owners=2 wrong_kind_rejected=3 configure_dict=3' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hazard_contract_smoke.gd
run_clean 'ship blueprint smoke' 'SHIP BLUEPRINT PASS sizes=3 conditions=3 serialization=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_blueprint_smoke.gd
run_clean 'room graph smoke' 'ROOM GRAPH PASS rooms=3 links=2 connected=true disconnected_detected=true serialization=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_graph_smoke.gd
run_clean 'room graph generator smoke' 'ROOM GRAPH GENERATOR PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_graph_generator_smoke.gd
run_clean 'structural placer smoke' 'STRUCTURAL PLACER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/structural_placer_smoke.gd
run_clean 'ship generator smoke' 'SHIP GENERATOR PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_generator_smoke.gd
run_clean 'archetype load smoke' 'ARCHETYPE LOAD PASS archetypes=3 round_trip=3' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/archetype_load_smoke.gd
run_clean 'load from blueprint integration' 'LOAD FROM BLUEPRINT INTEGRATION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/load_from_blueprint_smoke.gd
run_clean 'gameplay slice builder smoke' 'GAMEPLAY_SLICE_BUILDER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gameplay_slice_builder_smoke.gd
run_clean 'life boat layout smoke' 'LIFE_BOAT_LAYOUT PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_boat_layout_smoke.gd
run_clean 'start scenario smoke' 'START_SCENARIO PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/start_scenario_smoke.gd
run_clean 'procgen walkability smoke' 'WALKABILITY PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_walkability_smoke.gd
run_clean 'ship subcomponent smoke' 'SHIP SUBCOMPONENT PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_subcomponent_smoke.gd
run_clean 'ship system smoke' 'SHIP SYSTEM PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_system_smoke.gd
run_clean 'life support system smoke' 'LIFE SUPPORT SYSTEM PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_support_system_smoke.gd
run_clean 'ship systems definitions smoke' 'SHIP SYSTEMS DEFINITIONS PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_definitions_smoke.gd
run_clean 'ship systems manager smoke' 'SHIP SYSTEMS MANAGER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_smoke.gd
run_clean 'ship systems manager force repair smoke' 'SHIP SYSTEMS MANAGER FORCE REPAIR PASS health=1.0 unknown_rejected=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_force_repair_smoke.gd
run_clean 'playable manager built smoke' 'PLAYABLE MANAGER BUILT PASS systems=6' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/playable_manager_built_smoke.gd
run_clean 'class definitions smoke' 'CLASS DEFINITIONS PASS classes=8 engineer_repair=3 technical=1.5 default=1.0' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_definitions_smoke.gd
run_clean 'player progression model smoke' 'PLAYER PROGRESSION PASS class=engineer repair_start=3 leveled=4 round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_progression_state_smoke.gd
run_clean 'progression repair integration smoke' 'PROGRESSION REPAIR INTEGRATION PASS rejected_low=true success_hi=true faster_at_higher_skill=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/progression_repair_integration_smoke.gd
run_clean 'main progression smoke' 'MAIN PLAYABLE PROGRESSION PASS class=engineer repair_xp_gained=true hud=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_progression_smoke.gd
run_clean 'marker generator smoke' 'MARKER GENERATOR PASS deterministic=true per_cell=3 round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/marker_generator_smoke.gd
run_clean 'sargasso world smoke' 'SARGASSO WORLD PASS in_range_sorted=true generated=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sargasso_world_smoke.gd
run_clean 'scanner state smoke' 'SCANNER STATE PASS nav_off_empty=true scanners_off_detail1=true full_detail=6 round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/scanner_state_smoke.gd
run_clean 'travel controller smoke' 'TRAVEL CONTROLLER PASS propulsion_gate=true range_gate=true generated_node=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_controller_smoke.gd
run_clean 'ship instance smoke' 'SHIP INSTANCE PASS round_trip=true stubs_present=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_smoke.gd
run_clean 'travel integration smoke' 'TRAVEL INTEGRATION PASS start_wrapped=true scan_gated=true propulsion_gate=true swapped=true progression_persists=true world_recorded=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_integration_smoke.gd
run_clean 'scanner panel smoke' 'SCANNER PANEL PASS populated=true selection_moves=true travel_invoked=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/scanner_panel_smoke.gd
echo 'SARGASSO REGRESSION PASS commands=61 clean_output=true'
```

## Baseline Godot teardown noise

Two `ERROR:`/`WARNING:` lines are emitted on the engine teardown of every
smoke run in this regression bundle, including in unchanged smokes that were
already passing before the hazard feature was added. They are classified as
baseline engine noise and filtered by the script above:

- `ERROR: Capture not registered: 'gdaimcp'.` — emitted by Godot's
  `engine_debugger.cpp:62` when a registered message capture (the GDAI MCP
  capture, registered when the Sargasso Godot editor session is live) is
  not active during a `--headless --script` run. Present in every smoke.
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`
  — generic Godot cleanup-time warning from `object.cpp:2641`. The ObjectDB
  leak count is identical across every smoke; the smoke that runs first
  reports a higher count because earlier `addons/gdai-mcp-plugin-godot/`
  capture registrations are torn down once and not re-registered per run.

REQ-012 adds one additional expected `WARNING:` line that is part of the
save/load service contract test (the smoke writes a snapshot with an
incompatible `slice_version` and asserts the service rejects it via
`push_warning`):

- `WARNING: SaveLoadService: save file rejected by from_dict (missing fields or version mismatch)`
  — emitted by `scripts/systems/save_load_service.gd` when `load_current_run()`
  reads a save whose version markers do not match the current engine.
  The save/load service smoke writes an incompatible snapshot to verify
  this rejection path; the WARNING is the expected signal, not a failure.
  Filtered by the strict ERROR/WARNING check above; any other
  `SaveLoadService:` warning (a real parse error, missing file on a
  fresh load, etc.) still fails the bundle.

The REQ-012 reload-while-away fix adds one additional expected `WARNING:` line
emitted by the travel integration smoke when it calls `request_save()` while
aboard a traveled derelict to verify the away-save block:

- `WARNING: PlayableGeneratedShip: save blocked — cannot save while aboard a traveled derelict (away_from_start=true); return to the starting ship first`
  — emitted by `scripts/procgen/playable_generated_ship.gd` `request_save()`
  when `away_from_start` is true. The `travel_integration_smoke` deliberately
  calls `request_save()` in the away state to verify the guard rejects the
  request; the WARNING is the expected signal, not a failure. Filtered by
  `$REQ012_AWAY_SAVE_WARNING`; any other `PlayableGeneratedShip: save blocked`
  warning still fails the bundle.

The Phase 1 `load_from_blueprint_smoke` adds one additional expected
`ERROR:` line that is part of its null-guard contract test:

- `ERROR: PlayableGeneratedShip.load_from_blueprint: blueprint must not be null`
  — emitted by `scripts/procgen/playable_generated_ship.gd` when
  `load_from_blueprint(null)` is called. The smoke deliberately calls it with
  `null` to verify the guard rejects bad input; the ERROR is the expected
  signal, not a failure. Filtered by the strict check above via
  `$BLUEPRINT_NULL_ERROR`; any other `load_from_blueprint:` error still fails
  the bundle.

Evidence collection command (run before adding or removing a smoke from the
bundle; any unexpected `ERROR:`/`WARNING:` line that is not on the allowlist
must block the change):

```bash
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
for s in route_control_state_smoke main_playable_slice_route_control_smoke oxygen_state_smoke main_playable_slice_hazard_smoke fire_state_smoke main_playable_slice_fire_smoke main_playable_slice_ship_systems_smoke main_playable_slice_completion_smoke main_playable_slice_input_smoke main_playable_slice_readability_smoke save_load_service_smoke main_playable_slice_save_load_smoke objective_progress_state_smoke objective_progress_hud_label_smoke main_playable_slice_objective_variation_smoke req012_autosave_sequence_smoke main_playable_slice_text_scale_smoke electrical_arc_state_smoke main_playable_slice_arc_smoke main_playable_slice_junction_calibrator_save_load_smoke ship_blueprint_smoke room_graph_smoke room_graph_generator_smoke structural_placer_smoke ship_generator_smoke archetype_load_smoke load_from_blueprint_smoke procgen_stress_test; do
  echo "=== $s ==="
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path "$ROOT" --script res://scripts/validation/$s.gd 2>&1 | grep -E '^(ERROR|WARNING):'
done
```

If a future smoke adds a new `ERROR:` or `WARNING:` line, the strict filter
above will trip and the bundle will exit 1; classify the new line in this
section (and update the allowlist) before re-running.

## Artifact scope guard

Use after gameplay-system milestones where the user asked to avoid proof churn:

```bash
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
find "$ROOT/docs/superpowers/proofs" -maxdepth 1 -type f -newer "$ROOT/docs/game/00_vision.md" -print 2>/dev/null || true
find "$ROOT/.superpowers" -type f \( -name '*.html' -o -name '*.png' \) -newer "$ROOT/docs/game/00_vision.md" -print 2>/dev/null || true
```

Any printed route-control/gameplay-system proof artifact must be explained. Do not delete unrelated files from concurrent work.

## RED-phase warning

Godot `--script` parse/load errors can return exit code 0 before `_initialize()` runs. RED-phase validation must inspect output for parse errors or missing pass markers.

## Gate 1 playtest validation

In-engine behavioral playtests run on top of the regression bundle. The regression bundle must pass before any playtest protocol is evaluated; playtest evidence does not substitute for any smoke in the bundle.

Gate 1 accepts two evidence paths:

- Automated protocol: `docs/game/playtests/automated-playtest-protocol.md`. This is an alternative evidence source to the human fresh-player protocol and is sufficient for Gate 1 Go / Recycle / Hold decisions.
- Human protocol: `docs/game/playtests/gate-1-playtest-protocol.md`, with per-session logs at `docs/game/playtests/gate-1-<YYYY-MM-DD>-<player-pseudonym>.md` using `docs/game/playtests/playtest_template.md`. This remains recommended follow-up evidence before production-readiness sign-off.

Automated Gate 1 command:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/gate1_automated_playtest.gd
```

A Gate 1 Go decision requires the regression bundle plus either the automated protocol acceptance checklist or the human playtest protocol acceptance checklist to pass.

## Future validation additions
- [x] Inventory/tool model smoke: `scripts/validation/inventory_state_smoke.gd` (expected marker `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5`) and main-scene smoke `scripts/validation/main_playable_slice_inventory_smoke.gd` (expected marker `MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5`) (REQ-007). Added to regression bundle.
- [x] Fire hazard model smoke: `scripts/validation/fire_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_fire_smoke.gd` (REQ-010).
- [x] Golden fire-zone source marker smoke: `scripts/validation/golden_fire_zone_source_marker_smoke.gd` — pins the Gate 2 fire zone to a side link declared in BOTH `layout.json` and `gameplay_slice.json`, asserts target room is non-critical and not the obj3 → obj4 breach corridor, and verifies `FIRE_ZONE_FALLBACK_ROOM_ID` matches the marker. Added to regression bundle.
- [x] Objective variation model smoke: `scripts/validation/objective_progress_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_objective_variation_smoke.gd` (REQ-011). Added to regression bundle.
- [x] Objective HUD-label smoke: `scripts/validation/objective_progress_hud_label_smoke.gd` (REQ-011) — verifies the player-facing "Repair junction" label is shown for `kind == "repair_junction"` while the ship-system `type == "restore_systems"` stays preserved. Added to regression bundle.
- [x] Save/load service smoke: `scripts/validation/save_load_service_smoke.gd` (expected marker `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=8`) and main-scene smoke `scripts/validation/main_playable_slice_save_load_smoke.gd` (expected marker `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`) (REQ-012). Added to regression bundle. Marker updated from `summaries=7` to `summaries=8` by ADR-0010 (Phase 3 player progression added `player_progression_summary` to RunSnapshot).
- [x] REQ-012 auto-save sequence smoke: `scripts/validation/req012_autosave_sequence_smoke.gd` (expected marker `REQ012 AUTOSAVE SEQUENCE CHECK PASS live=2 snapshot=2 file=2 has_save=true`) — permanent regression for the auto-save ordering bug. Completes objective 1 and inspects the in-memory snapshot and the on-disk save BEFORE any manual `request_save()` so the auto-save-only path is locked down. Added to regression bundle.
- [x] Template B completion smoke: `scripts/validation/main_playable_slice_template_b_completion_smoke.gd` (expected marker `MAIN PLAYABLE TEMPLATE B COMPLETE PASS completed=5 current_sequence=6 run_complete=true`). Added to regression bundle.
- [x] Alternate input smoke: `scripts/validation/main_playable_slice_alternate_input_smoke.gd` (expected marker `MAIN PLAYABLE ALTERNATE INPUT PASS moves_alt=1 interact_alt=1`) — A11Y-P1-002 alternate keyboard binding surface. Verifies the InputMap carries both WASD/E/F5/F9 (original) and Arrows / Enter / Space / KP_Enter (alternates) on the movement and interact actions, that save/load (F5/F9) stays single-binding and non-conflicting, that the HUD prompt reflects the expanded surface, and that driving the action through `Input.action_press` (the exact code path the engine uses for a held arrow key) advances the player and registers an interact press. Added to regression bundle.
- [x] Alternate input events smoke: `scripts/validation/playable_slice_alternate_input_smoke.gd` (expected marker `PLAYABLE SLICE ALTERNATE INPUT EVENTS PASS static_bindings=ok moves_alt=1 interact_alt=3 enter=1 space=1 kp_enter=1`) — A11Y-P1-002 companion to the alternate input smoke above. Proves that a REAL `InputEventKey` routed through `Input.parse_input_event()` (the same code path a player's actual keypress takes) reaches the engine's input layer: KEY_RIGHT drives `move_right` via the player's `Input.get_action_strength` poll and the player's `global_position` advances on +X, and KEY_ENTER / KEY_SPACE / KEY_KP_ENTER each fire `PlayerController.interact_requested` exactly once (the same signal the original KEY_E binding fires via `PlayerController._unhandled_input`'s `event.is_action_pressed("interact")` watch). Drops the static-binding check so any silent removal of an alternate keycode from `ensure_default_input_actions()` fails this smoke with `static bindings incomplete: ...`, even when the WASD/E smoke and the action-press alternate smoke still pass. Added to regression bundle.
- [x] A11Y-P1-001 text scale smoke: `scripts/validation/main_playable_slice_text_scale_smoke.gd` (expected marker `MAIN PLAYABLE TEXT SCALE PASS scales=3 default=1.0x1.5x2.0 runtime_text=present`) — proves the single `AccessibilitySettings` seam drives both the HUD `font_size` and `custom_minimum_size` (default 1.0 reproduces font=18, panel=520x250) and the world `Label3D.pixel_size` for the breach unsafe marker and fire zone label (default 0.0035 reproduces exactly), and that the same seam scales consistently to 1.5x (font=27, panel=780x375, pixel=0.002333) and 2.0x (font=36, panel=1040x500, pixel=0.001750) while HUD text remains sourced from runtime state at every scale. Added to regression bundle.
- [x] Hub/meta progression smoke (deferred past Gate 2 per ADR-0003).
- [x] GUT suite if/when adopted by ADR.
- [x] Performance baseline smoke: `scripts/validation/performance_profiler.gd` (expected marker `PERFORMANCE BASELINE PASS templates=3`) — first baseline numbers established 2026-06-19 at `docs/game/performance_baseline.md`. Headless harness covers load time, procgen time, peak Godot static memory, and end-of-run OS RSS across the two known procgen templates plus the main playable scene. Windowed FPS at `scripts/validation/windowed_fps_capture.gd` is intentionally NOT in the bundle (requires a display server); it is the source of truth for the frame-time target and is run on demand during Gate 3 / Gate 4 review. Added to regression bundle.
- [x] Junction calibrator model smoke: `scripts/validation/junction_calibrator_state_smoke.gd` (expected marker `JUNCTION CALIBRATOR STATE PASS required_steps=2 consumed=true`) and main-scene smoke `scripts/validation/main_playable_slice_junction_calibrator_smoke.gd` (expected marker `MAIN PLAYABLE JUNCTION CALIBRATOR PASS acquired=true required_steps=2 consumed=true`) (REQ-014). Added to regression bundle. The main-scene smoke registers a synthetic 3-step junction through `register_junction_sequence_for_validation` so it asserts the exact `required_steps=2` post-calibration marker without depending on the seed template's exact step count (the seed template's sequence 2 is a 2-step junction; REQ-014's spec example requires a 3-step reduction target).
- [x] Junction calibrator save/load smoke: `scripts/validation/main_playable_slice_junction_calibrator_save_load_smoke.gd` (expected marker `MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS carried_load=true consumed_load=true next_frame_interaction=true`) — permanent regression for the two blocking findings from review t_80dcea4b. Drives the actual seed sequence 2 repair_junction through save/load in both carried and consumed/applied save states, including a real next-frame interaction after each load. Asserts the live coordinator path leaves the objective_progress model complete after the calibrator reduces a real 2-step junction to 1 (the pre-calibration `required_steps` snapshot lets `complete_step` fire on the first interaction instead of being skipped), and that post-load interactions survive the rebuild of the HUD layer / ObjectiveTracker that previously crashed with "Nonexistent function 'mark_completed' in base 'previously freed'". Also locks down the reload pickup-marker reconciliation (carried = hidden, spent = hidden) and the JSON-string-int-key round-trip in `ObjectiveProgressState.apply_summary` that would otherwise silently drop the per-sequence `calibrator_applied` flag. Added to regression bundle.
- [x] Electrical-arc hazard model smoke: `scripts/validation/electrical_arc_state_smoke.gd` (expected marker `ARC STATE PASS cycles=2 phases=4 passability_switches=4`) and main-scene smoke `scripts/validation/main_playable_slice_arc_smoke.gd` (expected marker `MAIN PLAYABLE ARC PASS state=DISCHARGED cycles=2 blocked_arcing=true blocked_discharged=false`) (REQ-013). The pure model smoke advances the cycle through two full DISCHARGED -> ARCING -> DISCHARGED rounds and asserts the phase / passability counts match the ADR-0005 contract; it also round-trips the summary through `apply_summary()` and verifies a wrong `hazard_kind` is rejected. The main-scene smoke drives the same model through `playable.electrical_arc_state.tick(...)` against template 002 (which carries the new `arc_side_01` non-critical side branch) and asserts collision is enabled only while ARCING. Both are added to the regression bundle.
- [x] Phase 1 walkable-ship gate smokes (procgen layout pipeline → walkable start scenario):
  - `scripts/validation/gameplay_slice_builder_smoke.gd` (expected marker `GAMEPLAY_SLICE_BUILDER PASS`) — `GameplaySliceBuilder.build()` produces a valid gameplay slice (distinct start/goal rooms, sequenced objectives with `approach_cell`, empty hazard-zone arrays) across all 3 templates × 3 seeds.
  - `scripts/validation/life_boat_layout_smoke.gd` (expected marker `LIFE_BOAT_LAYOUT PASS`) — `LifeBoatBuilder.build_layout()` emits a layout.json-compatible 3-room Dict (airlock/bridge/engineering) with structural placements, ≥2 room links, and a prototype carrying start/goal rooms.
  - `scripts/validation/start_scenario_smoke.gd` (expected marker `START_SCENARIO PASS`) — full start scenario: derelict layout through the pipeline + gameplay slice loads via `GeneratedShipLoader`, a nav mesh bakes from floor cells, and the life boat layout builds. The transient loader Node3D is freed before quit so no instantiated geometry/physics/nav RIDs leak into the strict ERROR/WARNING check.
  - `scripts/validation/procgen_walkability_smoke.gd` (expected marker `WALKABILITY PASS`) — definitive Phase 1 gate: generates a ship from seed, bakes a nav mesh, and walks a `NavigationAgent3D` from the start room through every objective room to the goal. Proves the spec exit criteria "rooms connect, geometry loads, player can walk through."
  All four added to the regression bundle (`commands=42`; bundle later extended to `commands=47` by Phase 2 ship-systems smokes).
- [x] ADR-0005 hazard contract static smoke: `scripts/validation/hazard_contract_smoke.gd` (expected marker `HAZARD CONTRACT PASS models=3 phase_timer_owners=2 wrong_kind_rejected=3 configure_dict=3`) — structural (no runtime tick) assertion that catches the three review-recycle findings on REQ-013 / REQ-014 hazard models: (1) FireState and ElectricalArcState MUST own a `PhaseTimer` instance and translate its `Phase.A/B` output into their own enum, (2) `get_summary()` MUST include `hazard_kind` on every model, and (3) `apply_summary()` MUST reject a wrong-kind summary. Also asserts OxygenState does NOT own a `PhaseTimer` (negative decision from ADR-0005: resource-drain hazards do not need timer phases) and that the `PhaseTimer` helper itself does not carry a `HAZARD_KIND` discriminator. Locks down the `configure(config: Dictionary)` uniform boundary from the ADR-0005 HazardStateContract. Added to regression bundle.
- [x] Phase 2 ship-systems model smokes (System 2 / ADR-0008): `ship_subcomponent_smoke.gd` (`SHIP SUBCOMPONENT PASS`), `ship_system_smoke.gd` (`SHIP SYSTEM PASS`), `life_support_system_smoke.gd` (`LIFE SUPPORT SYSTEM PASS`), `ship_systems_definitions_smoke.gd` (`SHIP SYSTEMS DEFINITIONS PASS`), and `ship_systems_manager_smoke.gd` (`SHIP SYSTEMS MANAGER PASS` — the Phase 2 gate: deterministic build, dependency cascade, advance/oxygen-drain, parameterized repair, and full round-trip). All five added to the regression bundle. The manager is intentionally NOT yet wired into the live SaveLoadService snapshot (build-alongside; `summaries=7` unchanged).
