# Feature: Audio, Music, Spatial Sound, Voice & Meta Events

Source package: `docs/game/build-plans/10-audio-music-spatial-e2e.md`
Architecture: `docs/game/adr/0029-audio-music-spatial-architecture.md`
Requirements covered: REQ-AU-001..010
Concept lock: Greenfield production audio layer (bus layout, ambient zones, SFX catalog, dynamic music layers, spatial attenuation/occlusion, voice/audio logs, meta-events).
Sargasso influence (not copy): ambient tension, directional SFX (creaks, groans, biomatter pulses), meta-events replacing the PZ helicopter/gunshot palette (biomatter pulses, distress beacons, hull groans).

## Player experience

A boarded player on a derelict hears a low ambient hum that shifts as they cross room roles (cargo hold, engine bay, med-bay, crew quarters), with breath and suit audio mixed above it. Picking up a tool triggers a short SFX through the `sfx` bus and prints a closed caption on the HUD. Combat raises the music from `exploration` to `tension` to `combat` based on real threat state, with a `critical` layer kicking in when vitals cross an unsafe threshold. Distant distress signals and biomatter pulses arrive as discrete meta-events through the `meta` bus, each carrying a deterministic clip id and an optional voice-log entry. A settings panel lets the player adjust each bus volume and toggle closed captions without reloading the run. Voice-log entries replay on demand through the `voice` bus.

## In-character translation

| PZ influence | Sargasso translation |
|---|---|
| Helicopter pass-by | Distress beacon (deterministic, scripted) |
| Gunshot audio cues | Hull groan meta-event + structural SFX |
| Zombie moans (directional) | Biomatter pulse + breathing ambient layer |
| Ambient thunder/rain | Hull-creak + reactor hum loop (per room role) |

## Acceptance criteria (Given/When/Then)

REQ-AU-001: All major gameplay events route through named audio events.
- Given a PlayableGeneratedShip with an attached `AudioManager`
- When any runtime system emits a named event (`sfx.tool.pickup`, `sfx.suit.breath`, `sfx.door.open`, `sfx.fire.crackle`, `sfx.arc.zap`, `ui.inventory.open`, `meta.beacon.distress`, etc.)
- Then the SfxEventRouter routes it to the correct bus (master / sfx / ui / voice / meta / ambient) with the configured volume and dedup cooldown.

REQ-AU-002: AudioBusConfig declares the full bus layout.
- Given the canonical bus config `res://data/audio/audio_bus_config.tres`
- When the playable loads
- Then the master, sfx, music, voice, ui, ambient, and meta buses exist with default dB values matching the spec.

REQ-AU-003: AmbientZoneState changes by room role and threat.
- Given the player traverses rooms of different role (cargo, engine, med-bay, crew_quarters, docking)
- When the player enters a new zone
- Then the ambient layer for that room role fades in (default 1.5s crossfade) and the previous room role fades out
- And the threat-driven intensity layer adds gain when the threat metric rises (any hazard state increases intensity by one tier).

REQ-AU-004: Dynamic music layers respond to gameplay state.
- Given the music state machine and per-state gain tables
- When the player enters combat (engagement flag) / tension (hazard active) / exploration (default) / critical (vitals unsafe)
- Then the target layer set is computed deterministically and the gains are crossfaded
- And the resulting layer combination matches the configured rule.

REQ-AU-005: SpatialAudioResolver is deterministic and testable.
- Given a listener position and an emitter position with a known occlusion flag
- When `resolve_volume_db(emitter_pos, listener_pos, occluded, base_db)` is called
- Then the returned dB value matches the deterministic formula `(base_db) - (distance_attenuation) - (occlusion_penalty)`
- And identical inputs always produce identical output (no random noise).

REQ-AU-006: Voice log entries replay through the `voice` bus.
- Given a registered audio-log entry
- When the player triggers playback (or the meta-event scheduler queues a voice line)
- Then the entry plays through the `voice` bus with the configured volume
- And the entry id appears in the playback UI list.

REQ-AU-007: MetaEventState schedules deterministic scripted events.
- Given a run seed and a list of meta-event specs (id, trigger_time, voice_log_entry_id)
- When the run elapses past the trigger time
- Then the meta-event fires on the `meta` bus and any associated voice-log entry is queued.

REQ-AU-008: Audio settings panel exposes per-bus volume controls.
- Given the audio settings panel is open
- When the player adjusts a bus slider
- Then the AudioManager applies the new dB and persists the audio_summary
- And on reload the dB values are restored.

REQ-AU-009: Closed captions appear for SFX events.
- Given a SFX event has a caption mapping
- When the SFX event fires
- Then the caption text appears in the HUD for the configured duration
- And the caption respects the closed-caption toggle in the audio settings panel.

REQ-AU-010: Audio summary round-trips through save/load.
- Given a run snapshot with non-default audio state
- When the snapshot is saved then reloaded
- Then the audio_summary is restored and every sub-summary (bus_config, ambient, sfx_router, music, spatial, meta_event) re-applies to the live models.

## Non-goals

- No real audio file mastering; placeholder silence / sine-tone WAVs are acceptable for headless validation.
- No voice acting scripts; voice-log entries are data-only (transcript + clip path placeholder).
- No procedural music composition; layer crossfade between pre-authored stems.
- No middleware (FMOD / Wwise); pure Godot Audio buses only.
- No spatial HRTF personalization; the deterministic attenuation curve is the only spatialization surface.
- No audio settings persistence beyond the active save slot (no per-user global prefs).
- No music beat-synced gameplay triggers.

## Verification

- `scripts/validation/audio_bus_config_smoke.gd` — `AUDIO BUS CONFIG PASS`
- `scripts/validation/ambient_zone_state_smoke.gd` — `AMBIENT ZONE STATE PASS`
- `scripts/validation/sfx_event_router_smoke.gd` — `SFX EVENT ROUTER PASS`
- `scripts/validation/dynamic_music_state_smoke.gd` — `DYNAMIC MUSIC STATE PASS`
- `scripts/validation/spatial_audio_resolver_smoke.gd` — `SPATIAL AUDIO RESOLVER PASS`
- `scripts/validation/meta_event_state_smoke.gd` — `META EVENT STATE PASS`
- `scripts/validation/main_playable_slice_audio_smoke.gd` — `MAIN PLAYABLE AUDIO PASS`
- `scripts/validation/audio_save_load_smoke.gd` — `AUDIO SAVE LOAD PASS`
- All seven plus save/load registered in `docs/game/06_validation_plan.md` regression bundle.

## Stop/block conditions

- Missing audio bus config file (`res://data/audio/audio_bus_config.tres`) cannot be defaulted in code without losing schema validation.
- `AudioStreamPlayer` or `AudioServer` is unavailable in headless mode and a test-only seam cannot substitute.
- An existing ADR directly contradicts the package architecture; ADR update required.
- Regression failures unrelated to this package are reported with evidence, not silently absorbed.
