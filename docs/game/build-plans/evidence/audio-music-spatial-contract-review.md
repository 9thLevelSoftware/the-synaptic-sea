# Audio / Music / Spatial / Voice / Meta Events — Contract Review

Source plan: `docs/game/build-plans/10-audio-music-spatial-e2e.md`
Package range: REQ-AU-001..010
Author: synaptic_seaworker (Task 10, run 6)

## Existing assets that must be extended, not replaced

| Area | Existing | Disposition |
|---|---|---|
| Pure state model pattern | `scripts/systems/fire_state.gd`, `electrical_arc_state.gd`, `oxygen_state.gd` (all `RefCounted` with `class_name`, `configure(config)`, `tick`, `get_summary`, `apply_summary`, `get_status_lines`) | Match exactly for every new pure model under `scripts/systems/` |
| Hazard model contract | ADR-0005 (`HazardStateContract` — Phase A/B + passability) | NOT reused here: audio models are not passability hazards. Define a parallel `AudioModelContract` (configure / tick / get_summary / apply_summary / get_status_lines) so downstream model and main-scene smokes can assert uniform shape. |
| Save snapshot shape | `scripts/systems/run_snapshot.gd` (eight summaries), `save_load_service.gd` (single-slot `user://saves/current_run.json`) | Add `audio_summary` as a ninth summary. Slot count rises to 9; the model smoke asserts `summaries=9`. No new save paths, no new slots. |
| Scene coordinator pattern | `scripts/procgen/playable_generated_ship.gd` owns scene node, owns pure model, applies summary to scene state in `_refresh_<thing>_state` | Audio follows the same shape: `audio_manager` (autoload-style service, not autoload per AGENTS.md) owned by the playable, with `_refresh_audio_state(force)` reading summaries and pushing to `AudioStreamPlayer` volume / `AudioListener3D` orientation |
| HUD style | `scripts/ui/accessibility_settings.gd` (A11Y-P1-001 scale seam), `player_vitals_panel.gd`, `objective_tracker.gd` | Audio settings panel reuses `accessibility_settings.scaled_hud_font_size` so A11Y-P1-001 cascades. |
| Main scene entry | `scenes/main.tscn` + `scripts/main.gd` | New audio panels attach to existing HUD root in `_build_runtime_nodes`; no new top-level scenes. |

## Greenfield files this package creates

Pure models (`scripts/systems/`):
- `audio_bus_config.gd` — `class_name AudioBusConfig` (Resource): bus layout (master, sfx, music, voice, ui, ambient, meta), per-bus volume dB, mute/solo, schema validation
- `ambient_zone_state.gd` — `class_name AmbientZoneState` (RefCounted): per-room-role ambience assignment, threat-driven intensity, transition rules
- `sfx_event_router.gd` — `class_name SfxEventRouter` (RefCounted): event-id to bus-id + volume + cooldown map, throttling, dedup
- `dynamic_music_state.gd` — `class_name DynamicMusicState` (RefCounted): layered music state machine (exploration / tension / combat / critical) with per-layer gain and transition rules
- `spatial_audio_resolver.gd` — `class_name SpatialAudioResolver` (RefCounted): deterministic distance attenuation + line-of-sight occlusion
- `meta_event_state.gd` — `class_name MetaEventState` (RefCounted): scripted meta-event schedule (biomatter pulse, distress signal, ship groan) with deterministic seeds and per-event SFX voice-line queue

Runtime service (`scripts/audio/`):
- `audio_manager.gd` — service object owned by `PlayableGeneratedShip`; reads summaries from the six models, drives `AudioStreamPlayer` volumes / bus indices and an `AudioListener3D`, exposes `play_sfx(event_id)`, `set_bus_volume(bus_id, db)`, `transition_music(target_state)`, `attach_listener(node)`, `play_voice_log(entry_id)`, `trigger_meta_event(event_id)`
- `audio_event_seam.gd` — typed constant table of event IDs and meta-event IDs, shared with smokes and UI
- `audio_log.gd` — voice-log entry registry (id, label, transcript, clip path, duration)

UI (`scripts/ui/`):
- `audio_settings_panel.gd` — per-bus volume sliders, mute toggles, accessibility text-scale cascade, closed-caption toggle, voice-log toggle
- `audio_log_panel.gd` — voice-log playback list, current entry, play/pause/stop, jump-to-entry

Persistence:
- Extend `scripts/systems/run_snapshot.gd` with `audio_summary` field (9th summary) and add to `SUMMARY_FIELDS`
- `audio_summary` is a flat dictionary with per-model sub-dicts (`bus_config`, `ambient`, `sfx_router`, `music`, `spatial`, `meta_event`)

Smokes (`scripts/validation/`):
- `audio_bus_config_smoke.gd`
- `ambient_zone_state_smoke.gd`
- `sfx_event_router_smoke.gd`
- `dynamic_music_state_smoke.gd`
- `spatial_audio_resolver_smoke.gd`
- `meta_event_state_smoke.gd`
- `main_playable_slice_audio_smoke.gd`

Docs:
- `docs/game/features/audio-music-spatial.md` (feature spec)
- `docs/game/adr/0029-audio-music-spatial-architecture.md`
- `docs/game/05_requirements.md` rows REQ-AU-001..010
- `docs/game/07_risk_register.md` row RISK-AU
- `docs/game/06_validation_plan.md` regression bundle entries
- `docs/game/balance/audio-music-spatial.md` (tuning note)
- `docs/game/09_system_roadmap.md` update
- `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md` update (per `13-systems-map-task-graph-update-e2e` which is a sibling card and will own the canonical merge; this package writes a patch draft)

## Non-extension seams (explicitly NOT reused)

- Autoloads: AGENTS.md forbids autoload god-objects. `AudioManager` is owned by `PlayableGeneratedShip`, not an autoload.
- Existing hazard `PhaseTimer`: not reused. Music uses its own internal scheduler because layer crossfades need cross-phase duals (A and B together for the duration of the fade), not a single-A-or-B toggle.
- SaveLoadService file layout: no new save paths or slots. Single `user://saves/current_run.json` is preserved.

## Existing ADR conflicts

None located. ADR-0005 (`HazardStateContract`) does not collide because audio models are not passability hazards. ADR-0007 (save/load scope) is respected: only the active ship slice writes audio state.
