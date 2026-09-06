extends RefCounted
class_name SaveMigrationService

const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ThreatSaveContractScript := preload("res://scripts/systems/threat_save_contract.gd")

## Save migration service (ADR-0032).
##
## Pure model. Owns a deterministic migration table mapping
## `from_version -> to_version`. Each step receives the parsed
## Dictionary and returns a new Dictionary with the target version's
## keys. No scene-tree access, no engine time. New steps are appended;
## old steps are never removed (auditable history).
##
## Invoked by `SaveLoadService` before RunSnapshot/WorldSnapshot decoding. P10
## keeps the result detached; an inspection copy may be written only after the
## complete candidate passes semantic preparation.

## The ordered list of slot schema versions the service knows how to
## walk. Each entry maps `from -> to`; the chain is followed until
## the slot's `slice_version` matches `target_version`.
const KNOWN_VERSIONS: Array = [
	"gate2-current-run-1",  # legacy: 6 model summaries, no player_progression
	"gate2-current-run-2",  # added player_progression_summary (Phase 3)
	"gate2-current-run-3",  # added slot_id / slot_kind / parent_world_slot metadata (Task 11)
	"gate2-current-run-4",  # added play_time_seconds / current_location / world_seed (ADR-0046)
	"gate2-current-run-5",  # complete crafting transaction + recipe knowledge boundary (ADR-0059/P10)
	"gate2-current-run-6",  # versioned combat authority + structure damage (ADR-0059/R02)
]

const WORLD_KNOWN_VERSIONS: Array = ["world-1", "world-2", "world-3", "world-4", "world-5", "world-6"]
const TARGET_VERSION: String = "gate2-current-run-6"
const WORLD_TARGET_VERSION: String = "world-6"
const WORLD_HOME_RUN_PAIRS: Dictionary = {
	"world-1": ["gate2-current-run-1"],
	"world-2": ["gate2-current-run-1"],
	"world-3": ["gate2-current-run-1"],
	"world-4": [
		"gate2-current-run-1", "gate2-current-run-3", "gate2-current-run-4",
	],
	"world-5": ["gate2-current-run-5"],
	"world-6": ["gate2-current-run-6"],
}
const LEGACY_CRAFT_SCHEMA: String = "legacy-craft-migration-1"
const RECIPE_KNOWLEDGE_SCHEMA: String = "recipe-knowledge-1"
const LEGACY_JOBS_SCHEMA: String = "craft-jobs-1"
const CURRENT_JOBS_SCHEMA: String = "craft-jobs-2"
const CURRENT_FIELD_PENDING_SCHEMA: String = "field-pending-2"

func migrate_run(parsed: Variant) -> Dictionary:
	return _migrate_run_to(parsed, TARGET_VERSION)


func _migrate_run_to(parsed: Variant, target_version: String) -> Dictionary:
	# {dict, from_version, to_version, migrated:bool}
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"dict": null, "from_version": "", "to_version": target_version, "migrated": false}
	var dict: Dictionary = parsed
	var current: String = str(dict.get("slice_version", ""))
	if current == target_version:
		if target_version == TARGET_VERSION:
			return {
				"dict": dict.duplicate(true), "from_version": current,
				"to_version": target_version, "migrated": false, "reason": "",
			}
		var nested: Dictionary = _migrate_current_run_contracts(dict, target_version)
		return {
			"dict": nested.get("dict", null),
			"from_version": current,
			"to_version": target_version,
			"migrated": bool(nested.get("migrated", false)),
			"reason": str(nested.get("reason", "")),
		}
	if current.is_empty():
		# Legacy file without slice_version: treat as the oldest known version.
		current = KNOWN_VERSIONS[0]
	if _index_of(current) < 0:
		# Newer than us — cannot downgrade.
		return {"dict": null, "from_version": current, "to_version": target_version, "migrated": false}
	var working: Dictionary = dict.duplicate(true)
	var migrated: bool = false
	# Walk the migration chain. We advance an index instead of relying
	# on the dict's `slice_version` so an older migration step that
	# forgets to bump the version cannot infinite-loop the loop.
	var chain: Array = KNOWN_VERSIONS.duplicate()
	var start_idx: int = _index_of(current)
	var target_idx: int = _index_of(target_version)
	if target_idx < 0 or start_idx > target_idx:
		return {"dict": null, "from_version": current, "to_version": target_version, "migrated": false}
	while start_idx < target_idx:
		var from_v: String = chain[start_idx]
		var step_result: Dictionary = _run_step_result(from_v, working)
		if not bool(step_result.get("ok", false)):
			return {
				"dict": null,
				"from_version": current,
				"to_version": target_version,
				"migrated": false,
				"reason": str(step_result.get("reason", "malformed_legacy_payload")),
			}
		working = step_result.dict as Dictionary
		# Stamp the next known version so the file is forward-compatible
		# even if the step itself didn't update slice_version.
		var next_v: String = chain[start_idx + 1] if start_idx + 1 < chain.size() else target_version
		working["slice_version"] = next_v
		start_idx += 1
		migrated = true
	working["slice_version"] = target_version
	return {"dict": working, "from_version": current, "to_version": target_version, "migrated": migrated}

func migrate_world(parsed: Variant) -> Dictionary:
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"dict": null, "from_version": "", "to_version": WORLD_TARGET_VERSION, "migrated": false}
	var dict: Dictionary = parsed
	var current: String = str(dict.get("slice_version", ""))
	var legacy_field_history_missing: bool = _world_has_legacy_missing_field_history(dict)
	if current == WORLD_TARGET_VERSION:
		var current_pair: Dictionary = _validate_world_home_pair(dict, current)
		if not bool(current_pair.get("ok", false)):
			return {
				"dict": null, "from_version": current,
				"to_version": WORLD_TARGET_VERSION, "migrated": false,
				"reason": str(current_pair.get("reason", "world_home_version_mismatch")),
			}
		var current_inner: Dictionary = _reconcile_world_terminal_history(
			dict.duplicate(true), false, legacy_field_history_missing)
		return {
			"dict": current_inner.get("dict", null),
			"from_version": current,
			"to_version": WORLD_TARGET_VERSION,
			"migrated": bool(current_inner.get("migrated", false)),
			"reason": str(current_inner.get("reason", "")),
		}
	if current.is_empty():
		current = "world-1"  # legacy world snapshot
	var start_idx: int = WORLD_KNOWN_VERSIONS.find(current)
	var target_idx: int = WORLD_KNOWN_VERSIONS.find(WORLD_TARGET_VERSION)
	if start_idx < 0:
		return {
			"dict": dict,
			"from_version": current,
			"to_version": WORLD_TARGET_VERSION,
			"migrated": false,
			"newer_than_current": _is_newer_world_version(current),
		}
	var working: Dictionary = dict.duplicate(true)
	var migrated: bool = false
	while start_idx < target_idx:
		var from_version: String = str(WORLD_KNOWN_VERSIONS[start_idx])
		var pair_result: Dictionary = _validate_world_home_pair(working, from_version)
		if not bool(pair_result.get("ok", false)):
			return {"dict": null, "from_version": current, "to_version": WORLD_TARGET_VERSION, "migrated": false, "reason": str(pair_result.get("reason", "world_home_version_mismatch"))}
		var step_result: Dictionary = _world_step_result(from_version, working)
		if not bool(step_result.get("ok", false)):
			return {"dict": null, "from_version": current, "to_version": WORLD_TARGET_VERSION, "migrated": false, "reason": str(step_result.get("reason", "malformed_world_payload"))}
		working = step_result.dict as Dictionary
		start_idx += 1
		working["slice_version"] = str(WORLD_KNOWN_VERSIONS[start_idx])
		migrated = true
	var reconciled: Dictionary = _reconcile_world_terminal_history(
		working, migrated, legacy_field_history_missing)
	return {
		"dict": reconciled.get("dict", null),
		"from_version": current,
		"to_version": WORLD_TARGET_VERSION,
		"migrated": bool(reconciled.get("migrated", migrated)),
		"reason": str(reconciled.get("reason", "")),
	}

func _step(from_version: String) -> Callable:
	match from_version:
		"gate2-current-run-1":
			return _migrate_v1_to_v2
		"gate2-current-run-2":
			return _migrate_v2_to_v3
		"gate2-current-run-3":
			return _migrate_v3_to_v4
		"gate2-current-run-4":
			return _migrate_v4_to_v5
		"gate2-current-run-5":
			return _migrate_v5_to_v6
	return Callable()


func _run_step_result(from_version: String, working: Dictionary) -> Dictionary:
	if from_version == "gate2-current-run-5":
		return _migrate_v5_to_v6_result(working)
	var step: Callable = _step(from_version)
	if not step.is_valid():
		return {"ok": false, "reason": "missing_run_migration_step"}
	var stepped: Variant = step.call(working)
	if not stepped is Dictionary or (stepped as Dictionary).is_empty():
		return {"ok": false, "reason": "malformed_legacy_payload"}
	return {"ok": true, "reason": "", "dict": stepped}

func _world_step(from_version: String) -> Callable:
	match from_version:
		"world-1":
			return _migrate_world_v1_to_v2
		"world-2":
			return _migrate_world_v2_to_v3
		"world-3":
			return _migrate_world_v3_to_v4
		"world-4":
			return _migrate_world_v4_to_v5
		"world-5":
			return _migrate_world_v5_to_v6
	return Callable()


func _world_step_result(from_version: String, working: Dictionary) -> Dictionary:
	if from_version == "world-5":
		return _migrate_world_v5_to_v6_result(working)
	var step: Callable = _world_step(from_version)
	if not step.is_valid():
		return {"ok": false, "reason": "missing_world_migration_step"}
	var stepped: Variant = step.call(working)
	if not stepped is Dictionary or (stepped as Dictionary).is_empty():
		return {"ok": false, "reason": "malformed_world_payload"}
	return {"ok": true, "reason": "", "dict": stepped}


func _validate_world_home_pair(world: Dictionary, world_version: String) -> Dictionary:
	var expected_v: Variant = WORLD_HOME_RUN_PAIRS.get(world_version, null)
	if not expected_v is Array:
		return {"ok": false, "reason": "world_home_version_mismatch:%s:expected=<unknown>:actual=<unknown>" % world_version}
	var expected: Array = expected_v as Array
	var home_v: Variant = world.get("home_ship", null)
	var actual: String = "<missing_home>"
	if home_v is Dictionary:
		var home: Dictionary = home_v as Dictionary
		if not home.has("slice_version"):
			actual = "<missing>"
		elif typeof(home.slice_version) != TYPE_STRING:
			actual = "<type:%s>" % type_string(typeof(home.slice_version))
		else:
			actual = home.slice_version as String
			if expected.has(actual):
				return {"ok": true, "reason": ""}
	var expected_strings: PackedStringArray = PackedStringArray()
	for version_v in expected:
		expected_strings.append(str(version_v))
	return {
		"ok": false,
		"reason": "world_home_version_mismatch:%s:expected=%s:actual=%s" % [
			world_version, "|".join(expected_strings), actual,
		],
	}

func _index_of(version: String) -> int:
	return KNOWN_VERSIONS.find(version)

func _is_newer_world_version(version: String) -> bool:
	var current_num: int = _world_version_number(version)
	var target_num: int = _world_version_number(WORLD_TARGET_VERSION)
	return current_num > target_num and target_num >= 0

func _world_version_number(version: String) -> int:
	var prefix: String = "world-"
	if not version.begins_with(prefix):
		return -1
	var suffix: String = version.trim_prefix(prefix)
	if suffix.is_empty() or not suffix.is_valid_int():
		return -1
	return int(suffix)

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

func _migrate_v3_to_v4(dict: Dictionary) -> Dictionary:
	# ADR-0046: real slot metadata. Older saves have no accumulated play
	# time, no location stamp, and no world seed; default them so the
	# slot browser renders honest zeros instead of the old placeholders
	# (player X as location, Unix epoch as play time).
	var out: Dictionary = dict.duplicate(true)
	if not out.has("play_time_seconds"):
		out["play_time_seconds"] = 0.0
	if not out.has("current_location"):
		out["current_location"] = ""
	if not out.has("world_seed"):
		out["world_seed"] = 0
	return out


func _migrate_v4_to_v5(dict: Dictionary) -> Dictionary:
	var out: Dictionary = dict.duplicate(true)
	var crafting_present: bool = out.has("crafting_summary")
	var crafting_value: Variant = out.get("crafting_summary", null)
	if crafting_present and not crafting_value is Dictionary:
		return {}
	var migrated_crafting: Dictionary = _migrate_crafting_boundary(
		crafting_value as Dictionary if crafting_present else {}, "gate2-current-run-4")
	if migrated_crafting.is_empty():
		return {}
	out["crafting_summary"] = migrated_crafting

	# Recipe discovery was not serialized before v5. Structural migration records
	# that evidence limit; detached preparation seeds only authored starter recipes
	# and binds the actual current-run player owner.
	if out.has("recipe_knowledge_summary"):
		if not out.recipe_knowledge_summary is Dictionary:
			return {}
	else:
		out["recipe_knowledge_summary"] = _empty_legacy_recipe_knowledge()
	if out.has("component_placement_summary"):
		if not out.component_placement_summary is Dictionary:
			return {}
		var migrated_components: Dictionary = _migrate_legacy_component_summary(
			out.component_placement_summary as Dictionary, "ship_start")
		if migrated_components.is_empty():
			return {}
		out["component_placement_summary"] = migrated_components
	else:
		out["component_placement_summary"] = {
			"schema": "component_placement_v2",
			"condition_authority_version": 1,
			"condition_lot_sequence": 0,
			"seed": 0,
			"count": 0,
			"placed": [],
			"rejected_saved_components": [],
		}
	return out


func _migrate_current_run_contracts(dict: Dictionary, source_version: String) -> Dictionary:
	var out: Dictionary = dict.duplicate(true)
	var crafting_v: Variant = out.get("crafting_summary", null)
	if not crafting_v is Dictionary:
		return {"dict": null, "migrated": false, "reason": "malformed_current_crafting"}
	var migrated_crafting: Dictionary = _migrate_crafting_boundary(
		crafting_v as Dictionary, source_version)
	if migrated_crafting.is_empty():
		return {"dict": null, "migrated": false, "reason": "unsupported_crafting_contract"}
	var changed: bool = migrated_crafting != crafting_v
	out["crafting_summary"] = migrated_crafting
	return {"dict": out, "migrated": changed, "reason": ""}


func _migrate_v5_to_v6(dict: Dictionary) -> Dictionary:
	var result: Dictionary = _migrate_v5_to_v6_result(dict)
	return result.get("dict", {}) as Dictionary


func _migrate_v5_to_v6_result(dict: Dictionary) -> Dictionary:
	var normalized: Dictionary = _migrate_current_run_contracts(
		dict, "gate2-current-run-5")
	if not normalized.get("dict", null) is Dictionary:
		return {"ok": false, "reason": str(normalized.get("reason", "malformed_current_crafting"))}
	var out: Dictionary = (normalized.dict as Dictionary).duplicate(true)
	var inventory_value: Variant = out.get("inventory_summary", null)
	if not inventory_value is Dictionary or (inventory_value as Dictionary).is_empty():
		return {"ok": false, "reason": "combat_migration_inventory_missing"}
	var inventory: Dictionary = (inventory_value as Dictionary).duplicate(true)
	if inventory.has("combat_hotbar_text") \
			and typeof(inventory.combat_hotbar_text) != TYPE_STRING:
		return {"ok": false, "reason": "combat_migration_invalid_hotbar_text"}
	if not inventory.has("combat_hotbar_text"):
		inventory["combat_hotbar_text"] = ""
	if inventory.has("threat_summary"):
		var combat_value: Variant = inventory.threat_summary
		if not combat_value is Dictionary:
			return {"ok": false, "reason": "legacy_combat_not_dictionary"}
		if (combat_value as Dictionary).is_empty():
			inventory.erase("threat_summary")
		else:
			var combat_result: Dictionary = ThreatSaveContractScript.migrate_legacy(combat_value)
			if not bool(combat_result.get("ok", false)):
				return {"ok": false, "reason": str(combat_result.get("reason", "legacy_combat_invalid"))}
			inventory["threat_summary"] = combat_result.summary
	out["inventory_summary"] = inventory
	return {"ok": true, "reason": "", "dict": out}


func _migrate_crafting_boundary(summary: Dictionary, source_version: String) -> Dictionary:
	if summary.is_empty():
		return _empty_current_crafting_summary()
	if summary.has("craft_jobs_v1"):
		var current: Dictionary = summary.duplicate(true)
		var jobs_result: Dictionary = _migrate_craft_jobs_envelope(
			current.get("craft_jobs_v1", null))
		if not bool(jobs_result.get("ok", false)):
			return {}
		current["craft_jobs_v1"] = jobs_result.summary
		if not current.has("physical_station_positions_v1"):
			current["physical_station_positions_v1"] = _empty_station_positions()
		if not current.has("field_crafting"):
			current["field_crafting"] = _empty_field_crafting_summary()
		elif not current.field_crafting is Dictionary:
			return {}
		else:
			var field: Dictionary = current.field_crafting
			var source_field_jobs_v: Variant = field.get("craft_jobs_v1", null)
			var source_was_legacy_field_jobs: bool = source_field_jobs_v is Dictionary \
					and str((source_field_jobs_v as Dictionary).get("schema", "")) \
						== LEGACY_JOBS_SCHEMA
			var field_jobs_result: Dictionary = _migrate_craft_jobs_envelope(
				source_field_jobs_v)
			if not bool(field_jobs_result.get("ok", false)):
				return {}
			field["craft_jobs_v1"] = field_jobs_result.summary
			var pending_result: Dictionary = _migrate_field_pending_envelope(
				field.get("field_pending_v1", null),
				source_was_legacy_field_jobs)
			if not bool(pending_result.get("ok", false)):
				return {}
			field["field_pending_v1"] = pending_result.summary
			current["field_crafting"] = field
		return current

	var fixed_bridge: Dictionary = _legacy_crafting_bridge(summary, source_version)
	if fixed_bridge.is_empty():
		return {}
	var result: Dictionary = _empty_current_crafting_summary()
	result["recipe_count"] = _legacy_nonnegative_integer(summary.get("recipe_count", 0))
	result["legacy_craft_migration_v1"] = fixed_bridge

	var field_value: Variant = summary.get("field_crafting", null)
	if field_value != null:
		if not field_value is Dictionary:
			return {}
		var field_bridge: Dictionary = _legacy_crafting_bridge(field_value as Dictionary, source_version)
		if field_bridge.is_empty():
			return {}
		var field_summary: Dictionary = _empty_field_crafting_summary()
		field_summary["recipe_count"] = _legacy_nonnegative_integer((field_value as Dictionary).get("recipe_count", 0))
		field_summary["legacy_craft_migration_v1"] = field_bridge
		result["field_crafting"] = field_summary
	return result


func _legacy_crafting_bridge(summary: Dictionary, source_version: String) -> Dictionary:
	for key in ["active_craft", "station_summaries"]:
		if summary.has(key) and not summary[key] is Dictionary:
			return {}
	if summary.has("recipe_count") and _legacy_nonnegative_integer(summary.recipe_count) < 0:
		return {}
	var active: Dictionary = (summary.get("active_craft", {}) as Dictionary).duplicate(true)
	var stations: Dictionary = summary.get("station_summaries", {}) as Dictionary
	var paid_active: Variant = null
	if not active.is_empty():
		paid_active = _legacy_paid_active(active, stations)
		if not paid_active is Dictionary or (paid_active as Dictionary).is_empty():
			return {}
	var queue: Array = []
	var station_keys: Array = stations.keys()
	station_keys.sort()
	var ordinal: int = 0
	for station_key in station_keys:
		if typeof(station_key) != TYPE_STRING or not stations[station_key] is Dictionary:
			return {}
		var station: Dictionary = stations[station_key]
		var station_kind: String = str(station.get("station_kind", station_key))
		if station_kind.is_empty() or station_kind != str(station_key):
			return {}
		var queued_value: Variant = station.get("queue", [])
		if not queued_value is Array:
			return {}
		for recipe_value in queued_value as Array:
			if typeof(recipe_value) != TYPE_STRING or str(recipe_value).is_empty():
				return {}
			queue.append({"station_kind": station_kind, "recipe_id": str(recipe_value), "ordinal": ordinal})
			ordinal += 1
	return {
		"schema": LEGACY_CRAFT_SCHEMA,
		"source_version": source_version,
		"paid_active": paid_active,
		"unreserved_queue": queue,
	}


func _legacy_paid_active(active: Dictionary, stations: Dictionary) -> Variant:
	for key in ["recipe_id", "station_kind", "quality_tier"]:
		if typeof(active.get(key, null)) != TYPE_STRING or str(active.get(key, "")).is_empty():
			return null
	for key in ["quality_score", "quality_multiplier"]:
		if not _finite_number(active.get(key, null)):
			return null
	var quality_score: float = float(active.quality_score)
	var quality_multiplier: float = float(active.quality_multiplier)
	if quality_score < 0.0 or quality_score > 1.0 or quality_multiplier <= 0.0:
		return null
	var station_kind: String = str(active.station_kind)
	var station_value: Variant = stations.get(station_kind, null)
	if not station_value is Dictionary:
		return null
	var station: Dictionary = station_value
	if str(station.get("station_kind", "")) != station_kind \
			or typeof(station.get("active_recipe_id", null)) != TYPE_STRING \
			or str(station.active_recipe_id) != str(active.recipe_id) \
			or not _finite_number(station.get("progress_seconds", null)) \
			or not _finite_number(station.get("required_seconds", null)) \
			or _legacy_nonnegative_integer(station.get("status", null)) < 0:
		return null
	var progress: float = float(station.progress_seconds)
	var required: float = float(station.required_seconds)
	var status: int = int(station.status)
	if required <= 0.0 or progress < 0.0 or progress > required or not [1, 2, 3].has(status):
		return null
	return {
		"recipe_id": str(active.recipe_id),
		"station_kind": station_kind,
		"quality_score": quality_score,
		"quality_tier": str(active.quality_tier),
		"quality_multiplier": quality_multiplier,
		"progress_seconds": progress,
		"required_seconds": required,
		"legacy_status": status,
	}


func _empty_current_crafting_summary() -> Dictionary:
	return {
		"recipe_count": 0,
		"active_craft": {},
		"station_summaries": {},
		"physical_station_summaries": {},
		"physical_station_positions_v1": _empty_station_positions(),
		"craft_jobs_v1": {"schema": CURRENT_JOBS_SCHEMA, "jobs": [], "owners": []},
		"field_crafting": _empty_field_crafting_summary(),
	}


func _empty_station_positions() -> Dictionary:
	return {"schema": "physical-station-positions-1", "owners": []}


func _migrate_craft_jobs_envelope(jobs_v: Variant) -> Dictionary:
	if not jobs_v is Dictionary:
		return {"ok": false}
	var jobs: Dictionary = (jobs_v as Dictionary).duplicate(true)
	var schema: String = str(jobs.get("schema", ""))
	if schema == CURRENT_JOBS_SCHEMA:
		return {"ok": true, "summary": jobs, "migrated": false}
	if schema != LEGACY_JOBS_SCHEMA or not jobs.get("jobs", null) is Array \
			or not jobs.get("owners", null) is Array:
		return {"ok": false}
	var rows: Array = (jobs.jobs as Array).duplicate(true)
	for index in range(rows.size()):
		if not rows[index] is Dictionary:
			return {"ok": false}
		var row: Dictionary = (rows[index] as Dictionary).duplicate(true)
		for current_only_key in [
				"refunded_lots_v1", "legacy_unreserved_cancelled_v1",
				"legacy_unrecorded_cancelled_v1"]:
			if row.has(current_only_key):
				return {"ok": false}
		# craft-jobs-1 predated terminal refund provenance. Preserve every lot
		# already present and mark only evidence-free cancelled rows as inert
		# tombstones. Whole-world reconciliation may promote a tombstone from an
		# exact surviving pending receipt; run-only migration never does.
		row["refunded_lots_v1"] = []
		row["legacy_unreserved_cancelled_v1"] = false
		var consumed_v: Variant = row.get("consumed_lots", null)
		var escrow_v: Variant = row.get("ingredient_escrow", null)
		row["legacy_unrecorded_cancelled_v1"] = (
			str(row.get("state", row.get("phase", ""))) == "cancelled" \
			and consumed_v is Array and (consumed_v as Array).is_empty() \
			and escrow_v is Array and (escrow_v as Array).is_empty())
		rows[index] = row
	jobs["jobs"] = rows
	jobs["schema"] = CURRENT_JOBS_SCHEMA
	return {"ok": true, "summary": jobs, "migrated": true}


func _migrate_field_pending_envelope(
		pending_v: Variant, source_was_legacy_jobs: bool) -> Dictionary:
	if not pending_v is Dictionary:
		return {"ok": false}
	var pending: Dictionary = (pending_v as Dictionary).duplicate(true)
	var schema: String = str(pending.get("schema", ""))
	if schema == CURRENT_FIELD_PENDING_SCHEMA:
		return {"ok": true, "summary": pending, "migrated": false}
	# The historical envelope was unversioned. It is recognized only beside the
	# historical job schema; deleting schema from a current envelope must not
	# route through this adapter.
	if not source_was_legacy_jobs or not schema.is_empty() \
			or pending.has("receipt_history_v1"):
		return {"ok": false}
	pending["schema"] = CURRENT_FIELD_PENDING_SCHEMA
	pending["receipt_history_v1"] = []
	return {"ok": true, "summary": pending, "migrated": true}


func _empty_field_crafting_summary() -> Dictionary:
	return {
		"recipe_count": 0,
		"active_craft": {},
		"station_summaries": {},
		"physical_station_summaries": {},
		"craft_jobs_v1": {"schema": CURRENT_JOBS_SCHEMA, "jobs": [], "owners": []},
		"field_pending_v1": {
			"schema": CURRENT_FIELD_PENDING_SCHEMA,
			"ship_id": "",
			"receipt_sequence": 0,
			"active_receipt_id": "",
			"pinned_destination_ship_id": "",
			"pinned_local_position": [],
			"receipt_history_v1": [],
		},
	}


func _empty_legacy_recipe_knowledge() -> Dictionary:
	return {
		"schema": RECIPE_KNOWLEDGE_SCHEMA,
		"owner_id": "",
		"known_recipe_ids": [],
		"event_receipt_ids": [],
		"event_sequence": 0,
		"dismantle_counts": {},
		"migration_origin": "legacy_unrecorded",
	}


func _legacy_nonnegative_integer(value: Variant) -> int:
	if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)) \
			or float(value) < 0.0 or float(value) != floor(float(value)):
		return -1
	return int(value)


func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _world_has_legacy_missing_field_history(world: Dictionary) -> bool:
	var home_v: Variant = world.get("home_ship", null)
	if not home_v is Dictionary:
		return false
	var crafting_v: Variant = (home_v as Dictionary).get("crafting_summary", null)
	if not crafting_v is Dictionary:
		return false
	var field_v: Variant = (crafting_v as Dictionary).get("field_crafting", null)
	if not field_v is Dictionary:
		return false
	var jobs_v: Variant = (field_v as Dictionary).get("craft_jobs_v1", null)
	var pending_v: Variant = (field_v as Dictionary).get("field_pending_v1", null)
	return jobs_v is Dictionary and pending_v is Dictionary \
		and str((jobs_v as Dictionary).get("schema", "")) == LEGACY_JOBS_SCHEMA \
		and not (pending_v as Dictionary).has("receipt_history_v1")


func _reconcile_world_terminal_history(
		world: Dictionary, already_migrated: bool,
		legacy_field_history_missing: bool) -> Dictionary:
	var out: Dictionary = world.duplicate(true)
	var pending_records: Array = _world_pending_records(out)
	if legacy_field_history_missing:
		for record_v in pending_records:
			if record_v is Dictionary \
					and str((record_v as Dictionary).get("producer_kind", "")) == "field_craft":
				return {
					"dict": null,
					"migrated": already_migrated,
					"reason": "legacy_field_receipt_history_unavailable",
				}
	var home_v: Variant = out.get("home_ship", null)
	if not home_v is Dictionary:
		return {"dict": out, "migrated": already_migrated, "reason": ""}
	var home: Dictionary = home_v as Dictionary
	var crafting_v: Variant = home.get("crafting_summary", null)
	if not crafting_v is Dictionary:
		return {"dict": out, "migrated": already_migrated, "reason": ""}
	var crafting: Dictionary = crafting_v as Dictionary
	var jobs_v: Variant = crafting.get("craft_jobs_v1", null)
	if not jobs_v is Dictionary or not (jobs_v as Dictionary).get("jobs", null) is Array:
		return {"dict": out, "migrated": already_migrated, "reason": ""}
	var rows: Array = (jobs_v as Dictionary).jobs as Array
	for index in range(rows.size()):
		if not rows[index] is Dictionary:
			continue
		var job: Dictionary = (rows[index] as Dictionary).duplicate(true)
		if not bool(job.get("legacy_unrecorded_cancelled_v1", false)):
			continue
		var receipt_id: String = "%s/refund" % str(job.get("job_id", ""))
		var matches: Array = []
		for record_v in pending_records:
			if record_v is Dictionary \
					and str((record_v as Dictionary).get("receipt_id", "")) == receipt_id:
				matches.append(record_v)
		if not matches.is_empty():
			# craft-jobs-1 retained no independently verifiable refunded lot
			# identity, quality, or condition. The pending record cannot validate
			# itself, so any surviving refund remains unrecoverable rather than
			# being promoted into newly trusted value.
			return {
				"dict": null,
				"migrated": already_migrated,
				"reason": "legacy_refund_history_unavailable",
			}
	return {"dict": out, "migrated": already_migrated, "reason": ""}


func _world_pending_records(world: Dictionary) -> Array:
	var records: Array = []
	var home_pending_v: Variant = world.get("home_pending_outputs_v1", null)
	if home_pending_v is Dictionary and (home_pending_v as Dictionary).get("records", null) is Array:
		for record_v in (home_pending_v as Dictionary).records as Array:
			records.append(record_v)
	var visited_v: Variant = world.get("visited_ships", null)
	if visited_v is Dictionary:
		for ship_v in (visited_v as Dictionary).values():
			if not ship_v is Dictionary:
				continue
			var pending_v: Variant = (ship_v as Dictionary).get("pending_outputs_v1", null)
			if pending_v is Dictionary and (pending_v as Dictionary).get("records", null) is Array:
				for record_v in (pending_v as Dictionary).records as Array:
					records.append(record_v)
	return records


func _migrate_world_v1_to_v2(dict: Dictionary) -> Dictionary:
	# The outer additions through world v3 did not advance the embedded run;
	# every shipped world v1-v3 paired with run v1. Preserve that source pairing
	# until the explicit world-v4 boundary owns the inner migration.
	return dict.duplicate(true)


func _migrate_world_v2_to_v3(dict: Dictionary) -> Dictionary:
	return dict.duplicate(true)


func _migrate_world_v3_to_v4(dict: Dictionary) -> Dictionary:
	return dict.duplicate(true)


func _migrate_world_v4_to_v5(dict: Dictionary) -> Dictionary:
	var inner: Dictionary = _migrate_world_home_ship(dict, "gate2-current-run-5")
	if inner.get("dict", null) == null:
		return {}
	var out: Dictionary = (inner.dict as Dictionary).duplicate(true)
	if not out.has("home_pending_outputs_v1"):
		out["home_pending_outputs_v1"] = _empty_pending_store("ship_start")
	elif not out.home_pending_outputs_v1 is Dictionary:
		return {}
	var visited_v: Variant = out.get("visited_ships", {})
	if not visited_v is Dictionary:
		return {}
	var visited: Dictionary = (visited_v as Dictionary).duplicate(true)
	for marker_variant in visited:
		var ship_v: Variant = visited[marker_variant]
		if not ship_v is Dictionary:
			return {}
		var ship_summary: Dictionary = (ship_v as Dictionary).duplicate(true)
		var ship_id: String = str(ship_summary.get("ship_id", ""))
		if ship_id.is_empty():
			return {}
		if ship_summary.has("component_placement"):
			if not ship_summary.component_placement is Dictionary:
				return {}
			var migrated_components: Dictionary = _migrate_legacy_component_summary(
				ship_summary.component_placement as Dictionary, ship_id)
			if migrated_components.is_empty():
				return {}
			ship_summary["component_placement"] = migrated_components
		if not ship_summary.has("pending_outputs_v1"):
			ship_summary["pending_outputs_v1"] = _empty_pending_store(ship_id)
		elif not ship_summary.pending_outputs_v1 is Dictionary:
			return {}
		visited[marker_variant] = ship_summary
	out["visited_ships"] = visited
	return out


func _migrate_world_v5_to_v6(dict: Dictionary) -> Dictionary:
	var result: Dictionary = _migrate_world_v5_to_v6_result(dict)
	return result.get("dict", {}) as Dictionary


func _migrate_world_v5_to_v6_result(dict: Dictionary) -> Dictionary:
	var inner: Dictionary = _migrate_world_home_ship(dict, TARGET_VERSION)
	if inner.get("dict", null) == null:
		return {"ok": false, "reason": str(inner.get("reason", "malformed_home_run"))}
	var out: Dictionary = (inner.dict as Dictionary).duplicate(true)
	var visited_value: Variant = out.get("visited_ships", null)
	if not visited_value is Dictionary:
		return {"ok": false, "reason": "combat_migration_invalid_visited_ships"}
	var visited: Dictionary = (visited_value as Dictionary).duplicate(true)
	for marker_value in visited:
		if typeof(marker_value) != TYPE_STRING or str(marker_value).is_empty() \
				or not visited[marker_value] is Dictionary:
			return {"ok": false, "reason": "combat_migration_invalid_visited_ship"}
		var ship: Dictionary = (visited[marker_value] as Dictionary).duplicate(true)
		if ship.has("combat"):
			var combat_value: Variant = ship.combat
			if not combat_value is Dictionary:
				return {"ok": false, "reason": "legacy_combat_not_dictionary"}
			if (combat_value as Dictionary).is_empty():
				ship.erase("combat")
			else:
				var combat_result: Dictionary = ThreatSaveContractScript.migrate_legacy(combat_value)
				if not bool(combat_result.get("ok", false)):
					return {"ok": false, "reason": str(combat_result.get("reason", "legacy_combat_invalid"))}
				ship["combat"] = combat_result.summary
		visited[marker_value] = ship
	out["visited_ships"] = visited
	return {"ok": true, "reason": "", "dict": out}


static func _empty_pending_store(ship_id: String) -> Dictionary:
	return {"schema": "pending-outputs-1", "ship_id": ship_id, "records": []}


func _migrate_legacy_component_summary(summary: Dictionary, ship_id: String) -> Dictionary:
	if ship_id.is_empty() or str(summary.get("schema", "")) != "component_placement_v2" \
			or not summary.get("placed", null) is Array:
		return {}
	var out: Dictionary = summary.duplicate(true)
	var placed: Array = (out.placed as Array).duplicate(true)
	var order: Array[int] = []
	for index in range(placed.size()):
		if not placed[index] is Dictionary:
			return {}
		order.append(index)
	order.sort_custom(func(left: int, right: int) -> bool:
		return str((placed[left] as Dictionary).get("component_instance_id", "")) \
			< str((placed[right] as Dictionary).get("component_instance_id", "")))
	var catalog = ComponentCatalogScript.new()
	if not catalog.load_default():
		return {}
	var next_sequence: int = 0
	var seen_slots: Dictionary = {}
	for index in order:
		var entry: Dictionary = (placed[index] as Dictionary).duplicate(true)
		var slot_id: String = str(entry.get("component_instance_id", ""))
		var component_id: String = str(entry.get("component_id", ""))
		var definition: Dictionary = catalog.get_component(component_id)
		var item_form: String = str(entry.get("item_form", definition.get("item_form", component_id)))
		if slot_id.is_empty() or seen_slots.has(slot_id) or definition.is_empty() or item_form.is_empty():
			return {}
		seen_slots[slot_id] = true
		# Pre-v5 placement rows treated absence as mounted. Only this recognized
		# outer-version adapter may synthesize that historical default; current
		# component_placement_v2 rows require an exact bool.
		if entry.has("mounted") and typeof(entry.mounted) != TYPE_BOOL:
			return {}
		if not entry.has("mounted"):
			entry["mounted"] = true
		if entry.has("source_lot"):
			# Trusted legacy provenance permits absence only. Present payloads are
			# preserved byte-for-byte for strict current validation to accept or reject.
			placed[index] = entry
			continue
		next_sequence += 1
		var condition: float = clampf(float(
			entry.get("condition", definition.get("condition_default", 1.0))), 0.0, 1.0)
		var lot_id: String = "ship:%s:components/lot-%06d" % [ship_id, next_sequence]
		entry["item_form"] = item_form
		entry["condition"] = condition
		entry["source_lot_id"] = lot_id
		entry["source_lot"] = {
			"lot_id": lot_id,
			"item_id": item_form,
			"quantity": 1,
			"quality_score": 0.5,
			"quality_tier": "standard",
			"condition": condition,
			"origin": {
				"kind": "legacy_unrecorded_component",
				"ship_id": ship_id,
				"slot_id": slot_id,
			},
		}
		placed[index] = entry
	out["placed"] = placed
	out["count"] = placed.size()
	out["condition_authority_version"] = 1
	out["condition_lot_sequence"] = next_sequence
	if not out.has("rejected_saved_components"):
		out["rejected_saved_components"] = []
	return out

func _migrate_world_home_ship(
		dict: Dictionary, target_run_version: String = TARGET_VERSION) -> Dictionary:
	var out: Dictionary = dict.duplicate(true)
	var migrated: bool = false
	var home_ship: Variant = out.get("home_ship", null)
	if home_ship is Dictionary and not (home_ship as Dictionary).is_empty():
		var inner: Dictionary = _migrate_run_to(home_ship, target_run_version)
		var inner_dict: Variant = inner.get("dict", null)
		if inner_dict is Dictionary:
			out["home_ship"] = inner_dict
			migrated = bool(inner.get("migrated", false)) or str((home_ship as Dictionary).get("slice_version", "")) != str((inner_dict as Dictionary).get("slice_version", ""))
		else:
			return {
				"dict": null,
				"migrated": false,
				"reason": str(inner.get("reason", "malformed_home_run")),
			}
	return {"dict": out, "migrated": migrated}
