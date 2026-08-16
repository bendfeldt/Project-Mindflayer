#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $versionFile = Join-Path $HOME '.ai-toolkit/version'
    if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
        throw "error: version file not found: $versionFile"
    }
    $installed = ([System.IO.File]::ReadAllText($versionFile, [Text.Encoding]::UTF8)).Trim()
    if (-not $installed) { throw "error: version file is empty: $versionFile" }

    $headers = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)" }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/bendfeldt/Project-Mindflayer/releases/latest' -Headers $headers
    $latest = [string]$release.tag_name
    if (-not $latest) { throw 'error: release response has no tag_name' }

    Write-Output "Installed: $($installed.TrimStart('v'))"
    Write-Output "Latest: $($latest.TrimStart('v'))"
    if ($installed.TrimStart('v') -ne $latest.TrimStart('v')) {
        Write-Output 'Update with an explicit tool list:'
        Write-Output '  ~/.ai-toolkit/install.ps1 -Global -Tools <tools> -Force'
    }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
