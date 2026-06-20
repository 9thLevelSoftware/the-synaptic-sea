#!/usr/bin/env bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
LOG_DIR=${1:-/tmp/sargasso_gate4_kickoff_$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/regression_bundle.log"
: > "$LOG"
BASELINE_ERROR="^ERROR: Capture not registered: 'gdaimcp'\\.$"
BASELINE_WARNING="^WARNING: ObjectDB instances leaked at exit \\(run with --verbose for details\\)\\.$"
REQ012_WARNING="^WARNING: SaveLoadService: save file rejected by from_dict \\(missing fields or version mismatch\\)$"
commands=0
run_clean() {
  local label="$1"
  local marker="$2"
  shift 2
  commands=$((commands + 1))
  echo "=== $label ===" | tee -a "$LOG"
  local out
  out=$("$@" 2>&1)
  printf '%s\n' "$out" >> "$LOG"
  if ! printf '%s\n' "$out" | grep -q "$marker"; then
    echo "MISSING_MARKER in $label: $marker" | tee -a "$LOG"
    printf '%s\n' "$out"
    exit 1
  fi
  local filtered
  filtered=$(printf '%s\n' "$out" | grep -E '^(ERROR|WARNING):' | grep -Ev "$BASELINE_ERROR|$BASELINE_WARNING|$REQ012_WARNING" || true)
  if [ -n "$filtered" ]; then
    echo "UNEXPECTED_ERROR_OR_WARNING in $label" | tee -a "$LOG"
    printf '%s\n' "$filtered" | tee -a "$LOG"
    printf '%s\n' "$out"
    exit 1
  fi
  local observed
  observed=$(printf '%s\n' "$out" | grep -m1 "$marker" || true)
  echo "PASS [$commands] $label :: ${observed:-$marker}" | tee -a "$LOG"
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
run_clean 'ship systems smoke' 'MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
run_clean 'completion smoke' 'MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
run_clean 'template b completion smoke' 'MAIN PLAYABLE TEMPLATE B COMPLETE PASS completed=5 current_sequence=6 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_template_b_completion_smoke.gd
run_clean 'input smoke' 'MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
run_clean 'readability smoke' 'MAIN PLAYABLE SLICE READABILITY PASS objective_props=5 blocked=1 ramp=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
run_clean 'main objective variation smoke' 'MAIN PLAYABLE OBJECTIVE VARIATION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
run_clean 'objective progress state smoke' 'OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_state_smoke.gd
run_clean 'objective progress hud label smoke' 'OBJECTIVE PROGRESS HUD LABEL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_hud_label_smoke.gd
run_clean 'save/load service smoke' 'SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=7' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
run_clean 'main save/load smoke' 'MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_save_load_smoke.gd
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
echo "SARGASSO REGRESSION PASS commands=$commands clean_output=true log=$LOG" | tee -a "$LOG"
