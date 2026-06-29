# 06 Validation Plan

## Core rule

No completion claim without fresh validation evidence.

## Godot binary

`/Users/christopherwilloughby/.local/bin/godot-4.6.2`

## Project root

`/Users/christopherwilloughby/the-synaptic-sea-of-stars`

## Focused route-control validation

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/route_control_state_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
```

Expected markers:

- `ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true`
- `MAIN PLAYABLE ROUTE CONTROL PASS gates=1 opened=1 blockers=0 extraction=true`

## Regression bundle

```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-synaptic-sea-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
# Known baseline Godot shutdown lines that appear identically in every
# unchanged smoke (route-control, completion, input, readability, oxygen,
# hazard, ship-systems) and are NOT introduced by the Synaptic Sea hazard code
# or any other Gate 1 runtime system. They are filtered out of the strict
# ERROR/WARNING check below; any other ERROR:/WARNING: line (parse errors,
# GDScript runtime errors, validation markers pushed via push_error) still
# fails the bundle. See "Baseline Godot teardown noise" below for the
# audit trail and the exact evidence-gathering command.
BASELINE_ERROR="^ERROR: Capture not registered: 'gdaimcp'\\.$"
BASELINE_WARNING="^WARNING: ObjectDB instances leaked at exit \\(run with --verbose for details\\)\\.$"
REQ012_WARNING="^WARNING: SaveLoadService: save file rejected by from_dict \\(missing fields or version mismatch\\)\$"
# The save/load service smoke deliberately writes a slot with an incompatible
# (newer) slice_version to assert the migration-rejection path; that emits one
# expected warning, allowlisted exactly like REQ012_WARNING above.
MIGRATION_REJECT_WARNING="^WARNING: SaveLoadService: slot rejected by migration \\(newer than current\\), slot_id=.*\$"
run_clean() {
  label="$1"
  marker="$2"
  shift 2
  echo "=== $label ==="
  OUT=$("$@" 2>&1)
  printf '%s\n' "$OUT"
  printf '%s\n' "$OUT" | grep -q "$marker"
  FILTERED=$(printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' | grep -Ev "$BASELINE_ERROR|$BASELINE_WARNING|$REQ012_WARNING|$MIGRATION_REJECT_WARNING" || true)
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
run_clean 'fire suppression model smoke' 'FIRE SUPPRESSION STATE PASS ignite=true persist=true extinguish=true auto_suppress=true vent=true spread=true reignite=true cascade=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_suppression_state_smoke.gd
run_clean 'extinguisher state smoke' 'EXTINGUISHER STATE PASS consume=true recharge=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/extinguisher_state_smoke.gd
run_clean 'ship systems damage smoke' 'SHIP SYSTEMS DAMAGE PASS damaged=true unknown_rejected=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_damage_smoke.gd
run_clean 'fire suppression point smoke' 'FIRE SUPPRESSION POINT PASS extinguished=true charge_spent=true gated=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_suppression_point_smoke.gd
run_clean 'extinguisher recharge port smoke' 'EXTINGUISHER RECHARGE PORT PASS powered_refills=true unpowered_noop=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/extinguisher_recharge_port_smoke.gd
run_clean 'main fire smoke' 'MAIN PLAYABLE FIRE PASS passable=true present=true vent=true vitals_drain=true system_damage=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_fire_smoke.gd
run_clean 'main fire loop smoke' 'MAIN PLAYABLE FIRE LOOP PASS ignite=true teeth=true extinguish=true reignite=true repair_stops=true recharge=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_fire_loop_smoke.gd
run_clean 'golden fire zone source marker smoke' 'GOLDEN FIRE ZONE SOURCE MARKER PASS marker_room=cargo_01' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/golden_fire_zone_source_marker_smoke.gd
run_clean 'ship systems smoke' 'MAIN PLAYABLE SHIP SYSTEMS PASS power=true breach_sealed=true gates_open=true logs=true reactor=true extraction=true power_pct=100' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
run_clean 'M7-A ship systems expanded smoke' 'MAIN PLAYABLE SHIP SYSTEMS EXPANDED PASS propulsion=true hull=true fire=true sustenance=true persistence=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd
run_clean 'completion smoke' 'MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
run_clean 'template b completion smoke' 'MAIN PLAYABLE TEMPLATE B COMPLETE PASS completed=5 current_sequence=6 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_template_b_completion_smoke.gd
run_clean 'input smoke' 'MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
run_clean 'readability smoke' 'MAIN PLAYABLE SLICE READABILITY PASS objective_props=5 blocked=1 ramp=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
run_clean 'main objective variation smoke' 'MAIN PLAYABLE OBJECTIVE VARIATION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
run_clean 'objective progress state smoke' 'OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_state_smoke.gd
run_clean 'objective progress hud label smoke' 'OBJECTIVE PROGRESS HUD LABEL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_hud_label_smoke.gd
run_clean 'save/load service smoke' 'SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
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
run_clean 'ADR-0005 hazard contract static smoke' 'HAZARD CONTRACT PASS models=2 phase_timer_owners=1 wrong_kind_rejected=2 configure_dict=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hazard_contract_smoke.gd
run_clean 'ADR-0038 station craft reachability smoke' 'MAIN PLAYABLE STATION CRAFT PASS crafted=true salvaged=true field=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_station_craft_smoke.gd
run_clean 'Bucket 3 meta-screen reachability smoke' 'MAIN PLAYABLE META SCREENS PASS screens=10 reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_meta_screens_smoke.gd
run_clean 'AutosavePolicy reachability smoke' 'MAIN PLAYABLE META AUTOSAVE PASS slot_rotated=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_meta_autosave_smoke.gd
run_clean 'KitCatalog lifeboat biome-skin reachability smoke' 'MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=3 live_match=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_lifeboat_biome_skin_smoke.gd
run_clean 'procgen derelict encounter-injection reachability smoke' 'MAIN PLAYABLE DERELICT ENCOUNTER INJECTION PASS injected_threats=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_derelict_encounter_injection_smoke.gd
run_clean 'REQ-FC food consumption reachability smoke' 'MAIN PLAYABLE FOOD CONSUMPTION PASS hunger_restored=true thirst_restored=true spoilage_tracked=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_food_consumption_smoke.gd
run_clean 'item economy data smoke' 'ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_enforced=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_economy_smoke.gd
run_clean 'main item economy reachability smoke' 'MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_item_economy_smoke.gd
run_clean 'spoilage stage threaded into eat path smoke' 'SPOILAGE EAT SCALING PASS stale_lt_fresh=true rotten_lt_stale=true fresh_fallback=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/spoilage_eat_scaling_smoke.gd
run_clean 'M7-A breach seal point model smoke' 'BREACH SEAL POINT PASS sealed=true breach_cleared=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/breach_seal_point_smoke.gd
run_clean 'M7-A life support vitals loop smoke' 'MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true seal_loop=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_life_support_vitals_smoke.gd
run_clean 'Domain 1 survival stakes (home) smoke' 'MAIN PLAYABLE SURVIVAL STAKES PASS gate_half=true gate_locked=true death=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_survival_stakes_smoke.gd
run_clean 'Domain 1 survival attrition away-path smoke' 'MAIN PLAYABLE SURVIVAL AWAY PASS away_ticks=true rad_drain=true temp_rise=true away_death=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_survival_away_smoke.gd
run_clean 'Domain 1 death clears autosave smoke' 'MAIN PLAYABLE DEATH CLEARS AUTOSAVE PASS wrote=true died=true cleared=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_death_clears_autosave_smoke.gd
run_clean 'vitals state model smoke' 'VITALS STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_state_smoke.gd
run_clean 'player movement gating seam smoke' 'PLAYER MOVEMENT GATING PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_movement_gating_smoke.gd
run_clean 'hallucination director model smoke' 'HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hallucination_director_smoke.gd
run_clean 'threat placeholder renderer smoke' 'THREAT PLACEHOLDER RENDERER PASS swarm=true anchored=true default=true color=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_placeholder_renderer_smoke.gd
run_clean 'main hallucination loop smoke' 'MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true no_respawn=true teeth=true away_ticks=true clears=true hud=true fx=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_hallucination_smoke.gd
run_clean 'biome loot_quality_modifier wired into rarity rolls' 'LOOT QUALITY MODIFIER PASS high_gt_base=true mid_between=true default_noop=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_quality_modifier_smoke.gd
run_clean 'REQ-AU-001 coordinator audio event coupling smoke' 'AUDIO COORDINATOR EVENTS PASS fire=true arc=true breath=true vitals_low_edge=true combat_music=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_coordinator_events_smoke.gd
run_clean 'REQ-AU-001 callsite audio event coupling smoke' 'AUDIO CALLSITE EVENTS PASS door=skip footstep=skip drop=skip tool=true inv_toggle=true objective=true save=true dock=skip load=skip' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_callsite_events_smoke.gd
# --- Task 15 documentation/manifest currency validators (host-side Python; no Godot) ---
# doc_currency_validators.py auto-detects the repo root (overridable via ROOT) and
# exits non-zero on failure. The kanban-manifest check needs the live Hermes board
# SQLite DB; when it is absent it prints "KANBAN MANIFEST SKIP" instead of
# "KANBAN MANIFEST PASS", and the gate accepts either (marker "KANBAN MANIFEST").
run_clean 'systems map currency' 'SYSTEMS MAP CURRENCY PASS' python3 "$ROOT/scripts/validation/doc_currency_validators.py" systems-map
run_clean 'requirement trace' 'REQUIREMENT TRACE PASS' python3 "$ROOT/scripts/validation/doc_currency_validators.py" requirement-trace
run_clean 'kanban manifest currency' 'KANBAN MANIFEST' python3 "$ROOT/scripts/validation/doc_currency_validators.py" kanban-manifest
# --- System inventory anti-drift check (host-side Python; no Godot) ---
# build_system_inventory.py auto-detects the repo root from its own path. --check
# re-renders SYSTEM_INVENTORY.md + system_map.html from system_inventory.json and
# fails on missing cited files, untraced simulation systems (confidence '?'),
# dangling integration/loop refs, or stale committed output. Marker carries a
# systems=/verified= count suffix; the bundle matches the leading marker string.
run_clean 'system inventory anti-drift check' 'SYSTEM INVENTORY CHECK PASS' python3 "$ROOT/tools/build_system_inventory.py" --check
run_clean 'fire suppression round-trip smoke' 'FIRE SUPPRESSION ROUND TRIP PASS topo=true fires=true spreads=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_suppression_round_trip_smoke.gd
run_clean 'ship instance fire persistence smoke' 'SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_fire_persistence_smoke.gd
run_clean 'derelict fire seed smoke' 'DERELICT FIRE SEED PASS deterministic=true rate_ok=true cap_ok=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_fire_seed_smoke.gd
run_clean 'main playable derelict fire smoke' 'MAIN PLAYABLE DERELICT FIRE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_derelict_fire_smoke.gd
run_clean 'derelict fire sequential persistence smoke' 'DERELICT FIRE SEQUENTIAL PERSISTENCE PASS remembered=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_fire_sequential_persistence_smoke.gd
echo 'SYNAPTIC_SEA REGRESSION PASS commands=68 clean_output=true'
```

## Baseline Godot teardown noise

Two `ERROR:`/`WARNING:` lines are emitted on the engine teardown of every
smoke run in this regression bundle, including in unchanged smokes that were
already passing before the hazard feature was added. They are classified as
baseline engine noise and filtered by the script above:

- `ERROR: Capture not registered: 'gdaimcp'.` — emitted by Godot's
  `engine_debugger.cpp:62` when a registered message capture (the GDAI MCP
  capture, registered when the Synaptic Sea Godot editor session is live) is
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

Evidence collection command (run before adding or removing a smoke from the
bundle; any unexpected `ERROR:`/`WARNING:` line that is not on the allowlist
must block the change):

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea-of-stars
for s in route_control_state_smoke main_playable_slice_route_control_smoke oxygen_state_smoke main_playable_slice_hazard_smoke fire_suppression_state_smoke extinguisher_state_smoke ship_systems_damage_smoke fire_suppression_point_smoke extinguisher_recharge_port_smoke main_playable_slice_fire_smoke main_playable_fire_loop_smoke main_playable_slice_ship_systems_smoke main_playable_slice_completion_smoke main_playable_slice_input_smoke main_playable_slice_readability_smoke save_load_service_smoke main_playable_slice_save_load_smoke objective_progress_state_smoke objective_progress_hud_label_smoke main_playable_slice_objective_variation_smoke req012_autosave_sequence_smoke main_playable_slice_text_scale_smoke electrical_arc_state_smoke main_playable_slice_arc_smoke main_playable_slice_junction_calibrator_save_load_smoke; do
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
ROOT=/Users/christopherwilloughby/the-synaptic-sea-of-stars
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
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/gate1_automated_playtest.gd
```

A Gate 1 Go decision requires the regression bundle plus either the automated protocol acceptance checklist or the human playtest protocol acceptance checklist to pass.

## Future validation additions
- [x] Inventory/tool model smoke: `scripts/validation/inventory_state_smoke.gd` (expected marker `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5`) and main-scene smoke `scripts/validation/main_playable_slice_inventory_smoke.gd` (expected marker `MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5`) (REQ-007). Added to regression bundle.
- [x] Fire hazard model smoke: ~~`scripts/validation/fire_state_smoke.gd`~~ **retired by M7-B (ADR-0041).** Fire left the ADR-0005 phase-timer cyclic contract and is now the authoritative persistent compartment hazard owned by `FireSuppressionState`. Replaced by: pure-model `scripts/validation/fire_suppression_state_smoke.gd` (marker `FIRE SUPPRESSION STATE PASS ignite=true persist=true extinguish=true auto_suppress=true vent=true spread=true reignite=true cascade=true round_trip=true`), `scripts/validation/extinguisher_state_smoke.gd` (`EXTINGUISHER STATE PASS consume=true recharge=true round_trip=true`), `scripts/validation/ship_systems_damage_smoke.gd` (`SHIP SYSTEMS DAMAGE PASS damaged=true unknown_rejected=true`), node smokes `scripts/validation/fire_suppression_point_smoke.gd` (`FIRE SUPPRESSION POINT PASS extinguished=true charge_spent=true gated=true`) and `scripts/validation/extinguisher_recharge_port_smoke.gd` (`EXTINGUISHER RECHARGE PORT PASS powered_refills=true unpowered_noop=true`), and main-scene `scripts/validation/main_playable_slice_fire_smoke.gd` (now `MAIN PLAYABLE FIRE PASS passable=true present=true vent=true vitals_drain=true system_damage=true`) plus the end-to-end `scripts/validation/main_playable_fire_loop_smoke.gd` (`MAIN PLAYABLE FIRE LOOP PASS ignite=true teeth=true extinguish=true reignite=true repair_stops=true recharge=true reachable=true`) (REQ-010 / ADR-0041). All added to regression bundle; `hazard_contract_smoke.gd` updated to `models=2 phase_timer_owners=1 wrong_kind_rejected=2 configure_dict=2` (fire out of the timer-hazard set).
- [x] Golden fire-zone source marker smoke: `scripts/validation/golden_fire_zone_source_marker_smoke.gd` — pins the Gate 2 fire zone to a side link declared in BOTH `layout.json` and `gameplay_slice.json`, asserts target room is non-critical and not the obj3 → obj4 breach corridor, and verifies `FIRE_ZONE_FALLBACK_ROOM_ID` matches the marker. Added to regression bundle.
- [x] Objective variation model smoke: `scripts/validation/objective_progress_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_objective_variation_smoke.gd` (REQ-011). Added to regression bundle.
- [x] Objective HUD-label smoke: `scripts/validation/objective_progress_hud_label_smoke.gd` (REQ-011) — verifies the player-facing "Repair junction" label is shown for `kind == "repair_junction"` while the ship-system `type == "restore_systems"` stays preserved. Added to regression bundle.
- [x] Save/load service smoke: `scripts/validation/save_load_service_smoke.gd` (expected marker `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=7`) and main-scene smoke `scripts/validation/main_playable_slice_save_load_smoke.gd` (expected marker `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`) (REQ-012). Added to regression bundle.
- [x] REQ-012 auto-save sequence smoke: `scripts/validation/req012_autosave_sequence_smoke.gd` (expected marker `REQ012 AUTOSAVE SEQUENCE CHECK PASS live=2 snapshot=2 file=2 has_save=true`) — permanent regression for the auto-save ordering bug. Completes objective 1 and inspects the in-memory snapshot and the on-disk save BEFORE any manual `request_save()` so the auto-save-only path is locked down. Added to regression bundle.
- [x] Template B completion smoke: `scripts/validation/main_playable_slice_template_b_completion_smoke.gd` (expected marker `MAIN PLAYABLE TEMPLATE B COMPLETE PASS completed=5 current_sequence=6 run_complete=true`). Added to regression bundle.
- [x] Alternate input smoke: `scripts/validation/main_playable_slice_alternate_input_smoke.gd` (expected marker `MAIN PLAYABLE ALTERNATE INPUT PASS moves_alt=1 interact_alt=1`) — A11Y-P1-002 alternate keyboard binding surface. Verifies the InputMap carries both WASD/E/F5/F9 (original) and Arrows / Enter / Space / KP_Enter (alternates) on the movement and interact actions, that save/load (F5/F9) stays single-binding and non-conflicting, that the HUD prompt reflects the expanded surface, and that driving the action through `Input.action_press` (the exact code path the engine uses for a held arrow key) advances the player and registers an interact press. Added to regression bundle.
- [x] Alternate input events smoke: `scripts/validation/playable_slice_alternate_input_smoke.gd` (expected marker `PLAYABLE SLICE ALTERNATE INPUT EVENTS PASS static_bindings=ok moves_alt=1 interact_alt=3 enter=1 space=1 kp_enter=1`) — A11Y-P1-002 companion to the alternate input smoke above. Proves that a REAL `InputEventKey` routed through `Input.parse_input_event()` (the same code path a player's actual keypress takes) reaches the engine's input layer: KEY_RIGHT drives `move_right` via the player's `Input.get_action_strength` poll and the player's `global_position` advances on +X, and KEY_ENTER / KEY_SPACE / KEY_KP_ENTER each fire `PlayerController.interact_requested` exactly once (the same signal the original KEY_E binding fires via `PlayerController._unhandled_input`'s `event.is_action_pressed("interact")` watch). Drops the static-binding check so any silent removal of an alternate keycode from `ensure_default_input_actions()` fails this smoke with `static bindings incomplete: ...`, even when the WASD/E smoke and the action-press alternate smoke still pass. Added to regression bundle.
- [x] A11Y-P1-001 text scale smoke: `scripts/validation/main_playable_slice_text_scale_smoke.gd` (expected marker `MAIN PLAYABLE TEXT SCALE PASS scales=3 default=1.0x1.5x2.0 runtime_text=present`) — proves the single `AccessibilitySettings` seam drives both the HUD `font_size` and `custom_minimum_size` (default 1.0 reproduces font=18, panel=520x250) and the world `Label3D.pixel_size` for the breach unsafe marker and fire zone label (default 0.0035 reproduces exactly), and that the same seam scales consistently to 1.5x (font=27, panel=780x375, pixel=0.002333) and 2.0x (font=36, panel=1040x500, pixel=0.001750) while HUD text remains sourced from runtime state at every scale. Added to regression bundle.
- [x] M7-A breach seal point model smoke: `scripts/validation/breach_seal_point_smoke.gd` (expected marker `BREACH SEAL POINT PASS sealed=true breach_cleared=true`) — pure-model smoke: a BreachSealPoint channel consumes a `hull_sealant` from inventory and seals a breached HullIntegrityState compartment; asserts breach_count returns to 0 and item is consumed. Added to regression bundle.
- [x] M7-A life support vitals loop (main-scene smoke): `scripts/validation/main_playable_life_support_vitals_smoke.gd` (expected marker `MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true seal_loop=true reachable=true`) — live-scene proof that a fouled hub atmosphere (hull breach + unpowered life support → `get_health_drain_per_second() > 0`) drains `vitals_state.health` while aboard; drain is zero while away on a derelict; restoring power halts it; player can seal via live `BreachSealPoint`. Closes the hull→atmosphere→vitals loop required by M7-A A1. Added to regression bundle.
- [x] Domain 1 survival stakes home-path smoke: `scripts/validation/main_playable_survival_stakes_smoke.gd` (expected marker `MAIN PLAYABLE SURVIVAL STAKES PASS gate_half=true gate_locked=true death=true reachable=true`) — live-scene proof via the real coordinator `_process` on the home branch (away_from_start=false) that (1) exhausted stamina halves the player's effective movement speed via the vitals movement gate, and (2) health reaching 0 locks movement entirely and ends the run as a death (`slice_complete=true`). Regression guard for Domain 1 survival stakes on the home path. Added to regression bundle.
- [x] Domain 1 survival attrition away-path smoke: `scripts/validation/main_playable_survival_away_smoke.gd` (expected marker `MAIN PLAYABLE SURVIVAL AWAY PASS away_ticks=true rad_drain=true temp_rise=true away_death=true`) — live-scene proof that the derelict (away_from_start=true) branch runs `_tick_survival_attrition(delta)`: radiation at 100 drains health, body temperature rises in the hazard extreme zone, and health reaching 0 ends the run as a death. Regression guard for the away early-return gap (line 4808) that previously starved all survival attrition on a boarded derelict. Added to regression bundle.
- [x] Domain 1 player movement-gating seam smoke: `scripts/validation/player_movement_gating_smoke.gd` (expected marker `PLAYER MOVEMENT GATING PASS`) — pure-node proof that `PlayerController.set_movement_speed_multiplier()` clamps to [0,1] and `get_effective_move_speed()` scales `move_speed` accordingly (full/half/locked), the seam the coordinator's vitals gate drives. Added to regression bundle.
- [x] Domain 1 death clears autosave smoke: `scripts/validation/main_playable_death_clears_autosave_smoke.gd` (expected marker `MAIN PLAYABLE DEATH CLEARS AUTOSAVE PASS wrote=true died=true cleared=true`) — live-scene proof that a forced rotating autosave is wiped when the player dies (`end_run("death")`), so a fatal run cannot be resumed from a stale autosave. Regression guard for the PR #50 terminal-state-integrity finding (end_run cleared only current_run/world). Added to regression bundle.
- [x] Hub/meta progression smoke (deferred past Gate 2 per ADR-0003).
- [x] GUT suite if/when adopted by ADR.
- [x] Performance baseline smoke: `scripts/validation/performance_profiler.gd` (expected marker `PERFORMANCE BASELINE PASS templates=3`) — first baseline numbers established 2026-06-19 at `docs/game/performance_baseline.md`. Headless harness covers load time, procgen time, peak Godot static memory, and end-of-run OS RSS across the two known procgen templates plus the main playable scene. Windowed FPS at `scripts/validation/windowed_fps_capture.gd` is intentionally NOT in the bundle (requires a display server); it is the source of truth for the frame-time target and is run on demand during Gate 3 / Gate 4 review. Added to regression bundle.
- [x] Junction calibrator model smoke: `scripts/validation/junction_calibrator_state_smoke.gd` (expected marker `JUNCTION CALIBRATOR STATE PASS required_steps=2 consumed=true`) and main-scene smoke `scripts/validation/main_playable_slice_junction_calibrator_smoke.gd` (expected marker `MAIN PLAYABLE JUNCTION CALIBRATOR PASS acquired=true required_steps=2 consumed=true`) (REQ-014). Added to regression bundle. The main-scene smoke registers a synthetic 3-step junction through `register_junction_sequence_for_validation` so it asserts the exact `required_steps=2` post-calibration marker without depending on the seed template's exact step count (the seed template's sequence 2 is a 2-step junction; REQ-014's spec example requires a 3-step reduction target).
- [x] Junction calibrator save/load smoke: `scripts/validation/main_playable_slice_junction_calibrator_save_load_smoke.gd` (expected marker `MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS carried_load=true consumed_load=true next_frame_interaction=true`) — permanent regression for the two blocking findings from review t_80dcea4b. Drives the actual seed sequence 2 repair_junction through save/load in both carried and consumed/applied save states, including a real next-frame interaction after each load. Asserts the live coordinator path leaves the objective_progress model complete after the calibrator reduces a real 2-step junction to 1 (the pre-calibration `required_steps` snapshot lets `complete_step` fire on the first interaction instead of being skipped), and that post-load interactions survive the rebuild of the HUD layer / ObjectiveTracker that previously crashed with "Nonexistent function 'mark_completed' in base 'previously freed'". Also locks down the reload pickup-marker reconciliation (carried = hidden, spent = hidden) and the JSON-string-int-key round-trip in `ObjectiveProgressState.apply_summary` that would otherwise silently drop the per-sequence `calibrator_applied` flag. Added to regression bundle.
- [x] Electrical-arc hazard model smoke: `scripts/validation/electrical_arc_state_smoke.gd` (expected marker `ARC STATE PASS cycles=2 phases=4 passability_switches=4`) and main-scene smoke `scripts/validation/main_playable_slice_arc_smoke.gd` (expected marker `MAIN PLAYABLE ARC PASS state=DISCHARGED cycles=2 blocked_arcing=true blocked_discharged=false`) (REQ-013). The pure model smoke advances the cycle through two full DISCHARGED -> ARCING -> DISCHARGED rounds and asserts the phase / passability counts match the ADR-0005 contract; it also round-trips the summary through `apply_summary()` and verifies a wrong `hazard_kind` is rejected. The main-scene smoke drives the same model through `playable.electrical_arc_state.tick(...)` against template 002 (which carries the new `arc_side_01` non-critical side branch) and asserts collision is enabled only while ARCING. Both are added to the regression bundle.
- [x] ADR-0005 hazard contract static smoke: `scripts/validation/hazard_contract_smoke.gd` (expected marker `HAZARD CONTRACT PASS models=3 phase_timer_owners=2 wrong_kind_rejected=3 configure_dict=3`) — structural (no runtime tick) assertion that catches the three review-recycle findings on REQ-013 / REQ-014 hazard models: (1) FireState and ElectricalArcState MUST own a `PhaseTimer` instance and translate its `Phase.A/B` output into their own enum, (2) `get_summary()` MUST include `hazard_kind` on every model, and (3) `apply_summary()` MUST reject a wrong-kind summary. Also asserts OxygenState does NOT own a `PhaseTimer` (negative decision from ADR-0005: resource-drain hazards do not need timer phases) and that the `PhaseTimer` helper itself does not carry a `HAZARD_KIND` discriminator. Locks down the `configure(config: Dictionary)` uniform boundary from the ADR-0005 HazardStateContract. Added to regression bundle.
- [x] Derelict fire — 5 smokes (M7-B / ADR-0041 / this branch `feat/derelict-fire`):
  - `scripts/validation/fire_suppression_round_trip_smoke.gd` (marker `FIRE SUPPRESSION ROUND TRIP PASS topo=true fires=true spreads=true`) — proves `FireSuppressionState.get_summary()`/`apply_summary()` round-trips the full state including compartments + adjacency topology, so a per-ship model restored from a snapshot still spreads.
  - `scripts/validation/ship_instance_fire_persistence_smoke.gd` (marker `SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true`) — proves the "fire" key is omitted from `ShipInstance.get_summary()` when no compartment burns (no snapshot bloat), and that a burning state is faithfully restored via `apply_summary()`.
  - `scripts/validation/derelict_fire_seed_smoke.gd` (marker `DERELICT FIRE SEED PASS deterministic=true rate_ok=true cap_ok=true`) — proves the presence gate is deterministic (RNG-free hash), rate is in the band around 15%, and the cap formula matches the real `ShipBlueprint.Condition` enum ordinals.
  - `scripts/validation/main_playable_derelict_fire_smoke.gd` (marker `MAIN PLAYABLE DERELICT FIRE PASS` — stable prefix; away_ticks count varies run-to-run and is not grepped) — live-scene proof: board a real derelict, fire ticks on the away branch, player standing in a derelict fire zone takes vitals drain, recharge port is power-gated by the derelict's own system, and manual extinguish works via the real interaction path. Requires `travel_to_marker_id` (not just `away_from_start=true`) so current_ship is a genuine derelict instance.
  - `scripts/validation/derelict_fire_sequential_persistence_smoke.gd` (marker `DERELICT FIRE SEQUENTIAL PERSISTENCE PASS remembered=true`) — live-revisit proof: board a derelict, ignite 2 compartments, extinguish 1 via the real interaction path, travel home, revisit the same marker — the burning set is preserved exactly (extinguished compartment stays out; remaining compartment still burns). Proves `fire_seeded` gate prevents re-seeding and `visited_ships` retains the per-ship `FireSuppressionState` across trips. All 5 added to regression bundle (commands 59–63).
