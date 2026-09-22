"""Create real Blender fixtures, not production assets, for parent validation."""
import bpy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.structural_visual_contract import load_dimensions, module_profile

OUT = Path(__file__).parent / 'parent-fixtures'
OUT.mkdir(exist_ok=True)
policy = load_dimensions()

def box(lo, hi):
    p=[(lo[0],lo[1],lo[2]),(hi[0],lo[1],lo[2]),(hi[0],hi[1],lo[2]),(lo[0],hi[1],lo[2]),
       (lo[0],lo[1],hi[2]),(hi[0],lo[1],hi[2]),(hi[0],hi[1],hi[2]),(lo[0],hi[1],hi[2])]
    faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]
    return [[p[a],p[b],p[c]] for q in faces for a,b,c in [(q[0],q[1],q[2]),(q[0],q[2],q[3])]]

def mesh(name, triangles, collection):
    data=bpy.data.meshes.new(name)
    # Actual native glTF axes, deliberately not the legacy source-helper mapping.
    coords=[(x,-z,y) for tri in triangles for x,y,z in tri]
    data.from_pydata(coords,[],[tuple(range(i,i+3)) for i in range(0,len(coords),3)])
    data.update()
    obj=bpy.data.objects.new(name,data)
    collection.objects.link(obj)
    return obj

records=[]
for mid in ['floor_1x1','floor_2x1','corridor_floor_1x1','corridor_floor_1x2',
            'wall_straight_1x1','doorway_frame_open_1x1','pillar_support_1x1']:
    profile=module_profile(mid,policy)
    if profile['family']=='doorway':
        triangles=box((-2,0,-.1),(-.6,3.2,.1))+box((.6,0,-.1),(2,3.2,.1))+box((-.6,2.2,-.1),(.6,3.2,.1))
    elif profile['family']=='pillar':
        triangles=box((-.25,0,-.25),(.25,3.2,.25))
    else:
        triangles=box(profile['bounds']['min'],profile['bounds']['max'])
    records.append((mid,mid,triangles,'pass',None))

floor=box((-2,-.25,-2),(2,0,2))
records += [
 ('raised_floor','floor_1x1',box((-2,-.25,-2),(2,.03,2)),'fail',None),
 ('wall_gap','wall_straight_1x1',box((-1.9,0,-.1),(1.9,3.1,.1))+box((-2,3.1,-.1),(2,3.2,.1)),'fail',None),
 ('thick_wall','wall_straight_1x1',box((-2,0,-.15),(2,3.2,.15)),'fail',None),
 ('leaked_helper','floor_1x1',floor,'fail','helper'),
 ('translated_floor','floor_1x1',floor,'fail','translated'),
 ('compensated_floor_origin','floor_1x1',floor,'fail','compensated'),
 ('blocked_doorway','doorway_frame_open_1x1',box((-2,0,-.1),(2,3.2,.1)),'fail',None),
 ('unsupported_ramp','ramp_up_1x2',floor,'hold',None),
]
manifest=[]
for label,mid,triangles,expected,extra in records:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    scene.unit_settings.system='METRIC'
    scene.unit_settings.scale_length=1
    scene['module_id']=mid
    collection=bpy.data.collections.new('Export_intact')
    collection['variant_role']='intact'
    scene.collection.children.link(collection)
    obj=mesh('Visual_'+label,triangles,collection)
    if extra=='helper':
        mesh('Collision_'+mid+'_Mesh',floor,collection)
    if extra=='translated':
        obj.location.x=.1
    if extra=='compensated':
        obj.location.x=.1
        for vertex in obj.data.vertices:
            vertex.co.x -= .1
    bpy.ops.object.select_all(action='DESELECT')
    for candidate in collection.objects:
        candidate.select_set(True)
    bpy.context.view_layer.objects.active=obj
    source=OUT/(label+'.blend')
    result=bpy.ops.wm.save_as_mainfile(filepath=str(source))
    assert 'FINISHED' in result
    glb=OUT/(label+'.glb')
    result=bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True)
    assert 'FINISHED' in result
    manifest.append(dict(label=label,module_id=mid,expected=expected,glb=str(glb),source=str(source)))
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PARENT_FIXTURES_CREATED',len(manifest))
