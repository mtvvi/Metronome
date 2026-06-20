param(
    [Parameter(Mandatory = $true)]
    [string]$AutoEqRepositoryPath,

    [string]$PinnedCommit = "7ae0f56d53074872b028649617a22bbb4232feb7",

    [string]$OutputPath = "PlayerApp/Resources/AutoEq/generated/presets.json"
)

$ErrorActionPreference = "Stop"

Write-Host "AutoEq repository: $AutoEqRepositoryPath"
Write-Host "Pinned commit: $PinnedCommit"
Write-Host "Output path: $OutputPath"

throw "AutoEq dataset conversion is intentionally not implemented yet. Verify attribution and schema before generating bundled preset data."
