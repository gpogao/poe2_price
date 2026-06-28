param(
    [Parameter(Mandatory=$true)]
    [string]$ModifiedIndex,
    [Parameter(Mandatory=$true)]
    [string]$OutputDir
)

<#
.SYNOPSIS
Extract fog/viewdistance/minimap assets from a 易泥-modified game state.
Run this AFTER applying 易泥 with 去除迷雾 + 调整视距 + 小地图全开 options.

.DESCRIPTION
Uses BundleExtractor.exe to pull the 853 modified files from the game's
Bundles2 index and saves them into the 特效补丁/assets/ directory.
These assets are then used by update_effect_patch.ps1 when applying the
corresponding EffectScope options.

.PARAMETER ModifiedIndex
Path to the modified _.index.bin (after 易泥 has been applied).

.PARAMETER OutputDir
Path to 特效补丁/assets/ directory where extracted files will be saved.

.EXAMPLE
.\extract_assets.ps1 -ModifiedIndex "D:\game\PathOfExile2\Bundles2\_.index.bin" -OutputDir "D:\poe2_price\特效补丁\assets"
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AssetsDir = Resolve-Path -LiteralPath $OutputDir

# Find BundleExtractor
$BundleExtractor = $null
$Candidates = @(
    (Join-Path $ScriptDir "BundleExtractor.exe"),
    (Join-Path (Split-Path -Parent $ScriptDir) "..\build\BundleExtractor\bin\Release\net8.0\win-x64\BundleExtractor.exe"),
    (Join-Path $ScriptDir "..\..\build\BundleExtractor\bin\Release\net8.0\win-x64\BundleExtractor.exe")
)
foreach ($c in $Candidates) {
    if (Test-Path -LiteralPath $c -PathType Leaf) {
        $BundleExtractor = (Resolve-Path -LiteralPath $c).Path
        break
    }
}
if (-not $BundleExtractor) {
    throw "BundleExtractor.exe not found. Build it first: dotnet publish build\BundleExtractor\BundleExtractor.csproj -c Release -r win-x64 -p:SelfContained=true -p:PublishSingleFile=true"
}

Write-Host "BundleExtractor: $BundleExtractor" -ForegroundColor Cyan
Write-Host "Modified Index:  $ModifiedIndex" -ForegroundColor Cyan
Write-Host "Output:          $AssetsDir" -ForegroundColor Cyan

$IndexPath = Resolve-Path -LiteralPath $ModifiedIndex

# Asset scopes and their path list files
$AssetScopes = @{
    "fog"          = Join-Path $AssetsDir "fog_paths.txt"
    "viewdistance" = Join-Path $AssetsDir "viewdistance_paths.txt"
    "minimap"      = Join-Path $AssetsDir "minimap_paths.txt"
}

$TotalFiles = 0
$Extracted = 0
$Failed = @()

foreach ($scope in $AssetScopes.Keys) {
    $PathList = $AssetScopes[$scope]
    $ScopeDir = Join-Path $AssetsDir $scope

    if (-not (Test-Path -LiteralPath $PathList -PathType Leaf)) {
        Write-Warning "Path list not found: $PathList, skipping scope '$scope'"
        continue
    }

    Write-Host ""
    Write-Host "==> Extracting scope: $scope" -ForegroundColor Green

    $paths = Get-Content -LiteralPath $PathList | Where-Object { $_.Trim().Length -gt 0 }
    $TotalFiles += $paths.Count

    foreach ($path in $paths) {
        $cleanPath = $path.Trim()
        if ([string]::IsNullOrEmpty($cleanPath)) { continue }

        $relativePath = $cleanPath.Replace('\', '/')
        $outputFile = Join-Path $ScopeDir $relativePath
        $outputParent = Split-Path -Parent $outputFile
        if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
        }

        Write-Host "  $relativePath" -NoNewline
        try {
            $result = & $BundleExtractor $IndexPath $cleanPath $outputFile 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host " [OK]" -ForegroundColor Green
                $Extracted++
            } else {
                Write-Host " [FAILED]" -ForegroundColor Red
                $Failed += $cleanPath
            }
        } catch {
            Write-Host " [ERROR: $_]" -ForegroundColor Red
            $Failed += $cleanPath
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Extraction complete: $Extracted / $TotalFiles files extracted" -ForegroundColor Green

if ($Failed.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILED files ($($Failed.Count)):" -ForegroundColor Red
    $Failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

Write-Host ""
Write-Host "Assets ready in: $AssetsDir" -ForegroundColor Green
Write-Host "You can now use: -EffectScope fog,viewdistance,minimap" -ForegroundColor Cyan
