extends RefCounted
class_name SkillTreeState

## REQ-PM-003 / REQ-PM-004 / ADR-0033 skill-tree model.
##
## Loads the skill catalog (`data/player/skills.json`), the skill book
## catalog (`data/player/skill_books.json`), and the per-skill
## prerequisite table (`data/player/skill_tree.json`). Exposes
## `can_unlock(skill_id)` and `unlock(skill_id)` against a `PlayerProgressionState`
## + a `MetaProgressionState` (the latter for cross-run book carries).
##
## Pure: no scene tree, no RNG. The tree panel UI reads from this model
## and the panels' `get_status_lines()` methods emit accessibility text.

const DEFAULT_SKILLS_PATH := "res://data/player/skills.json"
const DEFAULT_BOOKS_PATH := "res://data/player/skill_books.json"
const DEFAULT_PREREQS_PATH := "res://data/player/skill_tree.json"

var _skills_catalog: Dictionary = {}        # skill_id -> {category, display_name}
var _books_catalog: Dictionary = {}         # book_id -> {target_skill, book_xp, unlocks_skill}
var _prereqs: Dictionary = {}              # skill_id -> {requires: [...], book_prerequisite: ""}
var _unlocked: Dictionary = {}             # skill_id -> true (idempotent set)

static func load_skills_catalog(path: String = DEFAULT_SKILLS_PATH) -> Dictionary:
	return PlayerProgressionState.load_skills_catalog(path)

static func load_books_catalog(path: String = DEFAULT_BOOKS_PATH) -> Dictionary:
	return PlayerProgressionState.load_books_catalog(path)

## Loads the prerequisite table. Returns false if the file is missing or
## malformed; the tree still works without prereqs (every skill is
## unlockable from level 0).
func load_prerequisites(path: String = DEFAULT_PREREQS_PATH) -> bool:
	_prereqs.clear()
	if not FileAccess.file_exists(path):
		return false
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var variant: Variant = (parsed as Dictionary).get("skill_prerequisites", [])
	if typeof(variant) != TYPE_ARRAY:
		return false
	for entry in (variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sid: String = str((entry as Dictionary).get("skill_id", ""))
		if sid.is_empty():
			continue
		var requires_raw: Variant = (entry as Dictionary).get("requires", [])
		var requires: Array = []
		if typeof(requires_raw) == TYPE_ARRAY:
			for req in (requires_raw as Array):
				if typeof(req) != TYPE_DICTIONARY:
					continue
				requires.append({
					"skill_id": str((req as Dictionary).get("skill_id", "")),
					"min_level": int((req as Dictionary).get("min_level", 1)),
				})
		_prereqs[sid] = {
			"requires": requires,
			"book_prerequisite": str((entry as Dictionary).get("book_prerequisite", "")),
		}
	return true

## Sets the in-memory catalogs. The book catalog is read at unlock-time
## so live updates (player picks up a new book) work without re-loading.
func configure(skills_catalog: Dictionary, books_catalog: Dictionary) -> void:
	_skills_catalog = skills_catalog if skills_catalog != null else {}
	_books_catalog = books_catalog if books_catalog != null else {}

func set_books_catalog(books_catalog: Dictionary) -> void:
	_books_catalog = books_catalog if books_catalog != null else {}

## Returns the list of prerequisite skills for `skill_id`, or [] when the
## skill has no recorded prereqs (or is unknown).
func get_prerequisites(skill_id: String) -> Array:
	if not _prereqs.has(skill_id):
		return []
	var entry: Dictionary = _prereqs[skill_id]
	return (entry.get("requires", []) as Array).duplicate(true)

## Returns the book id required to unlock `skill_id`, or "" when no
## book is required.
func get_book_prerequisite(skill_id: String) -> String:
	if not _prereqs.has(skill_id):
		return ""
	return str(_prereqs[skill_id].get("book_prerequisite", ""))

## Returns true when `skill_id` is a known skill in the catalog.
func is_known_skill(skill_id: String) -> bool:
	return _skills_catalog.has(skill_id)

## Returns the unlocked set (idempotent copy).
func get_unlocked() -> Dictionary:
	return _unlocked.duplicate()

func is_unlocked(skill_id: String) -> bool:
	return _unlocked.has(skill_id) and bool(_unlocked[skill_id])

## Checks whether `skill_id` is currently unlockable, given a
## PlayerProgressionState (for level checks) and a MetaProgressionState
## (for book reads when books survive across runs).
##
## Rules:
##   1. Skill must be known.
##   2. Skill must not already be unlocked.
##   3. Every prerequisite skill must have level >= its min_level.
##   4. If a book_prerequisite is recorded, the book must be read in
##      the progression's `books_read` set.
##
## Returns a Dictionary {can: bool, reason: String, missing: Array} so
## the UI can show why a skill is locked.
func can_unlock(skill_id: String, progression, meta_state = null) -> Dictionary:
	if not is_known_skill(skill_id):
		return {"can": false, "reason": "unknown_skill", "missing": []}
	if is_unlocked(skill_id):
		return {"can": false, "reason": "already_unlocked", "missing": []}
	var missing: Array = []
	var prereqs: Array = get_prerequisites(skill_id)
	for req in prereqs:
		var req_sid: String = str(req.get("skill_id", ""))
		var min_level: int = int(req.get("min_level", 1))
		if progression == null or not progression.has_method("get_skill_level"):
			missing.append({"type": "skill_level", "skill_id": req_sid, "min_level": min_level, "current": 0})
			continue
		var current: int = int(progression.get_skill_level(req_sid))
		if current < min_level:
			missing.append({"type": "skill_level", "skill_id": req_sid, "min_level": min_level, "current": current})
	var book_prereq: String = get_book_prerequisite(skill_id)
	if not book_prereq.is_empty():
		var read: bool = false
		if progression != null and progression.has_method("has_read_book"):
			read = bool(progression.has_read_book(book_prereq))
		elif meta_state != null and meta_state.has_method("is_codex_entry_unlocked"):
			# Cross-run book carries: codex entry with the same id counts.
			read = bool(meta_state.is_codex_entry_unlocked(book_prereq))
		if not read:
			missing.append({"type": "book", "book_id": book_prereq})
	if missing.is_empty():
		return {"can": true, "reason": "ok", "missing": []}
	return {"can": false, "reason": "missing_prereqs", "missing": missing}

## Records an unlock. Idempotent. Returns true on a state change, false
## when already unlocked or skill is unknown.
func unlock(skill_id: String) -> bool:
	if not is_known_skill(skill_id):
		return false
	if is_unlocked(skill_id):
		return false
	_unlocked[skill_id] = true
	return true

## Returns every skill in the catalog (id + display_name + category +
## prereq count + unlocked flag) for the skill tree panel.
func get_skill_entries() -> Array:
	var out: Array = []
	for sid in _skills_catalog:
		var entry: Dictionary = (_skills_catalog[sid] as Dictionary).duplicate()
		var prereqs: Array = get_prerequisites(sid)
		out.append({
			"skill_id": sid,
			"category": str(entry.get("category", "")),
			"display_name": str(entry.get("display_name", sid)),
			"prereq_count": prereqs.size(),
			"book_prerequisite": get_book_prerequisite(sid),
			"unlocked": is_unlocked(sid),
		})
	out.sort_custom(func(a, b): return String(a.get("skill_id", "")) < String(b.get("skill_id", "")))
	return out

## Reset for a fresh run. The `unlocked` set is per-run; the catalogs
## persist.
func reset_unlocks() -> void:
	_unlocked.clear()

func to_dict() -> Dictionary:
	return {
		"unlocked": _unlocked.duplicate(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or typeof(summary) != TYPE_DICTIONARY:
		return false
	_unlocked.clear()
	var variant: Variant = summary.get("unlocked", {})
	if typeof(variant) == TYPE_DICTIONARY:
		for k in (variant as Dictionary):
			if bool((variant as Dictionary)[k]):
				_unlocked[str(k)] = true
	return true

func get_summary() -> Dictionary:
	return {
		"unlocked_count": _unlocked.size(),
		"unlocked": _unlocked.duplicate(),
	}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Skill Tree: %d / %d unlocked" % [_unlocked.size(), _skills_catalog.size()])
	return lines