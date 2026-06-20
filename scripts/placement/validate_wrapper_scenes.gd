extends SceneTree

const ALLOWED_CATEGORIES: Array[String] = ["structural", "gameplay-prop", "dressing", "character"]
const REQUIRED_ANCHORS_BY_CATEGORY := {
	"structural": ["Anchor_FloorCenter"],
	"gameplay-prop": ["Anchor_FloorCenter", "Anchor_Facing", "Anchor_InteractionPoint"],
	"dressing": [],
	"character": ["Anchor_FloorCenter", "Anchor_Facing", "Anchor_Seat"],
}
const COLLISION_ROOT_BY_KIND := {
	"static-body-proxy": "StaticBody3D",
	"character-body-proxy": "CharacterBody3D",
	"area-trigger-only": "Area3D",
	"no-collision": "",
	"dressing-no-collision": "",
}
const SHAPE_BY_PROXY := {
	"box": "BoxShape3D",
	"capsule": "CapsuleShape3D",
	"convex-hull": "BoxShape3D",
	"none": "",
}

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: godot --headless --path <project> --script res://scripts/placement/validate_wrapper_scenes.gd -- <scene-or-directory> [...]")
		quit(1)
		return

	var scene_paths: Array[String] = []
	var errors: Array[String] = []
	for raw_arg in args:
		if raw_arg.strip_edges().is_empty() or raw_arg == "--":
			continue
		_collect_scene_paths(_resolve_path(raw_arg), scene_paths, errors)

	scene_paths.sort()
	if scene_paths.is_empty():
		errors.append("no .tscn files found in the provided arguments")

	for scene_path in scene_paths:
		_validate_bundle(scene_path, errors)

	if errors.is_empty():
		print("Validated %d wrapper scene bundle(s)." % scene_paths.size())
		quit(0)
		return

	for error in errors:
		push_error(error)
	quit(1)


func _resolve_path(raw_path: String) -> String:
	if raw_path.begins_with("res://") or raw_path.begins_with("user://"):
		return ProjectSettings.globalize_path(raw_path)
	if raw_path.is_absolute_path():
		return raw_path
	if FileAccess.file_exists(raw_path) or DirAccess.open(raw_path) != null:
		return raw_path
	var cwd: String = OS.get_environment("PWD")
	if not cwd.is_empty():
		var cwd_path: String = cwd.path_join(raw_path)
		if FileAccess.file_exists(cwd_path) or DirAccess.open(cwd_path) != null:
			return cwd_path
	return ProjectSettings.globalize_path("res://%s" % raw_path)


func _collect_scene_paths(path: String, out_paths: Array[String], errors: Array[String]) -> void:
	if FileAccess.file_exists(path):
		if path.get_extension().to_lower() == "tscn":
			out_paths.append(path)
		return

	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		errors.append("path does not exist or is not readable: %s" % path)
		return

	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == ".." or entry.begins_with("."):
			continue
		var child_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_collect_scene_paths(child_path, out_paths, errors)
		elif entry.get_extension().to_lower() == "tscn":
			out_paths.append(child_path)
	dir.list_dir_end()


func _read_text(path: String, errors: Array[String]) -> String:
	if not FileAccess.file_exists(path):
		errors.append("missing file: %s" % path)
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("could not open file: %s" % path)
		return ""
	return file.get_as_text()


func _parse_json_file(path: String, errors: Array[String]) -> Dictionary:
	var text: String = _read_text(path, errors)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s: expected JSON object" % path)
		return {}
	return parsed


func _expect_dictionary(value: Variant, path: String, errors: Array[String]) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: expected JSON object" % path)
		return {}
	return value


func _get_quoted_value(line: String, key: String) -> String:
	var needle: String = "%s=\"" % key
	var start: int = line.find(needle)
	if start == -1:
		return ""
	start += needle.length()
	var finish: int = line.find("\"", start)
	if finish == -1:
		return ""
	return line.substr(start, finish - start)


func _get_ext_resource_value(line: String, key: String) -> String:
	var needle: String = "%s=ExtResource(\"" % key
	var start: int = line.find(needle)
	if start == -1:
		return ""
	start += needle.length()
	var finish: int = line.find("\"", start)
	if finish == -1:
		return ""
	var resource_id: String = line.substr(start, finish - start)
	return "ExtResource(\"%s\")" % resource_id


func _scene_base(scene_path: String) -> String:
	if scene_path.ends_with(".tscn"):
		return scene_path.substr(0, scene_path.length() - 5)
	return scene_path


func _parse_scene(scene_path: String, errors: Array[String]) -> Dictionary:
	var text: String = _read_text(scene_path, errors)
	if text.is_empty():
		return {}

	var extresources: Dictionary = {}
	var subresources: Dictionary = {}
	var nodes: Array[Dictionary] = []
	var current_node: Dictionary = {}
	var current_props: Array[String] = []
	var in_node: bool = false

	for raw_line in text.split("\n"):
		var line: String = raw_line.replace("\r", "")
		if line.begins_with("[ext_resource "):
			var ext_type: String = _get_quoted_value(line, "type")
			var ext_path: String = _get_quoted_value(line, "path")
			var ext_id: String = _get_quoted_value(line, "id")
			if ext_type.is_empty() or ext_path.is_empty() or ext_id.is_empty():
				errors.append("%s: malformed ext_resource header: %s" % [scene_path, line])
			else:
				extresources[ext_id] = {"type": ext_type, "path": ext_path}
			continue
		if line.begins_with("[sub_resource "):
			var sub_type: String = _get_quoted_value(line, "type")
			var sub_id: String = _get_quoted_value(line, "id")
			if sub_type.is_empty() or sub_id.is_empty():
				errors.append("%s: malformed sub_resource header: %s" % [scene_path, line])
			else:
				subresources[sub_id] = sub_type
			continue

		if line.begins_with("[node "):
			if in_node:
				current_node["props"] = current_props.duplicate()
				nodes.append(current_node)
			current_node = {
				"name": _get_quoted_value(line, "name"),
				"type": _get_quoted_value(line, "type"),
				"instance": _get_ext_resource_value(line, "instance"),
				"parent": _get_quoted_value(line, "parent"),
				"header": line,
				"props": [],
			}
			current_props = []
			in_node = true
			continue

		if in_node:
			current_props.append(line)

	if in_node:
		current_node["props"] = current_props.duplicate()
		nodes.append(current_node)

	return {
		"extresources": extresources,
		"subresources": subresources,
		"nodes": nodes,
	}


func _validate_bundle(scene_path: String, errors: Array[String]) -> void:
	if scene_path.get_extension().to_lower() != "tscn":
		return

	var base: String = _scene_base(scene_path)
	var manifest_path: String = "%s.manifest.json" % base
	var input_path: String = "%s.input.json" % base

	var manifest: Dictionary = _parse_json_file(manifest_path, errors)
	if manifest.is_empty():
		return

	var manifest_asset: Dictionary = _expect_dictionary(manifest.get("asset", {}), manifest_path + ":asset", errors)
	var generated: Dictionary = _expect_dictionary(manifest.get("generated", {}), manifest_path + ":generated", errors)

	if str(manifest.get("document_kind", "")) != "godot_wrapper_scene":
		errors.append("%s: expected document_kind godot_wrapper_scene" % manifest_path)

	var category: String = str(manifest_asset.get("category", ""))
	if not ALLOWED_CATEGORIES.has(category):
		errors.append("%s: invalid category %s" % [manifest_path, category])

	var collision_policy: Dictionary = _expect_dictionary(manifest_asset.get("collision_policy", {}), manifest_path + ":asset.collision_policy", errors)
	var anchors_block: Dictionary = _expect_dictionary(manifest_asset.get("anchors", {}), manifest_path + ":asset.anchors", errors)

	var exposed_anchors_variant: Variant = anchors_block.get("exposed", [])
	var exposed_anchors: Array = []
	if typeof(exposed_anchors_variant) == TYPE_ARRAY:
		exposed_anchors = exposed_anchors_variant
	else:
		errors.append("%s: asset.anchors.exposed must be an array" % manifest_path)

	var input_doc: Dictionary = _parse_json_file(input_path, errors)
	if not input_doc.is_empty():
		var input_asset: Dictionary = _expect_dictionary(input_doc.get("asset", {}), input_path + ":asset", errors)
		if str(input_doc.get("document_kind", "")) != "asset_semantics":
			errors.append("%s: expected document_kind asset_semantics" % input_path)
		if input_asset.get("category", null) != category:
			errors.append("%s: input and manifest categories do not match" % scene_path)
		if input_asset.get("wrapper_scene", null) != manifest_asset.get("wrapper_scene", null):
			errors.append("%s: input and manifest wrapper_scene paths do not match" % scene_path)
		if input_asset.get("contract_path", null) != manifest_asset.get("contract_path", null):
			errors.append("%s: input and manifest contract_path values do not match" % scene_path)
		if input_asset.get("inspection_path", null) != manifest_asset.get("inspection_path", null):
			errors.append("%s: input and manifest inspection_path values do not match" % scene_path)

	var expected_root_type: String = str(COLLISION_ROOT_BY_KIND.get(str(collision_policy.get("kind", "")), ""))
	var expected_shape_type: String = str(SHAPE_BY_PROXY.get(str(collision_policy.get("proxy_shape", "")), ""))

	var parsed_scene: Dictionary = _parse_scene(scene_path, errors)
	if parsed_scene.is_empty():
		return

	var nodes_variant: Variant = parsed_scene.get("nodes", [])
	var nodes: Array = []
	if typeof(nodes_variant) == TYPE_ARRAY:
		nodes = nodes_variant
	if nodes.is_empty():
		errors.append("%s: scene contains no node blocks" % scene_path)
		return

	var subresources_variant: Variant = parsed_scene.get("subresources", {})
	var subresources: Dictionary = {}
	if typeof(subresources_variant) == TYPE_DICTIONARY:
		subresources = subresources_variant

	var extresources_variant: Variant = parsed_scene.get("extresources", {})
	var extresources: Dictionary = {}
	if typeof(extresources_variant) == TYPE_DICTIONARY:
		extresources = extresources_variant

	var nodes_by_name: Dictionary = {}
	for node_variant in nodes:
		var node: Dictionary = node_variant
		var node_name: String = str(node.get("name", ""))
		var node_type: String = str(node.get("type", ""))
		var node_instance: String = str(node.get("instance", ""))
		if node_name.is_empty() or (node_type.is_empty() and node_instance.is_empty()):
			errors.append("%s: malformed node header: %s" % [scene_path, str(node.get("header", ""))])
			continue
		if nodes_by_name.has(node_name):
			errors.append("%s: duplicate node name %s" % [scene_path, node_name])
		else:
			nodes_by_name[node_name] = node

	var root: Dictionary = nodes[0]
	var root_name: String = str(root.get("name", ""))
	var root_type: String = str(root.get("type", ""))
	if root_type != "Node3D":
		errors.append("%s: root node must be Node3D, got %s" % [scene_path, root_type])
	if str(root.get("parent", "")) != "":
		errors.append("%s: root node must not declare a parent" % scene_path)
	if str(generated.get("scene_root", "")) != root_name:
		errors.append("%s: manifest.generated.scene_root does not match scene root name" % scene_path)
	if str(generated.get("root_transform", "")) != "identity":
		errors.append("%s: manifest.generated.root_transform must be identity" % scene_path)
	if generated.get("visual_child", null) != true:
		errors.append("%s: manifest.generated.visual_child must be true" % scene_path)
	var generated_collision_root_type: Variant = generated.get("collision_root_type", null)
	if expected_root_type.is_empty():
		if generated_collision_root_type != null and str(generated_collision_root_type) != "":
			errors.append("%s: manifest.generated.collision_root_type must be null for non-blocking wrappers" % scene_path)
	else:
		if str(generated_collision_root_type) != expected_root_type:
			errors.append("%s: manifest.generated.collision_root_type does not match collision policy" % scene_path)
	if str(generated.get("proxy_shape", "")) != str(collision_policy.get("proxy_shape", "")):
		errors.append("%s: manifest.generated.proxy_shape does not match collision policy" % scene_path)

	for prop_variant in root.get("props", []):
		var prop_line: String = str(prop_variant)
		if prop_line.begins_with("transform =") or prop_line.begins_with("position =") or prop_line.begins_with("rotation =") or prop_line.begins_with("scale ="):
			errors.append("%s: root node must use identity transform, found %s" % [scene_path, prop_line])

	var required_anchors: Array = REQUIRED_ANCHORS_BY_CATEGORY.get(category, [])
	for required_anchor_variant in required_anchors:
		var required_anchor: String = str(required_anchor_variant)
		if not nodes_by_name.has(required_anchor):
			errors.append("%s: missing required anchor %s for category %s" % [scene_path, required_anchor, category])

	var manifest_anchor_names: Array[String] = []
	for anchor_variant in exposed_anchors:
		if typeof(anchor_variant) != TYPE_DICTIONARY:
			errors.append("%s: anchors.exposed entries must be objects" % manifest_path)
			continue
		var anchor: Dictionary = anchor_variant
		var anchor_name: String = str(anchor.get("name", ""))
		if anchor_name.is_empty():
			errors.append("%s: anchor entry missing name" % manifest_path)
			continue
		manifest_anchor_names.append(anchor_name)
		if not nodes_by_name.has(anchor_name):
			errors.append("%s: missing anchor node %s" % [scene_path, anchor_name])
			continue
		var anchor_node: Dictionary = nodes_by_name[anchor_name]
		if str(anchor_node.get("type", "")) != "Marker3D":
			errors.append("%s: anchor node %s must be a Marker3D" % [scene_path, anchor_name])
		if str(anchor_node.get("parent", "")) != ".":
			errors.append("%s: anchor node %s must be parented to the root node" % [scene_path, anchor_name])

	var actual_anchor_names: Array[String] = []
	for node_variant in nodes:
		var node: Dictionary = node_variant
		var node_name: String = str(node.get("name", ""))
		if node_name.begins_with("Anchor_"):
			actual_anchor_names.append(node_name)
			if str(node.get("type", "")) != "Marker3D":
				errors.append("%s: anchor node %s must be a Marker3D" % [scene_path, node_name])
			if str(node.get("parent", "")) != ".":
				errors.append("%s: anchor node %s must be parented to the root node" % [scene_path, node_name])

	manifest_anchor_names.sort()
	actual_anchor_names.sort()
	if manifest_anchor_names != actual_anchor_names:
		errors.append("%s: scene anchor set does not match manifest asset.anchors.exposed" % scene_path)

	var visual_node: Dictionary = nodes_by_name.get("Visual", {})
	if visual_node.is_empty():
		errors.append("%s: missing Visual node" % scene_path)
	else:
		if str(visual_node.get("type", "")) != "Node3D":
			errors.append("%s: Visual node must be Node3D" % scene_path)
		if str(visual_node.get("parent", "")) != ".":
			errors.append("%s: Visual node must be parented to the root node" % scene_path)

	var generated_visual_scene_path: String = ""
	var generated_visual_scene_path_variant: Variant = generated.get("visual_scene_path", null)
	if typeof(generated_visual_scene_path_variant) == TYPE_STRING:
		generated_visual_scene_path = str(generated_visual_scene_path_variant)
	if not generated_visual_scene_path.is_empty():
		var visual_instance: Dictionary = nodes_by_name.get("VisualInstance", {})
		if visual_instance.is_empty():
			errors.append("%s: missing VisualInstance node for generated.visual_scene_path" % scene_path)
		else:
			if str(visual_instance.get("parent", "")) != "Visual":
				errors.append("%s: VisualInstance must be parented to Visual" % scene_path)
			var visual_instance_ref: String = str(visual_instance.get("instance", ""))
			if visual_instance_ref.is_empty():
				errors.append("%s: VisualInstance must instance the generated visual scene" % scene_path)
			else:
				var instance_start: int = visual_instance_ref.find("\"")
				var instance_finish: int = visual_instance_ref.find("\"", instance_start + 1)
				if instance_start == -1 or instance_finish == -1:
					errors.append("%s: VisualInstance has malformed ext_resource reference" % scene_path)
				else:
					var visual_instance_resource_id: String = visual_instance_ref.substr(instance_start + 1, instance_finish - instance_start - 1)
					var visual_instance_resource: Dictionary = extresources.get(visual_instance_resource_id, {})
					if visual_instance_resource.is_empty():
						errors.append("%s: VisualInstance references missing ext_resource %s" % [scene_path, visual_instance_resource_id])
					else:
						if str(visual_instance_resource.get("type", "")) != "PackedScene":
							errors.append("%s: VisualInstance ext_resource must be a PackedScene" % scene_path)
						if str(visual_instance_resource.get("path", "")) != generated_visual_scene_path:
							errors.append("%s: VisualInstance ext_resource path does not match manifest.generated.visual_scene_path" % scene_path)

	var collision_root: Dictionary = nodes_by_name.get("CollisionRoot", {})
	var collision_shape: Dictionary = nodes_by_name.get("CollisionShape3D", {})
	if expected_root_type.is_empty():
		if not collision_root.is_empty():
			errors.append("%s: collision root is forbidden for collision kind %s" % [scene_path, str(collision_policy.get("kind", ""))])
		if not collision_shape.is_empty():
			errors.append("%s: collision shape is forbidden for collision kind %s" % [scene_path, str(collision_policy.get("kind", ""))])
	else:
		if collision_root.is_empty():
			errors.append("%s: missing CollisionRoot node" % scene_path)
		else:
			if str(collision_root.get("type", "")) != expected_root_type:
				errors.append("%s: CollisionRoot must be %s for collision kind %s" % [scene_path, expected_root_type, str(collision_policy.get("kind", ""))])
			if expected_root_type == "StaticBody3D" or expected_root_type == "CharacterBody3D":
				var collision_props: Array = []
				var collision_props_variant: Variant = collision_root.get("props", [])
				if typeof(collision_props_variant) == TYPE_ARRAY:
					collision_props = collision_props_variant
				if not collision_props.has("collision_layer = 1"):
					errors.append("%s: CollisionRoot missing collision_layer = 1" % scene_path)
				if not collision_props.has("collision_mask = 1"):
					errors.append("%s: CollisionRoot missing collision_mask = 1" % scene_path)
		if collision_shape.is_empty():
			errors.append("%s: missing CollisionShape3D node" % scene_path)
		else:
			if str(collision_shape.get("parent", "")) != "CollisionRoot":
				errors.append("%s: CollisionShape3D must be parented to CollisionRoot" % scene_path)
			var shape_subresource_id: String = ""
			var shape_props_variant: Variant = collision_shape.get("props", [])
			if typeof(shape_props_variant) == TYPE_ARRAY:
				for prop_variant in shape_props_variant:
					var prop_line: String = str(prop_variant)
					if prop_line.begins_with("shape = SubResource("):
						var start: int = prop_line.find("\"")
						var finish: int = prop_line.find("\"", start + 1)
						if start != -1 and finish != -1:
							shape_subresource_id = prop_line.substr(start + 1, finish - start - 1)
							break
				if shape_subresource_id.is_empty():
					errors.append("%s: CollisionShape3D missing shape subresource" % scene_path)
				else:
					var shape_type: String = str(subresources.get(shape_subresource_id, ""))
					if not expected_shape_type.is_empty() and shape_type != expected_shape_type:
						errors.append("%s: CollisionShape3D must use %s, got %s" % [scene_path, expected_shape_type, shape_type])

	if category == "structural" and expected_root_type != "StaticBody3D":
		errors.append("%s: structural wrappers must use a StaticBody3D collision root" % scene_path)
	if category == "gameplay-prop" and expected_root_type != "StaticBody3D":
		errors.append("%s: gameplay-prop wrappers must use a StaticBody3D collision root" % scene_path)
	if category == "character" and expected_root_type != "CharacterBody3D":
		errors.append("%s: character wrappers must use a CharacterBody3D collision root" % scene_path)
	if category == "dressing" and not expected_root_type.is_empty():
		errors.append("%s: dressing wrappers must not declare a collision root" % scene_path)
