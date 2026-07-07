extends SceneTree

## Tranche 1 (audit): `playable_failed` was emitted on load failure but never
## connected anywhere — title_main.gd's _poll_for_playable_started re-deferred
## forever on a dead boot (infinite call_deferred loop), and a failure after a
## successful boot was silently ignored (the player stayed in a broken session
## with no way back).
##
## Drives the REAL title flow: title_main boots gameplay via _on_title_start,
## then the loader-failure entry point (_on_loader_failed — the same method the
## loader's failed signal calls) fires. The title must tear the session down,
## return to the title menu, and surface the failure reason.
##
## Pass marker: TITLE LOAD FAILURE PASS returned_to_title=true error_surfaced=true menu_visible=true

const TITLE_SCENE: PackedScene = preload("res://scenes/title_main.tscn")
const TIMEOUT_FRAMES: int = 400
const FAIL_REASON: String = "smoke_forced_failure"

var title: Node
var frame_count: int = 0
var phase: String = "wait_playable"
var settle_frames: int = 0
var finished: bool = false

func _initialize() -> void:
	title = TITLE_SCENE.instantiate()
	get_root().add_child(title)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if frame_count > TIMEOUT_FRAMES:
		_fail("timeout in phase %s" % phase)
		return
	match phase:
		"wait_playable":
			if frame_count == 1:
				if not title.has_method("_on_title_start"):
					_fail("title scene missing _on_title_start")
					return
				title._on_title_start()
				return
			var pi = title.playable_instance
			if pi != null and is_instance_valid(pi) and pi.playable_started:
				# Fire the production loader-failure entry point.
				pi._on_loader_failed(FAIL_REASON)
				phase = "settle"
		"settle":
			settle_frames += 1
			if settle_frames < 10:
				return
			_validate()

func _validate() -> void:
	finished = true
	if title.main_node != null and is_instance_valid(title.main_node):
		_fail("gameplay session still alive after playable_failed — title never tore it down")
		return
	if not ("_last_boot_error" in title) or String(title._last_boot_error) != FAIL_REASON:
		_fail("failure reason not surfaced on the title screen")
		return
	if title.menu_panel == null or not is_instance_valid(title.menu_panel) or not title.menu_panel.visible:
		_fail("title menu not rebuilt/visible after failure")
		return
	print("TITLE LOAD FAILURE PASS returned_to_title=true error_surfaced=true menu_visible=true")
	_cleanup(0)

func _fail(reason: String) -> void:
	push_error("TITLE LOAD FAILURE FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if is_instance_valid(title):
		title.queue_free()
	quit(code)
