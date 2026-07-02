extends RefCounted
class_name TitleSaveQuery

## ADR-0043: pure decision model for the title screen's Continue item.
## No scene-tree access -- headlessly smokeable. Continue is available
## when a world save exists AND the world slot has not been permadeath-
## frozen. Old (pre-Domain-8) saves have no world.death.json, so
## has_died_in defaults false and legacy saves are unaffected.

const WORLD_SLOT_ID: String = "world"

# `service`/`resolver` are intentionally typed `Object`, not
# `SaveLoadService`/`PermadeathResolver`: those two scripts do not preload
# this file, so a typed param here would risk a preload cycle if either of
# them ever needs to reference TitleSaveQuery. Do not "fix" this to a
# concrete type without first checking neither script preloads this one.
static func is_continue_available(service: Object, resolver: Object) -> bool:
	if service == null or resolver == null:
		return false
	if not service.has_slot(WORLD_SLOT_ID):
		return false
	return not resolver.has_died_in(WORLD_SLOT_ID)
