#requires -Version 7.4

[CmdletBinding()]
param(
    [string]$File,

    [Parameter(DontShow)]
    [switch]$ParseOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-StoreRegistry {
    param([Parameter(Mandatory)][string]$Path)

    $stores = [Collections.Generic.List[object]]::new()
    $current = $null
    $hasStoresHeader = $false
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
        $lineNumber++
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#', [StringComparison]::Ordinal)) { continue }
        if ($line -eq 'stores:') {
            if ($hasStoresHeader) { throw "error: duplicate stores key in $Path" }
            $hasStoresHeader = $true
            continue
        }
        if (-not $hasStoresHeader) { throw "error: expected stores key at $Path`:$lineNumber" }
        if ($line -match '^  - id:\s*([A-Za-z0-9][A-Za-z0-9_-]*)\s*$') {
            if ($null -ne $current) { $stores.Add([pscustomobject]$current) }
            $current = [ordered]@{ Id = $Matches[1]; Repository = ''; Type = ''; KnownVersion = '' }
            continue
        }
        if ($null -eq $current) { throw "error: expected store list item at $Path`:$lineNumber" }
        if ($line -match '^    repo:\s*([^\s]+/[^\s]+)\s*$') { $current.Repository = $Matches[1]; continue }
        if ($line -match '^    type:\s*(releases)\s*$') { $current.Type = $Matches[1]; continue }
        if ($line -match '^    known_version:\s*(\S+)\s*$') { $current.KnownVersion = $Matches[1]; continue }
        throw "error: unsupported stores.yml syntax at $Path`:$lineNumber"
    }
    if ($null -ne $current) { $stores.Add([pscustomobject]$current) }
    if (-not $hasStoresHeader -or $stores.Count -eq 0) { throw "error: no stores found in $Path" }

    $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($store in $stores) {
        if (-not $store.Repository -or -not $store.Type -or -not $store.KnownVersion) {
            throw "error: store '$($store.Id)' is missing repo, type, or known_version"
        }
        if (-not $seenIds.Add($store.Id)) { throw "error: duplicate store id '$($store.Id)'" }
    }
    return @($stores)
}

try {
    $storesFile = if ($File) {
        $File
    }
    elseif (Test-Path -LiteralPath './stores.yml' -PathType Leaf) {
        './stores.yml'
    }
    else {
        Join-Path $HOME '.ai-toolkit/stores.yml'
    }
    if (-not (Test-Path -LiteralPath $storesFile -PathType Leaf)) {
        throw "error: stores registry not found: $storesFile"
    }
    $stores = @(Read-StoreRegistry -Path $storesFile)
    Write-Output "Registry: $storesFile"
    if ($ParseOnly) {
        foreach ($store in $stores) {
            Write-Output ("{0}`t{1}`t{2}`t{3}" -f $store.Id, $store.Repository, $store.Type, $store.KnownVersion)
        }
        exit 0
    }

    $headers = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)" }
    $status = 0
    foreach ($store in $stores) {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$($store.Repository)/releases/latest" -Headers $headers
        $latest = [string]$release.tag_name
        if (-not $latest) { throw "error: release response for $($store.Id) has no tag_name" }
        Write-Output ("{0}: known={1} latest={2}" -f $store.Id, $store.KnownVersion, $latest)
        if ($latest -ne $store.KnownVersion) { $status = 1 }
    }
    exit $status
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
