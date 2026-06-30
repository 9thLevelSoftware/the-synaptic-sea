# Domain 2: Combat — Design Spec

> Part of the Completion Roadmap (`docs/superpowers/specs/2026-06-28-completion-roadmap-design.md`).
> Closes the `combat` loop (currently 🟡 partial → 🟢 closed).

## Goal

Make the threat/combat loop a real gameplay system instead of a decorative one, by closing its three verified break-points:

1. **Detection becomes the single source of truth** the enemy AI actually consumes (today it's a parallel HUD-only calc).
2. **Stealth is driven by genuine runtime signals** (movement, derived lighting, proximity, and a new crouch action) instead of hardcoded literals.
3. **Killing a threat is rewarding**: the corpse becomes a lootable container, the kill grants XP through the progression bus, and the dead threat is removed from the active array.

The player should be able to *sneak* (real noise/light/visibility/crouch counterplay against per-archetype senses) and be *rewarded* for kills (loot + XP), on derelicts as well as at home.

## Scope decisions (locked via brainstorming)

- **BP1 detection model:** *Per-enemy senses.* `detection_state` produces the player's emitted detectability profile (single source); each threat perceives that profile through its own archetype sensitivities + threshold. Preserves per-archetype variety; kills the duplicate calc.
- **BP2 stealth depth:** *Full.* All four signals real — movement noise, derived lighting, proximity visibility, and a new crouch input action.
- **BP3 reward + corpse:** *Lootable corpse container.* On death the corpse becomes an interactable `LootContainer` collected through the existing closed loot/interact path; the kill grants XP; the dead threat is removed from `threats[]`.
- **Kill-XP target:** data-driven `threat_killed` training action → interim skill `scavenging` (matches the scavenge-the-corpse reward). Deliberately re-targetable; see Non-goals.

## Tech stack / conventions

- Godot 4.6.2, typed GDScript. Model/Node separation (Resources = data, Nodes = scene consequences).
- Headless `--script` smokes (`extends SceneTree`, single `... PASS ...` marker). Trust the marker, not the exit code.
- **Both `_process` branches.** Combat happens primarily on a boarded derelict; every new per-frame system and the kill→reward→removal path must run on the `away_from_start` (derelict) branch as well as home. Validation drives `away_from_start=true` with an `away_ticks=`-style assertion.
- Done = loop green: `combat.closes == "closed"` in `docs/game/inventory/system_inventory.json`, regenerate views, `--check` passes, full regression bundle ends `SYNAPTIC_SEA REGRESSION PASS`.

---

## Current state (verified, with code references)

**Signal plumbing.** `_tick_threat_runtime(delta)` (`playable_generated_ship.gd:3905`) calls
`threat_manager.set_player_signals(noise, light, sight, crouching, room_id)` with near-hardcoded literals
(`0.2`/`0.05` noise from `is_moving`, `0.35` light, `0.55` sight, `false` crouch, `""` room).
`threat_manager.tick_threats` (`threat_manager.gd:65`) forwards these to
`detection_state.update_inputs(player_noise, player_light, player_sight, player_crouching, player_room_id)` (`:66`)
AND builds a per-threat AI context (`:76`) containing the same raw `noise_level/light_level/sight_level` plus
`detect_threshold: detection_state.detect_threshold` (`:81`).

**Dual awareness (BP1).** `detection_state` computes `detected/awareness_score/heard/seen` used **only** for the HUD line
(`threat_manager.gd:187`, `"Threat Indicator: %.2f detected=%s"`). Each threat's AI **independently** recomputes its own
`awareness_score` from the raw signals × its archetype sensitivities (`threat_ai_state.gd:88-94`), borrowing only the
static `detect_threshold`. The detection model's computed awareness is therefore decorative.

**Dead room signal (BP2).** `player_room_id` is fed `""`, so the AI's `same_room` (`threat_ai_state.gd:97`) is always false;
`player_light`/`player_sight` are constants. Only noise has a tiny live `is_moving` component.

**Corpses linger, no reward (BP3).** A threat enters `STATE_DEAD` (`threat_ai_state.gd:81,132`) but is never removed:
`_pick_target` (`threat_manager.gd:255`) merely skips `health <= 0.0`. No loot, no XP. Archetypes
(`data/combat/threat_archetypes.json`: `biomatter_swarm, puppet_corpse, stalker, mimic, hull_tendril`) carry combat stats
(`max_health, attack_damage, *_sensitivity, armor, tags`) but **no reward fields**.

**Reusable infrastructure already present.**
- `LootContainer` (`scripts/tools/loot_container.gd`): `configure(container_id, loot_table, seed_source, inventory_state, tables, world_position, radius, loot_context)`; the coordinator owns `loot_container_root: Node3D` + `loot_containers: Array` and rolls via `LootRoller`/`LootDistribution` against `data/items/loot_tables.json`. Collected through the existing interact dispatcher (`_on_player_interact_requested`) — the closed loot loop.
- Occupancy: `recompute_occupancy()` / `get_current_occupancy_for_validation()` resolve the player's current ship/room.
- Progression: `emit_training_event(event_id, target_id)` (`playable_generated_ship.gd:1503`) → `training_event_bus.emit` → `progression.grant_xp(skill_id, base_xp)`, driven by `data/player/training_actions.json` (`event_id → {target_skill, base_xp, category}`).
- Input: actions are built at runtime from an action→keycodes dict (`playable_generated_ship.gd:426`) and registered via `InputMap.add_action` (`:5217`); `player_controller.gd` reads them via `InputMap.has_action`/`Input.get_action_strength`.

---

## Design

### BP1 — Detection as the single source of truth (per-enemy senses)

`detection_state` becomes the **canonical producer of the player's emitted detectability profile** for the frame:

- New/clarified output on `detection_state`: an **emitted profile** `{emitted_noise, emitted_light, emitted_visibility}` — the
  effective signal the player gives off after global stealth modifiers (crouch reduction applied once, here, not per-threat).
  Its existing HUD aggregate (`awareness_score`/`detected`) is recomputed from this profile so it is a **real** summary, not decorative.
- `threat_manager.tick_threats` builds each threat's AI context from `detection_state`'s emitted profile (single source),
  **not** from the raw `player_*` fields. Concretely, the context keys `noise_level/light_level/sight_level` are sourced from
  `detection_state.emitted_*`. Each threat still applies its own `noise_sensitivity/light_sensitivity/sight_sensitivity` and the
  archetype `detect_threshold` (`threat_ai_state.gd:88-94`) → **per-archetype perception** of one shared signal.
- The AI no longer reads any signal the detection model didn't produce. The `detect_threshold` borrow from
  `detection_state.detect_threshold` is removed in favor of the archetype's own threshold (each threat already owns its threshold context).

**Interface:** `detection_state.update_inputs(...)` continues to receive the raw player signals + crouch and now exposes
`get_emitted_profile() -> Dictionary` (`{emitted_noise, emitted_light, emitted_visibility}`) consumed by `tick_threats`.
Single producer, N per-archetype consumers.

**Definition of CLOSED (BP1):** changing `detection_state`'s emitted profile changes what every threat perceives (verified by a
smoke that perturbs the profile and observes threat `awareness_score`), and two archetypes with different sensitivities perceive
the *same* profile differently. No code path computes threat awareness from a signal detection didn't produce.

### BP2 — Full stealth from real runtime signals

`_tick_threat_runtime` computes the four signals from live state each frame and passes them to `set_player_signals` (both branches):

- **noise** ← movement: `is_moving` (and, where available, speed) maps to a noise value; crouch multiplies it down. (Deepens the
  existing tiny `is_moving` component into the real noise driver.)
- **visibility (sight)** ← proximity: derived from the player's **current room** (occupancy `player_room_id`, now fed from
  `recompute_occupancy()` instead of `""`) and distance to each threat — same-room + nearer ⇒ more visible. Crouch reduces it.
  `player_room_id` flowing real also revives the AI's `same_room` gate.
- **light** ← derived lighting: a `_player_room_lit()` signal from the player's current-room **power/lit state** (a lit/powered room
  ⇒ higher emitted light ⇒ more visible; an unpowered/dark/breached room ⇒ lower ⇒ stealthier). Derived from the existing ship
  systems / power model for the player's occupied ship+room; no new lighting renderer.
- **crouch** ← a new `crouch` **InputMap action** added to the runtime action-map dict (`playable_generated_ship.gd:426`) and
  registered with the others. `player_controller.gd` reads it (held). Crouching: (a) lowers emitted noise & visibility (applied in
  `detection_state` as the global stealth modifier), and (b) reduces move speed by composing with Domain 1's
  `_speed_multiplier` (a crouch factor multiplied into the effective speed — does **not** fight the vitals gate; both apply).

**Definition of CLOSED (BP2):** each of noise/light/visibility/crouch is driven by a genuine runtime value (no literal placeholders
remain in `_tick_threat_runtime`'s `set_player_signals` call), verified by a smoke asserting: moving raises noise vs idle; the
player's lit room raises emitted light vs a dark room; same-room/near raises visibility vs far/other-room; holding crouch lowers
emitted noise & visibility and reduces effective move speed.

### BP3 — Lootable corpse + kill XP, corpse removed

When a threat transitions to `STATE_DEAD`, the coordinator (in a shared kill-handler called from both branches):

1. **Reward — loot:** spawn a `LootContainer` at the corpse's world position, configured with the archetype's `loot_table`
   (new per-archetype data field), registered in `loot_containers[]` under `loot_container_root`. The player collects it through the
   existing interact dispatcher → closed loot loop. The container persists until collected or a despawn timeout.
2. **Reward — XP:** `emit_training_event("threat_killed", archetype_id)` → XP via the progression bus (interim skill `scavenging`, a small `base_xp` e.g. 10, optionally scaled by the archetype's `xp` override).
3. **Removal:** remove the dead threat from `threats[]` and despawn its placeholder node (`placeholder_nodes[instance_id]`), so corpses
   don't linger. The kill-handler is idempotent per threat (a `rewarded` flag so a kill rewards/removes exactly once).

**Data additions:**
- `data/combat/threat_archetypes.json`: add `loot_table` (string, e.g. `combat_drop_common`) per archetype; optional `xp` override.
- `data/items/loot_tables.json`: add a combat drop table (e.g. `combat_drop_common`) — reuse/compose existing item pools.
- `data/player/training_actions.json`: add `threat_killed → {target_skill: "scavenging", base_xp: 10, category: "combat"}` (base value; re-targetable per Non-goals).

**Definition of CLOSED (BP3):** a kill (a) spawns a lootable container at the corpse whose collection grants the archetype's loot
through the real interact path, (b) emits a `threat_killed` training event that grants XP, and (c) removes the dead threat from the
active array (and despawns its placeholder) exactly once.

### Both-branches wiring

`_tick_threat_runtime` already runs on the `away_from_start` (derelict) branch. The new work that must also run away:
the real stealth-signal computation, the detection-driven AI context (inside `tick_threats`, branch-agnostic), and the
**kill→reward→removal handler**. The detection feed and kill handler are invoked from the threat tick / a post-tick sweep that runs
on both branches. The validation smoke boards a derelict (`away_from_start=true`) and asserts a kill there produces the container +
XP + removal.

### Validation

`combat_closure_smoke.gd` (scene smoke on `scenes/main.tscn`, driving the live coordinator `_process`):
- **BP1:** perturb `detection_state`'s emitted profile → a threat's `awareness_score` changes; two archetypes with different
  sensitivities perceive the same profile differently; assert no awareness is computed from a non-detection signal.
- **BP2:** assert moving > idle noise; lit room > dark room emitted light; same-room/near > far visibility; crouch lowers
  emitted noise/visibility and reduces effective move speed.
- **BP3:** kill a threat through the live tick → assert a `LootContainer` appears at the corpse and is collectable via the interact
  dispatcher (grants an item), `emit_training_event("threat_killed", …)` fired (XP granted), and the threat is gone from `threats[]`.
- **Away:** drive `away_from_start=true` and assert a derelict kill rewards + removes (the `away_ticks=`/`away_kill=` assertion).

Pure-model smokes extended where the change is model-level (`detection_state` emitted profile; `threat_ai_state` consuming it).
Register all new markers in `docs/game/06_validation_plan.md` and bump `commands=`.

### Inventory delta

In `docs/game/inventory/system_inventory.json`:
- `combat.closes → "closed"`; rewrite its `break_points` to a closure note + any documented deferral.
- `detection_state.output.live → true` (now consumed by the AI as the single source) + update desc/`at`; clear stale gaps.
- `threat_ai_state.output.live → true` (kill → reward/removal) + update desc; clear stale gaps.
- Touch `threat_manager` / `loot`-adjacent edges where health grades change (e.g. detection→AI edge `weak → healthy`).
Regenerate `SYSTEM_INVENTORY.md` + `system_map.html`; `--check` / `--coverage` / selftest pass; full bundle green.

---

## Non-goals (explicitly deferred)

- **Verbose skill overhaul (Project Zomboid / Barotrauma–style).** The kill-XP target (`scavenging`) is a **data-driven interim**
  mapping in `training_actions.json`; when the expanded skill system lands (Domain 6: Progression & Meta), it re-points the
  `threat_killed` action to the proper combat skill line with **no Domain 2 code change**. Domain 2 does not add a new skill,
  skill-tree node, or unlock.
- **New enemy archetypes / behaviors / animations.** Domain 2 closes the loop with the existing 5 archetypes; no new content breadth.
- **Weapon/damage rebalance.** The `damage_pipeline` + `armor_resolver` already apply; Domain 2 does not retune damage numbers
  beyond what's needed for the loot/XP/removal path.
- **Pathfinding / nav-mesh AI.** The AI stays state-machine driven (idle/investigate/hunt/attack/flee); no navigation rewrite.
- **Lighting renderer.** "Light" is a derived gameplay signal from room power state, not a real lighting/shadow system.

## Risks & mitigations

- **Crouch vs Domain 1 movement gate.** Crouch must *compose* with `_speed_multiplier`, not overwrite it. Mitigation: crouch is a
  separate multiplicative factor into effective speed; a smoke asserts crouch + low-vitals both apply (crouch while exhausted is
  slower than either alone, and never faster than walking).
- **Double-reward / double-remove on death.** A threat could be seen `STATE_DEAD` across multiple frames. Mitigation: a per-threat
  `rewarded` guard so the kill-handler fires exactly once; smoke asserts a second tick does not spawn a second container.
- **Away-branch starvation (the line-4808 class).** The kill handler and stealth feed must run on the derelict branch. Mitigation:
  wire into the both-branches threat path; the smoke's `away_kill=` assertion fails if the handler is home-only.
- **Detection refactor changing HUD numbers.** Recomputing the HUD aggregate from the emitted profile may shift the displayed
  indicator. Mitigation: the home combat/HUD regression smokes must stay green; if a HUD assertion shifts, confirm it reflects the
  now-real signal rather than masking a regression.
