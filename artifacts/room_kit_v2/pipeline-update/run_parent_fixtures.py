"""Run the actual Blender CLI against parent-created positive/negative fixtures."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).parent
manifest=json.loads((HERE/'parent-fixtures/manifest.json').read_text())
env=os.environ.copy()
env['PYTHONPATH']=str(ROOT)
env['TMPDIR']=str(HERE/'tmp')
results=[]
for entry in manifest:
    report=HERE/'parent-fixtures'/(entry['label']+'.report.json')
    before={path:hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in (entry['source'],entry['glb'])}
    command=['/opt/homebrew/bin/blender','--background','--factory-startup','--python-exit-code','1',
             '--python',str(ROOT/'tools/validate_structural_visual_fit.py'),'--','--project-root',str(ROOT),
             '--module',entry['module_id'],'--glb',entry['glb'],'--report',str(report)]
    result=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,text=True,timeout=120)
    (HERE/'parent-fixtures'/(entry['label']+'.log')).write_text(result.stdout+result.stderr)
    data=json.loads(report.read_text()) if report.exists() else {'status':'missing-report','errors':[result.stderr]}
    unchanged=all(hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest for path,digest in before.items())
    passed=data['status']==entry['expected'] and (result.returncode==0)==(entry['expected']=='pass') and unchanged
    results.append(dict(label=entry['label'],module_id=entry['module_id'],expected=entry['expected'],actual=data['status'],
                        exit_code=result.returncode,source_and_glb_unchanged=unchanged,passed=passed,errors=data.get('errors',[])))
    print(entry['label'],data['status'],result.returncode,'OK' if passed else 'MISMATCH',flush=True)
(HERE/'parent-real-blender-results.json').write_text(json.dumps(results,indent=2)+'\n')
print('PARENT_REAL_BLENDER_RESULTS',json.dumps({'count':len(results),'passed':sum(row['passed'] for row in results)}))
raise SystemExit(0 if all(row['passed'] for row in results) else 1)
