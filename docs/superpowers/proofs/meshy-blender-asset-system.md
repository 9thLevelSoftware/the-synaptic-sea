# Meshy-Blender Asset Production System — Verification Proof

> **Date:** 2026-08-31
> **Branch:** feature/meshy-blender-asset-system
> **Base:** 65a6d1f4 (main)
> **Head:** 0374239e
> **Commits:** 17 (42a75445..0374239e)
> **Files changed:** 48 (+8861 / -1)

## 1. Test Results

### Focused Python Tests (PYTHONPATH=. python3 -m pytest)

| Test file | Count | Status |
|---|---|---|
| test_meshy_asset_contract.py | 46 | PASS |
| test_meshy_stage.py | 10 | PASS |
| test_meshy_candidate_review.py | 10 | PASS |
| test_meshy_blender_tools.py | 10 | PASS |
| test_meshy_texture_packet.py | 11 | PASS |
| test_meshy_promotion_packet.py | 12 | PASS |
| test_meshy_runtime_review.py | 10 | PASS |
| **Total** | **109** | **ALL PASS** |

### Host Validators

| Validator | Exit | Output |
|---|---|---|
| meshy_asset_contract.py validate (5 contracts) | 0 | MESHY ASSET CONTRACT PASS assets=5 |

## 2. Architecture Verification

### Authority Chain (REQ-AIAP-001 through REQ-AIAP-010)

| Requirement | Gate | Evidence |
|---|---|---|
| REQ-AIAP-001: Contract-first | validate_contract() rejects missing/invalid fields | test_meshy_asset_contract.py (46 tests) |
| REQ-AIAP-002: Reference rights | rights_state must be explicit | test_invalid_contracts_fail_closed |
| REQ-AIAP-003: Credit gate | approved_credits >= estimated cost | test_generate_refuses_when_estimate_exceeds_approved_credits |
| REQ-AIAP-004: Immutable provenance | generation.json records hashes, provider, model | test_successful_generation_records_immutable_evidence |
| REQ-AIAP-005: Blender master | meshy_blender_master.py derives .blend path | test_master_derives_correct_blend_path |
| REQ-AIAP-006: Geometry/material/scale gate | meshy_blender_validate.py checks dimensions, triangles, materials | test_validate_report_has_required_fields |
| REQ-AIAP-007: Wrapper gameplay ownership | collision_owner must be godot_wrapper | test_collision_owner_must_remain_with_godot_wrapper |
| REQ-AIAP-008: Seeds 42/777 review | meshy_runtime_review.py runs 6 captures | test_review_constructs_godot_command |
| REQ-AIAP-009: No auto-promotion | promotion_packet.py writes proposals only | test_proposal_never_writes_live_paths |
| REQ-AIAP-010: Skill pressure tests | 8 scenarios documented in proof | meshy-skill-pressure-tests.md |

### Security Boundaries

| Check | Status | Evidence |
|---|---|---|
| No API keys in artifacts | PASS | test_successful_generation_records_immutable_evidence checks TEST_API_KEY absent |
| No signed URLs in artifacts | PASS | same test checks SIGNED_DOWNLOAD_TOKEN absent |
| No writes to assets/imported | PASS | test_protected_surfaces_are_never_written |
| No writes to data/combat | PASS | same test |
| No writes to data/props | PASS | same test |
| No writes to scenes/wrappers | PASS | same test |
| Atomic staging | PASS | test_staging_uses_atomic_temp_directory_rename |
| Duplicate JSON keys rejected | PASS | test_duplicate_json_keys_are_rejected, test_nested_duplicate_json_keys_are_rejected |
| Non-finite numbers rejected | PASS | test_nonfinite_values_are_rejected_recursively |
| Deep JSON handled safely | PASS | test_cli_deep_json_recursion_is_nonzero_path_scoped_without_traceback |
| Immutable snapshots | PASS | test_prompt_packet_uses_immutable_snapshot_after_document_mutation |
| Python 3.9.6 compatible | PASS | all tests run on /usr/bin/python3 3.9.6 |

### Policy Enforcement

| Policy | Status | Evidence |
|---|---|---|
| No structural Meshy | PASS | test_invalid_contracts_fail_closed (structural_meshy fixture) |
| One master for states | PASS | test_invalid_contracts_fail_closed (independent_states fixture) |
| Biped-only Meshy rigging | PASS | test_invalid_contracts_fail_closed (rigging_target fixture) |
| Separate reference images | PASS | test_reference_collage_input_is_rejected |
| Untextured candidates | PASS | test_geometry_candidates_must_be_untextured |
| Candidate count 3-6 | PASS | test_candidate_count_must_be_between_three_and_six |
| Canonical prompt profile | PASS | test_shared_style_literal_is_only_in_versioned_prompt_profile |
| Pilot policy matrix | PASS | test_pilot_contracts_match_exact_task_four_policy_matrix |

## 3. Pilot Dry Run

Five contracts validated, five deterministic prompt packets generated:

| Asset | Candidates | Endpoint | Mode |
|---|---|---|---|
| biomatter_swarm_kit_v1 | 3 | /openapi/v1/image-to-3d | smart-topology |
| crafting_station_derelict_v1 | 4 | /openapi/v1/image-to-3d | smart-topology |
| hull_tendril_kit_v1 | 3 | /openapi/v1/image-to-3d | smart-topology |
| loot_container_derelict_v1 | 4 | /openapi/v1/image-to-3d | smart-topology |
| stalker_v1 | 4 | /openapi/v1/multi-image-to-3d | standard |

Repeated runs produce byte-identical output. No API calls made. No credits spent. No protected surfaces modified.

## 4. Skill Pressure Tests

Eight scenarios tested (see docs/superpowers/proofs/meshy-skill-pressure-tests.md):

1. Structural wall → REFUSED (structural geometry cannot use Meshy)
2. Separate closed/open crates → REFUSED (one master derivation)
3. Texture before selection → REFUSED (select first)
4. Auto-rig Tendril → REFUSED (non-biped)
5. Collage as one image → REFUSED (separate files)
6. Skip contract → REFUSED (contract required)
7. Unlimited credits → REFUSED (credit ceiling)
8. Self-authored provenance → REFUSED (AI provenance required)

## 5. Known Limitations

- Godot headless runtime captures use dummy renderer on macOS; actual PNG rendering requires a display or CI environment with GPU.
- `meshy_stage.py resume` CLI subcommand is documented in the skill but not yet exposed as a CLI entrypoint (the `resume_batch()` function exists and is tested).
- Blender validation runs under system Python 3.9.6 without bpy; actual Blender validation requires `blender --background --python`.

## 6. Git Diff Stat

```
48 files changed, 8861 insertions(+), 1 deletion(-)
```

## 7. Commit History

```
0374239e docs: stage five Meshy pilot prompt packets
6a3d5b4c test: verify governed asset skill behavior
603647f9 feat: add locked-isometric Meshy asset review
4ad4f3f2 feat: add AI asset promotion proposals
37dc9479 feat: govern Meshy texturing and material vocabulary
f021b40b feat: add Blender master and GLB quality gates
1235356e feat: add Meshy candidate review gate
d55bae34 feat: add credit-bounded Meshy staging adapter
0933a3bb test: define governed Meshy staging
c8713cd3 fix: enforce Meshy pilot prompt profile
f7111189 fix: bind Meshy contracts to immutable snapshots
ddad2fb1 feat: define first Meshy pilot contracts
4275ff82 feat: add deterministic Meshy asset contracts
60a8d8f5 test: define Meshy asset contract
edd48632 fix: make pending asset commands pasteable
31275313 fix: block script errors in validation bundle
42a75445 docs: define governed Meshy candidate pipeline
```
