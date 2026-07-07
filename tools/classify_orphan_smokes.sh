#!/usr/bin/env bash
# Tranche 3 (2026-07-06): generates the per-file orphan-smoke classification
# consumed by docs/game/06_validation_plan.md ("Orphan smoke classification").
# Re-run after bundle changes to detect drift:
#   bash tools/classify_orphan_smokes.sh --check
# --check exits 1 when an orphan is unclassified or a classified name is no
# longer an orphan (promoted or deleted).
set -euo pipefail
cd "$(dirname "$0")/.."

ls scripts/validation/*.gd | sed 's|.*/||; s|\.gd$||' | sort -u > /tmp/_all_smokes.txt
grep -oE "res://scripts/validation/[a-z0-9_]+\.gd" docs/game/06_validation_plan.md \
  | sed 's|.*/||; s|\.gd$||' | sort -u > /tmp/_bundled.txt
comm -23 /tmp/_all_smokes.txt /tmp/_bundled.txt > /tmp/_orphans.txt

classify() {
  case "$1" in
    # -- cannot run headless (extend Node3D, no _initialize) ------------------
    locked_iso_readability_harness|m7_web_breached_encounter_proof)
      echo "non-headless-harness" ;;
    # -- capture / export / visual artifact tools -----------------------------
    _layout_visual_capture|coherent_proof_ship_capture|main_coherent_capture|\
    main_playable_slice_capture_sequence|procgen_playable_ship_capture|\
    procgen_runtime_demo_capture|windowed_fps_capture|ship_data_export|\
    ship_dump|ship_visualize)
      echo "legacy-capture" ;;
    # -- developer probes without pass-marker discipline -----------------------
    assert_hang_test|crafting_debug_smoke|debug_apply_summary|debug_save_load|\
    live_main_prepare_to_upgrade_probe)
      echo "debug-tool" ;;
    # -- release-process audit tools (run at export time, not per-commit) ------
    export_presets_smoke|product_audit_smoke|release_readiness_ledger_smoke)
      echo "release-audit-tool" ;;
    # -- gated feature: promote with the Tranche 6 DemoScopeGate wiring --------
    demo_scope_gate_smoke)
      echo "deferred-pending-T6" ;;
    # -- procgen / layout pipeline: promote with Tranche 5 (schema 1.2.0,
    #    archetype enforcement, encounter tables all move under it) ------------
    archetype_load_smoke|biome_profile_smoke|cell_layout_engine_smoke|\
    derelict_generator_smoke|encounter_injector_smoke|\
    floor_wrapper_collision_footprint_smoke|gameplay_slice_builder_smoke|\
    gridmap_meshlibrary_smoke|interior_aabb_smoke|kit_catalog_smoke|\
    layout_serializer_smoke|load_from_blueprint_smoke|marker_generator_smoke|\
    procgen_layout_stress_smoke|procgen_loader_playable_contract_smoke|\
    procgen_playable_ship_smoke|procgen_runtime_demo_smoke|\
    procgen_ship_gameplay_smoke|procgen_ship_walkthrough_smoke|\
    procgen_stress_test|procgen_walkability_smoke|readability_prop_factory_smoke|\
    room_assigner_smoke|room_graph_generator_smoke|room_graph_smoke|\
    seed_determinism_smoke|ship_blueprint_smoke|ship_generator_smoke|\
    ship_layout_generator_smoke|ship_layout_integration_smoke|\
    structural_placer_smoke|template_c_traversal_smoke|template_data_smoke|\
    template_selector_smoke|topology_template_smoke|wall_door_resolver_smoke)
      echo "deferred-pending-T5" ;;
    # -- everything else: real unregistered coverage; promotion candidates -----
    *)
      echo "promotion-candidate" ;;
  esac
}

if [ "${1:-}" = "--check" ]; then
  # Every orphan must appear in the doc section; every doc-section name must
  # still be an orphan.
  missing=0
  while read -r name; do
    if ! grep -q "^| \`$name\` |" docs/game/06_validation_plan.md; then
      echo "UNCLASSIFIED ORPHAN: $name"
      missing=1
    fi
  done < /tmp/_orphans.txt
  grep -oE "^\| \`[a-z0-9_]+\` \|" docs/game/06_validation_plan.md \
    | sed 's/^| `//; s/` |$//' | sort -u > /tmp/_classified.txt
  while read -r name; do
    if ! grep -qx "$name" /tmp/_orphans.txt; then
      echo "STALE CLASSIFICATION (no longer an orphan): $name"
      missing=1
    fi
  done < /tmp/_classified.txt
  if [ "$missing" -eq 0 ]; then
    echo "ORPHAN CLASSIFICATION CHECK PASS orphans=$(wc -l < /tmp/_orphans.txt | tr -d ' ')"
  fi
  exit "$missing"
fi

while read -r name; do
  echo "| \`$name\` | $(classify "$name") |"
done < /tmp/_orphans.txt
