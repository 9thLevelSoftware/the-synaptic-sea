extends SceneTree

## ADR-0043 TitleSaveQuery pure-model smoke: no-save, has-save, and
## permadeath-frozen-blocks-continue cases, all against the REAL
## user://saves/ dir (no test-scoped save root exists in this codebase --
## mirrors every other save-touching smoke's cleanup discipline).
##
## Pass marker:
##   TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true

const TitleSaveQueryScript := preload("res://scripts/systems/title_save_query.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")

func _initialize() -> void:
	var service := SaveLoadServiceScript.new()
	var resolver := PermadeathResolverScript.new()
	_wipe(service, resolver)

	# Case 1: no save at all.
	var no_save: bool = not TitleSaveQueryScript.is_continue_available(service, resolver)
	if not no_save:
		_fail("expected Continue unavailable with no world save")
		return

	# Case 2: a world save exists and is not frozen.
	var ws := WorldSnapshotScript.new()
	ws.home_ship = {"current_objective_sequence": 1}
	if not service.save_world(ws):
		_fail("save_world failed while seeding has-save case")
		return
	var has_save: bool = TitleSaveQueryScript.is_continue_available(service, resolver)
	if not has_save:
		_fail("expected Continue available with an unfrozen world save")
		return

	# Case 3: the world slot is permadeath-frozen -- Continue must be blocked
	# even though world.json is still present on disk (freeze-not-delete).
	resolver.record_death("world", "death", "test epitaph", 30.0, 2)
	var frozen_blocks: bool = not TitleSaveQueryScript.is_continue_available(service, resolver)
	if not frozen_blocks:
		_fail("expected Continue unavailable when world slot is frozen")
		return

	_wipe(service, resolver)
	print("TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true")
	quit(0)

func _wipe(service: SaveLoadService, resolver: PermadeathResolver) -> void:
	service.delete_current_run()
	resolver.clear_death("world")

func _fail(reason: String) -> void:
	push_error("TITLE SAVE QUERY FAIL reason=%s" % reason)
	var service := SaveLoadServiceScript.new()
	var resolver := PermadeathResolverScript.new()
	_wipe(service, resolver)
	quit(1)
