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
wired into the live run (ADR-0038 integration), and the Bucket 3 menu/meta-UI shell
(10 screens, plus the `localization_catalog` + `build_metadata_state` they consume) is
now player-reachable, the `autosave_policy` timed/rotating autosave loop is wired into the
live run, and `kit_catalog` now drives the lifeboat's biome-skinned structure. The
reachability source of truth is `docs/game/inventory/system_inventory.json` (rendered by
`tools/build_system_inventory.py`); as of the Tranche-6 correction it reports
`demo_scope_gate` reachable (wired 2026-07-07) and `release_readiness_ledger` +
the Bucket-1 tooling below still expected-unreached.**
See Buckets 2, 3, and the autosave + kit-catalog notes below.

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
After the Bucket 3 menu/meta-UI shell integration (2026-06-26): **92 reachable, 10 not
reachable** (the 10 menu/meta screens + `localization_catalog` + `build_metadata_state`
graduated to reachable). After wiring the `autosave_policy` timed/rotating autosave loop
(2026-06-26): **93 reachable, 9 not reachable** (`autosave_policy` graduated). After wiring
`kit_catalog` into the lifeboat's structural placer (2026-06-26): **94 reachable, 8 not
reachable** (`kit_catalog` graduated). The 8
remaining unreachable are the Bucket-1 infra/audit tooling below plus `junk_yield_resolver`
— all expected-unreached.

Tranche 6 correction (2026-07-07): the original audit script lived at `/tmp/reach.py`
on the original developer's machine and **no longer exists anywhere** — the historical
counts above are kept as history, not as a reproducible method. To re-verify
reachability after an integration change, use the canonical inventory instead:
`docs/game/inventory/system_inventory.json` records `reachable`/`driven` per system
(code-verified), `python3 tools/build_system_inventory.py --check` guards the rendered
outputs against drift, and `--coverage` sweeps for runtime scripts missing from the
inventory. For a quick spot check, grep the target script's path/`class_name` across
`scripts/` and `scenes/` excluding `scripts/validation/`.

## Bucket 1 — Infra / release / audit tooling (13). Expected to be unreached.

These are ledgers, reports, validators, and contracts that back the release/docs
pipeline. They are correctly **not** in the gameplay scene. They should **not**
count toward "playable systems."

- `scripts/systems/automated_playtest_rubric.gd`
- ~~`scripts/systems/autosave_policy.gd`~~ — **graduated to reachable** (timed/rotating
  autosave loop wired into `playable_generated_ship.gd`; see the autosave note below)
- `scripts/systems/balance_ledger.gd`
- ~~`scripts/systems/build_metadata_state.gd`~~ — **graduated to reachable** (Bucket 3:
  drives `ReleaseBadgeOverlay`)
- `scripts/systems/crash_report_bundle.gd`
- `scripts/systems/dependency_validator.gd`
- `scripts/systems/integration_matrix.gd`
- ~~`scripts/systems/localization_catalog.gd`~~ — **graduated to reachable** (Bucket 3:
  drives `LanguageSelector`)
- `scripts/systems/product_audit_report.gd`
- `scripts/procgen/seed_determinism_contract.gd`
- ~~`scripts/procgen/kit_catalog.gd`~~ — **graduated to reachable** (drives the lifeboat's
  biome-skinned structural modules via `StructuralPlacer`; see the kit-catalog note below)

Tranche 6 correction (2026-07-07): the previous claim here — that `demo_scope_gate` and
`release_readiness_ledger` had graduated to reachable — was **false** (2026-07-06 audit,
MEDIUM): the inventory showed both `reachable: false, driven: false` and a code sweep
confirmed zero non-smoke references. The truth: `demo_scope_gate` **became genuinely
reachable in Tranche 6** — `playable_generated_ship.gd` now owns and consults it at the
five demo-manifest enforcement points (saves, world snapshot, hub meta, derelict
hazards, cargo cap; see `demo_scope_enforcement_smoke`). `release_readiness_ledger`
**remains unreachable** (release/audit tooling, expected-unreached, Bucket 1). The
inventory JSON is the source of truth for the live counts.

Action: none required for playability. `build_metadata_state`, `localization_catalog`,
`autosave_policy`, and `kit_catalog` are now wired. The remaining unreached scripts are all
genuine release/audit/dev tooling (correctly **not** in the gameplay scene) plus
`junk_yield_resolver` (a static salvage helper superseded by the deconstruction path) — no
borderline player-facing systems remain.

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

## Bucket 3 — Menu / meta UI screens. RESOLVED (2026-06-26) — now player-reachable.

> **RESOLVED.** All ten meta screens are reachable from the live run through a new
> **Records** submenu on the existing in-run `MenuCoordinator` (which already mounts
> menu/codex/minimap/hotbar/tooltip/tutorial). `MenuCoordinator` now also mounts the ten
> screens as children (`_build_meta_screens()`), injects each screen's coordinator-owned
> data dependency (`bind_meta_screens()`), and routes `pause_menu → Records → <screen>`
> through the same `menu_state` + input path the codex uses. `playable_generated_ship.gd`
> constructs the three previously-missing deps in `_build_runtime_nodes()`
> (`LocalizationCatalog`, `BuildMetadataState`, `SaveLoadMenu`) and a live per-run
> `AchievementState` (previously only injected by the release build script, so the live
> `unlock_for_trigger` path was dormant). No new `RunSnapshot` field, no new ADR, no new
> keybind. Proven by `scripts/validation/main_playable_meta_screens_smoke.gd`, which opens
> each screen through the real coordinator seam and asserts it mounts + is populated by a
> live dependency → `MAIN PLAYABLE META SCREENS PASS screens=10 reachable=true`.

The following were moved out of the unreachable set by this change (now reachable + driven):

- `scripts/ui/achievements_panel.gd` — `set_state(achievement_state)` (now live)
- `scripts/ui/audio_log_panel.gd` — `set_audio_manager(audio_manager)`
- `scripts/ui/audio_settings_panel.gd` — `set_audio_manager` + `set_accessibility_settings`
- `scripts/ui/class_panel.gd` — `load_catalog()` + selected class from `player_progression`
- `scripts/ui/credits_screen.gd` — `load_catalog()`
- `scripts/ui/hub_upgrade_panel.gd` — `set_catalog(hub_upgrade_state)` + `set_meta_state(meta_progression_state)`
- `scripts/ui/language_selector.gd` — `set_catalog(localization_catalog)`
- `scripts/ui/release_badge_overlay.gd` — `set_metadata(build_metadata_state)`
- `scripts/ui/save_load_menu.gd` — `bind(save_load_service)`; rows surfaced in the Records list
- `scripts/ui/skill_tree_panel.gd` — `set_tree(skill_tree_state)` + `set_progression(player_progression)`

**Residual MVP limits (follow-ups, not blockers):** screens auto-select on open and are
read-only/keyboard-swallowing while displayed (no per-screen interactive nav beyond the
mouse widgets each panel already owns); the Records submenu is reached from the in-run
pause menu (the game still boots straight into the derelict — no separate pre-run main-menu
shell); cross-run achievement reconciliation (Steamworks, ADR-0029/0030) remains deferred —
`AchievementState` is per-run only.

## Autosave loop — `autosave_policy`. RESOLVED (2026-06-26) — now player-reachable.

> **RESOLVED.** The timed/rotating autosave loop is wired into the live run.
> `playable_generated_ship.gd` now constructs and owns `AutosavePolicy` in
> `_build_runtime_nodes()`; ticks it every frame from `_process()` in **both** the home and
> away (boarded-derelict) branches via `_tick_autosave_policy(delta)`, feeding it the
> accumulated run-clock seconds and a monotonically-growing event count
> (`objective_completion_count` + the training-event-bus log size); and on a fire writes a
> `RunSnapshot` into a rotating `autosave_a`/`b`/`c` slot through
> `save_load_service.save_to_slot(..., SLOT_KIND_AUTO, ...)` — the same slots the now-reachable
> `SaveLoadMenu` (Bucket 3) lists. **This is purely additive: the REQ-012 checkpoint path
> (`_auto_save_current_run` → `save_world` → `current_run.json`) and its resume smokes are
> untouched** (`REQ012 AUTOSAVE SEQUENCE CHECK PASS` + `AUTOSAVE POLICY PASS` still green;
> no new `RunSnapshot` field — `summaries=27` unchanged; no new ADR). Lifecycle handling:
> `_reset_runtime_for_reload()` reseeds the policy (`reset()` + zeroes the run-clock) so a stale
> event count/clock can't carry across a load, and slice completion deletes the rotating
> `autosave_a/b/c` slots alongside `delete_current_run()` so a finished run leaves no resumable
> rows. Proven coordinator-driven by `scripts/validation/main_playable_meta_autosave_smoke.gd`,
> which forces an autosave through the live coordinator seam and asserts a rotating
> `SLOT_KIND_AUTO` slot actually hits disk →
> `MAIN PLAYABLE META AUTOSAVE PASS slot_rotated=true reachable=true`.
>
> **Residual MVP limits (follow-ups, not blockers):** manual quicksave (`AutosavePolicy.try_quicksave`)
> is **not** wired — there is no quicksave keybind yet, so only the autosave loop runs; cadence
> tunables use the model defaults (90 in-game-second / 8-event cadence, 5 s real-time budget).

## Kit catalog — `kit_catalog`. RESOLVED (2026-06-26) — now player-reachable.

> **RESOLVED.** `KitCatalog` (role → structural-module registry, loaded from `data/kits/*.json`
> with biome-biased kit selection) now drives the **lifeboat's** structural modules.
> `StructuralPlacer` (`scripts/procgen/structural_placer.gd`) constructs and consults a
> `KitCatalog` in `_modules_for_role()` instead of its hardcoded `ROOM_MODULES` const, and
> accepts a `biome` param; `LifeBoatBuilder.build(biome)` threads it through, and
> `playable_generated_ship.gd:_build_lifeboat_at_home()` passes the run's deterministic biome
> (`_resolve_current_loot_biome_id()`). The lifeboat's room graph/cell positions stay fixed —
> only the per-role module *kit* changes, so each run's home craft gets a biome skin
> (`abyssal_synaptic_sea` → `ship_structural_v0`, `breach_field` → hazard kit, `dead_fleet` →
> industrial kit) without altering the floorplan the player learns. **Determinism preserved:**
> `ship_structural_v0.json` gained a `role_modules` map that mirrors `ROOM_MODULES` exactly plus
> a high `abyssal_synaptic_sea` affinity, so the default/abyssal lifeboat is byte-identical to
> before (`STRUCTURAL PLACER PASS … modules=24` unchanged). **Latent bug fixed:** `KitCatalog`
> previously mangled v0's asset-catalog `modules` (array of objects) into stringified-dict stems
> and ignored the JSON `default_role_module` field — both fixed in `_load_kit_file`, and
> `kit_catalog_smoke` strengthened to assert real `.tscn` stems. Proven coordinator-driven by
> `scripts/validation/main_playable_lifeboat_biome_skin_smoke.gd`, which reads the live
> lifeboat's instantiated modules and asserts they match the kit for the run's biome →
> `MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=3 live_match=true reachable=true`.
>
> **Out of scope:** derelict structural variety — derelicts use the `layout.json` pipeline
> (module ids baked per placement by `LayoutSerializer`), not `StructuralPlacer`. Kits are wired
> only into the lifeboat path here.

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
— **8 after wiring `kit_catalog`** (was 30 → 24 after Bucket 2 → 10 after Bucket 3 → 9
after `autosave_policy` → 8 after `kit_catalog`). The 8 remaining unreachable are Bucket-1
infra/audit/dev tooling plus `junk_yield_resolver` — all expected-unreached, with **no
borderline player-facing systems left**. Everything that is reachable is genuinely driven.

## Unlock-trigger content debt (Tranche 6, 2026-07-07)

`data/player/unlock_tables.json` authors 23 unlocks whose `trigger_event`s resolve
through the TrainingEventBus log at run end (`_apply_meta_payout_and_persist`). The
pipeline itself is wired; the debt is **emission**: production only fires the training
events whose player actions exist. After the Tranche-6 retargets
(`hub_scene_bridge` → `threat_killed`, `codex_repair_intro` → `repair_full_system`) and
the new `scavenge_container` emission at the loot-search handler, the live set is:

**Reachable in production (5 unlocks):** `hub_scene_workshop` (`fabricate_part`),
`hub_scene_bridge` (`threat_killed`), `codex_repair_intro` (`repair_full_system`),
`codex_scavenging_intro` + `class_unlock_salvage_captain` (`scavenge_container`).
Proven end-to-end by `unlock_trigger_production_smoke`.

**Content-pending (18 unlocks — trigger events with no production emission because the
player action does not exist yet):** `diagnose_fault`, `first_aid_self`,
`perform_surgery` (×3 unlocks: codex_surgery_intro, hub_scene_medical,
class_unlock_field_medic), `plot_course`, `complete_astrogation` (×2:
codex_astrogation_intro, hub_scene_reactor), `scan_derelict`, `decode_signal` (×2:
codex_signal_intro, class_unlock_signal_specialist), `cook_meal`, `build_shelter`,
`ration_supplies`, `inspire_crew`, `negotiate_truce`, `intimidate_threat`,
`transmit_relay`. These are authored content awaiting their interactions (medical,
navigation-ritual, social systems) — wiring an emission without the action would grant
XP for nothing. The orphaned `defeat_enemy` training action (intimidation +100) is
likewise content-pending: the kill path deliberately stays on the Domain-2 spec'd
`threat_killed` action (re-targetable data; emitting both would double-grant per kill).

Per user decision 2026-07-07 (retarget + flagship wire), these stay documented here
rather than force-wired. The `unlock_trigger_production_smoke` structural guard keeps
every catalog `trigger_event` inside the valid training-action vocabulary, so a future
content pass only needs to emit the event at its new interaction.

## Content-pending authored data (W9, 2026-07-07) — updated 2026-07-21

- ~~`data/ui/status_effect_icons.json`~~ — **CLOSED 2026-07-21**: 8 minimal PNG
  placeholders under `assets/placeholder/`; `status_effect_icons_smoke` asserts paths
  exist. Final art pass still future.
- ~~`data/procgen/encounter_tables/threat_drone_swarm.json`~~ — **CLOSED 2026-07-21**:
  `dead_fleet` biome now references `threat_drone_swarm` (`encounter_table_dead_fleet_smoke`).
  `derelict_pirate` remains available for retargets.

## Stream C wiring (2026-07-21)

1. **F6 quicksave** — `quicksave_run` → `request_quicksave()` via AutosavePolicy.try_quicksave
   + `save_to_slot(..., SLOT_KIND_QUICK)`. Proven by `main_playable_quicksave_smoke`.
2. **Ambient zone gameplay** — `_push_ambient_zone_from_gameplay` in `_refresh_audio_state`
   maps nearest layout room_role → AmbientZoneState + threat from hazard/combat.
3. Status icons + dead_fleet encounter table as above.

## Stream A reachability closures (2026-07-21)

Four player-facing holes identified in the 2026-07-21 gap analysis are now closed in
`playable_generated_ship.gd` and proven by `main_playable_reachability_smoke.gd`
(`MAIN PLAYABLE REACHABILITY PASS organic_cart=true home_loot=true hangar_interact=true achievements=true`):

1. **Hangar bay interact** — `_try_hangar_interact` is on the home and away interact
   chains; prefer dock when a co-present candidate exists, else launch. (Previously
   HangarBayControl was spawned and signals were connected, but nothing called
   `try_dock` / `try_launch` from player interact.)
2. **Home loot containers** — home-branch interact iterates `loot_containers` (was
   away-only).
3. **Organic salvage cart** — `_ensure_organic_cart` parks an `organic_cart_<ship_id>`
   on cargo/hangar-capable ships before cart controls spawn (no longer validation-only).
4. **Achievement catalog emitters** — production fires `loot_searched`, `repair_consumed`,
   `objective_completed` (`objectives[0]` + type), `reactor_stabilized`, and
   `run_complete` in addition to the existing `tool_acquired` path.

Inventory `gaps[]` for hangar/cart/achievements/home-loot/O2/corpses refreshed
2026-07-21 via `tools/build_system_inventory.py` after Stream A+B closures.

## Stream B survival + corpse loot (2026-07-21)

1. **Personal O2 away branch** — `_refresh_oxygen_state` on the derelict `_process`
   path; `OxygenState.tick` accepts `field_atmosphere` so suit pressure drains while
   boarded (independent of home breach seal). Hub life-support atmosphere bite stays
   home-only.
2. **Combat corpse persistence** — `ShipInstance.pending_corpse_loot` records
   unsearched kill drops; `_build_loot_containers` re-spawns them on revisit/save.
   Searched corpses leave the pending list and stay in `looted_container_ids`.
