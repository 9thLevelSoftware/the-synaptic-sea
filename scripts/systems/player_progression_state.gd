extends RefCounted
class_name PlayerProgressionState

## Pure player-progression model: skill levels (0..MAX), per-skill XP toward the
## next level, the skill->category map used to apply class XP multipliers,
## cross-training counters, and a books_read set.
##
## No scene tree, no RNG. Deterministic per XP sequence.
##
## Schema: `progression-2`. The cross_training and books_read fields are
## additive — older summaries (progression-1) load with empty defaults and
## `apply_summary` never overwrites an existing cross_training entry with
## empty data unless the source explicitly says so.

const MAX_SKILL_LEVEL := 10
const DEFAULT_SKILLS_PATH := "res://data/player/skills.json"
const DEFAULT_BOOKS_PATH := "res://data/player/skill_books.json"
const CROSS_TRAINING_PENALTY := 0.5
const SCHEMA_VERSION := "progression-2"

var class_id: String = ""
var skills: Dictionary = {}          # skill_id -> int level
var skill_xp: Dictionary = {}        # skill_id -> int xp toward next level
var cross_training: Dictionary = {}  # skill_id -> int raw XP earned off-category
var books_read: Dictionary = {}      # book_id -> true (idempotent set)
var skill_xp_fractional: Dictionary = {} # skill_id -> float carry preserved across fractional XP grants
var _xp_multipliers: Dictionary = {} # category -> float (from the class)
var _skill_category: Dictionary = {} # skill_id -> category (from the catalog)
var _book_catalog: Dictionary = {}   # book_id -> {target_skill, book_xp, unlocks_skill}

## Loads skills.json into { skill_id -> {category, display_name} }.
static func load_skills_catalog(path: String = DEFAULT_SKILLS_PATH) -> Dictionary:
	var out: Dictionary = {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var skills_variant: Variant = (parsed as Dictionary).get("skills", [])
	if typeof(skills_variant) != TYPE_ARRAY:
		return out
	for entry in (skills_variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sid: String = str((entry as Dictionary).get("skill_id", ""))
		if sid.is_empty():
			continue
		out[sid] = {
			"category": str((entry as Dictionary).get("category", "")),
			"display_name": str((entry as Dictionary).get("display_name", sid)),
		}
	return out

## Loads skill_books.json into { book_id -> {target_skill, book_xp, unlocks_skill} }.
static func load_books_catalog(path: String = DEFAULT_BOOKS_PATH) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		return out
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var books_variant: Variant = (parsed as Dictionary).get("books", [])
	if typeof(books_variant) != TYPE_ARRAY:
		return out
	for entry in (books_variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var bid: String = str((entry as Dictionary).get("book_id", ""))
		if bid.is_empty():
			continue
		out[bid] = {
			"target_skill": str((entry as Dictionary).get("target_skill", "")),
			"book_xp": int((entry as Dictionary).get("book_xp", 0)),
			"unlocks_skill": str((entry as Dictionary).get("unlocks_skill", "")),
		}
	return out

static func xp_for_next_level(level: int) -> int:
	return (level + 1) * 100

## Seeds skills from class_def.starting_skills (every catalog skill present, default 0),
## records skill->category, the class multipliers, resets all XP and cross-training
## to 0, and primes the book catalog.
func configure(class_def, skills_catalog: Dictionary, books_catalog: Dictionary = {}) -> void:
	skills.clear()
	skill_xp.clear()
	cross_training.clear()
	books_read.clear()
	skill_xp_fractional.clear()
	_skill_category.clear()
	_xp_multipliers = {}
	class_id = ""
	_book_catalog = books_catalog if books_catalog != null else {}
	if class_def != null:
		class_id = str(class_def.class_id)
		_xp_multipliers = (class_def.xp_multipliers as Dictionary).duplicate()
	for sid in skills_catalog:
		_skill_category[sid] = str((skills_catalog[sid] as Dictionary).get("category", ""))
		skills[sid] = 0
		skill_xp[sid] = 0
		cross_training[sid] = 0
		skill_xp_fractional[sid] = 0.0
	if class_def != null:
		for sid in (class_def.starting_skills as Dictionary):
			if skills.has(sid):
				skills[sid] = clampi(int(class_def.starting_skills[sid]), 0, MAX_SKILL_LEVEL)

func get_class_id() -> String:
	return class_id

func get_skill_level(skill_id: String) -> int:
	return int(skills.get(skill_id, 0))

func get_skill_xp(skill_id: String) -> int:
	return int(skill_xp.get(skill_id, 0))

func get_cross_training(skill_id: String) -> int:
	return int(cross_training.get(skill_id, 0))

func get_cross_training_total() -> int:
	var total: int = 0
	for sid in cross_training:
		total += int(cross_training[sid])
	return total

func has_read_book(book_id: String) -> bool:
	return books_read.has(book_id) and bool(books_read[book_id])

## Applies the class category multiplier to `amount`, banks it, and levels the
## skill up on the curve (capped at MAX_SKILL_LEVEL). Returns true if the level
## changed. Unknown skill -> false.
##
## `is_cross_training` defaults to false (caller knows the event category).
## When true, the raw amount is also recorded in the cross_training counter
## so the player can see how much off-category XP they've earned.
func grant_xp(skill_id: String, amount: int, is_cross_training: bool = false) -> bool:
	if not skills.has(skill_id):
		return false
	if amount <= 0:
		return false
	if is_cross_training:
		cross_training[skill_id] = int(cross_training.get(skill_id, 0)) + amount
		amount = int(round(float(amount) * CROSS_TRAINING_PENALTY))
	var category: String = str(_skill_category.get(skill_id, ""))
	var mult: float = float(_xp_multipliers.get(category, 1.0))
	var carry: float = float(skill_xp_fractional.get(skill_id, 0.0))
	var effective_total: float = (float(amount) * mult) + carry
	var effective: int = int(floor(effective_total))
	skill_xp_fractional[skill_id] = effective_total - float(effective)
	var level: int = int(skills[skill_id])
	if level >= MAX_SKILL_LEVEL:
		skill_xp[skill_id] = 0
		skill_xp_fractional[skill_id] = 0.0
		return false
	skill_xp[skill_id] = int(skill_xp[skill_id]) + effective
	var changed: bool = false
	while level < MAX_SKILL_LEVEL and int(skill_xp[skill_id]) >= xp_for_next_level(level):
		skill_xp[skill_id] = int(skill_xp[skill_id]) - xp_for_next_level(level)
		level += 1
		changed = true
	skills[skill_id] = level
	if level >= MAX_SKILL_LEVEL:
		skill_xp[skill_id] = 0
		skill_xp_fractional[skill_id] = 0.0
	return changed

## Reads a skill book. The book's `book_xp` is granted to `target_skill`
## (with the same class multipliers) and the book is recorded in
## `books_read`. Reading the same book twice is a no-op (returns false).
## Returns true on first read.
func grant_xp_from_book(book_id: String) -> bool:
	if not _book_catalog.has(book_id):
		return false
	if books_read.has(book_id) and bool(books_read[book_id]):
		return false
	var entry: Dictionary = _book_catalog[book_id]
	var target: String = str(entry.get("target_skill", ""))
	if target.is_empty() or not skills.has(target):
		# Still record the book so a corrupted skill id doesn't silently
		# re-fire later; but don't grant XP to a missing skill.
		books_read[book_id] = true
		return false
	var xp: int = int(entry.get("book_xp", 0))
	books_read[book_id] = true
	if xp <= 0:
		return true
	# Books are direct XP grants — count as cross-training only if the book's
	# target_skill category differs from the player's primary category, which
	# is captured by grant_xp's multiplier; we do NOT flag them as cross-training
	# because a book the player chose to read is intentional training.
	grant_xp(target, xp, false)
	return true

## Reloads _xp_multipliers for the current class_id from the class catalog.
## Uses load() (not preload) to match the headless-safe self-reference idiom
## and avoid a compile-time dependency cycle. Empties the multipliers if the
## class is unknown (grant_xp then falls back to a 1.0 multiplier per category).
func _reload_class_multipliers() -> void:
	var classes: Dictionary = load("res://scripts/systems/class_definition.gd").load_all()
	if classes.has(class_id):
		_xp_multipliers = (classes[class_id].xp_multipliers as Dictionary).duplicate()
	else:
		_xp_multipliers = {}

## Re-binds the book catalog at runtime. Used by the bus / smoke path when
## the player picks up a new skill book and the catalog reference changes.
func set_books_catalog(books_catalog: Dictionary) -> void:
	_book_catalog = books_catalog if books_catalog != null else {}

## Returns a copy of the book catalog for read-only inspection.
func get_books_catalog() -> Dictionary:
	return _book_catalog.duplicate(true)

func get_summary() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"class_id": class_id,
		"skills": skills.duplicate(),
		"skill_xp": skill_xp.duplicate(),
		"skill_xp_fractional": skill_xp_fractional.duplicate(),
		"cross_training": cross_training.duplicate(),
		"books_read": books_read.duplicate(),
	}

## Restores class_id/skills/skill_xp/cross_training/books_read from a
## get_summary() dict. Skills/xp are overwritten per-key (unknown keys
## ignored). Missing `cross_training` or `books_read` keys default to
## empty — older progression-1 summaries load cleanly.
## Returns true if anything changed.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_class: String = str(summary.get("class_id", class_id))
	if new_class != class_id:
		class_id = new_class
		# Reload the class XP multipliers for the restored class. configure()
		# set them for the ship's default class; without this a save whose
		# class differs from the default would keep the wrong multipliers and
		# grant_xp would level the wrong rates (PR #4 review).
		_reload_class_multipliers()
		changed = true
	var skills_variant: Variant = summary.get("skills", {})
	if typeof(skills_variant) == TYPE_DICTIONARY:
		for sid in (skills_variant as Dictionary):
			if skills.has(sid):
				var lvl: int = clampi(int((skills_variant as Dictionary)[sid]), 0, MAX_SKILL_LEVEL)
				if lvl != int(skills[sid]):
					skills[sid] = lvl
					changed = true
	var xp_variant: Variant = summary.get("skill_xp", {})
	if typeof(xp_variant) == TYPE_DICTIONARY:
		for sid in (xp_variant as Dictionary):
			if skill_xp.has(sid):
				var xp: int = maxi(0, int((xp_variant as Dictionary)[sid]))
				if xp != int(skill_xp[sid]):
					skill_xp[sid] = xp
					changed = true
	# Mirror grant_xp's cap behavior: a maxed skill carries no pending XP.
	for sid in skills:
		if int(skills[sid]) >= MAX_SKILL_LEVEL and int(skill_xp.get(sid, 0)) != 0:
			skill_xp[sid] = 0
			changed = true
	var frac_variant: Variant = summary.get("skill_xp_fractional", null)
	if typeof(frac_variant) == TYPE_DICTIONARY:
		for sid in (frac_variant as Dictionary):
			if skill_xp_fractional.has(sid):
				var frac: float = clampf(float((frac_variant as Dictionary)[sid]), 0.0, 0.999999)
				if absf(frac - float(skill_xp_fractional.get(sid, 0.0))) > 0.000001:
					skill_xp_fractional[sid] = frac
					changed = true
	for sid in skills:
		if int(skills[sid]) >= MAX_SKILL_LEVEL and absf(float(skill_xp_fractional.get(sid, 0.0))) > 0.000001:
			skill_xp_fractional[sid] = 0.0
			changed = true
	# progression-2 fields: only overwrite when the summary actually
	# contains them. progression-1 saves keep the runtime defaults.
	var ct_variant: Variant = summary.get("cross_training", null)
	if typeof(ct_variant) == TYPE_DICTIONARY:
		for sid in (ct_variant as Dictionary):
			if cross_training.has(sid):
				var ct: int = maxi(0, int((ct_variant as Dictionary)[sid]))
				if ct != int(cross_training.get(sid, 0)):
					cross_training[sid] = ct
					changed = true
	var br_variant: Variant = summary.get("books_read", null)
	if typeof(br_variant) == TYPE_DICTIONARY:
		for bid in (br_variant as Dictionary):
			if bool((br_variant as Dictionary)[bid]) and not books_read.has(bid):
				books_read[bid] = true
				changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Class: %s" % class_id)
	for sid in skills:
		var lvl: int = int(skills[sid])
		var xp: int = int(skill_xp.get(sid, 0))
		var ct: int = int(cross_training.get(sid, 0))
		var xp_to_next: int = xp_for_next_level(lvl) - xp if lvl < MAX_SKILL_LEVEL else 0
		var suffix: String = " (max)" if lvl >= MAX_SKILL_LEVEL else " xp=%d/%d" % [xp, xp_for_next_level(lvl)]
		var ct_suffix: String = " cross=%d" % ct if ct > 0 else ""
		lines.append("  - %s L%d%s%s" % [sid, lvl, suffix, ct_suffix])
	return lines