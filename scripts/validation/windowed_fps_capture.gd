extends SceneTree

# Windowed FPS Capture (NON-headless harness).
#
# This script runs WITHOUT --headless so the Godot renderer is live and the
# FPS we measure reflects the real rendering cost the player sees. It is
# the only place in the project that produces a windowed FPS number; the
# headless profiler measures physics-frame deltas only.
#
# Capture budget: 240 frames after playable_ready. Output: a JSON file
# under user://perf_windowed_fps.json plus one pass marker line.
#
# Usage (NOT in the regression bundle -- needs a display server):
#   /Users/christopherwilloughby/.local/bin/godot-4.6.2 \
#     --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
#     --script res://scripts/validation/windowed_fps_capture.gd
#
# Pass marker (on stdout):
#   WINDOWED FPS CAPTURE PASS frames=N median_ms=... p95_ms=... observed_fps=...

const PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_generated_ship.tscn")
const OUTPUT_PATH: String = "user://perf_windowed_fps.json"
const CAPTURE_FRAMES: int = 240

var _frame_deltas_us: Array[int] = []
var _last_us: int = 0
var _peak_static_mb: float = 0.0
var _peak_rss_mb: float = 0.0
var _ready_seen: bool = false
var _finalized: bool = false
var _playable_ship


func _initialize() -> void:
	_last_us = Time.get_ticks_usec()
	_playable_ship = PLAYABLE_SHIP_SCENE.instantiate()
	get_root().add_child(_playable_ship)
	_playable_ship.playable_ready.connect(_on_playable_ready)
	_playable_ship.playable_failed.connect(_on_playable_failed)
	process_frame.connect(_on_process_frame)


func _on_playable_ready(_summary: Dictionary) -> void:
	_ready_seen = true
	_last_us = Time.get_ticks_usec()
	_frame_deltas_us.clear()
	# Sample OS RSS at ready time as the "all rooms loaded" memory anchor.
	_peak_rss_mb = _read_rss_mb()
	print("WINDOWED FPS CAPTURE ready seen, capturing %d frames (peak_rss_mb=%.3f)" % [CAPTURE_FRAMES, _peak_rss_mb])


func _on_playable_failed(reason: String) -> void:
	push_error("WINDOWED FPS CAPTURE FAIL reason=%s" % reason)
	quit(1)


func _on_process_frame() -> void:
	if _finalized:
		return
	var now_us: int = Time.get_ticks_usec()
	if _ready_seen:
		_frame_deltas_us.append(now_us - _last_us)
		var mem_mb: float = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
		if mem_mb > _peak_static_mb:
			_peak_static_mb = mem_mb
		# Sample OS RSS at every 30th frame to keep the cost low; we still
		# record the max over the capture window.
		if _frame_deltas_us.size() % 30 == 0:
			var rss: float = _read_rss_mb()
			if rss > 0.0 and rss > _peak_rss_mb:
				_peak_rss_mb = rss
	_last_us = now_us
	if _ready_seen and _frame_deltas_us.size() >= CAPTURE_FRAMES:
		_finalize()


func _read_rss_mb() -> float:
	# macOS/Linux ps -o rss= reports kilobytes; divide by 1024 for MB. Returns
	# -1 if ps is unavailable, unsupported on this platform, or the parse fails.
	if OS.get_name() == "Windows":
		return -1.0
	var output: Array = []
	var exit_code: int = OS.execute("ps", ["-o", "rss=", "-p", str(OS.get_process_id())], output)
	if exit_code != 0:
		return -1.0
	var raw: String = String(output[0]).strip_edges()
	if raw.is_empty():
		return -1.0
	if not raw.is_valid_int():
		return -1.0
	return float(int(raw)) / 1024.0


func _finalize() -> void:
	if _finalized:
		return
	_finalized = true
	var deltas_ms: Array[float] = []
	for us in _frame_deltas_us:
		deltas_ms.append(float(us) / 1000.0)
	deltas_ms.sort()
	var n: int = deltas_ms.size()
	var median_ms: float = 0.0
	var p95_ms: float = 0.0
	if n > 0:
		median_ms = deltas_ms[n / 2]
		var p95_idx: int = int(floor(float(n) * 0.95))
		p95_ms = deltas_ms[min(p95_idx, n - 1)]
	var observed_fps: float = 0.0
	if median_ms > 0.0:
		observed_fps = 1000.0 / median_ms

	var summary: Dictionary = {
		"frames_captured": n,
		"median_frame_ms": median_ms,
		"p95_frame_ms": p95_ms,
		"observed_fps": observed_fps,
		"peak_static_mem_mb": _peak_static_mb,
		"peak_os_rss_mb": _peak_rss_mb,
		"reference_hardware": "Mac mini M4 (Apple Silicon), macOS 26.5.1",
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"windowed": true,
	}
	print(
		"WINDOWED FPS CAPTURE PASS frames=%d median_ms=%.3f p95_ms=%.3f observed_fps=%.2f peak_mem_mb=%.3f peak_rss_mb=%.3f"
		% [n, median_ms, p95_ms, observed_fps, _peak_static_mb, _peak_rss_mb]
	)
	var f: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
		print("WINDOWED FPS CAPTURE JSON user_path=%s" % OUTPUT_PATH)
	quit(0)
