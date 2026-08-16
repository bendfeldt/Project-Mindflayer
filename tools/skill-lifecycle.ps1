#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Check', 'Sync')]
    [string]$Mode,
    [switch]$DryRun,
    [switch]$Force,

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

try {
    if (-not $IsWindows -and -not $Local) {
        Stop-Lifecycle 'PowerShell skill lifecycle is supported only on Windows; -Local is reserved for internal portable tests'
    }
    if ($Mode -eq 'Check' -and ($DryRun -or $Force)) {
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
    $status = 0

    foreach ($root in $roots) {
        Write-Output $root.Path
        $obsoleteRecords = @(Get-ObsoleteSkillRecords `
            -OwnershipPath $ownershipPath `
            -TargetRoot $root.Path `
            -OwnershipRoot $root.OwnershipPath `
            -ManifestRows $manifestRows)
        foreach ($obsolete in $obsoleteRecords) {
            if ($Mode -eq 'Check') {
                Write-Output ("{0,-24} OBSOLETE" -f $obsolete.RecordedPath)
                $status = 1
                continue
            }
            $item = Get-Item -LiteralPath $obsolete.FullPath -Force -ErrorAction SilentlyContinue
            $isVerified = $null -eq $item -or
                (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                    (Get-CksumProof $obsolete.FullPath) -eq $obsolete.Proof)
            if (-not $isVerified) {
                [Console]::Error.WriteLine("! preserved obsolete $($obsolete.RecordedPath) (modified or type changed)")
                continue
            }
            if ($DryRun) {
                Write-Output "would remove obsolete $($obsolete.RecordedPath)"
                continue
            }
            if ($null -ne $item) { Remove-Item -LiteralPath $obsolete.FullPath -Force }
            Remove-FileOwnershipRecord -OwnershipPath $ownershipPath -RecordedPath $obsolete.RecordedPath
            Write-Output "- $($obsolete.RecordedPath) (obsolete)"
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
            $skillTarget = Join-Path $root.Path $skill.SkillName
            $ownershipSkillTarget = Join-Path $root.OwnershipPath $skill.SkillName
            $targetExists = Test-Path -LiteralPath $skillTarget
            $inSync = $targetExists -and (Test-ManifestFilesEqual -SourceRoot $skillSource -TargetRoot $skillTarget -Files $files)

            if ($Mode -eq 'Check') {
                if (-not $targetExists) {
                    Write-Output ('{0,-24} MISSING (toolkit {1})' -f $skill.SkillName, $skill.Version)
                    $status = 1
                }
                elseif ($inSync) {
                    Write-Output ('{0,-24} in sync ({1})' -f $skill.SkillName, $skill.Version)
                }
                else {
                    Write-Output ('{0,-24} DRIFTED ({1}, manifest files)' -f $skill.SkillName, $skill.Version)
                    $status = 1
                }
                continue
            }

            $action = if ($targetExists) { 'replace' } else { 'add' }
            if ($inSync) {
                Write-Output "= $($skill.SkillName)"
                continue
            }
            if ($targetExists -and -not $Force) {
                Write-Output "! preserve $($skill.SkillName) (drifted; use -Force)"
                continue
            }
            if ($DryRun) {
                Write-Output "would $action $($skill.SkillName)"
                continue
            }

            if ($targetExists) {
                $backup = Get-BackupPath $skillTarget
                Copy-Item -LiteralPath $skillTarget -Destination $backup -Recurse
                if (-not (Test-Path -LiteralPath $skillTarget -PathType Container)) {
                    Remove-Item -LiteralPath $skillTarget -Force
                }
            }
            [IO.Directory]::CreateDirectory($skillTarget) | Out-Null
            Copy-ManifestSkillFiles `
                -SourceRoot $skillSource `
                -TargetRoot $skillTarget `
                -OwnershipRoot $ownershipSkillTarget `
                -OwnershipPath $ownershipPath `
                -Files $files
            Write-Output "+ $($skill.SkillName) ($($skill.Version))"
        }
    }
    exit $status
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
