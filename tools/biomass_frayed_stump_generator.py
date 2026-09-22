"""Procedural frayed flesh stump base generator for biomass parts.
Creates a cylindrical base with frayed torn flesh tendrils at one end.
Three size variants: small (0.15m), medium (0.25m), large (0.35m).
"""
import bpy
import bmesh
import math
import os
import sys
import json
import argparse
from mathutils import Vector, noise
import random

def cleanup():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)

def create_tendril_segment(bm, base_pos, direction, length, width, segments=4):
    """Create a single frayed tendril as a series of connected quads."""
    verts = []
    current_pos = Vector(base_pos)
    current_dir = Vector(direction).normalized()
    
    for i in range(segments + 1):
        t = i / segments
        # Taper from base to tip
        seg_width = width * (1.0 - t * 0.8)
        
        # Perpendicular vectors for the cross-section
        if abs(current_dir.z) < 0.9:
            perp1 = current_dir.cross(Vector((0, 0, 1))).normalized()
        else:
            perp1 = current_dir.cross(Vector((1, 0, 0))).normalized()
        perp2 = current_dir.cross(perp1).normalized()
        
        # Create quad vertices at this segment
        v1 = bm.verts.new(current_pos + perp1 * seg_width)
        v2 = bm.verts.new(current_pos - perp1 * seg_width)
        v3 = bm.verts.new(current_pos - perp2 * seg_width * 0.3)
        v4 = bm.verts.new(current_pos + perp2 * seg_width * 0.3)
        verts.append((v1, v2, v3, v4))
        
        if i < segments:
            # Advance position with some random curve
            seg_len = length / segments
            # Add random curve
            curve = noise.noise_vector(current_pos * 5.0) * seg_len * 0.5
            current_pos += current_dir * seg_len + curve
            # Randomly bend direction
            bend = noise.noise_vector(current_pos * 3.0) * 0.3
            current_dir = (current_dir + bend).normalized()
    
    # Connect segments with faces
    for i in range(len(verts) - 1):
        v0 = verts[i]
        v1 = verts[i + 1]
        for j in range(4):
            j_next = (j + 1) % 4
            try:
                bm.faces.new([v0[j], v0[j_next], v1[j_next], v1[j]])
            except:
                pass

def create_frayed_stump(diameter=0.25, height=0.15, num_tendrils=30, tendril_length=0.12):
    """Create a frayed flesh stump base with long droopy tendrils."""
    radius = diameter / 2
    
    # Create base cylinder
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius,
        depth=height,
        vertices=32,
        location=(0, 0, height/2)
    )
    base = bpy.context.active_object
    base.name = "FrayedStump_Base"
    
    # Add subdivision for organic deformation
    bpy.ops.object.modifier_add(type='SUBSURF')
    base.modifiers["Subdivision"].levels = 2
    bpy.ops.object.modifier_apply(modifier="Subdivision")
    
    # Deform the base organically
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(base.data)
    bm.verts.ensure_lookup_table()
    
    random.seed(42)
    for v in bm.verts:
        loc = v.co
        noise_val = noise.noise_vector(loc * 3.0) * 0.02
        v.co += noise_val
        
        # Taper toward bottom
        if loc.z < height * 0.3:
            taper = 1.0 - (loc.z / (height * 0.3)) * 0.15
            v.co.x *= taper
            v.co.y *= taper
    
    bmesh.update_edit_mesh(base.data)
    bpy.ops.object.mode_set(mode='OBJECT')
    
    # Create long droopy frayed tendrils
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(base.data)
    
    for i in range(num_tendrils):
        angle = (i / num_tendrils) * math.pi * 2
        angle += random.uniform(-0.2, 0.2)
        
        # Position on the rim
        r = radius * random.uniform(0.6, 1.0)
        x = math.cos(angle) * r
        y = math.sin(angle) * r
        z = height
        
        # Outward direction with droop
        outward = Vector((x, y, 0)).normalized()
        droop = random.uniform(0.3, 0.8)
        direction = Vector((outward.x, outward.y, -droop)).normalized()
        
        # Vary tendril properties
        t_len = tendril_length * random.uniform(0.5, 1.5)
        t_width = 0.004 * random.uniform(0.5, 1.5)
        
        create_tendril_segment(
            bm,
            base_pos=Vector((x, y, z)),
            direction=direction,
            length=t_len,
            width=t_width,
            segments=random.randint(3, 6)
        )
    
    bmesh.update_edit_mesh(base.data)
    bpy.ops.object.mode_set(mode='OBJECT')
    
    stump = bpy.context.active_object
    stump.name = "FrayedStump"
    
    # Smooth shading
    bpy.ops.object.shade_smooth()
    
    # Add material
    mat = bpy.data.materials.new("FrayedStump_Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    
    for n in nodes:
        nodes.remove(n)
    
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (0, 0)
    bsdf.inputs['Base Color'].default_value = (0.73, 0.61, 0.63, 1.0)
    bsdf.inputs['Roughness'].default_value = 0.8
    bsdf.inputs['Specular IOR Level'].default_value = 0.2
    
    noise_node = nodes.new('ShaderNodeTexNoise')
    noise_node.location = (-400, 0)
    noise_node.inputs['Scale'].default_value = 15.0
    noise_node.inputs['Detail'].default_value = 8.0
    
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.location = (-200, 0)
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (0.5, 0.35, 0.38, 1.0)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (0.73, 0.61, 0.63, 1.0)
    
    links.new(noise_node.outputs['Fac'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    
    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (200, 0)
    links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    stump.data.materials.append(mat)
    
    return stump

def render_preview(stump, output_path):
    """Render a preview of the stump."""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.image_settings.file_format = 'PNG'
    
    all_co = []
    for v in stump.data.vertices:
        all_co.append(stump.matrix_world @ v.co)
    mn = Vector([min(c[i] for c in all_co) for i in range(3)])
    mx = Vector([max(c[i] for c in all_co) for i in range(3)])
    ctr = (mn + mx) / 2
    ext = max(mx - mn)
    
    cam = bpy.data.cameras.new('Cam')
    cam.lens = 50
    cam_obj = bpy.data.objects.new('Cam', cam)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    dist = ext * 2.0
    cam_obj.location = (ctr.x + dist * 0.7, ctr.y - dist * 0.7, ctr.z + dist * 0.5)
    direction = ctr - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    
    light = bpy.data.lights.new('L', 'AREA')
    light.energy = 50
    light.size = ext
    lo = bpy.data.objects.new('L', light)
    scene.collection.objects.link(lo)
    lo.location = (ctr.x + dist, ctr.y - dist, ctr.z + dist)
    lo.rotation_euler = (math.radians(45), 0, math.radians(45))
    
    w = bpy.data.worlds.new('W')
    scene.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes['Background']
    bg.inputs[0].default_value = (0.02, 0.02, 0.02, 1)
    bg.inputs[1].default_value = 1.0
    
    scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)
    print(f"Saved: {output_path}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--size', choices=['small', 'medium', 'large'], default='medium')
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    
    sizes = {
        'small':  {'diameter': 0.15, 'tendrils': 20, 'tendril_len': 0.08},
        'medium': {'diameter': 0.25, 'tendrils': 30, 'tendril_len': 0.12},
        'large':  {'diameter': 0.35, 'tendrils': 40, 'tendril_len': 0.16},
    }
    s = sizes[args.size]
    
    cleanup()
    stump = create_frayed_stump(
        diameter=s['diameter'],
        height=0.12,
        num_tendrils=s['tendrils'],
        tendril_length=s['tendril_len']
    )
    
    os.makedirs(args.output_dir, exist_ok=True)
    
    glb_path = os.path.join(args.output_dir, f"frayed_stump_{args.size}.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format='GLB',
        use_selection=False
    )
    print(f"Exported: {glb_path}")
    
    preview_path = os.path.join(args.output_dir, f"frayed_stump_{args.size}_preview.png")
    render_preview(stump, preview_path)
    
    blend_path = os.path.join(args.output_dir, f"frayed_stump_{args.size}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"Saved: {blend_path}")

if __name__ == '__main__':
    main()
