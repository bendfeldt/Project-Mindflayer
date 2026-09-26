#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Check', 'Sync')]
    [string]$Mode,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Add,
    [string]$AddSkills,

    [Parameter(DontShow)]
    [switch]$Local
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-Lifecycle {
    param([Parameter(Mandatory)][string]$Message)
    throw "error: $Message"
}

function Test-PathWithinRoot {
    param([string]$Path, [string]$Root)
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-SafeProjectPath {
    param([string]$Path, [string]$ProjectRoot)
    $fullPath = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $ProjectRoot $Path))
    }
    if (-not (Test-PathWithinRoot -Path $fullPath -Root $ProjectRoot)) {
        Stop-Lifecycle "managed path is outside project: $Path"
    }
    $current = $fullPath
    while ($current -and (Test-PathWithinRoot -Path $current -Root $ProjectRoot)) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Stop-Lifecycle "managed path crosses a reparse point: $current"
        }
        if ($current.TrimEnd([IO.Path]::DirectorySeparatorChar).Equals(
            [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar),
            [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = Split-Path -Parent $current
    }
    return $fullPath
}

function Get-ToolkitHome {
    if ($env:MINDFLAYER_HOME) { return $env:MINDFLAYER_HOME }
    if ($env:MINDFlAYER_HOME) { return $env:MINDFlAYER_HOME }
    return Join-Path $HOME '.ai-toolkit'
}

function Get-BackupPath {
    param([Parameter(Mandatory)][string]$Path)
    $stamp = [DateTime]::Now.ToString('yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture)
    $candidate = "$Path.bak.$stamp"
    $suffix = 0
    while (Test-Path -LiteralPath $candidate) {
        $suffix++
        $candidate = "$Path.bak.$stamp.$suffix"
    }
    return $candidate
}

function Get-CksumProof {
    param([Parameter(Mandatory)][string]$Path)

    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    [uint64]$crc = 0
    [uint64]$polynomial = 0x04C11DB7
    foreach ($byte in $bytes) {
        $crc = $crc -bxor ([uint64]$byte -shl 24)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 0x80000000) -ne 0) {
                $crc = (($crc -shl 1) -bxor $polynomial) -band ([uint64]4294967295)
            }
            else {
                $crc = ($crc -shl 1) -band ([uint64]4294967295)
            }
        }
    }
    [uint64]$length = $bytes.LongLength
    while ($length -ne 0) {
        $crc = $crc -bxor (($length -band 0xff) -shl 24)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 0x80000000) -ne 0) {
                $crc = (($crc -shl 1) -bxor $polynomial) -band ([uint64]4294967295)
            }
            else {
                $crc = ($crc -shl 1) -band ([uint64]4294967295)
            }
        }
        $length = $length -shr 8
    }
    $crc = (-bnot $crc) -band ([uint64]4294967295)
    return ('{0}:{1}' -f $crc, $bytes.LongLength)
}

function Write-OwnershipState {
    param([string]$OwnershipPath, [AllowEmptyString()][string]$Content)
    $parent = Split-Path -Parent $OwnershipPath
    $temporaryPath = Join-Path $parent (".{0}.{1}.tmp" -f ([IO.Path]::GetFileName($OwnershipPath)), [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporaryPath, $Content, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $OwnershipPath, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Get-ManagedRoots {
    param([Parameter(Mandatory)][string]$OwnershipPath)

    $projectRoot = [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $projectPrefix = $projectRoot + [IO.Path]::DirectorySeparatorChar
    $roots = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $ownershipItem = Get-Item -LiteralPath $OwnershipPath -Force
    if (($ownershipItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Lifecycle "ownership record must not be a reparse point: $OwnershipPath"
    }

    foreach ($line in [IO.File]::ReadAllLines($OwnershipPath, [Text.Encoding]::UTF8)) {
        if (-not $line) { continue }
        $fields = $line.Split("`t", 3)
        if ($fields.Count -ne 3 -or -not @('file', 'junction', 'directory', 'line').Contains($fields[1])) {
            Stop-Lifecycle "invalid ownership record in $OwnershipPath"
        }
        [void](Assert-SafeProjectPath -Path $fields[0] -ProjectRoot $projectRoot)
        if ($fields[1] -ne 'file') { continue }
        $normalized = $fields[0].Replace('\', '/')
        if ($normalized -notmatch '^(.*?/skills)/[^/]+/SKILL\.md$') { continue }
        $recordedRoot = $Matches[1]
        $segments = $recordedRoot.Split('/')
        if ([IO.Path]::IsPathRooted($recordedRoot) -or $segments -contains '..' -or $segments -contains '.' -or -not $recordedRoot) {
            Stop-Lifecycle "unsafe managed skill root: $recordedRoot"
        }
        $nativeRoot = $recordedRoot.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $fullRoot = [IO.Path]::GetFullPath($nativeRoot)
        if (-not $fullRoot.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Stop-Lifecycle "unsafe managed skill root outside project: $fullRoot"
        }
        if ($seen.Add($fullRoot)) {
            $roots.Add([pscustomobject]@{
                    Path = $fullRoot
                    OwnershipPath = $nativeRoot
                })
        }
    }
    if ($roots.Count -eq 0) {
        Stop-Lifecycle "no managed skill roots found in $OwnershipPath"
    }
    return @($roots)
}

function Get-ManifestRows {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][ValidateSet('windows')][string]$Platform
    )

    $rows = [Collections.Generic.List[object]]::new()
    $seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $allowedTypes = @('baseline', 'decision', 'document', 'license', 'manifest', 'registry', 'script', 'setting', 'shim', 'skill', 'skill-resource', 'template')
    $allowedOwnership = @('managed-file', 'managed-tree')
    $allowedConsumers = @('global', 'global:claude', 'global:codex', 'global:copilot', 'global:cursor', 'global:gemini', 'project', 'project:claude', 'project:claude:databricks', 'project:claude:fabric', 'project:claude:terraform', 'project:gemini', 'project:skills')
    foreach ($line in [IO.File]::ReadAllLines($ManifestPath, [Text.Encoding]::UTF8)) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $fields = $line.Split("`t")
        if ($fields.Count -ne 6) { Stop-Lifecycle 'manifest must contain exactly six fields per row' }
        $manifestPathValue = $fields[0]
        if (-not $manifestPathValue -or [IO.Path]::IsPathRooted($manifestPathValue) -or $manifestPathValue.Contains('\') -or
            @($manifestPathValue.Split('/') | Where-Object { -not $_ -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
            Stop-Lifecycle "unsafe manifest path: $manifestPathValue"
        }
        if (-not $seenPaths.Add($manifestPathValue)) { Stop-Lifecycle "duplicate manifest path: $manifestPathValue" }
        $declaredConsumers = $fields[3].Split(',')
        if (-not $allowedTypes.Contains($fields[1]) -or -not $fields[2] -or
            $declaredConsumers -contains '' -or @($declaredConsumers | Sort-Object -Unique).Count -ne $declaredConsumers.Count -or
            @($declaredConsumers | Where-Object { -not $allowedConsumers.Contains($_) }).Count -gt 0 -or
            -not $allowedOwnership.Contains($fields[4])) {
            Stop-Lifecycle "invalid manifest metadata: $manifestPathValue"
        }
        $declaredPlatforms = $fields[5].Split(',')
        if ($declaredPlatforms.Count -eq 0 -or $declaredPlatforms -contains '' -or
            @($declaredPlatforms | Sort-Object -Unique).Count -ne $declaredPlatforms.Count -or
            @($declaredPlatforms | Where-Object { -not @('linux', 'macos', 'windows').Contains($_) }).Count -gt 0) {
            Stop-Lifecycle "invalid platforms in manifest: $manifestPathValue"
        }
        if (-not @('skill', 'skill-resource').Contains($fields[1])) { continue }
        if ($fields.Count -lt 6) {
            Stop-Lifecycle "missing platforms in manifest: $($fields[0])"
        }
        if (-not $fields[3].Split(',').Contains('project:skills')) { continue }
        $platforms = $fields[5].Split(',')
        if ($platforms.Count -eq 0 -or $platforms -contains '') {
            Stop-Lifecycle "invalid platforms in manifest: $($fields[0])"
        }
        if (@($platforms | Sort-Object -Unique).Count -ne $platforms.Count) {
            Stop-Lifecycle "duplicate platforms in manifest: $($fields[0])"
        }
        foreach ($declaredPlatform in $platforms) {
            if (-not @('linux', 'macos', 'windows').Contains($declaredPlatform)) {
                Stop-Lifecycle "invalid platform in manifest: $($fields[0]) ($declaredPlatform)"
            }
        }
        if (-not $platforms.Contains($Platform)) { continue }
        if ($fields[0] -notmatch '^skills/([^/]+)/(.+)$') {
            Stop-Lifecycle "unsafe manifest skill path: $($fields[0])"
        }
        $skillName = $Matches[1]
        $relativePath = $Matches[2]
        $segments = $relativePath.Split('/')
        if ($segments -contains '' -or $segments -contains '.' -or $segments -contains '..') {
            Stop-Lifecycle "unsafe manifest skill path: $($fields[0])"
        }
        if ($fields[1] -eq 'skill' -and $relativePath -ne 'SKILL.md') {
            Stop-Lifecycle "invalid skill entry in manifest: $($fields[0])"
        }
        $rows.Add([pscustomobject]@{
                Path = $fields[0]
                Type = $fields[1]
                Version = $fields[2]
                SkillName = $skillName
                RelativePath = $relativePath
            })
    }
    return @($rows)
}

function Get-SkillFiles {
    param(
        [Parameter(Mandatory)][object[]]$ManifestRows,
        [Parameter(Mandatory)][string]$SkillName
    )
    return @($ManifestRows | Where-Object SkillName -eq $SkillName)
}

function Test-ManifestFilesEqual {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][object[]]$Files
    )

    if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) { return $false }
    foreach ($file in $Files) {
        $relative = $file.RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $source = Join-Path $SourceRoot $relative
        $target = Join-Path $TargetRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            Stop-Lifecycle "manifest skill source not found: $source"
        }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { return $false }
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($sourceHash -cne $targetHash) { return $false }
    }
    return $true
}

function Set-FileOwnershipRecord {
    param(
        [Parameter(Mandatory)][string]$OwnershipPath,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Proof
    )

    $normalizedPath = $Path.Replace('\', '/')
    $remaining = @(
        foreach ($line in [IO.File]::ReadAllLines($OwnershipPath, [Text.Encoding]::UTF8)) {
            if (-not $line) { continue }
            $fields = $line.Split("`t", 3)
            if ($fields.Count -eq 3 -and $fields[0].Replace('\', '/').Equals($normalizedPath, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $line
        }
    )
    $remaining += "$Path`tfile`t$Proof"
    $content = ($remaining -join "`n") + "`n"
    Write-OwnershipState -OwnershipPath $OwnershipPath -Content $content
}

function Remove-FileOwnershipRecord {
    param([string]$OwnershipPath, [string]$RecordedPath)
    $normalizedPath = $RecordedPath.Replace('\', '/')
    $remaining = @(
        foreach ($line in [IO.File]::ReadAllLines($OwnershipPath, [Text.Encoding]::UTF8)) {
            if (-not $line) { continue }
            $fields = $line.Split("`t", 3)
            if ($fields.Count -eq 3 -and $fields[0].Replace('\', '/').Equals($normalizedPath, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $line
        }
    )
    $content = if ($remaining.Count -gt 0) { ($remaining -join "`n") + "`n" } else { '' }
    Write-OwnershipState -OwnershipPath $OwnershipPath -Content $content
}

function Get-ObsoleteSkillRecords {
    param(
        [string]$OwnershipPath,
        [string]$TargetRoot,
        [string]$OwnershipRoot,
        [object[]]$ManifestRows
    )
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $ManifestRows) {
        $skillRelativePath = Join-Path $file.SkillName $file.RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        [void]$expected.Add([IO.Path]::GetFullPath((Join-Path $TargetRoot $skillRelativePath)))
    }
    $projectRoot = [IO.Path]::GetFullPath((Get-Location).Path)
    $fullTargetRoot = [IO.Path]::GetFullPath($TargetRoot)
    foreach ($line in [IO.File]::ReadAllLines($OwnershipPath, [Text.Encoding]::UTF8)) {
        if (-not $line) { continue }
        $fields = $line.Split("`t", 3)
        if ($fields.Count -ne 3 -or $fields[1] -ne 'file') { continue }
        $recorded = $fields[0].Replace('\', '/')
        $ownershipPrefix = $OwnershipRoot.Replace('\', '/').TrimEnd('/') + '/'
        if (-not $recorded.StartsWith($ownershipPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $fullPath = Assert-SafeProjectPath -Path $fields[0] -ProjectRoot $projectRoot
        if ((Test-PathWithinRoot -Path $fullPath -Root $fullTargetRoot) -and -not $expected.Contains($fullPath)) {
            [pscustomobject]@{ RecordedPath = $fields[0]; FullPath = $fullPath; Proof = $fields[2] }
        }
    }
}

function Copy-ManifestSkillFiles {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$OwnershipRoot,
        [Parameter(Mandatory)][string]$OwnershipPath,
        [Parameter(Mandatory)][object[]]$Files
    )

    foreach ($file in $Files) {
        $relative = $file.RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $source = Join-Path $SourceRoot $relative
        $target = Join-Path $TargetRoot $relative
        $recordedTarget = Join-Path $OwnershipRoot $relative
        $parent = Split-Path -Parent $target
        [IO.Directory]::CreateDirectory($parent) | Out-Null
        $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if ($null -ne $existing -and $existing.PSIsContainer) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
        Set-FileOwnershipRecord -OwnershipPath $OwnershipPath -Path $recordedTarget -Proof (Get-CksumProof $target)
    }
}

$script:UseColor = (-not [Console]::IsOutputRedirected) -and (-not $env:NO_COLOR) -and ($env:TERM -ne 'dumb')
$script:Migrations = [Collections.Generic.List[object]]::new()

function Format-Color {
    param([Parameter(Mandatory)][string]$Code, [AllowEmptyString()][string]$Text)
    if ($script:UseColor) { return "`e[$($Code)m$Text`e[0m" }
    return $Text
}

function Get-NormalizedText {
    param([Parameter(Mandatory)][string]$Path)
    return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Split-TextLines {
    param([AllowEmptyString()][string]$Text)
    if (-not $Text) { return , @() }
    $lines = $Text.Split("`n")
    if ($Text.EndsWith("`n")) { $lines = $lines[0..($lines.Count - 2)] }
    return , @($lines)
}

function Format-DiffRange {
    param([int]$Start, [int]$Count)
    if ($Count -eq 0) { return '{0},0' -f ($Start - 1) }
    if ($Count -eq 1) { return '{0}' -f $Start }
    return '{0},{1}' -f $Start, $Count
}

# Unified diff (3 lines of context) in the format of `diff -u`: deletions are
# listed before insertions and nearby changes share one hunk.
function Get-UnifiedDiff {
    param(
        [AllowEmptyCollection()][string[]]$OldLines,
        [AllowEmptyCollection()][string[]]$NewLines,
        [Parameter(Mandatory)][string]$OldLabel,
        [Parameter(Mandatory)][string]$NewLabel
    )
    $old = @($OldLines)
    $new = @($NewLines)
    $prefix = 0
    while ($prefix -lt $old.Count -and $prefix -lt $new.Count -and $old[$prefix] -ceq $new[$prefix]) { $prefix++ }
    $suffix = 0
    while ($suffix -lt ($old.Count - $prefix) -and $suffix -lt ($new.Count - $prefix) -and
        $old[$old.Count - 1 - $suffix] -ceq $new[$new.Count - 1 - $suffix]) { $suffix++ }
    $oldMiddle = $old.Count - $prefix - $suffix
    $newMiddle = $new.Count - $prefix - $suffix
    if ($oldMiddle -eq 0 -and $newMiddle -eq 0) { return @() }

    # lcs[i, j] = longest common subsequence of old[i..] and new[j..] within the middle.
    $lcs = [int[, ]]::new($oldMiddle + 1, $newMiddle + 1)
    for ($i = $oldMiddle - 1; $i -ge 0; $i--) {
        for ($j = $newMiddle - 1; $j -ge 0; $j--) {
            if ($old[$prefix + $i] -ceq $new[$prefix + $j]) { $lcs[$i, $j] = $lcs[($i + 1), ($j + 1)] + 1 }
            elseif ($lcs[($i + 1), $j] -ge $lcs[$i, ($j + 1)]) { $lcs[$i, $j] = $lcs[($i + 1), $j] }
            else { $lcs[$i, $j] = $lcs[$i, ($j + 1)] }
        }
    }
    $ops = [Collections.Generic.List[object]]::new()
    for ($k = 0; $k -lt $prefix; $k++) { $ops.Add([pscustomobject]@{ Op = ' '; Text = $old[$k]; Old = $k; New = $k }) }
    $i = 0; $j = 0
    while ($i -lt $oldMiddle -or $j -lt $newMiddle) {
        if ($i -lt $oldMiddle -and $j -lt $newMiddle -and $old[$prefix + $i] -ceq $new[$prefix + $j]) {
            $ops.Add([pscustomobject]@{ Op = ' '; Text = $old[$prefix + $i]; Old = $prefix + $i; New = $prefix + $j }); $i++; $j++
        }
        elseif ($j -ge $newMiddle -or ($i -lt $oldMiddle -and $lcs[($i + 1), $j] -ge $lcs[$i, ($j + 1)])) {
            $ops.Add([pscustomobject]@{ Op = '-'; Text = $old[$prefix + $i]; Old = $prefix + $i; New = $prefix + $j }); $i++
        }
        else {
            $ops.Add([pscustomobject]@{ Op = '+'; Text = $new[$prefix + $j]; Old = $prefix + $i; New = $prefix + $j }); $j++
        }
    }
    for ($k = 0; $k -lt $suffix; $k++) {
        $ops.Add([pscustomobject]@{ Op = ' '; Text = $old[$old.Count - $suffix + $k]; Old = $old.Count - $suffix + $k; New = $new.Count - $suffix + $k })
    }

    $context = 3
    $changes = @(for ($k = 0; $k -lt $ops.Count; $k++) { if ($ops[$k].Op -ne ' ') { $k } })
    $output = [Collections.Generic.List[string]]::new()
    $output.Add("--- $OldLabel")
    $output.Add("+++ $NewLabel")
    $index = 0
    while ($index -lt $changes.Count) {
        $first = $changes[$index]
        $last = $first
        while ($index + 1 -lt $changes.Count -and ($changes[$index + 1] - $last) -le (2 * $context + 1)) {
            $index++
            $last = $changes[$index]
        }
        $start = [Math]::Max(0, $first - $context)
        $end = [Math]::Min($ops.Count - 1, $last + $context)
        $oldCount = 0; $newCount = 0
        $oldStart = $null; $newStart = $null
        for ($k = $start; $k -le $end; $k++) {
            $op = $ops[$k]
            if ($op.Op -ne '+') { if ($null -eq $oldStart) { $oldStart = $op.Old + 1 }; $oldCount++ }
            if ($op.Op -ne '-') { if ($null -eq $newStart) { $newStart = $op.New + 1 }; $newCount++ }
        }
        if ($null -eq $oldStart) { $oldStart = $ops[$start].Old + 1 }
        if ($null -eq $newStart) { $newStart = $ops[$start].New + 1 }
        $output.Add(('@@ -{0} +{1} @@' -f (Format-DiffRange $oldStart $oldCount), (Format-DiffRange $newStart $newCount)))
        for ($k = $start; $k -le $end; $k++) { $output.Add($ops[$k].Op + $ops[$k].Text) }
        $index++
    }
    return $output.ToArray()
}

function Write-Diff {
    param([string]$LocalPath, [string]$ReleasePath, [string]$Label, [string]$LocalDescription, [string]$ReleaseDescription)
    $item = Get-Item -LiteralPath $LocalPath -Force -ErrorAction SilentlyContinue
    $localText = if ($null -ne $item -and -not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
        Get-NormalizedText $LocalPath
    }
    else { '' }
    $lines = Get-UnifiedDiff -OldLines (Split-TextLines $localText) -NewLines (Split-TextLines (Get-NormalizedText $ReleasePath)) `
        -OldLabel "$Label ($LocalDescription)" -NewLabel "$Label ($ReleaseDescription)"
    foreach ($line in $lines) {
        if ($line.StartsWith('--- ') -or $line.StartsWith('+++ ')) { Write-Output (Format-Color '1' $line) }
        elseif ($line.StartsWith('@@')) { Write-Output (Format-Color '36' $line) }
        elseif ($line.StartsWith('-')) { Write-Output (Format-Color '31' $line) }
        elseif ($line.StartsWith('+')) { Write-Output (Format-Color '32' $line) }
        else { Write-Output $line }
    }
}

function Get-FileOwnershipProof {
    param([string]$OwnershipPath, [string]$FullPath)
    foreach ($line in [IO.File]::ReadAllLines($OwnershipPath, [Text.Encoding]::UTF8)) {
        if (-not $line) { continue }
        $fields = $line.Split("`t", 3)
        if ($fields.Count -ne 3 -or $fields[1] -ne 'file') { continue }
        $recorded = if ([IO.Path]::IsPathRooted($fields[0])) { [IO.Path]::GetFullPath($fields[0]) } else { [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $fields[0])) }
        if ($recorded.Equals([IO.Path]::GetFullPath($FullPath), [StringComparison]::OrdinalIgnoreCase)) { return $fields[2] }
    }
    return $null
}

# new | current | update (unchanged since install) | local (edited) | unmanaged
function Get-SkillFileState {
    param([string]$OwnershipPath, [string]$Target, [string]$Source)
    $item = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'new' }
    $proof = Get-FileOwnershipProof -OwnershipPath $OwnershipPath -FullPath $Target
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($null -ne $proof) { return 'local' } else { return 'unmanaged' }
    }
    if ((Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -ceq (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash) { return 'current' }
    if ($null -eq $proof) { return 'unmanaged' }
    if ((Get-CksumProof $Target) -eq $proof) { return 'update' }
    return 'local'
}

function Get-AvailableSkills {
    param([object[]]$ManifestRows)
    return @($ManifestRows | Where-Object Type -eq 'skill' | ForEach-Object SkillName)
}

# The selection is declared in AGENTS.md ("- **skills:** a, b" or "none").
# Without that line every skill is selected, which matches earlier releases.
function Get-SkillSelection {
    param([string]$AgentsPath, [string[]]$Available)
    if (-not (Test-Path -LiteralPath $AgentsPath -PathType Leaf)) { return , @($Available) }
    $match = [regex]::Match((Get-NormalizedText $AgentsPath), '(?m)^\s*- \*\*skills:\*\*(.*)$')
    if (-not $match.Success) { return , @($Available) }
    $value = $match.Groups[1].Value -replace '\s', ''
    if (-not $value -or $value -eq 'none') { return , @() }
    $kept = foreach ($token in $value.Split(',')) {
        if (-not $token) { continue }
        if ($Available -contains $token) { $token }
        else { [Console]::Error.WriteLine("! AGENTS.md selects skill '$token', which this release does not provide; ignoring it") }
    }
    return , @($Available | Where-Object { @($kept) -contains $_ })
}

function Set-SkillsLineText {
    param([string]$Text, [string[]]$Selection, [string[]]$Available)
    $remove = (@($Selection) -join ',') -ceq (@($Available) -join ',')
    $value = if (@($Selection).Count -eq 0) { 'none' } else { @($Selection) -join ', ' }
    $line = "- **skills:** $value"
    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]$Text.Split("`n"))
    $trailing = $Text.EndsWith("`n")
    if ($trailing) { $lines.RemoveAt($lines.Count - 1) }
    $existing = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*- \*\*skills:\*\*') { $existing = $i; break } }
    if ($existing -ge 0) {
        if ($remove) { $lines.RemoveAt($existing) } else { $lines[$existing] = $line }
    }
    elseif (-not $remove) {
        $anchor = -1
        $inIdentity = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^##\s+Repository identity\s*$') { $inIdentity = $true; continue }
            if ($inIdentity -and $lines[$i].StartsWith('## ')) { break }
            if ($inIdentity -and $lines[$i] -match '^- \*\*[^*]+:\*\*') { $anchor = $i }
        }
        if ($anchor -lt 0) {
            for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains('<!-- template: AGENTS ')) { $anchor = $i; break } }
        }
        if ($anchor -lt 0) { Stop-Lifecycle 'could not update the skills line in AGENTS.md' }
        $lines.Insert($anchor + 1, $line)
    }
    $result = $lines -join "`n"
    if ($trailing) { $result += "`n" }
    return $result
}

function Get-SkillDescription {
    param([string]$SourceRoot, [string]$SkillName)
    $yaml = Join-Path (Join-Path $SourceRoot $SkillName) 'agents/openai.yaml'
    if (-not (Test-Path -LiteralPath $yaml -PathType Leaf)) { return '' }
    $match = [regex]::Match((Get-NormalizedText $yaml), '(?m)^\s*short_description:\s*"(.*)"\s*$')
    if ($match.Success) { return $match.Groups[1].Value }
    return ''
}

function Read-SkillsToAdd {
    param([string[]]$Candidates, [object[]]$Skills, [string]$SourceRoot)
    $names = @($Candidates)
    $marks = [bool[]]::new($names.Count)
    while ($true) {
        Write-Host ''
        Write-Host 'Add skills to this project'
        Write-Host ('         {0,-22} {1,-8} {2}' -f 'Skill', 'Release', 'Description')
        for ($i = 0; $i -lt $names.Count; $i++) {
            $mark = if ($marks[$i]) { '[x]' } else { '[ ]' }
            $version = ($Skills | Where-Object SkillName -eq $names[$i] | Select-Object -First 1).Version
            Write-Host ('  {0} {1,2} {2,-22} {3,-8} {4}' -f $mark, ($i + 1), $names[$i], $version, (Get-SkillDescription $SourceRoot $names[$i]))
        }
        Write-Host ''
        Write-Host 'Toggle with numbers or names (e.g. "1 3-4"), a = all, n = none,'
        Write-Host 'Enter = continue, q = cancel without changes.'
        [Console]::Write('> ')
        $inputLine = [Console]::ReadLine()
        if ($null -eq $inputLine) { Stop-Lifecycle 'input closed; nothing was changed' }
        $inputLine = $inputLine.Replace(',', ' ').Trim()
        if (-not $inputLine) { break }
        $lower = $inputLine.ToLowerInvariant()
        if (@('q', 'quit', 'cancel').Contains($lower)) { Stop-Lifecycle 'cancelled; nothing was changed' }
        if (@('a', 'all').Contains($lower)) { for ($i = 0; $i -lt $names.Count; $i++) { $marks[$i] = $true }; continue }
        if (@('n', 'none').Contains($lower)) { for ($i = 0; $i -lt $names.Count; $i++) { $marks[$i] = $false }; continue }
        foreach ($token in ($inputLine -split '\s+')) {
            if ($token -match '^(\d+)-(\d+)$') {
                $start = [int]$Matches[1]; $end = [int]$Matches[2]
                if ($start -lt 1 -or $end -gt $names.Count -or $start -gt $end) { Write-Host "Ignored '$token': choose numbers from 1 to $($names.Count)."; continue }
                for ($i = $start - 1; $i -lt $end; $i++) { $marks[$i] = -not $marks[$i] }
            }
            elseif ($token -match '^\d+$') {
                $number = [int]$token
                if ($number -lt 1 -or $number -gt $names.Count) { Write-Host "Ignored '$token': choose numbers from 1 to $($names.Count)."; continue }
                $marks[$number - 1] = -not $marks[$number - 1]
            }
            else {
                $position = [array]::IndexOf($names, $token)
                if ($position -lt 0) { Write-Host "Ignored '$token': not a number or skill name in the list."; continue }
                $marks[$position] = -not $marks[$position]
            }
        }
    }
    return , @(for ($i = 0; $i -lt $names.Count; $i++) { if ($marks[$i]) { $names[$i] } })
}

function Add-SkillsToSelection {
    param([string]$AgentsPath, [string[]]$Available, [string[]]$Selection, [object[]]$Skills, [string]$SourceRoot, [string]$OwnershipPath)
    if (-not (Test-Path -LiteralPath $AgentsPath -PathType Leaf) -or -not (Get-NormalizedText $AgentsPath).Contains('<!-- template: AGENTS ')) {
        Stop-Lifecycle 'AGENTS.md is missing or not toolkit-managed; add skills with install.ps1 -Project -Skills LIST'
    }
    $candidates = @($Available | Where-Object { @($Selection) -notcontains $_ })
    $requested = [Collections.Generic.List[string]]::new()
    if ($AddSkills) {
        foreach ($token in ($AddSkills -replace '\s', '').Split(',')) {
            if (-not $token) { Stop-Lifecycle '-Add contains an empty value' }
            if ($Available -notcontains $token) { Stop-Lifecycle "unknown skill '$token'; available skills: $($Available -join ', ')" }
            if (@($Selection) -contains $token) { Write-Output "= $token is already selected"; continue }
            if (-not $requested.Contains($token)) { $requested.Add($token) }
        }
    }
    elseif ($candidates.Count -eq 0) {
        Write-Output 'All available skills are already selected.'
    }
    elseif (-not $env:MINDFLAYER_NONINTERACTIVE -and -not $env:CI -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
        foreach ($name in (Read-SkillsToAdd -Candidates $candidates -Skills $Skills -SourceRoot $SourceRoot)) { $requested.Add($name) }
    }
    else {
        Stop-Lifecycle "-Add without skill names needs a terminal to choose from. Available: $($candidates -join ', '). Use -Add NAME[,NAME]"
    }
    # Output from this function is user-facing text, so the new selection is
    # stored in script scope rather than returned through the pipeline.
    $script:Selection = @($Selection)
    if ($requested.Count -eq 0) { return }
    $newSelection = @($Available | Where-Object { @($Selection) -contains $_ -or $requested.Contains($_) })
    $script:Selection = $newSelection
    if ($DryRun) {
        Write-Output "would select skills in AGENTS.md: $($requested -join ', ')"
        return
    }
    $agentsItem = Get-Item -LiteralPath $AgentsPath -Force
    if (($agentsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Lifecycle 'AGENTS.md is a link; replace it with a regular file before changing the skill selection'
    }
    $text = Get-NormalizedText $AgentsPath
    $updated = Set-SkillsLineText -Text $text -Selection $newSelection -Available $Available
    Write-Output "~ AGENTS.md (added: $($requested -join ', '))"
    $rendered = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($rendered, $updated, [Text.UTF8Encoding]::new($false))
        Write-Diff $AgentsPath $rendered 'AGENTS.md' 'current' 'updated'
    }
    finally { Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue }
    $proof = Get-FileOwnershipProof -OwnershipPath $OwnershipPath -FullPath $AgentsPath
    $wasOwned = $null -ne $proof -and (Get-CksumProof $AgentsPath) -eq $proof
    # Replace through a sibling temporary file so an interruption never truncates AGENTS.md.
    $temporary = Join-Path (Split-Path -Parent $AgentsPath) (".AGENTS.md.{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, $updated, [Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($temporary, $AgentsPath, [NullString]::Value)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    if ($wasOwned) { Set-FileOwnershipRecord -OwnershipPath $OwnershipPath -Path 'AGENTS.md' -Proof (Get-CksumProof $AgentsPath) }
}

function Write-MigrationSummary {
    if ($script:Migrations.Count -eq 0) { return }
    $kept = @($script:Migrations | Where-Object Kind -eq 'kept')
    $removal = @($script:Migrations | Where-Object Kind -eq 'kept-removal')
    $replaced = @($script:Migrations | Where-Object Kind -eq 'replaced')
    Write-Output ''
    Write-Output (Format-Color '1;31' 'Migration required')
    if ($kept.Count -gt 0) {
        Write-Output "  Kept with local changes, not updated ($($kept.Count)):"
        foreach ($entry in $kept) { Write-Output "    ! $($entry.Path)  (release: $($entry.Detail))" }
    }
    if ($removal.Count -gt 0) {
        Write-Output "  Kept although no longer installed, because they have local changes ($($removal.Count)):"
        foreach ($entry in $removal) { Write-Output "    ! $($entry.Path)  ($($entry.Detail))" }
    }
    if ($replaced.Count -gt 0) {
        Write-Output "  Replaced by the release; your previous version was saved ($($replaced.Count)):"
        foreach ($entry in $replaced) { Write-Output "    ! $($entry.Path)  -> $($entry.Detail)" }
    }
    Write-Output '  Next steps:'
    if ($kept.Count -gt 0) {
        Write-Output "    - Review the diffs above: '-' lines are your version, '+' lines are the release."
        Write-Output '      Move your customizations out of toolkit-managed files, then rerun with -Force'
        Write-Output '      to take the release; -Force saves each file as <file>.bak.<timestamp> first.'
    }
    if ($removal.Count -gt 0) {
        Write-Output '    - Files kept after their skill was removed stay listed here until you delete them.'
        Write-Output '      Copy anything you still need into your own files, then delete them.'
    }
    if ($replaced.Count -gt 0) {
        Write-Output '    - Re-apply any customizations you still need from the saved .bak files.'
    }
}

try {
    if (-not $IsWindows -and -not $Local) {
        Stop-Lifecycle 'PowerShell skill lifecycle is supported only on Windows; -Local is reserved for internal portable tests'
    }
    if ($Mode -eq 'Check' -and ($DryRun -or $Force -or $Add -or $AddSkills)) {
        Stop-Lifecycle 'check-skills-update.ps1 accepts no options'
    }

    $toolkitHome = Get-ToolkitHome
    $sourceRoot = Join-Path $toolkitHome 'skills'
    $manifestPath = Join-Path $toolkitHome 'manifest.tsv'
    $ownershipPath = Join-Path (Get-Location).Path '.mindflayer-managed.tsv'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { Stop-Lifecycle "manifest not found: $manifestPath" }
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { Stop-Lifecycle "skill source not found: $sourceRoot" }
    if (-not (Test-Path -LiteralPath $ownershipPath -PathType Leaf)) { Stop-Lifecycle "ownership record not found: $ownershipPath" }

    $roots = @(Get-ManagedRoots $ownershipPath)
    $manifestRows = @(Get-ManifestRows -ManifestPath $manifestPath -Platform windows)
    $skills = @($manifestRows | Where-Object Type -eq 'skill')
    $available = Get-AvailableSkills $manifestRows
    $agentsPath = Join-Path (Get-Location).Path 'AGENTS.md'
    $selection = Get-SkillSelection -AgentsPath $agentsPath -Available $available
    if ($Add -or $AddSkills) {
        $script:Selection = $selection
        Add-SkillsToSelection -AgentsPath $agentsPath -Available $available -Selection $selection `
            -Skills $skills -SourceRoot $sourceRoot -OwnershipPath $ownershipPath
        $selection = @($script:Selection)
        # Any selection is a list of known skill names; anything else is a bug.
        if (@($selection | Where-Object { $available -notcontains $_ }).Count -gt 0) {
            Stop-Lifecycle 'internal error: invalid skill selection'
        }
    }
    $status = 0

    foreach ($root in $roots) {
        Write-Output $root.Path
        $obsoleteRecords = @(Get-ObsoleteSkillRecords `
            -OwnershipPath $ownershipPath `
            -TargetRoot $root.Path `
            -OwnershipRoot $root.OwnershipPath `
            -ManifestRows @($manifestRows | Where-Object { @($selection) -contains $_.SkillName }))
        foreach ($obsolete in $obsoleteRecords) {
            $relativeToRoot = [IO.Path]::GetRelativePath($root.Path, $obsolete.FullPath).Replace('\', '/')
            $isDeclared = $false
            if ($relativeToRoot.Contains('/')) {
                $obsoleteSkill = $relativeToRoot.Split('/')[0]
                $obsoleteRelative = $relativeToRoot.Substring($obsoleteSkill.Length + 1)
                $isDeclared = @($manifestRows | Where-Object { $_.SkillName -eq $obsoleteSkill -and $_.RelativePath -eq $obsoleteRelative }).Count -gt 0
            }
            $reason = if ($isDeclared) { 'deselected' } else { 'obsolete' }
            $item = Get-Item -LiteralPath $obsolete.FullPath -Force -ErrorAction SilentlyContinue
            $isVerified = $null -eq $item -or
                (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                    (Get-CksumProof $obsolete.FullPath) -eq $obsolete.Proof)
            if ($null -ne $item -and -not $isVerified) {
                if ($Mode -eq 'Check') {
                    Write-Output ("{0,-24} LOCAL CHANGES ({1} file kept; migration required)" -f $obsolete.RecordedPath, $reason)
                }
                else {
                    Write-Output "! keep $reason $($obsolete.RecordedPath) (local changes)"
                    $script:Migrations.Add([pscustomobject]@{ Kind = 'kept-removal'; Path = $obsolete.RecordedPath; Detail = $reason })
                }
                $status = 1
                continue
            }
            if ($Mode -eq 'Check') {
                if ($null -eq $item) { continue }
                if ($reason -eq 'obsolete') { Write-Output ("{0,-24} OBSOLETE" -f $obsolete.RecordedPath) }
                else { Write-Output ("{0,-24} NOT SELECTED (owned; sync removes it)" -f $obsolete.RecordedPath) }
                $status = 1
                continue
            }
            if ($DryRun) {
                if ($null -ne $item) { Write-Output "would remove $reason $($obsolete.RecordedPath)" }
                continue
            }
            if ($null -ne $item) { Remove-Item -LiteralPath $obsolete.FullPath -Force }
            Remove-FileOwnershipRecord -OwnershipPath $ownershipPath -RecordedPath $obsolete.RecordedPath
            if ($null -ne $item) { Write-Output "- $($obsolete.RecordedPath) ($reason)" }
        }
        foreach ($skill in $skills) {
            $files = @(Get-SkillFiles -ManifestRows $manifestRows -SkillName $skill.SkillName)
            if ($files.Count -eq 0) {
                Stop-Lifecycle "no manifest files found for skill: $($skill.SkillName)"
            }
            $skillSource = Join-Path $sourceRoot $skill.SkillName
            foreach ($file in $files) {
                $sourceFile = Join-Path $skillSource $file.RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
                    Stop-Lifecycle "manifest skill source not found: $sourceFile"
                }
            }
            if (@($selection) -notcontains $skill.SkillName) {
                if ($Mode -eq 'Check') { Write-Output ('{0,-24} available (not selected)' -f $skill.SkillName) }
                continue
            }
            $skillTarget = Join-Path $root.Path $skill.SkillName
            $ownershipSkillTarget = Join-Path $root.OwnershipPath $skill.SkillName
            $targetItem = Get-Item -LiteralPath $skillTarget -Force -ErrorAction SilentlyContinue
            $states = @{}
            $hasLocal = $null -ne $targetItem -and (-not $targetItem.PSIsContainer -or ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
            $hasChange = $false
            $hasExisting = $false
            foreach ($file in $files) {
                $relative = $file.RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
                $state = if ($hasLocal) { 'local' } else {
                    Get-SkillFileState -OwnershipPath $ownershipPath -Target (Join-Path $skillTarget $relative) -Source (Join-Path $skillSource $relative)
                }
                $states[$file.RelativePath] = $state
                if (@('local', 'unmanaged').Contains($state)) { $hasLocal = $true }
                if (@('new', 'update').Contains($state)) { $hasChange = $true }
                if ($state -ne 'new') { $hasExisting = $true }
            }

            if ($Mode -eq 'Check') {
                if (-not $hasExisting) {
                    Write-Output ('{0,-24} MISSING (toolkit {1})' -f $skill.SkillName, $skill.Version)
                    $status = 1
                }
                elseif ($states.Values -contains 'unmanaged') {
                    Write-Output ('{0,-24} LOCAL CHANGES ({1}; not installed by the toolkit)' -f $skill.SkillName, $skill.Version)
                    $status = 1
                }
                elseif ($hasLocal) {
                    Write-Output ('{0,-24} LOCAL CHANGES ({1}; migration required)' -f $skill.SkillName, $skill.Version)
                    $status = 1
                }
                elseif ($hasChange) {
                    Write-Output ('{0,-24} UPDATE AVAILABLE ({1})' -f $skill.SkillName, $skill.Version)
                    $status = 1
                }
                else {
                    Write-Output ('{0,-24} in sync ({1})' -f $skill.SkillName, $skill.Version)
                }
                continue
            }

            if (-not $hasChange -and -not $hasLocal) {
                Write-Output "= $($skill.SkillName)"
                continue
            }
            # A skill directory replaced by a file or link is moved aside as a whole;
            # it cannot contain a discoverable SKILL.md of its own.
            if ($null -ne $targetItem -and $Force -and -not $DryRun -and
                (-not $targetItem.PSIsContainer -or ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
                $backup = Get-BackupPath $skillTarget
                Move-Item -LiteralPath $skillTarget -Destination $backup
                Write-Output "b $backup"
                $script:Migrations.Add([pscustomobject]@{ Kind = 'replaced'; Path = $skillTarget; Detail = $backup })
            }
            if (-not $DryRun) { [IO.Directory]::CreateDirectory($skillTarget) | Out-Null }
            foreach ($file in $files) {
                $relative = $file.RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
                $sourceFile = Join-Path $skillSource $relative
                $targetFile = Join-Path $skillTarget $relative
                $label = "$($root.OwnershipPath.Replace('\', '/'))/$($skill.SkillName)/$($file.RelativePath)"
                $release = "release $($skill.Version)"
                $state = $states[$file.RelativePath]
                if ($state -eq 'current') { continue }
                if ($state -eq 'new') {
                    if ($DryRun) { Write-Output "would add $label" }
                    else {
                        Copy-ManifestSkillFiles -SourceRoot $skillSource -TargetRoot $skillTarget -OwnershipRoot $ownershipSkillTarget -OwnershipPath $ownershipPath -Files @($file)
                        Write-Output "+ $label"
                    }
                    continue
                }
                if ($state -eq 'update') {
                    if ($DryRun) { Write-Output "would update $label" } else { Write-Output "~ $label (update to $($skill.SkillName) $($skill.Version))" }
                    Write-Diff $targetFile $sourceFile $label 'installed' $release
                    if (-not $DryRun) {
                        Copy-ManifestSkillFiles -SourceRoot $skillSource -TargetRoot $skillTarget -OwnershipRoot $ownershipSkillTarget -OwnershipPath $ownershipPath -Files @($file)
                    }
                    continue
                }
                if ($Force) {
                    if ($DryRun) { Write-Output "would replace $label (local changes; backup first)" } else { Write-Output "! replace $label (local changes; -Force)" }
                    Write-Diff $targetFile $sourceFile $label 'your version' $release
                    if (-not $DryRun) {
                        # Back up the single file next to itself: a <skill>.bak directory in
                        # the discovery root would be loaded by assistants as another skill.
                        $backup = '(no previous file)'
                        if (Test-Path -LiteralPath $targetFile) {
                            $backup = Get-BackupPath $targetFile
                            Copy-Item -LiteralPath $targetFile -Destination $backup -Recurse
                            Write-Output "b $backup"
                        }
                        Copy-ManifestSkillFiles -SourceRoot $skillSource -TargetRoot $skillTarget -OwnershipRoot $ownershipSkillTarget -OwnershipPath $ownershipPath -Files @($file)
                        $script:Migrations.Add([pscustomobject]@{ Kind = 'replaced'; Path = $label; Detail = $backup })
                    }
                }
                else {
                    Write-Output "! keep ${label}: $(Format-Color '1;31' 'LOCAL CHANGES - migration required')"
                    Write-Diff $targetFile $sourceFile $label 'your version' $release
                    $script:Migrations.Add([pscustomobject]@{ Kind = 'kept'; Path = $label; Detail = "$($skill.SkillName) $($skill.Version)" })
                }
            }
            if (-not $DryRun -and $hasChange) { Write-Output "+ $($skill.SkillName) ($($skill.Version))" }
        }
    }
    if ($Mode -eq 'Check') {
        if ($status -ne 0) {
            Write-Output ''
            Write-Output 'Run sync-skills -DryRun to see the differences, or sync-skills to apply updates.'
        }
        exit $status
    }
    Write-MigrationSummary
    $unresolved = @($script:Migrations | Where-Object { $_.Kind -in 'kept', 'kept-removal' }).Count
    if ($unresolved -gt 0) { exit 2 }
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
