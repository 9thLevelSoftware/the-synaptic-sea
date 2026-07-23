extends SceneTree

## SFX_WOUND_TREAT is seam+router catalogued (treat path plays it).
## Marker: TREAT WOUND SFX PASS seam=true router=true

const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")


func _initialize() -> void:
	var eid: String = String(AudioEventSeamScript.SFX_WOUND_TREAT)
	if not SfxEventRouterScript.EVENT_CATALOG.has(eid):
		_fail("router missing treat"); return
	var router = SfxEventRouterScript.new()
	router.configure({})
	if router.route(AudioEventSeamScript.SFX_WOUND_TREAT, false) == null:
		_fail("not routable"); return
	print("TREAT WOUND SFX PASS seam=true router=true")
	quit(0)


func _fail(msg: String) -> void:
	print("TREAT WOUND SFX FAIL: %s" % msg)
	quit(1)
