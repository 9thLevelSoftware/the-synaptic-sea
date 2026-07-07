#!/usr/bin/env bash
# Tranche 3 (2026-07-06): generates the per-file orphan-smoke classification
# consumed by docs/game/06_validation_plan.md ("Orphan smoke classification").
# Re-run after bundle changes to detect drift:
#   bash tools/classify_orphan_smokes.sh --check
# --check exits 1 when an orphan is unclassified or a classified name is no
# longer an orphan (promoted or deleted).
#
# PR #65 review fixes:
# - "bundled" means invoked by a run_clean line in the regression block, not
#   merely mentioned anywhere in the doc (Codex P2 — gate1_automated_playtest
#   is documented but deliberately outside the bundle, so it must be
#   classified, not silently excluded).
# - temp files via mktemp + trap instead of fixed /tmp names (Gemini).
set -euo pipefail
cd "$(dirname "$0")/.."

all_smokes=$(mktemp)
bundled=$(mktemp)
orphans=$(mktemp)
classified=$(mktemp)
trap 'rm -f "$all_smokes" "$bundled" "$orphans" "$classified"' EXIT

ls scripts/validation/*.gd | sed 's|.*/||; s|\.gd$||' | sort -u > "$all_smokes"
grep -E "^run_clean '" docs/game/06_validation_plan.md \
  | grep -oE "res://scripts/validation/[a-z0-9_]+\.gd" \
  | sed 's|.*/||; s|\.gd$||' | sort -u > "$bundled"
comm -23 "$all_smokes" "$bundled" > "$orphans"

classify() {
  case "$1" in
    # -- documented standalone gate, run ON TOP OF the bundle (see the
    #    "Automated Gate 1 playtest" section) — deliberately not a run_clean
    #    entry because its runtime dwarfs every smoke ---------------------------
    gate1_automated_playtest)
      echo "standalone-gate" ;;
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
    # -- Tranche 6 (2026-07-07): demo_scope_gate_smoke was promoted into the
    #    bundle alongside the DemoScopeGate production wiring — it is no longer
    #    an orphan and needs no case here.
    # -- Tranche 5 (2026-07-07): the deferred-pending-T5 set was resolved --
    #    32 promoted into the bundle (no longer orphans), 4 reclassified below.
    #    procgen_stress_test pins the removed ShipStructure root name plus a
    #    graph-vs-scene child-count comparison derelict_generator_smoke
    #    documents as wrong, and runs 1,800 generations.
    procgen_stress_test)
      echo "superseded-by-procgen_layout_stress_smoke" ;;
    # -- arg-driven external tools: cannot self-run under the bundle's bare
    #    --script invocation (gridmap also writes .validation.json into res://)
    gridmap_meshlibrary_smoke|procgen_ship_gameplay_smoke|procgen_ship_walkthrough_smoke)
      echo "debug-tool" ;;
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
  done < "$orphans"
  grep -oE "^\| \`[a-z0-9_]+\` \|" docs/game/06_validation_plan.md \
    | sed 's/^| `//; s/` |$//' | sort -u > "$classified"
  while read -r name; do
    if ! grep -qx "$name" "$orphans"; then
      echo "STALE CLASSIFICATION (no longer an orphan): $name"
      missing=1
    fi
  done < "$classified"
  if [ "$missing" -eq 0 ]; then
    echo "ORPHAN CLASSIFICATION CHECK PASS orphans=$(wc -l < "$orphans" | tr -d ' ')"
  fi
  exit "$missing"
fi

while read -r name; do
  echo "| \`$name\` | $(classify "$name") |"
done < "$orphans"
