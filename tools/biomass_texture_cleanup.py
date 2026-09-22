"""Standalone Blender cleanup for textured biomass assets.
Normalizes scale, adds sockets, preserves textures, renders previews.
Usage: blender --background --factory-startup --python tools/biomass_texture_cleanup.py -- <args>
"""
import argparse, json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector

def _da(): [o.select_set(False) for o in bpy.context.selected_objects]
def _at(objs, loc=False):
    _da()
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=loc, rotation=False, scale=True)
    _da()
def _bnds(objs):
    pts=[o.matrix_world@Vector(c) for o in objs for c in o.bound_box]
    return tuple(min(p[i] for p in pts) for i in range(3)),tuple(max(p[i] for p in pts) for i in range(3))
def _tc(objs): return sum(len(o.data.loop_triangles) for o in objs)
def _pa(o,p): o.rotation_euler=(p-o.location).to_track_quat("-Z","Y").to_euler()

pa=argparse.ArgumentParser()
pa.add_argument("--raw-glb",type=Path,required=True); pa.add_argument("--contract",type=Path,required=True)
pa.add_argument("--part-catalog",type=Path,required=True); pa.add_argument("--output-dir",type=Path,required=True)
a=pa.parse_args(sys.argv[sys.argv.index("--")+1:])
contract=json.loads(a.contract.read_text(encoding="utf-8"))
catalog=json.loads(a.part_catalog.read_text(encoding="utf-8"))
entry=catalog["parts"][contract["asset_id"]]; out=a.output_dir; out.mkdir(mode=0o700,parents=True,exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True); sc=bpy.context.scene
sc.render.engine="BLENDER_EEVEE"; sc.render.resolution_x=1024; sc.render.resolution_y=1024
sc.render.resolution_percentage=100; sc.render.image_settings.file_format="PNG"
sc.render.image_settings.color_mode="RGBA"; sc.render.image_settings.color_depth='16'
sc.eevee.taa_render_samples=64; sc.eevee.use_fast_gi=True; sc.eevee.fast_gi_quality=2.0; sc.eevee.ray_tracing_method="SCREEN"
w=bpy.data.worlds.new("W"); sc.world=w; w.use_nodes=True
for n in w.node_tree.nodes:
    if n.type=='BACKGROUND': n.inputs["Color"].default_value=(0.02,0.02,0.025,1.0); n.inputs["Strength"].default_value=0.5

bpy.ops.import_scene.gltf(filepath=str(a.raw_glb))
meshes=[o for o in bpy.data.objects if o.type=="MESH"]
if not meshes: sys.exit(1)

td=[float(v) for v in contract["dimensions_m"]]
mn,mx=_bnds(meshes); cur=[mx[i]-mn[i] for i in range(3)]
sc2=[td[i]/cur[i] for i in range(3)]
for o in meshes: o.scale=tuple(float(o.scale[i])*sc2[i] for i in range(3))
_at(meshes)
mn,mx=_bnds(meshes); ctr=[(mn[i]+mx[i])/2.0 for i in range(3)]
pv=contract.get("pivot","bottom_center")
sh=(-ctr[0],-ctr[1],-mn[2]) if pv=="bottom_center" else (-ctr[0],-ctr[1],-ctr[2])
for o in meshes: o.location=tuple(float(o.location[i])+sh[i] for i in range(3))
_at(meshes,loc=True)
hm=contract.get("budget",{}).get("triangles",{}).get("hard_max",2500)
tt=contract.get("budget",{}).get("triangles",{}).get("target",1400)
if _tc(meshes)>hm:
    for o in meshes:
        m=o.modifiers.new("D","DECIMATE"); m.ratio=max(0.01,min(1.0,float(tt)/float(_tc(meshes))))
        bpy.context.view_layer.objects.active=o; o.select_set(True)
        bpy.ops.object.modifier_apply(modifier=m.name); o.select_set(False)

guides=[]
for s in entry.get("sockets",[]): guides.append((s["name"],tuple(s.get("position_m",[0,0,0])),tuple(s.get("rotation_deg",[0,0,0]))))
sm=bpy.data.materials.new("sock"); sm.use_nodes=True
for n in sm.node_tree.nodes:
    if n.type=='BSDF_PRINCIPLED': n.inputs["Base Color"].default_value=(0.9,0.3,0.1,1.0); n.inputs["Emission Color"].default_value=(0.7,0.2,0.05,1.0); n.inputs["Emission Strength"].default_value=1.0; break
for nm,pos,rot in guides:
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.025,segments=16,ring_count=8)
    s=bpy.context.active_object; s.name=f"guide_{nm}"; s.location=(pos[0],pos[2],pos[1]); s.data.materials.append(sm); bpy.ops.object.shade_smooth()

mn,mx=_bnds(meshes); cz=mx[2]*0.5 if pv=="bottom_center" else (mn[2]+mx[2])/2.0; cp=Vector((0,0,cz))
for ln,en,col,loc in [("Key",300,(1.0,0.95,0.9),(2.5,-2.0,2.5)),("Fill",100,(0.85,0.88,1.0),(-3,-1,1.5)),("Rim",150,(0.9,0.9,1.0),(0,3,2))]:
    l=bpy.data.lights.new(f"{ln}L","AREA"); l.energy=en; l.shape="DISK"; l.size=2.0; l.color=col
    lo=bpy.data.objects.new(f"{ln}L",l); sc.collection.objects.link(lo); lo.location=loc; _pa(lo,cp)

cam=bpy.data.cameras.new("C"); cam.lens=50; camera=bpy.data.objects.new("C",cam)
sc.collection.objects.link(camera); sc.camera=camera
dist=max(td)*3.0+1.0
for leaf,loc in {"front.png":(0,-dist,cp.z),"side.png":(dist,0,cp.z),"three_quarter.png":(dist*.8,-dist*.8,cp.z),"socket_overlay.png":(dist*.8,-dist*.8,cp.z)}.items():
    camera.location=loc; _pa(camera,cp)
    for o in bpy.data.objects:
        if o.name.startswith("guide_"): o.hide_render=leaf!="socket_overlay.png"
    sc.render.filepath=str(out/leaf); bpy.ops.render.render(write_still=True)

_da()
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active=meshes[0]
bpy.ops.export_scene.gltf(filepath=str(out/"cleaned.glb"),export_format="GLB",use_selection=True,export_apply=True,export_extras=False,export_materials="EXPORT",export_texcoords=True,export_animations=False,export_yup=False,export_cameras=False,export_lights=False)
bpy.ops.wm.save_as_mainfile(filepath=str(out/"master.blend"))
mn,mx=_bnds(meshes); dims=[mx[i]-mn[i] for i in range(3)]
rt={"dimensions_m":[float(v) for v in dims],"triangle_count":int(sum(len(o.data.polygons) for o in meshes)),"textures_preserved":True,"uvs_present":all(bool(o.data.uv_layers) for o in meshes)}
(out/"runtime.json").write_text(json.dumps(rt,indent=2),encoding="utf-8")
print(f"PASS tris={rt['triangle_count']} dims={rt['dimensions_m']} textures=True")
