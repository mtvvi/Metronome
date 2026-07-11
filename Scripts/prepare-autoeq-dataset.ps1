param(
    [Parameter(Mandatory = $true)]
    [string]$AutoEqRepositoryPath,

    [string]$PinnedCommit = "7ae0f56d53074872b028649617a22bbb4232feb7",

    [string]$OutputPath = "PlayerApp/Resources/AutoEq/headphone-presets.json"
)

$ErrorActionPreference = "Stop"

$Repository = (Resolve-Path -LiteralPath $AutoEqRepositoryPath).Path
$ActualCommit = (& git -C $Repository rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read the AutoEq repository revision."
}
if ($ActualCommit -ne $PinnedCommit) {
    throw "AutoEq revision mismatch. Expected $PinnedCommit, found $ActualCommit."
}

$ResultsPath = Join-Path $Repository "results"
if (-not (Test-Path -LiteralPath $ResultsPath -PathType Container)) {
    throw "AutoEq results directory was not found at $ResultsPath."
}

$Swift = Get-Command swift -ErrorAction SilentlyContinue
if ($null -eq $Swift) {
    throw "The Swift toolchain is required to build the AutoEq catalog. Run this script on macOS with Xcode installed."
}

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$Generator = Join-Path $PSScriptRoot "build_autoeq_catalog.swift"
$ResolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
} else {
    Join-Path $ProjectRoot $OutputPath
}
$OutputDirectory = Split-Path -Parent $ResolvedOutput
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

& $Swift.Source $Generator $ResultsPath $ResolvedOutput
if ($LASTEXITCODE -ne 0) {
    throw "AutoEq catalog generation failed with exit code $LASTEXITCODE."
}

Write-Host "Generated pinned AutoEq catalog at $ResolvedOutput"
