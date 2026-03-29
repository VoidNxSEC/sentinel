# Build Windows packages for voidnxlabs.
# Requires: Rust with x86_64-pc-windows-gnu target
#
# Usage:
#   $env:VERSION = "0.1.0"
#   .\packaging\windows\build.ps1
#
# Output: dist\windows\

param(
    [string]$Version = $env:VERSION ?? "0.1.0"
)

$ErrorActionPreference = "Stop"
$RepoRoot = git rev-parse --show-toplevel
$DistDir = Join-Path $RepoRoot "dist\windows"

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

function Log { param($msg) Write-Host "[windows] $msg" }

function Build-RustBin {
    param(
        [string]$Project,
        [string]$Binary
    )

    $projectPath = Join-Path $RepoRoot $Project
    if (-not (Test-Path $projectPath)) {
        Log "Skipping $Project — directory not found"
        return
    }

    Log "Building $Project ($Binary)..."
    Push-Location $projectPath
    try {
        # Cross-compile to Windows GNU target
        rustup target add x86_64-pc-windows-gnu 2>$null | Out-Null
        cargo build --release --target x86_64-pc-windows-gnu

        $exePath = "target\x86_64-pc-windows-gnu\release\$Binary.exe"
        if (Test-Path $exePath) {
            Copy-Item $exePath (Join-Path $DistDir "$Binary-$Version-x86_64.exe")
            Log "  -> dist\windows\$Binary-$Version-x86_64.exe"
        } else {
            Log "  WARN: expected $exePath not found"
        }
    } finally {
        Pop-Location
    }
}

# Build Rust services
Build-RustBin "ai-agent-os"      "ai-agent"
Build-RustBin "securellm-bridge" "securellm-bridge"
Build-RustBin "phantom-nx"       "phantom-nx"

# Create winget manifest directory
$wingetDir = Join-Path $DistDir "winget-manifests\VoidNxSEC.voidnxlabs\$Version"
New-Item -ItemType Directory -Force -Path $wingetDir | Out-Null

# Basic winget manifest
$manifest = @"
PackageIdentifier: VoidNxSEC.voidnxlabs
PackageVersion: $Version
PackageName: voidnxlabs
Publisher: VoidNxSEC
License: Apache-2.0
ShortDescription: voidnxlabs AI infrastructure and security tooling
PackageUrl: https://github.com/VoidNxSEC
Installers:
  - Architecture: x64
    InstallerType: portable
    InstallerUrl: https://github.com/VoidNxSEC/releases/download/v$Version/ai-agent-$Version-x86_64.exe
    InstallerSha256: PLACEHOLDER
ManifestType: singleton
ManifestVersion: 1.4.0
"@

$manifest | Out-File -Encoding utf8 (Join-Path $wingetDir "VoidNxSEC.voidnxlabs.yaml")

Log ""
Log "Windows artifacts:"
Get-ChildItem $DistDir -Recurse | Format-Table Name, Length -AutoSize
