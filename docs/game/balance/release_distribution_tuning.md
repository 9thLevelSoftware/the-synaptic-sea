# Release Distribution — Tuning & Defaults

Date: 2026-06-25
Package: Task 13 (Distribution, Store, Achievements, Demo, Localization & Post-Launch Ops)
Source: `docs/game/features/release_distribution.md`, ADR-0029 / 0030 / 0031.

## Scope

This note captures every tunable number / default that ships in
`data/release/*.json` and the runtime services in `scripts/systems/`.
Everything here is data — no magic constants in code.

## Build metadata defaults

`data/release/build_metadata.json` carries:

| Field | Default | Rationale |
|---|---|---|
| `version` | `v0.1.0` | Aligned with the `build_release.sh` stamp. Bumped per release. |
| `build_kind` | `dev` for local runs, `release` for the storefront zip | Set by the release pipeline; the smoke proves the validator catches invalid kinds. |
| `store` | `itch` (default); `steam`, `gog`, `direct` reserved | The storefront stub the build was produced for. |
| `language_defaults` | `["en"]` | Only English at launch; the catalog is the door for adding languages. |
| `achievements_supported` | `true` for `steam` / `gog` builds, `false` for `demo` builds | Steam demo restrictions on achievements are common. |
| `demo_hub_unlocked_features` | `["oxygen_breach", "fire_hazard", "objective_progress"]` | What the demo build lets the player reach. |

## Achievement catalog

Eight achievements at launch (five required by REQ-RL-003):

| id | trigger_event | trigger_target |
|---|---|---|
| `first_breath` | `tool_acquired` | `portable_oxygen_pump` |
| `first_repair` | `repair_consumed` | any |
| `first_loot` | `loot_searched` | any |
| `objective_complete` | `objective_completed` | `objectives[0]` |
| `reactor_stabilized` | `reactor_stabilized` | `reactor` |
| `extracted` | `run_complete` | any |
| `junction_calibrator_used` | `tool_acquired` | `junction_calibrator` |
| `all_systems_restored` | `objective_completed` | `restore_systems` |

Per-run-only: a new run wipes the unlock set (ADR-0007 boundary).

## Localization catalog

English baseline only at launch:

- `oxygen.label`, `breach.sealed`, `breach.open`, `load.label`,
  `achievement.first_breath.name`, `achievement.first_breath.desc`,
  `credits.title`, `credits.dismiss`, `demo.badge`,
  `release.badge`, `dev.badge`.

≥ 10 string ids (REQ-RL-005 says 5; we ship 10 to cover the HUD labels
the smoke and the credits screen actually use).

Unknown id → empty string (or supplied fallback).
Unknown language → default language (`en`).
Missing translation key inside a known language → default language's
text (HUD never goes blank).

## Demo scope manifest

Five demo-restricted features at launch:

| feature_id | reason | hint |
|---|---|---|
| `cargo_hold.full_inventory` | Demo carries reduced cargo slots | Demo: carry up to 6 kg, full build: 30 kg |
| `multi_hazard.run` | Demo uses single-hazard seeds | Demo: 1 hazard, full build: 3 hazards |
| `long_run.persistence` | Demo wipes after 20 minutes | Demo: 20 min cap, full build: unlimited |
| `world_persistence.cross_run` | Demo does not persist world state | Demo: per-run only, full build: ADR-0012 |
| `hub.meta_progression` | Hub/meta is deferred per ADR-0003 | Demo: skip hub, full build: same (Gate 3) |

The gate returns `false` for unknown ids (no silent allow).

## Crash bundle cap

256 entries FIFO. The cap is the `MAX_BUNDLE_ENTRIES` constant in
`crash_report_bundle.gd`. A run that logs thousands of errors before
crashing still produces a bounded bundle that fits in any telemetry
upload.

## Release checklist (post-launch playbook)

12 checks across the three categories:

- **pre_launch (5):** export presets, build metadata, save/load round-trip, achievements smoke, demo scope gate.
- **launch_day (4):** credits screen loads, build manifest on storefront, language defaults list, telemetry endpoint reachable.
- **post_launch (3):** weekly telemetry review, monthly patch cadence, community engagement queue.

`source=external` rows require a non-empty `evidence_path` — the smoke
asserts the rejection so a CI step that forgets to attach a build URL
fails loudly.

## Safe ranges / presets

| Number | Safe range | Default |
|---|---|---|
| Crash bundle cap | 64 – 1024 | 256 |
| Achievement catalog size | 5 – 50 | 8 (at launch) |
| Localization string count | 5 – 500 | 10 (at launch) |
| Demo manifest entries | 0 – 30 | 5 (at launch) |
| Release checklist rows | 5 – 100 | 12 (at launch) |

All values are data-driven; adjusting them is a JSON edit plus a smoke
re-run. No code change.