extends SceneTree

## UI_WOUNDS_OPEN is catalogued and routable (panel open seam).
## Marker: WOUNDS PANEL OPEN SFX PASS seam=true router=true

const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")


func _initialize() -> void:
	var eid: String = String(AudioEventSeamScript.UI_WOUNDS_OPEN)
	if eid.is_empty():
		_fail("seam"); return
	if not SfxEventRouterScript.EVENT_CATALOG.has(eid):
		_fail("router"); return
	var router = SfxEventRouterScript.new()
	router.configure({})
	if router.route(AudioEventSeamScript.UI_WOUNDS_OPEN, false) == null:
		_fail("route"); return
	print("WOUNDS PANEL OPEN SFX PASS seam=true router=true")
	quit(0)


func _fail(msg: String) -> void:
	print("WOUNDS PANEL OPEN SFX FAIL: %s" % msg)
	quit(1)
