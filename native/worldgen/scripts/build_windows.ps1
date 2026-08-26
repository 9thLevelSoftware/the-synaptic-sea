# Builds the Rust GDExtension and installs the dll into the Godot addon.
# Run from anywhere: powershell -File scripts\build_windows.ps1 [-Debug] [-DestRepo <path>]
param(
    [switch]$Debug,
    [string]$DestRepo
)

$root = Split-Path $PSScriptRoot -Parent
$resolvedDestRepo = if ($DestRepo) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestRepo)
} else {
    $null
}
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
    $projectData = Join-Path $root "godot\.godot"
    $extensionList = Join-Path $projectData "extension_list.cfg"
    $extensionResource = "res://addons/derelict/derelict.gdextension"
    New-Item -ItemType Directory -Force $projectData | Out-Null
    $registeredExtensions = @()
    if (Test-Path -LiteralPath $extensionList -PathType Leaf) {
        $registeredExtensions = @(Get-Content -LiteralPath $extensionList | Where-Object { $_.Trim() })
    }
    $registeredExtensions = @($registeredExtensions + $extensionResource | Sort-Object -Unique)
    [System.IO.File]::WriteAllLines(
        $extensionList,
        [string[]]$registeredExtensions,
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "Installed derelict_godot.dll ($profileDir) -> $localBin"
    Write-Host "Registered DerelictGenerator addon -> $extensionList"

    if ($resolvedDestRepo) {
        $destAddon = Join-Path $resolvedDestRepo "addons\derelict"
        $destBin = Join-Path $destAddon "bin\win64"
        New-Item -ItemType Directory -Force $destBin | Out-Null
        Copy-Item $extensionSource $destAddon -Force
        Copy-Item $builtDll $destBin -Force
        Write-Host "Installed DerelictGenerator addon -> $destAddon"
    }
} finally {
    Pop-Location
}
