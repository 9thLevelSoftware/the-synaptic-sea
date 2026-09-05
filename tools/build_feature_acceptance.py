#!/usr/bin/env python3
"""Build and validate the feature-completion acceptance registry and card manifest.

P01 records source-backed leaf criteria. A missing acceptance section is an
explicit accounting blocker, not an implicit heading-level criterion. Evidence is
carried across regeneration only when the criterion fingerprint is unchanged.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
REQUIREMENTS_REL = Path("docs/game/05_requirements.md")
FEATURES_REL = Path("docs/game/features")
REGISTRY_REL = Path("docs/game/inventory/feature_acceptance.json")
CARDS_REL = Path("data/validation/feature_completion_cards.json")
PLAN_REL = Path("docs/superpowers/plans/2026-09-04-crafting-derelict-feature-completion.md")

REQUIREMENTS = ROOT / REQUIREMENTS_REL
REGISTRY = ROOT / REGISTRY_REL
CARDS = ROOT / CARDS_REL
PLAN = ROOT / PLAN_REL

EVIDENCE_STATES = {
    "not_verified",
    "blocked",
    "unbuilt",
    "failed",
    "verified_model",
    "verified_scene",
    "verified_player",
    "accepted",
}
DIAGNOSTIC_MARKERS = ["ERROR:", "WARNING:", "SCRIPT ERROR:"]

REVIEWED_EQUIVALENT_PACKAGE_CRITERIA = {
    'The "Audio, music, spatial audio, voice, meta events" package is implemented and smoke-validated.',
    'The "Combat, threat AI, damage, armor, status" package is implemented and smoke-validated.',
    'The "Consumables, medicine, stimulants, ammo, utility" package is implemented and smoke-validated.',
    'The "Crafting, materials, recipes, and stations" package is implemented and smoke-validated.',
    'The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.',
    'The "Distribution, store, achievements, demo, localization, post-launch ops" package is implemented and smoke-validated.',
    'The "Expanded ship systems and sustenance infrastructure" package is implemented and smoke-validated.',
    'The "Food, cooking, spoilage, and sustenance inputs" package is implemented and smoke-validated.',
    'The "Loot ecosystem" package is implemented and smoke-validated.',
    'The "Multi-slot save, autosave, migration, corruption, cloud manifest" package is implemented and smoke-validated.',
    'The "Player progression and meta progression" package is implemented and smoke-validated.',
    'The "Procedural generation expansion" package is implemented and smoke-validated.',
    'The "Survival vitals" package is implemented and smoke-validated.',
    'The "UI, HUD, tutorial, controller, accessibility" package is implemented and smoke-validated.',
}

# A mismatch raises before write_registry can replace the stored registry, so a
# later source edit cannot silently change scope or erase preserved evidence.
FROZEN_SCOPE_CONTRACT: dict[str, str] = {
    "frozen_on": "2026-09-05",
    "source_leaf_set_fingerprint": "8041e481680152f85fe2d3617491880a5268d89dcb63a59608590711edef48d0",
    "reviewer": "root_coordinator",
    "review_disposition": "approved_source_leaves_and_reviewed_equivalence_map",
}
_DEFAULT_FREEZE = object()

FC_OWNERS = {
    "01": "P01", "02": "P00", "03": "P02", "04": "P06", "05": "P03",
    "06": "P05", "07": "P07", "08": "P07", "09": "P08", "10": "P09",
    "11": "P09", "12": "P10", "13": "P11", "14": "P12", "15": "P13",
    "16": "P14", "17": "P15", "18": "P16", "19": "P17", "20": "P18",
    "21": "P20", "22": "P19", "23": "P23", "24": "P24",
}

CARD_DEPENDENCIES = {
    "P00": [],
    "P01": ["P00"],
    "P02": ["P01"],
    "P03": ["P01", "P02"],
    "P04": ["P03"],
    "P05": ["P03", "P04"],
    "P06": ["P01", "P02"],
    "P07": ["P03", "P06"],
    "P08": ["P04", "P07"],
    "P09": ["P05", "P06", "P07", "P08"],
    "P10": ["P03", "P04", "P05", "P06", "P07", "P08", "P09"],
    "P11": ["P01", "P02"],
    "P12": ["P03", "P11"],
    "P13": ["P07", "P12"],
    "P14": ["P05", "P12", "P13"],
    "P15": ["P05", "P12", "P13", "P14"],
    "P16": ["P01", "P02"],
    "P17": ["P12", "P13", "P16"],
    "P18": ["P17"],
    "P19": ["P10", "P14", "P15", "P18"],
    "P20": ["P13", "P14", "P19"],
    "P21": ["P09", "P15", "P20"],
    "P22": ["P10", "P20", "P21"],
    "P23": ["P01", "P02", "G4"],
    "P24": ["G4", "G5"],
}

CARD_REQUIREMENTS = {
    "P00": ["FC-02"], "P01": ["FC-01", "FC-23"],
    "P02": ["FC-01", "FC-02", "FC-03"], "P03": ["FC-05", "FC-12"],
    "P04": ["FC-05", "FC-09"], "P05": ["FC-06"], "P06": ["FC-04"],
    "P07": ["FC-07", "FC-08"], "P08": ["FC-08", "FC-09"],
    "P09": ["FC-10", "FC-11"], "P10": ["FC-12"], "P11": ["FC-13"],
    "P12": ["FC-14"], "P13": ["FC-15"], "P14": ["FC-16"],
    "P15": ["FC-17"], "P16": ["FC-18"], "P17": ["FC-18", "FC-19"],
    "P18": ["FC-20"], "P19": ["FC-22"], "P20": ["FC-21", "FC-22"],
    "P21": ["FC-11", "FC-17", "FC-18", "FC-19", "FC-20", "FC-21"],
    "P22": [f"FC-{number:02d}" for number in range(4, 23)],
    "P23": ["FC-23"], "P24": ["FC-24"],
}

CARD_NON_GOALS = {
    "P00": "Gameplay edits, blanket reimport churn, and installs.",
    "P01": "Increasing scores without evidence or hiding deferred scope.",
    "P02": "Replacing the canonical regression or relaxing diagnostic policy.",
    "P03": "UI, cargo, and rebalancing.",
    "P04": "Changing transfer distance, encumbrance, or cargo-weight policy.",
    "P05": "Random stat rerolls or new item IDs.",
    "P06": "A separate metaprogression system or hundreds of recipes.",
    "P07": "Queue UI or station-power rebalancing.",
    "P08": "Infinite hidden player storage.",
    "P09": "Recipe count as a completion metric.",
    "P10": "Save filename changes or historical-data deletion.",
    "P11": "Timing changes before P12 or synthetic replacement slots.",
    "P12": "Replacing the interaction system.",
    "P13": "Multiplayer authority or unrelated extraction.",
    "P14": "Free repair on install or balance inflation.",
    "P15": "Ordinary repair resurrecting destroyed modules.",
    "P16": "Reconstruction or altered room generation.",
    "P17": "Placement outside the original footprint.",
    "P18": "Visual-only replacement or native-generator replacement.",
    "P19": "Silently discarding unmatched deltas.",
    "P20": "Bypassing safe-return or ownership rules.",
    "P21": "A separate editor UI or final-art overhaul.",
    "P22": "Substituting headless helper calls for player evidence.",
    "P23": "Completion claims for uninspected domains.",
    "P24": "Publishing, purchasing services, or enabling cloud integrations.",
}

COORDINATOR = "scripts/procgen/playable_generated_ship.gd"
COMPONENT_CATALOG = "data/components/component_catalog.json"
WORK_ACTION_CATALOG = "data/work_actions/work_action_catalog.json"
VALIDATION = "scripts/validation/"

CARD_ALLOWLISTS: dict[str, list[str]] = {
    "P00": [
        "docs/game/06_validation_plan.md", "README.md", "AGENTS.md",
        "docs/game/adr/0061-persist-resolved-generation-context.md",
        "docs/game/adr/0063-lifeboat-compiled-biome-contract.md",
        "docs/game/adr/0064-versioned-current-topology-parity-fixture.md",
        "data/procgen/golden/compact_seed17_current/**",
        "scripts/procgen/ceiling_fade_controller.gd",
        "scripts/procgen/ship_blueprint.gd",
        "scripts/procgen/ship_generator.gd",
        "scripts/procgen/life_boat.gd",
        "scripts/procgen/room_assigner.gd",
        "scripts/procgen/playable_generated_ship.gd",
        "scripts/validation/fc_p00_ceiling_lifetime_smoke.gd",
        "scripts/validation/fc_p00_native_arc_smoke.gd",
        "scripts/validation/derelict_arc_smoke.gd",
        "scripts/validation/main_playable_lifeboat_biome_skin_smoke.gd",
        "scripts/validation/item_economy_smoke.gd",
        "scripts/validation/main_playable_item_economy_smoke.gd",
        "scripts/validation/main_playable_survival_stakes_smoke.gd",
        "scripts/validation/audio_spatial_playback_smoke.gd",
        "scripts/validation/vitals_state_save_load_smoke.gd",
        "scripts/validation/room_assigner_smoke.gd",
        "scripts/validation/capture_current_topology_fixture.gd",
        "scripts/validation/procgen_golden_parity_smoke.gd",
        "scripts/validation/procgen_layout_stress_smoke.gd",
        "assets/imported/structural/ship_structural_v0/doorway_frame_open_1x1/doorway_frame_open_1x1_damaged.glb.import",
        "assets/imported/structural/ship_structural_v0/doorway_frame_open_1x1/doorway_frame_open_1x1_breached.glb.import",
        "scenes/wrappers/structural/ship_structural_v0/doorway_frame_open_1x1.tscn",
    ],
    "P01": [
        "docs/game/features/crafting_derelict_feature_completion.md",
        "docs/game/adr/0059-crafting-and-derelict-restoration-transactions.md",
        "docs/game/05_requirements.md", "docs/game/07_risk_register.md",
        "docs/game/inventory/system_inventory.json", str(REGISTRY_REL).replace("\\", "/"),
        "docs/game/integration_debt.md", "STATUS.md", str(CARDS_REL).replace("\\", "/"),
        "tools/build_feature_acceptance.py", "tests/test_feature_acceptance_registry.py",
    ],
    "P02": [
        "tools/run_feature_completion.py", "data/validation/feature_completion_cases.json",
        "tools/build_system_inventory.py", "tools/test_build_system_inventory.py",
        "tests/test_feature_completion_runner.py", "tests/test_feature_acceptance_registry.py",
        "docs/game/06_validation_plan.md",
    ],
    "P03": [
        "scripts/systems/item_lot_ledger.gd", "scripts/systems/inventory_state.gd",
        "scripts/systems/material_state.gd", "scripts/systems/item_defs.gd",
        f"{VALIDATION}production_output_full_consume_smoke.gd",
        f"{VALIDATION}production_output_full_consume_away_smoke.gd",
        f"{VALIDATION}work_yield_scoop_denied_sfx_smoke.gd",
        f"{VALIDATION}work_yield_scoop_denied_away_smoke.gd",
        f"{VALIDATION}work_yield_partial_scoop_smoke.gd",
        f"{VALIDATION}work_yield_partial_scoop_away_smoke.gd",
        f"{VALIDATION}fc_p03_smoke.gd",
    ],
    "P04": [
        *[f"scripts/systems/{name}.gd" for name in ("ship_inventory", "cargo_transfer", "cart_state", "equipment_state", "deconstruction_resolver", "ship_instance", "world_snapshot")],
        *[f"scripts/tools/{name}.gd" for name in ("cargo_hold_control", "cart_control", "work_yield_drop", "loot_container", "crafting_station")],
        *[f"scripts/ui/{name}.gd" for name in ("inventory_panel", "inventory_row", "inventory_drop_zone")],
        COORDINATOR,
        *[f"{VALIDATION}{name}.gd" for name in (
            "fc_p04_smoke", "fc_p04_holder_atomicity_smoke", "fc_p04_floor_drop_persistence_smoke",
            "fc_p04_objective_lots_smoke",
            "equipment_carts_smoke", "main_playable_slice_inventory_ui_smoke",
            "crafting_quality_knowledge_smoke",
        )],
    ],
    "P05": [
        "scripts/systems/item_quality_effects.gd", "data/items/quality_effects.json",
        *[f"scripts/systems/{name}.gd" for name in (
            "quality_tier_resolver", "work_action_resolver", "consumable_state",
            "medicine_state", "stimulant_state", "effect_dispatcher", "component_mount_resolver",
            "ship_modification_state",
        )],
        "scripts/ui/inventory_panel.gd", "scripts/ui/inventory_row.gd", "scripts/ui/recipe_picker_panel.gd",
        "scripts/systems/work_action_driver.gd", COORDINATOR,
        "docs/game/balance/crafting_materials_tuning.md", f"{VALIDATION}fc_p05_smoke.gd",
    ],
    "P06": [
        *[f"scripts/systems/{name}.gd" for name in ("crafting_state", "field_crafting_state", "recipe_knowledge_state")],
        "scripts/tools/crafting_station.gd", "scripts/ui/recipe_picker_panel.gd", COORDINATOR,
        "data/recipes/recipe_definitions.json", "data/items/item_definitions.json",
        "data/items/loot_tables.json",
        f"{VALIDATION}fc_p06_smoke.gd",
    ],
    "P07": [
        *[f"scripts/systems/{name}.gd" for name in ("craft_job_state", "craft_job_scheduler", "crafting_state", "station_state", "ship_runtime")],
        "scripts/tools/crafting_station.gd", COORDINATOR,
        f"{VALIDATION}fc_p07_smoke.gd", f"{VALIDATION}station_tiers_batch_smoke.gd",
        f"{VALIDATION}fc_p06_smoke.gd",
    ],
    "P08": [
        "docs/game/adr/0062-ship-owned-pending-output-receipts.md",
        *[f"scripts/systems/{name}.gd" for name in ("pending_output_store", "craft_job_scheduler", "crafting_state", "station_state", "field_crafting_state", "deconstruction_resolver", "ship_instance", "inventory_state", "ship_inventory", "world_snapshot")],
        "scripts/tools/crafting_station.gd", "scripts/tools/work_yield_drop.gd", COORDINATOR,
        f"{VALIDATION}fc_p08_smoke.gd", f"{VALIDATION}fc_p07_smoke.gd",
    ],
    "P09": [
        "docs/game/adr/0059-crafting-and-derelict-restoration-transactions.md",
        "data/recipes/recipe_definitions.json", "data/materials/material_definitions.json",
        "data/items/item_definitions.json", "data/items/loot_tables.json",
        "data/items/quality_effects.json", COMPONENT_CATALOG,
        "tools/check_crafting_economy.py", "tests/test_crafting_economy.py",
        "scripts/tools/crafting_station.gd", "scripts/ui/recipe_picker_panel.gd", COORDINATOR,
        f"{VALIDATION}fc_p09_smoke.gd",
    ],
    "P10": [
        *[f"scripts/systems/{name}.gd" for name in ("run_snapshot", "world_snapshot", "save_migration_service", "save_load_service", "pillar_persistence", "ship_instance")],
        COORDINATOR, "tests/fixtures/feature_completion/**", f"{VALIDATION}fc_p10_smoke.gd",
    ],
    "P11": [
        *[f"scripts/systems/{name}.gd" for name in ("component_catalog", "component_placement_state", "component_mount_resolver", "ship_modification_state")],
        "scripts/ui/ship_modification_panel.gd", COMPONENT_CATALOG, COORDINATOR,
        "scripts/procgen/wall_door_resolver.gd", "scripts/procgen/layout_serializer.gd",
        "scripts/procgen/ship_generator.gd",
        "data/procgen/golden/coherent_ship_001/layout.json",
        "data/procgen/golden/coherent_ship_002/layout.json",
        *[f"{VALIDATION}{name}.gd" for name in (
            "ship_modification_smoke", "fc_p11_smoke", "fc_p11_live_smoke",
            "ship_modification_panel_smoke", "component_slot_population_smoke",
            "component_system_link_smoke", "component_mount_dismount_smoke",
            "pillar_revisit_persistence_smoke", "ship_mod_power_budget_scene_smoke",
            "ship_mod_power_budget_scene_away_smoke", "ship_mod_run_snapshot_smoke",
            "ship_mod_restore_effects_smoke", "ship_mod_restore_effects_away_smoke",
            "hull_plating_resist_smoke", "fire_plating_resist_smoke",
            "ship_mod_system_effect_smoke", "ship_mod_system_effect_away_smoke",
        )],
    ],
    "P12": [
        *[f"scripts/systems/{name}.gd" for name in ("ship_work_transaction", "work_action_state", "work_action_driver", "work_action_channel", "work_action_resolver", "component_mount_resolver", "component_placement_state")],
        "scripts/tools/repair_point.gd", "scripts/ui/ship_modification_panel.gd",
        "scripts/ui/work_action_hud_panel.gd", WORK_ACTION_CATALOG, COORDINATOR,
        *[f"{VALIDATION}{name}.gd" for name in (
            "fc_p12_smoke", "ship_modification_panel_smoke", "fc_p11_live_smoke",
            "ship_mod_system_effect_smoke", "ship_mod_system_effect_away_smoke",
            "ship_mod_power_budget_scene_smoke", "ship_mod_power_budget_scene_away_smoke",
            "ship_mod_restore_effects_smoke", "ship_mod_restore_effects_away_smoke",
            "component_dismount_interact_smoke", "component_dismount_interact_away_smoke",
            "component_mount_xp_live_smoke", "component_mount_xp_live_away_smoke",
            "component_mount_sfx_live_smoke", "component_mount_sfx_live_away_smoke",
            "component_remount_sfx_live_smoke", "component_remount_sfx_live_away_smoke",
        )],
    ],
    "P13": [
        *[f"scripts/systems/{name}.gd" for name in (
            "ship_work_context", "ship_runtime", "ship_instance", "ship_access_state", "crafting_state")],
        "scripts/ui/ship_modification_panel.gd", COORDINATOR, f"{VALIDATION}fc_p13_smoke.gd",
        *[f"{VALIDATION}{name}.gd" for name in (
            "ship_mod_inventory_sync_away_smoke", "ship_modification_panel_smoke",
            "ship_mod_system_effect_smoke", "ship_mod_system_effect_away_smoke")],
    ],
    "P14": [
        *[f"scripts/systems/{name}.gd" for name in ("ship_modification_state", "component_mount_resolver", "ship_systems_manager", "crafting_state")],
        COMPONENT_CATALOG, "data/ship_systems/power_budget_tables.json", COORDINATOR,
        f"{VALIDATION}fc_p14_smoke.gd",
    ],
    "P15": [
        *[f"scripts/systems/{name}.gd" for name in ("module_integrity_state", "module_integrity_map", "work_action_resolver", "ship_subcomponent")],
        "scripts/tools/repair_point.gd", WORK_ACTION_CATALOG, COORDINATOR, f"{VALIDATION}fc_p15_smoke.gd",
    ],
    "P16": [
        "scripts/systems/structural_rebuild_state.gd", "scripts/systems/module_integrity_map.gd",
        "scripts/systems/module_integrity_state.gd", "scripts/procgen/generated_ship_loader.gd",
        COORDINATOR, f"{VALIDATION}fc_p16_smoke.gd",
    ],
    "P17": [
        "scripts/systems/structural_rebuild_state.gd", "scripts/systems/ship_work_transaction.gd",
        "scripts/systems/work_action_catalog.gd", "scripts/systems/work_action_resolver.gd",
        "data/construction/structural_rebuild_catalog.json", "tools/check_structural_rebuild_catalog.py",
        "tests/test_structural_rebuild_catalog.py", WORK_ACTION_CATALOG, f"{VALIDATION}fc_p17_smoke.gd",
    ],
    "P18": [
        "scripts/procgen/structural_rebuild_applier.gd", "scripts/procgen/generated_ship_loader.gd",
        "scripts/procgen/slice_atmosphere_applier.gd", "scripts/systems/module_integrity_consequences.gd",
        "scripts/systems/ship_nav_graph.gd", "scripts/systems/structural_rebuild_state.gd",
        COORDINATOR, f"{VALIDATION}fc_p18_smoke.gd",
    ],
    "P19": [
        *[f"scripts/systems/{name}.gd" for name in ("pillar_persistence", "ship_instance", "ship_runtime", "run_snapshot", "world_snapshot", "save_migration_service")],
        COORDINATOR, "tests/fixtures/feature_completion/**", f"{VALIDATION}fc_p19_smoke.gd",
    ],
    "P20": [
        *[f"scripts/systems/{name}.gd" for name in ("ship_restoration_readiness", "ship_access_state", "travel_controller", "docking_manager", "ship_instance")],
        "scripts/tools/bridge_terminal.gd", COORDINATOR, f"{VALIDATION}fc_p20_smoke.gd",
    ],
    "P21": [
        "scripts/ui/ship_restoration_panel.gd", "scripts/ui/ship_modification_panel.gd",
        "scripts/ui/work_action_hud_panel.gd", "scripts/ui/recipe_picker_panel.gd", COORDINATOR,
        "data/ui/tutorial_triggers.json", "data/ui/input_glyphs.json",
        "data/release/localization_catalog.json", f"{VALIDATION}fc_p21_smoke.gd",
    ],
    "P22": [
        f"{VALIDATION}fc_p22_smoke.gd",
        "docs/game/playtests/feature-completion-restoration-protocol.md",
        "data/validation/feature_completion_cases.json", str(REGISTRY_REL).replace("\\", "/"),
        "tests/fixtures/feature_completion/**",
    ],
    "P23": [
        str(REGISTRY_REL).replace("\\", "/"), "docs/game/05_requirements.md",
        *[f"docs/game/build-plans/{number:02d}-{name}-e2e.md" for number, name in enumerate((
            "survival-vitals", "food-cooking-spoilage", "crafting-materials-recipes",
            "loot-ecosystem", "consumables-medicine-stimulants", "combat-threat-ai",
            "ship-systems-sustenance", "progression-skills-meta", "ui-ux-accessibility",
            "audio-music-spatial", "save-load-persistence", "procedural-generation-expansion",
            "distribution-store-postlaunch", "cross-system-integration-review",
            "systems-map-task-graph-update",
        ), 1)],
        str(CARDS_REL).replace("\\", "/"),
    ],
    "P24": [
        "export_presets.cfg", "tools/check_export_pipeline.py", "scripts/export/build_release.sh",
        f"{VALIDATION}export_presets_smoke.gd", f"{VALIDATION}release_readiness_ledger_smoke.gd",
        "data/validation/feature_completion_cases.json", "docs/game/export_regression_report.md",
        "docs/game/release_notes_template.md", str(REGISTRY_REL).replace("\\", "/"),
        "docs/game/performance_baseline.md", f"{VALIDATION}performance_profiler.gd",
        f"{VALIDATION}windowed_fps_capture.gd",
    ],
}

CARD_SMOKES = {
    "P00": ["fc_p00_ceiling_lifetime_smoke.gd", "fc_p00_native_arc_smoke.gd", "derelict_arc_smoke.gd", "crafting_state_smoke.gd", "module_integrity_consequences_smoke.gd", "repair_loop_smoke.gd", "main_playable_slice_station_craft_smoke.gd", "pilot_switch_smoke.gd", "main_playable_survival_stakes_smoke.gd", "audio_spatial_playback_smoke.gd", "vitals_state_save_load_smoke.gd", "room_assigner_smoke.gd", "procgen_golden_parity_smoke.gd"],
    "P03": [
        "inventory_state_smoke.gd", "material_state_smoke.gd",
        "production_output_full_consume_smoke.gd", "production_output_full_consume_away_smoke.gd",
        "work_yield_scoop_denied_sfx_smoke.gd", "work_yield_scoop_denied_away_smoke.gd",
        "work_yield_partial_scoop_smoke.gd", "work_yield_partial_scoop_away_smoke.gd",
    ],
    "P04": [
        "fc_p04_holder_atomicity_smoke.gd", "fc_p04_floor_drop_persistence_smoke.gd",
        "fc_p04_objective_lots_smoke.gd",
        "cargo_transfer_smoke.gd", "equipment_carts_smoke.gd", "main_playable_slice_inventory_ui_smoke.gd",
        "crafting_quality_knowledge_smoke.gd",
    ],
    "P05": ["quality_tier_smoke.gd", "crafting_quality_knowledge_smoke.gd"],
    "P06": ["crafting_recipe_list_smoke.gd", "main_playable_slice_recipe_picker_smoke.gd"],
    "P07": ["crafting_state_smoke.gd", "station_state_smoke.gd", "fc_p06_smoke.gd"],
    "P08": ["main_playable_slice_station_craft_smoke.gd", "main_playable_slice_salvage_picker_smoke.gd"],
    "P09": ["recipe_resource_smoke.gd", "recipe_picker_panel_smoke.gd"],
    "P10": ["save_migration_service_smoke.gd", "save_migration_world_smoke.gd", "save_load_service_smoke.gd"],
    "P11": ["component_slot_population_smoke.gd", "component_system_link_smoke.gd", "ship_modification_panel_smoke.gd", "ship_modification_smoke.gd"],
    "P12": ["repair_unification_smoke.gd", "repair_blocked_consume_smoke.gd", "work_action_driver_smoke.gd", "component_mount_dismount_smoke.gd"],
    "P13": ["component_mount_interact_away_smoke.gd", "ship_mod_inventory_sync_away_smoke.gd", "pillar_revisit_persistence_smoke.gd"],
    "P14": ["ship_mod_overbudget_power_smoke.gd", "ship_mod_station_tier_away_smoke.gd", "ship_mod_restore_effects_smoke.gd"],
    "P15": ["repair_loop_smoke.gd", "module_integrity_consequences_smoke.gd", "ship_mod_plating_repair_away_smoke.gd"],
    "P16": ["module_integrity_smoke.gd", "nav_solid_edges_smoke.gd"],
    "P18": ["module_integrity_consequences_smoke.gd", "ship_nav_graph_smoke.gd", "slice_atmosphere_smoke.gd", "physical_travel_smoke.gd"],
    "P19": ["pillar_persistence_smoke.gd", "pillar_revisit_persistence_smoke.gd", "world_persist_restore_smoke.gd", "docking_persistence_smoke.gd"],
    "P20": ["pilot_switch_smoke.gd", "repair_loop_smoke.gd", "docking_loop_smoke.gd", "worldgen_wired_travel_smoke.gd"],
}


def _normalized(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip())


def _clean_markdown(text: str) -> str:
    return _normalized(text).strip(" |")


def _default_evidence() -> dict[str, Any]:
    return {
        "implemented": False,
        "production_reachable": False,
        "fresh_validation": False,
        "player_accepted": False,
        "state": "not_verified",
        "refs": [],
    }


def _is_deferred(status: str) -> bool:
    lowered = status.lower()
    return "deferred" in lowered or "expected-unbuilt" in lowered


def _acceptance_kind(criterion: str, default: str) -> str:
    match = re.match(
        r"^\*\*(Workflow|Gameplay|Constraint|Deferred(?: scope)?):\*\*",
        criterion,
        re.IGNORECASE,
    )
    if not match:
        return default
    label = match.group(1).lower()
    return "deferred" if label.startswith("deferred") else label


def _domain(identifier: str) -> str:
    parts = identifier.split("-")
    return parts[1].lower() if len(parts) > 2 else "core"


def _digest(*parts: str) -> str:
    payload = "\x1f".join(_normalized(part) for part in parts)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _criterion(
    *,
    identifier: str,
    criterion: str,
    source_path: str,
    heading: str,
    line: int,
    domain: str,
    feature: str,
    owner: str,
    status: str,
    acceptance_kind: str = "requirement",
    requirement_id: str | None = None,
    verification: Iterable[str] = (),
) -> dict[str, Any]:
    text = _clean_markdown(criterion)
    fingerprint = _digest(source_path, heading, text)
    kind = _acceptance_kind(text, acceptance_kind)
    return {
        "id": identifier,
        **({"requirement_id": requirement_id} if requirement_id else {}),
        "criterion": text,
        "criterion_fingerprint": fingerprint,
        "source": {"path": source_path, "heading": heading, "line": line},
        "verification_source": [_clean_markdown(item) for item in verification],
        "domain": domain,
        "feature": feature,
        "owner_card": owner,
        "declared_status": status,
        "acceptance_kind": kind,
        "deferred": kind == "deferred" or _is_deferred(status),
        "evidence": _default_evidence(),
    }


def _list_item(line: str) -> tuple[int, str] | None:
    match = re.match(r"^(\s*)(?:[-*]|\d+[.)])\s+(.+?)\s*$", line)
    if not match:
        return None
    return len(match.group(1).expandtabs(4)), match.group(2)


def _leaf_list_items(lines: list[str], start: int, end: int, minimum_indent: int) -> list[tuple[int, str]]:
    bullets: list[tuple[int, int, str]] = []
    for index in range(start, end):
        item = _list_item(lines[index])
        if item is not None and item[0] > minimum_indent:
            bullets.append((index, item[0], item[1]))
    result: list[tuple[int, str]] = []
    for position, (index, indent, text) in enumerate(bullets):
        has_child = position + 1 < len(bullets) and bullets[position + 1][1] > indent
        if not has_child and text:
            next_index = bullets[position + 1][0] if position + 1 < len(bullets) else end
            continuation: list[str] = []
            for line in lines[index + 1:next_index]:
                if not line.strip() or re.match(r"^\s*(?:```|#|\|)", line):
                    continue
                leading = len(line) - len(line.lstrip())
                if leading > indent:
                    continuation.append(line.strip())
            result.append((index, _normalized(" ".join([text, *continuation]))))
    return result


def _verification_lines(block: list[str]) -> list[str]:
    offset = next((index for index, line in enumerate(block) if line.startswith("- Verification:")), None)
    if offset is None:
        return []
    end = next(
        (index for index in range(offset + 1, len(block)) if re.match(r"^- [A-Z][^:]*:", block[index])),
        len(block),
    )
    return [text for _, text in _leaf_list_items(block, offset + 1, end, -1)]


def _extract_requirements(root: Path) -> tuple[list[dict[str, Any]], dict[str, Any], list[dict[str, Any]], list[str]]:
    path = root / REQUIREMENTS_REL
    lines = path.read_text(encoding="utf-8").splitlines()
    starts = []
    for index, line in enumerate(lines):
        match = re.match(r"^## (REQ-[A-Z0-9-]+):\s*(.+)$", line)
        if match:
            starts.append((index, match.group(1), match.group(2)))
    criteria: list[dict[str, Any]] = []
    coverage: list[dict[str, Any]] = []
    blockers: list[str] = []
    unassessed: list[dict[str, Any]] = []
    source_path = REQUIREMENTS_REL.as_posix()
    for position, (start, requirement_id, title) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        block = lines[start:end]
        status = next((line.removeprefix("- Status:").strip() for line in block if line.startswith("- Status:")), "Unspecified")
        declared_source = next((line.removeprefix("- Source:").strip() for line in block if line.startswith("- Source:")), "Unspecified")
        acceptance = next((index for index, line in enumerate(block) if re.match(r"^- Acceptance criteria(?:\s|\(|:)", line)), None)
        if acceptance is None:
            anchor = f"{source_path}#{requirement_id}"
            blockers.append(anchor)
            unassessed.append({"heading": requirement_id, "line": start + 1, "reason": "missing_acceptance_section"})
            continue
        acceptance_end = next(
            (
                index
                for index in range(acceptance + 1, len(block))
                if _list_item(block[index]) is not None and _list_item(block[index])[0] == 0
            ),
            len(block),
        )
        leaves = _leaf_list_items(block, acceptance + 1, acceptance_end, -1)
        if not leaves:
            anchor = f"{source_path}#{requirement_id}"
            blockers.append(anchor)
            unassessed.append({"heading": requirement_id, "line": start + acceptance + 1, "reason": "empty_acceptance_section"})
            continue
        verification = _verification_lines(block)
        occurrences: defaultdict[str, int] = defaultdict(int)
        for local_index, text in leaves:
            content_hash = _digest(requirement_id, text)[:12]
            occurrences[content_hash] += 1
            suffix = f"-{occurrences[content_hash]}" if occurrences[content_hash] > 1 else ""
            criterion_id = f"{requirement_id}::acceptance-{content_hash}{suffix}"
            entry = _criterion(
                identifier=criterion_id,
                requirement_id=requirement_id,
                criterion=text,
                source_path=source_path,
                heading=requirement_id,
                line=start + local_index + 1,
                domain=_domain(requirement_id),
                feature=declared_source,
                owner="P23",
                status=status,
                verification=verification,
            )
            criteria.append(entry)
            coverage.append({"anchor": f"{source_path}:{entry['source']['line']}", "criterion_ids": [criterion_id]})
    assessment = "acceptance_extracted" if not unassessed else "unassessed_requirement_headings"
    source = {
        "path": source_path,
        "kind": "requirement_register",
        "assessment": assessment,
        "requirement_heading_count": len(starts),
        "acceptance_leaf_count": len(criteria),
        "unassessed_headings": unassessed,
    }
    return criteria, source, coverage, blockers


def _document_status(lines: list[str]) -> str:
    for line in lines[:30]:
        match = re.match(r"^(?:-\s+)?(?:\*\*)?Status:(?:\*\*)?\s*(.+)$", line)
        if match:
            return re.sub(r"\*", "", match.group(1)).strip()
    for index, line in enumerate(lines):
        if re.match(r"^#{1,6}\s+Status\s*$", line, re.IGNORECASE):
            for value in lines[index + 1:]:
                if value.strip():
                    return re.sub(r"^[*-]\s+|\*", "", value).strip()
    return "unassessed feature-spec leaf"


def _acceptance_sections(lines: list[str]) -> list[tuple[int, int, str]]:
    headings: list[tuple[int, int, str]] = []
    for index, line in enumerate(lines):
        match = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if match:
            headings.append((index, len(match.group(1)), match.group(2)))
    sections: list[tuple[int, int, str]] = []
    for position, (start, level, title) in enumerate(headings):
        normalized = re.sub(r"[^a-z]+", " ", title.lower()).strip()
        if (
            "acceptance" not in normalized
            or normalized.startswith("non acceptance")
            or "without acceptance" in normalized
            or "no acceptance" in normalized
        ):
            continue
        end = len(lines)
        for next_start, next_level, _ in headings[position + 1:]:
            if next_level <= level:
                end = next_start
                break
        sections.append((start + 1, end, title))
    return sections


def _extract_feature_sources(root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    criteria: list[dict[str, Any]] = []
    sources: list[dict[str, Any]] = []
    coverage: list[dict[str, Any]] = []
    blockers: list[str] = []
    for path in sorted((root / FEATURES_REL).glob("*.md")):
        relative = path.relative_to(root).as_posix()
        lines = path.read_text(encoding="utf-8").splitlines()
        if path.name == "feature_spec_template.md":
            sources.append({"path": relative, "kind": "template", "assessment": "excluded_template", "acceptance_leaf_count": 0})
            continue
        sections = _acceptance_sections(lines)
        inline = [index for index, line in enumerate(lines) if re.match(r"^\s*- Acceptance criteria:\s*$", line)]
        raw_leaves: list[tuple[int, str, str, str | None]] = []
        for start, end, heading in sections:
            for index in range(start, end):
                table = re.match(r"^\|\s*(FC-\d{2})\s*\|\s*(.+?)\s*\|", lines[index])
                if table and table.group(1) != "FC-ID":
                    raw_leaves.append((index, table.group(2), heading, table.group(1)))
            raw_leaves.extend((index, text, heading, None) for index, text in _leaf_list_items(lines, start, end, -1))
        for acceptance in inline:
            base_item = _list_item(lines[acceptance])
            assert base_item is not None
            base_indent = base_item[0]
            end = next(
                (index for index in range(acceptance + 1, len(lines))
                 if _list_item(lines[index]) is not None and _list_item(lines[index])[0] <= base_indent),
                len(lines),
            )
            raw_leaves.extend(
                (index, text, "Acceptance criteria", None)
                for index, text in _leaf_list_items(lines, acceptance + 1, end, base_indent)
            )
        unique_by_anchor: dict[int, tuple[int, str, str, str | None]] = {}
        for leaf in raw_leaves:
            unique_by_anchor.setdefault(leaf[0], leaf)
        raw_leaves = [unique_by_anchor[index] for index in sorted(unique_by_anchor)]
        mapped_ids: list[str] = []
        for start, end, _ in sections:
            body = " ".join(lines[start:end])
            mapping = re.search(r"Mapped 1:1 to (REQ-[A-Z0-9]+-)(\d+)\.\.(\d+)", body)
            if mapping:
                width = max(len(mapping.group(2)), len(mapping.group(3)))
                mapped_ids.extend(
                    f"{mapping.group(1)}{number:0{width}d}"
                    for number in range(int(mapping.group(2)), int(mapping.group(3)) + 1)
                )
            for line in lines[start:end]:
                if "Mapped to existing requirement rows:" in line:
                    mapped_ids.extend(re.findall(r"REQ-[A-Z0-9-]+", line))
        mapped_ids = list(dict.fromkeys(mapped_ids))
        if not sections and not inline:
            assessment = "unassessed_no_acceptance_section"
            blockers.append(relative)
        elif not raw_leaves and mapped_ids:
            assessment = "acceptance_mapped_to_requirements"
        elif not raw_leaves:
            assessment = "unassessed_empty_acceptance_section"
            blockers.append(relative)
        else:
            assessment = "acceptance_extracted"
        sources.append({
            "path": relative,
            "kind": "feature_spec",
            "assessment": assessment,
            "acceptance_leaf_count": len(raw_leaves),
            **({"mapped_requirement_ids": mapped_ids} if mapped_ids else {}),
        })
        status = _document_status(lines)
        occurrences: defaultdict[str, int] = defaultdict(int)
        for index, text, heading, fixed_id in raw_leaves:
            if fixed_id:
                criterion_id = fixed_id
                owner = FC_OWNERS[fixed_id.split("-")[1]]
                domain = "crafting_derelict"
            else:
                content_hash = _digest(relative, heading, text)[:12]
                occurrences[content_hash] += 1
                suffix = f"-{occurrences[content_hash]}" if occurrences[content_hash] > 1 else ""
                criterion_id = f"FEATURE::{relative}::{content_hash}{suffix}"
                owner = "P23"
                domain = "feature_spec"
            entry = _criterion(
                identifier=criterion_id,
                criterion=text,
                source_path=relative,
                heading=heading,
                line=index + 1,
                domain=domain,
                feature=path.stem,
                owner=owner,
                status=status,
                acceptance_kind="program_outcome" if fixed_id else "feature",
            )
            criteria.append(entry)
            coverage.append({"anchor": f"{relative}:{index + 1}", "criterion_ids": [criterion_id]})
    return criteria, sources, coverage, blockers


def _valid_evidence(evidence: Any) -> bool:
    if not isinstance(evidence, dict):
        return False
    required_bools = ("implemented", "production_reachable", "fresh_validation", "player_accepted")
    return (
        all(isinstance(evidence.get(name), bool) for name in required_bools)
        and evidence.get("state") in EVIDENCE_STATES
        and isinstance(evidence.get("refs"), list)
        and (evidence.get("state") == "not_verified" or bool(evidence.get("refs")))
    )


def _apply_reviewed_equivalence(criteria: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: defaultdict[str, list[str]] = defaultdict(list)
    display: dict[str, str] = {}
    for entry in criteria:
        key = _normalized(entry["criterion"]).casefold()
        groups[key].append(entry["id"])
        display.setdefault(key, entry["criterion"])
    review: list[dict[str, Any]] = []
    by_id = {entry["id"]: entry for entry in criteria}
    for key, identifiers in sorted(groups.items()):
        ordered = sorted(identifiers, key=lambda identifier: (by_id[identifier]["deferred"], identifier))
        is_duplicate = len(ordered) > 1
        approved_equivalent = is_duplicate and display[key] in REVIEWED_EQUIVALENT_PACKAGE_CRITERIA
        if approved_equivalent:
            assert all(identifier.startswith("REQ-") for identifier in ordered), "package equivalence must contain requirement rows only"
            assert len({by_id[identifier]["feature"] for identifier in ordered}) == 1, "package equivalence crossed source packages"
        representative = ordered[0]
        for identifier in ordered:
            by_id[identifier]["metric_equivalence"] = {
                "group_id": (
                    f"reviewed-package-{_digest(key)[:12]}"
                    if approved_equivalent
                    else f"distinct-{_digest(identifier)[:12]}"
                ),
                "representative_id": representative if approved_equivalent else identifier,
                "counts_toward_proposed_denominator": not approved_equivalent or identifier == representative,
            }
        if is_duplicate:
            item = {
                "criterion": display[key],
                "criterion_ids": ordered,
                "disposition": (
                    "reviewed_equivalent_same_package_boilerplate"
                    if approved_equivalent
                    else "reviewed_same_text_distinct_scope"
                ),
                "review": {
                    "reviewer": "root_coordinator",
                    "reviewed_on": "2026-09-04",
                    "basis": (
                        "Identical package-level boilerplate within the same authored feature package."
                        if approved_equivalent
                        else "Identical wording refers to different feature, claim, or tool context."
                    ),
                },
            }
            if approved_equivalent:
                item["representative_id"] = representative
                item["alias_ids"] = [identifier for identifier in ordered if identifier != representative]
            else:
                item["representative_ids"] = ordered
                item["alias_ids"] = []
            review.append(item)
    return review


def _scope_contract_fingerprint(
    criteria: list[dict[str, Any]],
    source_documents: list[dict[str, Any]],
) -> str:
    contract = {
        "criteria": [
            {
                "id": entry["id"],
                "fingerprint": entry["criterion_fingerprint"],
                "deferred": entry["deferred"],
                "kind": entry["acceptance_kind"],
                "metric_equivalence": entry["metric_equivalence"],
            }
            for entry in sorted(criteria, key=lambda item: item["id"])
        ],
        "sources": [
            {
                "path": source["path"],
                "assessment": source["assessment"],
                "mapped_requirement_ids": source.get("mapped_requirement_ids", []),
                "acceptance_leaf_count": source.get("acceptance_leaf_count", 0),
            }
            for source in sorted(source_documents, key=lambda item: item["path"])
        ],
    }
    payload = json.dumps(contract, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def build(
    root: Path = ROOT,
    *,
    frozen_scope_contract: dict[str, str] | None | object = _DEFAULT_FREEZE,
) -> dict[str, Any]:
    root = Path(root)
    if frozen_scope_contract is _DEFAULT_FREEZE:
        frozen_scope_contract = FROZEN_SCOPE_CONTRACT if root.resolve() == ROOT.resolve() else None
    requirements, requirement_source, requirement_coverage, requirement_blockers = _extract_requirements(root)
    features, feature_sources, feature_coverage, feature_blockers = _extract_feature_sources(root)
    known_requirement_ids = {entry["requirement_id"] for entry in requirements}
    for source in feature_sources:
        mapped = source.get("mapped_requirement_ids", [])
        missing = [identifier for identifier in mapped if identifier not in known_requirement_ids]
        if missing:
            source["assessment"] = "unassessed_invalid_requirement_mapping"
            source["missing_requirement_ids"] = missing
            feature_blockers.append(source["path"])
    criteria = features + requirements
    ids = [entry["id"] for entry in criteria]
    if len(ids) != len(set(ids)):
        duplicates = sorted(identifier for identifier in set(ids) if ids.count(identifier) > 1)
        raise AssertionError(f"duplicate criterion IDs: {duplicates}")

    registry_path = root / REGISTRY_REL
    try:
        prior = json.loads(registry_path.read_text(encoding="utf-8")) if registry_path.exists() else {"criteria": []}
    except json.JSONDecodeError as error:
        raise AssertionError(f"invalid prior registry JSON: {error}") from error
    old = {entry.get("id"): entry for entry in prior.get("criteria", []) if isinstance(entry, dict)}
    for entry in criteria:
        previous = old.get(entry["id"])
        if (
            previous
            and previous.get("criterion_fingerprint") == entry["criterion_fingerprint"]
            and _valid_evidence(previous.get("evidence"))
        ):
            entry["evidence"] = previous["evidence"]

    blockers = sorted(set(requirement_blockers + feature_blockers))
    duplicate_review = _apply_reviewed_equivalence(criteria)
    source_documents = [requirement_source, *feature_sources]
    scope_fingerprint = _scope_contract_fingerprint(criteria, source_documents)
    if frozen_scope_contract is not None:
        assert isinstance(frozen_scope_contract, dict), "invalid frozen scope contract"
        assert not blockers, "cannot freeze scope with source mapping blockers"
        assert frozen_scope_contract.get("source_leaf_set_fingerprint") == scope_fingerprint, (
            "frozen scope drift; coordinator review is required before regeneration"
        )
    active = [entry for entry in criteria if not entry["deferred"]]
    proposed_metric_criteria = [
        entry
        for entry in active
        if entry["metric_equivalence"]["counts_toward_proposed_denominator"]
    ]
    evidence_counts = {
        "implemented": sum(entry["evidence"]["implemented"] for entry in proposed_metric_criteria),
        "production_reachable": sum(entry["evidence"]["production_reachable"] for entry in proposed_metric_criteria),
        "freshly_validated": sum(entry["evidence"]["fresh_validation"] for entry in proposed_metric_criteria),
        "player_accepted": sum(entry["evidence"]["player_accepted"] for entry in proposed_metric_criteria),
        "accepted": sum(entry["evidence"]["state"] == "accepted" for entry in proposed_metric_criteria),
    }
    scope_frozen = dict(frozen_scope_contract) if frozen_scope_contract is not None else None
    percentages = (
        {
            "implemented": round(evidence_counts["implemented"] * 100 / len(proposed_metric_criteria), 2) if proposed_metric_criteria else None,
            "validated": round(evidence_counts["freshly_validated"] * 100 / len(proposed_metric_criteria), 2) if proposed_metric_criteria else None,
            "accepted": round(evidence_counts["accepted"] * 100 / len(proposed_metric_criteria), 2) if proposed_metric_criteria else None,
        }
        if scope_frozen is not None
        else {"implemented": None, "validated": None, "accepted": None}
    )
    return {
        "schema_version": "feature-acceptance-v5",
        "program": "crafting-derelict-feature-completion",
        "scope_frozen": scope_frozen,
        "scope_freeze_candidate": {
            "status": (
                "blocked_source_mapping"
                if blockers
                else "matches_frozen_contract"
                if scope_frozen is not None
                else "ready_for_final_review"
            ),
            "source_leaf_set_fingerprint": scope_fingerprint,
            "source_row_count": len(criteria),
            "active_row_count": len(active),
            "deferred_row_count": len(criteria) - len(active),
            "proposed_active_denominator": len(proposed_metric_criteria),
        },
        "scope_review": {
            "status": (
                "incomplete_source_mapping"
                if blockers
                else "ready_for_final_scope_review"
                if scope_frozen is None
                else "frozen"
            ),
            "source_mapping_blockers": len(blockers),
            "source_leaf_review": {
                "reviewer": "root_coordinator",
                "reviewed_on": "2026-09-04",
                "disposition": "approved_after_wording_corrections",
            },
            "reviewed_equivalence_groups": sum(
                group["disposition"] == "reviewed_equivalent_same_package_boilerplate"
                for group in duplicate_review
            ),
            "reviewed_distinct_same_text_groups": sum(
                group["disposition"] == "reviewed_same_text_distinct_scope"
                for group in duplicate_review
            ),
            "required_decisions": [
                "Confirm the scope-freeze candidate fingerprint and freeze date."
            ] if scope_frozen is None else [],
        },
        "board": "synaptic-sea-stage-gate",
        "card_manifest": CARDS_REL.as_posix(),
        "accounting": {
            "denominator_status": (
                "incomplete_unassessed_sources"
                if blockers
                else "frozen"
                if scope_frozen is not None
                else "ready_for_scope_freeze"
            ),
            "recorded": len(criteria),
            "active": len(active),
            "deferred": len(criteria) - len(active),
            "active_metric_denominator": len(proposed_metric_criteria),
            "equivalence_alias_count": len(active) - len(proposed_metric_criteria),
            **evidence_counts,
            "unassessed_source_count": len(blockers),
            "metric_blockers": blockers,
            "percentages": percentages,
            "definition": (
                "Percentages use the frozen active metric denominator after reviewed exact-text equivalence; historical status is provenance, not execution evidence."
                if scope_frozen is not None
                else "Percentages remain null until coordinator review freezes the source leaves and exact-text equivalence map; historical status is provenance, not execution evidence."
            ),
        },
        "migration_contract": {
            "reserved_run_version": "gate2-current-run-5",
            "reserved_world_version": "world-5",
            "implemented": False,
            "payloads": [
                "item_lots_v1", "craft_jobs_v1", "pending_outputs_v1",
                "recipe_knowledge_v1", "work_transactions_v1", "structural_rebuild_v1",
            ],
        },
        "source_documents": source_documents,
        "source_leaf_coverage": sorted(requirement_coverage + feature_coverage, key=lambda item: item["anchor"]),
        "duplicate_criterion_review": duplicate_review,
        "criteria": criteria,
    }


def write_registry(
    root: Path = ROOT,
    *,
    frozen_scope_contract: dict[str, str] | None | object = _DEFAULT_FREEZE,
) -> dict[str, Any]:
    registry = build(root, frozen_scope_contract=frozen_scope_contract)
    path = Path(root) / REGISTRY_REL
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(registry, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return registry


def _plan_anchors(root: Path) -> dict[str, int]:
    lines = (root / PLAN_REL).read_text(encoding="utf-8").splitlines()
    anchors: dict[str, int] = {}
    for line_number, line in enumerate(lines, 1):
        match = re.match(r"^### (P\d{2})\s+", line)
        if match:
            anchors[match.group(1)] = line_number
    return anchors


def _expanded_task_refs(text: str) -> list[str]:
    references: list[str] = []
    for match in re.finditer(r"\b([PG])(\d{1,2})(?:\s*-\s*(?:\1)?(\d{1,2}))?\b", text):
        prefix, start_text, end_text = match.groups()
        start = int(start_text)
        end = int(end_text) if end_text is not None else start
        width = 2 if prefix == "P" else 1
        references.extend(f"{prefix}{number:0{width}d}" for number in range(start, end + 1))
    return list(dict.fromkeys(references))


def _expanded_requirement_refs(text: str) -> list[str]:
    references: list[str] = []
    for match in re.finditer(r"\bFC-(\d{2})(?:(?:\.\.|-)(?:FC-)?(\d{2}))?\b", text):
        start = int(match.group(1))
        end = int(match.group(2)) if match.group(2) else start
        references.extend(f"FC-{number:02d}" for number in range(start, end + 1))
    return list(dict.fromkeys(references))


def _plan_card_contracts(root: Path) -> dict[str, dict[str, list[str]]]:
    lines = (root / PLAN_REL).read_text(encoding="utf-8").splitlines()
    starts = [(index, match.group(1)) for index, line in enumerate(lines)
              if (match := re.match(r"^### (P\d{2})\s+", line))]
    contracts: dict[str, dict[str, list[str]]] = {}
    for position, (start, card_id) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        block = " ".join(lines[start:end])
        depends = re.search(r"\*\*Depends:\*\*\s*(.*?)\s*\*\*Requirements:\*\*", block)
        requirements = re.search(r"\*\*Requirements:\*\*\s*(.*?)(?:\.\s|\*\*)", block)
        if not depends or not requirements:
            raise AssertionError(f"tracked plan contract is malformed: {card_id}")
        contracts[card_id] = {
            "depends_on": _expanded_task_refs(depends.group(1)),
            "requirements": _expanded_requirement_refs(requirements.group(1)),
        }
    return contracts


def _source_exists(root: Path, path: str) -> bool:
    if path.endswith("/**"):
        directory = root / path[:-3]
        return directory.is_dir() and any(item.is_file() for item in directory.rglob("*"))
    return (root / path).exists()


def _smoke_marker(root: Path, filename: str) -> str:
    path = root / VALIDATION / filename
    if path.is_file():
        source = path.read_text(encoding="utf-8", errors="replace")
        quoted = re.findall(r"[\"']([^\"'\r\n]*\b(?:SMOKE )?PASS\b[^\"'\r\n]*)[\"']", source)
        if quoted:
            marker = quoted[0].split("%", 1)[0].strip()
            marker = re.split(r"<[^>]+>", marker, 1)[0].strip()
            return marker
    if match := re.fullmatch(r"fc_(p\d{2})_smoke\.gd", filename):
        return f"FC {match.group(1).upper()} PASS"
    return filename.removesuffix("_smoke.gd").replace("_", " ").upper() + " PASS"


def _check(command: str, marker: str, *, forbid_diagnostics: bool = True) -> dict[str, Any]:
    return {
        "command": command,
        "success": {
            "exit_code": 0,
            "required_output": [marker],
            "forbidden_output": DIAGNOSTIC_MARKERS if forbid_diagnostics else [],
        },
    }


def _verification(card_id: str, root: Path) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    if card_id == "P01":
        return [_check("& $Python tools/build_feature_acceptance.py --check", "FEATURE ACCEPTANCE REGISTRY PASS")]
    if card_id == "P02":
        return [
            _check("& $Python -m pytest -q tests/test_feature_completion_runner.py tests/test_feature_acceptance_registry.py", "passed", forbid_diagnostics=False),
            _check("& $Python tools/test_build_system_inventory.py", "BUILD INVENTORY SELFTEST PASS", forbid_diagnostics=False),
            _check("& $Python tools/build_system_inventory.py --check", "SYSTEM INVENTORY CHECK PASS"),
            _check("& $Python tools/build_system_inventory.py --coverage", "SYSTEM INVENTORY COVERAGE PASS"),
        ]
    if re.fullmatch(r"P(?:0[3-9]|1\d|2[0-2])", card_id):
        checks.append(_check(
            f"& $Python tools/run_feature_completion.py --godot $Godot --case {card_id} --evidence-dir artifacts/feature-completion/{card_id}",
            f"FC {card_id} PASS",
        ))
    for filename in CARD_SMOKES.get(card_id, []):
        checks.append(_check(
            f"& $Godot --headless --path . --script res://scripts/validation/{filename}",
            _smoke_marker(root, filename),
        ))
    if card_id == "P09":
        checks.append(_check("& $Python -m unittest tests.test_crafting_economy", "OK", forbid_diagnostics=False))
    if card_id == "P17":
        checks.append(_check("& $Python -m unittest tests.test_structural_rebuild_catalog", "OK", forbid_diagnostics=False))
    if card_id in {"P00", "P10", "P20", "P22"}:
        profile = "baseline" if card_id == "P00" else "crafting" if card_id == "P10" else "restoration" if card_id == "P20" else "all"
        checks.append(_check(
            f"& $Python tools/run_feature_completion.py --godot $Godot --profile {profile} --evidence-dir artifacts/feature-completion/{card_id}-profile",
            "feature completion PASS:",
        ))
    if card_id == "P23":
        checks.append(_check(
            "& $Python tools/run_feature_completion.py --godot $Godot --profile all --evidence-dir artifacts/feature-completion/G5",
            "feature completion PASS:",
        ))
    if card_id == "P24":
        checks.extend([
            _check("& $Python tools/check_export_pipeline.py", "EXPORT PIPELINE CHECK PASS"),
            _check("& $Godot --headless --path . --script res://scripts/validation/export_presets_smoke.gd", "EXPORT PRESETS PASS"),
            _check("& $Godot --headless --path . --script res://scripts/validation/release_readiness_ledger_smoke.gd", "RELEASE READINESS LEDGER PASS"),
        ])
    return checks


def build_card_manifest(root: Path = ROOT) -> dict[str, Any]:
    root = Path(root)
    anchors = _plan_anchors(root)
    plan_contracts = _plan_card_contracts(root)
    expected = [f"P{number:02d}" for number in range(25)]
    missing = [card_id for card_id in expected if card_id not in anchors]
    if missing:
        raise AssertionError(f"tracked plan is missing card anchors: {missing}")
    cards = []
    for card_id in expected:
        assert plan_contracts[card_id]["depends_on"] == CARD_DEPENDENCIES[card_id], f"plan dependencies disagree with manifest scope: {card_id}"
        assert plan_contracts[card_id]["requirements"] == CARD_REQUIREMENTS[card_id], f"plan requirements disagree with manifest scope: {card_id}"
        cards.append({
            "id": card_id,
            "requirements": CARD_REQUIREMENTS[card_id],
            "depends_on": CARD_DEPENDENCIES[card_id],
            "allowlist": [
                {
                    "path": path,
                    "source_exists": _source_exists(root, path),
                    "scope_state": "present" if _source_exists(root, path) else "planned_missing",
                }
                for path in CARD_ALLOWLISTS[card_id]
            ],
            "scope_decisions_pending": [],
            "non_goals": CARD_NON_GOALS[card_id],
            "verification": _verification(card_id, root),
            "plan_anchor": {"path": PLAN_REL.as_posix(), "heading": card_id, "line": anchors[card_id]},
        })
    return {
        "schema_version": "feature-completion-card-manifest-v2",
        "board": "synaptic-sea-stage-gate",
        "sync_status": "pending",
        "sync_note": "Local import manifest only; no observed board integration or card creation is claimed.",
        "source_plan": PLAN_REL.as_posix(),
        "card_contract": "Tracked-plan card scopes expanded to repository paths; planned missing paths remain explicit and do not imply implementation.",
        "cards": cards,
    }


def write_card_manifest(root: Path = ROOT) -> dict[str, Any]:
    manifest = build_card_manifest(root)
    path = Path(root) / CARDS_REL
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest


def validate(registry: dict[str, Any], cards: dict[str, Any] | None = None, root: Path = ROOT) -> None:
    root = Path(root)
    assert registry["schema_version"] == "feature-acceptance-v5", "unexpected acceptance schema"
    identifiers = [entry["id"] for entry in registry["criteria"]]
    assert len(identifiers) == len(set(identifiers)), "duplicate criterion IDs"
    assert len([identifier for identifier in identifiers if re.fullmatch(r"FC-\d{2}", identifier)]) == 24, "missing FC criterion"
    assert len([identifier for identifier in identifiers if identifier.startswith("REQ-")]) >= 130, "requirement acceptance leaves not represented"
    assert registry["accounting"]["recorded"] == len(registry["criteria"]), "recorded denominator mismatch"
    assert registry["accounting"]["active"] + registry["accounting"]["deferred"] == len(registry["criteria"]), "active/deferred accounting mismatch"
    expected_source_paths = {REQUIREMENTS_REL.as_posix()} | {
        path.relative_to(root).as_posix() for path in (root / FEATURES_REL).glob("*.md")
    }
    actual_source_paths = [entry["path"] for entry in registry["source_documents"]]
    assert len(actual_source_paths) == len(set(actual_source_paths)), "duplicate source document accounting"
    assert set(actual_source_paths) == expected_source_paths, "source document inventory is incomplete or stale"
    expected_blockers: list[str] = []
    for source in registry["source_documents"]:
        if source["kind"] == "requirement_register":
            expected_blockers.extend(
                f"{source['path']}#{heading['heading']}" for heading in source["unassessed_headings"]
            )
        elif source["assessment"].startswith("unassessed_"):
            expected_blockers.append(source["path"])
    assert registry["accounting"]["metric_blockers"] == sorted(expected_blockers), "source blocker accounting mismatch"
    assert registry["accounting"]["unassessed_source_count"] == len(expected_blockers), "unassessed-source count mismatch"
    source_anchors = [entry["anchor"] for entry in registry["source_leaf_coverage"]]
    assert len(source_anchors) == len(set(source_anchors)), "duplicate source leaf anchors"
    covered_ids = {identifier for item in registry["source_leaf_coverage"] for identifier in item["criterion_ids"]}
    assert set(identifiers) == covered_ids, "source leaves and criteria are not one-to-one accounted"
    for entry in registry["criteria"]:
        assert entry["source"]["path"], f"missing source for {entry['id']}"
        assert entry["criterion_fingerprint"] == _digest(entry["source"]["path"], entry["source"]["heading"], entry["criterion"]), f"stale criterion fingerprint: {entry['id']}"
        assert _valid_evidence(entry["evidence"]), f"invalid evidence: {entry['id']}"
        equivalence = entry.get("metric_equivalence", {})
        assert equivalence.get("representative_id") in identifiers, f"invalid equivalence representative: {entry['id']}"
        assert isinstance(equivalence.get("counts_toward_proposed_denominator"), bool), f"invalid equivalence count flag: {entry['id']}"
    proposed_count = sum(
        not entry["deferred"] and entry["metric_equivalence"]["counts_toward_proposed_denominator"]
        for entry in registry["criteria"]
    )
    assert registry["accounting"]["active_metric_denominator"] == proposed_count, "active metric denominator mismatch"
    assert registry["accounting"]["equivalence_alias_count"] == registry["accounting"]["active"] - proposed_count, "equivalence alias accounting mismatch"
    entries_by_id = {entry["id"]: entry for entry in registry["criteria"]}
    for group in registry["duplicate_criterion_review"]:
        assert group["review"]["reviewer"] and group["review"]["reviewed_on"], "duplicate review provenance missing"
        if group["disposition"] == "reviewed_equivalent_same_package_boilerplate":
            assert group["representative_id"] in group["criterion_ids"], "duplicate representative missing from group"
            assert group["alias_ids"] == [identifier for identifier in group["criterion_ids"] if identifier != group["representative_id"]], "duplicate aliases mismatch"
            representative_equivalence = entries_by_id[group["representative_id"]]["metric_equivalence"]
            assert representative_equivalence["counts_toward_proposed_denominator"], "duplicate representative excluded from denominator"
            for identifier in group["criterion_ids"]:
                equivalence = entries_by_id[identifier]["metric_equivalence"]
                assert equivalence["group_id"] == representative_equivalence["group_id"], "duplicate group ID mismatch"
                assert equivalence["representative_id"] == group["representative_id"], "duplicate representative mapping mismatch"
                assert equivalence["counts_toward_proposed_denominator"] == (identifier == group["representative_id"]), "duplicate alias count flag mismatch"
        else:
            assert group["disposition"] == "reviewed_same_text_distinct_scope", "unknown duplicate disposition"
            assert group["alias_ids"] == [], "distinct-scope group contains aliases"
            assert group["representative_ids"] == group["criterion_ids"], "distinct-scope representatives mismatch"
            for identifier in group["criterion_ids"]:
                equivalence = entries_by_id[identifier]["metric_equivalence"]
                assert equivalence["representative_id"] == identifier, "distinct-scope criterion was aliased"
                assert equivalence["counts_toward_proposed_denominator"], "distinct-scope criterion excluded from denominator"
    candidate = registry["scope_freeze_candidate"]
    assert candidate["source_leaf_set_fingerprint"] == _scope_contract_fingerprint(
        registry["criteria"], registry["source_documents"]
    ), "scope-freeze candidate fingerprint mismatch"
    assert candidate["source_row_count"] == len(registry["criteria"]), "scope-freeze candidate row count mismatch"
    assert candidate["proposed_active_denominator"] == proposed_count, "scope-freeze candidate denominator mismatch"
    if registry["scope_frozen"] is None:
        expected_review_status = "incomplete_source_mapping" if registry["accounting"]["metric_blockers"] else "ready_for_final_scope_review"
        assert registry["scope_review"]["status"] == expected_review_status, "unfrozen scope lacks review state"
        assert all(value is None for value in registry["accounting"]["percentages"].values()), "unfrozen denominator published percentages"
    else:
        assert registry["scope_frozen"]["source_leaf_set_fingerprint"] == candidate["source_leaf_set_fingerprint"], "frozen scope fingerprint mismatch"
        assert registry["scope_review"]["status"] == "frozen", "frozen scope review state mismatch"
    if registry["accounting"]["metric_blockers"]:
        assert all(value is None for value in registry["accounting"]["percentages"].values()), "incomplete denominator published percentages"

    manifest = cards if cards is not None else build_card_manifest(root)
    assert manifest["sync_status"] == "pending", "board synchronization was not observed"
    assert "source_directory" not in manifest, "ignored brief directory cannot be a manifest source"
    expected = [f"P{number:02d}" for number in range(25)]
    assert [card["id"] for card in manifest["cards"]] == expected, "P00-P24 missing or out of order"
    valid_dependencies = set(expected) | {f"G{number}" for number in range(7)}
    plan_text = (root / PLAN_REL).read_text(encoding="utf-8")
    for card in manifest["cards"]:
        assert all(dependency in valid_dependencies for dependency in card["depends_on"]), f"invalid dependency: {card['id']}"
        assert f"### {card['id']} " in plan_text, f"missing tracked plan anchor: {card['id']}"
        assert card["allowlist"] and all("path" in item and item["path"] for item in card["allowlist"]), f"missing path allowlist: {card['id']}"
        assert card["verification"], f"missing verification: {card['id']}"
        for check in card["verification"]:
            assert check["command"] and check["success"]["required_output"], f"non-executable verification: {card['id']}"


def write_outputs(root: Path = ROOT) -> tuple[dict[str, Any], dict[str, Any]]:
    registry = write_registry(root)
    cards = write_card_manifest(root)
    validate(registry, cards, root)
    return registry, cards


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.write:
        registry, cards = write_outputs(root)
    else:
        registry = build(root)
        cards = build_card_manifest(root)
    if args.check:
        stored_registry = json.loads((root / REGISTRY_REL).read_text(encoding="utf-8"))
        stored_cards = json.loads((root / CARDS_REL).read_text(encoding="utf-8"))
        assert stored_registry == registry, "registry is stale; run build_feature_acceptance.py --write"
        assert stored_cards == cards, "card manifest is stale; run build_feature_acceptance.py --write"
        validate(stored_registry, stored_cards, root)
    print(
        "FEATURE ACCEPTANCE REGISTRY PASS "
        f"criteria={len(registry['criteria'])} "
        f"unassessed_sources={registry['accounting']['unassessed_source_count']}"
    )


if __name__ == "__main__":
    main()
