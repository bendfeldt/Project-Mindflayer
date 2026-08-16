#requires -Version 7.4

[CmdletBinding()]
param(
    [switch]$Global,
    [switch]$Project,
    [switch]$Confirm,
    [switch]$Force,

    [Parameter(DontShow)]
    [switch]$Local
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CksumProof {
    param([Parameter(Mandatory)][string]$Path)
    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    [uint64]$crc = 0
    [uint64]$polynomial = 0x04C11DB7
    foreach ($byte in $bytes) {
        $crc = $crc -bxor ([uint64]$byte -shl 24)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 0x80000000) -ne 0) { $crc = (($crc -shl 1) -bxor $polynomial) -band ([uint64]4294967295) }
            else { $crc = ($crc -shl 1) -band ([uint64]4294967295) }
        }
    }
    [uint64]$length = $bytes.LongLength
    while ($length -ne 0) {
        $crc = $crc -bxor (($length -band 0xff) -shl 24)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 0x80000000) -ne 0) { $crc = (($crc -shl 1) -bxor $polynomial) -band ([uint64]4294967295) }
            else { $crc = ($crc -shl 1) -band ([uint64]4294967295) }
        }
        $length = $length -shr 8
    }
    $crc = (-bnot $crc) -band ([uint64]4294967295)
    return ('{0}:{1}' -f $crc, $bytes.LongLength)
}

function Write-LfFile {
    param([string]$Path, [AllowEmptyString()][string]$Content)
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function Get-BackupPath {
    param([string]$Path)
    $stamp = [DateTime]::Now.ToString('yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture)
    $candidate = "$Path.bak.$stamp"
    $suffix = 0
    while (Test-Path -LiteralPath $candidate) { $suffix++; $candidate = "$Path.bak.$stamp.$suffix" }
    return $candidate
}

function Test-JunctionTarget {
    param([string]$Path, [string]$Proof)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.LinkType -ne 'Junction') { return $false }
    return [IO.Path]::GetFullPath([string]$item.Target).Equals([IO.Path]::GetFullPath($Proof), [StringComparison]::OrdinalIgnoreCase)
}

function Test-PathWithinRoot {
    param([string]$Path, [string]$Root)
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-OwnedPath {
    param([string]$RecordedPath, [string]$Kind, [string]$BaseRoot, [string[]]$AllowedRoots)
    if (-not $RecordedPath -or $RecordedPath.Contains("`r") -or $RecordedPath.Contains("`n") -or $RecordedPath.Contains("`t")) {
        throw 'error: ownership record contains an invalid path'
    }
    $fullPath = if ([IO.Path]::IsPathRooted($RecordedPath)) {
        [IO.Path]::GetFullPath($RecordedPath)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $BaseRoot $RecordedPath))
    }
    foreach ($root in $AllowedRoots) {
        if (-not (Test-PathWithinRoot -Path $fullPath -Root $root)) { continue }
        $current = $fullPath
        $isLeaf = $true
        while ($current -and (Test-PathWithinRoot -Path $current -Root $root)) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
            if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and
                -not ($isLeaf -and $Kind -eq 'junction')) {
                throw "error: managed path crosses a reparse point: $current"
            }
            if ($current.TrimEnd([IO.Path]::DirectorySeparatorChar).Equals(
                [IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar),
                [StringComparison]::OrdinalIgnoreCase)) { break }
            $current = Split-Path -Parent $current
            $isLeaf = $false
        }
        return [pscustomobject]@{ FullPath = $fullPath; AllowedRoot = [IO.Path]::GetFullPath($root) }
    }
    throw "error: managed path is outside the allowed uninstall roots: $RecordedPath"
}

function Remove-EmptyParents {
    param([string]$Path, [string]$Stop)
    $stopPath = [IO.Path]::GetFullPath($Stop).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    while ($parent -and -not $parent.Equals($stopPath, [StringComparison]::OrdinalIgnoreCase)) {
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { $parent = Split-Path -Parent $parent; continue }
        if (@(Get-ChildItem -LiteralPath $parent -Force).Count -ne 0) { break }
        Remove-Item -LiteralPath $parent -Force
        $parent = Split-Path -Parent $parent
    }
}

try {
    if (-not $IsWindows -and -not $Local) {
        throw 'error: PowerShell uninstall is supported only on Windows; -Local is reserved for internal portable tests'
    }
    if ($Global -eq $Project) { throw 'error: specify exactly one of -Global or -Project' }
    $state = if ($Global) { Join-Path $HOME '.ai-toolkit/managed.tsv' } else { Join-Path (Get-Location).Path '.mindflayer-managed.tsv' }
    $baseRoot = if ($Global) { [IO.Path]::GetFullPath($HOME) } else { [IO.Path]::GetFullPath((Get-Location).Path) }
    $allowedRoots = if ($Global) {
        @('.ai-toolkit', '.claude', '.codex', '.gemini', '.cursor', '.copilot', '.agents') |
            ForEach-Object { Join-Path $HOME $_ }
    }
    else { @($baseRoot) }
    if (-not (Test-Path -LiteralPath $state -PathType Leaf)) { throw "error: ownership record not found: $state" }

    $stateItem = Get-Item -LiteralPath $state -Force
    if (($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "error: ownership record must not be a reparse point: $state"
    }
    $records = @(
        [IO.File]::ReadAllLines($state, [Text.Encoding]::UTF8) | ForEach-Object {
            if (-not $_) { return }
            $fields = $_.Split("`t", 3)
            if ($fields.Count -ne 3 -or -not @('file', 'junction', 'directory', 'line').Contains($fields[1])) {
                throw "error: invalid ownership record in $state"
            }
            $resolved = Resolve-OwnedPath -RecordedPath $fields[0] -Kind $fields[1] -BaseRoot $baseRoot -AllowedRoots $allowedRoots
            [pscustomobject]@{
                Path = $resolved.FullPath
                RecordedPath = $fields[0]
                AllowedRoot = $resolved.AllowedRoot
                Kind = $fields[1]
                Proof = $fields[2]
            }
        }
    )
    [array]::Reverse($records)
    $removed = 0
    $preserved = 0

    foreach ($record in $records) {
        $path = $record.Path
        if ($record.Kind -eq 'line') {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $lines = @([IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8))
            if ($lines -notcontains $record.Proof) { continue }
            if ($Confirm) {
                $remaining = @($lines | Where-Object { $_ -cne $record.Proof })
                if ($remaining.Count -eq 0) { Remove-Item -LiteralPath $path -Force }
                else { Write-LfFile $path (($remaining -join "`n") + "`n") }
                Write-Output " removed line: $($record.Proof) from $path"
            }
            else { Write-Output " remove line: $($record.Proof) from $path" }
            $removed++
            continue
        }

        if ($record.Kind -eq 'directory') {
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
            if (@(Get-ChildItem -LiteralPath $path -Force).Count -ne 0) {
                Write-Output " preserve: $path (not empty)"
                $preserved++
                continue
            }
            if ($Confirm) { Remove-Item -LiteralPath $path -Force; Write-Output " removed: $path" }
            else { Write-Output " remove: $path" }
            $removed++
            continue
        }

        if ($record.Kind -eq 'junction') {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            if (-not (Test-JunctionTarget $path $record.Proof)) {
                Write-Output " preserve: $path (junction target changed)"
                $preserved++
                continue
            }
        }
        elseif ($record.Kind -eq 'file') {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            if ((Get-CksumProof $path) -ne $record.Proof) {
                if (-not $Force) {
                    Write-Output " preserve: $path (modified)"
                    $preserved++
                    continue
                }
                if ($Confirm) {
                    $backup = Get-BackupPath $path
                    Copy-Item -LiteralPath $path -Destination $backup
                    Write-Output " backup: $backup"
                }
            }
        }
        else {
            Write-Output " preserve: $path (unknown ownership class)"
            $preserved++
            continue
        }

        if ($Confirm) {
            Remove-Item -LiteralPath $path -Force
            Write-Output " removed: $path"
            Remove-EmptyParents $path $record.AllowedRoot
        }
        else { Write-Output " would remove: $path" }
        $removed++
    }

    if ($Confirm -and $preserved -eq 0) {
        Remove-Item -LiteralPath $state -Force
        if ($Global) {
            $toolkitHome = Join-Path $HOME '.ai-toolkit'
            if ((Test-Path -LiteralPath $toolkitHome -PathType Container) -and @(Get-ChildItem -LiteralPath $toolkitHome -Force).Count -eq 0) {
                Remove-Item -LiteralPath $toolkitHome -Force
            }
        }
    }
    elseif ($Confirm) { Write-Output " ownership record retained for preserved artifacts: $state" }
    else { Write-Output " ownership record retained: $state" }
    Write-Output "Summary: $removed removable, $preserved preserved"
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
