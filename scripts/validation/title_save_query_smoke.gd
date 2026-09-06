extends SceneTree

## ADR-0043 TitleSaveQuery pure-model smoke: no-save, has-save, and
## permadeath-frozen-blocks-continue cases, all against the REAL
## user://saves/ dir (no test-scoped save root exists in this codebase --
## mirrors every other save-touching smoke's cleanup discipline).
##
## Invalid-world case (PR #57 Codex P2): writes a valid JSON non-object over
## world.json (has_slot("world") still reports true -- the file exists,
## but it is not a world object) and asserts is_continue_available() now
## reads false, proving the strengthened gate actually calls
## load_world() rather than stopping at the has_slot/has_died_in checks.
## Using a syntactically valid array preserves the rejection predicate without
## manufacturing parser diagnostics in a successful smoke.
##
## Pass marker:
##   TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true

const TitleSaveQueryScript := preload("res://scripts/systems/title_save_query.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const CURRENT_WORLD_FIXTURE: String = \
	"res://tests/fixtures/feature_completion/p10_world_v5_transactional.json"

func _initialize() -> void:
	var service := SaveLoadServiceScript.new()
	var resolver := PermadeathResolverScript.new()
	_wipe(service, resolver)

	# Case 1: no save at all.
	var no_save: bool = not TitleSaveQueryScript.is_continue_available(service, resolver)
	if not no_save:
		_fail("expected Continue unavailable with no world save")
		return

	# Case 2: a world save exists and is not frozen. Must stamp real
	# slice_version/godot_version markers -- PR #57 Codex P2 strengthens
	# is_continue_available() to call load_world(), which (like
	# load_from_slot()) rejects a dict whose version markers do not match
	# the running engine. An unstamped fixture would make this case fail
	# for the wrong reason (version mismatch, not "no save").
	var ws = _current_world_fixture(service)
	if ws == null:
		_fail("current fixture could not be prepared")
		return
	service.set_active_run_id(str(ws.run_id))
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
	resolver.clear_death("world")

	# Case 4 (PR #57 Codex P2): a non-object world.json must also block
	# Continue. has_slot("world") reports true
	# (the file exists) and has_died_in is false, so only the strengthened
	# load_world()!=null check catches this -- proving the fix actually
	# calls it rather than stopping at the first two gates. Writes directly
	# to the on-disk path service.WORLD_SLOT_FILE resolves to (same path
	# save_world()/load_world() use), the way title_screen_flow_smoke
	# already reads/writes world.json through the live service.
	var world_path: String = service.WORLD_SLOT_FILE
	var corrupt_file := FileAccess.open(world_path, FileAccess.WRITE)
	if corrupt_file == null:
		_fail("could not open world.json path for corrupt-write fixture")
		return
	corrupt_file.store_string("[]")
	corrupt_file.close()
	var corrupt_blocks: bool = not TitleSaveQueryScript.is_continue_available(service, resolver)
	if not corrupt_blocks:
		_fail("expected Continue unavailable when world.json is corrupt")
		return

	_wipe(service, resolver)
	print("TITLE SAVE QUERY PASS no_save=true has_save=true frozen_blocks=true")
	quit(0)


func _current_world_fixture(service: RefCounted):
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CURRENT_WORLD_FIXTURE))
	if not parsed is Dictionary:
		return null
	_replace_fixture_version(parsed)
	var saves_dir: String = SaveLoadServiceScript.SAVES_DIR
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves_dir)) != OK:
		return null
	var file := FileAccess.open(SaveLoadServiceScript.WORLD_SLOT_FILE, FileAccess.WRITE)
	if file == null:
		return null
	file.store_string(JSON.stringify(parsed, "", true, true))
	file.close()
	var prepared: Dictionary = service.prepare_world_load()
	if not bool(prepared.get("ok", false)):
		return null
	var token: String = str(prepared.get("token", ""))
	var current_dict: Dictionary = service.inspect_prepared_world_for_validation(
		token, str(prepared.get("seal", "")))
	service.discard_prepared_load(token)
	return WorldSnapshotScript.from_dict(
		current_dict, WorldSnapshotScript.WORLD_SLICE_VERSION,
		Engine.get_version_info()["string"])


func _replace_fixture_version(value: Variant) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		for key in dict.keys():
			if str(key) == "godot_version" and str(dict[key]) == "fixture-current":
				dict[key] = Engine.get_version_info()["string"]
			else:
				_replace_fixture_version(dict[key])
	elif value is Array:
		for item in value as Array:
			_replace_fixture_version(item)

func _wipe(service, resolver) -> void:
	service.delete_current_run()
	resolver.clear_death("world")

func _fail(reason: String) -> void:
	push_error("TITLE SAVE QUERY FAIL reason=%s" % reason)
	var service := SaveLoadServiceScript.new()
	var resolver := PermadeathResolverScript.new()
	_wipe(service, resolver)
	quit(1)
