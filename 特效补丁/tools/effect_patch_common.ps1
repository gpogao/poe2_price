# effect_patch_common.ps1 — Shared helpers for the standalone effect patch tool.
# Self-contained; no dependency on 物价补丁/.

function Get-EffectPatchName {
    param([Parameter(Mandatory = $true)][string]$Name)

    switch ($Name) {
        "EffectPatchZip" {
            return [string]::Concat([char]0x7279, [char]0x6548, [char]0x8865, [char]0x4E01, ".zip")
        }
        default { throw "Unknown name: $Name" }
    }
}

function Test-EffectReleaseMode {
    return ($env:POE2_EFFECT_PATCH_RELEASE -eq "1")
}

# ─── Game detection ───────────────────────────────────────────────

function Get-EffectGameMode {
    param([Parameter(Mandatory = $true)][string]$Poe2Dir)

    $Bundles2Index = Join-Path $Poe2Dir "Bundles2\_.index.bin"
    $ContentGgpk = Join-Path $Poe2Dir "Content.ggpk"

    if (Test-Path -LiteralPath $Bundles2Index -PathType Leaf) {
        return "Bundles2"
    }
    elseif (Test-Path -LiteralPath $ContentGgpk -PathType Leaf) {
        return "GGPK"
    }
    throw "POE2 game not detected: $Poe2Dir (need Content.ggpk or Bundles2\_.index.bin)"
}

# ─── .NET 8 runtime ───────────────────────────────────────────────

function Test-EffectDotNet8Runtime {
    param([string]$DotnetPath)

    if ([string]::IsNullOrWhiteSpace($DotnetPath)) { return $false }
    if (-not (Test-Path -LiteralPath $DotnetPath -PathType Leaf)) { return $false }

    function Test-RuntimeDir {
        param([string]$Dir)
        if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return $false }
        foreach ($File in @("System.Private.CoreLib.dll", "System.Runtime.dll", "System.Collections.dll", "System.Console.dll")) {
            if (-not (Test-Path -LiteralPath (Join-Path $Dir $File) -PathType Leaf)) { return $false }
        }
        return $true
    }

    try {
        $Lines = & $DotnetPath --list-runtimes 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $DotnetRoot = Split-Path -Parent (Resolve-Path -LiteralPath $DotnetPath).Path
        $LocalRoot = Join-Path $DotnetRoot "shared\Microsoft.NETCore.App"
        if (Test-Path -LiteralPath $LocalRoot -PathType Container) {
            $Local = Get-ChildItem -LiteralPath $LocalRoot -Directory |
                Where-Object { $_.Name -match '^8\.' } |
                Sort-Object @{ Expression = { [version]$_.Name }; Descending = $true } |
                Select-Object -First 1
            if ($null -ne $Local -and (Test-RuntimeDir $Local.FullName)) { return $true }
        }
        foreach ($Line in $Lines) {
            if ($Line -match '^Microsoft\.NETCore\.App\s+(8\.[0-9]+\.[0-9]+)\s+\[(.+)\]$') {
                if (Test-RuntimeDir (Join-Path $Matches[2] $Matches[1])) { return $true }
            }
        }
        return $false
    }
    catch { return $false }
}

function Invoke-EffectDotNet {
    param(
        [Parameter(Mandatory = $true)][string]$Dotnet,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = "",
        [switch]$Quiet
    )

    $DotnetPath = (Resolve-Path -LiteralPath $Dotnet).Path
    $DotnetRoot = Split-Path -Parent $DotnetPath
    $OldRoot = $env:DOTNET_ROOT
    $OldLookup = $env:DOTNET_MULTILEVEL_LOOKUP
    $OldEA = $ErrorActionPreference
    $Pushed = $false
    try {
        $env:DOTNET_ROOT = $DotnetRoot
        $env:DOTNET_MULTILEVEL_LOOKUP = "0"
        $ErrorActionPreference = "Continue"
        if ($WorkingDirectory) { Push-Location -LiteralPath $WorkingDirectory; $Pushed = $true }
        $Output = & $DotnetPath @ArgumentList 2>&1
        $Code = $LASTEXITCODE
    }
    finally {
        if ($Pushed) { Pop-Location }
        $env:DOTNET_ROOT = $OldRoot
        $env:DOTNET_MULTILEVEL_LOOKUP = $OldLookup
        $ErrorActionPreference = $OldEA
    }
    $Lines = @($Output | ForEach-Object { [string]$_ })
    if (-not $Quiet) { foreach ($Line in $Lines) { Write-Host $Line } }
    return [pscustomobject]@{ ExitCode = $Code; Lines = $Lines; Text = ($Lines -join "`n") }
}

function Resolve-EffectDotNet8 {
    param([string]$ToolsDir)

    $Local = Join-Path $ToolsDir "dotnet-runtime\dotnet.exe"
    if (Test-EffectDotNet8Runtime $Local) { return $Local }

    if (Test-EffectReleaseMode) { return $null }

    $Sys = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $Sys -and (Test-EffectDotNet8Runtime $Sys.Source)) { return $Sys.Source }

    return $null
}

# ─── Python runtime ───────────────────────────────────────────────

function Invoke-EffectPython {
    param(
        [Parameter(Mandatory = $true)][string]$Python,
        [string[]]$ArgumentList = @(),
        [switch]$Quiet
    )
    $env:PYTHONIOENCODING = "utf-8"
    $env:PYTHONUTF8 = "1"
    $OldEA = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $Output = & $Python @ArgumentList 2>&1
        $Code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $OldEA }
    $Lines = @($Output | ForEach-Object { [string]$_ })
    if (-not $Quiet) { foreach ($Line in $Lines) { Write-Host $Line } }
    return [pscustomobject]@{ ExitCode = $Code; Lines = $Lines; Text = ($Lines -join "`n") }
}

function Test-EffectPythonPackages {
    param([string]$Python)
    $Result = Invoke-EffectPython -Python $Python -ArgumentList @("-c", "import json, zipfile, sys; print('ok')") -Quiet
    return ($Result.ExitCode -eq 0)
}

function Resolve-EffectPython {
    param([string]$ToolsDir)

    $Local = Join-Path $ToolsDir "python\python.exe"
    if ((Test-Path -LiteralPath $Local -PathType Leaf) -and (Test-EffectPythonPackages $Local)) {
        return $Local
    }

    $Sys = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $Sys -and (Test-EffectPythonPackages $Sys.Source)) {
        return $Sys.Source
    }

    return $null
}

# ─── Tool output helpers ──────────────────────────────────────────

function Test-PatchToolFailure {
    param([string]$Text)
    foreach ($Needle in @("FileNotFound", "Could not load", "Error", "Exception")) {
        if ($Text -match $Needle) { return $true }
    }
    return $false
}
