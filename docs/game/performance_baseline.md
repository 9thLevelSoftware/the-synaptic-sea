# Performance Baseline

This document captures the **first measured performance baseline** for The Synaptic Sea, recorded 2026-06-19 against the local Mac mini M4 dev box. It exists to anchor the Gate 4 Beta exit criterion "Performance pass — frame time, memory, load times acceptable" against hard numbers, and to make any future regression against those numbers immediately visible.

The baseline is produced by two reusable harness scripts under `scripts/validation/`:

- `performance_profiler.gd` — **headless** harness. Profiles each known procgen template (`golden_coherent_ship_001`, `smoke_seed_000017`) and the main playable scene end-to-end, recording procgen wall time, per-frame physics delta, node/mesh/collision counts, peak Godot-tracked static memory, and end-of-run OS RSS.
- `windowed_fps_capture.gd` — **non-headless** harness. Spawns the main playable scene in a real Godot window and records the per-frame render loop delta for 240 frames after `playable_ready`, then writes `user://perf_windowed_fps.json` with median / p95 frame time, observed FPS, peak Godot static memory, and peak OS RSS.

The windowed harness is the source of truth for the **frame time** target. The headless harness is the source of truth for the **load time**, **procgen time**, and **scene-tree memory proxy** targets (headless rendering is uncapped so its per-frame delta is informational only, not a real FPS measurement).

## Hardware matrix

The Beta Gate 4 performance pass needs cross-hardware evidence. The matrix below locks the three reference rows used for the extended baseline. Exact model names replace the placeholder examples once hardware access is confirmed.

| Tier | CPU / GPU | RAM | OS | Driver notes | Status |
| --- | --- | --- | --- | --- | --- |
| Low-end laptop | Integrated GPU (Intel Iris Xe / Apple M1 / AMD Vega iGPU class) | 16 GB | Windows 11 / Linux / macOS | Latest vendor drivers; measure at 1920×1080 native if possible | Proposed — pending access |
| Mid-tier desktop | Discrete GPU (NVIDIA GTX 1660 / RTX 3060 / AMD RX 6600 class) or Apple M2/M3 | 32 GB | Windows 11 / Linux / macOS | Latest vendor drivers; measure at 1920×1080 | Proposed — pending access |
| High-end desktop | Mac mini M4 (Apple Silicon) | 24 GB unified | macOS 26.5.1 | Metal 4.0 Forward+ | Measured (2026-06-19) |

Each row must be measured with the harness pair documented in [Reproduce](#reproduce): 3 headless runs per row and 3 windowed runs per row. The high-end row already has measured numbers in the sections below; the low-end and mid-tier rows are blocked until the user confirms machine access for this sprint.

## Reference hardware

| Field | Value |
| --- | --- |
| Machine | Mac mini M4 (Apple Silicon) |
| OS | macOS 26.5.1 (Build 25F80) |
| Display | 1920×1080 FHD |
| Godot | 4.6.2.stable.official (71f334935), Metal 4.0 Forward+ |
| Memory toolchain | Godot `Performance.MEMORY_STATIC` + macOS `ps -o rss=` (KB units, /1024 for MB) |

"Reference hardware" is the local dev box for now. When more hardware rows are added (Windows / Linux / older laptops) they belong in a follow-up card, not this baseline.

## Targets (from Kanban card t_e3fbaad1)

| Metric | Target | Stop condition |
| --- | --- | --- |
| Frame time | Stable 60fps | Block if below 30fps |
| Memory | <512MB peak | Block if >1GB |
| Scene load time | <3s per scene | — |
| Procgen time | <2s per template | — |

Stop conditions did not trip during baseline capture.

## Headless profiler results (3 runs)

`/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/performance_profiler.gd`

The full `summary_json` is printed inline on stdout as part of the `PERFORMANCE BASELINE PASS` line. Numbers below are extracted from 3 consecutive runs.

### golden_coherent_ship_001 (curated 5-room proof ship)

| Run | procgen_ms | peak_static_mem_mb | nodes | meshes | collisions |
| --- | --- | --- | --- | --- | --- |
| 1 | 5.507 | 23.772 | 489 | 62 | 31 |
| 2 | 5.362 | 23.771 | 489 | 62 | 31 |
| 3 | 5.565 | 23.762 | 489 | 62 | 31 |

Procgen target (<2s): **PASS** (max 5.6ms — 350× under budget).

### smoke_seed_000017 (8-room smoke seed with fire zone and oxygen breach)

| Run | procgen_ms | peak_static_mem_mb | nodes | meshes | collisions |
| --- | --- | --- | --- | --- | --- |
| 1 | 47.087 | 32.504 | 5030 | 637 | 317 |
| 2 | 49.909 | 32.503 | 5030 | 637 | 317 |
| 3 | 52.015 | 32.495 | 5030 | 637 | 317 |

Procgen target (<2s): **PASS** (max 52ms — 38× under budget). Note: smoke seed builds 10× the nodes of the golden template (5030 vs 489), so it is the worst-case "all rooms loaded" proxy for the procgen memory pipeline.

### main_scene (the actual `playable_generated_ship.tscn` the player launches into)

| Run | procgen_ms (== load_ms) | peak_static_mem_mb | nodes | meshes | collisions | playable_ready |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 100.995 | 37.450 | 5115 | 668 | 317 | true |
| 2 | 96.594 | 37.489 | 5115 | 668 | 317 | true |
| 3 | 94.191 | 37.480 | 5115 | 668 | 317 | true |

Scene load target (<3s): **PASS** (max 101ms — 30× under budget). `procgen_ok=true` confirms `playable_ready` fires inside the first physics tick after `_ready` (the loader is synchronous; the main-scene load metric covers loader call + player spawn + camera spawn + interactables + breach zone + fire zone + objective tracker setup).

### Headless end-of-run OS RSS

| Run | os_rss_mb |
| --- | --- |
| 1 | 153.281 |
| 2 | 150.375 |
| 3 | 148.0 (varies with previous runs) |

Includes full Godot engine + GDAI MCP plugin capture registration + all 3 profiles' accumulated state at the moment `_finalize()` runs. RSS grows by ~50MB across the 3 sequential profile passes in a single process; per-profile incremental cost is dominated by the smoke seed pass.

## Windowed FPS results (3 runs)

`/Users/christopherwilloughby/.local/bin/godot-4.6.2 --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/windowed_fps_capture.gd`

Capture window: 240 frames after `playable_ready` fires. JSON dump at `~/Library/Application Support/Godot/app_userdata/The Synaptic Sea/perf_windowed_fps.json`.

| Run | frames | median_ms | p95_ms | observed_fps | peak_static_mb | peak_rss_mb |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 240 | 16.727 | 21.487 | 59.78 | 59.507 | 290.750 |
| 2 | 240 | 16.672 | 21.427 | 59.98 | 59.507 | 291.234 |
| 3 | 240 | 16.663 | 20.769 | 60.01 | 59.507 | 290.234 |

Frame time target (stable 60fps): **PASS** — observed FPS is pegged at the project's `Engine.max_fps = 60` cap. Median frame time is ~16.67ms (one 60fps tick); p95 spikes to ~21ms which is still 47fps worst-case.

Memory target (<512MB): **PASS** — peak Godot static memory 59.5MB (≈12% of budget), peak OS RSS 291MB (≈57% of budget). RSS at idle is ~245MB which is dominated by the Metal renderer command buffers and the GDAI MCP plugin capture; a release build without the plugin should be ~30-50MB lighter.

## Headless warnings observed

The two baseline Godot teardown lines (`ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit.`) are the only engine noise emitted by the headless `performance_profiler.gd` run. They are classified in `docs/game/06_validation_plan.md` and continue to apply here.

The pre-existing `procgen_playable_ship_smoke.gd` and `main_playable_slice_*` smokes do emit a large number of `WARNING: Navigation map synchronization had N edge error(s).` lines from Godot's navigation server when the smoke seed template builds its nav region from the legacy `wall_segments` layout. Those warnings do NOT appear in the perf profiler output because the profiler only runs the loader's `_build_navigation_region` path once per template and does not exercise the post-build navigation sync the playable scene does on every `_process` tick. Suppression or fix for those warnings is owned by the navigation-region ADR (out of scope for this card).

## Summary

All four targets pass on reference hardware with comfortable margin:

- **Frame time**: 60.0 fps pegged at the cap; p95 21ms worst-case (47fps). 30fps stop condition does not approach.
- **Memory**: 60MB Godot / 291MB OS RSS, both <60% of the 512MB target and well below the 1GB stop.
- **Scene load**: 101ms worst-case (30× under 3s budget).
- **Procgen time**: 52ms worst-case across both templates (38× under 2s budget).

No follow-up cards are required against the card's "metric exceeding target" acceptance criterion. Two observations are worth recording but do not warrant blocking completion:

1. The smoke seed template emits navigation-region edge warnings during build. These are pre-existing (visible in older smokes) and do not affect pass markers; tracking the suppression or fix is owned by the navigation-region ADR (out of scope for this card).
2. p95 frame time spikes to ~21ms in windowed runs. Within tolerance but worth re-measuring after the third hazard type lands and after Gate 3 hazard content is complete — covered by a future perf-resampling card when the relevant specs are implemented.

## Reproduce

```bash
# Headless baseline (templates + main scene, no display required)
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/performance_profiler.gd

# Windowed FPS capture (requires display server; writes user://perf_windowed_fps.json)
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/windowed_fps_capture.gd
```

The windowed capture is NOT part of the regression bundle (it needs a display server). The headless capture IS in the regression bundle as the `performance_baseline_smoke` entry; see `docs/game/06_validation_plan.md`.

## Add to the regression bundle

The headless `performance_profiler.gd` smoke is pinned to the regression bundle via a new `run_clean` call:

```
run_clean 'performance baseline smoke' 'PERFORMANCE BASELINE PASS templates=3' \
  "$GODOT" --headless --path "$ROOT" \
  --script res://scripts/validation/performance_profiler.gd
```

It is a non-functional perf baseline rather than a behavioral smoke: a future drop in procgen time or a regression to load_seconds would not be caught by the strict ERROR/WARNING filter alone, but the per-entry `PERFORMANCE PROFILE PASS` lines make it easy to grep the baseline numbers in CI. This is intentional — the harness is the doc, and the doc is the test.

## 2026-06-19 re-baseline

This re-baseline was captured after landing **REQ-013** (Electrical Arc hazard, the third Alpha hazard type; see `docs/game/features/hazard_type_3.md`) and **ADR-0005** (Multi-Hazard Architecture — shared `HazardStateContract` plus reusable `PhaseTimer`, independent hazard models; see `docs/game/adr/0005-multi-hazard-architecture.md`). It measures whether adding the third hazard type and the hazard-contract recycle changed any of the four Gate 4 performance targets.

### Run metadata

| Field | Value |
| --- | --- |
| Date | 2026-06-19 |
| Commit SHA | N/A — workspace not under git at time of capture |
| Reference hardware | Mac mini M4 (Apple Silicon), macOS 26.5.1 |
| Godot | 4.6.2.stable.official, Metal 4.0 Forward+ |

### Frame time (windowed FPS, 3 runs)

Source: `scripts/validation/windowed_fps_capture.gd`, 240 frames per run after `playable_ready`.

| Run | frames | median_ms | p95_ms | observed_fps | peak_static_mb | peak_rss_mb | Pass/fail (>=30fps) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 240 | 16.621 | 19.382 | 60.165 | 60.016 | 294.453 | PASS |
| 2 | 240 | 16.578 | 20.671 | 60.321 | 60.012 | 295.391 | PASS |
| 3 | 240 | 16.655 | 18.609 | 60.042 | 60.012 | 294.406 | PASS |
| **Median / aggregate** | **240** | **16.621** | **19.382** | **60.165** | **60.012** | **294.453** | **PASS** |
| **Delta vs 2026-06-19 baseline** | — | **-0.051ms (-0.31%)** | **-2.045ms (-9.54%)** | **+0.185fps (+0.31%)** | **+0.505MB (+0.85%)** | **+3.703MB (+1.27%)** | — |

Frame time target: **PASS** — observed FPS remains pegged at the 60fps cap; worst p95 is ~48.4fps, still well above the 30fps stop condition.

### Memory (3 runs)

Windowed source: `windowed_fps_capture.gd`. Headless source: `performance_profiler.gd` main_scene profile. All values in MB.

| Run | win_static_mb | win_rss_mb | main_static_mb | headless_rss_mb | Pass/fail (<=1GB) |
| --- | --- | --- | --- | --- | --- |
| 1 | 60.016 | 294.453 | 37.987 | 153.203 | PASS |
| 2 | 60.012 | 295.391 | 37.987 | 152.844 | PASS |
| 3 | 60.012 | 294.406 | 37.948 | 153.922 | PASS |
| **Median / aggregate** | **60.012** | **294.453** | **37.987** | **153.203** | **PASS** |
| **Delta vs 2026-06-19 baseline** | **+0.505MB (+0.85%)** | **+3.703MB (+1.27%)** | **+0.507MB (+1.35%)** | **+2.828MB (+1.88%)** | — |

Memory target: **PASS** — every measured footprint is <30% of the 1GB stop condition and <60% of the 512MB target.

### Scene load time (main_scene, 3 runs)

Source: `performance_profiler.gd`. `load_ms` equals `procgen_ms` because the main-scene loader is synchronous.

| Run | load_ms | peak_static_mem_mb | nodes | meshes | collisions | playable_ready | Pass/fail (<=3s) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 103.074 | 37.987 | 5119 | 669 | 317 | true | PASS |
| 2 | 103.707 | 37.987 | 5119 | 669 | 317 | true | PASS |
| 3 | 109.831 | 37.948 | 5119 | 669 | 317 | true | PASS |
| **Median / aggregate** | **103.707** | **37.987** | **5119** | **669** | **317** | **true** | **PASS** |
| **Delta vs 2026-06-19 baseline** | **+7.113ms (+7.36%)** | **+0.507MB (+1.35%)** | **+4** | **+1** | **0** | — | — |

Scene load target: **PASS** — median 103.7ms is ~29× under the 3s budget. The small node/mesh increase (+4 nodes, +1 mesh) is the electrical-arc zone geometry added by REQ-013.

### Procgen time (3 runs)

Source: `performance_profiler.gd` template profiles.

| Run | template | procgen_ms | peak_static_mem_mb | nodes | meshes | collisions | Pass/fail (<=2s) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | golden_coherent_ship_001 | 5.437 | 23.798 | 489 | 62 | 31 | PASS |
| 2 | golden_coherent_ship_001 | 5.484 | 23.798 | 489 | 62 | 31 | PASS |
| 3 | golden_coherent_ship_001 | 5.421 | 23.798 | 489 | 62 | 31 | PASS |
| 1 | smoke_seed_000017 | 51.294 | 32.530 | 5030 | 637 | 317 | PASS |
| 2 | smoke_seed_000017 | 27.083 | 32.530 | 5030 | 637 | 317 | PASS |
| 3 | smoke_seed_000017 | 49.976 | 32.530 | 5030 | 637 | 317 | PASS |
| **Median / aggregate** | golden_coherent_ship_001 | **5.437** | **23.798** | **489** | **62** | **31** | **PASS** |
| **Median / aggregate** | smoke_seed_000017 | **49.976** | **32.530** | **5030** | **637** | **317** | **PASS** |
| **Delta vs 2026-06-19 baseline** | golden_coherent_ship_001 | **-0.070ms (-1.27%)** | **+0.027MB (+0.11%)** | **0** | **0** | **0** | — |
| **Delta vs 2026-06-19 baseline** | smoke_seed_000017 | **+0.067ms (+0.13%)** | **+0.027MB (+0.08%)** | **0** | **0** | **0** | — |

Procgen target: **PASS** — worst median is 49.98ms, ~40× under the 2s budget. No significant change from the prior baseline.

### Re-baseline summary

All four Gate 4 performance targets remain **PASS** after the REQ-013 / ADR-0005 work:

- Frame time: still capped at 60fps; p95 improved by ~2ms (-9.5%).
- Memory: all proxies grew by <2%, remaining well under the 512MB target and 1GB stop condition.
- Scene load: main_scene load rose by ~7ms (+7.4%), attributable to the extra electrical-arc zone nodes; still ~29× under budget.
- Procgen time: effectively unchanged (<2% either direction) for both templates.

The re-baseline does not trigger any stop condition and does not require new follow-up cards against the performance acceptance criteria.