# Domain 5: Consumables — design spec

**Date:** 2026-06-30
**Status:** approved in brainstorming; pending written-spec review.
**Roadmap:** `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` → Domain 5 (`consumables`, 🟡 partial).
**Depends on:** Domain 1 (survival/body-temp/sanity, closed), Domain 2 (combat/ammo, closed).

## Context

The `consumables` loop is 🟡 partial. The roadmap's five break-points predate the Domain 2 combat
closure and the Domain 4 live-persistent-ships `_process` rewrite; three of five have drifted. Verified
current state (2026-06-30):

1. **`ammo_state` is orphaned, not merely hollow.** Domain 2 combat did **not** wire `ammo_state`. It
   built a separate, working ammo path: `threat_manager.attack_with_weapon` (`threat_manager.gd:114-118`)
   loads `data/combat/ammo_definitions.json` and consumes ammo **directly from inventory**
   (`inventory_state.remove_item(ammo_item_id, 1)`), with a `no_ammo` gate. The consumables `ammo_state`
   model (reserves dict + `data/items/ammo_definitions.json` + the `flare_burn`/`shock_jolt` orphan
   effects) is redundant dead weight — only touched for construct/save (`playable_generated_ship.gd:1194,
   4175, 6221-6222, 6527-6528`).
2. **Orphan effect ids** `flare_burn`/`shock_jolt` live only in the orphaned `data/items/ammo_definitions.json`.
3. **Stim/addiction home-only tick** — still true. `stimulant_state.tick`/`addiction_state.tick` run only
   in the home branch (`playable_generated_ship.gd:5102-5105`); the away branch (`:5013-5079`) returns at
   `:5079` without ticking them. Item USE works away (input not away-gated); only per-frame buff/withdrawal/
   tolerance decay freezes on a boarded derelict.
4. **`utility_flag` bypass hollow** — still true. `utility_item_resolver` sets `active_flags`
   (`utility_lockpick_ready`, `utility_hack_chip_ready`, `flare`, `repair_foam`) but no gameplay system
   reads them. On inspection **all four flags plus the `utility_flare`/`*_ready` statuses are `add_status`
   with no reader**; only `repair_foam`'s `heal_small` effect does real work.
5. **`temperature_delta` dead branch** — still true. `effect_dispatcher.gd:55` has the branch; no effect
   definition uses `kind temperature_delta`.

## Goal

Close the `consumables` loop to `🟢 closed`: every consumable branch has a real, consumed effect, and the
per-frame decay ticks run on both `_process` branches. Measured by `system_inventory.json`
`consumables.closes → "closed"` with break-points cleared, `--check`/`--coverage` clean, and the full
regression bundle green.

## Global constraints (from the roadmap)

- **Validation is the definition of done** — no closure without fresh PASS-marker output.
- **Both `_process` branches.** Every per-frame tick added is wired into the `away_from_start` (derelict)
  branch **and** the home branch; each new smoke carries an `away_ticks=`-style assertion driving
  `away_from_start = true`.
- **Typed GDScript**; Resources are data, Nodes are behavior. New pure models are `RefCounted`/`Resource`
  with `get_summary()`/`apply_summary()` round-trip.
- **Baseline noise allowlist** unchanged; any other `ERROR:`/`WARNING:` blocks completion.
- Update `docs/game/06_validation_plan.md` with the new smokes and expected markers.
- Save-schema changes are **additive** (read via `.get(..., default)`); no `CURRENT_SLICE_VERSION` bump
  unless a field is removed in a way that breaks round-trip.

## Decisions locked (from brainstorming)

- **Ammo model = magazine/reload.** `ammo_state` is repurposed as a **per-weapon magazine** (loaded
  rounds); inventory remains the **reserve stock**. Combat fires from the magazine.
- **Timed reload (tension).** Reload takes **1.5s**; firing is blocked mid-reload; the reload timer ticks
  on **both** `_process` branches.
- **Empty-mag = dry-fire click.** Firing an empty magazine fails with a reload cue and does **not**
  auto-reload; the wasted-action teeth still apply. The player must manually reload.
- **Sealed-hatch doors (full mechanic).** A real locked-hatch interactable blocks a passage until bypassed;
  `lockpick`/`hack_chip` open mechanical/electronic hatches; generation seeds hatches on derelicts.
- **Thermal consumable.** A new `temperature_delta` effect + item shifts `body_temperature_state`, making
  the dead dispatcher branch live.
- **Flare closure.** `utility_flare` gets a real reader: while active it reduces sanity drain in unsafe
  zones ("steadies the player in dark corridors", per its use_note). Reuses Domain 1 sanity.

## Architecture / work items

### 1. Ammo → magazine/reload

- **`ammo_state.gd` repurposed** to a per-weapon magazine: `magazines: Dictionary` (`weapon_id → int`
  loaded rounds) + a `reload_active`/`reload_remaining`/`reload_weapon_id` timer block. Methods:
  `loaded(weapon_id) -> int`, `spend(weapon_id) -> bool` (decrement one; false if empty),
  `begin_reload(weapon_id, magazine_size, reserve_available) -> bool`, `tick(delta) -> bool` (returns true
  on reload completion so the coordinator can move rounds from inventory), `is_reloading() -> bool`.
  `get_summary()`/`apply_summary()` persist magazines + reload state additively.
- **`weapon_definitions.json`**: add `"magazine_size"` to each ranged weapon (flare_pistol, shock_probe,
  welding_lance); crowbar (melee, `ammo_item_id: ""`) has no magazine and always fires.
- **`threat_manager.attack_with_weapon`** (`:114-118`): replace the inventory read/decrement with a
  magazine check. Accept an `ammo_state`/magazine handle (via signature extension or a set reference).
  Empty magazine → `{ok:false, reason:"empty_magazine", ammo_item_id:...}`. On success decrement the
  magazine. `no_target` and the wasted-action teeth (`playable_generated_ship.gd:4133`) unchanged.
- **Reload input.** New `reload_weapon` action (KEY_R) registered alongside `attack_primary`
  (`playable_generated_ship.gd:450`, `DEFAULT_ATTACK_BINDINGS` pattern). `_input` (`:7374`) handles it →
  coordinator `begin_reload` for the equipped weapon if reserve stock > 0 and not already reloading.
- **Reload tick both branches.** `ammo_state.tick(delta)` runs in the home branch and the away branch; on
  completion the coordinator moves `min(magazine_size − loaded, inventory reserve)` from inventory into the
  magazine.
- **Save migration.** Old `ammo_summary` reserve-dict is ignored/repurposed; new magazine summary read
  additively. Reserve counts already live in inventory — no data loss.

### 2. Stim/addiction away-tick

- Add `stimulant_state.tick(delta, addiction_state, _consumable_pipeline_context())` and
  `addiction_state.tick(delta, status_effects_state)` to the away branch (`:5013-5079`), mirroring the home
  block (`:5102-5105`). Guard for null as the home branch does.

### 3. Sealed-hatch bypass sub-system

- **New `SealedHatch` node** (`scripts/interaction/sealed_hatch.gd` or `scripts/tools/`), a collision-bearing
  Node3D following the breach/arc-zone passability pattern (`playable_generated_ship.gd:5407-5417`): a
  collision shape whose `disabled` toggles with a `bypassed` flag. Fields: `hatch_id`, `lock_kind`
  (`"mechanical"`/`"electronic"`), `bypassed: bool`. Emits a `hatch_bypassed(hatch_id)` signal.
- **Bypass flow.** Use `lockpick_set`/`hack_chip` → `utility_item_resolver` sets the `*_ready` status/flag
  (20s window, `effect_definitions.json:18-19`). Interacting with a matching hatch while the flag is active
  → hatch `bypassed = true`, passage collision disabled, **flag consumed** (removed from `active_flags` and
  the status cleared). `lockpick_ready` opens `mechanical`; `hack_chip_ready` opens `electronic`. Mismatched
  or absent flag → interaction reports "locked / needs <tool>".
- **Generation seeding.** Loader emits hatch specs (mirror `get_loot_container_specs_copy` →
  `_build_sealed_hatches`), deterministic per seed; a small number of hatches placed on internal passages of
  a generated derelict. Built + cleared alongside loot containers; parented under a coordinator-owned root.
  Persisted (`bypassed` state) in the ship/world snapshot additively.
- **Both branches.** Hatch presence and the combined passability query include hatches on the away branch
  (hatches live on derelicts). Bypass interaction available while boarded.

### 4. Thermal consumable (temperature_delta)

- **`effect_definitions.json`**: add `"heatpack": {"kind": "temperature_delta", "amount": <+warmth>, ...}`
  (and optionally a coolant with negative amount). Confirm `effect_dispatcher.gd:55` reads the payload field
  it expects (`amount`/`delta`) and applies to `body_temperature_state`.
- **Item**: add a `heat_pack` utility/medicine item in the appropriate item-definitions file with
  `effects: ["heatpack"]`. Using it shifts `body_temperature_state`; the dispatcher branch is now live.

### 5. Flare closure

- Give `utility_flare` a reader: while the `utility_flare` status is active, the player counts as
  "steadied/lit" → **reduce sanity drain in unsafe zones** (a multiplier applied where `sanity_state.tick`
  or `_tick_survival_attrition` computes the unsafe-zone drain). Reuses the Domain 1 sanity model; no new
  system. The flare flag is thereby consumed (read) rather than decorative.

## Away-branch checklist

Reload timer tick · stim tick · addiction tick · sealed-hatch presence + bypass · thermal effect apply ·
flare sanity-steadying — all live/available on the `away_from_start` branch.

## Validation (register all in `06_validation_plan.md`)

- **`ammo_magazine_smoke.gd`** (pure-model + main-scene): magazine `spend` decrements; empty magazine →
  `empty_magazine` dry-fire (no shot, teeth still count); `begin_reload` + 1.5s of ticks refills from
  reserve; fire blocked while `is_reloading()`. `away_ticks=` asserts the reload timer advances and a shot
  fires from the magazine on a **derelict**.
  Marker e.g. `AMMO MAGAZINE PASS away_ticks=<n> spent=true dry_fire=true reloaded=true`.
- **`consumables_away_tick_smoke.gd`** (main-scene): drive `away_from_start = true`; a stim buff's timer and
  an addiction tolerance/withdrawal value advance across away ticks.
  Marker e.g. `CONSUMABLES AWAY TICK PASS away_ticks=<n> stim_decayed=true addiction_ticked=true`.
- **`sealed_hatch_smoke.gd`** (main-scene): prime lockpick (and hack_chip) → interact with a matching hatch
  → `bypassed=true`, passage collision disabled, flag consumed; mismatched flag does not open; hatch present
  on a **derelict** (`away_ticks=`).
  Marker e.g. `SEALED HATCH PASS away_ticks=<n> mechanical_open=true electronic_open=true flag_consumed=true`.
- **`thermal_consumable_smoke.gd`** (pure-model): dispatch `heatpack` → `body_temperature_state` shifts by
  the expected sign; dispatcher branch reached.
  Marker e.g. `THERMAL CONSUMABLE PASS temp_shifted=true`.
- Full regression bundle re-run green (`SYNAPTIC_SEA REGRESSION PASS`, `commands=` bumped for the 4 new
  smokes).

## Inventory delta (measurement mechanism)

- `consumables.closes → "closed"`; clear/reduce the five break-points (magazine consumption, orphan effects
  removed with the old file, stim/addiction away-tick, utility flags consumed by hatch bypass,
  `temperature_delta` live).
- Flip `ammo_state.output.live` (consumed by combat via magazine, cite `threat_manager` + coordinator),
  `utility_item_resolver.output.live` (flags consumed by hatch bypass + flare reader),
  `effect_dispatcher` temperature_delta note.
- Add inventory entries for the new `SealedHatch` model/manager and the reload/magazine state if catalogued;
  `tools/build_system_inventory.py` → `--check` (`SYSTEM INVENTORY CHECK PASS`) + `--coverage` clean.
- Distinguish **model tick** (both branches) from **player-facing output** (active-ship only) in any prose
  the change touches, to avoid the recurring contradiction defect.

## Critical files

- `scripts/systems/ammo_state.gd` — repurpose to magazine + reload timer.
- `scripts/systems/threat_manager.gd` — fire from magazine (`:114-118`).
- `scripts/procgen/playable_generated_ship.gd` — reload input + tick (both branches), stim/addiction away
  tick, sealed-hatch build/seed/interact + passability, thermal dispatch wiring, flare sanity reader,
  save/load.
- `scripts/interaction/sealed_hatch.gd` (**new**) — locked-hatch interactable.
- `scripts/systems/utility_item_resolver.gd` — flag consumption on bypass.
- `scripts/systems/effect_dispatcher.gd` — confirm `temperature_delta` payload (`:55`).
- `data/combat/weapon_definitions.json` — `magazine_size`.
- `data/items/effect_definitions.json` — `heatpack` effect; `data/items/<item defs>` — `heat_pack` item.
- **Remove** `data/items/ammo_definitions.json` (orphaned) + its `flare_burn`/`shock_jolt` references.
- New smokes: `ammo_magazine_smoke.gd`, `consumables_away_tick_smoke.gd`, `sealed_hatch_smoke.gd`,
  `thermal_consumable_smoke.gd`.
- `docs/game/inventory/system_inventory.json` (+ regenerated MD/HTML), `docs/game/06_validation_plan.md`.

## Risks

- **Re-touching the closed combat loop.** Moving ammo consumption from inventory to magazine changes
  `threat_manager.attack_with_weapon`, which Domain 2 closed. Mitigate: preserve `no_ammo`→`empty_magazine`
  semantics and the wasted-action teeth; keep existing combat smokes green as regression fences; the
  reserve stock stays in inventory (combat's source), only the final consumption indirects through the
  magazine.
- **Sealed-hatch is a mini-domain.** New interactable + seeding + passability integration is the largest
  chunk. Mitigate: reuse the breach/arc passability pattern and the loot-container seeding path verbatim;
  give the hatch its own smoke and own plan phase; keep it deterministic per seed.
- **Away-branch regression class.** The recurring failure. Mitigate: `away_ticks=` assertions in every new
  smoke; wire reload/stim/addiction/hatch on the away branch explicitly.
- **Save churn.** Magazine + hatch state + repurposed ammo_summary. Mitigate: additive reads; verify
  round-trip in the ammo/hatch smokes; keep the existing SaveLoadService rejection allowlist unchanged.
