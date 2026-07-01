extends RefCounted
class_name TrainingEventBus

## REQ-PM-002 / ADR-0033 deterministic training-event bus.
##
## The bus is a pure ordered log of `TrainingEvent` records. Each event
## has `{event_id, target_id, timestamp, source}` and is resolved through
## `data/player/training_actions.json` to a `(skill_id, base_xp,
## category)` triple, then forwarded to `PlayerProgressionState.grant_xp`.
##
## Determinism:
##   - No RNG anywhere in the bus.
##   - Events are processed in insertion order.
##   - Replaying the same event sequence yields the same XP awards.
##
## Pure: never reaches into the scene tree or any audio service. The
## playable ship's coordinator subscribes to `on_event_resolved` to play
## UI/audio feedback if desired.

const DEFAULT_TRAINING_ACTIONS_PATH := "res://data/player/training_actions.json"

## Optional signal-like callback. Set by the playable ship's coordinator.
## Signature: func(event: Dictionary) -> void
var on_event_resolved: Callable = Callable()
## Optional per-event suppression. When set, returns false from emit().
## Signature: func(event_id: String, target_id: String) -> bool.
## Convention: returning true SUPPRESSES/DROPS the event (opposite of
## `skill_gate` below — do not confuse the two).
var event_filter: Callable = Callable()

## Optional Domain 6 skill gate. When set, resolves the event's target_skill
## and consults this callable before XP is granted. Signature:
## func(skill_id: String) -> bool.
## Convention: returning true means the skill is ALLOWED to train (the event
## proceeds); returning false DROPS the event. This is the opposite
## convention from `event_filter` above — do not confuse the two.
var skill_gate: Callable = Callable()

var _actions_by_id: Dictionary = {}     # event_id -> {target_skill, base_xp, category}
var _log: Array = []                    # ordered list of resolved events
var _dropped: int = 0
var _xp_total: int = 0

## Loads the training-actions catalog. Returns false on parse error.
func configure(actions_catalog: Dictionary = {}) -> bool:
	_actions_by_id.clear()
	var variant: Variant
	if actions_catalog == null or actions_catalog.is_empty():
		if not FileAccess.file_exists(DEFAULT_TRAINING_ACTIONS_PATH):
			return false
		var text: String = FileAccess.get_file_as_string(DEFAULT_TRAINING_ACTIONS_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			return false
		variant = (parsed as Dictionary).get("training_actions", [])
	else:
		variant = actions_catalog.get("training_actions", [])
	if typeof(variant) != TYPE_ARRAY:
		return false
	for entry in (variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var eid: String = str((entry as Dictionary).get("event_id", ""))
		if eid.is_empty():
			continue
		_actions_by_id[eid] = {
			"target_skill": str((entry as Dictionary).get("target_skill", "")),
			"base_xp": int((entry as Dictionary).get("base_xp", 0)),
			"category": str((entry as Dictionary).get("category", "")),
		}
	return true

func is_known(event_id: String) -> bool:
	return _actions_by_id.has(event_id)

func get_event_count() -> int:
	return _log.size()

func get_dropped_count() -> int:
	return _dropped

func get_total_xp_delivered() -> int:
	return _xp_total

## Emits a training event. Returns the resolved record Dictionary on
## success; returns null on unknown id, `event_filter`-suppressed event,
## or empty target skill. The `target_id` argument is informational
## (e.g. "power_distribution"); it does not affect XP resolution.
##
## Domain 6 skill gate: when `skill_gate` is set and rejects the event's
## skill, the event is still APPENDED to the log (with `"gated": true`)
## so run-end unlock-trigger persistence (which iterates `get_log()`) can
## still see it fire — only the XP grant is suppressed. `_dropped` /
## `get_dropped_count()` is reserved for unknown-id / `event_filter` /
## empty-skill cases; a gated event does NOT increment it.
##
## On a non-gated success the bus calls `progression.grant_xp(skill_id,
## base_xp, is_cross_training)`. The cross-training flag is computed by
## comparing the action's category to the player's primary category (the
## first multiplier > 1.0 wins; ties broken alphabetically).
func emit(event_id: String, target_id: String, progression) -> Variant:
	if not _actions_by_id.has(event_id):
		_dropped += 1
		return null
	if event_filter.is_valid() and bool(event_filter.call(event_id, target_id)):
		_dropped += 1
		return null
	var action: Dictionary = _actions_by_id[event_id]
	var skill_id: String = str(action.get("target_skill", ""))
	var base_xp: int = int(action.get("base_xp", 0))
	if skill_id.is_empty() or base_xp <= 0:
		_dropped += 1
		return null
	var is_cross: bool = _is_cross_training(action.get("category", ""), progression)
	# Domain 6 skill gate (PR #55 Codex P1): when a tree-gated skill is NOT yet
	# unlocked, SUPPRESS the XP grant but STILL log the event, so the run-end
	# unlock-trigger stream (get_log) sees the action fire (e.g. field-crafting
	# must count toward the workshop/class unlock even before Fabrication trains).
	var gated: bool = skill_gate.is_valid() and not bool(skill_gate.call(skill_id))
	if not gated:
		if progression != null and progression.has_method("grant_xp"):
			progression.grant_xp(skill_id, base_xp, is_cross)
		_xp_total += base_xp
	var record: Dictionary = {
		"event_id": event_id,
		"target_id": target_id,
		"skill_id": skill_id,
		"base_xp": base_xp,
		"category": str(action.get("category", "")),
		"is_cross_training": is_cross,
		"sequence": _log.size(),
		"gated": gated,
	}
	_log.append(record)
	if on_event_resolved.is_valid():
		on_event_resolved.call(record)
	return record

## Replays the log into `progression` for deterministic restoration. Used
## by save/load to recover state after a snapshot round-trip.
func replay_into(progression) -> int:
	if progression == null:
		return 0
	var delivered: int = 0
	for record in _log:
		var skill_id: String = str(record.get("skill_id", ""))
		var base_xp: int = int(record.get("base_xp", 0))
		var is_cross: bool = bool(record.get("is_cross_training", false))
		if skill_id.is_empty() or base_xp <= 0:
			continue
		if bool(record.get("gated", false)):
			continue
		if progression.has_method("grant_xp"):
			progression.grant_xp(skill_id, base_xp, is_cross)
			delivered += base_xp
	return delivered

## Returns a copy of the log.
func get_log() -> Array:
	return _log.duplicate(true)

## Empties the log and counters. Used by start_new_run() on the playable
## so per-run replay state doesn't bleed into the next run.
func reset() -> void:
	_log.clear()
	_dropped = 0
	_xp_total = 0

## Computes the cross-training flag for a given category and player state.
## Returns true when the player's class multiplier for the event's
## category is NOT the highest among all of the class's multipliers.
## Engineer's technical=1.5 vs medical=0.7 means a medical event IS
## cross-training; engineer's technical event is primary.
func _is_cross_training(category: String, progression) -> bool:
	if progression == null or not progression.has_method("get_class_id"):
		return false
	if category.is_empty():
		return false
	# We use the static catalog lookup so the bus does not depend on the
	# PlayerProgressionState's internal _xp_multipliers dict (which is
	# private). The class definition script is the source of truth.
	var class_id: String = str(progression.get_class_id())
	if class_id.is_empty():
		return false
	var classes: Dictionary = load("res://scripts/systems/class_definition.gd").load_all()
	if not classes.has(class_id):
		return false
	var class_def = classes[class_id]
	var mults: Dictionary = class_def.xp_multipliers as Dictionary
	if mults.is_empty():
		return false
	# Find the highest multiplier category — that's the primary.
	var best_category: String = ""
	var best_mult: float = -1.0
	for cat in mults:
		var m: float = float(mults[cat])
		if m > best_mult or (m == best_mult and (best_category == "" or String(cat) < best_category)):
			best_mult = m
			best_category = String(cat)
	return best_category != category

## Returns a deterministic summary for save/load.
func to_dict() -> Dictionary:
	return {
		"log": _log.duplicate(true),
		"dropped": _dropped,
		"xp_total": _xp_total,
		"event_count": _log.size(),
	}

## Restores the log. Used by save/load to recover replayable state.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or typeof(summary) != TYPE_DICTIONARY:
		return false
	_log.clear()
	var log_v: Variant = summary.get("log", [])
	if typeof(log_v) == TYPE_ARRAY:
		for entry in (log_v as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			_log.append((entry as Dictionary).duplicate(true))
	_dropped = int(summary.get("dropped", 0))
	_xp_total = int(summary.get("xp_total", 0))
	return true