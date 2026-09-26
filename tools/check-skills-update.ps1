#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(DontShow)]
    [switch]$Local
)

& (Join-Path $PSScriptRoot 'skill-lifecycle.ps1') -Mode Check -Local:$Local
exit $LASTEXITCODE
