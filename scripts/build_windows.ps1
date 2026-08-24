# Builds the Rust GDExtension and installs the dll into the Godot addon.
# Run from anywhere: powershell -File scripts\build_windows.ps1 [-Debug]
param([switch]$Debug)

$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $cargoArgs = @("build", "-p", "derelict_godot")
    if (-not $Debug) { $cargoArgs += "--release" }
    $profileDir = if ($Debug) { "debug" } else { "release" }
    & cargo @cargoArgs
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }
    $dest = Join-Path $root "godot\addons\derelict\bin\win64"
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item (Join-Path $root "target\$profileDir\derelict_godot.dll") $dest -Force
    Write-Host "Installed derelict_godot.dll ($profileDir) -> $dest"
} finally {
    Pop-Location
}
