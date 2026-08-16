#requires -Version 7.4

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force
)

& (Join-Path $PSScriptRoot 'skill-lifecycle.ps1') -Mode Sync -DryRun:$DryRun -Force:$Force
exit $LASTEXITCODE
