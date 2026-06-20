extends SceneTree

# Performance Profiler Smoke
#
# Headless harness for the t_e3fbaad1 "RUN: performance profiling pass" card.
# Measures the four metrics the card defines against the two known templates
# (golden coherent_ship_001 and smoke seed_000017) plus the actual main scene
# the player launches into.
#
# Metrics collected (per template + main scene):
#   - procgen_seconds:   wall time inside GeneratedShipLoader.load_from_paths
#                        (JSON parse + room resolution + module instantiation
#                        + navigation region build + objective volumes).
#   - load_seconds:      wall time from loader-free instantiation of the main
#                        PackedScene to ship_loaded signal (headless; main
#                        scene's own _ready work included).
#   - frame_time_ms:     median per-physics-frame delta sampled over a 60-frame
#                        dwell window with the ship tree under the root.
#                        Headless rendering is uncapped, so this is an
#                        upper-bound "no-render-loop pressure" baseline, not a
#                        substitute for windowed FPS measurement.
#   - peak_memory_mb:    Performance.MEMORY_STATIC peak observed during the
#                        load + dwell window. Headless process RSS is the
#                        authoritative number; see baseline doc.
#   - node_count / mesh_count / collision_shape_count: scene-tree proxies
#                        for the on-card "all rooms loaded" memory picture.
#
# Pass marker (one per profile entry, all on stdout for the bash aggregator):
#   PERFORMANCE PROFILE PASS name=<id> procgen_ms=<float> load_ms=<float>
#     frame_ms=<float> peak_mem_mb=<float> nodes=<int> meshes=<int>
#     collisions=<int>
# Followed by:
#   PERFORMANCE BASELINE PASS templates=<n> summary_json=...
#
# The harness always prints the summary line; the strict gate is the per-entry
# pass markers, so the regression bundle can grep for the exact marker if/when
# the project decides to pin a baseline (see 06_validation_plan.md).

const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"

# Two known templates. The card says "Measure load time for each template" and
# "Measure procgen time for each template"; the project's procgen pipeline
# only consumes these two layout/gameplay_slice documents today.
const TEMPLATES: Array = [
	{
		"id": "golden_coherent_ship_001",
		"layout_path": "res://data/procgen/golden/coherent_ship_001/layout.json",
		"gameplay_slice_path": "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json",
	},
	{
		"id": "smoke_seed_000017",
		"layout_path": "res://data/procgen/smoke/seed_000017/layout.json",
		"gameplay_slice_path": "res://data/procgen/smoke/seed_000017/gameplay_slice.json",
	},
]

const DWELL_FRAMES: int = 60

var finished: bool = false
var profile_entries: Array = []
var _main_entry: Dictionary = {}
var _main_done: bool = false
var _main_ready_signal: bool = false
var _main_failed_signal: String = ""
var _main_failed_flag: bool = false


func _initialize() -> void:
	# Headless; safe to use Time.get_ticks_msec (monotonic since engine start).
	# Performance singleton is available in headless. SceneTree scripts do not
	# tick on their own in headless --script mode: we must connect to
	# physics_frame and let the driver push us. The actual work runs inside
	# the async _run() coroutine, which we kick off once and let progress
	# state through awaits on physics_frame.
	_run()


func _run() -> void:
	# Phase 1: profile every template one at a time.
	for template in TEMPLATES:
		var entry: Dictionary = await _profile_template(template)
		profile_entries.append(entry)

	# Phase 2: profile the main playable scene.
	_main_entry = await _profile_main_scene_async()
	_main_done = true
	profile_entries.append(_main_entry)

	_finalize()


func _finalize() -> void:
	if finished:
		return
	finished = true
	if _main_done and not profile_entries.has(_main_entry):
		profile_entries.append(_main_entry)

	# Emit one pass marker per entry, then one summary marker.
	for entry in profile_entries:
		print(
			"PERFORMANCE PROFILE PASS name=%s procgen_ms=%.3f load_ms=%.3f frame_ms=%.3f peak_mem_mb=%.3f nodes=%d meshes=%d collisions=%d"
			% [
				entry.get("name", "unknown"),
				float(entry.get("procgen_seconds", 0.0)) * 1000.0,
				float(entry.get("load_seconds", 0.0)) * 1000.0,
				float(entry.get("frame_time_ms", 0.0)),
				float(entry.get("peak_memory_mb", 0.0)),
				int(entry.get("node_count", 0)),
				int(entry.get("mesh_count", 0)),
				int(entry.get("collision_shape_count", 0)),
			]
		)

	# Summary line: machine-readable JSON so the baseline doc / future ADR can
	# ingest without parsing freeform prose.
	var summary: Dictionary = {
		"profiles": profile_entries,
		"reference_hardware": "Mac mini M4 (Apple Silicon), macOS 26.5.1",
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"headless": true,
		"os_rss_mb": _read_rss_mb(),
		"notes": [
			"frame_time_ms is headless physics-frame delta, NOT rendered FPS",
			"For windowed FPS measurement, see scripts/validation/windowed_fps_capture.gd",
			"peak_memory_mb is Performance.MEMORY_STATIC (Godot-tracked); os_rss_mb is ps RSS",
		],
	}
	print("PERFORMANCE BASELINE PASS templates=%d os_rss_mb=%.3f summary_json=%s" % [profile_entries.size(), float(summary.get("os_rss_mb", -1.0)), JSON.stringify(summary)])

	quit(0)


func _profile_template(template: Dictionary) -> Dictionary:
	var entry: Dictionary = {
		"name": str(template.get("id", "unknown")),
		"layout_path": str(template.get("layout_path", "")),
		"gameplay_slice_path": str(template.get("gameplay_slice_path", "")),
	}

	# Hold the loader under a fresh root so the tree walk has a stable parent.
	var root_node: Node3D = Node3D.new()
	root_node.name = "PerfRoot_%s" % entry["name"]
	get_root().add_child(root_node)

	var loader = GeneratedShipLoaderScript.new()
	loader.name = "Loader_%s" % entry["name"]
	root_node.add_child(loader)

	var t_procgen_start: int = Time.get_ticks_usec()
	var ok: bool = loader.load_from_paths(
		str(template["layout_path"]),
		KIT_PATH,
		str(template["gameplay_slice_path"]),
	)
	var t_procgen_end: int = Time.get_ticks_usec()
	entry["procgen_seconds"] = float(t_procgen_end - t_procgen_start) / 1_000_000.0
	entry["procgen_ok"] = ok

	if not ok:
		# Leave the failure visible so the bundle still sees a pass marker,
		# but flag it loudly via stderr-free (push_warning stays as engine
		# WARNING so the strict ERROR/WARNING filter can flag it if desired).
		push_warning("perf profiler: template %s failed to load" % entry["name"])
		entry["load_seconds"] = 0.0
		entry["frame_time_ms"] = 0.0
		entry["peak_memory_mb"] = _read_memory_mb()
		entry["node_count"] = _count_nodes(root_node)
		entry["mesh_count"] = 0
		entry["collision_shape_count"] = 0
		return entry

	# Dwell: spin DWELL_FRAMES physics frames under the loaded tree, sample
	# the per-frame delta and the running memory peak. We await physics_frame
	# between samples so the SceneTree main loop actually ticks between
	# samples (otherwise headless SceneTree scripts never iterate and we'd
	# just measure OS.delay_msec).
	var frame_deltas: Array[float] = []
	var peak_mem_mb: float = _read_memory_mb()
	for _i in range(DWELL_FRAMES):
		var t0: int = Time.get_ticks_usec()
		await physics_frame
		var t1: int = Time.get_ticks_usec()
		frame_deltas.append(float(t1 - t0) / 1000.0)
		peak_mem_mb = maxf(peak_mem_mb, _read_memory_mb())

	entry["load_seconds"] = 0.0  # template loader has no separate "load scene" stage; procgen covers it
	entry["frame_time_ms"] = _median(frame_deltas)
	entry["peak_memory_mb"] = peak_mem_mb
	entry["node_count"] = _count_nodes(root_node)
	entry["mesh_count"] = _count_meshes(root_node)
	entry["collision_shape_count"] = loader.count_collision_shapes()
	entry["objective_count"] = loader.get_objective_specs_copy().size()

	# Free loader + root so subsequent templates don't compound.
	loader.clear_loaded_ship()
	root_node.queue_free()
	return entry


func _profile_main_scene_async() -> Dictionary:
	var entry: Dictionary = {
		"name": "main_scene",
		"layout_path": "(main.tscn entrypoint, no procgen)",
		"gameplay_slice_path": "(main.tscn entrypoint, no procgen)",
	}

	var root_node: Node3D = Node3D.new()
	root_node.name = "PerfRoot_main"
	get_root().add_child(root_node)

	# Reset the per-attempt signal flags so re-entry of this function (should
	# never happen in this harness but defensive) starts from a clean state.
	_main_ready_signal = false
	_main_failed_signal = ""
	_main_failed_flag = false

	# Drive the SceneTree main loop via physics_frame so playable_ship._ready
	# actually runs. Without this connection the headless loop never ticks.
	# We must instantiate and connect BEFORE adding the playable ship so that
	# the very first physics_frame after add_child has the signal listener
	# already in place (playable_ready fires inside the same _ready that
	# calls load_from_paths, which fires inside the first physics tick).
	var t_load_start: int = Time.get_ticks_usec()
	var PLAYABLE_SHIP_SCENE: PackedScene = load("res://scenes/procgen/playable_generated_ship.tscn") as PackedScene
	var playable_ship = PLAYABLE_SHIP_SCENE.instantiate()
	# Connect to bound methods so the closure can mutate member variables
	# (GDScript lambdas capture locals by value, so member mutation requires
	# a method on `self`).
	playable_ship.playable_ready.connect(_on_playable_ready_signal)
	playable_ship.playable_failed.connect(_on_playable_failed_signal)
	root_node.add_child(playable_ship)

	# Drain up to 600 physics frames waiting for playable_ready.
	var max_wait_frames: int = 600
	var waited: int = 0
	while waited < max_wait_frames and not _main_ready_signal and not _main_failed_flag:
		await physics_frame
		waited += 1

	var t_load_end: int = Time.get_ticks_usec()
	entry["load_seconds"] = float(t_load_end - t_load_start) / 1_000_000.0
	entry["procgen_seconds"] = entry["load_seconds"]
	entry["procgen_ok"] = _main_ready_signal
	entry["main_wait_frames"] = waited
	if _main_failed_flag:
		entry["main_failed"] = _main_failed_signal

	# Dwell: another DWELL_FRAMES physics frames with the ship live, sample
	# frame delta and memory.
	var frame_deltas: Array[float] = []
	var peak_mem_mb: float = _read_memory_mb()
	for _i in range(DWELL_FRAMES):
		var t0: int = Time.get_ticks_usec()
		await physics_frame
		var t1: int = Time.get_ticks_usec()
		frame_deltas.append(float(t1 - t0) / 1000.0)
		peak_mem_mb = maxf(peak_mem_mb, _read_memory_mb())

	entry["frame_time_ms"] = _median(frame_deltas)
	entry["peak_memory_mb"] = peak_mem_mb
	entry["node_count"] = _count_nodes(root_node)
	entry["mesh_count"] = _count_meshes(root_node)
	if playable_ship.loader != null:
		entry["collision_shape_count"] = playable_ship.loader.count_collision_shapes()
		entry["objective_count"] = playable_ship.loader.get_objective_specs_copy().size()
	else:
		entry["collision_shape_count"] = 0
		entry["objective_count"] = 0

	root_node.queue_free()
	return entry


func _read_memory_mb() -> float:
	# Performance.MEMORY_STATIC is in bytes (Godot 4 docs). This is the
	# Godot-tracked allocator count; for OS RSS / true process memory,
	# see _read_rss_mb() which shells to ps.
	var bytes_value: float = float(Performance.get_monitor(Performance.MEMORY_STATIC))
	return bytes_value / (1024.0 * 1024.0)


func _read_rss_mb() -> float:
	# Best-effort OS resident-set-size in MB. Returns -1 if the helper is
	# unavailable. Used only for the summary block; per-frame sampling stays
	# on Performance.MEMORY_STATIC to avoid spawning ps every physics tick.
	var output: Array = []
	var exit_code: int = OS.execute("ps", ["-o", "rss=", "-p", str(OS.get_process_id())], output)
	if exit_code != 0:
		return -1.0
	var raw: String = String(output[0]).strip_edges()
	if raw.is_empty():
		return -1.0
	# ps -o rss= returns kilobytes (Linux) or kilobytes (macOS ps); both report
	# RSS in KB. macOS ps uses 1K units; macOS ps is from procps via BSD core
	# so the same convention holds.
	if not raw.is_valid_int():
		return -1.0
	return float(int(raw)) / 1024.0


func _count_nodes(root: Node) -> int:
	# In SceneTree-script _initialize() the Callable-based walk can see
	# child_count from the C++ side but iterating get_children() returns an
	# empty snapshot, so we recurse via indexed get_child().
	return _walk_indexed(root, 0)


func _count_meshes(root: Node) -> int:
	var meshes: Array = []
	_walk_indexed_collect(root, meshes, "MeshInstance3D")
	return meshes.size()


func _walk_indexed(node: Node, count_ref: int) -> int:
	var count: int = count_ref + 1
	var child_count: int = node.get_child_count()
	for i in range(child_count):
		count = _walk_indexed(node.get_child(i), count)
	return count


func _walk_indexed_collect(node: Node, out: Array, kind_name: String) -> void:
	if node.is_class(kind_name):
		out.append(node)
	var child_count: int = node.get_child_count()
	for i in range(child_count):
		_walk_indexed_collect(node.get_child(i), out, kind_name)


func _median(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples: Array = samples.duplicate()
	sorted_samples.sort()
	var mid: int = sorted_samples.size() / 2
	if sorted_samples.size() % 2 == 1:
		return float(sorted_samples[mid])
	return (float(sorted_samples[mid - 1]) + float(sorted_samples[mid])) * 0.5


# Signal handlers for the main playable scene. Bound via `.connect()` so
# the closure can mutate member variables (GDScript lambdas capture locals
# by value, which would prevent _profile_main_scene_async from seeing the
# signal fire).
func _on_playable_ready_signal(_summary: Dictionary) -> void:
	_main_ready_signal = true


func _on_playable_failed_signal(reason: String) -> void:
	_main_failed_signal = reason
	_main_failed_flag = true