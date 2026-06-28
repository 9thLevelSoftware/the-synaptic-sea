extends SceneTree
# A11Y-P1-001: focused validation for the scalable HUD and world text seam.
#
# This smoke proves that the new AccessibilitySettings seam drives:
# - HUD font_size (Control Label font theme override)
# - HUD panel + label minimum sizes
# - World Label3D pixel_size values for the breach unsafe marker (and, when
#   debug_affordance_labels_enabled is set, the affordance/landmark labels too).
#   (M7-B Task 7 retired the timed fire-zone Label3D.)
#
# It is structured as three sequential passes against the SAME live main
# scene instance so it exercises apply_accessibility_settings() in place
# rather than just the constructor defaults:
#   1. Default scale (1.0) matches the pre-A11Y-P1-001 hard-coded values.
#   2. Enlarged scale (1.5) produces scaled font, panel, and label sizes.
#   3. Maximum scale (2.0) produces the maximum allowed scale sizes.
#
# The HUD text remains sourced from runtime state at every scale (the
# tracker text is the same at every scale, just rendered larger).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AccessibilitySettingsScript := preload("res://scripts/ui/accessibility_settings.gd")
const TIMEOUT_FRAMES: int = 240
const DEFAULT_BASE_HUD_FONT_SIZE: int = 18
const DEFAULT_BASE_HUD_SIZE: Vector2 = Vector2(520.0, 250.0)
const DEFAULT_BASE_AFFORDANCE_PIXEL_SIZE: float = 0.003
const DEFAULT_BASE_HAZARD_PIXEL_SIZE: float = 0.0035
const DEFAULT_BASE_VITALS_FONT_SIZE: int = 18
const DEFAULT_BASE_VITALS_SIZE: Vector2 = Vector2(360.0, 150.0)

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var phase: int = 0
var finalized: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if phase == 0:
		phase = -1
		_validate_default_scale(playable)
	elif phase == 2:
		phase = -1
		_validate_15x_scale(playable)
	elif phase == 4:
		phase = -1
		_validate_20x_scale(playable)
	elif phase == 6:
		finished = true
		# A11Y-P1-001: disconnect from process_frame BEFORE calling
		# _finalize so the duplicate process_frame emission at end of
		# frame cannot re-enter the function. quit(0) is still called
		# to make the SceneTree actually exit.
		if process_frame.is_connected(_on_process_frame):
			process_frame.disconnect(_on_process_frame)
		_finalize()

func _validate_default_scale(playable: PlayableGeneratedShip) -> void:
	var tracker: ObjectiveTracker = playable.tracker as ObjectiveTracker
	if tracker == null:
		_fail("default: tracker missing")
		return
	var font_size: int = int(tracker.label.get_theme_font_size("font_size"))
	if font_size != DEFAULT_BASE_HUD_FONT_SIZE:
		_fail("default: font_size=%d expected %d" % [font_size, DEFAULT_BASE_HUD_FONT_SIZE])
		return
	if tracker.custom_minimum_size != DEFAULT_BASE_HUD_SIZE:
		_fail("default: cmin=%s expected %s" % [str(tracker.custom_minimum_size), str(DEFAULT_BASE_HUD_SIZE)])
		return
	# HUD text still sourced from runtime state (not hard-coded).
	var hud_text: String = tracker.get_hud_text()
	if not hud_text.contains("Synaptic Sea First Playable"):
		_fail("default: HUD missing runtime title: %s" % hud_text)
		return
	if not hud_text.contains("Current:"):
		_fail("default: HUD missing runtime 'Current:' line: %s" % hud_text)
		return
	# Default scale must reproduce the pre-A11Y-P1-001 world label sizes.
	# M7-B Task 7: the timed fire-zone Label3D was retired; only the breach
	# unsafe marker remains as a scalable world hazard label.
	var marker_pixel: float = -1.0
	if playable.unsafe_room_marker != null:
		marker_pixel = float(playable.unsafe_room_marker.pixel_size)
		if not is_equal_approx(marker_pixel, DEFAULT_BASE_HAZARD_PIXEL_SIZE):
			_fail("default: unsafe marker pixel_size=%.6f expected %.6f" % [marker_pixel, DEFAULT_BASE_HAZARD_PIXEL_SIZE])
			return
	if not _check_vitals_scale(playable, 1.0, "default"): return
	print("A11Y TEXT SCALE DEFAULT PASS font=%d panel=%s marker_pixel=%.4f" % [
		font_size,
		str(tracker.custom_minimum_size),
		marker_pixel,
	])
	_apply_scale(playable, 1.5)
	phase = 2

func _apply_scale(playable: PlayableGeneratedShip, scale: float) -> void:
	var settings: RefCounted = AccessibilitySettingsScript.new()
	settings.set_text_scale(scale)
	playable.apply_accessibility_settings(settings)

func _validate_15x_scale(playable: PlayableGeneratedShip) -> void:
	var tracker: ObjectiveTracker = playable.tracker as ObjectiveTracker
	if tracker == null:
		_fail("1.5x: tracker missing")
		return
	var expected_font: int = int(round(float(DEFAULT_BASE_HUD_FONT_SIZE) * 1.5))
	var actual_font: int = int(tracker.label.get_theme_font_size("font_size"))
	if actual_font != expected_font:
		_fail("1.5x: font_size=%d expected %d" % [actual_font, expected_font])
		return
	var expected_cmin: Vector2 = Vector2(DEFAULT_BASE_HUD_SIZE.x * 1.5, DEFAULT_BASE_HUD_SIZE.y * 1.5)
	if tracker.custom_minimum_size != expected_cmin:
		_fail("1.5x: cmin=%s expected %s" % [str(tracker.custom_minimum_size), str(expected_cmin)])
		return
	# HUD text still sourced from runtime state.
	var hud_text: String = tracker.get_hud_text()
	if not hud_text.contains("Current:"):
		_fail("1.5x: HUD missing runtime 'Current:' line: %s" % hud_text)
		return
	# World labels: at 1.5x, pixel_size is base/1.5 with a documented
	# minimum readable size of 0.0005. The two hazard label bases (0.0035)
	# divided by 1.5 land at ~0.002333, well above the floor.
	var expected_hazard_pixel: float = DEFAULT_BASE_HAZARD_PIXEL_SIZE / 1.5
	var marker_pixel: float = -1.0
	if playable.unsafe_room_marker != null:
		marker_pixel = float(playable.unsafe_room_marker.pixel_size)
		if not is_equal_approx(marker_pixel, expected_hazard_pixel):
			_fail("1.5x: unsafe marker pixel_size=%.6f expected %.6f" % [marker_pixel, expected_hazard_pixel])
			return
	if not _check_vitals_scale(playable, 1.5, "1.5x"): return
	print("A11Y TEXT SCALE 1.5X PASS font=%d panel=%s marker_pixel=%.6f" % [
		actual_font,
		str(tracker.custom_minimum_size),
		marker_pixel,
	])
	_apply_scale(playable, 2.0)
	phase = 4

func _validate_20x_scale(playable: PlayableGeneratedShip) -> void:
	var tracker: ObjectiveTracker = playable.tracker as ObjectiveTracker
	if tracker == null:
		_fail("2.0x: tracker missing")
		return
	var expected_font: int = int(round(float(DEFAULT_BASE_HUD_FONT_SIZE) * 2.0))
	var actual_font: int = int(tracker.label.get_theme_font_size("font_size"))
	if actual_font != expected_font:
		_fail("2.0x: font_size=%d expected %d" % [actual_font, expected_font])
		return
	var expected_cmin: Vector2 = Vector2(DEFAULT_BASE_HUD_SIZE.x * 2.0, DEFAULT_BASE_HUD_SIZE.y * 2.0)
	if tracker.custom_minimum_size != expected_cmin:
		_fail("2.0x: cmin=%s expected %s" % [str(tracker.custom_minimum_size), str(expected_cmin)])
		return
	# HUD text still sourced from runtime state.
	var hud_text: String = tracker.get_hud_text()
	if not hud_text.contains("Current:"):
		_fail("2.0x: HUD missing runtime 'Current:' line: %s" % hud_text)
		return
	# World labels: at 2.0x, pixel_size is base/2.0.
	var expected_hazard_pixel: float = DEFAULT_BASE_HAZARD_PIXEL_SIZE / 2.0
	var marker_pixel: float = -1.0
	if playable.unsafe_room_marker != null:
		marker_pixel = float(playable.unsafe_room_marker.pixel_size)
		if not is_equal_approx(marker_pixel, expected_hazard_pixel):
			_fail("2.0x: unsafe marker pixel_size=%.6f expected %.6f" % [marker_pixel, expected_hazard_pixel])
			return
	if not _check_vitals_scale(playable, 2.0, "2.0x"): return
	print("A11Y TEXT SCALE 2.0X PASS font=%d panel=%s marker_pixel=%.6f" % [
		actual_font,
		str(tracker.custom_minimum_size),
		marker_pixel,
	])
	phase = 6

func _finalize() -> void:
	# A11Y-P1-001: re-entry guard. Godot's process_frame can fire twice
	# around quit() in headless --script mode; without this guard the
	# PASS marker prints twice and the strict regression filter would
	# treat the duplicate as a parse/load artifact.
	if finalized:
		return
	finalized = true
	print("MAIN PLAYABLE TEXT SCALE PASS scales=3 default=1.0x1.5x2.0 runtime_text=present")
	_cleanup_and_quit(0)

func _check_vitals_scale(playable: PlayableGeneratedShip, scale: float, tag: String) -> bool:
	var vitals: PlayerVitalsPanel = playable.vitals_panel as PlayerVitalsPanel
	if vitals == null:
		_fail("%s: vitals panel missing" % tag)
		return false
	var expected_font: int = int(round(float(DEFAULT_BASE_VITALS_FONT_SIZE) * scale))
	var actual_font: int = int(vitals.label.get_theme_font_size("font_size"))
	if actual_font != expected_font:
		_fail("%s: vitals font_size=%d expected %d" % [tag, actual_font, expected_font])
		return false
	var expected_cmin: Vector2 = Vector2(DEFAULT_BASE_VITALS_SIZE.x * scale, DEFAULT_BASE_VITALS_SIZE.y * scale)
	if vitals.custom_minimum_size != expected_cmin:
		_fail("%s: vitals cmin=%s expected %s" % [tag, str(vitals.custom_minimum_size), str(expected_cmin)])
		return false
	return true

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE TEXT SCALE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
