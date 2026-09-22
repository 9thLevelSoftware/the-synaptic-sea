"""Exercise the real add-on export path without sacrificing unsaved work."""
import bpy
import hashlib
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT))
from tools.blender_addons.structural_module_toolkit.export import export_scene_to_staging

HERE=Path(__file__).parent
source=HERE/'parent-fixtures/floor_1x1.blend'
source_sha=hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(source))
marker=bpy.data.objects.new('ParentUnsavedArtistWork',None)
bpy.context.scene.collection.objects.link(marker)
marker['note']='unsaved source helper must survive'
bpy.context.scene['unsaved_pipeline_probe']='retain-me'
filepath=bpy.data.filepath
names=sorted(obj.name for obj in bpy.context.scene.objects)

def scene_unchanged():
    assert bpy.data.filepath==filepath,'active source path changed'
    assert sorted(obj.name for obj in bpy.context.scene.objects)==names,'unsaved object inventory lost'
    assert bpy.context.scene.get('unsaved_pipeline_probe')=='retain-me','unsaved scene data lost'
    assert bpy.data.objects['ParentUnsavedArtistWork']['note']=='unsaved source helper must survive'
    assert hashlib.sha256(source.read_bytes()).hexdigest()==source_sha,'source .blend was changed'

stage=HERE/'parent-addon-staging'
paths=export_scene_to_staging(bpy,stage,'floor_1x1')
scene_unchanged()
assert len(paths)==1
before=hashlib.sha256(paths[0].read_bytes()).hexdigest()
visual=bpy.data.objects['Visual_floor_1x1']
visual.data.vertices[0].co.z=.1
try:
    export_scene_to_staging(bpy,stage,'floor_1x1')
except (ValueError,RuntimeError) as exc:
    failure=str(exc)
else:
    raise AssertionError('invalid unsaved floor was accepted')
scene_unchanged()
assert abs(bpy.data.objects['Visual_floor_1x1'].data.vertices[0].co.z-.1)<1e-6,'unsaved mesh edit lost'
assert hashlib.sha256(paths[0].read_bytes()).hexdigest()==before,'invalid export replaced prior staging'
assert not list(paths[0].parent.glob('.*.tmp.glb')),'temporary GLBs leaked'
result={'status':'pass','valid_export_count':len(paths),'invalid_export_rejected':True,
        'source_file_unchanged':True,'unsaved_scene_and_mesh_preserved':True,
        'previous_staging_preserved':True,'rejection':failure}
(HERE/'parent-addon-state-results.json').write_text(json.dumps(result,indent=2)+'\n')
print('PARENT_ADDON_STATE_PASS',json.dumps(result))
