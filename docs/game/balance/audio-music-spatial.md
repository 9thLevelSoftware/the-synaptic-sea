# Audio, Music, Spatial — Balance & Tuning Note

Source: `docs/game/build-plans/10-audio-music-spatial-e2e.md`
ADR: `docs/game/adr/0029-audio-music-spatial-architecture.md`

## Safe ranges

All numbers live in `data/audio/audio_bus_config.tres` or the per-model
defaults in `scripts/systems/audio_*.gd`. Designers can re-tune without
re-encoding code; the `AudioBusConfig.validate()` schema check rejects
values outside the documented range.

### Per-bus default volumes (dB)

| Bus | Default | Range | Rationale |
|---|---|---|---|
| master | 0.0 | [-60, 0] | Top-level mix. A master at -6 dB is common in cinematic mixes but the canonical preset is 0 dB so per-bus levels carry the relative balance. |
| sfx | -3.0 | [-60, 0] | Gameplay SFX must cut through ambient + music without dominating. |
| music | -6.0 | [-60, 0] | Music is the bed; lower than sfx so SFX always wins the ear. |
| voice | -3.0 | [-60, 0] | Voice lines carry critical story / log content; matched to sfx so dialogue and gameplay SFX sit on the same plane. |
| ui | -6.0 | [-60, 0] | UI confirmations are felt, not heard; quieter than gameplay. |
| ambient | -9.0 | [-60, 0] | Ambient is the floor; the crossfade machinery ensures only one layer is dominant. |
| meta | -6.0 | [-60, 0] | Meta-events are scripted beats; quieter than sfx so they don't drown transient combat SFX. |

### Crossfade timings (seconds)

| Surface | Value | Range | Source |
|---|---|---|---|
| Ambient zone crossfade | 1.5 | [0.1, 10.0] | `AmbientZoneState.DEFAULT_CROSSFADE_SECONDS` |
| Music layer crossfade | 2.0 | [0.1, 30.0] | `DynamicMusicState.DEFAULT_CROSSFADE_SECONDS` |
| Caption duration | 2.5 | [0.5, 10.0] | `SfxEventRouter.DEFAULT_CAPTION_DURATION` |

### Music state priority

`DynamicMusicState.resolve_state()` returns:

1. `CRITICAL` when `vitals_critical == true` (oxygen <= 0.0 OR hp < 0.25)
2. `COMBAT` when `engagement_flag == true` (no hostile AI in the Gate 2 slice; left as a hook for REQ-006/REQ-007's threat loop)
3. `TENSION` when `hazard_active == true` (any of oxygen / fire / arc hazards is non-safe)
4. `EXPLORATION` otherwise

The priority order is intentional: when vitals drop, the music must
scream regardless of combat or hazard intensity so the player knows they
are about to die.

### Per-state layer gain targets

| Layer | EXPLORATION | TENSION | COMBAT | CRITICAL |
|---|---|---|---|---|
| base | 1.0 | 0.6 | 0.5 | 0.3 |
| tension_drone | 0.0 | 0.7 | 0.4 | 0.4 |
| combat_percussion | 0.0 | 0.0 | 0.9 | 0.7 |
| critical_pad | 0.0 | 0.0 | 0.0 | 0.9 |

Layers stack (AudioManager uses max across layers for combined gain),
so transitioning to a richer state adds rather than replaces — except
for the `critical_pad` and `combat_percussion` layers which only enter
at their own state.

### Spatial attenuation

| Setting | Default | Range | Source |
|---|---|---|---|
| ref_distance | 2.0 m | [0.01, 1000] | `SpatialAudioResolver.DEFAULT_REF_DISTANCE` |
| max_distance | 25.0 m | [ref + 0.01, 10000] | `SpatialAudioResolver.DEFAULT_MAX_DISTANCE` |
| max_attenuation_db | -36 dB | [-120, 0] | `SpatialAudioResolver.DEFAULT_MAX_ATTENUATION_DB` |
| occlusion_penalty_db | -6 dB | [-60, 0] | `SpatialAudioResolver.DEFAULT_OCCLUSION_PENALTY_DB` |

Linear rolloff in dB space; identical inputs are required to produce
identical output for headless testability. NaN / Inf vector inputs clamp
to 0 before distance math so callers cannot introduce non-finite volume
into the `AudioStreamPlayer.volume_db` property.

### Threat-driven ambient gain

| Parameter | Default | Range | Source |
|---|---|---|---|
| threat_threshold | 0.5 | [0, 1] | `AmbientZoneState.DEFAULT_THREAT_THRESHOLD` |
| threat_boost | 0.25 | [0, 1] | `AmbientZoneState.DEFAULT_THREAT_BOOST` |

Combined ambient gain = role_intensity × (1 + max(0, threat - threshold) × threat_boost × 2).
At threat=1.0 the multiplier is 1.25; the boost is intentionally capped
so a fully-loaded threat meter doesn't drown out gameplay SFX.

### Meta-event default schedule

| Event | Trigger time (s) | Voice log entry | dB |
|---|---|---|---|
| beacon_distress | 12.0 | log.beacon_01 | -3.0 |
| biomatter_pulse | 30.0 | log.pulse_01 | -6.0 |
| hull_groan | 55.0 | (none) | -6.0 |

Schedule offset derives from `run_seed % 7 × 0.5` seconds so re-runs with
the same seed produce the same sequence (deterministic).

## Difficulty presets

A single canonical preset is shipped. Future difficulty work can add
`easy / standard / hard` Resource variants that override
`AudioBusConfig` volumes and `MetaEventState` schedule densities; the
architecture supports it without code changes (per ADR-0029, the bus
config is data).

## Validation evidence

- `scripts/validation/audio_bus_config_smoke.gd` — `AUDIO BUS CONFIG PASS`
- `scripts/validation/ambient_zone_state_smoke.gd` — `AMBIENT ZONE STATE PASS`
- `scripts/validation/sfx_event_router_smoke.gd` — `SFX EVENT ROUTER PASS`
- `scripts/validation/dynamic_music_state_smoke.gd` — `DYNAMIC MUSIC STATE PASS`
- `scripts/validation/spatial_audio_resolver_smoke.gd` — `SPATIAL AUDIO RESOLVER PASS`
- `scripts/validation/meta_event_state_smoke.gd` — `META EVENT STATE PASS`
- `scripts/validation/main_playable_slice_audio_smoke.gd` — `MAIN PLAYABLE AUDIO PASS`
- `scripts/validation/audio_save_load_smoke.gd` — `AUDIO SAVE LOAD PASS`
