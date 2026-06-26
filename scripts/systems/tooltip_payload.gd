extends RefCounted
class_name TooltipPayload
## Read-only payload returned by `TooltipPresenter.resolve()`.
##
## Pure data carrier — no scene-tree access, no signal emission. The
## scene `TooltipPanel` reads the title / body / footer and renders.
##
## `footer_glyph` and `footer_action_label` split the legacy single
## footer string so the panel can swap the glyph (controller scheme)
## without re-running the catalog lookup.

var title: String = ""
var body: String = ""
var footer: String = ""
var footer_glyph: String = ""
var footer_action_label: String = ""
var subject_kind: String = ""
var subject_id: String = ""

func _init(p_title: String = "", p_body: String = "", p_footer: String = "", p_kind: String = "", p_id: String = "") -> void:
	title = p_title
	body = p_body
	footer = p_footer
	subject_kind = p_kind
	subject_id = p_id
	_split_footer()

func _split_footer() -> void:
	# Footer convention: "[glyph] action_label" — e.g. "[E] Pick up".
	# The split keeps the glyph and label separable so the panel can
	# swap the glyph based on the active controller scheme.
	var stripped: String = footer.strip_edges()
	if stripped.is_empty():
		return
	if not stripped.begins_with("["):
		footer_action_label = stripped
		return
	var end_bracket: int = stripped.find("]")
	if end_bracket < 0:
		footer_action_label = stripped
		return
	footer_glyph = stripped.substr(0, end_bracket + 1)
	var rest: String = stripped.substr(end_bracket + 1).strip_edges()
	footer_action_label = rest

func to_dict() -> Dictionary:
	return {
		"title": title,
		"body": body,
		"footer": footer,
		"footer_glyph": footer_glyph,
		"footer_action_label": footer_action_label,
		"subject_kind": subject_kind,
		"subject_id": subject_id,
	}

static func from_dict(d: Dictionary) -> RefCounted:
	var p: RefCounted = load("res://scripts/systems/tooltip_payload.gd").new(
		String(d.get("title", "")),
		String(d.get("body", "")),
		String(d.get("footer", "")),
		String(d.get("subject_kind", "")),
		String(d.get("subject_id", "")),
	)
	return p