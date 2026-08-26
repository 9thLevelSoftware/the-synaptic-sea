[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^[0-9a-f]{40}$')] [string] $SourceCommit,
    [Parameter(Mandatory)] [ValidatePattern('^[0-9a-f]{64}$')] [string] $ContentHash,
    [ValidateSet('true', 'false')] [string] $Dirty = 'false',
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\..\..\addons\derelict\bin\web'),
    [string] $WasmBindgen = 'wasm-bindgen'
)
$ErrorActionPreference = 'Stop'
$worldgen = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('derelict-wasm-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $env:SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT = $SourceCommit
    $env:SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH = $ContentHash
    $env:SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT = $Dirty
    & cargo build --manifest-path (Join-Path $worldgen 'Cargo.toml') -p derelict_wasm --release --target wasm32-unknown-unknown
    if ($LASTEXITCODE -ne 0) { throw 'cargo wasm release build failed' }
    & $WasmBindgen (Join-Path $worldgen 'target\wasm32-unknown-unknown\release\derelict_wasm.wasm') --target nodejs --out-dir $stage
    if ($LASTEXITCODE -ne 0) { throw 'wasm-bindgen package generation failed' }
    $wasm = Join-Path $stage 'derelict_wasm_bg.wasm'
    $js = Join-Path $stage 'derelict_wasm.js'
    if (-not (Test-Path $wasm) -or -not (Test-Path $js)) { throw 'wasm-bindgen did not produce both package files' }
    $destination = (Resolve-Path $OutputDirectory -ErrorAction SilentlyContinue)
    if (-not $destination) { New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null; $destination = Resolve-Path $OutputDirectory }
    Copy-Item -LiteralPath $wasm -Destination (Join-Path $destination.Path 'derelict_wasm_bg.wasm') -Force
    Copy-Item -LiteralPath $js -Destination (Join-Path $destination.Path 'derelict_wasm.js') -Force
    Write-Output "WASM_PACKAGE: PASS $($destination.Path)"
}
finally {
    if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
