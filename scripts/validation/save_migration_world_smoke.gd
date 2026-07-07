extends SceneTree

## Session 3 (audit): two world-migration defects in save_migration_service.gd.
##
##  1. unknown_version_passthrough — migrate_world's guard compared
##     `_world_step(current) == null`, but _world_step returns `Callable()`
##     (an EMPTY Callable, never null in GDScript 4). The guard never fired,
##     `.call()` executed the empty Callable, and a world save from a NEWER
##     build collapsed into a corrupt-looking dict instead of passing through
##     to the graceful "rejected (newer than current)" path.
##  2. legacy_home_ship_migrated — _migrate_world_legacy_to_world_4 was a
##     pure duplicate: the embedded home_ship RunSnapshot dict kept its old
##     slice_version, so a world-1..3 file survived the OUTER migration and
##     then failed RunSnapshot.from_dict on the inner slice.
##
## Pure-model smoke (no scene). Marker:
## SAVE MIGRATION WORLD PASS unknown_version_passthrough=true legacy_home_ship_migrated=true

const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")

func _initialize() -> void:
	var svc = SaveMigrationServiceScript.new()

	# --- 1. Unknown (future) world version must pass through intact ---------
	var future_world: Dictionary = {
		"slice_version": "world-99",
		"sentinel_field": "keep_me",
		"home_ship": {"slice_version": "gate2-current-run-99"},
	}
	var result: Dictionary = svc.migrate_world(future_world.duplicate(true))
	var out: Variant = result.get("dict", null)
	if not (out is Dictionary):
		_fail("future world collapsed to %s (empty-Callable guard bug)" % str(out))
		return
	if str((out as Dictionary).get("sentinel_field", "")) != "keep_me":
		_fail("future world lost fields through migrate_world: %s" % str(out))
		return
	if bool(result.get("migrated", true)):
		_fail("future world reported migrated=true (should be pass-through)")
		return
	var passthrough_ok: bool = true

	# --- 2. Legacy world must migrate the embedded home_ship slice ----------
	var legacy_world: Dictionary = {
		"slice_version": "world-2",
		"home_ship": {
			"slice_version": SaveMigrationServiceScript.KNOWN_VERSIONS[0],
			"player_position": [1.0, 0.0, 2.0],
		},
	}
	var legacy_result: Dictionary = svc.migrate_world(legacy_world)
	var legacy_out: Variant = legacy_result.get("dict", null)
	if not (legacy_out is Dictionary):
		_fail("legacy world migration returned null")
		return
	if str((legacy_out as Dictionary).get("slice_version", "")) != SaveMigrationServiceScript.WORLD_TARGET_VERSION:
		_fail("outer world version not stamped to target")
		return
	var inner: Variant = (legacy_out as Dictionary).get("home_ship", null)
	if not (inner is Dictionary):
		_fail("home_ship missing after legacy world migration")
		return
	var inner_version: String = str((inner as Dictionary).get("slice_version", ""))
	if inner_version != SaveMigrationServiceScript.TARGET_VERSION:
		_fail("embedded home_ship slice not migrated: slice_version='%s' expected '%s'" % [inner_version, SaveMigrationServiceScript.TARGET_VERSION])
		return

	print("SAVE MIGRATION WORLD PASS unknown_version_passthrough=%s legacy_home_ship_migrated=true" % str(passthrough_ok).to_lower())
	quit(0)

func _fail(reason: String) -> void:
	push_error("SAVE MIGRATION WORLD FAIL reason=%s" % reason)
	quit(1)
