# Domain 9: Audio (Bus + Pipeline) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register a real Godot `AudioBusLayout` so bus-volume pushes are no longer inert, prove the stream-loading path with two placeholder WAVs that actually play, and pump `SfxEventRouter` captions to the HUD on both `_process` branches — closing the `audio_reactive` loop per the roadmap's Domain 9 scope.
**Architecture:** `AudioBusLayout` (`data/audio/default_bus_layout.tres`) owns boot-time bus existence/hierarchy registered via `project.godot`'s new `[audio]` section; `AudioBusConfig` (existing pure Resource) keeps owning runtime volume/mute state and the save round-trip. `AudioManager` (the only scene-aware audio object, owned by `PlayableGeneratedShip`) gains a `STREAM_CATALOG` + `_loaded_streams` cache to lazily `load_from_file()` and `.play()` two placeholder clips, plus a `_engine_bus_name()` translation at the single `AudioServer.get_bus_index()` boundary so the pure model's lowercase `master` id resolves to the engine's immutable `"Master"`. Captions flow `SfxEventRouter` → `AudioManager.pump_captions()` → `_refresh_audio_state()` (already called on both branches) → a new `_last_caption_line` HUD member, with `SettingsState.captions` unified as the single source of truth for the caption toggle.
**Tech Stack:** Godot 4.6.2 GDScript (typed), headless SceneTree validation smokes, Python stdlib (`wave`) for asset generation

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (the `_console` build — required for headless runs so stdout/markers are captured).
- **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- Every validation command in this plan follows this exact pattern:
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke_name>.gd
  ```
- **PASS markers are the contract, never exit codes.** Godot `--script` can exit 0 on parse/load errors — a run only counts as passing when the exact marker string appears in stdout AND no unexpected `ERROR:`/`WARNING:` line is present.
- **Allowlisted noise only** (ignore these two lines wherever they appear; anything else is a failure that must be classified before proceeding):
  ```
  ERROR: Capture not registered: 'gdaimcp'.
  WARNING: ObjectDB instances leaked at exit (run with --verbose for details).
  ```
- **Never invoke Godot with `--editor`** on this machine — it injects autoloads and mutates `project.godot` as a side effect. Every command in this plan is `--headless --script` or a plain `--path` windowed run explicitly called out; never substitute `--editor`.
- **`project.godot` is surgical-only.** The only change permitted anywhere in this plan is inserting one `[audio]` section (Task 1). Run `git diff project.godot` immediately after any Godot invocation to catch unintended mutation.
- **Never stage `.godot/`, `*.uid` files, or `addons/`.** Every `git add` step in this plan lists exact file paths — never `git add -A` or `git add .`.
- **Typed GDScript** for all new code (function signatures, local vars where the type isn't already obvious from a literal).
- **Pure models never touch the scene tree.** `SfxEventRouter`, `AudioBusConfig`, `AudioEventSeam`, and the other five audio pure models stay `RefCounted`/`Resource`; only `AudioManagerScript` (a `Node`) and `playable_generated_ship.gd` touch `AudioServer`/`AudioStreamPlayer`/the scene tree.
- **`playable_generated_ship.gd::_process` has two branches** (`away_from_start` early-return vs. the home path) — both already call `_refresh_audio_state(false, delta)` (away at line 5358, home at line 5445) after `audio_manager.tick(delta)`, so the caption pump added inside `_refresh_audio_state` in Task 4 is structurally wired to both branches without touching `_process` itself. Do not add a second, branch-specific pump call.
- **Bundle must end** `SYNAPTIC_SEA REGRESSION PASS commands=121 clean_output=true` (112 existing `run_clean` lines + 8 newly-registered existing audio smokes + 1 new `audio_pipeline_smoke` = 121).
- Subagent implementers add **no commit trailers** — commit messages end at the Conventional Commits summary line, nothing appended.

## Task 1: Bus layout registration + Master-name translation

**Files:**
- Create: `C:/Users/dasbl/Documents/The Synaptic Sea/data/audio/default_bus_layout.tres`
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/project.godot` (insert `[audio]` section between `[application]` and `[display]`)
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/scripts/audio/audio_manager.gd` (add `_engine_bus_name`, update `_apply_bus_volumes`)

**Interfaces:**
- Produces: `AudioManagerScript._engine_bus_name(bus_id: StringName) -> String` — returns `"Master"` for `&"master"`, `String(bus_id)` otherwise.
- Consumes: `AudioServer.get_bus_index(name: String) -> int` (engine API), `bus_config.buses` (existing `AudioBusConfig` field).

- [ ] Create the directory `data/audio/` (already exists) and write `data/audio/default_bus_layout.tres` with exactly this content:
  ```
  [gd_resource type="AudioBusLayout" format=3]

  [resource]
  bus/1/name = &"sfx"
  bus/1/solo = false
  bus/1/mute = false
  bus/1/bypass_fx = false
  bus/1/volume_db = -3.0
  bus/1/send = &"Master"
  bus/2/name = &"music"
  bus/2/solo = false
  bus/2/mute = false
  bus/2/bypass_fx = false
  bus/2/volume_db = -6.0
  bus/2/send = &"Master"
  bus/3/name = &"voice"
  bus/3/solo = false
  bus/3/mute = false
  bus/3/bypass_fx = false
  bus/3/volume_db = -3.0
  bus/3/send = &"Master"
  bus/4/name = &"ui"
  bus/4/solo = false
  bus/4/mute = false
  bus/4/bypass_fx = false
  bus/4/volume_db = -6.0
  bus/4/send = &"Master"
  bus/5/name = &"ambient"
  bus/5/solo = false
  bus/5/mute = false
  bus/5/bypass_fx = false
  bus/5/volume_db = -9.0
  bus/5/send = &"Master"
  bus/6/name = &"meta"
  bus/6/solo = false
  bus/6/mute = false
  bus/6/bypass_fx = false
  bus/6/volume_db = -6.0
  bus/6/send = &"Master"
  ```

- [ ] Read `project.godot` and confirm it still contains exactly these three sections in this order: `[application]`, `[display]`, `[rendering]` (verify with `Read` before editing — if the file has drifted from this shape, stop and re-derive the exact insertion point instead of guessing). Then insert a new `[audio]` section directly between `[application]` and `[display]`, using this exact edit:
  - Old string:
    ```
    config/icon="res://icon.svg"

    [display]
    ```
  - New string:
    ```
    config/icon="res://icon.svg"

    [audio]

    buses/default_bus_layout="res://data/audio/default_bus_layout.tres"

    [display]
    ```

- [ ] Open `scripts/audio/audio_manager.gd` and add the `_engine_bus_name` helper directly above `_apply_bus_volumes` (currently at line 100). Old string:
  ```
  ## Push per-bus dB values into AudioServer. Skipped for buses that
  ## AudioServer doesn't know about (e.g. in headless tests where the
  ## .tres has not been loaded). The pure-model state remains the source
  ## of truth in that case.
  func _apply_bus_volumes() -> void:
  	for bus in bus_config.buses:
  		if typeof(bus) != TYPE_DICTIONARY:
  			continue
  		var bus_id: String = String(bus.get("id", ""))
  		if bus_id.is_empty():
  			continue
  		var bus_idx: int = AudioServer.get_bus_index(bus_id)
  		if bus_idx < 0:
  			# Bus not registered in AudioServer yet (headless / pre-init).
  			# Skip without error so the manager survives --script mode.
  			continue
  		var vol_db: float = float(bus.get("volume_db", 0.0))
  		var muted: bool = bool(bus.get("muted", false))
  		AudioServer.set_bus_volume_db(bus_idx, vol_db)
  		AudioServer.set_bus_mute(bus_idx, muted)
  ```
  New string:
  ```
  ## Translate a pure-model bus id (lowercase, e.g. &"master") to the engine's
  ## AudioServer bus name. Godot's bus 0 is immutably named "Master" (capital
  ## M) and AudioServer.get_bus_index("master") always returns -1 for it; the
  ## six child buses (sfx/music/voice/ui/ambient/meta) need no translation
  ## because their names already match between the pure model and the engine.
  ## This is the ONLY place the Master-name mismatch is bridged — every
  ## AudioServer boundary call goes through this helper (ADR-0044).
  func _engine_bus_name(bus_id: StringName) -> String:
  	if String(bus_id) == String(AudioEventSeamScript.BUS_MASTER):
  		return "Master"
  	return String(bus_id)

  ## Push per-bus dB values into AudioServer. Skipped for buses that
  ## AudioServer doesn't know about (e.g. in headless tests where the
  ## .tres has not been loaded). The pure-model state remains the source
  ## of truth in that case.
  func _apply_bus_volumes() -> void:
  	for bus in bus_config.buses:
  		if typeof(bus) != TYPE_DICTIONARY:
  			continue
  		var bus_id: String = String(bus.get("id", ""))
  		if bus_id.is_empty():
  			continue
  		var engine_name: String = _engine_bus_name(StringName(bus_id))
  		var bus_idx: int = AudioServer.get_bus_index(engine_name)
  		if bus_idx < 0:
  			# Bus not registered in AudioServer yet (headless / pre-init).
  			# Skip without error so the manager survives --script mode.
  			continue
  		var vol_db: float = float(bus.get("volume_db", 0.0))
  		var muted: bool = bool(bus.get("muted", false))
  		AudioServer.set_bus_volume_db(bus_idx, vol_db)
  		AudioServer.set_bus_mute(bus_idx, muted)
  ```

- [ ] Verify `project.godot` was touched surgically and nothing else drifted:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git diff project.godot
  ```
  Expected: a 6-line addition (`[audio]` blank line, `buses/default_bus_layout=...`, blank line) and nothing else. If any other line shows as changed, stop and investigate before proceeding — do not continue with a project.godot diff you did not author.

- [ ] Write a throwaway verification script (NOT committed) to confirm bus registration works exactly as the spec's pre-verified probe found. Create `scripts/validation/_task1_bus_probe.gd`:
  ```gdscript
  extends SceneTree
  # THROWAWAY — deleted before commit. Verifies AudioBusLayout registration
  # + AudioManager._engine_bus_name translation before the full pipeline
  # smoke (Task 6) exists.

  const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")

  func _initialize() -> void:
  	if AudioServer.bus_count != 7:
  		push_error("PROBE FAIL: bus_count=%d expected 7" % AudioServer.bus_count)
  		quit(1)
  		return
  	if AudioServer.get_bus_index("Master") != 0:
  		push_error("PROBE FAIL: Master bus_index=%d expected 0" % AudioServer.get_bus_index("Master"))
  		quit(1)
  		return
  	for bus_id in ["sfx", "music", "voice", "ui", "ambient", "meta"]:
  		if AudioServer.get_bus_index(bus_id) < 1:
  			push_error("PROBE FAIL: bus '%s' did not resolve" % bus_id)
  			quit(1)
  			return
  	var mgr := AudioManagerScript.new()
  	get_root().add_child(mgr)
  	await process_frame
  	if mgr._engine_bus_name(&"master") != "Master":
  		push_error("PROBE FAIL: _engine_bus_name(master) != Master")
  		quit(1)
  		return
  	if mgr._engine_bus_name(&"sfx") != "sfx":
  		push_error("PROBE FAIL: _engine_bus_name(sfx) != sfx")
  		quit(1)
  		return
  	for bus in mgr.bus_config.buses:
  		var bus_id: String = String(bus.get("id", ""))
  		var expected_db: float = float(bus.get("volume_db", 0.0))
  		var engine_name: String = mgr._engine_bus_name(StringName(bus_id))
  		var idx: int = AudioServer.get_bus_index(engine_name)
  		if idx < 0:
  			push_error("PROBE FAIL: bus '%s' -> engine '%s' did not resolve" % [bus_id, engine_name])
  			quit(1)
  			return
  		var actual_db: float = AudioServer.get_bus_volume_db(idx)
  		if absf(actual_db - expected_db) > 0.01:
  			push_error("PROBE FAIL: bus '%s' volume_db=%s expected %s" % [bus_id, str(actual_db), str(expected_db)])
  			quit(1)
  			return
  	print("TASK1 BUS PROBE PASS bus_count=7 master_translated=true volumes_agree=true")
  	mgr.queue_free()
  	quit(0)
  ```
  Run it:
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/_task1_bus_probe.gd
  ```
  Expected output contains `TASK1 BUS PROBE PASS bus_count=7 master_translated=true volumes_agree=true` and no `ERROR:`/`WARNING:` line beyond the two allowlisted ones.

- [ ] Delete the throwaway probe (it must never be committed):
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  rm scripts/validation/_task1_bus_probe.gd
  ```

- [ ] Re-run the existing pure-model smoke to confirm it is unaffected (it does not touch AudioServer, so it must still pass byte-identically):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_bus_config_smoke.gd
  ```
  Expected marker: `AUDIO BUS CONFIG PASS buses=7 default=true summary_round_trip=true`

- [ ] Re-run `main_playable_slice_audio_smoke.gd` (it boots the full playable scene, so this is the first real regression check against the new bus layout):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_audio_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE AUDIO PASS buses=6 routed=4 fired_meta=3 ambient_role=engine`

- [ ] Stage and commit only the named files:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git add data/audio/default_bus_layout.tres project.godot scripts/audio/audio_manager.gd
  git commit -m "feat: register AudioBusLayout and translate Master bus name at the AudioServer boundary"
  ```

## Task 2: Placeholder audio asset generator

**Files:**
- Create: `C:/Users/dasbl/Documents/The Synaptic Sea/tools/generate_placeholder_audio.py`
- Create (generated, committed as binary): `C:/Users/dasbl/Documents/The Synaptic Sea/data/audio/sfx/tool_pickup.wav`
- Create (generated, committed as binary): `C:/Users/dasbl/Documents/The Synaptic Sea/data/audio/music/exploration_base.wav`

**Interfaces:**
- Produces: two 16-bit mono PCM WAV files at fixed sample rate 22050 Hz.
- Consumes: Python stdlib `wave`, `struct`, `math`, `os` only — no third-party dependencies.

- [ ] Write `tools/generate_placeholder_audio.py`:
  ```python
  #!/usr/bin/env python3
  """Generate deterministic placeholder audio clips for Domain 9 (audio bus +
  pipeline) proof-of-stream-loading. Stdlib `wave` only, no randomness — every
  re-run produces byte-identical output so the committed .wav files are a
  reproducible build artifact, not a one-off asset.

  Produces:
    data/audio/sfx/tool_pickup.wav      ~0.25s 16-bit mono PCM @ 22050 Hz
    data/audio/music/exploration_base.wav ~1.5s 16-bit mono PCM @ 22050 Hz, loopable

  Both are pure sine-wave synthesis with a linear fade-in/fade-out envelope so
  the loop point (music clip) and the transient (sfx clip) do not click.
  """
  from __future__ import annotations

  import math
  import os
  import struct
  import wave

  SAMPLE_RATE = 22050
  ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


  def _envelope(i: int, n: int, fade_samples: int) -> float:
      """Linear fade-in/fade-out envelope, 1.0 in the steady region."""
      if n <= 0:
          return 0.0
      if i < fade_samples:
          return i / float(fade_samples)
      if i >= n - fade_samples:
          return (n - 1 - i) / float(fade_samples)
      return 1.0


  def _write_sine_wav(path: str, duration_s: float, frequencies: list[float], amplitude: float, fade_s: float) -> None:
      n = int(SAMPLE_RATE * duration_s)
      fade_samples = max(1, int(SAMPLE_RATE * fade_s))
      os.makedirs(os.path.dirname(path), exist_ok=True)
      with wave.open(path, "wb") as wf:
          wf.setnchannels(1)
          wf.setsampwidth(2)  # 16-bit
          wf.setframerate(SAMPLE_RATE)
          frames = bytearray()
          for i in range(n):
              t = i / float(SAMPLE_RATE)
              sample = 0.0
              for freq in frequencies:
                  sample += math.sin(2.0 * math.pi * freq * t)
              sample /= float(len(frequencies))
              sample *= amplitude * _envelope(i, n, fade_samples)
              clamped = max(-1.0, min(1.0, sample))
              frames += struct.pack("<h", int(clamped * 32767.0))
          wf.writeframes(bytes(frames))


  def main() -> int:
      # SFX: a short two-tone "pickup" chirp (ascending interval), 0.25s.
      sfx_path = os.path.join(ROOT, "data", "audio", "sfx", "tool_pickup.wav")
      _write_sine_wav(sfx_path, duration_s=0.25, frequencies=[880.0, 1320.0], amplitude=0.6, fade_s=0.02)
      print(f"wrote {sfx_path}")

      # Music base layer: a low sustained drone, 1.5s, loop-friendly (full-cycle
      # fade-in/out at the same envelope on both ends so LOOP_FORWARD does not click).
      music_path = os.path.join(ROOT, "data", "audio", "music", "exploration_base.wav")
      _write_sine_wav(music_path, duration_s=1.5, frequencies=[110.0, 220.0], amplitude=0.4, fade_s=0.05)
      print(f"wrote {music_path}")
      return 0


  if __name__ == "__main__":
      raise SystemExit(main())
  ```

- [ ] Run it:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  python tools/generate_placeholder_audio.py
  ```
  Expected output:
  ```
  wrote C:/Users/dasbl/Documents/The Synaptic Sea/data/audio/sfx/tool_pickup.wav
  wrote C:/Users/dasbl/Documents/The Synaptic Sea/data/audio/music/exploration_base.wav
  ```
  (exact path separators may render with `\` on Windows Python — either is acceptable, the file must simply exist at both paths).

- [ ] Verify determinism: run the script a second time and confirm the two files are byte-identical to the first run.
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  cp data/audio/sfx/tool_pickup.wav /tmp_check_sfx.wav 2>/dev/null || true
  python tools/generate_placeholder_audio.py
  ```
  (On Windows, use a simple re-run + `git status` check instead: since both files are freshly written every run, `git diff --stat data/audio` after the second run must show no changes if the files were already committed at this point — but since they are not yet committed in this task, instead confirm via checksum.)
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  python -c "import hashlib; print(hashlib.sha256(open('data/audio/sfx/tool_pickup.wav','rb').read()).hexdigest())"
  python tools/generate_placeholder_audio.py
  python -c "import hashlib; print(hashlib.sha256(open('data/audio/sfx/tool_pickup.wav','rb').read()).hexdigest())"
  ```
  Expected: both hash lines print the identical value.

- [ ] Verify the WAV files load in Godot via `AudioStreamWAV.load_from_file()` and report a positive length. Write a throwaway (NOT committed) script `scripts/validation/_task2_load_probe.gd`:
  ```gdscript
  extends SceneTree
  # THROWAWAY — deleted before commit. Confirms AudioStreamWAV.load_from_file()
  # loads both placeholder clips and reports get_length() > 0.

  func _initialize() -> void:
  	var sfx: AudioStreamWAV = AudioStreamWAV.load_from_file("res://data/audio/sfx/tool_pickup.wav")
  	if sfx == null:
  		push_error("PROBE FAIL: sfx clip failed to load")
  		quit(1)
  		return
  	if sfx.get_length() <= 0.0:
  		push_error("PROBE FAIL: sfx clip length <= 0")
  		quit(1)
  		return
  	var music: AudioStreamWAV = AudioStreamWAV.load_from_file("res://data/audio/music/exploration_base.wav")
  	if music == null:
  		push_error("PROBE FAIL: music clip failed to load")
  		quit(1)
  		return
  	if music.get_length() <= 0.0:
  		push_error("PROBE FAIL: music clip length <= 0")
  		quit(1)
  		return
  	print("TASK2 LOAD PROBE PASS sfx_length=%.3f music_length=%.3f" % [sfx.get_length(), music.get_length()])
  	quit(0)
  ```
  Run it:
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/_task2_load_probe.gd
  ```
  Expected: `TASK2 LOAD PROBE PASS sfx_length=0.250 music_length=1.500` (values approximate — any positive length satisfies the check; the exact printed value is diagnostic, not a byte-contract).

- [ ] Delete the throwaway probe:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  rm scripts/validation/_task2_load_probe.gd
  ```

- [ ] Stage and commit the generator script and the two generated WAV files:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git add tools/generate_placeholder_audio.py data/audio/sfx/tool_pickup.wav data/audio/music/exploration_base.wav
  git commit -m "feat: add deterministic placeholder audio generator and two placeholder clips"
  ```

## Task 3: AudioManager stream catalog + playback

**Files:**
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/scripts/audio/audio_manager.gd`

**Interfaces:**
- Produces: `const STREAM_CATALOG: Dictionary`, `_loaded_streams: Dictionary`, `_load_stream_cached(path: String) -> AudioStream`, updated `_play_via_bus(bus_id: String, volume_db: float, event_id: StringName = &"") -> void`.
- Consumes: `AudioStreamWAV.load_from_file(path: String) -> AudioStreamWAV` (verified available on this build), existing `play_sfx(event_id, position)` caller in `_play_via_bus`, existing `_apply_music_layer_gains()`.

- [ ] Add the stream catalog and cache fields directly below the existing `audio_log` model declaration (currently line 52) in `scripts/audio/audio_manager.gd`. Old string:
  ```
  var audio_log: AudioLog = AudioLogScript.new()

  ## Last-played voice-log entry id (for the panel to show "now playing").
  var current_voice_log_id: String = ""
  ```
  New string:
  ```
  var audio_log: AudioLog = AudioLogScript.new()

  ## Last-played voice-log entry id (for the panel to show "now playing").
  var current_voice_log_id: String = ""

  ## Event/layer id -> res:// path. Lives in the manager (the only scene-aware
  ## audio object), NOT in SfxEventRouter, which stays a pure RefCounted
  ## (ADR-0029/ADR-0044). Only entries listed here get a real .stream assigned;
  ## every other cataloged event id falls back to the pre-Domain-9 volume-push-
  ## only behavior (the deferred asset library is honest about what plays).
  const STREAM_CATALOG: Dictionary = {
  	"sfx.tool.pickup": "res://data/audio/sfx/tool_pickup.wav",
  	"layer.base": "res://data/audio/music/exploration_base.wav",
  }

  ## Path -> loaded AudioStream cache. Avoids re-loading the same WAV from
  ## disk on every play_sfx call.
  var _loaded_streams: Dictionary = {}

  ## Paths that already logged a missing/corrupt-file warning (warn-once so a
  ## missing asset doesn't spam push_warning every frame it's requested).
  var _warned_missing_paths: Dictionary = {}
  ```

- [ ] Add a `_load_stream_cached` helper. Insert it directly above `_play_via_bus` (currently at line 330). Old string:
  ```
  ## Internal: play through a non-spatial AudioStreamPlayer on a bus.
  func _play_via_bus(bus_id: String, volume_db: float) -> void:
  	var player: AudioStreamPlayer = _bus_players.get(bus_id, null)
  	if player == null:
  		return
  	# Without an actual AudioStream resource there is nothing to play in
  	# the headless case, but we still set the volume so the smoke can
  	# verify the push path runs without errors. The smoke inspects
  	# player.volume_db after each call.
  	player.volume_db = volume_db
  ```
  New string:
  ```
  ## Internal: load (and cache) an AudioStream from a res:// path. Returns null
  ## on a missing/corrupt file; logs exactly one push_warning per path (never
  ## per-frame spam) via the _warned_missing_paths flag.
  func _load_stream_cached(path: String) -> AudioStream:
  	if _loaded_streams.has(path):
  		return _loaded_streams[path]
  	if not FileAccess.file_exists(path):
  		if not _warned_missing_paths.has(path):
  			push_warning("AudioManager: stream file missing, path='%s'" % path)
  			_warned_missing_paths[path] = true
  		return null
  	var stream: AudioStreamWAV = AudioStreamWAV.load_from_file(path)
  	if stream == null:
  		if not _warned_missing_paths.has(path):
  			push_warning("AudioManager: load_from_file failed, path='%s'" % path)
  			_warned_missing_paths[path] = true
  		return null
  	_loaded_streams[path] = stream
  	return stream

  ## Internal: play through a non-spatial AudioStreamPlayer on a bus. When
  ## `event_id` is cataloged in STREAM_CATALOG, lazily loads and assigns the
  ## clip and calls play(); when not cataloged, behavior is byte-identical to
  ## pre-Domain-9 (volume push only) — the graceful missing-asset fallback
  ## that keeps the deferred asset library honest (ADR-0044).
  func _play_via_bus(bus_id: String, volume_db: float, event_id: StringName = &"") -> void:
  	var player: AudioStreamPlayer = _bus_players.get(bus_id, null)
  	if player == null:
  		return
  	player.volume_db = volume_db
  	var id_str: String = String(event_id)
  	if not id_str.is_empty() and STREAM_CATALOG.has(id_str):
  		var stream: AudioStream = _load_stream_cached(String(STREAM_CATALOG[id_str]))
  		if stream != null:
  			if player.stream != stream:
  				player.stream = stream
  			player.play()
  ```

- [ ] Update the one caller of `_play_via_bus` that has a known event id so the sfx path actually plays. In `play_sfx`, old string:
  ```
  		if position != null and position is Vector3:
  			_play_spatial(event_id, position, bus_id, vol_db)
  		else:
  			_play_via_bus(bus_id, vol_db)
  		return true
  ```
  New string:
  ```
  		if position != null and position is Vector3:
  			_play_spatial(event_id, position, bus_id, vol_db)
  		else:
  			_play_via_bus(bus_id, vol_db, event_id)
  		return true
  ```

- [ ] Confirm every other call site of `_play_via_bus` in this file (inside `tick()` for meta-events, `trigger_meta_event`, `play_voice_log`) is left as a 2-argument call (they pass no event id, which is correct — none of those ids are in `STREAM_CATALOG`, and the 3rd parameter already defaults to `&""`). Do not change those call sites.

- [ ] Wire the always-on music base layer. In `_apply_music_layer_gains` (currently starting at line 374), old string:
  ```
  ## Internal: apply per-layer music gains to the music bus player.
  func _apply_music_layer_gains() -> void:
  	var player: AudioStreamPlayer = _bus_players.get(String(AudioEventSeamScript.BUS_MUSIC), null)
  	if player == null:
  		return
  	var gains: Dictionary = music_state.get_layer_gains()
  	# Combined layer gain is the maximum across the four layers (they
  	# stack rather than average so exploration always has audible base).
  	var combined: float = 0.0
  	for layer_id in AudioEventSeamScript.ALL_MUSIC_LAYERS:
  		combined = maxf(combined, float(gains.get(layer_id, 0.0)))
  	# Combined in [0, 1] -> dB mapping: -24 dB at 0.0 -> 0 dB at 1.0.
  	player.volume_db = -24.0 + combined * 24.0
  ```
  New string:
  ```
  ## Internal: apply per-layer music gains to the music bus player.
  func _apply_music_layer_gains() -> void:
  	var player: AudioStreamPlayer = _bus_players.get(String(AudioEventSeamScript.BUS_MUSIC), null)
  	if player == null:
  		return
  	# Base layer proof-of-stream (REQ-AU criterion 2): the base layer is
  	# always-on in the default EXPLORATION state, so it is the one music
  	# layer that gets an actual assigned+looping .stream. Lazily assigned
  	# once; subsequent calls only touch volume_db (avoids restarting the
  	# clip every frame).
  	if player.stream == null:
  		var base_path: Variant = STREAM_CATALOG.get(String(AudioEventSeamScript.MUSIC_LAYER_BASE), null)
  		if base_path != null:
  			var stream: AudioStream = _load_stream_cached(String(base_path))
  			if stream != null:
  				if stream is AudioStreamWAV:
  					(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
  				player.stream = stream
  				player.play()
  	var gains: Dictionary = music_state.get_layer_gains()
  	# Combined layer gain is the maximum across the four layers (they
  	# stack rather than average so exploration always has audible base).
  	var combined: float = 0.0
  	for layer_id in AudioEventSeamScript.ALL_MUSIC_LAYERS:
  		combined = maxf(combined, float(gains.get(layer_id, 0.0)))
  	# Combined in [0, 1] -> dB mapping: -24 dB at 0.0 -> 0 dB at 1.0.
  	player.volume_db = -24.0 + combined * 24.0
  ```

- [ ] Re-run `main_playable_slice_audio_smoke.gd` — it must still PASS unchanged (this smoke never asserts `player.stream != null`, only volume/routing behavior, so this task must not change its marker):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_audio_smoke.gd
  ```
  Expected marker (unchanged from Task 1): `MAIN PLAYABLE AUDIO PASS buses=6 routed=4 fired_meta=3 ambient_role=engine`

- [ ] Re-run `audio_bus_config_smoke.gd` (pure-model smoke, must be unaffected):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_bus_config_smoke.gd
  ```
  Expected marker: `AUDIO BUS CONFIG PASS buses=7 default=true summary_round_trip=true`

- [ ] Stage and commit:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git add scripts/audio/audio_manager.gd
  git commit -m "feat: load and play catalog-backed audio streams for sfx.tool.pickup and the music base layer"
  ```

## Task 4: Caption pump + HUD line

**Files:**
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/scripts/procgen/playable_generated_ship.gd`

**Interfaces:**
- Produces: `_last_caption_line: String`, `_caption_expiry_seconds: float`, `_on_audio_caption(caption: Dictionary) -> void`, `get_last_caption_line() -> String`.
- Consumes: `audio_manager.pump_captions(caller: Callable) -> int` (existing, unchanged), `SfxEventRouter.DEFAULT_CAPTION_DURATION` (existing constant, value `2.5`).

- [ ] Add the caption HUD state member directly below `_last_loot_feedback_line` (currently line 315). Old string:
  ```
  var _loot_biome_ids_cache: Array[String] = []
  var _last_loot_feedback_line: String = ""
  var _home_player_position: Vector3 = Vector3.ZERO
  ```
  New string:
  ```
  var _loot_biome_ids_cache: Array[String] = []
  var _last_loot_feedback_line: String = ""
  # REQ-AU-001..010: most-recent audio caption + its remaining display time.
  # Mirrors the _last_loot_feedback_line pattern: no new HUD framework, just
  # another line folded into _combined_system_status_lines(). Multiple
  # captions arriving in one frame keep only the most recent (pump order).
  var _last_caption_line: String = ""
  var _caption_expiry_seconds: float = 0.0
  var _home_player_position: Vector3 = Vector3.ZERO
  ```

- [ ] Add the caption pump callback + expiry tick, and call the pump from `_refresh_audio_state`. Old string:
  ```
  	# Attach the AudioListener to the player when a player anchor exists.
  	if player != null and is_instance_valid(player) and player is Node3D:
  		audio_manager.attach_listener(player as Node3D)
  	audio_manager.update_listener_transform()
  	audio_manager.apply_spatial_attenuation()
  ```
  New string:
  ```
  	# Attach the AudioListener to the player when a player anchor exists.
  	if player != null and is_instance_valid(player) and player is Node3D:
  		audio_manager.attach_listener(player as Node3D)
  	audio_manager.update_listener_transform()
  	audio_manager.apply_spatial_attenuation()
  	# REQ-AU criterion 3: pump pending captions to the HUD. Both _process
  	# branches already call _refresh_audio_state (away :5358, home :5445),
  	# so this single call site satisfies the both-branches requirement
  	# structurally — no per-branch wiring needed here.
  	audio_manager.pump_captions(Callable(self, "_on_audio_caption"))
  	if not _last_caption_line.is_empty():
  		_caption_expiry_seconds -= _delta_seconds
  		if _caption_expiry_seconds <= 0.0:
  			_last_caption_line = ""
  			_caption_expiry_seconds = 0.0

  ## Callback for audio_manager.pump_captions(): records the most recent
  ## caption dict as the HUD's displayed caption line. `caption` carries at
  ## least {event_id, text, duration, elapsed} (SfxEventRouter's queue shape).
  ## Multiple captions pumped in the same frame: last call wins (most recent).
  func _on_audio_caption(caption: Dictionary) -> void:
  	var text: String = String(caption.get("text", ""))
  	if text.is_empty():
  		return
  	_last_caption_line = text
  	var duration: float = float(caption.get("duration", SfxEventRouterScript.DEFAULT_CAPTION_DURATION))
  	_caption_expiry_seconds = duration
  ```

- [ ] Add a `SfxEventRouterScript` const alias if one is not already present near the top of the file (check first — the file already has `AudioEventSeamScript` at line 49; search for `SfxEventRouterScript` before adding a duplicate). If absent, add it directly below the existing `AudioEventSeamScript` const. Old string:
  ```
  const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
  ```
  New string:
  ```
  const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
  const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")
  ```
  (If `SfxEventRouterScript` is already declared elsewhere in the file under a different alias, use that existing alias in `_on_audio_caption` instead of adding a duplicate preload — grep for `sfx_event_router.gd` first and reconcile to whichever name already exists.)

- [ ] Append the caption line in `_combined_system_status_lines()`, following the exact `_last_loot_feedback_line` pattern. Old string:
  ```
  	if not _last_loot_feedback_line.is_empty():
  		lines.append(_last_loot_feedback_line)
  	if unique_item_state != null:
  ```
  New string:
  ```
  	if not _last_loot_feedback_line.is_empty():
  		lines.append(_last_loot_feedback_line)
  	if not _last_caption_line.is_empty():
  		lines.append("Caption: %s" % _last_caption_line)
  	if unique_item_state != null:
  ```

- [ ] Add the validation seam `get_last_caption_line()` next to `get_audio_manager()` (currently line 6171). Old string:
  ```
  ## Validation seam: convenience accessors used by smokes that need to
  ## inspect the audio manager's state without poking at its internals.
  func get_audio_manager() -> Node:
  	return audio_manager
  ```
  New string:
  ```
  ## Validation seam: convenience accessors used by smokes that need to
  ## inspect the audio manager's state without poking at its internals.
  func get_audio_manager() -> Node:
  	return audio_manager

  ## Validation seam: the most recently pumped audio caption, or "" if none is
  ## currently displayed (either nothing has fired yet, or the last one expired).
  func get_last_caption_line() -> String:
  	return _last_caption_line
  ```

- [ ] Re-run `main_playable_slice_audio_smoke.gd` (must still PASS unchanged — this smoke never inspects captions):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_audio_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE AUDIO PASS buses=6 routed=4 fired_meta=3 ambient_role=engine`

- [ ] Stage and commit:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git add scripts/procgen/playable_generated_ship.gd
  git commit -m "feat: pump audio captions to the HUD status lines on both _process branches"
  ```

## Task 5: SettingsState caption unification + AudioSettingsPanel bug fix

**Files:**
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/scripts/procgen/playable_generated_ship.gd` (`_on_ui_settings_changed`)
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/scripts/ui/audio_settings_panel.gd` (fix `has_method("sfx_router")` bug)
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/scripts/ui/menu_coordinator.gd` (wire `settings_state` into the panel)

**Interfaces:**
- Produces: `AudioSettingsPanel.set_settings_state(state) -> void`.
- Consumes: `SettingsState.is_captions_enabled() -> bool` (existing), `SettingsState.set_captions_enabled(value: bool) -> bool` (existing), `menu_coordinator.settings_state` (existing public var on `MenuCoordinator`, line 46), `audio_manager.sfx_router.captions_enabled` (existing field, direct access — `sfx_router` is a public var on `AudioManagerScript`, not a method, which is the root of the pre-existing bug being fixed).

- [ ] Push `SettingsState.captions` into `SfxEventRouter.captions_enabled` at the single unification point, `_on_ui_settings_changed` (currently line 4598). This is the one seam all three apply paths funnel through: (1) in-game settings cycle (`menu_coordinator._cycle_setting` → `settings_changed.emit`), (2) title handoff (`title_main.gd` → `apply_ui_settings_summary` → `apply_settings_summary` → `settings_changed.emit`), (3) save/load restore (`_apply_run_snapshot` → `menu_coordinator.apply_settings_summary` → `settings_changed.emit`). Old string:
  ```
  func _on_ui_settings_changed(_summary: Dictionary) -> void:
  	apply_accessibility_settings(accessibility_settings)
  ```
  New string:
  ```
  func _on_ui_settings_changed(_summary: Dictionary) -> void:
  	apply_accessibility_settings(accessibility_settings)
  	# REQ-AU criterion 3 (ADR-0044): SettingsState.captions is the single
  	# source of truth for SfxEventRouter.captions_enabled. _summary is the
  	# SettingsState payload emitted by menu_coordinator.settings_changed
  	# (settings_state.get_summary()), which always carries a "captions" key
  	# (schema default true) — read it directly rather than re-deriving it
  	# from menu_coordinator to keep this a pure one-line push.
  	if is_instance_valid(audio_manager) and audio_manager.sfx_router != null:
  		audio_manager.sfx_router.captions_enabled = bool(_summary.get("captions", true))
  ```

- [ ] Fix `AudioSettingsPanel`'s caption checkbox: it currently gates on `audio_manager.has_method("sfx_router")`, which is always false (`sfx_router` is a property, not a method), so the checkbox has never synced or written anything. Read the full current file first (already done during planning — reproduced here for the edit). Old string (the panel's `audio_manager`/`accessibility_settings` fields and setters):
  ```
  var audio_manager: Node
  var accessibility_settings: RefCounted

  # Volume sliders indexed by bus id (StringName).
  var _volume_sliders: Dictionary = {}
  # Mute checkboxes indexed by bus id.
  var _mute_toggles: Dictionary = {}
  # Caption toggle (one for all buses).
  var _caption_toggle: CheckBox
  # Voice-log toggle.
  var _voice_log_toggle: CheckBox

  func _ready() -> void:
  	_build_layout()
  	_refresh_from_manager()

  func set_audio_manager(mgr: Node) -> void:
  	audio_manager = mgr
  	if is_inside_tree():
  		_refresh_from_manager()

  func set_accessibility_settings(settings: RefCounted) -> void:
  	accessibility_settings = settings
  	_apply_text_scale()
  ```
  New string:
  ```
  var audio_manager: Node
  var accessibility_settings: RefCounted
  # REQ-AU criterion 3 (ADR-0044): the settings seam this panel writes
  # captions through. Injected by MenuCoordinator (which already owns the
  # single settings_state instance) via set_settings_state(), following the
  # same pattern as set_accessibility_settings().
  var settings_state = null

  # Volume sliders indexed by bus id (StringName).
  var _volume_sliders: Dictionary = {}
  # Mute checkboxes indexed by bus id.
  var _mute_toggles: Dictionary = {}
  # Caption toggle (one for all buses).
  var _caption_toggle: CheckBox
  # Voice-log toggle.
  var _voice_log_toggle: CheckBox

  func _ready() -> void:
  	_build_layout()
  	_refresh_from_manager()

  func set_audio_manager(mgr: Node) -> void:
  	audio_manager = mgr
  	if is_inside_tree():
  		_refresh_from_manager()

  func set_accessibility_settings(settings: RefCounted) -> void:
  	accessibility_settings = settings
  	_apply_text_scale()

  func set_settings_state(state) -> void:
  	settings_state = state
  	if is_inside_tree():
  		_refresh_from_manager()
  ```

- [ ] Fix `_refresh_from_manager` and the two caption/voice-log handlers to read/write through `settings_state` instead of the always-false `has_method("sfx_router")` check. Old string:
  ```
  func _refresh_from_manager() -> void:
  	if audio_manager == null:
  		return
  	for bus_id in BUS_LIST:
  		var slider: HSlider = _volume_sliders.get(bus_id, null)
  		if slider != null:
  			slider.value = audio_manager.get_bus_volume(bus_id)
  		var toggle: CheckBox = _mute_toggles.get(bus_id, null)
  		if toggle != null:
  			toggle.button_pressed = audio_manager.is_bus_muted(bus_id)
  	# Caption toggle reflects the router's captions_enabled flag.
  	if _caption_toggle != null and audio_manager.has_method("sfx_router"):
  		_caption_toggle.button_pressed = bool(audio_manager.sfx_router.captions_enabled)
  	if _voice_log_toggle != null and audio_manager.has_method("audio_log"):
  		_voice_log_toggle.button_pressed = true

  func _on_volume_changed(value: float, bus_id: StringName) -> void:
  	if audio_manager == null:
  		return
  	audio_manager.set_bus_volume(bus_id, value)

  func _on_mute_changed(pressed: bool, bus_id: StringName) -> void:
  	if audio_manager == null:
  		return
  	audio_manager.set_bus_muted(bus_id, pressed)

  func _on_caption_toggled(pressed: bool) -> void:
  	if audio_manager == null or not audio_manager.has_method("sfx_router"):
  		return
  	audio_manager.sfx_router.captions_enabled = pressed

  func _on_voice_log_toggled(pressed: bool) -> void:
  	# Voice-log enable/disable is a UI flag — audio_log entries are
  	# always available; the panel just decides whether to show them.
  	# No model change needed here.
  	pass
  ```
  New string:
  ```
  func _refresh_from_manager() -> void:
  	if audio_manager == null:
  		return
  	for bus_id in BUS_LIST:
  		var slider: HSlider = _volume_sliders.get(bus_id, null)
  		if slider != null:
  			slider.value = audio_manager.get_bus_volume(bus_id)
  		var toggle: CheckBox = _mute_toggles.get(bus_id, null)
  		if toggle != null:
  			toggle.button_pressed = audio_manager.is_bus_muted(bus_id)
  	# Caption toggle reflects SettingsState.captions (the single source of
  	# truth, ADR-0044) — NOT audio_manager.sfx_router directly. The prior
  	# `audio_manager.has_method("sfx_router")` check was always false
  	# (sfx_router is a property, not a method), so this checkbox never
  	# synced before this fix.
  	if _caption_toggle != null and settings_state != null:
  		_caption_toggle.button_pressed = settings_state.is_captions_enabled()
  	if _voice_log_toggle != null and audio_manager.has_method("audio_log"):
  		_voice_log_toggle.button_pressed = true

  func _on_volume_changed(value: float, bus_id: StringName) -> void:
  	if audio_manager == null:
  		return
  	audio_manager.set_bus_volume(bus_id, value)

  func _on_mute_changed(pressed: bool, bus_id: StringName) -> void:
  	if audio_manager == null:
  		return
  	audio_manager.set_bus_muted(bus_id, pressed)

  func _on_caption_toggled(pressed: bool) -> void:
  	if settings_state == null:
  		return
  	settings_state.set_captions_enabled(pressed)
  	if is_instance_valid(audio_manager) and audio_manager.sfx_router != null:
  		audio_manager.sfx_router.captions_enabled = pressed

  func _on_voice_log_toggled(pressed: bool) -> void:
  	# Voice-log enable/disable is a UI flag — audio_log entries are
  	# always available; the panel just decides whether to show them.
  	# No model change needed here. Known no-op stub, flagged in ADR-0044,
  	# not fixed as part of Domain 9 (separate concern, out of scope).
  	pass
  ```

- [ ] Wire `MenuCoordinator.bind_meta_screens` to inject its own `settings_state` into the panel (the coordinator already owns `settings_state` as a public var, line 46 — no new parameter needed on `bind_meta_screens`, which keeps every existing caller, including `meta_screens_interactive_smoke.gd:74`, unchanged). Old string:
  ```
  	if is_instance_valid(audio_log_panel):
  		audio_log_panel.set_audio_manager(p_audio_manager)
  	if is_instance_valid(audio_settings_panel):
  		audio_settings_panel.set_audio_manager(p_audio_manager)
  		if p_a11y != null:
  			audio_settings_panel.set_accessibility_settings(p_a11y)
  ```
  New string:
  ```
  	if is_instance_valid(audio_log_panel):
  		audio_log_panel.set_audio_manager(p_audio_manager)
  	if is_instance_valid(audio_settings_panel):
  		audio_settings_panel.set_audio_manager(p_audio_manager)
  		if p_a11y != null:
  			audio_settings_panel.set_accessibility_settings(p_a11y)
  		audio_settings_panel.set_settings_state(settings_state)
  ```

- [ ] Enumerate and verify the three apply-path validations from spec §5.3 all reach `_on_ui_settings_changed`:
  1. **In-game settings cycle**: `menu_coordinator._cycle_setting` (line 374) sets a field then calls `settings_changed.emit(settings_state.get_summary())` (line 393) — `playable_generated_ship.gd` connects this signal to `_on_ui_settings_changed` at line 4135 (`menu_coordinator.settings_changed.connect(_on_ui_settings_changed)`). Confirmed reachable.
  2. **Title handoff**: `title_main.gd:146` calls `playable_instance.apply_ui_settings_summary(settings_state.get_summary())` when `_settings_dirty` — trace `apply_ui_settings_summary` (line 5845 area) to confirm it calls `menu_coordinator.apply_settings_summary(summary)`, which (per `menu_coordinator.gd:311-318`) calls `settings_changed.emit(...)` when the apply succeeded and `accessibility_settings != null`. Confirmed reachable (same signal, same listener).
  3. **Save/load restore**: `_apply_run_snapshot` (around line 6846) calls `menu_coordinator.apply_settings_summary(snapshot.settings_summary)` when the snapshot carries a non-empty `settings_summary` — same `apply_settings_summary` path as (2), same signal emit, same listener. Confirmed reachable.
  Read the actual body of `apply_ui_settings_summary` in `playable_generated_ship.gd` before checking this box — if it does NOT funnel through `menu_coordinator.apply_settings_summary`, stop and re-derive the real call chain rather than assuming the spec's description is exact.

- [ ] Re-run `main_playable_meta_screens_smoke.gd` (exercises the meta-screen shell including the audio settings panel's reachability; must still PASS unchanged):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_meta_screens_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE META SCREENS PASS screens=10 reachable=true`

- [ ] Re-run `meta_screens_interactive_smoke.gd` (calls `bind_meta_screens` directly with the same 12-argument signature that must still work unchanged):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_screens_interactive_smoke.gd
  ```
  Expected marker: `META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true registry_reader=true class_select=true`

- [ ] Re-run `title_settings_smoke.gd` (exercises the title-screen settings path; must still PASS unchanged — it does not touch the playable's `_on_ui_settings_changed`, only the title-local settings cycle):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/title_settings_smoke.gd
  ```
  Expected marker: `TITLE SETTINGS PASS open=true cycle=true back=true applied=true`

- [ ] Stage and commit:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git add scripts/procgen/playable_generated_ship.gd scripts/ui/audio_settings_panel.gd scripts/ui/menu_coordinator.gd
  git commit -m "fix: unify caption toggle on SettingsState and wire AudioSettingsPanel through the real settings seam"
  ```

## Task 6: `audio_pipeline_smoke.gd`

**Files:**
- Create: `C:/Users/dasbl/Documents/The Synaptic Sea/scripts/validation/audio_pipeline_smoke.gd`

**Interfaces:**
- Consumes: `PlayableShipScript` (`res://scripts/procgen/playable_generated_ship.gd`), golden fixture `res://data/procgen/golden/coherent_ship_002/{layout.json,gameplay_slice.json}`, `res://data/kits/ship_structural_v0.json`, `get_audio_manager()`, `get_last_caption_line()`, `away_from_start` (public var), `_refresh_audio_state`/`audio_manager.tick` driven manually for the away-branch tick loop.
- Produces marker (byte contract): `AUDIO PIPELINE PASS bus_index=true stream_playing=true caption_hud=true captions_toggle=true away_ticks=30`

> **Amendment (2026-07-02, controller, after Task 5 review):** the Task 5 review found the SettingsState→router caption unification ships with no direct regression coverage. This smoke therefore gains a `captions_toggle` stage (marker field added above and in the code's print). After the caption_hud stage passes, the smoke must: (a) capture `playable.menu_coordinator.get_settings_summary()`; (b) build a copy with `captions=false` and call `playable.menu_coordinator.apply_settings_summary(copy)`; (c) assert `playable.get_audio_manager().sfx_router.captions_enabled == false`; (d) fire `play_sfx(&"sfx.tool.pickup")` (after waiting out the 0.10s router cooldown via one `audio_manager.tick(0.2)`), pump one `_refresh_audio_state(false, 0.0)` tick, and assert `get_last_caption_line()` did NOT gain a new caption (the previous line may still be live or expired — assert on the router's `get_pending_captions().is_empty()` and `captions_enabled` rather than HUD string equality if simpler and race-free); (e) restore `captions=true` via the same seam and assert `captions_enabled == true`; set `captions_toggle` true only if all sub-asserts held. The code block below predates this amendment — implement the stage per this note and extend the final print accordingly (already updated below).
  ```gdscript
  extends SceneTree
  # Domain 9 (audio bus + pipeline) full pipeline smoke.
  #
  # Verifies the three roadmap CLOSED criteria in one run:
  # 1. AudioBusLayout registration: AudioServer.bus_count == 7; "Master" +
  #    the six lowercase children resolve via AudioManager._engine_bus_name;
  #    per-bus volume agrees with AudioBusConfig.make_default().
  # 2. Stream proof: play_sfx(&"sfx.tool.pickup") leaves the sfx player with
  #    stream != null and playing == true; the music player (base layer,
  #    always-on) also has stream != null and playing == true.
  # 3. Caption pump: after driving the away branch for 30 manual _process
  #    ticks, get_last_caption_line() is non-empty (the tool-pickup caption
  #    reached the HUD seam through _refresh_audio_state, which both
  #    _process branches already call).
  #
  # Pass marker: AUDIO PIPELINE PASS bus_index=true stream_playing=true caption_hud=true captions_toggle=true away_ticks=30
  #
  # Writes nothing to disk. Frees the scene in both the pass and fail exit paths.

  const PlayableShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
  const AudioBusConfigScript := preload("res://scripts/systems/audio_bus_config.gd")
  const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_002/layout.json"
  const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
  const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json"
  const READY_TIMEOUT_FRAMES: int = 300

  var playable: Node3D
  var frame_count: int = 0
  var phase: String = "waiting_ready"
  var finished: bool = false

  func _initialize() -> void:
  	playable = PlayableShipScript.new()
  	playable.name = "AudioPipelineSmoke"
  	playable.layout_path = LAYOUT_PATH
  	playable.kit_path = KIT_PATH
  	playable.gameplay_slice_path = GAMEPLAY_SLICE_PATH
  	get_root().add_child(playable)
  	process_frame.connect(_on_process_frame)

  func _on_process_frame() -> void:
  	if finished:
  		return
  	frame_count += 1
  	if playable == null or not is_instance_valid(playable):
  		_fail("playable freed unexpectedly")
  		return
  	if not playable.playable_started:
  		if frame_count > READY_TIMEOUT_FRAMES:
  			_fail("playable did not become ready")
  		return
  	if phase == "waiting_ready":
  		_validate_and_drive()

  func _validate_and_drive() -> void:
  	if not playable.has_method("get_audio_manager"):
  		_fail("get_audio_manager missing")
  		return
  	var mgr: Node = playable.get_audio_manager()
  	if mgr == null:
  		_fail("audio_manager is null")
  		return

  	# --- Criterion 1: bus registration ---
  	if AudioServer.bus_count != 7:
  		_fail("expected AudioServer.bus_count == 7, got %d" % AudioServer.bus_count)
  		return
  	if AudioServer.get_bus_index("Master") != 0:
  		_fail("expected Master bus_index == 0, got %d" % AudioServer.get_bus_index("Master"))
  		return
  	var default_cfg: AudioBusConfig = AudioBusConfigScript.make_default()
  	for bus_id in ["sfx", "music", "voice", "ui", "ambient", "meta"]:
  		var idx: int = AudioServer.get_bus_index(bus_id)
  		if idx < 1:
  			_fail("bus '%s' did not resolve (index=%d)" % [bus_id, idx])
  			return
  		var expected_db: float = default_cfg.get_volume_db(StringName(bus_id))
  		var actual_db: float = AudioServer.get_bus_volume_db(idx)
  		if absf(actual_db - expected_db) > 0.01:
  			_fail("bus '%s' volume mismatch: engine=%s config=%s" % [bus_id, str(actual_db), str(expected_db)])
  			return
  	var bus_index_ok: bool = true

  	# --- Criterion 2: stream proof ---
  	if not mgr.play_sfx(&"sfx.tool.pickup"):
  		_fail("play_sfx(sfx.tool.pickup) returned false")
  		return
  	var sfx_player: AudioStreamPlayer = mgr.get_bus_player(&"sfx")
  	if sfx_player == null or sfx_player.stream == null:
  		_fail("sfx player has no stream assigned after play_sfx")
  		return
  	if not sfx_player.playing:
  		_fail("sfx player is not playing after play_sfx")
  		return
  	# Drive one manual tick so _apply_music_layer_gains (which lazily assigns
  	# the base-layer stream on first call) has run at least once.
  	mgr.tick(0.016)
  	var music_player: AudioStreamPlayer = mgr.get_bus_player(&"music")
  	if music_player == null or music_player.stream == null:
  		_fail("music player has no stream assigned")
  		return
  	if not music_player.playing:
  		_fail("music player is not playing")
  		return
  	var stream_playing_ok: bool = true

  	# --- Criterion 3: caption pump on the away branch ---
  	playable.away_from_start = true
  	var away_ticks: int = 0
  	for i in range(30):
  		playable.call("_process", 0.1)
  		away_ticks += 1
  	var caption: String = playable.get_last_caption_line()
  	if caption.is_empty():
  		_fail("expected a non-empty caption after %d away-branch ticks, got empty" % away_ticks)
  		return
  	var caption_hud_ok: bool = true

  	finished = true
  	print("AUDIO PIPELINE PASS bus_index=%s stream_playing=%s caption_hud=%s captions_toggle=%s away_ticks=%d" % [
  		str(bus_index_ok).to_lower(),
  		str(stream_playing_ok).to_lower(),
  		str(caption_hud_ok).to_lower(),
  		away_ticks,
  	])
  	playable.queue_free()
  	quit(0)

  func _fail(reason: String) -> void:
  	if finished:
  		return
  	finished = true
  	push_error("AUDIO PIPELINE FAIL reason=%s" % reason)
  	if playable != null and is_instance_valid(playable):
  		playable.queue_free()
  	quit(1)
  ```

- [ ] Run it:
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_pipeline_smoke.gd
  ```
  Expected marker (exact byte contract): `AUDIO PIPELINE PASS bus_index=true stream_playing=true caption_hud=true captions_toggle=true away_ticks=30`
  No `ERROR:`/`WARNING:` line beyond the two allowlisted ones. If `str(bool).to_lower()` does not produce lowercase `"true"`/`"false"` on this Godot build, replace with the ternary `"true" if bus_index_ok else "false"` pattern instead (verify actual GDScript `String` casing behavior for `bool` — `str(true)` in GDScript 4.x already yields `"true"` lowercase, so `.to_lower()` is defensive and should be a no-op; if it errors as an unknown method on `String`, drop `.to_lower()` entirely since `str(bool)` alone is already lowercase).

- [ ] Stage and commit:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git add scripts/validation/audio_pipeline_smoke.gd
  git commit -m "test: add audio_pipeline_smoke covering bus registration, stream playback, and caption pump"
  ```

## Task 7: Register 9 smokes in the regression bundle

**Files:**
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/docs/game/06_validation_plan.md`

**Interfaces:**
- Consumes: exact current markers of the 8 previously-unregistered audio smokes (verified below) + Task 6's new smoke marker.
- Produces: 9 new `run_clean` lines + bumped final `echo` line (`commands=112` → `commands=121`).

- [ ] Run each of the 9 smokes individually first (evidence-before-registration, per the bundle's own discipline) and confirm the exact marker text and zero unexpected `ERROR:`/`WARNING:` lines:
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_bus_config_smoke.gd
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ambient_zone_state_smoke.gd
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sfx_event_router_smoke.gd
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dynamic_music_state_smoke.gd
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/spatial_audio_resolver_smoke.gd
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_event_state_smoke.gd
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_audio_smoke.gd
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_save_load_smoke.gd
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_pipeline_smoke.gd
  ```
  Expected markers (verified during planning by reading each smoke's `print()` line; confirm the live run reproduces these exactly before registering — if any value differs, use the ACTUAL observed value in the `run_clean` line below, not the value printed here):
  - `AUDIO BUS CONFIG PASS buses=7 default=true summary_round_trip=true`
  - `AMBIENT ZONE STATE PASS roles_changed=2 crossfades_completed=1 threat_applied=true`
  - `SFX EVENT ROUTER PASS routed=<N> dropped=<N> captions=<N>` (computed from live routed/dropped/caption counts — read the actual printed line and use it verbatim)
  - `DYNAMIC MUSIC STATE PASS states_visited=4 crossfade_changed=true`
  - `SPATIAL AUDIO RESOLVER PASS atten_ref=0 atten_max=-36 occluded=-6 determinism=true`
  - `META EVENT STATE PASS fired=3 pending=0 deterministic_seed=true`
  - `MAIN PLAYABLE AUDIO PASS buses=6 routed=4 fired_meta=3 ambient_role=engine`
  - `AUDIO SAVE LOAD PASS summary_keys=<N> round_trip=true` (read the actual printed key count)
  - `AUDIO PIPELINE PASS bus_index=true stream_playing=true caption_hud=true captions_toggle=true away_ticks=30`
  Any newly-surfaced `ERROR:`/`WARNING:` line beyond the two allowlisted ones (risk called out in spec §7.1 — real bus registration may surface dormant warnings) must be classified here before proceeding: either it is a genuine regression (stop, fix the root cause, re-verify) or it is a new deliberate/expected warning that needs its own allowlist regex added to `06_validation_plan.md` alongside the existing `BASELINE_ERROR`/`BASELINE_WARNING`/etc. definitions — do not silently register a smoke with an unclassified warning.

- [ ] Read `docs/game/06_validation_plan.md` and insert the 9 `run_clean` lines directly after line 142 (`run_clean 'REQ-AU-001 callsite audio event coupling smoke' ...`), using the exact marker strings confirmed in the previous step. Old string:
  ```
  run_clean 'REQ-AU-001 callsite audio event coupling smoke' 'AUDIO CALLSITE EVENTS PASS door=skip footstep=skip drop=skip tool=true inv_toggle=true objective=true save=true dock=skip load=skip' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_callsite_events_smoke.gd
  # --- Task 15 documentation/manifest currency validators (host-side Python; no Godot) ---
  ```
  New string:
  ```
  run_clean 'REQ-AU-001 callsite audio event coupling smoke' 'AUDIO CALLSITE EVENTS PASS door=skip footstep=skip drop=skip tool=true inv_toggle=true objective=true save=true dock=skip load=skip' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_callsite_events_smoke.gd
  run_clean 'audio bus config model smoke' 'AUDIO BUS CONFIG PASS buses=7 default=true summary_round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_bus_config_smoke.gd
  run_clean 'ambient zone state model smoke' 'AMBIENT ZONE STATE PASS roles_changed=2 crossfades_completed=1 threat_applied=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ambient_zone_state_smoke.gd
  run_clean 'sfx event router model smoke' 'SFX EVENT ROUTER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sfx_event_router_smoke.gd
  run_clean 'dynamic music state model smoke' 'DYNAMIC MUSIC STATE PASS states_visited=4 crossfade_changed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/dynamic_music_state_smoke.gd
  run_clean 'spatial audio resolver model smoke' 'SPATIAL AUDIO RESOLVER PASS atten_ref=0 atten_max=-36 occluded=-6 determinism=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/spatial_audio_resolver_smoke.gd
  run_clean 'meta event state model smoke' 'META EVENT STATE PASS fired=3 pending=0 deterministic_seed=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_event_state_smoke.gd
  run_clean 'main playable audio smoke' 'MAIN PLAYABLE AUDIO PASS buses=6 routed=4 fired_meta=3 ambient_role=engine' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_audio_smoke.gd
  run_clean 'audio save/load model smoke' 'AUDIO SAVE LOAD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_save_load_smoke.gd
  run_clean 'Domain 9 audio pipeline smoke' 'AUDIO PIPELINE PASS bus_index=true stream_playing=true caption_hud=true captions_toggle=true away_ticks=30' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/audio_pipeline_smoke.gd
  # --- Task 15 documentation/manifest currency validators (host-side Python; no Godot) ---
  ```
  Note: `sfx_event_router_smoke` and `audio_save_load_smoke` markers use a partial-match string (`'SFX EVENT ROUTER PASS'` / `'AUDIO SAVE LOAD PASS'`) rather than the full parameterized line, matching the existing bundle's convention of using a stable prefix for markers whose suffix values are computed at runtime (e.g. line 84's `'MAIN PLAYABLE ROUTE CONTROL PASS'`) — `grep -q` on the marker only needs the prefix substring to match, so this is consistent with the file's existing style, not a deviation.

  - [ ] Also add `main_playable_slice_audio_smoke` runtime cross-check: confirm it was NOT already double-registered anywhere else in the bundle before this edit (it wasn't, per the pre-Task-7 read of the file) — this is a genuinely new registration, not a duplicate.

- [ ] Bump the final echo line. Old string:
  ```
  echo 'SYNAPTIC_SEA REGRESSION PASS commands=112 clean_output=true'
  ```
  New string:
  ```
  echo 'SYNAPTIC_SEA REGRESSION PASS commands=121 clean_output=true'
  ```

- [ ] Count `run_clean` lines to confirm the arithmetic: 112 (original) + 9 (this task) = 121.
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  grep -c "^run_clean" docs/game/06_validation_plan.md
  ```
  Expected output: `121`

- [ ] Run the full regression bundle (extract the bash block from `docs/game/06_validation_plan.md` between the ```` ```bash ```` fences under "Regression bundle" and execute it with `GODOT`/`ROOT` set to the Windows values):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  bash -c "$(sed -n '/^```bash$/,/^```$/p' docs/game/06_validation_plan.md | sed '1d;$d')"
  ```
  Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=121 clean_output=true`. If any smoke fails, stop and root-cause it (per the project's systematic-debugging convention) before re-running — do not re-run in a loop hoping for a different result.

- [ ] Stage and commit:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git add docs/game/06_validation_plan.md
  git commit -m "test: register the 8 previously-unregistered audio smokes plus audio_pipeline_smoke in the regression bundle"
  ```

## Task 8: Docs — feature spec correction + ADR-0044

**Files:**
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/docs/game/features/audio-music-spatial.md` (line 100 false claim)
- Create: `C:/Users/dasbl/Documents/The Synaptic Sea/docs/game/adr/0044-audio-bus-layout-registration-and-caption-settings-unification.md`
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/docs/game/adr/README.md` (index table addition, optional per validator but added for convention consistency with ADR-0042's precedent)

**Interfaces:**
- Consumes: `REQUIRED_ADR_PATHS` list in `scripts/validation/doc_currency_validators.py` (confirmed during planning: ADR-0044 is NOT in this hardcoded list, so `AdrIndexValidator`/`RequirementTraceValidator` do not require it to be indexed — this task adds it to the README table anyway, for the same optional documentation-hygiene reason ADR-0042 was added despite ADR-0043 not being added).

- [ ] Fix the false claim at `docs/game/features/audio-music-spatial.md:100`. Old string:
  ```
  - All seven plus save/load registered in `docs/game/06_validation_plan.md` regression bundle.
  ```
  New string:
  ```
  - All seven plus save/load, plus the two coordinator-coupling smokes and the Domain 9 `audio_pipeline_smoke.gd`, are registered in `docs/game/06_validation_plan.md` regression bundle (10 audio-related `run_clean` entries total as of Domain 9).
  ```

- [ ] Create `docs/game/adr/0044-audio-bus-layout-registration-and-caption-settings-unification.md`:
  ```markdown
  # ADR-0044: Audio bus layout registration and caption settings unification

  Date: 2026-07-02
  Status: Accepted
  Supersedes: nothing — extends ADR-0029 (audio/music/spatial architecture).
  Roadmap source: `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` Domain 9 (`audio_reactive` loop, bus + pipeline scope).

  ## Context

  ADR-0029 built a rich audio architecture — six pure models plus an `AudioManager`
  node, ticked on both `_process` branches, with a full save/load round-trip — but
  it was structurally silent:

  - No `AudioBusLayout` was registered in `project.godot`; `AudioServer.get_bus_index`
    returned -1 for every named bus, so every volume push was inert.
  - No `AudioStream` was ever assigned and `.play()` was never called anywhere in
    the 8 audio scripts. Zero audio assets existed.
  - Captions never reached the player: `pump_captions`/`drain_captions` had zero
    gameplay callers.

  This ADR documents the four architectural decisions made to close that gap
  (Domain 9 of the completion roadmap), without expanding scope into the full
  asset library, spatial emitter population, or ambient-zone reactivity — all of
  which remain explicit, documented deferrals.

  ## Decision 1: AudioBusLayout / AudioBusConfig split of authority

  Two tables now describe the bus graph, each owning a different half:

  - **`data/audio/default_bus_layout.tres`** (a real Godot `AudioBusLayout`
    resource, registered via `project.godot`'s `[audio]` section) owns
    boot-time bus **existence and hierarchy** — which buses exist, what each
    sends to, at engine startup. This is the table Godot's `AudioServer`
    actually reads.
  - **`AudioBusConfig`** (the existing pure `Resource`, unchanged in shape)
    keeps owning runtime **state** — volumes, mutes — and the save/load round
    trip via `RunSnapshot.audio_summary`.

  The two tables must agree (volumes mirror `AudioBusConfig.make_default()`
  exactly: sfx -3, music -6, voice -3, ui -6, ambient -9, meta -6; Master is
  engine bus 0 at 0 dB). Any bus add/remove/rename must update both tables in
  the same PR. No engine-level cross-check enforces this automatically —
  `scripts/validation/audio_pipeline_smoke.gd` is the drift guard, asserting
  `AudioServer.bus_count == 7` and per-bus name/volume agreement with
  `AudioBusConfig.make_default()` at boot.

  `data/audio/audio_bus_config.tres` (a pre-existing, orphaned custom Resource
  file that nothing loads) is kept as-is and documented here as an orphan;
  building a loader for it is out of scope for this ADR.

  ## Decision 2: Master-name translation at the AudioServer boundary

  Godot's bus 0 is immutably named `"Master"` (capital M) and cannot be
  renamed; `AudioServer.get_bus_index("master")` (lowercase, matching the pure
  model's `AudioEventSeam.BUS_MASTER`) always returns -1. Rather than rename
  the pure model's bus id (which would ripple through save summaries, the
  settings panel, and `AudioBusConfig`'s own validation), `AudioManagerScript`
  gained a single private translation function, `_engine_bus_name(bus_id) ->
  String`, used at the one `AudioServer` boundary call (`_apply_bus_volumes`).
  The pure model keeps lowercase `master` everywhere; only the engine boundary
  translates. The six child buses need no translation — their names already
  match between the pure model and the engine.

  ## Decision 3: `load_from_file` placeholder clips + the stream registry

  A probe run on this machine (headless, Godot 4.6.2) confirmed
  `AudioStreamWAV.load_from_file()` is available and works at runtime, without
  the editor's asset-import pipeline (no `.import`/`.uid` churn). This was
  chosen over the alternative — committing clips through the editor's normal
  import flow — because:

  - The editor import pipeline requires opening the project in `--editor`
    mode at least once, which this machine's Godot binary is known to mutate
    (`project.godot` autoload injection) outside of controlled, surgical
    edits.
  - `load_from_file()` keeps the two placeholder clips as plain committed
    `.wav` files with zero generated `.import` sidecar noise, which matches
    the "deterministic, regenerable placeholder" spirit the roadmap asked for
    (`tools/generate_placeholder_audio.py` regenerates byte-identical output
    on every run).

  Two clips prove the path: `data/audio/sfx/tool_pickup.wav` (backs
  `sfx.tool.pickup`, a live gameplay callsite at item pickup) and
  `data/audio/music/exploration_base.wav` (backs music layer `layer.base`,
  always-on in the default EXPLORATION state).

  `AudioManagerScript` gained `const STREAM_CATALOG: Dictionary` (event/layer
  id → `res://` path) and a path-keyed `_loaded_streams` load cache. The
  catalog lives in the **manager**, not in `SfxEventRouter` — the router
  stays a pure `RefCounted` per ADR-0029 (the manager remains the only
  scene-aware audio object). Events not in the catalog behave exactly as
  before this ADR (volume push only, no stream) — the honest, deferred-asset
  fallback. A missing or corrupt file at runtime logs exactly one
  `push_warning` per path (never per-frame spam) and falls back to
  streamless behavior; it never crashes.

  ## Decision 4: SettingsState caption unification + panel bug fix

  `SettingsState.captions` (already the schema-backed, save-persisted field
  used by the in-game settings menu and the title screen) is now the single
  source of truth for `SfxEventRouter.captions_enabled`. The push happens at
  one seam, `playable_generated_ship.gd::_on_ui_settings_changed`, which all
  three apply paths already funnel through via `menu_coordinator.settings_changed`:

  1. In-game settings cycle (`menu_coordinator._cycle_setting` → emit)
  2. Title handoff (`title_main.gd` → `apply_ui_settings_summary` →
     `apply_settings_summary` → emit)
  3. Save/load restore (`_apply_run_snapshot` → `apply_settings_summary` → emit)

  This also fixes a latent pre-existing bug in `AudioSettingsPanel`: the
  captions checkbox gated on `audio_manager.has_method("sfx_router")`, which
  is always `false` — `sfx_router` is a property, not a method — so the
  checkbox never synced from or wrote back to any state. The panel now takes
  a `settings_state` reference (injected by `MenuCoordinator.bind_meta_screens`,
  which already owns a `settings_state` instance) and reads/writes through
  `SettingsState.is_captions_enabled()` / `set_captions_enabled()`, mirroring
  the toggle into `audio_manager.sfx_router.captions_enabled` on write.

  The panel's voice-log toggle remains a known no-op stub, unchanged by this
  ADR — a separate concern, explicitly out of scope here.

  ## Retained deferrals (explicitly out of scope)

  - Full SFX/music/voice asset library (a later content pass; only two
    placeholder clips exist).
  - Spatial emitter population (`play_sfx` with a `position` argument has a
    live code path, but no gameplay callsite passes one yet).
  - Ambient-zone reactivity (`set_room_role`/`set_threat_level` stay uncalled
    from gameplay).
  - A loader for the orphaned `data/audio/audio_bus_config.tres`.
  - The `AudioSettingsPanel` voice-log toggle stub.
  - Occlusion raycast (the deterministic distance/Y-band heuristic in
    `AudioManager._is_occluded` stays as a placeholder).

  ## Consequences

  - Bus volume pushes are no longer inert in any run mode (headless or
    windowed) — this was previously true even outside headless tests.
  - Two real audio events are now audible end-to-end: picking up a tool, and
    the always-on exploration music base layer.
  - Captions reach the HUD (`Caption: <text>` line in the combined system
    status lines) on both `_process` branches, gated by the same
    `SettingsState.captions` flag the settings menu already exposes.
  - The dual bus-table split (Decision 1) is a structural risk without an
    engine-level cross-check; `audio_pipeline_smoke.gd` is the only guard
    against drift and must be kept current if buses are ever added, removed,
    or renamed.
  ```

- [ ] Check whether `doc_currency_validators.py` requires ADR-0044 to be indexed. It does not — `REQUIRED_ADR_PATHS` (`scripts/validation/doc_currency_validators.py:32-51`) is a fixed, hardcoded list of specific pre-existing ADRs and does not include ADR-0044 (a genuinely new ADR can never appear in a list authored before it existed). `AdrIndexValidator.validate()` only checks that every path in that fixed list exists and is indexed — it does not scan `docs/game/adr/` for undocumented new files. Therefore adding ADR-0044 to `docs/game/adr/README.md` is NOT required for `REQUIREMENT TRACE PASS` to keep passing. Add it anyway, for the same documentation-hygiene reason ADR-0042 was added to the README table despite not being validator-required (ADR-0043 was not added, showing this is already an inconsistent, optional convention — Domain 9 follows ADR-0042's precedent rather than ADR-0043's).

- [ ] Add ADR-0044 to the index table in `docs/game/adr/README.md`. Old string:
  ```
  | 0042 | docs/game/adr/0042-sanity-hallucinations.md | sanity hallucination director (4 channels, deterministic, tier-3 teeth); closes M1 sanity cosmetic gap |
  ```
  New string:
  ```
  | 0042 | docs/game/adr/0042-sanity-hallucinations.md | sanity hallucination director (4 channels, deterministic, tier-3 teeth); closes M1 sanity cosmetic gap |
  | 0044 | docs/game/adr/0044-audio-bus-layout-registration-and-caption-settings-unification.md | AudioBusLayout registration, Master-name translation, stream catalog + placeholder clips, SettingsState caption unification; closes Domain 9 audio_reactive loop |
  ```

- [ ] Re-run the Task 15 doc-currency validators to confirm nothing broke (these do not require Godot):
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  python scripts/validation/doc_currency_validators.py systems-map
  python scripts/validation/doc_currency_validators.py requirement-trace
  ```
  Expected: `SYSTEMS MAP CURRENCY PASS` and `REQUIREMENT TRACE PASS`.

- [ ] Stage and commit:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git add docs/game/features/audio-music-spatial.md docs/game/adr/0044-audio-bus-layout-registration-and-caption-settings-unification.md docs/game/adr/README.md
  git commit -m "docs: correct audio smoke registration claim and add ADR-0044 for the bus/pipeline/caption closure"
  ```

## Task 9: System inventory update + final full bundle re-run

**Files:**
- Modify: `C:/Users/dasbl/Documents/The Synaptic Sea/docs/game/inventory/system_inventory.json`
- Regenerate (not hand-edited): `C:/Users/dasbl/Documents/The Synaptic Sea/docs/game/inventory/SYSTEM_INVENTORY.md`
- Regenerate (not hand-edited): `C:/Users/dasbl/Documents/The Synaptic Sea/docs/game/inventory/system_map.html`

**Interfaces:**
- Consumes: `tools/build_system_inventory.py` (`derive_coupling`, `leaf_completion`, `validate` — confirmed during planning: `output.live == true` flips `audio_manager`'s coupling from `"half"` to `"closed"` and raises its completion score; `--check` compares against the committed generated `.md`/`.html` files byte-for-byte).

- [ ] Read the current `audio_manager` entry (`docs/game/inventory/system_inventory.json`, starting at line 3887) and the current `audio_reactive` loop entry (starting at line 8746) once more immediately before editing — line numbers may have drifted slightly if earlier tasks touched nearby content (they should not have, since this file wasn't touched by Tasks 1-8, but confirm before editing rather than assuming).

- [ ] Edit `audio_manager.output` to reflect the now-live playback path. Old string:
  ```
        "output": {
        "live": false,
        "desc": "Terminal output only sets AudioStreamPlayer.volume_db on streamless players (_play_via_bus audio_manager.gd:330-338, _apply_music_layer_gains 385, apply_spatial_attenuation 247); VERIFIED no AudioStream is ever assigned and .play() is never called anywhere in the 8 audio scripts (grep confirmed), so nothing is audible. Captions are never drained by the HUD in gameplay (pump_captions/drain_captions have zero callers in the coordinator).",
        "at": "audio_manager.gd:330"
      },
  ```
  New string:
  ```
        "output": {
        "live": true,
        "desc": "Domain 9: real playback is now live. _play_via_bus (audio_manager.gd) assigns a cataloged event id's AudioStream via STREAM_CATALOG + _load_stream_cached, then calls player.play() -- verified for sfx.tool.pickup (item pickup callsite) and the music base layer (always-on in EXPLORATION, lazily assigned in _apply_music_layer_gains). AudioBusLayout is registered via project.godot's [audio] section (data/audio/default_bus_layout.tres), so AudioServer.get_bus_index resolves for Master + all six child buses and volume pushes are no longer inert. Captions now reach the HUD: pump_captions is called every _refresh_audio_state (both _process branches), landing in playable_generated_ship.gd's _last_caption_line / get_last_caption_line() seam.",
        "at": "audio_manager.gd:330"
      },
  ```

- [ ] Update `audio_manager.gaps` to drop the now-closed gaps and keep only the genuinely retained thin-library gap. Old string:
  ```
      "gaps": [
        "No AudioStream assets anywhere in data/ (no .ogg/.wav); system produces zero audible output (verified: no .play()/.stream= in any audio script)",
        "AudioLog voice clip_paths reference res://data/audio/voice/*.ogg which do not exist",
        "HUD never drains the SfxEventRouter caption queue during gameplay (no pump_captions/drain_captions call in coordinator — verified)",
        "Bus volume push to AudioServer is inert: the .tres is a custom Resource (not a Godot AudioBusLayout) and project.godot registers no bus layout, so get_bus_index returns -1 ALWAYS (not just headless) audio_manager.gd:107-114"
      ],
  ```
  New string:
  ```
      "gaps": [
        "Deferred, not broken: only two placeholder clips exist (data/audio/sfx/tool_pickup.wav, data/audio/music/exploration_base.wav) backing 2 of ~27 catalog event/layer ids; the full SFX/voice/music asset library is a later content pass (ADR-0044).",
        "Deferred, not broken: AudioLog voice clip_paths still reference res://data/audio/voice/*.ogg which do not exist; voice-log playback pushes bus volume only, same fallback path as any other uncataloged event id.",
        "Deferred, not broken: spatial emitter population and ambient-zone reactivity (set_room_role/set_threat_level) remain uncalled from gameplay (ADR-0044 explicit deferrals)."
      ],
  ```

- [ ] Update the `audio_reactive` loop entry: flip `closes` from `"broken"` to `"closed"` and rewrite `break_points` to reword the retained items as deferred-not-broken (dropping the three now-closed break points: the terminal no-audio break, the caption-never-reaches-player break, and the inert-bus-push break). Old string:
  ```
      "id": "audio_reactive",
      "name": "Audio Reactivity Loop (gameplay state -> audio -> player perception)",
      "closes": "broken",
      "steps": [
        {
          "system": "audio_manager",
          "role": "source/router: reads hazard/threat/vitals each frame and fires play_sfx + update_music_flags; ticked on BOTH _process branches (playable_generated_ship.gd:4806 away, 4904 home; refresh 5460-5514)"
        },
        {
          "system": "dynamic_music_state",
          "role": "music state machine -> layer gains -> music bus volume_db (audio_manager.gd:378->385)"
        },
        {
          "system": "sfx_event_router",
          "role": "event routing -> bus volume_db + caption queue (audio_manager.gd:202)"
        },
        {
          "system": "meta_event_state",
          "role": "timer-driven meta events -> meta bus + voice log (audio_manager.gd:183-194)"
        }
      ],
      "break_points": [
        "TERMINAL BREAK (verified): no AudioStream assets exist (only audio_bus_config.tres); grep confirms no .play() call or .stream= assignment in any of the 8 audio scripts — every model resolves to setting volume_db on a streamless player, so nothing is ever audible",
        "Captions never reach the player: HUD/coordinator never calls pump_captions/drain_captions in gameplay (verified zero callers)",
        "Ambient zone never reacts: set_room_role/set_threat_level have zero coordinator callers (room pinned to 'docking'), and ambient gains are never consumed for a volume push (_apply_music_layer_gains reads music_state only)",
        "Spatial audio is dead: every play_sfx call is single-arg (no position), so the spatial emitter pool is always empty and resolve_volume_db never runs",
        "Bus volume push is inert in ALL modes: the .tres is a custom Resource (not a Godot AudioBusLayout) and no bus layout is registered in project.godot, so AudioServer.get_bus_index always returns -1",
        "Voice logs reference missing res://data/audio/voice/*.ogg clips"
      ]
    },
  ```
  New string:
  ```
      "id": "audio_reactive",
      "name": "Audio Reactivity Loop (gameplay state -> audio -> player perception)",
      "closes": "closed",
      "steps": [
        {
          "system": "audio_manager",
          "role": "source/router: reads hazard/threat/vitals each frame and fires play_sfx + update_music_flags; ticked on BOTH _process branches (playable_generated_ship.gd:5358 away, 5445 home; refresh via _refresh_audio_state)"
        },
        {
          "system": "dynamic_music_state",
          "role": "music state machine -> layer gains -> music bus volume_db + base-layer stream playback (audio_manager.gd:378->385, Domain 9 lazily assigns + plays the base layer clip)"
        },
        {
          "system": "sfx_event_router",
          "role": "event routing -> bus volume_db + caption queue (audio_manager.gd:202); Domain 9 pumps the caption queue to the HUD every _refresh_audio_state call"
        },
        {
          "system": "meta_event_state",
          "role": "timer-driven meta events -> meta bus + voice log (audio_manager.gd:183-194)"
        }
      ],
      "break_points": [
        "Domain 9 CLOSED: AudioBusLayout is registered (data/audio/default_bus_layout.tres via project.godot's [audio] section); AudioServer.get_bus_index resolves for Master (translated via AudioManager._engine_bus_name) and all six child buses; volume pushes are no longer inert in any run mode.",
        "Domain 9 CLOSED: two placeholder clips actually play — sfx.tool.pickup (item pickup) and the always-on music base layer — proving the STREAM_CATALOG + load_from_file path end-to-end.",
        "Domain 9 CLOSED: captions reach the HUD on both _process branches via pump_captions inside _refresh_audio_state, landing in _last_caption_line / get_last_caption_line(); the caption toggle is unified on SettingsState.captions (ADR-0044), fixing a latent AudioSettingsPanel bug.",
        "Deferred, not broken: ambient zone reactivity (set_room_role/set_threat_level) has zero coordinator callers (room stays pinned to 'docking') — explicit Domain 9 out-of-scope item.",
        "Deferred, not broken: spatial audio stays dark — every current play_sfx callsite is single-arg (no position), so the spatial emitter pool is never populated — explicit Domain 9 out-of-scope item.",
        "Deferred, not broken: voice logs still reference missing res://data/audio/voice/*.ogg clips; voice-log playback uses the same honest volume-push-only fallback as any other uncataloged event."
      ]
    },
  ```

- [ ] Regenerate the derived inventory files:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  python tools/build_system_inventory.py
  ```
  Expected output: `SYSTEM INVENTORY BUILD PASS systems=<N> verified=<N>` (N is whatever the live count is — this is not a byte-contract, just confirm the marker prefix `SYSTEM INVENTORY BUILD PASS` appears with no `ERROR:` lines).

- [ ] Run the anti-drift check:
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  python tools/build_system_inventory.py --check
  ```
  Expected output: `SYSTEM INVENTORY CHECK PASS systems=<N> verified=<N>` with no `ERROR:` lines (this confirms the regenerated `.md`/`.html` match what's committed and no dangling ids/loop-step references were introduced by the edits above).

- [ ] Stage the JSON source AND the two regenerated derived files together (they must move as one commit or `--check` will fail for the next person who runs it):
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git add docs/game/inventory/system_inventory.json docs/game/inventory/SYSTEM_INVENTORY.md docs/game/inventory/system_map.html
  git commit -m "docs: close the audio_reactive loop in the system inventory and regenerate derived inventory files"
  ```

- [ ] Final full regression bundle re-run, confirming the complete Domain 9 change set together (this is the definition-of-done gate — no completion claim without this fresh evidence):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  bash -c "$(sed -n '/^```bash$/,/^```$/p' docs/game/06_validation_plan.md | sed '1d;$d')"
  ```
  Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=121 clean_output=true`.

- [ ] Verify no unintended files were modified across the whole Domain 9 branch (final sanity check before handing off):
  ```bash
  cd "C:/Users/dasbl/Documents/The Synaptic Sea"
  git status
  git diff main --stat
  ```
  Confirm `project.godot` shows only the 6-line `[audio]` section addition (per Task 1's earlier check) and no `.godot/`, `*.uid`, or `addons/` paths appear anywhere in the diff.
