# Builds the Rust GDExtension and installs the dll into the Godot addon.
# Run from anywhere: powershell -File scripts\build_windows.ps1 [-Debug] [-DestRepo <path>]
param(
    [switch]$Debug,
    [string]$DestRepo
)

$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $cargoArgs = @("build", "-p", "derelict_godot")
    if (-not $Debug) { $cargoArgs += "--release" }
    $profileDir = if ($Debug) { "debug" } else { "release" }
    & cargo @cargoArgs
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }
    $builtDll = Join-Path $root "target\$profileDir\derelict_godot.dll"
    if (-not (Test-Path -LiteralPath $builtDll -PathType Leaf)) {
        throw "Missing expected native library: $builtDll"
    }

    $addonRoot = Join-Path $root "godot\addons\derelict"
    $extensionSource = Join-Path $addonRoot "derelict.gdextension"
    if (-not (Test-Path -LiteralPath $extensionSource -PathType Leaf)) {
        throw "Missing expected addon descriptor: $extensionSource"
    }

    $localBin = Join-Path $addonRoot "bin\win64"
    New-Item -ItemType Directory -Force $localBin | Out-Null
    Copy-Item $builtDll $localBin -Force
    Write-Host "Installed derelict_godot.dll ($profileDir) -> $localBin"

    if ($DestRepo) {
        $destAddon = Join-Path $DestRepo "addons\derelict"
        $destBin = Join-Path $destAddon "bin\win64"
        New-Item -ItemType Directory -Force $destBin | Out-Null
        Copy-Item $extensionSource $destAddon -Force
        Copy-Item $builtDll $destBin -Force
        Write-Host "Installed DerelictGenerator addon -> $destAddon"
    }
} finally {
    Pop-Location
}
