# Integration Debt — Validated-but-Unreachable Systems

Date: 2026-06-26
Status: Living record. Created from a reachability audit of the E2E systems batch
(commit `5445480`, "land synaptic sea e2e package batch").

## Why this document exists

`09_system_roadmap.md` marks all system lanes **Validated**. That is accurate by
its own definition — every system has a passing model/smoke — but it overstates
**playability**. A reachability audit found that **30 of the 102 runtime scripts
added by the E2E batch were not reachable from the live main scene
(`scenes/main.tscn`)** — unit-tested in isolation but never mounted in the actual
derelict run. **As of 2026-06-26 the Bucket 2 crafting/salvage economy (6 scripts) is
wired into the live run (ADR-0038 integration), bringing the count to 24 unreachable /
78 reachable.** See Bucket 2 below.

These are **not stubs** — the models are real and smoke-backed. They are
**un-integrated**. This document tracks that debt so "Validated" is not read as
"player-reachable", and so depth/content work does not get built on systems no
player can reach.

## Audit method (reproducible)

Transitive reachability from `scenes/main.tscn` across both `.gd` and `.tscn`,
following `preload` / `load("res://…")` paths, `class_name` references, and scene
`ext_resource` links. Validation smokes (`scripts/validation/`) are excluded from
the runtime graph (a smoke referencing a script does not make it player-reachable).

Result (original audit): **102 new runtime scripts → 72 reachable, 30 not reachable.**
After the ADR-0038 crafting integration (2026-06-26): **78 reachable, 24 not reachable**
(6 of Bucket 2's 7 scripts wired; `junk_yield_resolver` remains a static helper).

Re-run the audit script at `/tmp/reach.py` (seed = `scenes/main.tscn`, diff base =
`5445480`) after any integration change to confirm a script has moved into the
reachable set.

## Bucket 1 — Infra / release / audit tooling (13). Expected to be unreached.

These are ledgers, reports, validators, and contracts that back the release/docs
pipeline. They are correctly **not** in the gameplay scene. They should **not**
count toward "playable systems."

- `scripts/systems/automated_playtest_rubric.gd`
- `scripts/systems/autosave_policy.gd`
- `scripts/systems/balance_ledger.gd`
- `scripts/systems/build_metadata_state.gd`
- `scripts/systems/crash_report_bundle.gd`
- `scripts/systems/demo_scope_gate.gd`
- `scripts/systems/dependency_validator.gd`
- `scripts/systems/integration_matrix.gd`
- `scripts/systems/localization_catalog.gd`
- `scripts/systems/product_audit_report.gd`
- `scripts/systems/release_readiness_ledger.gd`
- `scripts/procgen/seed_determinism_contract.gd`
- `scripts/procgen/kit_catalog.gd`

Action: none required for playability. Re-classify `autosave_policy`,
`localization_catalog`, and `kit_catalog` if/when their consumers (autosave loop,
live localization, encounter injection) are wired — they are borderline and may
move to a gameplay bucket.

## Bucket 2 — Crafting / salvage economy. RESOLVED (2026-06-26) — now player-reachable.

> **RESOLVED (ADR-0038 integration).** The crafting/materials/stations/salvage economy
> is wired into the live derelict run. `playable_generated_ship.gd` now constructs and
> owns `CraftingState`, `MaterialState`, `FieldCraftingState`, and `DeconstructionResolver`
> in `_build_runtime_nodes()`; builds player-reachable `CraftingStation` interactables
> (`scripts/tools/crafting_station.gd`) on the home ship in `_build_crafting_stations()`;
> dispatches them from `_on_player_interact_requested`; ticks the active craft and drives
> station power (`StationState.set_power` from the `stations` power channel) each frame in
> `_recompute_expanded_ship_systems()`; persists via the existing `crafting_summary` /
> `material_summary` snapshot fields (field crafting nested under
> `crafting_summary["field_crafting"]` — no new `RunSnapshot` field, no new ADR); and binds
> emergency field crafting to `C` via a new `field_craft_requested` player signal. Proven
> coordinator-driven (not just unit-tested) by
> `scripts/validation/main_playable_slice_station_craft_smoke.gd`, which drives the
> coordinator's **own** models through the real interaction seams and asserts
> `crafting_summary` is populated with no manual injection →
> `MAIN PLAYABLE STATION CRAFT PASS crafted=true salvaged=true field=true reachable=true`.
>
> **Residual MVP limits (Bucket 3 follow-ups, not blockers):** single active craft at a
> time (`CraftingState` is single-`_active_craft` by design); stations auto-select the first
> craftable recipe (no recipe-picker UI yet); powered-station crafts pause while away from
> home (only field crafting advances on a derelict); `JunkYieldResolver`-based raw-junk
> salvage is not yet in the live loop (the wired salvage path uses deconstruction recipes).

The following were moved out of the unreachable set by this change (now reachable + driven):

- `scripts/systems/crafting_state.gd` — owned + ticked by the coordinator
- `scripts/systems/field_crafting_state.gd` — owned + ticked (incl. away-branch)
- `scripts/systems/material_state.gd` — owned; quality drives craft output
- `scripts/systems/deconstruction_resolver.gd` — driven by the salvage station
- `scripts/systems/station_state.gd` — driven via `CraftingState` (power + progress)
- `scripts/systems/quality_tier_resolver.gd` — driven transitively by `begin_craft`
- `scripts/systems/junk_yield_resolver.gd` — still NOT in the live loop (static helper;
  the wired salvage path uses deconstruction recipes — see residual limits above)

## Bucket 3 — Menu / meta UI screens. Exist, never mounted, no shell flow (10).

The game boots straight into the derelict run (`main.gd` → playable ship),
bypassing any main-menu / pause shell. `menu_coordinator` mounts a subset of HUD
panels (menu, codex, minimap, hotbar, tooltip, tutorial) but **none** of the
screens below — each is referenced only by its own smoke. The entire
settings / save / meta-screen layer is dark.

- `scripts/ui/achievements_panel.gd`
- `scripts/ui/audio_log_panel.gd`
- `scripts/ui/audio_settings_panel.gd`
- `scripts/ui/class_panel.gd`
- `scripts/ui/credits_screen.gd`
- `scripts/ui/hub_upgrade_panel.gd`
- `scripts/ui/language_selector.gd`
- `scripts/ui/release_badge_overlay.gd`
- `scripts/ui/save_load_menu.gd`
- `scripts/ui/skill_tree_panel.gd`

Action: a navigable main-menu / pause shell wired into the boot flow that mounts
these screens. Until then they are tested components with nothing to assemble them.

## Deeper audit: are the reachable systems actually *driven*? (2026-06-26)

> Note: the counts in this section predate the ADR-0038 crafting integration; the 6 newly
> wired crafting/salvage systems are reachable **and** driven (owned + per-frame-ticked by
> `playable_generated_ship.gd` — see Bucket 2), so the "no idle reachable systems"
> conclusion still holds for the now-78 reachable set.

Reachable ≠ driven, so a second pass checked whether each reachable system is
exercised in the loop or merely instantiated and idle. Method: resolve each
owner's `preload`-alias → instance-var map, then classify the methods called on
each instance (excluding `new`/`get_summary`/`apply_summary`/getters as
"save/read-only").

**Result: no genuinely idle reachable systems.** Every reachable system is driven
by the main coordinator or a sub-coordinator:

- **Main coordinator (`playable_generated_ship.gd`)** constructs 32 of the new
  e2e systems and drives all 32 — each has `configure` + a per-frame `tick`
  (or real mutators). Per-frame `_process` ticks vitals, sanity, radiation,
  body_temperature, status_effects, stimulant, addiction, spoilage, cooking,
  hydroponics, synthesizer, water_recycler, sustenance, propulsion, shield,
  life_support, fire_suppression, plus fire/arc/oxygen and `audio_manager.tick`.
- **`audio_manager`** constructs and ticks its sub-systems: `ambient_zone_state`,
  `sfx_event_router`, `dynamic_music_state`, `meta_event_state` (all `.tick`),
  and `spatial_audio_resolver.resolve_volume_db`.
- **`threat_manager`** drives `detection_state.tick`, `damage_pipeline`, and
  per-threat `tick`.
- **`menu_coordinator`** drives `tutorial_state`, `tooltip_presenter`,
  `controller_glyph_state`, `menu_state`, `settings_state`.

A first automated pass flagged six audio systems as "idle"; that was a false
negative caused by instance var names differing from file names
(`music_state` ← `dynamic_music_state.gd`, `sfx_router` ← `sfx_event_router.gd`).
Verified by hand against `audio_manager.gd` — they are ticked every frame.

**Conclusion:** integration debt is confined entirely to the unreachable scripts above
(Buckets 1–3) — **24 after the ADR-0038 crafting integration** (was 30; Bucket 2's 6
crafting/salvage systems are now reachable + driven). Everything that is reachable is
genuinely driven.
