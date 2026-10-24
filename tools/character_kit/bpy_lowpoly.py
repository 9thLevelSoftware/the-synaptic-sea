"""Small bmesh helpers for low-poly, flat-shaded character parts.

Blender-only module: it imports ``bpy``/``bmesh`` at call time so host Python
can import the package without Blender present.
"""

from __future__ import annotations

import math
from typing import Dict, Sequence, Tuple

Vec3 = Tuple[float, float, float]


def reset_scene() -> None:
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Remove any residual datablocks so the exported GLB holds only kit data.
    for block_collection in (bpy.data.meshes, bpy.data.materials, bpy.data.actions, bpy.data.armatures):
        for block in list(block_collection):
            block_collection.remove(block)


def new_collection(name: str):
    import bpy

    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def make_materials(material_spec: Dict[str, Dict[str, object]]):
    """Create Principled BSDF materials whose base color / roughness / metallic
    and optional emission export to glTF without textures."""
    import bpy

    created = {}
    for name, props in material_spec.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        color = tuple(props["color"])  # type: ignore[index]
        mat.diffuse_color = color
        mat.roughness = float(props.get("roughness", 0.7))
        mat.metallic = float(props.get("metallic", 0.0))
        nodes = mat.node_tree.nodes
        bsdf = nodes.get("Principled BSDF")
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = color
            bsdf.inputs["Roughness"].default_value = float(props.get("roughness", 0.7))
            bsdf.inputs["Metallic"].default_value = float(props.get("metallic", 0.0))
            emission = props.get("emission")
            if emission is not None:
                bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)  # type: ignore[misc]
                bsdf.inputs["Emission Strength"].default_value = float(props.get("emission_strength", 1.0))
        created[name] = mat
    return created


class MeshBuilder:
    """Accumulates bevelled primitives into one flat-shaded mesh object that is
    rigidly skinned to a single bone (Project Zomboid style segmented body)."""

    def __init__(self, name: str, bone: str | None, armature, collection):
        import bmesh

        self.name = name
        self.bone = bone
        self.armature = armature
        self.collection = collection
        self.bm = bmesh.new()
        self.materials = []

    # -- primitives ---------------------------------------------------------
    def box(
        self,
        size: Vec3,
        center: Vec3,
        material,
        bevel: float = 0.015,
        taper_top: Tuple[float, float] = (1.0, 1.0),
        rotate: Tuple[float, str] | None = None,
    ) -> None:
        import bmesh
        from mathutils import Matrix, Vector

        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if taper_top != (1.0, 1.0):
            for v in bm.verts:
                if v.co.z > 0.0:
                    v.co.x *= taper_top[0]
                    v.co.y *= taper_top[1]
        if bevel > 0.0:
            offset = min(bevel, min(size) * 0.3)
            bmesh.ops.bevel(
                bm,
                geom=bm.edges[:],
                offset=offset,
                segments=1,
                profile=0.5,
                affect="EDGES",
                clamp_overlap=True,
            )
        if rotate is not None:
            angle, axis = rotate
            bmesh.ops.rotate(bm, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(angle, 3, axis), verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
        self._absorb(bm, material)

    def cylinder(
        self,
        radius_bottom: float,
        radius_top: float,
        depth: float,
        center: Vec3,
        material,
        segments: int = 8,
        axis: str = "Z",
    ) -> None:
        import bmesh
        from mathutils import Matrix, Vector

        bm = bmesh.new()
        bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=segments,
            radius1=radius_bottom,
            radius2=radius_top,
            depth=depth,
        )
        if axis == "X":
            bmesh.ops.rotate(bm, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(math.pi / 2.0, 3, "Y"), verts=bm.verts)
        elif axis == "Y":
            bmesh.ops.rotate(bm, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(math.pi / 2.0, 3, "X"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
        self._absorb(bm, material)

    def sphere(self, radius: float, center: Vec3, material, segments: int = 8, rings: int = 5) -> None:
        import bmesh
        from mathutils import Vector

        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
        bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
        self._absorb(bm, material)

    # -- assembly -----------------------------------------------------------
    def _absorb(self, part_bm, material) -> None:
        import bpy

        if material not in self.materials:
            self.materials.append(material)
        index = self.materials.index(material)
        for face in part_bm.faces:
            face.material_index = index
            face.smooth = False
        temp = bpy.data.meshes.new(f"_{self.name}_part")
        part_bm.to_mesh(temp)
        part_bm.free()
        self.bm.from_mesh(temp)
        bpy.data.meshes.remove(temp)

    def finish(self):
        import bpy

        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for mat in self.materials:
            mesh.materials.append(mat)
        for poly in mesh.polygons:
            poly.use_smooth = False
        mesh.validate(verbose=False)
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        self.collection.objects.link(obj)
        if self.armature is not None and self.bone:
            group = obj.vertex_groups.new(name=self.bone)
            group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
            modifier = obj.modifiers.new("Armature", "ARMATURE")
            modifier.object = self.armature
            modifier.use_vertex_groups = True
            obj.parent = self.armature
        return obj


def export_glb(filepath: str, animated: bool) -> None:
    """Normalized GLB export shared by the character and handheld-tool builders.

    ``animated`` enables skin + NLA-track animation export for the rigged kit;
    static props export geometry and materials only. Options are pinned for
    Blender 4.2 LTS so a different Blender fails loudly instead of silently
    exporting a different file."""
    import bpy

    bpy.ops.object.select_all(action="DESELECT")
    options = dict(
        filepath=filepath,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_extras=True,
        export_skins=animated,
        export_animations=animated,
    )
    if animated:
        options.update(
            export_all_influences=False,
            export_def_bones=True,
            export_rest_position_armature=True,
            export_animation_mode="NLA_TRACKS",
            export_force_sampling=True,
            export_frame_range=False,
            export_optimize_animation_size=False,
            export_anim_single_armature=True,
            export_reset_pose_bones=True,
            export_current_frame=False,
        )
    bpy.ops.export_scene.gltf(**options)


def triangle_count(obj) -> int:
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)
