# ADR-0029: Audio, Music, Spatial Sound, Voice & Meta Events Architecture

Status: Accepted
Date: 2026-06-25
Source package: `docs/game/build-plans/10-audio-music-spatial-e2e.md`
Requirements: REQ-AU-001..010
Feature spec: `docs/game/features/audio-music-spatial.md`

## Context

The Synaptic Sea playable slice has shipped pure-model gameplay systems (oxygen, fire, arc hazards, inventory, ship systems, route control, vitals) but no audio layer. Headless Godot validation does not need real audio playback, but the runtime architecture and player-facing feedback must be production-grade: every gameplay event must route through a named audio event, ambient layers must respond to room role and threat, dynamic music must respond to vitals and combat, spatialization must be deterministic, voice / audio log entries must replay, and meta-events (Project Zomboid's helicopter/gunshot palette, translated in-character as distress beacons / biomatter pulses / hull groans) must fire deterministically.

Headless `AudioServer` boots without a device and stream players load silence, so the runtime path is fully exercisable in CI. The architecture must therefore validate end-to-end without requiring a sound card.

## Decision

### Bus layout (REQ-AU-002)

Seven Godot AudioServer buses, in `res://data/audio/audio_bus_config.tres`:

| Bus | Default dB | Range | Purpose |
|---|---|---|---|
| `master` | 0.0 | [-60, 0] | Top-level mix output |
| `sfx` | -3.0 | [-60, 0] | Gameplay SFX (tools, doors, fire crackle, arc zap) |
| `music` | -6.0 | [-60, 0] | Music layer crossfade target |
| `voice` | -3.0 | [-60, 0] | Voice-log entries and voice lines |
| `ui` | -6.0 | [-60, 0] | UI confirmations (open/close) |
| `ambient` | -9.0 | [-60, 0] | Per-room-role ambient loops |
| `meta` | -6.0 | [-60, 0] | Meta-event dispatches (beacons, pulses, groans) |

All buses are children of `master`. The `AudioBusConfig` Resource validates every bus at load time (non-empty id, unique, recognized name, clamped dB).

### Pure-model-first architecture (parallels ADR-0005)

Six pure RefCounted models under `scripts/systems/`, plus the AudioBusConfig Resource. Each follows the standard Synaptic Sea model contract (configure / tick / get_summary / apply_summary / get_status_lines) — the same shape as `FireState` and `ElectricalArcState`, adapted for non-passability audio state:

1. **`AudioBusConfig`** (`Resource`, not RefCounted — it is data) — bus layout and per-bus volumes. `apply_bus_volumes(audio_server: AudioServer)` pushes dB values to the runtime buses.
2. **`AmbientZoneState`** (`RefCounted`) — current room role, transition state, threat meter. `set_room_role(role_id)` starts a crossfade; `set_threat_level(intensity)` adjusts the threat-driven gain.
3. **`SfxEventRouter`** (`RefCounted`) — event-id to bus-id + volume + cooldown + caption map. `route(event_id)` returns the routed bus and pushes the event through `AudioManager`. Captions queue in the router's caption queue and are exposed via `get_pending_captions()`.
4. **`DynamicMusicState`** (`RefCounted`) — four-state machine (EXPLORATION / TENSION / COMBAT / CRITICAL) with per-state layer set and per-layer crossfade.
5. **`SpatialAudioResolver`** (`RefCounted`) — deterministic `resolve_volume_db(emitter_pos, listener_pos, occluded, base_db)` with linear rolloff and configurable occlusion penalty.
6. **`MetaEventState`** (`RefCounted`) — deterministic seed-derived schedule; `tick(delta)` fires events whose `trigger_time` has elapsed and records them in the summary.

### AudioManager service (NOT an autoload)

`scripts/audio/audio_manager.gd` is owned by `PlayableGeneratedShip`, never an autoload. AGENTS.md forbids autoload god-objects; the manager is a service owned by the playable that:

- owns an `AudioStreamPlayer` per bus (one each for sfx, music, voice, ui, ambient, meta — all routed through `master`)
- owns an `AudioStreamPlayer3D` pool for spatial emitters (REQ-AU-005)
- owns an `AudioListener3D` that follows the player node
- exposes `play_sfx(event_id, position=null)`, `set_bus_volume(bus_id, db)`, `transition_music(target_state)`, `attach_listener(node)`, `play_voice_log(entry_id)`, `trigger_meta_event(event_id)`, `apply_summary(summary_dict)`, `get_summary() -> Dictionary`
- rebuilds state from the six pure-model summaries each `_refresh_audio_state` (mirrors `_refresh_fire_state`)

### Event catalog and routing (REQ-AU-001)

Typed constant table at `scripts/audio/audio_event_seam.gd`:

```
SfxEventIds.SFX_TOOL_PICKUP        -> bus=sfx, caption="Tool acquired"
SfxEventIds.SFX_SUIT_BREATH        -> bus=sfx, caption=null, cooldown=2.0
SfxEventIds.SFX_DOOR_OPEN          -> bus=sfx, caption="Door opened"
SfxEventIds.SFX_FIRE_CRACKLE       -> bus=sfx, caption=null, cooldown=0.5
SfxEventIds.SFX_ARC_ZAP            -> bus=sfx, caption=null, cooldown=0.5
SfxEventIds.UI_INVENTORY_OPEN      -> bus=ui, caption=null, cooldown=0.25
SfxEventIds.META_BEACON_DISTRESS   -> bus=meta, caption="Distress signal received"
SfxEventIds.META_BIOMATTER_PULSE   -> bus=meta, caption=null
SfxEventIds.VOICE_LOG_PLAY         -> bus=voice, caption=null
```

Unknown event ids are logged via `push_warning` and dropped — never silently routed to `master`.

### Closed captions (REQ-AU-009)

`SfxEventRouter` exposes `get_pending_captions() -> Array[Dictionary]` (entry: `{event_id, text, remaining_seconds}`). The audio_settings_panel drains the queue each frame and renders captions on the HUD using `accessibility_settings.scaled_hud_font_size`. The closed-caption toggle suppresses the caption queue drain without affecting SFX playback.

### Save/load integration (REQ-AU-010)

`RunSnapshot.audio_summary` is the 9th summary field. It contains six sub-dicts (`bus_config`, `ambient`, `sfx_router`, `music`, `spatial`, `meta_event`) — each matching the corresponding model's `get_summary()` shape so `apply_summary` round-trips it. The SaveLoadService smoke `summaries` count rises from 8 to 9.

### Why this architecture

- **Pure models stay scene-tree-free** — `SpatialAudioResolver` operates on plain `Vector3` arguments and never reaches into the scene; `AudioManager` is the only scene-aware object.
- **Headless testable** — every model smoke and the main-scene smoke exercise the full event-routing path without an audio device.
- **Deterministic** — no RNG in any model; meta-event schedule is seed-derived; spatial attenuation is a pure function.
- **Backward compatible** — `AudioBusConfig`, `AmbientZoneState`, `SfxEventRouter`, `DynamicMusicState`, `SpatialAudioResolver`, `MetaEventState` are additive; existing systems (oxygen, fire, arc, ship systems, route control) are not modified.

## Consequences

- `AudioManager` must own an `AudioStreamPlayer` pool for non-spatial buses even though headless playback is silent — the smoke verifies the pool exists and is wired.
- Adding new event ids requires (a) extending `AudioEventIds`, (b) adding a caption in the catalog if desired, (c) calling `AudioManager.play_sfx(id)` from the emitting site.
- The audio settings panel cascades through `AccessibilitySettings` (A11Y-P1-001), so any future HUD font scale change applies to audio panel labels without further work.
- Save/load smoke `summaries` count is hard-coded; any future model addition requires bumping that count from 9.

## Alternatives considered

- **Autoload AudioManager** — rejected. AGENTS.md explicitly forbids autoload god-objects, and the manager is closely tied to scene lifecycle (listener position, scene-tree cleanup).
- **Single `AudioState` mega-class** — rejected. Six small pure models each with one responsibility are easier to test, easier to swap, and easier to summarize into save state.
- **Real HRTF spatialization** — out of scope per REQ-AU-005 non-goals. Deterministic attenuation + occlusion is sufficient and testable in headless.
- **FMOD / Wwise middleware** — out of scope. Godot's native `AudioServer` is enough for the Gate 1/2 vertical slice.
