[CmdletBinding()]
param(
    [string]$GodotPath = 'C:\Users\dasbl\Downloads\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe',
    [switch]$FullSuite
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $root 'project.godot'
if (-not (Test-Path -LiteralPath $project -PathType Leaf)) {
    throw "Repository root was not found at '$root'. Run this script from a Synaptic Sea worktree."
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot console executable was not found: $GodotPath"
}

# Every entry is a SceneTree runner. In particular, procgen_bundle_consumer.gd
# is preloaded by its diagnostic runner and must not be passed to --script.
$smokes = [System.Collections.Generic.List[object]]::new()
$smokes.Add([pscustomobject]@{ Name = 'procgen diagnostic bundle'; Script = 'procgen_diagnostic_bundle_smoke.gd'; Marker = 'PROCGEN DIAGNOSTIC BUNDLE PASS deterministic=true timing_capture=true caps=true privacy=true conflict=true live=true' })
$smokes.Add([pscustomobject]@{ Name = 'procgen promotion store'; Script = 'procgen_promotion_store_smoke.gd'; Marker = 'PROCGEN PROMOTION STORE PASS schema=true privacy=true conflict=true readback=true' })
$smokes.Add([pscustomobject]@{ Name = 'procgen seed lab graph view'; Script = 'procgen_seed_lab_graph_view_smoke.gd'; Marker = 'PROCGEN SEED LAB GRAPH VIEW PASS permutation=true malformed_rejected=true selection=true domains=7 clamp=true draw=true' })
$smokes.Add([pscustomobject]@{ Name = 'procgen seed lab model'; Script = 'procgen_seed_lab_model_smoke.gd'; Marker = 'PROCGEN SEED LAB MODEL PASS graphs=7 compare=true locks=13 selective=true isolation=true trace=true promotion=3 controller_exact_one=true failure_state=true live=true' })
$smokes.Add([pscustomobject]@{ Name = 'procgen seed lab scene'; Script = 'procgen_seed_lab_scene_smoke.gd'; Marker = 'PROCGEN SEED LAB SCENE PASS live_generation=true slots=2 compare=true graphs=7 locks=13 selective=true diagnostic=true promotion=true frame=true' })
$smokes.Add([pscustomobject]@{ Name = 'procgen regression corpus'; Script = 'procgen_regression_corpus_smoke.gd'; Marker = 'PROCGEN REGRESSION CORPUS PASS entries=3 classifications=3 diagnostics=true live=true' })
$smokes.Add([pscustomobject]@{ Name = 'procgen Gate 6 documents'; Script = 'procgen_gate6_documents_smoke.gd'; Marker = 'PROCGEN GATE6 DOCUMENTS PASS bundle=true single_execution=true replay=true loader=true start_scene=true no_temp_files=true' })
$smokes.Add([pscustomobject]@{ Name = 'procgen Gate 6 source'; Script = 'procgen_gate6_source_smoke.gd'; Marker = 'PROCGEN GATE6 SOURCE PASS sources=11 save_identity=true temp_dirs=true title_order=true' })
$smokes.Add([pscustomobject]@{ Name = 'procgen Gate 6 save replay'; Script = 'procgen_gate6_save_replay_smoke.gd'; Marker = 'PROCGEN GATE6 SAVE REPLAY PASS version=gate2-current-run-5 request=true hash=true paths_empty=true roundtrip=true replay=true mismatch_rejected=true new_world_required=true prompt=true clean_break=true' })
$smokes.Add([pscustomobject]@{ Name = 'worldgen wired travel'; Script = 'worldgen_wired_travel_smoke.gd'; Marker = 'WORLDGEN WIRED TRAVEL PASS cases=9 difficulty=deep_dive deterministic=true bundle_authoritative=true oracle_invocations=0' })
$smokes.Add([pscustomobject]@{ Name = 'top-down production bundle'; Script = 'topdown_e2e_smoke.gd'; Marker = 'E2E smoke: pass_count=16 failure_count=0' })
$smokes.Add([pscustomobject]@{ Name = 'title production bundle'; Script = 'title_screen_flow_smoke.gd'; Marker = 'TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true' })
$smokes.Add([pscustomobject]@{ Name = 'runtime bundle demo'; Script = 'procgen_runtime_demo_smoke.gd'; Marker = 'RUNTIME GAMEPLAY DEMO PASS objectives=3 interactions=3' })
$smokes.Add([pscustomobject]@{ Name = 'main production bundle contract'; Script = 'main_playable_derelict_pipeline_contract_smoke.gd'; Marker = 'MAIN PLAYABLE DERELICT PIPELINE CONTRACT PASS layout=true nav=true bundle_authoritative=true' })

if ($FullSuite) {
    # These are additional clean, self-contained procgen SceneTree runners.
	# Their negative cases are in-memory contract checks and are required to
	# remain silent; warning-producing migration/recovery smokes stay separate.
	$smokes.Add([pscustomobject]@{ Name = 'procgen build manifest'; Script = 'procgen_build_manifest_smoke.gd'; Marker = 'PROCGEN BUILD MANIFEST PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'procgen canonical JSON'; Script = 'task5_canonical_json_smoke.gd'; Marker = 'TASK5 CANONICAL JSON SMOKE PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'procgen bridge source'; Script = 'task5_bridge_source_smoke.gd'; Marker = 'TASK5 BRIDGE SOURCE PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'procgen live consumer'; Script = 'task5_live_consumer_smoke.gd'; Marker = 'TASK5 LIVE CONSUMER PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'procgen consumer contract'; Script = 'task5_consumer_negative_smoke.gd'; Marker = 'TASK5 CONSUMER PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'procgen mapper fixture'; Script = 'task5_mapper_fixture_smoke.gd'; Marker = 'TASK5 MAPPER PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'procgen live mapper parity'; Script = 'task5_live_mapper_parity_smoke.gd'; Marker = 'TASK5 LIVE MAPPER PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'procgen authored fallback'; Script = 'task5_fallback_policy_smoke.gd'; Marker = 'TASK5 FALLBACK PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'generated world contract'; Script = 'task8_generated_world_contract_matrix.gd'; Marker = 'TASK8_GENERATED_WORLD_CONTRACT_PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'generated world save'; Script = 'task8_generated_world_save_smoke.gd'; Marker = 'TASK8_GENERATED_WORLD_SAVE_PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'generated world file service'; Script = 'task8_generated_world_file_service_smoke.gd'; Marker = 'TASK8 GENERATED WORLD FILE SERVICE PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'portable settings store'; Script = 'task8_portable_settings_store_smoke.gd'; Marker = 'TASK8 PORTABLE SETTINGS STORE PASS' })
    $smokes.Add([pscustomobject]@{ Name = 'procgen adaptive trace'; Script = 'procgen_adaptive_trace_smoke.gd'; Marker = 'PROCGEN ADAPTIVE TRACE PASS' })
    $smokes.Add([pscustomobject]@{ Name = 'procgen player model request'; Script = 'procgen_player_model_request_smoke.gd'; Marker = 'PROCGEN PLAYER MODEL REQUEST PASS' })
    $smokes.Add([pscustomobject]@{ Name = 'procgen exact drop runtime'; Script = 'procgen_exact_drop_runtime_smoke.gd'; Marker = 'PROCGEN EXACT DROP RUNTIME PASS' })
    $smokes.Add([pscustomobject]@{ Name = 'procgen authoritative threat runtime'; Script = 'procgen_authoritative_threat_runtime_smoke.gd'; Marker = 'PROCGEN AUTHORITATIVE THREAT RUNTIME PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'procgen authoritative loot bridge'; Script = 'procgen_authoritative_loot_bridge_smoke.gd'; Marker = 'PROCGEN AUTHORITATIVE LOOT BRIDGE PASS' })
	$smokes.Add([pscustomobject]@{ Name = 'authored migration scenario'; Script = 'start_scenario_smoke.gd'; Marker = 'START_SCENARIO PASS' })
}

$logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("synaptic-sea-procgen-gate6-{0}.log" -f ([guid]::NewGuid().ToString('N')))
$failures = [System.Collections.Generic.List[string]]::new()
try {
    foreach ($smoke in $smokes) {
        $scriptPath = "res://scripts/validation/$($smoke.Script)"
        Write-Host "RUN $($smoke.Name): $scriptPath"
        $lines = @(& $GodotPath --headless --path $root --script $scriptPath 2>&1 | ForEach-Object { [string]$_ })
        $output = $lines -join [Environment]::NewLine
        [System.IO.File]::AppendAllText($logPath, ("--- $($smoke.Name) ---" + [Environment]::NewLine + $output + [Environment]::NewLine))

        if ($LASTEXITCODE -ne 0) {
            $failures.Add("$($smoke.Name): Godot exit code $LASTEXITCODE")
        }
        if ($output.IndexOf($smoke.Marker, [System.StringComparison]::Ordinal) -lt 0) {
            $failures.Add("$($smoke.Name): missing marker '$($smoke.Marker)'")
        }
        # Ordinal, case-sensitive checks are deliberate: lowercase diagnostic
        # text is not promoted to a release-blocking engine error by this gate.
        foreach ($line in $lines) {
            if ($line.Contains('ERROR:') -or $line.Contains('WARNING:') -or $line.Contains('FAIL') -or $line.Contains('BLOCKED')) {
                $failures.Add("$($smoke.Name): unexpected strict-scan line: $line")
            }
        }
        if ($failures.Count -eq 0 -or -not $failures[$failures.Count - 1].StartsWith("$($smoke.Name):")) {
            Write-Host "PASS $($smoke.Name)"
        }
    }
    if ($failures.Count -gt 0) {
        throw ($failures -join [Environment]::NewLine)
    }
    Write-Host ("PROCGEN GATE6 REGRESSION PASS smokes={0} full_suite={1}" -f $smokes.Count, $FullSuite.IsPresent)
}
finally {
    if (Test-Path -LiteralPath $logPath) {
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }
}
