extends RefCounted
class_name SaveMigrationService

## Save migration service (ADR-0032).
##
## Pure model. Owns a deterministic migration table mapping
## `from_version -> to_version`. Each step receives the parsed
## Dictionary and returns a new Dictionary with the target version's
## keys. No scene-tree access, no engine time. New steps are appended;
## old steps are never removed (auditable history).
##
## Invoked by `SaveLoadService.load_from_slot` BEFORE `RunSnapshot.from_dict`
## (or `WorldSnapshot.from_dict`). The migrated form is written to
## `<slot_id>.migrated.json` so the player can inspect the upgrade.

## The ordered list of slot schema versions the service knows how to
## walk. Each entry maps `from -> to`; the chain is followed until
## the slot's `slice_version` matches `target_version`.
const KNOWN_VERSIONS: Array = [
	"gate2-current-run-1",  # legacy: 6 model summaries, no player_progression
	"gate2-current-run-2",  # added player_progression_summary (Phase 3)
	"gate2-current-run-3",  # added slot_id / slot_kind / parent_world_slot metadata (Task 11)
]

const TARGET_VERSION: String = "gate2-current-run-3"
const WORLD_TARGET_VERSION: String = "world-4"

func migrate_run(parsed: Variant) -> Dictionary:
	# {dict, from_version, to_version, migrated:bool}
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"dict": null, "from_version": "", "to_version": TARGET_VERSION, "migrated": false}
	var dict: Dictionary = parsed
	var current: String = str(dict.get("slice_version", ""))
	if current == TARGET_VERSION:
		return {"dict": dict, "from_version": current, "to_version": TARGET_VERSION, "migrated": false}
	if current.is_empty():
		# Legacy file without slice_version: treat as the oldest known version.
		current = KNOWN_VERSIONS[0]
	if _index_of(current) < 0:
		# Newer than us — cannot downgrade.
		return {"dict": null, "from_version": current, "to_version": TARGET_VERSION, "migrated": false}
	var working: Dictionary = dict.duplicate(true)
	var migrated: bool = false
	# Walk the migration chain. We advance an index instead of relying
	# on the dict's `slice_version` so an older migration step that
	# forgets to bump the version cannot infinite-loop the loop.
	var chain: Array = KNOWN_VERSIONS.duplicate()
	var start_idx: int = _index_of(current)
	var target_idx: int = _index_of(TARGET_VERSION)
	while start_idx < target_idx:
		var from_v: String = chain[start_idx]
		var step = _step(from_v)
		if step == null or not step.is_valid():
			break
		working = step.call(working)
		# Stamp the next known version so the file is forward-compatible
		# even if the step itself didn't update slice_version.
		var next_v: String = chain[start_idx + 1] if start_idx + 1 < chain.size() else TARGET_VERSION
		working["slice_version"] = next_v
		start_idx += 1
		migrated = true
	working["slice_version"] = TARGET_VERSION
	return {"dict": working, "from_version": current, "to_version": TARGET_VERSION, "migrated": migrated}

func migrate_world(parsed: Variant) -> Dictionary:
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"dict": null, "from_version": "", "to_version": WORLD_TARGET_VERSION, "migrated": false}
	var dict: Dictionary = parsed
	var current: String = str(dict.get("slice_version", ""))
	if current == WORLD_TARGET_VERSION:
		return {"dict": dict, "from_version": current, "to_version": WORLD_TARGET_VERSION, "migrated": false}
	if current.is_empty():
		current = "world-1"  # legacy world snapshot
	# For worlds we only know world-4 today. Future ADRs extend.
	# Session 3 (audit): _world_step returns Callable() for unknown versions —
	# an EMPTY Callable is never `== null` in GDScript 4, so the old guard
	# never fired and `.call()` collapsed the dict. Guard with is_valid()
	# (the migrate_run pattern); pass-through is the documented intent so a
	# NEWER-version world reaches the graceful from_dict rejection path
	# instead of being quarantined as corrupt.
	var step: Callable = _world_step(current)
	if not step.is_valid():
		return {"dict": dict, "from_version": current, "to_version": WORLD_TARGET_VERSION, "migrated": false}
	var working: Dictionary = step.call(dict)
	working["slice_version"] = WORLD_TARGET_VERSION
	return {"dict": working, "from_version": current, "to_version": WORLD_TARGET_VERSION, "migrated": true}

func _step(from_version: String) -> Callable:
	match from_version:
		"gate2-current-run-1":
			return _migrate_v1_to_v2
		"gate2-current-run-2":
			return _migrate_v2_to_v3
	return Callable()

func _world_step(from_version: String) -> Callable:
	match from_version:
		"world-1", "world-2", "world-3":
			return _migrate_world_legacy_to_world_4
	return Callable()

func _index_of(version: String) -> int:
	return KNOWN_VERSIONS.find(version)

func _migrate_v1_to_v2(dict: Dictionary) -> Dictionary:
	# Add player_progression_summary default if missing or empty. The
	# legacy v1 save might carry an empty {} placeholder rather than no
	# key at all (the v1 save was authored with the default `{}`); we
	# treat both cases as "needs migration" so the loaded snapshot has
	# a usable default the coordinator can read.
	var out: Dictionary = dict.duplicate(true)
	var existing_pp = out.get("player_progression_summary", null)
	if existing_pp == null or (typeof(existing_pp) == TYPE_DICTIONARY and (existing_pp as Dictionary).is_empty()):
		out["player_progression_summary"] = {
			"class_id": "",
			"xp": {},
			"level": 1,
		}
	return out

func _migrate_v2_to_v3(dict: Dictionary) -> Dictionary:
	# Add slot identity defaults. The slot_id/kind are stamped by the
	# service when it writes a slot, but a legacy save reopened after
	# migration needs the metadata present so the menu can render it.
	var out: Dictionary = dict.duplicate(true)
	if not out.has("slot_id"):
		out["slot_id"] = ""
	if not out.has("slot_kind"):
		out["slot_kind"] = ""
	if not out.has("is_autosave"):
		out["is_autosave"] = false
	if not out.has("is_quicksave"):
		out["is_quicksave"] = false
	if not out.has("parent_world_slot"):
		out["parent_world_slot"] = ""
	return out

func _migrate_world_legacy_to_world_4(dict: Dictionary) -> Dictionary:
	# The OUTER world field set grew additively through v1..v3, but the
	# EMBEDDED home_ship dict is a full RunSnapshot.to_dict() with its own
	# slice_version — a legacy world file survives the outer migration and
	# then fails RunSnapshot.from_dict unless the inner slice is migrated
	# too (Session 3 audit fix; this was a pure duplicate before).
	var out: Dictionary = dict.duplicate(true)
	var home_ship: Variant = out.get("home_ship", null)
	if home_ship is Dictionary and not (home_ship as Dictionary).is_empty():
		var inner: Dictionary = migrate_run(home_ship)
		var inner_dict: Variant = inner.get("dict", null)
		if inner_dict is Dictionary:
			out["home_ship"] = inner_dict
		# A null inner result (newer-than-us home_ship inside a LEGACY world
		# file — contradictory, effectively corrupt) keeps the original dict;
		# RunSnapshot.from_dict then rejects it with the allowlisted warning.
	return out