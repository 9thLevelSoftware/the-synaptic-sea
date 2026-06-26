extends RefCounted
class_name MenuStateSchema
## Static validation for `MenuState` catalog payloads.
##
## A menu catalog is a JSON document with the following shape:
##
##   {
##     "menus": [
##       { "id": "main_menu",
##         "title": "The Synaptic Sea",
##         "items": [
##           { "id": "start",   "label": "New Run",     "enabled": true,  "kind": "command" },
##           { "id": "continue","label": "Continue",   "enabled": false, "kind": "command" },
##           { "id": "settings","label": "Settings",   "enabled": true,  "kind": "command" },
##           { "id": "quit",    "label": "Quit",        "enabled": true,  "kind": "command" }
##         ]
##       },
##       ...
##     ]
##   }
##
## The schema rejects:
##   - missing / non-Dictionary root
##   - `menus` not an Array
##   - a menu without `id`, `title`, or `items`
##   - a menu with empty `items`
##   - an item without `id`, `label`, or `kind`
##   - a `kind` outside the allowlist (`command` / `submenu` / `toggle` / `slider`)
##   - duplicate menu ids
##   - duplicate item ids within a menu
##
## On rejection it `push_error`s and returns false. The catalog is the
## only source of truth; an unknown menu / item id is rejected by the
## state model, not silently accepted.

const VALID_KINDS: Array[String] = ["command", "submenu", "toggle", "slider"]

static func validate_catalog(catalog: Variant) -> bool:
	if catalog == null or typeof(catalog) != TYPE_DICTIONARY:
		push_error("MenuStateSchema: catalog must be a Dictionary; got %s" % typeof(catalog))
		return false
	var dict: Dictionary = catalog
	var menus_variant: Variant = dict.get("menus", null)
	if typeof(menus_variant) != TYPE_ARRAY:
		push_error("MenuStateSchema: 'menus' must be an Array")
		return false
	var menus: Array = menus_variant
	var seen_menu_ids: Dictionary = {}
	for menu in menus:
		if typeof(menu) != TYPE_DICTIONARY:
			push_error("MenuStateSchema: menu entry must be a Dictionary")
			return false
		var menu_dict: Dictionary = menu
		var menu_id: String = str(menu_dict.get("id", ""))
		if menu_id.is_empty():
			push_error("MenuStateSchema: menu missing 'id'")
			return false
		if seen_menu_ids.has(menu_id):
			push_error("MenuStateSchema: duplicate menu id '%s'" % menu_id)
			return false
		seen_menu_ids[menu_id] = true
		var title: String = str(menu_dict.get("title", ""))
		if title.is_empty():
			push_error("MenuStateSchema: menu '%s' missing 'title'" % menu_id)
			return false
		var items_variant: Variant = menu_dict.get("items", null)
		if typeof(items_variant) != TYPE_ARRAY:
			push_error("MenuStateSchema: menu '%s' 'items' must be an Array" % menu_id)
			return false
		var items: Array = items_variant
		if items.is_empty():
			push_error("MenuStateSchema: menu '%s' has empty 'items'" % menu_id)
			return false
		var seen_item_ids: Dictionary = {}
		for item in items:
			if typeof(item) != TYPE_DICTIONARY:
				push_error("MenuStateSchema: item in menu '%s' must be a Dictionary" % menu_id)
				return false
			var item_dict: Dictionary = item
			var item_id: String = str(item_dict.get("id", ""))
			if item_id.is_empty():
				push_error("MenuStateSchema: item in menu '%s' missing 'id'" % menu_id)
				return false
			if seen_item_ids.has(item_id):
				push_error("MenuStateSchema: duplicate item id '%s' in menu '%s'" % [item_id, menu_id])
				return false
			seen_item_ids[item_id] = true
			var label: String = str(item_dict.get("label", ""))
			if label.is_empty():
				push_error("MenuStateSchema: item '%s' in menu '%s' missing 'label'" % [item_id, menu_id])
				return false
			var kind: String = str(item_dict.get("kind", ""))
			if not VALID_KINDS.has(kind):
				push_error("MenuStateSchema: item '%s' in menu '%s' has invalid kind '%s'" % [item_id, menu_id, kind])
				return false
	return true

static func is_valid_kind(kind: String) -> bool:
	return VALID_KINDS.has(kind)