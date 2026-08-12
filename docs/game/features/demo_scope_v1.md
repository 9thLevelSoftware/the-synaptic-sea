# Feature: Demo Scope v1 (Milestone B bounds)

## Status

Active documentation of **what DemoScopeGate enforces today** and **proposed Milestone B** bounds for the public itch demo. Does not by itself flip `build_kind` to `demo`.

Related:

- Contract: `docs/game/features/vertical_slice_v1.md` (Milestone A)
- Plan: `.hermes/plans/2026-08-11_215934-production-grade-e2e.md` Phase 6
- Gate impl: `scripts/systems/demo_scope_gate.gd`
- Manifest: `data/release/demo_scope_manifest.json`
- Build meta: `data/release/build_metadata.json`

## How the gate works (code truth)

`DemoScopeGate` is a **blocklist** for `build_kind == "demo"`:

- `dev` / `release`: all features allowed (manifest ignored for blocking)
- `demo`: feature_ids listed in `demo_blocked_features` are blocked; everything else allowed
- Entries may carry machine-readable `params` via `get_params(feature_id)`

Configured on the live coordinator:

- `scripts/procgen/playable_generated_ship.gd` ~1390–1391  
  `demo_scope_gate.configure(manifest, build_metadata_state)`

Current `build_metadata.json`:

| Field | Value |
|---|---|
| `version` | `v0.1.0` |
| `build_kind` | **`dev`** (demo restrictions not active in normal local runs) |
| `store` | `itch` |
| `valid_build_kinds` | `dev`, `demo`, `release` |
| `demo_hub_unlocked_features` | `oxygen_breach`, `fire_hazard`, `objective_progress` (metadata; not the gate blocklist) |

## Manifest today (`demo_blocked_features`)

| feature_id | params | Intent (from JSON) |
|---|---|---|
| `cargo_hold.full_inventory` | `max_weight_kg: 6.0` | Cap ship cargo to 6 kg in demo (full ~500 kg) |
| `multi_hazard.run` | `max_hazards: 1` | Single hazard seed budget on derelicts |
| `long_run.persistence` | `max_play_seconds: 1200` | Refuse **new** saves after 20 minutes; existing saves kept |
| `world_persistence.cross_run` | (none) | Strip/limit cross-run world persistence behavior in demo |
| `hub.meta_progression` | (none) | Block hub meta purchase / class persistence paths |

## Production enforcement callsites (verified)

| Feature | Where | Behavior |
|---|---|---|
| Configure gate | `playable_generated_ship.gd:1390-1391` | Owns gate instance |
| `long_run.persistence` | `playable_generated_ship.gd:_demo_save_cap_seconds` / `_demo_save_refused` ~9664–9674 | Save refused after cap when blocked |
| `multi_hazard.run` | `playable_generated_ship.gd:_demo_max_hazards` ~9676–9681 | Returns max hazards or -1 unlimited |
| `cargo_hold.full_inventory` | `playable_generated_ship.gd:_apply_demo_cargo_cap` ~9683–9694 | Caps hold `max_weight` |
| `world_persistence.cross_run` | `playable_generated_ship.gd` ~10088+ (world snapshot path) | Demo strips/limits visited-ship cross-run payload (see enforcement smoke) |
| `hub.meta_progression` | `menu_coordinator.gd` ~816–840 | Blocks hub upgrade / meta confirm persistence when gate injected |

Smokes:

- `scripts/validation/demo_scope_gate_smoke.gd` (pure model)
- `scripts/validation/demo_scope_enforcement_smoke.gd` (coordinator production callsites)

## What is NOT enforced yet (gaps for Milestone B)

- **No max derelicts / travel hop count** in manifest
- **No biome/difficulty whitelist** (slice wants `breach_field` + `standard` as face, not hard-gated today)
- **No hard session end at 90 minutes** (only 20 min **save** refusal)
- **Cloud** is already a stub (`CloudManifestState`); not a demo blocklist row
- **Steamworks** absent (correct)
- `build_kind` remains **`dev`** until export packaging flips it
- `demo_hub_unlocked_features` is informational metadata — do not confuse with gate blocklist
- Manifest reasons still mention outdated Gate 2/3 language — treat params/code as truth

## Proposed Milestone B demo bounds

Align with Vertical Slice v1 public face, then extend playtime:

| Bound | Proposal | Mechanism |
|---|---|---|
| `build_kind` | `demo` on itch channels | `build_metadata.json` + export script stamp |
| Default face | biome `breach_field`, difficulty `standard` | first-run contract + travel defaults |
| Playtest seeds | `42`, `777` | content contract (A); demo may randomize after first hop |
| Max derelicts visited | **4** (hub + 3 away) | **new** manifest feature + coordinator check (not implemented yet) |
| Save budget | keep **20 min** auto-refuse **or** raise to **45 min** after playtests | `long_run.persistence.max_play_seconds` |
| Session hard cap | **90 minutes** wall-clock soft end → results | **new** (not implemented); optional |
| Hazards | keep `max_hazards: 1` for simpler first public build **or** raise to 2 after A playtests | `multi_hazard.run` |
| Cargo | keep 6 kg **or** raise to ~50 kg if playtests find it unfun | `cargo_hold.full_inventory` |
| Hub meta | keep blocked purchases in demo | `hub.meta_progression` |
| Cross-run world | keep blocked / stripped | `world_persistence.cross_run` |
| Cloud / Steam | disabled / absent | no SDK; stub only |
| Platforms | Windows x86_64 + macOS required; Linux optional | export presets |
| Content length target | 60–90 minutes variety | content depth phases, not gate alone |
| Threats | at least slice three fully presented | art gate + catalogs |

## Demo-ready acceptance (gate + packaging)

- [ ] `build_kind=demo` export boots title and New Game
- [ ] Enforcement smoke green on exported demo binary (or headless equivalent)
- [ ] All five current blocklist rows still intentional and playtested
- [ ] Max-derelict (or equivalent breadth cap) implemented if public demo needs it
- [ ] Store page + screenshots use live vertical-slice presentation
- [ ] Known issues list shipped beside build
- [ ] Vertical Slice Milestone A exit criteria met first

## Out of scope

- Steamworks achievements upload
- Full EA biome/threat breadth
- Cloud sync
- Turning demo into unlimited sandbox (`release` kind)

## Validation

```bash
GODOT=${GODOT:-/Users/christopherwilloughby/.local/bin/godot-4.6.2}
$GODOT --headless --path . -s res://scripts/validation/demo_scope_gate_smoke.gd
$GODOT --headless --path . -s res://scripts/validation/demo_scope_enforcement_smoke.gd
# Expect DEMO SCOPE markers / PASS lines from those smokes
```

## Risks

| Risk | Mitigation |
|---|---|
| Shipping with `build_kind=dev` | Export checklist must set `demo` |
| 6 kg cargo feels broken | Playtest before locking B numbers |
| 20 min save cap confuses players | Results copy + store page explain demo limits |
| Stale Gate language in manifest reasons | Refresh copy when touching JSON |
