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
ROOT="${ROOT:-/Users/christopherwilloughby/the-synaptic-sea-of-stars}"
GODOT="${GODOT:-/Users/christopherwilloughby/.local/bin/godot-4.6.2}"
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
# save_load_service_smoke deliberately writes a world-99 payload to prove an
# older build refuses the newer save without moving it into .corrupt; this is
# the expected warning from that preservation path.
WORLD_MIGRATION_REJECT_WARNING="^WARNING: SaveLoadService: world save rejected by migration \\(newer than current version\\)\$"
# title_save_query_smoke's corrupt-world case (PR #57 Codex P2) deliberately
# writes literal garbage over world.json to prove TitleSaveQuery.is_continue_available
# now calls load_world() (not just has_slot/has_died_in); load_world()'s
# JSON-parse-failure path emits this one expected warning before returning
# null, allowlisted the same way as REQ012_WARNING/MIGRATION_REJECT_WARNING.
CORRUPT_WORLD_WARNING="^WARNING: SaveLoadService: world save file is not valid JSON object\$"
# The same corrupt-world case's write goes through Godot's own JSON.parse_string,
# which prints its own native engine-level ERROR (not a push_error) before
# load_world() ever gets to check the parsed result. This is Godot engine
# behavior (core/io/json.cpp), not a Synaptic Sea system error -- allowlisted
# alongside CORRUPT_WORLD_WARNING as the deliberate/expected pair.
CORRUPT_WORLD_JSON_ERROR="^ERROR: Parse JSON failed\\..*\$"
# permadeath_freeze_smoke's reclaim-failure stage (PR #57 Codex round 3 P2)
# deliberately pre-creates a directory at world.json's path so
# FileAccess.open fails, proving save_world() leaves an existing death
# record intact when the write itself fails (clear_death now runs only
# after a confirmed write). That forced failure emits one expected warning,
# allowlisted the same way as the other deliberate-failure-path warnings
# above.
WORLD_WRITE_FAIL_WARNING="^WARNING: SaveLoadService: cannot open world save file for writing, error=.*\$"
# title_load_failure_smoke (Tranche 1 audit fix) deliberately fires the
# loader-failure entry point (reason=smoke_forced_failure) to prove the title
# screen tears down a dead boot instead of polling forever. That forced
# failure emits exactly one push_error (the playable's existing FAIL line) and
# one push_warning (TitleMain's new return-to-title handler). Both patterns
# are pinned to the smoke's sentinel reason so a REAL boot failure in any
# other smoke still fails the bundle.
TITLE_BOOT_FAIL_ERROR="^ERROR: PLAYABLE SHIP FAIL reason=smoke_forced_failure\$"
TITLE_BOOT_FAIL_WARNING="^WARNING: TitleMain: gameplay boot failed \\(smoke_forced_failure\\).*\$"
# meta_progression_state_smoke's tolerant-schema case (Session 3 B5)
# deliberately applies a mismatched-schema meta dict to prove best-effort
# apply (and a no-known-fields rejection); each emits one expected
# warn-once line, allowlisted like the deliberate-failure paths above.
META_SCHEMA_WARNING="^WARNING: MetaProgressionState: schema mismatch \\('.*' != 'meta-progression-1'\\); (best-effort apply of known fields|rejected \\(no known meta fields\\))\$"
# world_save_service_smoke's rejects_null case (Tranche 3 promotion)
# deliberately passes a null world snapshot to prove save_world refuses it;
# that emits this one expected warning.
NULL_WORLD_WARNING="^WARNING: SaveLoadService: cannot save null world snapshot\$"
# save_slot_state_smoke's corruption case (Tranche 3 promotion) deliberately
# writes garbage over slot_03.json to prove corruption detection + .corrupt/
# backup; the engine's JSON parse ERROR is covered by CORRUPT_WORLD_JSON_ERROR
# and this is the service's own expected warning, pinned to the smoke's slot.
CORRUPT_SLOT_WARNING="^WARNING: SaveLoadService: slot file is not valid JSON object, slot_id=slot_03\$"
# Tranche 4 (2026-07-06 audit): play_voice_log now routes each AudioLog
# entry's authored clip_path through the warn-once stream loader (ADR-0044
# honest-deferred-assets). The voice clip library is still deferred
# (data/audio/voice/ absent), so any smoke that plays a voice log — the
# audio log panel smoke directly, and main_playable_slice_audio_smoke via
# the 12s/30s scheduled meta events — emits one expected missing-file
# warning per distinct path. Pinned to the voice directory so a missing
# SFX/music placeholder in any other smoke still fails the bundle.
VOICE_CLIP_WARNING="^WARNING: AudioManager: stream file missing, path='res://data/audio/voice/.*'\$"
# Tranche 5 (2026-07-06 audit): encounter_injector_smoke's missing-table case
# (Case 11) deliberately points a biome at a nonexistent encounter table to
# prove the constants fallback + warn-once (ADR-0047). Pinned to the smoke's
# sentinel id so a genuinely missing production table still fails the bundle.
ENCOUNTER_TABLE_WARNING="^WARNING: EncounterInjector: encounter table file missing, falling back to role constants: res://data/procgen/encounter_tables/no_such_table\\.json\$"
# derelict_generator_smoke drives ShipGenerator with the derelict archetype
# against the legacy spine/bifurcated/stacked template trio, none of whose
# zone pools can host the archetype's guaranteed "dock" — the assigner's
# guarantee post-pass (Tranche 5 enforcement) correctly reports the skip.
# The dock itself is guaranteed by the v3 RoomGraphGenerator layer (the same
# smoke asserts dock_count==1) and by the derelict_a/b templates; production
# derelict travel passes an empty archetype, so this diagnostic never fires
# in play.
DOCK_GUARANTEE_WARNING="^WARNING: RoomAssigner: guaranteed role 'dock' has no eligible zone in this template; guarantee skipped\$"
# Soft-fail when all salted connectivity retries still produce a disconnected layout
# (best-effort ship still returned; quality gate fails hard on disconnect).
CONNECTIVITY_SOFT_FAIL_WARNING="^WARNING: ShipLayoutGenerator: layout connectivity soft-fail after [0-9]+ attempts seed="
# load_from_blueprint_smoke's null_rejected case deliberately passes a null
# blueprint to prove load_from_blueprint refuses it; this is the expected
# rejection line.
BLUEPRINT_NULL_ERROR="^ERROR: PlayableGeneratedShip.load_from_blueprint: blueprint must not be null\$"
# release_readiness_ledger_smoke deliberately sends one unknown check id, one
# invalid status, and one missing external evidence path to prove
# ReleaseReadinessLedger rejects malformed evidence rows instead of accepting
# them into the release ledger.
RELEASE_LEDGER_UNKNOWN_WARNING="^WARNING: ReleaseReadinessLedger: unknown check_id=totally_made_up_check\$"
RELEASE_LEDGER_STATUS_WARNING="^WARNING: ReleaseReadinessLedger: invalid status=WAT\$"
RELEASE_LEDGER_EXTERNAL_WARNING="^WARNING: ReleaseReadinessLedger: external evidence rejected, evidence_path is required\$"
run_clean() {
  label="$1"
  marker="$2"
  shift 2
  echo "=== $label ==="
  OUT=$("$@" 2>&1)
  printf '%s\n' "$OUT"
  printf '%s\n' "$OUT" | grep -q "$marker"
  FILTERED=$(printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' | grep -Ev "$BASELINE_ERROR|$BASELINE_WARNING|$REQ012_WARNING|$MIGRATION_REJECT_WARNING|$WORLD_MIGRATION_REJECT_WARNING|$CORRUPT_WORLD_WARNING|$CORRUPT_WORLD_JSON_ERROR|$WORLD_WRITE_FAIL_WARNING|$TITLE_BOOT_FAIL_ERROR|$TITLE_BOOT_FAIL_WARNING|$META_SCHEMA_WARNING|$NULL_WORLD_WARNING|$CORRUPT_SLOT_WARNING|$VOICE_CLIP_WARNING|$ENCOUNTER_TABLE_WARNING|$DOCK_GUARANTEE_WARNING|$CONNECTIVITY_SOFT_FAIL_WARNING|$BLUEPRINT_NULL_ERROR|$RELEASE_LEDGER_UNKNOWN_WARNING|$RELEASE_LEDGER_STATUS_WARNING|$RELEASE_LEDGER_EXTERNAL_WARNING" || true)
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
run_clean 'Domain 4 web infestation model smoke' 'WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/web_infestation_state_smoke.gd
run_clean 'Domain 4 ship systems closure smoke' 'SHIP SYSTEMS CLOSURE PASS away_ticks=60 web_grew=true hull_damaged=true breach_to_vitals=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_closure_smoke.gd
run_clean 'completion smoke' 'MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
run_clean 'template b completion smoke' 'MAIN PLAYABLE TEMPLATE B COMPLETE PASS completed=5 current_sequence=6 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_template_b_completion_smoke.gd
run_clean 'input smoke' 'MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
run_clean 'readability smoke' 'MAIN PLAYABLE SLICE READABILITY PASS objective_props=5 blocked=1 ramp=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
run_clean 'main objective variation smoke' 'MAIN PLAYABLE OBJECTIVE VARIATION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
run_clean 'objective progress state smoke' 'OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_state_smoke.gd
run_clean 'objective progress hud label smoke' 'OBJECTIVE PROGRESS HUD LABEL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_hud_label_smoke.gd
run_clean 'save/load service smoke' 'SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=32 survival_roundtrip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
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
run_clean 'derelict arc away-branch smoke' 'DERELICT ARC PASS boarded=true zone_on_derelict=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_arc_smoke.gd
run_clean 'away-branch integrity smoke' 'AWAY BRANCH INTEGRITY PASS boarded=true port_frame=true hud_refresh=true death_guard=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/away_branch_integrity_smoke.gd
run_clean 'title load-failure recovery smoke' 'TITLE LOAD FAILURE PASS returned_to_title=true error_surfaced=true menu_visible=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/title_load_failure_smoke.gd
run_clean 'hazard interaction feedback smoke' 'HAZARD FEEDBACK PASS extinguish_blocked=true seal_blocked=true breach_sealed=true sfx_routed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hazard_feedback_smoke.gd
run_clean 'ADR-0005 hazard contract static smoke' 'HAZARD CONTRACT PASS models=2 phase_timer_owners=1 wrong_kind_rejected=2 configure_dict=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hazard_contract_smoke.gd
run_clean 'ADR-0038 station craft reachability smoke' 'MAIN PLAYABLE STATION CRAFT PASS crafted=true salvaged=true field=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_station_craft_smoke.gd
run_clean 'REQ-CS-016 crafting recipe list smoke' 'CRAFTING RECIPE LIST PASS ready=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/crafting_recipe_list_smoke.gd
run_clean 'REQ-CS-016 recipe picker panel smoke' 'RECIPE PICKER PANEL PASS rows=3 move=true confirm=true closed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/recipe_picker_panel_smoke.gd
run_clean 'REQ-CS-016 main playable recipe picker smoke' 'MAIN PLAYABLE RECIPE PICKER PASS station=fabricator' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_recipe_picker_smoke.gd
run_clean 'REQ-CS-017 salvage list smoke' 'SALVAGE LIST PASS ready=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/salvage_list_smoke.gd
run_clean 'REQ-CS-017 main playable salvage picker smoke' 'MAIN PLAYABLE SALVAGE PICKER PASS target=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_salvage_picker_smoke.gd
run_clean 'REQ-CS-018 hydroponics crop list smoke' 'HYDROPONICS CROP LIST PASS crops=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hydroponics_crop_list_smoke.gd
run_clean 'REQ-CS-018 main playable hydro crop picker smoke' 'MAIN PLAYABLE HYDRO CROP PICKER PASS crop=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hydro_crop_picker_smoke.gd
run_clean 'Bucket 3 meta-screen reachability smoke' 'MAIN PLAYABLE META SCREENS PASS screens=10 reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_meta_screens_smoke.gd
run_clean 'AutosavePolicy reachability smoke' 'MAIN PLAYABLE META AUTOSAVE PASS slot_rotated=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_meta_autosave_smoke.gd
run_clean 'KitCatalog lifeboat biome-skin reachability smoke' 'MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=3 live_match=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_lifeboat_biome_skin_smoke.gd
run_clean 'procgen derelict encounter-injection reachability smoke' 'MAIN PLAYABLE DERELICT ENCOUNTER INJECTION PASS injected_threats=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_derelict_encounter_injection_smoke.gd
run_clean 'procgen encounter placement smoke' 'ENCOUNTER PLACEMENT PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/encounter_placement_smoke.gd
run_clean 'REQ-FC food consumption reachability smoke' 'MAIN PLAYABLE FOOD CONSUMPTION PASS hunger_restored=true thirst_restored=true spoilage_tracked=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_food_consumption_smoke.gd
run_clean 'item economy data smoke' 'ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_enforced=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_economy_smoke.gd
run_clean 'item data integrity smoke' 'ITEM DATA INTEGRITY PASS recipes=60 loot_ids=31 materials=33 no_shadow_defs=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_data_integrity_smoke.gd
run_clean 'main item economy reachability smoke' 'MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_item_economy_smoke.gd
run_clean 'spoilage stage threaded into eat path smoke' 'SPOILAGE EAT SCALING PASS stale_lt_fresh=true rotten_lt_stale=true fresh_fallback=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/spoilage_eat_scaling_smoke.gd
run_clean 'M7-A breach seal point model smoke' 'BREACH SEAL POINT PASS sealed=true breach_cleared=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/breach_seal_point_smoke.gd
run_clean 'M7-A life support vitals loop smoke' 'MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true seal_loop=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_life_support_vitals_smoke.gd
run_clean 'Domain 1 survival stakes (home) smoke' 'MAIN PLAYABLE SURVIVAL STAKES PASS gate_half=true gate_locked=true death=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_survival_stakes_smoke.gd
run_clean 'Domain 1 survival attrition away-path smoke' 'MAIN PLAYABLE SURVIVAL AWAY PASS away_ticks=true rad_drain=true temp_rise=true o2_drain=true o2_teeth=true away_death=true no_extract_on_death=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_survival_away_smoke.gd
run_clean 'vitals state model smoke' 'VITALS STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_state_smoke.gd
run_clean 'player movement gating seam smoke' 'PLAYER MOVEMENT GATING PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_movement_gating_smoke.gd
run_clean 'hallucination director model smoke' 'HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hallucination_director_smoke.gd
run_clean 'threat placeholder renderer smoke' 'THREAT PLACEHOLDER RENDERER PASS swarm=true anchored=true default=true color=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_placeholder_renderer_smoke.gd
run_clean 'main hallucination loop smoke' 'MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true no_respawn=true teeth=true away_ticks=true clears=true hud=true fx=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_hallucination_smoke.gd
run_clean 'biome loot_quality_modifier wired into rarity rolls' 'LOOT QUALITY MODIFIER PASS high_gt_base=true mid_between=true default_noop=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_quality_modifier_smoke.gd
run_clean 'REQ-AU-001 coordinator audio event coupling smoke' 'AUDIO COORDINATOR EVENTS PASS fire=true arc=true breath=true vitals_low_edge=true combat_music=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_coordinator_events_smoke.gd
run_clean 'REQ-AU-001 callsite audio event coupling smoke' 'AUDIO CALLSITE EVENTS PASS door=skip footstep=skip drop=skip tool=true inv_toggle=true objective=true save=true dock=skip load=skip' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_callsite_events_smoke.gd
run_clean 'audio bus config model smoke' 'AUDIO BUS CONFIG PASS buses=7 default=true summary_round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_bus_config_smoke.gd
run_clean 'ambient zone state model smoke' 'AMBIENT ZONE STATE PASS roles_changed=2 crossfades_completed=1 threat_applied=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ambient_zone_state_smoke.gd
run_clean 'sfx event router model smoke' 'SFX EVENT ROUTER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sfx_event_router_smoke.gd
run_clean 'dynamic music state model smoke' 'DYNAMIC MUSIC STATE PASS states_visited=4 crossfade_changed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dynamic_music_state_smoke.gd
run_clean 'spatial audio resolver model smoke' 'SPATIAL AUDIO RESOLVER PASS atten_ref=0 atten_max=-36 occluded=-6 determinism=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/spatial_audio_resolver_smoke.gd
run_clean 'meta event state model smoke' 'META EVENT STATE PASS fired=3 pending=0 deterministic_seed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_event_state_smoke.gd
run_clean 'main playable audio smoke' 'MAIN PLAYABLE AUDIO PASS buses=6 routed=4 fired_meta=3 ambient_role=engine' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_audio_smoke.gd
run_clean 'audio save/load model smoke' 'AUDIO SAVE LOAD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_save_load_smoke.gd
run_clean 'Domain 9 audio pipeline smoke' 'AUDIO PIPELINE PASS bus_index=true stream_playing=true caption_hud=true captions_toggle=true voice_toggle=true away_ticks=30' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_pipeline_smoke.gd
run_clean 'REQ-AU-005 spatial audio playback smoke' 'AUDIO SPATIAL PASS catalogued_playing=true fallback_honest=true production_pickup=true position_tracked=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_spatial_playback_smoke.gd
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
# --- REQ-DOC-009 as-built architecture visualizations (host-side Python + locked Mermaid CLI) ---
run_clean 'architecture diagram anti-drift check' '^ARCHITECTURE DIAGRAMS PASS diagrams=5 exports=5 references=[1-9][0-9]*$' bash -lc 'npm --prefix "$1/tools/architecture" ci --silent && python3 "$1/tools/validate_architecture_diagrams.py" --check' _ "$ROOT"
run_clean 'fire suppression round-trip smoke' 'FIRE SUPPRESSION ROUND TRIP PASS topo=true fires=true spreads=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_suppression_round_trip_smoke.gd
run_clean 'ship instance fire persistence smoke' 'SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_fire_persistence_smoke.gd
run_clean 'derelict fire seed smoke' 'DERELICT FIRE SEED PASS deterministic=true rate_ok=true cap_ok=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_fire_seed_smoke.gd
run_clean 'main playable derelict fire smoke' 'MAIN PLAYABLE DERELICT FIRE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_derelict_fire_smoke.gd
run_clean 'main playable reachability smoke' 'MAIN PLAYABLE REACHABILITY PASS organic_cart=true home_loot=true hangar_interact=true achievements=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_reachability_smoke.gd
run_clean 'main playable quicksave smoke' 'MAIN PLAYABLE QUICKSAVE PASS slot=quicksave kind=quick cooldown=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_quicksave_smoke.gd
run_clean 'encounter table dead fleet smoke' 'ENCOUNTER TABLE DEAD FLEET PASS table=threat_drone_swarm kinds=drone_swarm' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/encounter_table_dead_fleet_smoke.gd
run_clean 'status effect icons smoke' 'STATUS EFFECT ICONS PASS entries=8 all_exist=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/status_effect_icons_smoke.gd
run_clean 'derelict fire sequential persistence smoke' 'DERELICT FIRE SEQUENTIAL PERSISTENCE PASS remembered=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_fire_sequential_persistence_smoke.gd
run_clean 'detection state model smoke' 'DETECTION STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/detection_state_smoke.gd
run_clean 'threat detection source smoke' 'THREAT DETECTION SOURCE PASS single_source=true per_archetype=true proximity=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_detection_source_smoke.gd
run_clean 'player crouch seam smoke' 'PLAYER CROUCH PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_crouch_smoke.gd
run_clean 'crouch action smoke' 'CROUCH ACTION PASS registered=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/crouch_action_smoke.gd
run_clean 'threat kill removal smoke' 'THREAT KILL REMOVAL PASS emitted_once=true removed=true loot_table=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_kill_removal_smoke.gd
run_clean 'combat reward data smoke' 'COMBAT REWARD DATA PASS archetypes=true table=true training=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_reward_data_smoke.gd
run_clean 'combat closure smoke' 'COMBAT CLOSURE PASS away_kill=true noise=true crouch=true reward=true removed=true pending_corpse=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_closure_smoke.gd
run_clean 'combat corpse position smoke' 'MAIN PLAYABLE COMBAT CORPSE POSITION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_corpse_position_smoke.gd
run_clean 'Domain 3 production station wiring smoke' 'PRODUCTION WIRING PASS hydro=true recycler=true spoilage_registered=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/production_station_wiring_smoke.gd
run_clean 'Domain3 contaminated_water item smoke' 'CONTAMINATED WATER ITEM PASS defined=true supply=true lootable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/contaminated_water_item_smoke.gd
run_clean 'Domain3 production station unit smoke' 'PRODUCTION STATION PASS hydro_harvest=true recycler_collect=true blocked_in_progress=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/production_station_smoke.gd
run_clean 'Domain3 synthesizer retirement smoke' 'FOOD SYNTHESIZER RETIREMENT PASS orphan_removed=true crafting_synth_ok=true legacy_load_ok=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_synthesizer_retirement_smoke.gd
run_clean 'Domain3 food away tick smoke' 'FOOD AWAY TICK PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_away_tick_smoke.gd
run_clean 'Domain3 main playable food production smoke' 'MAIN PLAYABLE FOOD PRODUCTION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_food_production_smoke.gd
run_clean 'Phase 1 world time persistence smoke' 'WORLD TIME PASS advances=true world_snapshot_roundtrip=true ship_timestamp_roundtrip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_time_persistence_smoke.gd
run_clean 'Phase 2 ship instance models smoke' 'SHIP INSTANCE MODELS PASS hull_roundtrip=true web_roundtrip=true web_attached_delegates=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_models_smoke.gd
run_clean 'Phase 2 ship models seed smoke' 'SHIP MODELS SEED PASS hull_seeded=true web_attached=true timestamp_set=true active_resolves=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_models_seed_smoke.gd
run_clean 'Phase 4 ship catch-up smoke' 'SHIP CATCHUP PASS web_grew=true hull_degraded=true timestamp_stamped=true bounded=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_catchup_smoke.gd
run_clean 'Domain 5 sealed hatch seed + bypass smoke' 'SEALED HATCH PASS away_ticks=3 seeded=true mechanical_open=true flag_consumed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sealed_hatch_smoke.gd
run_clean 'Domain 5 thermal consumable smoke' 'THERMAL CONSUMABLE PASS temp_before=12.000 temp_after=20.000 temp_shifted=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/thermal_consumable_smoke.gd
run_clean 'Domain 5 ammo magazine state model smoke' 'AMMO MAGAZINE STATE PASS spent=true empty=true reloaded=true roundtrip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ammo_magazine_state_smoke.gd
run_clean 'Domain 5 ammo magazine away-branch smoke' 'AMMO MAGAZINE PASS away_ticks=30 spent=true dry_fire=true reloaded=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ammo_magazine_smoke.gd
run_clean 'Domain 5 weapon/ammo acquisition chain smoke' 'WEAPON AMMO ACQUISITION PASS data_reachable=true looted_ammo=true production_reload=true away_ticks=30' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/weapon_ammo_acquisition_smoke.gd
run_clean 'Domain 5 consumables away tick smoke' 'CONSUMABLES AWAY TICK PASS away_ticks=20 stim_decayed=true addiction_ticked=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/consumables_away_tick_smoke.gd
run_clean 'Domain 5 sealed hatch node smoke' 'SEALED HATCH NODE PASS locked=true opened=true collision_off=true signalled=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sealed_hatch_node_smoke.gd
run_clean 'Domain 5 flare steady sanity smoke' 'FLARE STEADY PASS drain_no_flare=15.000 drain_flare=7.500 steadier=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/flare_steady_smoke.gd
run_clean 'Domain 6 training gate model smoke' 'TRAINING GATE PASS gated=true drop=0 unlock_grants=true gated_logged=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/training_gate_smoke.gd
run_clean 'Domain 6 class catalog data smoke' 'CLASS CATALOG PASS base=8 unlockable=3 registry_class_ids=ok' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_catalog_smoke.gd
run_clean 'Domain 6 class gate config smoke' 'CLASS GATE CONFIG PASS available_gate=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_gate_config_smoke.gd
run_clean 'Domain 6 repair ingest smoke' 'REPAIR INGEST PASS bus_xp=120 single_grant=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_ingest_smoke.gd
run_clean 'Domain 6 meta progression state smoke' 'META PROGRESSION STATE PASS payout=39 unlocks=true persistence=true reset=true selected_class=true class_bridge=true tolerant=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_progression_state_smoke.gd
run_clean 'Domain 6 player progression full smoke' 'PLAYER PROGRESSION FULL PASS classes=11 cross_training=true books=true meta_payout=70 unlocks=true panels=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_progression_full_smoke.gd
run_clean 'Domain 6 interactive meta-screens smoke' 'META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true registry_reader=true class_select=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_screens_interactive_smoke.gd
run_clean 'Domain 6 progression meta closure smoke' 'PROGRESSION META CLOSURE PASS away_ticks=1 hub_bonus=1 gate=held gated_logged=true class_persist=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/progression_meta_smoke.gd
run_clean 'Domain 7 room variant selector smoke' 'ROOM VARIANT SELECTOR PASS distinct_per_index=4 distinct_per_seed=7 airlock_variants=4 corridor_variants=7 extended=8 legacy=3 deterministic=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_variant_selector_smoke.gd
run_clean 'Domain 7 procgen variation smoke' 'PROCGEN VARIATION PASS variants_vary=true loot_biased=true tmpl_gated=true deterministic=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_variation_smoke.gd
run_clean 'Domain 7 procgen variant hazard smoke' 'PROCGEN VARIANT HAZARD PASS away_ticks=1 fire_lit=true breach_open=true home_clean=true seal_point=true guarded=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_variant_hazard_smoke.gd
run_clean 'Domain 8 permadeath freeze smoke' 'PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true reclaim=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/permadeath_freeze_smoke.gd
run_clean 'Domain 8 title save query smoke' 'TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/title_save_query_smoke.gd
run_clean 'Domain 8 title screen flow smoke' 'TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/title_screen_flow_smoke.gd
run_clean 'Domain 8 title settings smoke' 'TITLE SETTINGS PASS open=true cycle=true back=true applied=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/title_settings_smoke.gd
run_clean 'Domain 8 save load slot screen smoke' 'SAVE LOAD SLOT SCREEN PASS save=true load=true delete_armed=true delete_confirmed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_slot_screen_smoke.gd
run_clean 'Domain 8 save and exit smoke' 'SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_and_exit_smoke.gd
run_clean 'Domain 10 tooltip presenter model smoke' 'TOOLTIP PRESENTER PASS title=Circuit Board' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/tooltip_presenter_smoke.gd
run_clean 'Domain 10 menu state model smoke' 'MENU STATE PASS menus=2 navigation=true enable_toggle=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/menu_state_smoke.gd
run_clean 'Domain 10 settings state model smoke' 'SETTINGS STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/settings_state_smoke.gd
run_clean 'Domain 10 tutorial state model smoke' 'TUTORIAL STATE PASS once=true dismiss=true codex_unlocks=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/tutorial_state_smoke.gd
run_clean 'Domain 10 controller glyph state model smoke' 'CONTROLLER GLYPH STATE PASS schemes=3 action=interact' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/controller_glyph_state_smoke.gd
run_clean 'Domain 10 UI shell parse check' 'UI SHELL PARSE PASS classes=12' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_shell_parse_check.gd
run_clean 'Domain 10 UI shell save/load smoke' 'UI SHELL SAVE LOAD PASS restored=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_shell_save_load_smoke.gd
run_clean 'Domain 10 main playable UI shell smoke' 'MAIN PLAYABLE UI SHELL PASS boot=main_menu pause=true codex=1 hotbar=true tooltip=true chart_gated=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_ui_shell_smoke.gd
run_clean 'Domain 10 main playable slice UI shell smoke' 'MAIN PLAYABLE SLICE UI SHELL PASS boot=main_menu pause=true codex=1 hotbar=true tooltip=true chart_gated=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ui_shell_smoke.gd
run_clean 'Domain 10 web chart state model smoke' 'WEB CHART STATE PASS known=2 detail_upgrade=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/web_chart_state_smoke.gd
run_clean 'Domain 10 UI polish end-to-end smoke' 'UI POLISH PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_polish_smoke.gd
run_clean 'menu signal wiring smoke' 'MENU SIGNAL WIRING PASS language=true enabled_render=true credits=true metadata=true ready=true progress=true run_outcome=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/menu_signal_wiring_smoke.gd
run_clean 'world migration smoke' 'SAVE MIGRATION WORLD PASS unknown_version_passthrough=true legacy_home_ship_migrated=true current_world_home_ship_migrated=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_migration_world_smoke.gd
run_clean 'slot metadata smoke' 'SLOT METADATA PASS location=home play_time_real=true seed_real=true roundtrip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/slot_metadata_smoke.gd
# --- Tranche 3 (2026-07-06): orphaned-smoke promotion — pure-model batch ---
run_clean 'Tranche 3 sanity state model smoke' 'SANITY STATE PASS drain=35.0 recovery=35.0 pressure=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sanity_state_smoke.gd
run_clean 'Tranche 3 radiation state model smoke' 'RADIATION STATE PASS accumulation=true drain=true decay=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/radiation_state_smoke.gd
run_clean 'Tranche 3 body temperature state model smoke' 'BODY TEMPERATURE STATE PASS safe=false extreme=true recovery=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/body_temperature_state_smoke.gd
run_clean 'Tranche 3 status effects model smoke' 'STATUS EFFECTS PASS count=2 expired=true modifier=1.00' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/status_effects_smoke.gd
run_clean 'Tranche 3 addiction state model smoke' 'ADDICTION STATE PASS tolerance=0.70 dependence=1.10 withdrawal=true cleared=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/addiction_state_smoke.gd
run_clean 'Tranche 3 damage pipeline model smoke' 'DAMAGE PIPELINE PASS vitals=65.0 threat=19.0 absorbed=10.0 status=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/damage_pipeline_smoke.gd
run_clean 'Tranche 3 life support state model smoke' 'LIFE SUPPORT STATE PASS offline_drain=true recovery=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_support_state_smoke.gd
run_clean 'Tranche 3 save migration service model smoke' 'SAVE MIGRATION SERVICE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_migration_service_smoke.gd
run_clean 'Tranche 3 world snapshot model smoke' 'WORLD SNAPSHOT PASS round_trip=true version_gated=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_snapshot_smoke.gd
run_clean 'Tranche 3 save slot state model smoke' 'SAVE SLOT STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_slot_state_smoke.gd
run_clean 'Tranche 3 autosave policy model smoke' 'AUTOSAVE POLICY PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/autosave_policy_smoke.gd
run_clean 'Tranche 3 synaptic sea world model smoke' 'SYNAPTIC_SEA WORLD PASS in_range_sorted=true generated=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/synaptic_sea_world_smoke.gd
run_clean 'Tranche 3 meta snapshot model smoke' 'META SNAPSHOT PASS meta=true unlocks=true boundary=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_snapshot_smoke.gd
run_clean 'Tranche 3 world save service smoke' 'WORLD SAVE SERVICE PASS disk_round_trip=true rejects_null=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_service_smoke.gd
run_clean 'Tranche 3 interactable distance fallback smoke' 'INTERACTABLE DISTANCE FALLBACK PASS completed_count=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/interactable_distance_fallback_smoke.gd
# --- Tranche 3: orphaned-smoke promotion — main-scene batch ---
run_clean 'Tranche 3 vitals save/load main-scene smoke' 'VITALS SAVE LOAD PASS vitals=true sanity=true radiation=true temperature=true status=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_state_save_load_smoke.gd
run_clean 'Tranche 3 vitals full main-scene smoke' 'MAIN PLAYABLE VITALS FULL PASS panel=true health=true stamina=true hunger=true thirst=true sanity=true radiation=true temperature=true status=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_full_smoke.gd
run_clean 'Tranche 3 HUD main-scene smoke' 'MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=520 current_sequence=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hud_smoke.gd
run_clean 'Tranche 3 derelict gameplay main-scene smoke' 'DERELICT GAMEPLAY PASS built=true cleared=true persists=true home_intact=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_gameplay_smoke.gd
run_clean 'Tranche 3 world persist/restore main-scene smoke' 'WORLD PERSIST RESTORE PASS registered=true state_preserved=true revisit_restores=true travel_home=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_persist_restore_smoke.gd
run_clean 'Tranche 3 world save anywhere main-scene smoke' 'WORLD SAVE ANYWHERE PASS away_save=true location_restored=true state_restored=true home_save=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_anywhere_smoke.gd
run_clean 'Tranche 3 input-action idempotency smoke' 'IDEMPOTENCY PASS actions=7 no_duplicates_after_second_call=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/a11y_p1_002_idempotency_smoke.gd
run_clean 'Tranche 3 progression main-scene smoke' 'MAIN PLAYABLE PROGRESSION PASS class=engineer repair_xp_gained=true hud=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_progression_smoke.gd
# --- Tranche 3: new coverage — PhaseTimer behavior + real Area3D interaction path ---
run_clean 'Tranche 3 phase timer model smoke' 'PHASE TIMER PASS clamp=true boundary=true carry=true single_flip=true progress=true durations=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/phase_timer_smoke.gd
run_clean 'Tranche 3 interactable body-entered physics smoke' 'INTERACTABLE BODY ENTERED PASS far_null=true entered=true interact=true exited_cleared=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/interactable_body_entered_smoke.gd
# --- Tranche 4 (2026-07-06): UI wiring — audio log panel, difficulty label, menu-modal guard ---
run_clean 'Tranche 4 audio log panel smoke' 'AUDIO LOG PANEL PASS entries=6 play=true stop=true clip_attempted=true populated_gate=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_log_panel_smoke.gd
run_clean 'Tranche 4 settings difficulty label smoke' 'SETTINGS DIFFICULTY LABEL PASS standard=x1.0 hardened=x1.4 deep_dive=x1.7 delegation=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/settings_difficulty_label_smoke.gd
run_clean 'Tranche 4 panel menu-modal guard smoke' 'PANEL MENU MODAL GUARD PASS scanner_blocked=true chart_blocked=true inventory_blocked=true reopens=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/panel_menu_modal_guard_smoke.gd
# --- Tranche 5 (2026-07-07): procgen & data coherence — behavior guards + the promoted procgen layout gate ---
# Two new Tranche-5 smokes, then the 32 deferred-pending-T5 promotions (run
# first -> stale pins fixed -> registered; see the orphan classification
# table). Long-runtime members (derelict generator 100 seeds, layout stress
# 60 runs, the physics walkers) add several minutes to a full bundle run.
run_clean 'Tranche 5 layout schema coherence smoke' 'LAYOUT SCHEMA COHERENCE PASS goldens=3 version_match=true keys_match=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/layout_schema_coherence_smoke.gd
run_clean 'Tranche 5 derelict fire zone marker smoke' 'DERELICT FIRE ZONE MARKER PASS boarded=true marker_position_used=true spec_meta=true fallback_intact=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_fire_zone_marker_smoke.gd
run_clean 'archetype load smoke' 'ARCHETYPE LOAD PASS archetypes=3 round_trip=3' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/archetype_load_smoke.gd
run_clean 'biome profile smoke' 'BIOME PROFILE PASS biomes=3 modifiers=ok hazard_override=ok empty_safe=true select_deterministic=true density_scales=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/biome_profile_smoke.gd
run_clean 'room graph smoke' 'ROOM GRAPH PASS rooms=3 links=2 connected=true disconnected_detected=true serialization=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_graph_smoke.gd
run_clean 'ship blueprint smoke' 'SHIP BLUEPRINT PASS sizes=3 conditions=3 serialization=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_blueprint_smoke.gd
run_clean 'topology template smoke' 'TOPOLOGY TEMPLATE PASS from_dict=true get_zone=true attached=true count_types=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/topology_template_smoke.gd
run_clean 'template data smoke' 'TEMPLATE DATA PASS templates=3 all_valid=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/template_data_smoke.gd
run_clean 'template selector smoke' 'TEMPLATE SELECTOR PASS explicit=true deterministic=true varied=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/template_selector_smoke.gd
run_clean 'marker generator smoke' 'MARKER GENERATOR PASS deterministic=true per_cell=3 round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/marker_generator_smoke.gd
run_clean 'wall door resolver smoke' 'WALL DOOR RESOLVER PASS walls=true portals=true interior=true no_conflict=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/wall_door_resolver_smoke.gd
# seed_determinism's marker ends with the pipeline-output hash, which is
# stable per code version but changes with ANY legitimate pipeline change —
# the pin stops at `hash=` on purpose.
run_clean 'seed determinism smoke' 'SEED DETERMINISM PASS fnv_empty=ok fnv_hello=ok match=true golden_match=true seeds_differ=true hash=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/seed_determinism_smoke.gd
run_clean 'cell layout engine smoke' 'CELL LAYOUT ENGINE PASS rooms=6 adjacencies=5 no_overlap=true connected=true deterministic=true connections_wired=true stacked_v2_elevator=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cell_layout_engine_smoke.gd
run_clean 'room assigner smoke' 'ROOM ASSIGNER PASS rooms=5 first=airlock last=reactor keys=valid ids=unique deterministic=true guaranteed=enforced max_duplicates=enforced' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_assigner_smoke.gd
run_clean 'layout serializer smoke' 'LAYOUT SERIALIZER PASS keys=valid rooms=2 schema=1.2.0 golden_format=true prototype=valid critical_path=valid portals_json=true link_deck=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/layout_serializer_smoke.gd
run_clean 'ship layout generator smoke' 'SHIP LAYOUT GENERATOR PASS spine=true bifurcated=true stacked=true deterministic=true varied=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_layout_generator_smoke.gd
run_clean 'ship layout integration smoke' 'SHIP LAYOUT INTEGRATION PASS generated=21/21 deterministic=true json_roundtrip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_layout_integration_smoke.gd
run_clean 'room graph generator smoke' 'ROOM GRAPH GENERATOR PASS life_boat=4 small=5 medium=8 deterministic=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_graph_generator_smoke.gd
run_clean 'structural placer smoke' 'STRUCTURAL PLACER PASS rooms=10 modules=24 second_rooms=8 second_modules=20 unknown_role_fallback=ok' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/structural_placer_smoke.gd
run_clean 'encounter injector smoke' 'ENCOUNTER INJECTOR PASS std_markers=0 deep_markers=2 markers_valid=true deterministic=true critical_safe=true legacy_compat=true table_driven=true table_fallback=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/encounter_injector_smoke.gd
run_clean 'gameplay slice builder smoke' 'GAMEPLAY_SLICE_BUILDER PASS all 9 layouts produced valid slices loot_containers=true salvage_tables=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gameplay_slice_builder_smoke.gd
run_clean 'template c traversal smoke' 'TEMPLATE C TRAVERSAL PASS transitions_checked=1 missing=ok deck=ok cell=ok self=ok critical_path=ok pipeline_transitions=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/template_c_traversal_smoke.gd
run_clean 'derelict generator smoke' 'DERELICT GENERATOR PASS seeds=100 determinism=3 hangar_seeds=80' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_generator_smoke.gd
# marker pinned to the bracket-free prefix: run_clean greps the marker, and
# the full line's rooms=[9,12] is a character class under grep.
run_clean 'procgen layout stress smoke' 'PROCGEN LAYOUT STRESS PASS total=60/60' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_layout_stress_smoke.gd
run_clean 'load from blueprint smoke' 'LOAD FROM BLUEPRINT INTEGRATION PASS sizes=3 room_count=10 null_rejected=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/load_from_blueprint_smoke.gd
run_clean 'ship generator smoke' 'SHIP GENERATOR PASS life_boat=true small=true deterministic=true life_rooms=10 small_rooms=12' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_generator_smoke.gd
run_clean 'procgen playable ship smoke' 'PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_playable_ship_smoke.gd
run_clean 'procgen runtime demo smoke' 'RUNTIME GAMEPLAY DEMO PASS objectives=4 interactions=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_runtime_demo_smoke.gd
run_clean 'procgen walkability smoke' 'WALKABILITY PASS spine_seed_42' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_walkability_smoke.gd
run_clean 'interior aabb smoke' 'INTERIOR AABB PASS nondegenerate=true positioned=true contains=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/interior_aabb_smoke.gd
run_clean 'kit catalog smoke' 'KIT CATALOG PASS loaded=3 default=ship_structural_v0 airlock=3 eng=3 breach_select=ok fallback=ok real_stems=true default_role_module=floor_1x1 ids_sorted=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/kit_catalog_smoke.gd
run_clean 'floor wrapper collision footprint smoke' 'FLOOR WRAPPER COLLISION FOOTPRINT PASS checked=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/floor_wrapper_collision_footprint_smoke.gd
run_clean 'readability prop factory smoke' 'READABILITY PROP FACTORY PASS props=9' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/readability_prop_factory_smoke.gd
run_clean 'procgen loader playable contract smoke' 'PROCGEN LOADER PLAYABLE CONTRACT PASS loaded=true objectives=4 collision_shapes=122' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_loader_playable_contract_smoke.gd
# --- Tranche 6 (2026-07-07): demo gate wiring + unlock triggers + the promoted gate model smoke ---
run_clean 'Tranche 6 demo scope gate model smoke' 'DEMO SCOPE GATE PASS build_kind=release blocked=5 allowed=0 unknown_rejected=true params=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/demo_scope_gate_smoke.gd
run_clean 'Tranche 6 demo scope enforcement smoke' 'DEMO SCOPE ENFORCEMENT PASS dev_unaffected=true save_cap=true world_skip=true hub_blocked=true hazards_capped=true cargo_capped=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/demo_scope_enforcement_smoke.gd
run_clean 'Tranche 6 unlock trigger production smoke' 'UNLOCK TRIGGER PRODUCTION PASS triggers_valid=true scavenge_emitted=true codex_unlocked=true class_unlocked=true bridge_unlocked=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/unlock_trigger_production_smoke.gd
run_clean 'Stream D unlock trigger live actions smoke' 'UNLOCK TRIGGER STREAM D PASS scan=true first_aid=true cook=true fabricate=true repair=true weld=true travel=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/unlock_trigger_stream_d_smoke.gd
run_clean 'Stream E unlock + junk salvage smoke' 'UNLOCK TRIGGER STREAM E PASS ration=true diagnose=true discover=true extract=true compound=true junk_salvage=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/unlock_trigger_stream_e_smoke.gd
run_clean 'Stream F unlock + Fire B2 smoke' 'UNLOCK TRIGGER STREAM F PASS surgery=true decode=true shelter=true social=true fire_b2=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/unlock_trigger_stream_f_smoke.gd
run_clean 'ADR-0049 ship nav graph smoke' 'SHIP NAV GRAPH PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_nav_graph_smoke.gd
run_clean 'ADR-0049 threat pathfinder smoke' 'THREAT PATHFINDER PASS path=true step=true flee=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_pathfinder_smoke.gd
run_clean 'ADR-0049 threat path follow smoke' 'THREAT PATH FOLLOW PASS advanced=true no_tunnel=true graph=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_path_follow_smoke.gd
run_clean 'ADR-0049 main playable threat pathfinding smoke' 'MAIN PLAYABLE THREAT PATHFINDING PASS graph=true advanced=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_threat_pathfinding_smoke.gd
run_clean 'Procgen quality gate smoke' 'PROCGEN QUALITY GATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_quality_gate_smoke.gd
run_clean 'Procgen golden parity smoke' 'PROCGEN GOLDEN PARITY PASS goldens=3 nav=true schema=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_golden_parity_smoke.gd
run_clean 'Procgen derelict pipeline contract smoke' 'MAIN PLAYABLE DERELICT PIPELINE CONTRACT PASS layout=true nav=true biome=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_derelict_pipeline_contract_smoke.gd
# --- Pre-polish foundations (2026-07-22 Wave 0): SimKeys + TuningCatalog shells ---
run_clean 'SimKeys contract smoke' 'SIM KEYS PASS hot=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sim_keys_smoke.gd
run_clean 'TuningCatalog shell smoke' 'TUNING CATALOG PASS shell=true dir_loaded=' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/tuning_catalog_smoke.gd
# --- Pre-polish PKG-A1a: ShipRuntime advance/catch-up ---
run_clean 'ShipRuntime shell smoke' 'SHIP RUNTIME PASS advance=true catchup=true idempotent=true hub_skip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_runtime_smoke.gd
run_clean 'Tick bands smoke' 'TICK BANDS PASS frame=true slow=true lazy=true catchup_lazy=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/tick_bands_smoke.gd
run_clean 'Module integrity pure smoke' 'MODULE INTEGRITY PASS fsm=true sparse=true determinism=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/module_integrity_smoke.gd
run_clean 'Dressing consumption smoke' 'DRESSING CONSUMPTION PASS presets=true descriptors=true lights=true density=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dressing_consumption_smoke.gd
run_clean 'WorkAction pure smoke' 'WORK ACTION STATE PASS catalog=true gates=true progress=true interrupt=true yield=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_action_state_smoke.gd
run_clean 'Module integrity consequences smoke' 'MODULE INTEGRITY CONSEQUENCES PASS fire=true breach_derived=true scene=true nav=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/module_integrity_consequences_smoke.gd
run_clean 'WorkAction resolve smoke' 'WORK ACTION RESOLVE PASS cut=true weld=true yields=true noise=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_action_resolve_smoke.gd
run_clean 'Component slot population smoke' 'COMPONENT SLOT POPULATION PASS catalog=true placed=true deterministic=true no_collision=true linked=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/component_slot_population_smoke.gd
run_clean 'Crafting quality knowledge smoke' 'CRAFTING QUALITY KNOWLEDGE PASS quality=true knowledge=true reverse=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/crafting_quality_knowledge_smoke.gd
run_clean 'Repair unification smoke' 'REPAIR UNIFICATION PASS repair=true seal=true suppress=true interrupt=true catalog=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_unification_smoke.gd
run_clean 'Component mount/dismount smoke' 'COMPONENT MOUNT DISMOUNT PASS dismount=true mount=true work=true mass=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/component_mount_dismount_smoke.gd
run_clean 'Station tiers batch smoke' 'STATION TIERS BATCH PASS tier=true queue=true gate=true schema=true batch=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/station_tiers_batch_smoke.gd
run_clean 'Wound state pure smoke' 'WOUND STATE PASS kinds=true bleed=true infection=true work_speed=true treat=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/wound_state_smoke.gd
run_clean 'Spatial perception pure smoke' 'SPATIAL PERCEPTION PASS los=true muffle=true blocked=true open=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/spatial_perception_smoke.gd
run_clean 'Vitals curves cross-coupling smoke' 'VITALS CURVES PASS curves=true cross=true wounds=true cold=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_curves_smoke.gd
run_clean 'Archetype behavior modifiers smoke' 'ARCHETYPE BEHAVIOR PASS ambush=true stalk=true swarm=true anchored=true telegraph=true verbs=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/archetype_behavior_smoke.gd
run_clean 'Manifestation pool schema smoke' 'MANIFESTATION POOL PASS schema=true kinds=true force_room=true force_log=true no_code_entry=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/manifestation_pool_smoke.gd
run_clean 'Sea graph pure smoke' 'SEA GRAPH PASS nodes=true route=true cost=true biomes=true extract=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sea_graph_smoke.gd
run_clean 'Templates wreck mutator smoke' 'TEMPLATES WRECK MUTATOR PASS catalog=true load=true zone=true branch=true wreck=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/templates_wreck_mutator_smoke.gd
run_clean 'Food sustenance closure smoke' 'FOOD CLOSURE PASS spoil_eat=true harvest=true travel=true loop=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_closure_smoke.gd
run_clean 'Skill effects consumers smoke' 'SKILL EFFECTS PASS audit=true work=true craft=true heal=true travel=true class_kit=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/skill_effects_smoke.gd
run_clean 'Pillar persistence smoke' 'PILLAR PERSISTENCE PASS integrity=true components=true work=true fuzz=true snapshot=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/pillar_persistence_smoke.gd
run_clean 'WorkAction driver smoke' 'WORK ACTION DRIVER PASS cut=true noise=true yield=true interrupt=true overload=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_action_driver_smoke.gd
run_clean 'Threat LOS perception smoke' 'THREAT LOS PERCEPTION PASS room_los=true closed_hatch=true raycast=true distance=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_los_perception_smoke.gd
run_clean 'UI consumers D9 smoke' 'UI CONSUMERS D9 PASS work_hud=true wounds=true chart_route=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_consumers_d9_smoke.gd
run_clean 'Audio event coverage smoke' 'AUDIO EVENT COVERAGE PASS verbs=true seam=true router=true work_driver=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_event_coverage_smoke.gd
run_clean 'Ship modification smoke' 'SHIP MODIFICATION PASS install=true power=true uninstall=true plating=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_modification_smoke.gd
run_clean 'Work action integration smoke' 'WORK ACTION INTEGRATION PASS driver=true hud=true wounds=true shipmod=true cut=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_action_integration_smoke.gd
run_clean 'Hub explorable verify smoke' 'HUB EXPLORABLE VERIFY PASS home=true stations=true repair=true walk=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hub_explorable_verify_smoke.gd
run_clean 'Pillar revisit persistence smoke' 'PILLAR REVISIT PERSISTENCE PASS integrity=true components=true ship=true runtime=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/pillar_revisit_persistence_smoke.gd
run_clean 'Ship modification panel smoke' 'SHIP MOD PANEL PASS bind=true install=true uninstall=true power=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_modification_panel_smoke.gd
run_clean 'Work action interact smoke' 'WORK ACTION INTERACT PASS start=true tick=true complete=true nearest=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_action_interact_smoke.gd
run_clean 'Component placement runtime smoke' 'COMPONENT PLACEMENT RUNTIME PASS wired=true populate_or_empty=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/component_placement_runtime_smoke.gd
run_clean 'Component dismount interact smoke' 'COMPONENT DISMOUNT INTERACT PASS start=true tick=true stripped=true yield=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/component_dismount_interact_smoke.gd
run_clean 'Component mount interact smoke' 'COMPONENT MOUNT INTERACT PASS dismount=true remount=true mounted=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/component_mount_interact_smoke.gd
run_clean 'Component markers smoke' 'COMPONENT MARKERS PASS wired=true count=true rebuild=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/component_markers_smoke.gd
run_clean 'Component system link smoke' 'COMPONENT SYSTEM LINK PASS catalog_links=true soft_fill=true coverage=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/component_system_link_smoke.gd
run_clean 'Dismount system damage smoke' 'DISMOUNT SYSTEM DAMAGE PASS link=true damage=true remount_no_autoheal=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dismount_system_damage_smoke.gd
run_clean 'Synthetic wall slots smoke' 'SYNTHETIC WALL SLOTS PASS wall=true center=true placed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/synthetic_wall_slots_smoke.gd
run_clean 'Multi-source module damage smoke' 'MULTI SOURCE MODULE DAMAGE PASS fire=true decomp=true threat=true tool=true interrupt=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/multi_source_module_damage_smoke.gd
run_clean 'Ship mod panel input smoke' 'SHIP MOD PANEL INPUT PASS open=true select=true close=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_panel_input_smoke.gd
run_clean 'Combat work interrupt smoke' 'COMBAT WORK INTERRUPT PASS start=true hit=true interrupted=true no_yield=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/combat_work_interrupt_smoke.gd
run_clean 'Tendril structure damage smoke' 'TENDRIL STRUCTURE DAMAGE PASS archetype=true hit=true damaged=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/tendril_structure_damage_smoke.gd
run_clean 'Work yield inventory smoke' 'WORK YIELD INVENTORY PASS cut=true scrap=true qty=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_yield_inventory_smoke.gd
run_clean 'Ship mod inventory sync smoke' 'SHIP MOD INVENTORY SYNC PASS install=true uninstall=true inv=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_inventory_sync_smoke.gd
run_clean 'Work yield drop smoke' 'WORK YIELD DROP PASS overload=true drop=true scoop=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_yield_drop_smoke.gd
run_clean 'Work progress noise smoke' 'WORK PROGRESS NOISE PASS cut=true pulse=true detection=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_progress_noise_smoke.gd
run_clean 'Wound bandage inventory smoke' 'WOUND BANDAGE INVENTORY PASS wound=true bandage=true consume=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/wound_bandage_inventory_smoke.gd
run_clean 'Cut module scene smoke' 'CUT MODULE SCENE PASS cut=true damaged=true sparse=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cut_module_scene_smoke.gd
run_clean 'Remount system restore smoke' 'REMOUNT SYSTEM RESTORE PASS damage=true remount=true floor=true no_full=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/remount_system_restore_smoke.gd
run_clean 'Ship mod run snapshot smoke' 'SHIP MOD RUN SNAPSHOT PASS shipmod=true pillar=true count=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_run_snapshot_smoke.gd
run_clean 'Work hold-to-work smoke' 'WORK HOLD TO WORK PASS freeze=true validation=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_hold_to_work_smoke.gd
run_clean 'Bandage training smoke' 'BANDAGE TRAINING PASS bandage_xp=true treat_xp=true catalog=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/bandage_training_smoke.gd
run_clean 'Ship mod install key smoke' 'SHIP MOD INSTALL KEY PASS install=true catalog=true uninstall=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_install_key_smoke.gd
run_clean 'Ship mod system effect smoke' 'SHIP MOD SYSTEM EFFECT PASS restore=true power=true uninstall_damage=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_system_effect_smoke.gd
run_clean 'Ship mod station tier smoke' 'SHIP MOD STATION TIER PASS install=true tier=true uninstall=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_station_tier_smoke.gd
run_clean 'Hull plating resist smoke' 'HULL PLATING RESIST PASS resist=true reduced=true zero_away=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hull_plating_resist_smoke.gd
run_clean 'Work stamina drain smoke' 'WORK STAMINA DRAIN PASS start=true drain=true speed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_stamina_drain_smoke.gd
run_clean 'Work weld damaged smoke' 'WORK WELD DAMAGED PASS start=true repair=true consume=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_weld_damaged_smoke.gd
run_clean 'Ship mod restore effects smoke' 'SHIP MOD RESTORE EFFECTS PASS restore=true tier=true system=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_restore_effects_smoke.gd
run_clean 'Fire plating resist smoke' 'FIRE PLATING RESIST PASS resist=true reduced=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_plating_resist_smoke.gd
run_clean 'Work stamina interrupt smoke' 'WORK STAMINA INTERRUPT PASS start=true exhaust=true interrupted=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_stamina_interrupt_smoke.gd
run_clean 'Work weld skill context smoke' 'WORK WELD SKILL CONTEXT PASS skill=true start=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_weld_skill_context_smoke.gd
run_clean 'Ship mod install XP smoke' 'SHIP MOD INSTALL XP PASS install_xp=true uninstall_xp=true catalog=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_install_xp_smoke.gd
run_clean 'Ship mod audio smoke' 'SHIP MOD AUDIO PASS seam=true router=true route=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_audio_smoke.gd
run_clean 'Hull plating catalog smoke' 'HULL PLATING CATALOG PASS catalog=true install=true bonus=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hull_plating_catalog_smoke.gd
run_clean 'Work block zero stamina smoke' 'WORK BLOCK ZERO STAMINA PASS block=true start_ok=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_block_zero_stamina_smoke.gd
run_clean 'Ship mod power budget scene smoke' 'SHIP MOD POWER BUDGET SCENE PASS fill=true reject=true inventory=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_power_budget_scene_smoke.gd
run_clean 'Work action XP catalog smoke' 'WORK ACTION XP CATALOG PASS cut=true weld=true salvage=true repair=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_action_xp_catalog_smoke.gd
run_clean 'Work cut XP live smoke' 'WORK CUT XP LIVE PASS start=true complete=true xp=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_cut_xp_live_smoke.gd
run_clean 'Work weld XP live smoke' 'WORK WELD XP LIVE PASS start=true complete=true xp=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_weld_xp_live_smoke.gd
run_clean 'Ship mod overbudget power smoke' 'SHIP MOD OVERBUDGET POWER PASS over=true unpowered=true ok=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_overbudget_power_smoke.gd
run_clean 'Work progress UI SFX smoke' 'WORK PROGRESS UI SFX PASS seam=true router=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_progress_ui_sfx_smoke.gd
run_clean 'Wounds panel open SFX smoke' 'WOUNDS PANEL OPEN SFX PASS seam=true router=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/wounds_panel_open_sfx_smoke.gd
run_clean 'Treat wound SFX smoke' 'TREAT WOUND SFX PASS seam=true router=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/treat_wound_sfx_smoke.gd
run_clean 'Craft complete SFX smoke' 'CRAFT COMPLETE SFX PASS seam=true router=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/craft_complete_sfx_smoke.gd
run_clean 'Repair complete SFX smoke' 'REPAIR COMPLETE SFX PASS seam=true router=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_complete_sfx_smoke.gd
run_clean 'Work complete SFX live smoke' 'WORK COMPLETE SFX LIVE PASS complete=true audio=true route=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/work_complete_sfx_live_smoke.gd
run_clean 'Salvage scavenge XP smoke' 'SALVAGE SCAVENGE XP PASS emit=true catalog=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/salvage_scavenge_xp_smoke.gd
run_clean 'Production harvest XP smoke' 'PRODUCTION HARVEST XP PASS emit=true catalog=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/production_harvest_xp_smoke.gd
run_clean 'Medbay surgery SFX smoke' 'MEDBAY SURGERY SFX PASS surgery=true heal=true xp=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/medbay_surgery_sfx_smoke.gd
run_clean 'Decode signal XP smoke' 'DECODE SIGNAL XP PASS emit=true catalog=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/decode_signal_xp_smoke.gd
run_clean 'Diagnose fault XP smoke' 'DIAGNOSE FAULT XP PASS emit=true catalog=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/diagnose_fault_xp_smoke.gd
run_clean 'Social training XP smoke' 'SOCIAL TRAINING XP PASS inspire=true negotiate=true intimidate=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/social_training_xp_smoke.gd
run_clean 'Stream D/E training XP smoke' 'STREAM DE TRAINING XP PASS discover=true extract=true plot=true ration=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/stream_de_training_xp_smoke.gd
run_clean 'Consumable training XP smoke' 'CONSUMABLE TRAINING XP PASS medicine=true food=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/consumable_training_xp_smoke.gd
run_clean 'Scanner open XP smoke' 'SCANNER OPEN XP PASS open=true xp=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/scanner_open_xp_smoke.gd
run_clean 'Travel training XP smoke' 'TRAVEL TRAINING XP PASS plot=true astrogation=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_training_xp_smoke.gd
run_clean 'Threat kill XP smoke' 'THREAT KILL XP PASS kill=true melee=true catalog=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_kill_xp_smoke.gd
run_clean 'Discover room XP smoke' 'DISCOVER ROOM XP PASS discover=true extract=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/discover_room_xp_smoke.gd
run_clean 'Ship mod plating repair smoke' 'SHIP MOD PLATING REPAIR PASS install=true repair=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_mod_plating_repair_smoke.gd
echo 'SYNAPTIC_SEA REGRESSION PASS commands=315 clean_output=true'
# Note: ShipRuntime smoke marker grew snapshot=true multi=true (PKG-A1b); prefix match above still holds.
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

PR #57 Codex P2 (`TitleSaveQuery.is_continue_available` strengthened to
require a parseable world save) adds one more expected `WARNING:` line:

- `WARNING: SaveLoadService: world save file is not valid JSON object`
  — emitted by `load_world()` when `title_save_query_smoke.gd`'s corrupt-world
  case deliberately overwrites `world.json` with literal garbage to prove
  `is_continue_available()` now calls `load_world()` (not just
  `has_slot`/`has_died_in`) and correctly reads it as unavailable. Filtered
  by `CORRUPT_WORLD_WARNING` in the strict check above; any other
  `SaveLoadService:` warning during this smoke still fails the bundle.
- `ERROR: Parse JSON failed. Error at line 0: ...` — Godot's own JSON parser
  (`core/io/json.cpp`), not a Synaptic Sea `push_error`, printed when
  `JSON.parse_string()` hits the literal garbage the same corrupt-world case
  writes, immediately before `load_world()`'s own dictionary-type check
  fires the `WARNING:` above. Filtered by `CORRUPT_WORLD_JSON_ERROR`; this is
  expected, deterministic engine noise for this one smoke only.

PR #57 Codex round 3 P2 (`save_world()`/`save_to_slot()` move `clear_death`
to after a confirmed write) adds one more expected `WARNING:` line:

- `WARNING: SaveLoadService: cannot open world save file for writing, error=...`
  — emitted by `save_world()` when `permadeath_freeze_smoke.gd`'s
  reclaim-failure stage deliberately pre-creates a directory at
  `world.json`'s path so `FileAccess.open` cannot open it, proving the
  forced write failure leaves an existing death record intact (the ordering
  fix under test). Filtered by `WORLD_WRITE_FAIL_WARNING` in the strict
  check above; any other `SaveLoadService:` warning during this smoke still
  fails the bundle.

`release_readiness_ledger_smoke.gd` adds three expected `WARNING:` lines:

- `WARNING: ReleaseReadinessLedger: unknown check_id=totally_made_up_check`
- `WARNING: ReleaseReadinessLedger: invalid status=WAT`
- `WARNING: ReleaseReadinessLedger: external evidence rejected, evidence_path is required`

These are deliberate rejection-path cases proving the release ledger refuses
unknown checks, invalid statuses, and external rows without evidence paths.
They are pinned to the smoke's sentinel values by
`RELEASE_LEDGER_UNKNOWN_WARNING`, `RELEASE_LEDGER_STATUS_WARNING`, and
`RELEASE_LEDGER_EXTERNAL_WARNING`; any other `ReleaseReadinessLedger:` warning
still fails the bundle.

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
- [x] Save/load service smoke: `scripts/validation/save_load_service_smoke.gd` (expected marker `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=28`) and main-scene smoke `scripts/validation/main_playable_slice_save_load_smoke.gd` (expected marker `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`) (REQ-012). Added to regression bundle.
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
- [x] Domain 4 web infestation model smoke: `scripts/validation/web_infestation_state_smoke.gd` (expected marker `WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true`) — pure-model: coverage grows while web-attached and tick() returns hull damage; recedes when cut free; save round-trip; apply_summary rejects a mismatched hazard_kind. Added to regression bundle.
- [x] Domain 4 ship systems closure smoke: `scripts/validation/ship_systems_closure_smoke.gd` (expected marker `SHIP SYSTEMS CLOSURE PASS away_ticks=60 web_grew=true hull_damaged=true breach_to_vitals=true`) — main-scene: drives `away_from_start = true` and proves the hub web infestation ticks on the away branch, damages the hull, and the resulting breach engages the life-support atmosphere→vitals drain. Closes the `ship_systems` loop's live-input + both-branch requirements. Added to regression bundle.
- [x] Hub/meta progression smoke (deferred past Gate 2 per ADR-0003).
- [x] GUT suite if/when adopted by ADR.
- [x] Performance baseline smoke: `scripts/validation/performance_profiler.gd` (expected marker `PERFORMANCE BASELINE PASS templates=3`) — first baseline numbers established 2026-06-19 at `docs/game/performance_baseline.md`. Headless harness covers load time, procgen time, peak Godot static memory, and end-of-run OS RSS across the two known procgen templates plus the main playable scene. Windowed FPS at `scripts/validation/windowed_fps_capture.gd` is intentionally NOT in the bundle (requires a display server); it is the source of truth for the frame-time target and is run on demand during Gate 3 / Gate 4 review. Added to regression bundle.
- [x] Junction calibrator model smoke: `scripts/validation/junction_calibrator_state_smoke.gd` (expected marker `JUNCTION CALIBRATOR STATE PASS required_steps=2 consumed=true`) and main-scene smoke `scripts/validation/main_playable_slice_junction_calibrator_smoke.gd` (expected marker `MAIN PLAYABLE JUNCTION CALIBRATOR PASS acquired=true required_steps=2 consumed=true`) (REQ-014). Added to regression bundle. The main-scene smoke registers a synthetic 3-step junction through `register_junction_sequence_for_validation` so it asserts the exact `required_steps=2` post-calibration marker without depending on the seed template's exact step count (the seed template's sequence 2 is a 2-step junction; REQ-014's spec example requires a 3-step reduction target).
- [x] Junction calibrator save/load smoke: `scripts/validation/main_playable_slice_junction_calibrator_save_load_smoke.gd` (expected marker `MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS carried_load=true consumed_load=true next_frame_interaction=true`) — permanent regression for the two blocking findings from review t_80dcea4b. Drives the actual seed sequence 2 repair_junction through save/load in both carried and consumed/applied save states, including a real next-frame interaction after each load. Asserts the live coordinator path leaves the objective_progress model complete after the calibrator reduces a real 2-step junction to 1 (the pre-calibration `required_steps` snapshot lets `complete_step` fire on the first interaction instead of being skipped), and that post-load interactions survive the rebuild of the HUD layer / ObjectiveTracker that previously crashed with "Nonexistent function 'mark_completed' in base 'previously freed'". Also locks down the reload pickup-marker reconciliation (carried = hidden, spent = hidden) and the JSON-string-int-key round-trip in `ObjectiveProgressState.apply_summary` that would otherwise silently drop the per-sequence `calibrator_applied` flag. Added to regression bundle.
- [x] Electrical-arc hazard model smoke: `scripts/validation/electrical_arc_state_smoke.gd` (expected marker `ARC STATE PASS cycles=2 phases=4 passability_switches=4`) and main-scene smoke `scripts/validation/main_playable_slice_arc_smoke.gd` (expected marker `MAIN PLAYABLE ARC PASS state=DISCHARGED cycles=2 blocked_arcing=true blocked_discharged=false`) (REQ-013). The pure model smoke advances the cycle through two full DISCHARGED -> ARCING -> DISCHARGED rounds and asserts the phase / passability counts match the ADR-0005 contract; it also round-trips the summary through `apply_summary()` and verifies a wrong `hazard_kind` is rejected. The main-scene smoke drives the same model through `playable.electrical_arc_state.tick(...)` against template 002 (which carries the new `arc_side_01` non-critical side branch) and asserts collision is enabled only while ARCING. Both are added to the regression bundle.
- [x] ADR-0005 hazard contract static smoke: `scripts/validation/hazard_contract_smoke.gd` (expected marker `HAZARD CONTRACT PASS models=2 phase_timer_owners=1 wrong_kind_rejected=2 configure_dict=2` — Tranche 6 prose correction: this bullet previously claimed the pre-ADR-0041 `models=3` counts; FireState left the timer-hazard set when ADR-0041 replaced it with FireSuppressionState, and the smoke + the bundle's run_clean pin have said `models=2` ever since) — structural (no runtime tick) assertion that catches the three review-recycle findings on REQ-013 / REQ-014 hazard models: (1) ElectricalArcState MUST own a `PhaseTimer` instance and translate its `Phase.A/B` output into its own enum, (2) `get_summary()` MUST include `hazard_kind` on every model, and (3) `apply_summary()` MUST reject a wrong-kind summary. Also asserts OxygenState does NOT own a `PhaseTimer` (negative decision from ADR-0005: resource-drain hazards do not need timer phases) and that the `PhaseTimer` helper itself does not carry a `HAZARD_KIND` discriminator. Locks down the `configure(config: Dictionary)` uniform boundary from the ADR-0005 HazardStateContract. Added to regression bundle.
- [x] Derelict fire — 5 smokes (M7-B / ADR-0041 / this branch `feat/derelict-fire`):
  - `scripts/validation/fire_suppression_round_trip_smoke.gd` (marker `FIRE SUPPRESSION ROUND TRIP PASS topo=true fires=true spreads=true`) — proves `FireSuppressionState.get_summary()`/`apply_summary()` round-trips the full state including compartments + adjacency topology, so a per-ship model restored from a snapshot still spreads.
  - `scripts/validation/ship_instance_fire_persistence_smoke.gd` (marker `SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true`) — proves the "fire" key is omitted from `ShipInstance.get_summary()` when no compartment burns (no snapshot bloat), and that a burning state is faithfully restored via `apply_summary()`.
  - `scripts/validation/derelict_fire_seed_smoke.gd` (marker `DERELICT FIRE SEED PASS deterministic=true rate_ok=true cap_ok=true`) — proves the presence gate is deterministic (RNG-free hash), rate is in the band around 15%, and the cap formula matches the real `ShipBlueprint.Condition` enum ordinals.
  - `scripts/validation/main_playable_derelict_fire_smoke.gd` (marker `MAIN PLAYABLE DERELICT FIRE PASS` — stable prefix; away_ticks count varies run-to-run and is not grepped) — live-scene proof: board a real derelict, fire ticks on the away branch, player standing in a derelict fire zone takes vitals drain, recharge port is power-gated by the derelict's own system, and manual extinguish works via the real interaction path. Requires `travel_to_marker_id` (not just `away_from_start=true`) so current_ship is a genuine derelict instance.
  - `scripts/validation/derelict_fire_sequential_persistence_smoke.gd` (marker `DERELICT FIRE SEQUENTIAL PERSISTENCE PASS remembered=true`) — live-revisit proof: board a derelict, ignite 2 compartments, extinguish 1 via the real interaction path, travel home, revisit the same marker — the burning set is preserved exactly (extinguished compartment stays out; remaining compartment still burns). Proves `fire_seeded` gate prevents re-seeding and `visited_ships` retains the per-ship `FireSuppressionState` across trips. All 5 added to regression bundle (commands 59–63).
- [x] Domain 2 combat — 7 smokes (BP1+BP2+BP3):
  - `scripts/validation/detection_state_smoke.gd` (marker `DETECTION STATE PASS`) — pure-model: `DetectionState` emitted-profile contract (noise rises with movement, visibility lowers with crouch). Added to regression bundle.
  - `scripts/validation/threat_detection_source_smoke.gd` (marker `THREAT DETECTION SOURCE PASS single_source=true per_archetype=true proximity=true`) — pure-model: `ThreatDetectionSource` per-archetype weighting and proximity falloff. Added to regression bundle.
  - `scripts/validation/player_crouch_smoke.gd` (marker `PLAYER CROUCH PASS`) — pure-node seam: `PlayerController` exposes a `set_crouching(bool)` method that the coordinator's detection feed reads. Added to regression bundle.
  - `scripts/validation/crouch_action_smoke.gd` (marker `CROUCH ACTION PASS registered=true`) — input-map seam: the `crouch` action is registered in `InputMap` so the coordinator can poll it. Added to regression bundle.
  - `scripts/validation/threat_kill_removal_smoke.gd` (marker `THREAT KILL REMOVAL PASS emitted_once=true removed=true loot_table=true`) — pure-model: health→0 emits `threat_killed`, `ThreatManager._sweep_dead_threats()` removes the entry, and a loot table row exists for the archetype. Added to regression bundle.
  - `scripts/validation/combat_reward_data_smoke.gd` (marker `COMBAT REWARD DATA PASS archetypes=true table=true training=true`) — data: loot-table JSON covers all combat archetypes, reward weights sum correctly, and at least one training-item row exists. Added to regression bundle.
  - `scripts/validation/combat_closure_smoke.gd` (marker `COMBAT CLOSURE PASS away_kill=true noise=true crouch=true reward=true removed=true`) — live-scene closure: on the derelict away branch the real coordinator `_process` tick drives BP2 (noise/visibility emitted profile), BP1 (detection state update), and BP3 (kill spawns lootable corpse + sweeps threat). Regression guard for the away-branch early-return gap that previously starved combat ticks. Added to regression bundle.
- [x] Live Persistent Ships Phase 1 — world time clock: `scripts/validation/world_time_persistence_smoke.gd` (marker `WORLD TIME PASS advances=true world_snapshot_roundtrip=true ship_timestamp_roundtrip=true`) — pure-model: `world_time` advances across simulated `_process` frames, round-trips through the world snapshot save/load path, and `ShipInstance.last_sim_time` round-trips through `ShipInstance.get_summary()`/`apply_summary()`. Added to regression bundle.
- [x] Live Persistent Ships Phase 2 — per-ship hull + web on ShipInstance: `scripts/validation/ship_instance_models_smoke.gd` (marker `SHIP INSTANCE MODELS PASS hull_roundtrip=true web_roundtrip=true web_attached_delegates=true`) — proves `ShipInstance` lazily creates + persists a `HullIntegrityState` and `WebInfestationState` per ship, both round-trip through summary, and `_active_hull()`/`_active_web()` accessor delegates resolve correctly. Added to regression bundle.
- [x] Live Persistent Ships Phase 2 (seed) — derelict hull + web seeded on generation: `scripts/validation/ship_models_seed_smoke.gd` (marker `SHIP MODELS SEED PASS hull_seeded=true web_attached=true timestamp_set=true active_resolves=true`) — proves derelict `ShipInstance` hull is seeded from config on generation, web is seeded with `web_attached=true`, `last_sim_time` is stamped, and the active accessors return the correct per-ship models. Added to regression bundle.
- [x] Live Persistent Ships Phase 4 — catch-up on revisit: `scripts/validation/ship_catchup_smoke.gd` (marker `SHIP CATCHUP PASS web_grew=true hull_degraded=true timestamp_stamped=true bounded=true`) — proves `_catch_up_ship` advances a retained derelict `ShipInstance` by the elapsed `world_time` gap (web coverage grew, hull degraded), stamps `last_sim_time`, and is numerically bounded (large `dt` via capped sub-steps produces no NaN/over-damage). Added to regression bundle.
- [x] Domain 6 progression — 8 smokes (REQ-PM-001..019 / ADR-0033):
  - `scripts/validation/training_gate_smoke.gd` (marker `TRAINING GATE PASS gated=true drop=1 unlock_grants=true`) — pure-model: an advanced-skill training event is dropped by `TrainingEventBus` while its `SkillTreeState` gate is locked, and grants once unlocked. Added to regression bundle.
  - `scripts/validation/class_catalog_smoke.gd` (marker `CLASS CATALOG PASS base=8 unlockable=3 registry_class_ids=ok`) — data: 8 base + 3 unlockable classes load and cross-check against `UnlockRegistry` class ids. Added to regression bundle.
  - `scripts/validation/class_gate_config_smoke.gd` (marker `CLASS GATE CONFIG PASS available_gate=true`) — data/config: an unlockable class stays gated until its unlock condition is met. Added to regression bundle.
  - `scripts/validation/repair_ingest_smoke.gd` (marker `REPAIR INGEST PASS bus_xp=120 single_grant=true`) — pure-model: a repair-subcomponent event ingested through `TrainingEventBus` grants XP exactly once per completion. Added to regression bundle.
  - `scripts/validation/meta_progression_state_smoke.gd` (marker `META PROGRESSION STATE PASS payout=39 unlocks=true persistence=true reset=true selected_class=true`) — pure-model: `MetaProgressionState`/`UnlockRegistry` currency, unlock, payout, disk persistence, reset, and `selected_class_id` round-trip. **Pre-existing coverage gap closed by this task** — this smoke existed but was never registered in the bundle prior to Domain 6 Task 9; its marker also gained the `selected_class=true` suffix in Task 1. Added to regression bundle.
  - `scripts/validation/player_progression_full_smoke.gd` (marker `PLAYER PROGRESSION FULL PASS classes=11 cross_training=true books=true meta_payout=70 unlocks=true panels=true`) — full-surface pure-model smoke covering `PlayerProgressionState`, cross-training, skill books, `SkillTreeState`, `HubUpgradeState` composition, `MetaProgressionState` payout, `UnlockRegistry`, and the class/skill-tree/hub-upgrade panel status lines. **Pre-existing coverage gap closed by this task** — never registered prior to Domain 6 Task 9. Added to regression bundle.
  - `scripts/validation/meta_screens_interactive_smoke.gd` (marker `META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true registry_reader=true class_select=true`) — live `MenuCoordinator` seam: drives hub-upgrade purchase, skill-tree unlock, unlock-registry reader, and class selection through the real confirm/selection input path. Hardened in this task to wipe the real `user://meta_progression.json` at start/success/failure so its class-select confirm (which saves through the coordinator's real save path) cannot pollute later main-scene smokes booting from the default meta file. Added to regression bundle.
  - `scripts/validation/progression_meta_smoke.gd` (marker `PROGRESSION META CLOSURE PASS away_ticks=1 hub_bonus=1 gate=held class_persist=true`) — end-to-end closure: a purchased hub upgrade persists to disk and composes its starting-skill bonus on a fresh run; an away-context (`away_ticks=1`) kill event grants XP through `TrainingEventBus`; the live-wired `fabricate_part` advanced-skill gate blocks XP until `SkillTreeState.unlock("fabrication")`, then grants; class selection persists across a reload. Closes the Domain 6 progression/meta loop. Added to regression bundle.
  - Also fixed as part of this task: `scripts/validation/main_playable_slice_progression_smoke.gd` now defensively wipes `user://meta_progression.json` in `_initialize()` so its `class=engineer` assertion is deterministic regardless of what ran earlier in the same bundle invocation.
- [x] Domain 7 procgen variation + variant-hazard — 3 smokes (travel loop closure):
  - `scripts/validation/room_variant_selector_smoke.gd` (marker `ROOM VARIANT SELECTOR PASS distinct_per_index=4 distinct_per_seed=7 airlock_variants=4 corridor_variants=7 extended=8 legacy=3 deterministic=true`) — pure-model: `RoomVariantSelector.pick` determinism, per-index/per-seed variation, fallback for unknown roles, `variants_for_role` counts, `TemplateSelector` extended/legacy sets, `effects_for` hazard payloads (fire, breach, empty), and `loot_bias` keys validated against `loot_tables.json`. Added to regression bundle.
  - `scripts/validation/procgen_variation_smoke.gd` (marker `PROCGEN VARIATION PASS variants_vary=true loot_biased=true tmpl_gated=true deterministic=true`) — pure-data generation layer: (1) two different seeds produce distinct room-variant multisets, (2) a variant with `loot_bias` changes a room's `loot_table` vs role baseline (bias-only tables `salvage_cargo`/`salvage_engineering`/`hidden_cache`/`repair_parts_common` prove the override), (3) extended templates (`compact`/`dispersed`/`stacked_v2`/`derelict_a`/`derelict_b`) engage at `deep_dive` while standard difficulty stays on legacy templates (`spine`/`bifurcated`/`stacked`), (4) same seed generated twice produces identical variant + template output. Added to regression bundle.
  - `scripts/validation/procgen_variant_hazard_smoke.gd` (marker `PROCGEN VARIANT HAZARD PASS away_ticks=<n> fire_lit=true breach_open=true home_clean=true seal_point=true guarded=true`) — main-scene away-branch proof: injects a `burned_out` (fire) variant on an engineering room and a `breached` variant on a bridge room of the boarded derelict's layout, configures per-ship hull + fire from tuning, then calls the real `_seed_derelict_breaches()`/`_seed_derelict_fire()` and asserts: engineering ignites on the derelict fire model, bridge breaches on the DERELICT hull (`current_ship.get_hull()`), `_build_breach_seal_points()` creates a seal node for the breached bridge (PR #56 ordering fix), home hull bridge stays clean (wrong-target regression guard), and re-calling the seed functions does not re-seed (`fire_seeded`/`breach_seeded` guards). Added to regression bundle.
- [x] Domain 8 save/persistence — title screen, permadeath freeze, Save & Exit — 6 smokes (ADR-0043):
  - `scripts/validation/permadeath_freeze_smoke.gd` (marker `PERMADEATH FREEZE PASS wrote=true died=true frozen=true reloadable=false epitaph_present=true reclaim=true`) — main-scene: drives death on both the home and away branches, asserts every slot written during the run (autosave family, quickslot, and any manual slot saved to that run) gets a `PermadeathResolver.record_death` entry, the frozen slot refuses to reload through `load_from_slot`/`load_world`, and the epitaph read path (`load_epitaph`) returns a populated record. Also asserts manual-slot freeze and post-death pause-menu access (the `_input` dead-zone fix). Final stage (RECLAIM, final-review C1 fix): simulates the next run's first save into the same "world"/autosave slots frozen by the away-branch death and asserts `save_world()`/`save_to_slot()` clear the death record on write (reclaim-on-write, ADR-0043) -- `has_died_in` flips back false, `load_world()` is non-null again, and `TitleSaveQuery.is_continue_available()` is true. Added to regression bundle.
  - `scripts/validation/title_save_query_smoke.gd` (marker `TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true`) — pure-model: proves the title screen's save-presence query reports no-save on a clean `user://`, has-save once a world/slot exists, and that a frozen (permadeath) slot is excluded from what "Continue" offers. Added to regression bundle.
  - `scripts/validation/title_screen_flow_smoke.gd` (marker `TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true`) — main-scene (boots `title_main.tscn`): drives New Game (instantiates `scenes/main.tscn` fresh) and Continue (instantiates it against an existing save), including a teardown/reinstantiate double-boot check, and asserts the quit action emits its signal. Added to regression bundle.
  - `scripts/validation/title_settings_smoke.gd` (marker `TITLE SETTINGS PASS open=true cycle=true back=true applied=true`) — main-scene (boots `title_main.tscn`): title settings sub-flow (spec §3.7 / ADR-0043 decision 6) — opens the title-local settings screen, cycles a setting (mirroring `menu_coordinator._cycle_setting`), backs out, and asserts the dirty-flagged summary is applied into the session via `apply_ui_settings_summary` on New Game/Continue. Added to regression bundle.
  - `scripts/validation/save_load_slot_screen_smoke.gd` (marker `SAVE LOAD SLOT SCREEN PASS save=true load=true delete_armed=true delete_confirmed=true`) — main-scene: drives the interactive multi-slot screen's save/load/delete-arm/delete-confirm dispatch through real input, including the ship-only-not-world assertion for manual-slot loads (ADR-0043 decision 4). Added to regression bundle.
  - `scripts/validation/save_and_exit_smoke.gd` (marker `SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true`) — main-scene: drives the pause-menu Save & Exit action, asserts `request_save()` persists world.json, a fresh boot reflects the saved state, and `return_to_title_requested` fires. Added to regression bundle.

## Orphan smoke classification (Tranche 3, 2026-07-06)

`scripts/validation/` carries far more smokes than the regression bundle runs. Tranche 3
(audit remediation) promoted 25 of them (23 orphans + 2 new) and classified every remaining
orphan below so none is silent. Dispositions:

- **promotion-candidate** — real, currently-unregistered coverage (mostly pure-model unit
  smokes plus some scene-level flows: docking/hangar is the largest fully-unrepresented
  subsystem, followed by coherent-loader, travel/lifeboat, cargo/cart/equipment,
  food/survival state models, UI panels, e2e chains, and the `main_playable_slice_*`
  cluster, which needs per-file supersession review before wholesale promotion). Promote
  opportunistically when a tranche touches the subsystem.
- **deferred-pending-T5** — RESOLVED 2026-07-07: Tranche 5 promoted 32 of the 36 into the
  bundle (their rows are removed from this table — they are no longer orphans) and
  reclassified the other 4: `procgen_stress_test` (superseded by
  `procgen_layout_stress_smoke`), `gridmap_meshlibrary_smoke` and the two arg-driven ship
  walkers (debug-tool).
- **deferred-pending-T6** — RESOLVED 2026-07-07: Tranche 6 wired DemoScopeGate into
  production (5 manifest enforcement points) and promoted `demo_scope_gate_smoke` into the
  bundle (marker gained `params=true`), alongside the new `demo_scope_enforcement_smoke` +
  `unlock_trigger_production_smoke`. The tag has no remaining members.
- **legacy-capture** — display-server/PNG/export artifact tools, self-excluded from headless
  regression by design.
- **debug-tool** — developer probes without pass-marker discipline (plus, since Tranche 5,
  arg-driven external tools that cannot self-run under the bundle's bare `--script`
  invocation).
- **superseded-by `<smoke>`** — coverage fully owned by a bundled smoke; kept for history.
- **release-audit-tool** — export-time checklist tools, not per-commit regression.
- **non-headless-harness** — `Node3D` scene fixtures with no `_initialize()`; cannot run as
  `--script` at all.
- **standalone-gate** — `gate1_automated_playtest`: documented to run ON TOP OF the bundle,
  deliberately not a `run_clean` entry (its runtime dwarfs every smoke). Surfaced when the
  checker was scoped to actual `run_clean` invocations (PR #65 review).

The table is generated and drift-checked by `tools/classify_orphan_smokes.sh`
(`--check` fails on any unclassified orphan or stale row; run it whenever bundle
membership changes).

| Orphan smoke | Disposition |
|---|---|
| `_layout_visual_capture` | legacy-capture |
| `achievement_state_smoke` | promotion-candidate |
| `armor_resolver_smoke` | promotion-candidate |
| `assert_hang_test` | debug-tool |
| `bay_dock_launch_smoke` | promotion-candidate |
| `bay_travel_unbay_smoke` | promotion-candidate |
| `boarding_flip_smoke` | promotion-candidate |
| `boot_dock_aligned_smoke` | promotion-candidate |
| `bridge_terminal_login_smoke` | promotion-candidate |
| `bridge_terminal_smoke` | promotion-candidate |
| `canonical_opening_smoke` | promotion-candidate |
| `cargo_hold_smoke` | promotion-candidate |
| `cargo_move_item_smoke` | promotion-candidate |
| `cargo_transfer_smoke` | promotion-candidate |
| `cart_control_smoke` | promotion-candidate |
| `cart_state_smoke` | promotion-candidate |
| `claim_persistence_smoke` | promotion-candidate |
| `class_definitions_smoke` | promotion-candidate |
| `coherent_loader_metadata_smoke` | promotion-candidate |
| `coherent_playable_scene_smoke` | promotion-candidate |
| `coherent_playable_traversal_smoke` | promotion-candidate |
| `coherent_proof_ship_capture` | legacy-capture |
| `coherent_runtime_loader_smoke` | promotion-candidate |
| `coherent_static_fixture_validator` | promotion-candidate |
| `consumable_save_load_smoke` | promotion-candidate |
| `consumable_state_smoke` | promotion-candidate |
| `container_variety_smoke` | promotion-candidate |
| `crafting_debug_smoke` | debug-tool |
| `crafting_recipe_list_smoke` | promotion-candidate |
| `crafting_state_smoke` | promotion-candidate |
| `cross_system_dependency_smoke` | promotion-candidate |
| `cross_training_smoke` | promotion-candidate |
| `debug_apply_summary` | debug-tool |
| `debug_save_load` | debug-tool |
| `derelict_loot_smoke` | promotion-candidate |
| `derelict_objective_controller_smoke` | promotion-candidate |
| `difficulty_profile_smoke` | promotion-candidate |
| `dock_breach_smoke` | promotion-candidate |
| `dock_copresence_smoke` | promotion-candidate |
| `dock_port_types_smoke` | promotion-candidate |
| `dock_ports_smoke` | promotion-candidate |
| `docking_loop_smoke` | promotion-candidate |
| `docking_manager_smoke` | promotion-candidate |
| `docking_persistence_smoke` | promotion-candidate |
| `e2e_combat_loot_craft_smoke` | promotion-candidate |
| `e2e_ship_meta_loop_smoke` | promotion-candidate |
| `e2e_survival_loop_smoke` | promotion-candidate |
| `effect_dispatcher_smoke` | promotion-candidate |
| `encumbrance_smoke` | promotion-candidate |
| `equipment_carts_smoke` | promotion-candidate |
| `equipment_defs_smoke` | promotion-candidate |
| `equipment_state_smoke` | promotion-candidate |
| `export_presets_smoke` | release-audit-tool |
| `field_crafting_state_smoke` | promotion-candidate |
| `food_save_load_smoke` | promotion-candidate |
| `food_state_smoke` | promotion-candidate |
| `gate1_automated_playtest` | standalone-gate |
| `gridmap_meshlibrary_smoke` | debug-tool (T5: requires CLI args, writes `.validation.json` next to each `.tres` in res://) |
| `hangar_bay_smoke` | promotion-candidate |
| `hangar_control_smoke` | promotion-candidate |
| `hangar_persistence_smoke` | promotion-candidate |
| `hangar_port_smoke` | promotion-candidate |
| `hydroponics_crop_list_smoke` | promotion-candidate |
| `hydroponics_state_smoke` | promotion-candidate |
| `inventory_panel_smoke` | promotion-candidate |
| `inventory_selection_model_smoke` | promotion-candidate |
| `inventory_widget_smoke` | promotion-candidate |
| `item_inventory_smoke` | promotion-candidate |
| `junk_items_smoke` | promotion-candidate |
| `life_boat_layout_smoke` | promotion-candidate |
| `life_boat_smoke` | promotion-candidate |
| `life_support_system_smoke` | promotion-candidate |
| `lifeboat_travel_gate_smoke` | promotion-candidate |
| `live_main_prepare_to_upgrade_probe` | debug-tool |
| `localization_catalog_smoke` | promotion-candidate |
| `locked_iso_readability_harness` | non-headless-harness |
| `loot_distribution_smoke` | promotion-candidate |
| `loot_table_biome_smoke` | promotion-candidate |
| `loot_table_smoke` | promotion-candidate |
| `m7_web_breached_encounter_proof` | non-headless-harness |
| `main_coherent_boot_smoke` | promotion-candidate |
| `main_coherent_capture` | legacy-capture |
| `main_playable_combat_encounter_smoke` | promotion-candidate |
| `main_playable_consumables_smoke` | promotion-candidate |
| `main_playable_slice_affordance_smoke` | promotion-candidate |
| `main_playable_slice_capture_sequence` | legacy-capture |
| `main_playable_slice_combat_encounter_smoke` | promotion-candidate |
| `main_playable_slice_crafting_smoke` | promotion-candidate |
| `main_playable_slice_recipe_picker_smoke` | promotion-candidate |
| `main_playable_slice_salvage_picker_smoke` | promotion-candidate |
| `main_playable_slice_hydro_crop_picker_smoke` | promotion-candidate |
| `main_playable_slice_inventory_ui_smoke` | promotion-candidate |
| `main_playable_slice_loot_ecosystem_smoke` | promotion-candidate |
| `main_playable_slice_multislot_save_smoke` | promotion-candidate |
| `main_playable_slice_reload_affordance_smoke` | promotion-candidate |
| `main_playable_slice_suit_oxygen_smoke` | promotion-candidate |
| `main_playable_slice_vitals_hud_smoke` | promotion-candidate |
| `material_state_smoke` | promotion-candidate |
| `medicine_state_smoke` | promotion-candidate |
| `occupancy_flip_smoke` | promotion-candidate |
| `oxygen_equipment_drain_smoke` | promotion-candidate |
| `physical_travel_smoke` | promotion-candidate |
| `pilot_switch_smoke` | promotion-candidate |
| `playable_component_smoke` | promotion-candidate |
| `playable_manager_built_smoke` | promotion-candidate |
| `player_gravity_floor_snap_smoke` | promotion-candidate |
| `player_progression_state_smoke` | promotion-candidate |
| `player_vitals_model_smoke` | promotion-candidate |
| `power_grid_state_smoke` | promotion-candidate |
| `procgen_playable_ship_capture` | legacy-capture |
| `procgen_runtime_demo_capture` | legacy-capture |
| `procgen_ship_gameplay_smoke` | debug-tool (T5: arg-driven external walker — needs --layout/--kit/--gameplay-slice; macOS-era header) |
| `procgen_ship_walkthrough_smoke` | debug-tool (T5: arg-driven external walker — needs --layout/--kit; macOS-era header) |
| `procgen_stress_test` | superseded-by `procgen_layout_stress_smoke` (T5: v4-broken asserts — pins the removed `ShipStructure` root name and a graph-vs-scene child-count comparison `derelict_generator_smoke` documents as wrong — plus a 1,800-generation runtime) |
| `product_audit_smoke` | release-audit-tool |
| `progression_repair_integration_smoke` | promotion-candidate |
| `qt_mini_smoke` | promotion-candidate |
| `quality_tier_smoke` | promotion-candidate |
| `rarity_tier_smoke` | promotion-candidate |
| `recipe_picker_panel_smoke` | promotion-candidate |
| `recipe_resource_smoke` | promotion-candidate |
| `recursive_travel_smoke` | promotion-candidate |
| `release_readiness_ledger_smoke` | release-audit-tool |
| `repair_consume_smoke` | promotion-candidate |
| `repair_loop_smoke` | promotion-candidate |
| `rigid_pair_travel_smoke` | promotion-candidate |
| `salvage_list_smoke` | promotion-candidate |
| `scanner_panel_smoke` | promotion-candidate |
| `scanner_state_smoke` | promotion-candidate |
| `ship_access_smoke` | promotion-candidate |
| `ship_data_export` | legacy-capture |
| `ship_dump` | legacy-capture |
| `ship_instance_dock_fields_smoke` | promotion-candidate |
| `ship_instance_smoke` | promotion-candidate |
| `ship_inventory_smoke` | promotion-candidate |
| `ship_occupancy_smoke` | promotion-candidate |
| `ship_subcomponent_smoke` | promotion-candidate |
| `ship_system_smoke` | promotion-candidate |
| `ship_systems_definitions_smoke` | promotion-candidate |
| `ship_systems_manager_force_repair_smoke` | promotion-candidate |
| `ship_systems_manager_smoke` | promotion-candidate |
| `ship_visualize` | legacy-capture |
| `skill_tree_panel_smoke` | promotion-candidate |
| `spoilage_state_smoke` | promotion-candidate |
| `start_scenario_smoke` | promotion-candidate |
| `station_state_mini_smoke` | promotion-candidate |
| `station_state_smoke` | promotion-candidate |
| `stimulant_state_smoke` | promotion-candidate |
| `sustenance_state_smoke` | promotion-candidate |
| `threat_ai_state_smoke` | promotion-candidate |
| `training_by_item_smoke` | promotion-candidate |
| `travel_controller_smoke` | promotion-candidate |
| `travel_integration_smoke` | promotion-candidate |
| `unique_item_state_smoke` | promotion-candidate |
| `windowed_fps_capture` | legacy-capture |
