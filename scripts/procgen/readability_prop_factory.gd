extends RefCounted
class_name ReadabilityPropFactory

# Semantic readability prop factory.
# Returns Node3D roots with stable names + readability_kind metadata.
# Every prop carries a multi-mesh composition (per concrete plan) with at
# least one MeshInstance3D child for visibility. Each root is flagged with
# meta normal_mode_visual=true so downstream visual-mode filters can find
# the prop without scanning the tree.
#
# Composition recipe (per implementation plan):
#   ObjectiveSupplyCache      crate box + lid box
#   ObjectiveBreakerPanel     panel box + switch box + lever box
#   ObjectiveMedTerminal      base cylinder + screen box
#   ObjectiveReactorConsole   base box + core sphere
#   BlockedBiomatter          membrane sphere + blob spheres
#   RampCue                   stem box + head box
#   EntryBeacon               post cylinder + base cylinder + glow sphere
#   DestinationReactorCore    column cylinder + base cylinder + glow sphere
#   RouteCue                  strip box + arrowhead box (local-space oriented)
#
# Primitive meshes only (BoxMesh, SphereMesh, CylinderMesh).

const OBJECTIVE_PREFIX: String = "ObjectiveAffordance_"
const OBJECTIVE_KIND_SUPPLY: String = "ObjectiveSupplyCache"
const OBJECTIVE_KIND_BREAKER: String = "ObjectiveBreakerPanel"
const OBJECTIVE_KIND_MED: String = "ObjectiveMedTerminal"
const OBJECTIVE_KIND_REACTOR_CONSOLE: String = "ObjectiveReactorConsole"
const OBJECTIVE_KIND_GENERIC: String = "ObjectiveGeneric"

const BLOCKED_NAME: String = "BlockedAffordance_01_BlockedBiomatter"
const BLOCKED_KIND: String = "BlockedBiomatter"

const RAMP_NAME: String = "VerticalAffordance_01_RampCue"
const RAMP_KIND: String = "RampCue"

const ENTRY_NAME: String = "EntryBeacon"
const ENTRY_KIND: String = "EntryBeacon"

const DESTINATION_NAME: String = "DestinationReactorCore"
const DESTINATION_KIND: String = "DestinationReactorCore"

const ROUTE_PREFIX: String = "RouteCue_"
const ROUTE_KIND: String = "RouteCue"


# --- public API ----------------------------------------------------------

static func create_objective_prop(sequence: int, objective_type: String) -> Node3D:
	var mapping: Dictionary = _objective_mapping(objective_type)
	var kind: String = str(mapping["kind"])
	var root: Node3D = _base_prop("%s%02d_%s" % [OBJECTIVE_PREFIX, sequence, kind], kind)
	root.set_meta("objective_type", objective_type)
	root.set_meta("sequence", sequence)
	_add_objective_composition(root, kind)
	return root


static func create_blocked_biomatter() -> Node3D:
	var root: Node3D = _base_prop(BLOCKED_NAME, BLOCKED_KIND)
	var membrane_color: Color = Color(0.45, 0.10, 0.10)
	var blob_color: Color = Color(0.85, 0.20, 0.15)
	# Membrane: large sphere anchoring the blocked-affordance volume.
	_add_sphere(root, "BlockedBiomatterMembrane", 1.20, Vector3(0.0, 0.80, 0.0), _material(membrane_color))
	# Blobs: small growth spheres scattered around the membrane.
	_add_sphere(root, "BlockedBiomatterBlobA", 0.45, Vector3(0.85, 0.30, 0.55), _material(blob_color))
	_add_sphere(root, "BlockedBiomatterBlobB", 0.35, Vector3(-0.75, 0.45, 0.35), _material(blob_color))
	_add_sphere(root, "BlockedBiomatterBlobC", 0.40, Vector3(0.20, 1.55, -0.65), _material(blob_color))
	_add_sphere(root, "BlockedBiomatterBlobD", 0.30, Vector3(-0.40, 0.20, -0.85), _material(blob_color))
	# Optional warning glow (light, not a mesh — does not satisfy mesh_count).
	var warn_light: OmniLight3D = OmniLight3D.new()
	warn_light.name = "BlockedBiomatterGlow"
	warn_light.light_color = Color(1.0, 0.35, 0.25)
	warn_light.light_energy = 0.9
	warn_light.omni_range = 4.0
	root.add_child(warn_light)
	return root


static func create_ramp_cue() -> Node3D:
	var root: Node3D = _base_prop(RAMP_NAME, RAMP_KIND)
	var stem_color: Color = Color(0.95, 0.78, 0.30)
	var head_color: Color = Color(0.98, 0.55, 0.12)
	# Stem: long flat strip on the floor pointing along +X.
	_add_box(root, "RampCueStem", Vector3(2.4, 0.15, 0.7), Vector3(0.0, 0.075, 0.0), _material(stem_color))
	# Head: wider, slightly raised arrowhead box at the +X end.
	_add_box(root, "RampCueHead", Vector3(0.9, 0.20, 1.3), Vector3(1.55, 0.10, 0.0), _material(head_color))
	# Optional aim marker (not a mesh — does not satisfy mesh_count).
	var aim: Marker3D = Marker3D.new()
	aim.name = "RampCueAim"
	aim.position = Vector3(2.0, 0.18, 0.0)
	root.add_child(aim)
	return root


static func create_entry_beacon() -> Node3D:
	var root: Node3D = _base_prop(ENTRY_NAME, ENTRY_KIND)
	var post_color: Color = Color(0.30, 0.65, 1.00)
	var glow_color: Color = Color(0.65, 0.92, 1.00)
	# Post: vertical cylinder pole.
	_add_cylinder(root, "EntryBeaconPost", 0.16, 0.20, 2.4, Vector3(0.0, 1.2, 0.0), _material(post_color))
	# Base: short disc anchoring the post to the ground.
	_add_cylinder(root, "EntryBeaconBase", 0.55, 0.55, 0.10, Vector3(0.0, 0.05, 0.0), _material(post_color))
	# Glow sphere: floating ball on top of the post.
	_add_sphere(root, "EntryBeaconGlowSphere", 0.38, Vector3(0.0, 2.7, 0.0), _material(glow_color))
	# Optional halo light (not a mesh — does not satisfy mesh_count).
	var halo: OmniLight3D = OmniLight3D.new()
	halo.name = "EntryBeaconHalo"
	halo.light_color = Color(0.40, 0.85, 1.00)
	halo.light_energy = 1.4
	halo.omni_range = 6.5
	halo.position = Vector3(0.0, 2.7, 0.0)
	root.add_child(halo)
	return root


static func create_destination_reactor_core() -> Node3D:
	var root: Node3D = _base_prop(DESTINATION_NAME, DESTINATION_KIND)
	var column_color: Color = Color(0.10, 0.55, 0.30)
	var glow_color: Color = Color(0.20, 1.00, 0.55)
	# Column: tapered cylinder body.
	_add_cylinder(root, "DestinationReactorColumn", 0.55, 0.85, 2.4, Vector3(0.0, 1.2, 0.0), _material(column_color))
	# Base ring: short wider cylinder foundation.
	_add_cylinder(root, "DestinationReactorBase", 1.10, 1.20, 0.25, Vector3(0.0, 0.125, 0.0), _material(column_color))
	# Glow sphere: bright top sphere (the actual core).
	_add_sphere(root, "DestinationReactorGlowSphere", 0.75, Vector3(0.0, 3.0, 0.0), _material(glow_color))
	# Optional pulse light + focus marker (not meshes).
	var pulse: OmniLight3D = OmniLight3D.new()
	pulse.name = "DestinationReactorCoreGlow"
	pulse.light_color = Color(0.20, 1.00, 0.55)
	pulse.light_energy = 2.0
	pulse.omni_range = 8.0
	pulse.position = Vector3(0.0, 3.0, 0.0)
	root.add_child(pulse)
	var focus: Marker3D = Marker3D.new()
	focus.name = "DestinationReactorCoreFocus"
	focus.position = Vector3(0.0, 3.0, 0.0)
	root.add_child(focus)
	return root


static func create_route_cue(index: int, from_pos: Vector3, to_pos: Vector3) -> Node3D:
	var root: Node3D = _base_prop("%s%02d" % [ROUTE_PREFIX, index], ROUTE_KIND)
	root.set_meta("route_from", from_pos)
	root.set_meta("route_to", to_pos)
	root.set_meta("route_index", index)

	var midpoint: Vector3 = (from_pos + to_pos) * 0.5
	var span: Vector3 = to_pos - from_pos
	var length: float = span.length()
	root.position = midpoint

	# Robust orientation for X/Z (horizontal) spans. We position the root
	# at the midpoint and orient it so local +X points along the direction;
	# child meshes then live in local space (a positioned root + local
	# strip box, no fragile Basis edge-case fallback for vertical spans).
	if length > 0.001:
		var dir: Vector3 = span / length
		var basis_z: Vector3 = Vector3.UP.cross(dir)
		if basis_z.length() > 0.001:
			basis_z = basis_z.normalized()
			var basis_y: Vector3 = dir.cross(basis_z).normalized()
			root.transform.basis = Basis(dir, basis_y, basis_z)

	var stem_length: float = max(length, 0.5)
	var stem_color: Color = Color(0.85, 0.85, 0.20)
	var head_color: Color = Color(0.95, 0.55, 0.10)
	# Stem: thin strip box scaled along local +X to span the route.
	_add_box(root, "RouteCueStem", Vector3(stem_length, 0.20, 0.30), Vector3(0.0, 0.10, 0.0), _material(stem_color))
	# Head: wider arrowhead box at the local +X end.
	var head_size: Vector3 = Vector3(0.55, 0.55, 0.55)
	var head_x: float = stem_length * 0.5 + head_size.x * 0.5
	_add_box(root, "RouteCueHead", head_size, Vector3(head_x, 0.10, 0.0), _material(head_color))

	# Optional from/to markers in local coordinates (not meshes).
	var tail: Marker3D = Marker3D.new()
	tail.name = "RouteCueFrom"
	tail.position = from_pos - midpoint
	root.add_child(tail)
	var head_marker: Marker3D = Marker3D.new()
	head_marker.name = "RouteCueTo"
	head_marker.position = to_pos - midpoint
	root.add_child(head_marker)
	return root


# --- internals -----------------------------------------------------------

static func _base_prop(p_name: String, kind: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = p_name
	root.set_meta("readability_kind", kind)
	root.set_meta("normal_mode_visual", true)
	return root


static func _add_box(root: Node3D, child_name: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = child_name
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	m.mesh = box
	m.position = pos
	m.material_override = material
	root.add_child(m)
	return m


static func _add_sphere(root: Node3D, child_name: String, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = child_name
	var s: SphereMesh = SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	m.mesh = s
	m.position = pos
	m.material_override = material
	root.add_child(m)
	return m


static func _add_cylinder(root: Node3D, child_name: String, top_radius: float, bottom_radius: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = child_name
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = top_radius
	c.bottom_radius = bottom_radius
	c.height = height
	m.mesh = c
	m.position = pos
	m.material_override = material
	root.add_child(m)
	return m


static func _material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


static func _objective_mapping(objective_type: String) -> Dictionary:
	match objective_type:
		"recover_supplies":
			return {"kind": OBJECTIVE_KIND_SUPPLY}
		"restore_systems":
			return {"kind": OBJECTIVE_KIND_BREAKER}
		"download_logs":
			return {"kind": OBJECTIVE_KIND_MED}
		"stabilize_reactor":
			return {"kind": OBJECTIVE_KIND_REACTOR_CONSOLE}
		_:
			return {"kind": OBJECTIVE_KIND_GENERIC}


static func _add_objective_composition(root: Node3D, kind: String) -> void:
	var base_color: Color = _objective_base_color(kind)
	var accent_color: Color = _objective_accent_color(kind)
	var glow_color: Color = _objective_glow_color(kind)
	match kind:
		OBJECTIVE_KIND_SUPPLY:
			# Crate box + lid box stacked.
			_add_box(root, "%sCrate" % kind, Vector3(1.20, 0.90, 1.20), Vector3(0.0, 0.45, 0.0), _material(base_color))
			_add_box(root, "%sLid" % kind, Vector3(1.30, 0.18, 1.30), Vector3(0.0, 0.99, 0.0), _material(accent_color))
		OBJECTIVE_KIND_BREAKER:
			# Wall-mounted panel + protruding switch box + small lever.
			_add_box(root, "%sPanel" % kind, Vector3(1.40, 1.10, 0.25), Vector3(0.0, 0.75, 0.0), _material(base_color))
			_add_box(root, "%sSwitch" % kind, Vector3(0.35, 0.35, 0.20), Vector3(0.0, 1.00, 0.18), _material(accent_color))
			_add_box(root, "%sSwitchLever" % kind, Vector3(0.10, 0.45, 0.10), Vector3(0.0, 1.00, 0.32), _material(glow_color))
		OBJECTIVE_KIND_MED:
			# Cylindrical base + flat screen tilted forward.
			_add_cylinder(root, "%sBase" % kind, 0.60, 0.70, 1.00, Vector3(0.0, 0.50, 0.0), _material(base_color))
			_add_box(root, "%sScreen" % kind, Vector3(0.95, 0.55, 0.10), Vector3(0.0, 1.15, 0.30), _material(accent_color))
		OBJECTIVE_KIND_REACTOR_CONSOLE:
			# Console base + glowing core sphere on top.
			_add_box(root, "%sBase" % kind, Vector3(1.50, 0.60, 1.00), Vector3(0.0, 0.30, 0.0), _material(base_color))
			_add_sphere(root, "%sCore" % kind, 0.42, Vector3(0.0, 0.85, 0.0), _material(glow_color))
		_:
			# Generic fallback: pedestal + orb.
			_add_cylinder(root, "%sPedestal" % kind, 0.45, 0.55, 0.90, Vector3(0.0, 0.45, 0.0), _material(base_color))
			_add_sphere(root, "%sOrb" % kind, 0.55, Vector3(0.0, 1.30, 0.0), _material(accent_color))
	# Optional category-tinted light (visual emphasis, not a mesh).
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.name = "%sGlow" % kind
	lamp.light_color = glow_color
	lamp.light_energy = 1.1
	lamp.omni_range = 4.0
	root.add_child(lamp)


static func _objective_base_color(kind: String) -> Color:
	match kind:
		OBJECTIVE_KIND_SUPPLY:
			return Color(0.85, 0.65, 0.22)
		OBJECTIVE_KIND_BREAKER:
			return Color(0.22, 0.45, 0.85)
		OBJECTIVE_KIND_MED:
			return Color(0.75, 0.25, 0.45)
		OBJECTIVE_KIND_REACTOR_CONSOLE:
			return Color(0.20, 0.75, 0.45)
		_:
			return Color(0.55, 0.55, 0.55)


static func _objective_accent_color(kind: String) -> Color:
	match kind:
		OBJECTIVE_KIND_SUPPLY:
			return Color(0.95, 0.78, 0.30)
		OBJECTIVE_KIND_BREAKER:
			return Color(0.30, 0.55, 0.95)
		OBJECTIVE_KIND_MED:
			return Color(0.95, 0.30, 0.55)
		OBJECTIVE_KIND_REACTOR_CONSOLE:
			return Color(0.25, 0.95, 0.55)
		_:
			return Color(0.80, 0.80, 0.80)


static func _objective_glow_color(kind: String) -> Color:
	match kind:
		OBJECTIVE_KIND_SUPPLY:
			return Color(1.00, 0.85, 0.30)
		OBJECTIVE_KIND_BREAKER:
			return Color(1.00, 0.30, 0.20)
		OBJECTIVE_KIND_MED:
			return Color(0.30, 0.95, 0.95)
		OBJECTIVE_KIND_REACTOR_CONSOLE:
			return Color(0.35, 1.00, 0.65)
		_:
			return Color(0.85, 0.85, 0.85)