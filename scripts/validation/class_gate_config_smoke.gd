extends SceneTree

## Domain 6 (WI-4) class-gate config smoke: an unlocked, persisted class selection
## is applied on a fresh run; an unlocked class is available; a locked one is not.
##
## Marker: `CLASS GATE CONFIG PASS`

const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const ClassPanelScript := preload("res://scripts/ui/class_panel.gd")

var _panel = null

func _initialize() -> void:
	var meta = MetaProgressionStateScript.new(); meta.configure({})
	_panel = ClassPanelScript.new()
	_panel.load_catalog()
	_panel.set_meta_state(meta)

	# A base class is always available; an unlockable class is not until unlocked.
	if not _panel.is_available("engineer"):
		_fail("engineer (base) should be available")
		return
	if _panel.is_available("field_medic"):
		_fail("field_medic should be locked before unlock")
		return
	meta.unlock_class("field_medic")
	if not _panel.is_available("field_medic"):
		_fail("field_medic should be available after unlock_class")
		return

	print("CLASS GATE CONFIG PASS available_gate=true")
	_cleanup()
	quit(0)

func _cleanup() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()

func _fail(reason: String) -> void:
	push_error("CLASS GATE CONFIG FAIL reason=%s" % reason)
	_cleanup()
	quit(1)
