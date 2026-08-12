# Feature: Demo Scope v1 (Milestone B)

## Status

**Proposed** — source-backed inventory of the current `DemoScopeGate` plus the
proposed bounds for the Milestone B public demo. This document describes what
is enforced today and what still requires a demo-build implementation pass.

## Purpose

`DemoScopeGate` is the runtime boundary between the unrestricted development /
release builds and a deliberately narrow demo. The authoritative current inputs
are:

- `data/release/demo_scope_manifest.json`
- `data/release/build_metadata.json`
- `scripts/systems/demo_scope_gate.gd`
- the production coordinator `scripts/procgen/playable_generated_ship.gd`

The code is the source of truth where older release prose differs. In
particular, the live build kinds are `dev`, `demo`, and `release`; there is no
runtime `full` build kind.

## Current manifest inventory (today)

`data/release/demo_scope_manifest.json` contains one top-level key:
`demo_blocked_features`. It is a five-entry blocklist. Each entry has a
`feature_id`, `reason`, and `hint`; three entries also have machine-readable
`params` consumed by production enforcement code.

| Manifest `feature_id` | Current authored restriction | Current `params` |
|---|---|---|
| `cargo_hold.full_inventory` | Demo cargo capacity is capped; the manifest describes 6 kg versus the standard 500 kg full-build capacity. | `max_weight_kg: 6.0` |
| `multi_hazard.run` | A demo derelict seeds one hazard; a full/release derelict may seed up to three. | `max_hazards: 1` |
| `long_run.persistence` | Demo refuses further saves after 20 minutes of active play; existing saves are retained. | `max_play_seconds: 1200` |
| `world_persistence.cross_run` | Demo snapshots are per-run rather than retaining arbitrary cross-run world state (the manifest cites ADR-0012). | none |
| `hub.meta_progression` | The manifest describes hub/meta progression as deferred and the hub as skipped. | none |

`DemoScopeGate.configure()` reads that array and copies any non-empty `params`
dictionary. `get_params(feature_id)` returns a defensive copy, so the runtime
caps come from the JSON rather than duplicated constants.

The gate has blocklist semantics:

- Empty `feature_id` is rejected (`is_allowed("") == false`) defensively.
- In `build_kind == "demo"`, a non-empty feature in the manifest is blocked.
- In `build_kind == "demo"`, a non-empty feature **not** in the manifest is
  allowed. The gate does not know the complete feature universe, so it cannot
  enumerate a complement set.
- `dev` and `release` builds are permissive for the manifest entries.

This corrects the older feature prose that said unknown IDs were rejected and
that the unrestricted kind was `full`; neither describes the current
`demo_scope_gate.gd` implementation.

## Current build metadata (today)

`data/release/build_metadata.json` currently reports:

| Key | Current value | Demo relevance |
|---|---|---|
| `version` | `v0.1.0` | Version carried into a future demo artifact. |
| `build_kind` | `dev` | All five gate restrictions are inert in the checked-in build. A packaged demo must change this to `demo`. |
| `store` | `itch` | Current metadata points at itch; this does not itself create a demo export. |
| `language_defaults` | `["en"]` | English is the only current default. |
| `achievements_supported` | `true` | Achievements are supported by the metadata service, but this is not a demo-scope cap. |
| `demo_hub_unlocked_features` | `["oxygen_breach", "fire_hazard", "objective_progress"]` | Metadata only today. No production consumer was found that turns this list into a hub allowlist or progression cap. |
| `valid_build_kinds` | `["dev", "demo", "release"]` | The accepted build-kind vocabulary. |
| `release_date` | `2026-Q4` | Release planning metadata, not enforcement. |
| `telemetry_endpoint_placeholder` | `https://telemetry.synaptic_sea.example/api/v1` | Placeholder only; no demo/cloud upload path consumes it. |

`PlayableGeneratedShip` constructs `BuildMetadataState` from this file and
configures one `DemoScopeGate` against that same live metadata instance. The
current checked-in `build_kind: "dev"` is therefore intentional for development
runs, not evidence that a demo build is already packaged.

## Enforcement points that are real today

The production call sites below were verified under `scripts/` (validation
scripts excluded from the production list). The gate is configured at
`playable_generated_ship.gd:1385-1391` and injected into `MenuCoordinator` at
`playable_generated_ship.gd:6355-6369`.

### Saves (`long_run.persistence`)

The authored `params.max_play_seconds` value is read by
`playable_generated_ship.gd:9664-9674`.

- Rotating autosave is stopped at `:9500-9504`.
- The checkpoint/world autosave is stopped at `:9474-9478`.
- Quicksave is refused at `:9592-9598`.
- Manual world save is refused at `:9626-9641`, with a player-facing
  `"Demo build: save limit reached (%d min)"` line.
- Records → Save/Load is also guarded through the injected callback at
  `scripts/ui/menu_coordinator.gd:890-897`, so it cannot bypass the same cap.

The behavior is **save refusal, never save deletion**. This is a 20-minute save
budget today, not a 20-minute session termination.

### World snapshot (`world_persistence.cross_run`)

`playable_generated_ship.gd:10040-10070` builds the world snapshot. In demo,
`playable_generated_ship.gd:10080-10115` filters `visited_ships` so arbitrary
unreferenced visited derelicts are not serialized. The currently boarded ship
and ships still referenced by the snapshot's piloted/aboard/dock-edge data are
kept so an away-save remains reconstructable. In `dev`/`release`, the full
`visited_ships` set is retained.

This is a snapshot serialization filter, not a limit on how many derelicts may
be visited during the current process.

### Hub/meta menu actions (`hub.meta_progression`)

The injected gate blocks these two live menu actions in demo:

- Hub upgrade purchase: `scripts/ui/menu_coordinator.gd:812-826`, with the
  block at `:815-818`.
- Class selection persistence: `scripts/ui/menu_coordinator.gd:837-851`, with
  the block at `:838-841`.

This is narrower than the manifest's broad “hub/meta progression” wording. The
skill-tree unlock branch at `menu_coordinator.gd:827-836` does not consult the
gate, and run-end `_apply_meta_payout_and_persist()` still persists
`meta_progression_state` and `unlock_registry` at
`playable_generated_ship.gd:9549-9580`. Those are current gaps, not assumed
coverage.

### Derelict hazards (`multi_hazard.run`)

`playable_generated_ship.gd:9676-9681` reads `params.max_hazards`. During
real derelict setup, `playable_generated_ship.gd:2188-2209` records the budget
and applies it in the existing deterministic seed order:

1. breach
2. fire
3. electrical arc

A demo budget of 1 therefore seeds only breach; `dev`/`release` use `-1` and
preserve the unrestricted path. The validation seams
`_last_derelict_hazard_budget` and `_last_derelict_hazards_seeded` expose the
result, but the enforcement itself is in the production travel/setup path.

### Cargo cap (`cargo_hold.full_inventory`)

`playable_generated_ship.gd:9683-9694` reads `params.max_weight_kg` and lowers
the ship inventory's maximum weight when needed. It is called before the cargo
room/control setup at `playable_generated_ship.gd:2424-2431` and therefore also
covers the home-ship setup at `:7122-7124` and later derelict setup. In demo,
subsequent inventory consumers see the 6 kg cap; `dev`/`release` are unchanged.

## What is not enforced yet

The following are not present in the current gate or current production path:

1. **No maximum derelicts visited.** `travel_to()` registers every first-time
   marker in `visited_ships` (`playable_generated_ship.gd:6069-6083`), with no
   demo count check. The demo world-snapshot filter does not change this
   in-process count.
2. **No demo session hard cap.** There is no 90-minute end-state or forced
   results flow. `max_play_seconds: 1200` only refuses saves; it does not stop
   play and is incompatible with a 60–90 minute public-demo target if left
   unchanged.
3. **No complete meta-progression cap.** Hub purchases and class selection are
   blocked, but skill-tree unlocks and run-end meta/unlock persistence are not
   gated. There is no numeric “maximum meta unlocks” or “maximum hub upgrades”
   predicate.
4. **No fixed demo biome/difficulty override.** The current resolver selects a
   biome from the seed (`_resolve_run_context`, `:10491-10496`) and bands
   difficulty by `size * 2 + condition` (`:10498-10507`). `breach_field` +
   `standard` is the locked product target in the vertical-slice spec, not a
   current DemoScopeGate rule.
5. **No demo-specific packaged metadata/export.** The repository metadata is
   `build_kind: "dev"`, and the current export presets are general platform
   presets. A demo artifact still needs a build metadata/profile step that sets
   `build_kind: "demo"` and validates the resulting package.
6. **No explicit cloud-disable policy.** There is no remote cloud provider or
   sync implementation today. `SaveLoadService` does write local
   `.cloud/*.manifest.json` sidecars with `cloud_provider: "stub"` for
   integrity/forward compatibility, and verifies their hashes on load. That is
   not cloud sync, but Milestone B should make “no remote upload/sync” an
   explicit acceptance check rather than relying on the absence of an adapter.
7. **`demo_hub_unlocked_features` is not an enforcement source.** The three
   values in build metadata do not currently control a menu, a hub scene, or a
   progression allowlist.

## Proposed Milestone B demo bounds

These are the proposed product bounds for a public, content-readable demo. They
are deliberately narrower than the full game and must be implemented as
explicit runtime/build-profile rules before the demo is called ready.

| Dimension | Milestone B bound |
|---|---|
| Build kind | `demo` in the packaged artifact and runtime metadata. |
| First face | One authored `breach_field` slice at `standard` difficulty. Do not use the current seed/depth selection as a substitute for this fixed demo profile. |
| Derelicts visited | **Maximum 4 distinct derelicts per demo run** (including the first away derelict). Revisit of an already-counted derelict does not consume another visit. The travel gate and load/revisit path must share the same count semantics. |
| Session length | Target 60–90 minutes for a cold player; **hard cap 90 minutes** (`5400` active-play seconds) with a clear warning and results/title transition. This is separate from save policy. |
| Saves | Keep saves bounded to the demo run and never delete existing saves on refusal. Before shipping, reconcile the current `long_run.persistence` 1200-second save refusal with the 90-minute session: either author a 5400-second demo save budget or replace it with a separate session-cap rule. A 20-minute save refusal is not an acceptable substitute for the proposed B contract. |
| Persistent meta unlocks | **0 cross-run meta unlocks** in the public demo. Any demonstration-only progression must be read-only or reset at run end; do not persist new class, codex, skill-tree, or hub-upgrade unlocks. |
| Hub upgrades | **0 purchaseable hub upgrades** in demo. The Records/meta surfaces may show the three metadata showcase IDs (`oxygen_breach`, `fire_hazard`, `objective_progress`) as read-only/status content only; they are not upgrade grants. |
| Cloud | Disabled: no remote cloud provider, upload, download, or sync. Local save files and the existing stub integrity sidecar may remain. |
| Platforms | Windows x86_64 and macOS required. Existing `export_presets.cfg` has Windows and macOS presets; demo-specific export validation/package output remains required. |
| Breadth | One coherent public slice; no Steamworks, no full Early Access breadth, and no unbounded biome/difficulty matrix in the demo package. |

The bounds intentionally do not broaden the current manifest silently. They
identify the additional rules (visit count, hard session cap, fixed profile,
complete meta reset, and packaging metadata) that a Milestone B implementation
must add or explicitly encode.

## Acceptance criteria: demo-ready

Milestone B is `demo-ready` only when all of the following are true:

- [ ] The packaged build reports `build_kind == "demo"`; a smoke proves the
      same `BuildMetadataState` instance drives the live gate.
- [ ] The manifest is parsed successfully and its current caps are verified:
      `max_weight_kg == 6.0`, `max_hazards == 1`, and the authored save-policy
      value is surfaced to the player without hardcoding.
- [ ] The focused demo enforcement smoke passes for saves, world snapshot,
      hub/meta actions, hazards, and cargo; a dev/release control run proves
      those restrictions remain inert outside demo.
- [ ] A real demo run cannot visit more than four distinct derelicts; revisits,
      save/load, and referenced-ship reconstruction cannot bypass the count.
- [ ] The first playable face is deterministically `breach_field` + `standard`,
      and the packaged demo does not silently fall back to the unrestricted
      seed/depth resolver.
- [ ] The 90-minute active-play cap is enforced with a readable warning and a
      non-crashing end/results/title transition. It is not implemented merely
      by refusing saves at 20 minutes.
- [ ] Hub upgrades and all cross-run meta unlock persistence are either blocked
      or reset according to the zero-persistent-meta bound; skill-tree and
      run-end payout paths are covered, not just the two existing menu guards.
- [ ] No remote cloud/network sync occurs in a demo run. Local stub manifests,
      if retained, are documented as integrity sidecars and remain
      `cloud_provider: "stub"`.
- [ ] Windows x86_64 and macOS demo exports are produced and launch through the
      normal title → playable path; export validation identifies them as demo
      artifacts rather than `dev` builds.
- [ ] A cold-player playtest reaches the intended 60–90 minute experience,
      with the hard cap at 90 minutes, no P0 crash/softlock, and a clear
      extraction/death/cap result.
- [ ] The documented Godot regression bundle and focused demo smoke finish
      without unclassified `ERROR:` or `WARNING:` output.

## Out of scope

- Steamworks SDK, Steam achievements activation, Steam Cloud, or any other
  remote cloud provider integration.
- Full Early Access breadth: additional biomes, unrestricted difficulty bands,
  large class trees, broad hub content, and unlimited derelict runs.
- Store upload automation, storefront entitlement, DRM, matchmaking, and
  multiplayer.
- Replacing the current local cloud-manifest integrity sidecar with a network
  service.
- Rewriting the full game's progression model; Milestone B only needs the
  explicit demo boundary and a safe reset/block policy.

## Related sources

- `data/release/demo_scope_manifest.json`
- `data/release/build_metadata.json`
- `scripts/systems/demo_scope_gate.gd`
- `scripts/systems/build_metadata_state.gd`
- `scripts/procgen/playable_generated_ship.gd`
- `scripts/ui/menu_coordinator.gd`
- `scripts/systems/save_load_service.gd`
- `scripts/systems/cloud_manifest_state.gd`
- `scripts/validation/demo_scope_enforcement_smoke.gd`
- `docs/game/features/vertical_slice_v1.md`
- `docs/game/integration_debt.md` (Tranche 6 correction)
- `STATUS.md` (Tranche 6 production wiring)
- `docs/game/adr/0029-release-distribution-architecture.md`
