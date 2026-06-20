extends RefCounted
class_name ObjectiveProgressState

## Runtime model for multi-step objective progress on the main playable slice.
## This model never reaches into the scene tree. PlayableGeneratedShip owns the
## interactables and decides when to advance sequence state based on this model.
##
## A sequence is registered once with an objective_type and required step count.
## Steps are completed by step_id; duplicate completions are idempotent.
## The sequence is considered complete only when completed_steps == required_steps.

var _objectives: Dictionary = {}

func register_objective(sequence: int, objective_type: String, required_steps: int) -> void:
	if sequence <= 0:
		return
	if required_steps < 1:
		required_steps = 1
	_objectives[sequence] = {
		"objective_type": objective_type,
		"required_steps": required_steps,
		"completed_steps": 0,
		"completed_step_ids": [],
		"complete": false,
		# REQ-014 junction_calibrator: per-sequence flag so save/load
		# restores the reduced step count and a second calibrator pickup
		# (already impossible — pickup is one-shot) cannot reduce the
		# same sequence twice in a single run.
		"calibrator_applied": false,
	}

## REQ-014: reduces the registered required_steps of a sequence by one
## (clamped at 1) and marks `calibrator_applied` so the reduction is
## idempotent across repeated application attempts and is preserved by
## REQ-012 save/load.
##
## The model does NOT gate on the registered `objective_type` here:
## `objective_type` carries the ship-system name (e.g. "restore_systems")
## set by the existing `_build_interactables` flow, which the existing
## objective_progress_state_smoke and objective_variation smoke assert
## on directly. The coordinator is the sole gatekeeper for the
## gameplay_slice.json `kind == "repair_junction"` semantics; it only
## calls this method when the active interactable comes from a junction
## spec, so the model's safety net is the three "reduction would change
## state" conditions below.
##
## Returns true and mutates the sequence record only when ALL of:
##   - the sequence is registered
##   - the sequence is not already complete
##   - required_steps > 1 (so a one-step junction cannot be shortened
##     and the calibrator is not consumed in that case — the coordinator
##     checks the boolean return to decide consumption)
##   - calibrator_applied is not already true
##
## Returns false and leaves state untouched otherwise. The coordinator is
## expected to remove the carried calibrator from InventoryState on a
## true return; this model never reaches into InventoryState.
func apply_junction_calibrator(sequence: int) -> bool:
	if sequence <= 0:
		return false
	if not _objectives.has(sequence):
		return false
	var objective: Dictionary = _objectives[sequence]
	if bool(objective.get("complete", false)):
		return false
	if bool(objective.get("calibrator_applied", false)):
		return false
	var required_steps: int = int(objective.get("required_steps", 1))
	if required_steps <= 1:
		return false
	objective["required_steps"] = required_steps - 1
	objective["calibrator_applied"] = true
	# If the calibrator arrives after the player has already completed
	# steps, the sequence may now be considered complete (e.g. 3-step
	# junction where all 3 steps were already done -> required_steps
	# drops to 2, completed_steps still 3 >= 2 -> complete stays true).
	if int(objective.get("completed_steps", 0)) >= int(objective["required_steps"]):
		objective["complete"] = true
	_objectives[sequence] = objective
	return true

## REQ-014: read-only convenience for the coordinator / save summary.
## Returns true when this sequence's step count was reduced by the
## junction_calibrator in the current run.
func has_calibrator_applied(sequence: int) -> bool:
	if not _objectives.has(sequence):
		return false
	return bool(_objectives[sequence].get("calibrator_applied", false))

func complete_step(sequence: int, step_id: String) -> bool:
	if sequence <= 0:
		return false
	if not _objectives.has(sequence):
		return false
	var objective: Dictionary = _objectives[sequence]
	if bool(objective.get("complete", false)):
		return false
	var completed_ids: Array = objective.get("completed_step_ids", [])
	if completed_ids.has(step_id):
		return false
	completed_ids.append(step_id)
	objective["completed_step_ids"] = completed_ids
	objective["completed_steps"] = completed_ids.size()
	if objective["completed_steps"] >= int(objective.get("required_steps", 1)):
		objective["complete"] = true
	_objectives[sequence] = objective
	return true

func is_sequence_complete(sequence: int) -> bool:
	if not _objectives.has(sequence):
		return false
	return bool(_objectives[sequence].get("complete", false))

func get_step_progress(sequence: int) -> Dictionary:
	if not _objectives.has(sequence):
		return { "required_steps": 0, "completed_steps": 0, "complete": false, "completed_step_ids": [] }
	var objective: Dictionary = _objectives[sequence]
	return {
		"required_steps": int(objective.get("required_steps", 1)),
		"completed_steps": int(objective.get("completed_steps", 0)),
		"complete": bool(objective.get("complete", false)),
		"completed_step_ids": objective.get("completed_step_ids", []).duplicate(),
		# REQ-014: surface the calibrator-applied flag so the HUD and
		# save/load can read it without poking at internal fields.
		"calibrator_applied": bool(objective.get("calibrator_applied", false)),
	}

func get_sequence_objective_type(sequence: int) -> String:
	if not _objectives.has(sequence):
		return ""
	return str(_objectives[sequence].get("objective_type", ""))

func get_summary() -> Dictionary:
	var summary: Dictionary = {}
	for sequence in _objectives.keys():
		var objective: Dictionary = _objectives[sequence]
		summary[sequence] = {
			"objective_type": str(objective.get("objective_type", "")),
			"required_steps": int(objective.get("required_steps", 1)),
			"completed_steps": int(objective.get("completed_steps", 0)),
			"completed_step_ids": objective.get("completed_step_ids", []).duplicate(),
			"complete": bool(objective.get("complete", false)),
			# REQ-014: persist the calibrator_applied flag through
			# get_summary / apply_summary so REQ-012 save/load restores
			# the reduced step count and a reloaded run cannot re-apply.
			"calibrator_applied": bool(objective.get("calibrator_applied", false)),
		}
	return summary

func reset() -> void:
	_objectives.clear()

## REQ-012: restore this model from a summary dictionary matching
## get_summary()'s shape. The summary is keyed by sequence number; each
## value is a dictionary with required_steps, completed_steps, and
## completed_step_ids. Unknown keys are ignored. Returns true if any
## field changed.
##
## REQ-014: also restores the per-sequence `calibrator_applied` flag so
## a save/load round-trip preserves the reduced step count and prevents
## a reloaded run from re-applying a calibrator to the same sequence.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	for sequence_variant in summary.keys():
		# REQ-014: JSON.stringify turns int dict keys into strings (e.g.
		# `2` -> `"2"`), so a save/load round-trip delivers the
		# per-sequence key as a String. Accept ints, floats, and
		# digit-only strings so the REQ-012 save/load path can re-apply
		# calibrator_applied / required_steps / complete. Anything that
		# does not parse to a positive integer is silently skipped.
		var sequence: int = 0
		match typeof(sequence_variant):
			TYPE_INT, TYPE_FLOAT:
				sequence = int(sequence_variant)
			TYPE_STRING:
				# REQ-014: accept JSON-stringified ints (the round-trip
				# through JSON.stringify turns int keys into strings).
				# Reject anything that doesn't parse cleanly to a positive
				# integer so accidental non-sequence keys cannot corrupt
				# the model.
				var raw: String = String(sequence_variant).strip_edges()
				if raw.is_valid_int() and raw.to_int() > 0:
					sequence = raw.to_int()
			_:
				continue
		if sequence <= 0:
			continue
		var objective_variant: Variant = summary[sequence_variant]
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant as Dictionary
		var required_steps: int = max(1, int(objective.get("required_steps", 1)))
		var completed_step_ids: Array = []
		var completed_ids_variant: Variant = objective.get("completed_step_ids", [])
		if typeof(completed_ids_variant) == TYPE_ARRAY:
			for step_id in (completed_ids_variant as Array):
				completed_step_ids.append(String(step_id))
		var objective_type: String = str(objective.get("objective_type", ""))
		var calibrator_applied: bool = bool(objective.get("calibrator_applied", false))
		var new_record: Dictionary = {
			"objective_type": objective_type,
			"required_steps": required_steps,
			"completed_steps": completed_step_ids.size(),
			"completed_step_ids": completed_step_ids,
			"complete": completed_step_ids.size() >= required_steps,
			"calibrator_applied": calibrator_applied,
		}
		if not _objectives.has(sequence) or _objectives[sequence] != new_record:
			_objectives[sequence] = new_record
			changed = true
	return changed
