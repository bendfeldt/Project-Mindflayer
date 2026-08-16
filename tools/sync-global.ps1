#requires -Version 7.4

[CmdletBinding()]
param()

Write-Output 'Global synchronization is replacement-sensitive.'
Write-Output 'Run install.ps1 -Global -Tools <explicit-list> -Force to back up and refresh selected consumers.'
