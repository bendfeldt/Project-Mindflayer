#requires -Version 7.4

[CmdletBinding()]
param()

& (Join-Path $PSScriptRoot 'skill-lifecycle.ps1') -Mode Check
exit $LASTEXITCODE
