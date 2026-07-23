extends SceneTree

## Ship-mod install/uninstall UI SFX ids exist in seam + router and route.
## Marker: SHIP MOD AUDIO PASS seam=true router=true route=true

const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")


func _initialize() -> void:
	var install_id: String = String(AudioEventSeamScript.UI_SHIP_MOD_INSTALL)
	var uninstall_id: String = String(AudioEventSeamScript.UI_SHIP_MOD_UNINSTALL)
	if install_id.is_empty() or uninstall_id.is_empty():
		_fail("seam constants"); return
	if not SfxEventRouterScript.EVENT_CATALOG.has(install_id):
		_fail("router missing install"); return
	if not SfxEventRouterScript.EVENT_CATALOG.has(uninstall_id):
		_fail("router missing uninstall"); return
	var router = SfxEventRouterScript.new()
	router.configure({})
	if router.route(AudioEventSeamScript.UI_SHIP_MOD_INSTALL, false) == null:
		_fail("install not routable"); return
	if router.route(AudioEventSeamScript.UI_SHIP_MOD_UNINSTALL, false) == null:
		_fail("uninstall not routable"); return
	print("SHIP MOD AUDIO PASS seam=true router=true route=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SHIP MOD AUDIO FAIL: %s" % msg)
	quit(1)
