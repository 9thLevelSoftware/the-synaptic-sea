extends SceneTree

## Work progress noise also routes UI_WORK_PROGRESS (catalog + router).
## Marker: WORK PROGRESS UI SFX PASS seam=true router=true

const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")


func _initialize() -> void:
	var eid: String = String(AudioEventSeamScript.UI_WORK_PROGRESS)
	if eid.is_empty():
		_fail("seam"); return
	if not SfxEventRouterScript.EVENT_CATALOG.has(eid):
		_fail("router missing UI_WORK_PROGRESS"); return
	var router = SfxEventRouterScript.new()
	router.configure({})
	if router.route(AudioEventSeamScript.UI_WORK_PROGRESS, false) == null:
		_fail("not routable"); return
	print("WORK PROGRESS UI SFX PASS seam=true router=true")
	quit(0)


func _fail(msg: String) -> void:
	print("WORK PROGRESS UI SFX FAIL: %s" % msg)
	quit(1)
