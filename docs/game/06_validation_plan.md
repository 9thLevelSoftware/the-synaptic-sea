# 06 Validation Plan

## Core rule

No completion claim without fresh validation evidence.

## Godot binary

`/Users/christopherwilloughby/.local/bin/godot-4.6.2`

## Project root

`/Users/christopherwilloughby/the-synaptic-sea`

## Focused route-control validation

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea --script res://scripts/validation/route_control_state_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
```

Expected markers:

- `ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true`
- `MAIN PLAYABLE ROUTE CONTROL PASS gates=1 opened=1 blockers=0 extraction=true`

## Focused crafting/materials validation

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2

"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/material_state_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/crafting_state_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/station_state_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/recipe_resource_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/quality_tier_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/field_crafting_state_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_crafting_smoke.gd
```

Expected markers:

- `MATERIAL STATE PASS`
- `CRAFTING STATE PASS`
- `STATION STATE PASS`
- `RECIPE RESOURCE PASS`
- `QUALITY TIER PASS`
- `FIELD CRAFTING STATE PASS`
- `MAIN PLAYABLE CRAFTING PASS`

## Focused loot ecosystem validation

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2

"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/rarity_tier_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_distribution_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_table_biome_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/unique_item_state_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/junk_items_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/container_variety_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_loot_ecosystem_smoke.gd
```

Expected markers:

- `RARITY TIER PASS`
- `LOOT DISTRIBUTION PASS`
- `LOOT TABLE BIOME PASS`
- `UNIQUE ITEM STATE PASS`
- `JUNK ITEMS PASS`
- `CONTAINER VARIETY PASS`
- `MAIN PLAYABLE LOOT ECOSYSTEM PASS`

## Focused live main prepare-to-upgrade probe

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2

"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/live_main_prepare_to_upgrade_probe.gd
```

Expected marker:

- `LIVE MAIN PREPARE UPGRADE PROBE PASS stages=7`

## Regression bundle

```bash
set -euo pipefail
# Honor GODOT/ROOT environment overrides (quoted to tolerate spaces in the
# path, e.g. the Windows checkout "The Synaptic Sea"); fall back to the
# original author's macOS paths when unset.
ROOT="${ROOT:-/Users/christopherwilloughby/the-synaptic-sea}"
GODOT="${GODOT:-/Users/christopherwilloughby/.local/bin/godot-4.6.2}"
# Known baseline Godot shutdown lines that appear identically in every
# unchanged smoke (route-control, completion, input, readability, oxygen,
# hazard, ship-systems) and are NOT introduced by the Sargasso hazard code
# or any other Gate 1 runtime system. They are filtered out of the strict
# ERROR/WARNING/SCRIPT ERROR check below; any other ERROR:/WARNING:/SCRIPT ERROR:
# line (parse errors, GDScript runtime errors, validation markers pushed via
# push_error) still fails the bundle. See "Baseline Godot teardown noise" below for the
# audit trail and the exact evidence-gathering command.
BASELINE_ERROR="^ERROR: Capture not registered: 'gdaimcp'\\.$"
# Pre-existing autoload UID noise from a now-removed editor plugin. The
# autoload entry `GDAIMCPRuntime="*uid://dcne7ryelpxmn"` is left in
# project.godot (the gdai-mcp plugin folder is .gitignored) and Godot
# emits three ERRORs on every smoke because the UID no longer resolves.
# They are infrastructure noise, not a smoke failure. Filtered here so
# the regression bundle can run against a clean project. Re-evaluate
# when the gdai-mcp autoload is removed or fixed.
BASELINE_AUTOLOAD_ERRORS='^ERROR: (Unrecognized UID: "uid://dcne7ryelpxmn"\.|Resource file not found: res:// \(expected type: unknown\)$|Failed to instantiate an autoload, can.t load from path: \.$)'
BASELINE_WARNING="^WARNING: ObjectDB instances leaked at exit \(run with --verbose for details\)\.$"
REQ012_WARNING="^WARNING: SaveLoadService: save file rejected by from_dict \\(missing fields or version mismatch\\)$"
# Task 11 (multi-slot save, sibling card) emits this WARNING when the
# smoke's "incompatible-version" snapshot fails migration. It is the
# expected signal on the rejection path, not a failure.
SAVE_MIGRATION_WARNING="^WARNING: SaveLoadService: slot rejected by migration \\(newer than current\\)"
# Task 11 corruption-path smokes (`save_slot_state_smoke` and
# `main_playable_slice_multislot_save_smoke`) deliberately overwrite a
# slot file with `not-a-json...` and then load it to prove the service
# backs the file up under `.corrupt/` instead of loading it. Godot emits
# both the JSON parse error and the service warning on that intentional
# path; they are expected signals, not failures.
TASK11_CORRUPT_PARSE_ERROR="^ERROR: Parse JSON failed\. Error at line 0: Expected 'true', 'false', or 'null', got 'not'$"
TASK11_CORRUPT_SLOT_WARNING="^WARNING: SaveLoadService: slot file is not valid JSON object, slot_id=(slot_01|slot_03)$"
# load_from_blueprint_smoke deliberately calls load_from_blueprint(null) to
# verify the null-blueprint guard; that guard emits this push_error on the
# rejection path. It is the expected signal, not a failure (mirrors the
# REQ-012 save/load rejection WARNING above).
BLUEPRINT_NULL_ERROR="^ERROR: PlayableGeneratedShip\\.load_from_blueprint: blueprint must not be null\$"
# world_save_service_smoke deliberately calls save_world(null) to verify the
# null-snapshot guard; that guard emits this push_warning on the rejection
# path. It is the expected signal, not a failure.
WORLD_SAVE_NULL_WARNING="^WARNING: SaveLoadService: cannot save null world snapshot$"
# Task 13 release_readiness_ledger_smoke (REQ-RL-008) deliberately drives
# the rejection paths (unknown check_id, invalid status, empty
# evidence_path for an external row) to verify the guard contracts. The
# WARNINGs are the expected signal, not a failure. Any other
# ReleaseReadinessLedger: warning still fails the bundle. The regex
# uses unescaped end-of-line anchors (no `\\$` because the bash
# heredoc escape would turn it into a literal `\$` requirement that
# no warning line satisfies; see the validation plan's escaping audit
# note below for the full reasoning).
RL008_UNKNOWN_CHECK_WARNING="^WARNING: ReleaseReadinessLedger: unknown check_id=.*"
RL008_INVALID_STATUS_WARNING="^WARNING: ReleaseReadinessLedger: invalid status=.*"
RL008_EXTERNAL_EMPTY_WARNING="^WARNING: ReleaseReadinessLedger: external evidence rejected, evidence_path is required.*"
run_clean() {
  label="$1"
  marker="$2"
  shift 2
  echo "=== $label ==="
  OUT=$("$@" 2>&1)
  printf '%s\n' "$OUT"
  printf '%s\n' "$OUT" | grep -F -q "$marker"
  FILTERED=$(printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING|SCRIPT ERROR|SCRIPT WARNING):' | grep -Ev "$BASELINE_ERROR|$BASELINE_AUTOLOAD_ERRORS|$BASELINE_WARNING|$REQ012_WARNING|$SAVE_MIGRATION_WARNING|$TASK11_CORRUPT_PARSE_ERROR|$TASK11_CORRUPT_SLOT_WARNING|$BLUEPRINT_NULL_ERROR|$WORLD_SAVE_NULL_WARNING|$RL008_UNKNOWN_CHECK_WARNING|$RL008_INVALID_STATUS_WARNING|$RL008_EXTERNAL_EMPTY_WARNING" || true)
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
run_clean 'save/load service smoke' 'SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
run_clean 'material state smoke' 'MATERIAL STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/material_state_smoke.gd
run_clean 'crafting state smoke' 'CRAFTING STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/crafting_state_smoke.gd
run_clean 'station state smoke' 'STATION STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/station_state_smoke.gd
run_clean 'recipe resource smoke' 'RECIPE RESOURCE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/recipe_resource_smoke.gd
run_clean 'quality tier smoke' 'QUALITY TIER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/quality_tier_smoke.gd
run_clean 'field crafting smoke' 'FIELD CRAFTING STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/field_crafting_state_smoke.gd
run_clean 'main playable crafting smoke' 'MAIN PLAYABLE CRAFTING PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_crafting_smoke.gd
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
run_clean 'menu state smoke' 'MENU STATE PASS menus=2 navigation=true enable_toggle=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/menu_state_smoke.gd
run_clean 'settings state smoke' 'SETTINGS STATE PASS text_scale=1.5 hold_to_tap=true glyph=keyboard' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/settings_state_smoke.gd
run_clean 'tutorial state smoke' 'TUTORIAL STATE PASS once=true dismiss=true codex_unlocks=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/tutorial_state_smoke.gd
run_clean 'map fog state smoke' 'MAP FOG STATE PASS rooms=3 discovered=3 revealed=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/map_fog_state_smoke.gd
run_clean 'controller glyph state smoke' 'CONTROLLER GLYPH STATE PASS schemes=3 action=interact glyph=[E]' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/controller_glyph_state_smoke.gd
run_clean 'tooltip presenter smoke' 'TOOLTIP PRESENTER PASS title=Circuit Board footer=[E] Pick up' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/tooltip_presenter_smoke.gd
run_clean 'main playable ui shell smoke' 'MAIN PLAYABLE UI SHELL PASS boot=main_menu pause=true codex=1 minimap=true hotbar=true tooltip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ui_shell_smoke.gd
run_clean 'ui shell save/load smoke' 'UI SHELL SAVE LOAD PASS restored=true text_scale=2.0 hold_to_tap=true colorblind=deuteranopia glyph=keyboard' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_shell_save_load_smoke.gd
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
run_clean 'gameplay slice builder smoke' 'GAMEPLAY_SLICE_BUILDER PASS all' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gameplay_slice_builder_smoke.gd
run_clean 'item inventory smoke' 'ITEM INVENTORY PASS add=true weight_cap=true round_trip=true legacy_compat=true repair_vocab=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_inventory_smoke.gd
run_clean 'rarity tier smoke' 'RARITY TIER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/rarity_tier_smoke.gd
run_clean 'loot distribution smoke' 'LOOT DISTRIBUTION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_distribution_smoke.gd
run_clean 'loot table biome smoke' 'LOOT TABLE BIOME PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_table_biome_smoke.gd
run_clean 'loot table smoke' 'LOOT TABLE PASS deterministic=true varies_by_seed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_table_smoke.gd
run_clean 'unique item state smoke' 'UNIQUE ITEM STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/unique_item_state_smoke.gd
run_clean 'junk items smoke' 'JUNK ITEMS PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/junk_items_smoke.gd
run_clean 'container variety smoke' 'CONTAINER VARIETY PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/container_variety_smoke.gd
run_clean 'derelict loot smoke' 'DERELICT LOOT PASS searched=true carried=true persists=true home_intact=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_loot_smoke.gd
run_clean 'main loot ecosystem smoke' 'MAIN PLAYABLE LOOT ECOSYSTEM PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_loot_ecosystem_smoke.gd
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
run_clean 'meta progression state smoke' 'META PROGRESSION STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_progression_state_smoke.gd
run_clean 'player progression full smoke' 'PLAYER PROGRESSION FULL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_progression_full_smoke.gd
run_clean 'marker generator smoke' 'MARKER GENERATOR PASS deterministic=true per_cell=3 round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/marker_generator_smoke.gd
run_clean 'sargasso world smoke' 'SARGASSO WORLD PASS in_range_sorted=true generated=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sargasso_world_smoke.gd
run_clean 'scanner state smoke' 'SCANNER STATE PASS nav_off_empty=true scanners_off_detail1=true full_detail=6 round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/scanner_state_smoke.gd
run_clean 'travel controller smoke' 'TRAVEL CONTROLLER PASS propulsion_gate=true range_gate=true generated_node=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_controller_smoke.gd
run_clean 'ship instance smoke' 'SHIP INSTANCE PASS round_trip=true stubs_present=true objective_round_trip=true looted_round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_smoke.gd
run_clean 'travel integration smoke' 'TRAVEL INTEGRATION PASS start_wrapped=true scan_gated=true propulsion_gate=true swapped=true progression_persists=true world_recorded=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_integration_smoke.gd
run_clean 'scanner panel smoke' 'SCANNER PANEL PASS populated=true selection_moves=true travel_invoked=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/scanner_panel_smoke.gd
run_clean 'world snapshot smoke' 'WORLD SNAPSHOT PASS round_trip=true version_gated=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_snapshot_smoke.gd
run_clean 'save slot state smoke' 'SAVE SLOT STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_slot_state_smoke.gd
run_clean 'save migration service smoke' 'SAVE MIGRATION SERVICE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_migration_service_smoke.gd
run_clean 'autosave policy smoke' 'AUTOSAVE POLICY PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/autosave_policy_smoke.gd
run_clean 'main playable multislot save smoke' 'MAIN PLAYABLE MULTISLOT SAVE PASS manual=1 quick=1 world=1 corruption_backed_up=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_multislot_save_smoke.gd
run_clean 'world save service smoke' 'WORLD SAVE SERVICE PASS disk_round_trip=true rejects_null=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_service_smoke.gd
run_clean 'world persist restore smoke' 'WORLD PERSIST RESTORE PASS registered=true state_preserved=true revisit_restores=true travel_home=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_persist_restore_smoke.gd
run_clean 'world save anywhere smoke' 'WORLD SAVE ANYWHERE PASS away_save=true location_restored=true state_restored=true home_save=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_anywhere_smoke.gd
run_clean 'derelict objective controller smoke' 'DERELICT OBJECTIVE CONTROLLER PASS configure=true cleared_on_goal=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_objective_controller_smoke.gd
run_clean 'derelict gameplay smoke' 'DERELICT GAMEPLAY PASS built=true cleared=true persists=true home_intact=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_gameplay_smoke.gd
run_clean 'repair loop smoke' 'REPAIR LOOP PASS opening=true channeled=true persists=true home_intact=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_loop_smoke.gd
run_clean 'repair consume smoke' 'REPAIR CONSUME PASS repaired=true consumed=true cascade=true rejects=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_consume_smoke.gd
run_clean 'lifeboat travel gate smoke' 'LIFEBOAT TRAVEL GATE PASS blocked_offline=true travels_after_repair=true home_always=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/lifeboat_travel_gate_smoke.gd
run_clean 'docking manager model smoke' 'DOCKING MANAGER PASS aligned=true relationship=true undock=true rejects=true self_guard=true resevers=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/docking_manager_smoke.gd
run_clean 'ship occupancy model smoke' 'SHIP OCCUPANCY PASS contained=true tiebreak=host outside=null malformed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_occupancy_smoke.gd
run_clean 'ship instance dock fields smoke' 'SHIP INSTANCE DOCK FIELDS PASS alias=true aabb=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_dock_fields_smoke.gd
run_clean 'dock ports model smoke' 'DOCK PORTS PASS lifeboat=true derelict=true empty_guard=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_ports_smoke.gd
run_clean 'dock copresence smoke' 'DOCK COPRESENCE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_copresence_smoke.gd
run_clean 'occupancy flip smoke' 'OCCUPANCY FLIP PASS derelict=true home=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/occupancy_flip_smoke.gd
run_clean 'canonical opening smoke' 'CANONICAL OPENING PASS docked=true aboard_derelict=true prop_offline=true loot=true repair_in_lifeboat=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/canonical_opening_smoke.gd
run_clean 'docking loop smoke' 'DOCKING LOOP PASS opening=true looped=true persisted=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/docking_loop_smoke.gd
run_clean 'dock port types model smoke' 'DOCK PORT TYPES PASS compat=true condition_from_seed=true typed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_port_types_smoke.gd
run_clean 'interior aabb model smoke' 'INTERIOR AABB PASS nondegenerate=true positioned=true contains=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/interior_aabb_smoke.gd
run_clean 'boot dock aligned smoke' 'BOOT DOCK ALIGNED PASS flush=true gap_lt_0p5=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/boot_dock_aligned_smoke.gd
run_clean 'dock breach model smoke' 'DOCK BREACH PASS intact_instant=true broken_channel=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dock_breach_smoke.gd
run_clean 'bridge terminal node smoke' 'BRIDGE TERMINAL SMOKE PASS ship=ship_test' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bridge_terminal_smoke.gd
run_clean 'physical travel smoke' 'PHYSICAL TRAVEL PASS aboard_lifeboat=true flush=true barrier_closed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/physical_travel_smoke.gd
run_clean 'boarding flip smoke' 'BOARDING FLIP PASS closed_in_lifeboat=true barrier_opens=true flips_to_host=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/boarding_flip_smoke.gd
run_clean 'docking persistence smoke' 'DOCKING PERSISTENCE PASS dock_edge=true occupancy=true opened_port=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/docking_persistence_smoke.gd
run_clean 'ship access smoke' 'SHIP ACCESS SMOKE PASS owner=player_local access=2 ship_owner=player_local' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_access_smoke.gd
run_clean 'bridge terminal login smoke' 'BRIDGE TERMINAL LOGIN SMOKE PASS piloted=lifeboat' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bridge_terminal_login_smoke.gd
run_clean 'pilot switch smoke' 'PILOT SWITCH SMOKE PASS piloted=lifeboat' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/pilot_switch_smoke.gd
run_clean 'rigid pair travel smoke' 'RIGID PAIR TRAVEL SMOKE PASS piloted=lifeboat' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/rigid_pair_travel_smoke.gd
run_clean 'claim persistence smoke' 'CLAIM PERSISTENCE SMOKE PASS piloted=ship_0:0:0 owner=player_local' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/claim_persistence_smoke.gd
run_clean 'hangar bay model smoke' 'HANGAR BAY SMOKE PASS slots=2 size=1 occupant=0' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_bay_smoke.gd
run_clean 'hangar port smoke' 'HANGAR PORT SMOKE PASS slots=3 size=2 cargo_slots=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_port_smoke.gd
run_clean 'hangar control node smoke' 'HANGAR CONTROL SMOKE PASS dock=1 launch=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_control_smoke.gd
run_clean 'bay dock/launch smoke' 'BAY DOCK LAUNCH SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bay_dock_launch_smoke.gd
run_clean 'recursive travel smoke' 'RECURSIVE TRAVEL SMOKE PASS piloted_geom=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/recursive_travel_smoke.gd
run_clean 'hangar persistence smoke' 'HANGAR PERSISTENCE SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hangar_persistence_smoke.gd
run_clean 'bay travel unbay smoke' 'BAY TRAVEL UNBAY SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bay_travel_unbay_smoke.gd
run_clean 'ship inventory model smoke' 'SHIP INVENTORY SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_inventory_smoke.gd
run_clean 'cargo transfer smoke' 'CARGO TRANSFER SMOKE PASS conserved=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_transfer_smoke.gd
run_clean 'cargo hold smoke' 'CARGO HOLD SMOKE PASS section_a=true deposited=6 withdrew=6 persisted=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_hold_smoke.gd
run_clean 'equipment defs smoke' 'EQUIPMENT DEFS SMOKE PASS slots=3 effects=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_defs_smoke.gd
run_clean 'equipment state smoke' 'EQUIPMENT STATE SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_state_smoke.gd
run_clean 'encumbrance curve smoke' 'EQUIPMENT ENCUMBRANCE SMOKE PASS floor=0.25' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/encumbrance_smoke.gd
run_clean 'equipment carts main-scene smoke' 'EQUIPMENT CARTS SMOKE PASS section_a=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_carts_smoke.gd
run_clean 'cart state model smoke' 'CART STATE SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cart_state_smoke.gd
run_clean 'cart control node smoke' 'CART CONTROL SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cart_control_smoke.gd
run_clean 'cargo move-item primitive' 'CARGO MOVE ITEM SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_move_item_smoke.gd
run_clean 'inventory selection model' 'INVENTORY SELECTION MODEL SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_selection_model_smoke.gd
run_clean 'inventory panel' 'INVENTORY PANEL SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_panel_smoke.gd
run_clean 'inventory UI slice' 'INVENTORY UI SLICE SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_inventory_ui_smoke.gd
run_clean 'inventory widget layer' 'INVENTORY WIDGET SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_widget_smoke.gd
run_clean 'oxygen+equipment drain' 'OXYGEN EQUIPMENT DRAIN SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_equipment_drain_smoke.gd
run_clean 'suit oxygen slice' 'SUIT OXYGEN SLICE SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_suit_oxygen_smoke.gd
run_clean 'player vitals model' 'PLAYER VITALS MODEL SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_vitals_model_smoke.gd
run_clean 'main playable slice hud' 'MAIN PLAYABLE SLICE HUD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hud_smoke.gd
run_clean 'player vitals hud' 'MAIN PLAYABLE VITALS HUD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_hud_smoke.gd
run_clean 'export presets smoke' 'EXPORT PRESETS PASS presets=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/export_presets_smoke.gd
run_clean 'achievement state smoke' 'ACHIEVEMENT STATE PASS unlocked=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/achievement_state_smoke.gd
run_clean 'localization catalog smoke' 'LOCALIZATION CATALOG PASS languages=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/localization_catalog_smoke.gd
run_clean 'demo scope gate smoke' 'DEMO SCOPE GATE PASS build_kind=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/demo_scope_gate_smoke.gd
run_clean 'release readiness ledger smoke' 'RELEASE READINESS LEDGER PASS rows=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/release_readiness_ledger_smoke.gd
run_clean 'template C traversal smoke' 'TEMPLATE C TRAVERSAL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/template_c_traversal_smoke.gd
run_clean 'room variant selector smoke' 'ROOM VARIANT SELECTOR PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_variant_selector_smoke.gd
run_clean 'kit catalog smoke' 'KIT CATALOG PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/kit_catalog_smoke.gd
run_clean 'biome profile smoke' 'BIOME PROFILE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/biome_profile_smoke.gd
run_clean 'difficulty profile smoke' 'DIFFICULTY PROFILE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/difficulty_profile_smoke.gd
run_clean 'encounter injector smoke' 'ENCOUNTER INJECTOR PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/encounter_injector_smoke.gd
run_clean 'seed determinism smoke' 'SEED DETERMINISM PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/seed_determinism_smoke.gd
run_clean 'audio bus config smoke' 'AUDIO BUS CONFIG PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_bus_config_smoke.gd
run_clean 'ambient zone state smoke' 'AMBIENT ZONE STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ambient_zone_state_smoke.gd
run_clean 'sfx event router smoke' 'SFX EVENT ROUTER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sfx_event_router_smoke.gd
run_clean 'dynamic music state smoke' 'DYNAMIC MUSIC STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dynamic_music_state_smoke.gd
run_clean 'spatial audio resolver smoke' 'SPATIAL AUDIO RESOLVER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/spatial_audio_resolver_smoke.gd
run_clean 'meta event state smoke' 'META EVENT STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_event_state_smoke.gd
run_clean 'main playable slice audio smoke' 'MAIN PLAYABLE AUDIO PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_audio_smoke.gd
run_clean 'audio save load smoke' 'AUDIO SAVE LOAD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_save_load_smoke.gd
run_clean 'vitals state smoke' 'VITALS STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_state_smoke.gd
run_clean 'sanity state smoke' 'SANITY STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sanity_state_smoke.gd
run_clean 'radiation state smoke' 'RADIATION STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/radiation_state_smoke.gd
run_clean 'body temperature state smoke' 'BODY TEMPERATURE STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/body_temperature_state_smoke.gd
run_clean 'main playable vitals full smoke' 'MAIN PLAYABLE VITALS FULL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_full_smoke.gd
run_clean 'vitals save load smoke' 'VITALS SAVE LOAD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_state_save_load_smoke.gd
run_clean 'food state smoke' 'FOOD STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_state_smoke.gd
run_clean 'spoilage state smoke' 'SPOILAGE STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/spoilage_state_smoke.gd
run_clean 'cooking state smoke' 'COOKING STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cooking_state_smoke.gd
run_clean 'main playable cooking smoke' 'MAIN PLAYABLE COOKING PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_cooking_smoke.gd
run_clean 'effect dispatcher smoke' 'EFFECT DISPATCHER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/effect_dispatcher_smoke.gd
run_clean 'consumable state smoke' 'CONSUMABLE STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/consumable_state_smoke.gd
run_clean 'medicine state smoke' 'MEDICINE STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/medicine_state_smoke.gd
run_clean 'stimulant state smoke' 'STIMULANT STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/stimulant_state_smoke.gd
run_clean 'addiction state smoke' 'ADDICTION STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/addiction_state_smoke.gd
run_clean 'consumable save load smoke' 'CONSUMABLE SAVE LOAD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/consumable_save_load_smoke.gd
run_clean 'main playable consumables smoke' 'MAIN PLAYABLE CONSUMABLES PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_consumables_smoke.gd
run_clean 'damage pipeline smoke' 'DAMAGE PIPELINE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/damage_pipeline_smoke.gd
run_clean 'armor resolver smoke' 'ARMOR RESOLVER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/armor_resolver_smoke.gd
run_clean 'status effects smoke' 'STATUS EFFECTS PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/status_effects_smoke.gd
run_clean 'detection state smoke' 'DETECTION STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/detection_state_smoke.gd
run_clean 'threat ai state smoke' 'THREAT AI STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_ai_state_smoke.gd
run_clean 'main playable combat encounter smoke' 'MAIN PLAYABLE COMBAT ENCOUNTER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_combat_encounter_smoke.gd
run_clean 'hydroponics state smoke' 'HYDROPONICS STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hydroponics_state_smoke.gd
run_clean 'synthesizer state smoke' 'SYNTHESIZER STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/synthesizer_state_smoke.gd
run_clean 'food save load smoke' 'FOOD SAVE LOAD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_save_load_smoke.gd
run_clean 'power grid state smoke' 'POWER GRID STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/power_grid_state_smoke.gd
run_clean 'life support state smoke' 'LIFE SUPPORT STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_support_state_smoke.gd
run_clean 'sustenance state smoke' 'SUSTENANCE STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sustenance_state_smoke.gd
run_clean 'main playable ship systems expanded smoke' 'MAIN PLAYABLE SHIP SYSTEMS EXPANDED PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd
run_clean 'cross system dependency smoke' 'CROSS SYSTEM DEPENDENCY PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cross_system_dependency_smoke.gd
run_clean 'e2e survival loop smoke' 'E2E SURVIVAL LOOP PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/e2e_survival_loop_smoke.gd
run_clean 'e2e combat loot craft smoke' 'E2E COMBAT LOOT CRAFT PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/e2e_combat_loot_craft_smoke.gd
run_clean 'e2e ship meta loop smoke' 'E2E SHIP META LOOP PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/e2e_ship_meta_loop_smoke.gd
run_clean 'product audit smoke' 'PRODUCT AUDIT PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/product_audit_smoke.gd
run_clean 'systems map currency smoke' 'SYSTEMS MAP CURRENCY PASS' python3 "$ROOT/scripts/validation/systems_map_currency_smoke.py"
run_clean 'requirement trace smoke' 'REQUIREMENT TRACE PASS' python3 "$ROOT/scripts/validation/requirement_trace_smoke.py"
run_clean 'kanban manifest smoke' 'KANBAN MANIFEST PASS' python3 "$ROOT/scripts/validation/kanban_manifest_smoke.py"
echo 'SARGASSO REGRESSION PASS commands=166 clean_output=true'
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

The Phase 1 `load_from_blueprint_smoke` adds one additional expected
`ERROR:` line that is part of its null-guard contract test:

- `ERROR: PlayableGeneratedShip.load_from_blueprint: blueprint must not be null`
  — emitted by `scripts/procgen/playable_generated_ship.gd` when
  `load_from_blueprint(null)` is called. The smoke deliberately calls it with
  `null` to verify the guard rejects bad input; the ERROR is the expected
  signal, not a failure. Filtered by the strict check above via
  `$BLUEPRINT_NULL_ERROR`; any other `load_from_blueprint:` error still fails
  the bundle.

The world-persistence sub-project (ADR-0012) travel integration smoke
(`travel_integration_smoke.gd`) instantiates and then frees a full
`PlayableGeneratedShip` scene within a single headless run. Its travel and
world-load paths detach the starting ship's gameplay roots (interaction /
affordance / route / oxygen / tool / fire / arc) and the original home hull
from the coordinator without re-attaching them when the world load restores a
derelict. The smoke's `_teardown_and_quit` frees each of those detached roots
explicitly (along with the active scene under `main_node`) so no physics /
renderer RIDs leak at exit. There is therefore NO RID-leak allowlist for this
smoke — any `RID allocations`/`Leaked instance dependency`/`resources still in
use`/`Pages in use` line from any smoke fails the bundle.

The world-persistence sub-project (ADR-0012) adds one additional expected
`WARNING:` line emitted by the world save service smoke when it calls
`save_world(null)` to verify the null-snapshot guard:

- `WARNING: SaveLoadService: cannot save null world snapshot`
  — emitted by `scripts/systems/save_load_service.gd` `save_world()` when
  called with a `null` argument. The `world_save_service_smoke` deliberately
  passes `null` to verify the guard rejects the request; the WARNING is the
  expected signal, not a failure. Filtered by `$WORLD_SAVE_NULL_WARNING`; any
  other `SaveLoadService: cannot save` warning still fails the bundle.

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
- [x] Loot ecosystem package smokes: `scripts/validation/rarity_tier_smoke.gd`, `scripts/validation/loot_distribution_smoke.gd`, `scripts/validation/unique_item_state_smoke.gd`, and `scripts/validation/main_playable_slice_loot_ecosystem_smoke.gd` (expected markers `RARITY TIER PASS`, `LOOT DISTRIBUTION PASS`, `UNIQUE ITEM STATE PASS`, and `MAIN PLAYABLE LOOT ECOSYSTEM PASS`). Added to regression bundle.
- [x] Fire hazard model smoke: `scripts/validation/fire_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_fire_smoke.gd` (REQ-010).
- [x] Golden fire-zone source marker smoke: `scripts/validation/golden_fire_zone_source_marker_smoke.gd` — pins the Gate 2 fire zone to a side link declared in BOTH `layout.json` and `gameplay_slice.json`, asserts target room is non-critical and not the obj3 → obj4 breach corridor, and verifies `FIRE_ZONE_FALLBACK_ROOM_ID` matches the marker. Added to regression bundle.
- [x] Objective variation model smoke: `scripts/validation/objective_progress_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_objective_variation_smoke.gd` (REQ-011). Added to regression bundle.
- [x] Objective HUD-label smoke: `scripts/validation/objective_progress_hud_label_smoke.gd` (REQ-011) — verifies the player-facing "Repair junction" label is shown for `kind == "repair_junction"` while the ship-system `type == "restore_systems"` stays preserved. Added to regression bundle.
- [x] Save/load service smoke: `scripts/validation/save_load_service_smoke.gd` (expected marker `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27`) and main-scene smoke `scripts/validation/main_playable_slice_save_load_smoke.gd` (expected marker `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`) (REQ-012). Added to regression bundle. Marker has risen over time as additive snapshot summaries landed; the current baseline is 27.
- [x] Task 03 crafting/materials package: `scripts/validation/material_state_smoke.gd` (`MATERIAL STATE PASS`), `scripts/validation/crafting_state_smoke.gd` (`CRAFTING STATE PASS`), `scripts/validation/station_state_smoke.gd` (`STATION STATE PASS`), `scripts/validation/recipe_resource_smoke.gd` (`RECIPE RESOURCE PASS`), `scripts/validation/quality_tier_smoke.gd` (`QUALITY TIER PASS`), `scripts/validation/field_crafting_state_smoke.gd` (`FIELD CRAFTING STATE PASS`), and `scripts/validation/main_playable_slice_crafting_smoke.gd` (`MAIN PLAYABLE CRAFTING PASS`). Covers the material catalog, recipe schema, queue/power-aware station state, deterministic quality resolution, field-crafting restrictions, and the additive `RunSnapshot` crafting/material save-load contract with a mid-craft resume path that does not duplicate ingredients.
- [x] Task 05 consumables package: `scripts/validation/effect_dispatcher_smoke.gd` (`EFFECT DISPATCHER PASS`), `scripts/validation/consumable_state_smoke.gd` (`CONSUMABLE STATE PASS`), `scripts/validation/medicine_state_smoke.gd` (`MEDICINE STATE PASS`), `scripts/validation/stimulant_state_smoke.gd` (`STIMULANT STATE PASS`), `scripts/validation/addiction_state_smoke.gd` (`ADDICTION STATE PASS`), `scripts/validation/consumable_save_load_smoke.gd` (`CONSUMABLE SAVE LOAD PASS`), and `scripts/validation/main_playable_consumables_smoke.gd` (`MAIN PLAYABLE CONSUMABLES PASS`). Covers dispatcher routing, category-specific item use, medicine cures, stimulant withdrawal, summary round-trips, hotbar integration, and save/load restoration.
- [x] Task 06 combat / threat / encounter package: `scripts/validation/damage_pipeline_smoke.gd` (`DAMAGE PIPELINE PASS`), `scripts/validation/armor_resolver_smoke.gd` (`ARMOR RESOLVER PASS`), `scripts/validation/status_effects_smoke.gd` (`STATUS EFFECTS PASS`), `scripts/validation/detection_state_smoke.gd` (`DETECTION STATE PASS`), `scripts/validation/threat_ai_state_smoke.gd` (`THREAT AI STATE PASS`), and `scripts/validation/main_playable_slice_combat_encounter_smoke.gd` (`MAIN PLAYABLE COMBAT ENCOUNTER PASS`). Covers deterministic damage resolution, armor wear, effect ticking, player stealth/detection memory, shared threat-state transitions, and save/load restoration of live encounter state.
- [x] REQ-012 auto-save sequence smoke: `scripts/validation/req012_autosave_sequence_smoke.gd` (expected marker `REQ012 AUTOSAVE SEQUENCE CHECK PASS live=2 snapshot=2 file=2 has_save=true`) — permanent regression for the auto-save ordering bug. Completes objective 1 and inspects the in-memory snapshot and the on-disk save BEFORE any manual `request_save()` so the auto-save-only path is locked down. Added to regression bundle.
- [x] Task 11 multi-slot + autosave + migration + permadeath + cloud-manifest smokes (ADR-0031, ADR-0032; REQ-SL-001..012):
  - `scripts/validation/save_slot_state_smoke.gd` (expected marker `SAVE SLOT STATE PASS`) — pure-model proof of `SaveSlotState`/`SaveIndexState` round-trip, multi-slot writes to manual slots, list_slots ordering, cloud manifest sha matches the slot file bytes, corruption detection + `.corrupt/` backup, manual/world slot scope isolation, and `SaveLoadMenu.refresh()` UI seam.
  - `scripts/validation/save_migration_service_smoke.gd` (expected marker `SAVE MIGRATION SERVICE PASS`) — pure-model proof of `SaveMigrationService` walking v1 -> v2 -> v3 deterministically, v1 save without `player_progression_summary` migrating forward and gaining the default, forward-only rejection of newer saves, migrated form persisted to `<slot>.migrated.json`, `PermadeathResolver.record_death` + `has_died_in` + load-from-death-frozen-slot returning null + `clear_death` re-enables loads.
  - `scripts/validation/autosave_policy_smoke.gd` (expected marker `AUTOSAVE POLICY PASS`) — pure-model proof of `AutosavePolicy.tick` cadence + event triggers, rotation through `autosave_a`/`autosave_b`/`autosave_c`, and `try_quicksave` cooldown (10 s default) rejecting the second quicksave inside the cooldown.
  - `scripts/validation/main_playable_slice_multislot_save_smoke.gd` (expected marker `MAIN PLAYABLE MULTISLOT SAVE PASS manual=1 quick=1 world=1 corruption_backed_up=true`) — main-scene end-to-end proof that `PlayableGeneratedShip` can write to a manual slot, a quicksave, and a world slot; that `list_slots()` reports them; that `load_from_slot("slot_01")` restores the slot identity and objective sequence; that an in-place corrupted slot is backed up to `.corrupt/` and marked `corrupt=true` in the index; and that `delete_current_run` (driven by `playable.complete_all_objectives_for_validation`) clears all save state.
- [x] Template B completion smoke: `scripts/validation/main_playable_slice_template_b_completion_smoke.gd` (expected marker `MAIN PLAYABLE TEMPLATE B COMPLETE PASS completed=5 current_sequence=6 run_complete=true`). Added to regression bundle.
- [x] Alternate input smoke: `scripts/validation/main_playable_slice_alternate_input_smoke.gd` (expected marker `MAIN PLAYABLE ALTERNATE INPUT PASS moves_alt=1 interact_alt=1`) — A11Y-P1-002 alternate keyboard binding surface. Verifies the InputMap carries both WASD/E/F5/F9 (original) and Arrows / Enter / Space / KP_Enter (alternates) on the movement and interact actions, that save/load (F5/F9) stays single-binding and non-conflicting, that the HUD prompt reflects the expanded surface, and that driving the action through `Input.action_press` (the exact code path the engine uses for a held arrow key) advances the player and registers an interact press. Added to regression bundle.
- [x] Alternate input events smoke: `scripts/validation/playable_slice_alternate_input_smoke.gd` (expected marker `PLAYABLE SLICE ALTERNATE INPUT EVENTS PASS static_bindings=ok moves_alt=1 interact_alt=3 enter=1 space=1 kp_enter=1`) — A11Y-P1-002 companion to the alternate input smoke above. Proves that a REAL `InputEventKey` routed through `Input.parse_input_event()` (the same code path a player's actual keypress takes) reaches the engine's input layer: KEY_RIGHT drives `move_right` via the player's `Input.get_action_strength` poll and the player's `global_position` advances on +X, and KEY_ENTER / KEY_SPACE / KEY_KP_ENTER each fire `PlayerController.interact_requested` exactly once (the same signal the original KEY_E binding fires via `PlayerController._unhandled_input`'s `event.is_action_pressed("interact")` watch). Drops the static-binding check so any silent removal of an alternate keycode from `ensure_default_input_actions()` fails this smoke with `static bindings incomplete: ...`, even when the WASD/E smoke and the action-press alternate smoke still pass. Added to regression bundle.
- [x] A11Y-P1-001 text scale smoke: `scripts/validation/main_playable_slice_text_scale_smoke.gd` (expected marker `MAIN PLAYABLE TEXT SCALE PASS scales=3 default=1.0x1.5x2.0 runtime_text=present`) — proves the single `AccessibilitySettings` seam drives both the HUD `font_size` and `custom_minimum_size` (default 1.0 reproduces font=18, panel=520x250) and the world `Label3D.pixel_size` for the breach unsafe marker and fire zone label (default 0.0035 reproduces exactly), and that the same seam scales consistently to 1.5x (font=27, panel=780x375, pixel=0.002333) and 2.0x (font=36, panel=1040x500, pixel=0.001750) while HUD text remains sourced from runtime state at every scale. Added to regression bundle.
- [x] UI / UX / accessibility package smokes (REQ-UI-001..016, ADR-0033):
  - `scripts/validation/menu_state_smoke.gd` (expected marker `MENU STATE PASS menus=2 navigation=true enable_toggle=true`) — pure-model proof that the menu stack opens, navigates, confirms, cancels, and accepts enable/disable overrides without scene-tree access.
  - `scripts/validation/settings_state_smoke.gd` (expected marker `SETTINGS STATE PASS text_scale=1.5 hold_to_tap=true glyph=keyboard`) — pure-model proof that `SettingsState` mutates, applies into the shared `AccessibilitySettings` seam, and round-trips through `get_summary` / `apply_summary`.
  - `scripts/validation/tutorial_state_smoke.gd` (expected marker `TUTORIAL STATE PASS once=true dismiss=true codex_unlocks=1`) — pure-model proof that tutorial triggers are once-per-pair, dismissible, and unlock codex help.
  - `scripts/validation/map_fog_state_smoke.gd` (expected marker `MAP FOG STATE PASS rooms=3 discovered=3 revealed=2`) — pure-model proof of deterministic room discovery, reveal, and tracked-room bookkeeping.
  - `scripts/validation/controller_glyph_state_smoke.gd` (expected marker `CONTROLLER GLYPH STATE PASS schemes=3 action=interact glyph=[E]`) — pure-model proof that controller glyph lookups resolve per scheme with keyboard fallback.
  - `scripts/validation/tooltip_presenter_smoke.gd` (expected marker `TOOLTIP PRESENTER PASS title=Circuit Board footer=[E] Pick up`) — pure-model proof that catalog queries resolve to payloads for known `(subject_kind, subject_id)` pairs.
  - `scripts/validation/main_playable_slice_ui_shell_smoke.gd` (expected marker `MAIN PLAYABLE UI SHELL PASS boot=main_menu pause=true codex=1 minimap=true hotbar=true tooltip=true`) — end-to-end proof that the playable boots into the main menu, exposes the runtime UI shell, reaches codex / minimap / hotbar / tooltip surfaces, and unlocks codex content from a dismissed tutorial.
  - `scripts/validation/ui_shell_save_load_smoke.gd` (expected marker `UI SHELL SAVE LOAD PASS restored=true text_scale=2.0 hold_to_tap=true colorblind=deuteranopia glyph=keyboard`) — end-to-end proof that `RunSnapshot.settings_summary` survives save/load and reapplies into the live UI shell.
  - All eight Task 09 smokes are registered in the regression bundle above.
- [x] Hub/meta progression smoke (deferred past Gate 2 per ADR-0003).
- [x] Audio / Music / Spatial / Voice / Meta Events package (REQ-AU-001..010, ADR-0029):
  - `scripts/validation/audio_bus_config_smoke.gd` (expected marker `AUDIO BUS CONFIG PASS buses=7 default=true summary_round_trip=true`) — validates the seven-bus layout, rejects malformed configs, round-trips `get_summary` / `apply_summary`.
  - `scripts/validation/ambient_zone_state_smoke.gd` (expected marker `AMBIENT ZONE STATE PASS roles_changed=2 crossfades_completed=1 threat_applied=true`) — drives role changes with a 1.0s crossfade, verifies threat-driven gain multiplier above 0.5 threshold, rejects unknown roles.
  - `scripts/validation/sfx_event_router_smoke.gd` (expected marker `SFX EVENT ROUTER PASS routed=0 dropped=0 captions=3`) — routes SFX/UI/meta/voice events to the right buses, drops unknown ids, applies cooldown, queues and drains captions.
  - `scripts/validation/dynamic_music_state_smoke.gd` (expected marker `DYNAMIC MUSIC STATE PASS states_visited=4 crossfade_changed=true`) — walks EXPLORATION → TENSION → COMBAT → CRITICAL under the priority rules and verifies the layer crossfade advances toward target gains.
  - `scripts/validation/spatial_audio_resolver_smoke.gd` (expected marker `SPATIAL AUDIO RESOLVER PASS atten_ref=0 atten_max=-36 occluded=-6 determinism=true`) — pin ref/max/mid attenuation values, occlusion penalty, determinism across repeat calls, NaN/Inf safety.
  - `scripts/validation/meta_event_state_smoke.gd` (expected marker `META EVENT STATE PASS fired=3 pending=0 deterministic_seed=true`) — drives the default schedule to completion, verifies no re-fire, seed-derived offset determinism, custom `events=` schedule honored.
  - `scripts/validation/main_playable_slice_audio_smoke.gd` (expected marker `MAIN PLAYABLE AUDIO PASS buses=6 routed=4 fired_meta=3 ambient_role=engine`) — loads the playable against `coherent_ship_002`, asserts AudioManager built with six per-bus AudioStreamPlayer children, routes SFX events through SfxEventRouter + AudioStreamPlayer pool, spawns a spatial AudioStreamPlayer3D, drives an ambient role change with crossfade completion, transitions music to TENSION via hazard flag, fires default meta-events, and round-trips the audio summary through JSON.
  - `scripts/validation/audio_save_load_smoke.gd` (expected marker `AUDIO SAVE LOAD PASS summary_keys=6 round_trip=true`) — drives the playable to a non-default audio state, saves through `SaveLoadService`, reloads, applies the loaded `audio_summary` to a fresh AudioManager, and asserts every sub-model (bus_config volumes/mutes, ambient role, sfx router routed_count + cooldown, music state, meta_event fired_count) is restored.
  - All eight entries added to the regression bundle; `save_load_service_smoke.gd` `summaries` count updated from 8 to 9 to include the new `audio_summary` field on `RunSnapshot`.
- [x] GUT suite if/when adopted by ADR.
- [x] Performance baseline smoke: `scripts/validation/performance_profiler.gd` (expected marker `PERFORMANCE BASELINE PASS templates=3`) — first baseline numbers established 2026-06-19 at `docs/game/performance_baseline.md`. Headless harness covers load time, procgen time, peak Godot static memory, and end-of-run OS RSS across the two known procgen templates plus the main playable scene. Windowed FPS at `scripts/validation/windowed_fps_capture.gd` is intentionally NOT in the bundle (requires a display server); it is the source of truth for the frame-time target and is run on demand during Gate 3 / Gate 4 review. Added to regression bundle.
- [x] Junction calibrator model smoke: `scripts/validation/junction_calibrator_state_smoke.gd` (expected marker `JUNCTION CALIBRATOR STATE PASS required_steps=2 consumed=true`) and main-scene smoke `scripts/validation/main_playable_slice_junction_calibrator_smoke.gd` (expected marker `MAIN PLAYABLE JUNCTION CALIBRATOR PASS acquired=true required_steps=2 consumed=true`) (REQ-014). Added to regression bundle. The main-scene smoke registers a synthetic 3-step junction through `register_junction_sequence_for_validation` so it asserts the exact `required_steps=2` post-calibration marker without depending on the seed template's exact step count (the seed template's sequence 2 is a 2-step junction; REQ-014's spec example requires a 3-step reduction target).
- [x] Junction calibrator save/load smoke: `scripts/validation/main_playable_slice_junction_calibrator_save_load_smoke.gd` (expected marker `MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS carried_load=true consumed_load=true next_frame_interaction=true`) — permanent regression for the two blocking findings from review t_80dcea4b. Drives the actual seed sequence 2 repair_junction through save/load in both carried and consumed/applied save states, including a real next-frame interaction after each load. Asserts the live coordinator path leaves the objective_progress model complete after the calibrator reduces a real 2-step junction to 1 (the pre-calibration `required_steps` snapshot lets `complete_step` fire on the first interaction instead of being skipped), and that post-load interactions survive the rebuild of the HUD layer / ObjectiveTracker that previously crashed with "Nonexistent function 'mark_completed' in base 'previously freed'". Also locks down the reload pickup-marker reconciliation (carried = hidden, spent = hidden) and the JSON-string-int-key round-trip in `ObjectiveProgressState.apply_summary` that would otherwise silently drop the per-sequence `calibrator_applied` flag. Added to regression bundle.
- [x] Electrical-arc hazard model smoke: `scripts/validation/electrical_arc_state_smoke.gd` (expected marker `ARC STATE PASS cycles=2 phases=4 passability_switches=4`) and main-scene smoke `scripts/validation/main_playable_slice_arc_smoke.gd` (expected marker `MAIN PLAYABLE ARC PASS state=DISCHARGED cycles=2 blocked_arcing=true blocked_discharged=false`) (REQ-013). The pure model smoke advances the cycle through two full DISCHARGED -> ARCING -> DISCHARGED rounds and asserts the phase / passability counts match the ADR-0005 contract; it also round-trips the summary through `apply_summary()` and verifies a wrong `hazard_kind` is rejected. The main-scene smoke drives the same model through `playable.electrical_arc_state.tick(...)` against template 002 (which carries the new `arc_side_01` non-critical side branch) and asserts collision is enabled only while ARCING. Both are added to the regression bundle.
- [x] Phase 1 walkable-ship gate smokes (procgen layout pipeline → walkable start scenario):
  - `scripts/validation/gameplay_slice_builder_smoke.gd` (expected marker `GAMEPLAY_SLICE_BUILDER PASS all 9 layouts produced valid slices loot_containers=true salvage_tables=true`) — `GameplaySliceBuilder.build()` produces a valid gameplay slice (distinct start/goal rooms, sequenced objectives with `approach_cell`, empty hazard-zone arrays, plus the sub-project #3 `loot_containers` array and a `loot_table` on every salvage objective) across all 3 templates × 3 seeds.
  - `scripts/validation/life_boat_layout_smoke.gd` (expected marker `LIFE_BOAT_LAYOUT PASS`) — `LifeBoatBuilder.build_layout()` emits a layout.json-compatible 3-room Dict (airlock/bridge/engineering) with structural placements, ≥2 room links, and a prototype carrying start/goal rooms.
  - `scripts/validation/start_scenario_smoke.gd` (expected marker `START_SCENARIO PASS`) — full start scenario: derelict layout through the pipeline + gameplay slice loads via `GeneratedShipLoader`, a nav mesh bakes from floor cells, and the life boat layout builds. The transient loader Node3D is freed before quit so no instantiated geometry/physics/nav RIDs leak into the strict ERROR/WARNING check.
  - `scripts/validation/procgen_walkability_smoke.gd` (expected marker `WALKABILITY PASS`) — definitive Phase 1 gate: generates a ship from seed, bakes a nav mesh, and walks a `NavigationAgent3D` from the start room through every objective room to the goal. Proves the spec exit criteria "rooms connect, geometry loads, player can walk through."
  All four added to the regression bundle (`commands=42`; bundle later extended to `commands=47` by Phase 2 ship-systems smokes).
- [x] ADR-0005 hazard contract static smoke: `scripts/validation/hazard_contract_smoke.gd` (expected marker `HAZARD CONTRACT PASS models=3 phase_timer_owners=2 wrong_kind_rejected=3 configure_dict=3`) — structural (no runtime tick) assertion that catches the three review-recycle findings on REQ-013 / REQ-014 hazard models: (1) FireState and ElectricalArcState MUST own a `PhaseTimer` instance and translate its `Phase.A/B` output into their own enum, (2) `get_summary()` MUST include `hazard_kind` on every model, and (3) `apply_summary()` MUST reject a wrong-kind summary. Also asserts OxygenState does NOT own a `PhaseTimer` (negative decision from ADR-0005: resource-drain hazards do not need timer phases) and that the `PhaseTimer` helper itself does not carry a `HAZARD_KIND` discriminator. Locks down the `configure(config: Dictionary)` uniform boundary from the ADR-0005 HazardStateContract. Added to regression bundle.
- [x] Phase 2 ship-systems model smokes (System 2 / ADR-0008): `ship_subcomponent_smoke.gd` (`SHIP SUBCOMPONENT PASS`), `ship_system_smoke.gd` (`SHIP SYSTEM PASS`), `life_support_system_smoke.gd` (`LIFE SUPPORT SYSTEM PASS`), `ship_systems_definitions_smoke.gd` (`SHIP SYSTEMS DEFINITIONS PASS`), and `ship_systems_manager_smoke.gd` (`SHIP SYSTEMS MANAGER PASS` — the Phase 2 gate: deterministic build, dependency cascade, advance/oxygen-drain, parameterized repair, and full round-trip). All five added to the regression bundle. The manager is intentionally NOT yet wired into the live SaveLoadService snapshot (build-alongside; `summaries=7` unchanged).
- [x] Sub-project #4 opening repair loop integration smoke: `scripts/validation/repair_loop_smoke.gd` (expected marker `REPAIR LOOP PASS opening=true channeled=true persists=true home_intact=true`) — main-scene end-to-end proof that the lifeboat boots with propulsion offline (nav_linkage broken by `_apply_lifeboat_opening_damage`), guaranteed starting loot (container `start_supply_a` uses `repair_parts_starter` — 1 roll, circuit_board only) yields exactly one circuit_board, the timed channel repair is NOT instant (0.01 s tick leaves it incomplete, 999 s advance completes it), propulsion comes online, a previously-blocked jump succeeds, the repaired state survives a disk save/load, and the player returns home with `away_from_start=false`. Added to regression bundle (`commands=71`). Golden slice data fix: `data/items/loot_tables.json` adds `repair_parts_starter` (1 roll, circuit_board guaranteed) and `data/procgen/golden/coherent_ship_001/gameplay_slice.json` changes `start_supply_a.loot_table` from `repair_parts_common` (2 rolls, probabilistic) to `repair_parts_starter` (deterministic).
- [x] Sub-project #4 repair consume smoke: `scripts/validation/repair_consume_smoke.gd` (expected marker `REPAIR CONSUME PASS repaired=true consumed=true cascade=true rejects=true`) — pure-model proof that `ShipSystemsManager.repair_with_inventory` consumes parts on success, triggers the dependency cascade, and rejects repair when parts or skill are insufficient. Added to regression bundle (`commands=72`).
- [x] Sub-project #4 lifeboat travel gate smoke: `scripts/validation/lifeboat_travel_gate_smoke.gd` (expected marker `LIFEBOAT TRAVEL GATE PASS blocked_offline=true travels_after_repair=true home_always=true`) — proves the lifeboat is travel-blocked when propulsion is offline, travel succeeds after repair, and `travel_home()` is always available (no-strand guarantee). Added to regression bundle (`commands=73`).
- [x] Phase 5a Task 6 dock copresence smoke: `scripts/validation/dock_copresence_smoke.gd` (expected marker `DOCK COPRESENCE PASS`) — proves home + lifeboat + traveled derelict are all co-present in-tree (`active_ship_root_count >= 3`), ship origins are spatially separated, and loot containers target the correct ship. Added to regression bundle (`commands=74`).
- [x] Phase 5a Task 6 occupancy flip smoke: `scripts/validation/occupancy_flip_smoke.gd` (expected marker `OCCUPANCY FLIP PASS derelict=true home=true`) — proves `recompute_occupancy()` flips `current_occupancy` when the player walks between the home derelict and a traveled derelict. Added to regression bundle (`commands=75`).
- [x] Phase 5a Task 7 canonical opening smoke: `scripts/validation/canonical_opening_smoke.gd` (expected marker `CANONICAL OPENING PASS docked=true aboard_derelict=true prop_offline=true loot=true`) — proves the docked-pair canonical opening: lifeboat is present and docked to home_ship at boot, player starts aboard the home derelict, propulsion is offline, and home loot containers yield a circuit_board. Added to regression bundle (`commands=76`).
- [x] Phase 5a Task 8 docking loop persistence smoke: `scripts/validation/docking_loop_smoke.gd` (expected marker `DOCKING LOOP PASS opening=true looped=true persisted=true`) — end-to-end proof that the canonical docked-pair opening survives a full repair→travel→home loop AND a disk save/load: lifeboat is non-null with `parent_ship == home_ship` and `active_ship_root_count >= 2` at boot, propulsion goes operational after looting circuit_board + repairing nav_linkage, travel succeeds, and after `request_save()`/`request_load()` the lifeboat is rebuilt + re-docked and the repair persists. Fix applied to `playable_generated_ship.gd`: `current_ship = null` moved outside the `if away_from_start:` guard in `_reset_runtime_for_reload()` so `_on_ship_loaded`'s `if current_ship == null` guard triggers `_build_lifeboat_at_home()` on reload-from-home (not just reload-from-derelict). Added to regression bundle (`commands=77`).
- [x] Task 12 procedural generation expansion (REQ-PG-001..012 / ADR-0029): seven new model smokes — `template_c_traversal_smoke.gd` (`TEMPLATE C TRAVERSAL PASS`), `room_variant_selector_smoke.gd` (`ROOM VARIANT SELECTOR PASS`), `kit_catalog_smoke.gd` (`KIT CATALOG PASS`), `biome_profile_smoke.gd` (`BIOME PROFILE PASS`), `difficulty_profile_smoke.gd` (`DIFFICULTY PROFILE PASS`), `encounter_injector_smoke.gd` (`ENCOUNTER INJECTOR PASS`), `seed_determinism_smoke.gd` (`SEED DETERMINISM PASS`). Headless proof that the seven pure-model classes (RoomVariantSelector, KitCatalog, TemplateCTraversal, BiomeProfile, DifficultyProfile, EncounterInjector, SeedDeterminismContract) meet the package acceptance criteria: six+ templates selectable by seed, biome+difficulty composition clamped to `[0.0, 3.0]`, encounter markers skip critical-path rooms, FNV-1a 64-bit pipeline match is byte-equal across runs. Layout JSON schema bumps from `1.1.0` to `1.2.0` with a single additive new key (`encounters`); the existing `layout_serializer_smoke.gd` assertion was updated to expect the new schema version. Added to regression bundle (`commands=132`; bundle was `commands=125` before this package).
- [x] Task 04 loot ecosystem smokes (REQ-LE-001..009 / ADR-0037): `rarity_tier_smoke.gd` (`RARITY TIER PASS`), `loot_distribution_smoke.gd` (`LOOT DISTRIBUTION PASS deterministic=true unique_filtered=true junk_yields=2`), `loot_table_biome_smoke.gd` (`LOOT TABLE BIOME PASS variants=2 changed=true`), `unique_item_state_smoke.gd` (`UNIQUE ITEM STATE PASS claimed=1 codex=2`), `junk_items_smoke.gd` (`JUNK ITEMS PASS items=4 yields=8`), `container_variety_smoke.gd` (`CONTAINER VARIETY PASS kinds=4 placed=2`), and `main_playable_slice_loot_ecosystem_smoke.gd` (`MAIN PLAYABLE LOOT ECOSYSTEM PASS marker=0:0:0 searched=true feedback=true captions=1`). Together they lock the full package contract: deterministic rarity-aware rolling, biome/depth/container variation, once-per-world unique tracking, junk yield catalogs, visible container subtypes, and an end-to-end gameplay path that proves the HUD feedback line, caption-backed audio seam, rarity-bordered inventory row, and save/load persistence all fire from a real loot search.
- [x] Task 13 release-distribution smokes (`commands=125`):
- [x] Task 01 survival vitals smokes (REQ-SV-001..008 / ADR-0034):
  - `scripts/validation/vitals_state_smoke.gd` (expected marker `VITALS STATE PASS health=%.1f stamina=%.1f hunger=%.1f thirst=%.1f`) — pure-model proof for REQ-SV-001: health, stamina, hunger, thirst drain/recovery, hunger->stamina cascade, thirst->vision warning, temperature->thirst multiplier, radiation->health drain, and apply_summary round-trip.
  - `scripts/validation/sanity_state_smoke.gd` (expected marker `SANITY STATE PASS drain=%.1f recovery=%.1f pressure=true`) — pure-model proof for REQ-SV-002: sanity drain in unsafe zones, recovery in safe zones, perception pressure below 40%, and apply_summary round-trip.
  - `scripts/validation/radiation_state_smoke.gd` (expected marker `RADIATION STATE PASS accumulation=true drain=true decay=true`) — pure-model proof for REQ-SV-003: radiation accumulation in zones, passive health drain above 50%, decay outside zones, and apply_summary round-trip.
  - `scripts/validation/body_temperature_state_smoke.gd` (expected marker `BODY TEMPERATURE STATE PASS safe=false extreme=true recovery=true`) — pure-model proof for REQ-SV-004: temperature rise in extreme zones, thirst multiplier when unsafe, recovery toward default, and apply_summary round-trip.
  - `scripts/validation/main_playable_slice_vitals_full_smoke.gd` (expected marker `MAIN PLAYABLE VITALS FULL PASS panel=true health=true stamina=true hunger=true thirst=true sanity=true radiation=true temperature=true status=true`) — main-scene proof for REQ-SV-007: HUD panel under `hud_layer`, all seven vital categories displayed, cascade warnings visible after forced non-default state.
  - `scripts/validation/vitals_state_save_load_smoke.gd` (expected marker `VITALS SAVE LOAD PASS vitals=true sanity=true radiation=true temperature=true status=true`) — main-scene proof for REQ-SV-008: RunSnapshot carries and restores vitals, sanity, radiation, temperature, and status effects summaries; non-default values survive configure/reset/apply round-trip.
  - All six added to regression bundle (`commands=135`; bundle was `commands=128` before this package).
  - `scripts/validation/export_presets_smoke.gd` (expected marker `EXPORT PRESETS PASS presets=4 all_runnable=true paths_under_build=true`) — REQ-RL-001 export preset validation; parses `export_presets.cfg`, asserts every preset has the required keys and a path under `build/exports/<preset_name>/`, asserts the build metadata catalog loads with a known `build_kind`, and asserts the credits catalog carries ≥ 5 entries (REQ-RL-009).
  - `scripts/validation/achievement_state_smoke.gd` (expected marker `ACHIEVEMENT STATE PASS unlocked=0 catalog=8 unknown_rejected=true round_trip=true`) — REQ-RL-003 / REQ-RL-004 achievement catalog and persistence; loads the catalog, exercises unlock / trigger unlock / duplicate / unknown-id rejection / round-trip through `apply_summary`, and asserts `start_new_run` wipes the unlock set per ADR-0007.
  - `scripts/validation/localization_catalog_smoke.gd` (expected marker `LOCALIZATION CATALOG PASS languages=1 translations=14 fallback=true unknown_returns_default=true`) — REQ-RL-005 localization catalog; loads the catalog, asserts known translation returns the catalog text, unknown id returns empty / supplied fallback, unknown language falls back to default, and summary drift is asserted.
  - `scripts/validation/demo_scope_gate_smoke.gd` (expected marker `DEMO SCOPE GATE PASS build_kind=release blocked=5 allowed=0 unknown_rejected=true`) — REQ-RL-006 demo scope gate; configures the gate in `demo`, `release`, and `dev` build kinds and asserts every feature in the manifest is blocked only in demo, every feature is allowed in release/dev, and unknown ids are rejected (no silent allow).
  - `scripts/validation/release_readiness_ledger_smoke.gd` (expected marker `RELEASE READINESS LEDGER PASS rows=2 local=1 external=1 external_evidence_required=true categories_ok=true crash_round_trip=true crash_cap=256`) — REQ-RL-007 / REQ-RL-008 / REQ-RL-010 release readiness ledger + crash bundle + post-launch playbook; loads the checklist with ≥ 1 check per category, exercises local/external evidence recording, asserts empty-evidence-path external rows are rejected, splits rows by source in the summary, splits rows by category in the status lines, and asserts `CrashReportBundle` round-trips and caps at 256 entries FIFO. Three WARNING allowlist entries (`RL008_UNKNOWN_CHECK_WARNING`, `RL008_INVALID_STATUS_WARNING`, `RL008_EXTERNAL_EMPTY_WARNING`) are added for the rejection-path assertions; any other `ReleaseReadinessLedger:` warning still fails the bundle.
- [x] Task 14 cross-system integration and product audit smokes (REQ-INT-001..010 / ADR-0039):
  - `scripts/validation/cross_system_dependency_smoke.gd` (expected marker `CROSS SYSTEM DEPENDENCY PASS`) — loads `IntegrationMatrix` and `DependencyValidator`, then verifies every cited package row has existing code/data/docs/smoke files, requirement headings in `05_requirements.md`, and registered smoke markers in this validation plan.
  - `scripts/validation/e2e_survival_loop_smoke.gd` (expected marker `E2E SURVIVAL LOOP PASS`) — scores the full prepare -> derelict -> survive -> loot -> craft -> return -> upgrade scenario through `AutomatedPlaytestRubric` and `BalanceLedger`.
  - `scripts/validation/e2e_combat_loot_craft_smoke.gd` (expected marker `E2E COMBAT LOOT CRAFT PASS`) — composes live `DamagePipeline`, `ThreatAIState`, `LootDistribution`, `InventoryState`, `MaterialState`, and `CraftingState` into one deterministic combat/loot/craft path.
  - `scripts/validation/e2e_ship_meta_loop_smoke.gd` (expected marker `E2E SHIP META LOOP PASS`) — composes `PowerGridState`, `MetaProgressionState`, and `HubUpgradeState` to prove repair/return/upgrade continuity.
  - `scripts/validation/product_audit_smoke.gd` (expected marker `PRODUCT AUDIT PASS`) — validates the product audit JSON and known-issue manifest so contradictions are linked to explicit cards (`t_c7ac4d08`, `t_4e47145d`, `t_cc483347`) instead of silent caveats.


## Focused Task 15 systems-map / requirement / manifest currency validation

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea python3 scripts/validation/systems_map_currency_smoke.py
ROOT=/Users/christopherwilloughby/the-synaptic-sea python3 scripts/validation/requirement_trace_smoke.py
ROOT=/Users/christopherwilloughby/the-synaptic-sea python3 scripts/validation/kanban_manifest_smoke.py
```

Expected markers:

- `SYSTEMS MAP CURRENCY PASS`
- `REQUIREMENT TRACE PASS`
- `KANBAN MANIFEST PASS`
