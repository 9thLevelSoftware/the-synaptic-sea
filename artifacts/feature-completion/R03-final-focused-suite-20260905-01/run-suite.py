import json, os, re, subprocess, sys, time
from pathlib import Path
root = Path(r"D:\the-synaptic-sea-feature-completion")
evidence = root / "artifacts/feature-completion/R03-final-focused-suite-20260905-01"
godot = Path(r"C:\Users\dasbl\Downloads\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe")
probe_script = "res://scripts/validation/fc_p10_process_smoke.gd"
cases = [
 ("arc-state", "electrical_arc_state_smoke.gd", "ARC STATE PASS ", False),
 ("fc-p10", "fc_p10_smoke.gd", "FC P10 PASS", False),
 ("fc-p13", "fc_p13_smoke.gd", "FC P13 PASS", False),
 ("migration-service", "save_migration_service_smoke.gd", "SAVE MIGRATION SERVICE PASS", False),
 ("migration-world", "save_migration_world_smoke.gd", "SAVE MIGRATION WORLD PASS ", False),
 ("save-load-service", "save_load_service_smoke.gd", "SAVE LOAD SERVICE PASS ", False),
 ("world-snapshot", "world_snapshot_smoke.gd", "WORLD SNAPSHOT PASS ", False),
 ("world-save", "world_save_service_smoke.gd", "WORLD SAVE SERVICE PASS ", False),
 ("ship-mod-run", "ship_mod_run_snapshot_smoke.gd", "SHIP MOD RUN SNAPSHOT PASS ", False),
 ("combat", "combat_persistence_smoke.gd", "COMBAT PERSISTENCE PASS ", False),
 ("ship-generator", "ship_generator_smoke.gd", "SHIP GENERATOR PASS ", False),
 ("manual-load", "main_playable_slice_save_load_smoke.gd", "MAIN PLAYABLE SAVE LOAD PASS ", False),
 ("quick-load", "main_playable_quicksave_smoke.gd", "MAIN PLAYABLE QUICKSAVE PASS ", False),
 ("auto-load", "main_playable_meta_autosave_smoke.gd", "MAIN PLAYABLE META AUTOSAVE PASS ", False),
 ("title-query", "title_save_query_smoke.gd", "TITLE SAVE QUERY PASS ", False),
 ("title-failure", "title_load_failure_smoke.gd", "TITLE LOAD FAILURE PASS ", True),
]
diag_re = re.compile(r"^(?:ERROR|WARNING|SCRIPT ERROR):.*$", re.M)
expected_title_diags = [
 "ERROR: PLAYABLE SHIP FAIL reason=smoke_forced_failure",
 "WARNING: TitleMain: gameplay boot failed (smoke_forced_failure) — returning to title",
]
results=[]
for name, script, marker_prefix, intentional in cases:
    case = evidence / name
    case.mkdir()
    home = case / "owned-user"
    home.mkdir()
    env=os.environ.copy()
    for key in ("APPDATA","LOCALAPPDATA","GODOT_USER_PATH","XDG_DATA_HOME"):
        env[key]=str(home)
    (case / "env.json").write_text(json.dumps({k:env[k] for k in ("APPDATA","LOCALAPPDATA","GODOT_USER_PATH","XDG_DATA_HOME")}, indent=2), encoding="utf-8")
    probe_cmd=[str(godot),"--headless","--path",str(root),"--log-file",str(case/"probe-godot.log"),"--user-data-dir",str(home),"--script",probe_script,"--","--mode=probe",f"--user_data={home}"]
    (case/"probe-command.json").write_text(json.dumps(probe_cmd,indent=2),encoding="utf-8")
    started=time.monotonic()
    try:
        probe=subprocess.run(probe_cmd,cwd=root,env=env,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=180,check=False)
        probe_timeout=False
    except subprocess.TimeoutExpired as ex:
        probe=subprocess.CompletedProcess(probe_cmd,124,ex.stdout or "",ex.stderr or "")
        probe_timeout=True
    (case/"probe-stdout.log").write_text(probe.stdout,encoding="utf-8")
    (case/"probe-stderr.log").write_text(probe.stderr,encoding="utf-8")
    probe_markers=[line for line in (probe.stdout+"\n"+probe.stderr).splitlines() if line.startswith("FC P10 USER DATA PROBE PASS resolved_user=")]
    probe_diags=diag_re.findall(probe.stdout+"\n"+probe.stderr)
    probe_ok=probe.returncode==0 and not probe_timeout and len(probe_markers)==1 and not probe_diags
    body_result=None
    if probe_ok:
        body_cmd=[str(godot),"--headless","--path",str(root),"--log-file",str(case/"body-godot.log"),"--user-data-dir",str(home),"--script",f"res://scripts/validation/{script}"]
        (case/"body-command.json").write_text(json.dumps(body_cmd,indent=2),encoding="utf-8")
        try:
            body=subprocess.run(body_cmd,cwd=root,env=env,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=180,check=False)
            body_timeout=False
        except subprocess.TimeoutExpired as ex:
            body=subprocess.CompletedProcess(body_cmd,124,ex.stdout or "",ex.stderr or "")
            body_timeout=True
        (case/"body-stdout.log").write_text(body.stdout,encoding="utf-8")
        (case/"body-stderr.log").write_text(body.stderr,encoding="utf-8")
        combined=body.stdout+"\n"+body.stderr
        marker_lines=[line for line in combined.splitlines() if line.startswith(marker_prefix)]
        diags=diag_re.findall(combined)
        diagnostics_ok=(diags==expected_title_diags) if intentional else not diags
        body_ok=body.returncode==0 and not body_timeout and len(marker_lines)==1 and diagnostics_ok
        body_result={"command":body_cmd,"exit_code":body.returncode,"timed_out":body_timeout,"marker_prefix":marker_prefix,"marker_lines":marker_lines,"marker_count":len(marker_lines),"diagnostics":diags,"intentional_injected_diagnostics":intentional,"expected_diagnostics":expected_title_diags if intentional else [],"diagnostics_classification":"expected loader-failure injection only" if intentional and diagnostics_ok else "clean" if diagnostics_ok else "unexpected diagnostics","stdout_bytes":len(body.stdout.encode()),"stderr_bytes":len(body.stderr.encode()),"passed":body_ok}
    passed=probe_ok and bool(body_result and body_result["passed"])
    result={"name":name,"script":script,"home":str(home),"environment":{k:env[k] for k in ("APPDATA","LOCALAPPDATA","GODOT_USER_PATH","XDG_DATA_HOME")},"probe":{"command":probe_cmd,"exit_code":probe.returncode,"timed_out":probe_timeout,"marker_count":len(probe_markers),"markers":probe_markers,"diagnostics":probe_diags,"passed":probe_ok},"body":body_result,"duration_seconds":round(time.monotonic()-started,6),"passed":passed}
    (case/"result.json").write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding="utf-8")
    results.append(result)
    print(f"{name} probe={probe_ok} body={bool(body_result and body_result['passed'])} exit={body_result['exit_code'] if body_result else 'SKIP'} marker={body_result['marker_count'] if body_result else 0} diag={len(body_result['diagnostics']) if body_result else 0}")
summary={"schema":"r03-final-focused-suite-1","root":str(root),"godot":str(godot),"timeout_seconds":180,"fresh_distinct_homes":len({r['home'] for r in results})==len(results),"all_four_environment_exact":all(len(set(r['environment'].values()))==1 and next(iter(r['environment'].values()))==r['home'] for r in results),"results":results,"passed":all(r['passed'] for r in results)}
(evidence/"summary.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding="utf-8")
print("R03 FINAL FOCUSED SUITE PASS" if summary["passed"] else "R03 FINAL FOCUSED SUITE FAIL")
sys.exit(0 if summary["passed"] else 1)
