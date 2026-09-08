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
SUPERSESSIONS_REL = Path("data/validation/reviewed_criterion_supersessions_v1.json")
PLAN_REL = Path("docs/superpowers/plans/2026-09-04-crafting-derelict-feature-completion.md")

REQUIREMENTS = ROOT / REQUIREMENTS_REL
REGISTRY = ROOT / REGISTRY_REL
CARDS = ROOT / CARDS_REL
PLAN = ROOT / PLAN_REL
SUPERSESSIONS_SCHEMA = "reviewed-criterion-supersessions-v1"
REVIEWED_FEATURE_SUPERSESSION_SOURCES: dict[str, set[str]] = {
    "docs/game/features/structural_wrapper_collision.md": {"Acceptance criteria"},
}

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
    "reviewed_supersession_set_fingerprint": "54f7c6f782eac4ca7e4a589304b9a74fc754ab3f3384bdf0d5ee3121ec482a8f",
    "reviewer": "root_coordinator",
    "review_disposition": "approved_source_leaves_and_reviewed_equivalence_map",
}

# This is a reviewed, document-specific scope ruling.  It is deliberately not a
# status-based filter: every other feature document remains source-accounted.
REVIEWED_OUT_OF_SCOPE_PROPOSALS: dict[str, dict[str, str | int]] = {
    "docs/game/features/ui_presentation_program.md": {
        "disposition": "excluded_reviewed_planning_proposal",
        "reason": "Planning-only UI presentation proposal is outside the frozen crafting/derelict completion program.",
        "required_status": "Proposed for review, 2026-09-05. Planning only; no UI implementation or visual acceptance is claimed.",
        "expected_leaf_count": 21,
    },
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
    "P17": ["P09", "P12", "P13", "P16"],
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
    "P09": "Recipe count as a completion metric; arbitrary loot or balance additions from a sampled absence; injected inventory, force repair, teleport, direct skill mutation, or snapshot seeding as natural-path evidence; retired donor healing; unproven low-repair-class softlock claims; editor/import/plugin launch; or early full-source pinning.",
    "P10": "Save filename changes, historical-data deletion, default-profile cleanup, comparison epsilon, new ignored fields, generalized oxygen normalization, combat-schema weakening, editor/import/plugin launch, or unrelated P09/P17/catalog/navigation behavior.",
    "P11": "Synthetic replacement slots, freeform construction, or P14 condition policy.",
    "P12": "Replacing the interaction system, adding a second mutation authority, or absorbing P15/P17 work.",
    "P13": "Multiplayer authority, unrelated extraction, or implicit current/home-ship owner fallback.",
    "P14": "Free repair on install or balance inflation.",
    "P15": "Ordinary repair resurrecting destroyed modules.",
    "P16": "Reconstruction or altered room generation.",
    "P17": "Claiming FC-19 from the R10-A baseline prerequisite; placement outside the original footprint; preserving room-center or diagnostic-coordinate docking; nearest-room, center-snap, silent alternate-layout, collision-disable, or invented-spawn recovery; arbitrary reinterpretation of world-6 transforms/global pose; or unreviewed cart push physics.",
    "P18": "Visual-only replacement or native-generator replacement.",
    "P19": "Silently discarding unmatched deltas.",
    "P20": "Bypassing safe-return or ownership rules.",
    "P21": "A separate editor UI or final-art overhaul.",
    "P22": "Substituting headless helper calls for player evidence.",
    "P23": "Completion claims for uninspected domains.",
    "P24": "Publishing, purchasing services, or enabling cloud integrations.",
}

CARD_SCOPE_DECISIONS = {
    "P09": [
        "R04 may propose a minimal balance or authored-progression change only after normal-control evidence demonstrates a specific broken link; root owns that ruling.",
        "Full production-source closure is deferred until reviewed R03/R11 integration; R04 records exact source hashes and reachable-route limits.",
        "R07 machinery-condition review retires old donor-healing assumptions; R04 must observe only current intended station/system benefit.",
        "Every P09 Godot body uses the hardened feature-completion runner, which first runs the accepted FC P10 USER DATA PROBE PASS containment check with all four owned-home variables."
    ],
    "P11": [
        "R06 adds distinct no-spend cases for authored slot identity/profile, footprint or size, socket or type, occupancy, water, unknown component, and wrong selected ship without changing FC-13 text.",
        "Every R06 Godot body runs through the tracked physical-work runner, a thin hardened execute_isolated_case adapter that preserves the fresh four-variable home and separate P10 containment probe.",
    ],
    "P12": [
        "R06 distinguishes pre-escrow admission denial from paid interruption: admission spends nothing; pause retains exact escrow and progress; explicit cancel refunds exact lots.",
        "Commit revalidates target existence and revision, range, owner, access, occupancy, and tool; duplicate or reentrant completion may produce one receipt, effect, noise completion, and XP award.",
        "Every R06 Godot body runs through the tracked physical-work runner, a thin hardened execute_isolated_case adapter that preserves the fresh four-variable home and separate P10 containment probe.",
    ],
    "P13": [
        "Physical work requires an explicit target ship and current binding generation; missing owners fail closed and may not resolve through current_ship or home_ship.",
        "R03 already accepted the production same-ship and cross-ship exact-lot move through two reloads; R06 reruns canonical P10 and reviews those predicates instead of duplicating them.",
        "Every R06 Godot body runs through the tracked physical-work runner, a thin hardened execute_isolated_case adapter that preserves the fresh four-variable home and separate P10 containment probe.",
    ],
    "P17": [
        "R10-A precedes R04 natural-route runtime and R09 live-scene acceptance; it restores registered production docking, ordinary seam traversal, the ceiling proxy, and strict persistence without emitting FC P17 PASS.",
        "Every production endpoint comes from actual occupancy and an explicit one-sided exterior portal whose plane is the projected doorway frame's outer collision face; each non-join shape intersecting the finite aperture projection remains wholly inward, while every shape still participates in strict cross-ship pair checks.",
        "Docking derives the mobile transform from opposing authenticated descriptors; author-time selection and live preflight use one pure projected pair predicate that rejects every positive-volume cross-ship intersection, including authenticated join identities, while permitting exact zero-volume contact without epsilon. R10-A freezes canonical fixed-lifeboat pairing for production hosts while claimed-ship pairing remains R14.",
        "The fixed lifeboat owns one authored clear initial interior spawn, distinct from the threshold but permitted to reuse its interior clearance anchor; New Game applies it only after pair/barrier construction and publishes only when occupancy is the lifeboat and the closed barrier excludes home.",
        "At home and away, the real PlayerController remains grounded through ordinary input in both directions when open and is physically denied when closed. Overlapping room AABBs resolve only through the authenticated connection plane; exact tie is mobile, and closing behind a player does not rewrite the cleared-side owner.",
        "Governance allocates gate2-current-run-7/world-7; RunSnapshot drops its global pose and WorldSnapshot owns the sole owner-local pose, while raw standalone run6 remains unclosed_owner_graph and world6 migration handles at-home duplicate versus away obsolete home-departure data explicitly.",
        "Historical integrity migration reuses one public typed compiled-placement identity function in ModuleIntegrityConsequences; compiled seeding calls the same function, and focused tests compare exact full-edge, half-span, vertex, floor, and ceiling IDs against registered modules without changing health semantics.",
        "Current run7/world7 integrity admission rejects malformed nonempty envelopes before normalization, preserves absent/empty versus explicit repaired state, and validates exact health rows; descriptor-bound application rejects unknown IDs, count/kind/room mismatches atomically while historical decoding remains version-specific.",
        "World-6 attachment projection pins the minimal c51 historical generation/data closure and exact native-v2 hash/version; incomplete route sets and differing surviving transforms reject explicitly. Its focused smoke proves exact historical descriptors without current-generation substitution, save publication, or health migration.",
        "Corrected ceiling physical bounds are Y 3.8..4.0 while transform-aware visual bounds independently retain decorative underside; source regeneration and validation must prove both.",
        "R10 vertex-half-span correction preserves the three real corner/T module IDs: vertex-owned 2 m by 3 m by 0.2 m rays claim exact incident SOLID half spans; residual half straights use scale (0.5, 1, 1), and every 4 m SOLID edge resolves end-to-end without missing, extra, or duplicate centerline span. Changed geometry-dependent acceptance evidence requires fresh requalification.",
    ],
    "P23": [
        "The reviewed planning-only proposal docs/game/features/ui_presentation_program.md is catalogued outside the frozen crafting/derelict acceptance program only while its status remains Proposed for review and Planning only; status drift, a missing catalogued source, or any unexpected feature source fails closed during scope review.",
        "Canonical-regression reconciliation records the observed 652 calls against a strict numeric final marker with a runtime count guard, and records Meshy ADR-0068 identity while preserving the historical ADR-0060 filename.",
    ],
}

CARD_CONTRACTS = {
    "P10": {
        "r02_versions": {
            "run": "gate2-current-run-6",
            "world": "world-6",
            "combat": "threat-manager-2",
            "future_rejection": ["gate2-current-run-7", "world-7"],
        },
        "combat_codec": {
            "path": "scripts/systems/threat_save_contract.gd",
            "api": [
                "validate_current(summary: Variant) -> Dictionary",
                "migrate_legacy(summary: Variant) -> Dictionary",
            ],
        },
        "combat_initializer": {
            "path": "scripts/systems/threat_initial_state_builder.gd",
            "api": "build_initial_v2(layout: Dictionary, markers: Array, anchor: Vector3, definitions: Dictionary) -> Dictionary",
            "production_consumer": "ThreatManager.configure_for_layout",
        },
        "generation_documents": {
            "path": "scripts/procgen/ship_generator.gd",
            "api": "generate_documents_from_seed(seed_value: int, size: int = 0, condition: int = 1) -> Dictionary",
            "contract": "Pure native-or-fallback layout/kit/gameplay documents shared by scene generation and legacy bootstrap; no Node/RID and no fallback after a selected pipeline fails.",
        },
        "version_policy": "Run v5-to-v6 performs pinned v5 normalization then combat migration; declared run v6 is strict. World v5-to-v6 alone migrates its embedded run; declared world v6 requires embedded run v6 exactly.",
        "bootstrap_policy": "Current run v6 requires initialized home combat and current world v6 requires active-away combat. Recognized pre-v6 absence or empty data at those paths is initialized before strict decode and sealing from validated original layout, markers, owner anchor, generation context, and injected canonical definitions. Inactive never-initialized owners may remain absent; current present empty dictionaries reject; complete v2 empty managers are authoritative.",
        "owner_policy": "Embedded inventory threat_summary belongs to home_ship; active visited combat belongs to that visited ship and is synchronized before capture; inactive owners retain stored combat. SaveRestoreCandidate retains validated threat_summary and required exact-String current combat_hotbar_text through inventory canonicalization. Recognized pre-v6 absence materializes the empty runtime default before sealing; present historical text remains byte-for-byte.",
        "legacy_structure_damage": {
            "hull_tendril": 0.4,
            "biomatter_swarm": 0.0,
            "puppet_corpse": 0.0,
            "stalker": 0.0,
            "mimic": 0.0,
            "drone_swarm": 0.0,
        },
        "authority": "ADR-0059 decisions 33-39",
    },
    "P17": {
        "r10a_status": "baseline_component_candidate_frozen_independent_review_pending_run7_world7_not_started",
        "r10a_prerequisites": ["P01/R01 governance", "P03/R03 persistence governance", "accepted R06 fix re-review handoff"],
        "r10b_prerequisites": ["R09 live blocker binding", "R10-A accepted baseline"],
        "full_p17_acceptance_prerequisites": ["P09", "P12", "P13", "P16", "R10-A", "R09", "R10-B"],
        "boarding_endpoints_v1_exact_fields": [
            "endpoint_id", "port_id", "portal_id", "type", "size_class",
            "room_id", "deck", "edge_cell", "edge_direction",
            "structural_edge_key", "target_module_id", "structural_module_id",
            "local_position", "outward_normal", "threshold_nav_node_id",
            "interior_nav_node_id", "threshold_clearance_point_local",
            "interior_clearance_point_local", "join_piece_placement_ids",
            "join_collision_fingerprint",
        ],
        "endpoint_geometry": "Explicit one-sided exterior portal on the projected canonical doorway frame's exact outer collision face; each non-join owner shape whose tangent/up projection intersects the finite aperture remains wholly inward and threshold clearance remains outside; all shapes remain subject to strict cross-ship pair checks; fixed lifeboat west airlock/engine seam is forbidden.",
        "dock_collision_projection": {
            "schema": "dock-collision-projection-v1",
            "owner": "data/kits/ship_structural_v0.json",
            "source": "contract-selected canonical wrapper trees",
            "module_fields": ["module_id", "wrapper_scene", "wrapper_sha256", "content_sha256", "boxes"],
            "box_fields": ["shape_path", "basis", "basis_f32_bits", "origin", "origin_f32_bits", "dimensions", "dimensions_f32_bits"],
            "numeric_encoding": "Readable numeric components are binary32-normalized and must reproduce their paired exact IEEE-754 bit strings; either representation rejects when they disagree.",
            "policy": "Generated deterministically from current selected BoxShape3D wrappers while recording any finite non-singular composed basis exactly; source-byte hashes are build provenance; pure authorizer consumes a validated immutable projection; exported live loader requires exact materialized path/shape/transform/dimension and normalized-content fingerprint agreement; no missing-source bypass, GLB sidecar substitution, or hardcoded doorway half-depth.",
        },
        "initial_player_spawn_v1_exact_fields": [
            "spawn_id", "owner_ship_id", "room_id", "nav_node_id", "local_position",
        ],
        "fresh_spawn_policy": "Fixed-lifeboat authored clear interior point distinct from the threshold and permitted to reuse its capsule-clear interior clearance anchor; applied once after corrected pair/closed-barrier construction; publish only when occupancy is lifeboat and barrier excludes home; never save/load or migration recovery. Later separation requires a new authored spawn and complete opening requalification.",
        "seam_overlap_policy": "Every positive-volume cross-hull intersection rejects, including authenticated open-frame and directly incident floor/corridor-floor join identities. Exact zero-volume contact is allowed without epsilon, slab, seam exception, or global margin; join IDs authenticate placement/connection identity only; full capsule clearance is independent.",
        "pair_predicate_policy": "Author-time compatible-pair selection and live preflight call the same pure projected cross-hull predicate. R10-A freezes canonical fixed-lifeboat pairing for production home, fallback and native hosts; arbitrary claimed-ship pairing remains R14.",
        "occupancy_overlap_policy": "Merged room AABB overlap resolves only through the authenticated current connection, barrier and both endpoint IDs, then the registered connection plane; the exact tie belongs to mobile, and closing behind a player who cleared either side does not rewrite ownership.",
        "production_traversal_policy": "Real PlayerController inputs and move_and_slide remain grounded across the open seam in both directions at home and away; the closed barrier denies each crossing.",
        "dock_connections_v1_exact_fields": [
            "connection_id", "port_type", "slot_index", "host", "mobile",
        ],
        "connection_endpoint_exact_fields": ["ship_id", "endpoint_id", "port_id"],
        "player_owner_pose_v1_exact_fields": [
            "owner_ship_id", "location_kind", "local_position",
            "connection_id", "endpoint_id",
        ],
        "boarding_port_states_v1_exact_fields": [
            "ship_id", "endpoint_id", "barrier_open",
        ],
        "allocated_world7_current_keys": [
            "dock_connections_v1", "player_owner_pose_v1",
            "boarding_port_states_v1", "aboard_ship_id",
        ],
        "allocated_current_forbidden_legacy_keys": [
            "dock_edges", "player_position", "player_position_in_ship", "opened_ports",
            "hallucination_summary",
        ],
        "player_pose_owner": "WorldSnapshot.player_owner_pose_v1 is sole current authority; RunSnapshot has no pose field in run7.",
        "legacy_player_pose_policy": "At-home world6 requires exact embedded/top-level equality and explicit aboard owner, then migrates once; away world6 validates and discards finite obsolete home-departure coordinates and migrates only the explicit top-level owner pose.",
        "legacy_run_admission_matrix": {
            "raw_gate2_current_run_6": "reject unclosed_owner_graph explicitly after CURRENT_SLICE_VERSION advances; never fall through the older-run adapter",
            "recognized_pre_v6_direct_run": "retain only the existing strict historical closed-world adapter preconditions",
            "world_6_home": "require finite exact embedded/top-level position equality and explicit aboard owner; migrate one pose and discard duplicate",
            "world_6_away": "require finite embedded legacy coordinate, discard it as obsolete, and migrate top-level pose through explicit aboard owner",
        },
        "allocated_versions": {"run": "gate2-current-run-7", "world": "world-7", "next_future_rejection": ["gate2-current-run-8", "world-8"]},
        "preimplementation_sentinel_state": "R06/P10 still names run7/world7 as future rejection; implementation preserves those artifacts as history and moves active fixtures/sentinels to run8/world8 before making the allocated pair current.",
        "threshold_owner": "mobile endpoint",
        "precision_policy": "Preserve the accepted full-precision owner-local pose under an exact central restore receipt; unchanged recapture is bit-exact without epsilon, rounding, or another inverse transform.",
        "legacy_spatial_policy": "Ship-local carts, floor drops, corpse drops, and station positions remain exact; version-pinned migration transforms visited combat world_position/last_known_position for moved owners and rejects any unprovable world-space field.",
        "live_spatial_policy": "The docking pre-mutation transaction rebases active/stored combat world_position and last_known_position with the mobile root delta while established ship-local fields inherit the root; unknown world-space owners reject.",
        "ceiling_collision_bounds": [[-2.0, 3.8, -2.0], [2.0, 4.0, 2.0]],
        "ceiling_visual_bounds_policy": "Transform-aware visual bounds are independent and retain decorative underside to approximately Y 3.6875.",
        "authority": "ADR-0017 R10-A amendment, ADR-0065 section 4, and ADR-0059 accepted decisions 44-49",
    },
}

COORDINATOR = "scripts/procgen/playable_generated_ship.gd"
COMPONENT_CATALOG = "data/components/component_catalog.json"
WORK_ACTION_CATALOG = "data/work_actions/work_action_catalog.json"
VALIDATION = "scripts/validation/"
R06_GOVERNANCE_SCOPE = [
    ".superpowers/sdd/2026-09-05-remaining-feature-completion/task-6-brief.md",
    ".superpowers/sdd/2026-09-05-remaining-feature-completion/task-6-report.md",
    "tools/run_physical_work_smokes.py",
    "tests/test_physical_work_runner.py",
    "docs/game/05_requirements.md",
    "docs/game/features/crafting_derelict_feature_completion.md",
    "docs/superpowers/plans/2026-09-04-crafting-derelict-feature-completion.md",
    "tools/build_feature_acceptance.py",
    "data/validation/feature_completion_cards.json",
    "docs/game/inventory/feature_acceptance.json",
]
R06_CARD_METADATA = {
    card_id: {
        "closure_package": "R06",
        "owner": {
            "integration": "sol_engineer",
            "bounded_tests": "terra_worker",
            "coordinator_and_acceptance": "root",
        },
        "feature_spec": "docs/game/features/crafting_derelict_feature_completion.md",
        "architecture": "docs/game/adr/0059-crafting-and-derelict-restoration-transactions.md",
    }
    for card_id in ("P11", "P12", "P13")
}

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
        "scripts/validation/load_denied_sfx_smoke.gd",
        "scripts/validation/vitals_state_save_load_smoke.gd",
        "scripts/validation/room_assigner_smoke.gd",
        "scripts/validation/capture_current_topology_fixture.gd",
        "scripts/validation/procgen_golden_parity_smoke.gd",
        "scripts/validation/procgen_layout_stress_smoke.gd",
        "scripts/validation/procgen_playable_ship_smoke.gd",
        "scripts/validation/procgen_loader_playable_contract_smoke.gd",
        "scripts/validation/generated_seed_boarded_slice_smoke.gd",
        "docs/game/adr/0067-native-first-run-candidate-authority.md",
        "docs/game/features/generated_seed_boarded_slice.md",
        "data/procgen/slice/first_run_contract.json",
        "scripts/procgen/first_run_contract.gd",
        "scripts/validation/first_run_contract_smoke.gd",
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
        "tools/classify_orphan_smokes.sh", ".gitattributes",
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
        "scripts/systems/ship_work_context.gd",
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
        "scripts/systems/work_action_driver.gd",
        "scripts/tools/crafting_station.gd", "scripts/ui/recipe_picker_panel.gd", COORDINATOR,
        f"{VALIDATION}fc_p09_smoke.gd", f"{VALIDATION}fc_p05_smoke.gd",
        f"{VALIDATION}fc_p09_natural_route_smoke.gd",
        f"{VALIDATION}recipe_resource_smoke.gd",
        f"{VALIDATION}recipe_picker_panel_smoke.gd",
        f"{VALIDATION}fc_p12_smoke.gd",
    ],
    "P10": [
        "docs/game/adr/0059-crafting-and-derelict-restoration-transactions.md",
        ".superpowers/sdd/2026-09-04-crafting-derelict-feature-completion/P10-implementation-brief.md",
        ".superpowers/sdd/2026-09-04-crafting-derelict-feature-completion/P10-repair-proposal.md",
        "scripts/systems/save_restore_candidate.gd",
        "scripts/main.gd", "scripts/title_main.gd",
        "scripts/audio/audio_manager.gd",
        "scripts/camera/iso_camera_rig.gd",
        "scripts/ui/save_load_menu.gd", "scripts/ui/menu_coordinator.gd",
        "scripts/ui/recipe_picker_panel.gd", "scripts/ui/ship_modification_panel.gd",
        "scripts/tools/crafting_station.gd", "scripts/systems/ship_work_context.gd",
        "scripts/systems/electrical_arc_state.gd",
        *[f"scripts/systems/{name}.gd" for name in (
            "run_snapshot", "world_snapshot", "save_migration_service", "save_load_service",
            "crafting_state", "craft_job_state", "craft_job_scheduler", "station_state",
            "field_crafting_state", "recipe_knowledge_state", "component_placement_state",
            "ship_instance", "ship_runtime", "pillar_persistence", "threat_ai_state",
            "threat_manager", "threat_save_contract", "threat_initial_state_builder",
        )],
        COORDINATOR, "tests/fixtures/feature_completion/**", f"{VALIDATION}fc_p10_smoke.gd",
        f"{VALIDATION}fc_p10_process_smoke.gd", f"{VALIDATION}fc_p13_smoke.gd",
        f"{VALIDATION}combat_persistence_smoke.gd",
        "tools/run_p10_process_smoke.py",
        "tests/test_p10_process_runner.py",
        "tests/fixtures/feature_completion/p10_run_v7_future.json",
        "tests/fixtures/feature_completion/p10_world_v7_future.json",
        "scripts/procgen/ship_generator.gd", f"{VALIDATION}ship_generator_smoke.gd",
        *[f"{VALIDATION}{name}.gd" for name in (
            "threat_ai_state_smoke", "tendril_structure_damage_smoke",
            "save_migration_service_smoke", "save_migration_world_smoke",
            "save_load_service_smoke", "world_snapshot_smoke", "world_save_service_smoke",
            "ship_mod_run_snapshot_smoke", "electrical_arc_state_smoke",
            "main_playable_quicksave_smoke",
            "main_playable_meta_autosave_smoke", "title_save_query_smoke",
            "title_load_failure_smoke",
        )],
        "tools/run_feature_completion.py", "tests/test_feature_completion_runner.py",
        "docs/game/05_requirements.md",
        "docs/game/features/crafting_derelict_feature_completion.md",
        "docs/superpowers/plans/2026-09-04-crafting-derelict-feature-completion.md",
        ".superpowers/sdd/2026-09-05-remaining-feature-completion/task-3-brief.md",
        "tools/build_feature_acceptance.py", "data/validation/feature_completion_cards.json",
        "docs/game/inventory/feature_acceptance.json",
        "docs/game/06_validation_plan.md", "tools/classify_orphan_smokes.sh",
    ],
    "P11": [
        *R06_GOVERNANCE_SCOPE,
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
        *R06_GOVERNANCE_SCOPE,
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
        *R06_GOVERNANCE_SCOPE,
        *[f"scripts/systems/{name}.gd" for name in (
            "ship_work_context", "ship_runtime", "ship_instance", "ship_access_state", "crafting_state")],
        "scripts/systems/world_snapshot.gd", "scripts/ui/ship_modification_panel.gd",
        COORDINATOR, f"{VALIDATION}fc_p13_smoke.gd",
        f"{VALIDATION}fc_p07_smoke.gd",
        *[f"{VALIDATION}{name}.gd" for name in (
            "ship_mod_inventory_sync_away_smoke", "ship_modification_panel_smoke",
            "ship_mod_system_effect_smoke", "ship_mod_system_effect_away_smoke",
            "component_remount_sfx_live_away_smoke")],
    ],
    "P14": [
        "docs/game/adr/0066-durable-machinery-condition-and-effective-system-health.md",
        "docs/game/adr/README.md",
        ".superpowers/sdd/2026-09-04-crafting-derelict-feature-completion/P14-implementation-brief.md",
        "docs/game/05_requirements.md", str(SUPERSESSIONS_REL).replace("\\", "/"),
        str(REGISTRY_REL).replace("\\", "/"), str(CARDS_REL).replace("\\", "/"),
        str(PLAN_REL).replace("\\", "/"), "tools/build_feature_acceptance.py",
        "tests/test_feature_acceptance_registry.py", "tests/test_p14_health_authority.py",
        *[f"scripts/systems/{name}.gd" for name in (
            "component_placement_state", "component_mount_resolver", "ship_systems_manager",
            "ship_system", "ship_subcomponent", "ship_modification_state", "crafting_state",
        )],
        "scripts/tools/repair_point.gd", COORDINATOR,
        *[f"{VALIDATION}{name}.gd" for name in (
            "fc_p14_smoke", "ship_systems_manager_smoke",
            "ship_systems_manager_force_repair_smoke", "component_mount_dismount_smoke",
            "dismount_system_damage_smoke", "remount_system_restore_smoke",
            "ship_mod_system_effect_smoke", "ship_mod_system_effect_away_smoke",
            "ship_mod_restore_effects_smoke", "ship_mod_restore_effects_away_smoke",
            "ship_mod_plating_repair_smoke", "ship_mod_plating_repair_away_smoke",
            "ship_mod_station_tier_smoke", "ship_mod_station_tier_away_smoke",
            "ship_mod_run_snapshot_smoke",
        )],
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
        ".superpowers/sdd/2026-09-05-remaining-feature-completion/task-10a-brief.md",
        ".superpowers/sdd/2026-09-05-remaining-feature-completion/task-10a-report.md",
        ".superpowers/sdd/2026-09-05-remaining-feature-completion/task-10a-beforeimages/manifest.json",
        ".superpowers/sdd/2026-09-05-remaining-feature-completion/task-10a-beforeimages/runtime-after-r06-manifest.json",
        ".superpowers/sdd/2026-09-05-remaining-feature-completion/r04-traversal-diagnosis.md",
        ".superpowers/sdd/2026-09-05-remaining-feature-completion/r17-hallucination-save-remediation-design.md",
        "docs/superpowers/plans/2026-09-05-remaining-feature-completion.md",
        "docs/superpowers/plans/2026-09-04-crafting-derelict-feature-completion.md",
        "docs/game/adr/0017-physical-docking-and-ports.md",
        "docs/game/adr/0042-sanity-hallucinations.md",
        "docs/game/adr/0059-crafting-and-derelict-restoration-transactions.md",
        "docs/game/adr/0065-structural-replacement-safety-and-scene-commit.md",
        "docs/game/features/crafting_derelict_feature_completion.md",
        "docs/game/features/structural_wrapper_collision.md",
        "docs/game/features/remaining_procgen_play_stack.md",
        "docs/game/features/socketed_enclosed_interiors.md",
        "docs/game/05_requirements.md", "tools/build_feature_acceptance.py",
        "tests/test_feature_acceptance_registry.py",
        "data/validation/reviewed_criterion_supersessions_v1.json",
        "data/validation/feature_completion_cards.json",
        "docs/game/inventory/feature_acceptance.json",
        ".superpowers/sdd/2026-09-05-remaining-feature-completion/task-10a-work-evidence/fix-round-01-source-contract-proposal-02/source_change_spec.json",
        ".superpowers/sdd/2026-09-05-remaining-feature-completion/task-10a-work-evidence/fix-round-01-source-contract-proposal-02/criterion_text_mapping.json",
        "scripts/systems/structural_rebuild_state.gd", "scripts/systems/ship_work_transaction.gd",
        "scripts/systems/module_integrity_map.gd", "scripts/systems/structural_rebuild_catalog.gd",
        "scripts/systems/module_integrity_state.gd",
        "scripts/validation/r10a_integrity_admission_smoke.gd",
        "scripts/systems/module_integrity_consequences.gd",
        "scripts/validation/module_integrity_consequences_smoke.gd",
        "scripts/systems/runtime_physical_volume_catalog.gd",
        "scripts/systems/runtime_physical_volume.gd",
        "scripts/systems/structural_rebuild_collision_query.gd",
        "scripts/systems/work_action_catalog.gd", "scripts/systems/work_action_resolver.gd",
        "scripts/procgen/structural_rebuild_preflight.gd",
        "scripts/procgen/dock_endpoint_authoring.gd",
        "scripts/procgen/structural_edge_compiler.gd",
        "scripts/procgen/structural_plan_validator.gd",
        "scripts/procgen/layout_serializer.gd",
        "scripts/procgen/ship_layout_generator.gd", "scripts/procgen/ship_generator.gd",
        "scripts/procgen/cell_layout_engine.gd",
        "scripts/validation/cell_layout_engine_smoke.gd",
        "scripts/procgen/life_boat.gd", "scripts/procgen/generated_ship_loader.gd",
        "scripts/procgen/modular_socket_catalog.gd", "scripts/systems/dock_ports.gd",
        "scripts/systems/docking_manager.gd", "scripts/systems/ship_instance.gd",
        "scripts/systems/ship_nav_graph.gd", "scripts/tools/dock_port_barrier.gd", COORDINATOR,
        "scripts/systems/run_snapshot.gd", "scripts/systems/world_snapshot.gd",
        "scripts/systems/save_load_service.gd", "scripts/systems/save_migration_service.gd",
        "scripts/systems/save_restore_candidate.gd",
        "scripts/systems/hallucination_director.gd",
        "scripts/systems/hallucination_manager.gd",
        "scripts/systems/threat_save_contract.gd", "scripts/systems/threat_manager.gd",
        "data/procgen/golden/compact_seed17_halfspan/edge_map.json",
        "data/procgen/golden/compact_seed17_halfspan/provenance.json",
        "data/construction/structural_rebuild_catalog.json", "data/tools/tool_definitions.json",
        "data/items/item_definitions.json", "data/physics/runtime_physical_volume_profiles.json",
        "data/procgen/golden/coherent_ship_001/layout.json",
        "data/placement/contracts/structural/ship_structural_v0/ceiling_cap_1x1_contract.json",
        "data/placement/contracts/structural/ship_structural_v0/ceiling_cap_1x1_contract.tres",
        "scenes/wrappers/structural/ship_structural_v0/ceiling_cap_1x1.tscn",
        "scenes/wrappers/structural/ship_structural_v0/ceiling_cap_1x1.input.json",
        "scenes/wrappers/structural/ship_structural_v0/ceiling_cap_1x1.manifest.json",
        "data/kits/ship_structural_v0.json", "tools/focused_nine_blender_recipes.py",
        "tools/rebuild_vertex_span_modules.py",
        "assets/_source/recovered/ship_structural_v0/.gdignore",
        "assets/_source/recovered/ship_structural_v0/wall_inner_corner/wall_inner_corner.blend",
        "assets/_source/recovered/ship_structural_v0/wall_inner_corner/wall_inner_corner.source.json",
        "assets/_source/recovered/ship_structural_v0/wall_outer_corner/wall_outer_corner.blend",
        "assets/_source/recovered/ship_structural_v0/wall_outer_corner/wall_outer_corner.source.json",
        "assets/_source/recovered/ship_structural_v0/wall_t_junction/wall_t_junction.blend",
        "assets/_source/recovered/ship_structural_v0/wall_t_junction/wall_t_junction.source.json",
        "assets/imported/structural/ship_structural_v0/wall_inner_corner/wall_inner_corner.glb",
        "assets/imported/structural/ship_structural_v0/wall_outer_corner/wall_outer_corner.glb",
        "assets/imported/structural/ship_structural_v0/wall_t_junction/wall_t_junction.glb",
        "scenes/wrappers/structural/ship_structural_v0/wall_inner_corner.tscn",
        "scenes/wrappers/structural/ship_structural_v0/wall_outer_corner.tscn",
        "scenes/wrappers/structural/ship_structural_v0/wall_t_junction.tscn",
        "scenes/wrappers/structural/ship_structural_v0/wall_inner_corner.input.json",
        "scenes/wrappers/structural/ship_structural_v0/wall_outer_corner.input.json",
        "scenes/wrappers/structural/ship_structural_v0/wall_t_junction.input.json",
        "scenes/wrappers/structural/ship_structural_v0/wall_inner_corner.manifest.json",
        "scenes/wrappers/structural/ship_structural_v0/wall_outer_corner.manifest.json",
        "scenes/wrappers/structural/ship_structural_v0/wall_t_junction.manifest.json",
        "data/placement/contracts/structural/ship_structural_v0/wall_inner_corner_contract.json",
        "data/placement/contracts/structural/ship_structural_v0/wall_inner_corner_contract.tres",
        "data/placement/contracts/structural/ship_structural_v0/wall_outer_corner_contract.json",
        "data/placement/contracts/structural/ship_structural_v0/wall_outer_corner_contract.tres",
        "data/placement/contracts/structural/ship_structural_v0/wall_t_junction_contract.json",
        "data/placement/contracts/structural/ship_structural_v0/wall_t_junction_contract.tres",
        "tools/build_dock_collision_projection.py", "tests/test_dock_collision_projection.py",
        "tools/prop_visual_metadata.py", "tests/test_focused_nine_blender_recipes.py",
        "tests/test_prop_visual_metadata.py", "scripts/placement/validate_wrapper_scenes.gd",
        "tools/check_structural_rebuild_catalog.py", "tests/test_structural_rebuild_catalog.py",
        "tools/check_runtime_physical_volume_catalog.py",
        "tests/test_runtime_physical_volume_catalog.py", "tools/classify_orphan_smokes.sh",
        "docs/game/06_validation_plan.md",
        WORK_ACTION_CATALOG, f"{VALIDATION}fc_p17_smoke.gd", f"{VALIDATION}fc_p16_smoke.gd",
        f"{VALIDATION}structural_rebuild_policy_smoke.gd",
        f"{VALIDATION}runtime_physical_volume_smoke.gd",
        f"{VALIDATION}structural_rebuild_collision_query_smoke.gd",
        f"{VALIDATION}structural_rebuild_candidate_nav_smoke.gd",
        f"{VALIDATION}structural_wrapper_collision_footprint_smoke.gd",
        "tools/run_r10a_docking_smokes.py", "tests/test_r10a_docking_runner.py",
        f"{VALIDATION}r10a_dock_endpoint_contract_smoke.gd",
        f"{VALIDATION}r10a_dock_traversal_smoke.gd",
        f"{VALIDATION}r10a_ceiling_clearance_smoke.gd",
        f"{VALIDATION}canonical_opening_smoke.gd",
        f"{VALIDATION}docking_manager_smoke.gd", f"{VALIDATION}dock_ports_smoke.gd",
        f"{VALIDATION}boot_dock_aligned_smoke.gd", f"{VALIDATION}occupancy_flip_smoke.gd",
        f"{VALIDATION}physical_travel_smoke.gd", f"{VALIDATION}docking_persistence_smoke.gd",
        f"{VALIDATION}combat_persistence_smoke.gd",
        f"{VALIDATION}save_migration_world_smoke.gd",
        f"{VALIDATION}save_migration_service_smoke.gd",
        f"{VALIDATION}r10a_run7_save_transition_smoke.gd",
        f"{VALIDATION}r10a_world7_snapshot_smoke.gd",
        "scripts/systems/world_v6_layout_projection.gd",
        "data/migrations/world_v6_geometry_authority_v1.json",
        f"{VALIDATION}r10a_world6_layout_projection_smoke.gd",
        "scripts/systems/world_v6_integrity_projection.gd",
        f"{VALIDATION}r10a_world6_integrity_projection_smoke.gd",
        f"{VALIDATION}save_load_service_smoke.gd",
        f"{VALIDATION}ship_mod_run_snapshot_smoke.gd",
        f"{VALIDATION}pillar_persistence_smoke.gd",
        f"{VALIDATION}world_snapshot_smoke.gd",
        f"{VALIDATION}hallucination_director_smoke.gd",
        f"{VALIDATION}fc_p09_natural_route_smoke.gd",
        "tests/fixtures/feature_completion/p10_run_v7_future.json",
        "tests/fixtures/feature_completion/p10_world_v7_future.json",
        "tests/fixtures/feature_completion/p10_run_v8_future.json",
        "tests/fixtures/feature_completion/p10_world_v8_future.json",
    ],
    "P18": [
        "scripts/procgen/structural_rebuild_applier.gd", "scripts/procgen/generated_ship_loader.gd",
        "scripts/procgen/slice_atmosphere_applier.gd", "scripts/systems/module_integrity_consequences.gd",
        "scripts/systems/ship_nav_graph.gd", "scripts/systems/structural_rebuild_state.gd",
        "scripts/systems/ship_work_transaction.gd",
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
        "docs/game/06_validation_plan.md",
        "tools/run_canonical_regression.py",
        "tests/test_run_canonical_regression.py",
        "tools/synaptic_sea_gate4_regression.sh",
        "docs/game/adr/0060-meshy-offline-evidence-rebind.md",
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
    "P09": ["fc_p09_natural_route_smoke.gd", "recipe_resource_smoke.gd", "recipe_picker_panel_smoke.gd"],
    "P10": [
        "fc_p13_smoke.gd", "save_migration_service_smoke.gd",
        "save_migration_world_smoke.gd", "save_load_service_smoke.gd",
        "world_snapshot_smoke.gd", "world_save_service_smoke.gd",
        "ship_mod_run_snapshot_smoke.gd", "electrical_arc_state_smoke.gd",
        "combat_persistence_smoke.gd",
        "ship_generator_smoke.gd", "main_playable_quicksave_smoke.gd",
        "main_playable_meta_autosave_smoke.gd", "title_save_query_smoke.gd",
        "title_load_failure_smoke.gd",
    ],
    "P11": ["component_slot_population_smoke.gd", "component_system_link_smoke.gd", "ship_modification_panel_smoke.gd", "ship_modification_smoke.gd"],
    "P12": ["repair_unification_smoke.gd", "repair_blocked_consume_smoke.gd", "work_action_driver_smoke.gd", "component_mount_dismount_smoke.gd"],
    "P13": ["component_mount_interact_away_smoke.gd", "ship_mod_inventory_sync_away_smoke.gd", "component_remount_sfx_live_away_smoke.gd", "pillar_revisit_persistence_smoke.gd"],
    "P14": [
        "fc_p14_smoke.gd", "ship_mod_overbudget_power_smoke.gd",
        "ship_mod_station_tier_away_smoke.gd", "ship_mod_run_snapshot_smoke.gd",
    ],
    "P15": ["repair_loop_smoke.gd", "module_integrity_consequences_smoke.gd", "ship_mod_plating_repair_away_smoke.gd"],
    "P16": ["module_integrity_smoke.gd", "nav_solid_edges_smoke.gd"],
    "P17": [
        "runtime_physical_volume_smoke.gd",
        "structural_rebuild_collision_query_smoke.gd",
        "structural_rebuild_candidate_nav_smoke.gd",
    ],
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


def _require_exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    assert actual == expected, (
        f"{label} keys mismatch; missing={sorted(expected - actual)} "
        f"unexpected={sorted(actual - expected)}"
    )


def _natural_requirement_criterion_id(requirement_id: str, criterion: str) -> str:
    return f"{requirement_id}::acceptance-{_digest(requirement_id, criterion)[:12]}"


def _natural_feature_criterion_id(source_path: str, heading: str, criterion: str) -> str:
    return f"FEATURE::{source_path}::{_digest(source_path, heading, criterion)[:12]}"


def _load_reviewed_supersessions(root: Path) -> dict[str, Any]:
    path = root / SUPERSESSIONS_REL
    if not path.exists():
        return {
            "schema_version": SUPERSESSIONS_SCHEMA,
            "program": "crafting-derelict-feature-completion",
            "reviewed_supersessions": [],
            "source_present": False,
        }
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise AssertionError(f"invalid reviewed supersession JSON: {error}") from error
    assert isinstance(document, dict), "reviewed supersession document must be an object"
    _require_exact_keys(
        document,
        {"schema_version", "program", "reviewed_supersessions"},
        "reviewed supersession document",
    )
    assert document["schema_version"] == SUPERSESSIONS_SCHEMA, "unexpected reviewed supersession schema"
    assert document["program"] == "crafting-derelict-feature-completion", "reviewed supersession program mismatch"
    rows = document["reviewed_supersessions"]
    assert isinstance(rows, list), "reviewed supersessions must be an array"
    stable_ids: list[str] = []
    replacement_ids: list[str] = []
    normalized_rows: list[dict[str, Any]] = []
    for index, raw in enumerate(rows):
        label = f"reviewed supersession[{index}]"
        assert isinstance(raw, dict), f"{label} must be an object"
        _require_exact_keys(
            raw,
            {
                "stable_criterion_id", "source", "original", "replacement",
                "review", "accounting",
            },
            label,
        )
        source = raw["source"]
        original = raw["original"]
        replacement = raw["replacement"]
        review = raw["review"]
        accounting = raw["accounting"]
        for child, keys in (
            (source, {"path", "heading"}),
            (original, {"criterion", "natural_id", "criterion_fingerprint"}),
            (replacement, {"criterion", "natural_id", "criterion_fingerprint"}),
            (review, {"status", "adr", "reviewer", "reviewed_on"}),
            (
                accounting,
                {
                    "metric_disposition", "acceptance_kind", "deferred",
                    "counts_toward_proposed_denominator", "representative_id",
                    "denominator_delta",
                },
            ),
        ):
            assert isinstance(child, dict), f"{label} contains a non-object section"
            _require_exact_keys(child, keys, label)
        stable_id = raw["stable_criterion_id"]
        source_path = source["path"]
        heading = source["heading"]
        assert all(isinstance(value, str) and value for value in (stable_id, source_path, heading)), (
            f"{label} identity fields must be nonempty strings"
        )
        is_requirement = source_path == REQUIREMENTS_REL.as_posix()
        is_allowlisted_feature = heading in REVIEWED_FEATURE_SUPERSESSION_SOURCES.get(source_path, set())
        assert is_requirement or is_allowlisted_feature, (
            f"{label} source path/heading is not an approved supersession source"
        )
        if is_requirement:
            assert re.fullmatch(r"REQ-[A-Z0-9-]+", heading), f"{label} source heading is not a requirement ID"
            assert stable_id.startswith(f"{heading}::acceptance-"), f"{label} stable ID crosses requirement scope"
        else:
            assert stable_id.startswith(f"FEATURE::{source_path}::"), f"{label} stable ID crosses feature scope"
        for side_name, side in (("original", original), ("replacement", replacement)):
            assert all(isinstance(side[key], str) and side[key] for key in side), (
                f"{label} {side_name} fields must be nonempty strings"
            )
            normalized_criterion = _clean_markdown(side["criterion"]) if is_requirement else side["criterion"]
            expected_id = (
                _natural_requirement_criterion_id(heading, normalized_criterion)
                if is_requirement
                else _natural_feature_criterion_id(source_path, heading, normalized_criterion)
            )
            expected_fingerprint = _digest(source_path, heading, normalized_criterion)
            assert side["natural_id"] == expected_id, f"{label} {side_name} natural ID mismatch"
            assert side["criterion_fingerprint"] == expected_fingerprint, (
                f"{label} {side_name} criterion fingerprint mismatch"
            )
        assert stable_id == original["natural_id"], f"{label} stable ID must preserve the original natural ID"
        assert original["criterion"] != replacement["criterion"], f"{label} does not change criterion text"
        assert original["natural_id"] != replacement["natural_id"], f"{label} does not change natural ID"
        assert review["status"] == "accepted", f"{label} is not accepted"
        assert review["reviewer"] == "root_coordinator", f"{label} reviewer is not authoritative"
        assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", review["reviewed_on"]), f"{label} review date is invalid"
        assert isinstance(review["adr"], str) and review["adr"], f"{label} ADR is missing"
        assert (root / review["adr"]).is_file(), f"{label} ADR does not exist"
        assert accounting["metric_disposition"] == "one_for_one_active_leaf", (
            f"{label} has unsupported metric disposition"
        )
        assert accounting["acceptance_kind"] == ("requirement" if is_requirement else "feature"), (
            f"{label} changes acceptance kind"
        )
        assert accounting["deferred"] is False, f"{label} changes deferred accounting"
        assert accounting["counts_toward_proposed_denominator"] is True, (
            f"{label} excludes the replacement from the denominator"
        )
        assert accounting["representative_id"] == stable_id, f"{label} changes metric representative"
        assert type(accounting["denominator_delta"]) is int and accounting["denominator_delta"] == 0, (
            f"{label} changes the frozen denominator"
        )
        stable_ids.append(stable_id)
        replacement_ids.append(replacement["natural_id"])
        normalized_rows.append(raw)
    assert len(stable_ids) == len(set(stable_ids)), "duplicate reviewed supersession stable IDs"
    assert len(replacement_ids) == len(set(replacement_ids)), "duplicate reviewed supersession replacement IDs"
    graph = {
        row["stable_criterion_id"]: row["replacement"]["natural_id"]
        for row in normalized_rows
    }
    for start in graph:
        visiting: set[str] = set()
        current = start
        while current in graph:
            assert current not in visiting, "cyclic reviewed criterion supersession mapping"
            visiting.add(current)
            current = graph[current]
    assert not (set(stable_ids) & set(replacement_ids)), (
        "chained reviewed criterion supersessions require a new reviewed schema"
    )
    return {
        "schema_version": document["schema_version"],
        "program": document["program"],
        "reviewed_supersessions": normalized_rows,
        "source_present": True,
    }


def _apply_reviewed_supersessions(
    criteria: list[dict[str, Any]],
    coverage: list[dict[str, Any]],
    supersessions: list[dict[str, Any]],
) -> None:
    by_id = {entry["id"]: entry for entry in criteria}
    assert len(by_id) == len(criteria), "duplicate natural criterion IDs before supersession review"
    for mapping in supersessions:
        stable_id = mapping["stable_criterion_id"]
        replacement_id = mapping["replacement"]["natural_id"]
        assert stable_id not in by_id, f"reviewed supersession original still present: {stable_id}"
        assert replacement_id in by_id, f"reviewed supersession target missing: {replacement_id}"
        entry = by_id.pop(replacement_id)
        assert entry["source"]["path"] == mapping["source"]["path"], (
            f"reviewed supersession source path mismatch: {stable_id}"
        )
        assert entry["source"]["heading"] == mapping["source"]["heading"], (
            f"reviewed supersession source heading mismatch: {stable_id}"
        )
        assert entry["criterion"] == mapping["replacement"]["criterion"], (
            f"reviewed supersession replacement text mismatch: {stable_id}"
        )
        assert entry["criterion_fingerprint"] == mapping["replacement"]["criterion_fingerprint"], (
            f"reviewed supersession replacement fingerprint mismatch: {stable_id}"
        )
        accounting = mapping["accounting"]
        assert entry["acceptance_kind"] == accounting["acceptance_kind"], (
            f"reviewed supersession acceptance kind drift: {stable_id}"
        )
        assert entry["deferred"] is accounting["deferred"], (
            f"reviewed supersession deferred accounting drift: {stable_id}"
        )
        entry["id"] = stable_id
        entry["criterion_supersession"] = {
            "mapping_path": SUPERSESSIONS_REL.as_posix(),
            "stable_criterion_id": stable_id,
            "replacement_natural_id": replacement_id,
        }
        by_id[stable_id] = entry
        matched_coverage = 0
        for item in coverage:
            if item["criterion_ids"] == [replacement_id]:
                item["criterion_ids"] = [stable_id]
                matched_coverage += 1
        assert matched_coverage == 1, f"reviewed supersession coverage mismatch: {stable_id}"


def _supersession_set_fingerprint(supersessions: Iterable[dict[str, Any]]) -> str:
    payload = json.dumps(
        list(supersessions),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _validate_supersession_metric_contract(
    criteria: list[dict[str, Any]],
    supersessions: Iterable[dict[str, Any]],
) -> None:
    by_id = {entry["id"]: entry for entry in criteria}
    for mapping in supersessions:
        stable_id = mapping["stable_criterion_id"]
        assert stable_id in by_id, f"reviewed supersession stable row missing: {stable_id}"
        entry = by_id[stable_id]
        accounting = mapping["accounting"]
        equivalence = entry.get("metric_equivalence", {})
        assert entry["acceptance_kind"] == accounting["acceptance_kind"], (
            f"reviewed supersession acceptance kind drift: {stable_id}"
        )
        assert entry["deferred"] is accounting["deferred"], (
            f"reviewed supersession deferred accounting drift: {stable_id}"
        )
        assert equivalence.get("counts_toward_proposed_denominator") is accounting["counts_toward_proposed_denominator"], (
            f"reviewed supersession denominator membership drift: {stable_id}"
        )
        assert equivalence.get("representative_id") == accounting["representative_id"], (
            f"reviewed supersession representative drift: {stable_id}"
        )


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


def _document_status_declarations(lines: list[str]) -> list[str]:
    declarations: list[str] = []
    for line in lines:
        match = re.match(r"^(?:-\s+)?(?:\*\*)?Status:(?:\*\*)?\s*(.+)$", line)
        if match:
            declarations.append(re.sub(r"\*", "", match.group(1)).strip())
    for index, line in enumerate(lines):
        if re.match(r"^#{1,6}\s+Status\s*$", line, re.IGNORECASE):
            for value in lines[index + 1:]:
                if value.strip():
                    declarations.append(re.sub(r"^[*-]\s+|\*", "", value).strip())
                    break
    return declarations


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


def _feature_raw_leaves(lines: list[str]) -> list[tuple[int, str, str, str | None]]:
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
    return [unique_by_anchor[index] for index in sorted(unique_by_anchor)]


def _reviewed_out_of_scope_proposals(root: Path) -> list[dict[str, Any]]:
    catalog: list[dict[str, Any]] = []
    for relative, review in REVIEWED_OUT_OF_SCOPE_PROPOSALS.items():
        path = root / relative
        assert path.is_file(), f"catalogued out-of-scope proposal is missing: {relative}"
        lines = path.read_text(encoding="utf-8").splitlines()
        status_declarations = _document_status_declarations(lines)
        assert len(status_declarations) == 1, (
            f"catalogued out-of-scope proposal status declarations must be singular: {relative}"
        )
        status = status_declarations[0]
        assert status == review["required_status"], (
            f"catalogued out-of-scope proposal status is not reviewable planning-only: {relative}"
        )
        leaves = _feature_raw_leaves(lines)
        expected_count = review["expected_leaf_count"]
        assert len(leaves) == expected_count, (
            f"catalogued out-of-scope proposal leaf count drift: {relative} "
            f"expected {expected_count}, found {len(leaves)}"
        )
        catalog.append({
            "path": relative,
            "disposition": review["disposition"],
            "actual_status": status,
            "reason": review["reason"],
            "extracted_leaf_count": len(leaves),
        })
    return catalog


def _extract_feature_sources(
    root: Path,
    excluded_proposal_paths: set[str] | None = None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    excluded_proposal_paths = excluded_proposal_paths or set()
    criteria: list[dict[str, Any]] = []
    sources: list[dict[str, Any]] = []
    coverage: list[dict[str, Any]] = []
    blockers: list[str] = []
    for path in sorted((root / FEATURES_REL).glob("*.md")):
        relative = path.relative_to(root).as_posix()
        if relative in excluded_proposal_paths:
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        if path.name == "feature_spec_template.md":
            sources.append({"path": relative, "kind": "template", "assessment": "excluded_template", "acceptance_leaf_count": 0})
            continue
        sections = _acceptance_sections(lines)
        inline = [index for index, line in enumerate(lines) if re.match(r"^\s*- Acceptance criteria:\s*$", line)]
        raw_leaves = _feature_raw_leaves(lines)
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
    supersessions: Iterable[dict[str, Any]] = (),
) -> str:
    supersessions_by_id = {
        row["stable_criterion_id"]: row
        for row in supersessions
    }
    normalized_criteria: list[dict[str, Any]] = []
    for entry in sorted(criteria, key=lambda item: item["id"]):
        fingerprint = entry["criterion_fingerprint"]
        mapping = supersessions_by_id.get(entry["id"])
        if mapping is not None:
            assert entry["criterion"] == mapping["replacement"]["criterion"], (
                f"reviewed supersession scope text mismatch: {entry['id']}"
            )
            assert fingerprint == mapping["replacement"]["criterion_fingerprint"], (
                f"reviewed supersession scope fingerprint mismatch: {entry['id']}"
            )
            assert entry.get("criterion_supersession", {}).get("replacement_natural_id") == mapping["replacement"]["natural_id"], (
                f"reviewed supersession scope annotation mismatch: {entry['id']}"
            )
            fingerprint = mapping["original"]["criterion_fingerprint"]
        normalized_criteria.append({
            "id": entry["id"],
            "fingerprint": fingerprint,
            "deferred": entry["deferred"],
            "kind": entry["acceptance_kind"],
            "metric_equivalence": entry["metric_equivalence"],
        })
    contract = {
        "criteria": normalized_criteria,
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
    supersession_document = _load_reviewed_supersessions(root)
    supersessions = supersession_document["reviewed_supersessions"]
    if root.resolve() == ROOT.resolve():
        assert supersession_document["source_present"], "reviewed supersession registry is missing"
    supersession_set_fingerprint = _supersession_set_fingerprint(supersessions)
    requirements, requirement_source, requirement_coverage, requirement_blockers = _extract_requirements(root)
    requirement_supersessions = [
        mapping for mapping in supersessions
        if mapping["source"]["path"] == REQUIREMENTS_REL.as_posix()
    ]
    feature_supersessions = [
        mapping for mapping in supersessions
        if mapping["source"]["path"] != REQUIREMENTS_REL.as_posix()
    ]
    _apply_reviewed_supersessions(requirements, requirement_coverage, requirement_supersessions)
    out_of_scope_proposals = _reviewed_out_of_scope_proposals(root)
    excluded_proposal_paths = {entry["path"] for entry in out_of_scope_proposals}
    features, feature_sources, feature_coverage, feature_blockers = _extract_feature_sources(root, excluded_proposal_paths)
    _apply_reviewed_supersessions(features, feature_coverage, feature_supersessions)
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
        same_supersession = (
            "criterion_supersession" not in entry
            or previous is not None
            and previous.get("criterion_supersession") == entry["criterion_supersession"]
        )
        if (
            previous
            and previous.get("criterion_fingerprint") == entry["criterion_fingerprint"]
            and same_supersession
            and _valid_evidence(previous.get("evidence"))
        ):
            entry["evidence"] = previous["evidence"]

    blockers = sorted(set(requirement_blockers + feature_blockers))
    duplicate_review = _apply_reviewed_equivalence(criteria)
    _validate_supersession_metric_contract(criteria, supersessions)
    source_documents = [requirement_source, *feature_sources]
    scope_fingerprint = _scope_contract_fingerprint(criteria, source_documents, supersessions)
    if frozen_scope_contract is not None:
        assert isinstance(frozen_scope_contract, dict), "invalid frozen scope contract"
        assert not blockers, "cannot freeze scope with source mapping blockers"
        if supersessions or "reviewed_supersession_set_fingerprint" in frozen_scope_contract:
            assert frozen_scope_contract.get("reviewed_supersession_set_fingerprint") == supersession_set_fingerprint, (
                "reviewed supersession set drift; coordinator review is required before regeneration"
            )
        assert frozen_scope_contract.get("source_leaf_set_fingerprint") == scope_fingerprint, (
            "frozen scope drift; coordinator review is required before regeneration"
        )
    active = [entry for entry in criteria if not entry["deferred"]]
    proposed_metric_criteria = [
        entry
        for entry in active
        if entry["metric_equivalence"]["counts_toward_proposed_denominator"]
    ]
    promoted_evidence_counts = {
        "implemented": sum(entry["evidence"]["implemented"] for entry in proposed_metric_criteria),
        "production_reachable": sum(entry["evidence"]["production_reachable"] for entry in proposed_metric_criteria),
        "freshly_validated": sum(entry["evidence"]["fresh_validation"] for entry in proposed_metric_criteria),
        "player_accepted": sum(entry["evidence"]["player_accepted"] for entry in proposed_metric_criteria),
        "accepted": sum(entry["evidence"]["state"] == "accepted" for entry in proposed_metric_criteria),
    }
    mapped_criteria = [
        entry for entry in proposed_metric_criteria
        if entry["evidence"]["state"] != "not_verified" and bool(entry["evidence"]["refs"])
    ]
    # The source scope is frozen, but incomplete criterion mapping is unknown
    # coverage, not an assertion that the product has zero implementation.
    evidence_mapping = {
        "status": "complete" if len(mapped_criteria) == len(proposed_metric_criteria) else "incomplete",
        "mapped_criteria": len(mapped_criteria),
        "unknown_criteria": len(proposed_metric_criteria) - len(mapped_criteria),
        "coverage_percent": round(len(mapped_criteria) * 100 / len(proposed_metric_criteria), 2) if proposed_metric_criteria else None,
        "definition": "Only reviewed criterion-level evidence mappings count as coverage; historical status and standalone/helper PASS output do not create one.",
    }
    scope_frozen = dict(frozen_scope_contract) if frozen_scope_contract is not None else None
    percentages = (
        {
            "implemented": round(promoted_evidence_counts["implemented"] * 100 / len(proposed_metric_criteria), 2) if evidence_mapping["status"] == "complete" and proposed_metric_criteria else None,
            "validated": round(promoted_evidence_counts["freshly_validated"] * 100 / len(proposed_metric_criteria), 2) if evidence_mapping["status"] == "complete" and proposed_metric_criteria else None,
            "accepted": round(promoted_evidence_counts["accepted"] * 100 / len(proposed_metric_criteria), 2) if evidence_mapping["status"] == "complete" and proposed_metric_criteria else None,
        }
        if scope_frozen is not None and evidence_mapping["status"] == "complete"
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
        "criterion_supersession_source": {
            "path": SUPERSESSIONS_REL.as_posix(),
            "schema_version": supersession_document["schema_version"],
            "source_present": supersession_document["source_present"],
            "reviewed_mapping_count": len(supersessions),
            "reviewed_mapping_fingerprint": supersession_set_fingerprint,
        },
        "criterion_supersession_review": supersessions,
        "reviewed_out_of_scope_proposals": out_of_scope_proposals,
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
            "implemented": promoted_evidence_counts["implemented"] if evidence_mapping["status"] == "complete" else None,
            "production_reachable": promoted_evidence_counts["production_reachable"] if evidence_mapping["status"] == "complete" else None,
            "freshly_validated": promoted_evidence_counts["freshly_validated"] if evidence_mapping["status"] == "complete" else None,
            "player_accepted": promoted_evidence_counts["player_accepted"] if evidence_mapping["status"] == "complete" else None,
            "accepted": promoted_evidence_counts["accepted"] if evidence_mapping["status"] == "complete" else None,
            "promoted_evidence_counts": promoted_evidence_counts,
            "evidence_mapping": evidence_mapping,
            "unassessed_source_count": len(blockers),
            "metric_blockers": blockers,
            "percentages": percentages,
            "definition": (
                "Implementation, reachability, validation, and acceptance totals remain unknown until criterion-level evidence mapping is reviewed. promoted_evidence_counts records only explicit registry promotion, not product completion."
                if scope_frozen is not None
                else "Percentages remain null until coordinator review freezes the source leaves and exact-text equivalence map; historical status is provenance, not execution evidence."
            ),
        },
        "migration_contract": {
            "reserved_run_version": "gate2-current-run-5",
            "reserved_world_version": "world-5",
            "implemented": False,
            "reservation_status": "historical ADR-0059 pre-P10 reservation metadata",
            "current_run_version": "gate2-current-run-6",
            "current_world_version": "world-6",
            "current_combat_version": "threat-manager-2",
            "r02_implemented": True,
            "r02_historical_world_run_pairs": {
                "world-1": ["gate2-current-run-1"],
                "world-2": ["gate2-current-run-1"],
                "world-3": ["gate2-current-run-1"],
                "world-4": [
                    "gate2-current-run-1", "gate2-current-run-3",
                    "gate2-current-run-4",
                ],
                "world-5": ["gate2-current-run-5"],
                "world-6": ["gate2-current-run-6"],
            },
            "r02_home_bootstrap_profiles": [
                "default_seed_000017", "coherent_ship_001",
                "coherent_ship_002",
            ],
            "r02_active_away_anchor_policy": {
                "canonical_restore_authority": "activate_derelict_then_attach_at_dock_offset_then_apply_docking_snapshot",
                "stationary_current_host": "require_host_current_location_edge_with_known_non_active_mobile_then_use_canonical_restore_anchor",
                "missing_host_witness": "reject_unreconstructable_historical_anchor",
                "active_mobile_edge": "reject_unreconstructable_historical_anchor",
            },
            "r02_last_attack_result_variants": {
                "empty": "exact_empty_dictionary",
                "incoming_damage": "ThreatManager.tick->DamagePipeline.apply_to_vitals",
                "weapon_hit": "ThreatManager.attack_with_weapon->DamagePipeline.apply_to_threat",
                "validation": "exact_keys_and_types_no_coercion",
            },
            "r02_focused_user_isolation": [
                "APPDATA", "LOCALAPPDATA", "GODOT_USER_PATH", "XDG_DATA_HOME",
            ],
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
    if card_id in {"P11", "P12", "P13"}:
        checks.append(_check(
            "& $Python -m pytest -q tests/test_physical_work_runner.py",
            "passed",
            forbid_diagnostics=False,
        ))
        checks.append(_check(
            "& $Python tools/run_physical_work_smokes.py "
            f"--godot $Godot --group {card_id} --evidence-dir artifacts/feature-completion/R06-{card_id}-focused",
            f"R06 {card_id} FOCUSED PASS cases={len(CARD_SMOKES[card_id])}",
        ))
        if card_id == "P13":
            checks.append(_check(
                "& $Python tools/run_feature_completion.py --godot $Godot --case P10 --evidence-dir artifacts/feature-completion/R06-P10-relocation-reload",
                "FC P10 PASS",
            ))
    else:
        for filename in CARD_SMOKES.get(card_id, []):
            checks.append(_check(
                f"& $Godot --headless --path . --script res://scripts/validation/{filename}",
                _smoke_marker(root, filename),
            ))
    if card_id == "P09":
        checks.append(_check("& $Python -m unittest tests.test_crafting_economy", "OK", forbid_diagnostics=False))
    if card_id == "P10":
        checks.append(_check(
            "& $Python -m pytest -q tests/test_p10_process_runner.py tests/test_feature_completion_runner.py",
            "passed",
            forbid_diagnostics=False,
        ))
        checks.append(_check(
            "& $Python tools/run_p10_process_smoke.py --godot $Godot --root . --evidence-dir artifacts/feature-completion/P10-process",
            "FC P10 PROCESS PASS",
        ))
    if card_id == "P17":
        checks.extend([
            _check(
                "& $Python tools/run_r10a_docking_smokes.py --godot $Godot --root . --evidence-dir artifacts/feature-completion/R10-A",
                "R10-A DOCKING PREREQUISITE PASS",
            ),
            _check("& $Python -m unittest tests.test_structural_rebuild_catalog", "OK", forbid_diagnostics=False),
            _check("& $Python -m unittest tests.test_runtime_physical_volume_catalog", "OK", forbid_diagnostics=False),
            _check("bash tools/classify_orphan_smokes.sh --check", "ORPHAN CLASSIFICATION CHECK PASS", forbid_diagnostics=False),
        ])
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
            "scope_decisions_pending": CARD_SCOPE_DECISIONS.get(card_id, []),
            "non_goals": CARD_NON_GOALS[card_id],
            **R06_CARD_METADATA.get(card_id, {}),
            **({"contract": CARD_CONTRACTS[card_id]} if card_id in CARD_CONTRACTS else {}),
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
    supersession_document = _load_reviewed_supersessions(root)
    supersessions = supersession_document["reviewed_supersessions"]
    out_of_scope_proposals = _reviewed_out_of_scope_proposals(root)
    assert registry["schema_version"] == "feature-acceptance-v5", "unexpected acceptance schema"
    identifiers = [entry["id"] for entry in registry["criteria"]]
    assert len(identifiers) == len(set(identifiers)), "duplicate criterion IDs"
    assert len([identifier for identifier in identifiers if re.fullmatch(r"FC-\d{2}", identifier)]) == 24, "missing FC criterion"
    if root.resolve() == ROOT.resolve():
        assert len([identifier for identifier in identifiers if identifier.startswith("REQ-")]) >= 130, "requirement acceptance leaves not represented"
    assert registry["accounting"]["recorded"] == len(registry["criteria"]), "recorded denominator mismatch"
    assert registry["accounting"]["active"] + registry["accounting"]["deferred"] == len(registry["criteria"]), "active/deferred accounting mismatch"
    assert registry.get("criterion_supersession_source") == {
        "path": SUPERSESSIONS_REL.as_posix(),
        "schema_version": supersession_document["schema_version"],
        "source_present": supersession_document["source_present"],
        "reviewed_mapping_count": len(supersessions),
        "reviewed_mapping_fingerprint": _supersession_set_fingerprint(supersessions),
    }, "reviewed supersession source metadata mismatch"
    assert registry.get("criterion_supersession_review") == supersessions, (
        "reviewed supersession history mismatch"
    )
    excluded_proposal_paths = {entry["path"] for entry in out_of_scope_proposals}
    assert registry.get("reviewed_out_of_scope_proposals") == out_of_scope_proposals, (
        "reviewed out-of-scope proposal catalog mismatch"
    )
    expected_source_paths = {REQUIREMENTS_REL.as_posix()} | {
        path.relative_to(root).as_posix() for path in (root / FEATURES_REL).glob("*.md")
        if path.relative_to(root).as_posix() not in excluded_proposal_paths
    }
    actual_source_paths = [entry["path"] for entry in registry["source_documents"]]
    assert len(actual_source_paths) == len(set(actual_source_paths)), "duplicate source document accounting"
    assert set(actual_source_paths) == expected_source_paths, "source document inventory is incomplete or stale"
    assert not any(entry["source"]["path"] in excluded_proposal_paths for entry in registry["criteria"]), (
        "catalogued out-of-scope proposal emitted acceptance criteria"
    )
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
    expected_superseded_ids: set[str] = set()
    for mapping in supersessions:
        stable_id = mapping["stable_criterion_id"]
        replacement_id = mapping["replacement"]["natural_id"]
        expected_superseded_ids.add(stable_id)
        assert stable_id in entries_by_id, f"reviewed supersession stable row missing: {stable_id}"
        assert replacement_id not in entries_by_id, f"reviewed supersession emitted an extra replacement row: {stable_id}"
        entry = entries_by_id[stable_id]
        assert entry["criterion"] == mapping["replacement"]["criterion"], (
            f"reviewed supersession current text mismatch: {stable_id}"
        )
        assert entry["criterion_fingerprint"] == mapping["replacement"]["criterion_fingerprint"], (
            f"reviewed supersession current fingerprint mismatch: {stable_id}"
        )
        assert entry.get("criterion_supersession") == {
            "mapping_path": SUPERSESSIONS_REL.as_posix(),
            "stable_criterion_id": stable_id,
            "replacement_natural_id": replacement_id,
        }, f"reviewed supersession row annotation mismatch: {stable_id}"
        accounting = mapping["accounting"]
        equivalence = entry["metric_equivalence"]
        assert entry["acceptance_kind"] == accounting["acceptance_kind"], (
            f"reviewed supersession acceptance kind mismatch: {stable_id}"
        )
        assert entry["deferred"] is accounting["deferred"], (
            f"reviewed supersession deferred accounting mismatch: {stable_id}"
        )
        assert equivalence["counts_toward_proposed_denominator"] is accounting["counts_toward_proposed_denominator"], (
            f"reviewed supersession denominator membership mismatch: {stable_id}"
        )
        assert equivalence["representative_id"] == accounting["representative_id"], (
            f"reviewed supersession representative mismatch: {stable_id}"
        )
    annotated_ids = {
        entry["id"]
        for entry in registry["criteria"]
        if "criterion_supersession" in entry
    }
    assert annotated_ids == expected_superseded_ids, "unreviewed criterion supersession annotation"
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
        registry["criteria"], registry["source_documents"], supersessions
    ), "scope-freeze candidate fingerprint mismatch"
    assert candidate["source_row_count"] == len(registry["criteria"]), "scope-freeze candidate row count mismatch"
    assert candidate["proposed_active_denominator"] == proposed_count, "scope-freeze candidate denominator mismatch"
    if registry["scope_frozen"] is None:
        expected_review_status = "incomplete_source_mapping" if registry["accounting"]["metric_blockers"] else "ready_for_final_scope_review"
        assert registry["scope_review"]["status"] == expected_review_status, "unfrozen scope lacks review state"
        assert all(value is None for value in registry["accounting"]["percentages"].values()), "unfrozen denominator published percentages"
    else:
        assert registry["scope_frozen"]["source_leaf_set_fingerprint"] == candidate["source_leaf_set_fingerprint"], "frozen scope fingerprint mismatch"
        if supersessions:
            assert registry["scope_frozen"].get("reviewed_supersession_set_fingerprint") == _supersession_set_fingerprint(supersessions), (
                "frozen reviewed supersession set fingerprint mismatch"
            )
        assert registry["scope_review"]["status"] == "frozen", "frozen scope review state mismatch"
    if registry["accounting"]["metric_blockers"]:
        assert all(value is None for value in registry["accounting"]["percentages"].values()), "incomplete denominator published percentages"
    evidence_mapping = registry["accounting"].get("evidence_mapping", {})
    proposed_metric_criteria = [
        entry for entry in registry["criteria"]
        if not entry["deferred"] and entry["metric_equivalence"]["counts_toward_proposed_denominator"]
    ]
    expected_mapped_criteria = [
        entry for entry in registry["criteria"]
        if not entry["deferred"]
        and entry["metric_equivalence"]["counts_toward_proposed_denominator"]
        and entry["evidence"]["state"] != "not_verified"
        and bool(entry["evidence"]["refs"])
    ]
    expected_promoted_evidence_counts = {
        "implemented": sum(entry["evidence"]["implemented"] for entry in proposed_metric_criteria),
        "production_reachable": sum(entry["evidence"]["production_reachable"] for entry in proposed_metric_criteria),
        "freshly_validated": sum(entry["evidence"]["fresh_validation"] for entry in proposed_metric_criteria),
        "player_accepted": sum(entry["evidence"]["player_accepted"] for entry in proposed_metric_criteria),
        "accepted": sum(entry["evidence"]["state"] == "accepted" for entry in proposed_metric_criteria),
    }
    assert evidence_mapping.get("mapped_criteria") == len(expected_mapped_criteria), "evidence mapping count mismatch"
    assert evidence_mapping.get("unknown_criteria") == proposed_count - len(expected_mapped_criteria), "evidence mapping unknown count mismatch"
    assert registry["accounting"].get("promoted_evidence_counts") == expected_promoted_evidence_counts, "promoted evidence count mismatch"
    if evidence_mapping.get("status") == "incomplete":
        assert all(value is None for value in registry["accounting"]["percentages"].values()), "unreviewed evidence mapping published completion percentages"
        assert all(registry["accounting"][field] is None for field in (
            "implemented", "production_reachable", "freshly_validated", "player_accepted", "accepted"
        )), "unreviewed evidence mapping published completion totals"
    else:
        assert evidence_mapping.get("status") == "complete", "invalid evidence mapping status"
        assert len(expected_mapped_criteria) == proposed_count, "complete evidence mapping has unknown criteria"
        assert all(registry["accounting"][field] == expected_promoted_evidence_counts[field] for field in (
            "implemented", "production_reachable", "freshly_validated", "player_accepted", "accepted"
        )), "complete evidence mapping headline totals mismatch"

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
