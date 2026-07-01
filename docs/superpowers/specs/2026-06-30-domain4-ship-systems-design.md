# Domain 4 — Ship Systems closure + Web Infestation foundation (design spec)

**Date:** 2026-06-30
**Status:** approved in brainstorming; pending written-spec review.
**Roadmap:** closes Domain 4 of `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md`
(loop `ship_systems`, currently `🟡 partial`). Domains 1–3 (survival, combat, food) are merged.

## Context

The `ship_systems` loop is structurally complete but `partial` on two verified break-points (line
numbers are live as of this spec; the roadmap's were pre-Domains-1–3 and have drifted):

1. **Hull has no live damage source.** `hull_integrity_state.damage_compartment()`
   (`scripts/systems/hull_integrity_state.gd:21`) is only called by the config seed
   (`playable_generated_ship.gd:1325`) and the validation seam `force_hull_breach_for_validation`
   (`:1426`). Nothing in real play damages the hull, so `hull_integrity_state.input.live = false`.
2. **Hub sim is home-only.** `ship_systems_manager.advance()` (`:4972`) +
   `_recompute_expanded_ship_systems()` (`:4973`) run only *after* the `away_from_start`
   early-return at `:4906`. On a boarded derelict (the primary gameplay context) the hub ship's
   power / propulsion / life-support / hull simulation does not advance.

The hull's *outputs* are already live and wired: `get_breach_count()` → life-support atmosphere
drain (`:1366`) → vitals (Domain 1); `average_integrity()` → propulsion `hull_penalty` (`:1358`);
player seals breaches at `BreachSealPoint`s configured at `:2580` (hull_sealant). So closing the
loop needs a **live input**, not new outputs.

## The damage source: web infestation (the game's premise, made live)

The project premise is a hub ship **"trapped in a biomatter web."** Domain 4 makes that literal: the
web is a slime-mold contagion that slowly devours the hull of any ship it is attached to. The hub is
web-attached from the start (it is trapped), so its hull is under constant slow attrition — the
player holds the line by sealing breaches. This is the live damage source, and it is on-theme rather
than a bolted-on "pressure" abstraction.

**Decisions locked (from brainstorming):**

1. **Scope: foundation now, full web later.** This spec delivers a per-ship `WebInfestationState`
   model that (a) gives the hub hull its live damage source and (b) seeds the spread mechanic, and
   closes the `ship_systems` loop green. The **full contagion system** — dock-graph spread across
   multiple persistent derelicts, the "cut a ship free from the web" action and its dangers,
   "reaching" / re-contact after a cut, and per-derelict hull so the web damages each ship's own
   hull — is a **dedicated follow-on spec**, sequenced with the Phase-5 docking-graph work
   (`ship_instance.gd:40-42` `parent_ship` / `docked_ships` / `docking_ports` are declared but
   **"Phase 5 stubs — unused this phase"**, so the full spread mechanic is blocked on docking
   becoming live).
2. **Live damage source = web infestation.** The hub is attached by default; coverage grows over
   time and inflicts hull damage. A **foundation contagion seed**: while docked to a still-attached
   derelict, the hub's web growth is boosted (the slime-mold creeps onto your docked ship).
3. **Fully live persistent sim — no pausing.** Once procgen generates a derelict it is live and
   persistent (stations, power draw, hazards), the same as the ship you docked with. The hub's
   `ship_systems_manager.advance` + the expanded recompute + the web tick run on **both** `_process`
   branches. This **revives powered stations/crafting while away**, superseding the `:4948` inline
   "powered-station crafts pause while away" convention (ADR-0038 is updated to record the change;
   it was an emergent side-effect of the home-only recompute, not a hard architectural rule).

## Architecture

### Model / Node separation (follows the existing per-ship pattern)

`ShipInstance` (`scripts/systems/ship_instance.gd`) already bundles per-ship `systems_manager` and a
lazily-created per-ship `fire` (FireSuppressionState), each with `get_summary`/`apply_summary`
persistence. `WebInfestationState` drops in the same way `fire` did.

**New model — `scripts/systems/web_infestation_state.gd` (`extends RefCounted`, typed):**

```
class_name WebInfestationState

var attached_to_web: bool = true          # is this ship in contact with the web
var coverage: float = 0.0                 # 0..1 infestation level
var growth_rate: float = ...              # coverage/sec while attached (from config)
var recession_rate: float = ...           # coverage/sec while cut free (from config)
var damage_rate: float = ...              # hull damage/sec at full coverage (from config)
var contact_boost: float = ...            # extra growth/sec while docked to an attached derelict

func configure(config: Dictionary) -> void           # load rates from web_infestation.json
func tick(delta: float, contact: bool) -> float       # advance coverage; return hull damage this tick
func cut_free() -> void                                # attached_to_web = false (foundation hook)
func get_summary() -> Dictionary                       # {hazard_kind, attached_to_web, coverage}
func apply_summary(summary: Dictionary) -> bool        # validates hazard_kind == "web_infestation"
func get_status_lines() -> PackedStringArray           # HUD: "Web Infestation NN%"
```

- `tick(delta, contact)`: if `attached_to_web`, `coverage += (growth_rate + (contact_boost if
  contact else 0)) * delta`, clamped to 1.0; else `coverage -= recession_rate * delta`, clamped to
  0.0. Returns `coverage * damage_rate * delta` (the hull-damage magnitude the coordinator applies).
- **Hazard contract:** web infestation is a continuous growth/drain hazard, not phase-based — the
  same exemption class as `oxygen_state` (ADR-0005 reserves `PhaseTimer` + `Phase.A/B` for
  phase-based hazards; oxygen is the documented non-timer precedent). `get_summary()` still carries a
  `hazard_kind: "web_infestation"` discriminator that `apply_summary()` validates, for save
  robustness. It is **not** added to `hazard_contract_smoke.gd` (which enforces the PhaseTimer
  contract); it gets its own pure-model smoke.

**New config — `data/ship_systems/web_infestation.json`:** `{ "growth_rate", "recession_rate",
"damage_rate", "contact_boost", "seed_coverage" }`. Rates tuned slow (long-game pressure, not a
death spiral); exact values set in the plan and balanced so the closure smoke can drive a breach in a
bounded number of ticks while normal play stays survivable via sealing.

### Coordinator wiring (`playable_generated_ship.gd`)

**Ownership:** the coordinator owns `hull_web_state` (a `WebInfestationState`) for the hub hull,
created and `configure`d alongside `hull_integrity_state` (`:1324-1325`) and persisted in the
expanded-systems summary (`_expanded_ship_systems_summary`, `:1401`) + restored in the load path
(`:6312`). Derelict `ShipInstance`s gain a lazily-created `web` field (mirroring `fire`) so the
contagion seed has a per-derelict attachment flag; for the foundation, derelicts generate
web-attached and their `web` model exists primarily to source the hub's `contact` boost. (Per-derelict
hull damage is the follow-on, since derelicts have no hull model yet.)

**Live damage application (both branches):** each tick, `var dmg := hull_web_state.tick(delta,
_active_derelict_web_attached())`; distribute `dmg` across `hull_integrity_state.compartments` via
`damage_compartment(cid, share)`. `_active_derelict_web_attached()` returns true while away and the
`current_ship`'s `web.attached_to_web` is true (the contagion seed); false at home.

**Both-branch sim (BP2) — required refactor to avoid double-ticks:** the away branch already ticks
the *derelict's* fire (`_active_fire_state().tick` at `:4935`), fire→system damage (`:4937`), and
field crafting (`:4950`). `_recompute_expanded_ship_systems` *also* ticks fire (`:1369-1374`) and
field crafting (`:1391`). To run the recompute on both branches without double-ticking those:

1. **Extract** the fire tick + `_apply_fire_system_damage` (`:1369-1374`) and the `field_crafting`
   tick (`:1391`) **out of** `_recompute_expanded_ship_systems`. The home branch calls them
   explicitly once (as the away branch already does); the slimmed recompute no longer touches them.
2. The slimmed `_recompute_expanded_ship_systems(delta)` (power rebalance, propulsion, life-support,
   crafting/station power, recharge port, sustenance) then runs on **both** branches.
3. On the **away** branch, before the early `return` at `:4964`, add: `ship_systems_manager.advance(
   delta)`, the `hull_web_state` damage application, and `_recompute_expanded_ship_systems(delta)` —
   placed so they coexist with the existing away ticks (threat/sanity/fire/survival/audio/food)
   without disturbing them.
4. The home branch keeps its existing `advance` (`:4972`) + recompute (`:4973`), now plus the
   `hull_web_state` damage application and the explicit fire/field-crafting calls extracted in (1).

**Revived stations away:** because the slimmed recompute drives station power on both branches,
powered crafting now advances while away. Update the `:4948-4949` comment to reflect the live-sim
decision; add a one-line note to `docs/game/adr/0038-crafting-materials-stations-architecture.md`
recording that the away-pause convention is superseded; fix any smoke that asserted the pause.

### Save / persistence

`hull_web_state.get_summary()` is added to `_expanded_ship_systems_summary()` (`:1401`) under
`web_infestation_summary` and restored in the expanded-systems apply path (`:6307-6334`). Derelict
`web` round-trips via `ShipInstance.get_summary/apply_summary` (under `"web"`, only when attached or
coverage > 0), mirroring `fire`. **Additive only** — older saves lacking the field load with the
default (`attached_to_web = true`, `coverage = 0.0`); `RunSnapshot.CURRENT_SLICE_VERSION` is **not**
bumped (the `.get(key, {})` read path already tolerates a missing field, per the Domain 3 precedent).

## Definition of CLOSED

1. `hull_integrity_state` takes **live damage** from `hull_web_state` in real play (not only config
   seed / validation seam) — `input.live = true` with the web citation.
2. `ship_systems_manager.advance` + the expanded recompute + the web tick run on the **away**
   branch (verified by an `away_ticks=` assertion), so the hub sim is live while boarded.
3. Powered stations/crafting advance on both branches (live-sim decision); the away-pause comment +
   ADR note updated.
4. `ship_systems.closes → "closed"` in the inventory with both break-points cleared; `--check`
   passes; the full regression bundle ends `SYNAPTIC_SEA REGRESSION PASS`.

## Away-branch checklist (the mandatory global constraint)

On the `away_from_start` branch: `hull_web_state.tick` + hull-damage application · `ship_systems_
manager.advance` · slimmed `_recompute_expanded_ship_systems` (power/propulsion/life-support/
crafting/sustenance) — all live, with no double-tick of the fire/field-crafting the branch already
owns.

## Validation

- **`web_infestation_state_smoke.gd`** (pure model): attached → `coverage` grows and `tick` returns
  damage > 0; `cut_free()` → coverage recedes and damage falls to 0; `get_summary`/`apply_summary`
  round-trip; `apply_summary` rejects a wrong/missing `hazard_kind`. Marker e.g.
  `WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true`.
- **`ship_systems_closure_smoke.gd`** (main-scene, drives `away_from_start = true`): assert on the
  away branch that (a) `hull_web_state` advanced and damaged a hull compartment, (b)
  `ship_systems_manager.advance` ran, (c) a resulting breach raised `get_breach_count()` and engaged
  the life-support atmosphere → vitals drain on the derelict. Include an `away_ticks=` value in the
  marker, e.g. `SHIP SYSTEMS CLOSURE PASS away_ticks=N hull_web_damage=true advance_ran=true
  breach_to_vitals=true`.
- Register both in `docs/game/06_validation_plan.md` (new `run_clean` lines; bump `commands=`); the
  bundle must stay clean against the unchanged baseline noise allowlist.

## Inventory delta

- `ship_systems.closes → "closed"`; clear both `break_points` (or reduce to documented deferrals
  pointing at the follow-on web spec).
- `hull_integrity_state.input.live → true` with `desc`/`at` citing `hull_web_state` and the
  both-branch application site.
- Re-confirm `ship_systems_manager` / `power_grid_state` / `propulsion_expanded_state` /
  `life_support_expanded_state` coupling now that the recompute runs on both branches.
- Regenerate `SYSTEM_INVENTORY.md` + `system_map.html` via `tools/build_system_inventory.py`;
  `--check` marker `SYSTEM INVENTORY CHECK PASS` must pass.

## Non-goals (explicitly deferred to the follow-on web spec)

- Dock-graph contagion spread across multiple persistent derelicts (blocked on Phase-5 docking).
- The "cut a derelict free from the web" player action and its dangers; "reaching" / re-contact.
- Per-derelict hull integrity (so the web damages each ship's own hull, not just the hub's).
- The "keep a flyable ship clear of the web" steady-state and any web-driven win/lose end state.
- Web visual/FX, audio, and any new asset content.

## Risks

- **Coordinator churn.** Extracting the fire + field-crafting ticks out of the shared recompute is
  the delicate change; a missed call site means a double- or zero-tick. Mitigated by: the extraction
  is mechanical (move two blocks, add explicit home-branch calls), and the closure smoke asserts
  fire/field-crafting still tick exactly once per branch via existing markers + the bundle's
  unexpected-WARNING gate.
- **Reviving stations away touches a closed loop (crafting).** Mitigated by updating the comment +
  ADR + the one affected smoke, and by the crafting loop's own smokes remaining green in the bundle.
- **Balance.** Web rates too high → unwinnable hull spiral; too low → loop closes but never bites.
  Mitigated by config-driven rates and a closure smoke that pins the "drives a breach in N ticks"
  behavior.
