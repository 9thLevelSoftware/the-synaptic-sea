extends RefCounted
class_name TitleSaveQuery

## ADR-0043: pure decision model for the title screen's Continue item.
## No scene-tree access -- headlessly smokeable. Continue is available
## when a world save exists, the world slot has not been permadeath-
## frozen, AND the save is actually parseable/migratable (PR #57 Codex
## P2: an empty/corrupt/version-incompatible world.json previously still
## enabled Continue, so request_load() would fail post-boot and strand
## the player in a silently-fresh run). Old (pre-Domain-8) saves have no
## world.death.json, so has_died_in defaults false and legacy saves are
## unaffected.

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
	if resolver.has_died_in(WORLD_SLOT_ID):
		return false
	# PR #57 Codex P2: load_world() already runs the migration + version +
	# permadeath gates and is read-only from this call's perspective (its
	# only side effect on a bad file is quarantining it to .corrupt/ and
	# flagging the index row, which is the same cleanup load_world's own
	# callers already rely on -- see save_load_service.gd:116-155). A null
	# result here means request_load() would fail post-boot, so Continue
	# must not be offered.
	return service.load_world() != null
