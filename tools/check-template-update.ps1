#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $configuredHome = if ($env:MINDFlAYER_HOME) { $env:MINDFlAYER_HOME } else { Join-Path $HOME '.ai-toolkit' }
    $template = Join-Path $configuredHome 'templates/AGENTS.md'
    if (-not (Test-Path -LiteralPath 'AGENTS.md' -PathType Leaf)) {
        Write-Output 'No AGENTS.md in current directory.'
        exit 1
    }
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "Template not found: $template" }

    $pattern = '<!--\s*template:\s*AGENTS\s*\|\s*version:\s*([^\s]+)\s*-->'
    $installedMatch = [regex]::Match([IO.File]::ReadAllText((Join-Path (Get-Location).Path 'AGENTS.md')), $pattern)
    if (-not $installedMatch.Success) {
        Write-Output 'AGENTS.md is not toolkit-template based.'
        exit 0
    }
    $availableMatch = [regex]::Match([IO.File]::ReadAllText($template), $pattern)
    $installed = $installedMatch.Groups[1].Value
    $available = if ($availableMatch.Success) { $availableMatch.Groups[1].Value } else { '' }
    Write-Output "Installed schema: $installed"
    Write-Output "Current schema:   $available"
    if ($installed -eq $available) { exit 0 }
    exit 1
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
