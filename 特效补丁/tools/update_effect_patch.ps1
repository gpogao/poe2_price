param(
    [string]$Poe2Dir = "",
    [switch]$NoInstall,
    [switch]$Restore,
    [string]$EffectScope = "all"
)

# Validate EffectScope (comma-separated, each token must be valid)
$ValidScopes = @("all", "easyfarm", "spells", "mtx", "monsters", "environment", "other", "fog", "viewdistance", "minimap")
foreach ($tok in $EffectScope -split ",") {
    $t = $tok.Trim()
    if ($t -and $t -notin $ValidScopes) {
        throw "Invalid EffectScope '$t'. Valid values: $($ValidScopes -join ', ')"
    }
}

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot "effect_patch_common.ps1")

$ToolsDir = $PSScriptRoot
$PatchRoot = Split-Path -Parent $ToolsDir
$OutDir = Join-Path $PatchRoot "output"
$EffectScript = Join-Path $ToolsDir "poe2_skill_effect_patch.py"

if ([string]::IsNullOrWhiteSpace($Poe2Dir)) {
    $Poe2Dir = Split-Path -Parent $PatchRoot
}
$Poe2Dir = (Resolve-Path -LiteralPath $Poe2Dir).Path

$GameMode = Get-EffectGameMode -Poe2Dir $Poe2Dir
$Bundles2Index = Join-Path $Poe2Dir "Bundles2\_.index.bin"
$BackupIndex = Join-Path $OutDir "backup\_.index.bin"

Write-Host "POE2 特效补丁" -ForegroundColor Green
Write-Host "游戏目录：$Poe2Dir"
Write-Host "游戏模式：$GameMode" -ForegroundColor Cyan
Write-Host "特效范围：$EffectScope" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $EffectScript -PathType Leaf)) {
    throw "Missing effect patch script: $EffectScript"
}

$Python = Resolve-EffectPython -ToolsDir $ToolsDir
if ([string]::IsNullOrWhiteSpace($Python)) {
    throw "No usable Python runtime found."
}

if ($GameMode -ne "Bundles2") {
    Write-Host "GGPK not yet supported" -ForegroundColor Yellow
    exit 1
}

# ── Build effect patch zip ──
Write-Host ""
Write-Host "==> 生成特效简化补丁" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$PatchZip = Join-Path $OutDir "特效补丁.zip"
$ReportJson = Join-Path $OutDir "effect_patch.report.json"

$EffectResult = Invoke-EffectPython -Python $Python -ArgumentList @(
    $EffectScript, "build",
    "--scope", $EffectScope,
    "--output-zip", $PatchZip,
    "--report", $ReportJson
)
if ($EffectResult.ExitCode -ne 0) {
    throw "Effect patch build failed. Exit code: $($EffectResult.ExitCode)"
}
Write-Host "已生成：$PatchZip" -ForegroundColor Green

if ($NoInstall) {
    Write-Host "已跳过写入游戏文件。" -ForegroundColor Yellow
    exit 0
}

# ── Restore ──
if ($Restore) {
    Write-Host ""
    Write-Host "==> 还原特效补丁" -ForegroundColor Cyan

    if (Test-Path -LiteralPath $BackupIndex -PathType Leaf) {
        Copy-Item -LiteralPath $BackupIndex -Destination $Bundles2Index -Force
        Write-Host "已还原索引备份" -ForegroundColor Green
    } else {
        Write-Warning "没有索引备份。请使用 Steam/Epic 验证游戏文件完整性。"
        exit 1
    }

    # Clean ZZZZZZZZ bundle
    $BundleDir = Join-Path $Poe2Dir "Bundles2\ZZZZZZZZ"
    if (Test-Path -LiteralPath $BundleDir -PathType Container) {
        Remove-Item -LiteralPath $BundleDir -Recurse -Force
        Write-Host "已删除 ZZZZZZZZ 补丁目录" -ForegroundColor Green
    }
    Write-Host "完成。" -ForegroundColor Green
    exit 0
}

# ── Install via PatchBundle3 (writes to ZZZZZZZZ/) ──
Write-Host ""
Write-Host "==> 写入特效补丁到 Bundles2" -ForegroundColor Cyan

# Backup index first (only if no clean backup exists)
$BackupDir = Join-Path $OutDir "backup"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
if (-not (Test-Path -LiteralPath $BackupIndex -PathType Leaf)) {
    Copy-Item -LiteralPath $Bundles2Index -Destination $BackupIndex -Force
    Write-Host "已备份原始索引" -ForegroundColor Green
} else {
    Write-Host "已有索引备份，跳过" -ForegroundColor Green
}

# ── Strip .ao files in-place (particle scopes only) ──
$AoPathsFile = Join-Path $OutDir "ao_paths.txt"
python3 -c @"
import sys; sys.path.insert(0, r'$ToolsDir')
from poe2_skill_effect_patch import _read_paths, _resolve_scopes, PARTICLE_SCOPES
scopes = [s for s in _resolve_scopes(r'$EffectScope') if s in PARTICLE_SCOPES]
paths = []
for s in scopes:
    for p in _read_paths(s):
        if p.endswith('.ao'):
            paths.append(p)
with open(r'$AoPathsFile', 'w') as f:
    f.write('\n'.join(paths))
print(f'{len(paths)} .ao paths written')
"@ 2>&1

$AoStripper = Join-Path $ToolsDir "StripAoEffects.exe"
if (Test-Path -LiteralPath $AoStripper -PathType Leaf) {
    Write-Host ""
    Write-Host "==> 清空 .ao 特效引用" -ForegroundColor Cyan
    $AoResult = & $AoStripper $Bundles2Index $AoPathsFile 2>&1
    $AoResult | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "StripAoEffects failed, continuing. Exit code: $LASTEXITCODE"
    }
} else {
    Write-Warning "StripAoEffects.exe not found, .ao files won't be stripped. Build it from LibGGPK3/Examples/StripAoEffects/"
}

$PatchExe = Join-Path $ToolsDir "PatchBundle3.exe"
if (-not (Test-Path -LiteralPath $PatchExe -PathType Leaf)) {
    throw "PatchBundle3.exe not found: $PatchExe"
}

Write-Host "工具: $PatchExe"
Write-Host "索引: $Bundles2Index"
Write-Host "补丁: $PatchZip"

$Output = & $PatchExe $Bundles2Index $PatchZip 2>&1
$ExitCode = $LASTEXITCODE
$Output | ForEach-Object { Write-Host $_ }

if ($ExitCode -ne 0) {
    throw "PatchBundle3 failed. Exit code: $ExitCode"
}

Write-Host ""
Write-Host "完成。" -ForegroundColor Green
